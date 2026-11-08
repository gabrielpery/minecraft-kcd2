#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit camera/render-only probe of an already-running exact tools test process.
# Does not launch games, move player feet or install a gameplay camera toggle.
[CmdletBinding()]
param(
    [ValidateSet('back','front')][string]$Mode='back',
    [ValidateScript({[double]::IsFinite($_) -and $_ -gt 0 -and $_ -le 2.5})][double]$Distance=0.25,
    [ValidateRange(100,15000)][int]$DurationMilliseconds=300,
    [ValidateSet('','observe','resample')][string]$LookStrategy='',
    [switch]$HideBody,
    [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
if(-not $LookStrategy -and $DurationMilliseconds -gt 1000){throw 'A static camera probe is limited to 1000 milliseconds; use LookStrategy for a bounded mouse-look observation.'}
if($HideBody -and -not $LookStrategy){throw 'HideBody is available only in a bounded LookStrategy probe, with an explicitly visible body baseline.'}
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly){Write-Output 'Exact tools process/version/hash/endpoint preflight passed; no Lua or camera changes made.';return}
Get-MineComeToolsConsoleBinding | Out-Null
$Mode=$Mode.ToLowerInvariant()
$LookStrategy=$LookStrategy.ToLowerInvariant()
$probe=$null;$requested=$false;$failure=$null;$cancelFailure=$null;$captureFailure=$null
$receipts=@();$dispatch=@();$terminal=$null;$cameraReadback=$false;$restored=$false;$feetUnchanged=$false
function Read-PerspectiveEvidence {
    Assert-MineComeProbeContext $context
    $fresh=Read-MineComeProbeLog $context $probe.Offset
    $events=@(Get-MineComeProbeReceipts $fresh 'MineComePerspectiveProbe' $probe.Run)
    $requests=@(Get-MineComeProbeReceipts $fresh 'MineComePerspectiveDispatch' $probe.Run)
    $receiptLimit=if($LookStrategy){160}else{16}
    if($events.Count -gt $receiptLimit -or $requests.Count -gt 1){throw 'Duplicate or excessive perspective receipts.'}
    foreach($event in $events){
        if($event.mode -cne $Mode -or $event.distance -ne $Distance -or $event.duration_ms -ne $DurationMilliseconds -or $event.player_writes -ne 0){throw 'Perspective receipt does not match the requested camera-only bounds.'}
        foreach($key in @('terminal','write_attempted','reset_succeeded','camera_readback','restored_readback','feet_unchanged','timers_cancelled')){
            if($event.$key -isnot [bool]){throw "Perspective receipt has invalid $key."}
        }
        if($LookStrategy){
            if($event.look_strategy -cne $LookStrategy){throw 'Perspective look receipt does not match the requested strategy.'}
            if($event.hide_body -isnot [bool] -or $event.hide_body -ne [bool]$HideBody){throw 'Perspective body receipt does not match the requested experiment.'}
            foreach($key in @('normal_sample_immediate','normal_view_position_restored','original_view_basis_restored')){
                if($event.$key -isnot [bool]){throw "Perspective look receipt has invalid $key."}
            }
            if($event.look_samples -isnot [long] -and $event.look_samples -isnot [int]){throw 'Perspective look receipt has invalid sample count.'}
            if($event.look_samples -lt 0 -or $event.look_samples -gt 150){throw 'Perspective look sample count exceeds its bound.'}
            if($HideBody){
                foreach($key in @('body_baseline_succeeded','body_hide_succeeded','body_restore_succeeded','body_visibility_readback_verified')){
                    if($event.$key -isnot [bool]){throw "Perspective body receipt has invalid $key."}
                }
            }
        }
    }
    $ends=@($events|Where-Object terminal)
    if($ends.Count -gt 1){throw 'Multiple terminal perspective receipts.'}
    [pscustomobject]@{Log=$fresh;Receipts=$events;Dispatch=$requests;Terminal=if($ends.Count){$ends[0]}else{$null}}
}
function Test-PerspectiveRestoration($event) {
    if($null -eq $event){return $false}
    $released=$event.reset_succeeded -and $event.restored_readback -and $event.feet_unchanged -and $event.timers_cancelled -and $event.result -ceq 'restored'
    # A look probe intentionally permits a changed view direction. It must
    # restore the current native head position/direction and eye FOV; static probes still require their
    # original camera basis through restored_readback in the Lua module.
    return $released -and (-not $LookStrategy -or $event.normal_view_position_restored) -and (-not $HideBody -or $event.body_restore_succeeded)
}
try {
    $entryPoint=if($LookStrategy){'BeginPerspectiveLookProbe'}else{'BeginPerspectiveProbe'}
    $probe=New-MineComeProbeRun $context 'perspective-probe' (Join-Path $context.ProjectRoot 'kcd2/probes/perspective_probe.lua') $entryPoint -PrepareOnly
    Initialize-MineComeProbeRun $context $probe
    $distanceLiteral=$Distance.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $lookArgument=if($LookStrategy){",'$LookStrategy',"+([bool]$HideBody).ToString().ToLowerInvariant()}else{''}
    $command="#local called,ok,reason=pcall(MineCome.$entryPoint,'$($probe.Run)','$Mode',$distanceLiteral,$DurationMilliseconds$lookArgument); reason=called and reason or 'lua_error'; if type(reason)~='string' or not reason:match('^[a-z_]+$') then reason='unexpected_result' end; System.LogAlways('[MineComePerspectiveDispatch] '..string.format('{`"schema`":1,`"run`":`"$($probe.Run)`",`"accepted`":%s,`"reason`":`"%s`"}',tostring(called and ok==true),reason))"
    # Dispatch timeouts are ambiguous: mark requested before sending so finally
    # still sends an owned cancellation. Never repeat Begin on an HTTP failure.
    $requested=$true
    Invoke-MineComeProbeConsole $context $command
    if($LookStrategy){Write-Output "KCD_PERSPECTIVE_LOOK_READY run=$($probe.Run) strategy=$LookStrategy hide_body=$([bool]$HideBody) duration_ms=$DurationMilliseconds evidence=$($probe.Directory)"}
    $deadline=[DateTime]::UtcNow.AddMilliseconds($DurationMilliseconds+5000)
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
    $restored=Test-PerspectiveRestoration $terminal
    if($dispatch.Count -ne 1 -or -not $dispatch[0].accepted){throw 'No unique accepted dispatch receipt.'}
    if(-not $restored){throw 'Camera restoration was not verified; inspect evidence before any repeat.'}
    if($HideBody -and (-not $terminal.body_baseline_succeeded -or -not $terminal.body_hide_succeeded)){throw 'Body render experiment did not complete baseline/hide dispatch; inspect evidence.'}
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
            $restored=Test-PerspectiveRestoration $terminal
        }catch{$captureFailure=$_.Exception.Message;if(-not $failure){$failure=$captureFailure}}
        @($receipts)|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'receipts.json')
        $verification=[ordered]@{Kind='Bounded native perspective camera probe';Run=$probe.Run;Mode=$Mode;Distance=$Distance;DurationMilliseconds=$DurationMilliseconds;LookStrategy=$LookStrategy;HideBody=[bool]$HideBody;BodyVisibleBaselineRestored=([bool]$HideBody -and $terminal.body_restore_succeeded);BodyVisibilityReadbackVerified=$false;LookSampleCount=@($receipts|Where-Object stage -CEQ 'look').Count;
            GamePid=$context.GamePid;GameStartedUtc=$context.GameStartedUtc;GamePath=$context.GamePath;GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FunctionReloadVerified=$probe.FunctionReloadVerified;FreshLogOffset=$probe.Offset;
            CameraRequested=$requested;Dispatch=$dispatch;CameraReadbackVerified=$cameraReadback;FeetUnchangedVerified=$feetUnchanged;RestorationVerified=$restored;
            IndependentMouseLookVerified=$false;IntegratedGameplayPerspectiveVerified=$false;PlayerWrites=0;Failure=$failure;CancelFailure=$cancelFailure;CaptureFailure=$captureFailure}
        $verification|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
if($failure){throw "$failure Evidence: $($probe.Directory)"}
[pscustomobject]@{EvidenceDirectory=$probe.Directory;Run=$probe.Run;LookStrategy=$LookStrategy;HideBody=[bool]$HideBody;BodyVisibleBaselineRestored=([bool]$HideBody -and $terminal.body_restore_succeeded);BodyVisibilityReadbackVerified=$false;LookSampleCount=@($receipts|Where-Object stage -CEQ 'look').Count;CameraReadbackVerified=$cameraReadback;FeetUnchangedVerified=$feetUnchanged;RestorationVerified=$restored;IndependentMouseLookVerified=$false;IntegratedGameplayPerspectiveVerified=$false}
