#Requires -Version 7.3
# Receipt/provenance regressions only; this script does not launch Minecraft or KCD.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$script:checks=0
function Check([bool]$value,[string]$why){$script:checks++;if(-not $value){throw $why}}
function Reject([scriptblock]$work,[string]$why){$failed=$false;try{& $work | Out-Null}catch{$failed=$true};Check $failed $why}
function Clone($value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $value -Depth 16)}
$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-HudPhysicalMovementFixture.ps1'),[ref]$null,[ref]$parseErrors)
Check ($parseErrors.Count -eq 0) 'Fixture runner syntax'
foreach($functionName in @('Assert-HudWalkingAimedFixtureProof','Assert-HudPhysicalFixtureResult')){
    $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
$childErrors=$null;$childAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Run-HudStreamClient.ps1'),[ref]$null,[ref]$childErrors)
Check ($childErrors.Count -eq 0) 'HUD child runner syntax'
$childMode=$childAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudWalkingAimedChildMode'},$true)
. ([scriptblock]::Create($childMode.Extent.Text))
Assert-HudWalkingAimedChildMode $true $true $true $true $false;Check $true 'Explicit standalone extended combined profile accepted'
foreach($missing in 0..2){
    $flags=@($true,$true,$true);$flags[$missing]=$false
    Reject {Assert-HudWalkingAimedChildMode $true $flags[0] $flags[1] $flags[2] $false} 'Combined child requires every standalone extended fixture flag'
}
Reject {Assert-HudWalkingAimedChildMode $true $true $true $true $true} 'Combined fixture cannot mix with another live or scripted profile'
foreach($yaw in @(-1,1,[double]::NaN,[double]::PositiveInfinity)){
    Reject {Assert-HudWalkingAimedChildMode $true $true $true $true $false $yaw} 'Combined fixture requires tested zero yaw'
}
Assert-HudWalkingAimedChildMode $false $false $false $false $true 90;Check $true 'Ordinary child profile constraints remain in its existing validator'
$run='a'*32;$hash='b'*64
$movement=@{run=$run;patch_sha256=$hash;ground_source_kind='standalone_ground_fixture';input_source='scripted_hud_physical_controller_fixture';scripted_input=$true;physical_input_verified=$false;trace_result='passed';post_settle_corrections=0;client_walk=.6;server_walk=.6;held_ticks=9;started=$true;completed=$true;trace_closed=$true;client_proxy_released=$true;server_proxy_released=$true;controls_released=$true}
$proof=@{kind='standalone_hud_physical_controller_fixture_v1';scripted_input=$true;physical_input_verified=$false;kcd_compositing_verified=$false;completed=$true;camera_worker_stopped=$true;inventory_client_max_displacement=0;inventory_server_max_displacement=0;inventory_frames=8;walking_hud_frames=40;synthetic_camera_samples=160;physical_movement=$movement;pulses=@(@{key='W';step_m=.3;client_server_distance=.001},@{key='W';step_m=.3;client_server_distance=.001},@{key='S';step_m=.3;client_server_distance=.001})}
$receipt=Clone @{schema=1;run=$run;result='passed';source_kind='minecraft_vanilla_ui_stream_v1';ui_physical_controller_fixture=$true;ui_input_physical_movement=$false;scripted_input=$true;physical_input_verified=$false;standalone=$true;kcd_compositing_verified=$false;published_frames=120;closed_published=$true;mapping_unmapped=$true;mapping_handle_closed=$true;mutex_handle_closed=$true;lab_evidence=@{physical_controller_fixture=$proof}}
foreach($pulse in $receipt.lab_evidence.physical_controller_fixture.pulses){$pulse | Add-Member -NotePropertyName server_step_m -NotePropertyValue .3}
$receipt.lab_evidence | Add-Member -NotePropertyName input_tick_phase -NotePropertyValue 'start_before_vanilla'
$timing=Clone @{kind='minecome_hud_movement_timing_v1';truncated=$false;native_application_measured=$false;display_latency_measured=$false;
    event_count=3;binding_state_count=3;events=@();binding_states=@()}
for($index=0;$index -lt 3;$index++){
    $stamp=1000000000L+$index*1000000000L;$key=if($index -eq 2){0x53}else{0x57};$mask=if($key -eq 0x53){2}else{1}
    $timing.events+=Clone @{input_sequence=$index*2+1;key=$key;accepted_down=$true;received_monotonic_ns=$stamp}
    $timing.binding_states+=Clone @{stage='before_vanilla_poll';after_input_sequence=$index*2+1;mask=$mask;monotonic_ns=$stamp+1000000}
}
$receipt.lab_evidence.physical_controller_fixture.physical_movement | Add-Member -NotePropertyName input_timing -NotePropertyValue $timing
$null=Assert-HudPhysicalFixtureResult $receipt $run $hash;Check $true 'Explicit scripted actual-controller fixture proof accepted'
foreach($field in @('ui_physical_controller_fixture','scripted_input','standalone','closed_published','mapping_unmapped','mapping_handle_closed','mutex_handle_closed')){
    $bad=Clone $receipt;$bad.$field=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} "Missing fixture/cleanup marker $field"
}
foreach($field in @('ui_input_physical_movement','physical_input_verified','kcd_compositing_verified')){
    $bad=Clone $receipt;$bad.$field=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} "Fixture cannot claim live authority $field"
}
foreach($value in @('true',1,$null)){
    $bad=Clone $receipt;$bad.scripted_input=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Scripted flag must be an actual boolean'
}
foreach($field in @('completed','camera_worker_stopped')){
    $bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.$field=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} "Fixture incomplete $field"
}
foreach($field in @('inventory_client_max_displacement','inventory_server_max_displacement')){
    foreach($value in @(.02,[double]::NaN,-.1,'0')){
        $bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.$field=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} "Invalid inventory displacement $field"
    }
}
foreach($value in @(0,.049,[double]::NaN,'0.5')){
    $bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.pulses[1].step_m=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Second press must cause finite useful movement'
}
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.pulses[2].key='W';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Required opposite direction pulse absent'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.pulses[2].client_server_distance=.11;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Server did not agree with scripted client'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.pulses[1].server_step_m=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Second W must independently move server'
foreach($field in @('started','completed','trace_closed','client_proxy_released','server_proxy_released','controls_released')){
    $bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.$field=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} "Actual controller proof missing $field"
}
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.input_source='hud_input_v2';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Live input provenance cannot enter scripted proof'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.ground_source_kind='live_kcd_ground_patch';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Fixture must re-label copied numeric terrain'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.post_settle_corrections=1;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Actual server correction invalidates fixture'
Reject {Assert-HudPhysicalFixtureResult $receipt ('c'*32) $hash} 'Fixture run identity mismatch'
Reject {Assert-HudPhysicalFixtureResult $receipt $run ('c'*64)} 'Fixture patch hash mismatch'
$bad=Clone $receipt;$bad.lab_evidence.input_tick_phase='end_after_vanilla';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Fixture must run input before vanilla'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.input_timing.truncated=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Fixture must retain accepted inputs'
$bad=Clone $receipt;$bad.lab_evidence.physical_controller_fixture.physical_movement.input_timing.binding_states[0].mask=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash} 'Accepted scripted press must reach real binding state'

# The longer fixture must prove fresh presses after the old five-second cutoff,
# reopening inventory without motion, and the selected complete time budget.
$extended=Clone $receipt;$extendedProof=$extended.lab_evidence.physical_controller_fixture;$extendedMovement=$extendedProof.physical_movement
foreach($marker in @($extended,$extendedProof,$extendedMovement)){$marker | Add-Member -NotePropertyName movement_session -NotePropertyValue 'extended'}
$extendedMovement | Add-Member -NotePropertyName duration_ms -NotePropertyValue 15500
foreach($field in @('post_walk_inventory_opened','post_walk_inventory_closed')){$extendedProof | Add-Member -NotePropertyName $field -NotePropertyValue $true}
foreach($field in @('post_walk_inventory_client_max_displacement','post_walk_inventory_server_max_displacement')){$extendedProof | Add-Member -NotePropertyName $field -NotePropertyValue 0.0}
$extendedProof | Add-Member -NotePropertyName post_walk_inventory_frames -NotePropertyValue 8
for($index=0;$index -lt 3;$index++){$extendedProof.pulses[$index] | Add-Member -NotePropertyName elapsed_from_first_movement_ms -NotePropertyValue (650+$index*1000)}
for($index=3;$index -lt 5;$index++){
    $elapsed=7000+($index-3)*1000;$stamp=1000000000L+$elapsed*1000000L;$key=if($index -eq 3){0x57}else{0x53};$mask=if($key -eq 0x57){1}else{2}
    $extendedProof.pulses+=Clone @{key=$(if($key -eq 0x57){'W'}else{'S'});step_m=.3;server_step_m=.3;client_server_distance=.001;elapsed_from_first_movement_ms=$elapsed+650}
    $extendedMovement.input_timing.events+=Clone @{input_sequence=$index*2+1;key=$key;accepted_down=$true;received_monotonic_ns=$stamp}
    $extendedMovement.input_timing.binding_states+=Clone @{stage='before_vanilla_poll';after_input_sequence=$index*2+1;mask=$mask;monotonic_ns=$stamp+1000000}
}
$extendedMovement.input_timing.event_count=5;$extendedMovement.input_timing.binding_state_count=5
$null=Assert-HudPhysicalFixtureResult $extended $run $hash -ExtendedWalking;Check $true 'Longer fixture preserves actual late presses and stationary reopened inventory'
Reject {Assert-HudPhysicalFixtureResult $extended $run $hash} 'Extended receipt cannot be accepted as short'
Reject {Assert-HudPhysicalFixtureResult $receipt $run $hash -ExtendedWalking} 'Short receipt cannot be accepted as extended'
foreach($where in @('stream','fixture','movement')){
    foreach($value in @('short','Extended',$true,$null)){
        $bad=Clone $extended;$marker=switch($where){stream{$bad}fixture{$bad.lab_evidence.physical_controller_fixture}movement{$bad.lab_evidence.physical_controller_fixture.physical_movement}}
        $marker.movement_session=$value
        Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} "Extended identity marker required at $where"
    }
}
foreach($field in @('post_walk_inventory_opened','post_walk_inventory_closed')){
    foreach($value in @($false,'true',1)){$bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.$field=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} "Real inventory transition required: $field"}
}
foreach($field in @('post_walk_inventory_client_max_displacement','post_walk_inventory_server_max_displacement')){
    foreach($value in @(.02,-.1,[double]::NaN,'0')){$bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.$field=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} "Stationary reopened inventory required: $field"}
}
foreach($value in @(0,1,'2',$true)){
    $bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.post_walk_inventory_frames=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Actual reopened inventory frames required'
}
foreach($value in @(5999,14999,16001,'15500',15500.1,$true)){
    $bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.physical_movement.duration_ms=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Extended duration must complete within exact selected bounds'
}
foreach($value in @(5000,16001,[double]::NaN,'7000',2650)){
    $bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.pulses[3].elapsed_from_first_movement_ms=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Late pulse proof must be ordered and beyond short duration'
}
foreach($offset in @(5000000000L,15000000000L,-1L)){
    $bad=Clone $extended;$badTiming=$bad.lab_evidence.physical_controller_fixture.physical_movement.input_timing
    $badTiming.events[3].received_monotonic_ns=$badTiming.events[0].received_monotonic_ns+$offset
    Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Accepted late key must be inside extended input window'
}
$bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.pulses[3].server_step_m=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Late key must move actual server'
$bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.physical_movement.input_timing.events[3].accepted_down=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Late key cannot merely be consumed'
$bad=Clone $extended;$bad.lab_evidence.physical_controller_fixture.physical_movement.input_timing.events[4].key=0x57;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking} 'Accepted key direction must match actual pulse proof'
$null=Assert-HudPhysicalFixtureResult (Clone $extended) $run $hash -ExtendedWalking;Check $true 'Repeated verification of valid copied evidence remains valid'

$combined=Clone $extended;$combinedProof=$combined.lab_evidence.physical_controller_fixture
$combined | Add-Member -NotePropertyName ui_walking_aimed_fixture -NotePropertyValue $true
$combined | Add-Member -NotePropertyName save -NotePropertyValue 'MineCome-HudStream-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$combinedProof | Add-Member -NotePropertyName ui_walking_aimed_fixture -NotePropertyValue $true
$combinedProof | Add-Member -NotePropertyName aimed_hud_frames -NotePropertyValue 3
$combinedProof.physical_movement | Add-Member -NotePropertyName patch_run -NotePropertyValue ('c'*32)
$seed=@{x=2;y=64;z=0};$support=@{x=2;y=63;z=0};$top=@{x=2;y=65;z=0};$west=@{x=1;y=64;z=0}
$aimed=Clone @{kind='standalone_hud_walking_aimed_fixture_v1';scripted_input=$true;synthetic_host_rays=$true;physical_input_verified=$false;kcd_connected=$false;
    completed=$true;alignment_before_movement=$true;bootstrap_before_movement=$true;movement_before_interactions=$true;movement_resumed_after_interactions=$true;
    patch_run=('c'*32);patch_sha256=$hash;support=$support;seed=$seed;support_fixture_setup_writes=1;support_fixture_cleanup_writes=1;arena_direct_block_writes=0;
    support_client_server_prepared=$true;support_client_server_restored_air=$true;imported_cells_unchanged=$true;final_client_server_air=$true;walk_before_m=.3;walk_after_m=.3;confirmations=@();
    arena=@{schema=1;kind='minecome_aimed_stone_arena_v1';save=$combined.save;seed=$seed;block_writes=0;inventory_writes=0;camera_writes=0;owned_count=0;omitted_receipts=0;owned_cells=@();pending=$false;failure=$null;requests=@();confirmations=@();max_owned_count=16;arena_minimum=@{x=0;y=62;z=-2};arena_maximum_inclusive=@{x=4;y=66;z=2};vanilla_outline_raycast=$true;fluid_raycast='NONE';live_transport_enabled=$false;build_region=@{patch_run=('c'*32);patch_sha256=$hash;support=$support;support_editable=$false;protected_imported_cells=16}}}
$labels=@('bootstrap','top_place','upper_break','west_place','west_break','seed_break');$actions=@(1,1,2,1,2,2);$targets=@($seed,$top,$top,$west,$west,$seed);$hits=@($support,$seed,$top,$seed,$west,$seed)
for($index=0;$index -lt 6;$index++){
    $face=if($index -eq 3){'WEST'}else{'UP'};$elapsed=if($index -eq 0){-2000}else{2700+$index*300}
    $aimed.confirmations+=Clone @{label=$labels[$index];id=$index+1;action=$actions[$index];target=$targets[$index];hit_block=$hits[$index];face=$face;client_and_server=$true;confirmed=$true;elapsed_from_first_movement_ms=$elapsed;client_server_distance=0.0;speed_metric='horizontal_xz';client_speed=0.0;server_speed=0.0;client_vertical_velocity=-.0784;server_vertical_velocity=-.0784;client_on_ground=$true;server_on_ground=$true}
    $row=Clone @{id=$index+1;action=$actions[$index];target=$targets[$index];hit_block=$hits[$index];face=$face;client_and_server=$true;status='confirmed'}
    $aimed.arena.confirmations+=$row;$aimed.arena.requests+=Clone $row
}
$combinedProof | Add-Member -NotePropertyName aimed_blocks -NotePropertyValue $aimed
$null=Assert-HudPhysicalFixtureResult $combined $run $hash -ExtendedWalking -AimedBlocks;Check $true 'Combined fixture proves walked, placed/broke exact faces, and resumed walking'
Reject {Assert-HudPhysicalFixtureResult $combined $run $hash -ExtendedWalking} 'Ordinary extended fixture cannot accept combined proof'
Reject {Assert-HudPhysicalFixtureResult $extended $run $hash -ExtendedWalking -AimedBlocks} 'Combined mode cannot accept ordinary extended proof'
Reject {Assert-HudPhysicalFixtureResult $combined $run $hash -AimedBlocks} 'Combined mode requires explicit extended selection'
foreach($where in @('stream','fixture')){
    foreach($value in @($false,'true',1,$null)){
        $bad=Clone $combined;$marker=if($where -ceq 'stream'){$bad}else{$bad.lab_evidence.physical_controller_fixture};$marker.ui_walking_aimed_fixture=$value
        Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Exact combined fixture markers required'
    }
}
foreach($name in @('scripted_input','synthetic_host_rays','completed','alignment_before_movement','bootstrap_before_movement','movement_before_interactions','movement_resumed_after_interactions','support_client_server_prepared','support_client_server_restored_air','imported_cells_unchanged','final_client_server_air')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.$name=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} "Combined proof missing required $name"
}
foreach($name in @('physical_input_verified','kcd_connected')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.$name=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Combined fixture cannot claim native or physical proof'
}
foreach($name in @('support_fixture_setup_writes','support_fixture_cleanup_writes')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.$name=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Fixture support setup and cleanup writes must be accounted separately'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena_direct_block_writes=1;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Direct world writes cannot masquerade as vanilla actions'
foreach($name in @('walk_before_m','walk_after_m')){
    foreach($value in @(0,'0.3',[double]::NaN)){$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.$name=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Combined actions require actual walking before and after'}
}
foreach($name in @('patch_run','patch_sha256')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.$name='wrong';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Combined arena must bind exact terrain session'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.support.x++;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Fixture support must be directly below seed'
foreach($name in @('block_writes','inventory_writes','camera_writes','owned_count','omitted_receipts')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.$name=1;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Aimed arena must preserve direct-write and complete receipt contract'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.pending=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Pending aimed action cannot pass fixture'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.failure='failed';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Failed aimed arena cannot pass fixture'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.owned_cells=@($seed);Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Owned block remains after fixture'
foreach($name in @('confirmations','requests')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.$name=@($bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.$name | Select-Object -First 5);Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Every action needs request and client/server confirmation'
}
foreach($name in @('id','action')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[3].$name=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Combined action identity/order must match exact sequence'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[3].face='EAST';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'West placement requires actual west face'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].target.y=64;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Top placement target must be above seed'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[4].hit_block.x=2;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Break hit must match the exact owned target'
foreach($name in @('client_and_server','confirmed')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[5].$name=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Actions require authoritative and client confirmation'
}
foreach($name in @('client_speed','server_speed')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].$name=.03;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Action attempted before player settled'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].client_server_distance=.011;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Settled action requires agreeing client/server position'
foreach($name in @('client_vertical_velocity','server_vertical_velocity')){
    foreach($value in @(-.1,.1,[double]::NaN,'0')){$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].$name=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Airborne action cannot claim a settled barrier'}
}
foreach($name in @('client_on_ground','server_on_ground')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].$name=$false;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Both client and server must be grounded for action'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].speed_metric='total_speed';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Horizontal velocity metric must be explicit'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_hud_frames=1;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Aimed interactions need actual HUD frame evidence'
foreach($time in @(-1,15000,2650)){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[1].elapsed_from_first_movement_ms=$time;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Interactions must follow walking and remain inside the input window'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[0].elapsed_from_first_movement_ms=0;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Bootstrap must precede initial movement'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.confirmations[-1].elapsed_from_first_movement_ms=7000;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Subsequent accepted walking key must follow final block confirmation'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.confirmations[2].target.x=9;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Helper summary must correlate with actual arena receipt'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.max_owned_count=17;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Combined arena cannot expand sixteen-cell ownership budget'
foreach($name in @('patch_run','patch_sha256')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.build_region.$name='wrong';Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Actual arena build policy must bind exact imported patch'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.build_region.support.x++;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Actual arena build support must match fixture support'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.build_region.support_editable=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Fixture support must not become an editable gameplay block'
foreach($value in @(0,15,33,16.5,'16')){
    $bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.build_region.protected_imported_cells=$value;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Protected imported cells must retain full bounded terrain coverage'
}
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.arena_maximum_inclusive.x++;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Actual arena cannot expand its bounded cube'
$bad=Clone $combined;$bad.lab_evidence.physical_controller_fixture.aimed_blocks.arena.live_transport_enabled=$true;Reject {Assert-HudPhysicalFixtureResult $bad $run $hash -ExtendedWalking -AimedBlocks} 'Standalone proof cannot activate live transport'
$null=Assert-HudPhysicalFixtureResult (Clone $combined) $run $hash -ExtendedWalking -AimedBlocks;Check $true 'Valid combined proof remains idempotently verifiable'
Write-Output "HUD_PHYSICAL_FIXTURE_TESTS_PASS checks=$script:checks no_game_started=true"
