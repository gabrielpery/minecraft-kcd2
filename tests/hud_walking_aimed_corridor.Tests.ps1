#Requires -Version 7.3
# Synthetic admission/geometry proofs only. No game, deployment or input calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudWalkingAimed.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudWalkingAimedProfile.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudGroundCorridor.ps1')
$checks=0
function Check($V,[string]$Why){$script:checks++;if(-not $V){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Check $failed $Why}
function Clone($V){$V|ConvertTo-Json -Depth 24|ConvertFrom-Json -Depth 24}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-aimed-corridor-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$run='c'*32
function Input([bool]$Captured=$false,[bool]$Sloped=$false){
    $manifest=New-HudGroundCorridorFixture $run
    foreach($tile in $manifest.tiles){
        $p=$tile.json|ConvertFrom-Json -Depth 12
        if(-not $Sloped){foreach($point in $p.points){$point.z=56}}
        if($Captured){$p.provenance.kind='live_kcd_ground_patch'}
        $tile.json=$p|ConvertTo-Json -Depth 12 -Compress
        $tile.sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($tile.json))
    }
    $path=Join-Path $directory ("$Captured-$Sloped.json")
    [IO.File]::WriteAllText($path,($manifest|ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
    # Deliberately synthetic metadata; this helper never authenticates a host.
    [pscustomobject]@{Path=$path;Hash=(Get-FileHash $path).Hash.ToLowerInvariant();Run=$run;TileHashes=@($manifest.tiles|ForEach-Object sha256);Anchor=[pscustomobject]@{x=120;y=2040;z=56};Captured=$Captured}
}
function Guest($Ground,[bool]$Fixture=$false){
    $seed=@{x=-1;y=64;z=-5};$support=@{x=-1;y=63;z=-5}
    $rows=@(@{target=$seed;client_and_server=$true},@{target=$seed;client_and_server=$true})
    $arena=@{seed=$seed;arena_minimum=@{x=-3;y=62;z=-7};arena_maximum_inclusive=@{x=1;y=66;z=-3};confirmations=$rows;pending=$false;owned_count=0;owned_cells=@();
        build_region=@{patch_run=$Ground.Run;patch_sha256=$Ground.Hash;protected_imported_cells=96;support=$support;support_editable=$false}}
    $movement=@{walking_area='corridor';anchor_mc=@{x=0;y=64;z=0};patch_run=$Ground.Run;patch_sha256=$Ground.Hash;
        ground_source_kind=$(if($Fixture){'standalone_corridor_fixture'}else{'live_kcd_ground_corridor'});
        corridor=@{anchor=$Ground.Anchor;tile_sha256=$Ground.TileHashes;client_vanilla_cells_air=$true;server_vanilla_cells_air=$true}}
    if($Fixture){
        $aimed=@{kind='standalone_hud_walking_aimed_fixture_v1';patch_run=$Ground.Run;patch_sha256=$Ground.Hash;support=$support;seed=$seed;support_selection='corridor_side_perimeter';arena=$arena;confirmations=$rows;
            scripted_input=$true;synthetic_host_rays=$true;completed=$true;support_client_server_prepared=$true;support_client_server_restored_air=$true;imported_cells_unchanged=$true;final_client_server_air=$true;
            kcd_connected=$false;physical_input_verified=$false;support_fixture_setup_writes=1;support_fixture_cleanup_writes=1}
        return Clone @{ui_walking_aimed_fixture=$true;standalone=$true;scripted_input=$true;ui_physical_controller_fixture=$true;ui_input_physical_movement=$false;
            lab_evidence=@{physical_controller_fixture=@{ui_walking_aimed_fixture=$true;physical_movement=$movement;aimed_blocks=$aimed}}}
    }
    Clone @{lab_evidence=@{physical_movement=$movement;stone_bridge=@{arena_offer=@{seed=$seed};arena=$arena;confirmations=$rows;pending=$false;owned_count=0;
        guest_world_cleanup_complete=$true;logical_closed_before_restore=$true;
        build_support=@{patch_run=$Ground.Run;patch_sha256=$Ground.Hash;prepared=$true;cleanup_complete=$true;direct_support_writes=2;failure=$null;
            selection=@{mode='corridor_side_perimeter';support=$support}}}}}
}
try{
    $fixture=Input;$live=Input $true;$slope=Input $false $true
    $geometry=Get-HudWalkingAimedCorridorGeometry $fixture
    Check ($geometry.Cells.Count -eq 96 -and $geometry.Cells.Contains('7,63,-4') -and $geometry.Cells.Contains('0,63,0') -and -not $geometry.Cells.Contains('-1,63,-5')) 'Protected union must cover both tiles and exclude fixed outside support'
    $sloped=Get-HudWalkingAimedCorridorGeometry $slope
    Check ($sloped.Cells.Count -eq 160 -and $sloped.Cells.Contains('7,64,-4') -and $sloped.Cells.Contains('7,63,-4')) 'Partial slabs must protect both intersected vertical cells'
    $proof=Assert-HudWalkingAimedCorridorBuild (Guest $fixture $true) $fixture
    Check ($proof.result -ceq 'passed' -and $proof.standalone_fixture -and $proof.protected_imported_cells -eq 96) 'Explicit fixture geometry proof failed'
    $proof=Assert-HudWalkingAimedCorridorBuild (Guest $live) $live ([pscustomobject]@{x=0;y=64;z=0})
    Check ($proof.result -ceq 'passed' -and -not $proof.standalone_fixture) 'Bound live geometry proof failed'
    Reject {Assert-HudWalkingAimedCorridorBuild (Guest $fixture) $fixture} 'Fixture manifest authorized live proof'
    Reject {Assert-HudWalkingAimedCorridorBuild (Guest $live $true) $live} 'Captured manifest masqueraded as standalone fixture'
    Reject {Assert-HudWalkingAimedCorridorBuild (Guest $live) $live ([pscustomobject]@{x=.01;y=64;z=0})} 'Ready and physical anchors differed'
    foreach($mutate in @(
        {param($g)$g.lab_evidence.stone_bridge.arena.build_region.protected_imported_cells=64},
        {param($g)$g.lab_evidence.stone_bridge.arena.build_region.patch_sha256='f'*64},
        {param($g)$g.lab_evidence.stone_bridge.build_support.cleanup_complete=$false},
        {param($g)$g.lab_evidence.stone_bridge.build_support.direct_support_writes=3},
        {param($g)$g.lab_evidence.stone_bridge.build_support.selection.support.x=0},
        {param($g)$g.lab_evidence.stone_bridge.build_support.selection.mode='host_view_perimeter'},
        {param($g)$g.lab_evidence.stone_bridge.arena_offer.seed.z=-4},
        {param($g)$g.lab_evidence.stone_bridge.arena.build_region.support_editable=$true},
        {param($g)$g.lab_evidence.stone_bridge.confirmations[1].target=[pscustomobject]@{x=-1;y=63;z=-4}},
        {param($g)$g.lab_evidence.stone_bridge.arena.confirmations[1].target=[pscustomobject]@{x=-1;y=63;z=-5}},
        {param($g)$g.lab_evidence.stone_bridge.confirmations[1].target.x=3},
        {param($g)$g.lab_evidence.stone_bridge.arena.arena_minimum.x=-4},
        {param($g)$g.lab_evidence.stone_bridge.logical_closed_before_restore=$false},
        {param($g)$g.lab_evidence.physical_movement.corridor.client_vanilla_cells_air=$false},
        {param($g)$g.lab_evidence.physical_movement.corridor.tile_sha256[1]='f'*64},
        {param($g)$g.lab_evidence.physical_movement.corridor.anchor.x+=4},
        {param($g)$g.lab_evidence.physical_movement.ground_source_kind='live_kcd_ground_patch'}
    )){$g=Guest $live;& $mutate $g;Reject {Assert-HudWalkingAimedCorridorBuild $g $live} 'Malformed or unprotected live geometry passed'}
    $g=Guest $fixture $true;$g.lab_evidence.physical_controller_fixture.aimed_blocks.imported_cells_unchanged=$false
    Reject {Assert-HudWalkingAimedCorridorBuild $g $fixture} 'Fixture imported terrain mutation passed'
    $g=Guest $fixture $true;$g.lab_evidence.physical_controller_fixture.aimed_blocks.support_fixture_cleanup_writes=0
    Reject {Assert-HudWalkingAimedCorridorBuild $g $fixture} 'Fixture support cleanup omitted'
    $bad=Clone $live;$bad.Hash='f'*64;Reject {Get-HudWalkingAimedCorridorGeometry $bad} 'Changed manifest bytes accepted'
    $bad=Clone $live;$bad.TileHashes[1]='f'*64;Reject {Get-HudWalkingAimedCorridorGeometry $bad} 'Changed tile identity accepted'
    $bad=Clone $live;$bad.Anchor.x+=4;Reject {Get-HudWalkingAimedCorridorGeometry $bad} 'Reanchored corridor accepted'
    $context=[pscustomobject]@{GamePid=42;GameStartedUtc=[datetime]'2026-10-29T00:00:00Z'}
    $state=New-HudWalkingAimedAdmission ('a'*32) ('b'*32) $live $context -CorridorWalking
    Check ($state.CorridorWalking -and $state.PatchHash -ceq $live.Hash) 'Corridor admission did not preserve composite identity'
    Reject {New-HudWalkingAimedAdmission ('a'*32) ('b'*32) $fixture $context -CorridorWalking} 'Fixture can grant live corridor admission'
    $ready=Clone @{ui_input_walking_aimed=$true;ui_input_protocol=2;ui_input_physical_movement=$true;movement_session='extended';scripted_input=$false;walking_area='corridor';
        ui_input_stone_bridge=$true;ui_input_stone_live=$true;ui_input_aimed_stone_bridge=$true;ui_input_live_mouse=$true;ui_input_offscreen_presentation=$true;
        ui_input_fixture=$false;ui_input_stone_fixture=$false;ui_input_pointer_fixture=$false;ui_input_delay_fixture=$false;ui_input_background_trial=$false;ui_input_offscreen_trial=$false}
    Assert-HudWalkingAimedReady $ready $true -CorridorWalking;Assert-HudWalkingAimedProducer $ready -CorridorWalking
    Check $true 'Explicit corridor aimed readiness accepted'
    Reject {Assert-HudWalkingAimedReady $ready $true} 'Implicit corridor aimed readiness accepted'
    Reject {Assert-HudWalkingAimedProducer $ready} 'Implicit corridor aimed producer accepted'
    $r=Clone $ready;$r.walking_area='wide';Reject {Assert-HudWalkingAimedProducer $r -CorridorWalking} 'Wide receipt accepted by corridor producer'
    $r=Clone $ready;$r|Add-Member NoteProperty ui_walking_aimed_fixture $true
    Reject {Assert-HudWalkingAimedProducer $r -CorridorWalking} 'Fixture producer granted live corridor input'
    foreach($name in @('Start-HudWalkingAimed.ps1','Test-HudWalkingAimed.ps1')){
        $tokens=$null;$errors=$null;$path=Join-Path $PSScriptRoot "../scripts/$name"
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        Check ($errors.Count -eq 0 -and @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath) -contains 'CorridorWalking') 'Corridor starter/controller parser contract missing'
    }
    "HUD_WALKING_AIMED_CORRIDOR_TESTS_PASS checks=$checks no_game_started=true"
}finally{
    foreach($file in [IO.Directory]::EnumerateFiles($directory)){Remove-Item -LiteralPath $file -Force}
    Remove-Item -LiteralPath $directory -Force
}
