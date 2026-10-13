# Exact original mouse build profile. Read-only helpers shared by staging,
# deployment, rollback and arming; no arbitrary custom renderer is accepted.
function Get-MineComeMouseProfile {
    $path=Join-Path $PSScriptRoot '../config/hud-mouse-profile.json'
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked mouse profile path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $path).Length -gt 16KB){throw 'Mouse profile exceeds its bound.'}
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if($profile.schema -ne 1 -or $profile.kind -cne 'minecome_hud_mouse_profile_v1' -or
       $profile.upstream_commit -cne '18deaa52de0c425a78b329e9cb3c497281cd00ec' -or $profile.mouse_capture_api -ne 1){throw 'Unknown mouse profile.'}
    foreach($field in @('runtime_sha256','addon_sha256','shader_sha256','build_receipt_sha256','patch_sha256','api_sha256')){
        if($profile.$field -cnotmatch '^[0-9a-f]{64}$' -or $profile.$field -ceq ('0'*64)){throw "Unfrozen mouse profile: $field"}
    }
    return $profile
}
function Assert-MineComeMouseBundle($Manifest,$Profile) {
    $fields=if($Manifest -is [Collections.IDictionary]){@($Manifest.Keys)}else{@($Manifest.PSObject.Properties.Name)}
    if($fields -notcontains 'mouse_capture_api' -or $Manifest.mouse_capture_api -ne 1 -or
       $Manifest.stream_protocol -ne 1 -or $Manifest.ui_input_protocol -ne 1 -or
       $Manifest.arm_config_relative_path -cne 'minecome-hud/addons/MineComeHudMouse.ini' -or
       $Manifest.runtime.reshade64_sha256 -cne $Profile.runtime_sha256 -or
       $Manifest.runtime.build_receipt_sha256 -cne $Profile.build_receipt_sha256){throw 'Exact prepared mouse profile required.'}
    $expected=[ordered]@{'dxgi.dll'=$Profile.runtime_sha256;'minecome-hud/addons/MineComeHudCompositor.addon64'=$Profile.addon_sha256;'minecome-hud/shaders/MineComeHud.fx'=$Profile.shader_sha256}
    foreach($path in $expected.Keys){
        $entries=@($Manifest.files | Where-Object {$_.path -ceq $path})
        if($entries.Count -ne 1 -or $entries[0].sha256 -cne $expected[$path]){throw "Mouse profile artifact differs: $path"}
    }
}
