# Read-only three-tile terrain capture. Never launches or moves either game.
[CmdletBinding()]
param([switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Extension capture failed: $code"};return
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

function ConvertTo-MineComeGroundExtension($Summary,[object[]]$Points,$Context,[string]$SourceHash,[string]$Run){
    function Number($Value){
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or
            -not [double]::IsFinite([double]$Value)){throw 'Extension numeric field is invalid.'}
        return [double]$Value
    }
    function Exactly($Value,[double]$Expected){if((Number $Value) -ne $Expected){throw 'Extension numeric contract differs.'}}
    function Flag($Value,[bool]$Expected){if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Extension boolean contract differs.'}}
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $SourceHash -cnotmatch '^[0-9a-f]{64}$'){throw 'Extension identity/hash invalid.'}
    Exactly $Summary.schema 1
    if($Summary.run -cne $Run -or $Summary.result -cne 'sampled' -or $Summary.mask_name -cne 'ent_terrain'){throw 'Extension receipt identity/result differs.'}
    foreach($field in @('tile_count','offset_x','grid_size','spacing','point_count','valid_count','ray_count')){
        $expected=@{tile_count=3;offset_x=4;grid_size=9;spacing=1;point_count=243;valid_count=243;ray_count=243}[$field]
        Exactly $Summary.$field $expected
    }
    Flag $Summary.stable_player $true;Flag $Summary.approximate_heightfield $true;Flag $Summary.full_collision_export_verified $false
    $mask=Number $Summary.mask
    if($mask -le 0 -or $mask -gt 2147483647 -or $mask -ne [Math]::Floor($mask)){throw 'Extension terrain mask invalid.'}
    foreach($axis in @('x','y','z')){if([Math]::Abs((Number $Summary.anchor.$axis)) -gt 9999988){throw 'Extension anchor outside coordinate bounds.'}}
    if($Points.Count -ne 243){throw 'Complete three-tile capture required.'}
    $seen=@{};$byTile=@(@{},@{},@{})
    foreach($point in $Points){
        Exactly $point.schema 1
        if($point.run -cne $Run -or $point.result -cne 'hit'){throw 'Extension point identity/result differs.'}
        $tile=Number $point.tile;$index=Number $point.index
        if($tile -notin @(0,1,2) -or $index -lt 1 -or $index -gt 81 -or $index -ne [Math]::Floor($index)){throw 'Extension tile/index outside bounds.'}
        $key="$tile,$index";if($seen.ContainsKey($key)){throw 'Duplicate extension point.'};$seen[$key]=$true
        $byTile[[int]$tile][[int]$index]=$point
        Flag $point.valid $true;Flag $point.approximate_heightfield $true;Flag $point.full_collision_export_verified $false
        Exactly $point.mask $mask
        $row=[Math]::Floor(($index-1)/9);$col=($index-1)%9
        if([Math]::Abs((Number $point.x)-((Number $Summary.anchor.x)+4*$tile+$col-4)) -gt .0001 -or
            [Math]::Abs((Number $point.y)-((Number $Summary.anchor.y)+$row-4)) -gt .0001 -or
            [Math]::Abs((Number $point.z)-(Number $Summary.anchor.z)) -gt 8){throw 'Extension point is outside its anchored grid.'}
        $nx=Number $point.nx;$ny=Number $point.ny;$nz=Number $point.nz
        if([Math]::Abs($nx*$nx+$ny*$ny+$nz*$nz-1) -gt .05 -or $nz -lt .5){throw 'Extension terrain normal is unsuitable.'}
    }
    for($tile=0;$tile -lt 3;$tile++){
        for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){
            $i=1+$row*9+$col;$p=$byTile[$tile][$i]
            if(($col -lt 8 -and [Math]::Abs($p.z-$byTile[$tile][$i+1].z) -gt .5) -or
                ($row -lt 8 -and [Math]::Abs($p.z-$byTile[$tile][$i+9].z) -gt .5)){throw 'Extension adjacent height step exceeds0.5m.'}
        }}
    }
    for($left=0;$left -lt 2;$left++){for($right=$left+1;$right -lt 3;$right++){
        $offset=4*($right-$left)
        for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9-$offset;$col++){
            $a=$byTile[$left][1+$row*9+$col+$offset];$b=$byTile[$right][1+$row*9+$col]
            foreach($field in @('x','y','z','nx','ny','nz')){if([Math]::Abs($a.$field-$b.$field) -gt .0001){throw 'Captured extension overlap changed between tiles.'}}
        }}
    }}
    $tileDocuments=@();$entries=@()
    for($tile=0;$tile -lt 3;$tile++){
        $document=[ordered]@{schema=1;run=$Run;result='sampled';center=[ordered]@{x=$Summary.anchor.x+4*$tile;y=$Summary.anchor.y;z=$Summary.anchor.z};
            grid_size=9;spacing=1;walking_area='wide';point_count=81;valid_count=81;stable_player=$true;approximate_heightfield=$true;full_collision_export_verified=$false;
            points=@(1..81 | ForEach-Object {$byTile[$tile][$_]});provenance=[ordered]@{kind='live_kcd_ground_patch';game_pid=$Context.GamePid;
                game_start_filetime=$Context.GameStartedUtc.ToFileTimeUtc().ToString();game_exe_hash=$Context.GameHash.ToLowerInvariant();source_sha256=$SourceHash}}
        $json=ConvertTo-Json -InputObject $document -Depth 8 -Compress
        $bytes=[Text.Encoding]::UTF8.GetBytes($json)
        if($bytes.Length -gt 65536){throw 'Extension tile exceeds64KiB.'}
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $entries+=,[ordered]@{sha256=$hash;json=$json};$tileDocuments+=,$json
    }
    $manifest=[ordered]@{schema=1;kind='minecome_ground_extension_v1';run=$Run;tiles=$entries}
    $json=ConvertTo-Json -InputObject $manifest -Depth 5 -Compress
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 294912){throw 'Extension manifest exceeds288KiB.'}
    [pscustomobject]@{Json=$json;Tiles=$tileDocuments;TileHashes=@($entries | ForEach-Object sha256);Anchor=$Summary.anchor}
}

function Wait-MineComeGroundExtensionEndpoint($Context){
    for($attempt=1;$attempt -le 3;$attempt++){
        Assert-MineComeProbeContext $Context
        try{
            $null=Get-MineComeToolsConsoleBinding
            Assert-MineComeProbeContext $Context
            return [pscustomobject]@{attempts=$attempt;binding_verified=$true;module_load_retried=$false}
        }catch{
            # Process replacement and all other errors remain fatal. Endpoint
            # metadata queries are read-only; no ambiguous Lua load is retried.
            Assert-MineComeProbeContext $Context
            if($attempt -eq 3 -or $_.Exception.Message -cnotin @('Official tools request exceeded its absolute timeout','Official tools Console ExecuteString binding is not ready')){throw}
            Start-Sleep -Milliseconds 250
        }
    }
}

. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
if($PreflightOnly){Write-Output 'GROUND_EXTENSION_PREFLIGHT_PASS no_changes=true';return}
$probe=New-MineComeProbeRun $context 'ground-extension' (Join-Path $context.ProjectRoot 'kcd2/probes/ground_extension.lua') 'SampleGroundExtension' -PrepareOnly
$result='failed';$failure=$null;$summary=$null;$document=$null;$manifestPath=$null;$manifestHash=$null;$endpointReadiness=$null;$stage='endpoint_readiness'
try{
    $endpointReadiness=Wait-MineComeGroundExtensionEndpoint $context
    $stage='module_load'
    Initialize-MineComeProbeRun $context $probe
    $stage='sampling'
    Invoke-MineComeProbeConsole $context ("#MineCome.SampleGroundExtension('$($probe.Run)'); System.LogAlways('[MineComeExtensionFlush] $($probe.Run)')")
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    do{
        Assert-MineComeProbeContext $context
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $receipts=@(Get-MineComeProbeReceipts $fresh 'MineComeGroundExtension' $probe.Run)
        if($receipts.Count -gt 1){throw 'Repeated extension summary receipts.'}
        if($receipts.Count -eq 1){$summary=$receipts[0];break}
        Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $deadline)
    if($null -eq $summary){throw 'Fresh extension engine receipt absent.'}
    $points=@(Get-MineComeProbeReceipts $fresh 'MineComeGroundExtensionPoint' $probe.Run)
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'receipt.json') -Encoding utf8NoBOM
    ConvertTo-Json -InputObject $points -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'points.json') -Encoding utf8NoBOM
    $document=ConvertTo-MineComeGroundExtension $summary $points $context $probe.SnapshotHash.ToLowerInvariant() $probe.Run
    Assert-MineComeProbeContext $context
    for($tile=0;$tile -lt 3;$tile++){
        $path=Join-Path $probe.Directory "ground-tile-$tile.json"
        [IO.File]::WriteAllText($path,$document.Tiles[$tile],[Text.UTF8Encoding]::new($false));(Get-Item -LiteralPath $path).IsReadOnly=$true
    }
    $manifestPath=Join-Path $probe.Directory 'ground-extension.json'
    [IO.File]::WriteAllText($manifestPath,$document.Json,[Text.UTF8Encoding]::new($false))
    $manifestHash=(Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant();(Get-Item -LiteralPath $manifestPath).IsReadOnly=$true
    $result='passed';$stage='complete'
    Write-Output ([pscustomobject]@{GroundExtensionFile=$manifestPath;EvidenceDirectory=$probe.Directory})
    Write-Host "GROUND_EXTENSION_CAPTURE_PASS run=$($probe.Run) tiles=3 points=243 player_moved=false full_collision_export_verified=false"
}catch{$failure=$_.Exception.Message;throw}
finally{
    try{Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') -Encoding utf8NoBOM}catch{}
    [ordered]@{schema=1;kind='minecome_ground_extension_capture_v1';result=$result;run=$probe.Run;manifest_sha256=$manifestHash;
        source_sha256=$probe.SnapshotHash.ToLowerInvariant();game_pid=$context.GamePid;game_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();
        game_path=$context.GamePath;game_sha256=$context.GameHash.ToLowerInvariant();anchor=$(if($summary){$summary.anchor}else{$null});
        player_unchanged=($result -ceq 'passed');tile_hashes=$(if($document){$document.TileHashes}else{@()});
        function_reload_verified=$probe.FunctionReloadVerified;endpoint_readiness=$endpointReadiness;stage=$stage;player_movement_applied=$false;full_collision_export_verified=$false;failure=$failure} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
}
