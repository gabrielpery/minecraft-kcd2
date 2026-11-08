#Requires -Version 7.3
# Bounded experiment on one owned NPC only. No HUD/client/player-health changes.
[CmdletBinding()]
param([Parameter(Mandatory)][int]$ExpectedPid,[switch]$NormalHit)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$ctx=Get-MineComeProbeContext;if($ctx.GamePid -ne $ExpectedPid){throw 'Combat protection probe PID differs.'}
Get-MineComeToolsConsoleBinding|Out-Null
$loaded=@()
foreach($m in @(@('combat-fixture','combat_fixture.lua','GameplayCombatFixtureBegin'),@('combat-protection','combat_protection_probe.lua','GameplayCombatProtectionProbe'))){
 $loaded+=New-MineComeProbeRun $ctx $m[0] (Join-Path $ctx.ProjectRoot ('kcd2/gameplay/'+$m[1])) $m[2]
}
$damageMode=if($NormalHit){'normal_hit'}else{'soul'}
$attackerKind=if($NormalHit){'entity_handle'}else{'wuid'}
$probe=$loaded[-1];$run=$probe.Run;$offset=(Get-Item -LiteralPath $ctx.GameLog).Length;$log='';$outcome=@();$fixture=@()
try{
 Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatProtectionProbe('$run','$damageMode')"|Out-Null
 $until=[DateTime]::UtcNow.AddSeconds(7)
 do{
  Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeCombatProtectionFlush] $run')"|Out-Null
  $log=Read-MineComeProbeLog $ctx $offset
  $outcome=@(Get-MineComeProbeReceipts $log 'MineComeCombatProtection' $run)
  $fixture=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true})
  if($outcome.Count -gt 0 -and $fixture.Count -gt 0){break};Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $until)
}finally{
 Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatProtectionEnd('$run');MineCome.GameplayCombatFixtureEnd('$run')"|Out-Null
 $cleanupUntil=[DateTime]::UtcNow.AddSeconds(2)
 do{
  Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeCombatProtectionFinal] $run')"|Out-Null
  $log=Read-MineComeProbeLog $ctx $offset
  $outcome=@(Get-MineComeProbeReceipts $log 'MineComeCombatProtection' $run)
  $fixture=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true})
  if($fixture.Count -gt 0){break};Start-Sleep -Milliseconds 50
 }while([DateTime]::UtcNow -lt $cleanupUntil)
 [IO.File]::WriteAllText((Join-Path $probe.Directory 'game.log'),$log)
}
$completed=$outcome.Count -eq 1 -and $outcome[0].completed -eq $true -and $outcome[0].damage_mode -ceq $damageMode -and $outcome[0].attacker_identifier_kind -ceq $attackerKind -and $outcome[0].timers_cancelled -eq $true -and $outcome[0].buff_removed -eq $true -and $outcome[0].callback_restored -eq $true -and $outcome[0].player_mutated -eq $false -and $fixture.Count -gt 0
[ordered]@{schema=1;kind='minecome_native_combat_protection_experiment_v1';completed=$completed;damage_mode=$damageMode;attacker_identifier_kind=$attackerKind;run=$run;pid=$ctx.GamePid;outcome=$outcome;fixture=$fixture;modules=$loaded;production_incoming_damage_verified=$false;hostile_free_aim_verified=$false}|
 ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $probe.Directory 'result.json') -Encoding utf8NoBOM
Write-Output "COMBAT_PROTECTION_EVIDENCE=$($probe.Directory)"
if(-not $completed){throw 'Protection experiment stopped without complete confirmed ownership/cleanup; inspect saved receipts.'}
Write-Output "COMBAT_DAMAGE_MODE=$damageMode COMBAT_PROTECTION_OBSERVED=$($outcome[0].protection_observed) CALLBACKS=$($outcome[0].callback_count) (owned NPC only; no incoming gameplay claim)"
