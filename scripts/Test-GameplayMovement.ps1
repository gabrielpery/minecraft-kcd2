# Two actual Minecraft launches; scripted standalone controls, no KCD or native-input claim.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay movement failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-movement-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance'
$patchFile=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patchFile -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant()
$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
function Get-GameplayPositionDistance($A,$B){
 return [Math]::Sqrt([Math]::Pow([double]$A.x-[double]$B.x,2)+[Math]::Pow([double]$A.y-[double]$B.y,2)+[Math]::Pow([double]$A.z-[double]$B.z,2))
}
try{
 foreach($phase in @('walking','walking-resume')){
  if((Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant() -cne $patchHash){throw 'Terrain bytes changed between launches.'}
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Movement=$true;GroundPatchFile=$patchFile}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {
   if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}
  })
  if($result.Count -ne 1){throw "Missing $phase session result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement){throw "Unverified movement save/shutdown for $phase."}
  $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json'
  $session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
  $fixture=$session.fixture;$movement=$session.movement
  if($fixture.kind -cne 'minecome_gameplay_movement_fixture_v1' -or $fixture.mode -cne $phase -or $fixture.result -cne 'passed' -or
   -not $fixture.standalone_scripted -or $fixture.native_input_verified -or $fixture.live_kcd_verified -or
   $session.kcd_movement_connected -or $session.host_command_typing_verified -or $session.save -cne 'MineCome-Gameplay'){
   throw 'Movement fixture identity or verified scope differs.'
  }
  if($movement.patch_run -cne $run -or $movement.patch_sha256 -cne $patchHash -or $movement.world_id -cne $session.world_id -or
   $movement.failure -or $movement.client_walk -lt .15 -or $movement.server_walk -lt .15 -or
   $movement.client_queries -le 0 -or $movement.server_queries -le 0 -or $movement.pose_writes -le 0 -or
   -not $movement.resume_checkpoint_present -or -not $movement.cleanup_complete -or -not $movement.ground_cells_air -or $movement.blocks_written -ne 0){
   throw 'Actual client/server walking, ephemeral collision, pose publication or saved checkpoint proof failed.'
  }
  if((Get-GameplayPositionDistance $movement.resume_checkpoint $movement.server_position) -gt .04){throw 'Saved checkpoint does not match the final stable server position.'}
  if($phase -ceq 'walking'){
   if(-not $session.new_world -or $fixture.elapsed_ms -lt 35000 -or -not $fixture.early_step_verified -or
    -not $fixture.late_step_verified -or -not $fixture.inventory_suppression_verified -or
    -not $fixture.walking_after_inventory_verified -or $fixture.idle_hotbar_ticks -lt 20 -or -not $movement.first_attachment -or
    (Get-GameplayPositionDistance $fixture.before_late $fixture.after_late) -lt .15){throw 'Sustained early/late walking and inventory isolation proof failed.'}
  }else{
   if($session.new_world -or $session.world_id -cne $proofs[0].session.world_id -or $session.run -ceq $proofs[0].session.run -or
    -not $fixture.resume_verified -or -not $fixture.late_step_verified -or $movement.first_attachment -or -not $movement.resume_position_restored -or
    (Get-GameplayPositionDistance $fixture.initial_position $proofs[0].session.movement.resume_checkpoint) -gt .04){throw 'Second launch did not resume the same world and saved location.'}
  }
  $poseFile=Join-Path $result[0].EvidenceDirectory 'gameplay-pose.json'
  if((Get-Item -LiteralPath $poseFile).Length -gt 4096){throw 'Latest-pose transport exceeded its constant-space bound.'}
  $pose=Get-Content -LiteralPath $poseFile -Raw|ConvertFrom-Json
  if($pose.schema -ne 1 -or $pose.kind -cne 'minecome_gameplay_pose_v1' -or $pose.run -cne $session.run -or
   $pose.world_id -cne $session.world_id -or $pose.patch_run -cne $run -or $pose.patch_sha256 -cne $patchHash -or $pose.seq -le 0){throw 'Latest-pose identity proof failed.'}
  $mapped=[pscustomobject]@{x=120+[double]$movement.server_position.x;y=2040-[double]$movement.server_position.z;z=56+[double]$movement.server_position.y-64}
  if((Get-GameplayPositionDistance $pose.position $mapped) -gt .04){throw 'Host pose does not match the authoritative Minecraft position transform.'}
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant();session=$session;pose=$pose})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_movement_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;
  instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_MOVEMENT_PASS evidence=$directory"
