# Separate standalone extension profile; no live input or native movement authority.
function Assert-HudGroundExtensionMode([bool]$Enabled,[bool]$Standalone,[bool]$OtherMode,[string]$File,[bool]$Coupled=$false,[string]$Trace='',[bool]$DelayHandoff=$false){
    if($DelayHandoff -and -not ($Enabled -or $Coupled)){throw 'Delay fixture requires an explicit extension mode.'}
    if(($Enabled -and $Coupled) -or (($Enabled -or $Coupled) -and (-not $Standalone -or $OtherMode))){throw 'Terrain extension requires one separate standalone HUD profile.'}
    if(-not ($Enabled -or $Coupled) -and $File){throw 'Extension file requires its explicit selector.'}
    if($Coupled -and (-not $File -or -not $Trace)){throw 'Coupled extension requires captured geometry and a new trace.'}
    if($Enabled -and $Trace){throw 'Standalone extension fixture cannot emit a follower trace.'}
}
function Assert-HudGroundExtensionMarker($Receipt,[bool]$Expected,[bool]$Coupled=$false,[bool]$DelayHandoff=$false){
    $delayField=$Receipt.PSObject.Properties['ui_ground_extension_delay_fixture']
    if($DelayHandoff){
        if(-not ($Expected -or $Coupled) -or $null -eq $delayField -or $delayField.Value -isnot [bool] -or -not $delayField.Value){throw 'Explicit extension delay marker missing.'}
    }elseif($delayField){throw 'Unrequested extension delay fixture marker.'}
    if($Expected -and $Coupled){throw 'Conflicting extension receipt modes.'}
    $field=$Receipt.PSObject.Properties['ui_ground_extension_fixture']
    if($Expected){
        if($null -eq $field -or $field.Value -isnot [bool] -or -not $field.Value){throw 'Explicit standalone extension marker missing.'}
    }elseif($field){throw 'Unrequested extension fixture marker.'}
    $coupledField=$Receipt.PSObject.Properties['ui_ground_extension_coupled']
    if($Coupled){
        if($null -eq $coupledField -or $coupledField.Value -isnot [bool] -or -not $coupledField.Value -or $Receipt.walking_area -cne 'extension'){throw 'Explicit coupled extension marker missing.'}
    }elseif($coupledField){throw 'Unrequested coupled extension marker.'}
    if($Expected -or $Coupled){
        if($Receipt.standalone -isnot [bool] -or -not $Receipt.standalone){throw 'Extension requires its standalone receiver.'}
        foreach($name in @('ui_ground_movement_fixture','ui_ground_movement_coupled','ui_ground_corridor_fixture','ui_ground_corridor_coupled','corridor_walk_only','ui_input_physical_movement','ui_physical_controller_fixture')){
            if($Receipt.PSObject.Properties[$name]){throw 'Extension receipt contains another movement authority marker.'}
        }
    }
}
function Assert-HudGroundExtensionProof($Guest,[string]$Run,$Extension,[switch]$Coupled,[string]$TraceFile,[switch]$DelayHandoff){
    function Flag($Object,[string]$Field,[bool]$Expected){if($Object.$Field -isnot [bool] -or $Object.$Field -ne $Expected){throw "Extension boolean differs: $Field"}}
    function Number($Object,[string]$Field,[double]$Minimum,[double]$Maximum){
        $v=$Object.$Field
        if(($v -isnot [int] -and $v -isnot [long] -and $v -isnot [double] -and $v -isnot [decimal]) -or -not [double]::IsFinite([double]$v) -or $v -lt $Minimum -or $v -gt $Maximum){throw "Extension numeric proof differs: $Field"}
    }
    Assert-HudGroundExtensionMarker $Guest (-not $Coupled) ([bool]$Coupled) ([bool]$DelayHandoff)
    if(-not $Extension.Captured -and $Extension.Run -cne $Run){throw 'Synthetic extension requires the same owned HUD run.'}
    $p=$Guest.lab_evidence.ground_movement
    $kind=if($Coupled){'minecome_hud_ground_extension_coupled_v1'}else{'minecome_hud_ground_extension_fixture_v1'}
    $source=if($Extension.Captured){'live_kcd_ground_extension'}else{'standalone_ground_extension_fixture'}
    if($Guest.run -cne $Run -or $Guest.result -cne 'passed' -or $Guest.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or
        $p.schema -ne 1 -or $p.kind -cne $kind -or $p.phase -cne 'PASSED' -or
        $p.save -cne $Guest.save -or $p.save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        $p.patch_run -cne $Extension.Run -or $p.patch_sha256 -cne $Extension.Hash -or $p.ground_source_kind -cne $source){throw 'Extension completion identity differs.'}
    foreach($field in @('synthetic_input','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){Flag $p $field $true}
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified','client_air','server_air','client_land','server_land')){Flag $p $field $false}
    foreach($field in @('client_walk','server_walk')){Number $p $field 9 11.5}
    foreach($field in @('client_proxy_queries','server_proxy_queries')){Number $p $field 1 ([int]::MaxValue)}
    Number $p 'post_settle_corrections' 0 0
    Number $p.frame_captures 'WALKING' 1 ([int]::MaxValue)
    Number $p.frame_captures 'JUMPING' 0 0;Number $p.frame_captures 'LANDING' 0 0
    $e=$p.extension
    Flag $e 'handoff_delay_fixture' ([bool]$DelayHandoff)
    $minimumWait=if($DelayHandoff){600}else{0}
    Number $e 'minimum_handoff_wait_ms' $minimumWait $minimumWait
    Number $e 'handoff_wait_ms' $minimumWait 1999.999999
    if($DelayHandoff -and $Coupled){Number $e 'handoff_trace_samples' 3 256}
    if($e.plan_sha256 -cne $Extension.Hash -or $e.expanded_sha256 -cne $Extension.Hash -or
        $Extension.InitialHash -cnotmatch '^[0-9a-f]{64}$' -or $e.initial_sha256 -cne $Extension.InitialHash){throw 'Extension immutable surface identities differ.'}
    if((@($e.tile_sha256) -join ',') -cne (@($Extension.TileHashes) -join ',') -or @($e.tile_sha256).Count -ne 3){throw 'Extension tile identity differs.'}
    foreach($axis in @('x','y','z')){if($e.anchor.$axis -ne $Extension.Anchor.$axis){throw 'Extension coordinate anchor changed.'}}
    Number $e 'initial_max_x' 8 8;Number $e 'expanded_max_x' 12 12;Number $e 'trigger_x' 4.5 4.5
    foreach($field in @('client_installed','server_installed','client_vanilla_cells_air','server_vanilla_cells_air')){Flag $e $field $true}
    foreach($field in @('client_max_x','server_max_x')){Number $e $field 9.5 11.5}
    foreach($field in @('client_return_distance','server_return_distance')){Number $e $field 0 .75}
    Number $e 'max_client_server_distance' 0 1
    foreach($field in @('transition_hud_frames','crossing_hud_frames','return_hud_frames')){Number $e $field 1 ([int]::MaxValue)}
    Number $e 'slab_count' 128 128;Number $e 'collision_cell_count' 128 256
    if($Coupled){
        if(-not $Extension.Captured -or -not $TraceFile -or $p.trace_file -ine $TraceFile -or $p.trace_result -cne 'passed' -or $p.hud_run -cne $Run){throw 'Coupled extension requires its exact successful server trace.'}
        Flag $p 'trace_closed' $true;Number $p 'trace_records' 3 256
    }
    return $p
}
