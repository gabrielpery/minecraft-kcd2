# Real vanilla eating, interruptions, regeneration and a second launch of the saved world.
[CmdletBinding()]
param([string]$JavaHome='C:/Program Files/Java/jdk-24',[string]$ReceiverPath)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Gameplay food check failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/gameplay-food-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run)
[void][IO.Directory]::CreateDirectory($directory)
$instance=Join-Path $directory 'instance';$patch=Join-Path $directory 'ground-patch.json'
New-HudGroundMovementPatch $run -WideWalking|ConvertTo-Json -Depth 12 -Compress|Set-Content -LiteralPath $patch -Encoding utf8NoBOM
$hash=(Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant()
$proofs=[Collections.Generic.List[object]]::new();$passed=$false;$failure=$null
try{
 foreach($phase in @('food','food-resume')){
  $arguments=@{JavaHome=$JavaHome;InstanceDirectory=$instance;EvidenceDirectory=(Join-Path $directory $phase);FixturePhase=$phase;Hands=$true;GroundPatchFile=$patch}
  if($ReceiverPath){$arguments.ReceiverPath=$ReceiverPath}
  $result=@(& (Join-Path $PSScriptRoot 'Start-GameplayGuest.ps1') @arguments | ForEach-Object {if($_ -isnot [string] -and $_.PSObject.Properties['VerificationFile']){$_}else{Write-Host $_}})
  if($result.Count -ne 1){throw "Missing $phase result."}
  $verification=Get-Content -LiteralPath $result[0].VerificationFile -Raw|ConvertFrom-Json
  $file=Join-Path $result[0].EvidenceDirectory 'gameplay-session.json'
  $session=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json -Depth 24
  $fixture=$session.fixture;$blocks=$session.blocks;$movement=$session.movement;$food=$blocks.food_use
  if($verification.result -cne 'passed' -or -not $verification.normal_client_exit -or -not $verification.blocks -or
   $fixture.kind -cne 'minecome_gameplay_food_fixture_v1' -or $fixture.mode -cne $phase -or $fixture.result -cne 'passed' -or
   -not $fixture.actual_minecraft -or -not $fixture.standalone_scripted -or $fixture.native_input_verified -or $fixture.live_kcd_verified -or
   $session.kcd_movement_connected -or $session.host_command_typing_verified -or $fixture.direct_health_food_inventory_writes -or
   $fixture.world_id -cne $session.world_id){throw "Food fixture verification scope differs: $phase"}
  if($blocks.failure -or $blocks.pending -or $blocks.owned_count -ne 0 -or -not $blocks.controls_released -or -not $blocks.cleanup_complete -or
   $food.held -or $food.active -or -not $food.controls_released -or $food.synthetic_use_key -or $food.health_food_stack_written_directly){throw "Food controller failed cleanup: $phase"}
  if($movement.failure -or -not $movement.cleanup_complete -or -not $movement.controls_released -or -not $movement.terrain_cells_valid -or
   $movement.patch_run -cne $run -or $movement.patch_sha256 -cne $hash -or (Get-FileHash -LiteralPath $patch).Hash.ToLowerInvariant() -cne $hash){throw "Food fixture terrain changed: $phase"}
  if($phase -ceq 'food'){
   if(-not $session.new_world -or $food.preserved_ticks -lt 20 -or $food.starts -lt 5){throw 'Food hold did not exercise vanilla continuation.'}
   foreach($flag in @('early_release_verified','slot_change_verified','inventory_interrupt_verified','authority_gate_verified','mode_change_verified','hunger_refill_verified','full_hunger_rejected','regeneration_verified')){
    if($fixture.$flag -ne $true){throw "Missing food capability: $flag"}
   }
   if(@($fixture.meals).Count -lt 2 -or $food.server_consumptions -ne @($fixture.meals).Count -or
    $fixture.final_state.bread_count -ne $fixture.baseline.bread_count-@($fixture.meals).Count -or
    $fixture.final_state.health -le $fixture.baseline.health -or $fixture.final_state.natural_regeneration -or
    $fixture.damage_after_observed_server_ticks -lt 61){throw 'Vanilla server consumption, recovery or setup proof differs.'}
  }else{
   if($session.new_world -or -not $fixture.resume_verified -or $session.world_id -cne $proofs[0].session.world_id){throw 'Food resume replaced or failed to restore the saved world.'}
   foreach($key in @('player_id','mode','health','food','saturation','exhaustion','natural_regeneration','selected','bread_count')){
    if($fixture.final_state.$key -cne $proofs[0].session.fixture.final_state.$key){throw "Food reload differs for $key"}
   }
  }
  $proofs.Add([pscustomobject]@{phase=$phase;directory=$result[0].EvidenceDirectory;session_sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();session=$session})
 }
 $passed=$true
}catch{$failure=$_.Exception.Message;throw}
finally{
 [ordered]@{schema=1;kind='minecome_gameplay_food_verification_v1';run=$run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;
  actual_minecraft=$true;kcd_connected=$false;native_input_verified=$false;host_command_typing_verified=$false;instance=$instance;patch_sha256=$hash;launches=$proofs.ToArray()}|
  ConvertTo-Json -Depth 24|Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
}
Write-Output "GAMEPLAY_FOOD_PASS evidence=$directory"
