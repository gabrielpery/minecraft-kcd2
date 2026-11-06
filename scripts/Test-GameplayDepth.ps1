# Actual Minecraft pixels: opaque terrain depth, partial occlusion, untouched hands/UI and cleanup.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Depth check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-depth-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$session=$null
try{
 $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory 'depth');FixturePhase='depth';WorldBlocks=$true;GroundPatchFile=$patch}
 if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
 $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
 if($result.Count -ne 1){throw 'Missing depth fixture result.'}
 $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
 if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Depth fixture did not save and close normally.'}
 $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
 $f=$session.fixture;$m=$session.movement;$b=$session.blocks
 if($f.kind -cne 'minecome_gameplay_depth_fixture_v1' -or $f.mode -cne 'depth' -or $f.result -cne 'passed' -or $f.failure -or
  -not $f.actual_minecraft -or -not $f.standalone_scripted -or -not $f.synthetic_render_surface -or $f.native_input_verified -or $f.live_kcd_verified -or
  $f.direct_command_api_used -or $f.position_writes_used -or $f.walking_verified -or -not $f.render_pixels_verified -or
  $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or -not $session.world_blocks_enabled){throw 'Depth fixture scope/state differs.'}
 if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
  -not $m.cleanup_complete -or -not $m.terrain_cells_valid -or -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or
  $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or $b.minecraft_blocks_removed_on_stop -ne 0 -or $b.persisted_revision -ne $b.revision -or
  $b.places -ne 1 -or $b.breaks -ne 1 -or $b.owned_count -ne 0 -or -not $session.new_world){throw 'Depth fixture block/collision ownership or cleanup failed.'}
 if(@($f.submitted_commands).Count -ne 1 -or $f.submitted_commands[0] -cne '/item replace entity @s hotbar.0 with minecraft:stone'){throw 'Depth fixture must use the real chat and one vanilla placement.'}
 $names=@('empty_terrain','visible','hidden','far','partial','restored','cleared')
 if(@($f.images).Count -ne 7 -or (@($f.images.stage) -join '|') -cne ($names -join '|')){throw 'Depth image set incomplete.'}
 foreach($capture in $f.images){
  $file=Join-Path $result[0].EvidenceDirectory $capture.file
  $empty=$capture.stage -cin @('empty_terrain','cleared');$depth=$capture.stage -cin @('empty_terrain','hidden','far','partial')
  if($capture.file -cne ('depth-'+$capture.stage+'.png') -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or
   (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $capture.sha256 -or $capture.metadata.world_id -cne $session.world_id -or
   $capture.metadata.world_blocks_fixture_stage -cne $capture.stage){throw 'Depth PNG bytes/identity differ.'}
  if($capture.metadata.rendered_world_blocks -ne $(if($empty){0}else{1}) -or $capture.metadata.screen -ne 0 -or -not $capture.metadata.hand_pass_rendered -or
   [bool]$capture.metadata.world_block_outline -eq $empty -or [bool]$capture.metadata.terrain_depth_occlusion -ne $depth -or
   $capture.metadata.terrain_depth_boxes -ne $(if($depth){1}else{0}) -or $capture.stray_opaque_samples -ne 0 -or $capture.hand_opaque_samples -lt 100 -or $capture.hud_opaque_samples -lt 100){throw 'Depth pass or unaffected foreground proof missing.'}
  if($empty -or $capture.stage -ceq 'hidden'){if($capture.block_region_opaque_samples -ne 0){throw 'Terrain/hidden block has visible colour.'}}
  elseif($capture.stage -ceq 'visible'){if($capture.block_region_opaque_samples -lt 1000){throw 'Visible actual block baseline missing.'}}
  elseif($capture.stage -ceq 'partial'){
   if($capture.baseline_samples -lt 1000 -or $capture.retained_samples -lt $capture.baseline_samples*.15 -or $capture.hidden_samples -lt $capture.baseline_samples*.15 -or
    $capture.retained_samples+$capture.hidden_samples -lt $capture.baseline_samples*.98){throw 'Partial terrain did not retain and hide the actual model/outline.'}
  }elseif($capture.baseline_samples -lt 1000 -or $capture.retained_samples -lt $capture.baseline_samples*.98){throw 'Far terrain or restored view changed the visible block.'}
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_depth_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_ui=$true;synthetic_render_surface=$true;native_input_verified=$false;kcd_connected=$false;walking_verified=$false;instance=$instance;patch_sha256=$patchHash;session=$session}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_DEPTH_PASS evidence=$directory"
