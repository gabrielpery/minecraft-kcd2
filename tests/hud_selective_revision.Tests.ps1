#Requires -Version 5.1
# Closed revision selection and exact predecessor proofs, without game access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudMouseProfile.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
function Parse-Script([string]$Name){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('scripts/'+$Name+'.ps1')),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Invalid syntax: $Name"
    return $ast
}
function Load-Function($Ast,[string]$Name){
    $node=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    Check ($null -ne $node) "Production function missing: $Name"
    return [scriptblock]::Create($node.Extent.Text)
}
function New-Profile([int]$Revision){
    $value=[ordered]@{runtime_sha256=('a'*64);addon_sha256=('b'*64);shader_sha256=('c'*64);build_receipt_sha256=('d'*64);patch_sha256=('e'*64);api_sha256=('f'*64)}
    if($Revision -ge 2){$value.selective_revision=$Revision;$value.diagnostics_api_sha256='1'*64}
    if($Revision -eq 3){$value.raw_diagnostics_api_sha256='6'*64}
    return $value
}
function New-Manifest([int]$Revision,$Profile=(New-Profile $Revision)){
    $value=[ordered]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;mouse_capture_api=2;stream_protocol=1;ui_input_protocol=1;world_clicks=$true;selective_mouse=$true
        arm_config_relative_path='minecome-hud/addons/MineComeHudSelective.ini'
        runtime=[ordered]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=$Profile.runtime_sha256;build_receipt_sha256=$Profile.build_receipt_sha256}
        files=@([ordered]@{path='dxgi.dll';bytes=10;sha256=$Profile.runtime_sha256},[ordered]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=20;sha256=$Profile.addon_sha256},[ordered]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=30;sha256=$Profile.shader_sha256})}
    foreach($path in @('ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt')){$value.files+=@([ordered]@{path=$path;bytes=40;sha256=('e'*64)})}
    if($Revision -ge 2){$value.selective_revision=$Revision}
    return $value
}
function New-Receipt($Manifest){[ordered]@{schema=1;kind='minecome_hud_install_v1';files=@($Manifest.files|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})}}
foreach($declared in @(1,2,3)){
    foreach($requested in @(1,2,3)){
        foreach($json in @($false,$true)){
            $manifest=New-Manifest $declared;$profile=New-Profile $requested
            if($json){$manifest=$manifest|ConvertTo-Json -Depth 8|ConvertFrom-Json}
            if($declared -eq $requested){Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse -SelectiveRevision $requested;Check $true 'Matching revision accepted'}
            else{Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks -SelectiveMouse -SelectiveRevision $requested} 'Revision mismatch accepted'}
        }
    }
}
foreach($invalid in @($null,$false,$true,'2',[double]2,0,1,3)){
    $manifest=New-Manifest 2;$manifest.selective_revision=$invalid
    Reject {Assert-MineComeMouseBundle $manifest (New-Profile 2) -WorldClicks -SelectiveMouse -SelectiveRevision 2} 'Untyped/wrong revision marker accepted'
}
$manifest=New-Manifest 2;$manifest.Remove('selective_revision')
Reject {Assert-MineComeMouseBundle $manifest (New-Profile 2) -WorldClicks -SelectiveMouse -SelectiveRevision 2} 'Missing revision marker accepted'
Reject {Assert-MineComeMouseBundle (New-Manifest 2) (New-Profile 1) -WorldClicks -SelectiveMouse -SelectiveRevision 2} 'Mixed profile revision accepted'
foreach($arguments in @(@{},@{WorldClicks=$true})){
    Reject {Get-MineComeMouseProfile @arguments -SelectiveRevision 2} 'Revision 2 implicitly enabled selective mode'
    Reject {Assert-MineComeMouseBundle (New-Manifest 2) (New-Profile 2) @arguments -SelectiveRevision 2} 'Revision 2 bundle enabled an undeclared mode'
}
foreach($revision in @(0,4)){
    Reject {Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision $revision} 'Unsupported revision accepted'
}
function New-BuildReceipt {
    [ordered]@{kind='minecome_selective_reshade_build_v2';selective_revision=2;status='built';commit='18deaa52de0c425a78b329e9cb3c497281cd00ec';version='6.8.0.4';mouse_capture_api=2;output_sha256=('a'*64)
        generated_outputs_unchanged=$true;patched_source_unchanged=$true;installed_proxy_unchanged=$true;reference_unchanged=$true;pristine_source_unchanged=$true;pristine_script_unchanged=$true
        original_inputs=@([ordered]@{path='C:\private\selective-motion-r2.patch';sha256=('e'*64)},[ordered]@{path='C:\private\selective_capture_api.hpp';sha256=('f'*64)},[ordered]@{path='C:\private\selective_capture_policy.hpp';sha256=('2'*64)},[ordered]@{path='C:\private\selective_capture_adapter.hpp';sha256=('3'*64)},[ordered]@{path='C:\private\motion_capture_adapter.hpp';sha256=('4'*64)},[ordered]@{path='C:\private\motion_policy.hpp';sha256=('5'*64)},[ordered]@{path='C:\private\motion_diagnostics_api.hpp';sha256=('1'*64)})
        patched_paths=@('source/input_windows.cpp','source/windows/dinput8.cpp','source/windows/selective_capture_api.hpp','source/windows/selective_capture_policy.hpp','source/windows/selective_capture_adapter.hpp','source/windows/motion_capture_adapter.hpp','source/windows/motion_policy.hpp','source/windows/motion_diagnostics_api.hpp')}
}
foreach($json in @($false,$true)){
    $build=New-BuildReceipt;if($json){$build=$build|ConvertTo-Json -Depth 8|ConvertFrom-Json}
    Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2;Check $true 'Exact revision 2 receipt accepted'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 1)} 'Revision 2 runtime accepted by original profile'
}
foreach($field in @('kind','status','commit','version','mouse_capture_api','output_sha256','selective_revision')){
    $build=New-BuildReceipt;$build[$field]=$null
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Incomplete revision 2 runtime identity accepted'
}
foreach($version in @('6.8.0.3','6.8.0.5')){
    $build=New-BuildReceipt;$build.version=$version
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Wrong runtime version accepted'
}
for($index=0;$index -lt 7;$index++){
    $build=New-BuildReceipt;$build.original_inputs[$index].path='C:\private\unexpected.hpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Unexpected revision 2 source input accepted'
}
foreach($index in @(0,1,6)){
    $build=New-BuildReceipt;$build.original_inputs[$index].sha256='9'*64
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Changed patch/API input accepted'
}
for($index=0;$index -lt 8;$index++){
    $build=New-BuildReceipt;$build.patched_paths[$index]='source/unexpected.cpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Unexpected patched path accepted'
}
function New-RawBuildReceipt {
    $value=New-BuildReceipt
    $value.selective_revision=3;$value.version='6.8.0.5'
    $value.original_inputs[0].path='C:\private\selective-motion-r3.patch'
    $value.original_inputs+=@([ordered]@{path='C:\private\raw_motion_capture_adapter.hpp';sha256=('7'*64)},[ordered]@{path='C:\private\raw_motion_policy.hpp';sha256=('8'*64)},[ordered]@{path='C:\private\raw_motion_diagnostics_api.hpp';sha256=('6'*64)})
    $value.patched_paths+=@('source/windows/raw_motion_capture_adapter.hpp','source/windows/raw_motion_policy.hpp','source/windows/raw_motion_diagnostics_api.hpp')
    return $value
}
foreach($json in @($false,$true)){
    $build=New-RawBuildReceipt;if($json){$build=$build|ConvertTo-Json -Depth 8|ConvertFrom-Json}
    Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3;Check $true 'Exact revision 3 runtime receipt accepted'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 2) -SelectiveRevision 2} 'Revision 3 runtime accepted as revision 2'
    Reject {Assert-MineComeSelectiveBuildReceipt (New-BuildReceipt) (New-Profile 3) -SelectiveRevision 3} 'Revision 2 runtime accepted as revision 3'
}
foreach($invalid in @($null,$false,$true,'3',[double]3,0,1,2,4)){
    $manifest=New-Manifest 3;$manifest.selective_revision=$invalid
    Reject {Assert-MineComeMouseBundle $manifest (New-Profile 3) -WorldClicks -SelectiveMouse -SelectiveRevision 3} 'Untyped/wrong revision 3 marker accepted'
}
foreach($field in @('kind','status','commit','version','mouse_capture_api','output_sha256','selective_revision')){
    $build=New-RawBuildReceipt;$build[$field]=$null
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3} 'Incomplete revision 3 runtime identity accepted'
}
foreach($version in @('6.8.0.4','6.8.0.6')){
    $build=New-RawBuildReceipt;$build.version=$version
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3} 'Wrong revision 3 runtime version accepted'
}
for($index=0;$index -lt 10;$index++){
    $build=New-RawBuildReceipt;$build.original_inputs[$index].path='C:\private\unexpected.hpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3} 'Unexpected revision 3 source input accepted'
}
for($index=0;$index -lt 11;$index++){
    $build=New-RawBuildReceipt;$build.patched_paths[$index]='source/unexpected.cpp'
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3} 'Unexpected revision 3 patched path accepted'
}
foreach($index in @(0,1,6,9)){
    $build=New-RawBuildReceipt;$build.original_inputs[$index].sha256='9'*64
    Reject {Assert-MineComeSelectiveBuildReceipt $build (New-Profile 3) -SelectiveRevision 3} 'Changed revision 3 patch/API input accepted'
}
$asts=@{}
foreach($name in @('Build-SelectiveReShade','Prepare-HudCompositor','Update-HudCompositor','Disable-HudCompositor','Arm-HudStream','Start-HudInputLab')){
    $ast=Parse-Script $name;$asts[$name]=$ast
    $parameter=@($ast.ParamBlock.Parameters|Where-Object{$_.Name.VariablePath.UserPath -eq 'SelectiveRevision'})
    Check ($parameter.Count -eq 1 -and $parameter[0].DefaultValue.Extent.Text -ceq '1' -and $parameter[0].Extent.Text.Contains('ValidateSet(1,2,3)')) "Closed revision selector/default missing: $name"
}
foreach($name in @('Update-HudCompositor','Disable-HudCompositor','Arm-HudStream')){
    $guards=@()
    foreach($statement in $asts[$name].EndBlock.Statements){
        if($statement -is [Management.Automation.Language.IfStatementAst]){$guards+=$statement.Extent.Text}
        elseif($guards.Count){break}
    }
    $guard=[scriptblock]::Create($guards -join "`n")
    foreach($revision in @(2,3)){
        foreach($selective in @($false,$true)){
            $SelectiveRevision=$revision;$SelectiveMouse=$selective;$WorldClicks=$true;$LiveMouse=$true;$InputMode=$true;$OffscreenPresentation=$true;$StoneLive=$true
            if($selective){& $guard;Check $true 'Explicit revision prerequisites accepted'}else{Reject {& $guard} 'Revision accepted without explicit selective mode'}
        }
    }
}
$runtimeRoot=Join-Path $root 'runtime';$LiveMouse=$true;$WorldClicks=$true;$SelectiveMouse=$true
foreach($name in @('Prepare-HudCompositor','Update-HudCompositor','Disable-HudCompositor','Arm-HudStream','Start-HudInputLab')){
    $variable=if($name -eq 'Prepare-HudCompositor'){'OutputDirectory'}else{'BundleDirectory'}
    $node=$asts[$name].Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -match ('^if\s*\(\s*-not \$'+$variable+'\)')},$true)
    Check ($null -ne $node) "Bundle default not found: $name"
    $default=[scriptblock]::Create($node.Extent.Text)
    foreach($revision in @(1,2,3)){
        $SelectiveRevision=$revision;$BundleDirectory=$null;$OutputDirectory=$null;$Mode='Selective'
        . $default
        $actual=if($variable -eq 'OutputDirectory'){$OutputDirectory}else{$BundleDirectory}
        $expected=if($revision -eq 3){'hud-compositor-selective-r3'}elseif($revision -eq 2){'hud-compositor-selective-r2'}else{'hud-compositor-selective'}
        Check ((Split-Path -Leaf $actual) -ceq $expected) "Wrong revision bundle default: $name"
    }
}
$update=$asts['Update-HudCompositor']
$defaultPrior=$update.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text.StartsWith('if(-not $PreviousBundleDirectory)')},$true)
Check ($null -ne $defaultPrior) 'Predecessor default found'
foreach($revision in @(1,2,3)){
    $SelectiveRevision=$revision;$PreviousBundleDirectory=$null
    . ([scriptblock]::Create($defaultPrior.Extent.Text))
    $expected=if($revision -eq 3){'hud-compositor-selective-r2'}elseif($revision -eq 2){'hud-compositor-selective'}else{'hud-compositor-world'}
    Check ((Split-Path -Leaf $PreviousBundleDirectory) -ceq $expected) 'Exact revision predecessor default selected'
}
$prepareGuard=$asts['Prepare-HudCompositor'].EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst]}|Select-Object -First 1
$SelectiveRevision=2
foreach($mode in @('Static','Stream','Input','Mouse','World')){
    $Mode=$mode;Reject {& ([scriptblock]::Create($prepareGuard.Extent.Text))} 'Revision 2 staging accepted in a different mode'
}
$Mode='Selective';& ([scriptblock]::Create($prepareGuard.Extent.Text));Check $true 'Explicit revision 2 staging accepted'
$prior=$update.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.Contains('Assert-MineComeMouseInstalledBundle')}|Select-Object -First 1
Check ($null -ne $prior) 'Exact predecessor branch found'
$priorGuard=[scriptblock]::Create($prior.Extent.Text)
function Read-Json([string]$Path){return $script:priorManifest}
$SelectiveRevision=2;$SelectiveMouse=$true;$WorldClicks=$true;$PreviousBundleDirectory='C:\private\previous'
$oldProfile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse
$script:priorManifest=New-Manifest 1 $oldProfile;$old=New-Receipt $script:priorManifest
. $priorGuard;Check ($previousProxyHash -ceq $oldProfile.runtime_sha256) 'Revision 2 selects exact original Selective runtime'
foreach($index in @(0,1,2,3,4,5)){
    $old=New-Receipt $script:priorManifest;$old.files[$index].sha256='8'*64
    Reject {& $priorGuard} 'Changed predecessor file accepted'
}
$script:priorManifest=New-Manifest 2 $oldProfile;$old=New-Receipt $script:priorManifest
Reject {& $priorGuard} 'Revision 2 predecessor metadata accepted instead of original Selective'
$revision2Profile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 2
$SelectiveRevision=3
$script:priorManifest=New-Manifest 2 $revision2Profile;$old=New-Receipt $script:priorManifest
. $priorGuard;Check ($previousProxyHash -ceq $revision2Profile.runtime_sha256) 'Revision 3 selects exact frozen revision 2 runtime'
foreach($index in @(0,1,2,3,4,5)){
    $old=New-Receipt $script:priorManifest;$old.files[$index].sha256='8'*64
    Reject {& $priorGuard} 'Changed revision 2 predecessor file accepted'
}
foreach($wrongRevision in @(1,3)){
    $script:priorManifest=New-Manifest $wrongRevision $revision2Profile;$old=New-Receipt $script:priorManifest
    Reject {& $priorGuard} 'Wrong revision predecessor accepted for revision 3'
}
$controller=$asts['Start-HudInputLab']
. (Load-Function $controller 'Assert-HudSelectiveArm')
. (Load-Function $controller 'Assert-HudStoneConfiguration')
foreach($representation in @('ordered','hashtable','json')){
    foreach($revision in @(1,2,3)){
        $receipt=[ordered]@{selective_mouse=$true};if($revision -ge 2){$receipt.selective_revision=$revision}
        if($representation -eq 'hashtable'){$copy=@{};foreach($key in $receipt.Keys){$copy[$key]=$receipt[$key]};$receipt=$copy}
        if($representation -eq 'json'){$receipt=$receipt|ConvertTo-Json|ConvertFrom-Json}
        Assert-HudSelectiveArm $receipt $true $revision;Check $true 'Direct/stored arm revision accepted'
        foreach($other in @(1,2,3)|Where-Object{$_ -ne $revision}){Reject {Assert-HudSelectiveArm $receipt $true $other} 'Wrong direct/stored arm revision accepted'}
    }
}
foreach($invalid in @($null,$false,$true,'2',[double]2,0,1,3)){
    Reject {Assert-HudSelectiveArm ([ordered]@{selective_mouse=$true;selective_revision=$invalid}) $true 2} 'Untyped arm revision accepted'
}
foreach($invalid in @($null,$false,$true,'3',[double]3,0,1,2,4)){
    Reject {Assert-HudSelectiveArm ([ordered]@{selective_mouse=$true;selective_revision=$invalid}) $true 3} 'Untyped/wrong revision 3 arm accepted'
}
Reject {Assert-HudSelectiveArm ([ordered]@{selective_mouse=$false;selective_revision=2}) $false 2} 'Revision 2 arm accepted without selective mode'
$configuration=@{Mode='Live';StoneFixture=$false;StoneLive=$true;LiveMouse=$true;OffscreenPresentation=$true;OffscreenTrial=$false;HostGpuBudget=$true;PointerFixture=$false;DelayFixture=$false;BackgroundTrial=$false;HideHostHud=$true;WorldClicks=$true;SelectiveMouse=$true;SelectiveRevision=2}
Assert-HudStoneConfiguration @configuration;Check $true 'Revision 2 controller prerequisites accepted'
foreach($field in @('SelectiveMouse','WorldClicks','StoneLive','LiveMouse','OffscreenPresentation','HostGpuBudget')){
    $configuration[$field]=$false;Reject {Assert-HudStoneConfiguration @configuration} 'Missing revision 2 controller prerequisite accepted';$configuration[$field]=$true
}
$configuration.SelectiveRevision=3
Assert-HudStoneConfiguration @configuration;Check $true 'Revision 3 controller prerequisites accepted'
foreach($field in @('SelectiveMouse','WorldClicks','StoneLive','LiveMouse','OffscreenPresentation','HostGpuBudget')){
    $configuration[$field]=$false;Reject {Assert-HudStoneConfiguration @configuration} 'Missing revision 3 controller prerequisite accepted';$configuration[$field]=$true
}
$calls=@($controller.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.Extent.Text.StartsWith('& (Join-Path') -and $n.Extent.Text.Contains("'Arm-HudStream.ps1'")},$true))
Check ($calls.Count -eq 2) 'Preflight and live arm call sites found'
foreach($call in $calls){Check ($call.Extent.Text.Contains('-SelectiveRevision $SelectiveRevision')) 'Controller does not pass revision into child arm'}
Check ($controller.Extent.Text.Contains('Assert-HudSelectiveArm $armEvidence ([bool]$SelectiveMouse) $SelectiveRevision')) 'Controller must validate returned arm revision'
Check ($controller.Extent.Text.Contains('selective_revision_requested=$(if($SelectiveMouse){$SelectiveRevision}else{0})')) 'Controller receipt records requested revision'
$profile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 2
Check ($profile.selective_revision -eq 2 -and $profile.mouse_capture_api -eq 2) 'Revision 2 profile frozen'
foreach($field in @('runtime_sha256','addon_sha256','build_receipt_sha256','patch_sha256')){Check ($profile.$field -cne $oldProfile.$field) 'New runtime/add-on/receipt/patch separately pinned'}
foreach($field in @('api_sha256','shader_sha256')){Check ($profile.$field -ceq $oldProfile.$field) 'Original API2 ABI/HUD shader preserved'}
Check ($oldProfile.runtime_sha256 -ceq '2157f25f36baebe1c577cb3c6d8a485691fbacc727262d1a4bc09f9265522511' -and $oldProfile.addon_sha256 -ceq '15f3ac12101f0a1f36aa731c89f5df9018dc8d0b43d1e966117f78d138fba4de') 'Original Selective profile preserved'
$rawProfile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 3
Check ($rawProfile.selective_revision -eq 3 -and $rawProfile.mouse_capture_api -eq 2) 'Revision 3 profile frozen'
foreach($field in @('runtime_sha256','addon_sha256','build_receipt_sha256','patch_sha256')){Check ($rawProfile.$field -cne $revision2Profile.$field) 'Revision 3 runtime/add-on/receipt/patch separately pinned'}
foreach($field in @('api_sha256','shader_sha256','diagnostics_api_sha256')){Check ($rawProfile.$field -ceq $revision2Profile.$field) 'Existing API2 ABI, motion diagnostics and HUD shader preserved'}
Check ($revision2Profile.runtime_sha256 -ceq '7a0464fc9f32cbed3e37efb924144dd6128d894f3a1f24fb9eb943e392609774' -and $revision2Profile.addon_sha256 -ceq '960c9493b0836ab916c57f7592745ec265bf0f2fcae78b55d2a350fbc92755e0') 'Frozen revision 2 profile preserved'
Write-Output "HUD_SELECTIVE_REVISION_TEST_PASS checks=$checks no_game=true deployment=false"
