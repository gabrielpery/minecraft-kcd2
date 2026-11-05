# Actual Minecraft flight from ordinary jump/modifier edges and real ChatScreen commands.
# The paired run proves vanilla simulation/persistence; it does not claim native KCD input.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath,[ValidateSet('flight','flight-fall')][string]$FixturePhase='flight')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Gameplay flight check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$falling=$FixturePhase -ceq 'flight-fall'
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-'+$FixturePhase+'-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
function Get-FlightFixtureDistance($A,$B){return [Math]::Sqrt([Math]::Pow([double]$A.x-[double]$B.x,2)+[Math]::Pow([double]$A.y-[double]$B.y,2)+[Math]::Pow([double]$A.z-[double]$B.z,2))}
try{
 foreach($phase in @($FixturePhase,($FixturePhase+'-resume'))){
  if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash){throw 'Flight fixture terrain changed between launches.'}
  $launchArguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Flight=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$launchArguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @launchArguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Flight guest did not save and close normally.'}
  $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
  $f=$session.fixture;$m=$session.movement
  if($f.kind -cne 'minecome_gameplay_flight_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or $f.ability_writes_used -or $f.position_writes_used -or
   $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified -or $f.game_mode -cne $(if($falling){'survival'}else{'creative'}) -or -not $session.flight_enabled){throw 'Flight fixture identity/state or evidence scope differs.'}
  if(-not $falling){foreach($flag in @('ascent_verified','descent_verified','landing_verified')){if($f.$flag -ne $true){throw "Missing actual flight capability: $flag"}}}
  if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
   -not $m.flight_enabled -or
   -not $m.cleanup_complete -or -not $m.ground_cells_air -or -not $m.terrain_cells_valid -or
   -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or -not $m.resume_checkpoint_present -or
   (Get-FlightFixtureDistance $m.resume_checkpoint $m.server_position) -gt .04){throw 'Actual flight observation, checkpoint or cleanup failed.'}
  if($phase -cne 'flight-fall-resume' -and ($m.client_flight_ticks -le 0 -or $m.server_flight_ticks -le 0 -or $f.flight_ticks -lt 10)){throw 'No actual client/server flight was observed.'}
  if($session.blocks.failure -or $session.blocks.owned_count -ne 0 -or -not $session.blocks.cleanup_complete){throw 'Flight changed the stone ledger or failed cleanup.'}
  if($phase -ceq 'flight-fall'){
   foreach($flag in @('takeoff_verified','ascent_verified','mode_change_verified','falling_save_verified')){if($f.$flag -ne $true){throw "Missing falling-save capability: $flag"}}
   if(-not $session.new_world -or -not $m.first_attachment -or $m.resume_checkpoint.flying -or -not $m.resume_checkpoint.falling -or
    $m.resume_checkpoint.fall_distance -le 3 -or $f.server_flying -or $f.max_altitude -lt 6 -or $f.health -ne 20 -or
    $m.resume_checkpoint.y -lt 67 -or ($f.submitted_commands -join '|') -cne '/gamemode survival'){throw 'First falling phase did not save a real Survival descent.'}
  }elseif($phase -ceq 'flight-fall-resume'){
   foreach($flag in @('resume_verified','landing_verified','fall_distance_preserved')){if($f.$flag -ne $true){throw "Missing fall-resume capability: $flag"}}
   $restored=$f.movement.resume_checkpoint;$saved=$proofs[0].session.movement.resume_checkpoint
   if($session.new_world -or $session.world_id -cne $proofs[0].session.world_id -or $f.player_id -cne $proofs[0].session.fixture.player_id -or
    $m.first_attachment -or -not $m.resume_position_restored -or -not $restored.falling -or $restored.flying -or
    (Get-FlightFixtureDistance $restored $saved) -gt .00001 -or [double]$restored.fall_distance -ne [double]$saved.fall_distance -or
    $f.health -le 0 -or $f.server_flying -or $m.resume_checkpoint.flying -or $m.resume_checkpoint.falling -or
    @($f.submitted_commands).Count -ne 0){throw 'Saved Survival descent did not reopen, preserve fall state and land with damage.'}
   if(-not $m.resume_fall_restored -or -not $m.resume_fall_landed -or [double]$m.resume_fall_distance_max -lt [double]$saved.fall_distance+.5){throw 'Server fall distance did not continue after restoration.'}
   if($m.resume_fall_landing_age -lt 60){
    if(-not $f.login_grace_verified -or $f.fall_damage_verified -or $f.health -ne $proofs[0].session.fixture.health){throw 'Vanilla login grace changed during falling resume.'}
   }else{
    # Inspected LivingEntity.computeFallDamage uses these actual attributes.
    $expectedDamage=[Math]::Ceiling(([double]$saved.fall_distance+[double]$saved.y-[double]$f.server_position.y-[double]$f.safe_fall_distance)*[double]$f.fall_damage_multiplier)
    $actualDamage=[double]$proofs[0].session.fixture.health-[double]$f.health
    if(-not $f.fall_damage_verified -or $expectedDamage -lt 4 -or [Math]::Abs($actualDamage-$expectedDamage) -gt 1){throw 'Landing damage does not include the fall distance accumulated before saving.'}
   }
  }elseif($phase -ceq 'flight'){
   foreach($flag in @('takeoff_verified','horizontal_verified','sprint_verified','inventory_suppression_verified','chat_suppression_verified','mode_change_verified','second_takeoff_verified')){if($f.$flag -ne $true){throw "Missing flight/input capability: $flag"}}
   if(-not $session.new_world -or -not $m.first_attachment -or -not $m.resume_checkpoint.flying -or -not $f.server_flying -or
    $f.max_altitude -lt .8 -or $f.inventory_ticks -lt 10 -or $f.chat_ticks -lt 10 -or
    ($f.submitted_commands -join '|') -cne '/gamemode survival|/gamemode creative|/gamemode survival|/gamemode creative'){throw 'First flight did not exercise commands, flight and an airborne save.'}
  }else{
   if($session.new_world -or -not $f.resume_verified -or $session.world_id -cne $proofs[0].session.world_id -or $f.player_id -cne $proofs[0].session.fixture.player_id -or
    $m.first_attachment -or -not $m.resume_position_restored -or (Get-FlightFixtureDistance $f.initial_position $proofs[0].session.movement.resume_checkpoint) -gt .04 -or
    $f.server_flying -or $m.resume_checkpoint.flying -or @($f.submitted_commands).Count -ne 0){throw 'Saved aerial checkpoint/abilities did not reopen and land normally.'}
  }
  $pose=Get-Content -LiteralPath (Join-Path $result[0].EvidenceDirectory 'gameplay-pose.json') -Raw|ConvertFrom-Json
  if($pose.kind -cne 'minecome_gameplay_pose_v1' -or $pose.run -cne $session.run -or $pose.world_id -cne $session.world_id -or $pose.seq -le 0){throw 'Flight pose publication missing or identity differs.'}
  $mapped=[pscustomobject]@{x=120+[double]$m.server_position.x;y=2040-[double]$m.server_position.z;z=56+[double]$m.server_position.y-64}
  if($phase -ceq 'flight-fall'){
   # Cleanup captures a newer authoritative falling position after pose publication
   # has stopped. Its checkpoint can therefore be below the last published pose.
   $top=56+[double]$f.points.before_fall.y-64
   if([Math]::Abs([double]$pose.position.x-$mapped.x) -gt .04 -or [Math]::Abs([double]$pose.position.y-$mapped.y) -gt .04 -or
    [double]$pose.position.z -lt $mapped.z-.04 -or [double]$pose.position.z -gt $top){throw 'Last fall pose is outside the authoritative descent.'}
  }elseif((Get-FlightFixtureDistance $pose.position $mapped) -gt .04){throw 'Host pose does not contain the authoritative vertical/horizontal flight position.'}
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant();session=$session;pose=$pose})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_flight_verification_v1';scenario=$FixturePhase;run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_flight_input=$true;direct_command_api_used=$false;ability_writes_used=$false;position_writes_used=$false;kcd_connected=$false;native_input_verified=$false;instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_FLIGHT_PASS evidence=$directory"
