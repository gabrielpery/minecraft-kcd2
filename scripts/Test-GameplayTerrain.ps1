# Two actual Minecraft launches: synthetic tile arrives during play, then coverage/blocks/player resume.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay terrain fixture failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$tileRun=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-terrain-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json';$east=Join-Path $directory 'east-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$tile=New-HudGroundMovementPatch $tileRun -WideWalking
$tile.center.x+=8;foreach($point in $tile.points){$point.x+=8}
$tile|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $east -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$tileHash=(Get-FileHash -LiteralPath $east).Hash.ToLowerInvariant()
$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
function Get-TerrainFixtureDistance($A,$B){return [Math]::Sqrt([Math]::Pow([double]$A.x-[double]$B.x,2)+[Math]::Pow([double]$A.y-[double]$B.y,2)+[Math]::Pow([double]$A.z-[double]$B.z,2))}
try{
 foreach($phase in @('terrain','terrain-resume')){
  if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash -or (Get-FileHash -LiteralPath $east).Hash.ToLowerInvariant() -cne $tileHash){throw 'Terrain fixture input bytes changed between launches.'}
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Explore=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {
   if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
  })
  if($result.Count -ne 1){throw "Missing $phase session result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw "Unverified terrain save/shutdown for $phase."}
  $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json'
  $session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
  $fixture=$session.fixture;$movement=$session.movement;$blocks=$session.blocks
  if($fixture.kind -cne 'minecome_gameplay_terrain_fixture_v1' -or $fixture.mode -cne $phase -or $fixture.result -cne 'passed' -or
   $fixture.tile_source_kind -cne 'standalone_fixture' -or $fixture.tile_sha256 -cne $tileHash -or -not $fixture.actual_minecraft -or
   -not $fixture.standalone_scripted -or $fixture.native_input_verified -or $fixture.live_kcd_verified -or
   $fixture.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified){throw 'Terrain fixture identity or proof scope differs.'}
  if($movement.patch_run -cne $run -or $movement.patch_sha256 -cne $patchHash -or $movement.world_id -cne $session.world_id -or
   $movement.failure -or $movement.terrain_failure -or $movement.terrain_generation -ne 1 -or $movement.terrain_tiles -ne 2 -or
   $movement.terrain_client_generation -ne 1 -or $movement.terrain_server_generation -ne 1 -or $movement.terrain_transition -or
   -not $movement.cleanup_complete -or -not $movement.terrain_cells_valid -or -not $movement.controls_released -or
   -not $movement.client_collision_released -or -not $movement.server_collision_released -or -not $movement.resume_checkpoint_present -or
   $movement.resume_checkpoint.x -le 4 -or (Get-TerrainFixtureDistance $movement.resume_checkpoint $movement.server_position) -gt .04){throw 'Expanded collision, durable coverage or player checkpoint verification failed.'}
  if($blocks.failure -or $blocks.pending -or -not $blocks.cleanup_complete -or -not $blocks.controls_released -or
   $blocks.persisted_revision -ne $blocks.revision -or $blocks.minecraft_blocks_removed_on_stop -ne 0 -or
   $fixture.base.x -lt 4 -or -not $fixture.later_walking_verified -or -not $fixture.break_verified){throw 'Expanded-terrain block actions, walking or persistence failed.'}
  if($phase -ceq 'terrain'){
   foreach($flag in @('admission_written','admission_verified','crossing_verified','ground_placement_verified','top_placement_verified','inventory_suppression_verified')){if($fixture.$flag -ne $true){throw "Missing terrain capability: $flag"}}
   if(-not $session.new_world -or -not $movement.first_attachment -or $movement.terrain_admissions -ne 1 -or
    $movement.client_walk -le 4.5 -or $movement.server_walk -le 4.5 -or $fixture.inventory_ticks -lt 5 -or
    $blocks.places -ne 2 -or $blocks.breaks -ne 1 -or $blocks.ground_places -ne 1 -or $blocks.owned_count -ne 1 -or
    (Get-TerrainFixtureDistance $fixture.base $blocks.blocks[0]) -ne 0){throw 'First session did not cross, build and retain a block on newly admitted terrain.'}
   $ack=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'terrain-ack.json') -Raw|ConvertFrom-Json
   if($ack.status -cne 'admitted' -or $ack.run -cne $session.run -or $ack.world_id -cne $session.world_id -or $ack.generation -ne 1 -or
    $ack.tx -ne 1 -or $ack.tz -ne 0 -or $ack.tile_sha256 -cne $tileHash -or $ack.coverage_digest -cne $movement.terrain_digest){throw 'Actual admission acknowledgement differs from active durable coverage.'}
  }else{
   if($session.new_world -or -not $fixture.resume_verified -or $fixture.admission_written -or $movement.terrain_admissions -ne 0 -or
    $movement.first_attachment -or -not $movement.resume_position_restored -or $session.world_id -cne $proofs[0].session.world_id -or
    $movement.terrain_digest -cne $proofs[0].session.movement.terrain_digest -or $fixture.initial_position.x -le 4 -or
    (Get-TerrainFixtureDistance $fixture.initial_position $proofs[0].session.movement.resume_checkpoint) -gt .04 -or
    $movement.client_walk -lt .15 -or $movement.server_walk -lt .15 -or $blocks.places -ne 0 -or $blocks.breaks -ne 1 -or $blocks.owned_count -ne 0){throw 'Reopen did not retain expanded terrain, saved player position and real base block.'}
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant();session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_terrain_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;synthetic_tile_arrival=$true;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;
  instance=$instance;patch_sha256=$patchHash;tile_sha256=$tileHash;launches=$proofs.ToArray()}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_TERRAIN_PASS evidence=$directory"
