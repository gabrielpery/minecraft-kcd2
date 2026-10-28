#Requires -Version 7.3
# Explicit combined15-second movement/aiming session and30-second HUD.
[CmdletBinding()]
param([switch]$PreflightOnly,[string]$JavaHome,[string]$BundleDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
. (Join-Path $PSScriptRoot 'HudBufferedMovement.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'HudCameraDelivery.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
. (Join-Path $PSScriptRoot 'CoupledMovementProof.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingAimed.ps1')
. (Join-Path $PSScriptRoot 'HudAimedRelay.ps1')
$ExtendedWalking=$true
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$walkingSession=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
if(-not $JavaHome){$JavaHome='C:\Program Files\Java\jdk-24'}
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))){throw 'A local supported JDK is required.'}
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor-walking-aimed'}
$context=Get-MineComeProbeContext
& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -WalkingAimed -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -PreflightOnly
if($PreflightOnly){Write-Output 'HUD_WALKING_AIMED_PREFLIGHT_PASS no_changes=true';return}
$probe=$null;$helper=$null;$arm=$null;$budget=$null;$budgetEvidence=$null;$failure=$null
$followerStarted=$false;$restored=$false;$passed=$false;$traceEnded=$false;$tracePassed=$false
$followerFinishRequested=$false;$sourceClock=New-HudBufferedSourceState -ExtendedWalking:$ExtendedWalking
$ready=$null;$readyHash=$null;$guest=$null;$producerIdentity=$null;$receiver=$null;$physicalReady=$null
$run=[Guid]::NewGuid().ToString('N');$camera=$null;$cameraState=$null
$forwarded=[Collections.Generic.List[object]]::new()
$traceValidationTimings=[Collections.Generic.List[object]]::new();$parserWarmup=$null
$traceReader=[pscustomobject]@{Path=$null;Stream=$null;Bytes=[byte[]]::new(0)}
$lineCount=0;$lastRestoreFlush=0L
$receipts=@();$applied=@();$traceHash=$null
$receiptCursor=$null
$aimRelay=$null;$aimState=$null;$aimClicks=$null;$aimReadyHash=$null;$aimClosedHash=$null
$aimRelayEvidence=$null;$aimClickEvidence=$null;$aimCleanupBeforeRestore=$false;$aimCleanupUtcMs=0L;$finishRequestUtcMs=0L
function Read-Receipts([string]$Tag){
    return @(Read-HudWalkingReceipts $script:receiptCursor $Tag)
}
function Console([string]$Code){
    # CryLog finalizes the previous line when another record arrives. The
    # marker makes a completed receipt readable without accepting a partial tail.
    Invoke-MineComeProbeConsole $context ('#'+$Code+"; System.LogAlways('[MineComeHudWalkingFlush] $($probe.Run)')")
}
function Get-CurrentAimDecline([long]$NowUtcMs){
    if(-not $aimState){return 'aim_not_initialized'}
    if(-not(Test-Path -LiteralPath $viewFile)){return 'host_view_unavailable'}
    $view=Read-HudMovementJson $viewFile
    $views=@(Read-Receipts 'MineComeHudPhysicalView' | Where-Object seq -EQ $view.seq)
    if($views.Count -gt 1){throw 'Duplicate native camera sequence.'}
    $nativeView=if($views.Count){$views[0]}else{$null}
    Get-HudWalkingAimedDecline $aimState $view $nativeView $NowUtcMs
}
function Send-Pose($Sample,[long]$ReceivedUtcMs,[double]$ValidationMs){
    $preparation=[Diagnostics.Stopwatch]::StartNew()
    Assert-MineComeProbeContext $context
    $frame=$Sample.Record;$target=$Sample.Target
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $x=([double]$target.x).ToString('R',$culture);$y=([double]$target.y).ToString('R',$culture);$z=([double]$target.z).ToString('R',$culture)
    $sourcePreciseMs=Get-HudBufferedSourceTime -State $sourceClock -Record $frame
    $sourceMs=[double][single]$sourcePreciseMs
    $sourceText=([double]$sourceMs).ToString('R',$culture)
    $apply="MineCome.ApplyBufferedMovementFollower('$($probe.Run)',$($frame.seq),$x,$y,$z,$sourceText)"
    $code=$apply
    if(-not $script:followerStarted){
        $cx=([double]$receiver.Center.x).ToString('R',$culture);$cy=([double]$receiver.Center.y).ToString('R',$culture);$cz=([double]$receiver.Center.z).ToString('R',$culture)
        $code="local p=player and player:GetWorldPos(); if p and (p.x-($cx))^2+(p.y-($cy))^2+(p.z-($cz))^2<=0.01 then if MineCome.$($walkingSession.BeginFunction)('$($probe.Run)') then $apply end end"
    }
    $requestPath='/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString('#'+$code)
    $dispatchUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $age=$dispatchUtc-[long]$frame.utc_ms
    if($age -lt -50 -or [Math]::Max(0,$age)+$frame.server_age_ns/1000000.0 -gt 300){throw 'A buffered source point expired before dispatch.'}
    $preparationMs=$preparation.Elapsed.TotalMilliseconds
    $script:followerStarted=$true
    $request=[Diagnostics.Stopwatch]::StartNew()
    Invoke-MineComeToolsRequest -PathAndQuery $requestPath -TimeoutMilliseconds 150 | Out-Null
    $requestMs=$request.Elapsed.TotalMilliseconds
    # Keep timing diagnostics in memory until cleanup; no extra per-pose file IO
    # or claims that a successful HTTP response proves native application.
    $forwarded.Add([pscustomobject]@{TraceSeq=[long]$frame.seq;ServerSeq=[long]$frame.server_seq;Phase=$frame.phase;UtcMs=[long]$frame.utc_ms;SourceMs=$sourceMs;SourcePreciseMs=$sourcePreciseMs;Target=$target;
        ReceivedUtcMs=$ReceivedUtcMs;ValidationMs=$ValidationMs;PreparationMs=$preparationMs;
        DispatchUtcMs=$dispatchUtc;RequestMs=$requestMs;SourceAgeAtDispatchMs=[Math]::Max(0,$age)+$frame.server_age_ns/1000000.0})
    Add-HudWalkingAimedSample $aimState $Sample $sourcePreciseMs
}
try{
    $probe=New-MineComeProbeRun $context 'hud-walking-aimed' (Join-Path $root 'kcd2/probes/movement_probe.lua') $walkingSession.BeginFunction
    $receiptCursor=New-HudWalkingReceiptCursor $context.GameLog $probe.Offset $probe.Run -KeepOpen
    Console "MineCome.ProbeMovementCapabilities('$($probe.Run)')"
    $until=[DateTime]::UtcNow.AddSeconds(4);$cap=$null
    do{
        $values=@(Read-Receipts 'MineComeMovementCapabilities')
        if($values.Count -eq 1){$cap=$values[0];break}
        Start-Sleep -Milliseconds 30
    }while([DateTime]::UtcNow -lt $until)
    if(-not $cap -or $cap.identity_stable -ne $true -or $cap.linked_kind -notin @('nil','number_zero')){throw 'No verified stationary actor/no-link contract.'}
    Console "MineCome.VerifyMovementNoLinkContract('$($probe.Run)','$($cap.linked_kind)')"
    $until=[DateTime]::UtcNow.AddSeconds(4)
    do{
        $contract=@(Read-Receipts 'MineComeMovementContract' | Where-Object result -EQ 'verified')
        if($contract.Count -eq 1){break};Start-Sleep -Milliseconds 30
    }while([DateTime]::UtcNow -lt $until)
    if($contract.Count -ne 1){throw 'No-link contract was not acknowledged.'}
    $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch | Where-Object {$_ -isnot [string] -and $_.GroundPatchFile})
    if($capture.Count -ne 1){throw 'One fresh live terrain capture is required.'}
    $patchFile=$capture[0].GroundPatchFile
    $livePatch=Read-HudLiveGroundPatch $patchFile $root $context
    $directory=$probe.Directory
    $traceReader.Path=Join-Path $directory 'movement.ndjson'
    $viewFile=Join-Path $directory 'host-view.json'
    $readyPath=Join-Path $directory 'capture/stream-ready.json';$resultPath=Join-Path $directory 'capture/stream-result.json'
    $minimumUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$expires=$minimumUtc+180000
    $budget=New-MineComeHudGpuBudget $context
    Start-MineComeHudGpuBudget $budget
    $deadline=[DateTime]::UtcNow.AddSeconds(112)
    $camera=Start-HudCameraDelivery -Context $context -Probe $probe -Run $run -LivePatch $livePatch -ViewFile $viewFile -ProjectRoot $root
    $initialViewDeadline=[DateTime]::UtcNow.AddSeconds(2)
    do{
        $cameraState=Get-HudCameraDeliveryState $camera
        if($cameraState.Failure){throw $cameraState.Failure}
        if($cameraState.Stopped){throw 'Camera delivery stopped before initial readiness.'}
        if($cameraState.ViewCount -gt 0){break}
        Start-Sleep -Milliseconds 10
    }while([DateTime]::UtcNow -lt $initialViewDeadline)
    if($cameraState.ViewCount -lt 1){throw 'Initial fresh camera view did not acknowledge.'}
    $aimState=New-HudWalkingAimedAdmission $run $probe.Run $livePatch $context
    $aimRelay=New-MineComeHudAimedRelay $context $directory $run $expires -ExternalPhysicalPoseRun $probe.Run
    Start-MineComeHudAimedRelay $aimRelay
    $aimClicks=New-MineComeHudWorldClicks $context (Join-Path ([IO.Path]::GetDirectoryName($context.GamePath)) 'ReShade.log') $run
    Initialize-HudWalkingAimedClicks $aimClicks $aimRelay
    $aimReadyPath=Join-Path $directory 'capture/walking-aim-ready.json'
    $aimClosedPath=Join-Path $directory 'capture/walking-aim-closed.json'
    $args=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,
        '-TargetPid',[string]$context.GamePid,'-TargetStart',$context.GameStartedUtc.ToFileTimeUtc().ToString(),
        '-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-InputMode','-LiveMouse','-OffscreenPresentation','-WalkingAimed',
        '-GroundPatchFile',$patchFile,'-MovementTraceFile',$traceReader.Path,'-HostViewFile',$viewFile,
        '-StoneTokenFile',$aimRelay.TokenFile,'-StonePort',[string]$aimRelay.Port)
    if($ExtendedWalking){$args+='-ExtendedWalking'}
    $quoted=@($args | ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
    $helper=Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'helper.log') -RedirectStandardError (Join-Path $directory 'helper-errors.log')
    Write-Output "HUD_WALKING_AIMED_START run=$run evidence=$directory"
    do{
        Assert-MineComeProbeContext $context
        if(-not $traceEnded){
            $cameraState=Get-HudCameraDeliveryState $camera
            if($cameraState.Failure){throw $cameraState.Failure}
            if($cameraState.Stopped){throw 'Camera delivery stopped before movement completed.'}
        }
        if(-not $ready -and (Test-Path -LiteralPath $readyPath)){
            $ready=Read-HudMovementJson $readyPath
            Assert-HudWalkingAimedProducer $ready
            Assert-HudWalkingSession $ready -ExtendedWalking:$ExtendedWalking
            if($ready.run -cne $run){throw 'Physical HUD producer run mismatch.'}
            # Exercise the cold parser with disposable diagnostic state before
            # arming input. Its synthetic records never enter the live receiver.
            $parserWarmup=Initialize-HudBufferedMovementPipeline -PatchFile $patchFile -ExpectedHudSave $ready.save -MinimumUtcMs $minimumUtc -ExtendedWalking:$ExtendedWalking
            $receiver=New-MineComeTraceReceiver $patchFile $minimumUtc -ExpectedHudSave $ready.save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking:$ExtendedWalking
            if($receiver.PatchHash -cne $livePatch.Hash){throw 'Live terrain changed before trace binding.'}
            $arm=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -WalkingAimed -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -ReadyManifest $readyPath
            $readyHash=(Get-FileHash -LiteralPath $readyPath).Hash
            $producerIdentity=[pscustomobject]@{Pid=$ready.producer_pid;Start=[string]$ready.producer_start_filetime}
            Write-Output "HUD_WALKING_AIMED_ARMED run=$run waiting_for_settled_guest=true"
        }
        $physicalReadyPath=Join-Path $directory 'capture/physical-ready.json'
        if($ready -and -not $physicalReady -and (Test-Path -LiteralPath $physicalReadyPath)){
            $physicalReady=Read-HudMovementJson $physicalReadyPath
            Assert-HudWalkingSession $physicalReady -ExtendedWalking:$ExtendedWalking
            if($physicalReady.schema -ne 1 -or $physicalReady.kind -cne 'minecome_hud_physical_ready_v1' -or
                $physicalReady.ready -isnot [bool] -or -not $physicalReady.ready -or $physicalReady.run -cne $run -or
                $physicalReady.save -cne $ready.save -or $physicalReady.patch_run -cne $receiver.ExpectedRun -or
                $physicalReady.patch_sha256 -cne $receiver.PatchHash -or $physicalReady.target_pid -ne $context.GamePid -or
                $physicalReady.target_start_filetime -cne $context.GameStartedUtc.ToFileTimeUtc().ToString() -or
                $physicalReady.utc_ms -lt $minimumUtc -or $physicalReady.utc_ms -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+50 -or
                $physicalReady.view_seq -lt 1 -or $physicalReady.view_seq -gt (Get-HudCameraDeliveryState $camera).Sequence){throw 'Actual physical guest readiness did not match the current session.'}
            $activationWindow=[int][Math]::Floor(($deadline-[DateTime]::UtcNow).TotalSeconds-35)
            if($activationWindow -lt 1){throw 'Not enough bounded time remains for the full physical HUD check.'}
            Write-Output "HUD_WALKING_AIMED_READY run=$run press_F8=true press_F8_within_seconds=$activationWindow movement_seconds=$($walkingSession.SourceMs/1000) input_seconds=$($walkingSession.InputMs/1000) movement_session=$($walkingSession.Name) hud_seconds=30"
        }
        if($receiver -and -not $traceEnded){
            $producer=Get-Process -Id $producerIdentity.Pid
            try{if($producer.ProcessName -cne 'java' -or $producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $producerIdentity.Start){throw 'HUD producer identity changed.'}}finally{$producer.Dispose()}
            $lines=@(Read-CoupledTraceLines $traceReader -ExtendedWalking:$ExtendedWalking)
            for($i=$lineCount;$i -lt $lines.Count;$i++){
                $receivedUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $validation=[Diagnostics.Stopwatch]::StartNew()
                $received=Receive-MineComeMovementTrace $receiver $lines[$i] $receivedUtc
                $validationMs=$validation.Elapsed.TotalMilliseconds
                $traceValidationTimings.Add([pscustomobject]@{TraceSeq=[long]$received.Record.seq;Kind=$received.Kind;ValidationStartedUtcMs=$receivedUtc;ValidationMs=$validationMs})
                # Every source waypoint matters to the playback timeline,
                # especially its initial stationary anchor. Do not coalesce it.
                if($received.Kind -ceq 'sample'){Send-Pose $received $receivedUtc $validationMs}
                elseif($received.Kind -ceq 'stale' -or ($received.Kind -ceq 'observe' -and $received.Record.kind -ceq 'sample')){
                    throw "Buffered playback refused source waypoint seq=$($received.Record.seq) phase=$($received.Record.phase) kind=$($received.Kind); no waypoint may be omitted."
                }
                elseif($received.Kind -ceq 'end'){$traceEnded=$true;$tracePassed=$received.Record.result -ceq 'passed'}
            }
            $lineCount=$lines.Count
        }
        if($traceEnded -and -not $tracePassed){throw 'Minecraft physical movement trace failed.'}
        if($receiver -and $receiver.Begun -and -not $aimState.Ready -and (Test-Path -LiteralPath $aimReadyPath)){
            Set-HudWalkingAimedReady $aimState (Read-HudMovementJson $aimReadyPath) $receiver $ready.save $minimumUtc ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $aimReadyHash=(Get-FileHash -LiteralPath $aimReadyPath).Hash
        }
        if($aimState.Ready -and -not $aimState.Closed -and (Test-Path -LiteralPath $aimClosedPath)){
            Set-HudWalkingAimedClosed $aimState (Read-HudMovementJson $aimClosedPath) $ready.save $minimumUtc ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            $aimClosedHash=(Get-FileHash -LiteralPath $aimClosedPath).Hash
            Request-MineComeHudAimedRelayStop $aimRelay
        }
        # Every edge is consumed once, including moving, stale or closing edges.
        # Re-read original source/view evidence immediately before dispatch too.
        if(-not $aimRelay.AsyncStopRequested){Invoke-HudWalkingAimedClicks $aimClicks $aimRelay {param($Now) Get-CurrentAimDecline $Now}}
        elseif(-not $aimRelay.AsyncStopVerified){
            if(Complete-MineComeHudAimedRelayStop $aimRelay){
                Assert-HudWalkingAimedCleanup $aimState $aimRelay $followerFinishRequested
                $aimCleanupBeforeRestore=$true;$aimCleanupUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            }
        }
        if($traceEnded -and $followerStarted -and -not $followerFinishRequested){
            if(-not $aimCleanupBeforeRestore){throw 'Aimed cleanup did not finish inside the reserved movement completion tail.'}
            # Seal the immutable source timeline. The game thread observes its
            # final point and restores immediately, independent of log polling.
            Console "MineCome.FinishBufferedMovementFollower('$($probe.Run)',$($forwarded[-1].TraceSeq))"
            $finishRequestUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $followerFinishRequested=$true
        }
        if($followerFinishRequested -and $camera){
                Request-HudCameraDeliveryStop $camera
                $cameraState=Stop-HudCameraDelivery $camera
                if($cameraState.ResourcesClosed){$camera=$null}
                if($cameraState.Failure -or -not $cameraState.Stopped -or -not $cameraState.ResourcesClosed){throw 'Camera delivery did not stop cleanly.'}
        }
        $receipts=@(Read-Receipts 'MineComeMovementFollower')
        $terminal=@($receipts | Where-Object terminal -EQ $true)
        if($followerFinishRequested -and -not $terminal.Count -and
            [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$lastRestoreFlush -ge 100){
            $lastRestoreFlush=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            Console "System.LogAlways('[MineComeHudRestoreFlush] $($probe.Run)')"
        }
        if($terminal.Count -and -not $traceEnded){throw 'KCD follower stopped before the guest trace ended.'}
        if(Test-Path -LiteralPath $resultPath){break}
        if($helper.HasExited){throw 'HUD helper exited without its completion receipt.'}
        Start-Sleep -Milliseconds 15
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not(Test-Path -LiteralPath $resultPath)){throw 'Bounded physical HUD session timed out.'}
    $guest=Read-HudMovementJson $resultPath
    Assert-HudWalkingAimedProducer $guest
    Assert-HudWalkingSession $guest -ExtendedWalking:$ExtendedWalking
    if($guest.run -cne $run -or $guest.save -cne $ready.save -or $guest.result -cne 'input_completed'){throw 'Actual HUD input session did not complete.'}
    if(-not $traceEnded -or -not $tracePassed -or -not $followerStarted){throw 'No completed real physical movement trace.'}
    if(-not $aimCleanupBeforeRestore -or -not $aimState.Closed -or $aimCleanupUtcMs -gt $finishRequestUtcMs){throw 'Combined cleanup ordering was not verified.'}
    Assert-MineComeHudAimedRelayGuest $aimRelay $guest
    Assert-HudWalkingAimedClicks $aimClicks $aimRelay
    if($guest.lab_evidence.stone_bridge.confirmed_network_actions -lt 1){throw 'Combined session did not confirm an aimed interaction.'}
    if((Get-FileHash -LiteralPath $aimReadyPath).Hash -cne $aimReadyHash -or (Get-FileHash -LiteralPath $aimClosedPath).Hash -cne $aimClosedHash){throw 'Combined alignment or closure receipt changed.'}
    $receipts=@(Read-Receipts 'MineComeMovementFollower')
    Assert-HudWalkingFollowerSession $receipts -ExtendedWalking:$ExtendedWalking
    $restored=@($receipts | Where-Object {$_.event -ceq 'restored' -and $_.result -ceq 'restored' -and $_.physical_movement -eq $true -and $_.camera_basis_valid -eq $true -and $_.terminal -eq $true -and $_.timers_cancelled -eq $true -and $_.readback -eq $true -and $_.end_result -ceq 'explicit_end' -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15}).Count -eq 1
    if(-not $restored){throw 'Physical KCD follower restoration was not verified.'}
    $applied=@($receipts | Where-Object {$_.event -ceq 'applied' -and $_.physical_movement -eq $true -and $_.readback -eq $true -and $_.camera_basis_valid -eq $true -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15})
    if($applied.Count -lt 3){throw 'Too few actual delayed KCD movement readbacks.'}
    $playbackEpoch=$null;$lastCrossed=0;$crossedPoints=0;$previousSourceIndex=-1
    foreach($receipt in $applied){
        $proof=Assert-HudBufferedMovementReceipt -Receipt $receipt -Forwarded $forwarded -ExtendedWalking:$ExtendedWalking
        if(($null -ne $playbackEpoch -and $proof.EpochEngineSeconds -ne $playbackEpoch) -or $proof.CrossedSourceSeq -le $lastCrossed){throw 'Buffered playback changed epoch or replayed a source point.'}
        if($proof.SourcePointsCrossed -ne $proof.SourceIndex-$previousSourceIndex){throw 'Buffered source crossing count differs from actual progress.'}
        $previousSourceIndex=$proof.SourceIndex
        $playbackEpoch=$proof.EpochEngineSeconds;$lastCrossed=$proof.CrossedSourceSeq
        $crossedPoints+=$receipt.source_points_crossed
    }
    if($lastCrossed -ne $forwarded[-1].TraceSeq -or $crossedPoints -ne $forwarded.Count){throw 'Buffered playback did not drain all forwarded source points.'}
    $movement=$guest.lab_evidence.physical_movement
    Assert-HudWalkingSession $movement -ExtendedWalking:$ExtendedWalking
    Assert-HudWalkingDuration $movement -ExtendedWalking:$ExtendedWalking
    foreach($field in @('completed','trace_closed','controls_released','client_proxy_released','server_proxy_released')){
        if($movement.$field -isnot [bool] -or -not $movement.$field){throw "Missing physical movement completion: $field"}
    }
    if($movement.kind -cne 'minecome_hud_physical_movement_v1' -or $movement.patch_sha256 -cne $receiver.PatchHash -or
        $movement.run -cne $run -or $movement.save -cne $ready.save -or $movement.patch_run -cne $receiver.ExpectedRun -or
        $movement.ground_source_kind -cne 'live_kcd_ground_patch' -or $movement.input_source -cne 'hud_input_v2' -or
        $movement.scripted_input -isnot [bool] -or $movement.scripted_input -or
        $movement.trace_file -ine $traceReader.Path -or $movement.trace_records -ne $receiver.Records -or
        $movement.duration_ms -lt 0 -or $movement.duration_ms -gt $walkingSession.SourceMs -or
        $movement.trace_result -cne 'passed' -or $movement.client_walk -lt 0.15 -or $movement.server_walk -lt 0.15 -or
        $movement.movement_events_applied -lt 1 -or $movement.view_updates -lt 2 -or $movement.post_settle_corrections -ne 0){throw 'Physical movement evidence did not demonstrate actual vanilla walking.'}
    $final=@(Read-CoupledTraceLines $traceReader -ExtendedWalking:$ExtendedWalking)
    if($final.Count -ne $lineCount -or $traceReader.Bytes[-1] -ne 10 -or (Get-FileHash -LiteralPath $readyPath).Hash -cne $readyHash -or (Get-FileHash -LiteralPath $patchFile).Hash.ToLowerInvariant() -cne $receiver.PatchHash){throw 'Owned trace/readiness/terrain changed after completion.'}
    $traceHash=(Get-FileHash -LiteralPath $traceReader.Path).Hash
    $exitDeadline=[DateTime]::UtcNow.AddSeconds(15)
    while(-not $helper.HasExited -and [DateTime]::UtcNow -lt $exitDeadline){Start-Sleep -Milliseconds 50}
    if(-not $helper.HasExited){throw 'Minecraft normal exit remained pending.'}
    $helper.WaitForExit()
    if($helper.ExitCode -ne 0){throw 'Minecraft child returned a failure exit.'}
    Stop-MineComeHudGpuBudget $budget
    $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
    if(-not $budget.RestorationVerified -or -not $budget.BudgetValid){throw 'Temporary host FPS budget was not restored.'}
    $passed=$true
    Write-Output "HUD_WALKING_AIMED_PASS run=$run server_frames=$($forwarded.Count) delayed_kcd_readbacks=$($applied.Count) restored=true evidence=$directory"
}catch{$failure=$_.Exception.Message;throw}
finally{
    # Revoke input first on every failure path. If guest/native completion was
    # not acknowledged, preserve that failure; ordinary game-owned leases remain
    # the fallback and never become proof of ordered combined completion.
    if($aimState){$aimState.Stopping=$true}
    if($aimRelay -and -not $aimRelay.AsyncStopRequested){
        try{Request-MineComeHudAimedRelayStop $aimRelay}catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
    }
    if($probe){
        # Stop publication immediately; joining the worker must not delay the
        # follower's explicit end command or its restoration receipt.
        if($camera){Request-HudCameraDeliveryStop $camera}
        if($followerStarted -and -not $restored){
            $beforeCleanup=$receipts
            try{
                try{
                    if($receiptCursor){Close-HudWalkingReceiptCursor $receiptCursor}
                    $receiptCursor=New-HudWalkingReceiptCursor $context.GameLog ([IO.FileInfo]::new($context.GameLog).Length) $probe.Run -KeepOpen
                }catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
                $receipts=@()
                $endCode="MineCome.EndMovementFollower('$($probe.Run)')"
                # Failure cleanup may duplicate the relay's later End receipt;
                # it cannot certify normal completion. Revoke the observed arena
                # on the same game-thread call before restoring the follower.
                $knownArena=$null
                if($aimClicks -and $aimClicks.AimedLedger.Arena){$knownArena=$aimClicks.AimedLedger.Arena}
                elseif($aimState -and $aimState.Ready){$knownArena=$aimState.Ready.arena_offer.arenaId}
                if($null -ne $knownArena){
                    Assert-MineComeAimedInteger $knownArena 1 9007199254740991
                    $endCode="MineCome.EndAimedInput('$run','$knownArena'); "+$endCode
                }
                Console $endCode
                $cleanupUntil=[DateTime]::UtcNow.AddSeconds(3)
                do{
                    Start-Sleep -Milliseconds 100
                    Console "System.LogAlways('[MineComeHudRestoreFlush] $($probe.Run)')"
                    $receipts=@(Read-Receipts 'MineComeMovementFollower')
                    $restored=@($receipts | Where-Object {$_.event -ceq 'restored' -and $_.result -ceq 'restored' -and $_.terminal -eq $true -and $_.timers_cancelled -eq $true -and $_.readback -eq $true -and $_.physical_movement -eq $true -and $_.camera_basis_valid -eq $true -and $null -ne $_.player_readback_error -and $_.player_readback_error -le .15}).Count -eq 1
                    if($restored){break}
                }while([DateTime]::UtcNow -lt $cleanupUntil)
            }catch{[IO.File]::WriteAllText((Join-Path $probe.Directory 'cleanup-error.txt'),$_.Exception.Message)}
            finally{$receipts=@($beforeCleanup)+@($receipts)}
        }
        if($receiptCursor){
            try{Close-HudWalkingReceiptCursor $receiptCursor}
            catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        }
        # Join the cancelled worker. The guest's 300ms view lease and native
        # 250ms input lease release movement; the engine owns its 400ms lease.
        if($camera){
            try{
                $cameraState=Stop-HudCameraDelivery $camera
                if($cameraState.ResourcesClosed){$camera=$null}
                if($cameraState.Failure -or -not $cameraState.Stopped -or -not $cameraState.ResourcesClosed){
                    if(-not $failure){$failure='Camera delivery did not stop cleanly.'};$passed=$false
                }
            }
            catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        }
        if($budget -and -not $budget.StopAttempted){
            try{Stop-MineComeHudGpuBudget $budget}catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
            $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
        }
        if($aimRelay){
            try{
                if(-not $aimRelay.StopAttempted){Stop-MineComeHudAimedRelay $aimRelay}
                $aimRelayEvidence=Get-MineComeHudAimedRelayEvidence $aimRelay
                if($aimRelay.CleanupFailure -or -not $aimRelay.CleanupVerified -or -not $aimRelay.InputCleanupVerified){$passed=$false;if(-not $failure){$failure='Aimed relay cleanup incomplete.'}}
            }catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
        }
        if($aimClicks){$aimClickEvidence=Get-MineComeHudWorldClickEvidence $aimClicks $aimRelay}
        [ordered]@{schema=1;kind='minecome_hud_walking_aimed_cleanup_v1';run=$run;alignment=$(if($aimState){$aimState.Ready}else{$null});closure=$(if($aimState){$aimState.Closed}else{$null});
            aim_cleanup_before_follower_finish=$aimCleanupBeforeRestore;aim_cleanup_utc_ms=$aimCleanupUtcMs;follower_finish_requested_utc_ms=$finishRequestUtcMs;
            ready_sha256=$aimReadyHash;closed_sha256=$aimClosedHash;clicks=$aimClickEvidence;relay=$aimRelayEvidence;visual_verified=$false} |
            ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $probe.Directory 'aimed-verification.json') -Encoding utf8NoBOM
        # Preserve actual delayed readbacks even when a later check failed.
        $applied=@($receipts | Where-Object {$_.event -ceq 'applied' -and $_.physical_movement -eq $true -and $_.readback -eq $true -and $_.camera_basis_valid -eq $true -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15})
        ConvertTo-Json -InputObject $forwarded.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'forwarded.json') -Encoding utf8NoBOM
        [ordered]@{schema=1;kind='minecome_hud_dispatch_diagnostics_v1';parser_warmup=$parserWarmup;
            validation_timings=$traceValidationTimings.ToArray();validation_start_is_file_arrival=$false;
            physical_key_latency_measured=$false;native_application_proved_by_http=$false} |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'dispatch-timings.json') -Encoding utf8NoBOM
        ConvertTo-Json -InputObject $receipts -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') -Encoding utf8NoBOM
        $viewTimings=@();$viewCount=0;$cameraEvidence=$null
        if($cameraState){$viewCount=$cameraState.ViewCount;$cameraEvidence=$cameraState | Select-Object -ExcludeProperty Timings;if($cameraState.PSObject.Properties['Timings']){$viewTimings=@($cameraState.Timings)}}
        ConvertTo-Json -InputObject $viewTimings -Depth 4 | Set-Content -LiteralPath (Join-Path $probe.Directory 'view-timings.json') -Encoding utf8NoBOM
        [ordered]@{schema=1;kind='minecome_hud_walking_aimed_controller_v1';movement_session=$walkingSession.Name;run=$run;probe_run=$probe.Run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();source_sha256=$probe.SourceHash;compositor_armed=[bool]$arm;view_samples=$viewCount;camera_worker=$cameraEvidence;forwarded_frames=$forwarded.Count;delayed_readbacks=$applied.Count;trace_passed=$tracePassed;trace_sha256=$traceHash;restoration_verified=$restored;host_gpu_budget=$budgetEvidence;guest=$guest;visual_verified=$false;physical_input_exclusivity_verified=$false;full_world_movement_authority_verified=$false} |
            ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
    if($traceReader.Stream){$traceReader.Stream.Dispose()}
    if($helper){$helper.Dispose()}
}
