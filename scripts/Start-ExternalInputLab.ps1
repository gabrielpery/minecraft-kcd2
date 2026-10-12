#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Owns a fresh Minecraft input lab. KCD2 is never launched, stopped or moved here.
[CmdletBinding()]
param(
    [switch]$Fixture,
    [string]$PatchFile,
    [string]$JavaHome,
    [string]$Bindings='W,S,A,D,SPACE,LSHIFT',
    [ValidateRange(15,40)][int]$InputSeconds=30,
    [ValidateRange(1,60)][int]$ArmWaitSeconds=60,
    [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'InputBindings.ps1')
. (Join-Path $PSScriptRoot 'InputLabEvidence.ps1')
. (Join-Path $PSScriptRoot 'ExternalInputPoseEvidence.ps1')
$bindingSet=Get-MineComeInputBindings $Bindings
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw|ConvertFrom-Json
if(-not $JavaHome) {
    foreach($candidate in @($env:JAVA_HOME)+@($inventory.java.jdks|ForEach-Object home)) {
        if($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'release')) -and
            [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { $JavaHome=$candidate;break }
    }
}
if(-not $JavaHome) { throw 'An existing tested JDK21 or24 is required.' }
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or
    [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { throw 'The supplied JDK is outside the tested21/24 versions.' }
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'"|Where-Object{
    $_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*') })
if($clients.Count) { throw 'An owned development client is already open; preserving it.' }
$context=$null;$captureExe=$null
if(-not $Fixture) {
    . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
    $context=Get-MineComeProbeContext
    $captureExe=(Resolve-Path -LiteralPath (Join-Path $root 'build/native/Release/minecome_input_capture.exe')).Path
}
if($PreflightOnly) { Write-Output 'External-input lab preflight passed; no process or world changes made.';return }
$run=[Guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/external-input-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run)
New-Item -ItemType Directory -Path $directory|Out-Null
$inputFile=Join-Path $directory 'input.ndjson'
$poseFile=Join-Path $directory 'minecraft-pose.ndjson'
$poseEvidence=$null
$client=$null;$native=$null;$failure=$null;$passed=$false;$nativeCleanup=$false;$kind=$null
$targetPid=if($Fixture){1}else{$context.GamePid}
$targetStart=if($Fixture){'1'}else{$context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)}
$clientStart=$null;$nativeStart=$null;$nativeSnapshot=$null
$viewEvidence=$null;$viewFile=$null;$viewHash=$null;$captureHash=$null
function Write-FixtureInput {
    $encoding=[Text.UTF8Encoding]::new($false,$true)
    $stream=[IO.FileStream]::new($inputFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $clock=[Diagnostics.Stopwatch]::StartNew();$sequence=0
    function Emit-Fixture([string]$RecordKind,[bool]$Focused,[bool]$Armed,[bool]$Forward,[bool]$Jump,[int]$Dx=0,[int]$Dy=0,[int]$AgeMillis=0) {
        $script:fixtureSequence++
        $record=[ordered]@{schema=1;source_kind='windows_raw_input_v1';kind=$RecordKind;run=$run;seq=$script:fixtureSequence;utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();monotonic_ms=$(if($RecordKind -eq 'begin'){0}else{$clock.ElapsedMilliseconds});target_pid=$targetPid;target_start_filetime=$targetStart;focused=$Focused;armed=$Armed;held=[ordered]@{forward=$Forward;back=$false;left=$false;right=$false;jump=$Jump;sprint=$false};mouse_dx=$Dx;mouse_dy=$Dy}
        if($AgeMillis){$record.utc_ms-=$AgeMillis}
        if($RecordKind -eq 'end'){$record.reason='duration'}
        $bytes=$encoding.GetBytes(($record|ConvertTo-Json -Depth 5 -Compress)+"`n")
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush()
    }
    $script:fixtureSequence=0;$mouseSent=$false
    try {
        Emit-Fixture begin $false $false $false $false
        # Deliberately old held/mouse input must be discarded; the next fresh neutral
        # sample reopens the gate before the ordinary walking/jumping/look proof.
        Emit-Fixture sample $true $true $true $false 17 11 500
        while($clock.ElapsedMilliseconds -lt 5500) {
            Start-Sleep -Milliseconds 50;$elapsed=$clock.ElapsedMilliseconds
            $dx=0;$dy=0
            if($elapsed -ge 2850 -and -not $mouseSent){$dx=30;$dy=-12;$mouseSent=$true}
            $focused=$elapsed -lt 5000
            Emit-Fixture sample $focused $focused ($elapsed -ge 200 -and $elapsed -lt 400) ($elapsed -ge 950 -and $elapsed -lt 1100) $dx $dy
        }
        Emit-Fixture end $false $false $false $false
    } finally { $stream.Dispose();$clock.Stop() }
    Write-Output 'INPUT_FIXTURE_COMPLETE synthetic keys/mouse plus one expired held/mouse sample; physical KCD input was not supplied.'
}
try {
    if($Fixture -and -not $PatchFile) {
        $points=for($row=0;$row -lt 5;$row++){for($column=0;$column -lt 5;$column++){
            [ordered]@{index=1+$row*5+$column;x=120+$column-2;y=2040+$row-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit'}
        }}
        $PatchFile=Join-Path $directory 'synthetic-ground.json'
        [ordered]@{schema=1;run=$run;result='sampled';center=[ordered]@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=[ordered]@{kind='standalone_fixture';captured_utc=[DateTime]::UtcNow.ToString('o')}}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $PatchFile -Encoding utf8
    } elseif(-not $PatchFile) {
        $captureOutput=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch)
        $capture=@($captureOutput|Where-Object{$_ -isnot [string] -and $_.GroundPatchFile})
        if($capture.Count -ne 1){throw 'One complete ground capture is required.'}
        $PatchFile=$capture[0].GroundPatchFile
    }
    $PatchFile=(Resolve-Path -LiteralPath $PatchFile).Path
    if((Get-Item -LiteralPath $PatchFile).Length -gt 65536){throw 'Ground patch exceeds64KiB.'}
    $data=Get-Content -LiteralPath $PatchFile -Raw|ConvertFrom-Json;$kind=$data.provenance.kind
    $patchHash=(Get-FileHash -LiteralPath $PatchFile).Hash
    if($kind -eq 'standalone_fixture' -and -not $Fixture){throw 'Synthetic terrain/input requires explicit -Fixture.'}
    if($kind -notin @('standalone_fixture','live_kcd_ground_patch')){throw 'Unknown ground provenance.'}
    if($kind -eq 'live_kcd_ground_patch') {
        $sourceDirectory=Split-Path -Parent $PatchFile
        $record=Get-Content -LiteralPath (Join-Path $sourceDirectory 'verification.json') -Raw|ConvertFrom-Json
        $receipt=Get-Content -LiteralPath (Join-Path $sourceDirectory 'receipt.json') -Raw|ConvertFrom-Json
        $sourceHash=(Get-FileHash -LiteralPath (Join-Path $sourceDirectory 'ground_patch.lua')).Hash
        $currentHash=(Get-FileHash -LiteralPath (Join-Path $root 'kcd2/probes/ground_patch.lua')).Hash
        $official=@($inventory.steam.relevant_apps|Where-Object{$_.role -eq 'official_tools' -and $_.installed})
        $pinned=@($official.binaries|Where-Object path -eq $record.GamePath)
        if($record.Patch -ne $true -or $record.FunctionReloadVerified -ne $true -or $record.EngineReceiptVerified -ne $true -or $record.Failure -or
            $record.GroundPatchFile -ne $PatchFile -or $record.GroundPatchHash -ne $patchHash -or $record.Run -ne $data.run -or $receipt.run -ne $data.run -or
            $receipt.stable_player -ne $true -or $receipt.valid_count -ne 25 -or $sourceHash -ne $currentHash -or $record.SourceHash -ne $sourceHash -or $record.SnapshotHash -ne $sourceHash -or
            $data.provenance.source_sha256 -ne $sourceHash -or $pinned.Count -ne 1 -or $pinned[0].sha256 -ne $record.GameHash -or $data.provenance.game_exe_hash -ne $record.GameHash){throw 'Live ground patch does not match its captured immutable engine evidence.'}
    }
    $snapshot=Join-Path $directory 'ground-patch.json';Copy-Item -LiteralPath $PatchFile -Destination $snapshot
    if((Get-FileHash -LiteralPath $snapshot).Hash -ne $patchHash){throw 'Ground patch changed while copying.'}
    (Get-Item -LiteralPath $snapshot).IsReadOnly=$true
    $viewFile=Join-Path $directory 'view-seed.json'
    if($Fixture) {
        # Explicitly synthetic yaw45/pitch-10, distinct from the old fixed yaw90.
        [ordered]@{schema=1;run=$run;source_kind='standalone_fixture';patch_sha256=$patchHash.ToLowerInvariant();target_pid=$targetPid;target_start_filetime=$targetStart;captured_utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();player=$data.center;forward=[ordered]@{x=-0.6963642403200189;y=-0.696364240320019;z=0.17364817766693033};up=[ordered]@{x=0.12278780396897282;y=0.12278780396897285;z=0.984807753012208}}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $viewFile -Encoding utf8
        (Get-Item -LiteralPath $viewFile).IsReadOnly=$true
    } else {
        $viewEvidence=& (Join-Path $PSScriptRoot 'Capture-InputViewSeed.ps1') -Context $context -PatchFile $snapshot -EvidenceDirectory $directory -InputRun $run
        $viewFile=$viewEvidence.ViewSeedFile
    }
    $viewHash=(Get-FileHash -LiteralPath $viewFile).Hash
    $viewKind=if($Fixture){'standalone_fixture'}else{'live_kcd_view_seed'}
    $starter=Join-Path $PSScriptRoot 'Run-ExternalInputClient.ps1'
    $arguments=@('-NoProfile','-File',('"'+$starter+'"'),'-EvidenceDirectory',('"'+$directory+'"'),'-PatchFile',('"'+$snapshot+'"'),'-ViewSeedFile',('"'+$viewFile+'"'),'-InputFile',('"'+$inputFile+'"'),'-PoseFile',('"'+$poseFile+'"'),'-InputRun',$run,'-TargetPid',[string]$targetPid,'-TargetStartFiletime',$targetStart,'-JavaHome',('"'+$JavaHome+'"'))
    if($Fixture){$arguments+='-Fixture'}
    if(-not $Fixture){Write-Output "Preparing input lab: forward/back/left/right/jump/sprint=$($bindingSet.Argument); F8 arms. Keep the KCD player/view still during startup. After READY, use a short forward tap within the4x4m patch."}
    $client=Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -WorkingDirectory $root -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'client.stdout.log') -RedirectStandardError (Join-Path $directory 'client.stderr.log')
    $clientStart=$client.StartTime.ToUniversalTime();$deadline=[DateTime]::UtcNow.AddSeconds(140);$ready=$false
    $logFile=Join-Path $directory 'minecraft.log'
    do {
        if(Test-Path -LiteralPath $logFile){$log=Get-Content -LiteralPath $logFile -Raw;if($log){$ready=Test-MineComeInputLabMarker -Log $log -Event READY -Run $run -ViewHash $viewHash -ViewKind $viewKind};if($log -match 'EXTERNAL_INPUT_LAB_FAIL'){throw 'Minecraft input lab failed before ready; inspect its log.'}}
        if($ready){break};if($client.HasExited){throw 'Owned Minecraft launcher exited before readiness.'};Start-Sleep -Milliseconds 100
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $ready){throw 'Minecraft input lab readiness deadline elapsed.'}
    if($Fixture){Write-FixtureInput}
    else {
        Assert-MineComeProbeContext $context
        $nativeSnapshot=Join-Path $directory 'minecome_input_capture.exe';$captureHash=(Get-FileHash -LiteralPath $captureExe).Hash
        Copy-Item -LiteralPath $captureExe -Destination $nativeSnapshot
        if((Get-FileHash -LiteralPath $nativeSnapshot).Hash -ne $captureHash){throw 'Native input helper changed while copying.'}
        (Get-Item -LiteralPath $nativeSnapshot).IsReadOnly=$true
        $args=@('--target-pid',[string]$targetPid,'--target-start',$targetStart,'--run',$run,'--output',('"'+$inputFile+'"'),'--seconds',[string]$InputSeconds,'--bindings',$bindingSet.Argument,'--arm-wait-seconds',[string]$ArmWaitSeconds)
        $native=Start-Process -FilePath $nativeSnapshot -WorkingDirectory $root -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'native.stdout.log') -RedirectStandardError (Join-Path $directory 'native.stderr.log')
        $nativeStart=$native.StartTime.ToUniversalTime()
        Write-Output "EXTERNAL_INPUT_CAPTURE_READY: you have $ArmWaitSeconds seconds to switch to KCD2, close menus, release controls and press F8. Wait briefly, tap $($bindingSet.Forward) for about0.2s, release, press $($bindingSet.Jump), then move the mouse slightly horizontally and vertically. Capture ends $InputSeconds seconds after arming; rearming does not restart it."
    }
    $finish=[DateTime]::UtcNow.AddSeconds($ArmWaitSeconds+$InputSeconds+30)
    while(-not $client.HasExited -and [DateTime]::UtcNow -lt $finish){Start-Sleep -Milliseconds 100}
    if(-not $client.HasExited){throw 'Owned Minecraft normal shutdown is pending; no existing game was stopped.'}
    $client.WaitForExit();$log=Get-Content -LiteralPath $logFile -Raw
    $passed=$client.ExitCode -eq 0 -and (Test-MineComeInputLabMarker -Log $log -Event READY -Run $run -ViewHash $viewHash -ViewKind $viewKind) -and (Test-MineComeInputLabMarker -Log $log -Event PASS -Run $run -ViewHash $viewHash -ViewKind $viewKind) -and $log -notmatch 'EXTERNAL_INPUT_LAB_FAIL'
    if(-not $passed){throw 'Minecraft input proof did not complete; inspect EXTERNAL_INPUT_LAB_FAIL in minecraft.log. The owned native helper will be stopped.'}
    if($native){$native.WaitForExit(5000)|Out-Null;if(-not $native.HasExited -or $native.ExitCode -ne 0){throw 'Native capture did not exit normally.'};$nativeLog=Get-Content -LiteralPath (Join-Path $directory 'native.stdout.log') -Raw;$nativeCleanup=$nativeLog -match 'INPUT_CAPTURE_CLEANUP unregistered=true' -and $nativeLog -match 'FOCUS_OBSERVER_CLEANUP unhooked=true' -and $nativeLog -match 'INPUT_CAPTURE_END reason=duration';if(-not $nativeCleanup){throw 'Native capture cleanup was not acknowledged.'}}
    if($native -and $nativeLog -notmatch ('(?m)^INPUT_CAPTURE_BINDINGS keys='+[regex]::Escape($bindingSet.Argument)+'\r?$')){throw 'Native capture did not acknowledge the selected bindings.'}
    if($native -and ($nativeLog -notmatch '(?m)^INPUT_CAPTURE_ARMED elapsed_ms=\d+ active_seconds=' -or $nativeLog -match 'INPUT_CAPTURE_ARM_TIMEOUT')){throw 'F8 was not observed within the arm window; physical-input check is incomplete.'}
    if($Fixture -and $log -notmatch ('EXTERNAL_INPUT_EXPIRED_SAMPLE_DROPPED inputRun='+$run+' inputSeq=2 discardedFrames=1')){throw 'The fixture did not acknowledge dropping its expired held/mouse sample.'}
    $poseEvidence=Test-MineComeExternalInputPoseEvidence -Path $poseFile -InputRun $run -TargetPid $targetPid -TargetStartFiletime $targetStart -PatchFile $snapshot -ViewSeedFile $viewFile -Fixture ([bool]$Fixture)
    $poseEvidence|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $directory 'pose-verification.json')
    Write-Output "EXTERNAL_INPUT_APPLICATION_PASS fixture=$Fixture ground=$kind; actual vanilla client/server movement/view/release verified. Evidence: $directory"
}catch{$failure=$_.Exception.Message;throw}
finally {
    if($native -and -not $native.HasExited){try{$owned=Get-Process -Id $native.Id -ErrorAction Stop;if($owned.Path -eq $nativeSnapshot -and $owned.StartTime.ToUniversalTime() -eq $nativeStart){Stop-Process -Id $native.Id -ErrorAction Stop}}catch{$_|Out-String|Set-Content -LiteralPath (Join-Path $directory 'native-recovery-error.txt')}}
    [pscustomobject]@{
        Kind='Owned external-input Minecraft lab';Run=$run;FixtureInput=[bool]$Fixture
        GroundSourceKind=$kind;PatchFile=$PatchFile;PatchHash=$patchHash
        ViewSeedFile=$viewFile;ViewSeedHash=$viewHash;ViewCaptureEvidence=$viewEvidence
        Bindings=$bindingSet;RequestedArmWaitSeconds=$ArmWaitSeconds;RequestedActiveSeconds=$InputSeconds
        InputFile=$inputFile;ExpectedTargetPid=$targetPid;ExpectedTargetStartFiletime=$targetStart
        PoseFile=$poseFile;PoseEvidence=$poseEvidence;PoseExportVerified=($null -ne $poseEvidence)
        ClientHelperPid=$(if($client){$client.Id}else{$null});ClientHelperStartedUtc=$clientStart
        NativeHelperPid=$(if($native){$native.Id}else{$null});NativeCaptureHash=$captureHash
        NativeCleanupVerified=$nativeCleanup;MinecraftInputApplicationVerified=$passed
        PhysicalKcdInputVerified=$false;KcdPlayerMovementApplied=$false;FullWorldMovementAuthorityVerified=$false;Failure=$failure
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $directory 'verification.json')
}
