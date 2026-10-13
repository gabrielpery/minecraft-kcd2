# Exact original mouse/world/selective build profiles. Read-only helpers shared by staging,
# deployment, rollback and arming; no arbitrary custom renderer is accepted.
function Assert-MineComeSelectiveRevision($Value,[bool]$SelectiveMouse,[ValidateSet(1,2,3)][int]$SelectiveRevision=1) {
    if($SelectiveRevision -ge 2 -and -not $SelectiveMouse){throw 'A selective revision requires explicit SelectiveMouse mode.'}
    $fields=if($Value -is [Collections.IDictionary]){@($Value.Keys)}else{@($Value.PSObject.Properties.Name)}
    if($SelectiveRevision -ge 2){
        if($fields -notcontains 'selective_revision' -or
           ($Value.selective_revision -isnot [int] -and $Value.selective_revision -isnot [long]) -or
           $Value.selective_revision -ne $SelectiveRevision){throw 'Explicit matching integer selective revision provenance required.'}
    }elseif($fields -contains 'selective_revision'){throw 'Revision metadata cannot be mixed into a frozen original profile.'}
}
function Get-MineComeMouseProfile {
    param([switch]$WorldClicks,[switch]$SelectiveMouse,[ValidateSet(1,2,3)][int]$SelectiveRevision=1)
    if($SelectiveMouse -and -not $WorldClicks){throw 'Selective mouse profile requires explicit WorldClicks mode.'}
    if($SelectiveRevision -ge 2 -and -not $SelectiveMouse){throw 'A selective revision requires explicit SelectiveMouse mode.'}
    $path=Join-Path $PSScriptRoot $(if($SelectiveMouse -and $SelectiveRevision -eq 3){'../config/hud-selective-profile-r3.json'}elseif($SelectiveMouse -and $SelectiveRevision -eq 2){'../config/hud-selective-profile-r2.json'}elseif($SelectiveMouse){'../config/hud-selective-profile.json'}elseif($WorldClicks){'../config/hud-world-profile.json'}else{'../config/hud-mouse-profile.json'})
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked mouse profile path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $path).Length -gt 16KB){throw 'Mouse profile exceeds its bound.'}
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Assert-MineComeSelectiveRevision $profile ([bool]$SelectiveMouse) $SelectiveRevision
    $expectedKind=if($SelectiveMouse){'minecome_hud_selective_profile_v2'}elseif($WorldClicks){'minecome_hud_world_profile_v1'}else{'minecome_hud_mouse_profile_v1'}
    $expectedApi=if($SelectiveMouse){2}else{1}
    if($profile.schema -ne 1 -or $profile.kind -cne $expectedKind -or
       $profile.upstream_commit -cne '18deaa52de0c425a78b329e9cb3c497281cd00ec' -or $profile.mouse_capture_api -ne $expectedApi){throw 'Unknown mouse profile.'}
    $hashFields=@('runtime_sha256','addon_sha256','shader_sha256','build_receipt_sha256','patch_sha256','api_sha256')
    if($SelectiveRevision -ge 2){$hashFields+=@('diagnostics_api_sha256')}
    if($SelectiveRevision -eq 3){$hashFields+=@('raw_diagnostics_api_sha256')}
    foreach($field in $hashFields){
        if($profile.$field -cnotmatch '^[0-9a-f]{64}$' -or $profile.$field -ceq ('0'*64)){throw "Unfrozen mouse profile: $field"}
    }
    return $profile
}
function Assert-MineComeMouseBundle($Manifest,$Profile,[switch]$WorldClicks,[switch]$SelectiveMouse,[ValidateSet(1,2,3)][int]$SelectiveRevision=1) {
    if($SelectiveMouse -and -not $WorldClicks){throw 'Selective mouse bundle requires explicit WorldClicks mode.'}
    Assert-MineComeSelectiveRevision $Manifest ([bool]$SelectiveMouse) $SelectiveRevision
    Assert-MineComeSelectiveRevision $Profile ([bool]$SelectiveMouse) $SelectiveRevision
    $fields=if($Manifest -is [Collections.IDictionary]){@($Manifest.Keys)}else{@($Manifest.PSObject.Properties.Name)}
    $expectedArm=if($SelectiveMouse){'minecome-hud/addons/MineComeHudSelective.ini'}elseif($WorldClicks){'minecome-hud/addons/MineComeHudWorld.ini'}else{'minecome-hud/addons/MineComeHudMouse.ini'}
    $expectedApi=if($SelectiveMouse){2}else{1}
    if($SelectiveMouse){
        if($fields -notcontains 'selective_mouse' -or $Manifest.selective_mouse -isnot [bool] -or $Manifest.selective_mouse -ne $true){throw 'Selective mouse requires explicit Boolean bundle provenance.'}
    }elseif($fields -contains 'selective_mouse'){throw 'Selective bundle requires explicit SelectiveMouse mode.'}
    if($WorldClicks){
        if($fields -notcontains 'world_clicks' -or $Manifest.world_clicks -isnot [bool] -or $Manifest.world_clicks -ne $true){throw 'World clicks require explicit Boolean bundle provenance.'}
    }elseif($fields -contains 'world_clicks'){throw 'World bundle requires explicit WorldClicks mode.'}
    if($fields -notcontains 'mouse_capture_api' -or $Manifest.mouse_capture_api -ne $expectedApi -or
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
function Assert-MineComeMouseInstalledBundle($Manifest,$Receipt,$Profile,[switch]$WorldClicks,[switch]$SelectiveMouse,[ValidateSet(1,2,3)][int]$SelectiveRevision=1) {
    Assert-MineComeMouseBundle $Manifest $Profile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision
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

function Assert-MineComeSelectiveBuildReceipt($Receipt,$Profile,[ValidateSet(1,2,3)][int]$SelectiveRevision=1) {
    Assert-MineComeSelectiveRevision $Receipt $true $SelectiveRevision
    Assert-MineComeSelectiveRevision $Profile $true $SelectiveRevision
    $expectedVersion=if($SelectiveRevision -eq 3){'6.8.0.5'}elseif($SelectiveRevision -eq 2){'6.8.0.4'}else{'6.8.0.3'}
    if($Receipt.kind -cne 'minecome_selective_reshade_build_v2' -or $Receipt.status -cne 'built' -or
       $Receipt.commit -cne '18deaa52de0c425a78b329e9cb3c497281cd00ec' -or
       $Receipt.version -cne $expectedVersion -or $Receipt.mouse_capture_api -ne 2 -or
       $Receipt.output_sha256 -ine $Profile.runtime_sha256){throw 'Exact API2 selective build receipt required.'}
    foreach($flag in @('generated_outputs_unchanged','patched_source_unchanged','installed_proxy_unchanged','reference_unchanged','pristine_source_unchanged','pristine_script_unchanged')){
        if($Receipt.$flag -isnot [bool] -or $Receipt.$flag -ne $true){throw "Selective build verification missing: $flag"}
    }
    $patchName=if($SelectiveRevision -eq 3){'selective-motion-r3.patch'}elseif($SelectiveRevision -eq 2){'selective-motion-r2.patch'}else{'selective-capture.patch'}
    $expected=[ordered]@{};$expected[$patchName]=$Profile.patch_sha256;$expected['selective_capture_api.hpp']=$Profile.api_sha256
    $expectedInputs=@($patchName,'selective_capture_api.hpp','selective_capture_policy.hpp','selective_capture_adapter.hpp')
    if($SelectiveRevision -ge 2){
        $expectedInputs+=@('motion_capture_adapter.hpp','motion_policy.hpp','motion_diagnostics_api.hpp')
        $expected['motion_diagnostics_api.hpp']=$Profile.diagnostics_api_sha256
    }
    if($SelectiveRevision -eq 3){
        $expectedInputs+=@('raw_motion_capture_adapter.hpp','raw_motion_policy.hpp','raw_motion_diagnostics_api.hpp')
        $expected['raw_motion_diagnostics_api.hpp']=$Profile.raw_diagnostics_api_sha256
    }
    if(@($Receipt.original_inputs).Count -ne $expectedInputs.Count -or
       ((@($Receipt.original_inputs|ForEach-Object{[IO.Path]::GetFileName($_.path)})|Sort-Object) -join '|') -cne (($expectedInputs|Sort-Object) -join '|')){throw 'Selective build must identify its exact patch and original headers.'}
    foreach($name in $expected.Keys){
        $records=@($Receipt.original_inputs | Where-Object {[IO.Path]::GetFileName($_.path) -ceq $name})
        if($records.Count -ne 1 -or $records[0].sha256 -ine $expected[$name]){throw 'Selective patch/API source differs from its frozen profile.'}
    }
    $expectedPaths=@('source/input_windows.cpp','source/windows/dinput8.cpp','source/windows/selective_capture_api.hpp','source/windows/selective_capture_policy.hpp','source/windows/selective_capture_adapter.hpp')
    if($SelectiveRevision -ge 2){$expectedPaths+=@('source/windows/motion_capture_adapter.hpp','source/windows/motion_policy.hpp','source/windows/motion_diagnostics_api.hpp')}
    if($SelectiveRevision -eq 3){$expectedPaths+=@('source/windows/raw_motion_capture_adapter.hpp','source/windows/raw_motion_policy.hpp','source/windows/raw_motion_diagnostics_api.hpp')}
    if(@($Receipt.patched_paths).Count -ne $expectedPaths.Count -or
       ((@($Receipt.patched_paths)|Sort-Object) -join '|') -cne (($expectedPaths|Sort-Object) -join '|')){throw 'Selective build changed an unexpected source path.'}
}
