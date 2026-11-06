# Actual vanilla player, armor and held-item pixels in the production transparent world/depth layers.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Player render check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-player-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'player');FixturePhase='player';WorldBlocks=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing player guest result.'}
 $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks -or -not $verification.hands){throw 'Player fixture did not save and close normally.'}
 $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 $f=$session.fixture;$m=$session.movement;$b=$session.blocks
 if($f.kind -cne 'minecome_gameplay_player_fixture_v1' -or $f.mode -cne 'player' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.native_camera_verified -or $f.direct_command_api_used -or $f.position_writes_used -or $f.velocity_writes_used -or
  -not $f.walking_verified -or -not $f.inventory_suppression_verified -or $f.client_walk_distance -lt .5 -or $f.client_walk_distance -gt 3.25 -or $f.server_walk_distance -lt .5 -or [Math]::Abs($f.client_walk_distance-$f.server_walk_distance) -gt .04 -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or -not $session.world_blocks_enabled -or -not $session.new_world -or
  -not $f.render_pixels_verified -or -not $f.perspective_restored -or $f.skin_texture -cne 'minecraft:textures/entity/player/wide/steve.png' -or $f.skin_model -cne 'WIDE' -or
  $f.helmet -cne 'minecraft:diamond_helmet' -or $f.chestplate -cne 'minecraft:diamond_chestplate' -or $f.held -cne 'minecraft:diamond_sword' -or $f.selected_slot -ne 0){throw 'Player fixture state/scope differs.'}
 if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
  -not $m.cleanup_complete -or -not $m.terrain_cells_valid -or -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or
  $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or $b.owned_count -ne 0){throw 'Player fixture collision/controls cleanup failed.'}
 if(($f.submitted_commands -join '|') -cne '/item replace entity @s armor.head with minecraft:diamond_helmet|/item replace entity @s armor.chest with minecraft:diamond_chestplate|/item replace entity @s hotbar.0 with minecraft:diamond_sword'){throw 'Equipment did not come through actual vanilla chat.'}
 $names=@('back','front','armored','sword','walking_a','walking_b','inventory','restored','first_person')
 if(@($f.images).Count -ne $names.Count -or (@($f.images.stage) -join '|') -cne ($names -join '|')){throw 'Player image set incomplete.'}
 foreach($capture in $f.images){
  $file=Join-Path $result[0].EvidenceDirectory $capture.file;$worldFile=Join-Path $result[0].EvidenceDirectory $capture.world_file
  if($capture.file -cne ('player-'+$capture.stage+'.png') -or $capture.world_file -cne ('player-'+$capture.stage+'-world.png') -or
   -not (Test-Path -LiteralPath $file -PathType Leaf) -or -not (Test-Path -LiteralPath $worldFile -PathType Leaf) -or
   (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $capture.sha256 -or (Get-FileHash -LiteralPath $worldFile).Hash.ToLowerInvariant() -cne $capture.world_sha256 -or
   $capture.metadata.world_id -cne $session.world_id -or $capture.metadata.player_fixture_stage -cne $capture.stage){throw 'Player PNG content/identity differs.'}
  $first=$capture.stage -ceq 'first_person';$inventory=$capture.stage -ceq 'inventory'
  $perspective=if($first){'FIRST_PERSON'}elseif($capture.stage -ceq 'back'){'THIRD_PERSON_BACK'}else{'THIRD_PERSON_FRONT'}
  if($capture.metadata.frame_format -ne 2 -or $capture.metadata.rendered_world_blocks -ne 0 -or [bool]$capture.metadata.player_pixels -eq $first -or
   $capture.metadata.perspective -cne $perspective -or [bool]$capture.metadata.hand_pass_rendered -ne $first -or $capture.metadata.screen -ne $(if($inventory){1}else{0}) -or
   -not $capture.depth_finite_unit_range -or $capture.world_stray_pixels -ne 0){throw 'Player perspective/depth/hand metadata differs.'}
  if($first){if($capture.world_opaque_pixels -ne 0 -or $capture.foreground_hand_pixels -lt 100){throw 'First-person body suppression/hand return failed.'}}
  elseif($capture.world_opaque_pixels -lt 500 -or $capture.world_with_depth_pixels -lt $capture.world_opaque_pixels*.95){throw 'Actual player pixels lack same-frame world depth.'}
 }
 $armored=@($f.images|Where-Object stage -CEQ 'armored')[0];$sword=@($f.images|Where-Object stage -CEQ 'sword')[0]
 if($armored.changed_from_front_pixels -lt 150 -or $sword.changed_from_armored_pixels -lt 50){throw 'Armor/held-item changes did not change body pixels.'}
 $walkA=@($f.images|Where-Object stage -CEQ 'walking_a')[0];$walkB=@($f.images|Where-Object stage -CEQ 'walking_b')[0]
 $motionA=$walkA.metadata.player_fixture_motion;$motionB=$walkB.metadata.player_fixture_motion
 if($walkA.changed_from_sword_pixels -lt 100 -or $walkB.changed_from_walking_a_pixels -lt 100 -or
  $motionA.client_horizontal_speed -lt .05 -or $motionB.client_horizontal_speed -lt .05 -or $motionA.limb_speed -lt .1 -or $motionB.limb_speed -lt .1 -or
  [Math]::Abs($motionB.limb_position-$motionA.limb_position) -lt .2){throw 'Ordinary W input did not produce moving vanilla limbs and changed body pixels.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_player_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_ui=$true;direct_command_api_used=$false;native_input_verified=$false;kcd_connected=$false;native_camera_verified=$false;instance=$instance;patch_sha256=$patchHash;session=$session}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_PLAYER_PASS evidence=$directory"
