# Pure source-time normalization and observed buffered-path proof. No game calls.
function Get-HudBufferedNumber($Value,[string]$Name,[double]$Minimum,[double]$Maximum) {
    if($Value -isnot [ValueType] -or $Value -is [bool] -or $Value -is [char] -or
        $Value -is [datetime] -or -not [double]::IsFinite([double]$Value) -or
        [double]$Value -lt $Minimum -or [double]$Value -gt $Maximum) {
        throw "Invalid buffered movement number: $Name"
    }
    return [double]$Value
}
function Get-HudBufferedInteger($Value,[string]$Name,[long]$Minimum,[long]$Maximum) {
    # JSON clock integers must not pass through double and lose nanoseconds.
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "Invalid buffered movement integer: $Name"
    }
    return [long]$Value
}
function Get-HudBufferedField($Value,[string]$Name) {
    if($null -eq $Value -or $null -eq $Value.PSObject.Properties[$Name]) {
        if($Value -is [Collections.IDictionary] -and $Value.Contains($Name)){return ,($Value[$Name])}
        throw "Missing buffered movement field: $Name"
    }
    return ,($Value.$Name)
}
function New-HudBufferedSourceState {
    return [pscustomobject]@{Kind='minecome_hud_buffered_source_state_v1';Count=0;
        AnchorNs=$null;LastSourceNs=$null;LastMonotonicNs=$null;LastTraceSeq=0L;LastServerSeq=0L}
}
function Get-HudBufferedSourceTime($State,$Record) {
    if((Get-HudBufferedField $State 'Kind') -cne 'minecome_hud_buffered_source_state_v1') {
        throw 'Invalid buffered source state.'
    }
    $count=Get-HudBufferedInteger (Get-HudBufferedField $State 'Count') 'state count' 0 199
    $monotonic=Get-HudBufferedInteger (Get-HudBufferedField $Record 'monotonic_ns') 'monotonic_ns' ([long]::MinValue) ([long]::MaxValue)
    $age=Get-HudBufferedInteger (Get-HudBufferedField $Record 'server_age_ns') 'server_age_ns' 0 250000000
    $seq=Get-HudBufferedInteger (Get-HudBufferedField $Record 'seq') 'seq' 1 200
    $serverSeq=Get-HudBufferedInteger (Get-HudBufferedField $Record 'server_seq') 'server_seq' 1 1000000
    $phase=Get-HudBufferedField $Record 'phase';$kind=Get-HudBufferedField $Record 'kind'
    if($kind -isnot [string] -or $kind -cne 'sample' -or $phase -isnot [string] -or
        $phase -cnotin @('SETTLING','WALKING','RESTING','JUMPING','LANDING','PASSED') -or
        ($count -eq 0 -and $phase -cne 'SETTLING')) {
        throw 'Buffered timing must begin with the initial settling sample.'
    }
    # Decimal subtraction detects signed-long underflow without rounding either
    # clock. System.nanoTime may legitimately be negative.
    $sourceDecimal=[decimal]$monotonic-[decimal]$age
    if($sourceDecimal -lt [decimal][long]::MinValue){throw 'Server observation clock underflow.'}
    $source=[long]$sourceDecimal
    if($count -eq 0){
        $anchor=$source;$milliseconds=0.0
        if($null -ne $State.AnchorNs -or $null -ne $State.LastSourceNs -or
            $null -ne $State.LastMonotonicNs -or $State.LastTraceSeq -ne 0 -or $State.LastServerSeq -ne 0) {
            throw 'Uninitialized buffered source state has previous observations.'
        }
    }else{
        $anchor=Get-HudBufferedInteger (Get-HudBufferedField $State 'AnchorNs') 'anchor clock' ([long]::MinValue) ([long]::MaxValue)
        $last=Get-HudBufferedInteger (Get-HudBufferedField $State 'LastSourceNs') 'last server clock' ([long]::MinValue) ([long]::MaxValue)
        $lastMono=Get-HudBufferedInteger (Get-HudBufferedField $State 'LastMonotonicNs') 'last monotonic clock' ([long]::MinValue) ([long]::MaxValue)
        $lastTrace=Get-HudBufferedInteger (Get-HudBufferedField $State 'LastTraceSeq') 'last trace sequence' 1 200
        $lastServer=Get-HudBufferedInteger (Get-HudBufferedField $State 'LastServerSeq') 'last server sequence' 1 1000000
        if($last -lt $anchor -or $source -le $last -or $monotonic -le $lastMono -or $seq -le $lastTrace -or $serverSeq -le $lastServer) {
            throw 'Buffered source clocks and sequences must strictly advance.'
        }
        $elapsed=[decimal]$source-[decimal]$anchor
        if($elapsed -lt 0 -or $elapsed -gt 6000000000){throw 'Buffered source exceeds the six-second trace bound.'}
        $milliseconds=[double]($elapsed/1000000)
    }
    # No state changes until every check succeeds. The caller still enforces
    # provenance, source freshness, terrain and dispatch ownership.
    $State.AnchorNs=$anchor;$State.LastSourceNs=$source;$State.LastMonotonicNs=$monotonic
    $State.LastTraceSeq=$seq;$State.LastServerSeq=$serverSeq;$State.Count=[int]($count+1)
    return [double]$milliseconds
}
function Get-HudBufferedVector($Value,[string]$Name,[double]$Limit=10000000) {
    $out=[ordered]@{}
    foreach($axis in @('x','y','z')){
        $out[$axis]=Get-HudBufferedNumber (Get-HudBufferedField $Value $axis) "$Name.$axis" (-$Limit) $Limit
    }
    return [pscustomobject]$out
}
function Get-HudBufferedDistance($First,$Second) {
    return [Math]::Sqrt([Math]::Pow($First.x-$Second.x,2)+[Math]::Pow($First.y-$Second.y,2)+[Math]::Pow($First.z-$Second.z,2))
}
function Assert-HudBufferedFlag($Value,[string]$Name,[bool]$Expected) {
    if($Value -isnot [bool] -or $Value -ne $Expected){throw "Invalid buffered movement flag: $Name"}
}
function Assert-HudBufferedExactVector($Actual,$Expected,[string]$Name) {
    foreach($axis in @('x','y','z')){
        if($Actual.$axis -ne [double][single]$Expected.$axis){throw "Buffered float32 target mismatch: $Name.$axis"}
    }
}
function Test-HudBufferedArithmetic([double]$Actual,[double]$DoubleResult,[double]$SingleResult) {
    # Supported Lua builds expose either double arithmetic or float32 numbers.
    # Accept their evaluated results, not an arbitrary positional error window.
    return [Math]::Abs($Actual-$DoubleResult) -le .0000001 -or
        $Actual -eq [double][single]$DoubleResult -or $Actual -eq $SingleResult
}
function Get-HudBufferedCamera($Value,[string]$Name) {
    $position=Get-HudBufferedVector (Get-HudBufferedField $Value 'position') "$Name.position"
    $forward=Get-HudBufferedVector (Get-HudBufferedField $Value 'forward') "$Name.forward" 1.1
    $up=Get-HudBufferedVector (Get-HudBufferedField $Value 'up') "$Name.up" 1.1
    $fov=Get-HudBufferedNumber (Get-HudBufferedField $Value 'fov') "$Name.fov" .01 ([Math]::PI)
    $zero=[pscustomobject]@{x=0.0;y=0.0;z=0.0}
    if([Math]::Abs((Get-HudBufferedDistance $forward $zero)-1) -gt .05 -or
        [Math]::Abs((Get-HudBufferedDistance $up $zero)-1) -gt .05 -or
        [Math]::Abs($forward.x*$up.x+$forward.y*$up.y+$forward.z*$up.z) -gt .05) {
        throw 'Buffered readback camera has an invalid basis.'
    }
    return [pscustomobject]@{position=$position;forward=$forward;up=$up;fov=$fov}
}
function Assert-HudBufferedMovementReceipt($Receipt,$Forwarded) {
    # This proves retained observed path samples, not unrecorded frames or visual
    # smoothness. The caller separately pins run/process/source provenance and
    # checks common epoch/increasing source acknowledgements across receipts.
    if($Forwarded -isnot [Collections.ICollection] -or $Forwarded.Count -lt 1 -or $Forwarded.Count -gt 200) {
        throw 'Buffered proof requires one to 200 dispatched source points.'
    }
    $points=[Collections.Generic.List[object]]::new();$bySeq=@{};$lastSeq=0L;$lastMs=-1.0
    foreach($point in $Forwarded){
        $seq=Get-HudBufferedInteger (Get-HudBufferedField $point 'TraceSeq') 'forwarded sequence' 1 200
        $ms=Get-HudBufferedNumber (Get-HudBufferedField $point 'SourceMs') 'forwarded source time' 0 6000
        if($ms -ne [double][single]$ms){throw 'Forwarded SourceMs must retain the exact float32 wire value.'}
        $target=Get-HudBufferedVector (Get-HudBufferedField $point 'Target') 'forwarded target'
        if($seq -le $lastSeq -or $ms -le $lastMs -or ($points.Count -eq 0 -and $ms -ne 0)) {
            throw 'Dispatched source points must have a zero anchor and strictly increasing sequence/time.'
        }
        $entry=[pscustomobject]@{Seq=$seq;Ms=$ms;Target=$target;Index=$points.Count}
        $points.Add($entry);$bySeq[$seq]=$entry;$lastSeq=$seq;$lastMs=$ms
    }
    foreach($pair in @(@('position_mode','source_time_buffered'),@('event','applied'),@('result','applied_readback'))){
        $text=Get-HudBufferedField $Receipt $pair[0]
        if($text -isnot [string] -or $text -cne $pair[1]){throw 'Receipt is not an applied source-time buffered observation.'}
    }
    [void](Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'playback_delay_ms') 'playback delay' 200 200)
    foreach($flag in @('physical_movement','readback','camera_basis_valid')) {
        Assert-HudBufferedFlag (Get-HudBufferedField $Receipt $flag) $flag $true
    }
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'terminal') 'terminal' $false
    if($null -ne (Get-HudBufferedField $Receipt 'interpolation_ms') -or
        $null -ne (Get-HudBufferedField $Receipt 'endpoint_write_performed')) {
        throw 'Buffered receipt cannot claim a fixed-duration source-endpoint write.'
    }
    $seq=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'seq') 'acknowledged sequence' 1 200
    $sourceSeq=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'source_seq') 'crossed source sequence' 1 200
    if($seq -ne $sourceSeq -or -not $bySeq.ContainsKey($seq)){throw 'Buffered ACK has no unique dispatched source point.'}
    $source=$bySeq[$seq]
    $sourceMs=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'source_ms') 'acknowledged source time' 0 6000
    if($sourceMs -ne $source.Ms){throw 'Acknowledged source time differs from dispatch.'}
    Assert-HudBufferedExactVector (Get-HudBufferedVector (Get-HudBufferedField $Receipt 'source_target') 'acknowledged source target') $source.Target 'source target'
    $crossed=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'source_points_crossed') 'crossed source count' 1 8
    if($crossed -gt $source.Index+1){throw 'Crossed count exceeds available source history.'}
    $epoch=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'playback_epoch_engine_seconds') 'playback epoch' 0 1000000000000
    $singleEpoch=[single]$epoch
    $clockUlp=[Math]::Max([double][MathF]::BitIncrement($singleEpoch)-$singleEpoch,
        [double]$singleEpoch-[MathF]::BitDecrement($singleEpoch))
    # Engine timestamps are float32 on the pinned tools build. Account for one
    # representable clock step in acceptance comparisons, not a renewed lease.
    $originTolerance=[Math]::Max(.0000001,$clockUlp)
    $sampled=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'sampled_engine_seconds') 'receipt engine time' $epoch ($epoch+8)
    $sourceAge=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'target_receipt_age_ms') 'acknowledged source age' 0 400
    if($sourceAge -le 0){throw 'Buffered source ACK must be delayed after acceptance.'}
    $sourceAccepted=$sampled-$sourceAge/1000
    if($sourceAccepted -lt $epoch-.2-$originTolerance){throw 'Source acknowledgement predates the initial acceptance.'}
    $singleSourceAccepted=[double][single]$sourceAccepted
    $singleInitialEpoch=[double][single]($singleSourceAccepted+[double][single]0.2)
    if($sourceMs -eq 0 -and -not (Test-HudBufferedArithmetic $epoch ($sourceAccepted+.2) $singleInitialEpoch)){
        throw 'The source-zero acknowledgement does not anchor the fixed 200 ms epoch.'
    }
    $updates=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'segment_update_count') 'segment setter count' 0 511
    $observations=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'segment_observation_count') 'segment observation count' 1 8192
    $maxError=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'segment_max_readback_error') 'maximum observed error' 0 .05
    $maxGap=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'segment_max_observation_gap_ms') 'maximum observation gap' 0 400
    $truncated=Get-HudBufferedField $Receipt 'segment_observed_samples_truncated'
    if($truncated -isnot [bool]){throw 'Observation truncation must be explicit.'}
    $samples=Get-HudBufferedField $Receipt 'segment_observed_samples'
    if($samples -isnot [Collections.ICollection] -or $samples.Count -lt 1 -or $samples.Count -gt 8 -or
        $observations -lt $samples.Count -or ($truncated -ne ($observations -gt $samples.Count))) {
        throw 'Invalid bounded retained observation list.'
    }
    $previousWritten=$null;$previousObserved=$null;$previousPlayback=-1.0;$previousFrame=$null
    $retainedSetters=0;$gaps=[Collections.Generic.List[double]]::new();$largestError=0.0;$last=$null
    foreach($sample in $samples){
        $fromSeq=Get-HudBufferedInteger (Get-HudBufferedField $sample 'bracket_from_seq') 'left bracket sequence' 1 200
        $toSeq=Get-HudBufferedInteger (Get-HudBufferedField $sample 'bracket_to_seq') 'right bracket sequence' 1 200
        if(-not $bySeq.ContainsKey($fromSeq) -or -not $bySeq.ContainsKey($toSeq)){throw 'Observed bracket references an unknown source point.'}
        $from=$bySeq[$fromSeq];$to=$bySeq[$toSeq]
        $fromMs=Get-HudBufferedNumber (Get-HudBufferedField $sample 'bracket_from_ms') 'left source time' 0 6000
        $toMs=Get-HudBufferedNumber (Get-HudBufferedField $sample 'bracket_to_ms') 'right source time' 0 6000
        if($fromMs -ne $from.Ms -or $toMs -ne $to.Ms){throw 'Observed bracket time differs from dispatch.'}
        $fromTarget=Get-HudBufferedVector (Get-HudBufferedField $sample 'bracket_from_target') 'left bracket target'
        $toTarget=Get-HudBufferedVector (Get-HudBufferedField $sample 'bracket_to_target') 'right bracket target'
        Assert-HudBufferedExactVector $fromTarget $from.Target 'left bracket target'
        Assert-HudBufferedExactVector $toTarget $to.Target 'right bracket target'
        $written=Get-HudBufferedNumber (Get-HudBufferedField $sample 'written_engine_seconds') 'write engine time' $epoch $sampled
        $observed=Get-HudBufferedNumber (Get-HudBufferedField $sample 'observed_engine_seconds') 'observation engine time' $written $sampled
        $accepted=Get-HudBufferedNumber (Get-HudBufferedField $sample 'bracket_to_received_engine_seconds') 'destination acceptance time' ($epoch-.2-$originTolerance) $written
        if($observed -le $written -or ($written-$accepted)*1000 -gt 400.000001 -or
            ($null -ne $previousWritten -and $written -le $previousWritten) -or
            ($null -ne $previousObserved -and ($observed -le $previousObserved -or $written -lt $previousObserved))) {
            throw 'Buffered observations must follow ordered normal frames within the original destination lease.'
        }
        $writtenFrame=Get-HudBufferedField $sample 'written_frame_id';$observedFrame=Get-HudBufferedField $sample 'observed_frame_id'
        if($null -ne $writtenFrame){
            $writtenFrame=Get-HudBufferedInteger $writtenFrame 'written frame ID' 0 ([long]::MaxValue)
            if($null -ne $previousFrame -and $writtenFrame -lt $previousFrame){throw 'Native write frame regressed.'}
        }
        if($null -ne $observedFrame){
            $observedFrame=Get-HudBufferedInteger $observedFrame 'observed frame ID' 0 ([long]::MaxValue)
            if(($null -ne $writtenFrame -and $observedFrame -le $writtenFrame) -or
                ($null -ne $previousFrame -and $observedFrame -le $previousFrame)){throw 'Native observation frame did not advance.'}
            $previousFrame=$observedFrame
        }
        $playback=Get-HudBufferedNumber (Get-HudBufferedField $sample 'playback_source_ms') 'playback source time' 0 8000
        $fraction=Get-HudBufferedNumber (Get-HudBufferedField $sample 'fraction') 'interpolation fraction' 0 1
        $hold=Get-HudBufferedField $sample 'source_hold'
        if($hold -isnot [bool] -or [Math]::Abs($playback-($written-$epoch)*1000) -gt .001 -or $playback -le $previousPlayback) {
            throw 'Playback time does not follow the fixed source-time epoch.'
        }
        if($hold){
            if($fromSeq -ne $toSeq -or $fraction -ne 0 -or $playback+.001 -lt $fromMs){throw 'A source hold must retain one known point without extrapolation.'}
        }elseif($to.Index -ne $from.Index+1 -or $toMs -le $fromMs -or $playback -lt $fromMs-.001 -or $playback -gt $toMs+.001 -or
            [Math]::Abs($fraction-($playback-$fromMs)/($toMs-$fromMs)) -gt .00001){
            throw 'Buffered fraction does not match an adjacent source-time bracket.'
        }
        $expected=[pscustomobject]@{x=$fromTarget.x+($toTarget.x-$fromTarget.x)*$fraction;
            y=$fromTarget.y+($toTarget.y-$fromTarget.y)*$fraction;z=$fromTarget.z+($toTarget.z-$fromTarget.z)*$fraction}
        $requested=Get-HudBufferedVector (Get-HudBufferedField $sample 'requested') 'requested point'
        # Source vectors are float32. Evaluate the float32 arithmetic path too:
        # the actual tools build rounds each operation, even before SetWorldPos.
        foreach($axis in @('x','y','z')){
            $singleDelta=[single]($toTarget.$axis-$fromTarget.$axis)
            $singleProduct=[single]($singleDelta*[single]$fraction)
            $singleResult=[double][single]($fromTarget.$axis+$singleProduct)
            if(-not(Test-HudBufferedArithmetic $requested.$axis $expected.$axis $singleResult)){
                throw 'Requested point leaves its source-time linear path.'
            }
        }
        $actual=Get-HudBufferedVector (Get-HudBufferedField $sample 'actual') 'actual observed point'
        $error=Get-HudBufferedNumber (Get-HudBufferedField $sample 'readback_error') 'observed readback error' 0 .05
        $measured=Get-HudBufferedDistance $requested $actual
        if($measured -gt .05 -or [Math]::Abs($error-$measured) -gt .000001 -or $maxError+.000001 -lt $measured){throw 'Buffered observed drift differs from the reported proof.'}
        Assert-HudBufferedFlag (Get-HudBufferedField $sample 'camera_basis_valid') 'observed camera basis' $true
        $camera=Get-HudBufferedCamera (Get-HudBufferedField $sample 'camera') 'observed camera'
        $didWrite=Get-HudBufferedField $sample 'write_performed'
        if($didWrite -isnot [bool]){throw 'Observed setter ownership must be explicit.'}
        if($didWrite){$retainedSetters++}
        $delay=($observed-$written)*1000
        if($maxGap+.001 -lt $delay){throw 'Observation gap summary hides a retained delayed sample.'}
        $gaps.Add($delay);$largestError=[Math]::Max($largestError,$measured)
        $last=[pscustomobject]@{From=$from;To=$to;Fraction=$fraction;Playback=$playback;Requested=$requested;Actual=$actual;
            Camera=$camera;Observed=$observed;Written=$written;DidWrite=$didWrite;DestinationAccepted=$accepted}
        $previousWritten=$written;$previousObserved=$observed;$previousPlayback=$playback
    }
    if($updates -lt $retainedSetters -or (-not $truncated -and ($updates -ne $retainedSetters -or $maxError-$largestError -gt .000001))) {
        throw 'Setter/error summary differs from complete retained observations.'
    }
    # Highest crossed source is the left anchor. A sample exactly at its right
    # endpoint may name that endpoint; it still cannot claim a source endpoint
    # was written merely because its timeline was crossed.
    $highest=if(-not $hold -and $last.Fraction -eq 1){$last.To}else{$last.From}
    if($source.Seq -ne $highest.Seq -or $sourceMs -gt $last.Playback+.001 -or $sampled -ne $last.Observed){
        throw 'Buffered source ACK is not backed by its final retained observation.'
    }
    $target=Get-HudBufferedVector (Get-HudBufferedField $Receipt 'target') 'receipt actual target'
    $player=Get-HudBufferedVector (Get-HudBufferedField $Receipt 'player') 'receipt player'
    foreach($axis in @('x','y','z')){
        if($target.$axis -ne $last.Requested.$axis -or $player.$axis -ne $last.Actual.$axis){throw 'Buffered receipt point differs from its final observation.'}
    }
    $playerError=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'player_readback_error') 'receipt player error' 0 .05
    if([Math]::Abs($playerError-(Get-HudBufferedDistance $target $player)) -gt .000001){throw 'Buffered player error summary differs.'}
    $ackWrite=Get-HudBufferedField $Receipt 'acknowledged_write_performed'
    Assert-HudBufferedFlag $ackWrite 'acknowledged setter' $last.DidWrite
    $receiptCamera=Get-HudBufferedCamera (Get-HudBufferedField $Receipt 'camera') 'receipt camera'
    foreach($part in @('position','forward','up')){
        foreach($axis in @('x','y','z')){if($receiptCamera.$part.$axis -ne $last.Camera.$part.$axis){throw 'Receipt camera differs from the delayed sample.'}}
    }
    if($receiptCamera.fov -ne $last.Camera.fov){throw 'Receipt camera FOV differs from the delayed sample.'}
    $ordered=@($gaps | Sort-Object)
    return [pscustomobject]@{Sequence=$seq;CrossedSourceSeq=$sourceSeq;SourceIndex=$source.Index;SourceMs=$sourceMs;SourcePointsCrossed=$crossed;
        EpochEngineSeconds=$epoch;PlaybackSourceMs=$last.Playback;
        SourceEndpointWritten=($last.DidWrite -and (Get-HudBufferedDistance $target ([pscustomobject]@{x=[double][single]$source.Target.x;y=[double][single]$source.Target.y;z=[double][single]$source.Target.z})) -eq 0);
        Observations=$observations;RetainedObservations=$samples.Count;CompleteObservations=(-not $truncated);
        Updates=$updates;RetainedSetters=$retainedSetters;MedianObservationDelayMs=$ordered[[int][Math]::Floor(($ordered.Count-1)/2)];
        MaximumRetainedObservationDelayMs=$ordered[-1];MaximumRetainedError=$largestError;ActualTarget=$target}
}
