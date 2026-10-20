#Requires -Version 5.1
# Pure exact-profile, receipt-chain and mode checks. No process or game access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudMouseProfile.ps1')
$script:checks=0
$SelectiveRevision=1
$AimedStone=$false
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
function Parse-Script([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Invalid syntax: $Relative"
    return $ast
}
$profile=[pscustomobject]@{runtime_sha256=('a'*64);addon_sha256=('b'*64);shader_sha256=('c'*64);build_receipt_sha256=('d'*64);patch_sha256=('e'*64);api_sha256=('f'*64)}
function New-Manifest([string]$Mode='Selective',$Profile=$script:profile){
    $value=[ordered]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;mouse_capture_api=$(if($Mode -eq 'Selective'){2}else{1});stream_protocol=1;ui_input_protocol=1
        arm_config_relative_path=('minecome-hud/addons/MineComeHud'+$Mode+'.ini')
        runtime=[ordered]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=$Profile.runtime_sha256;build_receipt_sha256=$Profile.build_receipt_sha256}
        files=@([ordered]@{path='dxgi.dll';bytes=10;sha256=$Profile.runtime_sha256},[ordered]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=20;sha256=$Profile.addon_sha256},[ordered]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=30;sha256=$Profile.shader_sha256})}
    foreach($path in @('ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt')){$value.files+=@([ordered]@{path=$path;bytes=40;sha256=('e'*64)})}
    if($Mode -ne 'Mouse'){$value.world_clicks=$true}
    if($Mode -eq 'Selective'){$value.selective_mouse=$true}
    return $value
}
function New-Receipt($Manifest){[ordered]@{schema=1;kind='minecome_hud_install_v1';files=@($Manifest.files|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})}}
foreach($declared in @('Mouse','World','Selective')){
    foreach($requested in @('Mouse','World','Selective')){
        foreach($json in @($false,$true)){
            $manifest=New-Manifest $declared
            if($json){$manifest=$manifest|ConvertTo-Json -Depth 8|ConvertFrom-Json}
            $arguments=@{WorldClicks=($requested -ne 'Mouse');SelectiveMouse=($requested -eq 'Selective')}
            if($declared -eq $requested){Assert-MineComeMouseBundle $manifest $profile @arguments;Check $true 'Exact requested profile accepted'}
            else{Reject {Assert-MineComeMouseBundle $manifest $profile @arguments} 'Mixed capture profile accepted'}
        }
    }
}
Reject {Get-MineComeMouseProfile -SelectiveMouse} 'Selective profile accepted without explicit world mode'
Reject {Assert-MineComeMouseBundle (New-Manifest) $profile -SelectiveMouse} 'Selective manifest accepted without explicit world mode'
foreach($field in @('world_clicks','selective_mouse')){
    foreach($invalid in @($false,'true','false',0,1,$null)){
        $manifest=New-Manifest;$manifest[$field]=$invalid
        Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Non-true Boolean selective marker accepted'
    }
    $manifest=New-Manifest;$manifest.Remove($field)
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Missing selective marker accepted'
}
foreach($mode in @('Mouse','World')){
    foreach($invalid in @($false,'true',0,1,$null,$true)){
        $manifest=New-Manifest $mode;$manifest.selective_mouse=$invalid
        Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks:($mode -eq 'World')} 'Selective provenance accepted by a legacy mode'
    }
}
foreach($version in @(0,1,3)){
    $manifest=New-Manifest;$manifest.mouse_capture_api=$version
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Non-v2 API accepted'
}
foreach($path in @('MineComeHudMouse.ini','MineComeHudWorld.ini','MineComeHudInput.ini','MineComeHudSELECTIVE.ini')){
    $manifest=New-Manifest;$manifest.arm_config_relative_path='minecome-hud/addons/'+$path
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Wrong selective arm accepted'
}
for($index=0;$index -lt 3;$index++){
    $manifest=New-Manifest;$manifest.files[$index].sha256='1'*64
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Unfrozen selective artifact accepted'
    $manifest=New-Manifest;$manifest.files+=@($manifest.files[$index])
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse} 'Duplicate selective artifact accepted'
}

function New-BuildReceipt {
    [ordered]@{kind='minecome_selective_reshade_build_v2';status='built';commit='18deaa52de0c425a78b329e9cb3c497281cd00ec';version='6.8.0.3';mouse_capture_api=2;output_sha256=('a'*64)
        generated_outputs_unchanged=$true;patched_source_unchanged=$true;installed_proxy_unchanged=$true;reference_unchanged=$true;pristine_source_unchanged=$true;pristine_script_unchanged=$true
        original_inputs=@([ordered]@{path='C:\private\selective-capture.patch';sha256=('e'*64)},[ordered]@{path='C:\private\selective_capture_api.hpp';sha256=('f'*64)},[ordered]@{path='C:\private\selective_capture_policy.hpp';sha256=('1'*64)},[ordered]@{path='C:\private\selective_capture_adapter.hpp';sha256=('2'*64)})
        patched_paths=@('source/input_windows.cpp','source/windows/dinput8.cpp','source/windows/selective_capture_api.hpp','source/windows/selective_capture_policy.hpp','source/windows/selective_capture_adapter.hpp')}
}
$build=New-BuildReceipt;Assert-MineComeSelectiveBuildReceipt $build $profile;Check $true 'Exact selective receipt accepted'
Assert-MineComeSelectiveBuildReceipt ($build|ConvertTo-Json -Depth 8|ConvertFrom-Json) $profile;Check $true 'Exact JSON selective receipt accepted'
foreach($flag in @('generated_outputs_unchanged','patched_source_unchanged','installed_proxy_unchanged','reference_unchanged','pristine_source_unchanged','pristine_script_unchanged')){
    foreach($invalid in @($false,'true',1,$null)){
        $build=New-BuildReceipt;$build[$flag]=$invalid
        Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Missing typed build verification accepted'
    }
}
foreach($field in @('kind','status','commit','version','mouse_capture_api','output_sha256')){
    $build=New-BuildReceipt;$build[$field]=$null
    Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Missing selective build identity accepted'
}
for($index=0;$index -lt 2;$index++){
    $build=New-BuildReceipt;$build.original_inputs[$index].sha256='3'*64
    Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Different selective patch/API input accepted'
    $build=New-BuildReceipt;$build.original_inputs[$index].path='C:\private\unexpected.hpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Missing selective patch/API input accepted'
}
$build=New-BuildReceipt;$build.original_inputs+=@($build.original_inputs[0]);Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Repeated selective input accepted'
for($index=0;$index -lt 5;$index++){
    $build=New-BuildReceipt;$build.patched_paths[$index]='source/extra.cpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build $profile} 'Unexpected selective patch source accepted'
}

$arm=Parse-Script 'scripts/Arm-HudStream.ps1'
$update=Parse-Script 'scripts/Update-HudCompositor.ps1'
$disable=Parse-Script 'scripts/Disable-HudCompositor.ps1'
$prepare=Parse-Script 'scripts/Prepare-HudCompositor.ps1'
$archive=Parse-Script 'scripts/Archive-HudArm.ps1'
$null=Parse-Script 'scripts/Build-SelectiveReShade.ps1'
$null=Parse-Script 'scripts/HudMouseProfile.ps1'
$PhysicalMovement=$false
foreach($ast in @($arm,$update,$disable)){
    Check (@($ast.ParamBlock.Parameters|Where-Object{$_.Name.VariablePath.UserPath -eq 'SelectiveMouse'}).Count -eq 1) 'Explicit selective option present'
    $guards=@()
    foreach($statement in $ast.EndBlock.Statements){
        if($statement -is [Management.Automation.Language.IfStatementAst]){$guards+=$statement.Extent.Text}
        elseif($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -ceq '$inputProtocol'){continue}
        elseif($guards.Count){break}
    }
    Check ($guards.Count -eq $(if($ast -eq $arm){8}else{4})) 'Initial pure configuration guards found'
    $guard=[scriptblock]::Create($guards -join "`n")
    foreach($world in @($false,$true)){
        foreach($mouse in @($false,$true)){
            $WorldClicks=$world;$LiveMouse=$mouse;$SelectiveMouse=$true;$InputMode=$true;$OffscreenPresentation=$true;$StoneLive=$true
            if($world -and $mouse){& $guard;Check $true 'Explicit selective configuration accepted'}
            else{Reject {& $guard} 'Partial selective configuration accepted'}
        }
    }
}
foreach($ast in @($arm,$update,$archive)){
    Check ($ast.Extent.Text.Contains("'MineComeHudSelective.ini'")) 'Selective arm included in conflict/ownership checks'
}
$mode=$prepare.ParamBlock.Parameters|Where-Object{$_.Name.VariablePath.UserPath -eq 'Mode'}
Check ($mode.Extent.Text.Contains("'Selective'")) 'Selective staging mode available'

# Run the actual Update prior-profile branch with synthetic receipts. This
# proves Selective chooses the frozen World predecessor, while World keeps Mouse.
$prior=$update.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.Contains('Assert-MineComeMouseInstalledBundle')}|Select-Object -First 1
Check ($null -ne $prior) 'Actual predecessor validation branch found'
$priorGuard=[scriptblock]::Create($prior.Extent.Text)
function Read-Json([string]$Path){return $script:priorManifest}
$PreviousBundleDirectory='C:\private\previous';$WorldClicks=$true
foreach($selective in @($false,$true)){
    $SelectiveMouse=$selective;$priorMode=if($selective){'World'}else{'Mouse'}
    $priorProfile=Get-MineComeMouseProfile -WorldClicks:$selective
    $script:priorManifest=New-Manifest $priorMode $priorProfile;$old=New-Receipt $script:priorManifest
    . $priorGuard;Check ($previousProxyHash -ceq $priorProfile.runtime_sha256) 'Exact frozen predecessor proxy selected'
    $old.files[0].sha256='4'*64
    Reject {& $priorGuard} 'Changed predecessor proxy accepted'
    $wrongMode=if($selective){'Mouse'}else{'World'}
    $script:priorManifest=New-Manifest $wrongMode $priorProfile;$old=New-Receipt $script:priorManifest
    Reject {& $priorGuard} 'Wrong predecessor profile accepted'
}
$mouseProfile=Get-MineComeMouseProfile;$worldProfile=Get-MineComeMouseProfile -WorldClicks
Check ($mouseProfile.addon_sha256 -ceq 'e947533ec27e70a4782fa3c4e40df4d2fc69d85b00d768393bd1c43345fb34ca') 'V1 Mouse profile preserved'
Check ($worldProfile.addon_sha256 -ceq '8d65235dcb59bf0f27300164c46ecb357983513d41150df69055b21614265cdb') 'V1 World profile preserved'
$selectiveProfile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse
Check ($selectiveProfile.kind -ceq 'minecome_hud_selective_profile_v2' -and $selectiveProfile.mouse_capture_api -eq 2) 'Selective API2 profile frozen'
Check ($selectiveProfile.runtime_sha256 -cne $worldProfile.runtime_sha256 -and $selectiveProfile.addon_sha256 -cne $worldProfile.addon_sha256) 'Selective proxy/add-on distinct from both v1 fallbacks'
Check ($selectiveProfile.shader_sha256 -ceq $worldProfile.shader_sha256) 'Verified HUD shader preserved'
Write-Output "HUD_SELECTIVE_PROFILE_TEST_PASS checks=$checks no_game=true deployment=false"
