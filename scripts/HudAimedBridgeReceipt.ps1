# Original pure validation of an actual HUD-adapter run against a synthetic host.
. (Join-Path $PSScriptRoot 'HudAimedRelay.ps1')
function Assert-MineComeHudAimedBridgeReceipt {
    param($Guest,$Native,[string]$Run,[int]$ProducerPid,[string]$ProducerStart)
    function Flag($Object,[string]$Key,[bool]$Expected){if($Object.$Key -isnot [bool] -or $Object.$Key -ne $Expected){throw "HUD adapter flag mismatch: $Key"}}
    function Int($Object,[string]$Key,[long]$Expected){if(($Object.$Key -isnot [int] -and $Object.$Key -isnot [long]) -or $Object.$Key -ne $Expected){throw "HUD adapter integer mismatch: $Key"}}
    function Text($Object,[string]$Key,[string]$Expected){if($Object.$Key -isnot [string] -or $Object.$Key -cne $Expected){throw "HUD adapter text mismatch: $Key"}}
    function Number($Value,[double]$Minimum,[double]$Maximum){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or
            [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'HUD adapter finite number required.'}
        [double]$Value
    }
    function Vec($Value){@((Number $Value.x -10000000 10000000),(Number $Value.y -10000000 10000000),(Number $Value.z -10000000 10000000))}
    function Cell($Value){foreach($axis in @('x','y','z')){if(($Value.$axis -isnot [int] -and $Value.$axis -isnot [long]) -or [Math]::Abs([double]$Value.$axis) -gt 10000000){throw 'HUD adapter integer cell required.'}}}
    function Same($A,$B){Cell $A;Cell $B;foreach($axis in @('x','y','z')){if($A.$axis -ne $B.$axis){throw 'HUD adapter cell correlation differs.'}}}
    function Near([double]$A,[double]$B,[double]$Tolerance=0.000001){if([Math]::Abs($A-$B) -gt $Tolerance){throw 'HUD adapter geometry differs.'}}
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $ProducerPid -le 0 -or $ProducerStart -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'Expected HUD adapter identity invalid.'}
    Int $Guest schema 1;Text $Guest kind 'minecome_hud_aimed_bridge_fixture_v1';Text $Guest result 'passed';Text $Guest failure ''
    Text $Guest run $Run;Text $Guest save ('MineCome-HudStream-'+[guid]::ParseExact($Run,'N').ToString('D'))
    Int $Guest producer_pid $ProducerPid;Text $Guest producer_start_filetime $ProducerStart;Int $Guest protocol_minor 2
    foreach($key in @('actual_minecraft','hud_adapter','synthetic_host','synthetic_host_rays','synthetic_arming','options_restored','fixture_inventory_prepared','native_receipt_confirmed','bridge_contract_validated')){Flag $Guest $key $true}
    foreach($key in @('hud_rendered','kcd_connected','physical_input_verified','world_block_writes')){Flag $Guest $key $false}
    Int $Native schema 1;Text $Native kind 'minecome_aimed_bridge_fixture_v1';Text $Native result 'passed'
    Flag $Native kcd_connected $false;Flag $Native synthetic_host $true;Flag $Native alignment_ack $true;Flag $Native graceful_stop $true
    Int $Native placed 1;Int $Native removed 1;Int $Native result_code 1;Int $Native request_id 1
    $stone=$Guest.stone_bridge
    Assert-MineComeHudAimedBridgeProof $stone
    Text $stone save $Guest.save;Int $stone request_count 1;Int $stone confirmed_network_actions 1
    Int $stone confirmed_actions 2;Int $stone confirmed_places 1;Int $stone confirmed_breaks 1;Int $stone block_events_queued 2
    Int $stone owned_count 0;Flag $stone guest_world_cleanup_complete $true
    $offer=$stone.arena_offer;$seed=$offer.seed;$arena=$stone.arena;$request=$stone.requests[0];$wire=$request.wire
    Int $Native arena_id $offer.arenaId;Same $Native.seed $seed;Same $arena.seed $seed;Text $arena save $Guest.save
    foreach($axis in @('x','y','z')){Int $offer.minimum $axis ($seed.$axis-2);Int $offer.maximum $axis ($seed.$axis+2)}
    $m=Vec $offer.minecraftAnchor;$k=Vec $offer.kcdAnchor;$mapped=Vec $Native.mapped_seed_center
    Near (Number $offer.blocksPerUnit 1 1) 1
    Near $mapped[0] ($k[0]+$seed.x+0.5-$m[0]);Near $mapped[1] ($k[1]-$seed.z-0.5+$m[2]);Near $mapped[2] ($k[2]+$seed.y+0.5-$m[1])
    foreach($proof in @($stone.initial_baseline,$stone.pre_bootstrap_baseline)){
        Same $proof.seed $seed;Flag $proof seed_air $true;Flag $proof support_solid_up $true;Text $proof selected_item 'minecraft:stone';Int $proof selected_count 64
        $null=Number $proof.observation_age_ns 0 500000000;$client=Vec $proof.client_eye;$server=Vec $proof.server_eye
        for($i=0;$i -lt 3;$i++){Near $client[$i] $server[$i] 0.05;Near $client[$i] $m[$i] 0.05}
    }
    Int $wire requestId 1;Int $wire action 2;Int $wire occlusion 1;Int $request result 1;Int $request component_request_id 2
    $null=Number $request.captured_age_ns 0 500000000
    $origin=Vec $wire.origin;$direction=Vec $wire.direction;Near (Number $wire.range 0.000001 4.5) 4.5;Near (Number $wire.nearestDistance 0 0) 0
    Near ($direction[0]*$direction[0]+$direction[1]*$direction[1]+$direction[2]*$direction[2]) 1
    $distance=0.0;for($i=0;$i -lt 3;$i++){$distance+=($mapped[$i]-$origin[$i])*($mapped[$i]-$origin[$i]);Near $origin[$i] $k[$i] 0.05};$distance=[Math]::Sqrt($distance)
    if($distance -le 0 -or $distance -gt 4.5){throw 'Synthetic seed center out of reach.'}
    for($i=0;$i -lt 3;$i++){Near ($origin[$i]+$direction[$i]*$distance) $mapped[$i]}
    Int $arena omitted_receipts 0;Int $arena owned_count 0;Flag $arena pending $false
    foreach($field in @('block_writes','inventory_writes','camera_writes')){Int $arena $field 0}
    if($null -ne $arena.failure -or @($arena.confirmations).Count -ne 2 -or @($arena.requests).Count -ne 2 -or @($arena.owned_cells).Count -ne 0){throw 'HUD Arena did not finish its two actions cleanly.'}
    for($i=0;$i -lt 2;$i++){
        $confirmation=$stone.confirmations[$i];$component=$arena.confirmations[$i];$queued=$arena.requests[$i]
        Int $confirmation component_request_id ($i+1);Int $confirmation action ($i+1);Same $confirmation.target $seed
        foreach($local in @($component,$queued)){Int $local id ($i+1);Int $local action ($i+1);Text $local status 'confirmed';Flag $local client_and_server $true;Same $local.target $seed}
        Same $confirmation.hit_block $component.hit_block;Text $confirmation face $component.face
    }
    $ray=$arena.confirmations[1].host_ray;$rayOrigin=Vec $ray.origin;$rayDirection=Vec $ray.direction
    for($i=0;$i -lt 3;$i++){Near $rayOrigin[$i] $origin[$i];Near $rayDirection[$i] $direction[$i]}
    $null=Number $ray.age_at_queue_ns 0 500000000;Near (Number $ray.range 0.000001 4.5) $wire.range;Text $ray host_obstruction 'KNOWN_CLEAR'
    if(@($Guest.final_client_server_air_cells).Count -ne 1){throw 'Independent final client/server air proof required.'}
    Same $Guest.final_client_server_air_cells[0] $seed
}
