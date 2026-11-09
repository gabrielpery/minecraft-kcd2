# Actual vanilla melee/armour and optional bow use/rendering; synthetic host only.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath,[switch]$BowCheck)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Combat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-combat-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
$terrain=New-HudGroundMovementPatch $run -WideWalking
$terrain|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'combat');FixturePhase='combat';WorldBlocks=$true;Combat=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 if($BowCheck){$arguments.BowCheck=$true}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments|ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing combat result.'}
 $v=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 $file=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$session=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -Depth 30
 $f=$session.fixture;$m=$session.movement;$b=$session.blocks;$c=$session.combat
 if($v.result -cne 'passed' -or -not $v.normal_client_exit -or -not $session.world_blocks_enabled -or
  $f.kind -cne 'minecome_gameplay_combat_fixture_v1' -or $f.mode -cne 'combat' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or -not $f.synthetic_host -or $f.native_input_verified -or $f.live_kcd_verified -or $f.position_writes_used -or $f.direct_health_inventory_entity_writes -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified){throw 'Combat verification scope differs.'}
 foreach($flag in @('fist_damage_verified','wooden_sword_verified','diamond_sword_verified','cooldown_verified','durability_verified','inventory_suppression_verified','minecraft_block_occlusion_verified','incoming_damage_verified','armor_verified','render_pixels_verified')){if($f.$flag -ne $true){throw "Missing actual combat capability: $flag"}}
 if($f.hits.Count -ne 4 -or $f.barehand_damage -ne 1 -or $f.wooden_sword_damage -ne 4 -or $f.diamond_sword_damage -ne 7 -or
  $f.rapid_diamond_damage -le 0 -or $f.rapid_diamond_damage -ge $f.diamond_sword_damage -or $f.unarmored_hurt -ne 8 -or $f.armored_hurt -le 0 -or $f.armored_hurt -ge 8 -or
  $f.final_state.held_damage -ne 2 -or $f.final_state.chest_damage -le 0){throw 'Vanilla weapons/cooldown/armour evidence differs.'}
 if($m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $hash -or
  $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or ($c.PSObject.Properties['failure'] -and $c.failure) -or -not $c.cleanup_complete -or $c.pending -or
  $c.outgoing_hits -ne 4 -or $c.hit_ack -ne 4 -or $c.hurt_ack -ne 2 -or $c.incoming_hurts -ne 2){throw 'Combat ownership, confirmation or cleanup differs.'}
 $expectedStages=if($BowCheck){'combat|bow'}else{'combat'}
 if(($f.images.stage -join '|') -cne $expectedStages){throw 'Missing actual combat HUD capture.'}
 foreach($capture in $f.images){if($capture.file -cne ('combat-'+$capture.stage+'.png') -or (Get-FileHash -LiteralPath (Join-Path $result[0].EvidenceDirectory $capture.file)).Hash.ToLowerInvariant() -cne $capture.sha256 -or
  $capture.metadata.world_id -cne $session.world_id -or $capture.metadata.combat_fixture_stage -cne $capture.stage -or -not $capture.metadata.PSObject.Properties['world_camera']){throw 'Combat capture bytes/identity differ.'}}
 if($BowCheck){
  $bow=$f.bow
  foreach($flag in @('experimental_fixture_only','inventory_cancel_verified','authority_cancel_verified','short_charge_verified','full_charge_verified','no_ammunition_verified','projectile_render_pixels_verified')){if($bow.$flag -isnot [bool] -or -not $bow.$flag){throw "Missing actual bow capability: $flag"}}
  if($bow.native_projectile_collision_verified -isnot [bool] -or $bow.native_projectile_collision_verified -or
   $bow.controller.starts -ne 4 -or $bow.controller.vanilla_releases -ne 2 -or $bow.controller.cancellations -ne 3 -or $bow.controller.rejected -ne 1 -or
   $bow.controller.cancel_pending -or $bow.controller.held -or $bow.controller.active -or $bow.controller.synthetic_use_key -or $bow.controller.projectiles_created_directly -or
   $bow.final_state.arrows -ne 0 -or $bow.final_state.held -cne 'minecraft:bow' -or $bow.final_state.held_damage -ne 2){throw 'Bow ownership, vanilla use or cleanup differs.'}
  if($bow.shots.Count -ne 2 -or $bow.shots[0].critical -or -not $bow.shots[1].critical -or
   $bow.shots[0].initial_speed -le .3 -or $bow.shots[0].initial_speed -ge 2.5 -or $bow.shots[1].initial_speed -lt 2.8 -or $bow.shots[1].initial_speed -gt 3.2 -or
   $bow.shots[0].id -ceq $bow.shots[1].id -or $bow.shots[0].owner -cne $bow.shots[1].owner){throw 'Vanilla bow shots differ.'}
  foreach($shot in $bow.shots){[void][guid]::Parse($shot.id);[void][guid]::Parse($shot.owner)}
  $capture=$f.images[1];$meta=$capture.metadata
  if($capture.world_file -cne 'combat-bow-world.png' -or (Get-FileHash -LiteralPath (Join-Path $result[0].EvidenceDirectory $capture.world_file)).Hash.ToLowerInvariant() -cne $capture.world_sha256 -or
   $capture.world_pixels -lt 1 -or $capture.world_with_depth_pixels -lt 1 -or $meta.projectile_render_count -lt 1 -or $meta.projectiles.Count -ne $meta.projectile_render_count -or
   $meta.rendered_world_blocks -ne 0 -or $meta.dropped_item_render_count -ne 0 -or $meta.player_pixels){throw 'Isolated real arrow pixels or depth missing.'}
  foreach($projectile in $meta.projectiles){if($projectile.owner -cne $bow.shots[0].owner -or $projectile.id -cnotin $bow.shots.id){throw 'Rendered arrow is not an observed vanilla bow shot.'}}
 }elseif($f.PSObject.Properties['bow']){throw 'Unexpected bow experiment in ordinary combat fixture.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_combat_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;synthetic_host=$true;bow_check=[bool]$BowCheck;scripted_guest_input=$true;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$hash;session=$session}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_COMBAT_PASS evidence=$directory"
