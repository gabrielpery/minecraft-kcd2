# Two actual Minecraft launches with gameplay actions and saved user blocks; no KCD launch.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay blocks failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-blocks-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patchFile=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patchFile -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant()
$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
function Get-BlocksFixtureDistance($A,$B){return [Math]::Sqrt([Math]::Pow([double]$A.x-[double]$B.x,2)+[Math]::Pow([double]$A.y-[double]$B.y,2)+[Math]::Pow([double]$A.z-[double]$B.z,2))}
try{
 foreach($phase in @('blocks','blocks-resume')){
  if((Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant() -cne $patchHash){throw 'Terrain bytes changed between fixture launches.'}
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Blocks=$true;GroundPatchFile=$patchFile}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {
   if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
  })
  if($result.Count -ne 1){throw "Missing $phase session result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement){throw "Unverified blocks save/shutdown for $phase."}
  $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json'
  $session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
  $fixture=$session.fixture;$movement=$session.movement;$blocks=$session.blocks
  if($fixture.kind -cne 'minecome_gameplay_blocks_fixture_v1' -or $fixture.mode -cne $phase -or $fixture.result -cne 'passed' -or
   -not $fixture.standalone_scripted -or -not $fixture.actual_minecraft -or $fixture.native_input_verified -or $fixture.live_kcd_verified -or
   $fixture.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified -or $session.save -cne 'MineCome-Gameplay'){
   throw 'Blocks fixture identity or claimed verification scope differs.'
  }
  if($movement.patch_run -cne $run -or $movement.patch_sha256 -cne $patchHash -or $movement.world_id -cne $session.world_id -or
   $movement.failure -or $movement.client_queries -le 0 -or $movement.server_queries -le 0 -or $movement.pose_writes -le 0 -or
   -not $movement.resume_checkpoint_present -or -not $movement.cleanup_complete -or -not $movement.terrain_cells_valid -or
   -not $movement.controls_released -or -not $movement.client_collision_released -or -not $movement.server_collision_released){
   throw 'Actual terrain collision, walking checkpoint or orderly release failed.'
  }
  if((Get-BlocksFixtureDistance $movement.resume_checkpoint $movement.server_position) -gt .04){throw 'Saved walking checkpoint differs from final server position.'}
  if($blocks.kind -cne 'minecome_gameplay_blocks_controller_v1' -or $blocks.run -cne $session.run -or $blocks.world_id -cne $session.world_id -or
   $blocks.failure -or $blocks.pending -or -not $blocks.cleanup_complete -or -not $blocks.controls_released -or $blocks.minecraft_blocks_removed_on_stop -ne 0 -or
   $blocks.snapshot_writes -le 0 -or $blocks.persisted_revision -ne $blocks.revision){throw 'Server-confirmed block ownership, persistence or orderly release failed.'}
  if($phase -ceq 'blocks'){
   foreach($flag in @('ground_placement_verified','top_placement_verified','side_placement_verified','upper_break_verified','side_break_verified',
    'early_walking_verified','inventory_suppression_verified','later_walking_verified')){if($fixture.$flag -ne $true){throw "Missing actual gameplay capability: $flag"}}
   if(-not $session.new_world -or -not $movement.first_attachment -or $fixture.inventory_ticks -lt 5 -or
    $movement.client_walk -lt .15 -or $movement.server_walk -lt .15 -or $blocks.places -ne 3 -or $blocks.breaks -ne 2 -or
    $blocks.ground_places -ne 1 -or $blocks.owned_count -ne 1 -or $fixture.stone_count -ne 64){throw 'First blocks session lacks its exact ground/face/break/walking proof.'}
   if((Get-BlocksFixtureDistance $fixture.base $blocks.blocks[0]) -ne 0){throw 'Persisted base coordinates differ from actual tested block.'}
  }else{
   if($session.new_world -or $session.world_id -cne $proofs[0].session.world_id -or $session.run -ceq $proofs[0].session.run -or
    -not $fixture.resume_verified -or $movement.first_attachment -or -not $movement.resume_position_restored -or
    $blocks.places -ne 0 -or $blocks.breaks -ne 1 -or $blocks.owned_count -ne 0 -or @($blocks.blocks).Count -ne 0 -or
    $fixture.stone_count -ne $proofs[0].session.fixture.stone_count -or
    (Get-BlocksFixtureDistance $fixture.base $proofs[0].session.fixture.base) -ne 0){throw 'Second launch did not resume and normally break the saved base block.'}
  }
  $snapshotFile=Join-Path $result[0].EvidenceDirectory 'gameplay-blocks.json'
  if((Get-Item -LiteralPath $snapshotFile).Length -gt 32768){throw 'Latest blocks snapshot exceeded its bounded size.'}
  $snapshot=Get-Content -LiteralPath $snapshotFile -Raw|ConvertFrom-Json -Depth 12
  if($snapshot.schema -ne 1 -or $snapshot.kind -cne 'minecome_gameplay_blocks_v1' -or $snapshot.run -cne $session.run -or
   $snapshot.world_id -cne $session.world_id -or $snapshot.patch_run -cne $run -or $snapshot.patch_sha256 -cne $patchHash -or
   $snapshot.seq -le 0 -or $snapshot.revision -ne $blocks.revision -or @($snapshot.blocks).Count -ne $blocks.owned_count){throw 'Host blocks snapshot does not match authoritative Minecraft ownership.'}
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant();session=$session;snapshot=$snapshot})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_blocks_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;
  instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_BLOCKS_PASS evidence=$directory"
