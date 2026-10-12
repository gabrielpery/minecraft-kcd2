#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
[CmdletBinding()]
param([ValidateSet('Capabilities','Position')][string]$Action='Capabilities',[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
$source=Join-Path $context.ProjectRoot 'kcd2/probes/movement_probe.lua'
if($PreflightOnly) { Write-Output 'Exact tools process/version/hash/endpoint preflight passed; no Lua or world changes made.';return }
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$capabilities=$null;$movement=@();$failure=$null;$movementRequested=$false;$restorationVerified=$false;$positionVerified=$false;$cameraFollowVerified=$false
try {
    $probe=New-MineComeProbeRun $context 'movement-probe' $source 'ProbeMovementCapabilities'
    Invoke-MineComeProbeConsole $context ("#MineCome.ProbeMovementCapabilities('$($probe.Run)')")
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $found=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementCapabilities' $probe.Run)
        if($found.Count -eq 1) { $capabilities=$found[0];break }
        Start-Sleep -Milliseconds 50
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $capabilities) { throw 'No fresh matching engine movement-capability receipt.' }
    $capabilities | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'capabilities.json')
    Write-Output ($capabilities | ConvertTo-Json -Depth 10)
    if($Action -eq 'Position') {
        if($capabilities.identity_stable -ne $true -or $capabilities.linked_kind -notin @('nil','number_zero')) { throw 'No proved stationary actor/no-link contract; no movement requested.' }
        $kind=$capabilities.linked_kind
        Invoke-MineComeProbeConsole $context ("#MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$kind')")
        Invoke-MineComeProbeConsole $context ("#MineCome.BeginMovementProbe('$($probe.Run)')")
        $movementRequested=$true
        $deadline=[DateTime]::UtcNow.AddSeconds(5)
        do {
            Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
            $fresh=Read-MineComeProbeLog $context $probe.Offset
            $movement=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementProbe' $probe.Run)
            $restored=@($movement | Where-Object { $_.stage -eq 'restored' -and $_.terminal -eq $true -and $_.readback -eq $true -and $_.restore_result -eq 'restored' -and $_.timers_cancelled -eq $true })
            if($restored.Count -eq 1) { $restorationVerified=$true;break }
            if(@($movement | Where-Object { $_.stage -in @('rejected','restore_failed','restore_skipped') }).Count) { break }
            Start-Sleep -Milliseconds 100
        } while([DateTime]::UtcNow -lt $deadline)
        $movement | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'movement.json')
        Write-Output ($movement | ConvertTo-Json -Depth 10)
        if(-not $restorationVerified) { throw 'The bounded position probe did not confirm restoration; inspect its receipts before repeating.' }
        $positionVerified=@($movement | Where-Object { $_.stage -eq 'applied' -and $_.applied -eq $true -and $_.readback -eq $true }).Count -eq 1
        $cameraFollowVerified=@($movement | Where-Object { $_.stage -in @('sample100','sample250') -and $_.readback -eq $true -and $_.camera_follow -eq $true }).Count -gt 0
        if(-not $positionVerified -or -not $cameraFollowVerified) { throw 'Restoration passed, but position application or camera following was not verified.' }
    }
    Write-Output "Engine $Action probe captured. Evidence: $($probe.Directory)"
} catch { $failure=$_.Exception.Message;throw }
finally {
    if($probe) {
        if($movementRequested -and -not $restorationVerified) {
            try { Invoke-MineComeProbeConsole $context ("#MineCome.EndMovementProbe('$($probe.Run)')");Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')") }
            catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'cancel-error.txt') }
        }
        try { Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') } catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt') }
        [pscustomobject]@{Action=$Action;Run=$probe.Run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameStartedUtc=$context.GameStartedUtc;GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FreshLogOffset=$probe.Offset;FunctionReloadVerified=$probe.FunctionReloadVerified;CapabilitiesVerified=($null -ne $capabilities);MovementRequested=$movementRequested;PositionVerified=$positionVerified;CameraFollowVerified=$cameraFollowVerified;RestorationVerified=$restorationVerified;FullMovementAuthorityVerified=$false;Failure=$failure} |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
