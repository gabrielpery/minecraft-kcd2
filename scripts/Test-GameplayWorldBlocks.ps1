# Real placement/model pixels and saved-state continuation in two isolated Minecraft launches.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "World blocks check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-world-blocks-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$passed=$false;$failure=$null;$proofs=[Collections.Generic.List[object]]::new()
try{
 foreach($phase in @('world-blocks','world-blocks-resume')){
  if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash){throw 'Terrain bytes changed between launches.'}
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;WorldBlocks=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'World blocks did not save and close normally.'}
  $session=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-session.json') -Raw|ConvertFrom-Json -Depth 24
  $f=$session.fixture;$m=$session.movement;$b=$session.blocks
  if($f.kind -cne 'minecome_gameplay_world_blocks_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or $f.position_writes_used -or
   $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or -not $session.world_blocks_enabled -or -not $f.render_pixels_verified){throw 'World block fixture state/scope differs.'}
  if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
   -not $m.cleanup_complete -or -not $m.terrain_cells_valid -or -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or
   $b.failure -or $b.pending -or -not $b.cleanup_complete -or -not $b.controls_released -or $b.minecraft_blocks_removed_on_stop -ne 0 -or $b.persisted_revision -ne $b.revision){throw 'World block/collision ownership or cleanup failed.'}
  if($phase -ceq 'world-blocks'){
   if(-not $session.new_world -or $b.owned_count -ne 4 -or $b.places -ne 4 -or $b.breaks -ne 0 -or
    ($f.actual_states -join '|') -cne 'minecraft:dirt|minecraft:oak_planks|minecraft:bricks|minecraft:oak_log[axis=x]'){throw 'Four distinct actual blocks and log axis did not persist.'}
   $expectedCommands=@('dirt','oak_planks','bricks','oak_log')|ForEach-Object {"/item replace entity @s hotbar.0 with minecraft:$_"}
   if(($f.submitted_commands -join '|') -cne ($expectedCommands -join '|')){throw 'Items did not come through real Minecraft chat.'}
   $names=@('empty','dirt','oak_planks','bricks','oak_log','outline_stale','outline_hover','outline_blocked','outline_miss','outline_restored','inventory','restored')
  }else{
   if($session.new_world -or $session.world_id -cne $proofs[0].session.world_id -or $f.player_id -cne $proofs[0].session.fixture.player_id -or
    -not $f.resume_verified -or -not $m.resume_position_restored -or $b.owned_count -ne 0 -or $b.places -ne 0 -or $b.breaks -ne 4 -or
    ($f.actual_states -join '|') -cne 'minecraft:air|minecraft:air|minecraft:air|minecraft:air'){throw 'Saved state restoration/mining failed.'}
   $names=@('resumed','cleared')
  }
  if(@($f.images).Count -ne $names.Count -or (@($f.images.stage) -join '|') -cne ($names -join '|')){throw 'World model image set incomplete.'}
  foreach($capture in $f.images){
   $file=Join-Path $result[0].EvidenceDirectory $capture.file
   if($capture.file -cne ('world-blocks-'+$capture.stage+'.png') -or -not (Test-Path -LiteralPath $file -PathType Leaf) -or
    (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -cne $capture.sha256 -or $capture.metadata.world_id -cne $session.world_id -or
    $capture.metadata.world_blocks_fixture_stage -cne $capture.stage){throw 'World model PNG bytes/identity differ.'}
   $inventory=$capture.stage -ceq 'inventory'
   if([bool]$capture.metadata.hand_pass_rendered -eq $inventory -or $capture.metadata.screen -ne $(if($inventory){1}else{0}) -or
    $capture.metadata.screen_kind -cne $(if($inventory){'CreativeInventoryScreen'}else{'none'})){throw 'Inventory did not hide hands/restore the world view.'}
   if(-not $inventory -and ($capture.clear_region_pixels -ne 0 -or $capture.transparent_pixels -lt $capture.pixels*.25)){throw 'Opaque world leaked outside owned models.'}
   $count=switch($capture.stage){'empty'{0};'dirt'{1};'oak_planks'{2};'bricks'{3};'cleared'{0};default{4}}
   if($capture.metadata.rendered_world_blocks -ne $count -or [bool]$capture.metadata.world_block_pixels -ne ($count -gt 0) -or ($count -gt 0 -and $capture.world_region_pixels -lt 200)){throw 'Actual model render pass missing.'}
   $outlined=$capture.stage -cin @('outline_hover','outline_restored','restored')
   if([bool]$capture.metadata.world_block_outline -ne $outlined -or [bool]$capture.metadata.PSObject.Properties['outline_position'] -ne $outlined){throw 'Outline was missing or survived a denied target/UI state.'}
   if($outlined){
    $position=$capture.metadata.outline_position
    $log=@($f.blocks.blocks|Where-Object state -CEQ 'minecraft:oak_log[axis=x]')
    if($log.Count -ne 1 -or $position.x -ne $log[0].x -or $position.y -ne $log[0].y -or $position.z -ne $log[0].z){throw 'Outline target differs from the confirmed owned oak log.'}
   }
   if($capture.stage.StartsWith('outline_') -or $capture.stage -ceq 'restored'){
    $baseline=@($f.images|Where-Object stage -CEQ 'outline_stale')[0]
    if($capture.outline_comparison_baseline -cne 'outline_stale' -or
     ($capture.outline_view|ConvertTo-Json -Depth 8 -Compress) -cne ($baseline.outline_view|ConvertTo-Json -Depth 8 -Compress) -or
     $capture.outline_edge_pixels -ne $baseline.outline_edge_pixels -or $capture.outline_edge_pixels -lt 100){throw 'Outline comparison did not use the same camera/projected cube edge mask.'}
    if($outlined){
     if($capture.outline_changed_pixels -lt 20 -or $capture.outline_darkened_pixels -lt 10 -or
      $capture.outline_changed_pixels -gt $capture.outline_edge_pixels*.6 -or $capture.outline_changed_pixels -gt $capture.pixels*.025){throw 'Actual outline pixels were absent or not localized to cube edges.'}
    }elseif($capture.outline_changed_pixels -gt 20){throw 'Stale/blocked/missed targeting changed the settled cube-edge pixels.'}
   }
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_world_blocks_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_ui=$true;direct_command_api_used=$false;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_WORLD_BLOCKS_PASS evidence=$directory"
