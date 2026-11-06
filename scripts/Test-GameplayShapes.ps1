# Real vanilla slab merging, stair neighbour updates, partial model pixels and saved-state continuation.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Shape check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-shapes-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
$terrain=New-HudGroundMovementPatch $run -WideWalking
# Fractional plateau away from the established A/B/C/D shape scene. The
# surrounding half-height ring keeps every neighboring sample delta <=0.3m.
foreach($point in $terrain.points){
 if($point.x -ge 118 -and $point.x -le 119 -and $point.y -ge 2037 -and $point.y -le 2038){$point.z=56.6}
 elseif($point.x -ge 117 -and $point.x -le 120 -and $point.y -ge 2036 -and $point.y -le 2039){$point.z=56.3}
}
$terrain|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$proofs=[Collections.Generic.List[object]]::new()
try{
 foreach($phase in @('shapes','shapes-resume')){
  if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash){throw 'Terrain bytes changed between launches.'}
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;WorldBlocks=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Shapes did not save and close normally.'}
  $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
  $f=$session.fixture;$m=$session.movement;$b=$session.blocks
  if($f.kind -cne 'minecome_gameplay_shapes_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or $f.position_writes_used -or $f.walking_verified -or
   $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or -not $session.world_blocks_enabled -or -not $f.render_pixels_verified -or -not $f.shape_support_verified){throw 'Shape fixture state/scope differs.'}
  if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
   -not $m.cleanup_complete -or -not $m.terrain_cells_valid -or -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or
   $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or $b.minecraft_blocks_removed_on_stop -ne 0 -or $b.persisted_revision -ne $b.revision){throw 'Shape/collision ownership or cleanup failed.'}
  if($phase -ceq 'shapes'){
   if(-not $session.new_world -or $b.owned_count -ne 3 -or $b.places -ne 6 -or $b.breaks -ne 2 -or
    ($f.actual_states -join '|') -cne 'minecraft:oak_slab[type=double,waterlogged=false]|minecraft:oak_slab[type=top,waterlogged=false]|minecraft:oak_stairs[facing=north,half=bottom,shape=straight,waterlogged=false]|minecraft:air|minecraft:air'){throw 'Merged/top slabs and restored stair did not persist.'}
   $names=@('empty','raised_slab','raised_mined','bottom_slab','double_slab','top_slab','straight_stair','corner_stair','restored_stair')
   if(@($f.shape_checks).Count -ne 8 -or @($f.submitted_commands).Count -ne 6 -or
    ($f.submitted_commands -join '|') -cne '/item replace entity @s hotbar.0 with minecraft:oak_slab|/item replace entity @s hotbar.0 with minecraft:oak_slab|/item replace entity @s hotbar.0 with minecraft:oak_slab|/item replace entity @s hotbar.0 with minecraft:oak_slab|/item replace entity @s hotbar.0 with minecraft:oak_stairs|/item replace entity @s hotbar.0 with minecraft:oak_stairs'){throw 'Real chat/shape check sequence differs.'}
   $raised=@($f.shape_checks | Where-Object stage -CEQ raised_slab)
   if($raised.Count -ne 1 -or [Math]::Abs($raised[0].host_ground_y-64.6) -gt .000001 -or $raised[0].placed_y -ne 65 -or $raised[0].visible_top_y -ne 65.5 -or -not $raised[0].heightfield_aim_checked){throw 'Fractional native-ground placement and targeting regression was not covered.'}
  }else{
   if($session.new_world -or $session.world_id -cne $proofs[0].session.world_id -or $f.player_id -cne $proofs[0].session.fixture.player_id -or
    -not $f.resume_verified -or -not $m.resume_position_restored -or $b.owned_count -ne 0 -or $b.places -ne 0 -or $b.breaks -ne 3 -or
    ($f.actual_states -join '|') -cne 'minecraft:air|minecraft:air|minecraft:air|minecraft:air|minecraft:air'){throw 'Saved shape restoration/mining failed.'}
   $names=@('resumed','mined_stair','mined_top','cleared')
  }
  if(@($f.images).Count -ne $names.Count -or (@($f.images.stage) -join '|') -cne ($names -join '|')){throw 'Shape image set incomplete.'}
  foreach($capture in $f.images){
   $file=Join-Path $result[0].EvidenceDirectory $capture.file
   if($capture.file -cne ('shapes-'+$capture.stage+'.png') -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or
    (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $capture.sha256 -or $capture.metadata.world_id -cne $session.world_id -or
    $capture.metadata.world_blocks_fixture_stage -cne $capture.stage){throw 'Shape PNG bytes/identity differ.'}
   $count=switch($capture.stage){'empty'{0};'cleared'{0};'raised_mined'{0};'raised_slab'{1};'bottom_slab'{1};'double_slab'{1};'mined_top'{1};'top_slab'{2};'mined_stair'{2};'corner_stair'{4};default{3}}
   if($capture.metadata.rendered_world_blocks -ne $count -or [bool]$capture.metadata.world_block_pixels -ne ($count -gt 0) -or
      $capture.metadata.screen -ne 0 -or -not $capture.metadata.hand_pass_rendered -or [bool]$capture.metadata.world_block_outline -ne ($count -gt 0)){throw 'Actual shape render/outline pass missing.'}
   if($count -gt 0 -and ($capture.occupied_samples -lt 50 -or $capture.occupied_mismatches -gt $capture.occupied_samples*.02)){throw 'Actual shape interior pixels absent.'}
   if($capture.stage -cin @('raised_slab','bottom_slab','top_slab','straight_stair','corner_stair','restored_stair') -and
      ($capture.empty_samples -lt 20 -or $capture.empty_mismatches -gt $capture.empty_samples*.02)){throw 'Shape vacancies rendered as full cubes.'}
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_shapes_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_ui=$true;direct_command_api_used=$false;native_input_verified=$false;kcd_connected=$false;walking_verified=$false;instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_SHAPES_PASS evidence=$directory"
