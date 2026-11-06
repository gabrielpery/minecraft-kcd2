#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit camera-only probe of an already-running exact tools test process.
# Does not launch games, move player feet or install a gameplay camera toggle.
[CmdletBinding()]
param(
    [ValidateSet('back','front')][string]$Mode='back',
    [ValidateScript({[double]::IsFinite($_) -and $_ -gt 0 -and $_ -le 2.5})][double]$Distance=0.25,
    [ValidateRange(100,1000)][int]$DurationMilliseconds=300,
    [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly){Write-Output 'Exact tools process/version/hash/endpoint preflight passed; no Lua or camera changes made.';return}
Get-MineComeToolsConsoleBinding | Out-Null
$Mode=$Mode.ToLowerInvariant()
$probe=$null;$requested=$false;$failure=$null;$cancelFailure=$null;$captureFailure=$null
$receipts=@();$dispatch=@();$terminal=$null;$cameraReadback=$false;$restored=$false;$feetUnchanged=$false
function Read-PerspectiveEvidence {
    Assert-MineComeProbeContext $context
    $fresh=Read-MineComeProbeLog $context $probe.Offset
    $events=@(Get-MineComeProbeReceipts $fresh 'MineComePerspectiveProbe' $probe.Run)
    $requests=@(Get-MineComeProbeReceipts $fresh 'MineComePerspectiveDispatch' $probe.Run)
    if($events.Count -gt 16 -or $requests.Count -gt 1){throw 'Duplicate or excessive perspective receipts.'}
    foreach($event in $events){
        if($event.mode -cne $Mode -or $event.distance -ne $Distance -or $event.duration_ms -ne $DurationMilliseconds -or $event.player_writes -ne 0){throw 'Perspective receipt does not match the requested camera-only bounds.'}
        foreach($key in @('terminal','write_attempted','reset_succeeded','camera_readback','restored_readback','feet_unchanged','timers_cancelled')){
            if($event.$key -isnot [bool]){throw "Perspective receipt has invalid $key."}
        }
    }
    $ends=@($events|Where-Object terminal)
    if($ends.Count -gt 1){throw 'Multiple terminal perspective receipts.'}
    [pscustomobject]@{Log=$fresh;Receipts=$events;Dispatch=$requests;Terminal=if($ends.Count){$ends[0]}else{$null}}
}
try {
    $probe=New-MineComeProbeRun $context 'perspective-probe' (Join-Path $context.ProjectRoot 'kcd2/probes/perspective_probe.lua') 'BeginPerspectiveProbe' -PrepareOnly
    Initialize-MineComeProbeRun $context $probe
    $distanceLiteral=$Distance.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $command="#local called,ok,reason=pcall(MineCome.BeginPerspectiveProbe,'$($probe.Run)','$Mode',$distanceLiteral,$DurationMilliseconds); reason=called and reason or 'lua_error'; if type(reason)~='string' or not reason:match('^[a-z_]+$') then reason='unexpected_result' end; System.LogAlways('[MineComePerspectiveDispatch] '..string.format('{`"schema`":1,`"run`":`"$($probe.Run)`",`"accepted`":%s,`"reason`":`"%s`"}',tostring(called and ok==true),reason))"
    # Dispatch timeouts are ambiguous: mark requested before sending so finally
    # still sends an owned cancellation. Never repeat Begin on an HTTP failure.
    $requested=$true
    Invoke-MineComeProbeConsole $context $command
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do {
        Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComePerspectiveFlush] $($probe.Run)')")
        $evidence=Read-PerspectiveEvidence
        $receipts=$evidence.Receipts;$dispatch=$evidence.Dispatch;$terminal=$evidence.Terminal
        if($dispatch.Count -eq 1 -and ($dispatch[0].accepted -isnot [bool] -or -not $dispatch[0].accepted)){throw "Camera probe rejected: $($dispatch[0].reason)."}
        if($terminal){break}
        Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $terminal){throw 'No matching terminal camera receipt; restoration is unverified.'}
    $cameraReadback=@($receipts|Where-Object {$_.stage -ceq 'sample' -and $_.camera_readback -and $_.feet_unchanged}).Count -eq 1
    $feetUnchanged=$receipts.Count -gt 0 -and @($receipts|Where-Object {-not $_.feet_unchanged}).Count -eq 0
    $restored=$terminal.reset_succeeded -and $terminal.restored_readback -and $terminal.feet_unchanged -and $terminal.timers_cancelled -and $terminal.result -ceq 'restored'
    if($dispatch.Count -ne 1 -or -not $dispatch[0].accepted){throw 'No unique accepted dispatch receipt.'}
    if(-not $restored){throw 'Camera restoration was not verified; inspect evidence before any repeat.'}
    if(-not $cameraReadback -or -not $feetUnchanged){throw 'Camera was released, but requested perspective or unchanged player feet did not verify.'}
} catch {$failure=$_.Exception.Message}
finally {
    if($probe){
        if($requested -and ($failure -or -not $restored)){
            try {
                Invoke-MineComeProbeConsole $context ("#if MineCome and type(MineCome.EndPerspectiveProbe)=='function' then MineCome.EndPerspectiveProbe('$($probe.Run)') end")
                $cancelDeadline=[DateTime]::UtcNow.AddSeconds(2)
                do {
                    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComePerspectiveCancelFlush] $($probe.Run)')")
                    $evidence=Read-PerspectiveEvidence
                    if($evidence.Terminal){break}
                    Start-Sleep -Milliseconds 50
                }while([DateTime]::UtcNow -lt $cancelDeadline)
            }catch{$cancelFailure=$_.Exception.Message}
        }
        try {
            $evidence=Read-PerspectiveEvidence;$receipts=$evidence.Receipts;$dispatch=$evidence.Dispatch;$terminal=$evidence.Terminal
            $evidence.Log|Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log')
            $cameraReadback=@($receipts|Where-Object {$_.stage -ceq 'sample' -and $_.camera_readback -and $_.feet_unchanged}).Count -eq 1
            $feetUnchanged=$receipts.Count -gt 0 -and @($receipts|Where-Object {-not $_.feet_unchanged}).Count -eq 0
            $restored=$null -ne $terminal -and $terminal.reset_succeeded -and $terminal.restored_readback -and $terminal.feet_unchanged -and $terminal.timers_cancelled -and $terminal.result -ceq 'restored'
        }catch{$captureFailure=$_.Exception.Message;if(-not $failure){$failure=$captureFailure}}
        @($receipts)|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'receipts.json')
        $verification=[ordered]@{Kind='Bounded native perspective camera probe';Run=$probe.Run;Mode=$Mode;Distance=$Distance;DurationMilliseconds=$DurationMilliseconds;
            GamePid=$context.GamePid;GameStartedUtc=$context.GameStartedUtc;GamePath=$context.GamePath;GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FunctionReloadVerified=$probe.FunctionReloadVerified;FreshLogOffset=$probe.Offset;
            CameraRequested=$requested;Dispatch=$dispatch;CameraReadbackVerified=$cameraReadback;FeetUnchangedVerified=$feetUnchanged;RestorationVerified=$restored;
            IndependentMouseLookVerified=$false;IntegratedGameplayPerspectiveVerified=$false;PlayerWrites=0;Failure=$failure;CancelFailure=$cancelFailure;CaptureFailure=$captureFailure}
        $verification|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
if($failure){throw "$failure Evidence: $($probe.Directory)"}
[pscustomobject]@{EvidenceDirectory=$probe.Directory;Run=$probe.Run;CameraReadbackVerified=$cameraReadback;FeetUnchangedVerified=$feetUnchanged;RestorationVerified=$restored;IndependentMouseLookVerified=$false;IntegratedGameplayPerspectiveVerified=$false}
