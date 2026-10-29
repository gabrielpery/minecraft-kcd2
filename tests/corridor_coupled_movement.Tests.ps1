#requires -Version 7.3
# Synthetic receiver/readback contract only. No game, process or renderer calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
. (Join-Path $root 'scripts/CoupledMovementProof.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20}
$run='a'*32;$hudRun='b'*32;$world='12345678-1234-1234-1234-123456789abc';$save='MineCome-HudStream-'+$world
$utc=1700000000000L;$start='134363864241979118'
$dir=Join-Path $root ('runtime/evidence/corridor-coupled-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$path=Join-Path $dir 'corridor.json';$trace=Join-Path $dir 'movement.ndjson'
$manifest=New-HudGroundCorridorFixture $run
# This fixture deliberately carries live labels solely to exercise the pure
# receiver. Real capture/process authentication remains the controller's job.
for($i=0;$i -lt 2;$i++){
    $tile=$manifest.tiles[$i].json | ConvertFrom-Json
    $tile.provenance.kind='live_kcd_ground_patch'
    $tile | Add-Member approximate_heightfield $true
    $tile | Add-Member full_collision_export_verified $false
    $manifest.tiles[$i].json=$tile | ConvertTo-Json -Depth 12 -Compress
    $manifest.tiles[$i].sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($manifest.tiles[$i].json))
}
function Save-Corridor($InputManifest){
    [IO.File]::WriteAllText($path,($InputManifest | ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
    $first=$InputManifest.tiles[0].json | ConvertFrom-Json
    return [pscustomobject]@{Path=$path;Hash=(Get-FileHash $path).Hash.ToLowerInvariant();Run=$InputManifest.run;
        Anchor=$first.center;TileHashes=@($InputManifest.tiles.sha256);Captured=$true}
}
function Receiver($InputCorridor,[switch]$WalkOnly){New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -CorridorWalking -Corridor $InputCorridor -CorridorWalkOnly:$WalkOnly}
function Trace-Record($State,[string]$Kind,[int]$Seq,[string]$Phase='WALKING',[double]$X=.5){
    $r=[ordered]@{schema=1;kind=$Kind;run=$State.ExpectedRun;patch_sha256=$State.PatchHash;source_kind=$(if($State.CorridorWalkOnly){'hud_corridor_walk_coupled'}else{'hud_corridor_coupled'});walking_area='corridor';save=$save;world=$world;seq=$Seq;utc_ms=$utc;phase=$Phase}
    if($Kind -ceq 'begin'){
        $r.phase='SETTLING';$r.started_monotonic_ns=100L;$r.center=$State.Center;$r.anchor_mc=@{x=0;y=64;z=0}
        $r.approximate_heightfield=$true;$r.full_collision_export_verified=$false
    }elseif($Kind -ceq 'end'){$r.result='passed';$r.reason='';$r.last_server_seq=$Seq-2}
    else{
        $r.monotonic_ns=100L+($Seq-1)*90000000L;$r.server_seq=$Seq-1;$r.server_age_ns=0L
        foreach($side in @('client','server')){$r[$side]=@{x=$X;y=64;z=.5;vx=0;vy=0;vz=0;on_ground=$true;proxy_support=$true}}
    }
    return $r
}
function Receive($State,$Record,[long]$Now=$utc){Receive-MineComeMovementTrace $State ($Record | ConvertTo-Json -Depth 8 -Compress) $Now}
function Reject-Record($State,$Record,[string]$Message){
    $before=$State | ConvertTo-Json -Depth 12 -Compress
    Reject {Receive $State $Record} $Message
    Check (($State | ConvertTo-Json -Depth 12 -Compress) -ceq $before) 'Rejected corridor record mutated receiver state'
}
function Begin($State){$null=Receive $State (Trace-Record $State begin 1)}
function Rehash-Tile($InputManifest,[int]$Index,$Tile){
    $InputManifest.tiles[$Index].json=$Tile | ConvertTo-Json -Depth 12 -Compress
    $InputManifest.tiles[$Index].sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($InputManifest.tiles[$Index].json))
}
try{
    $corridor=Save-Corridor $manifest
    $state=Receiver $corridor
    Check ($state.Corridor -eq $corridor -and $state.Center.x -eq 120 -and -not $state.WideWalking) 'One fixed authenticated corridor origin'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -WideWalking -CorridorWalking -Corridor $corridor} 'Wide and corridor combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -CorridorWalking -Corridor $corridor} 'Physical and corridor combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -ScriptedHudCoupled -CorridorWalking -Corridor $corridor} 'Legacy and corridor combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -Corridor $corridor} 'Corridor implicitly selected'
    foreach($field in @('Hash','Run','Path')){$bad=Clone $corridor;$bad.$field='different';Reject {Receiver $bad} "Unbound capture $field accepted"}
    $bad=Clone $corridor;$bad.Captured=$false;Reject {Receiver $bad} 'Fixture admitted as captured corridor'
    $bad=Clone $corridor;$bad.Anchor.x+=4;Reject {Receiver $bad} 'Rebased authenticated origin accepted'
    foreach($mutation in @(
        {param($m)$m.tiles[1].sha256='0'*64},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.center.x+=1;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.points[0].z+=.01;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.points[80].x+=1;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.provenance.kind='standalone_fixture';Rehash-Tile $m 1 $p},
        {param($m)$m | Add-Member unexpected $true}
    )){$bad=Clone $manifest;& $mutation $bad;$identity=Save-Corridor $bad;Reject {Receiver $identity} 'Invalid corridor geometry/provenance admitted'}
    $corridor=Save-Corridor $manifest;$state=Receiver $corridor
    $record=Trace-Record $state begin 1;$record.anchor_mc.x=.5;Reject-Record $state $record 'Spawn silently became coordinate anchor'
    Begin $state
    foreach($axis in @('x','z','y')){
        $bad=Trace-Record $state sample 2
        $bad.server[$axis]=@{x=7.5001;z=3.5001;y=67.5001}[$axis]
        Reject-Record $state $bad "Corridor upper $axis bound admitted"
        $bad.server[$axis]=@{x=-3.5001;z=-3.5001;y=57.8999}[$axis]
        Reject-Record $state $bad "Corridor lower $axis bound admitted"
    }
    $bad=Trace-Record $state sample 2;$bad.monotonic_ns=20000000101L;Reject-Record $state $bad 'Source beyond20s accepted'
    $bad=Trace-Record $state sample 2;$bad.monotonic_ns=99;Reject-Record $state $bad 'Sample before source start accepted'
    $bad=Trace-Record $state sample 2;$bad.source_kind='live_kcd_ground_patch';Reject-Record $state $bad 'Legacy source admitted'
    $bad=Trace-Record $state sample 2;$bad.walking_area='wide';Reject-Record $state $bad 'Legacy area admitted'
    $bad=Trace-Record $state sample 2;$bad.server_age_ns=250000001;Reject-Record $state $bad 'Stale real-server guard widened'
    $accepted=Receive $state (Trace-Record $state sample 2 WALKING 5.75)
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 125.75 -and $accepted.Target.y -eq 2039.5) 'Crossing maps through original C, not tile1 center'
    $stale=Receive $state (Trace-Record $state sample 3 RETURNING 3.5) ($utc+301)
    Check ($stale.Kind -ceq 'stale' -and -not $stale.PSObject.Properties['Target']) 'Late return never forwarded'
    $accepted=Receive $state (Trace-Record $state sample 4 RETURNING 3.0)
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 123) 'Fresh grounded return crosses seam'
    $accepted=Receive $state (Trace-Record $state sample 5 RETURN_REST .6)
    Check ($accepted.Kind -ceq 'sample') 'Return-rest remains visible to follower'
    $bad=Trace-Record $state sample 6;$bad.server_seq=4;Reject-Record $state $bad 'Repeated real-server sequence accepted'
    $null=Receive $state (Trace-Record $state sample 6 PASSED .6)
    $null=Receive $state (Trace-Record $state end 7 PASSED)
    Check $state.Ended 'Fresh terminal source succeeds'
    # Additional records/bytes are exclusive to this profile;200 was too small
    # to reserve an end record for the20-second source deadline.
    $longState=Receiver $corridor;Begin $longState
    for($seq=2;$seq -le 201;$seq++){$null=Receive $longState (Trace-Record $longState sample $seq)}
    Check ($longState.Records -eq 201 -and $longState.Bytes -gt 65536) 'Corridor uses bounded larger stream'
    $null=Receive $longState (Trace-Record $longState sample 202 PASSED)
    $null=Receive $longState (Trace-Record $longState end 203 PASSED)
    $reader=[pscustomobject]@{Path=$trace;Stream=$null;Bytes=[byte[]]::new(0)}
    [IO.File]::WriteAllText($trace,('x'*70000)+"`n")
    try{
        Reject {Read-CoupledTraceLines $reader} 'Legacy reader silently enlarged'
        Check (@(Read-CoupledTraceLines $reader -CorridorWalking).Count -eq 1) 'Corridor bounded append reader accepts larger stream'
        [IO.File]::WriteAllText($trace,('y'*70000)+"`n")
        Reject {Read-CoupledTraceLines $reader -CorridorWalking} 'Corridor reader accepted rewritten bytes'
    }finally{if($reader.Stream){$reader.Stream.Dispose()}}

    $ready=[pscustomobject]@{schema=1;run=$hudRun;source_kind='minecraft_vanilla_ui_stream_v1';mapping_bytes=8294656
        mapping_name='Local\MineComeHud_'+$hudRun;mutex_name='Local\MineComeHudLock_'+$hudRun;target_pid=321;target_start_filetime=$start
        producer_pid=123;producer_start_filetime=$start;save=$save;expires_utc_ms=$utc+180000;standalone=$true;ui_ground_corridor_coupled=$true;walking_area='corridor'}
    Assert-CoupledHudReady $ready 321 $start $utc -CorridorWalking
    Check $true 'Explicit corridor readiness accepted'
    Reject {Assert-CoupledHudReady $ready 321 $start $utc} 'Corridor readiness passed legacy route'
    Reject {Assert-CoupledHudReady $ready 321 $start $utc -CorridorWalking -WideWalking} 'Corridor readiness also wide'
    $bad=Clone $ready;$bad | Add-Member ui_ground_movement_coupled $true
    Reject {Assert-CoupledHudReady $bad 321 $start $utc -CorridorWalking} 'Legacy marker authorized corridor'
    $proof=[ordered]@{schema=1;kind='minecome_hud_ground_corridor_coupled_v1';save=$save;patch_run=$run;patch_sha256=$corridor.Hash;
        ground_source_kind='live_kcd_ground_corridor';phase='PASSED';client_walk=5.2;server_walk=5.2;client_proxy_queries=100;server_proxy_queries=100;
        post_settle_corrections=0;frame_captures=@{WALKING=4;JUMPING=1;LANDING=4};trace_file=$trace;trace_records=203;trace_closed=$true;trace_result='passed';hud_run=$hudRun}
    foreach($field in @('synthetic_input','client_air','server_air','client_land','server_land','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){$proof[$field]=$true}
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')){$proof[$field]=$false}
    $proof.corridor=@{anchor=$corridor.Anchor;tile_sha256=$corridor.TileHashes;bounds=@{min_x=-4;max_x=8;min_z=-4;max_z=4};
        original_edge_x=4;crossing_target_x=5.5;client_max_x=5.7;server_max_x=5.7;client_return_distance=.1;server_return_distance=.1;
        max_client_server_distance=.1;crossing_hud_frames=2;return_hud_frames=3;crossed_original_edge=$true;returned_to_start=$true;
        client_vanilla_cells_air=$true;server_vanilla_cells_air=$true;slab_count=96;collision_cell_count=120}
    $guest=Clone ([ordered]@{run=$hudRun;result='passed';save=$save;source_kind='minecraft_vanilla_ui_stream_v1';standalone=$true;
        ui_ground_corridor_coupled=$true;walking_area='corridor';lab_evidence=@{ground_movement=$proof}})
    $verification=Clone ([ordered]@{schema=1;kind='minecome_hud_stream_controller_v1';result='passed';failure=$null;run=$hudRun;
        target_kind='standalone_controller';target_pid=321;target_start_filetime=$start;target_sha256=('c'*64);ground_patch_run=$run;
        ground_patch_sha256=$corridor.Hash;movement_trace_file=$trace;walking_area='corridor';ground_movement_fixture=$false;
        compositor_armed=$false;composite_requested=$false;kcd_compositing_verified=$false;kcd_launched=$false;kcd_stopped=$false;
        ground_movement_coupled=$false;ground_corridor_coupled=$true;ground_movement=$proof})
    $null=Assert-CoupledHudCompletion $verification $ready $guest $longState $trace 321 $start ('c'*64) -CorridorWalking
    Check $true 'Corridor completion binds exact helper, captured tiles, closed203-record trace and HUD crossing/return'
    foreach($mutation in @(
        {param($v,$g)$v.ground_movement_coupled=$true},
        {param($v,$g)$v.ground_corridor_coupled=$false},
        {param($v,$g)$g.lab_evidence.ground_movement.trace_records=202},
        {param($v,$g)$g.lab_evidence.ground_movement.trace_closed=$false},
        {param($v,$g)$g.lab_evidence.ground_movement.corridor.anchor.x+=4},
        {param($v,$g)$g.lab_evidence.ground_movement.corridor.return_hud_frames=0},
        {param($v,$g)$g.lab_evidence.ground_movement.hud_run=$run}
    )){$v=Clone $verification;$g=Clone $guest;& $mutation $v $g;Reject {Assert-CoupledHudCompletion $v $ready $g $longState $trace 321 $start ('c'*64) -CorridorWalking} 'Unbound corridor completion accepted'}
    $center=$corridor.Anchor
    $frames=@(
        [pscustomobject]@{TraceSeq=2;Phase='WALKING';Target=[pscustomobject]@{x=120.5;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=3;Phase='WALKING';Target=[pscustomobject]@{x=125.8;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=4;Phase='JUMPING';Target=[pscustomobject]@{x=125.8;y=2039.5;z=56.8}}
        [pscustomobject]@{TraceSeq=5;Phase='RETURNING';Target=[pscustomobject]@{x=123.8;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=6;Phase='RETURN_REST';Target=[pscustomobject]@{x=120.8;y=2039.5;z=56.0}}
    )
    $receipts=@([pscustomobject]@{schema=1;run=$run;event='begin';result='awaiting_first_pose';terminal=$false;player=$center;walking_area='corridor'})
    foreach($frame in $frames){
        $target=[pscustomobject]@{x=[double][single]$frame.Target.x;y=[double][single]$frame.Target.y;z=[double][single]$frame.Target.z}
        $receipts+=[pscustomobject]@{schema=1;run=$run;event='applied';result='applied_readback';terminal=$false;seq=$frame.TraceSeq;target=$target;player=(Clone $target);readback=$true;follow_error=.01;walking_area='corridor'}
    }
    $receipts+=[pscustomobject]@{schema=1;run=$run;event='restoring';result='restored_position_pending_camera';terminal=$false;readback=$true;end_result='explicit_end';target=$center;player=$center;walking_area='corridor'}
    $receipts+=[pscustomobject]@{schema=1;run=$run;event='restored';result='restored';terminal=$true;readback=$true;timers_cancelled=$true;end_result='explicit_end';follow_error=.01;target=$center;player=$center;walking_area='corridor'}
    Check (@(Assert-CoupledFollowerProof $receipts $frames $run $center -CorridorWalking).Count -eq 5) 'KCD crossing, return and exact saved-origin restoration accepted'
    foreach($mutation in @(
        {param($r,$f)$f[1].Phase='RETURNING';$f[2].Phase='RETURNING'},
        {param($r,$f)$f[3].Phase='WALKING'},
        {param($r,$f)$f[4].Phase='RETURNING'},
        {param($r,$f)$r[-1].target.x+=.0001},
        {param($r,$f)$r[-2].target.x+=.0001},
        {param($r,$f)$r[-1].player.x+=.051},
        {param($r,$f)$r[-2].player.x+=.051},
        {param($r,$f)$r[2].target.x+=.01},
        {param($r,$f)$r[2].player.x+=.051},
        {param($r,$f)$r[2].player.x=[double]::NaN},
        {param($r,$f)$r[2].walking_area='wide'},
        {param($r,$f)$r[-1].end_result='input_expired'}
    )){$badReceipts=Clone $receipts;$badFrames=Clone $frames;& $mutation $badReceipts $badFrames;Reject {Assert-CoupledFollowerProof $badReceipts $badFrames $run $center -CorridorWalking} 'Incomplete/unbound corridor readback accepted'}
    # A separate milestone selects walking without claiming the unresolved
    # camera response during jumping. No actor/camera/restore bound is relaxed.
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -CorridorWalkOnly} 'Walk-only implied corridor authority'
    $walkState=Receiver $corridor -WalkOnly;Begin $walkState
    foreach($phase in @('JUMPING','LANDING')){Reject-Record $walkState (Trace-Record $walkState sample 2 $phase) 'Walk-only accepted jump/landing phase'}
    $bad=Trace-Record $walkState sample 2;$bad.source_kind='hud_corridor_coupled'
    Reject-Record $walkState $bad 'Walk-only accepted full-jump source'
    $fullState=Receiver $corridor;Begin $fullState
    $bad=Trace-Record $fullState sample 2;$bad.source_kind='hud_corridor_walk_coupled'
    Reject-Record $fullState $bad 'Full-jump accepted walk-only source'
    $null=Receive $walkState (Trace-Record $walkState sample 2 WALKING 5.8)
    $null=Receive $walkState (Trace-Record $walkState sample 3 RETURNING 3)
    $null=Receive $walkState (Trace-Record $walkState sample 4 RETURN_REST .6)
    $null=Receive $walkState (Trace-Record $walkState sample 5 PASSED .6)
    $null=Receive $walkState (Trace-Record $walkState end 6 PASSED)
    Check ($walkState.Ended -and $walkState.Records -eq 6) 'Walk-only trace crosses and returns with its exact separate source identity'
    $walkReady=Clone $ready;$walkReady | Add-Member corridor_walk_only $true
    Assert-CoupledHudReady $walkReady 321 $start $utc -CorridorWalking -CorridorWalkOnly
    Check $true 'Explicit walk-only readiness accepted'
    Reject {Assert-CoupledHudReady $walkReady 321 $start $utc -CorridorWalkOnly} 'Walk-only readiness implied corridor'
    Reject {Assert-CoupledHudReady $walkReady 321 $start $utc -CorridorWalking} 'Full-jump accepted walk-only readiness'
    Reject {Assert-CoupledHudReady $ready 321 $start $utc -CorridorWalking -CorridorWalkOnly} 'Walk-only accepted absent marker'
    $bad=Clone $walkReady;$bad.corridor_walk_only='true'
    Reject {Assert-CoupledHudReady $bad 321 $start $utc -CorridorWalking -CorridorWalkOnly} 'Walk-only marker coerced from string'
    $walkGuest=Clone $guest;$walkGuest | Add-Member corridor_walk_only $true
    $walkProof=$walkGuest.lab_evidence.ground_movement;$walkProof.kind='minecome_hud_ground_corridor_walk_coupled_v1'
    foreach($field in @('client_air','server_air','client_land','server_land')){$walkProof.$field=$false}
    $walkProof.frame_captures.JUMPING=0;$walkProof.frame_captures.LANDING=0;$walkProof.trace_records=6
    $walkVerification=Clone $verification;$walkVerification | Add-Member corridor_walk_only $true
    $walkVerification.ground_movement=$walkProof
    $null=Assert-CoupledHudCompletion $walkVerification $walkReady $walkGuest $walkState $trace 321 $start ('c'*64) -CorridorWalking -CorridorWalkOnly
    Check $true 'Distinct walk-only completion proves crossing/return/HUD without airborne claims'
    foreach($mutation in @(
        {param($g)$g.lab_evidence.ground_movement.kind='minecome_hud_ground_corridor_coupled_v1'},
        {param($g)$g.lab_evidence.ground_movement.client_air=$true},
        {param($g)$g.lab_evidence.ground_movement.server_land=$true},
        {param($g)$g.lab_evidence.ground_movement.frame_captures.JUMPING=1},
        {param($g)$g.corridor_walk_only=$false}
    )){$bad=Clone $walkGuest;& $mutation $bad;Reject {Assert-CoupledHudCompletion $walkVerification $walkReady $bad $walkState $trace 321 $start ('c'*64) -CorridorWalking -CorridorWalkOnly} 'Walk-only completion admitted incompatible jump proof'}
    $walkFrames=Clone $frames;$walkReceipts=Clone $receipts
    $walkFrames[2].Phase='RESTING';$walkFrames[2].Target.z=56
    $walkReceipts[3].target.z=56;$walkReceipts[3].player.z=56
    Check (@(Assert-CoupledFollowerProof $walkReceipts $walkFrames $run $center -CorridorWalking -CorridorWalkOnly).Count -eq 5) 'Walk-only native proof needs crossing, return and restore without artificial vertical displacement'
    Reject {Assert-CoupledFollowerProof $walkReceipts $walkFrames $run $center -CorridorWalking} 'Full-jump proof weakened to accept walk-only sequence'
    Reject {Assert-CoupledFollowerProof $receipts $frames $run $center -CorridorWalking -CorridorWalkOnly} 'Walk-only proof accepted forwarded airborne sequence'
    $bad=Clone $walkReceipts;$bad[2].follow_error=.151
    Reject {Assert-CoupledFollowerProof $bad $walkFrames $run $center -CorridorWalking -CorridorWalkOnly} 'Walk-only camera error bound relaxed'
    $bad=Clone $walkReceipts;$bad[2].player.x+=.051
    Reject {Assert-CoupledFollowerProof $bad $walkFrames $run $center -CorridorWalking -CorridorWalkOnly} 'Walk-only actor readback bound relaxed'
    $bad=Clone $walkReceipts;$bad[-1].target.x+=.001
    Reject {Assert-CoupledFollowerProof $bad $walkFrames $run $center -CorridorWalking -CorridorWalkOnly} 'Walk-only restoration origin relaxed'
    Write-Output "CORRIDOR_COUPLED_MOVEMENT_TESTS_PASS checks=$script:checks no_game_started=true"
}finally{
    foreach($file in @($path,$trace)){if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
    [IO.Directory]::Delete($dir,$false)
}
