# Buffered source timing, observed-path proof and disposable warmup. No game calls.
. (Join-Path $PSScriptRoot 'HudWalkingSession.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingArea.ps1')
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
function Assert-HudWalkingFollowerSession($Receipts,[switch]$ExtendedWalking,[switch]$WideWalking,[switch]$CorridorWalking) {
    if($CorridorWalking -and -not $ExtendedWalking){throw 'Physical corridor requires the extended buffered session.'}
    $session=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
    if(@($Receipts).Count -lt 1 -or @($Receipts).Count -gt $session.Receipts){throw 'Follower receipt budget exceeded or absent.'}
    foreach($receipt in $Receipts){
        Assert-HudWalkingArea $receipt ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
        Assert-HudWalkingSession $receipt -ExtendedWalking:$ExtendedWalking
        [void](Get-HudBufferedNumber (Get-HudBufferedField $receipt 'hard_deadline_ms') 'hard deadline' $session.DeadlineMs $session.DeadlineMs)
        [void](Get-HudBufferedInteger (Get-HudBufferedField $receipt 'writes') 'follower writes' 0 ($session.OrdinaryWrites+1))
        # Restoration is observed on a later frame; it does not extend motion authority.
        [void](Get-HudBufferedNumber (Get-HudBufferedField $receipt 'elapsed_ms') 'follower elapsed' 0 ($session.DeadlineMs+1000))
    }
}
function Assert-HudWalkingDuration($Movement,[switch]$ExtendedWalking) {
    $session=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
    $minimum=if($ExtendedWalking){$session.InputMs}else{0}
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Movement 'duration_ms') 'completed movement duration' $minimum $session.SourceMs)
}
function New-HudBufferedSourceState([switch]$ExtendedWalking) {
    return [pscustomobject]@{Kind='minecome_hud_buffered_source_state_v1';Count=0;
        ExtendedWalking=[bool]$ExtendedWalking;AnchorNs=$null;LastSourceNs=$null;LastMonotonicNs=$null;LastTraceSeq=0L;LastServerSeq=0L}
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
        $session=Get-HudWalkingSession -ExtendedWalking:$State.ExtendedWalking
        if($elapsed -lt 0 -or $elapsed -gt ([decimal]$session.SourceMs*1000000)){throw 'Buffered source exceeds the selected trace duration.'}
        $milliseconds=[double]($elapsed/1000000)
    }
    # No state changes until every check succeeds. The caller still enforces
    # provenance, source freshness, terrain and dispatch ownership.
    $State.AnchorNs=$anchor;$State.LastSourceNs=$source;$State.LastMonotonicNs=$monotonic
    $State.LastTraceSeq=$seq;$State.LastServerSeq=$serverSeq;$State.Count=[int]($count+1)
    return [double]$milliseconds
}
function Initialize-HudBufferedMovementPipeline {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PatchFile,
        [Parameter(Mandatory)][string]$ExpectedHudSave,
        [Parameter(Mandatory)]$MinimumUtcMs,[switch]$ExtendedWalking,[switch]$WideWalking,[switch]$CorridorWalking,$Corridor)
    $ErrorActionPreference='Stop'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        # This receiver is disposable diagnostic state, never the live receiver.
        # Validate the caller's inputs normally, then bind only this fresh state
        # to a separate synthetic world so these records cannot name the HUD save.
        $diagnosticReceiver=New-MineComeTraceReceiver -PatchFile $PatchFile -MinimumUtcMs $MinimumUtcMs `
            -ExpectedHudSave $ExpectedHudSave -PhysicalMovement -BufferedPhysicalMovement -ExtendedWalking:$ExtendedWalking -WideWalking:$WideWalking -CorridorWalking:$CorridorWalking -Corridor $Corridor
        $diagnosticWorld=[Guid]::NewGuid().ToString('D')
        $diagnosticSave='MineCome-HudStream-'+$diagnosticWorld
        $diagnosticReceiver.ExpectedHudSave=$diagnosticSave
        $diagnosticClock=New-HudBufferedSourceState -ExtendedWalking:$ExtendedWalking
        $diagnosticIdentity=[ordered]@{schema=1;run=$diagnosticReceiver.ExpectedRun;patch_sha256=$diagnosticReceiver.PatchHash;
            source_kind=$(if($CorridorWalking){'live_kcd_hud_physical_movement_corridor'}else{(Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking).SourceKind});save=$diagnosticSave;world=$diagnosticWorld;utc_ms=[long]$MinimumUtcMs}
        if($CorridorWalking){$diagnosticIdentity.walking_area='corridor'}elseif($WideWalking){$diagnosticIdentity.walking_area='wide'}
        $diagnosticBegin=[ordered]@{}
        foreach($entry in $diagnosticIdentity.GetEnumerator()){$diagnosticBegin[$entry.Key]=$entry.Value}
        $diagnosticBegin.kind='begin';$diagnosticBegin.seq=1L;$diagnosticBegin.phase='SETTLING'
        $diagnosticBegin.started_monotonic_ns=0L;$diagnosticBegin.center=$diagnosticReceiver.Center
        $diagnosticY=if($CorridorWalking){$diagnosticReceiver.InitialGroundY}else{64.0}
        $diagnosticBegin.anchor_mc=[pscustomobject]@{x=0.0;y=$diagnosticY;z=0.0}
        $diagnosticBegin.approximate_heightfield=$true;$diagnosticBegin.full_collision_export_verified=$false
        $diagnosticResult=Receive-MineComeMovementTrace -State $diagnosticReceiver `
            -JsonLine (ConvertTo-Json -InputObject $diagnosticBegin -Depth 8 -Compress) -NowUtcMs $MinimumUtcMs
        if($diagnosticResult.Kind -cne 'begin'){throw 'Diagnostic buffered warmup did not accept its synthetic begin.'}
        # Exercise both first-anchor and subsequent normalization branches. No
        # synthetic trace, source time, target or receiver is emitted or saved.
        foreach($index in 1..2){
            $diagnosticSample=[ordered]@{}
            foreach($entry in $diagnosticIdentity.GetEnumerator()){$diagnosticSample[$entry.Key]=$entry.Value}
            $diagnosticSample.kind='sample';$diagnosticSample.seq=[long]($index+1)
            $diagnosticSample.phase=if($index -eq 1){'SETTLING'}else{'RESTING'}
            $diagnosticSample.monotonic_ns=[long]($index*100000000);$diagnosticSample.server_seq=[long]$index
            $diagnosticSample.server_age_ns=0L
            $diagnosticSample.client=[pscustomobject]@{x=0.0;y=$diagnosticY;z=0.0;vx=0.0;vy=0.0;vz=0.0;on_ground=$true;proxy_support=$true}
            $diagnosticSample.server=[pscustomobject]@{x=0.0;y=$diagnosticY;z=0.0;vx=0.0;vy=0.0;vz=0.0;on_ground=$true;proxy_support=$true}
            $diagnosticJson=ConvertTo-Json -InputObject $diagnosticSample -Depth 8 -Compress
            $diagnosticResult=Receive-MineComeMovementTrace -State $diagnosticReceiver -JsonLine $diagnosticJson -NowUtcMs $MinimumUtcMs
            if($diagnosticResult.Kind -cne 'sample'){throw 'Diagnostic buffered warmup did not accept its synthetic stationary sample.'}
            $diagnosticParsed=ConvertFrom-Json -InputObject $diagnosticJson
            $diagnosticSourceMs=Get-HudBufferedSourceTime -State $diagnosticClock -Record $diagnosticParsed
            if($diagnosticSourceMs -ne ($index-1)*100){throw 'Diagnostic buffered warmup source-time check failed.'}
        }
    } finally {$watch.Stop()}
    return [pscustomobject]@{kind='diagnostic_warmup';status='completed';diagnostic_records=3;
        elapsed_ms=[Math]::Round($watch.Elapsed.TotalMilliseconds,3)}
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
function Assert-HudBufferedMovementReceipt($Receipt,$Forwarded,[switch]$ExtendedWalking,[switch]$WideWalking,[switch]$CorridorWalking) {
    if($CorridorWalking -and -not $ExtendedWalking){throw 'Physical corridor requires the extended buffered session.'}
    Assert-HudWalkingArea $Receipt ([bool]$WideWalking) -CorridorWalking:$CorridorWalking
    $session=Get-HudWalkingSession -ExtendedWalking:$ExtendedWalking
    Assert-HudWalkingSession $Receipt -ExtendedWalking:$ExtendedWalking
    # This proves retained observed path samples, not unrecorded frames or visual
    # smoothness. The caller separately pins run/process/source provenance and
    # checks common epoch/increasing source acknowledgements across receipts.
    if($Forwarded -isnot [Collections.ICollection] -or $Forwarded.Count -lt 1 -or $Forwarded.Count -gt 200) {
        throw 'Buffered proof requires one to 200 dispatched source points.'
    }
    $points=[Collections.Generic.List[object]]::new();$bySeq=@{};$lastSeq=0L;$lastMs=-1.0
    foreach($point in $Forwarded){
        $seq=Get-HudBufferedInteger (Get-HudBufferedField $point 'TraceSeq') 'forwarded sequence' 1 200
        $ms=Get-HudBufferedNumber (Get-HudBufferedField $point 'SourceMs') 'forwarded source time' 0 $session.SourceMs
        if($ms -ne [double][single]$ms){throw 'Forwarded SourceMs must retain the exact float32 wire value.'}
        $target=Get-HudBufferedVector (Get-HudBufferedField $point 'Target') 'forwarded target'
        if($CorridorWalking -and $points.Count -gt 0){
            # Source zero is the real settled anchor mapped to the saved KCD
            # origin, never the centre of the second tile or a rolling anchor.
            $origin=$points[0].Target
            if($target.x -lt $origin.x-3.5 -or $target.x -gt $origin.x+7.5 -or
                $target.y -lt $origin.y-3.5 -or $target.y -gt $origin.y+3.5 -or
                $target.z -lt $origin.z-6.1 -or $target.z -gt $origin.z+3.5){throw 'Buffered corridor source leaves its immutable rectangle.'}
        }
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
    $sourceMs=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'source_ms') 'acknowledged source time' 0 $session.SourceMs
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
    $sampled=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'sampled_engine_seconds') 'receipt engine time' $epoch ($epoch+$session.DeadlineMs/1000)
    $sourceAge=Get-HudBufferedNumber (Get-HudBufferedField $Receipt 'target_receipt_age_ms') 'acknowledged source age' 0 400
    if($sourceAge -le 0){throw 'Buffered source ACK must be delayed after acceptance.'}
    $sourceAccepted=$sampled-$sourceAge/1000
    if($sourceAccepted -lt $epoch-.2-$originTolerance){throw 'Source acknowledgement predates the initial acceptance.'}
    $singleSourceAccepted=[double][single]$sourceAccepted
    $singleInitialEpoch=[double][single]($singleSourceAccepted+[double][single]0.2)
    if($sourceMs -eq 0 -and -not (Test-HudBufferedArithmetic $epoch ($sourceAccepted+.2) $singleInitialEpoch)){
        throw 'The source-zero acknowledgement does not anchor the fixed 200 ms epoch.'
    }
    $updates=Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'segment_update_count') 'segment setter count' 0 $session.OrdinaryWrites
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
        $fromMs=Get-HudBufferedNumber (Get-HudBufferedField $sample 'bracket_from_ms') 'left source time' 0 $session.SourceMs
        $toMs=Get-HudBufferedNumber (Get-HudBufferedField $sample 'bracket_to_ms') 'right source time' 0 $session.SourceMs
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
        $playback=Get-HudBufferedNumber (Get-HudBufferedField $sample 'playback_source_ms') 'playback source time' 0 $session.DeadlineMs
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
