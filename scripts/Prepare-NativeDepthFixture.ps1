# Creates a disposable visual-test save. It never edits the source save or starts either game.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourceInstance,
 [Parameter(Mandatory)][string]$DestinationInstance,[string]$CellsJson='')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
 $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
 if($code -ne 0){throw "Native depth fixture preparation failed: $code"};return
}
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Assert-FixturePath([string]$Path){
 $full=[IO.Path]::GetFullPath($Path)
 if(-not $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture paths must stay inside this project.'}
 $part=$full
 while($part -and $part.Length -ge $root.Length){
  if(Test-Path -LiteralPath $part){if((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Fixture paths must not traverse links.'}}
  if($part -ieq $root){break};$part=Split-Path -Parent $part
 }
 return $full
}
function Write-NewFixtureText([string]$Path,[string]$Text){
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
 $file=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text);$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
}
function Read-FixtureJson([string]$Path,[long]$Limit=65536){
 $item=Get-Item -LiteralPath $Path -Force
 if($item.PSIsContainer -or $item.Length -gt $Limit -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Invalid fixture JSON: $Path"}
 return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 32
}
$source=Assert-FixturePath $SourceInstance;$destination=Assert-FixturePath $DestinationInstance
if(Test-Path -LiteralPath $destination){throw 'Destination must be a new instance; nothing will be overwritten.'}
if($destination.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Destination cannot be inside the source instance.'}
$save=Join-Path $source 'saves/MineCome-Gameplay'
$sourceMarker=Read-FixtureJson (Join-Path $save 'minecome-world.json') 2048
if($sourceMarker.schema -ne 1 -or $sourceMarker.kind -cne 'minecome_gameplay_world_v1' -or $sourceMarker.save -cne 'MineCome-Gameplay' -or
 ([guid]$sourceMarker.world_id).ToString() -cne $sourceMarker.world_id){throw 'Source is not an owned gameplay world.'}
if(-not (Test-Path -LiteralPath (Join-Path $save 'level.dat') -PathType Leaf)){throw 'Source save has no level.dat.'}
if(Test-Path -LiteralPath (Join-Path $source 'native-depth-fixture.json')){throw 'Use an original native save, not an existing depth fixture.'}
$binding=Read-FixtureJson (Join-Path $save 'minecome-terrain/binding.json')
$patchPath=Join-Path $save 'minecome-terrain/ground-patch.json'
$patch=Read-FixtureJson $patchPath;$patchHash=(Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($binding.schema -ne 1 -or $binding.kind -cne 'minecome_gameplay_terrain_v1' -or $binding.world_id -cne $sourceMarker.world_id -or
 $binding.patch_run -cne $patch.run -or $binding.patch_sha256 -cne $patchHash -or $patch.provenance.kind -cne 'live_kcd_ground_patch' -or
 $patch.schema -ne 1 -or $patch.grid_size -ne 9 -or $patch.spacing -ne 1 -or $patch.walking_area -cne 'wide' -or
 $patch.valid_count -ne 81 -or $patch.point_count -ne 81){throw 'Source requires its unchanged complete live 9x9 terrain capture.'}
$ledgerPath=Join-Path $save 'minecome-blocks.json';$ledger=Read-FixtureJson $ledgerPath 16384
if($ledger.schema -ne 1 -or $ledger.kind -cne 'minecome_gameplay_block_ledger_v1' -or $ledger.world_id -cne $sourceMarker.world_id -or
 $ledger.patch_run -cne $patch.run -or $ledger.patch_sha256 -cne $patchHash -or @($ledger.blocks).Count -ne 0 -or $ledger.revision -lt 0){throw 'Source must have an empty, matching owned-block ledger.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$root+'*')})
if($clients.Count){throw 'Close the MineCome Minecraft client normally before copying its save.'}
$lockPath=Join-Path $save 'session.lock'
if(Test-Path -LiteralPath $lockPath){$lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$lock.Dispose()}
if($CellsJson){$cells=@($CellsJson | ConvertFrom-Json -Depth 8)}else{
 $cells=@(foreach($x in -1,0,1){foreach($y in 65,66){[pscustomobject]@{x=$x;y=$y;z=-4;state='minecraft:magenta_concrete'}}})
}
if($cells.Count -lt 1 -or $cells.Count -gt 16){throw 'Choose 1 to 16 controlled visual fixture cells.'}
$seen=[Collections.Generic.HashSet[string]]::new();$normalized=@(foreach($cell in $cells){
 if((@($cell.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'state,x,y,z'){throw 'Each cell needs only x,y,z,state.'}
 foreach($axis in 'x','y','z'){if($cell.$axis -is [string] -or [double]$cell.$axis -ne [math]::Truncate([double]$cell.$axis)){throw 'Cell coordinates must be integers.'}}
 $x=[int]$cell.x;$y=[int]$cell.y;$z=[int]$cell.z
 if($x -lt -4 -or $x -gt 3 -or $z -lt -4 -or $z -gt 3 -or $y -lt 56 -or $y -gt 80 -or -not $seen.Add("$x,$y,$z")){throw 'Cell is duplicated or outside initial captured coverage.'}
 if($cell.state -cnotmatch '^minecraft:(stone|bricks|dirt|(white|orange|magenta|light_blue|yellow|lime|pink|gray|light_gray|cyan|purple|blue|brown|green|red|black)_(concrete|wool))$'){throw 'Use a supported opaque fixture block.'}
 if($binding.PSObject.Properties['resume']){$p=$binding.resume;if($x -lt $p.x+.31 -and $x+1 -gt $p.x-.31 -and $z -lt $p.z+.31 -and $z+1 -gt $p.z-.31 -and $y -lt $p.y+1.8 -and $y+1 -gt $p.y){throw 'Fixture cell overlaps the saved player.'}}
 [pscustomobject]@{x=$x;y=$y;z=$z;state=[string]$cell.state}
})
$entries=@(Get-ChildItem -LiteralPath $save -Recurse -Force)
if($entries.Count -gt 10000 -or @($entries | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Source tree is too large or contains links.'}
$files=@($entries | Where-Object {-not $_.PSIsContainer})
$manifest=@(foreach($file in $files){[pscustomobject]@{path=[IO.Path]::GetRelativePath($save,$file.FullName);bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$copySave=Join-Path $destination 'saves/MineCome-Gameplay';[void][IO.Directory]::CreateDirectory($copySave)
foreach($record in $manifest){
 $from=Join-Path $save $record.path;$to=Join-Path $copySave $record.path
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $to));[IO.File]::Copy($from,$to,$false)
 if((Get-FileHash -LiteralPath $to -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256 -or
    (Get-FileHash -LiteralPath $from -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.sha256){throw 'Source changed during copy; preserving the incomplete fixture for inspection.'}
}
$run=[guid]::NewGuid().ToString('N');$packName='minecome_native_depth_'+$run
$pack=Join-Path $copySave ('datapacks/'+$packName)
if(Test-Path -LiteralPath $pack){throw 'Unexpected fixture pack collision.'}
# Inspected pinned Yarn1.21.1+build.3: version.json data48; FunctionLoader uses
# singular function paths; MinecraftServer.loadDataPacks auto-enables new packs.
# CommandFunctionManager.tick executes load before END_SERVER_TICK reconciliation.
Write-NewFixtureText (Join-Path $pack 'pack.mcmeta') '{"pack":{"pack_format":48,"description":"MineCome disposable native-depth visual fixture"}}'
Write-NewFixtureText (Join-Path $pack 'data/minecraft/tags/function/load.json') '{"values":["minecome_depth_fixture:load"]}'
Write-NewFixtureText (Join-Path $pack 'data/minecome_depth_fixture/function/load.mcfunction') 'execute unless data storage minecome_depth_fixture:state seeded run function minecome_depth_fixture:seed'
$commands=@($normalized | ForEach-Object {"setblock $($_.x) $($_.y) $($_.z) $($_.state)"})
$checks=($normalized | ForEach-Object {"if block $($_.x) $($_.y) $($_.z) $($_.state)"}) -join ' '
$commands+="execute $checks run data modify storage minecome_depth_fixture:state seeded set value 1b"
Write-NewFixtureText (Join-Path $pack 'data/minecome_depth_fixture/function/seed.mcfunction') (($commands -join "`n")+"`n")
$copyLedger=Join-Path $copySave 'minecome-blocks.json'
[IO.File]::Copy($copyLedger,(Join-Path $destination 'source-block-ledger.json'),$false)
$ledger.blocks=$normalized;$ledger.revision=[long]$ledger.revision+1
[IO.File]::WriteAllText($copyLedger,($ledger|ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
$receipt=[ordered]@{schema=1;kind='minecome_native_depth_fixture_preparation_v1';run=$run;result='prepared_not_run';
 source_instance=$source;destination_instance=$destination;world_id=$sourceMarker.world_id;source_unchanged=$true;
 fixture_only=$true;native_input_verified=$false;vanilla_placement_verified=$false;native_occlusion_verified=$false;
 seeded_via='vanilla datapack load function on next Minecraft server startup';minecraft_version='1.21.1';data_pack_format=48;
 patch_run=$patch.run;patch_sha256=$patchHash;cells=$normalized;pack_name=$packName;commands=$commands;source_files=$manifest}
Write-NewFixtureText (Join-Path $destination 'native-depth-fixture.json') ($receipt | ConvertTo-Json -Depth 16)
[pscustomobject]@{InstanceDirectory=$destination;FixtureReceipt=(Join-Path $destination 'native-depth-fixture.json');Cells=$normalized;Result='prepared_not_run'}
