# Two actual Minecraft launches. Commands are typed into real ChatScreen input;
# native keyboard capture and live KCD composition are not claimed.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){$code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters;if($code -ne 0){throw "Gameplay chat check failed: $code"};return}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N');$directory=Join-Path $root ('runtime/evidence/gameplay-chat-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$patchHash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant();$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
function Get-ChatFixtureDistance($A,$B){return [Math]::Sqrt([Math]::Pow([double]$A.x-[double]$B.x,2)+[Math]::Pow([double]$A.y-[double]$B.y,2)+[Math]::Pow([double]$A.z-[double]$B.z,2))}
try{
 foreach($phase in @('chat','chat-resume')){
  if((Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $patchHash){throw 'Chat fixture terrain changed between launches.'}
  $launchArguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Chat=$true;GroundPatchFile=$patch};if($ReceiverPath){$launchArguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @launchArguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.movement -or -not $verification.blocks){throw 'Chat guest did not save and close normally.'}
  $sessionFile=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json';$session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json -Depth 24
  $f=$session.fixture;$m=$session.movement
  if($f.kind -cne 'minecome_gameplay_chat_fixture_v1' -or $f.mode -cne $phase -or $f.result -cne 'passed' -or $f.failure -or
   -not $f.actual_minecraft -or -not $f.standalone_scripted -or $f.native_input_verified -or $f.live_kcd_verified -or $f.direct_command_api_used -or
   $f.world_id -cne $session.world_id -or $session.kcd_movement_connected -or $session.host_command_typing_verified -or $f.game_mode -cne 'survival' -or $f.stone_count -ne 7){throw 'Chat fixture state, identity or evidence scope differs.'}
  foreach($flag in @('survival_verified','creative_verified','give_verified','walking_after_chat_verified')){if($f.$flag -ne $true){throw "Missing actual chat capability: $flag"}}
  if($m.failure -or $m.patch_run -cne $run -or $m.patch_sha256 -cne $patchHash -or $m.world_id -cne $session.world_id -or
   $m.client_walk -lt .15 -or $m.server_walk -lt .15 -or -not $m.cleanup_complete -or -not $m.ground_cells_air -or -not $m.terrain_cells_valid -or
   -not $m.controls_released -or -not $m.client_collision_released -or -not $m.server_collision_released -or -not $m.resume_checkpoint_present -or
   (Get-ChatFixtureDistance $m.resume_checkpoint $m.server_position) -gt .04){throw 'Chat movement isolation/resume checkpoint or cleanup failed.'}
  if($session.blocks.failure -or $session.blocks.owned_count -ne 0 -or -not $session.blocks.cleanup_complete){throw 'Chat profile altered the stone ledger or failed cleanup.'}
  if($phase -ceq 'chat'){
   foreach($flag in @('editing_verified','cancel_verified','invalid_command_recovered','chat_suppression_verified')){if($f.$flag -ne $true){throw "Missing chat editor/isolation capability: $flag"}}
   if(-not $session.new_world -or -not $m.first_attachment -or $f.chat_ticks -lt 5 -or $f.text_events -lt 100 -or $f.edit_events -lt 10 -or
    ($f.submitted_commands -join '|') -cne '/gamemode survival|/give @s minecraft:stone 7|/minecome_nonexistent_command|/gamemode creative|/gamemode survival'){throw 'First chat phase did not exercise expected actual commands and editor controls.'}
  }else{
   if($session.new_world -or -not $f.resume_verified -or $session.world_id -cne $proofs[0].session.world_id -or $f.player_id -cne $proofs[0].session.fixture.player_id -or
    $m.first_attachment -or -not $m.resume_position_restored -or (Get-ChatFixtureDistance $f.initial_position $proofs[0].session.movement.resume_checkpoint) -gt .04 -or
    ($f.submitted_commands -join '|') -cne '/gamemode creative|/gamemode survival'){throw 'Saved chat-produced game mode/items/player checkpoint did not survive reopening.'}
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $sessionFile).Hash.ToLowerInvariant();session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{[ordered]@{schema=1;kind='minecome_gameplay_chat_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;actual_minecraft=$true;scripted_chat_input=$true;direct_command_api_used=$false;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;instance=$instance;patch_sha256=$patchHash;launches=$proofs.ToArray()}|ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM}
Write-Output "GAMEPLAY_CHAT_PASS evidence=$directory"
