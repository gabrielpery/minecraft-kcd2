# SPDX-License-Identifier: GPL-3.0-or-later
# Actual Minecraft controller/HUD/blocks, followed by recorded native KCD movement.
# Requires an already-open exact tools world. Never launches or stops KCD2.
[CmdletBinding()]
param([switch]$PreflightOnly,[string]$JavaHome)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Combined physical extension failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundExtension.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
function Get-CoupledPhysicalExtensionFixtureArguments([string]$Patch,[string]$JavaHome,[switch]$PreflightOnly){
    $arguments=@{ExtendedWalking=$true;ExtensionWalking=$true;AimedBlocks=$true}
    if($Patch){$arguments.GroundPatchFile=$Patch}
    if($JavaHome){$arguments.JavaHome=$JavaHome}
    if($PreflightOnly){$arguments.PreflightOnly=$true}
    return $arguments
}
function Get-CoupledPhysicalExtensionReplayArguments([string]$Patch,[string]$Evidence){
    return @{ExtensionWalking=$true;GroundExtensionFile=$Patch;TraceDirectory=$Evidence}
}
function Assert-CoupledPhysicalExtensionProof($Fixture,$Replay,[string]$CaptureHash,[string]$FixtureDirectory,[int]$GamePid){
    foreach($key in @('scripted_input','trace_passed','source_hashes_verified','ui_walking_aimed_fixture')){
        if($Fixture.$key -isnot [bool] -or -not $Fixture.$key){throw "Combined extension fixture lacks $key"}
    }
    foreach($key in @('physical_input_verified','kcd_compositing_verified','renderer_armed','reverse_input_mapping_created')){
        if($Fixture.$key -isnot [bool] -or $Fixture.$key){throw 'Combined extension cannot claim live input or native HUD composition.'}
    }
    if($Fixture.result -cne 'passed' -or $Fixture.walking_area -cne 'extension' -or $Fixture.movement_session -cne 'extended' -or
        $Fixture.original_capture_sha256 -cne $CaptureHash -or $Fixture.extension_plan.result -cne 'passed' -or
        $Fixture.extension_plan.patch_sha256 -cne $Fixture.patch_sha256 -or $Fixture.extension_plan.aimed_blocks -cne $true){throw 'Combined extension requires its verified captured-terrain controller/blocks proof.'}
    if($Replay.kind -cne 'minecome_buffered_extension_movement_replay_v1' -or $Replay.result -cne 'passed' -or
        $Replay.walking_area -cne 'extension' -or $Replay.movement_session -cne 'extended' -or $Replay.target_pid -ne $GamePid -or
        $Replay.original_capture_sha256 -cne $CaptureHash -or $Replay.fixture_sha256 -cne $Fixture.patch_sha256 -or
        $Replay.source_trace_sha256 -cne $Fixture.trace_sha256 -or [IO.Path]::GetFullPath($Replay.source_evidence) -ine [IO.Path]::GetFullPath($FixtureDirectory)){
        throw 'Combined extension replay is not bound to the completed controller fixture.'
    }
    foreach($key in @('scripted_replay','restoration_verified')){if($Replay.$key -isnot [bool] -or -not $Replay.$key){throw "Native extension replay lacks $key"}}
    foreach($key in @('physical_input_verified','minecraft_connected','hud_armed','visual_smoothness_verified')){
        if($Replay.$key -isnot [bool] -or $Replay.$key){throw 'Recorded native replay cannot claim simultaneous Minecraft/HUD or manual validation.'}
    }
    foreach($key in @('cap_verified','restoration_verified','budget_valid')){
        if($Replay.host_gpu_budget.$key -isnot [bool] -or -not $Replay.host_gpu_budget.$key){throw 'Replay GPU budget did not restore cleanly.'}
    }
}
function Read-CoupledPhysicalExtensionVerification([string]$Path,[string]$Root){
    $path=Resolve-HudMovementEvidencePath $Path $Root
    $item=Get-Item -LiteralPath $path
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 1MB){throw 'Combined extension verification size differs.'}
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 24
}
$context=Get-MineComeProbeContext
if($PreflightOnly){
    & (Join-Path $PSScriptRoot 'Test-KcdGroundExtension.ps1') -PreflightOnly
    $arguments=Get-CoupledPhysicalExtensionFixtureArguments '' $JavaHome -PreflightOnly
    & (Join-Path $PSScriptRoot 'Test-HudPhysicalMovementFixture.ps1') @arguments
    Write-Output 'COUPLED_PHYSICAL_EXTENSION_PREFLIGHT_PASS no_changes=true no_game_started=true'
    return
}
$run=[guid]::NewGuid().ToString('N')
$directory=Resolve-HudMovementEvidencePath (Join-Path $context.ProjectRoot ('runtime/evidence/coupled-physical-extension-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)) $context.ProjectRoot
[void][IO.Directory]::CreateDirectory($directory)
$passed=$false;$failure=$null;$stage='capture';$capture=$null;$fixture=$null;$replay=$null;$fixtureProof=$null;$replayProof=$null
$budget=$null;$budgetEvidence=$null;$captureHash=$null;$fixtureHash=$null;$replayHash=$null;$traceHash=$null;$planHash=$null
$sourceHash=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
try{
    $captured=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundExtension.ps1') | ForEach-Object {
        if($_ -isnot [string] -and $_.PSObject.Properties['GroundExtensionFile']){$_}else{Write-Host $_}
    })
    if($captured.Count -ne 1){throw 'Expected one complete live extension capture.'}
    $capture=$captured[0];$surface=Read-HudLiveGroundExtension $capture.GroundExtensionFile $context.ProjectRoot $context;$captureHash=$surface.Hash
    $stage='minecraft_controller'
    Assert-MineComeProbeContext $context
    $budget=New-MineComeHudGpuBudget $context
    try{
        Start-MineComeHudGpuBudget $budget
        $arguments=Get-CoupledPhysicalExtensionFixtureArguments $capture.GroundExtensionFile $JavaHome
        $fixtures=@(& (Join-Path $PSScriptRoot 'Test-HudPhysicalMovementFixture.ps1') @arguments | ForEach-Object {
            if($_ -isnot [string] -and $_.PSObject.Properties['EvidenceDirectory']){$_}else{Write-Host $_}
        })
        if($fixtures.Count -ne 1){throw 'Expected one completed physical extension controller fixture.'}
        $fixture=$fixtures[0]
    }finally{
        Stop-MineComeHudGpuBudget $budget
        $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
    }
    if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Fixture GPU cap was not restored before native replay.'}
    $fixtureProof=Read-CoupledPhysicalExtensionVerification $fixture.VerificationFile $context.ProjectRoot
    $fixtureHash=(Get-FileHash -LiteralPath $fixture.VerificationFile).Hash.ToLowerInvariant();$traceHash=$fixtureProof.trace_sha256;$planHash=$fixtureProof.patch_sha256
    $stage='native_recorded_replay'
    Assert-MineComeProbeContext $context
    [void](Read-HudLiveGroundExtension $capture.GroundExtensionFile $context.ProjectRoot $context)
    $arguments=Get-CoupledPhysicalExtensionReplayArguments $capture.GroundExtensionFile $fixture.EvidenceDirectory
    $replays=@(& (Join-Path $PSScriptRoot 'Test-KcdBufferedReplay.ps1') @arguments | ForEach-Object {
        if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
    })
    if($replays.Count -ne 1){throw 'Expected one structured completed native extension replay.'}
    $replay=$replays[0];$replayProof=Read-CoupledPhysicalExtensionVerification $replay.VerificationFile $context.ProjectRoot
    $replayHash=(Get-FileHash -LiteralPath $replay.VerificationFile).Hash.ToLowerInvariant()
    Assert-CoupledPhysicalExtensionProof $fixtureProof $replayProof $captureHash $fixture.EvidenceDirectory $context.GamePid
    Assert-MineComeProbeContext $context
    if((Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Combined extension controller changed during the run.'}
    $passed=$true;$stage='complete'
}catch{$failure=$_.Exception.Message;throw}
finally{
    [ordered]@{schema=1;kind='minecome_coupled_physical_extension_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});stage=$stage;failure=$failure;
        source_sha256=$sourceHash;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();target_sha256=$context.GameHash.ToLowerInvariant();
        walking_area='extension';movement_session='extended';scripted_controller=$true;scripted_replay=$true;physical_input_verified=$false;
        simultaneous_minecraft_kcd_movement=$false;kcd_hud_composition_verified=$false;visual_smoothness_verified=$false;kcd_launched=$false;kcd_stopped=$false;
        capture_file=$(if($capture){$capture.GroundExtensionFile}else{$null});original_capture_sha256=$captureHash;
        fixture_evidence=$(if($fixture){$fixture.EvidenceDirectory}else{$null});fixture_verification_sha256=$fixtureHash;fixture_plan_sha256=$planHash;source_trace_sha256=$traceHash;
        replay_evidence=$(if($replay){$replay.EvidenceDirectory}else{$null});replay_verification_sha256=$replayHash;
        player_restoration_verified=$(if($replayProof){[bool]$replayProof.restoration_verified}else{$false});host_gpu_budget=$budgetEvidence;
        approximate_heightfield=$true;full_collision_export_verified=$false} | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
if($passed){
    Write-Host "COUPLED_PHYSICAL_EXTENSION_VERIFIED run=$run evidence=$directory scripted_controller=true scripted_replay=true native_hud_verified=false"
    [pscustomobject]@{EvidenceDirectory=$directory;VerificationFile=(Join-Path $directory 'verification.json');FixtureEvidenceDirectory=$fixture.EvidenceDirectory;ReplayEvidenceDirectory=$replay.EvidenceDirectory}
}
