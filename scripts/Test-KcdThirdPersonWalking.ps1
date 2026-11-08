# Actual guest key events -> vanilla client/server movement -> live KCD camera/HUD.
# This does not inject or claim physical Windows keyboard input.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$BundleDirectory,[Parameter(Mandatory)][string]$InstanceDirectory,
 [string]$JavaHome='C:/Program Files/Java/jdk-24')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Native walking check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$saved=$null
& (Join-Path $PSScriptRoot 'Start-GameplaySession.ps1') -BundleDirectory $BundleDirectory -InstanceDirectory $InstanceDirectory -JavaHome $JavaHome -WorldBlocks -ThirdPersonWalkingCheck | ForEach-Object {
 if($_ -is [string] -and $_.StartsWith('GAMEPLAY_SESSION_SAVED evidence=')){$saved=$_.Substring('GAMEPLAY_SESSION_SAVED evidence='.Length)}
 Write-Host $_
}
if(-not $saved){throw 'Native walking did not produce a saved session.'}
$session=Get-Content -LiteralPath (Join-Path $saved 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 30
$hostProof=Get-Content -LiteralPath (Join-Path $saved 'host-movement.json') -Raw|ConvertFrom-Json -Depth 30
$native=Get-Content -LiteralPath (Join-Path $saved 'verification.json') -Raw|ConvertFrom-Json
$f=$session.fixture
if($native.result -cne 'passed' -or -not $native.normal_client_exit -or $hostProof.Failure -or -not $hostProof.ResourcesClosed -or
 $hostProof.Terminal.result -cne 'explicit_stop' -or -not $hostProof.Terminal.camera_restored -or -not $hostProof.Terminal.body_restore_dispatched -or $hostProof.Terminal.body_hidden -or
 $hostProof.Terminal.writes -lt 2 -or $hostProof.ViewCount -lt 20 -or $hostProof.LastView.perspective -ne 0 -or $hostProof.Terminal.applied_seq -le 0){throw 'Native walking/camera/cleanup receipt incomplete.'}
$stages=@('back_before','back_walking','back_after','inventory','front_before','front_walking','front_after','first_person')
if(($f.images.stage -join '|') -cne ($stages -join '|') -or $f.back_strides -ne 6 -or $f.front_strides -ne 6 -or $f.max_excursion -gt 1 -or $f.back_distance -lt 2.1 -or $f.front_distance -lt 2.1 -or @($f.points).Count -ne 18 -or $f.stationary_back_dwell_ms -lt 12000){throw 'Native repeated walking stage evidence missing.'}
foreach($receipt in @($hostProof.LastView,$hostProof.Terminal)){
 if(-not $receipt.camera_collision_complete -or $receipt.camera_collision_generation -lt 1 -or $receipt.camera_collision_generation -ne $receipt.camera_collision_required){throw 'Native camera collision generation was not committed completely.'}
}
foreach($capture in $f.images){
 foreach($pair in @(@('file','sha256'),@('world_file','world_sha256'))){
  $file=[string]$capture.($pair[0]);$expected='native-walking-'+$capture.stage+$(if($pair[0] -ceq 'world_file'){'-world'}else{''})+'.png'
  if($file -cne $expected -or (Get-FileHash -LiteralPath (Join-Path $saved $file)).Hash.ToLowerInvariant() -cne $capture.($pair[1])){throw 'Native walking image name/hash differs.'}
 }
 if($capture.metadata.world_id -cne $session.world_id -or $capture.metadata.native_walking_stage -cne $capture.stage -or $capture.metadata.frame_format -ne 2){throw 'Native walking image identity differs.'}
}
[ordered]@{schema=1;kind='minecome_native_third_person_walking_verification_v1';result='passed';run=$session.run;world_id=$session.world_id;
 actual_minecraft=$true;scripted_guest_input=$true;live_kcd_camera_acknowledged=$true;physical_native_keys_verified=$false;
 position_writes_used=$false;velocity_writes_used=$false;fixture_camera_writes_used=$false;back_distance=$f.back_distance;front_distance=$f.front_distance;
 back_strides=$f.back_strides;front_strides=$f.front_strides;max_excursion=$f.max_excursion;camera_collision_generation=$hostProof.Terminal.camera_collision_generation;camera_collision_complete=$true;
 stationary_back_dwell_ms=$f.stationary_back_dwell_ms;stationary_back_started_utc_ms=$f.stationary_back_started_utc_ms;stationary_back_completed_utc_ms=$f.stationary_back_completed_utc_ms;
 captured_stages=$stages;normal_client_exit=$native.normal_client_exit;camera_restored=$hostProof.Terminal.camera_restored;body_restored=$hostProof.Terminal.body_restore_dispatched}|
 ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $saved 'native-walking-verification.json') -Encoding utf8NoBOM
Write-Output "NATIVE_THIRD_PERSON_WALKING_PASS evidence=$saved"
