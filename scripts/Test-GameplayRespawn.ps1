# Actual vanilla death, dropped inventory, Respawn button and saved construction across two launches.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Respawn check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-respawn-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
$terrain=New-HudGroundMovementPatch $run -WideWalking
$terrain|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
try{
 foreach($phase in @('respawn','respawn-resume')){
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;WorldBlocks=$true;Explore=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $v=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  $file=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$s=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -Depth 30
  $f=$s.fixture;$m=$s.movement;$b=$s.blocks
  if($v.result -cne 'passed' -or -not $v.normal_client_exit -or -not $s.world_blocks_enabled -or
   $f.kind -cne 'minecome_gameplay_respawn_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.position_writes_used -or
   $f.world_id -cne $s.world_id -or $s.kcd_movement_connected -or $s.host_command_typing_verified){throw "Respawn verification scope differs: $phase"}
  if($m.failure -or -not $m.cleanup_complete -or -not $m.controls_released -or -not $m.terrain_cells_valid -or
   $m.patch_run -cne $run -or $m.patch_sha256 -cne $hash -or (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $hash -or
   $b.failure -or $b.pending -or $b.owned_count -ne 1 -or -not $b.cleanup_complete -or -not $b.controls_released){throw 'Respawn terrain/block cleanup differs.'}
  if($phase -ceq 'respawn'){
   foreach($flag in @('death_verified','death_drops_verified','respawn_button_verified','respawn_verified','construction_preserved_verified','walking_after_respawn_verified','render_pixels_verified')){if($f.$flag -ne $true){throw "Missing respawn capability: $flag"}}
   if(-not $s.new_world -or $b.places -ne 1 -or $s.respawn.client_rebound_epoch -ne 1 -or $s.respawn.respawn_ack_epoch -ne 1 -or $s.fixture.pointer.mouse_click_calls -lt 1){throw 'Production placement/respawn/UI path was not exercised.'}
   $names=@('dead','respawned')
  }else{
   if($s.new_world -or -not $f.resume_verified -or $s.world_id -cne $proofs[0].session.world_id -or -not $m.resume_position_restored){throw 'Respawn reload changed its saved world/player.'}
   if($f.drop_id -cne $proofs[0].session.fixture.drop_id){throw 'Death drop identity did not survive reload.'}
   $names=@('resumed')
  }
  if(($f.images.stage -join '|') -cne ($names -join '|')){throw 'Respawn UI capture stages incomplete.'}
  foreach($capture in $f.images){
   $image=Join-Path $result[0].EvidenceDirectory $capture.file
   if($capture.file -cne ('respawn-'+$capture.stage+'.png') -or (Get-FileHash -LiteralPath $image).Hash.ToLowerInvariant() -cne $capture.sha256 -or
    $capture.metadata.world_id -cne $s.world_id -or $capture.metadata.respawn_fixture_stage -cne $capture.stage -or $capture.metadata.frame_format -ne 2){throw 'Respawn UI capture bytes/identity differ.'}
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();session=$s})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_respawn_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_guest_input=$true;native_input_verified=$false;kcd_connected=$false;instance=$instance;patch_sha256=$hash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_RESPAWN_PASS evidence=$directory"
