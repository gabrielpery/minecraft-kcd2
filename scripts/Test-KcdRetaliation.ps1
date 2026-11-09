#Requires -Version 7.3
# Real hostile attacks only; exact owned temporary native protection, no health refund.
[CmdletBinding()]
param([Parameter(Mandatory)][int]$ExpectedPid,[switch]$FreeAim)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$ctx=Get-MineComeProbeContext;if($ctx.GamePid -ne $ExpectedPid){throw 'Retaliation target PID differs.'}
Get-MineComeToolsConsoleBinding|Out-Null
$loaded=@();$modules=@()
if($FreeAim){$modules+=,@('gameplay-combat','combat_session.lua','GameplayCombatBegin')}
$modules+=@(@('combat-fixture','combat_fixture.lua','GameplayCombatFixtureBegin'),@('combat-retaliation','combat_retaliation_probe.lua','GameplayRetaliationProbe'))
foreach($m in $modules){
 $loaded+=New-MineComeProbeRun $ctx $m[0] (Join-Path $ctx.ProjectRoot ('kcd2/gameplay/'+$m[1])) $m[2]
}
$probe=$loaded[-1];$run=$probe.Run;$offset=(Get-Item -LiteralPath $ctx.GameLog).Length;$log='';$outcome=@();$fixture=@();$combatSequence=0;$combatStarted=$false
try{
 if($FreeAim){$combatStarted=$true;Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatBegin('$run',20000,16,8)"|Out-Null}
 Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayRetaliationProbe('$run')"|Out-Null
 $until=[DateTime]::UtcNow.AddSeconds(22)
 do{
  if($FreeAim){$combatSequence++;Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatSample('$run',$combatSequence)"|Out-Null}
  Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeRetaliationFlush] $run')"|Out-Null
  $log=Read-MineComeProbeLog $ctx $offset;$outcome=@(Get-MineComeProbeReceipts $log 'MineComeRetaliation' $run)
  if($outcome.Count){break};Start-Sleep -Milliseconds 100
 }while([DateTime]::UtcNow -lt $until)
}finally{
 Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayRetaliationEnd('$run')"|Out-Null
 $until=[DateTime]::UtcNow.AddSeconds(3)
 do{
  Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeRetaliationFinal] $run')"|Out-Null
  $log=Read-MineComeProbeLog $ctx $offset;$outcome=@(Get-MineComeProbeReceipts $log 'MineComeRetaliation' $run)
  if($outcome.Count){break};Start-Sleep -Milliseconds 100
 }while([DateTime]::UtcNow -lt $until)
 if($combatStarted){
  Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatEnd('$run')"|Out-Null
  $until=[DateTime]::UtcNow.AddSeconds(2)
  do{
   Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeRetaliationCombatFinal] $run')"|Out-Null
   $log=Read-MineComeProbeLog $ctx $offset
   if(@(Get-MineComeProbeReceipts $log 'MineComeGameplayCombat' $run|Where-Object event -CEQ 'terminal').Count){break}
   Start-Sleep -Milliseconds 50
  }while([DateTime]::UtcNow -lt $until)
 }
 [IO.File]::WriteAllText((Join-Path $probe.Directory 'game.log'),$log)
}
$fixture=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.mode -ceq 'hostile' -and $_.removed -eq $true -and $_.path_restored -eq $true})
$complete=$outcome.Count -eq 1 -and $outcome[0].completed -eq $true -and $outcome[0].fixture_removed -eq $true -and $outcome[0].buff_removed -eq $true -and $outcome[0].callback_restored -eq $true -and $outcome[0].timers_cancelled -eq $true -and $fixture.Count -gt 0
$combat=@(Get-MineComeProbeReceipts $log 'MineComeGameplayCombat' $run)
$policyActive=@($combat|Where-Object {$_.event -ceq 'begin' -and $_.result -ceq 'ready' -and $_.lock_policy_active -is [bool] -and $_.lock_policy_active}).Count -eq 1
$policyRestored=@($combat|Where-Object {$_.event -ceq 'terminal' -and $_.lock_policy_restored -eq $true -and $_.timers_cancelled -eq $true}).Count -gt 0
if($FreeAim -and (-not $policyActive -or -not $policyRestored)){$complete=$false}
$freeAimVerified=$FreeAim -and $complete -and $outcome[0].lock_seen -eq $false -and $outcome[0].health_loss_observed -eq $true
[ordered]@{schema=1;kind='minecome_native_retaliation_observation_v1';completed=$complete;pid=$ctx.GamePid;run=$run;outcome=$outcome;fixture=$fixture;modules=$loaded;production_incoming_damage_verified=$false;free_aim_requested=[bool]$FreeAim;hostile_free_aim_verified=[bool]$freeAimVerified;combat=$combat}|
 ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $probe.Directory 'result.json') -Encoding utf8NoBOM
Write-Output "RETALIATION_EVIDENCE=$($probe.Directory)"
if(-not $complete){throw 'Retaliation observation/cleanup incomplete; inspect saved evidence. Protection is intentionally retained if the owned hostile removal is unconfirmed.'}
Write-Output "RETALIATION_OBSERVED attack=$($outcome[0].attack_observed) health_loss=$($outcome[0].health_loss) callbacks=$($outcome[0].callback_count) locked=$($outcome[0].lock_seen) (observation only; no incoming gameplay claim)"
