#Requires -Version 7.3
# Pure profile/receipt tests. No game launch, deployment or arming occurs.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 14)}
. (Join-Path $root 'scripts/HudWalkingAimedProfile.ps1')
$profile=Get-MineComeWalkingAimedProfile
$walking=Get-MineComePhysicalMovementProfile
$r4=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
Check ($profile.addon_sha256 -cne $walking.addon_sha256 -and $profile.addon_sha256 -cne $r4.addon_sha256) 'Combined artifact must be distinct from both existing profiles'
Check ($profile.runtime_sha256 -ceq $r4.runtime_sha256 -and $profile.shader_sha256 -ceq $r4.shader_sha256) 'Combined profile reuses the frozen runtime and shader'
foreach($relative in @('scripts/HudWalkingAimedProfile.ps1','scripts/Prepare-HudWalkingAimed.ps1','scripts/Arm-HudStream.ps1',
    'scripts/Install-HudCompositor.ps1','scripts/Update-HudCompositor.ps1','scripts/Disable-HudCompositor.ps1','scripts/Archive-HudArm.ps1')){
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Syntax errors: $relative"
}
$bundle=[pscustomobject]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;walking_aimed=$true;physical_movement=$true;world_clicks=$true;selective_mouse=$true;selective_revision=4
    stream_protocol=1;ui_input_protocol=2;mouse_capture_api=2;arm_config_relative_path='minecome-hud/addons/MineComeHudWalkingAimed.ini'
    runtime=[pscustomobject]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=$profile.runtime_sha256;build_receipt_sha256=$profile.build_receipt_sha256}
    files=@(
        [pscustomobject]@{path='dxgi.dll';bytes=10;sha256=$profile.runtime_sha256},
        [pscustomobject]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=20;sha256=$profile.addon_sha256},
        [pscustomobject]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=30;sha256=$profile.shader_sha256},
        [pscustomobject]@{path='ReShade.ini';bytes=40;sha256='a'*64},
        [pscustomobject]@{path='MineComeHudPreset.ini';bytes=50;sha256='b'*64},
        [pscustomobject]@{path='ReShade-LICENSE.txt';bytes=60;sha256='c'*64})}
Assert-MineComeWalkingAimedBundle $bundle $profile
Check $true 'Exact combined bundle accepted'
$repeatProfile=Get-MineComeWalkingAimedProfile -RepeatSession
Check ($repeatProfile.addon_sha256 -cne $profile.addon_sha256) 'Repeat sessions use a separately frozen addon'
$repeatBundle=Clone $bundle
$repeatBundle.arm_config_relative_path='minecome-hud/addons/MineComeHudWalkingRepeat.ini'
$repeatBundle.files[1].sha256=$repeatProfile.addon_sha256
$repeatBundle | Add-Member NoteProperty repeat_sessions 2
Assert-MineComeWalkingAimedBundle $repeatBundle $repeatProfile
Check $true 'Explicit repeat-session bundle accepted'
$updatePath=Join-Path $root 'scripts/Update-HudCompositor.ps1'
$tokens=$null;$errors=$null
$updateAst=[Management.Automation.Language.Parser]::ParseFile($updatePath,[ref]$tokens,[ref]$errors)
$transition=$updateAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-MineComePhysicalUpdatePreviousProfile'},$true)
if(-not $transition){throw 'Missing integrated physical update predecessor check'}
Invoke-Expression $transition.Extent.Text
$repeatInstalled=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $repeatBundle.files)}
Check ((Get-MineComePhysicalUpdatePreviousProfile $repeatBundle $repeatInstalled $true).addon_sha256 -ceq $repeatProfile.addon_sha256) 'Explicit return to plain physical selects the exact repeat predecessor pins'
Reject {Get-MineComePhysicalUpdatePreviousProfile $repeatBundle $repeatInstalled $false} 'Default physical transition silently accepted repeat predecessor'
$r4Bundle=Clone $bundle;$r4Bundle.ui_input_protocol=1;$r4Bundle.arm_config_relative_path='minecome-hud/addons/MineComeHudSelective.ini'
$r4Bundle.PSObject.Properties.Remove('walking_aimed');$r4Bundle.PSObject.Properties.Remove('physical_movement');$r4Bundle.files[1].sha256=$r4.addon_sha256
$r4Installed=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $r4Bundle.files)}
Check ((Get-MineComePhysicalUpdatePreviousProfile $r4Bundle $r4Installed $false).addon_sha256 -ceq $r4.addon_sha256) 'Default physical transition retains the original exact r4 predecessor'
Reject {Get-MineComePhysicalUpdatePreviousProfile $r4Bundle $r4Installed $true} 'Explicit repeat transition accepted r4 instead'
Reject {Get-MineComePhysicalUpdatePreviousProfile $bundle ([pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $bundle.files)}) $true} 'Repeat predecessor accepted one-shot walking aimed'
for($index=0;$index -lt 6;$index++){
    $bad=Clone $repeatInstalled;$bad.files[$index].sha256='f'*64
    Reject {Get-MineComePhysicalUpdatePreviousProfile $repeatBundle $bad $true} 'Repeat transition bypassed one installed file identity'
}
foreach($field in @('repeat_sessions','walking_aimed','physical_movement')){
    $bad=Clone $repeatBundle;$bad.$field=$false
    Reject {Get-MineComePhysicalUpdatePreviousProfile $bad $repeatInstalled $true} 'Repeat transition accepted an altered predecessor profile'
}
Reject {& $updatePath -FromWalkingAimedRepeat -PreflightOnly} 'Repeat transition flag silently selected a destination profile'
Reject {& $updatePath -PhysicalMovement -FromWalkingAimedRepeat -WalkingAimed -PreflightOnly} 'Repeat transition accepted mixed destination profiles'
Reject {Assert-MineComeWalkingAimedBundle $repeatBundle $profile} 'One-shot profile cannot select repeat bundle'
Reject {Assert-MineComeWalkingAimedBundle $bundle $repeatProfile} 'Repeat profile cannot select one-shot bundle'
foreach($marker in @($true,'2',1,3)){
    $bad=Clone $repeatBundle;$bad.repeat_sessions=$marker
    Reject {Assert-MineComeWalkingAimedBundle $bad $repeatProfile} 'Altered repeat-session limit refused'
}
foreach($field in @('tools_only','walking_aimed','physical_movement','world_clicks','selective_mouse')){
    foreach($value in @($false,0,1,'true',$null)){$bad=Clone $bundle;$bad.$field=$value;Reject {Assert-MineComeWalkingAimedBundle $bad $profile} "Malformed combined marker: $field"}
    $bad=Clone $bundle;$bad.PSObject.Properties.Remove($field);Reject {Assert-MineComeWalkingAimedBundle $bad $profile} "Missing combined marker: $field"
}
foreach($field in @('schema','stream_protocol','ui_input_protocol','mouse_capture_api','selective_revision')){
    foreach($value in @('2',$false,$null,9)){$bad=Clone $bundle;$bad.$field=$value;Reject {Assert-MineComeWalkingAimedBundle $bad $profile} "Malformed combined version: $field"}
}
foreach($change in @(
    {param($b)$b.ui_input_protocol=1}, {param($b)$b.arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini'},
    {param($b)$b.arm_config_relative_path='minecome-hud/addons/MineComeHudSelective.ini'},
    {param($b)$b.runtime.reshade64_sha256='f'*64}, {param($b)$b.runtime.build_receipt_sha256='f'*64},
    {param($b)$b.files[0].sha256='f'*64}, {param($b)$b.files[1].sha256='f'*64}, {param($b)$b.files[2].sha256='f'*64},
    {param($b)$b.files[4]=$b.files[3]}, {param($b)$b.files[1].bytes='20'}, {param($b)$b.files[3].path='../outside'}
)){$bad=Clone $bundle;& $change $bad;Reject {Assert-MineComeWalkingAimedBundle $bad $profile} 'Altered combined artifact accepted'}
Reject {Assert-MineComePhysicalMovementBundle $bundle $walking} 'Combined bundle accepted by original walking profile'
Reject {Assert-MineComeMouseBundle $bundle $r4 -WorldClicks -SelectiveMouse -SelectiveRevision 4} 'Combined bundle accepted by selective r4'
$old=Clone $bundle;$old.PSObject.Properties.Remove('walking_aimed');$old.arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini'
Reject {Assert-MineComeWalkingAimedBundle $old $profile} 'Original walking bundle accepted as combined'
$receipt=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $bundle.files)}
Assert-MineComeWalkingAimedInstalledBundle $bundle $receipt $profile
Check $true 'Exact installed combined bundle accepted'
for($index=0;$index -lt 6;$index++){
    $bad=Clone $receipt;$bad.files[$index].sha256='f'*64;Reject {Assert-MineComeWalkingAimedInstalledBundle $bundle $bad $profile} 'Altered installed file accepted'
    $bad=Clone $receipt;$bad.files[$index].bytes++;Reject {Assert-MineComeWalkingAimedInstalledBundle $bundle $bad $profile} 'Altered installed file size accepted'
}
$ready=[pscustomobject]@{ui_input_walking_aimed=$true;ui_input_protocol=2;ui_input_physical_movement=$true;movement_session='extended';scripted_input=$false
    ui_input_stone_bridge=$true;ui_input_stone_live=$true;ui_input_aimed_stone_bridge=$true;ui_input_live_mouse=$true;ui_input_offscreen_presentation=$true}
Assert-HudWalkingAimedReady $ready $true
Check $true 'Explicit live extended readiness accepted'
foreach($field in @('ui_input_walking_aimed','ui_input_physical_movement','ui_input_stone_bridge','ui_input_stone_live','ui_input_aimed_stone_bridge','ui_input_live_mouse','ui_input_offscreen_presentation')){
    foreach($value in @($false,'true',1,$null)){$bad=Clone $ready;$bad.$field=$value;Reject {Assert-HudWalkingAimedReady $bad $true} "Malformed readiness marker: $field"}
    $bad=Clone $ready;$bad.PSObject.Properties.Remove($field);Reject {Assert-HudWalkingAimedReady $bad $true} "Missing readiness marker: $field"
}
foreach($field in @('ui_walking_aimed_fixture','ui_physical_controller_fixture','ui_ground_movement_fixture','ui_ground_movement_coupled','standalone')){
    $bad=Clone $ready;$bad | Add-Member -NotePropertyName $field -NotePropertyValue $true
    Reject {Assert-HudWalkingAimedReady $bad $true} 'Fixture accepted as live combined readiness'
}
foreach($change in @({param($r)$r.ui_input_protocol=1},{param($r)$r.ui_input_protocol='2'},{param($r)$r.movement_session='short'},{param($r)$r.scripted_input=$true})){
    $bad=Clone $ready;& $change $bad;Reject {Assert-HudWalkingAimedReady $bad $true} 'Wrong input contract accepted'
}
Reject {Assert-HudWalkingAimedReady $ready $false} 'Combined guest accepted by an old controller'
Assert-HudWalkingAimedReady ([pscustomobject]@{ui_input_protocol=2;ui_input_physical_movement=$true}) $false
Check $true 'Existing walking readiness remains accepted by its controller'
foreach($script in @('Update-HudCompositor.ps1','Disable-HudCompositor.ps1')){
    foreach($flag in @('PhysicalMovement','LiveMouse','WorldClicks','SelectiveMouse')){
        $arguments=@{WalkingAimed=$true};$arguments[$flag]=$true
        Reject {& (Join-Path $root ('scripts/'+$script)) @arguments} 'Mixed update/disable profile flags accepted'
    }
}
foreach($flag in @('PhysicalMovement','StoneLive','WorldClicks','SelectiveMouse','AimedStone')){
    $arguments=@{WalkingAimed=$true;InputMode=$true;LiveMouse=$true;OffscreenPresentation=$true};$arguments[$flag]=$true
    Reject {& (Join-Path $root 'scripts/Arm-HudStream.ps1') @arguments} 'Mixed arm profile flags accepted'
}
Write-Output "HUD_WALKING_AIMED_PROFILE_TESTS checks=$script:checks PASS"
