# Immutable two-tile inputs and standalone proof; no KCD calls or movement authority.
function Assert-HudGroundCorridorMode([bool]$Enabled,[bool]$Standalone,[bool]$OtherMode,[string]$File,[bool]$Coupled=$false,[string]$Trace='',[bool]$WalkOnly=$false){
    if($WalkOnly -and -not $Coupled){throw 'Walk-only corridor requires the explicit coupled profile.'}
    if(($Enabled -and $Coupled) -or (($Enabled -or $Coupled) -and (-not $Standalone -or $OtherMode))){throw 'Corridor requires exactly one separate standalone HUD mode.'}
    if(-not ($Enabled -or $Coupled) -and $File){throw 'Corridor file requires an explicit corridor mode.'}
    if($Coupled -and (-not $File -or -not $Trace)){throw 'Coupled corridor requires a captured manifest and new movement trace.'}
    if($Enabled -and $Trace){throw 'Standalone corridor fixture cannot emit a follower trace.'}
}
function Get-HudCorridorHash([byte[]]$Bytes){
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function New-HudGroundCorridorFixture([string]$Run){
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'A fresh HUD run is required.'}
    $tiles=foreach($offset in @(0,4)){
        $points=for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){
            $dx=$col-4+$offset;$dy=$row-4
            $length=[Math]::Sqrt(1+.02*.02+.01*.01)
            [ordered]@{index=1+$row*9+$col;x=120+$dx;y=2040+$dy;z=56+.02*$dx+.01*$dy;nx=-.02/$length;ny=-.01/$length;nz=1/$length;valid=$true;result='hit'}
        }}
        $tile=[ordered]@{schema=1;run=$Run;grid_size=9;walking_area='wide';spacing=1;center=[ordered]@{x=120+$offset;y=2040;z=56};point_count=81;valid_count=81;stable_player=$true;points=@($points);provenance=[ordered]@{kind='standalone_fixture'}}
        $json=$tile | ConvertTo-Json -Depth 8 -Compress
        [ordered]@{sha256=Get-HudCorridorHash ([Text.Encoding]::UTF8.GetBytes($json));json=$json}
    }
    return [ordered]@{schema=1;kind='minecome_ground_corridor_v1';run=$Run;tiles=@($tiles)}
}
function Read-HudGroundCorridorInput([string]$Path,[string]$Root,[bool]$Captured){
    $full=Resolve-HudMovementEvidencePath $Path $Root
    $item=Get-Item -LiteralPath $full
    if($item.Length -lt 2 -or $item.Length -gt 192KB){throw 'Corridor exceeds its bounded input size.'}
    $bytes=[IO.File]::ReadAllBytes($full)
    $data=[Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json -Depth 12
    if($data.schema -ne 1 -or $data.kind -cne 'minecome_ground_corridor_v1' -or $data.run -cnotmatch '^[0-9a-f]{32}$' -or @($data.tiles).Count -ne 2){throw 'Expected one immutable two-tile corridor.'}
    $source=if($Captured){'live_kcd_ground_patch'}else{'standalone_fixture'}
    $parsed=@();$hashes=@()
    foreach($tile in $data.tiles){
        if($tile.json -isnot [string] -or $tile.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid raw corridor tile.'}
        $raw=[Text.Encoding]::UTF8.GetBytes($tile.json)
        if($raw.Length -gt 64KB -or (Get-HudCorridorHash $raw) -cne $tile.sha256){throw 'Corridor tile bytes differ from hash.'}
        $p=$tile.json | ConvertFrom-Json -Depth 12
        if($p.run -cne $data.run -or $p.provenance.kind -cne $source -or $p.grid_size -ne 9 -or $p.walking_area -cne 'wide' -or $p.stable_player -isnot [bool] -or -not $p.stable_player){throw 'Corridor tile provenance or capture identity differs.'}
        $parsed+=,$p;$hashes+=$tile.sha256
    }
    $hash=Get-HudCorridorHash $bytes
    if($Captured){
        $directory=Split-Path -Parent $full
        $record=Read-HudMovementJson (Join-Path $directory 'verification.json')
        $receipt=Read-HudMovementJson (Join-Path $directory 'receipt.json')
        $snapshot=Join-Path $directory 'ground_corridor.lua'
        $sourceHash=(Get-FileHash -LiteralPath (Join-Path $Root 'kcd2/probes/ground_corridor.lua')).Hash.ToLowerInvariant()
        $inventory=Get-Content -LiteralPath (Join-Path $Root 'runtime/environment.json') -Raw | ConvertFrom-Json
        $tools=@($inventory.steam.relevant_apps | Where-Object {$_.role -ceq 'official_tools' -and $_.installed -and $_.distribution -ceq 'Steam' -and $_.app_id -eq '2429020'})
        if($tools.Count -ne 1){throw 'One pinned tools installation is required for capture provenance.'}
        $exe=Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe'
        $pin=@($tools[0].binaries | Where-Object {$_.path -ieq $exe})
        if($pin.Count -ne 1 -or $record.kind -cne 'minecome_ground_corridor_capture_v1' -or $record.result -cne 'passed' -or
            $record.run -cne $data.run -or $record.manifest_sha256 -cne $hash -or $record.player_unchanged -isnot [bool] -or -not $record.player_unchanged -or
            $record.source_sha256 -cne $sourceHash -or (Get-FileHash -LiteralPath $snapshot).Hash.ToLowerInvariant() -cne $sourceHash -or
            $record.game_path -ine $exe -or $record.game_sha256 -cne ([string]$pin[0].sha256).ToLowerInvariant() -or
            (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $record.game_sha256 -or
            $receipt.run -cne $data.run -or $receipt.result -cne 'sampled' -or
            (@($record.tile_hashes) -join ',') -cne ($hashes -join ',')){throw 'Captured corridor lacks matching pinned-engine evidence.'}
        foreach($axis in @('x','y','z')){if($record.anchor.$axis -ne $parsed[0].center.$axis){throw 'Capture anchor differs from the first tile.'}}
    }
    return [pscustomobject]@{Path=$full;Hash=$hash;Run=$data.run;TileHashes=$hashes;Anchor=$parsed[0].center;Captured=$Captured}
}
function Read-HudLiveGroundCorridor([string]$Path,[string]$Root,$Context){
    $corridor=Read-HudGroundCorridorInput $Path $Root $true
    $record=Read-HudMovementJson (Join-Path (Split-Path -Parent $corridor.Path) 'verification.json')
    if($record.game_pid -ne $Context.GamePid -or
        [string]$record.game_start_filetime -cne $Context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture) -or
        $record.game_path -ine $Context.GamePath -or $record.game_sha256 -ine $Context.GameHash -or
        $record.function_reload_verified -isnot [bool] -or -not $record.function_reload_verified){throw 'Corridor capture does not belong to this exact running KCD process.'}
    return $corridor
}
function Assert-HudGroundCorridorMarker($Receipt,[bool]$Expected,[bool]$Coupled=$false,[bool]$WalkOnly=$false){
    if($WalkOnly -and -not $Coupled){throw 'Walk-only marker requires coupled corridor.'}
    $field=$Receipt.PSObject.Properties['ui_ground_corridor_fixture']
    if($Expected){
        if($null -eq $field -or $field.Value -isnot [bool] -or -not $field.Value -or $Receipt.standalone -isnot [bool] -or -not $Receipt.standalone){throw 'Explicit standalone corridor marker missing.'}
    }elseif($field){throw 'Unrequested corridor marker.'}
    $coupledField=$Receipt.PSObject.Properties['ui_ground_corridor_coupled']
    if($Coupled){
        if($Expected -or $null -eq $coupledField -or $coupledField.Value -isnot [bool] -or -not $coupledField.Value -or
            $Receipt.standalone -isnot [bool] -or -not $Receipt.standalone -or $Receipt.walking_area -cne 'corridor'){throw 'Explicit coupled corridor marker missing.'}
    }elseif($coupledField){throw 'Unrequested coupled corridor marker.'}
    $walkField=$Receipt.PSObject.Properties['corridor_walk_only']
    if($WalkOnly){if($null -eq $walkField -or $walkField.Value -isnot [bool] -or -not $walkField.Value){throw 'Explicit walk-only corridor marker missing.'}}
    elseif($walkField){throw 'Unrequested walk-only corridor marker.'}
    if($Expected -or $Coupled){
        foreach($name in @('ui_ground_movement_fixture','ui_ground_movement_coupled')){if($Receipt.PSObject.Properties[$name]){throw 'Legacy ground marker cannot authorize a corridor.'}}
    }
}
function Assert-HudGroundCorridorProof($Guest,[string]$Run,$Corridor,[switch]$Coupled,[string]$TraceFile,[switch]$WalkOnly){
    function Flag($Object,[string]$Field,[bool]$Expected){if($Object.$Field -isnot [bool] -or $Object.$Field -ne $Expected){throw "Corridor boolean differs: $Field"}}
    function Number($Object,[string]$Field,[double]$Minimum,[double]$Maximum){
        $v=$Object.$Field
        if(($v -isnot [int] -and $v -isnot [long] -and $v -isnot [double] -and $v -isnot [decimal]) -or -not [double]::IsFinite([double]$v) -or $v -lt $Minimum -or $v -gt $Maximum){throw "Corridor numeric proof differs: $Field"}
    }
    Assert-HudGroundCorridorMarker $Guest (-not $Coupled) ([bool]$Coupled) ([bool]$WalkOnly)
    $expectedKind=if($WalkOnly){'minecome_hud_ground_corridor_walk_coupled_v1'}elseif($Coupled){'minecome_hud_ground_corridor_coupled_v1'}else{'minecome_hud_ground_corridor_fixture_v1'}
    $p=$Guest.lab_evidence.ground_movement
    $expectedSource=if($Corridor.Captured){'live_kcd_ground_corridor'}else{'standalone_corridor_fixture'}
    if(-not $Corridor.Captured -and $Corridor.Run -cne $Run){throw 'Synthetic corridor requires the same owned HUD run.'}
    if($Guest.run -cne $Run -or $Guest.result -cne 'passed' -or $Guest.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or
        $p.schema -ne 1 -or $p.kind -cne $expectedKind -or $p.phase -cne 'PASSED' -or
        $p.save -cne $Guest.save -or $p.save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        $p.patch_run -cne $Corridor.Run -or $p.patch_sha256 -cne $Corridor.Hash -or $p.ground_source_kind -cne $expectedSource){throw 'Corridor completion identity differs.'}
    foreach($field in @('synthetic_input','client_proxy_released','server_proxy_released','controls_released','approximate_heightfield')){Flag $p $field $true}
    foreach($field in @('client_air','server_air','client_land','server_land')){Flag $p $field (-not $WalkOnly)}
    foreach($field in @('kcd_calls','kcd_movement_applied','physical_input_verified','full_collision_export_verified')){Flag $p $field $false}
    foreach($field in @('client_walk','server_walk')){Number $p $field 5 7}
    foreach($field in @('client_proxy_queries','server_proxy_queries')){Number $p $field 1 ([int]::MaxValue)}
    Number $p 'post_settle_corrections' 0 0
    Number $p.frame_captures 'WALKING' 1 ([int]::MaxValue)
    Number $p.frame_captures 'JUMPING' 0 ([int]::MaxValue)
    Number $p.frame_captures 'LANDING' 0 ([int]::MaxValue)
    if($WalkOnly){if($p.frame_captures.JUMPING+$p.frame_captures.LANDING -ne 0){throw 'Walk-only corridor unexpectedly includes a jump.'}}
    elseif($p.frame_captures.JUMPING+$p.frame_captures.LANDING -lt 1){throw 'No real HUD captured during jump/landing.'}
    $c=$p.corridor
    foreach($axis in @('x','y','z')){if($c.anchor.$axis -ne $Corridor.Anchor.$axis){throw 'Corridor coordinate anchor changed.'}}
    if((@($c.tile_sha256) -join ',') -cne (@($Corridor.TileHashes) -join ',')){throw 'Corridor tile identity changed.'}
    foreach($entry in @{min_x=-4;max_x=8;min_z=-4;max_z=4}.GetEnumerator()){Number $c.bounds $entry.Key $entry.Value $entry.Value}
    Number $c 'original_edge_x' 4 4;Number $c 'crossing_target_x' 5.5 5.5
    foreach($field in @('client_max_x','server_max_x')){Number $c $field 5.5 7.5}
    foreach($field in @('client_return_distance','server_return_distance')){Number $c $field 0 .75}
    Number $c 'max_client_server_distance' 0 1
    foreach($field in @('crossing_hud_frames','return_hud_frames')){Number $c $field 1 ([int]::MaxValue)}
    foreach($field in @('crossed_original_edge','returned_to_start','client_vanilla_cells_air','server_vanilla_cells_air')){Flag $c $field $true}
    Number $c 'slab_count' 96 96;Number $c 'collision_cell_count' 96 192
    if($Coupled){
        if(-not $Corridor.Captured -or -not $TraceFile -or $p.trace_result -cne 'passed' -or $p.trace_file -ine $TraceFile){throw 'Coupled corridor lacks its exact successful real-server trace.'}
        Flag $p 'trace_closed' $true
        if($p.hud_run -cne $Run){throw 'Corridor trace does not bind this HUD run.'}
        Number $p 'trace_records' 3 256
    }
    return $p
}
