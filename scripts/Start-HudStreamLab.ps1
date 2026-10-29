#Requires -Version 7.3
# Genuine continuous Minecraft UI -> standalone native receiver by default.
# Optional composition only arms an already-running, separately installed renderer.
# Never launches, stops, injects input into, or moves KCD2.
[CmdletBinding()]
param([string]$JavaHome, [switch]$Standalone, [switch]$Composite, [string]$BundleDirectory, [switch]$PreflightOnly, [switch]$GroundMovementFixture,
    [switch]$GroundMovementCoupled,[switch]$WideWalking,[string]$GroundPatchFile,[string]$MovementTraceFile,[string]$EvidenceDirectory,
    [switch]$GroundCorridorFixture,[switch]$GroundCorridorCoupled,[switch]$GroundCorridorWalkOnly,[string]$GroundCorridorFile,
    [ValidateRange(320,1920)][int]$Width=1280,[ValidateRange(240,1080)][int]$Height=720,[ValidateRange(1,4)][int]$GuiScale=2)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundCorridor.ps1')
Assert-HudGroundCorridorMode ([bool]$GroundCorridorFixture) ([bool]$Standalone) ([bool]($Composite -or $GroundMovementFixture -or $GroundMovementCoupled -or $WideWalking -or $GroundPatchFile)) $GroundCorridorFile ([bool]$GroundCorridorCoupled) $MovementTraceFile ([bool]$GroundCorridorWalkOnly)
Assert-HudGroundMovementMode ([bool]$GroundMovementFixture) ([bool]$Standalone) ([bool]$Composite) ([bool]$GroundMovementCoupled) -WideWalking:$WideWalking
if(-not $GroundCorridorCoupled){Assert-HudGroundMovementPaths ([bool]$GroundMovementCoupled) $GroundPatchFile $MovementTraceFile}
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$receiverPath=Join-Path $root 'build\hud-stream-20261012\kcd2\hud\stream\Release\minecome_hud_stream_receiver.exe'
if(-not (Test-Path -LiteralPath $receiverPath -PathType Leaf)) {throw 'Build the standalone HUD stream receiver first.'}
$receiverHash=(Get-FileHash -LiteralPath $receiverPath -Algorithm SHA256).Hash.ToLowerInvariant()
$inventory=Get-Content -LiteralPath (Join-Path $root 'runtime\environment.json') -Raw | ConvertFrom-Json
if(-not $JavaHome) {
    foreach($candidate in @($inventory.java.jdks | ForEach-Object home)) {
        if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') {$JavaHome=$candidate;break}
    }
}
if(-not $JavaHome) {throw 'An installed tested JDK21 or24 is required.'}
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin\javac.exe')) -or [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') {throw 'An installed tested JDK21 or24 is required.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')})
if($clients.Count) {throw 'An existing MineCome Minecraft client is open; preserving it.'}
if($Standalone -and $Composite) {throw 'Standalone receiver mode cannot arm KCD composition.'}
if($Standalone) {
    $ownProcess=Get-Process -Id $PID
    $context=[pscustomobject]@{GamePid=$PID;GameStartedUtc=$ownProcess.StartTime.ToUniversalTime();GamePath=$ownProcess.Path;GameHash=(Get-FileHash -LiteralPath $ownProcess.Path).Hash}
    $ownProcess.Dispose()
} else {$context=Get-MineComeProbeContext}
$groundContext=$null;$livePatch=$null;$corridorInput=$null
if($GroundCorridorFile){$corridorInput=Read-HudGroundCorridorInput $GroundCorridorFile $root $true}
if($GroundMovementCoupled -or $GroundCorridorCoupled){
    $groundContext=Get-MineComeProbeContext
    if($GroundCorridorCoupled){$corridorInput=Read-HudLiveGroundCorridor $GroundCorridorFile $root $groundContext}
    else{$livePatch=Read-HudLiveGroundPatch $GroundPatchFile $root $groundContext -WideWalking:$WideWalking}
    $MovementTraceFile=Resolve-HudMovementEvidencePath $MovementTraceFile $root
    if((Test-Path -LiteralPath $MovementTraceFile) -or -not (Test-Path -LiteralPath (Split-Path -Parent $MovementTraceFile) -PathType Container)){throw 'Coupled HUD trace requires a new file in an existing evidence directory.'}
}
if($EvidenceDirectory){
    $EvidenceDirectory=Resolve-HudMovementEvidencePath $EvidenceDirectory $root
    if((Test-Path -LiteralPath $EvidenceDirectory) -or -not (Test-Path -LiteralPath (Split-Path -Parent $EvidenceDirectory) -PathType Container)){throw 'HUD output requires a fresh evidence directory with an existing parent.'}
}
function Assert-SessionTarget {
    if($groundContext){Assert-MineComeProbeContext $groundContext}
    if(-not $Standalone) {Assert-MineComeProbeContext $context;return}
    $target=Get-Process -Id $context.GamePid
    try {if($target.StartTime.ToUniversalTime() -ne $context.GameStartedUtc -or $target.Path -ine $context.GamePath) {throw 'Standalone controller identity changed.'}}
    finally {$target.Dispose()}
}
if($Composite) {
    if(-not $BundleDirectory) {$BundleDirectory=Join-Path $root 'runtime\hud-compositor-stream'}
    & (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -BundleDirectory $BundleDirectory -PreflightOnly
}
if($PreflightOnly) {Write-Output 'HUD_STREAM_PREFLIGHT_PASS no_process_started=true kcd_unchanged=true';return}
$run=[guid]::NewGuid().ToString('N')
$directory=if($EvidenceDirectory){$EvidenceDirectory}else{Join-Path $root ('runtime\evidence\hud-stream-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)}
if(Test-Path -LiteralPath $directory) {throw 'Fresh evidence directory required.'}
[IO.Directory]::CreateDirectory($directory) | Out-Null
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000
$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
$client=$null;$receiver=$null;$failure=$null;$passed=$false;$armEvidence=$null;$groundProof=$null;$patchHash=$null;$patchRun=$null
function Read-BoundedJson([string]$Path) {
    $item=Get-Item -LiteralPath $Path
    if($item.Length -lt 2 -or $item.Length -gt 64KB -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'Invalid bounded receipt file.'}
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 12)
}
function Start-Child([string]$Executable,[string[]]$Arguments) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable;$start.WorkingDirectory=$root
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in $Arguments) {$start.ArgumentList.Add($argument)}
    return [Diagnostics.Process]::Start($start)
}
try {
    $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-TargetPid',[string]$context.GamePid,'-TargetStart',$targetStart,'-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-Width',[string]$Width,'-Height',[string]$Height,'-GuiScale',[string]$GuiScale)
    if($Standalone){$arguments+='-Standalone'}
    if($WideWalking){$arguments+='-WideWalking'}
    if($GroundMovementFixture){
        $patchPath=Join-Path $directory 'standalone-ground-fixture.json'
        New-HudGroundMovementPatch $run | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
        $patchHash=(Get-FileHash -LiteralPath $patchPath).Hash.ToLowerInvariant()
        $patchRun=$run
        (Get-Item -LiteralPath $patchPath).IsReadOnly=$true
        $arguments+=@('-GroundMovementFixture','-GroundPatchFile',$patchPath)
    }
    if($GroundCorridorFixture -or $GroundCorridorCoupled){
        $patchPath=Join-Path $directory 'ground-corridor.json'
        if($corridorInput){
            Copy-Item -LiteralPath $corridorInput.Path -Destination $patchPath
            if((Get-FileHash -LiteralPath $patchPath).Hash.ToLowerInvariant() -cne $corridorInput.Hash){throw 'Captured corridor changed during immutable copy.'}
        }else{
            New-HudGroundCorridorFixture $run | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
            $corridorInput=Read-HudGroundCorridorInput $patchPath $root $false
        }
        $patchHash=$corridorInput.Hash;$patchRun=$corridorInput.Run
        (Get-Item -LiteralPath $patchPath).IsReadOnly=$true
        $selector=if($GroundCorridorCoupled){'-GroundCorridorCoupled'}else{'-GroundCorridorFixture'}
        $arguments+=@($selector,'-GroundPatchFile',$patchPath)
        if($GroundCorridorCoupled){$arguments+=@('-MovementTraceFile',$MovementTraceFile)}
        if($GroundCorridorWalkOnly){$arguments+='-GroundCorridorWalkOnly'}
    }
    if($GroundMovementCoupled){
        Assert-MineComeProbeContext $groundContext
        $patchPath=Join-Path $directory 'captured-ground-patch.json'
        Copy-Item -LiteralPath $livePatch.Path -Destination $patchPath
        $patchHash=(Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if($patchHash -cne $livePatch.Hash){throw 'Captured ground patch changed while making immutable HUD input.'}
        (Get-Item -LiteralPath $patchPath).IsReadOnly=$true
        $patchRun=$livePatch.Run
        $arguments+=@('-GroundMovementCoupled','-GroundPatchFile',$patchPath,'-MovementTraceFile',$MovementTraceFile)
    }
    $client=Start-Child (Join-Path $PSHOME 'pwsh.exe') $arguments
    Write-Output "HUD_STREAM_START run=$run evidence=$directory composite=$([bool]$Composite)"
    $producerDirectory=Join-Path $directory 'capture'
    $readyPath=Join-Path $producerDirectory 'stream-ready.json'
    while(-not (Test-Path -LiteralPath $readyPath)) {
        if($client.HasExited) {throw "Minecraft launcher exited before readiness: $($client.ExitCode)"}
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires-25000) {throw 'Stream startup deadline reached.'}
        Assert-SessionTarget
        Start-Sleep -Milliseconds 100
    }
    $ready=Read-BoundedJson $readyPath
    if(-not $GroundCorridorCoupled){Assert-HudGroundMovementMarkers $ready ([bool]$GroundMovementFixture) ([bool]$GroundMovementCoupled) -WideWalking:$WideWalking}
    Assert-HudGroundCorridorMarker $ready ([bool]$GroundCorridorFixture) ([bool]$GroundCorridorCoupled) ([bool]$GroundCorridorWalkOnly)
    if($ready.schema -ne 1 -or $ready.run -cne $run -or $ready.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or $ready.mapping_bytes -ne 8294656 -or $ready.mapping_name -cne ('Local\MineComeHud_'+$run) -or $ready.mutex_name -cne ('Local\MineComeHudLock_'+$run) -or [string]$ready.target_pid -cne [string]$context.GamePid -or [string]$ready.target_start_filetime -cne $targetStart -or [long]$ready.expires_utc_ms -ne $expires) {throw 'Producer readiness does not match this fresh session.'}
    $producer=Get-Process -Id $ready.producer_pid -ErrorAction Stop
    try {
        if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne [string]$ready.producer_start_filetime -or -not $producer.Path.Equals((Join-Path $JavaHome 'bin\java.exe'),[StringComparison]::OrdinalIgnoreCase)) {throw 'Producer process path/start identity differs.'}
    } finally {$producer.Dispose()}
    if((Get-FileHash -LiteralPath $receiverPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $receiverHash) {throw 'Built receiver changed before launch.'}
    $receiverOutput=Join-Path $directory 'receiver-result.json'
    $receiver=Start-Child $receiverPath @('--run',$run,'--target-pid',[string]$context.GamePid,'--target-start',$targetStart,'--producer-pid',[string]$ready.producer_pid,'--producer-start',[string]$ready.producer_start_filetime,'--expires',[string]$expires,'--output',$receiverOutput)
    if($Composite) {$armEvidence=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -BundleDirectory $BundleDirectory -ReadyManifest $readyPath}
    Write-Output "HUD_STREAM_READY run=$run producer_pid=$($ready.producer_pid) receiver_pid=$($receiver.Id)"
    while(-not $client.HasExited -or -not $receiver.HasExited) {
        Assert-SessionTarget
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires+15000) {throw 'Bounded stream shutdown deadline reached; any still-running owned processes are preserved.'}
        Start-Sleep -Milliseconds 200
    }
    if($client.ExitCode -ne 0 -or $receiver.ExitCode -ne 0) {throw "Client/receiver exit failure: $($client.ExitCode)/$($receiver.ExitCode)"}
    $guest=Read-BoundedJson (Join-Path $producerDirectory 'stream-result.json')
    $native=Read-BoundedJson $receiverOutput
    if(($GroundCorridorFixture -or $GroundCorridorCoupled) -and $guest.result -ceq 'failed'){
        $reason=if($guest.lab_evidence.PSObject.Properties.Name -contains 'failure'){$guest.lab_evidence.failure}else{'No failure detail recorded'}
        throw "Minecraft corridor failed: $reason"
    }
    if(-not $GroundCorridorCoupled){Assert-HudGroundMovementMarkers $guest ([bool]$GroundMovementFixture) ([bool]$GroundMovementCoupled) -WideWalking:$WideWalking}
    Assert-HudGroundCorridorMarker $guest ([bool]$GroundCorridorFixture) ([bool]$GroundCorridorCoupled) ([bool]$GroundCorridorWalkOnly)
    if($GroundMovementFixture -or $GroundMovementCoupled){$groundProof=Assert-HudGroundMovementProof $guest $run $patchHash ([bool]$GroundMovementCoupled) $patchRun $MovementTraceFile -WideWalking:$WideWalking}
    if($GroundCorridorFixture -or $GroundCorridorCoupled){$groundProof=Assert-HudGroundCorridorProof $guest $run $corridorInput -Coupled:$GroundCorridorCoupled -TraceFile $MovementTraceFile -WalkOnly:$GroundCorridorWalkOnly}
    if($guest.run -cne $run -or $guest.result -cne 'passed' -or $native.run -cne $run -or $native.result -cne 'passed' -or $native.accepted_frames -lt 30 -or $native.closed_seen -ne $true -or $native.stale_hidden_verified -ne $true -or $native.fresh_resumption_verified -ne $true) {throw 'Continuous stream or freshness/closure evidence did not pass.'}
    foreach($expectedState in @(@(0,0),@(1,0),@(1,1),@(2,0))) {
        if(@($native.states_seen | Where-Object {$_.selected -eq $expectedState[0] -and $_.screen -eq $expectedState[1]}).Count -ne 1) {throw 'Native receiver did not observe every actual vanilla UI state.'}
    }
    Assert-SessionTarget
    $passed=$true
    Write-Output "HUD_STREAM_VERIFIED run=$run accepted_frames=$($native.accepted_frames) stale_hidden=true closed=true host_visual_verified=false"
} catch {$failure=$_.Exception.Message;throw}
finally {
    $verification=[ordered]@{schema=1;kind='minecome_hud_stream_controller_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;evidence=$directory;ground_movement_fixture=[bool]$GroundMovementFixture;ground_movement_coupled=[bool]$GroundMovementCoupled;ground_movement=$groundProof;ground_patch_sha256=$patchHash;ground_patch_run=$patchRun;movement_trace_file=$MovementTraceFile;target_kind=$(if($Standalone){'standalone_controller'}else{'kcd_tools'});target_pid=$context.GamePid;target_start_filetime=$targetStart;target_sha256=$context.GameHash;receiver_sha256=$receiverHash;compositor_armed=[bool]$armEvidence;composite_requested=[bool]$Composite;kcd_compositing_verified=$false;interactive_inventory_verified=$false;kcd_launched=$false;kcd_stopped=$false;created_utc_ms=$expires-180000;expires_utc_ms=$expires}
    if($WideWalking){$verification.walking_area='wide'}
    if($GroundCorridorFixture){$verification.ground_corridor_fixture=$true}
    if($GroundCorridorCoupled){$verification.ground_corridor_coupled=$true;$verification.walking_area='corridor'}
    if($GroundCorridorWalkOnly){$verification.corridor_walk_only=$true}
    $verification | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    if($receiver) {$receiver.Dispose()};if($client) {$client.Dispose()}
}
