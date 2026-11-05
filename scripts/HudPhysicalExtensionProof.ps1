# Read-only binding of physical extension evidence to its complete immutable plan.
function Get-HudPhysicalExtensionGeometry($Extension){
    $bytes=[IO.File]::ReadAllBytes($Extension.Path)
    if((Get-HudExtensionHash $bytes) -cne $Extension.Hash){throw 'Physical extension geometry bytes changed.'}
    $data=ConvertFrom-HudGroundExtensionJson ([Text.Encoding]::UTF8.GetString($bytes))
    $tiles=@(foreach($entry in $data.tiles){
        if((Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($entry.json))) -cne $entry.sha256){throw 'Physical extension tile hash differs.'}
        ConvertFrom-HudGroundExtensionJson $entry.json
    })
    Assert-HudGroundExtensionGeometry $data $tiles
    if($data.run -cne $Extension.Run -or (@($data.tiles.sha256) -join ',') -cne (@($Extension.TileHashes) -join ',')){throw 'Physical extension plan identity differs.'}
    $anchor=$tiles[0].center
    foreach($axis in @('x','y','z')){if($anchor.$axis -ne $Extension.Anchor.$axis){throw 'Physical extension origin moved.'}}
    $unique=@{}
    for($tile=0;$tile -lt 3;$tile++){
        foreach($point in $tiles[$tile].points){
            $col=($point.index-1)%9+4*$tile;$row=[int][Math]::Floor(($point.index-1)/9)
            $unique["$col,$row"]=$point
        }
    }
    if($unique.Count -ne 153){throw 'Physical extension point coverage differs.'}
    $cells=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for($row=0;$row -lt 8;$row++){for($col=0;$col -lt 16;$col++){
        $height=($unique["$col,$row"].z+$unique["$($col+1),$row"].z+$unique["$col,$($row+1)"].z+$unique["$($col+1),$($row+1)"].z)/4
        $top=64+$height-$anchor.z;$x=$col-4;$z=3-$row
        for($y=[int][Math]::Floor($top-.5);$y -lt [int][Math]::Ceiling($top);$y++){[void]$cells.Add("$x,$y,$z")}
    }}
    if($cells.Count -lt 128 -or $cells.Count -gt 256){throw 'Physical extension imported-cell coverage differs.'}
    return [pscustomobject]@{Cells=$cells;Anchor=$anchor;Run=$Extension.Run;Hash=$Extension.Hash;InitialHash=$Extension.InitialHash;TileHashes=$Extension.TileHashes}
}
function Assert-HudPhysicalExtensionManifestProof($Guest,$Extension,[switch]$AimedBlocks){
    if($Extension.Captured){throw 'Standalone physical extension requires its normalized fixture manifest.'}
    $geometry=Get-HudPhysicalExtensionGeometry $Extension
    $proof=$Guest.lab_evidence.physical_controller_fixture;$movement=$proof.physical_movement;$handoff=$movement.extension
    if($movement.patch_run -cne $geometry.Run -or $movement.patch_sha256 -cne $geometry.Hash -or
        $movement.ground_source_kind -cne 'standalone_ground_extension_fixture' -or $handoff.initial_sha256 -cne $geometry.InitialHash -or
        (@($handoff.tile_sha256) -join ',') -cne (@($geometry.TileHashes) -join ',') -or $handoff.protected_imported_cells -ne $geometry.Cells.Count){throw 'Physical extension proof uses different geometry or generations.'}
    foreach($axis in @('x','y','z')){if($handoff.anchor.$axis -ne $geometry.Anchor.$axis){throw 'Physical extension proof moved its fixed source origin.'}}
    $mc=$movement.anchor_mc
    if([Math]::Abs($mc.x) -gt .01 -or [Math]::Abs($mc.z) -gt .01 -or $mc.y -lt 57.9 -or $mc.y -gt 67.5){throw 'Physical extension settled origin differs.'}
    if($handoff.handoff_wait_ms -isnot [ValueType] -or $handoff.handoff_wait_ms -is [bool] -or
        -not [double]::IsFinite([double]$handoff.handoff_wait_ms) -or $handoff.handoff_wait_ms -lt 0 -or $handoff.handoff_wait_ms -gt 15000){throw 'Physical extension admission timing differs.'}
    foreach($axis in @('client_max_x','server_max_x')){
        if($handoff.$axis -isnot [ValueType] -or $handoff.$axis -is [bool] -or -not [double]::IsFinite([double]$handoff.$axis) -or $handoff.$axis -lt 8.5 -or $handoff.$axis -gt 11.5){throw 'Physical extension controller did not enter the admitted tile.'}
    }
    if($AimedBlocks){
        $aim=$proof.aimed_blocks;$region=$aim.arena.build_region
        if($region.patch_sha256 -cne $geometry.Hash -or $region.patch_run -cne $geometry.Run -or $region.protected_imported_cells -ne $geometry.Cells.Count){throw 'Physical extension build region does not reserve the complete plan.'}
        $support="-1,$([long][Math]::Floor($mc.y)-1),-5";$seed="-1,$([long][Math]::Floor($mc.y)),-5"
        if("$($aim.support.x),$($aim.support.y),$($aim.support.z)" -cne $support -or "$($aim.seed.x),$($aim.seed.y),$($aim.seed.z)" -cne $seed -or $geometry.Cells.Contains($support) -or $geometry.Cells.Contains($seed)){throw 'Physical extension support is not outside its immutable collision.'}
        foreach($row in @($aim.confirmations)+@($aim.arena.confirmations)){
            $cell="$($row.target.x),$($row.target.y),$($row.target.z)"
            if($geometry.Cells.Contains($cell) -or $cell -ceq $support){throw 'Physical extension action modifies immutable imported collision or support.'}
        }
    }
    return [pscustomobject]@{schema=1;kind='minecome_hud_physical_extension_manifest_proof_v1';result='passed';patch_run=$geometry.Run;
        patch_sha256=$geometry.Hash;initial_sha256=$geometry.InitialHash;tile_sha256=$geometry.TileHashes;anchor=$geometry.Anchor;
        protected_imported_cells=$geometry.Cells.Count;aimed_blocks=[bool]$AimedBlocks;standalone_fixture=$true}
}
