#requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure synthetic receipt tests. No game, process, network, save or engine access.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/AimedBridgeReceipt.ps1')
$script:checks = 0
$run = '0123456789abcdef0123456789abcdef'
$producerStart = '134048700000000000'
function Point($x,$y,$z) {
    # PowerShell's command argument parser passes a bare negative integer as text.
    if($x -is [string]){$x=[int]$x};if($y -is [string]){$y=[int]$y};if($z -is [string]){$z=[int]$z}
    return @{ x=$x; y=$y; z=$z }
}
function Copy-Receipt($value) { return ($value | ConvertTo-Json -Depth 50 | ConvertFrom-Json) }
function Check-Receipt($guest,$native) {
    $output = @(Assert-MineComeAimedBridgeReceipt -Guest $guest -Native $native -Run $run -ProducerPid 4242 -ProducerStart $producerStart)
    if ($output.Count -ne 0) { throw 'Receipt validator unexpectedly emitted output.' }
}
function Reject-Mutation([string]$Name,[scriptblock]$Mutation) {
    $guest = Copy-Receipt $script:validGuest
    $native = Copy-Receipt $script:validNative
    & $Mutation $guest $native
    $rejected = $false
    try { Check-Receipt $guest $native } catch { $rejected = $true }
    if (-not $rejected) { throw "Synthetic malformed aimed bridge receipt accepted: $Name" }
    $script:checks++
}

$seed = Point 2 64 0
$mcEye = Point 0.5 65.62 0.5
$hostEye = Point 100.0 200.0 50.0
$mapped = Point 102.0 200.0 48.88
$distance = [Math]::Sqrt(2.0*2.0 + 1.12*1.12)
$direction = Point (2.0/$distance) 0.0 (-1.12/$distance)
$ray = @{
    origin=$hostEye; direction=$direction; range=4.5; age_at_queue_ns=20000000L
    host_obstruction='KNOWN_CLEAR'; host_obstruction_distance=0.0
}
$baseline = @{
    seed=$seed; seed_air=$true; support_solid_up=$true; selected_item='minecraft:stone'
    selected_count=64; selected_slot=0; observation_age_ns=10000000L; client_eye=$mcEye; server_eye=$mcEye
}
$bootstrap = @{
    id=1; action=1; status='confirmed'; reason='client_and_integrated_server'; client_and_server=$true
    bootstrap=$true; target=$seed; hit_block=(Point 2 63 0); face='UP'; hit_point=@(2.5,64.0,0.5)
    selected_slot=0; selected_item='minecraft:stone'; selected_count=64
}
$broken = @{
    id=2; action=2; status='confirmed'; reason='client_and_integrated_server'; client_and_server=$true
    bootstrap=$false; target=$seed; hit_block=$seed; face='WEST'; hit_point=@(2.0,64.78,0.5)
    selected_slot=0; selected_item='minecraft:stone'; selected_count=64; host_ray=$ray
}
$save = 'MineCome-AimedStone-' + [guid]::ParseExact($run,'N').ToString('D')
$script:validGuest = @{
    schema=1; kind='minecome_aimed_bridge_fixture_v1'; result='passed'; failure=''; run=$run; save=$save
    producer_pid=4242; producer_start_filetime=$producerStart; protocol_minor=2
    kcd_connected=$false; synthetic_host=$true; synthetic_host_rays=$true; network_fixture=$true
    options_restored=$true; arena_acknowledged=$true; bootstrap_confirmed=$true; world_block_writes=$false
    session=1; world=0; reset=0; host_goodbye_session=1
    initial_baseline=$baseline; pre_bootstrap_baseline=$baseline
    arena_offer=@{ arenaId=1; minecraftAnchor=$mcEye; kcdAnchor=$hostEye; blocksPerUnit=1.0
        seed=$seed; minimum=(Point 0 62 -2); maximum=(Point 4 66 2) }
    permits=@(@{ arenaId=1; permitId=1 })
    request=@{ session=1; world=0; reset=0; captured_age_ns=10000000L; component_request_id=2
        wire=@{ arenaId=1; requestId=1; permitId=1; action=2; occlusion=1; origin=$hostEye
            direction=$direction; range=4.5; nearestDistance=0.0 } }
    result_evidence=@{ wire_result=1; client_server_confirmed=$true; local=$broken }
    bridge_status=@{ connected=$false; session=1; world=0; pendingEvents=0; queuedEvents=2
        sentEvents=2; droppedEvents=0; resets=0; receivedPoses=10 }
    block_events=@(
        @{ operation=1; x=2; y=64; z=0; block_id='minecraft:stone'; queued=$true },
        @{ operation=2; x=2; y=64; z=0; block_id='minecraft:stone'; queued=$true }
    )
    final_client_server_air_cells=@($seed)
    arena=@{
        schema=1; kind='minecome_aimed_stone_arena_v1'; save=$save; failure=$null
        ready=$true; bootstrapped=$true; vanilla_outline_raycast=$true; pending=$false
        live_transport_enabled=$false; owned_count=0; omitted_receipts=0; block_writes=0
        inventory_writes=0; camera_writes=0; max_owned_count=16; max_ray_age_ms=500
        eye_tolerance=0.25; max_host_ray_range=4.5; fluid_raycast='NONE'; owned_cells=@()
        seed=$seed; arena_minimum=(Point 0 62 -2); arena_maximum_inclusive=(Point 4 66 2)
        alignment=@{ minecraft_anchor=$mcEye; host_anchor=$hostEye; blocks_per_host_unit=1.0 }
        confirmations=@($bootstrap,$broken); requests=@($bootstrap,$broken)
    }
}
$script:validNative = @{
    schema=1; kind='minecome_aimed_bridge_fixture_v1'; result='passed'; arena_id=1; request_id=1
    result_code=1; placed=1; removed=1; seed=$seed; mapped_seed_center=$mapped; alignment_ack=$true
    kcd_connected=$false; synthetic_host=$true; graceful_stop=$true
}

# Both forms are used by callers: direct dictionaries and deserialized JSON.
Check-Receipt $script:validGuest $script:validNative
$script:checks++
Check-Receipt (Copy-Receipt $script:validGuest) (Copy-Receipt $script:validNative)
$script:checks++

foreach ($field in @($script:validGuest.Keys)) {
    Reject-Mutation "missing guest.$field" { param($g,$n) $g.PSObject.Properties.Remove($field) }
}
foreach ($field in @($script:validNative.Keys)) {
    Reject-Mutation "missing native.$field" { param($g,$n) $n.PSObject.Properties.Remove($field) }
}
foreach ($field in @('run','save','producer_start_filetime','kind','result','failure')) {
    Reject-Mutation "wrong guest.$field" { param($g,$n) $g.$field = 'incorrect' }
}
foreach ($field in @('producer_pid','schema','protocol_minor')) {
    Reject-Mutation "wrong guest.$field" { param($g,$n) $g.$field = 17 }
    Reject-Mutation "string guest.$field" { param($g,$n) $g.$field = [string]$g.$field }
}
foreach ($field in @('kcd_connected','synthetic_host','synthetic_host_rays','network_fixture','options_restored','arena_acknowledged','bootstrap_confirmed','world_block_writes')) {
    Reject-Mutation "wrong Boolean guest.$field" { param($g,$n) $g.$field = -not $g.$field }
    Reject-Mutation "coerced Boolean guest.$field" { param($g,$n) $g.$field = [string]$g.$field }
}
foreach ($field in @('alignment_ack','graceful_stop','kcd_connected','synthetic_host')) {
    Reject-Mutation "wrong native.$field" { param($g,$n) $n.$field = -not $n.$field }
}
foreach ($field in @('placed','removed','result_code','arena_id','request_id')) {
    Reject-Mutation "wrong native.$field" { param($g,$n) $n.$field = 2 }
}
foreach ($proof in @('initial_baseline','pre_bootstrap_baseline')) {
    foreach ($field in @('seed','seed_air','support_solid_up','selected_item','selected_count','selected_slot','observation_age_ns','client_eye','server_eye')) {
        Reject-Mutation "missing $proof.$field" { param($g,$n) $g.$proof.PSObject.Properties.Remove($field) }
    }
    foreach ($bad in @(-1L,500000001L,[double]::NaN,[double]::PositiveInfinity,'100')) {
        Reject-Mutation "invalid observation age $proof=$bad" { param($g,$n) $g.$proof.observation_age_ns=$bad }
    }
    Reject-Mutation "occupied seed $proof" { param($g,$n) $g.$proof.seed_air=$false }
    Reject-Mutation "missing support $proof" { param($g,$n) $g.$proof.support_solid_up=$false }
    Reject-Mutation "wrong selected item $proof" { param($g,$n) $g.$proof.selected_item='minecraft:dirt' }
    Reject-Mutation "wrong selected count $proof" { param($g,$n) $g.$proof.selected_count=63 }
    Reject-Mutation "invalid slot $proof" { param($g,$n) $g.$proof.selected_slot=9 }
    Reject-Mutation "server eye mismatch $proof" { param($g,$n) $g.$proof.server_eye.x+=0.1 }
    Reject-Mutation "client eye mismatch $proof" { param($g,$n) $g.$proof.client_eye.y+=0.1 }
}
foreach ($bad in @(-1L,500000001L,[double]::NaN,[double]::PositiveInfinity,'100')) {
    Reject-Mutation "invalid captured age=$bad" { param($g,$n) $g.request.captured_age_ns=$bad }
    Reject-Mutation "invalid queued age=$bad" { param($g,$n) $g.arena.confirmations[1].host_ray.age_at_queue_ns=$bad }
}
foreach ($field in @('session','world','reset')) {
    Reject-Mutation "request generation $field" { param($g,$n) $g.request.$field++ }
    Reject-Mutation "negative generation $field" { param($g,$n) $g.$field=-1 }
}
foreach ($badId in @(0L,9007199254740992L)) {
    Reject-Mutation "paired invalid permit ID=$badId" { param($g,$n) $g.request.wire.permitId=$badId; $g.permits[0].permitId=$badId }
    Reject-Mutation "paired invalid component ID=$badId" {
        param($g,$n)
        $g.request.component_request_id=$badId
        $g.arena.confirmations[1].id=$badId
        $g.result_evidence.local.id=$badId
    }
}
foreach ($axis in @('x','y','z')) {
    Reject-Mutation "MC alignment $axis" { param($g,$n) $g.arena.alignment.minecraft_anchor.$axis+=1 }
    Reject-Mutation "host alignment $axis" { param($g,$n) $g.arena.alignment.host_anchor.$axis+=1 }
    Reject-Mutation "ray origin $axis" { param($g,$n) $g.request.wire.origin.$axis+=1 }
    Reject-Mutation "native mapped center $axis" { param($g,$n) $n.mapped_seed_center.$axis+=1 }
    Reject-Mutation "offer bounds $axis" { param($g,$n) $g.arena_offer.maximum.$axis++ }
    Reject-Mutation "native cell $axis" { param($g,$n) $n.seed.$axis++ }
    Reject-Mutation "final air cell $axis" { param($g,$n) $g.final_client_server_air_cells[0].$axis++ }
    Reject-Mutation "actual removal cell $axis" { param($g,$n) $g.block_events[1].$axis++ }
}
foreach ($field in @('x','y','z')) {
    foreach ($bad in @([double]::NaN,[double]::PositiveInfinity,'0',10000001)) {
        Reject-Mutation "invalid ray component $field=$bad" { param($g,$n) $g.request.wire.direction.$field=$bad }
    }
}
$mutations = [ordered]@{
    'host goodbye session' = { param($g,$n) $g.host_goodbye_session=2 }
    'false authoritative proof' = { param($g,$n) $g.result_evidence.client_server_confirmed=$false }
    'wrong wire outcome' = { param($g,$n) $g.result_evidence.wire_result=7 }
    'wrong local outcome' = { param($g,$n) $g.result_evidence.local.status='rejected' }
    'local result ID' = { param($g,$n) $g.result_evidence.local.id=3 }
    'component request ID' = { param($g,$n) $g.request.component_request_id=3 }
    'false component confirmation' = { param($g,$n) $g.arena.confirmations[1].client_and_server=$false }
    'unexpected bootstrap' = { param($g,$n) $g.arena.confirmations[1].bootstrap=$true }
    'wrong confirmation operation' = { param($g,$n) $g.arena.confirmations[1].action=1 }
    'wrong confirmation target' = { param($g,$n) $g.arena.confirmations[1].target.z++ }
    'wrong permit' = { param($g,$n) $g.request.wire.permitId=2 }
    'missing permits' = { param($g,$n) $g.permits=@() }
    'duplicate permit' = { param($g,$n) $g.permits=@($g.permits[0],$g.permits[0]) }
    'wrong permit arena' = { param($g,$n) $g.permits[0].arenaId=2 }
    'wrong request arena' = { param($g,$n) $g.request.wire.arenaId=2 }
    'wrong request operation' = { param($g,$n) $g.request.wire.action=1 }
    'unknown obstruction' = { param($g,$n) $g.request.wire.occlusion=0 }
    'host obstruction' = { param($g,$n) $g.request.wire.occlusion=2 }
    'clear ray with hit distance' = { param($g,$n) $g.request.wire.nearestDistance=1.0 }
    'oversized ray' = { param($g,$n) $g.request.wire.range=4.6 }
    'zero ray' = { param($g,$n) $g.request.wire.direction=Point 0.0 0.0 0.0 }
    'wrong ray direction' = { param($g,$n) $g.request.wire.direction.x=-$g.request.wire.direction.x }
    'different confirmed ray' = { param($g,$n) $g.arena.confirmations[1].host_ray.direction.x+=0.1 }
    'different confirmed origin' = { param($g,$n) $g.arena.confirmations[1].host_ray.origin.z+=0.1 }
    'unknown confirmed obstruction' = { param($g,$n) $g.arena.confirmations[1].host_ray.host_obstruction='UNAVAILABLE' }
    'arena scale' = { param($g,$n) $g.arena.alignment.blocks_per_host_unit=2.0 }
    'offered scale' = { param($g,$n) $g.arena_offer.blocksPerUnit=2.0 }
    'missing sent event' = { param($g,$n) $g.bridge_status.sentEvents=1 }
    'dropped event' = { param($g,$n) $g.bridge_status.droppedEvents=1 }
    'pending event' = { param($g,$n) $g.bridge_status.pendingEvents=1 }
    'event wrong block' = { param($g,$n) $g.block_events[1].block_id='minecraft:dirt' }
    'event not queued' = { param($g,$n) $g.block_events[1].queued=$false }
    'event missing' = { param($g,$n) $g.block_events=@($g.block_events[0]) }
    'event duplicated' = { param($g,$n) $g.block_events=@($g.block_events[0],$g.block_events[0]) }
    'arena error' = { param($g,$n) $g.arena.failure='server unavailable' }
    'arena still pending' = { param($g,$n) $g.arena.pending=$true }
    'arena owned count' = { param($g,$n) $g.arena.owned_count=1 }
    'arena leftover cell' = { param($g,$n) $g.arena.owned_cells=@((Point 2 64 0)) }
    'arena omitted receipt' = { param($g,$n) $g.arena.omitted_receipts=1 }
    'missing action confirmation' = { param($g,$n) $g.arena.confirmations=@($g.arena.confirmations[0]) }
    'missing component request' = { param($g,$n) $g.arena.requests=@($g.arena.requests[0]) }
    'missing final server observation' = { param($g,$n) $g.final_client_server_air_cells=@() }
    'duplicate final server observation' = { param($g,$n) $g.final_client_server_air_cells=@($g.final_client_server_air_cells[0],$g.final_client_server_air_cells[0]) }
}
foreach ($name in $mutations.Keys) { Reject-Mutation $name $mutations[$name] }

# Inclusive freshness limit is valid; one nanosecond over was rejected above.
$guest=Copy-Receipt $script:validGuest
$guest.initial_baseline.observation_age_ns=500000000L
$guest.pre_bootstrap_baseline.observation_age_ns=500000000L
$guest.request.captured_age_ns=500000000L
$guest.arena.confirmations[1].host_ray.age_at_queue_ns=500000000L
Check-Receipt $guest (Copy-Receipt $script:validNative)
$script:checks++
Write-Output "AIMED_BRIDGE_RECEIPT_TESTS_PASS checks=$script:checks synthetic_receipts=true game_access=false"
