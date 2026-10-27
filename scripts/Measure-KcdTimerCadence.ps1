#Requires -Version 7.3
# No actor or input writes; three bounded chains observe official frame IDs.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
$context=Get-MineComeProbeContext;$budget=New-MineComeHudGpuBudget $context;$probe=$null
try{
    Start-MineComeHudGpuBudget $budget
    $probe=New-MineComeProbeRun $context 'timer-cadence' (Join-Path $context.ProjectRoot 'kcd2/probes/timer_cadence_probe.lua') 'ProbeTimerCadence'
    Invoke-MineComeProbeConsole $context "#MineCome.ProbeTimerCadence('$($probe.Run)')"
    Start-Sleep -Milliseconds 700
    Invoke-MineComeProbeConsole $context "#System.LogAlways('[MineComeTimerCadenceFlush] $($probe.Run)')"
    $records=@(Get-MineComeProbeReceipts (Read-MineComeProbeLog $context $probe.Offset) 'MineComeTimerCadence' $probe.Run)
    $records | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'receipts.json') -Encoding utf8NoBOM
    if(@($records | Where-Object {$_.event -ceq 'complete' -and $_.timers_cancelled -eq $true}).Count -ne 1){throw 'Timer observation did not complete with cancellation.'}
    $records | Select-Object event,chain,count,engine_seconds,frame_id,frame_time_raw | Format-Table
    Write-Output "TIMER_CADENCE_MEASURED actor_writes=0 evidence=$($probe.Directory)"
}finally{
    Stop-MineComeHudGpuBudget $budget
    if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Timer measurement FPS budget restoration failed.'}
}
