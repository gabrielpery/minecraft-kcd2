# SPDX-License-Identifier: GPL-3.0-or-later
# Automatic three-tile Minecraft extension with a pinned KCD player/camera follower.
# Does not launch/stop KCD2, capture keys or arm native HUD composition.
[CmdletBinding()]
param([switch]$PreflightOnly,[switch]$DelayHandoff)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Coupled extension failed: $code"};return
}

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundExtension.ps1')
. (Join-Path $PSScriptRoot 'GroundExtensionMovementProof.ps1')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly) { Write-Output 'Coupled-extension exact tools preflight passed; no game changes made.';return }
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$helper=$null;$failure=$null;$followerStarted=$false;$restored=$false;$tracePassed=$false;$minecraftPassed=$false;$coupledPassed=$false
$forwarded=[Collections.Generic.List[object]]::new();$accepted=[Collections.Generic.List[object]]::new()
$receipts=@();$capabilities=$null;$helperStarted=$null;$hudReady=$null;$hudProof=$null;$hudVerificationHash=$null
$hudReadyHash=$null;$hudDirectory=$null;$producerIdentity=$null;$patchFile=$null;$traceHash=$null
$hostBudgetSession=$null;$hostBudgetEvidence=$null
$traceReader=[pscustomobject]@{Path=$null;Stream=$null;Bytes=[byte[]]::new(0)}
function Get-CoupledExtensionHudArguments([string]$ScriptDirectory,[string]$Patch,[string]$Trace,[string]$Evidence,[switch]$DelayHandoff){
    $childArguments=@('-NoProfile','-File',(Join-Path $ScriptDirectory 'Start-HudStreamLab.ps1'),'-Standalone','-GroundExtensionCoupled',
        '-GroundExtensionFile',$Patch,'-MovementTraceFile',$Trace,'-EvidenceDirectory',$Evidence)
    if($DelayHandoff){$childArguments+='-GroundExtensionDelayFixture'}
    return $childArguments
}
function Flush-Probe {
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
}
function Send-FreshPose($Frame,$Target) {
    Assert-MineComeProbeContext $context
    # Recheck freshness after the endpoint ownership query, directly before
    # dispatch. The game-owned follower enforces its own short input lease.
    $age=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-[long]$Frame.utc_ms
    $observationAgeMs=[Math]::Max([long]0,$age)+[long]$Frame.server_age_ns/1000000.0
    if($age -lt -50 -or $observationAgeMs -gt 300) { return $false }
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $x=([double]$Target.x).ToString('R',$culture);$y=([double]$Target.y).ToString('R',$culture);$z=([double]$Target.z).ToString('R',$culture)
    $apply="MineCome.ApplyMovementFollower('$($probe.Run)',$([long]$Frame.seq),$x,$y,$z)"
    $areaArgument=",'extension'"
    $begin="MineCome.BeginMovementFollower('$($probe.Run)'$areaArgument)"
    $command=if($followerStarted){"#$apply"}else{"#if $begin then $apply end"}
    if(-not $followerStarted){
        # Read the same actor immediately before Begin in the same request.
        # Startup cannot silently move the captured terrain under a new origin.
        $cx=([double]$receiver.Center.x).ToString('R',$culture)
        $cy=([double]$receiver.Center.y).ToString('R',$culture)
        $cz=([double]$receiver.Center.z).ToString('R',$culture)
        $command="#local p=player and player:GetWorldPos(); if p and (p.x-($cx))^2+(p.y-($cy))^2+(p.z-($cz))^2<=0.01 then if $begin then $apply end end"
    }
    # A timeout can follow a dispatched Begin. Always request guarded cleanup
    # after that uncertain outcome; actual begin remains a receipt-only claim.
    $script:followerStarted=$true
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds 150 | Out-Null
    $forwarded.Add([pscustomobject]@{TraceSeq=[long]$Frame.seq;ServerSeq=[long]$Frame.server_seq;Phase=$Frame.phase;UtcMs=[long]$Frame.utc_ms;Target=$Target;DispatchedUtc=[DateTime]::UtcNow})
    return $true
}
try {
    $probe=New-MineComeProbeRun $context 'coupled-ground-extension' (Join-Path $context.ProjectRoot 'kcd2/probes/movement_probe.lua') 'BeginMovementFollower'
    Invoke-MineComeProbeConsole $context ("#MineCome.ProbeMovementCapabilities('$($probe.Run)')")
    Flush-Probe
    $capabilityDeadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $found=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementCapabilities' $probe.Run)
        if($found.Count -eq 1){$capabilities=$found[0];break}
        Start-Sleep -Milliseconds 30
    } while([DateTime]::UtcNow -lt $capabilityDeadline)
    if(-not $capabilities -or $capabilities.identity_stable -ne $true -or $capabilities.linked_kind -notin @('nil','number_zero')) { throw 'No verified stationary actor/no-link capability contract.' }
    $capabilities | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'capabilities.json')
    Invoke-MineComeProbeConsole $context ("#MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$($capabilities.linked_kind)')")
    Flush-Probe
    $contractDeadline=[DateTime]::UtcNow.AddSeconds(4);$noLinkVerified=$false
    do {
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $contract=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementContract' $probe.Run)
        $noLinkVerified=@($contract|Where-Object result -eq 'verified').Count -eq 1
        if($noLinkVerified){break};Start-Sleep -Milliseconds 30
    } while([DateTime]::UtcNow -lt $contractDeadline)
    if(-not $noLinkVerified){throw 'The actual actor no-link contract did not acknowledge; no Minecraft launch attempted.'}
    
        $captureOutput=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundExtension.ps1'))
        $capture=@($captureOutput | Where-Object { $_ -isnot [string] -and $_.PSObject.Properties['GroundExtensionFile'] })
        if($capture.Count -ne 1){throw 'One complete live KCD extension is required.'}
        $patchFile=$capture[0].GroundExtensionFile
        $livePatch=Read-HudLiveGroundExtension $patchFile $context.ProjectRoot $context
    
    $traceFile=Join-Path $probe.Directory 'movement.ndjson'
    $traceReader.Path=$traceFile
    $minimumUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $receiver=$null
    $powerShell=Join-Path $PSHOME 'pwsh.exe'
    $powerShell=(Resolve-Path -LiteralPath $powerShell).Path
    $helperLog=Join-Path $probe.Directory 'minecraft-helper.log';$helperError=Join-Path $probe.Directory 'minecraft-helper-errors.log'
    
        $hudDirectory=Join-Path $probe.Directory 'hud-stream'
        [void](Resolve-HudMovementEvidencePath $hudDirectory $context.ProjectRoot)
        $arguments=Get-CoupledExtensionHudArguments $PSScriptRoot $patchFile $traceFile $hudDirectory -DelayHandoff:$DelayHandoff

        $hostBudgetSession=New-MineComeHudGpuBudget $context
        Start-MineComeHudGpuBudget $hostBudgetSession
    
    # Use Windows argv quoting, not shell interpolation. File redirection also
    # preserves diagnostics if the owned helper outlives a controller failure.
    $quotedArguments=@($arguments | ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
    $helper=Start-Process -FilePath $powerShell -ArgumentList ([string]::Join(' ',$quotedArguments)) -WorkingDirectory $context.ProjectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $helperLog -RedirectStandardError $helperError
    $helperStarted=$helper.StartTime.ToUniversalTime()
    $helperStartFileTime=$helperStarted.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
    $helperHash=(Get-FileHash -LiteralPath $powerShell -Algorithm SHA256).Hash
    Write-Output "COUPLED_EXTENSION_WAITING run=$($probe.Run) helperPid=$($helper.Id)"
    $deadline=[DateTime]::UtcNow.AddSeconds(150);$lineCount=0;$traceEnded=$false
    do {
        $current=Get-Process -Id $context.GamePid -ErrorAction Stop
        try{if($current.Path -ne $context.GamePath -or $current.StartTime.ToUniversalTime() -ne $context.GameStartedUtc) { throw 'Captured KCD process identity changed.' }}finally{$current.Dispose()}
        if(-not $hudReady){
            $readyPath=Join-Path $hudDirectory 'capture/stream-ready.json'
            if(Test-Path -LiteralPath $readyPath){
                [void](Resolve-HudMovementEvidencePath $readyPath $context.ProjectRoot)
                $hudReady=Read-HudMovementJson $readyPath
                Assert-CoupledExtensionHudReady $hudReady $helper.Id $helperStartFileTime $minimumUtcMs -DelayHandoff:$DelayHandoff
                if($hudReady.expires_utc_ms -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()){throw 'HUD readiness already expired.'}
                $producer=Get-Process -Id $hudReady.producer_pid -ErrorAction Stop
                try{
                    if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne [string]$hudReady.producer_start_filetime -or
                        [IO.Path]::GetFileName($producer.Path) -ine 'java.exe'){throw 'HUD producer identity differs from readiness.'}
                    $producerIdentity=[pscustomobject]@{Pid=$producer.Id;Path=$producer.Path;StartedUtc=$producer.StartTime.ToUniversalTime()}
                }finally{$producer.Dispose()}
                $hudReadyHash=(Get-FileHash -LiteralPath $readyPath).Hash
                $receiver=New-MineComeTraceReceiver $patchFile $minimumUtcMs -ExpectedHudSave $hudReady.save -ExtensionWalking -Extension $livePatch
                if($receiver.PatchHash -cne $livePatch.Hash){throw 'Captured terrain changed before HUD trace binding.'}
            }else{
                if($helper.HasExited){throw 'Owned HUD helper exited before exact save readiness.'}
                Start-Sleep -Milliseconds 20;continue
            }
        }
        
            $producer=Get-Process -Id $producerIdentity.Pid -ErrorAction Stop
            try{if($producer.Path -ine $producerIdentity.Path -or $producer.StartTime.ToUniversalTime() -ne $producerIdentity.StartedUtc){throw 'HUD producer process changed during movement.'}}finally{$producer.Dispose()}
        
        $lines=@(Read-CoupledExtensionTraceLines $traceReader)
        if($lines.Count -lt $lineCount) { throw 'Movement trace was replaced/truncated.' }
        $candidate=$null
        for($index=$lineCount;$index -lt $lines.Count;$index++) {
            $received=Receive-MineComeMovementTrace $receiver $lines[$index] ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $accepted.Add($received)
            if($received.Kind -eq 'sample') { $candidate=$received }
            elseif($received.Kind -eq 'end') {
                $traceEnded=$true;$tracePassed=$received.Record.result -eq 'passed'
            }
        }
        $lineCount=$lines.Count
        if($candidate -and -not $traceEnded) { Send-FreshPose $candidate.Record $candidate.Target | Out-Null }
        if($traceEnded -and $followerStarted) { Invoke-MineComeProbeConsole $context ("#MineCome.EndMovementFollower('$($probe.Run)')") }
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $receipts=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementFollower' $probe.Run)
        $terminal=@($receipts | Where-Object { $_.terminal -eq $true })
        if($terminal.Count -and -not $traceEnded) { throw 'The game-owned follower ended before the Minecraft trace; inspect its lease/state receipts.' }
        if($traceEnded){break}
        if($helper.HasExited){throw 'Owned Minecraft helper exited before a complete trace end.'}
        Start-Sleep -Milliseconds 20
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $traceEnded -or -not $tracePassed){throw 'No successful fresh Minecraft movement trace termination.'}
    $restoreDeadline=[DateTime]::UtcNow.AddSeconds(3)
    do {
        Start-Sleep -Milliseconds 150;Flush-Probe
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $receipts=@(Get-MineComeProbeReceipts $fresh 'MineComeMovementFollower' $probe.Run)
        $restored=@($receipts | Where-Object { $_.event -eq 'restored' -and $_.result -eq 'restored' -and $_.terminal -eq $true -and $_.readback -eq $true -and $_.timers_cancelled -eq $true -and $_.end_result -eq 'explicit_end' -and $null -ne $_.follow_error -and $_.follow_error -le 0.15 }).Count -eq 1
        if($restored){break}
    } while([DateTime]::UtcNow -lt $restoreDeadline)
    if(-not $restored){throw 'The exact KCD player/camera follower restoration was not verified.'}
    [void](Assert-CoupledExtensionFollowerProof $receipts $forwarded.ToArray() $probe.Run $receiver.Center)
    $applied=@($receipts | Where-Object { $_.event -eq 'applied' -and $_.readback -eq $true -and $null -ne $_.follow_error -and $_.follow_error -le 0.15 })
    if($applied.Count -lt 3){throw 'Insufficient delayed KCD player/camera readbacks from real server samples.'}
    $phases=@($forwarded | Where-Object { $_.TraceSeq -in @($applied.seq) } | ForEach-Object Phase | Sort-Object -Unique)
    if('WALKING' -notin $phases) { throw 'Required movement phases were not reflected in KCD receipts.' }
    $xRange=($applied.target.x | Measure-Object -Minimum -Maximum);$zRange=($applied.target.z | Measure-Object -Minimum -Maximum)
    if($xRange.Maximum-$xRange.Minimum -lt 0.3) { throw 'KCD receipts did not reflect sufficient real movement displacement.' }
    $finishDeadline=[DateTime]::UtcNow.AddSeconds(130)
    while(-not $helper.HasExited -and [DateTime]::UtcNow -lt $finishDeadline){Start-Sleep -Milliseconds 100}
    if(-not $helper.HasExited){throw 'Owned Minecraft helper normal shutdown remained pending; no game process was stopped.'}
    $helper.WaitForExit();$log=Get-Content -LiteralPath $helperLog -Raw
    
        $verificationPath=Join-Path $hudDirectory 'verification.json'
        $hudVerification=Read-HudMovementJson $verificationPath
        $guest=Read-HudMovementJson (Join-Path $hudDirectory 'capture/stream-result.json')
        if((Get-FileHash -LiteralPath $readyPath).Hash -cne $hudReadyHash -or (Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant() -cne $receiver.PatchHash){
            throw 'Readiness or captured patch changed during the bounded run.'
        }
        $finalLines=@(Read-CoupledExtensionTraceLines $traceReader)
        if($finalLines.Count -ne $lineCount -or $traceReader.Bytes.Length -eq 0 -or $traceReader.Bytes[-1] -ne 10){
            throw 'Movement trace appended after its end or retained an incomplete tail.'
        }
        $hudProof=Assert-CoupledExtensionHudCompletion $hudVerification $hudReady $guest $receiver $traceFile $helper.Id $helperStartFileTime $helperHash -DelayHandoff:$DelayHandoff
        $hudVerificationHash=(Get-FileHash -LiteralPath $verificationPath).Hash
        $traceHash=(Get-FileHash -LiteralPath $traceFile).Hash
        $minecraftPassed=$helper.ExitCode -eq 0 -and $log -match ('(?m)^HUD_STREAM_VERIFIED run='+$hudReady.run+' ')
        Stop-MineComeHudGpuBudget $hostBudgetSession
        $hostBudgetEvidence=Get-MineComeHudGpuBudgetEvidence $hostBudgetSession
        if(-not $hostBudgetSession.BudgetValid -or -not $hostBudgetSession.RestorationVerified -or $hostBudgetSession.Failure){
            throw 'HUD host GPU budget completion and restoration were not verified.'
        }
    
    $coupledPassed=$minecraftPassed -and $tracePassed -and $restored
    if(-not $coupledPassed){throw 'Minecraft did not complete its independent movement proof and normal shutdown.'}
    Write-Output "COUPLED_EXTENSION_PASS realServerFrames=$($forwarded.Count) delayedKcdReceipts=$($applied.Count) restored=true. Evidence: $($probe.Directory)"
} catch { $failure=$_.Exception.Message;throw }
finally {
    if($probe) {
        $cleanupConfirmed=$restored
        if($followerStarted -and -not $restored) {
            try {
                Invoke-MineComeProbeConsole $context ("#MineCome.EndMovementFollower('$($probe.Run)')")
                $cleanupDeadline=[DateTime]::UtcNow.AddSeconds(4)
                do {
                    Start-Sleep -Milliseconds 100;Flush-Probe
                    $cleanupText=Read-MineComeProbeLog $context $probe.Offset
                    $cleanup=@(Get-MineComeProbeReceipts $cleanupText 'MineComeMovementFollower' $probe.Run)
                    $cleanupConfirmed=@($cleanup | Where-Object { $_.event -eq 'restored' -and $_.result -eq 'restored' -and $_.terminal -eq $true -and $_.readback -eq $true -and $_.timers_cancelled -eq $true }).Count -eq 1
                    if($cleanupConfirmed -or @($cleanup | Where-Object { $_.terminal -eq $true -and $_.event -eq 'restore_failed' }).Count){break}
                } while([DateTime]::UtcNow -lt $cleanupDeadline)
            } catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'cancel-error.txt') }
        }
        if($hostBudgetSession -and -not $hostBudgetSession.StopAttempted){
            try{Stop-MineComeHudGpuBudget $hostBudgetSession}catch{if(-not $failure){$failure=$_.Exception.Message};$coupledPassed=$false}
            $hostBudgetEvidence=Get-MineComeHudGpuBudgetEvidence $hostBudgetSession
            if(-not $hostBudgetSession.BudgetValid -or -not $hostBudgetSession.RestorationVerified){$coupledPassed=$false}
        }
        ConvertTo-Json -InputObject $forwarded.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'forwarded.json')
        ConvertTo-Json -InputObject $accepted.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'trace-receipts.json')
        try { $fresh=Read-MineComeProbeLog $context $probe.Offset;$fresh|Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log');@((Get-MineComeProbeReceipts $fresh 'MineComeMovementFollower' $probe.Run))|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') } catch { $_.Exception.Message|Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt') }
        $verification=[ordered]@{Kind='Bounded real Minecraft server to KCD player/camera follower';Run=$probe.Run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameStartedUtc=$context.GameStartedUtc;GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FreshLogOffset=$probe.Offset;FunctionReloadVerified=$probe.FunctionReloadVerified;HelperPid=$(if($helper){$helper.Id}else{$null});HelperStartedUtc=$helperStarted;ForwardedFrames=$forwarded.Count;FollowerStartRequested=$followerStarted;FollowerStarted=(@($receipts | Where-Object { $_.event -eq 'begin' -and $_.result -eq 'awaiting_first_pose' }).Count -eq 1);RestorationVerified=$restored;CleanupConfirmed=$cleanupConfirmed;TracePass=$tracePassed;MinecraftPass=$minecraftPassed;CoupledMovementPass=$coupledPassed;HudWorld=$true;HudReady=$hudReady;HudReadySha256=$hudReadyHash;HudVerificationFile=$(if($hudDirectory){Join-Path $hudDirectory 'verification.json'}else{$null});HudVerificationSha256=$hudVerificationHash;HudGroundProof=$hudProof;HostGpuBudget=$hostBudgetEvidence;GroundPatchFile=$patchFile;TraceSha256=$traceHash;KcdHudCompositingVerified=$false;KcdKeyboardForwardingVerified=$false;FullWorldMovementAuthorityVerified=$false;Failure=$failure}
        $verification.walking_area='extension';$verification.ground_extension_coupled=$true;$verification.delay_handoff=[bool]$DelayHandoff
        $verification | ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
    if($traceReader.Stream){$traceReader.Stream.Dispose()}
    if($helper){$helper.Dispose()}
}
