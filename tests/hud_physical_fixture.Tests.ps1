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
$function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudPhysicalFixtureResult'},$true)
. ([scriptblock]::Create($function.Extent.Text))
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
Write-Output "HUD_PHYSICAL_FIXTURE_TESTS_PASS checks=$script:checks no_game_started=true"
