# A dedicated bounded runspace owns camera request/receipt/publication. It cannot
# move an actor; parent controller work must not stall the camera's original lease.
function Read-HudCameraSnapshot([string]$Path,[string]$ProjectRoot){
    $stream=$null
    try{
        $resolved=Resolve-HudMovementEvidencePath $Path $ProjectRoot
        # Atomic replacement may retire this filename while we read. Read only
        # this opened version, and do not deny the publisher its rename/delete.
        $stream=[IO.FileStream]::new($resolved,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $attributes=[IO.File]::GetAttributes($stream.SafeFileHandle)
        $length=$stream.Length
        if(($attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -or $length -lt 2 -or $length -gt 65536){
            throw 'Invalid bounded camera snapshot.'
        }
        $bytes=[byte[]]::new([int]$length)
        $stream.ReadExactly($bytes,0,$bytes.Length)
        if($stream.ReadByte() -ne -1 -or $stream.Length -ne $length){throw 'Camera snapshot changed size while reading.'}
        # Keep the existing ancestor/reparse policy on both sides of the open.
        # An atomic replacement can change the leaf identity, never its owner.
        $null=Resolve-HudMovementEvidencePath $resolved $ProjectRoot
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        $options=[Text.Json.JsonDocumentOptions]::new();$options.MaxDepth=12
        $document=[Text.Json.JsonDocument]::Parse($json,$options)
        try{if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Camera snapshot must be a JSON object.'}}
        finally{$document.Dispose()}
        return ConvertFrom-Json -InputObject $json -Depth 12 -NoEnumerate -ErrorAction Stop
    }catch [IO.IOException]{
        # These native races mean no current snapshot, not a longer lease. The
        # caller declines this physical click; it never queues it for retry.
        # Access denied, malformed data and all other I/O failures remain fatal.
        $code=$_.Exception.HResult -band 0xffff
        if($code -in @(2,3,32,33,303)){return $null}
        throw
    }finally{if($stream){$stream.Dispose()}}
}
function Get-HudCameraDeliveryWorkerScript {
    return {
        param($Context,$Probe,[string]$Run,$LivePatch,[string]$ViewFile,[string]$ProjectRoot,$Shared,$StopToken,$Timings,[long]$DeadlineUtcMs,[long]$DeadlineStamp)
        $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
        $sequence=0L;$viewCount=0L;$staleViews=0L;$lastRequest=0L;$lastRequestStamp=0L;$lastPublished=0L;$engine=-1.0
        # At most 1019 requests in 112 seconds, below the unchanged Lua 1024 cap.
        # Monotonic cadence keeps this budget valid across wall-clock changes.
        $minimumRequestIntervalMs=110L
        $failure=$null;$stage='initializing';$pending=$null;$seenViews=0;$cursor=$null;$temporary=$ViewFile+'.'+$Run+'.tmp'
        $frequency=[Diagnostics.Stopwatch]::Frequency
        function Milliseconds([long]$From){([Diagnostics.Stopwatch]::GetTimestamp()-$From)*1000.0/$frequency}
        function Expired { $StopToken.IsCancellationRequested -or [Diagnostics.Stopwatch]::GetTimestamp() -ge $DeadlineStamp -or [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $DeadlineUtcMs }
        function Publish-State([bool]$Stopped=$false){
            $Shared['Snapshot']=[pscustomobject]@{Sequence=$sequence;ViewCount=$viewCount;StaleViews=$staleViews;Failure=$failure;Stopped=$Stopped;Stage=$stage;LastRequestUtcMs=$lastRequest;LastPublishedUtcMs=$lastPublished;TimingsCount=$Timings.Count;DeadlineUtcMs=$DeadlineUtcMs}
        }
        try{
            . (Join-Path $ProjectRoot 'scripts/KcdToolsProbeHelpers.ps1')
            . (Join-Path $ProjectRoot 'scripts/HudGroundMovement.ps1')
            . (Join-Path $ProjectRoot 'scripts/HudWalkingReceipts.ps1')
            $null=Resolve-HudMovementEvidencePath $ViewFile $ProjectRoot
            $null=Resolve-HudMovementEvidencePath $temporary $ProjectRoot
            if([IO.File]::Exists($ViewFile) -or [IO.File]::Exists($temporary)){throw 'Camera worker requires unused owned output files.'}
            $cursor=New-HudWalkingReceiptCursor $Context.GameLog $Probe.Offset $Probe.Run -KeepOpen
            $stage='waiting';Publish-State
            while(-not (Expired)){
                if($null -eq $pending){
                    if($lastRequestStamp -ne 0 -and (Milliseconds $lastRequestStamp) -lt $minimumRequestIntervalMs){Start-Sleep -Milliseconds 5;continue}
                    # The original request UTC includes guards and HTTP. It is never
                    # replaced by response, log-read, or publication time.
                    $lastRequest=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    $lastRequestStamp=[Diagnostics.Stopwatch]::GetTimestamp()
                    $pending=[pscustomobject]@{Utc=$lastRequest;Sequence=$sequence+1;Mono=$lastRequestStamp;GuardMs=0.0;HttpMs=0.0;LookupMs=0.0;Polls=0}
                    $stage='checking_owner';Publish-State
                    $tick=[Diagnostics.Stopwatch]::GetTimestamp();Assert-MineComeProbeContext $Context;$pending.GuardMs=Milliseconds $tick
                    if(Expired){break}
                    $stage='requesting';Publish-State
                    # Only validated run/sequence literals enter the command.
                    # A rejected sampler never supplies a view or renews a lease.
                    # Restrict its diagnostic to a bounded JSON-safe reason token.
                    $code=@'
#local accepted,reason=MineCome.SamplePhysicalHudView('@RUN@'); if accepted==false then if type(reason)~='string' or #reason>64 or not reason:match('^[a-z_]+$') then reason='invalid_rejection_reason' end; System.LogAlways('[MineComeHudPhysicalViewRejected] {"schema":1,"run":"@RUN@","seq":@SEQ@,"result":"rejected","reason":"'..reason..'"}') end; System.LogAlways('[MineComeHudWalkingFlush] @RUN@')
'@
                    $code=$code.Replace('@RUN@',[string]$Probe.Run).Replace('@SEQ@',$pending.Sequence.ToString([Globalization.CultureInfo]::InvariantCulture))
                    $remaining=$DeadlineUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    if($remaining -le 0){break}
                    $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($code)) -TimeoutMilliseconds ([int][Math]::Max(1,[Math]::Min(1000,$remaining))) | Out-Null
                    $pending.HttpMs=Milliseconds $tick
                }
                if(Expired){break}
                $stage='awaiting_receipt';Publish-State
                $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                $values=@(Read-HudWalkingReceipts $cursor 'MineComeHudPhysicalView')
                $pending.LookupMs+=Milliseconds $tick;$pending.Polls++
                # The cursor parsed both tags atomically from the same fresh bytes.
                # Any rejection ends this request; do not redispatch or rebase it.
                $rejections=$cursor.Receipts['MineComeHudPhysicalViewRejected']
                if($rejections.Count){
                    if($rejections.Count -ne 1){throw 'Physical camera request has multiple rejection receipts.'}
                    $rejection=$rejections[0]
                    if($rejection.seq -isnot [ValueType] -or $rejection.seq -is [bool] -or $rejection.seq -ne $pending.Sequence -or
                        $rejection.result -cne 'rejected' -or $rejection.reason -isnot [string] -or $rejection.reason -cnotmatch '^[a-z_]{1,64}$'){
                        throw 'Physical camera rejection receipt does not match its request.'
                    }
                    throw "Physical camera sampler rejected request $($pending.Sequence): $($rejection.reason)."
                }
                $newCount=$values.Count-$seenViews
                if($newCount -lt 0){throw 'Camera receipt history regressed.'}
                if($newCount -eq 0){
                    if((Milliseconds $pending.Mono) -ge 1000){throw 'Physical camera request did not acknowledge within one second.'}
                    Start-Sleep -Milliseconds 5;continue
                }
                if($newCount -ne 1){throw 'Physical camera request lacked exactly one acknowledgement.'}
                if((Milliseconds $pending.Mono) -ge 1000){throw 'Physical camera acknowledgement exceeded its one-second deadline.'}
                $sample=$values[$seenViews];$seenViews++
                if($sample.result -cne 'sampled' -or $sample.physical_movement -isnot [bool] -or -not $sample.physical_movement -or
                    $sample.camera_basis_valid -isnot [bool] -or -not $sample.camera_basis_valid -or
                    $sample.seq -ne $pending.Sequence -or $sample.sampled_engine_seconds -le $engine){
                    throw 'Physical camera sampler lost its verified actor/basis/sequence/clock.'
                }
                $sequence=[long]$sample.seq;$engine=[double]$sample.sampled_engine_seconds
                $receiptUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                $timing=[ordered]@{seq=$sequence;requested_utc_ms=$pending.Utc;receipt_utc_ms=$receiptUtc;published_utc_ms=$null;stale=$false;guard_ms=$pending.GuardMs;http_ms=$pending.HttpMs;receipt_lookup_ms=$pending.LookupMs;receipt_polls=$pending.Polls;serialize_ms=0.0;path_validation_ms=0.0;write_flush_ms=0.0;replace_ms=0.0}
                if($receiptUtc-$pending.Utc -gt 250){
                    $staleViews++;$timing.stale=$true;$Timings.Enqueue([pscustomobject]$timing);$pending=$null;$stage='discarded_stale';Publish-State;continue
                }
                if(Expired){break}
                $stage='publishing';Publish-State
                $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                $view=[ordered]@{schema=1;source_kind='live_kcd_hud_view_v1';run=$Run;patch_run=$LivePatch.Run;patch_sha256=$LivePatch.Hash;target_pid=$Context.GamePid;target_start_filetime=$Context.GameStartedUtc.ToFileTimeUtc().ToString();seq=$sequence;utc_ms=$pending.Utc;forward=$sample.camera.forward;up=$sample.camera.up}
                $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($view | ConvertTo-Json -Depth 5 -Compress))
                if($bytes.Length -gt 4096){throw 'Physical camera file exceeds its bound.'}
                $timing.serialize_ms=Milliseconds $tick
                $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                $null=Resolve-HudMovementEvidencePath $ViewFile $ProjectRoot
                $null=Resolve-HudMovementEvidencePath $temporary $ProjectRoot
                $timing.path_validation_ms=Milliseconds $tick
                if(Expired){break}
                $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                $file=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try{$file.Write($bytes);$file.Flush($false)}finally{$file.Dispose()}
                $timing.write_flush_ms=Milliseconds $tick
                # This is an ephemeral lease, not durable state. Closing flushes
                # userspace buffers; forcing a disk barrier adds no authority.
                if(Expired){break}
                $tick=[Diagnostics.Stopwatch]::GetTimestamp()
                if([IO.File]::Exists($ViewFile)){[IO.File]::Replace($temporary,$ViewFile,[NullString]::Value)}else{[IO.File]::Move($temporary,$ViewFile,$false)}
                $timing.replace_ms=Milliseconds $tick
                $lastPublished=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$timing.published_utc_ms=$lastPublished
                $viewCount++;$Timings.Enqueue([pscustomobject]$timing);$pending=$null;$stage='waiting';Publish-State
            }
            if(-not $StopToken.IsCancellationRequested){$failure='Physical camera worker deadline expired.'}
        }catch{$failure=$_.Exception.Message}
        finally{
            try{if($cursor){Close-HudWalkingReceiptCursor $cursor}}catch{if(-not $failure){$failure=$_.Exception.Message}}
            try{
                if([IO.File]::Exists($temporary)){
                    $null=Resolve-HudMovementEvidencePath $temporary $ProjectRoot
                    [IO.File]::Delete($temporary)
                }
            }catch{if(-not $failure){$failure=$_.Exception.Message}}
            $stage='stopped';Publish-State $true
        }
    }
}
function Start-HudCameraDelivery($Context,$Probe,[string]$Run,$LivePatch,[string]$ViewFile,[string]$ProjectRoot){
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $Probe.Run -cnotmatch '^[0-9a-f]{32}$' -or $LivePatch.Run -cnotmatch '^[0-9a-f]{32}$' -or
        $LivePatch.Hash -cnotmatch '^[0-9a-f]{64}$' -or $Probe.Offset -lt 0){throw 'Invalid camera worker identity.'}
    $ProjectRoot=[IO.Path]::GetFullPath($ProjectRoot);$ViewFile=[IO.Path]::GetFullPath($ViewFile)
    if($ProjectRoot -ine $Context.ProjectRoot -or $ViewFile -ine [IO.Path]::GetFullPath((Join-Path $Probe.Directory 'host-view.json'))){throw 'Camera worker must own its probe output path.'}
    $capturedContext=[pscustomobject]@{ProjectRoot=$ProjectRoot;GameRoot=[string]$Context.GameRoot;GamePath=[string]$Context.GamePath;GameHash=[string]$Context.GameHash;GamePid=[int]$Context.GamePid;GameStartedUtc=[datetime]$Context.GameStartedUtc;GameLog=[string]$Context.GameLog}
    $capturedProbe=[pscustomobject]@{Run=[string]$Probe.Run;Offset=[long]$Probe.Offset;Directory=[string]$Probe.Directory}
    $capturedPatch=[pscustomobject]@{Run=[string]$LivePatch.Run;Hash=[string]$LivePatch.Hash}
    $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new([StringComparer]::Ordinal)
    $timings=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $cancellation=[Threading.CancellationTokenSource]::new()
    $deadline=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+112000
    $deadlineStamp=[Diagnostics.Stopwatch]::GetTimestamp()+[long]([Diagnostics.Stopwatch]::Frequency*112)
    $shared['Snapshot']=[pscustomobject]@{Sequence=0L;ViewCount=0L;StaleViews=0L;Failure=$null;Stopped=$false;Stage='starting';LastRequestUtcMs=0L;LastPublishedUtcMs=0L;TimingsCount=0;DeadlineUtcMs=$deadline}
    $runspace=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
    try{
        $runspace.Open();$pipeline.Runspace=$runspace
        $null=$pipeline.AddScript((Get-HudCameraDeliveryWorkerScript).ToString()).AddArgument($capturedContext).AddArgument($capturedProbe).AddArgument($Run).AddArgument($capturedPatch).AddArgument($ViewFile).AddArgument($ProjectRoot).AddArgument($shared).AddArgument($cancellation.Token).AddArgument($timings).AddArgument($deadline).AddArgument($deadlineStamp)
        $async=$pipeline.BeginInvoke()
        return [pscustomobject]@{Runspace=$runspace;PowerShell=$pipeline;Async=$async;Shared=$shared;Cancellation=$cancellation;Timings=$timings;StopAsync=$null;Final=$null;Disposed=$false}
    }catch{$cancellation.Cancel();$pipeline.Dispose();$runspace.Dispose();$cancellation.Dispose();throw}
}
function Get-HudCameraDeliveryState($Session){
    if($Session.Final){return $Session.Final}
    $snapshot=$Session.Shared['Snapshot']
    if($Session.Async.IsCompleted -and (-not $snapshot.Stopped -or ($Session.PowerShell.HadErrors -and -not $snapshot.Failure))){
        $reason=if($Session.PowerShell.Streams.Error.Count){[string]$Session.PowerShell.Streams.Error[0]}else{'Camera worker ended without a terminal snapshot.'}
        return [pscustomobject]@{Sequence=$snapshot.Sequence;ViewCount=$snapshot.ViewCount;StaleViews=$snapshot.StaleViews;Failure=$reason;Stopped=$true;Stage='unexpected_exit';LastRequestUtcMs=$snapshot.LastRequestUtcMs;LastPublishedUtcMs=$snapshot.LastPublishedUtcMs;TimingsCount=$snapshot.TimingsCount;DeadlineUtcMs=$snapshot.DeadlineUtcMs}
    }
    return $snapshot
}
function Request-HudCameraDeliveryStop($Session){
    if(-not $Session.Final -and -not $Session.Disposed){$Session.Cancellation.Cancel()}
}
function Stop-HudCameraDelivery($Session){
    if($Session.Final){return $Session.Final}
    Request-HudCameraDeliveryStop $Session
    $completed=$Session.Async.AsyncWaitHandle.WaitOne(1500)
    if(-not $completed){
        # Request pipeline cancellation without an unbounded synchronous Stop.
        # Publication checks the same token before writing and before replacement.
        if(-not $Session.StopAsync){$Session.StopAsync=$Session.PowerShell.BeginStop($null,$null)}
        $snapshot=Get-HudCameraDeliveryState $Session
        return [pscustomobject]@{Sequence=$snapshot.Sequence;ViewCount=$snapshot.ViewCount;StaleViews=$snapshot.StaleViews;Failure='Camera worker did not stop inside its cleanup bound.';Stopped=$false;Stage='cleanup_pending';LastRequestUtcMs=$snapshot.LastRequestUtcMs;LastPublishedUtcMs=$snapshot.LastPublishedUtcMs;TimingsCount=$Session.Timings.Count;DeadlineUtcMs=$snapshot.DeadlineUtcMs;Timings=$Session.Timings.ToArray();ResourcesClosed=$false}
    }
    $endFailure=$null
    try{$null=$Session.PowerShell.EndInvoke($Session.Async)}catch{$endFailure=$_.Exception.Message}
    $snapshot=Get-HudCameraDeliveryState $Session
    $failure=$snapshot.Failure
    if(-not $failure -and $endFailure){$failure=$endFailure}
    $Session.PowerShell.Dispose();$Session.Runspace.Dispose();$Session.Cancellation.Dispose();$Session.Disposed=$true
    $Session.Final=[pscustomobject]@{Sequence=$snapshot.Sequence;ViewCount=$snapshot.ViewCount;StaleViews=$snapshot.StaleViews;Failure=$failure;Stopped=$true;Stage='stopped';LastRequestUtcMs=$snapshot.LastRequestUtcMs;LastPublishedUtcMs=$snapshot.LastPublishedUtcMs;TimingsCount=$Session.Timings.Count;DeadlineUtcMs=$snapshot.DeadlineUtcMs;Timings=$Session.Timings.ToArray();ResourcesClosed=$true}
    return $Session.Final
}
