# Explicit physical -> aimed-repeat transition. Pure records; no deployment.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/HudWalkingAimedProfile.ps1')
$path=Join-Path $root 'scripts/Update-HudCompositor.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in @('Assert-Record','Get-MineComeWalkingAimedUpdatePreviousProfile')){
    $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    if(-not $definition){throw "Missing updater function $name"};Invoke-Expression $definition.Extent.Text
}
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12)}
$physical=Get-MineComePhysicalMovementProfile;$aimed=Get-MineComeWalkingAimedProfile
$bundle=[pscustomobject]@{schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;physical_movement=$true;
    stream_protocol=1;ui_input_protocol=2;mouse_capture_api=2;arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini';
    runtime=[pscustomobject]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=$physical.runtime_sha256;build_receipt_sha256=$physical.build_receipt_sha256};
    files=@([pscustomobject]@{path='dxgi.dll';bytes=10;sha256=$physical.runtime_sha256},
        [pscustomobject]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=20;sha256=$physical.addon_sha256},
        [pscustomobject]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=30;sha256=$physical.shader_sha256},
        [pscustomobject]@{path='ReShade.ini';bytes=40;sha256=('a'*64)},
        [pscustomobject]@{path='MineComeHudPreset.ini';bytes=50;sha256=('b'*64)},
        [pscustomobject]@{path='ReShade-LICENSE.txt';bytes=60;sha256=('c'*64)})}
$installed=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $bundle.files)}
Check ((Get-MineComeWalkingAimedUpdatePreviousProfile $bundle $installed $true $true).addon_sha256 -ceq $physical.addon_sha256) 'Explicit physical predecessor retains its frozen pins'
Check ((Get-MineComeWalkingAimedUpdatePreviousProfile $bundle $installed $false $false).addon_sha256 -ceq $physical.addon_sha256) 'Legacy physical-to-one-shot transition is unchanged'
Reject {Get-MineComeWalkingAimedUpdatePreviousProfile $bundle $installed $true $false} 'Default repeat transition must not infer the physical predecessor'
Reject {Get-MineComeWalkingAimedUpdatePreviousProfile $bundle $installed $false $true} 'New predecessor flag requires the repeat destination'
$oldAimed=Clone $bundle
$oldAimed.arm_config_relative_path='minecome-hud/addons/MineComeHudWalkingAimed.ini';$oldAimed.files[1].sha256=$aimed.addon_sha256
foreach($name in @('walking_aimed','world_clicks','selective_mouse')){$oldAimed | Add-Member NoteProperty $name $true}
$oldAimed | Add-Member NoteProperty selective_revision 4
$oldInstalled=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $oldAimed.files)}
Check ((Get-MineComeWalkingAimedUpdatePreviousProfile $oldAimed $oldInstalled $true $false).addon_sha256 -ceq $aimed.addon_sha256) 'Default repeat transition retains one-shot aimed pins'
Reject {Get-MineComeWalkingAimedUpdatePreviousProfile $oldAimed $oldInstalled $true $true} 'Explicit physical transition rejects an aimed predecessor'
for($i=0;$i -lt 6;$i++){
    foreach($field in @('sha256','bytes','path')){
        $bad=Clone $installed
        $bad.files[$i].$field=if($field -ceq 'sha256'){'f'*64}elseif($field -ceq 'bytes'){1}else{'foreign'}
        Reject {Get-MineComeWalkingAimedUpdatePreviousProfile $bundle $bad $true $true} "All six installed $field values remain immutable"
    }
}
foreach($change in @('missing','duplicate','addon','runtime','arm')){
    $bad=Clone $bundle
    switch($change){
        missing {$bad.files=$bad.files[0..4]}
        duplicate {$bad.files[5]=$bad.files[4]}
        addon {$bad.files[1].sha256='f'*64}
        runtime {$bad.runtime.reshade64_sha256='f'*64}
        arm {$bad.arm_config_relative_path='minecome-hud/addons/MineComeHudWalkingRepeat.ini'}
    }
    Reject {Get-MineComeWalkingAimedUpdatePreviousProfile $bad $installed $true $true} "Reject predecessor mutation $change"
}
foreach($arguments in @(
    @{FromPhysicalMovement=$true},
    @{FromPhysicalMovement=$true;WalkingAimed=$true},
    @{FromPhysicalMovement=$true;PhysicalMovement=$true},
    @{FromPhysicalMovement=$true;WalkingAimed=$true;RepeatSession=$true;FromWalkingAimedRepeat=$true},
    @{FromPhysicalMovement=$true;WalkingAimed=$true;RepeatSession=$true;PhysicalMovement=$true}
)){
    $caught=$null;try{& $path @arguments -PreflightOnly | Out-Null}catch{$caught=$_.Exception.Message}
    Check ($null -ne $caught -and ($caught -like '*FromPhysicalMovement*' -or $caught -like '*FromWalkingAimedRepeat*' -or $caught -like '*separate update profile*')) 'Invalid mode combination rejected before reading installed files'
}
Write-Output "Physical-to-aimed-repeat transition: $script:checks pure checks passed; no deployment."
