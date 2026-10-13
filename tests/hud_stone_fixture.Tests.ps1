#Requires -Version 7.3
# Pure production receipt validation; no controller, game or peer is started.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Start-HudInputLab.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in @('Assert-HudStoneMode','Assert-HudStoneFixture')){
    $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    if(-not $function){throw "Production function missing: $name"}
    . ([scriptblock]::Create($function.Extent.Text))
}
$script:checks=0
$run='0123456789abcdef0123456789abcdef'
function Accept($Evidence){
    Assert-HudStoneFixture $Evidence.Guest $Evidence.Native $Evidence.Peer $run
    $script:checks++
}
function Reject([scriptblock]$Action){
    $rejected=$false;try{& $Action}catch{$rejected=$true}
    if(-not $rejected){throw 'Invalid combined stone fixture proof accepted'}
    $script:checks++
}
function Fresh {
    $actions=@(1,2,1,1,1,2);$results=@(1,1,2,2,1,1);$slots=@(0,1,1,0,0,0)
    $reasons=@('permitted','permitted','selected_item_not_stone','screen_open','permitted','permitted')
    $requests=@(for($i=0;$i -lt 6;$i++){
        [pscustomobject]@{id=$i+1;action=$actions[$i];result=$results[$i];selected_slot=$slots[$i];selected_item=$(if($slots[$i] -eq 0){'minecraft:stone'}else{'minecraft:dirt'});selected_count=$(if($slots[$i] -eq 0){64}else{32});result_queued=$true;actions_enabled=$true;screen_open=($i -eq 3);gate=[pscustomobject]@{reason=$reasons[$i];transport_result=0}}
    })
    $confirmations=@(foreach($id in @(1,2,5,6)){
        $request=$requests[$id-1]
        [pscustomobject]@{id=$id;action=$request.action;selected_slot=$request.selected_slot;selected_item=$request.selected_item;selected_count=$request.selected_count;client_and_server=$true;inventory_mutated=$false;server_age_ms=50}
    })
    $items=@('stone','dirt','cobblestone','oak_planks','stick','apple','torch','diamond','iron_pickaxe');$counts=@(64,32,16,8,3,2,12,1,1)
    $clientSlots=@(for($i=0;$i -lt 9;$i++){[pscustomobject]@{slot=$i;item=('minecraft:'+$items[$i]);count=$counts[$i]}})
    $serverSlots=@(for($i=0;$i -lt 9;$i++){[pscustomobject]@{slot=$i;item=('minecraft:'+$items[$i]);count=$counts[$i]}})
    $proof=[pscustomobject]@{
        schema=1;kind='minecome_hud_stone_bridge_v1';save=('MineCome-HudStream-'+$run);baseline_confirmed=$true;closed=$true;vanilla_dispatch_inventory_unchanged=$true
        failed=$false;pending=$false;confirmed_cell_stone=$false;inventory_mutated=$false;camera_mutated=$false;engine_mirroring_verified=$false;visual_verified=$false
        cancelled_pending=0;stale_results=0;busy_results=0;omitted_requests=0;omitted_confirmations=0
        request_count=6;accepted_dispatches=4;unavailable_results=2;confirmed_actions=4;confirmed_places=2;confirmed_breaks=2;block_events_queued=4
        requests=$requests;confirmations=$confirmations;target=[pscustomobject]@{x=2;y=64;z=0}
    }
    return [pscustomobject]@{
        Guest=[pscustomobject]@{run=$run;result='input_passed';save=$proof.save;ui_input_stone_bridge=$true;ui_input_stone_fixture=$true;ui_input_stone_live=$false;lab_evidence=[pscustomobject]@{input_events_applied=8;input_consumed_sequence=8;stone_bridge=$proof;final_client_slots=$clientSlots;final_server_slots=$serverSlots}}
        Native=[pscustomobject]@{run=$run;result='passed';stone_fixture=$true;stone_fixture_verified=$true;stone_steps_completed=6;events_sent=8;all_events_acknowledged=$true}
        Peer=[pscustomobject]@{schema=1;run=$run;result='passed';peer_kind='standalone_protocol_fixture';steps=6;block_events=4;auth_verified=$true;synthetic_host_pose=$true;kcd_compositing_verified=$false;physical_input_verified=$false;guest_socket_closed=$true;received_poses=10;fixed_cell=@(2,64,0)}
    }
}
foreach($expected in @($false,$true)){
    $mode=[pscustomobject]@{ui_input_stone_bridge=$expected;ui_input_stone_fixture=$expected;ui_input_stone_live=$false}
    Assert-HudStoneMode $mode $expected;$script:checks++
    foreach($field in @('ui_input_stone_bridge','ui_input_stone_fixture')){
        foreach($invalid in @((-not $expected),[string]$expected,1,0,$null)){
            $changed=[pscustomobject]@{ui_input_stone_bridge=$expected;ui_input_stone_fixture=$expected;ui_input_stone_live=$false};$changed.$field=$invalid
            Reject {Assert-HudStoneMode $changed $expected}
        }
        $changed=[pscustomobject]@{ui_input_stone_bridge=$expected;ui_input_stone_fixture=$expected;ui_input_stone_live=$false};$changed.PSObject.Properties.Remove($field)
        Reject {Assert-HudStoneMode $changed $expected}
    }
    foreach($invalid in @($true,'false',0,1,$null)){
        $changed=[pscustomobject]@{ui_input_stone_bridge=$expected;ui_input_stone_fixture=$expected;ui_input_stone_live=$invalid}
        Reject {Assert-HudStoneMode $changed $expected}
    }
    $changed=[pscustomobject]@{ui_input_stone_bridge=$expected;ui_input_stone_fixture=$expected}
    Reject {Assert-HudStoneMode $changed $expected}
}
Accept (Fresh)
foreach($side in @('Guest','Native','Peer')){
    $e=Fresh;$e.$side.run='fedcba9876543210fedcba9876543210';Reject {Accept $e}
    $e=Fresh;$e.$side.result='failed';Reject {Accept $e}
}
$e=Fresh;$e.Guest.save='MineCome-HudStream-other';Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.kind='unknown';Reject {Accept $e}
foreach($field in @('stone_fixture','stone_fixture_verified','all_events_acknowledged')){
    foreach($invalid in @($false,'true',1)){$e=Fresh;$e.Native.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('stone_steps_completed','events_sent')){
    foreach($invalid in @('8',$true,8.0,-1)){$e=Fresh;$e.Native.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('input_events_applied','input_consumed_sequence')){
    foreach($invalid in @('8',$true,8.0,7)){$e=Fresh;$e.Guest.lab_evidence.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged')){
    foreach($invalid in @($false,'true',1)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){
    foreach($invalid in @($true,'false',0)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('cancelled_pending','stale_results','busy_results','omitted_requests','omitted_confirmations','request_count','accepted_dispatches','unavailable_results','confirmed_actions','confirmed_places','confirmed_breaks','block_events_queued')){
    foreach($invalid in @('0',$false,0.0,-1)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.$field=$invalid;Reject {Accept $e}}
}
# Exact transcript: placing with dirt or an open inventory must be unavailable;
# breaking while dirt is selected is valid and has actual server confirmation.
foreach($index in @(2,3)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$index].result=1;Reject {Accept $e}}
foreach($index in @(0,1,4,5)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$index].result=2;Reject {Accept $e}}
for($i=0;$i -lt 6;$i++){
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$i].gate.reason='stale_server';Reject {Accept $e}
    foreach($invalid in @('0',$true,$false,0.0,1,-1,$null)){
        $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$i].gate.transport_result=$invalid;Reject {Accept $e}
    }
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$i].PSObject.Properties.Remove('gate');Reject {Accept $e}
    foreach($field in @('reason','transport_result')){
        $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$i].gate.PSObject.Properties.Remove($field);Reject {Accept $e}
    }
}
foreach($index in @(2,3)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[$index].gate.reason='permitted';Reject {Accept $e}}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[2].gate.reason='screen_open';Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[3].gate.reason='selected_item_not_stone';Reject {Accept $e}
foreach($field in @('id','action','result','selected_slot','selected_count')){
    foreach($invalid in @('1',$true,1.0,-1)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[0].$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('result_queued','actions_enabled','screen_open')){
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[0].$field='true';Reject {Accept $e}
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[0].$field=(-not $e.Guest.lab_evidence.stone_bridge.requests[0].$field);Reject {Accept $e}
}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[2].selected_item='minecraft:stone';Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests[3].screen_open=$false;Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.requests=@($e.Guest.lab_evidence.stone_bridge.requests[0..4]);Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations=@($e.Guest.lab_evidence.stone_bridge.confirmations[0..2]);Reject {Accept $e}
foreach($invalid in @($false,'true',1)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].client_and_server=$invalid;Reject {Accept $e}}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].PSObject.Properties.Remove('client_and_server');Reject {Accept $e}
foreach($invalid in @(251,-1,'50',50.0,$true)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].server_age_ms=$invalid;Reject {Accept $e}}
foreach($age in @(0,250)){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].server_age_ms=$age;Accept $e}
foreach($field in @('id','action','selected_slot','selected_count')){
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].$field=999;Reject {Accept $e}
    $e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].$field='1';Reject {Accept $e}
}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[1].selected_item='minecraft:stone';Reject {Accept $e}
$e=Fresh;$e.Guest.lab_evidence.stone_bridge.confirmations[0].inventory_mutated=$true;Reject {Accept $e}
foreach($side in @('final_client_slots','final_server_slots')){
    $e=Fresh;$e.Guest.lab_evidence.$side=@($e.Guest.lab_evidence.$side[0..7]);Reject {Accept $e}
    for($i=0;$i -lt 9;$i++){
        $e=Fresh;$e.Guest.lab_evidence.$side[$i].count++;Reject {Accept $e}
        $e=Fresh;$e.Guest.lab_evidence.$side[$i].item='minecraft:air';Reject {Accept $e}
        $e=Fresh;$e.Guest.lab_evidence.$side[$i].slot=($i+1)%9;Reject {Accept $e}
    }
}
foreach($field in @('auth_verified','synthetic_host_pose','guest_socket_closed')){
    foreach($invalid in @($false,'true',1)){$e=Fresh;$e.Peer.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('kcd_compositing_verified','physical_input_verified')){
    foreach($invalid in @($true,'false',0)){$e=Fresh;$e.Peer.$field=$invalid;Reject {Accept $e}}
}
foreach($field in @('schema','steps','block_events','received_poses')){
    foreach($invalid in @('1',$true,1.0,-1,0)){$e=Fresh;$e.Peer.$field=$invalid;Reject {Accept $e}}
}
$e=Fresh;$e.Peer.peer_kind='live_host';Reject {Accept $e}
$e=Fresh;$e.Peer.fixed_cell=@(2,64);Reject {Accept $e}
for($i=0;$i -lt 3;$i++){$e=Fresh;$e.Peer.fixed_cell[$i]++;Reject {Accept $e}}
foreach($coordinate in @('x','y','z')){
    foreach($invalid in @('2',$true,2.0,([long][int]::MaxValue+1))){$e=Fresh;$e.Guest.lab_evidence.stone_bridge.target.$coordinate=$invalid;Reject {Accept $e}}
}
Write-Output "HUD_STONE_FIXTURE_RECEIPT_TEST_PASS checks=$script:checks no_game_actions=true"
