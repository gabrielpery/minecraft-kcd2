#Requires -Version 5.1
# Exercise the exact profile split and mode guards without deploying or accessing a game.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudMouseProfile.ps1')
$script:checks=0
$AimedStone=$false
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
function Parse-Script([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Invalid syntax: $Relative"
    return $ast
}
$profile=[pscustomobject]@{runtime_sha256=('a'*64);addon_sha256=('b'*64);shader_sha256=('c'*64);build_receipt_sha256=('d'*64)}
function New-Manifest([bool]$World=$true){
    $value=[ordered]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;mouse_capture_api=1;stream_protocol=1;ui_input_protocol=1
        arm_config_relative_path=$(if($World){'minecome-hud/addons/MineComeHudWorld.ini'}else{'minecome-hud/addons/MineComeHudMouse.ini'})
        runtime=[ordered]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=('a'*64);build_receipt_sha256=('d'*64)}
        files=@([ordered]@{path='dxgi.dll';bytes=10;sha256=('a'*64)},[ordered]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=20;sha256=('b'*64)},[ordered]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=30;sha256=('c'*64)})}
    foreach($path in @('ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt')){$value.files+=@([ordered]@{path=$path;bytes=40;sha256=('e'*64)})}
    if($World){$value.world_clicks=$true}
    return $value
}
function New-Receipt($Manifest){[ordered]@{schema=1;kind='minecome_hud_install_v1';files=@($Manifest.files|ForEach-Object{[ordered]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})}}
foreach($json in @($false,$true)){
    $world=New-Manifest;$mouse=New-Manifest $false
    if($json){$world=$world|ConvertTo-Json -Depth 8|ConvertFrom-Json;$mouse=$mouse|ConvertTo-Json -Depth 8|ConvertFrom-Json}
    Assert-MineComeMouseBundle $world $profile -WorldClicks;Check $true 'Explicit world profile accepted'
    Assert-MineComeMouseBundle $mouse $profile;Check $true 'Frozen mouse profile remains accepted'
    Reject {Assert-MineComeMouseBundle $world $profile} 'World profile accepted as mouse'
    Reject {Assert-MineComeMouseBundle $mouse $profile -WorldClicks} 'Mouse profile accepted as world'
    Assert-MineComeMouseInstalledBundle $mouse (New-Receipt $mouse) $profile;Check $true 'Exact owned previous mouse installation accepted'
    Assert-MineComeMouseInstalledBundle $world (New-Receipt $world) $profile -WorldClicks;Check $true 'Exact owned world installation accepted'
}
foreach($invalid in @($false,'true','false',0,1,$null)){
    $manifest=New-Manifest;$manifest.world_clicks=$invalid
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks} 'Non-true Boolean world marker accepted'
    Reject {Assert-MineComeMouseBundle $manifest $profile} 'World marker accepted in mouse mode'
}
$manifest=New-Manifest;$manifest.Remove('world_clicks');Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks} 'Missing world marker accepted'
foreach($field in @('mouse_capture_api','stream_protocol','ui_input_protocol')){
    $manifest=New-Manifest;$manifest[$field]=2;Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks} "Changed $field accepted"
    $manifest=New-Manifest;$manifest.Remove($field);Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks} "Missing $field accepted"
}
foreach($path in @('MineComeHud.ini','MineComeHudStream.ini','MineComeHudInput.ini','MineComeHudMouse.ini','MineComeHudWORLD.ini')){
    $manifest=New-Manifest;$manifest.arm_config_relative_path='minecome-hud/addons/'+$path
    Reject {Assert-MineComeMouseBundle $manifest $profile -WorldClicks} 'Foreign world arm path accepted'
}
foreach($field in @('runtime_sha256','addon_sha256','shader_sha256','build_receipt_sha256')){
    $foreign=[pscustomobject]@{runtime_sha256=('a'*64);addon_sha256=('b'*64);shader_sha256=('c'*64);build_receipt_sha256=('d'*64)};$foreign.$field='f'*64
    Reject {Assert-MineComeMouseBundle (New-Manifest) $foreign -WorldClicks} 'Foreign exact profile accepted'
}
for($i=0;$i -lt 6;$i++){
    foreach($field in @('sha256','bytes','path')){
        $manifest=New-Manifest $false;$receipt=New-Receipt $manifest
        $receipt.files[$i][$field]=$(if($field -eq 'bytes'){123}else{'changed'})
        Reject {Assert-MineComeMouseInstalledBundle $manifest $receipt $profile} 'Changed previous owned record accepted'
    }
    $manifest=New-Manifest $false;$receipt=New-Receipt $manifest;$receipt.files[$i]=$receipt.files[($i+1)%6]
    Reject {Assert-MineComeMouseInstalledBundle $manifest $receipt $profile} 'Duplicate/missing previous owned path accepted'
}
foreach($field in @('schema','kind','tools_only')){
    $manifest=New-Manifest $false;$receipt=New-Receipt $manifest;$manifest[$field]=$null
    Reject {Assert-MineComeMouseInstalledBundle $manifest $receipt $profile} 'Invalid previous manifest accepted'
}
$manifest=New-Manifest $false;$receipt=New-Receipt $manifest;$receipt.files=@($receipt.files[0..4]);Reject {Assert-MineComeMouseInstalledBundle $manifest $receipt $profile} 'Incomplete previous installation accepted'
$manifest=New-Manifest;$receipt=New-Receipt $manifest;Reject {Assert-MineComeMouseInstalledBundle $manifest $receipt $profile} 'Prior world installation accepted as frozen mouse'

$arm=Parse-Script 'scripts/Arm-HudStream.ps1'
$update=Parse-Script 'scripts/Update-HudCompositor.ps1'
$prepare=Parse-Script 'scripts/Prepare-HudCompositor.ps1'
$disable=Parse-Script 'scripts/Disable-HudCompositor.ps1'
$archive=Parse-Script 'scripts/Archive-HudArm.ps1'
$null=Parse-Script 'scripts/HudMouseProfile.ps1'
foreach($ast in @($arm,$update,$disable)){
    Check (@($ast.ParamBlock.Parameters|Where-Object{$_.Name.VariablePath.UserPath -eq 'WorldClicks'}).Count -eq 1) 'Explicit world option is available'
}
# Execute only the initial, pure guards. Stop before the first dot-source or
# assignment to a project path, so no helper discovery or game access occurs.
# The pure protocol selection between mode guards is deliberately not executed.
$guardText=@()
foreach($statement in $arm.EndBlock.Statements){
    if($statement -is [Management.Automation.Language.IfStatementAst]){$guardText+=$statement.Extent.Text}
    elseif($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -ceq '$inputProtocol'){continue}
    elseif($guardText.Count){break}
}
Check ($guardText.Count -eq 8) 'All arm configuration guards isolated'
$PhysicalMovement=$false
$SelectiveMouse=$false
$SelectiveRevision=1
$guards=[scriptblock]::Create($guardText -join "`n")
foreach($inputEnabled in @($false,$true)){
    foreach($offscreen in @($false,$true)){
        foreach($mouse in @($false,$true)){
            foreach($stone in @($false,$true)){
                $InputMode=$inputEnabled;$OffscreenPresentation=$offscreen;$LiveMouse=$mouse;$StoneLive=$stone;$WorldClicks=$true
                if($inputEnabled -and $offscreen -and $mouse -and $stone){& $guards;Check $true 'Full world arming configuration accepted'}
                else{Reject {& $guards} 'Partial world arming configuration accepted'}
            }
        }
    }
}
$updateGuard=$update.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith('if($WorldClicks ')}|Select-Object -First 1
$WorldClicks=$true;$LiveMouse=$false;Reject {& ([scriptblock]::Create($updateGuard.Extent.Text))} 'World update accepted without mouse mode'
$LiveMouse=$true;& ([scriptblock]::Create($updateGuard.Extent.Text));Check $true 'Explicit world update accepted'
$disableGuard=$disable.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.IfStatementAst] -and $_.Extent.Text.StartsWith('if($WorldClicks ')}|Select-Object -First 1
$LiveMouse=$false;Reject {& ([scriptblock]::Create($disableGuard.Extent.Text))} 'World rollback accepted without mouse mode'
$LiveMouse=$true;& ([scriptblock]::Create($disableGuard.Extent.Text));Check $true 'Explicit world rollback accepted'
foreach($ast in @($arm,$update,$archive)){
    Check ($ast.Extent.Text.Contains("'MineComeHudWorld.ini'")) 'World arm included in ownership/conflict enumeration'
}
$mode=$prepare.ParamBlock.Parameters|Where-Object{$_.Name.VariablePath.UserPath -eq 'Mode'}
Check ($mode.Extent.Text.Contains("'World'")) 'World staging mode available'
$mouseProfile=Get-MineComeMouseProfile
Check ($mouseProfile.addon_sha256 -ceq 'e947533ec27e70a4782fa3c4e40df4d2fc69d85b00d768393bd1c43345fb34ca') 'Working mouse add-on hash preserved'
$worldProfile=Get-MineComeMouseProfile -WorldClicks
Check ($worldProfile.kind -ceq 'minecome_hud_world_profile_v1' -and $worldProfile.addon_sha256 -cne $mouseProfile.addon_sha256) 'New world add-on is separately frozen'
foreach($field in @('runtime_sha256','shader_sha256','build_receipt_sha256','patch_sha256','api_sha256')){
    Check ($worldProfile.$field -ceq $mouseProfile.$field) 'World profile retains exact verified API1 proxy and shader provenance'
}
Write-Output "HUD_WORLD_PROFILE_TEST_PASS checks=$checks no_game=true deployment=false"
