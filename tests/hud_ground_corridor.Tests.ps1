$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/HudGroundCorridor.ps1')
$checks=0
function Check([bool]$Value,[string]$Message){$script:checks++;if(-not $Value){throw $Message}}
function Reject([scriptblock]$Call,[string]$Message){$failed=$false;try{& $Call | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20}
$directory=Join-Path $root ('runtime/evidence/corridor-proof-fixture-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($directory) | Out-Null
$run='a'*32;$path=Join-Path $directory 'corridor.json'
try{
    $manifest=New-HudGroundCorridorFixture $run
    $manifest | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    $inputRecord=Read-HudGroundCorridorInput $path $root $false
    Check ($inputRecord.Run -ceq $run -and $inputRecord.TileHashes.Count -eq 2 -and $inputRecord.Anchor.x -eq 120) 'Exact synthetic manifest identity'
    $null=Assert-HudGroundCorridorMode $true $true $false ''
    Reject {Assert-HudGroundCorridorMode $true $false $false ''} 'Live controller cannot select corridor'
    Reject {Assert-HudGroundCorridorMode $true $true $true ''} 'Other mode cannot mix with corridor'
    Reject {Assert-HudGroundCorridorMode $false $true $false $path} 'Implicit corridor file rejected'
    Reject {Read-HudGroundCorridorInput $path $root $true} 'Synthetic patch cannot claim capture provenance'
    foreach($change in @('hash','run','provenance')){
        $bad=Clone $manifest
        if($change -eq 'hash'){$bad.tiles[1].sha256='0'*64}
        elseif($change -eq 'run'){$bad.run='b'*32}
        else{$tile=$bad.tiles[0].json | ConvertFrom-Json;$tile.provenance.kind='live_kcd_ground_patch';$bad.tiles[0].json=$tile | ConvertTo-Json -Depth 8 -Compress;$bad.tiles[0].sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($bad.tiles[0].json))}
        $bad | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        Reject {Read-HudGroundCorridorInput $path $root $false} "Reject $change mismatch"
    }
    $save='MineCome-HudStream-11111111-1111-4111-8111-111111111111'
    $proof=[ordered]@{schema=1;kind='minecome_hud_ground_corridor_fixture_v1';save=$save;patch_run=$run;patch_sha256=$inputRecord.Hash;ground_source_kind='standalone_corridor_fixture';phase='PASSED';client_walk=5.2;server_walk=5.2;client_proxy_queries=100;server_proxy_queries=100;post_settle_corrections=0;frame_captures=@{WALKING=4;JUMPING=1;LANDING=4}}
    foreach($field in @('synthetic_input','client_air','server_air','client_land','server_land','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){$proof[$field]=$true}
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')){$proof[$field]=$false}
    $proof.corridor=[ordered]@{anchor=$inputRecord.Anchor;tile_sha256=$inputRecord.TileHashes;bounds=@{min_x=-4;max_x=8;min_z=-4;max_z=4};original_edge_x=4;crossing_target_x=5.5;client_max_x=5.7;server_max_x=5.7;client_return_distance=.1;server_return_distance=.1;max_client_server_distance=.1;crossing_hud_frames=2;return_hud_frames=3;crossed_original_edge=$true;returned_to_start=$true;client_vanilla_cells_air=$true;server_vanilla_cells_air=$true;slab_count=96;collision_cell_count=120}
    $guest=Clone ([ordered]@{run=$run;result='passed';save=$save;source_kind='minecraft_vanilla_ui_stream_v1';ui_ground_corridor_fixture=$true;standalone=$true;lab_evidence=@{ground_movement=$proof}})
    $null=Assert-HudGroundCorridorProof $guest $run $inputRecord
    Check $true 'Complete seam-crossing/return/HUD/cleanup proof accepted'
    foreach($change in @('crossing','return','hud','anchor','hash','cleanup','live','marker','correction','nan')){
        $bad=Clone $guest;$p=$bad.lab_evidence.ground_movement;$c=$p.corridor
        switch($change){
            crossing{$c.server_max_x=4}
            return{$c.client_return_distance=1}
            hud{$c.crossing_hud_frames=0}
            anchor{$c.anchor.z=57}
            hash{$c.tile_sha256[1]='0'*64}
            cleanup{$p.server_proxy_released=$false}
            live{$p.kcd_movement_applied=$true}
            marker{$bad.standalone=$false}
            correction{$p.post_settle_corrections=1}
            nan{$c.max_client_server_distance=[double]::NaN}
        }
        Reject {Assert-HudGroundCorridorProof $bad $run $inputRecord} "Reject $change proof"
    }
    Reject {Assert-HudGroundCorridorMarker $guest $false} 'Unrequested corridor marker rejected'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Run-HudStreamClient.ps1'),[ref]$tokens,[ref]$errors)
    $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudCorridorChildMode'},$true)
    Invoke-Expression $function.Extent.Text
    $null=Assert-HudCorridorChildMode $true $true $path $false
    Reject {Assert-HudCorridorChildMode $true $true $path $true} 'Child rejects live or mixed mode'
    Reject {Assert-HudCorridorChildMode $true $true '' $false} 'Child requires immutable manifest'
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Arm-HudStream.ps1'),[ref]$tokens,[ref]$errors)
    $function=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-HudNonFixtureArm'},$true)
    Invoke-Expression $function.Extent.Text
    Reject {Assert-HudNonFixtureArm ([pscustomobject]@{ui_ground_corridor_fixture=$true;standalone=$false})} 'Corridor cannot arm live composition even with malformed standalone flag'
    Write-Output "HUD_GROUND_CORRIDOR_TESTS_PASS checks=$checks no_game_started=true"
}finally{
    $resolved=[IO.Path]::GetFullPath($directory)
    $allowed=[IO.Path]::GetFullPath((Join-Path $root 'runtime/evidence'))+[IO.Path]::DirectorySeparatorChar
    if($resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('corridor-proof-fixture-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
