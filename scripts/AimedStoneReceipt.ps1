# Standalone receipt validation; loading this file performs no process or game operations.
function Assert-MineComeAimedStoneReceipt {
    param([object]$Receipt,[string]$Run,[int]$ProducerPid,[string]$ProducerStart)
    function Need($Object,[string[]]$Names) {
        if($Object -is [Collections.IDictionary]){$keys=@($Object.Keys)}
        elseif($null -ne $Object -and $Object -is [pscustomobject]){$keys=@($Object.PSObject.Properties.Name)}
        else{throw 'Aimed fixture object required.'}
        foreach($name in $Names){if($keys -notcontains $name){throw "Missing aimed fixture field: $name"}}
    }
    function Bool($Object,[string]$Name,[bool]$Expected){Need $Object @($Name);if($Object.$Name -isnot [bool] -or $Object.$Name -ne $Expected){throw "Aimed fixture Boolean differs: $Name"}}
    function Text($Object,[string]$Name,[string]$Expected){Need $Object @($Name);if($Object.$Name -isnot [string] -or $Object.$Name -cne $Expected){throw "Aimed fixture text differs: $Name"}}
    function Integer($Object,[string]$Name,[long]$Expected){Need $Object @($Name);$v=$Object.$Name;if(($v -isnot [int] -and $v -isnot [long]) -or $v -ne $Expected){throw "Aimed fixture integer differs: $Name"}}
    function Number($Value,[double]$Minimum,[double]$Maximum) {
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or
           [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Aimed fixture finite number required.'}
        return [double]$Value
    }
    function Vector($Value){Need $Value @('x','y','z');return @((Number $Value.x -10000000 10000000),(Number $Value.y -10000000 10000000),(Number $Value.z -10000000 10000000))}
    function Near([double]$First,[double]$Second,[double]$Tolerance=0.000001){if([Math]::Abs($First-$Second) -gt $Tolerance){throw 'Aimed fixture geometry correlation differs.'}}
    function Cell($Value){Need $Value @('x','y','z');foreach($a in @('x','y','z')){$v=$Value.$a;if(($v -isnot [int] -and $v -isnot [long]) -or $v -lt -10000000 -or $v -gt 10000000){throw 'Aimed fixture integer cell required.'}}}
    function SameCell($First,$Second){Cell $First;Cell $Second;foreach($a in @('x','y','z')){if($First.$a -ne $Second.$a){throw 'Aimed fixture target correlation differs.'}}}
    function Offset($Cell,[int]$X,[int]$Y,[int]$Z){return @{x=[long]$Cell.x+$X;y=[long]$Cell.y+$Y;z=[long]$Cell.z+$Z}}
    function ConfirmationInventory($Proof,[int]$ClientSelected,[int[]]$ServerSelected) {
        Need $Proof @('confirmation_inventory')
        $inventory=$Proof.confirmation_inventory
        Integer $inventory original_slot 0;Integer $inventory client_selected_slot $ClientSelected
        Need $inventory @('server_selected_slot')
        $slot=$inventory.server_selected_slot
        if(($slot -isnot [int] -and $slot -isnot [long]) -or $ServerSelected -notcontains $slot){throw 'Aimed confirmation server selection differs.'}
        Text $inventory client_original_item 'minecraft:stone';Integer $inventory client_original_count 64
        Text $inventory server_original_item 'minecraft:stone';Integer $inventory server_original_count 64
    }
    function Point($Value,$Block,[string]$Face) {
        if($Value -isnot [array] -or $Value.Count -ne 3){throw 'Aimed hit point array required.'}
        $axes=@('x','y','z');for($i=0;$i -lt 3;$i++){$null=Number $Value[$i] ($Block.($axes[$i])-0.000001) ($Block.($axes[$i])+1.000001)}
        switch -CaseSensitive ($Face){DOWN{Near $Value[1] $Block.y} UP{Near $Value[1] ($Block.y+1)} NORTH{Near $Value[2] $Block.z} SOUTH{Near $Value[2] ($Block.z+1)} WEST{Near $Value[0] $Block.x} EAST{Near $Value[0] ($Block.x+1)} default{throw 'Invalid aimed hit face.'}}
    }
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $ProducerPid -le 0 -or $ProducerStart -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'Invalid expected aimed fixture identity.'}
    Need $Receipt @('schema','kind','run','save','producer_pid','producer_start_filetime','result','failure','checks','fixture_teleports','arena','final_client_server_air_cells','original_stack_mutation')
    Integer $Receipt schema 1;Integer $Receipt producer_pid $ProducerPid
    $expectedSave='MineCome-AimedStone-'+[guid]::ParseExact($Run,'N').ToString('D')
    Text $Receipt kind 'minecome_aimed_stone_fixture_v1';Text $Receipt run $Run;Text $Receipt save $expectedSave
    Text $Receipt producer_start_filetime $ProducerStart;Text $Receipt result 'passed';Text $Receipt failure ''
    foreach($field in @('synthetic_host_rays','bootstrap_confirmed','options_restored')){Bool $Receipt $field $true}
    foreach($field in @('kcd_connected','world_block_writes')){Bool $Receipt $field $false}
    $arena=$Receipt.arena
    Need $arena @('schema','kind','save','failure','owned_cells','requests','confirmations','seed','alignment','arena_minimum','arena_maximum_inclusive')
    Integer $arena schema 1;Text $arena kind 'minecome_aimed_stone_arena_v1';Text $arena save $expectedSave
    if($null -ne $arena.failure){throw 'Aimed arena failed.'}
    foreach($field in @('ready','bootstrapped','vanilla_outline_raycast')){Bool $arena $field $true}
    foreach($field in @('pending','live_transport_enabled')){Bool $arena $field $false}
    foreach($field in @('owned_count','omitted_receipts','block_writes','inventory_writes','camera_writes')){Integer $arena $field 0}
    Integer $arena max_owned_count 16;Integer $arena max_ray_age_ms 500
    Near (Number $arena.eye_tolerance 0 1) 0.25;Near (Number $arena.max_host_ray_range 0 32) 4.5;Text $arena fluid_raycast 'NONE'
    if(@($arena.owned_cells).Count -ne 0){throw 'Aimed arena cleanup incomplete.'}
    Cell $arena.seed;$seed=$arena.seed;$middle=Offset $seed 0 1 0;$top=Offset $seed 0 2 0;$east=Offset $seed 1 2 0
    SameCell $arena.arena_minimum (Offset $seed -2 -2 -2);SameCell $arena.arena_maximum_inclusive (Offset $seed 2 2 2)
    Need $arena.alignment @('minecraft_anchor','host_anchor','blocks_per_host_unit')
    foreach($v in ((Vector $arena.alignment.minecraft_anchor)+(Vector $arena.alignment.host_anchor))){Near $v 0}
    Near (Number $arena.alignment.blocks_per_host_unit 0.0001 10000) 1
    # This auxiliary arena intentionally fails after vanilla has broken its seed.
    # Keep its stale confirmed ownership visible; independent air observations
    # and inventory restoration establish cleanup without inventing a confirmation.
    $mutation=$Receipt.original_stack_mutation
    Integer $mutation schema 1;Text $mutation kind 'minecome_aimed_stack_mutation_fixture_v1'
    foreach($field in @('expected_failure','observed_dispatched','mutation_after_dispatch','client_server_seed_air','closed','inventory_restored')){Bool $mutation $field $true}
    Integer $mutation original_slot 0;Text $mutation original_item 'minecraft:stone'
    foreach($field in @('before_count','restored_client_count','restored_server_count')){Integer $mutation $field 64}
    foreach($field in @('mutated_count','client_mutated_count','server_mutated_count')){Integer $mutation $field 63}
    Need $mutation @('arena');$failedArena=$mutation.arena
    Integer $failedArena schema 1;Text $failedArena kind 'minecome_aimed_stone_arena_v1';Text $failedArena save $expectedSave
    Text $failedArena failure 'selected_stack_changed_during_action'
    foreach($field in @('ready','pending','live_transport_enabled')){Bool $failedArena $field $false}
    foreach($field in @('bootstrapped','vanilla_outline_raycast')){Bool $failedArena $field $true}
    foreach($field in @('omitted_receipts','block_writes','inventory_writes','camera_writes')){Integer $failedArena $field 0}
    Integer $failedArena owned_count 1;Integer $failedArena max_owned_count 16;Integer $failedArena max_ray_age_ms 500
    Near (Number $failedArena.eye_tolerance 0 1) 0.25;Near (Number $failedArena.max_host_ray_range 0 32) 4.5;Text $failedArena fluid_raycast 'NONE'
    SameCell $failedArena.seed $seed;SameCell $failedArena.arena_minimum $arena.arena_minimum;SameCell $failedArena.arena_maximum_inclusive $arena.arena_maximum_inclusive
    Need $failedArena @('alignment','owned_cells','requests','confirmations')
    Need $failedArena.alignment @('minecraft_anchor','host_anchor','blocks_per_host_unit')
    foreach($v in ((Vector $failedArena.alignment.minecraft_anchor)+(Vector $failedArena.alignment.host_anchor))){Near $v 0}
    Near (Number $failedArena.alignment.blocks_per_host_unit 0.0001 10000) 1
    if(@($failedArena.owned_cells).Count -ne 1 -or @($failedArena.requests).Count -ne 2 -or @($failedArena.confirmations).Count -ne 1){throw 'Auxiliary mutation arena proof counts differ.'}
    SameCell $failedArena.owned_cells[0] $seed
    $auxConfirmed=$failedArena.confirmations[0];$auxRequested=$failedArena.requests[0];$auxRefused=$failedArena.requests[1]
    foreach($proof in @($auxConfirmed,$auxRequested)){
        Integer $proof id 1;Integer $proof action 1;Text $proof status 'confirmed';Text $proof reason 'client_and_integrated_server'
        Bool $proof client_and_server $true;Bool $proof bootstrap $true
        SameCell $proof.target $seed;SameCell $proof.hit_block (Offset $seed 0 -1 0);Text $proof face 'UP';Point $proof.hit_point $proof.hit_block 'UP'
        Integer $proof selected_slot 0;Text $proof selected_item 'minecraft:stone';Integer $proof selected_count 64
        ConfirmationInventory $proof 0 @(0)
    }
    for($axis=0;$axis -lt 3;$axis++){Near $auxRequested.hit_point[$axis] $auxConfirmed.hit_point[$axis]}
    Integer $auxRefused id 2;Integer $auxRefused action 2;Text $auxRefused status 'rejected';Text $auxRefused reason 'selected_stack_changed_during_action'
    Bool $auxRefused client_and_server $false;Bool $auxRefused bootstrap $false
    SameCell $auxRefused.target $seed;SameCell $auxRefused.hit_block $seed;Point $auxRefused.hit_point $seed $auxRefused.face
    Integer $auxRefused selected_slot 0;Text $auxRefused selected_item 'minecraft:stone';Integer $auxRefused selected_count 64
    Need $auxRefused @('host_ray');$auxRay=$auxRefused.host_ray
    Need $auxRay @('origin','direction','range','age_at_queue_ns','host_obstruction','host_obstruction_distance')
    $null=Vector $auxRay.origin;$auxDirection=Vector $auxRay.direction
    Near ($auxDirection[0]*$auxDirection[0]+$auxDirection[1]*$auxDirection[1]+$auxDirection[2]*$auxDirection[2]) 1
    Near (Number $auxRay.range 0.0001 32) 4.5;$null=Number $auxRay.age_at_queue_ns 0 500000000
    Text $auxRay host_obstruction 'KNOWN_CLEAR';Near (Number $auxRay.host_obstruction_distance 0 4.5) 0
    $cleanup=@($Receipt.final_client_server_air_cells);$expectedCells=@($seed,$middle,$top,$east)
    if($cleanup.Count -ne 4){throw 'Final client/server cleanup count differs.'}
    foreach($expected in $expectedCells){$matches=0;foreach($actual in $cleanup){Cell $actual;if($actual.x -eq $expected.x -and $actual.y -eq $expected.y -and $actual.z -eq $expected.z){$matches++}};if($matches -ne 1){throw 'Final client/server cleanup cells differ.'}}
    $names=@('column_middle','column_top','remove_seed','remove_middle','face_down','face_up','face_north','face_south','face_west','face_east','place_east','nearest','miss','unowned_floor','host_occluded','host_occlusion_unavailable','stale_ray','origin_mismatch','alignment_changed','view_origin_measured','view_origin_boundary','view_origin_over_limit','cancel_before_dispatch','turn_while_pending','slot_changed_before_dispatch','slot_changed_after_place','slot_changed_after_break','cleanup_top')
    $rejections=@{miss='ray_miss';unowned_floor='unowned_hit';host_occluded='host_obstructed';host_occlusion_unavailable='host_obstruction_unavailable';stale_ray='ray_stale';origin_mismatch='ray_origin_disagrees_with_eye';alignment_changed='alignment_changed';view_origin_over_limit='ray_origin_disagrees_with_eye'}
    $dispatch=@{column_middle=1;column_top=1;remove_seed=2;remove_middle=2;place_east=1;turn_while_pending=2;slot_changed_after_place=1;slot_changed_after_break=2;cleanup_top=2}
    if(@($Receipt.checks).Count -ne $names.Count -or @($Receipt.fixture_teleports).Count -ne $names.Count){throw 'Aimed scenario/teleport count mismatch.'}
    $confirmations=@($arena.confirmations);$requests=@($arena.requests)
    if($confirmations.Count -ne 10 -or $requests.Count -ne 20){throw 'Aimed action/refusal proof count differs.'}
    $ids=@(1,2,3,4,5,6,15,17,18,19);$actions=@(1,1,1,2,2,1,2,1,2,2);$targets=@($seed,$middle,$top,$seed,$middle,$east,$east,$east,$east,$top)
    $hitCells=@((Offset $seed 0 -1 0),$seed,$middle,$seed,$middle,$top,$east,$top,$east,$top);$faces=@('UP','UP','UP','WEST','WEST','EAST','EAST','EAST','EAST','WEST')
    for($i=0;$i -lt $confirmations.Count;$i++) {
        $c=$confirmations[$i];Integer $c id $ids[$i];Integer $c action $actions[$i];Bool $c client_and_server $true;Bool $c bootstrap ($i -eq 0)
        Text $c status 'confirmed';Text $c reason 'client_and_integrated_server';Text $c face $faces[$i]
        SameCell $c.target $targets[$i];SameCell $c.hit_block $hitCells[$i];Point $c.hit_point $c.hit_block $c.face
        Integer $c selected_slot 0;Text $c selected_item 'minecraft:stone';Integer $c selected_count 64
        if($c.id -in @(17,18)){ConfirmationInventory $c 1 @(0,1)}else{ConfirmationInventory $c 0 @(0)}
        if($i -gt 0){Need $c @('host_ray');Need $c.host_ray @('origin','direction','range','age_at_queue_ns','host_obstruction','host_obstruction_distance');$null=Number $c.host_ray.age_at_queue_ns 0 500000000;Text $c.host_ray host_obstruction 'KNOWN_CLEAR';Near (Number $c.host_ray.host_obstruction_distance 0 4.5) 0}
    }
    $requestIds=@(1,2,3,4,5,6,7,7,8,9,10,11,12,13,14,15,16,17,18,19)
    $confirmedById=@{};foreach($c in $confirmations){$confirmedById[[long]$c.id]=$c}
    $rejectedReasons=@('ray_miss','unowned_hit','host_obstructed','host_obstruction_unavailable','ray_stale','ray_origin_disagrees_with_eye','alignment_changed','actions_disabled_before_dispatch')
    for($i=0;$i -lt $requests.Count;$i++) {
        $q=$requests[$i];$id=$requestIds[$i];Integer $q id $id
        if($confirmedById.ContainsKey([long]$id)) {
            $c=$confirmedById[[long]$id];Integer $q action $c.action;Bool $q client_and_server $true;Text $q status 'confirmed';Text $q reason 'client_and_integrated_server'
            SameCell $q.target $c.target;SameCell $q.hit_block $c.hit_block;Text $q face $c.face;Point $q.hit_point $q.hit_block $q.face
            for($axis=0;$axis -lt 3;$axis++){Near $q.hit_point[$axis] $c.hit_point[$axis]}
            Integer $q selected_slot 0;Text $q selected_item 'minecraft:stone';Integer $q selected_count 64
            ConfirmationInventory $q $c.confirmation_inventory.client_selected_slot @($c.confirmation_inventory.server_selected_slot)
        } else {
            Integer $q action 2;Bool $q client_and_server $false;Text $q status 'rejected'
            if($i -eq 7){Text $q reason 'request_id_not_increasing'}
            elseif($id -eq 16){
                Text $q reason 'selected_stack_changed';Bool $q bootstrap $false
                SameCell $q.target $top;SameCell $q.hit_block $top;Text $q face 'WEST';Point $q.hit_point $top 'WEST'
                Integer $q selected_slot 0;Text $q selected_item 'minecraft:stone';Integer $q selected_count 64
            }else{Text $q reason $rejectedReasons[$id-7]}
        }
    }
    $actionIndex=1;$negativeId=7
    for($i=0;$i -lt $names.Count;$i++) {
        $c=$Receipt.checks[$i];$name=$names[$i];$t=$Receipt.fixture_teleports[$i];$negative=$rejections.ContainsKey($name);$doesDispatch=$dispatch.ContainsKey($name)
        Text $c name $name;Text $t scenario $name;Bool $t client_server_eye_agreed $true;Bool $c passed $true
        Bool $c selection_allowed (-not $negative);Bool $c vanilla_dispatch $doesDispatch;Bool $c client_and_server_confirmed $doesDispatch
        $selectionOnlyRefusal=$name -eq 'view_origin_over_limit'
        Bool $c view_turned_after_queue ($name -eq 'turn_while_pending');Bool $c rejected_request_checked ($negative -and -not $selectionOnlyRefusal);Bool $c rejected_id_replay_checked ($name -eq 'miss')
        if($negative){Text $c reason $rejections[$name];if(-not $selectionOnlyRefusal){Integer $c request_id $negativeId;Integer $c action 2;$negativeId++}}else{Text $c reason 'selected'}
        if($name -eq 'cancel_before_dispatch'){
            Integer $c request_id 14;Integer $c action 2;Bool $c queued_then_cancelled $true
            Text $c cancellation_reason 'actions_disabled_before_dispatch';Bool $c client_server_cells_unchanged $true
            SameCell $c.target $east;SameCell $c.hit_block $east;Text $c face 'east'
        }
        if($name -eq 'slot_changed_before_dispatch'){
            Integer $c request_id 16;Integer $c action 2;Bool $c queued_then_cancelled $true
            Text $c cancellation_reason 'selected_stack_changed';Bool $c client_server_cells_unchanged $true
            SameCell $c.target $top;SameCell $c.hit_block $top;Text $c face 'west'
        }
        if($name.StartsWith('slot_changed_')){
            Need $c @('selection_change');$change=$c.selection_change
            if($name -eq 'slot_changed_before_dispatch'){Text $change phase 'before_dispatch';Text $change observed_status 'queued'}
            else{Text $change phase 'after_dispatch';Text $change observed_status 'dispatched'}
            foreach($field in @('before_slot','original_slot','restored_client_slot','restored_server_slot')){Integer $change $field 0}
            foreach($field in @('after_slot','client_changed_slot','server_changed_slot')){Integer $change $field 1}
            Text $change original_item 'minecraft:stone';Integer $change original_count 64
        }
        if($name.StartsWith('face_')){Text $c face $name.Substring(5);SameCell $c.hit_block $top;SameCell $c.target $top}
        if($name -eq 'nearest'){SameCell $c.target $east;SameCell $c.hit_block $east;Text $c face 'east'}
        if($name -in @('view_origin_measured','view_origin_boundary')){SameCell $c.target $top;SameCell $c.hit_block $top;Text $c face 'west'}
        if($doesDispatch){$proof=$confirmations[$actionIndex++];Integer $c request_id $proof.id;Integer $c action $dispatch[$name];SameCell $c.target $proof.target;SameCell $c.hit_block $proof.hit_block;Text $c face $proof.face.ToLowerInvariant()}
        Need $c @('synthetic_ray');$ray=$c.synthetic_ray
        Need $ray @('host_origin','host_direction','host_range','minecraft_anchor','host_anchor','blocks_per_host_unit','occlusion_kind','host_obstruction_distance','age_at_selection_ns')
        $origin=Vector $ray.host_origin;$direction=Vector $ray.host_direction;$eye=Vector $t.eye;$anchor=Vector $ray.minecraft_anchor;$hostAnchor=Vector $ray.host_anchor
        Near (Number $ray.host_range 0.0001 32) 4.5;Near (Number $ray.blocks_per_host_unit 0.0001 10000) 1
        Near ($direction[0]*$direction[0]+$direction[1]*$direction[1]+$direction[2]*$direction[2]) 1
        for($a=0;$a -lt 3;$a++){Near $hostAnchor[$a] 0;$expectedAnchor=0;if($name -eq 'alignment_changed' -and $a -eq 0){$expectedAnchor=1};Near $anchor[$a] $expectedAnchor}
        $mapped=@($origin[0],$origin[2],(-$origin[1]));$errorSquared=0.0
        $viewOffset=switch($name){view_origin_measured{0.17794543}view_origin_boundary{0.25}view_origin_over_limit{0.250001}default{0.0}}
        for($a=0;$a -lt 3;$a++){$expected=$eye[$a];if($name -eq 'origin_mismatch' -and $a -eq 0){$expected++};if($a -eq 0){$expected+=$viewOffset};$errorSquared+=($mapped[$a]-$expected)*($mapped[$a]-$expected);if($name.StartsWith('view_origin_')){Near $mapped[$a] $expected 0.0000001}}
        if($errorSquared -gt 0.0225){throw 'Synthetic ray origin does not correlate to fixture eye.'}
        $age=Number $ray.age_at_selection_ns 0 10000000000
        if($name -eq 'stale_ray'){if($age -le 500000000){throw 'Stale scenario ray was fresh.'}}elseif($age -gt 500000000){throw 'Fresh scenario ray was stale.'}
        $obstruction=Number $ray.host_obstruction_distance 0 4.5
        if($name -eq 'host_occluded'){Text $ray occlusion_kind 'HIT';Near $obstruction 0.25}
        elseif($name -eq 'host_occlusion_unavailable'){Text $ray occlusion_kind 'UNAVAILABLE';Near $obstruction 0}
        else{Text $ray occlusion_kind 'KNOWN_CLEAR';Near $obstruction 0}
        if($doesDispatch){$planned=$proof.host_ray;$po=Vector $planned.origin;$pd=Vector $planned.direction;for($a=0;$a -lt 3;$a++){Near $po[$a] $origin[$a];Near $pd[$a] $direction[$a]};Near (Number $planned.range 0 32) $ray.host_range}
    }
}
