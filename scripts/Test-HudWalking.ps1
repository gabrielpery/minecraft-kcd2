#Requires -Version 7.3
# One explicit physical activation. Short: 5+1 seconds; extended: 15+1 seconds.
# Each has its own game-owned bound within the existing thirty-second HUD session.
[CmdletBinding()]
param([switch]$PreflightOnly,[string]$JavaHome,[string]$BundleDirectory,[switch]$ExtendedWalking,[switch]$WideWalking,[switch]$CorridorWalking)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundCorridor.ps1')
if($CorridorWalking -and (-not $ExtendedWalking -or $WideWalking)){throw 'CorridorWalking requires its separate extended walking profile.'}
. (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
. (Join-Path $PSScriptRoot 'HudBufferedMovement.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'HudCameraDelivery.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
. (Join-Path $PSScriptRoot 'CoupledMovementProof.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$walkingSession=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
$walkingAreaArgument=if($CorridorWalking){",'corridor'"}elseif($WideWalking){",'wide'"}else{''}
if(-not $JavaHome){$JavaHome='C:\Program Files\Java\jdk-24'}
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))){throw 'A local supported JDK is required.'}
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor-walking'}
$context=Get-MineComeProbeContext
& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -PhysicalMovement -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -PreflightOnly -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
if($PreflightOnly){Write-Output 'HUD_WALKING_PREFLIGHT_PASS no_changes=true';return}
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
function Read-Receipts([string]$Tag){
    return @(Read-HudWalkingReceipts $script:receiptCursor $Tag)
}
function Console([string]$Code){
    # CryLog finalizes the previous line when another record arrives. The
    # marker makes a completed receipt readable without accepting a partial tail.
    Invoke-MineComeProbeConsole $context ('#'+$Code+"; System.LogAlways('[MineComeHudWalkingFlush] $($probe.Run)')")
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
        $code="local p=player and player:GetWorldPos(); if p and (p.x-($cx))^2+(p.y-($cy))^2+(p.z-($cz))^2<=0.01 then if MineCome.$($walkingSession.BeginFunction)('$($probe.Run)'$walkingAreaArgument) then $apply end end"
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
}
try{
    $probe=New-MineComeProbeRun $context 'hud-walking' (Join-Path $root 'kcd2/probes/movement_probe.lua') $walkingSession.BeginFunction
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
    if($CorridorWalking){
        $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundCorridor.ps1') | Where-Object {$_ -isnot [string] -and $_.PSObject.Properties['GroundCorridorFile']})
        if($capture.Count -ne 1){throw 'One live corridor capture is required.'}
        $patchFile=$capture[0].GroundCorridorFile
        $livePatch=Read-HudLiveGroundCorridor $patchFile $root $context
    }else{
        $capture=@(& (Join-Path $PSScriptRoot 'Test-KcdGroundProbe.ps1') -Patch -WideWalking:$WideWalking | Where-Object {$_ -isnot [string] -and $_.GroundPatchFile})
        if($capture.Count -ne 1){throw 'One live ground patch is required.'}
        $patchFile=$capture[0].GroundPatchFile
        $livePatch=Read-HudLiveGroundPatch $patchFile $root $context -WideWalking:$WideWalking
    }
    $corridorBinding=if($CorridorWalking){@{Corridor=$livePatch}}else{@{}}
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
    $args=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,
        '-TargetPid',[string]$context.GamePid,'-TargetStart',$context.GameStartedUtc.ToFileTimeUtc().ToString(),
        '-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-InputMode','-LiveMouse','-OffscreenPresentation','-PhysicalMovement',
        '-GroundPatchFile',$patchFile,'-MovementTraceFile',$traceReader.Path,'-HostViewFile',$viewFile)
    if($ExtendedWalking){$args+='-ExtendedWalking'}
    if($WideWalking){$args+='-WideWalking'}
    if($CorridorWalking){$args+='-CorridorWalking'}
    $quoted=@($args | ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
    $helper=Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'helper.log') -RedirectStandardError (Join-Path $directory 'helper-errors.log')
    Write-Output "HUD_WALKING_START run=$run evidence=$directory"
    do{
        Assert-MineComeProbeContext $context
        if(-not $traceEnded){
            $cameraState=Get-HudCameraDeliveryState $camera
            if($cameraState.Failure){throw $cameraState.Failure}
            if($cameraState.Stopped){throw 'Camera delivery stopped before movement completed.'}
        }
        if(-not $ready -and (Test-Path -LiteralPath $readyPath)){
            $ready=Read-HudMovementJson $readyPath
            Assert-HudPhysicalMovementReady $ready $true -CorridorWalking:$CorridorWalking
            Assert-HudWalkingSession $ready -ExtendedWalking:$ExtendedWalking
            Assert-HudWalkingArea $ready ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
            if($ready.run -cne $run){throw 'Physical HUD producer run mismatch.'}
            # Exercise the cold parser with disposable diagnostic state before
            # arming input. Its synthetic records never enter the live receiver.
            $parserWarmup=Initialize-HudBufferedMovementPipeline @corridorBinding -PatchFile $patchFile -ExpectedHudSave $ready.save -MinimumUtcMs $minimumUtc -ExtendedWalking:$ExtendedWalking -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
            $receiver=New-MineComeTraceReceiver @corridorBinding $patchFile $minimumUtc -ExpectedHudSave $ready.save -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking:$ExtendedWalking -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
            if($receiver.PatchHash -cne $livePatch.Hash){throw 'Live terrain changed before trace binding.'}
            $arm=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -PhysicalMovement -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -ReadyManifest $readyPath -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
            $readyHash=(Get-FileHash -LiteralPath $readyPath).Hash
            $producerIdentity=[pscustomobject]@{Pid=$ready.producer_pid;Start=[string]$ready.producer_start_filetime}
            Write-Output "HUD_WALKING_ARMED run=$run waiting_for_settled_guest=true"
        }
        $physicalReadyPath=Join-Path $directory 'capture/physical-ready.json'
        if($ready -and -not $physicalReady -and (Test-Path -LiteralPath $physicalReadyPath)){
            $physicalReady=Read-HudMovementJson $physicalReadyPath
            Assert-HudWalkingSession $physicalReady -ExtendedWalking:$ExtendedWalking
            Assert-HudWalkingArea $physicalReady ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
            if($physicalReady.schema -ne 1 -or $physicalReady.kind -cne 'minecome_hud_physical_ready_v1' -or
                $physicalReady.ready -isnot [bool] -or -not $physicalReady.ready -or $physicalReady.run -cne $run -or
                $physicalReady.save -cne $ready.save -or $physicalReady.patch_run -cne $receiver.ExpectedRun -or
                $physicalReady.patch_sha256 -cne $receiver.PatchHash -or $physicalReady.target_pid -ne $context.GamePid -or
                $physicalReady.target_start_filetime -cne $context.GameStartedUtc.ToFileTimeUtc().ToString() -or
                $physicalReady.utc_ms -lt $minimumUtc -or $physicalReady.utc_ms -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+50 -or
                $physicalReady.view_seq -lt 1 -or $physicalReady.view_seq -gt (Get-HudCameraDeliveryState $camera).Sequence){throw 'Actual physical guest readiness did not match the current session.'}
            $activationWindow=[int][Math]::Floor(($deadline-[DateTime]::UtcNow).TotalSeconds-35)
            if($activationWindow -lt 1){throw 'Not enough bounded time remains for the full physical HUD check.'}
            Write-Output "HUD_WALKING_READY run=$run press_F8=true press_F8_within_seconds=$activationWindow movement_seconds=$($walkingSession.SourceMs/1000) input_seconds=$($walkingSession.InputMs/1000) movement_session=$($walkingSession.Name) hud_seconds=30"
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
        if($traceEnded -and $followerStarted -and -not $followerFinishRequested){
            # Seal the immutable source timeline. The game thread observes its
            # final point and restores immediately, independent of log polling.
            Console "MineCome.FinishBufferedMovementFollower('$($probe.Run)',$($forwarded[-1].TraceSeq))"
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
    Assert-HudPhysicalMovementReady $guest $true -CorridorWalking:$CorridorWalking
    Assert-HudWalkingSession $guest -ExtendedWalking:$ExtendedWalking
    Assert-HudWalkingArea $guest ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
    if($guest.run -cne $run -or $guest.save -cne $ready.save -or $guest.result -cne 'input_completed'){throw 'Actual HUD input session did not complete.'}
    if(-not $traceEnded -or -not $tracePassed -or -not $followerStarted){throw 'No completed real physical movement trace.'}
    $receipts=@(Read-Receipts 'MineComeMovementFollower')
    Assert-HudWalkingFollowerSession $receipts -ExtendedWalking:$ExtendedWalking -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
    $restored=@($receipts | Where-Object {$_.event -ceq 'restored' -and $_.result -ceq 'restored' -and $_.physical_movement -eq $true -and $_.camera_basis_valid -eq $true -and $_.terminal -eq $true -and $_.timers_cancelled -eq $true -and $_.readback -eq $true -and $_.end_result -ceq 'explicit_end' -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15}).Count -eq 1
    if(-not $restored){throw 'Physical KCD follower restoration was not verified.'}
    $applied=@($receipts | Where-Object {$_.event -ceq 'applied' -and $_.physical_movement -eq $true -and $_.readback -eq $true -and $_.camera_basis_valid -eq $true -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15})
    if($applied.Count -lt 3){throw 'Too few actual delayed KCD movement readbacks.'}
    $playbackEpoch=$null;$lastCrossed=0;$crossedPoints=0;$previousSourceIndex=-1
    foreach($receipt in $applied){
        $proof=Assert-HudBufferedMovementReceipt -Receipt $receipt -Forwarded $forwarded -ExtendedWalking:$ExtendedWalking -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking
        if(($null -ne $playbackEpoch -and $proof.EpochEngineSeconds -ne $playbackEpoch) -or $proof.CrossedSourceSeq -le $lastCrossed){throw 'Buffered playback changed epoch or replayed a source point.'}
        if($proof.SourcePointsCrossed -ne $proof.SourceIndex-$previousSourceIndex){throw 'Buffered source crossing count differs from actual progress.'}
        $previousSourceIndex=$proof.SourceIndex
        $playbackEpoch=$proof.EpochEngineSeconds;$lastCrossed=$proof.CrossedSourceSeq
        $crossedPoints+=$receipt.source_points_crossed
    }
    if($lastCrossed -ne $forwarded[-1].TraceSeq -or $crossedPoints -ne $forwarded.Count){throw 'Buffered playback did not drain all forwarded source points.'}
    $movement=$guest.lab_evidence.physical_movement
    Assert-HudWalkingSession $movement -ExtendedWalking:$ExtendedWalking
    Assert-HudWalkingArea $movement ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
    Assert-HudWalkingDuration $movement -ExtendedWalking:$ExtendedWalking
    foreach($field in @('completed','trace_closed','controls_released','client_proxy_released','server_proxy_released')){
        if($movement.$field -isnot [bool] -or -not $movement.$field){throw "Missing physical movement completion: $field"}
    }
    if($movement.kind -cne 'minecome_hud_physical_movement_v1' -or $movement.patch_sha256 -cne $receiver.PatchHash -or
        $movement.run -cne $run -or $movement.save -cne $ready.save -or $movement.patch_run -cne $receiver.ExpectedRun -or
        $movement.ground_source_kind -cne $(if($CorridorWalking){'live_kcd_ground_corridor'}else{'live_kcd_ground_patch'}) -or $movement.input_source -cne 'hud_input_v2' -or
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
    Write-Output "HUD_WALKING_PASS run=$run server_frames=$($forwarded.Count) delayed_kcd_readbacks=$($applied.Count) restored=true evidence=$directory"
}catch{$failure=$_.Exception.Message;throw}
finally{
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
                Console "MineCome.EndMovementFollower('$($probe.Run)')"
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
        $verification=[ordered]@{schema=1;kind='minecome_hud_walking_controller_v1';movement_session=$walkingSession.Name;run=$run;probe_run=$probe.Run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();source_sha256=$probe.SourceHash;compositor_armed=[bool]$arm;view_samples=$viewCount;camera_worker=$cameraEvidence;forwarded_frames=$forwarded.Count;delayed_readbacks=$applied.Count;trace_passed=$tracePassed;trace_sha256=$traceHash;restoration_verified=$restored;host_gpu_budget=$budgetEvidence;guest=$guest;visual_verified=$false;physical_input_exclusivity_verified=$false;full_world_movement_authority_verified=$false}
        if($WideWalking){$verification.walking_area='wide'}
        if($CorridorWalking){$verification.walking_area='corridor'}
        $verification | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
    if($traceReader.Stream){$traceReader.Stream.Dispose()}
    if($helper){$helper.Dispose()}
}
