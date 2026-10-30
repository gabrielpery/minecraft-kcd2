#requires -Version 7.3
# Combined corridor capability boundaries only; no process or game calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudPhysicalMovement.ps1')
$checks=0
function Check([bool]$Ok,[string]$Why){$script:checks++;if(-not $Ok){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Why}
$ready=[pscustomobject]@{walking_area='corridor';movement_session='extended';ui_input_protocol=2;ui_input_physical_movement=$true;ui_input_walking_aimed=$true;ui_input_aimed_stone_bridge=$true;scripted_input=$false}
Assert-HudPhysicalMovementReady $ready $true -CorridorWalking -WalkingAimed;Check $true 'Explicit combined producer accepted'
Reject {Assert-HudPhysicalMovementReady $ready $true -CorridorWalking} 'Plain corridor accepted combined capabilities'
Reject {Assert-HudPhysicalMovementReady $ready $true -WalkingAimed} 'Combined profile inferred corridor area'
foreach($name in @('ui_input_walking_aimed','ui_input_aimed_stone_bridge')){
    foreach($value in @($false,1,'true',$null)){
        $bad=$ready | ConvertTo-Json | ConvertFrom-Json;$bad.$name=$value
        Reject {Assert-HudPhysicalMovementReady $bad $true -CorridorWalking -WalkingAimed} 'False or nonboolean combined marker accepted'
    }
}
$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Run-HudStreamClient.ps1'),[ref]$null,[ref]$errors)
Check ($errors.Count -eq 0) 'Child parser failed'
foreach($name in @('Assert-HudCorridorPhysicalChildMode','Assert-HudWalkingAimedChildMode','Assert-HudLateCutoffChildMode')){
    $function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true)
    . ([scriptblock]::Create($function.Extent.Text))
}
Assert-HudCorridorPhysicalChildMode $true $true $false $false $false $true;Check $true 'Live combined corridor selected'
Assert-HudWalkingAimedChildMode $true $true $true $true $false -90 -CorridorWalking;Check $true 'Combined corridor fixture uses eastward crossing'
Reject {Assert-HudCorridorPhysicalChildMode $true $true $true $false $false $true} 'Two live controllers selected'
Reject {Assert-HudCorridorPhysicalChildMode $true $true $false $true $false $true} 'Live and fixture mixed'
Reject {Assert-HudCorridorPhysicalChildMode $true $false $false $false $false $true} 'Short session selected'
Reject {Assert-HudWalkingAimedChildMode $true $true $true $true $false -90} 'Legacy profile accepted corridor yaw'
Reject {Assert-HudWalkingAimedChildMode $true $true $true $true $false 0 -CorridorWalking} 'Corridor fixture missed the X edge'
Assert-HudLateCutoffChildMode $true $true $true $true $true $true $false;Check $true 'Explicit late-cutoff fixture admitted'
for($i=1;$i -le 5;$i++){
    $flags=@($true,$true,$true,$true,$true,$true,$false);$flags[$i]=$false
    Reject {Assert-HudLateCutoffChildMode @flags} 'Incomplete late-cutoff fixture admitted'
}
Reject {Assert-HudLateCutoffChildMode $true $true $true $true $true $true $true} 'Late-cutoff fixture accepted a live/other mode'
Assert-HudLateCutoffChildMode $false $false $false $false $false $false $true;Check $true 'Ordinary modes gained late-cutoff requirements'
Write-Output "HUD_CORRIDOR_AIMED_ENTRY_TESTS_PASS checks=$checks no_game_started=true"
