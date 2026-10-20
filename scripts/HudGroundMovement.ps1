# Pure configuration and evidence checks for the standalone HUD/ground fixture.
function Assert-HudGroundMovementMode([bool]$GroundMovementFixture,[bool]$Standalone,[bool]$Composite) {
    if($GroundMovementFixture -and (-not $Standalone -or $Composite)) {
        throw 'HUD ground movement requires explicit standalone mode without KCD composition.'
    }
}
function New-HudGroundMovementPatch([string]$Run) {
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'A fresh fixture run token is required.'}
    $points=for($row=0;$row -lt 5;$row++){for($column=0;$column -lt 5;$column++){
        [ordered]@{schema=1;run=$Run;index=1+$row*5+$column;x=120+$column-2;y=2040+$row-2;z=56;nx=0;ny=0;nz=1;valid=$true;result='hit';mask=256;approximate_heightfield=$true;full_collision_export_verified=$false}
    }}
    return [ordered]@{schema=1;run=$Run;result='sampled';center=@{x=120;y=2040;z=56};grid_size=5;spacing=1;point_count=25;valid_count=25;stable_player=$true;mask=256;approximate_heightfield=$true;full_collision_export_verified=$false;points=@($points);provenance=@{kind='standalone_fixture'}}
}
function Assert-HudGroundMovementMarkers($Receipt,[bool]$Expected) {
    foreach($field in @('ui_ground_movement_fixture','standalone')){
        if($null -eq $Receipt.PSObject.Properties[$field]) {
            if($Expected){throw 'HUD ground movement readiness marker missing.'}
            continue
        }
        # Ordinary standalone streams may also identify their controller.
        if($Receipt.$field -isnot [bool] -or ($field -eq 'ui_ground_movement_fixture' -and $Receipt.$field -ne $Expected) -or ($Expected -and -not $Receipt.$field)) {
            throw 'HUD ground movement readiness mode mismatch.'
        }
    }
}
function Assert-HudGroundMovementProof($Guest,[string]$Run,[string]$PatchHash) {
    Assert-HudGroundMovementMarkers $Guest $true
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $PatchHash -cnotmatch '^[0-9a-f]{64}$' -or $Guest.run -cne $Run -or $Guest.result -cne 'passed') {throw 'Ground/HUD result does not belong to this completed stream.'}
    $proof=$Guest.lab_evidence.ground_movement
    if($proof.schema -ne 1 -or $proof.kind -cne 'minecome_hud_ground_movement_fixture_v1' -or
        $proof.save -cne $Guest.save -or $proof.save -cnotmatch '^MineCome-HudStream-[0-9a-f-]{36}$' -or
        $proof.patch_run -cne $Run -or $proof.patch_sha256 -cne $PatchHash -or
        $proof.ground_source_kind -cne 'standalone_fixture' -or $proof.phase -cne 'PASSED') {
        throw 'Ground/HUD fixture provenance or terminal phase differs.'
    }
    foreach($field in @('synthetic_input','client_air','server_air','client_land','server_land','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')) {
        if($proof.$field -isnot [bool] -or -not $proof.$field){throw "Ground/HUD completion proof missing: $field"}
    }
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')) {
        if($proof.$field -isnot [bool] -or $proof.$field){throw "Ground/HUD fixture overclaims live evidence: $field"}
    }
    foreach($field in @('client_walk','server_walk')) {
        $value=$proof.$field
        if(($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long] -and $value -isnot [decimal]) -or
            -not [double]::IsFinite([double]$value) -or $value -lt 0.3 -or $value -gt 4){throw 'Vanilla walk was not confirmed inside the bounded patch.'}
    }
    foreach($field in @('client_proxy_queries','server_proxy_queries')){
        if(($proof.$field -isnot [int] -and $proof.$field -isnot [long]) -or $proof.$field -lt 1){throw 'Both game threads must query imported ground collision.'}
    }
    if(($proof.post_settle_corrections -isnot [int] -and $proof.post_settle_corrections -isnot [long]) -or $proof.post_settle_corrections -ne 0){throw 'Unexpected movement correction after settling.'}
    $captures=$proof.frame_captures
    foreach($phase in @('WALKING','JUMPING','LANDING')){
        if(($captures.$phase -isnot [int] -and $captures.$phase -isnot [long]) -or $captures.$phase -lt 0){throw 'Invalid movement-phase capture evidence.'}
    }
    if($captures.WALKING -lt 1 -or $captures.JUMPING+$captures.LANDING -lt 1){throw 'HUD frames did not overlap walk and jump phases.'}
    return $proof
}
