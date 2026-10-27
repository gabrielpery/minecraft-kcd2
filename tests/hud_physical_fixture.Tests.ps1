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
Write-Output "HUD_PHYSICAL_FIXTURE_TESTS_PASS checks=$script:checks no_game_started=true"
