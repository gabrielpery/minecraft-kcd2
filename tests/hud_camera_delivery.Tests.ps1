#Requires -Version 7.3
# Real bounded runspace and filesystem delivery with a simulated console only.
# No engine, game process, renderer or HTTP endpoint is accessed.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudCameraDelivery.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
$fixture=Join-Path $root ('runtime/evidence/hud-camera-delivery-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$fakeHelpers=Join-Path $fixture 'fake-console.ps1'
$fakeSource=@'
$script:fakeMode=[IO.File]::ReadAllText((Join-Path $Context.GameRoot 'mode.txt'))
$script:fakeSequence=0
function Assert-MineComeProbeContext($Value){
    if($Value.GamePid -ne 424242 -or $Value.GameRoot -ne [IO.Path]::GetDirectoryName($Value.GameLog)){throw 'Unexpected simulated context'}
}
function Invoke-MineComeToolsRequest {
    param([string]$PathAndQuery,[int]$TimeoutMilliseconds)
    $command=[Uri]::UnescapeDataString($PathAndQuery)
    if($command -notmatch "SamplePhysicalHudView\('([0-9a-f]{32})'\)" -or $TimeoutMilliseconds -gt 1000 -or $TimeoutMilliseconds -lt 1){throw 'Unexpected simulated request'}
    $run=$Matches[1];$script:fakeSequence++
    [IO.File]::AppendAllText((Join-Path $Context.GameRoot 'requests.log'),([string]$pending.Mono+"`n"))
    if($script:fakeMode -eq 'rotated_log' -and $script:fakeSequence -eq 2){[IO.File]::Move($Context.GameLog,($Context.GameLog+'.rotated'));[IO.File]::WriteAllText($Context.GameLog,'')}
    if($script:fakeMode -eq 'no_ack'){return}
    if($script:fakeMode -eq 'stale'){Start-Sleep -Milliseconds 300}
    if($script:fakeMode -eq 'slow_stop'){Start-Sleep -Milliseconds 500}
    if($script:fakeMode -eq 'late_ack'){Start-Sleep -Milliseconds 1100}
    if($script:fakeMode -eq 'blocked_stop' -and $script:fakeSequence -eq 2){[Threading.Thread]::Sleep(2300)}
    if($script:fakeMode -eq 'malformed'){
        [IO.File]::AppendAllText($Context.GameLog,"[MineComeHudPhysicalView] {broken`n");return
    }
    $seq=$script:fakeSequence;$engine=[double]$seq/10
    if($script:fakeMode -eq 'wrong_sequence'){$seq++}
    if($script:fakeMode -eq 'regressed_clock'){$engine=1.0}
    if($script:fakeMode -eq 'wrong_run'){$run='9'*32}
    $basis=$true;if($script:fakeMode -eq 'bad_basis'){$basis=$false}
    $physical=$true;if($script:fakeMode -eq 'untyped_physical'){$physical='true'}
    $record=[ordered]@{schema=1;run=$run;result='sampled';seq=$seq;sampled_engine_seconds=$engine;physical_movement=$physical;camera_basis_valid=$basis;camera=@{forward=@{x=0;y=1;z=0};up=@{x=0;y=0;z=1}}}
    [IO.File]::AppendAllText($Context.GameLog,('[MineComeHudPhysicalView] '+($record | ConvertTo-Json -Depth 5 -Compress)+"`n"))
}
'@
[IO.File]::WriteAllText($fakeHelpers,$fakeSource)
$originalWorker=(Get-HudCameraDeliveryWorkerScript).ToString()
$cadenceMatch=[regex]::Match($originalWorker,'\$minimumRequestIntervalMs=(\d+)L')
$lifetimeMatch=[regex]::Match((Get-Command Start-HudCameraDelivery).ScriptBlock.ToString(),'Stopwatch\]::Frequency\*(\d+)')
$engineBudgetMatch=[regex]::Match([IO.File]::ReadAllText((Join-Path $root 'kcd2/probes/movement_probe.lua')),'view\.sequence >= (\d+)')
Check ($cadenceMatch.Success -and $lifetimeMatch.Success -and $engineBudgetMatch.Success) 'Camera cadence/lifetime/source-budget contract is not inspectable'
$minimumInterval=[long]$cadenceMatch.Groups[1].Value
$lifetimeMs=1000L*[long]$lifetimeMatch.Groups[1].Value
$maximumRequests=[long][Math]::Ceiling($lifetimeMs/[double]$minimumInterval)
Check ($minimumInterval -eq 110 -and $lifetimeMs -eq 112000 -and $engineBudgetMatch.Groups[1].Value -ceq '1024' -and $maximumRequests -eq 1019 -and $maximumRequests -le [long]$engineBudgetMatch.Groups[1].Value) 'Worker can exhaust the unchanged source budget before its bounded lifetime'
$import=". (Join-Path `$ProjectRoot 'scripts/KcdToolsProbeHelpers.ps1')"
Check ($originalWorker.Contains($import)) 'Production console import seam changed'
$script:fixtureWorker=[scriptblock]::Create($originalWorker.Replace($import,". '$($fakeHelpers.Replace("'","''"))'"))
# Start/Get/Stop stay production code. Only its worker's console dependency is replaced.
function Get-HudCameraDeliveryWorkerScript {return $script:fixtureWorker}
function New-Case([string]$Mode){
    $directory=Join-Path $fixture ($Mode+'-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($directory)
    [IO.File]::WriteAllText((Join-Path $directory 'mode.txt'),$Mode)
    $log=Join-Path $directory 'game.log';[IO.File]::WriteAllText($log,'')
    [pscustomobject]@{
        Context=[pscustomobject]@{ProjectRoot=$root;GameRoot=$directory;GamePath='simulated-game.exe';GameHash='a'*64;GamePid=424242;GameStartedUtc=[datetime]::UtcNow;GameLog=$log}
        Probe=[pscustomobject]@{Run=[Guid]::NewGuid().ToString('N');Offset=0L;Directory=$directory}
        Run=[Guid]::NewGuid().ToString('N');Patch=[pscustomobject]@{Run=[Guid]::NewGuid().ToString('N');Hash='b'*64}
        View=(Join-Path $directory 'host-view.json');Directory=$directory
    }
}
function Start-Case($Case){Start-HudCameraDelivery $Case.Context $Case.Probe $Case.Run $Case.Patch $Case.View $root}
function Wait-State($Session,[scriptblock]$Predicate,[int]$TimeoutMs=3000){
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{$state=Get-HudCameraDeliveryState $Session;if(& $Predicate $state){return $state};if($state.Failure){throw $state.Failure};Start-Sleep -Milliseconds 10}while($clock.ElapsedMilliseconds -lt $TimeoutMs)
    throw 'Simulated worker state deadline exceeded.'
}
$case=New-Case 'valid';$session=Start-Case $case
try{
    $first=Wait-State $session {param($s)$s.ViewCount -ge 1}
    $firstCount=$first.ViewCount
    # Simulate the parent being occupied with unrelated work. The production
    # worker must continue requesting and publishing without parent polling.
    Start-Sleep -Milliseconds 750
    $later=Get-HudCameraDeliveryState $session
    Check ($later.ViewCount -ge $firstCount+4 -and -not $later.Failure) 'Camera stalled while the caller was blocked'
    Check ($first.ViewCount -eq $firstCount) 'Earlier snapshot was mutated by later worker publication'
    Check ($later.LastPublishedUtcMs -gt $first.LastPublishedUtcMs -and [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$later.LastPublishedUtcMs -lt 250) 'Published snapshot did not stay fresh independently'
    Check ($later.DeadlineUtcMs-$first.LastRequestUtcMs -le 112000) 'Worker lifetime exceeds 112 seconds'
}finally{$final=Stop-HudCameraDelivery $session}
Check ($final.Stopped -and $final.ResourcesClosed -and -not $final.Failure -and $session.Disposed) 'Normal worker cleanup did not close resources'
$exclusive=[IO.FileStream]::new($case.Context.GameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{Check $exclusive.CanRead 'Stopped worker retained the game log handle'}finally{$exclusive.Dispose()}
$view=Get-Content -LiteralPath $case.View -Raw | ConvertFrom-Json
$timing=@($final.Timings | Where-Object seq -EQ $view.seq)
Check ($timing.Count -eq 1 -and $view.utc_ms -eq $timing[0].requested_utc_ms -and $view.utc_ms -le $timing[0].receipt_utc_ms -and $view.utc_ms -le $timing[0].published_utc_ms) 'Publication rebased the original request timestamp'
Check ($view.run -ceq $case.Run -and $view.patch_run -ceq $case.Patch.Run -and $view.patch_sha256 -ceq $case.Patch.Hash -and $view.target_pid -eq 424242 -and $view.target_start_filetime -ceq $case.Context.GameStartedUtc.ToFileTimeUtc().ToString()) 'Published identity differs from captured session'
Check ($view.source_kind -ceq 'live_kcd_hud_view_v1' -and $view.forward.y -eq 1 -and $view.up.z -eq 1) 'Publication lost verified camera basis'
$tooClose=$false
$requestStamps=@(Get-Content -LiteralPath (Join-Path $case.Directory 'requests.log') | ForEach-Object {[long]$_})
for($i=1;$i -lt $requestStamps.Count;$i++){if(($requestStamps[$i]-$requestStamps[$i-1])*1000.0/[Diagnostics.Stopwatch]::Frequency -lt $minimumInterval){$tooClose=$true}}
Check (-not $tooClose) 'Camera requests bypassed their 110ms monotonic minimum cadence'
$hash=(Get-FileHash -LiteralPath $case.View).Hash
Start-Sleep -Milliseconds 150
Check ((Get-FileHash -LiteralPath $case.View).Hash -ceq $hash) 'Camera changed after Stop returned'
Check ([object]::ReferenceEquals($final,(Stop-HudCameraDelivery $session))) 'Stop was not idempotent'
Check (@(Get-ChildItem -LiteralPath $case.Directory -Filter '*.tmp').Count -eq 0) 'Temporary publication remains after cleanup'

$case=New-Case 'stale';$session=Start-Case $case
try{$stale=Wait-State $session {param($s)$s.StaleViews -ge 1}}finally{$final=Stop-HudCameraDelivery $session}
Check ($final.StaleViews -ge 1 -and $final.ViewCount -eq 0 -and -not [IO.File]::Exists($case.View)) 'Old receipt was published'
Check (-not $final.Failure -and $final.ResourcesClosed) 'Discarding a stale receipt corrupted worker cleanup'
Check (@($final.Timings | Where-Object {$_.stale -ne $true -or $null -ne $_.published_utc_ms -or $_.receipt_utc_ms-$_.requested_utc_ms -le 250}).Count -eq 0) 'Stale diagnostic lost original request age'

foreach($mode in @('wrong_sequence','malformed','bad_basis','untyped_physical','regressed_clock','wrong_run','no_ack','late_ack')){
    $case=New-Case $mode;$session=Start-Case $case
    try{$failed=Wait-State $session {param($s)$s.Stopped}}finally{$final=Stop-HudCameraDelivery $session}
    Check ($final.Stopped -and $final.ResourcesClosed -and [bool]$final.Failure) "Invalid $mode did not fail closed"
    if($mode -eq 'regressed_clock'){Check ($final.ViewCount -eq 1) 'Regressed clock published another camera'}
    else{Check ($final.ViewCount -eq 0 -and -not [IO.File]::Exists($case.View)) "Invalid $mode published a camera"}
    if($mode -in @('wrong_run','no_ack','late_ack')){
        Check (@(Get-Content -LiteralPath (Join-Path $case.Directory 'requests.log')).Count -eq 1) 'Outstanding unacknowledged request was redispatched'
        Check ($final.Failure -match 'one[- ]second') 'Unacknowledged request missed its one-second deadline'
    }
}

$case=New-Case 'rotated_log';$session=Start-Case $case
try{$failed=Wait-State $session {param($s)$s.Stopped}}finally{$final=Stop-HudCameraDelivery $session}
Check ($final.ViewCount -eq 1 -and $final.Failure -match 'one[- ]second' -and $final.ResourcesClosed) 'Rotated replacement supplied a camera acknowledgement'
Check (@(Get-Content -LiteralPath (Join-Path $case.Directory 'requests.log')).Count -eq 2) 'Rotated log caused unacknowledged redispatch'
$exclusive=[IO.FileStream]::new(($case.Context.GameLog+'.rotated'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{Check $exclusive.CanRead 'Failed worker retained the original game log handle'}finally{$exclusive.Dispose()}

$case=New-Case 'slow_stop';$session=Start-Case $case
try{
    $null=Wait-State $session {param($s)$s.Stage -eq 'requesting'}
    $clock=[Diagnostics.Stopwatch]::StartNew();Request-HudCameraDeliveryStop $session
    Check ($clock.ElapsedMilliseconds -lt 200) 'Requesting camera stop blocks parent restoration'
}finally{$final=Stop-HudCameraDelivery $session}
Check ($final.Stopped -and $final.ResourcesClosed -and -not $final.Failure) 'Cancelled in-flight request did not clean up'
Check ($final.ViewCount -eq 0 -and -not [IO.File]::Exists($case.View)) 'In-flight response published after cancellation'
Check (@(Get-ChildItem -LiteralPath $case.Directory -Filter '*.tmp').Count -eq 0) 'Cancelled publication left a temporary file'

# Exercise the bounded Stop result for an uninterruptible mocked dependency.
# Returning cleanup_pending must not claim that its runspace was disposed.
$case=New-Case 'blocked_stop';$session=Start-Case $case
try{
    $null=Wait-State $session {param($s)$s.ViewCount -eq 1 -and @(Get-Content -LiteralPath (Join-Path $case.Directory 'requests.log')).Count -eq 2}
    $clock=[Diagnostics.Stopwatch]::StartNew();$pendingStop=Stop-HudCameraDelivery $session
    Check ($clock.ElapsedMilliseconds -lt 2000 -and $pendingStop.Stage -ceq 'cleanup_pending') 'Unresponsive dependency defeated the 1500ms cleanup bound'
    Check (-not $pendingStop.Stopped -and -not $pendingStop.ResourcesClosed -and -not $session.Disposed) 'Pending cleanup falsely claimed disposed resources'
}finally{$final=Stop-HudCameraDelivery $session}
Check ($final.Stopped -and $final.ResourcesClosed -and $session.Disposed) 'Retrying pending cleanup did not close the runspace'
Check ($final.ViewCount -eq 1 -and (Get-Content -LiteralPath $case.View -Raw | ConvertFrom-Json).seq -eq 1) 'Late blocked operation published after cancellation'
$exclusive=[IO.FileStream]::new($case.Context.GameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{Check $exclusive.CanRead 'Forced pipeline stop retained the game log handle'}finally{$exclusive.Dispose()}

# Execute the same worker at an already-expired monotonic deadline, avoiding a
# 112-second test wait while still exercising its real terminal logic.
$case=New-Case 'valid'
$shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$timings=[Collections.Concurrent.ConcurrentQueue[object]]::new()
$cancellation=[Threading.CancellationTokenSource]::new()
try{
    & $script:fixtureWorker $case.Context $case.Probe $case.Run $case.Patch $case.View $root $shared $cancellation.Token $timings ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+112000) ([Diagnostics.Stopwatch]::GetTimestamp()-1)
    Check ($shared['Snapshot'].Stopped -and $shared['Snapshot'].Failure -match 'deadline') 'Monotonic lifetime deadline did not stop the worker'
    Check (-not [IO.File]::Exists($case.View) -and -not [IO.File]::Exists((Join-Path $case.Directory 'requests.log'))) 'Expired worker dispatched or published'
}finally{$cancellation.Dispose()}

$case=New-Case 'valid'
Reject {Start-HudCameraDelivery $case.Context $case.Probe 'bad-run' $case.Patch $case.View $root} 'Invalid session identity accepted'
Reject {Start-HudCameraDelivery $case.Context $case.Probe $case.Run $case.Patch (Join-Path $case.Directory 'other.json') $root} 'Unowned output filename accepted'
Write-Output "HUD_CAMERA_DELIVERY_TESTS checks=$script:checks PASS game_calls=false http_calls=false"
