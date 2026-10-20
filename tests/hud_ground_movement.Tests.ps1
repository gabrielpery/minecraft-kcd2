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
foreach($field in @('standalone','ui_ground_movement_fixture','ui_ground_movement_coupled')){
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

# The live-ground guest remains a standalone receiver, with a separate captured
# patch identity. It must never become an implicit renderer/input mode.
Assert-HudGroundMovementMode $false $true $false $true
Assert-HudGroundMovementPaths $true 'patch.json' 'trace.ndjson'
Assert-HudGroundChildMode $false $true 'patch.json' $false $true 'trace.ndjson'
Reject {Assert-HudGroundMovementMode $true $true $false $true} 'Both movement modes accepted'
Reject {Assert-HudGroundMovementMode $false $false $false $true} 'Coupled guest without standalone accepted'
Reject {Assert-HudGroundMovementMode $false $true $true $true} 'Coupled guest allowed compositor'
Reject {Assert-HudGroundMovementPaths $true '' 'trace.ndjson'} 'Coupled mode allowed missing patch'
Reject {Assert-HudGroundMovementPaths $true 'patch.json' ''} 'Coupled mode allowed missing trace'
Reject {Assert-HudGroundMovementPaths $false 'patch.json' ''} 'Captured patch implicitly enabled coupled mode'
Reject {Assert-HudGroundMovementPaths $false '' 'trace.ndjson'} 'Trace implicitly enabled coupled mode'
Reject {Assert-HudGroundChildMode $true $true 'patch' $false $true 'trace'} 'Both child movement modes accepted'
Reject {Assert-HudGroundChildMode $false $true 'patch' $true $true 'trace'} 'Coupled child combined another lab'
Reject {Assert-HudGroundChildMode $false $true 'patch' $false $true ''} 'Coupled child missing trace accepted'
Reject {Assert-HudGroundChildMode $true $true 'patch' $false $false 'trace'} 'Synthetic fixture gained a follower trace'
$capturedRun='fedcba9876543210fedcba9876543210'
$trace=Join-Path $root 'runtime/evidence/example/movement.ndjson'
function GoodCoupled {
    $value=Good
    $value.PSObject.Properties.Remove('ui_ground_movement_fixture')
    $value | Add-Member ui_ground_movement_coupled $true
    $proof=$value.lab_evidence.ground_movement
    $proof.kind='minecome_hud_ground_movement_coupled_v1'
    $proof.patch_run=$capturedRun;$proof.ground_source_kind='live_kcd_ground_patch'
    $proof | Add-Member hud_run $run
    $proof | Add-Member trace_file $trace
    $proof | Add-Member trace_records 30
    $proof | Add-Member trace_closed $true
    $proof | Add-Member trace_result 'passed'
    return $value
}
$guest=GoodCoupled
$null=Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace
Check $true 'Coupled ground proof binds distinct patch and HUD runs'
Reject {Assert-HudGroundMovementProof $guest $run $hash} 'Coupled result accepted as synthetic fixture'
$guest=Good
Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} 'Fixture result accepted as coupled'
foreach($field in @('hud_run','trace_file','trace_result','ground_source_kind','patch_run')){
    $guest=GoodCoupled;$guest.lab_evidence.ground_movement.$field='different'
    Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} "Coupled proof accepted mismatched $field"
}
foreach($value in @($false,1,'true',$null)){
    $guest=GoodCoupled;$guest.lab_evidence.ground_movement.trace_closed=$value
    Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} 'Incomplete trace close accepted'
}
foreach($value in @(0,3,201,'30',30.5)){
    $guest=GoodCoupled;$guest.lab_evidence.ground_movement.trace_records=$value
    Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} 'Unbounded trace records accepted'
}
$guest=GoodCoupled;$guest | Add-Member ui_ground_movement_fixture $true
Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} 'Both result modes accepted'
$guest=GoodCoupled;$guest.lab_evidence.ground_movement.save='MineCome-HudStream-'+('-'*36)
$guest.save=$guest.lab_evidence.ground_movement.save
Reject {Assert-HudGroundMovementProof $guest $run $hash $true $capturedRun $trace} 'Noncanonical HUD save accepted'

$sourceHash='b'*64
$patchPath=Join-Path $root 'runtime/evidence/capture/ground-patch.json'
$captureClock=[DateTimeOffset]::Parse('2026-10-20T15:00:00Z').ToUnixTimeMilliseconds()
function LiveEvidence {
    $context=[pscustomobject]@{GamePath='C:\test\KingdomCome.exe';GameHash=('c'*64);GamePid=321;GameStartedUtc=([datetime]'2026-10-20T14:00:00Z').ToUniversalTime()}
    $data=[pscustomobject](New-HudGroundMovementPatch $capturedRun)
    $data.provenance=[pscustomobject]@{kind='live_kcd_ground_patch';source_sha256=$sourceHash;game_exe_hash=$context.GameHash;game_pid=321;game_started_utc=$context.GameStartedUtc;captured_utc='2026-10-20T15:00:00Z'}
    $record=[pscustomobject]@{Patch=$true;FunctionReloadVerified=$true;EngineReceiptVerified=$true;Failure=$null;GroundPatchFile=$patchPath;GroundPatchHash=$hash;Run=$capturedRun;SourceHash=$sourceHash;SnapshotHash=$sourceHash;GamePath=$context.GamePath;GameHash=$context.GameHash;GamePid=321;GameStartedUtc=$context.GameStartedUtc}
    $receipt=[pscustomobject]@{run=$capturedRun;result='sampled';stable_player=$true;grid_size=5;spacing=1;point_count=25;valid_count=25;approximate_heightfield=$true;full_collision_export_verified=$false;center=@{x=120;y=2040;z=56}}
    return [pscustomobject]@{Data=$data;Record=$record;Receipt=$receipt;Context=$context}
}
function Assert-Evidence($Value){
    Assert-HudLivePatchEvidence $Value.Data $Value.Record $Value.Receipt $patchPath $hash $sourceHash $sourceHash $Value.Context $captureClock
}
Assert-Evidence (LiveEvidence)
Check $true 'Complete fresh captured patch accepted'
foreach($field in @('Patch','FunctionReloadVerified','EngineReceiptVerified')){
    foreach($value in @($false,1,'true',$null)){
        $case=LiveEvidence;$case.Record.$field=$value
        Reject {Assert-Evidence $case} "Invalid capture Boolean $field accepted"
    }
}
foreach($field in @('GroundPatchFile','GroundPatchHash','Run','SourceHash','SnapshotHash','GamePath','GameHash')){
    $case=LiveEvidence;$case.Record.$field='different'
    Reject {Assert-Evidence $case} "Mismatched captured $field accepted"
}
foreach($field in @('kind','source_sha256','game_exe_hash')){
    $case=LiveEvidence;$case.Data.provenance.$field='different'
    Reject {Assert-Evidence $case} "Wrong live provenance $field accepted"
}
foreach($parent in @('Record','Context')){
    $case=LiveEvidence;$case.$parent.GamePid=123
    Reject {Assert-Evidence $case} 'Different KCD process accepted'
    $case=LiveEvidence;$case.$parent.GameStartedUtc=$case.$parent.GameStartedUtc.AddSeconds(1)
    Reject {Assert-Evidence $case} 'Reused KCD PID accepted'
}
$case=LiveEvidence;$case.Data.provenance.game_pid=123
Reject {Assert-Evidence $case} 'Mismatched patch process accepted'
$case=LiveEvidence;$case.Data.provenance.game_started_utc=$case.Context.GameStartedUtc.AddSeconds(1)
Reject {Assert-Evidence $case} 'Mismatched patch process start accepted'
foreach($stamp in @('2026-10-20T14:56:59Z','2026-10-20T15:00:06Z')){
    $case=LiveEvidence;$case.Data.provenance.captured_utc=$stamp
    Reject {Assert-Evidence $case} 'Stale or future capture accepted'
}
$case=LiveEvidence;$case.Receipt.center.z=57
Reject {Assert-Evidence $case} 'Changed capture centre accepted'
$case=LiveEvidence;$case.Record.Failure='probe failed'
Reject {Assert-Evidence $case} 'Failed capture accepted'
$case=LiveEvidence;$case.Data.points=@()
Reject {Assert-Evidence $case} 'Missing terrain points accepted'
$case=LiveEvidence;$case.Receipt.valid_count=24
Reject {Assert-Evidence $case} 'Incomplete captured terrain accepted'
Reject {Resolve-HudMovementEvidencePath '..\escape' $root} 'Relative output accepted'
Reject {Resolve-HudMovementEvidencePath (Join-Path $root 'minecraft/escaped.ndjson') $root} 'Output outside evidence accepted'
Check ((Resolve-HudMovementEvidencePath $trace $root) -eq $trace) 'Evidence child path accepted'
Write-Output "HUD_GROUND_MOVEMENT_TESTS_PASS checks=$script:checks no_game_calls=true"
