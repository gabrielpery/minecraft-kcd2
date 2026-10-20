#Requires -Version 7.3
# Mode/provenance regressions without a game, renderer arm or process launch.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action | Out-Null}catch{$threw=$true};Check $threw $Message}
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
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
$arm=Parse 'scripts/Arm-HudStream.ps1'
$child=Parse 'scripts/Run-HudStreamClient.ps1'
$null=Parse 'scripts/HudGroundMovement.ps1'
$null=Parse 'scripts/Start-HudStreamLab.ps1'
$null=Parse 'scripts/Start-HudGroundMovementLab.ps1'
. (Import-Function $arm 'Assert-HudNonFixtureArm')
. (Import-Function $child 'Assert-HudGroundChildMode')
Assert-HudGroundMovementMode $true $true $false
Assert-HudGroundMovementMode $false $false $true
Reject {Assert-HudGroundMovementMode $true $false $false} 'Missing standalone mode accepted'
Reject {Assert-HudGroundMovementMode $true $true $true} 'Fixture accepted KCD composition'
Assert-HudGroundChildMode $true $true 'owned.json' $false
Assert-HudGroundChildMode $false $false '' $true
Reject {Assert-HudGroundChildMode $true $false 'owned.json' $false} 'Child accepted live target'
Reject {Assert-HudGroundChildMode $true $true '' $false} 'Child accepted missing patch'
Reject {Assert-HudGroundChildMode $true $true 'owned.json' $true} 'Child accepted another input/stone mode'
Reject {Assert-HudGroundChildMode $false $true 'owned.json' $false} 'Child accepted implicit movement'
foreach($field in @('standalone','ui_ground_movement_fixture')){
    foreach($value in @($true,1,'false',$null)){
        $receipt=[pscustomobject]@{};$receipt | Add-Member -NotePropertyName $field -NotePropertyValue $value
        Reject {Assert-HudNonFixtureArm $receipt} "Live arm accepted fixture/malformed $field"
    }
}
Assert-HudNonFixtureArm ([pscustomobject]@{})
Assert-HudNonFixtureArm ([pscustomobject]@{standalone=$false;ui_ground_movement_fixture=$false})
Check $true 'Legacy live readiness still accepted'
$run='0123456789abcdef0123456789abcdef'
$hash='a'*64
$patch=New-HudGroundMovementPatch $run
Check ($patch.provenance.kind -ceq 'standalone_fixture' -and $patch.points.Count -eq 25) 'Patch provenance/count'
Check (@($patch.points | Where-Object {$_.z -ne 56 -or $_.nz -ne 1 -or $_.run -cne $run}).Count -eq 0) 'Flat bounded fixture geometry'
Reject {New-HudGroundMovementPatch '../invalid'} 'Invalid fixture run accepted'
function Good {
    [pscustomobject]@{
        run=$run;result='passed';save='MineCome-HudStream-01234567-89ab-cdef-0123-456789abcdef'
        standalone=$true;ui_ground_movement_fixture=$true
        lab_evidence=[pscustomobject]@{ground_movement=[pscustomobject]@{
            schema=1;kind='minecome_hud_ground_movement_fixture_v1';save='MineCome-HudStream-01234567-89ab-cdef-0123-456789abcdef'
            patch_run=$run;patch_sha256=$hash;ground_source_kind='standalone_fixture';phase='PASSED'
            synthetic_input=$true;kcd_calls=$false;kcd_movement_applied=$false;physical_input_verified=$false
            client_walk=0.6;server_walk=0.6;client_air=$true;server_air=$true;client_land=$true;server_land=$true
            client_proxy_queries=40;server_proxy_queries=40;post_settle_corrections=0
            client_proxy_released=$true;server_proxy_released=$true;controls_released=$true
            frame_captures=[pscustomobject]@{WALKING=3;JUMPING=0;LANDING=5}
            approximate_heightfield=$true;full_collision_export_verified=$false
        }}
    }
}
$guest=Good;$proof=Assert-HudGroundMovementProof $guest $run $hash
Check ($proof.phase -ceq 'PASSED') 'Complete shared-world proof accepted'
$guest=Good;$guest.lab_evidence.ground_movement.frame_captures.LANDING=0;$guest.lab_evidence.ground_movement.frame_captures.JUMPING=1
$null=Assert-HudGroundMovementProof $guest $run $hash
Check $true 'Either jump or landing capture establishes airborne-phase stream overlap'
foreach($field in @('standalone','ui_ground_movement_fixture')){
    $guest=Good;$guest.$field=$false
    Reject {Assert-HudGroundMovementProof $guest $run $hash} "Fixture proof accepted false $field"
    $guest=Good;$guest.PSObject.Properties.Remove($field)
    Reject {Assert-HudGroundMovementProof $guest $run $hash} "Fixture proof accepted missing $field"
}
foreach($field in @('synthetic_input','client_air','server_air','client_land','server_land','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){
    $guest=Good;$guest.lab_evidence.ground_movement.$field=$false
    Reject {Assert-HudGroundMovementProof $guest $run $hash} "Incomplete $field accepted"
}
foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')){
    $guest=Good;$guest.lab_evidence.ground_movement.$field=$true
    Reject {Assert-HudGroundMovementProof $guest $run $hash} "Overclaim $field accepted"
}
foreach($field in @('client_walk','server_walk')){
    foreach($value in @(0.29,5,[double]::NaN,'0.6',$null)){
        $guest=Good;$guest.lab_evidence.ground_movement.$field=$value
        Reject {Assert-HudGroundMovementProof $guest $run $hash} "Invalid $field accepted"
    }
}
foreach($field in @('client_proxy_queries','server_proxy_queries')){
    $guest=Good;$guest.lab_evidence.ground_movement.$field=0
    Reject {Assert-HudGroundMovementProof $guest $run $hash} 'No collision queries accepted'
}
foreach($field in @('patch_run','patch_sha256','save','ground_source_kind','phase')){
    $guest=Good;$guest.lab_evidence.ground_movement.$field='different'
    Reject {Assert-HudGroundMovementProof $guest $run $hash} "Wrong $field accepted"
}
$guest=Good;$guest.lab_evidence.ground_movement.post_settle_corrections=1
Reject {Assert-HudGroundMovementProof $guest $run $hash} 'Position correction accepted'
$guest=Good;$guest.lab_evidence.ground_movement.frame_captures.WALKING=0
Reject {Assert-HudGroundMovementProof $guest $run $hash} 'Missing walk capture accepted'
$guest=Good;$guest.lab_evidence.ground_movement.frame_captures.LANDING=0
Reject {Assert-HudGroundMovementProof $guest $run $hash} 'Missing jump and landing captures accepted'
Write-Output "HUD_GROUND_MOVEMENT_TESTS_PASS checks=$script:checks no_game_calls=true"
