# Actual Minecraft controller/physics/HUD exercise with explicitly scripted edges.
# No KCD commands, renderer arm, reverse-input mapping, or physical-input claims.
[CmdletBinding()]
param([string]$JavaHome,[string]$GroundPatchFile,[ValidateRange(-180,180)][double]$YawDegrees=0,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "Scripted physical controller fixture failed with exit code $bootstrapExit."};return
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
function Assert-HudPhysicalFixtureResult($Guest,[string]$Run,[string]$PatchHash) {
    if($Guest.schema -ne 1 -or $Guest.run -cne $Run -or $Guest.result -cne 'passed' -or $Guest.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or
        $Guest.ui_physical_controller_fixture -isnot [bool] -or -not $Guest.ui_physical_controller_fixture -or $Guest.ui_input_physical_movement -isnot [bool] -or $Guest.ui_input_physical_movement -or
        $Guest.scripted_input -isnot [bool] -or -not $Guest.scripted_input -or $Guest.physical_input_verified -isnot [bool] -or $Guest.physical_input_verified -or
        $Guest.standalone -isnot [bool] -or -not $Guest.standalone -or $Guest.kcd_compositing_verified -isnot [bool] -or $Guest.kcd_compositing_verified -or $Guest.published_frames -lt 30){throw 'Fixture stream identity/provenance/frame evidence differs.'}
    foreach($name in @('closed_published','mapping_unmapped','mapping_handle_closed','mutex_handle_closed')){
        if($Guest.$name -isnot [bool] -or -not $Guest.$name){throw "Fixture stream cleanup missing: $name"}
    }
    $proof=$Guest.lab_evidence.physical_controller_fixture
    foreach($number in @($proof.inventory_client_max_displacement,$proof.inventory_server_max_displacement,$proof.physical_movement.client_walk,$proof.physical_movement.server_walk)){
        if($number -isnot [ValueType] -or $number -is [bool] -or -not [double]::IsFinite([double]$number) -or $number -lt 0){throw 'Fixture contains invalid/nonfinite displacement.'}
    }
    if($proof.kind -cne 'standalone_hud_physical_controller_fixture_v1' -or $proof.scripted_input -isnot [bool] -or -not $proof.scripted_input -or
        $proof.physical_input_verified -isnot [bool] -or $proof.physical_input_verified -or $proof.kcd_compositing_verified -isnot [bool] -or $proof.kcd_compositing_verified -or
        $proof.completed -isnot [bool] -or -not $proof.completed -or $proof.camera_worker_stopped -isnot [bool] -or -not $proof.camera_worker_stopped -or
        $proof.inventory_client_max_displacement -gt .01 -or $proof.inventory_server_max_displacement -gt .01 -or $proof.inventory_frames -lt 2 -or $proof.walking_hud_frames -lt 2 -or $proof.synthetic_camera_samples -lt 10){throw 'Fixture did not verify actual inventory suppression, HUD frames and camera cleanup.'}
    if(@($proof.pulses).Count -ne 3){throw 'Fixture requires three actual movement pulses.'}
    for($index=0;$index -lt 3;$index++){
        $pulse=$proof.pulses[$index]
        if($pulse.key -cne @('W','W','S')[$index] -or $pulse.step_m -isnot [ValueType] -or $pulse.step_m -is [bool] -or -not [double]::IsFinite([double]$pulse.step_m) -or $pulse.step_m -lt .05 -or
            $pulse.server_step_m -isnot [ValueType] -or $pulse.server_step_m -is [bool] -or -not [double]::IsFinite([double]$pulse.server_step_m) -or $pulse.server_step_m -lt .05 -or
            $pulse.client_server_distance -isnot [ValueType] -or $pulse.client_server_distance -is [bool] -or -not [double]::IsFinite([double]$pulse.client_server_distance) -or $pulse.client_server_distance -lt 0 -or $pulse.client_server_distance -gt .1){throw 'Fixture repeated movement/server agreement failed.'}
    }
    $movement=$proof.physical_movement
    if($movement.run -cne $Run -or $movement.patch_sha256 -cne $PatchHash -or $movement.ground_source_kind -cne 'standalone_ground_fixture' -or
        $movement.input_source -cne 'scripted_hud_physical_controller_fixture' -or $movement.scripted_input -isnot [bool] -or -not $movement.scripted_input -or
        $movement.physical_input_verified -isnot [bool] -or $movement.physical_input_verified -or $movement.trace_result -cne 'passed' -or $movement.post_settle_corrections -ne 0 -or
        $movement.client_walk -lt .15 -or $movement.server_walk -lt .15 -or $movement.held_ticks -lt 3){throw 'Actual controller movement proof differs.'}
    foreach($name in @('started','completed','trace_closed','client_proxy_released','server_proxy_released','controls_released')){
        if($movement.$name -isnot [bool] -or -not $movement.$name){throw "Actual controller completion/cleanup missing: $name"}
    }
    return $proof
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw | ConvertFrom-Json
if(-not $JavaHome){foreach($candidate in @($inventory.java.jdks | ForEach-Object home)){if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){$JavaHome=$candidate;break}}}
if(-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){throw 'An installed tested JDK21 or24 is required.'}
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
$sourceHash=$null
if($GroundPatchFile){
    $GroundPatchFile=Resolve-HudMovementEvidencePath $GroundPatchFile $root
    if((Get-Item -LiteralPath $GroundPatchFile).Length -gt 65536){throw 'Source terrain patch exceeds64KiB.'}
    $patch=Get-Content -LiteralPath $GroundPatchFile -Raw | ConvertFrom-Json
    $sourceHash=(Get-FileHash -LiteralPath $GroundPatchFile -Algorithm SHA256).Hash.ToLowerInvariant()
}else{
    $points=@(for($row=0;$row -lt 5;$row++){for($column=0;$column -lt 5;$column++){[ordered]@{index=$row*5+$column+1;x=$column-2;y=$row-2;z=10;nx=0;ny=0;nz=1}}})
    $patch=[pscustomobject]@{schema=1;run='pending';grid_size=5;spacing=1;center=[ordered]@{x=0;y=0;z=10};points=$points;provenance=[ordered]@{kind='standalone_ground_fixture'}}
}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')})
if($clients.Count){throw 'An existing MineCome Minecraft client is open; preserving it.'}
if($PreflightOnly){Write-Output 'HUD_PHYSICAL_FIXTURE_PREFLIGHT_PASS no_process_started=true kcd_unchanged=true';return}
$run=[guid]::NewGuid().ToString('N');$patchRun=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/hud-physical-fixture-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[IO.Directory]::CreateDirectory($directory) | Out-Null
$patchPath=Join-Path $directory 'standalone-ground-patch.json';$tracePath=Join-Path $directory 'movement.ndjson';$viewPath=Join-Path $directory 'fixture-view.json'
$patch.run=$patchRun
$patch | Add-Member -NotePropertyName provenance -NotePropertyValue ([ordered]@{kind='standalone_ground_fixture';original_capture_sha256=$sourceHash;numeric_samples_only=$true}) -Force
$patch | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $patchPath -Encoding utf8NoBOM
(Get-Item -LiteralPath $patchPath).IsReadOnly=$true
$patchHash=(Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
$ownProcess=Get-Process -Id $PID
try{$targetStart=$ownProcess.StartTime.ToUniversalTime().ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)}finally{$ownProcess.Dispose()}
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+120000
$passed=$false;$failure=$null;$proof=$null
try{
    Write-Output "HUD_PHYSICAL_FIXTURE_START run=$run evidence=$directory scripted_input=true kcd_unchanged=true"
    & (Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1') -EvidenceDirectory $directory -Run $run -TargetPid $PID -TargetStart $targetStart -ExpiresUtcMs $expires -JavaHome $JavaHome -Standalone -PhysicalMovementFixture -GroundPatchFile $patchPath -MovementTraceFile $tracePath -HostViewFile $viewPath -PhysicalFixtureYaw $YawDegrees
    if($LASTEXITCODE -ne 0){throw "Minecraft fixture child failed: $LASTEXITCODE"}
    $guest=Get-Content -LiteralPath (Join-Path $directory 'capture/stream-result.json') -Raw | ConvertFrom-Json
    if($guest.result -ceq 'failed'){
        $reason=if($guest.PSObject.Properties.Name -contains 'failure'){$guest.failure}elseif($guest.lab_evidence.PSObject.Properties.Name -contains 'failure'){$guest.lab_evidence.failure}else{'Producer reported failure without a diagnostic'}
        throw "Minecraft fixture failed: $reason"
    }
    $proof=Assert-HudPhysicalFixtureResult $guest $run $patchHash
    $records=@(Get-Content -LiteralPath $tracePath | ForEach-Object {$_ | ConvertFrom-Json})
    if($records.Count -lt 5 -or $records.Count -gt 200 -or $records[0].kind -cne 'begin' -or $records[-1].kind -cne 'end' -or $records[-1].result -cne 'passed'){throw 'Fixture actual controller trace did not complete.'}
    foreach($record in $records){if($record.source_kind -cne 'standalone_hud_physical_movement_fixture' -or $record.run -cne $patchRun -or $record.patch_sha256 -cne $patchHash){throw 'Fixture trace provenance/session differs.'}}
    foreach($state in @('fixture_inventory_blocked','fixture_scripted_walking')){
        $sample=@($guest.samples | Where-Object state -CEQ $state)
        if($sample.Count -ne 1 -or $sample[0].png_file -notmatch '^sample-[a-z0-9_]+\.png$'){throw 'Fixture real HUD/inventory PNG sample absent.'}
        $png=Join-Path $directory ('capture/'+$sample[0].png_file)
        if((Get-Item -LiteralPath $png).Length -lt 100 -or (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sample[0].png_sha256){throw 'Fixture captured PNG hash differs.'}
    }
    $passed=$true;Write-Output "HUD_PHYSICAL_FIXTURE_VERIFIED run=$run pulses=3 inventory_movement_suppressed=true actual_minecraft=true physical_input_verified=false kcd_compositing_verified=false"
}catch{$failure=$_.Exception.Message;throw}
finally{
    [ordered]@{schema=1;kind='standalone_hud_physical_controller_fixture_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;scripted_input=$true;physical_input_verified=$false;kcd_compositing_verified=$false;kcd_commands_sent=0;renderer_armed=$false;reverse_input_mapping_created=$false;patch_sha256=$patchHash;original_capture_sha256=$sourceHash;yaw_degrees=$YawDegrees;proof=$proof} | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
