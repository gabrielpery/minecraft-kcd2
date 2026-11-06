# Real client/server walking over controller-placed slabs/stairs and against fences.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Shape walking check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-shape-walking-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'shape-walking');FixturePhase='shape-walking';WorldBlocks=$true;Explore=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing shape-walking result.'}
 $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Walking shapes did not save and close normally.'}
 $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 $f=$session.fixture;$m=$session.movement;$b=$session.blocks
 if($f.kind -cne 'minecome_gameplay_shape_walking_fixture_v1' -or $f.mode -cne 'shape-walking' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or
  $f.position_writes_used -or $f.velocity_writes_used -or $f.block_state_writes_used -or $session.kcd_movement_connected -or
  $f.world_id -cne $session.world_id -or -not $session.new_world -or -not $session.world_blocks_enabled){throw 'Shape walking scope/identity differs.'}
 foreach($field in @('slab_walking_verified','stair_walking_verified','inventory_suppression_verified','descent_verified','fence_blocking_verified','fence_jump_blocked_verified')){
  if($f.$field -isnot [bool] -or -not $f.$field){throw "Missing actual movement proof: $field"}
 }
 if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
  $m.client_walk -lt 1.9 -or $m.server_walk -lt 1.9 -or $m.client_queries -le 0 -or $m.server_queries -le 0 -or $m.pose_writes -le 0 -or
  -not $m.cleanup_complete -or -not $m.terrain_cells_valid -or -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or
  $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or $b.minecraft_blocks_removed_on_stop -ne 0 -or $b.persisted_revision -ne $b.revision -or
  $b.owned_count -ne 6 -or $b.places -ne 6 -or $b.breaks -ne 0 -or $session.world_block_render_frames -le 0 -or $session.terrain_depth_render_frames -le 0){throw 'Walking, render publication, ledger ownership or cleanup failed.'}
 $names=@('standing_on_bottom_slab','standing_on_stair','inventory_suppressed_on_stair','descended_to_ground','stopped_by_fence','fence_jump_blocked_and_landed')
 if(($f.positions.stage -join '|') -cne ($names -join '|')){throw 'Missing walking positions.'}
 foreach($point in $f.positions){
  $wanted=if($point.stage -ceq 'standing_on_bottom_slab'){64.5}elseif($point.stage -cin @('standing_on_stair','inventory_suppressed_on_stair')){65}else{64}
  if(-not $point.client_grounded -or -not $point.server_grounded -or [Math]::Abs($point.client_position.y-$wanted) -gt .015 -or [Math]::Abs($point.server_position.y-$wanted) -gt .015 -or
   [Math]::Abs($point.client_support_y-$wanted) -gt .015 -or [Math]::Abs($point.server_support_y-$wanted) -gt .015){throw "Actual feet and support disagree at $($point.stage)."}
 }
 if($f.jump_peak_y -lt 64.7 -or $f.jump_peak_y -gt 65.5 -or @($f.submitted_commands).Count -ne 6 -or ($f.submitted_commands -join '|') -cne
  '/item replace entity @s hotbar.0 with minecraft:oak_fence|/item replace entity @s hotbar.0 with minecraft:oak_fence|/item replace entity @s hotbar.0 with minecraft:oak_stairs|/item replace entity @s hotbar.0 with minecraft:oak_stairs|/item replace entity @s hotbar.0 with minecraft:oak_slab|/item replace entity @s hotbar.0 with minecraft:oak_slab'){throw 'Fixture item sequence or normal fence jump differs.'}
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_shape_walking_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
 actual_minecraft=$true;scripted_ui=$true;direct_command_api_used=$false;position_writes_used=$false;native_input_verified=$false;kcd_connected=$false;
 walking_verified=$passed;instance=$instance;patch_sha256=$patchHash;session=$session}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_SHAPE_WALKING_PASS evidence=$directory"
