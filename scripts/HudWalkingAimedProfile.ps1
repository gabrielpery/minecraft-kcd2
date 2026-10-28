# Explicit combined profile. Neither existing walking nor selective r4 can select it implicitly.
. (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
function Get-MineComeWalkingAimedProfile {
    $base=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
    $path=Join-Path $PSScriptRoot '../config/hud-walking-aimed-profile.json'
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked walking aimed profile refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $path).Length -gt 16KB){throw 'Walking aimed profile exceeded its bound.'}
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if($profile.schema -ne 1 -or $profile.kind -cne 'minecome_hud_walking_aimed_profile_v1' -or
        $profile.ui_input_protocol -ne 2 -or $profile.mouse_capture_api -ne 2 -or
        $profile.runtime_sha256 -cne $base.runtime_sha256 -or $profile.shader_sha256 -cne $base.shader_sha256 -or
        $profile.build_receipt_sha256 -cne $base.build_receipt_sha256 -or
        $profile.addon_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $profile.addon_sha256 -ceq ('0'*64) -or
        $profile.addon_sha256 -ceq $base.addon_sha256 -or $profile.addon_sha256 -ceq (Get-MineComePhysicalMovementProfile).addon_sha256){
        throw 'Exact separate walking aimed profile required.'
    }
    return $profile
}
function Assert-MineComeWalkingAimedBundle($Manifest,$Profile){
    foreach($field in @('schema','stream_protocol','ui_input_protocol','mouse_capture_api')){
        if($Manifest.$field -isnot [int] -and $Manifest.$field -isnot [long]){throw 'Walking aimed protocol versions must be integers.'}
    }
    foreach($field in @('tools_only','walking_aimed','physical_movement','world_clicks','selective_mouse')){
        if($Manifest.$field -isnot [bool] -or -not $Manifest.$field){throw "Explicit walking aimed Boolean required: $field"}
    }
    if($Manifest.schema -ne 1 -or $Manifest.kind -cne 'minecome_hud_compositor_bundle_v1' -or
        $Manifest.stream_protocol -ne 1 -or $Manifest.ui_input_protocol -ne 2 -or $Manifest.mouse_capture_api -ne 2 -or
        ($Manifest.selective_revision -isnot [int] -and $Manifest.selective_revision -isnot [long]) -or $Manifest.selective_revision -ne 4 -or
        $Manifest.arm_config_relative_path -cne 'minecome-hud/addons/MineComeHudWalkingAimed.ini' -or
        $Manifest.runtime.version -cne '6.8.0' -or $Manifest.runtime.full_addon_support -isnot [bool] -or -not $Manifest.runtime.full_addon_support -or
        $Manifest.runtime.reshade64_sha256 -cne $Profile.runtime_sha256 -or
        $Manifest.runtime.build_receipt_sha256 -cne $Profile.build_receipt_sha256 -or @($Manifest.files).Count -ne 6){
        throw 'Exact walking aimed bundle required.'
    }
    $paths=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
    foreach($path in $paths){
        $entry=@($Manifest.files | Where-Object path -CEQ $path)
        if($entry.Count -ne 1 -or $entry[0].sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            ($entry[0].bytes -isnot [int] -and $entry[0].bytes -isnot [long]) -or $entry[0].bytes -lt 1 -or $entry[0].bytes -gt 64MB){throw 'Invalid walking aimed artifact identity.'}
    }
    $hashes=@{'dxgi.dll'=$Profile.runtime_sha256;'minecome-hud/addons/MineComeHudCompositor.addon64'=$Profile.addon_sha256;'minecome-hud/shaders/MineComeHud.fx'=$Profile.shader_sha256}
    foreach($path in $hashes.Keys){if(@($Manifest.files | Where-Object path -CEQ $path)[0].sha256 -cne $hashes[$path]){throw 'Walking aimed artifact hash mismatch.'}}
}
function Assert-MineComeWalkingAimedInstalledBundle($Manifest,$Receipt,$Profile){
    Assert-MineComeWalkingAimedBundle $Manifest $Profile
    if($Receipt.schema -ne 1 -or $Receipt.kind -cne 'minecome_hud_install_v1' -or @($Receipt.files).Count -ne 6){throw 'Exact walking aimed installation receipt required.'}
    foreach($entry in $Manifest.files){
        $owned=@($Receipt.files | Where-Object path -CEQ $entry.path)
        if($owned.Count -ne 1 -or $owned[0].sha256 -cne $entry.sha256 -or
            ($owned[0].bytes -isnot [int] -and $owned[0].bytes -isnot [long]) -or $owned[0].bytes -ne $entry.bytes){throw 'Walking aimed installed files differ from their bundle.'}
    }
}
function Assert-HudWalkingAimedReady($Ready,[bool]$Expected){
    $marker=$Ready.PSObject.Properties['ui_input_walking_aimed']
    if(-not $Expected){
        if($null -ne $marker -and ($marker.Value -isnot [bool] -or $marker.Value)){throw 'Walking aimed producer requires its explicit controller.'}
        return
    }
    if($null -eq $marker -or $marker.Value -isnot [bool] -or -not $marker.Value){throw 'Walking aimed readiness marker missing or malformed.'}
    Assert-HudPhysicalMovementReady $Ready $true
    if($Ready.ui_input_protocol -isnot [int] -and $Ready.ui_input_protocol -isnot [long]){throw 'Walking aimed input protocol must be an integer.'}
    if($Ready.movement_session -cne 'extended' -or $Ready.scripted_input -isnot [bool] -or $Ready.scripted_input){throw 'Walking aimed requires the extended non-scripted live profile.'}
    foreach($field in @('ui_input_stone_bridge','ui_input_stone_live','ui_input_aimed_stone_bridge','ui_input_live_mouse','ui_input_offscreen_presentation')){
        if($Ready.$field -isnot [bool] -or -not $Ready.$field){throw "Walking aimed guest capability missing: $field"}
    }
    foreach($field in @('ui_walking_aimed_fixture','ui_physical_controller_fixture','ui_ground_movement_fixture','ui_ground_movement_coupled','standalone')){
        $value=$Ready.PSObject.Properties[$field]
        if($null -ne $value -and ($value.Value -isnot [bool] -or $value.Value)){throw 'Fixture producer cannot arm walking aimed input.'}
    }
}
