$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/AimedStoneReceipt.ps1')
$run='0123456789abcdef0123456789abcdef';$start='134048700000000000'
function V($x,$y,$z){if($x -is [string]){$x=[int]$x};if($y -is [string]){$y=[int]$y};if($z -is [string]){$z=[int]$z};return @{x=$x;y=$y;z=$z}}
function CloneReceipt($value){return ($value | ConvertTo-Json -Depth 40 | ConvertFrom-Json)}
function Ray($name){
    $origin=V 0.0 0.0 0.0;$anchor=V 0.0 0.0 0.0;$kind='KNOWN_CLEAR';$distance=0.0;$age=100L
    if($name -eq 'origin_mismatch'){$origin.x=1.0};if($name -eq 'alignment_changed'){$anchor.x=1.0}
    if($name -eq 'host_occluded'){$kind='HIT';$distance=0.25};if($name -eq 'host_occlusion_unavailable'){$kind='UNAVAILABLE'}
    if($name -eq 'stale_ray'){$age=2000000000L}
    return @{host_origin=$origin;host_direction=(V 1.0 0.0 0.0);host_range=4.5;minecraft_anchor=$anchor;host_anchor=(V 0.0 0.0 0.0);blocks_per_host_unit=1.0;occlusion_kind=$kind;host_obstruction_distance=$distance;age_at_selection_ns=$age}
}
$seed=V 0 0 0;$middle=V 0 1 0;$top=V 0 2 0;$east=V 1 2 0
$ids=@(1,2,3,4,5,6,14,15);$actions=@(1,1,1,2,2,1,2,2);$targets=@($seed,$middle,$top,$seed,$middle,$east,$east,$top)
$hits=@((V 0 -1 0),$seed,$middle,$seed,$middle,$top,$east,$top);$faces=@('UP','UP','UP','WEST','WEST','EAST','EAST','WEST')
$confirmations=@(for($i=0;$i -lt 8;$i++){
    $h=$hits[$i];$point=@(($h.x+0.5),($h.y+0.5),($h.z+0.5));if($faces[$i] -eq 'UP'){$point[1]=$h.y+1.0}elseif($faces[$i] -eq 'WEST'){$point[0]=[double]$h.x}else{$point[0]=$h.x+1.0}
    $r=@{id=$ids[$i];action=$actions[$i];status='confirmed';reason='client_and_integrated_server';client_and_server=$true;bootstrap=($i -eq 0);target=$targets[$i];hit_block=$h;face=$faces[$i];hit_point=$point;selected_slot=0;selected_item='minecraft:stone';selected_count=64}
    if($i -gt 0){$r.host_ray=@{origin=(V 0.0 0.0 0.0);direction=(V 1.0 0.0 0.0);range=4.5;age_at_queue_ns=100L;host_obstruction='KNOWN_CLEAR';host_obstruction_distance=0.0}}
    $r
})
$reasons=@('ray_miss','unowned_hit','host_obstructed','host_obstruction_unavailable','ray_stale','ray_origin_disagrees_with_eye','alignment_changed')
$requests=@($confirmations[0..5])+@(@{id=7;action=2;status='rejected';reason=$reasons[0];client_and_server=$false},@{id=7;action=2;status='rejected';reason='request_id_not_increasing';client_and_server=$false})
for($i=1;$i -lt 7;$i++){$requests+=@{id=7+$i;action=2;status='rejected';reason=$reasons[$i];client_and_server=$false}}
$requests+=@($confirmations[6],$confirmations[7])
$names=@('column_middle','column_top','remove_seed','remove_middle','face_down','face_up','face_north','face_south','face_west','face_east','place_east','nearest','miss','unowned_floor','host_occluded','host_occlusion_unavailable','stale_ray','origin_mismatch','alignment_changed','turn_while_pending','cleanup_top')
$dispatch=@{column_middle=1;column_top=2;remove_seed=3;remove_middle=4;place_east=5;turn_while_pending=6;cleanup_top=7}
$checks=@();$teleports=@();$negativeId=7
for($i=0;$i -lt $names.Count;$i++){
    $name=$names[$i];$negative=$i -ge 12 -and $i -le 18;$d=$dispatch.ContainsKey($name)
    $c=@{name=$name;passed=$true;reason='selected';selection_allowed=(-not $negative);vanilla_dispatch=$d;client_and_server_confirmed=$d;view_turned_after_queue=($name -eq 'turn_while_pending');rejected_request_checked=$negative;rejected_id_replay_checked=($name -eq 'miss');synthetic_ray=(Ray $name)}
    if($d){$proof=$confirmations[$dispatch[$name]];$c.request_id=$proof.id;$c.action=$proof.action;$c.target=$proof.target;$c.hit_block=$proof.hit_block;$c.face=$proof.face.ToLowerInvariant()}
    if($negative){$c.request_id=$negativeId;$c.action=2;$c.reason=$reasons[$negativeId-7];$negativeId++}
    if($name.StartsWith('face_')){$c.target=$top;$c.hit_block=$top;$c.face=$name.Substring(5)}
    if($name -eq 'nearest'){$c.target=$east;$c.hit_block=$east;$c.face='east'}
    $checks+=$c;$teleports+=@{scenario=$name;eye=(V 0.0 0.0 0.0);client_server_eye_agreed=$true}
}
$save='MineCome-AimedStone-'+[guid]::ParseExact($run,'N').ToString('D')
$valid=@{schema=1;kind='minecome_aimed_stone_fixture_v1';run=$run;save=$save;producer_pid=42;producer_start_filetime=$start;result='passed';failure='';synthetic_host_rays=$true;kcd_connected=$false;bootstrap_confirmed=$true;options_restored=$true;world_block_writes=$false;checks=$checks;fixture_teleports=$teleports;final_client_server_air_cells=@($seed,$middle,$top,$east);arena=@{schema=1;kind='minecome_aimed_stone_arena_v1';save=$save;failure=$null;ready=$true;bootstrapped=$true;vanilla_outline_raycast=$true;pending=$false;live_transport_enabled=$false;owned_count=0;omitted_receipts=0;block_writes=0;inventory_writes=0;camera_writes=0;max_owned_count=16;max_ray_age_ms=500;eye_tolerance=0.15;max_host_ray_range=4.5;fluid_raycast='NONE';owned_cells=@();seed=$seed;arena_minimum=(V -2 -2 -2);arena_maximum_inclusive=(V 2 2 2);alignment=@{minecraft_anchor=(V 0.0 0.0 0.0);host_anchor=(V 0.0 0.0 0.0);blocks_per_host_unit=1.0};confirmations=$confirmations;requests=$requests}}
$count=0
function Check($value){Assert-MineComeAimedStoneReceipt -Receipt $value -Run $run -ProducerPid 42 -ProducerStart $start}
Check $valid;$count++;Check (CloneReceipt $valid);$count++
$mutations=@(
    {param($r)$r.arena.PSObject.Properties.Remove('failure')},
    {param($r)$r.producer_pid='42'},
    {param($r)$r.producer_start_filetime='134048700000000001'},
    {param($r)$r.result='failed'},
    {param($r)$r.options_restored='true'},
    {param($r)$r.arena.live_transport_enabled=$true},
    {param($r)$r.final_client_server_air_cells[3]=$r.final_client_server_air_cells[2]},
    {param($r)$r.arena.confirmations[0].target.x=4},
    {param($r)$r.arena.confirmations[0].hit_block.y=0},
    {param($r)$r.arena.confirmations[5].action='1'},
    {param($r)$r.arena.confirmations[5].hit_point[0]=0.5},
    {param($r)$r.arena.confirmations[1].host_ray.age_at_queue_ns=500000001L},
    {param($r)$r.arena.requests[7].reason='ray_miss'},
    {param($r)$r.arena.requests[8].client_and_server=$true},
    {param($r)$r.checks[4].face='up'},
    {param($r)$r.checks[11].target.x=0},
    {param($r)$r.checks[12].request_id=8},
    {param($r)$r.checks[14].reason='ray_miss'},
    {param($r)$r.checks[0].synthetic_ray.host_origin.x=[double]::NaN},
    {param($r)$r.checks[0].synthetic_ray.host_direction.x='1'},
    {param($r)$r.checks[0].synthetic_ray.host_direction.x=2.0},
    {param($r)$r.checks[0].synthetic_ray.host_range=32.0},
    {param($r)$r.checks[17].synthetic_ray.host_origin.x=0.0},
    {param($r)$r.checks[18].synthetic_ray.minecraft_anchor.x=0.0},
    {param($r)$r.checks[16].synthetic_ray.age_at_selection_ns=0L},
    {param($r)$r.checks[15].synthetic_ray.occlusion_kind='KNOWN_CLEAR'},
    {param($r)$r.checks[14].synthetic_ray.host_obstruction_distance=4.5},
    {param($r)$r.checks[20].synthetic_ray.host_direction.x=-1.0},
    {param($r)$r.arena.arena_maximum_inclusive.y=3}
)
foreach($mutate in $mutations){$r=CloneReceipt $valid;& $mutate $r;$rejected=$false;try{Check $r}catch{$rejected=$true};if(-not $rejected){throw "Malformed aimed receipt accepted, case $count"};$count++}
Write-Output "AIMED_STONE_RECEIPT_TESTS_PASS checks=$count"
