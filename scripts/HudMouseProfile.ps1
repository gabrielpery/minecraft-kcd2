# Exact original mouse/world build profiles. Read-only helpers shared by staging,
# deployment, rollback and arming; no arbitrary custom renderer is accepted.
function Get-MineComeMouseProfile {
    param([switch]$WorldClicks)
    $path=Join-Path $PSScriptRoot $(if($WorldClicks){'../config/hud-world-profile.json'}else{'../config/hud-mouse-profile.json'})
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked mouse profile path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $path).Length -gt 16KB){throw 'Mouse profile exceeds its bound.'}
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $expectedKind=if($WorldClicks){'minecome_hud_world_profile_v1'}else{'minecome_hud_mouse_profile_v1'}
    if($profile.schema -ne 1 -or $profile.kind -cne $expectedKind -or
       $profile.upstream_commit -cne '18deaa52de0c425a78b329e9cb3c497281cd00ec' -or $profile.mouse_capture_api -ne 1){throw 'Unknown mouse profile.'}
    foreach($field in @('runtime_sha256','addon_sha256','shader_sha256','build_receipt_sha256','patch_sha256','api_sha256')){
        if($profile.$field -cnotmatch '^[0-9a-f]{64}$' -or $profile.$field -ceq ('0'*64)){throw "Unfrozen mouse profile: $field"}
    }
    return $profile
}
function Assert-MineComeMouseBundle($Manifest,$Profile,[switch]$WorldClicks) {
    $fields=if($Manifest -is [Collections.IDictionary]){@($Manifest.Keys)}else{@($Manifest.PSObject.Properties.Name)}
    $expectedArm=if($WorldClicks){'minecome-hud/addons/MineComeHudWorld.ini'}else{'minecome-hud/addons/MineComeHudMouse.ini'}
    if($WorldClicks){
        if($fields -notcontains 'world_clicks' -or $Manifest.world_clicks -isnot [bool] -or $Manifest.world_clicks -ne $true){throw 'World clicks require explicit Boolean bundle provenance.'}
    }elseif($fields -contains 'world_clicks'){throw 'World bundle requires explicit WorldClicks mode.'}
    if($fields -notcontains 'mouse_capture_api' -or $Manifest.mouse_capture_api -ne 1 -or
       $Manifest.stream_protocol -ne 1 -or $Manifest.ui_input_protocol -ne 1 -or
       $Manifest.arm_config_relative_path -cne $expectedArm -or
       $Manifest.runtime.reshade64_sha256 -cne $Profile.runtime_sha256 -or
       $Manifest.runtime.build_receipt_sha256 -cne $Profile.build_receipt_sha256){throw 'Exact prepared mouse profile required.'}
    $expected=[ordered]@{'dxgi.dll'=$Profile.runtime_sha256;'minecome-hud/addons/MineComeHudCompositor.addon64'=$Profile.addon_sha256;'minecome-hud/shaders/MineComeHud.fx'=$Profile.shader_sha256}
    foreach($path in $expected.Keys){
        $entries=@($Manifest.files | Where-Object {$_.path -ceq $path})
        if($entries.Count -ne 1 -or $entries[0].sha256 -cne $expected[$path]){throw "Mouse profile artifact differs: $path"}
    }
}

# A prior custom proxy is accepted only when both its frozen bundle and the
# installation receipt describe the same complete six-file owned installation.
function Assert-MineComeMouseInstalledBundle($Manifest,$Receipt,$Profile,[switch]$WorldClicks) {
    Assert-MineComeMouseBundle $Manifest $Profile -WorldClicks:$WorldClicks
    if($Manifest.schema -ne 1 -or $Manifest.kind -cne 'minecome_hud_compositor_bundle_v1' -or
       $Manifest.tools_only -ne $true -or $Manifest.runtime.version -cne '6.8.0' -or
       $Manifest.runtime.full_addon_support -ne $true -or $Receipt.schema -ne 1 -or
       $Receipt.kind -cne 'minecome_hud_install_v1' -or @($Manifest.files).Count -ne 6 -or @($Receipt.files).Count -ne 6){throw 'Exact previous custom bundle and installation receipt required.'}
    foreach($path in @('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')){
        $staged=@($Manifest.files | Where-Object {$_.path -ceq $path})
        $installed=@($Receipt.files | Where-Object {$_.path -ceq $path})
        if($staged.Count -ne 1 -or $installed.Count -ne 1 -or
           $staged[0].sha256 -cne $installed[0].sha256 -or $staged[0].bytes -ne $installed[0].bytes){throw 'Previous custom bundle differs from the owned installation receipt.'}
    }
}
