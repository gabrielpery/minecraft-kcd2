#Requires -Version 5.1
# Pure production guard/receipt checks. Never runs the rollback script or queries a game.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){
    $threw=$false;try{& $Action | Out-Null}catch{$threw=$true}
    Check $threw $Message
}
function Clone($Value){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Depth 12)}
function Parse([string]$Relative){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $Relative),[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "Syntax errors in $Relative"
    return $ast
}
function Import-Function($Ast,[string]$Name){
    $node=$Ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name},$true)
    if(-not $node){throw "Missing production function $Name"}
    return [scriptblock]::Create($node.Extent.Text)
}
$disable=Parse 'scripts/Disable-HudCompositor.ps1'
$profileAst=Parse 'scripts/HudPhysicalMovement.ps1'
. (Import-Function $profileAst 'Assert-MineComePhysicalMovementBundle')
. (Import-Function $disable 'Assert-MineComePhysicalMovementRollbackReceipt')
$guards=@()
foreach($statement in $disable.EndBlock.Statements){
    if($statement -is [Management.Automation.Language.IfStatementAst]){$guards+=$statement.Extent.Text}
    elseif($guards.Count){break}
}
Check ($guards.Count -eq 5) 'All initial rollback mode gates must be exercised'
$guard=[scriptblock]::Create($guards -join "`n")
$WalkingAimed=$false;$PhysicalMovement=$true;$LiveMouse=$false;$WorldClicks=$false;$SelectiveMouse=$false;$SelectiveRevision=1
& $guard
Check $true 'Explicit physical rollback accepted'
foreach($field in @('LiveMouse','WorldClicks','SelectiveMouse')){
    Set-Variable -Name $field -Value $true
    Reject {& $guard} "Physical rollback accepted mixed $field profile"
    Set-Variable -Name $field -Value $false
}
foreach($revision in @(2,3,4)){
    $SelectiveRevision=$revision
    Reject {& $guard} 'Physical rollback accepted a selective revision'
}
$SelectiveRevision=1
$defaultNode=$disable.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and
    $n.Extent.Text -match '^if\s*\(\s*-not \$BundleDirectory\)'},$true)
Check ($null -ne $defaultNode) 'Production bundle default found'
$default=[scriptblock]::Create($defaultNode.Extent.Text)
$runtimeRoot=Join-Path $root 'runtime'
$BundleDirectory=$null
. $default
Check ((Split-Path -Leaf $BundleDirectory) -ceq 'hud-compositor-walking') 'Physical default must be the separate walking bundle'
$explicit=Join-Path $runtimeRoot 'explicit-owned-walking'
$BundleDirectory=$explicit
. $default
Check ($BundleDirectory -ceq $explicit) 'Explicit physical bundle was overwritten'
$PhysicalMovement=$false
foreach($mode in @('static','mouse','world','selective1','selective2','selective3','selective4')){
    $LiveMouse=$mode -ne 'static';$WorldClicks=$mode -notin @('static','mouse')
    $SelectiveMouse=$mode.StartsWith('selective');$SelectiveRevision=if($SelectiveMouse){[int]$mode.Substring(9)}else{1}
    & $guard
    Check $true "Legacy $mode gates accepted"
    $BundleDirectory=$null
    . $default
    $expected=switch($mode){
        'static'{'hud-compositor'}
        'mouse'{'hud-compositor-mouse'}
        'world'{'hud-compositor-world'}
        'selective1'{'hud-compositor-selective'}
        default{'hud-compositor-selective-r'+$SelectiveRevision}
    }
    Check ((Split-Path -Leaf $BundleDirectory) -ceq $expected) "Legacy $mode default changed"
}

$profile=[pscustomobject]@{runtime_sha256='a'*64;addon_sha256='b'*64;shader_sha256='c'*64;build_receipt_sha256='d'*64}
$manifest=[pscustomobject]@{
    schema=1;kind='minecome_hud_compositor_bundle_v1';tools_only=$true;physical_movement=$true
    stream_protocol=1;ui_input_protocol=2;mouse_capture_api=2
    arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini'
    runtime=[pscustomobject]@{version='6.8.0';full_addon_support=$true;reshade64_sha256=$profile.runtime_sha256;build_receipt_sha256=$profile.build_receipt_sha256}
    files=@(
        [pscustomobject]@{path='dxgi.dll';bytes=4096;sha256=$profile.runtime_sha256},
        [pscustomobject]@{path='minecome-hud/addons/MineComeHudCompositor.addon64';bytes=2048;sha256=$profile.addon_sha256},
        [pscustomobject]@{path='minecome-hud/shaders/MineComeHud.fx';bytes=512;sha256=$profile.shader_sha256},
        [pscustomobject]@{path='ReShade.ini';bytes=100;sha256='e'*64},
        [pscustomobject]@{path='MineComeHudPreset.ini';bytes=100;sha256='e'*64},
        [pscustomobject]@{path='ReShade-LICENSE.txt';bytes=100;sha256='e'*64}
    )
}
$receipt=[pscustomobject]@{schema=1;kind='minecome_hud_install_v1';files=(Clone $manifest).files}
Assert-MineComePhysicalMovementRollbackReceipt $manifest $receipt $profile
Check $true 'Exact physical installation accepted'
foreach($change in @(
    {param($m,$r)$r.files[1].sha256='f'*64},
    {param($m,$r)$r.files[1].bytes++},
    {param($m,$r)$r.files[5]=$r.files[0]},
    {param($m,$r)$r.files=@($r.files[0..4])},
    {param($m,$r)$r.files+=@($r.files[0])},
    {param($m,$r)$r.schema=2},
    {param($m,$r)$r.kind='another_installation'},
    {param($m,$r)$m.runtime.version='6.8.1'},
    {param($m,$r)$m.runtime.full_addon_support='true'},
    {param($m,$r)$m.ui_input_protocol=1},
    {param($m,$r)$m.physical_movement=$false},
    {param($m,$r)$m | Add-Member -NotePropertyName selective_revision -NotePropertyValue 4},
    {param($m,$r)$m.arm_config_relative_path='minecome-hud/addons/MineComeHudSelective.ini'},
    {param($m,$r)$m.files[3].path='../unexpected';$r.files[3].path='../unexpected'}
)){
    $badManifest=Clone $manifest;$badReceipt=Clone $receipt
    & $change $badManifest $badReceipt
    Reject {Assert-MineComePhysicalMovementRollbackReceipt $badManifest $badReceipt $profile} 'Foreign, mismatched or mixed installation accepted'
}
foreach($badBytes in @(0,-1,67108865,'100',1.5,$null)){
    $badManifest=Clone $manifest;$badReceipt=Clone $receipt
    $badManifest.files[3].bytes=$badBytes;$badReceipt.files[3].bytes=$badBytes
    Reject {Assert-MineComePhysicalMovementRollbackReceipt $badManifest $badReceipt $profile} 'Unbounded/noninteger file size accepted'
}
foreach($badHash in @(('E'*64),('f'*63),('z'*64),$null)){
    $badManifest=Clone $manifest;$badReceipt=Clone $receipt
    $badManifest.files[3].sha256=$badHash;$badReceipt.files[3].sha256=$badHash
    Reject {Assert-MineComePhysicalMovementRollbackReceipt $badManifest $badReceipt $profile} 'Noncanonical file hash accepted'
}
Write-Output "HUD_PHYSICAL_ROLLBACK_PURE_PASS checks=$script:checks game_calls=false rollback_executed=false"
