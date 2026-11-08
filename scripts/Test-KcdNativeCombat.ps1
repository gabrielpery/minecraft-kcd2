#Requires -Version 7.3
[CmdletBinding()]
param([Parameter(Mandatory)][int]$ExpectedPid)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$ctx=Get-MineComeProbeContext;if($ctx.GamePid -ne $ExpectedPid){throw 'Native combat proof target PID differs.'}
Get-MineComeToolsConsoleBinding|Out-Null
$modules=@(@('gameplay-movement','movement_session.lua','GameplayMovementBegin'),@('gameplay-combat','combat_session.lua','GameplayCombatBegin'),@('combat-fixture','combat_fixture.lua','GameplayCombatFixtureBegin'),@('combat-native','combat_native_probe.lua','GameplayCombatNativeProbe'))
$loaded=@();foreach($m in $modules){$loaded+=New-MineComeProbeRun $ctx $m[0] (Join-Path $ctx.ProjectRoot ('kcd2/gameplay/'+$m[1])) $m[2]}
$probe=$loaded[-1];$run=$probe.Run;$offset=(Get-Item -LiteralPath $ctx.GameLog).Length
try{
    Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatNativeProbe('$run')"|Out-Null
    $until=[DateTime]::UtcNow.AddSeconds(3)
    do{
        Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeCombatNativeFlush] $run')"|Out-Null
        $log=Read-MineComeProbeLog $ctx $offset
        $outcome=@(Get-MineComeProbeReceipts $log 'MineComeCombatNativeProbe' $run)
        $fixture=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true})
        if($outcome.Count -gt 0 -and $fixture.Count -gt 0){break};Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $until)
}finally{
    Invoke-MineComeProbeConsole $ctx "#MineCome.GameplayCombatEnd('$run');MineCome.GameplayMovementEnd('$run');MineCome.GameplayCombatFixtureEnd('$run')"|Out-Null
    Invoke-MineComeProbeConsole $ctx "#System.LogAlways('[MineComeCombatNativeFinal] $run')"|Out-Null
    $log=Read-MineComeProbeLog $ctx $offset
    [IO.File]::WriteAllText((Join-Path $probe.Directory 'game.log'),$log)
}
$outcome=@(Get-MineComeProbeReceipts $log 'MineComeCombatNativeProbe' $run)
$combat=@(Get-MineComeProbeReceipts $log 'MineComeGameplayCombat' $run)
$fixture=@(Get-MineComeProbeReceipts $log 'MineComeCombatFixture' $run|Where-Object {$_.event -ceq 'terminal' -and $_.removed -eq $true -and $_.path_restored -eq $true})
$movement=@(Get-MineComeProbeReceipts $log 'MineComeGameplayMovement' $run|Where-Object {$_.event -ceq 'terminal'})
$success=$outcome.Count -eq 1 -and $outcome[0].ok -eq $true -and $fixture.Count -gt 0 -and @($combat|Where-Object {$_.event -ceq 'terminal' -and $_.timers_cancelled -eq $true}).Count -gt 0 -and $movement.Count -gt 0 -and $movement[-1].writes -eq 0
$result=[ordered]@{schema=1;kind='minecome_native_combat_proof_v1';success=$success;run=$run;pid=$ctx.GamePid;outcome=$outcome;combat=$combat;movement=$movement;fixture=$fixture;modules=$loaded}
$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $probe.Directory 'result.json') -Encoding utf8NoBOM
Write-Output $probe.Directory
if(-not $success){throw 'Native combat proof failed; inspect saved receipts.'}
Write-Output 'PASS real KCD NPC melee health delta, duplicate acknowledgement and owned cleanup; zero movement writes.'
