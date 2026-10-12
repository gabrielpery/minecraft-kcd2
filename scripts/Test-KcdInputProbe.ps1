#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Observe existing Lua action delivery; never inject keys or replace action maps.
[CmdletBinding()]
param([ValidateRange(15,60)][int]$Seconds=60,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly) { Write-Output 'Exact tools preflight passed; no callback installed.';return }
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$sessions=@();$events=@();$motion=@();$restored=$false;$failure=$null;$started=$false
function Sample-InputMotion {
    $command=@'
#local p=player and player:GetWorldPos(); local f=System.GetViewCameraDir(); if p and f then System.LogAlways(string.format('[MineComeInputMotion] {"schema":1,"run":"RUN_TOKEN","player":{"x":%.17g,"y":%.17g,"z":%.17g},"forward":{"x":%.17g,"y":%.17g,"z":%.17g}}',p.x,p.y,p.z,f.x,f.y,f.z)) end
'@
    Invoke-MineComeProbeConsole $context $command.Replace('RUN_TOKEN',$probe.Run)
}
try {
    $probe=New-MineComeProbeRun $context 'input-probe' (Join-Path $context.ProjectRoot 'kcd2/probes/input_probe.lua') 'BeginInputProbe'
    Invoke-MineComeProbeConsole $context ("#MineCome.BeginInputProbe('$($probe.Run)',$Seconds)")
    Sample-InputMotion
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $installDeadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $sessions=@(Get-MineComeProbeReceipts $fresh 'MineComeActionProbeSession' $probe.Run)
        $started=@($sessions | Where-Object { $_.event -eq 'begin' -and $_.result -eq 'started' -and $_.lease_ms -eq $Seconds*1000 }).Count -eq 1
        if($started) { break }
        Start-Sleep -Milliseconds 30
    } while([DateTime]::UtcNow -lt $installDeadline)
    if(-not $started) { throw 'The exact player callback observer did not acknowledge installation.' }
    Write-Output "INPUT_OBSERVER_ARMED run=$($probe.Run) seconds=$Seconds; original gameplay callback continues unchanged."
    $deadline=[DateTime]::UtcNow.AddSeconds($Seconds+4)
    do {
        Sample-InputMotion
        Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $sessions=@(Get-MineComeProbeReceipts $fresh 'MineComeActionProbeSession' $probe.Run)
        $terminal=@($sessions | Where-Object { $_.event -ne 'begin' -and $_.callback_restored -eq $true })
        if($terminal.Count) { $restored=$true;break }
        Start-Sleep -Milliseconds 750
    } while([DateTime]::UtcNow -lt $deadline)
    Invoke-MineComeProbeConsole $context ("#MineCome.EndInputProbe('$($probe.Run)')")
    Sample-InputMotion
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $fresh=Read-MineComeProbeLog $context $probe.Offset
    $sessions=@(Get-MineComeProbeReceipts $fresh 'MineComeActionProbeSession' $probe.Run)
    $events=@(Get-MineComeProbeReceipts $fresh 'MineComeActionProbe' $probe.Run)
    $motion=@(Get-MineComeProbeReceipts $fresh 'MineComeInputMotion' $probe.Run)
    $restored=@($sessions | Where-Object { $_.event -ne 'begin' -and $_.callback_restored -eq $true }).Count -gt 0
    $sessions | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'sessions.json')
    ConvertTo-Json -InputObject $events -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'events.json')
    $motion | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'motion.json')
    if(-not $restored) { throw 'Original player callback restoration was not verified.' }
    Write-Output "Input observation ended; events=$($events.Count), callback restored=$restored. Evidence: $($probe.Directory)"
} catch { $failure=$_.Exception.Message;throw }
finally {
    if($probe) {
        if($started -and -not $restored) { try { Invoke-MineComeProbeConsole $context ("#MineCome.EndInputProbe('$($probe.Run)')") } catch {} }
        try { Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') } catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt') }
        [pscustomobject]@{Run=$probe.Run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameHash=$context.GameHash;GameStartedUtc=$context.GameStartedUtc;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FreshLogOffset=$probe.Offset;FunctionReloadVerified=$probe.FunctionReloadVerified;ObserverStarted=$started;Seconds=$Seconds;ActionReceipts=$events.Count;CallbackRestorationVerified=$restored;PhysicalInputDeliveryVerified=$false;Failure=$failure} |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
