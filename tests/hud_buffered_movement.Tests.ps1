#Requires -Version 7.3
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudBufferedMovement.ps1')
$checks=0
function Check([bool]$Condition,[string]$Reason){$script:checks++;if(-not $Condition){throw $Reason}}
function Reject([scriptblock]$Work,[string]$Reason){$rejected=$false;try{& $Work | Out-Null}catch{$rejected=$true};Check $rejected $Reason}
function Clone($Value){return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json}
function ClockRecord([long]$Seq,[long]$Mono,[long]$Age,[long]$Server,[string]$Phase='RESTING'){
    return [pscustomobject]@{kind='sample';seq=$Seq;monotonic_ns=$Mono;server_age_ns=$Age;server_seq=$Server;phase=$Phase}
}
function V([double]$X,[double]$Y=0,[double]$Z=0){return [pscustomobject]@{x=$X;y=$Y;z=$Z}}
function Camera($Point){return [pscustomobject]@{position=(V $Point.x $Point.y ($Point.z+1.6));forward=(V 0 1 0);up=(V 0 0 1);fov=1.2}}

$state=New-HudBufferedSourceState
Check ((Get-HudBufferedSourceTime $state (ClockRecord 2 100000000000 20000000 10 SETTLING)) -eq 0) 'First actual server observation must anchor source zero'
Check ((Get-HudBufferedSourceTime $state (ClockRecord 3 100130000000 50000000 12)) -eq 100) 'Playback must preserve server observation time rather than client capture cadence'
Check ($state.LastSourceNs -eq 100080000000 -and $state.Count -eq 2) 'Validated source state was not committed'
$before=$state | ConvertTo-Json -Compress
Reject {Get-HudBufferedSourceTime $state (ClockRecord 4 100140000000 80000000 13)} 'A newer client capture with older server observation passed'
Check (($state | ConvertTo-Json -Compress) -ceq $before) 'Rejected clock changed the source state'
Reject {Get-HudBufferedSourceTime $state (ClockRecord 4 100140000000 60000000 13)} 'Repeated actual server clock passed'
Reject {Get-HudBufferedSourceTime $state (ClockRecord 4 100120000000 0 13)} 'Regressed client monotonic clock passed'
Reject {Get-HudBufferedSourceTime $state (ClockRecord 3 100150000000 0 13)} 'Repeated trace sequence passed'
Reject {Get-HudBufferedSourceTime $state (ClockRecord 4 100150000000 0 12)} 'Repeated server sequence passed'
Reject {Get-HudBufferedSourceTime (New-HudBufferedSourceState) (ClockRecord 2 100 0 1 WALKING)} 'Missing initial settling source passed'
Reject {Get-HudBufferedSourceTime (New-HudBufferedSourceState) (ClockRecord 2 100 -1 1 SETTLING)} 'Negative server age passed'
Reject {Get-HudBufferedSourceTime (New-HudBufferedSourceState) (ClockRecord 2 1000000000 250000001 1 SETTLING)} 'Unbounded server age passed'
Reject {Get-HudBufferedSourceTime (New-HudBufferedSourceState) (ClockRecord 2 ([long]::MinValue) 1 1 SETTLING)} 'Signed server-clock underflow passed'
$bad=ClockRecord 2 100 0 1 SETTLING;$bad.monotonic_ns=[double]100
Reject {Get-HudBufferedSourceTime (New-HudBufferedSourceState) $bad} 'Floating nanosecond clock passed and could lose precision'
$negative=New-HudBufferedSourceState
Check ((Get-HudBufferedSourceTime $negative (ClockRecord 2 -10000000000 20000000 1 SETTLING)) -eq 0) 'Signed System.nanoTime is valid'
Check ((Get-HudBufferedSourceTime $negative (ClockRecord 3 -9900000000 20000000 2)) -eq 100) 'Negative monotonic source normalization failed'
$precise=New-HudBufferedSourceState
[void](Get-HudBufferedSourceTime $precise (ClockRecord 2 ([long]::MaxValue-10) 0 1 SETTLING))
Check ((Get-HudBufferedSourceTime $precise (ClockRecord 3 ([long]::MaxValue-9) 0 2)) -eq .000001) 'Nanosecond difference above double integer precision was lost'
$bounded=New-HudBufferedSourceState
[void](Get-HudBufferedSourceTime $bounded (ClockRecord 2 0 0 1 SETTLING))
Check ((Get-HudBufferedSourceTime $bounded (ClockRecord 3 6000000000 0 2 PASSED)) -eq 6000) 'Exact six-second source limit rejected'
Reject {Get-HudBufferedSourceTime $bounded (ClockRecord 4 6000000001 0 3)} 'Six-second source bound extended'
$bounded.Count=200
Reject {Get-HudBufferedSourceTime $bounded (ClockRecord 5 6000000002 0 4)} 'Unbounded source-record state passed'

# A real buffered ACK can cross source time100 while the actor is already part
# way along100..250. It must prove the actual point1.08, not pretend source1.0
# was written. Server targets intentionally include a non-float32 decimal.
$forwarded=@(
    [pscustomobject]@{TraceSeq=2L;SourceMs=0.0;Target=(V 0)},
    [pscustomobject]@{TraceSeq=3L;SourceMs=100.0;Target=(V 1)},
    [pscustomobject]@{TraceSeq=4L;SourceMs=250.0;Target=(V 2)},
    [pscustomobject]@{TraceSeq=5L;SourceMs=400.0;Target=(V 3)}
)
function Make-Sample([double]$Playback,[long]$Frame){
    $from=if($Playback -lt 100){$forwarded[0]}else{$forwarded[1]}
    $to=if($Playback -lt 100){$forwarded[1]}else{$forwarded[2]}
    $fraction=($Playback-$from.SourceMs)/($to.SourceMs-$from.SourceMs)
    $requested=V ($from.Target.x+($to.Target.x-$from.Target.x)*$fraction)
    $actual=V ([double][single]$requested.x)
    return [pscustomobject]@{fraction=$fraction;requested=$requested;actual=$actual;
        written_engine_seconds=10.2+$Playback/1000;observed_engine_seconds=10.216+$Playback/1000;
        written_frame_id=$Frame;observed_frame_id=$Frame+1;write_performed=$true;
        readback_error=[Math]::Abs($actual.x-$requested.x);camera=(Camera $actual);camera_basis_valid=$true;
        bracket_from_seq=$from.TraceSeq;bracket_from_ms=$from.SourceMs;bracket_from_target=$from.Target;
        bracket_to_seq=$to.TraceSeq;bracket_to_ms=$to.SourceMs;bracket_to_target=$to.Target;
        bracket_to_received_engine_seconds=if($to.TraceSeq -eq 3){10.1}else{10.25};
        playback_source_ms=$Playback;source_hold=$false}
}
$samples=@(for($i=2;$i -le 7;$i++){Make-Sample (16*$i) (100+$i)})
$last=$samples[-1]
$receipt=[pscustomobject]@{position_mode='source_time_buffered';event='applied';result='applied_readback';
    playback_delay_ms=200;playback_epoch_engine_seconds=10.2;physical_movement=$true;readback=$true;camera_basis_valid=$true;terminal=$false;
    interpolation_ms=$null;endpoint_write_performed=$null;seq=3L;source_seq=3L;source_ms=100.0;source_target=(V 1);
    source_points_crossed=1;sampled_engine_seconds=$last.observed_engine_seconds;target_receipt_age_ms=228.0;
    segment_update_count=$samples.Count;segment_observation_count=$samples.Count;segment_max_readback_error=($samples.readback_error | Measure-Object -Maximum).Maximum;
    segment_max_observation_gap_ms=16.0;segment_observed_samples_truncated=$false;segment_observed_samples=$samples;
    target=$last.requested;player=$last.actual;player_readback_error=$last.readback_error;
    acknowledged_write_performed=$true;camera=$last.camera}
$proof=Assert-HudBufferedMovementReceipt $receipt $forwarded
Check ($proof.CrossedSourceSeq -eq 3 -and $proof.SourceMs -eq 100 -and $proof.PlaybackSourceMs -eq 112) 'Buffered ACK source timeline was not preserved'
Check ($proof.SourceIndex -eq 1) 'Caller cannot verify each crossing count against dispatched history'
Check (-not $proof.SourceEndpointWritten -and $proof.ActualTarget.x -ne 1) 'Intermediate actual point was falsely claimed as the crossed source endpoint'
Check ($proof.CompleteObservations -and $proof.Updates -eq 6 -and $proof.MaximumRetainedObservationDelayMs -lt 16.01) 'Complete normal-frame observation proof rejected'

foreach($field in @('readback','physical_movement','camera_basis_valid')){
    $bad=Clone $receipt;$bad.$field='true'
    Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} "Non-Boolean $field passed"
}
$bad=Clone $receipt;$bad.position_mode=@('source_time_buffered')
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'An array substituted for a protocol discriminator passed'
$bad=Clone $receipt;$bad.source_seq=199
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Unknown acknowledged sequence passed'
$bad=Clone $receipt;$bad.source_ms=101
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Acknowledged source time mismatch passed'
$bad=Clone $receipt;$bad.source_target.x=1.0001
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Exact float32 source mismatch passed'
$bad=Clone $receipt;$bad.target=$bad.source_target
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Source endpoint substituted for actual interpolated point passed'
$bad=Clone $receipt;$bad.source_points_crossed=9
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Unbounded source crossing count passed'
$bad=Clone $receipt;$bad.source_points_crossed=3
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Crossing more source points than exist passed'
$bad=Clone $receipt;$bad.target_receipt_age_ms=400.001
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Expired crossed source ACK passed'
$bad=Clone $receipt;$bad.playback_delay_ms=300
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Changing playback delay passed'
$bad=Clone $receipt;$bad.playback_epoch_engine_seconds+=.01
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Changing epoch without source-time evidence passed'
$bad=Clone $receipt;$bad.interpolation_ms=100
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Fixed-duration compression claim passed buffered proof'
$bad=Clone $receipt;$bad.endpoint_write_performed=$true
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Unproven source endpoint write claim passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].bracket_to_seq=199
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Unknown source bracket passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].bracket_to_seq=4;$bad.segment_observed_samples[0].bracket_to_ms=250;$bad.segment_observed_samples[0].bracket_to_target=V 2
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Skipped intermediate source point in bracket passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].bracket_to_target.x=1.001
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Source target mismatch inside bracket passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].fraction+=.01
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Fraction not corresponding to source time passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].fraction=1.01
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Extrapolated fraction passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].playback_source_ms+=1
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Playback time detached from engine clock passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].requested.y=.001
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Off-path requested point passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].actual.y=.051
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Native observed drift hidden by summary passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].readback_error=.01
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'False actual readback error passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].observed_engine_seconds=$bad.segment_observed_samples[0].written_engine_seconds
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Same-clock observation passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].observed_frame_id=$bad.segment_observed_samples[0].written_frame_id
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Same native frame observation passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].written_frame_id=$null
Check ((Assert-HudBufferedMovementReceipt $bad $forwarded).Observations -eq 6) 'One unavailable diagnostic frame ID invalidated later clock proof'
$bad=Clone $receipt;$bad.segment_observed_samples[0].observed_frame_id=$null
Check ((Assert-HudBufferedMovementReceipt $bad $forwarded).Observations -eq 6) 'Unavailable observed frame ID invalidated later clock proof'
$bad=Clone $receipt;$bad.segment_observed_samples[0].written_frame_id=$null;$bad.segment_observed_samples[0].observed_frame_id=-1
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Present invalid frame identity passed just because its counterpart was unavailable'
$bad=Clone $receipt;$bad.segment_observed_samples[0].camera.forward=V 0 0 0
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Invalid camera hidden by valid-basis flag passed'
$bad=Clone $receipt;$bad.segment_observed_samples[0].camera.position.x=[double]::NaN
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Nonfinite observed camera passed'
$bad=Clone $receipt;$bad.camera.position.x+=.01
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Receipt camera differs from actual delayed observation'
$bad=Clone $receipt;$bad.sampled_engine_seconds+=.001
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Final receipt time differs from its observed sample'
$bad=Clone $receipt;$bad.acknowledged_write_performed=$false
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Final setter ownership differs from its observed sample'
$bad=Clone $receipt;$bad.segment_update_count--
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Hidden retained setter passed'
$bad=Clone $receipt;$bad.segment_observation_count=9000
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Unbounded observation count passed'
$bad=Clone $receipt;$bad.segment_observed_samples=@($bad.segment_observed_samples)*2
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'More than eight retained samples passed'
$bad=Clone $receipt;$bad.segment_observed_samples_truncated=$true
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Inconsistent truncation summary passed'
$bad=Clone $receipt;$bad.segment_max_observation_gap_ms=1
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Gap summary concealed actual later observation delay'

# Nullable frame IDs are diagnostic only. Honest truncation remains explicit and
# does not promote unrecorded frames into complete proof.
$partial=Clone $receipt
foreach($sample in $partial.segment_observed_samples){$sample.written_frame_id=$null;$sample.observed_frame_id=$null}
Check ((Assert-HudBufferedMovementReceipt $partial $forwarded).Observations -eq 6) 'Engine-time proof wrongly requires optional native frame IDs'
$partial.segment_observed_samples=@($partial.segment_observed_samples[0],$partial.segment_observed_samples[-1]);$partial.segment_observed_samples_truncated=$true
$proof=Assert-HudBufferedMovementReceipt $partial $forwarded
Check (-not $proof.CompleteObservations -and $proof.RetainedObservations -eq 2 -and $proof.Observations -eq 6) 'Truncated evidence incorrectly claimed complete observations'

# Holding a known endpoint is allowed after its source time; extrapolating beyond
# its coordinate is not. A no-write observation must not claim an endpoint write.
$hold=Clone $receipt;$hs=$hold.segment_observed_samples[-1]
$hs.bracket_from_seq=3L;$hs.bracket_to_seq=3L;$hs.bracket_from_ms=100.0;$hs.bracket_to_ms=100.0
$hs.bracket_from_target=V 1;$hs.bracket_to_target=V 1;$hs.bracket_to_received_engine_seconds=10.1
$hs.fraction=0.0;$hs.source_hold=$true;$hs.requested=V 1;$hs.actual=V 1;$hs.readback_error=0.0;$hs.write_performed=$false;$hs.camera=Camera $hs.actual
$hold.segment_observed_samples=@($hs);$hold.segment_update_count=0;$hold.segment_observation_count=1;$hold.segment_max_readback_error=0.0
$hold.target=$hs.requested;$hold.player=$hs.actual;$hold.player_readback_error=0.0;$hold.camera=$hs.camera;$hold.acknowledged_write_performed=$false
$proof=Assert-HudBufferedMovementReceipt $hold $forwarded
Check ($proof.Updates -eq 0 -and -not $proof.SourceEndpointWritten) 'Observed stationary hold became a false endpoint setter'
$bad=Clone $hold;$bad.segment_observed_samples[0].requested.x=1.1
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Hold extrapolated beyond its known coordinate'
$bad=Clone $hold;$bad.segment_observed_samples[0].source_hold=$false
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Degenerate bracket falsely claimed interpolation'
$bad=Clone $hold;$bad.segment_observed_samples[0].bracket_to_received_engine_seconds=10.0;$bad.segment_observed_samples[0].written_engine_seconds=10.401;$bad.segment_observed_samples[0].observed_engine_seconds=10.417;$bad.segment_observed_samples[0].playback_source_ms=201
$bad.sampled_engine_seconds=10.417;$bad.target_receipt_age_ms=317
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Expired original destination lease passed despite a fresh top-level source age'
$bad=Clone $hold;$bad.segment_observed_samples[0].bracket_to_received_engine_seconds=10.4
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'Destination accepted after its alleged write passed'
$badForward=Clone $forwarded;$badForward[0].SourceMs=1
Reject {Assert-HudBufferedMovementReceipt $receipt $badForward} 'Missing source-zero anchor passed'
$badForward=Clone $forwarded;$badForward[2].SourceMs=100
Reject {Assert-HudBufferedMovementReceipt $receipt $badForward} 'Repeated forwarded source time passed'
$badForward=Clone $forwarded;$badForward[2].TraceSeq=3L
Reject {Assert-HudBufferedMovementReceipt $receipt $badForward} 'Ambiguous source sequence passed'
$badForward=@($forwarded)*51
Reject {Assert-HudBufferedMovementReceipt $receipt $badForward} 'Unbounded forwarded dataset passed'
$badForward=Clone $forwarded;$badForward[1].SourceMs=100.123456789
Reject {Assert-HudBufferedMovementReceipt $receipt $badForward} 'Precise timestamp silently substituted for the transmitted float32 timestamp'

# Numeric regression: these source vectors, fraction and requested point are
# copied from the c869 timed-interpolation evidence. The wrapper below is a
# synthetic buffered receipt; it is not relabelled live buffered verification.
$nativeForward=@(
    [pscustomobject]@{TraceSeq=2L;SourceMs=0.0;Target=(V 120.17870330810547 2040.6510009765625 56.29341506958008)},
    [pscustomobject]@{TraceSeq=3L;SourceMs=100.0;Target=(V 120.20343780517578 2040.745849609375 56.29341506958008)}
)
$native=Clone $hold;$ns=$native.segment_observed_samples[0]
$native.playback_epoch_engine_seconds=105.48889923095703
$firstAccepted=[double][single]($native.playback_epoch_engine_seconds-[double][single]0.2)
$ns.written_engine_seconds=105.50477600097656;$ns.observed_engine_seconds=105.52064514160156
$ns.bracket_from_seq=2L;$ns.bracket_from_ms=0.0;$ns.bracket_from_target=$nativeForward[0].Target
$ns.bracket_to_seq=3L;$ns.bracket_to_ms=100.0;$ns.bracket_to_target=$nativeForward[1].Target
$ns.bracket_to_received_engine_seconds=$firstAccepted+.1
$ns.playback_source_ms=15.87677001953125;$ns.fraction=.1587677001953125;$ns.source_hold=$false
$ns.requested=V 120.18263244628906 2040.666015625 56.29341506958008;$ns.actual=Clone $ns.requested
$ns.camera=Camera $ns.actual;$ns.write_performed=$true
$native.seq=2L;$native.source_seq=2L;$native.source_ms=0.0;$native.source_target=$nativeForward[0].Target
$native.source_points_crossed=1;$native.sampled_engine_seconds=$ns.observed_engine_seconds
$native.target_receipt_age_ms=[double][single](($native.sampled_engine_seconds-$firstAccepted)*1000)
$native.segment_update_count=1;$native.segment_max_observation_gap_ms=($ns.observed_engine_seconds-$ns.written_engine_seconds)*1000
$native.target=$ns.requested;$native.player=$ns.actual;$native.camera=$ns.camera;$native.acknowledged_write_performed=$true
$proof=Assert-HudBufferedMovementReceipt $native $nativeForward
Check (-not $proof.SourceEndpointWritten -and $proof.MaximumRetainedError -eq 0) 'Actual float32 interpolation arithmetic falsely failed double-only path proof'
$bad=Clone $native;$bad.segment_observed_samples[0].requested.y+=.0005
Reject {Assert-HudBufferedMovementReceipt $bad $nativeForward} 'Native precision handling became a broad off-path tolerance'

# At1800 seconds, float32(clock+.2) differs from double by about49 microseconds.
# Preserve that exact numeric path without letting the epoch be renewed.
$longClock=Clone $hold;$lc=$longClock.segment_observed_samples[0];$initial=1800.0
$longClock.playback_epoch_engine_seconds=[double][single]($initial+[double][single]0.2)
$lc.written_engine_seconds=[double][single]($longClock.playback_epoch_engine_seconds+[double][single]0.016)
$lc.observed_engine_seconds=[double][single]($lc.written_engine_seconds+[double][single]0.016)
$lc.playback_source_ms=[double][single](($lc.written_engine_seconds-$longClock.playback_epoch_engine_seconds)*1000)
$lc.bracket_from_seq=2L;$lc.bracket_to_seq=2L;$lc.bracket_from_ms=0.0;$lc.bracket_to_ms=0.0
$lc.bracket_from_target=V 0;$lc.bracket_to_target=V 0;$lc.bracket_to_received_engine_seconds=$initial
$lc.requested=V 0;$lc.actual=V 0;$lc.camera=Camera $lc.actual
$longClock.seq=2L;$longClock.source_seq=2L;$longClock.source_ms=0.0;$longClock.source_target=V 0
$longClock.sampled_engine_seconds=$lc.observed_engine_seconds
$longClock.target_receipt_age_ms=[double][single](($lc.observed_engine_seconds-$initial)*1000)
$longClock.segment_max_observation_gap_ms=[double][single](($lc.observed_engine_seconds-$lc.written_engine_seconds)*1000)
$longClock.target=$lc.requested;$longClock.player=$lc.actual;$longClock.camera=$lc.camera
Check ((Assert-HudBufferedMovementReceipt $longClock $forwarded).SourceMs -eq 0) 'Exact float32 initial epoch arithmetic failed at a long-running engine clock'
$bad=Clone $longClock;$bad.playback_epoch_engine_seconds=[double][MathF]::BitIncrement([single]$bad.playback_epoch_engine_seconds)
Reject {Assert-HudBufferedMovementReceipt $bad $forwarded} 'An independently shifted initial epoch passed native precision proof'

# Extension must be explicit at both ends, never inferred from a large clock.
$extended=New-HudBufferedSourceState -ExtendedWalking
[void](Get-HudBufferedSourceTime $extended (ClockRecord 2 0 0 1 SETTLING))
Check ((Get-HudBufferedSourceTime $extended (ClockRecord 3 10100000000 0 2)) -eq 10100) 'Extended source after the old deadline was rejected'
Check ((Get-HudBufferedSourceTime $extended (ClockRecord 4 16000000000 0 3 PASSED)) -eq 16000) 'Exact extended source limit rejected'
$before=Clone $extended
Reject {Get-HudBufferedSourceTime $extended (ClockRecord 5 16000000001 0 4)} 'Extended source duration became unbounded'
Check (($extended | ConvertTo-Json -Compress) -ceq ($before | ConvertTo-Json -Compress)) 'Rejected source changed clock state'

$extendedPoints=Clone $forwarded
for($i=1;$i -lt $extendedPoints.Count;$i++){$extendedPoints[$i].SourceMs+=10000}
$extendedAck=Clone $receipt
$extendedAck | Add-Member movement_session extended
$extendedAck.source_ms+=10000
$s=Clone $samples[-1]
foreach($field in @('written_engine_seconds','observed_engine_seconds','bracket_to_received_engine_seconds')){$s.$field+=10}
foreach($field in @('bracket_from_ms','bracket_to_ms','playback_source_ms')){$s.$field+=10000}
$extendedAck.sampled_engine_seconds=$s.observed_engine_seconds
$extendedAck.segment_update_count=1;$extendedAck.segment_observation_count=1
$extendedAck.segment_max_readback_error=$s.readback_error
$extendedAck.segment_observed_samples=@($s)
Check ((Assert-HudBufferedMovementReceipt $extendedAck $extendedPoints -ExtendedWalking).SourceMs -eq 10100) 'Delayed extended native observation did not preserve its original source clock'
Reject {Assert-HudBufferedMovementReceipt $extendedAck $extendedPoints} 'Extended receipt crossed into default profile'
Reject {Assert-HudBufferedMovementReceipt $receipt $forwarded -ExtendedWalking} 'Unlabelled short receipt impersonated extended playback'
foreach($value in @($null,15,'EXTENDED','short',$true)){
    $bad=Clone $extendedAck;$bad.movement_session=$value
    Reject {Assert-HudBufferedMovementReceipt $bad $extendedPoints -ExtendedWalking} 'Malformed or mismatched native session accepted'
}
$summary=[pscustomobject]@{movement_session='extended';hard_deadline_ms=18000;writes=2048;elapsed_ms=16050}
Assert-HudWalkingFollowerSession @($summary) -ExtendedWalking
Reject {Assert-HudWalkingFollowerSession @($summary)} 'Extended native bounds accepted by short controller'
$summary.writes=2049
Reject {Assert-HudWalkingFollowerSession @($summary) -ExtendedWalking} 'Native write budget ignored'
$summary.writes=1;$summary.hard_deadline_ms=18001
Reject {Assert-HudWalkingFollowerSession @($summary) -ExtendedWalking} 'Native hard deadline extended by receipt'
$summary.hard_deadline_ms=18000
Reject {Assert-HudWalkingFollowerSession (@($summary)*257) -ExtendedWalking} 'Native receipt history unbounded'
foreach($duration in @(5999,14999,16001,15000.5,'15000',$null)){
    Reject {Assert-HudWalkingDuration ([pscustomobject]@{duration_ms=$duration}) -ExtendedWalking} 'Extended label substituted for actual bounded duration'
}
Assert-HudWalkingDuration ([pscustomobject]@{duration_ms=15000}) -ExtendedWalking
Assert-HudWalkingDuration ([pscustomobject]@{duration_ms=16000}) -ExtendedWalking

Write-Output "HUD_BUFFERED_MOVEMENT_TESTS_PASS checks=$checks game_calls=false"
