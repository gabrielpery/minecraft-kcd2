#Requires -Version 7.3
# Pure receipt validation; extracts the production function without running a controller.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Start-HudInputLab.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudWindowCleanup'},$true)
. ([scriptblock]::Create($function.Extent.Text))
$script:checks=0
function Accept($Visibility,$Hidden,[bool]$Mouse=$true,[bool]$Offscreen=$true,[string]$Mode='Live',[bool]$Exited=$true,[int]$ExitCode=0){
    Assert-HudWindowCleanup $Visibility $Hidden $Mouse $Offscreen $Mode $Exited $ExitCode;$script:checks++
}
function Reject([scriptblock]$Action){
    $rejected=$false;try{& $Action}catch{$rejected=$true}
    if(-not $rejected){throw 'Invalid cleanup proof accepted'};$script:checks++
}
function Fresh {
    return [pscustomobject]@{policy='hidden_until_process_exit';hidden_for_exit=$true;cleanup_succeeded=$true;window_identity_verified=$true;layout_runtime_restore_skipped=$true;layout_options_restored=$true;actual_visible=$false;focus_requested=$false;show_with_focus_disabled=$false;process_exit_observed=$false;expected_window_handle='42';actual_window_handle='42';original_focus_on_show=$true;actual_focus_on_show=$true;original_visible=$true;restored=$false}
}
$hidden=[pscustomobject]@{hide_verified=$true;owned_window_handle='42'}
Accept (Fresh) $hidden
Reject {Accept (Fresh) $hidden $false}
Reject {Accept (Fresh) $hidden $true $false}
Reject {Accept (Fresh) $hidden $true $true 'Fixture'}
Reject {Accept (Fresh) $hidden $true $true 'Live' $false}
Reject {Accept (Fresh) $hidden $true $true 'Live' $true 1}
foreach($field in @('hidden_for_exit','cleanup_succeeded','window_identity_verified','layout_runtime_restore_skipped','layout_options_restored')){
    $proof=Fresh;$proof.$field=$false;Reject {Accept $proof $hidden}
    $proof=Fresh;$proof.$field='true';Reject {Accept $proof $hidden}
    $proof=Fresh;$proof.PSObject.Properties.Remove($field);Reject {Accept $proof $hidden}
}
foreach($field in @('actual_visible','focus_requested','show_with_focus_disabled','process_exit_observed')){
    $proof=Fresh;$proof.$field=$true;Reject {Accept $proof $hidden}
    $proof=Fresh;$proof.$field='false';Reject {Accept $proof $hidden}
}
foreach($field in @('expected_window_handle','actual_window_handle')){
    $proof=Fresh;$proof.$field='43';Reject {Accept $proof $hidden}
    $proof=Fresh;$proof.$field=42;Reject {Accept $proof $hidden}
}
$proof=Fresh;Reject {Accept $proof ([pscustomobject]@{hide_verified=$true;owned_window_handle='0'})}
Reject {Accept (Fresh) ([pscustomobject]@{hide_verified=$false;owned_window_handle='42'})}
$proof=Fresh;$proof.actual_focus_on_show=$false;Reject {Accept $proof $hidden}
$proof=Fresh;$proof.restored=$true;Reject {Accept $proof $hidden}
$proof=Fresh;$proof.original_visible=$false;$proof.restored=$true;Accept $proof $hidden
$proof=Fresh;$proof.policy='unknown';Reject {Accept $proof $hidden}
# Prior normal/fixture receipts remain supported and still require restoration.
$ordinary=[pscustomobject]@{restored=$true;original_visible=$true;actual_visible=$true;original_focus_on_show=$true;actual_focus_on_show=$true;focus_requested=$false}
Accept $ordinary $hidden $false $true 'Fixture'
Accept $ordinary $hidden $false $true 'Live'
$ordinary | Add-Member -NotePropertyName policy -NotePropertyValue 'unknown'
Reject {Accept $ordinary $hidden $false $true 'Fixture'}
$ordinary.policy='restore_original_visibility';Accept $ordinary $hidden $false $true 'Fixture'
$ordinary.PSObject.Properties.Remove('policy')
$ordinary.restored=$false;Reject {Accept $ordinary $hidden $false $true 'Fixture'}
$ordinary.restored=$true;$ordinary.actual_visible=$false;Reject {Accept $ordinary $hidden $false $true 'Live'}
Write-Output "HUD_WINDOW_CLEANUP_RECEIPT_TEST_PASS checks=$script:checks no_game_actions=true"
