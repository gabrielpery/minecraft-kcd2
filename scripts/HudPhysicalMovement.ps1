# Explicit physical walking profile. The working r4 profile remains immutable.
. (Join-Path $PSScriptRoot 'HudMouseProfile.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingArea.ps1')
. (Join-Path $PSScriptRoot 'HudWalkingSession.ps1')
function Get-MineComePhysicalMovementProfile {
    $base=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
    $path=Join-Path $PSScriptRoot '../config/hud-physical-movement-profile.json'
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked physical movement profile refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $path).Length -gt 16KB){throw 'Physical movement profile exceeded its bound.'}
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if($profile.schema -ne 1 -or $profile.kind -cne 'minecome_hud_physical_movement_profile_v1' -or
        $profile.ui_input_protocol -ne 2 -or $profile.mouse_capture_api -ne 2 -or
        $profile.runtime_sha256 -cne $base.runtime_sha256 -or $profile.shader_sha256 -cne $base.shader_sha256 -or
        $profile.build_receipt_sha256 -cne $base.build_receipt_sha256 -or
        $profile.addon_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $profile.addon_sha256 -ceq ('0'*64)){
        throw 'Exact frozen physical movement profile required.'
    }
    return $profile
}
function Assert-MineComePhysicalMovementBundle($Manifest,$Profile){
    if($Manifest.schema -ne 1 -or $Manifest.kind -cne 'minecome_hud_compositor_bundle_v1' -or
        $Manifest.tools_only -isnot [bool] -or -not $Manifest.tools_only -or
        $Manifest.physical_movement -isnot [bool] -or -not $Manifest.physical_movement -or
        $Manifest.stream_protocol -ne 1 -or $Manifest.ui_input_protocol -ne 2 -or $Manifest.mouse_capture_api -ne 2 -or
        $Manifest.arm_config_relative_path -cne 'minecome-hud/addons/MineComeHudMovement.ini' -or
        $Manifest.runtime.reshade64_sha256 -cne $Profile.runtime_sha256 -or
        $Manifest.runtime.build_receipt_sha256 -cne $Profile.build_receipt_sha256 -or @($Manifest.files).Count -ne 6){
        throw 'Exact physical movement bundle required.'
    }
    foreach($field in @('world_clicks','selective_mouse','selective_revision')){
        if($Manifest.PSObject.Properties.Name -contains $field){throw 'Physical movement cannot accept another input profile.'}
    }
    $hashes=@{'dxgi.dll'=$Profile.runtime_sha256;'minecome-hud/addons/MineComeHudCompositor.addon64'=$Profile.addon_sha256;'minecome-hud/shaders/MineComeHud.fx'=$Profile.shader_sha256}
    foreach($path in $hashes.Keys){
        $entry=@($Manifest.files | Where-Object path -CEQ $path)
        if($entry.Count -ne 1 -or $entry[0].sha256 -cne $hashes[$path]){throw 'Physical movement artifact hash mismatch.'}
    }
}
function Assert-HudPhysicalMovementReady($Ready,[bool]$Expected,[switch]$CorridorWalking,[switch]$WalkingAimed){
    if($CorridorWalking){
        if(-not $Expected){throw 'Corridor readiness requires its explicit physical walking controller.'}
        Assert-HudWalkingArea $Ready $false -CorridorWalking
        Assert-HudWalkingSession $Ready -ExtendedWalking
        foreach($name in @('ui_walking_aimed_fixture','facing_seed','ui_ground_corridor_fixture','ui_ground_corridor_coupled','corridor_walk_only')){
            $marker=$Ready.PSObject.Properties[$name]
            if($marker -and ($marker.Value -isnot [bool] -or $marker.Value)){throw 'Physical corridor cannot use an aimed, facing or scripted producer.'}
        }
        foreach($name in @('ui_input_walking_aimed','ui_input_aimed_stone_bridge')){
            $marker=$Ready.PSObject.Properties[$name]
            if($WalkingAimed){if(-not $marker -or $marker.Value -isnot [bool] -or -not $marker.Value){throw 'Combined corridor requires explicit aimed producer markers.'}}
            elseif($marker -and ($marker.Value -isnot [bool] -or $marker.Value)){throw 'Aimed corridor requires its combined controller.'}
        }
    }elseif($Ready.PSObject.Properties['walking_area'] -and $Ready.walking_area -ceq 'corridor'){
        throw 'Corridor readiness requires explicit corridor arming.'
    }
    # A standalone controller fixture must never become a live renderer/input
    # producer, even if a malformed receipt also advertises live protocol fields.
    if($null -ne $Ready.PSObject.Properties['ui_physical_controller_fixture']){
        throw 'Standalone physical controller fixtures cannot arm live HUD input.'
    }
    $scripted=$Ready.PSObject.Properties['scripted_input']
    if($Expected -and $null -ne $scripted -and ($scripted.Value -isnot [bool] -or $scripted.Value)){
        throw 'Live physical walking requires non-scripted input.'
    }
    $field=$Ready.PSObject.Properties['ui_input_physical_movement']
    if($Expected){
        if($null -eq $field -or $field.Value -isnot [bool] -or -not $field.Value -or $Ready.ui_input_protocol -ne 2){
            throw 'Physical walking requires an explicit protocol2 producer.'
        }
    }elseif($null -ne $field -and ($field.Value -isnot [bool] -or $field.Value)){
        throw 'Physical walking producer requires its separate controller.'
    }
}
