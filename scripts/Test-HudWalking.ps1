#Requires -Version 7.3
# One explicit physical input activation, six seconds of guest motion, eight-second
# game-owned follower bound, and the existing thirty-second HUD session.
[CmdletBinding()]
param([switch]$PreflightOnly,[string]$JavaHome,[string]$BundleDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingReceipts.ps1')
. (Join-Path $PSScriptRoot 'MovementTraceReceiver.ps1')
. (Join-Path $PSScriptRoot 'CoupledMovementProof.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $JavaHome){$JavaHome='C:\Program Files\Java\jdk-24'}
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))){throw 'A local supported JDK is required.'}
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor-walking'}
$context=Get-MineComeProbeContext
& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -PhysicalMovement -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -PreflightOnly
if($PreflightOnly){Write-Output 'HUD_WALKING_PREFLIGHT_PASS no_changes=true';return}
$probe=$null;$helper=$null;$arm=$null;$budget=$null;$budgetEvidence=$null;$failure=$null
$followerStarted=$false;$restored=$false;$passed=$false;$traceEnded=$false;$tracePassed=$false
$ready=$null;$readyHash=$null;$guest=$null;$producerIdentity=$null;$receiver=$null;$physicalReady=$null
$run=[Guid]::NewGuid().ToString('N');$viewSequence=0L;$viewEngine=-1.0;$viewCount=0
$forwarded=[Collections.Generic.List[object]]::new()
$traceReader=[pscustomobject]@{Path=$null;Stream=$null;Bytes=[byte[]]::new(0)}
$lineCount=0;$lastViewRequest=0L;$viewTemporary=$null;$viewPending=$null;$staleViews=0;$lastRestoreFlush=0L
$receipts=@();$applied=@();$traceHash=$null
$receiptCursor=$null
$viewTimings=[Collections.Generic.List[object]]::new()
function Read-Receipts([string]$Tag){
    return @(Read-HudWalkingReceipts $script:receiptCursor $Tag)
}
function Console([string]$Code){
    # CryLog finalizes the previous line when another record arrives. The
    # marker makes a completed receipt readable without accepting a partial tail.
    Invoke-MineComeProbeConsole $context ('#'+$Code+"; System.LogAlways('[MineComeHudWalkingFlush] $($probe.Run)')")
}
function Refresh-View {
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($null -eq $script:viewPending){
        if($now-$script:lastViewRequest -lt 90){return}
        $script:lastViewRequest=$now
        $script:viewPending=[pscustomobject]@{Utc=$now;Sequence=$script:viewSequence+1}
        Console "MineCome.SamplePhysicalHudView('$($probe.Run)')"
    }
    $requestUtc=$script:viewPending.Utc
    $values=@(Read-Receipts 'MineComeHudPhysicalView' | Where-Object {$_.seq -gt $script:viewSequence})
    if(-not $values.Count){
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$requestUtc -gt 1000){throw 'Physical camera request did not acknowledge.'}
        return
    }
    if($values.Count -ne 1){throw 'Physical camera request lacked exactly one acknowledgement.'}
    $sample=$values[-1]
    if($sample.result -cne 'sampled' -or $sample.physical_movement -ne $true -or $sample.camera_basis_valid -ne $true -or
        $sample.seq -le $script:viewSequence -or $sample.sampled_engine_seconds -le $script:viewEngine){
        throw 'Physical camera sampler lost its verified actor/basis/clock.'
    }
    # Timestamp the request, never publication: delayed log reads cannot freshen
    # an old camera observation. Only this request's immediately following sample
    # is accepted; another pending request cannot be stamped with a newer clock.
    if($sample.seq -ne $script:viewPending.Sequence){throw 'Physical view sampler skipped a sequence.'}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $script:viewSequence=[long]$sample.seq;$script:viewEngine=[double]$sample.sampled_engine_seconds
    $script:viewPending=$null
    # Startup scheduling gaps own no movement. Consume, but never publish an
    # expired observation; later genuinely fresh observations may restore readiness.
    # During movement Java's300ms view lease still releases keys and fails closed.
    if($now-$requestUtc -gt 250){
        $script:staleViews++
        $script:viewTimings.Add([pscustomobject]@{seq=$sample.seq;requested_utc_ms=$requestUtc;receipt_utc_ms=$now;published_utc_ms=$null;stale=$true})
        return
    }
    $view=[ordered]@{schema=1;source_kind='live_kcd_hud_view_v1';run=$run;patch_run=$livePatch.Run;patch_sha256=$livePatch.Hash;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();seq=$script:viewSequence;utc_ms=$requestUtc;forward=$sample.camera.forward;up=$sample.camera.up}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($view | ConvertTo-Json -Depth 5 -Compress))
    if($bytes.Length -gt 4096){throw 'Physical camera file exceeds its bound.'}
    [void](Resolve-HudMovementEvidencePath $viewFile $root)
    $file=[IO.FileStream]::new($viewTemporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
    if(Test-Path -LiteralPath $viewFile){[IO.File]::Replace($viewTemporary,$viewFile,[NullString]::Value)}
    else{[IO.File]::Move($viewTemporary,$viewFile,$false)}
    $script:viewTimings.Add([pscustomobject]@{seq=$sample.seq;requested_utc_ms=$requestUtc;receipt_utc_ms=$now;published_utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();stale=$false})
    $script:viewCount++
}
function Send-Pose($Sample){
    Assert-MineComeProbeContext $context
    $frame=$Sample.Record;$target=$Sample.Target
    $age=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-[long]$frame.utc_ms
    if($age -lt -50 -or [Math]::Max(0,$age)+$frame.server_age_ns/1000000.0 -gt 300){return}
    $culture=[Globalization.CultureInfo]::InvariantCulture
    $x=([double]$target.x).ToString('R',$culture);$y=([double]$target.y).ToString('R',$culture);$z=([double]$target.z).ToString('R',$culture)
    $apply="MineCome.ApplyMovementFollower('$($probe.Run)',$($frame.seq),$x,$y,$z)"
    $code=$apply
    if(-not $script:followerStarted){
        $cx=([double]$receiver.Center.x).ToString('R',$culture);$cy=([double]$receiver.Center.y).ToString('R',$culture);$cz=([double]$receiver.Center.z).ToString('R',$culture)
        $code="local p=player and player:GetWorldPos(); if p and (p.x-($cx))^2+(p.y-($cy))^2+(p.z-($cz))^2<=0.01 then if MineCome.BeginPhysicalMovementFollower('$($probe.Run)') then $apply end end"
    }
    $script:followerStarted=$true
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString('#'+$code)) -TimeoutMilliseconds 150 | Out-Null
    $forwarded.Add([pscustomobject]@{TraceSeq=[long]$frame.seq;ServerSeq=[long]$frame.server_seq;Phase=$frame.phase;UtcMs=[long]$frame.utc_ms;Target=$target})
}
try{
    $probe=New-MineComeProbeRun $context 'hud-walking' (Join-Path $root 'kcd2/probes/movement_probe.lua') 'BeginPhysicalMovementFollower'
    $receiptCursor=New-HudWalkingReceiptCursor $context.GameLog $probe.Offset $probe.Run
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
    $viewFile=Join-Path $directory 'host-view.json';$viewTemporary=$viewFile+'.'+$run+'.tmp'
    $readyPath=Join-Path $directory 'capture/stream-ready.json';$resultPath=Join-Path $directory 'capture/stream-result.json'
    $minimumUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$expires=$minimumUtc+180000
    $initialViewDeadline=[DateTime]::UtcNow.AddSeconds(2)
    do{Refresh-View;if($viewCount){break};Start-Sleep -Milliseconds 10}while([DateTime]::UtcNow -lt $initialViewDeadline)
    if($viewCount -ne 1){throw 'Initial fresh camera view did not acknowledge.'}
    $budget=New-MineComeHudGpuBudget $context
    Start-MineComeHudGpuBudget $budget
    $args=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,
        '-TargetPid',[string]$context.GamePid,'-TargetStart',$context.GameStartedUtc.ToFileTimeUtc().ToString(),
        '-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-InputMode','-LiveMouse','-OffscreenPresentation','-PhysicalMovement',
        '-GroundPatchFile',$patchFile,'-MovementTraceFile',$traceReader.Path,'-HostViewFile',$viewFile)
    $quoted=@($args | ForEach-Object {ConvertTo-MineComeWindowsArgument $_})
    $helper=Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -ArgumentList ([string]::Join(' ',$quoted)) -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $directory 'helper.log') -RedirectStandardError (Join-Path $directory 'helper-errors.log')
    Write-Output "HUD_WALKING_START run=$run evidence=$directory"
    $deadline=[DateTime]::UtcNow.AddSeconds(112)
    do{
        Assert-MineComeProbeContext $context
        if(-not $traceEnded){Refresh-View}
        if(-not $ready -and (Test-Path -LiteralPath $readyPath)){
            $ready=Read-HudMovementJson $readyPath
            Assert-HudPhysicalMovementReady $ready $true
            if($ready.run -cne $run){throw 'Physical HUD producer run mismatch.'}
            $arm=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -PhysicalMovement -InputMode -LiveMouse -OffscreenPresentation -BundleDirectory $BundleDirectory -ReadyManifest $readyPath
            $readyHash=(Get-FileHash -LiteralPath $readyPath).Hash
            $receiver=New-MineComeTraceReceiver $patchFile $minimumUtc -ExpectedHudSave $ready.save -PhysicalMovement
            if($receiver.PatchHash -cne $livePatch.Hash){throw 'Live terrain changed before trace binding.'}
            $producerIdentity=[pscustomobject]@{Pid=$ready.producer_pid;Start=[string]$ready.producer_start_filetime}
            Write-Output "HUD_WALKING_ARMED run=$run waiting_for_settled_guest=true"
        }
        $physicalReadyPath=Join-Path $directory 'capture/physical-ready.json'
        if($ready -and -not $physicalReady -and (Test-Path -LiteralPath $physicalReadyPath)){
            $physicalReady=Read-HudMovementJson $physicalReadyPath
            if($physicalReady.schema -ne 1 -or $physicalReady.kind -cne 'minecome_hud_physical_ready_v1' -or
                $physicalReady.ready -isnot [bool] -or -not $physicalReady.ready -or $physicalReady.run -cne $run -or
                $physicalReady.save -cne $ready.save -or $physicalReady.patch_run -cne $receiver.ExpectedRun -or
                $physicalReady.patch_sha256 -cne $receiver.PatchHash -or $physicalReady.target_pid -ne $context.GamePid -or
                $physicalReady.target_start_filetime -cne $context.GameStartedUtc.ToFileTimeUtc().ToString() -or
                $physicalReady.utc_ms -lt $minimumUtc -or $physicalReady.utc_ms -gt [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+50 -or
                $physicalReady.view_seq -lt 1 -or $physicalReady.view_seq -gt $viewSequence){throw 'Actual physical guest readiness did not match the current session.'}
            Write-Output "HUD_WALKING_READY run=$run press_F8=true movement_seconds=6 hud_seconds=30"
        }
        if($receiver -and -not $traceEnded){
            $producer=Get-Process -Id $producerIdentity.Pid
            try{if($producer.ProcessName -cne 'java' -or $producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $producerIdentity.Start){throw 'HUD producer identity changed.'}}finally{$producer.Dispose()}
            $lines=@(Read-CoupledTraceLines $traceReader);$candidate=$null
            for($i=$lineCount;$i -lt $lines.Count;$i++){
                $received=Receive-MineComeMovementTrace $receiver $lines[$i] ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                if($received.Kind -ceq 'sample'){$candidate=$received}
                elseif($received.Kind -ceq 'end'){$traceEnded=$true;$tracePassed=$received.Record.result -ceq 'passed'}
            }
            $lineCount=$lines.Count
            if($candidate -and -not $traceEnded){Send-Pose $candidate}
            if($traceEnded -and $followerStarted){Console "MineCome.EndMovementFollower('$($probe.Run)')"}
        }
        $receipts=@(Read-Receipts 'MineComeMovementFollower')
        $terminal=@($receipts | Where-Object terminal -EQ $true)
        if($traceEnded -and $followerStarted -and -not $terminal.Count -and
            [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()-$lastRestoreFlush -ge 100){
            $lastRestoreFlush=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            Console "System.LogAlways('[MineComeHudRestoreFlush] $($probe.Run)')"
        }
        if($terminal.Count -and -not $traceEnded){throw 'KCD follower stopped before the guest trace ended.'}
        if($traceEnded -and -not $tracePassed){throw 'Minecraft physical movement trace failed.'}
        if(Test-Path -LiteralPath $resultPath){break}
        if($helper.HasExited){throw 'HUD helper exited without its completion receipt.'}
        Start-Sleep -Milliseconds 15
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not(Test-Path -LiteralPath $resultPath)){throw 'Bounded physical HUD session timed out.'}
    $guest=Read-HudMovementJson $resultPath
    Assert-HudPhysicalMovementReady $guest $true
    if($guest.run -cne $run -or $guest.save -cne $ready.save -or $guest.result -cne 'input_completed'){throw 'Actual HUD input session did not complete.'}
    if(-not $traceEnded -or -not $tracePassed -or -not $followerStarted){throw 'No completed real physical movement trace.'}
    $receipts=@(Read-Receipts 'MineComeMovementFollower')
    $restored=@($receipts | Where-Object {$_.event -ceq 'restored' -and $_.result -ceq 'restored' -and $_.physical_movement -eq $true -and $_.camera_basis_valid -eq $true -and $_.terminal -eq $true -and $_.timers_cancelled -eq $true -and $_.readback -eq $true -and $_.end_result -ceq 'explicit_end' -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15}).Count -eq 1
    if(-not $restored){throw 'Physical KCD follower restoration was not verified.'}
    $applied=@($receipts | Where-Object {$_.event -ceq 'applied' -and $_.physical_movement -eq $true -and $_.readback -eq $true -and $_.camera_basis_valid -eq $true -and $null -ne $_.player_readback_error -and $_.player_readback_error -le 0.15})
    if($applied.Count -lt 3){throw 'Too few actual delayed KCD movement readbacks.'}
    foreach($receipt in $applied){
        $sent=@($forwarded | Where-Object TraceSeq -EQ $receipt.seq)
        if($sent.Count -ne 1){throw 'KCD movement receipt lacks a unique dispatched server pose.'}
        foreach($axis in @('x','y','z')){
            if([double]$receipt.target.$axis -ne [double][single]$sent[0].Target.$axis){throw 'KCD target differs from the exact float32 server target.'}
        }
    }
    $movement=$guest.lab_evidence.physical_movement
    foreach($field in @('completed','trace_closed','controls_released','client_proxy_released','server_proxy_released')){
        if($movement.$field -isnot [bool] -or -not $movement.$field){throw "Missing physical movement completion: $field"}
    }
    if($movement.kind -cne 'minecome_hud_physical_movement_v1' -or $movement.patch_sha256 -cne $receiver.PatchHash -or
        $movement.run -cne $run -or $movement.save -cne $ready.save -or $movement.patch_run -cne $receiver.ExpectedRun -or
        $movement.ground_source_kind -cne 'live_kcd_ground_patch' -or $movement.input_source -cne 'hud_input_v2' -or
        $movement.scripted_input -isnot [bool] -or $movement.scripted_input -or
        $movement.trace_file -ine $traceReader.Path -or $movement.trace_records -ne $receiver.Records -or
        $movement.duration_ms -lt 0 -or $movement.duration_ms -gt 6000 -or
        $movement.trace_result -cne 'passed' -or $movement.client_walk -lt 0.15 -or $movement.server_walk -lt 0.15 -or
        $movement.movement_events_applied -lt 1 -or $movement.view_updates -lt 2 -or $movement.post_settle_corrections -ne 0){throw 'Physical movement evidence did not demonstrate actual vanilla walking.'}
    $final=@(Read-CoupledTraceLines $traceReader)
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
        if($followerStarted -and -not $restored){
            try{
                Console "MineCome.EndMovementFollower('$($probe.Run)')"
                $cleanupUntil=[DateTime]::UtcNow.AddSeconds(3)
                do{
                    Start-Sleep -Milliseconds 100
                    Console "System.LogAlways('[MineComeHudRestoreFlush] $($probe.Run)')"
                    $receipts=@(Read-Receipts 'MineComeMovementFollower')
                    $restored=@($receipts | Where-Object {$_.event -ceq 'restored' -and $_.result -ceq 'restored' -and $_.terminal -eq $true -and $_.timers_cancelled -eq $true}).Count -eq 1
                    if($restored){break}
                }while([DateTime]::UtcNow -lt $cleanupUntil)
            }catch{[IO.File]::WriteAllText((Join-Path $probe.Directory 'cleanup-error.txt'),$_.Exception.Message)}
        }
        if($budget -and -not $budget.StopAttempted){
            try{Stop-MineComeHudGpuBudget $budget}catch{if(-not $failure){$failure=$_.Exception.Message};$passed=$false}
            $budgetEvidence=Get-MineComeHudGpuBudgetEvidence $budget
        }
        # On failure, stop refreshing view. The guest's300ms lease and native
        # input250ms lease release held movement; the engine owns its400ms lease.
        if($viewTemporary -and (Test-Path -LiteralPath $viewTemporary)){Remove-Item -LiteralPath $viewTemporary}
        ConvertTo-Json -InputObject $forwarded.ToArray() -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'forwarded.json') -Encoding utf8NoBOM
        ConvertTo-Json -InputObject $receipts -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'kcd-receipts.json') -Encoding utf8NoBOM
        ConvertTo-Json -InputObject $viewTimings.ToArray() -Depth 4 | Set-Content -LiteralPath (Join-Path $probe.Directory 'view-timings.json') -Encoding utf8NoBOM
        [ordered]@{schema=1;kind='minecome_hud_walking_controller_v1';run=$run;probe_run=$probe.Run;result=$(if($passed){'passed'}else{'failed'});failure=$failure;target_pid=$context.GamePid;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();source_sha256=$probe.SourceHash;compositor_armed=[bool]$arm;view_samples=$viewCount;forwarded_frames=$forwarded.Count;delayed_readbacks=$applied.Count;trace_passed=$tracePassed;trace_sha256=$traceHash;restoration_verified=$restored;host_gpu_budget=$budgetEvidence;guest=$guest;visual_verified=$false;physical_input_exclusivity_verified=$false;full_world_movement_authority_verified=$false} |
            ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
    if($traceReader.Stream){$traceReader.Stream.Dispose()}
    if($helper){$helper.Dispose()}
}
