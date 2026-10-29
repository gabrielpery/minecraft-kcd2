#Requires -Version 7.3
# Combined-mode admission/proof only. Dot sourcing does not start either game.
. (Join-Path $PSScriptRoot 'HudBufferedMovement.ps1')
. (Join-Path $PSScriptRoot 'AimedWorldClicks.ps1')
. (Join-Path $PSScriptRoot 'HudWorldClicks.ps1')

# Exercise first-use parsing/binding before Minecraft starts. This disposable
# state is never joined to a live controller, permit ledger, or input channel.
function Initialize-HudWalkingAimedAdmissionWarmup([string]$Directory,[string]$ProjectRoot,$Context){
    Initialize-MineComeHudWorldNative
    $path=Resolve-HudMovementEvidencePath (Join-Path $Directory 'diagnostic-aim-view.json') $ProjectRoot
    $run='a'*32;$probe='b'*32;$patch='c'*32;$hash='d'*64
    $view=[pscustomobject]@{schema=1;source_kind='live_kcd_hud_view_v1';run=$run;patch_run=$patch;patch_sha256=$hash;
        target_pid=1;target_start_filetime='1';seq=4;utc_ms=1420;forward=[pscustomobject]@{x=1.;y=0.;z=0.};up=[pscustomobject]@{x=0.;y=0.;z=1.}}
    $native=[pscustomobject]@{schema=1;run=$probe;seq=4;result='sampled';physical_movement=$true;camera_basis_valid=$true;
        player=[pscustomobject]@{x=100.2;y=200.;z=50.};camera=[pscustomobject]@{position=[pscustomobject]@{x=100.2;y=200.;z=51.7};forward=$view.forward;up=$view.up;fov=1.2}}
    $pose=[pscustomobject]@{x=.2;y=64.;z=0.}
    $first=[pscustomobject]@{SourceMs=500.;Record=[pscustomobject]@{utc_ms=1200L}}
    $latest=[pscustomobject]@{SourceMs=700.;Target=$native.player;Record=[pscustomobject]@{utc_ms=1400L;server_age_ns=1000000L;client=$pose;server=$pose}}
    $state=[pscustomobject]@{LastClock=0L;Stopping=$false;Closed=$null;Run=$run;ProbeRun=$probe;PatchRun=$patch;PatchHash=$hash;TargetPid=1;TargetStart='1';LastViewSeq=0L;
        LastSample=$latest;Stationary=@($first,$first,$latest);Ready=[pscustomobject]@{initial_guest_feet=[pscustomobject]@{x=0.;y=64.;z=0.};host_anchor=[pscustomobject]@{x=100.;y=200.;z=51.7}}}
    $snapshot=[ordered]@{schema=1;kind='minecome_hud_diagnostic_aim_view_v1';diagnostic_only=$true;synthetic_view=$view}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($snapshot|ConvertTo-Json -Depth 8 -Compress))
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
    $measurements=[Collections.Generic.List[object]]::new();$total=[Diagnostics.Stopwatch]::StartNew()
    foreach($iteration in 1..2){
        $watch=[Diagnostics.Stopwatch]::StartNew();$discard=Read-HudCameraSnapshot $path $ProjectRoot;$snapshotMs=$watch.Elapsed.TotalMilliseconds
        if($null -eq $discard -or -not $discard.diagnostic_only){throw 'Diagnostic camera warmup did not read its own snapshot.'}
        $watch.Restart();$null=Test-MineComeHudWorldForeground $Context;$foregroundMs=$watch.Elapsed.TotalMilliseconds
        $watch.Restart();$reason=Get-HudWalkingAimedDecline $state $view $native 1450;$policyMs=$watch.Elapsed.TotalMilliseconds
        if($reason){throw "Disposable settled-admission warmup failed: $reason"}
        $measurements.Add([pscustomobject]@{iteration=$iteration;snapshot_ms=$snapshotMs;foreground_ms=$foregroundMs;settled_policy_ms=$policyMs})
    }
    [pscustomobject]@{schema=1;kind='minecome_hud_aim_admission_warmup_v1';diagnostic_only=$true;synthetic_policy_state=$true;
        discarded_foreground_results=$true;live_authority_granted=$false;input_generated=$false;permits_issued=0;http_requests=0;
        diagnostic_snapshot=$path;elapsed_ms=$total.Elapsed.TotalMilliseconds;measurements=$measurements.ToArray();game_input_latency_measured=$false}
}

# Post-run evidence only. This helper also accepts the same collector receipt
# from a standalone fixture, without turning that fixture into live host proof.
function Assert-HudWalkingInventoryEvidence($Evidence) {
    if($null -eq $Evidence -or (Get-HudBufferedField $Evidence 'kind') -cne 'minecome_hud_movement_inventory_v1') {
        throw 'unsupported_evidence: bounded movement inventory windows are required.'
    }
    function Int($O,[string]$K,[long]$Min,[long]$Max){Get-HudBufferedInteger (Get-HudBufferedField $O $K) $K $Min $Max}
    function Num($O,[string]$K,[double]$Min,[double]$Max){Get-HudBufferedNumber (Get-HudBufferedField $O $K) $K $Min $Max}
    function Flag($O,[string]$K,[bool]$V){Assert-HudBufferedFlag (Get-HudBufferedField $O $K) $K $V}
    [void](Int $Evidence schema 1 1);[void](Int $Evidence max_windows 4 4);[void](Int $Evidence max_events 32 32)
    Flag $Evidence truncated $false;Flag $Evidence capture_finished $true;Flag $Evidence capture_complete $true
    $windows=Get-HudBufferedField $Evidence 'windows';$windows=@($windows)
    $events=Get-HudBufferedField $Evidence 'events';$events=@($events)
    if($windows.Count -lt 1 -or $windows.Count -gt 4 -or $events.Count -gt 32){throw 'Inventory evidence window/event bounds exceeded or absent.'}
    [void](Int $Evidence window_count $windows.Count $windows.Count);[void](Int $Evidence event_count $events.Count $events.Count)
    if($null -ne (Get-HudBufferedField $Evidence 'failure')){throw 'Inventory capture reported a failure.'}
    $verified=[Collections.Generic.List[object]]::new();$refused=[Collections.Generic.List[object]]::new();$previousClose=$null
    foreach($window in $windows) {
        $id=Int $window id 1 4
        if($id -ne $verified.Count+$refused.Count+1){throw 'Inventory window IDs are not consecutive.'}
        $open=Int $window opened_monotonic_ns ([long]::MinValue) ([long]::MaxValue)
        $close=Int $window closed_monotonic_ns ([long]::MinValue) ([long]::MaxValue)
        $duration=[decimal]$close-[decimal]$open
        if($duration -lt 0 -or $duration -gt 30000000000 -or ($null -ne $previousClose -and $open -lt $previousClose)){throw 'Inventory window times overlap or regress.'}
        $previousClose=$close
        [void](Int $window opened_utc_ms 1 ([long]::MaxValue));[void](Int $window closed_utc_ms 1 ([long]::MaxValue))
        Flag $window complete $true
        try {
            if($duration -lt 250000000){throw 'Inventory window was shorter than 250ms.'}
            [void](Int $window samples 3 2000);[void](Int $window stale_samples 0 0)
            [void](Int $window server_sequence_advances 2 2000)
            [void](Int $window max_sample_gap_ns 0 250000000);[void](Int $window max_server_age_ns 0 250000000)
            [void](Num $window max_client_displacement 0 .01);[void](Num $window max_server_displacement 0 .01)
            [void](Num $window client_server_max_error 0 .01)
            Flag $window all_grounded $true;Flag $window immobility_verified $true
            [void](Int $window nonzero_binding_samples 0 0);[void](Int $window bindings_or 0 0)
            $resume=Get-HudBufferedField $window 'resumed_movement'
            $sequence=Int $resume input_sequence 1 ([long]::MaxValue)
            $key=Int $resume key 0 255
            if($key -notin @(87,83,65,68)){throw 'Resumption requires a walking key.'}
            $resumeNs=Int $resume received_monotonic_ns ([long]::MinValue) ([long]::MaxValue)
            if($resumeNs -le $close){throw 'Movement resumption predates inventory close.'}
            [void](Int $resume captured_utc_ms $window.closed_utc_ms ([long]::MaxValue));[void](Int $resume received_utc_ms 1 ([long]::MaxValue))
            Flag $resume binding_observed $true;Flag $resume verified $true
            [void](Int $resume stale_samples 0 0)
            [void](Num $resume client_displacement .05 4);[void](Num $resume server_displacement .05 4)
            [void](Num $resume client_displacement_from_close .05 4);[void](Num $resume server_displacement_from_close .05 4)
            $matching=@($events | Where-Object {$_.input_sequence -eq $sequence})
            if($matching.Count -ne 1){throw 'Resumed movement has no unique delivered movement event.'}
            $edge=$matching[0]
            [void](Int $edge kind 1 1);[void](Int $edge key $key $key)
            [void](Int $edge received_monotonic_ns $resumeNs $resumeNs)
            foreach($clock in @('captured_utc_ms','received_utc_ms')){[void](Int $edge $clock $resume.$clock $resume.$clock)}
            Flag $edge accepted_down $true;Flag $edge inventory_open $false
            Flag $edge context_observed $true;[void](Int $edge window_id 0 0)
            $verified.Add([pscustomobject]@{id=$id;duration_ms=[double]($duration/1000000);samples=$window.samples;
                max_client_displacement=$window.max_client_displacement;max_server_displacement=$window.max_server_displacement;
                resumed_movement=$resume})
        }catch{$refused.Add([pscustomobject]@{id=$id;reason=$_.Exception.Message})}
    }
    if($verified.Count -eq 0){throw ('insufficient_evidence: no stationary inventory window followed by actual resumed walking. '+(($refused | ForEach-Object {$_.reason}) -join ' '))}
    [pscustomobject]@{schema=1;kind='minecome_hud_walking_inventory_proof_v1';verified_windows=$verified.ToArray();refused_windows=$refused.ToArray();
        physical_w_attempt_verified=$false;physical_w_denial_verified=$false;host_rendering_verified=$false}
}

# Additional scenario requirements. The caller must first validate the complete
# guest/native bridge, movement trace, delayed host readbacks and cleanup receipts.
# The default deliberately adds no requirement to the established WalkingBreak.
function Assert-HudWalkingAimedScenario {
    param($Guest,[ValidateSet('WalkingBreak','TopFaceInventory','SideFaceInventory')][string]$Scenario='WalkingBreak')
    $proof=[ordered]@{schema=1;kind='minecome_hud_walking_aimed_scenario_v1';scenario=$Scenario;result='passed';
        requested_face=$null;confirmed_network_actions=$null;inventory=$null;visual_verified=$false;physical_w_attempt_verified=$false;physical_w_denial_verified=$false}
    if($Scenario -eq 'WalkingBreak'){return [pscustomobject]$proof}
    function Int($O,[string]$K,[long]$Min,[long]$Max){Get-HudBufferedInteger (Get-HudBufferedField $O $K) $K $Min $Max}
    function Flag($O,[string]$K,[bool]$V){Assert-HudBufferedFlag (Get-HudBufferedField $O $K) $K $V}
    function Cell($Value){foreach($axis in @('x','y','z')){[void](Int $Value $axis -10000000 10000000)};return "$($Value.x),$($Value.y),$($Value.z)"}
    function Same($A,$B){if((Cell $A) -cne (Cell $B)){throw 'Scenario target/hit cell differs from requested face.'}}
    $lab=Get-HudBufferedField $Guest 'lab_evidence';$stone=Get-HudBufferedField $lab 'stone_bridge';$arena=$stone.arena
    $seed=$stone.arena_offer.seed;$null=Cell $seed
    # The bootstrap can lie on any captured perimeter. Select the vertical
    # face toward the immutable Minecraft origin, with X winning exact ties.
    $face=if($Scenario -eq 'TopFaceInventory'){'UP'}
        elseif([Math]::Abs($seed.x+.5) -ge [Math]::Abs($seed.z+.5)){if($seed.x+.5 -gt 0){'WEST'}else{'EAST'}}
        else{if($seed.z+.5 -gt 0){'NORTH'}else{'SOUTH'}}
    $added=[pscustomobject]@{x=$seed.x;y=$seed.y;z=$seed.z}
    switch -CaseSensitive ($face){UP{$added.y++}WEST{$added.x--}EAST{$added.x++}NORTH{$added.z--}SOUTH{$added.z++}}
    $support=[pscustomobject]@{x=$seed.x;y=$seed.y-1;z=$seed.z}
    $confirmations=@($stone.confirmations);$components=@($arena.confirmations);$requests=@($stone.requests)
    if($confirmations.Count -ne 4 -or $components.Count -ne 4 -or $requests.Count -lt 3 -or $requests.Count -gt 16){throw 'Scenario requires bootstrap, face placement, added-block break and seed break.'}
    [void](Int $stone confirmed_network_actions 3 3);[void](Int $stone owned_count 0 0);[void](Int $arena owned_count 0 0)
    Flag $stone guest_world_cleanup_complete $true;Flag $stone logical_closed_before_restore $true;Flag $stone.build_support cleanup_complete $true
    Flag $stone pending $false;Flag $arena pending $false
    [void](Int $arena omitted_receipts 0 0)
    foreach($field in @('block_writes','inventory_writes','camera_writes')){[void](Int $arena $field 0 0)}
    if(@($arena.owned_cells).Count -ne 0){throw 'Scenario left owned guest blocks behind.'}
    $targets=@($seed,$added,$added,$seed);$hits=@($support,$seed,$added,$seed);$actions=@(1,1,2,2)
    $lastComponent=0L;$lastWire=0L
    for($i=0;$i -lt 4;$i++) {
        $row=$confirmations[$i];$component=$components[$i]
        $id=Int $row component_request_id ($lastComponent+1) ([long]::MaxValue);$lastComponent=$id
        [void](Int $component id $id $id)
        foreach($actual in @($row,$component)) {
            [void](Int $actual action $actions[$i] $actions[$i]);Flag $actual bootstrap ($i -eq 0);Flag $actual client_and_server $true
            Same $actual.target $targets[$i];Same $actual.hit_block $hits[$i]
            if($actual.face -cnotin @('UP','DOWN','NORTH','SOUTH','EAST','WEST') -or ($i -eq 0 -and $actual.face -cne 'UP') -or ($i -eq 1 -and $actual.face -cne $face)){throw 'Scenario vanilla hit face differs from requested face.'}
        }
        if($component.status -cne 'confirmed' -or $row.face -cne $component.face){throw 'Scenario component confirmation differs from bridge.'}
        Flag $row block_event_queued $true
        if($i -eq 0){[void](Int $row wire_request_id 0 0)}
        else {
            $wire=Int $row wire_request_id ($lastWire+1) ([long]::MaxValue);$lastWire=$wire
            $matching=@($requests | Where-Object {$_.wire.requestId -eq $wire})
            if($matching.Count -ne 1){throw 'Scenario action lacks a unique vanilla network request.'}
            $request=$matching[0]
            [void](Int $request component_request_id $id $id);[void](Int $request result 1 1);[void](Int $request.wire action $actions[$i] $actions[$i])
            foreach($flag in @('actions_enabled','vanilla_queued','client_and_server','result_queued')){Flag $request $flag $true}
        }
    }
    Flag $lab inventory_opened $true;Flag $lab inventory_closed $true
    $movement=Get-HudBufferedField $lab 'physical_movement'
    if($null -eq $movement.PSObject.Properties['inventory_evidence']){throw 'unsupported_evidence: this guest predates bounded movement inventory windows.'}
    $inventory=Assert-HudWalkingInventoryEvidence $movement.inventory_evidence
    $timing=Get-HudBufferedField $movement 'input_timing';Flag $timing truncated $false
    $events=@($timing.events);$bindings=@($timing.binding_states)
    if($events.Count -gt 32 -or $bindings.Count -gt 32){throw 'Scenario movement timing exceeded bounded evidence.'}
    foreach($window in $inventory.verified_windows) {
        $resume=$window.resumed_movement;$matching=@($events | Where-Object {$_.input_sequence -eq $resume.input_sequence})
        if($matching.Count -ne 1){throw 'Scenario resumed edge missing from movement timing.'}
        $edge=$matching[0]
        [void](Int $edge kind 1 1);[void](Int $edge key $resume.key $resume.key);Flag $edge accepted_down $true
        foreach($clock in @('captured_utc_ms','received_utc_ms','received_monotonic_ns')){[void](Int $edge $clock $resume.$clock $resume.$clock)}
        $bit=@{87=1;83=2;65=4;68=8}[[int]$resume.key]
        $applied=@($bindings | Where-Object {$_.after_input_sequence -eq $resume.input_sequence -and $_.stage -ceq 'before_vanilla_poll' -and $_.monotonic_ns -ge $resume.received_monotonic_ns -and ($_.mask -band $bit) -ne 0})
        if($applied.Count -lt 1){throw 'Scenario resumed movement lacks the actual vanilla key binding.'}
    }
    $proof.requested_face=$face;$proof.confirmed_network_actions=3;$proof.inventory=$inventory
    return [pscustomobject]$proof
}

function New-HudWalkingAimedAdmission([string]$Run,[string]$ProbeRun,$LivePatch,$Context) {
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $ProbeRun -cnotmatch '^[0-9a-f]{32}$' -or
        $LivePatch.Run -cnotmatch '^[0-9a-f]{32}$' -or $LivePatch.Hash -cnotmatch '^[0-9a-f]{64}$') {throw 'Invalid combined controller identity.'}
    [pscustomobject]@{Run=$Run;ProbeRun=$ProbeRun;PatchRun=$LivePatch.Run;PatchHash=$LivePatch.Hash;
        TargetPid=$Context.GamePid;TargetStart=$Context.GameStartedUtc.ToFileTimeUtc().ToString();
        Ready=$null;Closed=$null;LastSample=$null;Stationary=[Collections.Generic.List[object]]::new();
        LastSourceMs=-1.0;LastTraceSeq=0L;LastViewSeq=0L;LastClock=0L;Stopping=$false}
}
function Assert-HudWalkingAimedIdentity($Receipt,$State,[string]$Save,[string]$Kind,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'schema') 'combined schema' 1 1)
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'utc_ms') 'combined receipt clock' $MinimumUtcMs ($NowUtcMs+50))
    if($Receipt.kind -cne $Kind -or $Receipt.run -cne $State.Run -or $Receipt.save -cne $Save -or
        $Receipt.patch_run -cne $State.PatchRun -or $Receipt.patch_sha256 -cne $State.PatchHash -or
        $Receipt.target_pid -ne $State.TargetPid -or $Receipt.target_start_filetime -cne $State.TargetStart){throw 'Combined receipt identity differs.'}
}
function Assert-HudWalkingAimedProducer($Receipt) {
    Assert-HudWalkingSession $Receipt -ExtendedWalking
    foreach($name in @('ui_input_walking_aimed','ui_input_physical_movement','ui_input_aimed_stone_bridge','ui_input_stone_bridge','ui_input_stone_live','ui_input_live_mouse','ui_input_offscreen_presentation')) {
        Assert-HudBufferedFlag (Get-HudBufferedField $Receipt $name) $name $true
    }
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'ui_input_protocol') 'combined UI protocol' 2 2)
    foreach($name in @('ui_physical_controller_fixture','ui_walking_aimed_fixture','scripted_input')) {
        $field=$Receipt.PSObject.Properties[$name]
        if($field -and ($name -ceq 'ui_physical_controller_fixture' -or $field.Value -isnot [bool] -or $field.Value)) {throw 'Fixture cannot authorize combined live input.'}
    }
    foreach($name in @('ui_input_fixture','ui_input_stone_fixture','ui_input_pointer_fixture','ui_input_delay_fixture','ui_input_background_trial','ui_input_offscreen_trial')) {
        Assert-HudBufferedFlag (Get-HudBufferedField $Receipt $name) $name $false
    }
}
function Set-HudWalkingAimedReady($State,$Receipt,$Receiver,[string]$Save,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    if($State.Ready -or $State.Stopping){throw 'Combined alignment cannot be replaced.'}
    Assert-HudWalkingAimedIdentity $Receipt $State $Save 'minecome_hud_walking_aim_ready_v1' $MinimumUtcMs $NowUtcMs
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'bootstrap_confirmed') 'bootstrap confirmation' $true
    foreach($name in @('initial_guest_feet','initial_guest_eye','host_anchor','host_player_anchor')) {
        [void](Get-HudBufferedVector (Get-HudBufferedField $Receipt $name) $name)
    }
    if((Get-HudBufferedDistance $Receipt.initial_guest_feet $Receiver.Anchor) -gt .01 -or
        (Get-HudBufferedDistance $Receipt.host_player_anchor $Receiver.Center) -gt .05 -or
        (Get-HudBufferedDistance $Receipt.host_anchor $Receipt.host_player_anchor) -gt 3 -or
        (Get-HudBufferedDistance $Receipt.initial_guest_eye $Receipt.initial_guest_feet) -gt 3){throw 'Combined alignment does not match the terrain/player anchors.'}
    $offer=$Receipt.arena_offer
    foreach($pair in @(@('minecraftAnchor','initial_guest_eye'),@('kcdAnchor','host_anchor'))) {
        if((Get-HudBufferedDistance (Get-HudBufferedVector (Get-HudBufferedField $offer $pair[0]) $pair[0]) $Receipt.($pair[1])) -gt .000001){throw 'Combined arena offer differs from its alignment.'}
    }
    [void](Get-HudBufferedNumber (Get-HudBufferedField $offer 'blocksPerUnit') 'combined scale' 1 1)
    $State.Ready=$Receipt
}
function Add-HudWalkingAimedSample($State,$Received,[double]$SourceMs) {
    if($Received.Kind -cne 'sample'){throw 'Combined admission requires an already validated source sample.'}
    $frame=$Received.Record
    [void](Get-HudBufferedNumber $SourceMs 'combined source time' 0 16000)
    if($frame.seq -le $State.LastTraceSeq -or $SourceMs -le $State.LastSourceMs){throw 'Combined trace order regressed.'}
    $sample=[pscustomobject]@{Record=$frame;Target=$Received.Target;SourceMs=$SourceMs}
    $stationary=$frame.phase -cin @('SETTLING','RESTING','WALKING')
    foreach($side in @('client','server')) {
        $pose=$frame.$side
        if(-not $pose.on_ground -or -not $pose.proxy_support -or
            [Math]::Sqrt($pose.vx*$pose.vx+$pose.vz*$pose.vz) -ge .03 -or [Math]::Abs($pose.vy) -ge .1){$stationary=$false}
    }
    if((Get-HudBufferedDistance $frame.client $frame.server) -gt .01){$stationary=$false}
    if($State.LastSample -and ($SourceMs-$State.LastSourceMs -gt 200 -or
        (Get-HudBufferedDistance $frame.client $State.LastSample.Record.client) -gt .01 -or
        (Get-HudBufferedDistance $frame.server $State.LastSample.Record.server) -gt .01)){$State.Stationary.Clear()}
    if(-not $stationary){$State.Stationary.Clear()}
    else {
        $State.Stationary.Add($sample)
        while($State.Stationary.Count -gt 8){$State.Stationary.RemoveAt(0)}
        # Compare the full retained window, not only adjacent tiny changes.
        while($State.Stationary.Count -gt 1 -and ((Get-HudBufferedDistance $frame.client $State.Stationary[0].Record.client) -gt .01 -or
            (Get-HudBufferedDistance $frame.server $State.Stationary[0].Record.server) -gt .01)){$State.Stationary.RemoveAt(0)}
    }
    $State.LastSample=$sample;$State.LastSourceMs=$SourceMs;$State.LastTraceSeq=[long]$frame.seq
}
function Get-HudWalkingAimedDecline($State,$View,$NativeView,[long]$NowUtcMs) {
    if($NowUtcMs -lt $State.LastClock){throw 'Combined admission clock regressed.'};$State.LastClock=$NowUtcMs
    if($State.Stopping -or $State.Closed){return 'aim_closing'}
    if(-not $State.Ready){return 'aim_bootstrap_pending'}
    if(-not $State.LastSample -or $State.Stationary.Count -lt 3){return 'guest_not_settled'}
    $latest=$State.LastSample;$first=$State.Stationary[0];$frame=$latest.Record
    $age=$NowUtcMs-[long]$frame.utc_ms
    if($age -lt 0 -or $age+$frame.server_age_ns/1000000.0 -gt 300){return 'guest_source_stale'}
    # Reserve three seconds of the unchanged15-second input authority. These
    # source times are original server times, never controller-receipt times.
    if($latest.SourceMs+$age+$frame.server_age_ns/1000000.0 -ge 12000){return 'completion_tail'}
    if($latest.SourceMs-$first.SourceMs -lt 200){return 'guest_not_settled'}
    if(-not $View -or -not $NativeView){return 'host_view_unavailable'}
    if($View.run -cne $State.Run -or $View.patch_run -cne $State.PatchRun -or $View.patch_sha256 -cne $State.PatchHash -or
        $View.target_pid -ne $State.TargetPid -or $View.target_start_filetime -cne $State.TargetStart -or
        $View.source_kind -cne 'live_kcd_hud_view_v1' -or $NativeView.run -cne $State.ProbeRun -or
        $NativeView.seq -ne $View.seq -or $NativeView.result -cne 'sampled' -or
        $NativeView.physical_movement -isnot [bool] -or -not $NativeView.physical_movement -or
        $NativeView.camera_basis_valid -isnot [bool] -or -not $NativeView.camera_basis_valid){throw 'Combined native view identity differs.'}
    [void](Get-HudBufferedInteger $View.seq 'combined view sequence' 1 1024)
    [void](Get-HudBufferedInteger $View.utc_ms 'combined view original clock' 1 ([long]::MaxValue))
    if($View.seq -lt $State.LastViewSeq){throw 'Combined view sequence regressed.'};$State.LastViewSeq=$View.seq
    if($NowUtcMs -lt $View.utc_ms -or $NowUtcMs-$View.utc_ms -gt 300){return 'host_view_stale'}
    # Require a native sample requested after the stationary source had time to
    # cross the existing200ms playback buffer. Matching coordinates alone cannot
    # certify that an old host view has caught up.
    if($View.utc_ms -lt $first.Record.utc_ms+200){return 'host_playback_not_settled'}
    $camera=Get-HudBufferedCamera $NativeView.camera 'combined native camera'
    $player=Get-HudBufferedVector $NativeView.player 'combined native player'
    foreach($part in @('forward','up')) {foreach($axis in @('x','y','z')){
        if($View.$part.$axis -ne $camera.$part.$axis){throw 'Combined published camera differs from its original receipt.'}
    }}
    if((Get-HudBufferedDistance $player $latest.Target) -gt .05){return 'host_player_not_settled'}
    $alignment=$State.Ready;$delta=[pscustomobject]@{x=$frame.server.x-$alignment.initial_guest_feet.x;y=$frame.server.y-$alignment.initial_guest_feet.y;z=$frame.server.z-$alignment.initial_guest_feet.z}
    $expected=[pscustomobject]@{x=$alignment.host_anchor.x+$delta.x;y=$alignment.host_anchor.y-$delta.z;z=$alignment.host_anchor.z+$delta.y}
    # Use the existing aimed-ray eye-origin allowance; the player's delayed
    # feet position still has the stricter.05m catch-up requirement above.
    if((Get-HudBufferedDistance $camera.position $expected) -gt .25){return 'host_camera_not_settled'}
    return $null
}
function Set-HudWalkingAimedClosed($State,$Receipt,[string]$Save,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    if(-not $State.Ready -or $State.Closed){throw 'Combined closure requires one established alignment.'}
    Assert-HudWalkingAimedIdentity $Receipt $State $Save 'minecome_hud_walking_aim_closed_v1' $MinimumUtcMs $NowUtcMs
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'logical_closed') 'logical aim closure' $true
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'pending') 'pending aim request' $false
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'owned_count') 'remaining owned stones' 0 16)
    foreach($flag in @('guest_world_cleanup_complete','support_cleanup_complete')) {
        if((Get-HudBufferedField $Receipt $flag) -isnot [bool]){throw 'Combined cleanup evidence must be Boolean.'}
    }
    $State.Closed=$Receipt;$State.Stopping=$true
}
function Assert-HudWalkingAimedCleanup($State,$Relay,[bool]$FollowerFinishRequested) {
    if(-not $State.Closed -or -not $State.Stopping -or $State.Closed.owned_count -ne 0 -or
        -not $State.Closed.guest_world_cleanup_complete -or -not $State.Closed.support_cleanup_complete -or
        -not $Relay.ExitObserved -or $Relay.ExitCode -ne 0 -or -not $Relay.CleanupVerified -or -not $Relay.InputCleanupVerified -or
        $Relay.Failure -or $Relay.CleanupFailure -or $Relay.ReceiptAuditFailure){throw 'Combined aim authority/world cleanup is not complete.'}
    if($FollowerFinishRequested){throw 'Combined aim cleanup must be verified before follower restoration is requested.'}
}
function Initialize-HudWalkingAimedClicks($State,$Session){
    if($State.Run -cne $Session.Run){throw 'Aimed reader and relay runs differ.'}
    $path=Assert-MineComeHudStonePath $Session.Stdout
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        $reader=[pscustomobject]@{Path=$path;Identity=(Get-MineComeHudWorldFileIdentity $stream);Offset=0L;ReadBytes=0L;Pending=[byte[]]@();DiscardInitialFragment=$false}
    }finally{$stream.Dispose()}
    $State | Add-Member NoteProperty AimedLedger (New-MineComeAimedClickLedger $State.Run)
    $State | Add-Member NoteProperty PermitReader $reader
}
function Get-HudWalkingAimedCurrentDecline($State,$Session,$Click,$Selection,[scriptblock]$SettledAdmission){
    $reason=Get-MineComeHudWorldCurrentDecline $State $Session $Click
    if($reason){return $reason}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($now -lt $Selection.installed_utc_ms -or $now -lt $Click.utc_ms){return 'clock_rollback'}
    if($now-$Selection.installed_utc_ms -gt 350){return 'permit_dispatch_expired'}
    if($now-$Click.utc_ms -gt 250){return 'stale_edge'}
    if(-not $SettledAdmission){throw 'Combined clicks require current settled admission.'}
    $reason=& $SettledAdmission $now
    if($reason){return [string]$reason}
    return $null
}
function Update-HudWalkingAimedPermitLedger($State){
    foreach($line in @(Read-MineComeHudWorldClickLines $State.PermitReader)){Add-MineComeAimedPermitLine $State.AimedLedger $line}
}
function Invoke-HudWalkingAimedClicks($State,$Session,[scriptblock]$SettledAdmission){
    if($State.Failure){throw 'Aimed world-click reader is already failed; input will not be retried.'}
    try{
        if($State.Run -cne $Session.Run -or $State.Context.GamePid -ne $Session.Context.GamePid -or $State.Context.GameStartedUtc -ne $Session.Context.GameStartedUtc){throw 'Aimed world-click relay owner differs.'}
        # Read acknowledgements first. Selection still requires their native
        # installation timestamp to precede the physical edge strictly.
        Update-HudWalkingAimedPermitLedger $State
        foreach($line in @(Read-MineComeHudWorldClickLines $State)){
            $click=ConvertFrom-MineComeHudWorldClick $line $State.Run $State.Sequence
            if($null -eq $click){continue}
            $State.Sequence=$click.sequence
            $record=[pscustomobject]@{sequence=$click.sequence;utc_ms=$click.utc_ms;action=$click.action;observed_utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();status='pending';reason=$null;intent_ordinal=0;request_id=0L;arena_id=$null;permit_id=$null;installed_utc_ms=0L;
                timings=[pscustomobject]@{selection_ms=0.;admission_ms=0.;admission_calls=0;send_including_admission_ms=0.;send_excluding_admission_ms=0.;processing_ms=0.;game_input_latency_measured=$false}}
            $State.Clicks.Add($record)
            $clickTiming=$record.timings
            $processing=[Diagnostics.Stopwatch]::StartNew()
            try{
            # Admission consumes every sequence, including foreground/lease
            # refusals; a selected permit is spent even if dispatch then fails.
            $selectionWatch=[Diagnostics.Stopwatch]::StartNew()
            try{$selection=Select-MineComeAimedClickPermit $State.AimedLedger $click $record.observed_utc_ms}
            finally{$record.timings.selection_ms=$selectionWatch.Elapsed.TotalMilliseconds}
            if(-not $selection.accepted){$record.status='declined';$record.reason=$selection.reason;continue}
            $record.arena_id=$selection.arena;$record.permit_id=$selection.permit;$record.installed_utc_ms=$selection.installed_utc_ms
            # The sender invokes this admission after its owner/permit reads and
            # before recording or sending anything. Doing the same camera/log
            # reads here first needlessly spends the original edge/permit lease.
            $sendWatch=[Diagnostics.Stopwatch]::StartNew()
            try{
                $receipt=Send-MineComeHudAimedIntent $Session $selection $click -BeforeDispatch {
                    $clickTiming.admission_calls++;$admissionWatch=[Diagnostics.Stopwatch]::StartNew()
                    try{Get-HudWalkingAimedCurrentDecline $State $Session $click $selection $SettledAdmission}
                    finally{$clickTiming.admission_ms+=$admissionWatch.Elapsed.TotalMilliseconds}
                }
            }finally{
                $record.timings.send_including_admission_ms=$sendWatch.Elapsed.TotalMilliseconds
                $record.timings.send_excluding_admission_ms=[Math]::Max(0,$record.timings.send_including_admission_ms-$record.timings.admission_ms)
            }
            if(-not $receipt.accepted){$record.status='declined';$record.reason=$receipt.reason;continue}
            $record.status='sent';$record.intent_ordinal=$receipt.ordinal;$record.request_id=$receipt.request_id
            }finally{$record.timings.processing_ms=$processing.Elapsed.TotalMilliseconds}
        }
    }catch{$State.Failure=$_.Exception.Message;if($State.Clicks.Count -gt 0 -and $State.Clicks[-1].status -ceq 'pending'){$State.Clicks[-1].status='failed';$State.Clicks[-1].reason=$State.Failure};throw}
}
function Assert-HudWalkingAimedClicks($State,$Session){
    Assert-MineComeHudWorldClicks $State $Session
    if($State.AimedLedger.Failed -or $State.AimedLedger.LastClick -ne $State.Sequence){throw 'Aimed physical-edge ledger did not complete.'}
    $sent=@($State.Clicks | Where-Object status -CEQ 'sent')
    for($i=0;$i -lt $sent.Count;$i++){
        $click=$sent[$i];$intent=$Session.Intents[$i]
        if([string]$click.arena_id -cne [string]$intent.arena_id -or [string]$click.permit_id -cne [string]$intent.permit_id -or
           $click.sequence -ne $intent.sequence -or $click.sequence -ne $intent.request_id -or
           $click.utc_ms -ne $intent.edge_utc_ms -or $click.installed_utc_ms -ne $intent.installed_utc_ms -or
           $click.installed_utc_ms -ge $click.utc_ms){throw 'Aimed physical edge differs from its original installed permit.'}
    }
}
