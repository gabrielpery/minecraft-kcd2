# Immutable three-tile extension plan; no game calls or movement authority.
function Get-HudExtensionHash([byte[]]$Bytes){
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function New-HudGroundExtensionFixture([string]$Run){
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'A fresh HUD run is required.'}
    $tiles=foreach($offset in @(0,4,8)){
        $points=for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){
            $dx=$col-4+$offset;$dy=$row-4
            $length=[Math]::Sqrt(1+.02*.02+.01*.01)
            [ordered]@{index=1+$row*9+$col;x=120+$dx;y=2040+$dy;z=56+.02*$dx+.01*$dy;nx=-.02/$length;ny=-.01/$length;nz=1/$length;valid=$true;result='hit'}
        }}
        $tile=[ordered]@{schema=1;run=$Run;grid_size=9;walking_area='wide';spacing=1;center=[ordered]@{x=120+$offset;y=2040;z=56};point_count=81;valid_count=81;stable_player=$true;points=@($points);provenance=[ordered]@{kind='standalone_fixture'}}
        $json=$tile | ConvertTo-Json -Depth 8 -Compress
        [ordered]@{sha256=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($json));json=$json}
    }
    return [ordered]@{schema=1;kind='minecome_ground_extension_v1';run=$Run;tiles=@($tiles)}
}
function ConvertFrom-HudGroundExtensionJson([string]$Json){
    # ConvertFrom-Json otherwise accepts duplicate object members; validate the
    # structure before conversion so a hash cannot hide two different meanings.
    $options=[Text.Json.JsonDocumentOptions]::new();$options.MaxDepth=12
    $document=[Text.Json.JsonDocument]::Parse($Json,$options)
    function UniqueMembers($Element){
        if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
            $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($property in $Element.EnumerateObject()){
                if(-not $names.Add($property.Name)){throw 'Duplicate extension JSON field.'}
                UniqueMembers $property.Value
            }
        }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){
            foreach($entry in $Element.EnumerateArray()){UniqueMembers $entry}
        }
    }
    try{UniqueMembers $document.RootElement;return ConvertFrom-Json -InputObject $Json -Depth 12}
    finally{$document.Dispose()}
}
function Assert-HudGroundExtensionGeometry($Data,[object[]]$Tiles){
    function Number($Value){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or -not [double]::IsFinite([double]$Value)){throw 'Invalid extension number.'}
        return [double]$Value
    }
    if(($Data.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',' -cne 'kind,run,schema,tiles'){throw 'Unknown or missing extension manifest fields.'}
    if((Number $Data.schema) -ne 1 -or $Tiles.Count -ne 3){throw 'Invalid extension schema or tile count.'}
    $anchor=$Tiles[0].center
    foreach($axis in @('x','y','z')){if([Math]::Abs((Number $anchor.$axis)) -gt 9999988){throw 'Extension origin outside bounds.'}}
    for($tile=0;$tile -lt 3;$tile++){
        $p=$Tiles[$tile]
        if((Number $p.schema) -ne 1 -or (Number $p.grid_size) -ne 9 -or (Number $p.spacing) -ne 1 -or (Number $p.point_count) -ne 81 -or (Number $p.valid_count) -ne 81 -or @($p.points).Count -ne 81){throw 'Incomplete extension tile.'}
        if((Number $p.center.x) -ne $anchor.x+4*$tile -or (Number $p.center.y) -ne $anchor.y -or (Number $p.center.z) -ne $anchor.z){throw 'Extension tile moved the shared origin.'}
        for($i=0;$i -lt 81;$i++){
            $point=$p.points[$i];$row=[Math]::Floor($i/9);$col=$i%9
            if((Number $point.index) -ne $i+1 -or $point.valid -isnot [bool] -or -not $point.valid -or $point.result -cne 'hit'){throw 'Invalid extension point identity.'}
            if([Math]::Abs((Number $point.x)-($anchor.x+4*$tile+$col-4)) -gt .0001 -or [Math]::Abs((Number $point.y)-($anchor.y+$row-4)) -gt .0001 -or [Math]::Abs((Number $point.z)-$anchor.z) -gt 8){throw 'Extension point outside anchored grid.'}
            $nx=Number $point.nx;$ny=Number $point.ny;$nz=Number $point.nz
            if([Math]::Abs($nx*$nx+$ny*$ny+$nz*$nz-1) -gt .05 -or $nz -lt .5){throw 'Invalid extension terrain normal.'}
            if(($col -lt 8 -and [Math]::Abs($point.z-(Number $p.points[$i+1].z)) -gt .5) -or ($row -lt 8 -and [Math]::Abs($point.z-(Number $p.points[$i+9].z)) -gt .5)){throw 'Extension adjacent height step exceeds 0.5m.'}
        }
    }
    for($left=0;$left -lt 2;$left++){for($right=$left+1;$right -lt 3;$right++){
        $offset=4*($right-$left)
        for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9-$offset;$col++){
            $a=$Tiles[$left].points[$row*9+$col+$offset];$b=$Tiles[$right].points[$row*9+$col]
            foreach($field in @('x','y','z','nx','ny','nz')){if([Math]::Abs($a.$field-$b.$field) -gt .0001){throw 'Extension overlap differs.'}}
        }}
    }}
}
function Read-HudGroundExtensionInput([string]$Path,[string]$Root,[bool]$Captured){
    $full=Resolve-HudMovementEvidencePath $Path $Root
    $item=Get-Item -LiteralPath $full
    if($item.Length -lt 2 -or $item.Length -gt 288KB){throw 'Extension exceeds its bounded input size.'}
    $bytes=[IO.File]::ReadAllBytes($full)
    $data=ConvertFrom-HudGroundExtensionJson ([Text.UTF8Encoding]::new($false,$true).GetString($bytes))
    if($data.schema -ne 1 -or $data.kind -cne 'minecome_ground_extension_v1' -or $data.run -cnotmatch '^[0-9a-f]{32}$' -or @($data.tiles).Count -ne 3){throw 'Expected one immutable three-tile extension.'}
    $source=if($Captured){'live_kcd_ground_patch'}else{'standalone_fixture'}
    $parsed=@();$hashes=@()
    foreach($tile in $data.tiles){
        if(($tile.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',' -cne 'json,sha256'){throw 'Unknown or missing extension tile entry fields.'}
        if($tile.json -isnot [string] -or $tile.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid raw extension tile.'}
        $raw=[Text.Encoding]::UTF8.GetBytes($tile.json)
        if($raw.Length -gt 64KB -or (Get-HudExtensionHash $raw) -cne $tile.sha256){throw 'Extension tile bytes differ from hash.'}
        $p=ConvertFrom-HudGroundExtensionJson $tile.json
        if($p.run -cne $data.run -or $p.provenance.kind -cne $source -or $p.grid_size -ne 9 -or $p.walking_area -cne 'wide' -or $p.stable_player -isnot [bool] -or -not $p.stable_player){throw 'Extension tile provenance or capture identity differs.'}
        $parsed+=,$p;$hashes+=$tile.sha256
    }
    Assert-HudGroundExtensionGeometry $data $parsed
    $hash=Get-HudExtensionHash $bytes
    if($Captured){
        $directory=Split-Path -Parent $full
        $record=Read-HudMovementJson (Join-Path $directory 'verification.json')
        $receipt=Read-HudMovementJson (Join-Path $directory 'receipt.json')
        $snapshot=Join-Path $directory 'ground_extension.lua'
        $sourceHash=(Get-FileHash -LiteralPath (Join-Path $Root 'kcd2/probes/ground_extension.lua')).Hash.ToLowerInvariant()
        $inventory=Get-Content -LiteralPath (Join-Path $Root 'runtime/environment.json') -Raw | ConvertFrom-Json
        $tools=@($inventory.steam.relevant_apps | Where-Object {$_.role -ceq 'official_tools' -and $_.installed -and $_.distribution -ceq 'Steam' -and $_.app_id -eq '2429020'})
        if($tools.Count -ne 1){throw 'One pinned tools installation is required for capture provenance.'}
        $exe=Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe'
        $pin=@($tools[0].binaries | Where-Object {$_.path -ieq $exe})
        if($pin.Count -ne 1 -or $record.kind -cne 'minecome_ground_extension_capture_v1' -or $record.result -cne 'passed' -or
            $record.run -cne $data.run -or $record.manifest_sha256 -cne $hash -or $record.player_unchanged -isnot [bool] -or -not $record.player_unchanged -or
            $record.source_sha256 -cne $sourceHash -or (Get-FileHash -LiteralPath $snapshot).Hash.ToLowerInvariant() -cne $sourceHash -or
            $record.game_path -ine $exe -or $record.game_sha256 -cne ([string]$pin[0].sha256).ToLowerInvariant() -or
            (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant() -cne $record.game_sha256 -or
            $record.function_reload_verified -isnot [bool] -or -not $record.function_reload_verified -or
            $record.player_movement_applied -isnot [bool] -or $record.player_movement_applied -or
            $receipt.run -cne $data.run -or $receipt.result -cne 'sampled' -or $receipt.tile_count -ne 3 -or $receipt.valid_count -ne 243 -or $receipt.ray_count -ne 243 -or
            (@($record.tile_hashes) -join ',') -cne ($hashes -join ',')){throw 'Captured extension lacks matching pinned-engine evidence.'}
        foreach($axis in @('x','y','z')){if($record.anchor.$axis -ne $parsed[0].center.$axis -or $receipt.anchor.$axis -ne $record.anchor.$axis){throw 'Capture anchor differs from the first tile.'}}
        foreach($p in $parsed){
            if($p.provenance.game_pid -ne $record.game_pid -or [string]$p.provenance.game_start_filetime -cne [string]$record.game_start_filetime -or $p.provenance.game_exe_hash -cne $record.game_sha256 -or $p.provenance.source_sha256 -cne $sourceHash){throw 'Extension tile provenance differs from the pinned capture.'}
        }
    }
    $initialEntries=@(foreach($entry in @($data.tiles[0],$data.tiles[1])){[ordered]@{sha256=$entry.sha256;json=$entry.json}})
    $initialJson=ConvertTo-Json -InputObject ([ordered]@{schema=1;kind='minecome_ground_corridor_v1';run=$data.run;tiles=$initialEntries}) -Depth 5 -Compress
    $initialHash=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($initialJson))
    return [pscustomobject]@{Path=$full;Hash=$hash;Run=$data.run;TileHashes=$hashes;Anchor=$parsed[0].center;Captured=$Captured;InitialHash=$initialHash}
}
function Read-HudLiveGroundExtension([string]$Path,[string]$Root,$Context){
    $extension=Read-HudGroundExtensionInput $Path $Root $true
    $record=Read-HudMovementJson (Join-Path (Split-Path -Parent $extension.Path) 'verification.json')
    if($record.game_pid -ne $Context.GamePid -or
        [string]$record.game_start_filetime -cne $Context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture) -or
        $record.game_path -ine $Context.GamePath -or $record.game_sha256 -ine $Context.GameHash -or
        $record.function_reload_verified -isnot [bool] -or -not $record.function_reload_verified){throw 'Extension capture does not belong to this exact running KCD process.'}
    return $extension
}
