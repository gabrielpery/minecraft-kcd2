# Correlates actual Minecraft and synthetic native-host receipts. No processes are started here.
function Assert-MineComeAimedBridgeReceipt {
    param([object]$Guest,[object]$Native,[string]$Run,[int]$ProducerPid,[string]$ProducerStart)
    function Need($Value,[string[]]$Names){
        if($Value -is [Collections.IDictionary]){$keys=@($Value.Keys)}
        elseif($null -ne $Value -and $Value -is [pscustomobject]){$keys=@($Value.PSObject.Properties.Name)}
        else{throw 'Expected aimed network receipt object.'}
        foreach($name in $Names){if($keys -notcontains $name){throw "Missing aimed network field: $name"}}
    }
    function Text($Value,[string]$Name,[string]$Expected){Need $Value @($Name);if($Value.$Name -isnot [string] -or $Value.$Name -cne $Expected){throw "Aimed network text differs: $Name"}}
    function Bool($Value,[string]$Name,[bool]$Expected){Need $Value @($Name);if($Value.$Name -isnot [bool] -or $Value.$Name -ne $Expected){throw "Aimed network Boolean differs: $Name"}}
    function Int($Value,[string]$Name,[long]$Expected){Need $Value @($Name);$n=$Value.$Name;if(($n -isnot [int] -and $n -isnot [long]) -or $n -ne $Expected){throw "Aimed network integer differs: $Name"}}
    function Number($Value,[double]$Min,[double]$Max){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or
           [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or $Value -lt $Min -or $Value -gt $Max){throw 'Aimed network finite number required.'}
        return [double]$Value
    }
    function Vector($Value){Need $Value @('x','y','z');return @((Number $Value.x -10000000 10000000),(Number $Value.y -10000000 10000000),(Number $Value.z -10000000 10000000))}
    function Cell($Value){Need $Value @('x','y','z');foreach($axis in @('x','y','z')){$n=$Value.$axis;if(($n -isnot [int] -and $n -isnot [long]) -or $n -lt -10000000 -or $n -gt 10000000){throw 'Aimed network cell must be bounded integer.'}}}
    function SameCell($A,$B){Cell $A;Cell $B;foreach($axis in @('x','y','z')){if($A.$axis -ne $B.$axis){throw 'Aimed network cell correlation differs.'}}}
    function Near([double]$A,[double]$B,[double]$Tolerance=0.000001){if([Math]::Abs($A-$B) -gt $Tolerance){throw 'Aimed network coordinate correlation differs.'}}
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $ProducerPid -le 0 -or $ProducerStart -cnotmatch '^[1-9][0-9]{0,19}$'){throw 'Invalid expected network fixture identity.'}
    foreach($receipt in @($Guest,$Native)){Int $receipt schema 1;Text $receipt kind 'minecome_aimed_bridge_fixture_v1';Text $receipt result 'passed';Bool $receipt kcd_connected $false;Bool $receipt synthetic_host $true}
    Text $Guest run $Run;Text $Guest save ('MineCome-AimedStone-'+[guid]::ParseExact($Run,'N').ToString('D'))
    Int $Guest producer_pid $ProducerPid;Text $Guest producer_start_filetime $ProducerStart;Text $Guest failure '';Int $Guest protocol_minor 2
    foreach($field in @('synthetic_host_rays','network_fixture','options_restored','arena_acknowledged','bootstrap_confirmed')){Bool $Guest $field $true}
    Bool $Guest world_block_writes $false;Bool $Native alignment_ack $true;Bool $Native graceful_stop $true
    Int $Native placed 1;Int $Native removed 1;Int $Native result_code 1
    Need $Guest @('initial_baseline','pre_bootstrap_baseline','arena_offer','session','world','reset','request','result_evidence','bridge_status','block_events','host_goodbye_session','final_client_server_air_cells','arena','permits')
    foreach($field in @('session','world','reset')){$null=Number $Guest.$field 0 9007199254740991;Int $Guest $field ([long]$Guest.$field)}
    if($Guest.session -lt 1){throw 'Authenticated session required.'};Int $Guest host_goodbye_session $Guest.session
    $offer=$Guest.arena_offer;$baseline=$Guest.initial_baseline;$arena=$Guest.arena;$request=$Guest.request;$wire=$request.wire
    Need $offer @('arenaId','minecraftAnchor','kcdAnchor','blocksPerUnit','seed','minimum','maximum')
    $null=Number $offer.arenaId 1 9007199254740991;Int $offer arenaId ([long]$offer.arenaId);Int $Native arena_id $offer.arenaId
    $m=Vector $offer.minecraftAnchor;$k=Vector $offer.kcdAnchor;Near (Number $offer.blocksPerUnit 1 1) 1
    Cell $offer.seed;Cell $offer.minimum;Cell $offer.maximum
    foreach($axis in @('x','y','z')){Int $offer.minimum $axis ($offer.seed.$axis-2);Int $offer.maximum $axis ($offer.seed.$axis+2)}
    SameCell $baseline.seed $offer.seed;SameCell $Native.seed $offer.seed;SameCell $arena.seed $offer.seed
    foreach($proof in @($baseline,$Guest.pre_bootstrap_baseline)){
        SameCell $proof.seed $offer.seed;Bool $proof seed_air $true;Bool $proof support_solid_up $true
        Text $proof selected_item 'minecraft:stone';Int $proof selected_count 64
        $null=Number $proof.selected_slot 0 8;Int $proof selected_slot ([long]$proof.selected_slot)
        $null=Number $proof.observation_age_ns 0 500000000
        $clientEye=Vector $proof.client_eye;$serverEye=Vector $proof.server_eye
        for($i=0;$i -lt 3;$i++){Near $clientEye[$i] $serverEye[$i] 0.05;Near $clientEye[$i] $m[$i] 0.05}
    }
    $arenaM=Vector $arena.alignment.minecraft_anchor;$arenaK=Vector $arena.alignment.host_anchor
    Near (Number $arena.alignment.blocks_per_host_unit 1 1) 1
    for($i=0;$i -lt 3;$i++){Near $arenaM[$i] $m[$i];Near $arenaK[$i] $k[$i]}
    $mapped=Vector $Native.mapped_seed_center
    Near $mapped[0] ($k[0]+$offer.seed.x+0.5-$m[0]);Near $mapped[1] ($k[1]-($offer.seed.z+0.5-$m[2]));Near $mapped[2] ($k[2]+$offer.seed.y+0.5-$m[1])
    foreach($field in @('session','world','reset')){Int $request $field $Guest.$field}
    $null=Number $request.captured_age_ns 0 500000000
    Int $wire arenaId $offer.arenaId;Int $wire action 2
    $null=Number $wire.requestId 1 9007199254740991;Int $wire requestId ([long]$wire.requestId);Int $Native request_id $wire.requestId
    $null=Number $wire.permitId 1 9007199254740991;Int $wire permitId ([long]$wire.permitId)
    Int $wire occlusion 1;Near (Number $wire.nearestDistance 0 0) 0;Near (Number $wire.range 0.000001 4.5) 4.5
    $origin=Vector $wire.origin;$direction=Vector $wire.direction
    for($i=0;$i -lt 3;$i++){Near $origin[$i] $k[$i] 0.05}
    Near ($direction[0]*$direction[0]+$direction[1]*$direction[1]+$direction[2]*$direction[2]) 1
    $distance=0.0;for($i=0;$i -lt 3;$i++){$distance+=($mapped[$i]-$origin[$i])*($mapped[$i]-$origin[$i])};$distance=[Math]::Sqrt($distance)
    if($distance -le 0 -or $distance -gt 4.5){throw 'Fixture aimed center is outside its ray.'}
    for($i=0;$i -lt 3;$i++){Near ($origin[$i]+$direction[$i]*$distance) $mapped[$i]}
    $permits=@($Guest.permits | Where-Object { $_.arenaId -eq $wire.arenaId -and $_.permitId -eq $wire.permitId })
    if($permits.Count -ne 1){throw 'Request lacks its unique issued guest permit.'}
    Int $permits[0] permitId $wire.permitId;Int $permits[0] arenaId $wire.arenaId
    Int $Guest.result_evidence wire_result 1;Bool $Guest.result_evidence client_server_confirmed $true
    Int $Guest.bridge_status sentEvents 2;Int $Guest.bridge_status droppedEvents 0;Int $Guest.bridge_status pendingEvents 0
    if(@($Guest.block_events).Count -ne 2){throw 'Expected actual placement and removal events.'}
    for($i=0;$i -lt 2;$i++){$event=$Guest.block_events[$i];Int $event operation ($i+1);Text $event block_id 'minecraft:stone';Bool $event queued $true;SameCell $event $offer.seed}
    Need $arena @('failure','requests','confirmations','owned_cells')
    if($null -ne $arena.failure){throw 'Minecraft arena failed.'}
    Bool $arena pending $false;Int $arena owned_count 0;Int $arena omitted_receipts 0
    if(@($arena.owned_cells).Count -ne 0 -or @($arena.confirmations).Count -ne 2 -or @($arena.requests).Count -ne 2){throw 'Arena proof count/cleanup differs.'}
    for($i=0;$i -lt 2;$i++){
        $proof=$arena.confirmations[$i];Int $proof action ($i+1);Text $proof status 'confirmed';Bool $proof client_and_server $true;Bool $proof bootstrap ($i -eq 0);SameCell $proof.target $offer.seed
        Int $proof id ($i+1)
        $queued=$arena.requests[$i];Int $queued id $proof.id;Int $queued action $proof.action;Text $queued status 'confirmed';Bool $queued client_and_server $true;SameCell $queued.target $proof.target
    }
    Int $request component_request_id $arena.confirmations[1].id
    $local=$Guest.result_evidence.local
    Int $local id $request.component_request_id;Int $local action 2;Text $local status 'confirmed';Bool $local client_and_server $true;SameCell $local.target $offer.seed
    $ray=$arena.confirmations[1].host_ray
    $rayOrigin=Vector $ray.origin;$rayDirection=Vector $ray.direction
    for($i=0;$i -lt 3;$i++){Near $rayOrigin[$i] $origin[$i];Near $rayDirection[$i] $direction[$i]}
    Near (Number $ray.range 0.000001 4.5) $wire.range;Text $ray host_obstruction 'KNOWN_CLEAR'
    $null=Number $ray.age_at_queue_ns 0 500000000
    if(@($Guest.final_client_server_air_cells).Count -ne 1){throw 'Final actual client/server air observation required.'}
    SameCell $Guest.final_client_server_air_cells[0] $offer.seed
}
