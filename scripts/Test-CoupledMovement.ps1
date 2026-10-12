#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded real-server-pose follower; does not launch/stop KCD2 or capture its keys.
[CmdletBinding()]
param([switch]$PreflightOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly) { Write-Output 'Coupled-movement exact tools preflight passed; no game changes made.';return }
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$helper=$null;$failure=$null;$followerStarted=$false;$restored=$false;$tracePassed=$false;$minecraftPassed=$false;$coupledPassed=$false
$forwarded=[Collections.Generic.List[object]]::new();$accepted=[Collections.Generic.List[object]]::new()
$receipts=@();$capabilities=$null;$helperStarted=$null
function Flush-Probe {
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
}
function Read-TraceLines([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path)) { return @() }
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $length=$stream.Length
        if($length -gt 65536) { throw 'Movement trace exceeded64KiB.' }
        $bytes=[byte[]]::new([int]$length);$read=0
        while($read -lt $bytes.Length) {
            $n=$stream.Read($bytes,$read,$bytes.Length-$read)
            if($n -eq 0) { throw 'Movement trace was truncated during read.' };$read+=$n
        }
        $last=$bytes.Length-1
        while($last -ge 0 -and $bytes[$last] -ne 10) { $last-- }
        if($last -lt 0){return @()}
        $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes,0,$last+1)
        @($text.Split([char]10) | Where-Object { $_.Length -gt 0 })
    } finally { $stream.Dispose() }
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
    $command=if($followerStarted){"#$apply"}else{"#if MineCome.BeginMovementFollower('$($probe.Run)') then $apply end"}
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds 150 | Out-Null
    $script:followerStarted=$true
    $forwarded.Add([pscustomobject]@{TraceSeq=[long]$Frame.seq;ServerSeq=[long]$Frame.server_seq;Phase=$Frame.phase;UtcMs=[long]$Frame.utc_ms;Target=$Target;DispatchedUtc=[DateTime]::UtcNow})
    return $true
}
try {
    $probe=New-MineComeProbeRun $context 'coupled-movement' (Join-Path $context.ProjectRoot 'kcd2/probes/movement_probe.lua') 'BeginMovementFollower'
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
    $captureOutput=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch)
    $capture=@($captureOutput | Where-Object { $_ -isnot [string] -and $_.GroundPatchFile })
    if($capture.Count -ne 1){throw 'One complete live KCD ground patch is required.'}
    $patchFile=$capture[0].GroundPatchFile
    $traceFile=Join-Path $probe.Directory 'movement.ndjson'
    $minimumUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $receiver=New-MineComeTraceReceiver $patchFile $minimumUtcMs
    $powerShell=Join-Path $PSHOME 'pwsh.exe'
    $powerShell=(Resolve-Path -LiteralPath $powerShell).Path
    $starter=Join-Path $PSScriptRoot 'Start-GroundMovementLab.ps1'
    $helperLog=Join-Path $probe.Directory 'minecraft-helper.log';$helperError=Join-Path $probe.Directory 'minecraft-helper-errors.log'
    $arguments=@('-NoProfile','-File',('"'+$starter+'"'),'-PatchFile',('"'+$patchFile+'"'),'-TraceFile',('"'+$traceFile+'"'))
    $helper=Start-Process -FilePath $powerShell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $helperLog -RedirectStandardError $helperError
    $helperStarted=$helper.StartTime.ToUniversalTime()
    Write-Output "COUPLED_MOVEMENT_WAITING run=$($probe.Run) helperPid=$($helper.Id)"
    $deadline=[DateTime]::UtcNow.AddSeconds(150);$lineCount=0;$traceEnded=$false
    do {
        $current=Get-Process -Id $context.GamePid -ErrorAction Stop
        if($current.Path -ne $context.GamePath -or $current.StartTime.ToUniversalTime() -ne $context.GameStartedUtc) { throw 'Captured KCD process identity changed.' }
        $lines=@(Read-TraceLines $traceFile)
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
    $applied=@($receipts | Where-Object { $_.event -eq 'applied' -and $_.readback -eq $true -and $null -ne $_.follow_error -and $_.follow_error -le 0.15 })
    if($applied.Count -lt 3){throw 'Insufficient delayed KCD player/camera readbacks from real server samples.'}
    $phases=@($forwarded | Where-Object { $_.TraceSeq -in @($applied.seq) } | ForEach-Object Phase | Sort-Object -Unique)
    if('WALKING' -notin $phases -or ('JUMPING' -notin $phases -and 'LANDING' -notin $phases)) { throw 'Walking and airborne trace phases were not both reflected in KCD receipts.' }
    $xRange=($applied.target.x | Measure-Object -Minimum -Maximum);$zRange=($applied.target.z | Measure-Object -Minimum -Maximum)
    if($xRange.Maximum-$xRange.Minimum -lt 0.3 -or $zRange.Maximum-$zRange.Minimum -lt 0.5) { throw 'KCD receipts did not reflect sufficient real walking and vertical jumping displacement.' }
    $finishDeadline=[DateTime]::UtcNow.AddSeconds(130)
    while(-not $helper.HasExited -and [DateTime]::UtcNow -lt $finishDeadline){Start-Sleep -Milliseconds 100}
    if(-not $helper.HasExited){throw 'Owned Minecraft helper normal shutdown remained pending; no game process was stopped.'}
    $helper.WaitForExit();$log=Get-Content -LiteralPath $helperLog -Raw
    $minecraftPassed=$helper.ExitCode -eq 0 -and $log -match 'GROUND_MOVEMENT_LAB_PASS' -and $log -notmatch 'GROUND_MOVEMENT_LAB_FAIL'
    $coupledPassed=$minecraftPassed -and $tracePassed -and $restored
    if(-not $coupledPassed){throw 'Minecraft did not complete its independent movement proof and normal shutdown.'}
    Write-Output "COUPLED_MOVEMENT_PASS realServerFrames=$($forwarded.Count) delayedKcdReceipts=$($applied.Count) restored=true. Evidence: $($probe.Directory)"
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
        ConvertTo-Json -InputObject $forwarded.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'forwarded.json')
        ConvertTo-Json -InputObject $accepted.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'trace-receipts.json')
        try { $fresh=Read-MineComeProbeLog $context $probe.Offset;$fresh|Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log');@((Get-MineComeProbeReceipts $fresh 'MineComeMovementFollower' $probe.Run))|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') } catch { $_.Exception.Message|Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt') }
        [pscustomobject]@{Kind='Bounded real Minecraft server to KCD player/camera follower';Run=$probe.Run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameStartedUtc=$context.GameStartedUtc;GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash;FreshLogOffset=$probe.Offset;FunctionReloadVerified=$probe.FunctionReloadVerified;HelperPid=$(if($helper){$helper.Id}else{$null});HelperStartedUtc=$helperStarted;ForwardedFrames=$forwarded.Count;FollowerStartRequested=$followerStarted;FollowerStarted=(@($receipts | Where-Object { $_.event -eq 'begin' -and $_.result -eq 'awaiting_first_pose' }).Count -eq 1);RestorationVerified=$restored;CleanupConfirmed=$cleanupConfirmed;TracePass=$tracePassed;MinecraftPass=$minecraftPassed;CoupledMovementPass=$coupledPassed;KcdKeyboardForwardingVerified=$false;FullWorldMovementAuthorityVerified=$false;Failure=$failure}|
            ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
