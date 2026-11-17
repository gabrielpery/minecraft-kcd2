# Actual vanilla Elytra input/physics in an isolated save, including UI hold and natural landing.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath,[switch]$Persistence,[string]$VerifyEvidenceDirectory)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Gameplay Elytra check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$verifyOnly=-not [string]::IsNullOrWhiteSpace($VerifyEvidenceDirectory)
if($verifyOnly){
 $directory=(Resolve-Path -LiteralPath $VerifyEvidenceDirectory).Path
 if(-not $directory.StartsWith((Join-Path $root 'runtime/evidence')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Saved Elytra evidence must be inside this project.'}
 $patch=Join-Path $directory 'ground-patch.json'
 $patchData=Get-Content -LiteralPath $patch -Raw|ConvertFrom-Json -Depth 12
 $run=[string]$patchData.run
 if($run -cnotmatch '^[0-9a-f]{32}$' -or $patchData.provenance.kind -cne 'standalone_fixture'){throw 'Saved Elytra fixture terrain identity differs.'}
 $instance=Join-Path $directory 'instance'
}else{
 $run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-elytra-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
 [void][IO.Directory]::CreateDirectory($directory)
 $instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
 New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
}
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null;$guestDirectory=$null;$proofs=[Collections.Generic.List[object]]::new()
try{
 foreach($phase in $(if($Persistence){@('elytra-save','elytra-resume')}else{@('elytra')})){
 if($verifyOnly){
  $guestDirectory=Join-Path $directory $phase
  $verificationFile=Join-Path $guestDirectory 'verification.json'
 }else{
  $launchArguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Flight=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$launchArguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @launchArguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw 'Missing Elytra guest result.'}
  $guestDirectory=$result[0].EvidenceDirectory;$verificationFile=$result[0].VerificationFile
 }
 $verification=Get-Content -LiteralPath $verificationFile -Raw|ConvertFrom-Json
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Elytra guest did not save and close normally.'}
 $session=Get-Content -LiteralPath (Join-Path $guestDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 $f=$session.fixture;$m=$session.movement
 if($f.kind -cne 'minecome_gameplay_elytra_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or
  $f.direct_command_api_used -or $f.ability_writes_used -or $f.position_writes_used -or $f.glide_flag_writes_used -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified -or
  $f.game_mode -cne 'survival' -or -not $session.flight_enabled){throw 'Elytra fixture scope/state differs.'}
 if(-not $Persistence){
 foreach($flag in @('creative_takeoff_verified','glide_verified','steering_verified','glide_pose_verified','inventory_hold_verified','glide_resumed_verified','landing_verified','walking_after_landing_verified','missing_elytra_rejected','rocket_boost_verified','ground_rocket_rejected')){
  if($f.$flag -ne $true){throw "Missing actual Elytra capability: $flag"}
 }
 if($f.glide_ticks -lt 10 -or $f.inventory_ticks -lt 10 -or $f.max_altitude -lt 9 -or $f.health -le 0 -or
  ($f.submitted_commands -join '|') -cne '/item replace entity @s armor.chest with minecraft:elytra|/item replace entity @s weapon.mainhand with minecraft:firework_rocket 3|/gamemode survival|/item replace entity @s armor.chest with minecraft:air'){
  throw 'Actual gliding/input/command evidence is incomplete.'
 }
 foreach($point in @('glide_started','forward_glide','steered','held_inventory')){
  if(-not $f.points.$point.gliding -or $f.points.$point.flying -or [Math]::Abs([double]$f.points.$point.eye_height-.4) -gt .001){throw "Missing actual prone glide pose: $point"}
 }
 if(-not $f.points.landed.grounded -or $f.points.landed.gliding -or -not $f.points.unequipped_jump.grounded){throw 'Elytra did not finish a natural landing and no-equipment jump.'}
 }else{
  if($phase -ceq 'elytra-save'){
   foreach($flag in @('creative_takeoff_verified','glide_verified','steering_verified','glide_pose_verified','gliding_save_verified')){
    if($f.$flag -ne $true){throw "Missing saved Elytra capability: $flag"}
   }
   if(-not $session.new_world -or -not $m.first_attachment -or -not $m.resume_checkpoint.gliding -or -not $f.server_gliding -or
    $f.glide_ticks -lt 10 -or $f.max_altitude -lt 9 -or $f.rocket_boost_verified -or $f.health -le 0 -or
    ($f.submitted_commands -join '|') -cne '/item replace entity @s armor.chest with minecraft:elytra|/item replace entity @s weapon.mainhand with minecraft:firework_rocket 3|/gamemode survival'){
    throw 'First Elytra persistence phase did not save actual airborne vanilla state.'
   }
  }else{
   foreach($flag in @('glide_verified','steering_verified','glide_pose_verified','resume_verified','glide_resumed_verified','landing_verified','walking_after_landing_verified')){
    if($f.$flag -ne $true){throw "Missing resumed Elytra capability: $flag"}
   }
   $prior=$proofs[0].session;$restored=$f.movement.resume_checkpoint;$saved=$prior.movement.resume_checkpoint
   if($session.new_world -or $m.first_attachment -or -not $m.resume_position_restored -or
    $f.player_id -cne $prior.fixture.player_id -or $session.world_id -cne $prior.world_id -or
    -not $restored.gliding -or $restored.flying -or $restored.falling -or $m.resume_checkpoint.gliding -or $f.server_gliding -or
    $f.points.resumed_glide.health -ne $prior.fixture.health -or @($f.submitted_commands).Count -ne 0){throw 'Saved Elytra identity, state or normal landing differs.'}
   foreach($axis in @('x','y','z')){
    if([Math]::Abs([double]$restored.$axis-[double]$saved.$axis) -gt .00001 -or
     [Math]::Abs([double]$f.initial_position.$axis-[double]$saved.$axis) -gt .04){throw "Saved glide position changed on $axis"}
   }
   if(-not $f.points.resumed_glide.gliding -or [Math]::Abs([double]$f.points.resumed_glide.eye_height-.4) -gt .001 -or
    -not $f.points.resume_landed.grounded -or $f.points.resume_landed.gliding){throw 'Persisted Elytra pose did not resume and land.'}
  }
 }
 if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
  -not $m.flight_enabled -or -not $m.cleanup_complete -or -not $m.ground_cells_air -or -not $m.terrain_cells_valid -or
  -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or -not $m.resume_checkpoint_present -or
  $m.resume_checkpoint.flying -or $m.resume_checkpoint.falling){throw 'Elytra movement/collision/checkpoint cleanup failed.'}
 if($session.blocks.failure -or $session.blocks.owned_count -ne 0 -or -not $session.blocks.cleanup_complete){throw 'Elytra changed block ownership or failed cleanup.'}
 if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash){throw 'Elytra fixture modified its captured terrain.'}
 $pose=Get-Content -LiteralPath (Join-Path $guestDirectory 'gameplay-pose.json') -Raw|ConvertFrom-Json
 if($pose.kind -cne 'minecome_gameplay_pose_v1' -or $pose.run -cne $session.run -or $pose.world_id -cne $session.world_id -or $pose.seq -le 0){throw 'Elytra pose publication identity differs.'}
 $proofs.Add([pscustomobject]@{phase=$phase;directory=$guestDirectory;session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_elytra_verification_v1';run=$run;persistence=[bool]$Persistence;verified_existing_evidence=$verifyOnly;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;scripted_flight_input=$true;direct_command_api_used=$false;ability_writes_used=$false;position_writes_used=$false;
  glide_flag_writes_used=$false;kcd_connected=$false;native_input_verified=$false;instance=$instance;patch_sha256=$patchHash;guest_directory=$guestDirectory;session=$session;launches=$proofs.ToArray()
 }|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory $(if($verifyOnly){'reverification.json'}else{'verification.json'})) -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_ELYTRA_PASS evidence=$directory"
