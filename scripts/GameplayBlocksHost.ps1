#Requires -Version 7.3
# Stone mirror integrated into the existing single gameplay console worker.
# This helper never launches a game or owns an additional HTTP/runspace loop.
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'HudStoneRelay.ps1')

function Test-GameplayBlocksAssets($Context){
    Assert-MineComeProbeContext $Context
    # Reuse the existing relay's owned deployment/hash convention without
    # requiring or starting its demo-only native relay executable.
    $deploymentPath=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot 'runtime/lua-deployment.json')
    $deployment=Get-Content -LiteralPath $deploymentPath -Raw|ConvertFrom-Json
    $mod=Assert-MineComeHudStonePath (Join-Path $Context.GameRoot 'Mods/minecome')
    $pak=Assert-MineComeHudStonePath (Join-Path $mod 'Data/minecome-diagnostics.pak')
    $manifest=Assert-MineComeHudStonePath (Join-Path $mod 'mod.manifest')
    if($deployment.ModPath -ine $mod -or $deployment.ContainsLocalMinecraftAssets -ne $true -or
        (Get-FileHash -LiteralPath $pak).Hash -ine $deployment.PakHash -or (Get-FileHash -LiteralPath $manifest).Hash -ine $deployment.ManifestHash){throw 'Owned Minecraft stone package differs from its deployment receipt.'}
    $compiled=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot 'runtime/compiled-block')
    $provenancePath=Assert-MineComeHudStonePath (Join-Path $compiled 'provenance.json')
    $provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json -Depth 12
    if($provenance.schema -ne 1 -or $provenance.stage -cne 'asset_compilation' -or $provenance.physics_proxy -ne $false){throw 'Actual Minecraft stone compilation provenance is required.'}
    foreach($name in @('stone.obj','block-atlas.png')){
        $source=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot ('minecraft/run/minecome-export/stone/'+$name))
        $record=@($provenance.source.PSObject.Properties|Where-Object {[IO.Path]::GetFullPath($_.Name) -ieq $source})
        if($record.Count -ne 1 -or $record[0].Value -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $source).Hash -ine $record[0].Value){throw 'Stone compilation source differs from the Minecraft export.'}
    }
    $stream=[IO.File]::OpenRead($pak);$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
    try{
        foreach($name in @('stone.cgf','stone.mtl','block-atlas.dds')){
            $entryName='objects/minecome/'+$name;$key='Data\objects\minecome\'+$name
            $record=$provenance.outputs.PSObject.Properties[$key]
            if(-not $record -or $record.Value.sha256 -cnotmatch '^[0-9a-f]{64}$'){throw "Missing compiled Minecraft asset receipt: $name"}
            $local=Assert-MineComeHudStonePath (Join-Path $compiled ('Data/'+$entryName))
            if((Get-FileHash -LiteralPath $local).Hash -ine $record.Value.sha256){throw "Compiled Minecraft asset changed: $name"}
            $entry=@($archive.Entries|Where-Object {$_.FullName -ceq $entryName})
            if($entry.Count -ne 1 -or $entry[0].Length -ne $record.Value.bytes){throw "Installed compiled Minecraft asset missing or ambiguous: $name"}
            $assetStream=$entry[0].Open()
            try{if((Get-FileHash -InputStream $assetStream).Hash -ine $record.Value.sha256){throw "Installed compiled Minecraft asset hash differs: $name"}}finally{$assetStream.Dispose()}
        }
    }finally{$archive.Dispose();$stream.Dispose()}
    [pscustomobject]@{DeploymentPath=$deploymentPath;PakHash=$deployment.PakHash;ManifestHash=$deployment.ManifestHash;ProvenancePath=$provenancePath;ProvenanceHash=(Get-FileHash -LiteralPath $provenancePath).Hash;Model='objects/minecome/stone.cgf'}
}

function Test-GameplayBlockInteger($Value,[long]$Minimum,[long]$Maximum){
    return $Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value) -and $Value -eq [Math]::Floor([double]$Value) -and $Value -ge $Minimum -and $Value -le $Maximum
}
function Read-GameplayBlocksSnapshot([string]$Path,$Identity,$Bounds,[long]$Now,$TerrainState=$null){
    if(-not [IO.File]::Exists($Path)){return $null}
    $file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt 16384){throw 'Gameplay block snapshot exceeds16384 bytes.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes)
        if($file.ReadByte() -ne -1){throw 'Block snapshot changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
        $doc=[Text.Json.JsonDocument]::Parse($json)
        try{
            $top=$doc.RootElement
            if($top.ValueKind -ne [Text.Json.JsonValueKind]::Object -or $top.GetProperty('blocks').ValueKind -ne [Text.Json.JsonValueKind]::Array){throw 'Block snapshot shape differs.'}
            $objects=@($top)+@($top.GetProperty('blocks').EnumerateArray())
            foreach($o in $objects){
                if($o.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw 'Block record must be an object.'}
                $names=@($o.EnumerateObject()|ForEach-Object {$_.Name})
                if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Duplicate block snapshot fields.'}
            }
        }finally{$doc.Dispose()}
        $value=$json|ConvertFrom-Json -Depth 6
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
    $keys=@('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','revision','blocks')
    if((($value.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($keys|Sort-Object)-join ',') -or
        $value.schema -ne 1 -or $value.kind -cne 'minecome_gameplay_blocks_v1' -or $value.run -cne $Identity.Run -or
        $value.world_id -cne $Identity.WorldId -or $value.patch_run -cne $Identity.PatchRun -or $value.patch_sha256 -cne $Identity.PatchHash -or
        $value.target_pid -ne $Identity.Pid -or $value.target_start_filetime -isnot [string] -or $value.target_start_filetime -cne $Identity.Start){throw 'Block snapshot identity differs.'}
    if(-not(Test-GameplayBlockInteger $value.schema 1 1) -or -not(Test-GameplayBlockInteger $value.target_pid 1 2147483647) -or
        -not(Test-GameplayBlockInteger $value.seq 1 10000000) -or -not(Test-GameplayBlockInteger $value.revision 0 10000000) -or
        -not(Test-GameplayBlockInteger $value.utc_ms 1 ($Now+50))){throw 'Block snapshot sequence/clock differs.'}
    $blocks=@($value.blocks);if($blocks.Count -gt 64){throw 'Stone snapshot capacity exceeds64.'}
    # The guest may publish its durable ack between this worker's initial ack
    # read and this snapshot read. Recheck after reading the snapshot bytes.
    if($TerrainState -and $TerrainState.Pending -and $TerrainState.Pending.Tile){Read-GameplayTerrainAck $TerrainState}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$flat=[Collections.Generic.List[string]]::new()
    foreach($b in $blocks){
        if((($b.PSObject.Properties.Name|Sort-Object)-join ',') -cne 'state,x,y,z' -or $b.state -cne 'minecraft:stone' -or
            -not(Test-GameplayBlockInteger $b.x $Bounds.MinX $Bounds.MaxX) -or -not(Test-GameplayBlockInteger $b.y 56 80) -or
            -not(Test-GameplayBlockInteger $b.z $Bounds.MinZ $Bounds.MaxZ)){throw 'Only complete captured stone cells are supported.'}
        if($TerrainState -and -not (Test-GameplayTerrainCell $TerrainState ([int]$b.x) ([int]$b.z))){throw 'Stone leaves admitted terrain coverage.'}
        $cell=([string]$b.x)+','+([string]$b.y)+','+([string]$b.z)
        if(-not $seen.Add($cell)){throw 'Duplicate stone coordinate.'};$flat.Add($cell)
    }
    if($Now-$value.utc_ms -gt 500){return $null}
    # Canonical cell order allows harmless snapshot reordering but never changes
    # a revision's meaning. Integer coordinates need no Lua escaping.
    $canonical=[string]::Join(',',@($flat.ToArray()|Sort-Object -CaseSensitive))
    [pscustomobject]@{Sequence=[long]$value.seq;UtcMs=[long]$value.utc_ms;Revision=[long]$value.revision;Count=$blocks.Count;Cells=$canonical}
}
function New-GameplayBlocksHost {
    param($Context,[string]$Run,[string]$WorldId,$Patch,[string]$SnapshotFile,[long]$ExpiresUtcMs,$TerrainState=$null)
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $WorldId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or $Patch.Run -cnotmatch '^[0-9a-f]{32}$' -or $Patch.Hash -cnotmatch '^[0-9a-f]{64}$'){throw 'Gameplay blocks identity invalid.'}
    $SnapshotFile=Resolve-HudMovementEvidencePath $SnapshotFile $Context.ProjectRoot
    if((Get-FileHash -LiteralPath $Patch.Path).Hash -ine $Patch.Hash){throw 'Gameplay block terrain changed.'}
    $data=Get-Content -LiteralPath $Patch.Path -Raw|ConvertFrom-Json -Depth 12
    if($data.grid_size -ne 9 -or $data.spacing -ne 1 -or @($data.points).Count -ne 81 -or $data.provenance.kind -cne 'live_kcd_ground_patch'){throw 'Block mirror requires the captured wide patch.'}
    $bounds=if($TerrainState){[pscustomobject]@{MinX=-68;MaxX=67;MinZ=-68;MaxZ=67}}else{[pscustomobject]@{MinX=-4;MaxX=3;MinZ=-4;MaxZ=3}}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if($ExpiresUtcMs-$now -lt 1000 -or $ExpiresUtcMs-$now -gt 86400000){throw 'Gameplay blocks expiry differs.'}
    $assets=Test-GameplayBlocksAssets $Context
    $probe=New-MineComeProbeRun $Context 'gameplay-blocks' (Join-Path $Context.ProjectRoot 'kcd2/gameplay/blocks_session.lua') 'GameplayBlocksBegin'
    [pscustomobject]@{Identity=[pscustomobject]@{Run=$Run;WorldId=$WorldId;Pid=$Context.GamePid;Start=$Context.GameStartedUtc.ToFileTimeUtc().ToString();PatchRun=$Patch.Run;PatchHash=$Patch.Hash};
        SnapshotFile=$SnapshotFile;Bounds=$bounds;TerrainState=$TerrainState;Center=$data.center;ExpiresUtcMs=$ExpiresUtcMs;StartedUtcMs=$now;Probe=$probe;Assets=$assets;
        BeginSent=$false;Begin=$null;Terminal=$null;Failure=$null;Stopping=$false;LastSendUtcMs=0L;LastSnapshotUtcMs=0L;Sequence=0L;Revision=-1L;Cells=$null;
        PendingRevision=-1L;PendingSinceUtcMs=0L;PendingCount=0;AppliedRevision=-1L;AppliedCount=0;Applications=0L;Spawned=0L;Removed=0L}
}
function Get-GameplayBlocksCommands($State,[long]$Now){
    if($State.Failure){throw $State.Failure};if($State.Stopping){return ''}
    if($Now -ge $State.ExpiresUtcMs){throw 'Gameplay block identity expired.'}
    $run=$State.Identity.Run
    if(-not $State.BeginSent){
        $State.BeginSent=$true;$State.LastSendUtcMs=$Now
        $duration=[Math]::Min(86400000,$State.ExpiresUtcMs-$Now)
        $numbers=@($duration,$State.Center.x,$State.Center.y,$State.Center.z,$State.Bounds.MinX,$State.Bounds.MaxX,$State.Bounds.MinZ,$State.Bounds.MaxZ)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
        return "MineCome.GameplayBlocksBegin('$run',$([string]::Join(',',$numbers)))"
    }
    if(-not $State.Begin){if($Now-$State.LastSendUtcMs -gt 1500){throw 'Gameplay block begin was not acknowledged.'};return ''}
    $terrainState=if($State.PSObject.Properties['TerrainState']){$State.TerrainState}else{$null}
    $snapshot=Read-GameplayBlocksSnapshot $State.SnapshotFile $State.Identity $State.Bounds $Now $terrainState
    if($snapshot){
        if($snapshot.Sequence -lt $State.Sequence -or $snapshot.Revision -lt $State.Revision -or $snapshot.UtcMs -lt $State.LastSnapshotUtcMs -or
            ($snapshot.Sequence -eq $State.Sequence -and ($snapshot.UtcMs -ne $State.LastSnapshotUtcMs -or $snapshot.Revision -ne $State.Revision -or $State.Cells -cne $snapshot.Cells)) -or
            ($snapshot.Revision -eq $State.Revision -and $State.Cells -cne $snapshot.Cells)){throw 'Block snapshot revision/sequence changed or regressed.'}
        if($snapshot.Sequence -gt $State.Sequence){$State.Sequence=$snapshot.Sequence;$State.LastSnapshotUtcMs=$snapshot.UtcMs;$State.Revision=$snapshot.Revision;$State.Cells=$snapshot.Cells}
    }
    if(($State.LastSnapshotUtcMs -gt 0 -and $Now-$State.LastSnapshotUtcMs -gt 1000) -or ($State.LastSnapshotUtcMs -eq 0 -and $Now-$State.StartedUtcMs -gt 12000)){throw 'Minecraft block snapshot expired.'}
    if($State.PendingRevision -ge 0 -and $Now-$State.PendingSinceUtcMs -gt 1500){throw 'Native block reconciliation did not complete.'}
    if($State.PendingRevision -lt 0 -and $State.Revision -gt $State.AppliedRevision){
        $State.PendingRevision=$State.Revision;$State.PendingSinceUtcMs=$Now;$State.LastSendUtcMs=$Now
        $State.PendingCount=$(if([string]::IsNullOrEmpty($State.Cells)){0}else{$State.Cells.Split(',').Length/3})
        return "MineCome.GameplayBlocksApply('$run',$($State.Revision),{$($State.Cells)})"
    }
    if($Now-$State.LastSendUtcMs -ge 250){$State.LastSendUtcMs=$Now;return "MineCome.GameplayBlocksHeartbeat('$run')"}
    return ''
}
function Accept-GameplayBlocksReceipt($State,$Receipt){
    if($Receipt.schema -ne 1 -or $Receipt.run -cne $State.Identity.Run){throw 'Block receipt identity differs.'}
    switch -CaseSensitive ($Receipt.event){
        'begin'{if($State.Begin -or $Receipt.result -cne 'ready' -or -not $Receipt.active){throw 'Block begin differs.'};$State.Begin=$Receipt}
        'applied'{
            if($Receipt.result -cne 'mirrored' -or -not $Receipt.active -or $Receipt.revision -ne $State.PendingRevision -or -not(Test-GameplayBlockInteger $Receipt.count 0 64) -or $Receipt.count -ne $State.PendingCount){throw 'Block reconciliation acknowledgement differs.'}
            $State.AppliedRevision=[long]$Receipt.revision;$State.PendingRevision=-1L;$State.AppliedCount=[int]$Receipt.count;$State.Applications++
        }
        'terminal'{$State.Terminal=$Receipt;if(-not $State.Stopping -or $Receipt.result -cne 'explicit_stop' -or $Receipt.count -ne 0 -or -not $Receipt.timers_cancelled){$State.Failure='Native blocks stopped: '+$Receipt.result}}
        'rejected'{$State.Failure='Native blocks rejected: '+$Receipt.result}
        default{throw 'Unknown block receipt event.'}
    }
    if($Receipt.PSObject.Properties['spawned']){$State.Spawned=[long]$Receipt.spawned;$State.Removed=[long]$Receipt.removed}
}
function Get-GameplayBlocksStopCommand($State){$State.Stopping=$true;return "MineCome.GameplayBlocksEnd('$($State.Identity.Run)')"}
function Get-GameplayBlocksHostState($State){
    [pscustomobject]@{Run=$State.Identity.Run;Failure=$State.Failure;Begin=$State.Begin;Terminal=$State.Terminal;Applications=$State.Applications;AppliedRevision=$State.AppliedRevision;
        MirroredCount=$State.AppliedCount;Spawned=$State.Spawned;Removed=$State.Removed;LastSnapshotUtcMs=$State.LastSnapshotUtcMs;
        Assets=$(if($State.PSObject.Properties['Assets']){$State.Assets}else{$null});
        CleanupComplete=(-not $State.BeginSent -or ($State.Terminal -and $State.Terminal.count -eq 0 -and $State.Terminal.timers_cancelled -and $State.Terminal.result -ceq 'explicit_stop'))}
}
