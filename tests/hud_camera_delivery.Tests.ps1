#Requires -Version 7.3
# Real bounded runspace and filesystem delivery with a simulated console only.
# No engine, game process, renderer or HTTP endpoint is accessed.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudCameraDelivery.ps1')
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
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
    if($command -notmatch 'MineComeHudPhysicalViewRejected' -or $command -notmatch ('"seq":'+$script:fakeSequence+',') -or
        $command -notmatch 'accepted==false' -or $command -notmatch 'invalid_rejection_reason'){throw 'Sampler rejection wrapper/correlation missing'}
    if($script:fakeSequence -eq 1){[IO.File]::WriteAllText((Join-Path $Context.GameRoot 'request.lua'),$command.Substring($command.IndexOf('#')+1))}
    [IO.File]::AppendAllText((Join-Path $Context.GameRoot 'requests.log'),([string]$pending.Mono+"`n"))
    if($script:fakeMode -eq 'rotated_log' -and $script:fakeSequence -eq 2){[IO.File]::Move($Context.GameLog,($Context.GameLog+'.rotated'));[IO.File]::WriteAllText($Context.GameLog,'')}
    if($script:fakeMode -eq 'no_ack'){return}
    if($script:fakeMode -eq 'stale'){Start-Sleep -Milliseconds 300}
    if($script:fakeMode -eq 'slow_stop'){Start-Sleep -Milliseconds 500}
    if($script:fakeMode -eq 'late_ack'){Start-Sleep -Milliseconds 1100}
    if($script:fakeMode -eq 'blocked_stop' -and $script:fakeSequence -eq 2){[Threading.Thread]::Sleep(2300)}
    if($script:fakeMode -like '*rejection*'){
        $rejected=[ordered]@{schema=1;run=$run;seq=$script:fakeSequence;result='rejected';reason='velocity_unavailable_or_moving'}
        if($script:fakeMode -eq 'wrong_rejection_sequence'){$rejected.seq++}
        if($script:fakeMode -eq 'wrong_rejection_run'){$rejected.run='9'*32}
        if($script:fakeMode -eq 'bad_rejection_reason'){$rejected.reason='unsafe"reason'}
        $line='[MineComeHudPhysicalViewRejected] '+($rejected | ConvertTo-Json -Compress)+"`n"
        [IO.File]::AppendAllText($Context.GameLog,$line)
        if($script:fakeMode -eq 'duplicate_rejection'){[IO.File]::AppendAllText($Context.GameLog,$line)}
        return
    }
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

foreach($mode in @('sampler_rejection','wrong_rejection_sequence','wrong_rejection_run','bad_rejection_reason','duplicate_rejection')){
    $case=New-Case $mode;$session=Start-Case $case
    try{$failed=Wait-State $session {param($s)$s.Stopped}}finally{$final=Stop-HudCameraDelivery $session}
    Check ($final.Stopped -and $final.ResourcesClosed -and $final.ViewCount -eq 0 -and -not [IO.File]::Exists($case.View)) "Rejected $mode published a view or leaked resources"
    Check (@(Get-Content -LiteralPath (Join-Path $case.Directory 'requests.log')).Count -eq 1) "Rejected $mode was retried"
    if($mode -eq 'sampler_rejection'){
        Check ($final.Failure -ceq 'Physical camera sampler rejected request 1: velocity_unavailable_or_moving.') 'Actual sampler reason was replaced by a generic timeout'
    }elseif($mode -eq 'wrong_rejection_run'){
        Check ($final.Failure -match 'one[- ]second') 'Foreign rejection affected this request'
    }else{Check ($final.Failure -match 'rejection receipt') "Invalid $mode was trusted as a sampler reason"}
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

# Snapshot readers share deletion with the actual atomic publisher. A transient
# external lock yields no view immediately; recovery never rebases its timestamp.
$snapshot=Join-Path $fixture 'snapshot.json'
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($snapshot,'{"seq":1,"utc_ms":1234}',$utf8)
$read=Read-HudCameraSnapshot $snapshot $root
Check ($read.seq -eq 1 -and $read.utc_ms -eq 1234) 'Snapshot changed the original publication identity/clock'
$locked=[IO.FileStream]::new($snapshot,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{
    $clock=[Diagnostics.Stopwatch]::StartNew();$read=Read-HudCameraSnapshot $snapshot $root
    Check ($null -eq $read -and $clock.ElapsedMilliseconds -lt 250) 'Sharing conflict must be unavailable without retrying or stalling movement'
}finally{$locked.Dispose()}
Check ((Read-HudCameraSnapshot $snapshot $root).seq -eq 1) 'Snapshot reader failed to recover after an external lock ended'
$retired=$snapshot+'.retired';[IO.File]::Move($snapshot,$retired)
Check ($null -eq (Read-HudCameraSnapshot $snapshot $root)) 'Missing publication must be unavailable'
[IO.File]::Move($retired,$snapshot)
Check ((Read-HudCameraSnapshot $snapshot $root).utc_ms -eq 1234) 'Deletion-race recovery altered the source age'

foreach($bad in @('{"seq":','null','[]','{"seq":1,}','{/*comment*/"seq":1}')){
    [IO.File]::WriteAllText($snapshot,$bad,$utf8)
    Reject {Read-HudCameraSnapshot $snapshot $root} 'Malformed/nonobject camera JSON was treated as transient availability'
}
[IO.File]::WriteAllBytes($snapshot,[byte[]](0x7b,0x22,0x78,0x22,0x3a,0x22,0xc3,0x28,0x22,0x7d))
Reject {Read-HudCameraSnapshot $snapshot $root} 'Invalid UTF-8 was silently replaced'
[IO.File]::WriteAllText($snapshot,('{"padding":"'+('x'*65536)+'"}'),$utf8)
Reject {Read-HudCameraSnapshot $snapshot $root} 'Oversized opened snapshot was accepted'
[IO.File]::WriteAllText($snapshot,'{"padding":"'+('x'*65522)+'"}',$utf8)
Check ((Get-Item -LiteralPath $snapshot).Length -eq 65536 -and (Read-HudCameraSnapshot $snapshot $root).padding.Length -eq 65522) 'Exact 64KiB snapshot boundary was rejected'
Reject {Read-HudCameraSnapshot $fixture $root} 'Directory/access failure was silently swallowed'
Reject {Read-HudCameraSnapshot (Join-Path $root 'README.md') $root} 'Snapshot read escaped the owned evidence root'
$linkTarget=Join-Path $fixture 'snapshot-target';[void][IO.Directory]::CreateDirectory($linkTarget)
[IO.File]::WriteAllText((Join-Path $linkTarget 'view.json'),'{"seq":1}',$utf8)
$junction=Join-Path $fixture 'snapshot-junction'
$null=New-Item -ItemType Junction -Path $junction -Target $linkTarget
Reject {Read-HudCameraSnapshot (Join-Path $junction 'view.json') $root} 'Snapshot followed a reparse ancestor'

# Exercise the production writer concurrently: a shared reader holds an old
# opened version while Replace publishes newer versions under the same name.
$case=New-Case 'valid';$session=Start-Case $case;$opened=$null
try{
    $first=Wait-State $session {param($s)$s.ViewCount -ge 1}
    $opened=[IO.FileStream]::new($case.View,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $firstSnapshot=Read-HudCameraSnapshot $case.View $root;$lastSequence=$firstSnapshot.seq;$readCount=0
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do{
        $snapshotValue=Read-HudCameraSnapshot $case.View $root
        if($null -ne $snapshotValue){
            Check ($snapshotValue.seq -ge $lastSequence -and $snapshotValue.run -ceq $case.Run -and $snapshotValue.utc_ms -gt 0) 'Atomic reader returned a mixed or regressed publication'
            $lastSequence=$snapshotValue.seq;$readCount++
        }
        Start-Sleep -Milliseconds 5
    }while($clock.ElapsedMilliseconds -lt 650)
    $later=Get-HudCameraDeliveryState $session
    Check ($readCount -gt 10 -and $later.ViewCount -ge $first.ViewCount+3 -and -not $later.Failure) 'Shared snapshot reads blocked atomic camera publication'
    Check ($opened.Length -gt 0 -and $lastSequence -gt $firstSnapshot.seq) 'Opened snapshot was not preserved across replacement'
}finally{if($opened){$opened.Dispose()};$final=Stop-HudCameraDelivery $session}
Check ($final.ResourcesClosed -and -not $final.Failure) 'Concurrent camera reader/writer cleanup failed'

# Execute the actual caller function without starting its controller. A missing
# view declines the current edge before looking up native receipts or permits.
$controllerAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-HudWalkingAimed.ps1'),[ref]$null,[ref]$null)
$declineFunction=$controllerAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-CurrentAimDecline'},$true)
Check ($null -ne $declineFunction) 'Combined camera admission function is missing'
. ([scriptblock]::Create($declineFunction.Extent.Text))
$aimState=[pscustomobject]@{present=$true};$viewFile=Join-Path $fixture 'absent-current-view.json'
function Read-Receipts {throw 'Unavailable snapshot must not reach native receipt lookup.'}
Check ((Get-CurrentAimDecline 9999) -ceq 'host_view_unavailable') 'Missing camera snapshot did not decline the current aimed edge'
[IO.File]::WriteAllText($viewFile,'{"seq":1,"utc_ms":1234}',$utf8)
$locked=[IO.FileStream]::new($viewFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try{Check ((Get-CurrentAimDecline 9999) -ceq 'host_view_unavailable') 'Locked camera snapshot did not decline the current aimed edge'}
finally{$locked.Dispose()}
function Read-Receipts {return [pscustomobject]@{seq=1}}
function Get-HudWalkingAimedDecline($State,$View,$Native,[long]$Now){
    Check ($View.utc_ms -eq 1234 -and $View.seq -eq $Native.seq -and $Now -eq 9999) 'Recovery changed freshness inputs to existing settled admission'
    return 'simulated_existing_admission'
}
Check ((Get-CurrentAimDecline 9999) -ceq 'simulated_existing_admission') 'Recovered snapshot did not return to existing settled admission'
Write-Output "HUD_CAMERA_DELIVERY_TESTS checks=$script:checks PASS game_calls=false http_calls=false"
