$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/HudGroundExtensionProof.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Call,[string]$Message){$failed=$false;try{& $Call | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20}
$run='a'*32
$inputRecord=[pscustomobject]@{Run=$run;Hash=('b'*64);InitialHash=('c'*64);Captured=$false;TileHashes=@(('d'*64),('e'*64),('f'*64));Anchor=@{x=120;y=2040;z=56}}
$save='MineCome-HudStream-11111111-1111-4111-8111-111111111111'
$proof=[ordered]@{schema=1;kind='minecome_hud_ground_extension_fixture_v1';save=$save;patch_run=$run;patch_sha256=$inputRecord.Hash;ground_source_kind='standalone_ground_extension_fixture';phase='PASSED';client_walk=9.2;server_walk=9.2;client_proxy_queries=100;server_proxy_queries=100;post_settle_corrections=0;frame_captures=@{WALKING=10;JUMPING=0;LANDING=0}}
foreach($field in @('synthetic_input','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){$proof[$field]=$true}
foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified','client_air','server_air','client_land','server_land')){$proof[$field]=$false}
$proof.extension=[ordered]@{handoff_delay_fixture=$false;minimum_handoff_wait_ms=0;handoff_wait_ms=100;handoff_trace_samples=0;plan_sha256=$inputRecord.Hash;initial_sha256=$inputRecord.InitialHash;expanded_sha256=$inputRecord.Hash;tile_sha256=$inputRecord.TileHashes;anchor=$inputRecord.Anchor;initial_max_x=8;expanded_max_x=12;trigger_x=4.5;client_installed=$true;server_installed=$true;client_vanilla_cells_air=$true;server_vanilla_cells_air=$true;client_max_x=9.7;server_max_x=9.7;client_return_distance=.1;server_return_distance=.1;max_client_server_distance=.1;transition_hud_frames=1;crossing_hud_frames=2;return_hud_frames=3;slab_count=128;collision_cell_count=160}
$guest=Clone ([ordered]@{run=$run;result='passed';save=$save;source_kind='minecraft_vanilla_ui_stream_v1';ui_ground_extension_fixture=$true;standalone=$true;lab_evidence=@{ground_movement=$proof}})
$null=Assert-HudGroundExtensionProof $guest $run $inputRecord
Check $true 'Complete handoff/crossing/return/HUD/cleanup proof accepted'
$null=Assert-HudGroundExtensionMode $true $true $false ''
Check $true 'Separate standalone mode accepted'
Reject {Assert-HudGroundExtensionMode $true $false $false ''} 'Live target mode rejected'
Reject {Assert-HudGroundExtensionMode $true $true $true ''} 'Another movement mode rejected'
Reject {Assert-HudGroundExtensionMode $false $true $false 'manifest'} 'Implicit extension file rejected'
Reject {Assert-HudGroundExtensionMarker $guest $false} 'Unrequested marker rejected'
foreach($change in @('client_install','server_install','initial_hash','plan_hash','expanded_hash','tile_hash','anchor','trigger','crossing','return','handoff_hud','crossing_hud','return_hud','terrain_modified','cleanup','jump','correction','nan','source','foreign_run','live_marker','legacy_marker','slabs')){
    $bad=Clone $guest;$p=$bad.lab_evidence.ground_movement;$e=$p.extension
    switch($change){
        client_install{$e.client_installed=$false}
        server_install{$e.server_installed=$false}
        initial_hash{$e.initial_sha256='0'*64}
        plan_hash{$e.plan_sha256='0'*64}
        expanded_hash{$e.expanded_sha256='0'*64}
        tile_hash{$e.tile_sha256[2]='0'*64}
        anchor{$e.anchor.x=124}
        trigger{$e.trigger_x=8}
        crossing{$e.server_max_x=8}
        return{$e.client_return_distance=1}
        handoff_hud{$e.transition_hud_frames=0}
        crossing_hud{$e.crossing_hud_frames=0}
        return_hud{$e.return_hud_frames=0}
        terrain_modified{$e.server_vanilla_cells_air=$false}
        cleanup{$p.server_proxy_released=$false}
        jump{$p.client_air=$true}
        correction{$p.post_settle_corrections=1}
        nan{$e.max_client_server_distance=[double]::NaN}
        source{$p.ground_source_kind='live_kcd_ground_extension'}
        foreign_run{$bad.run='c'*32}
        live_marker{$bad.standalone=$false}
        legacy_marker{$bad | Add-Member ui_ground_corridor_coupled $true}
        slabs{$e.slab_count=96}
    }
    Reject {Assert-HudGroundExtensionProof $bad $run $inputRecord} "Reject $change proof"
}
$captured=Clone $inputRecord;$captured.Captured=$true
$capturedGuest=Clone $guest;$capturedGuest.lab_evidence.ground_movement.ground_source_kind='live_kcd_ground_extension'
$null=Assert-HudGroundExtensionProof $capturedGuest $run $captured
Check $true 'Authenticated captured geometry may use the separate scripted profile'
$coupled=Clone $capturedGuest;$coupled.PSObject.Properties.Remove('ui_ground_extension_fixture')
$coupled | Add-Member ui_ground_extension_coupled $true;$coupled | Add-Member walking_area 'extension'
$p=$coupled.lab_evidence.ground_movement;$p.kind='minecome_hud_ground_extension_coupled_v1'
$p | Add-Member trace_file 'trace.ndjson';$p | Add-Member trace_result 'passed';$p | Add-Member trace_closed $true;$p | Add-Member trace_records 200;$p | Add-Member hud_run $run
$null=Assert-HudGroundExtensionProof $coupled $run $captured -Coupled -TraceFile 'trace.ndjson'
Check $true 'Explicit coupled mode has same-frame extension and trace proof'
Reject {Assert-HudGroundExtensionMode $true $true $false 'manifest' $true 'trace'} 'Conflicting extension modes rejected'
Reject {Assert-HudGroundExtensionMode $false $true $false 'manifest' $true ''} 'Coupled extension needs trace'
Reject {Assert-HudGroundExtensionMode $false $true $false '' $true 'trace'} 'Coupled extension needs capture'
Reject {Assert-HudGroundExtensionMode $true $true $false 'manifest' $false 'trace'} 'Fixture cannot emit trace'
Reject {Assert-HudGroundExtensionProof $coupled $run $inputRecord -Coupled -TraceFile 'trace.ndjson'} 'Coupled cannot use synthetic provenance'
Reject {Assert-HudGroundExtensionProof $coupled $run $captured -Coupled -TraceFile 'foreign.ndjson'} 'Coupled trace path bound'
Reject {Assert-HudGroundExtensionProof $coupled $run $captured} 'Coupled marker cannot claim fixture'
foreach($field in @('trace_closed','trace_result','trace_records','hud_run')){
    $bad=Clone $coupled;$p=$bad.lab_evidence.ground_movement
    switch($field){trace_closed{$p.trace_closed=$false} trace_result{$p.trace_result='failed'} trace_records{$p.trace_records=0} hud_run{$p.hud_run='c'*32}}
    Reject {Assert-HudGroundExtensionProof $bad $run $captured -Coupled -TraceFile 'trace.ndjson'} "Coupled $field proof bound"
}
$delayed=Clone $coupled;$delayed | Add-Member ui_ground_extension_delay_fixture $true
$e=$delayed.lab_evidence.ground_movement.extension;$e.handoff_delay_fixture=$true;$e.minimum_handoff_wait_ms=600;$e.handoff_wait_ms=700;$e.handoff_trace_samples=6
$null=Assert-HudGroundExtensionProof $delayed $run $captured -Coupled -TraceFile 'trace.ndjson' -DelayHandoff
Check $true 'Delayed coupled handoff requires trace freshness throughout actual wait'
Reject {Assert-HudGroundExtensionProof $delayed $run $captured -Coupled -TraceFile 'trace.ndjson'} 'Ordinary mode cannot accept a delay fixture'
Reject {Assert-HudGroundExtensionProof $coupled $run $captured -Coupled -TraceFile 'trace.ndjson' -DelayHandoff} 'Delay mode needs its explicit marker'
Reject {Assert-HudGroundExtensionMode $false $true $false '' $false '' $true} 'Delay selector cannot activate another mode'
foreach($change in @('flag','minimum','short_wait','long_wait','trace_samples')){
    $bad=Clone $delayed;$e=$bad.lab_evidence.ground_movement.extension
    switch($change){flag{$e.handoff_delay_fixture=$false} minimum{$e.minimum_handoff_wait_ms=0} short_wait{$e.handoff_wait_ms=599} long_wait{$e.handoff_wait_ms=2000} trace_samples{$e.handoff_trace_samples=2}}
    Reject {Assert-HudGroundExtensionProof $bad $run $captured -Coupled -TraceFile 'trace.ndjson' -DelayHandoff} "Reject delayed $change"
}
Write-Output "HUD_GROUND_EXTENSION_PROOF_TESTS_PASS checks=$script:checks"
