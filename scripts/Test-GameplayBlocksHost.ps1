#Requires -Version 7.3
# Standalone snapshot/command contract checks; no game or network calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayBlocksHost.ps1')
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-blocks-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$file=Join-Path $directory 'blocks.json';$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$id=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$bounds=[pscustomobject]@{MinX=-4;MaxX=3;MinZ=-4;MaxZ=3};$passed=0
$valid=[ordered]@{schema=1;kind='minecome_gameplay_blocks_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=1;utc_ms=$now;revision=0;blocks=@(@{x=1;y=64;z=2;state='minecraft:stone'})}
function Require([bool]$c,[string]$m){if(-not $c){throw $m}}
function Write-Snapshot($v){$v|ConvertTo-Json -Depth 6 -Compress|Set-Content -LiteralPath $file -Encoding utf8NoBOM}
function Copy-Snapshot{$v=@{};foreach($k in $valid.Keys){$v[$k]=$valid[$k]};return $v}
function Refuses([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Require $failed 'Invalid snapshot accepted.'}
try{
 Write-Snapshot $valid;$s=Read-GameplayBlocksSnapshot $file $id $bounds $now
 Require ($s.Count -eq 1 -and $s.Cells -ceq '1,64,2' -and $s.Revision -eq 0) 'Snapshot differs.';$passed++
 Require ($null -eq (Read-GameplayBlocksSnapshot $file $id $bounds ($now+501))) 'Stale snapshot renewed.';$passed++
 foreach($change in @(@{run='d'*32},@{target_pid='123'},@{revision=-1},@{seq=0},@{utc_ms=$now+51},@{schema='1'})){
  $v=Copy-Snapshot;foreach($k in $change.Keys){$v[$k]=$change[$k]};Write-Snapshot $v;Refuses {Read-GameplayBlocksSnapshot $file $id $bounds $now}
 };$passed++
 foreach($bad in @(@{x=4;y=64;z=0;state='minecraft:stone'},@{x=0;y=81;z=0;state='minecraft:stone'},@{x=0;y=64;z=0;state='minecraft:dirt'},@{x=0.5;y=64;z=0;state='minecraft:stone'})){
  $v=Copy-Snapshot;$v.blocks=@($bad);Write-Snapshot $v;Refuses {Read-GameplayBlocksSnapshot $file $id $bounds $now}
 };$passed++
 $v=Copy-Snapshot;$v.blocks=@($valid.blocks[0],$valid.blocks[0]);Write-Snapshot $v;Refuses {Read-GameplayBlocksSnapshot $file $id $bounds $now}
 $raw=($valid|ConvertTo-Json -Depth 6 -Compress).Replace('"seq":1','"seq":1,"seq":2');[IO.File]::WriteAllText($file,$raw);Refuses {Read-GameplayBlocksSnapshot $file $id $bounds $now};$passed++
 Write-Snapshot $valid
 $state=[pscustomobject]@{Identity=$id;SnapshotFile=$file;Bounds=$bounds;Center=@{x=120.;y=2040.;z=56.};ExpiresUtcMs=$now+86400000;StartedUtcMs=$now;Probe=$null;
  BeginSent=$false;Begin=$null;Terminal=$null;Failure=$null;Stopping=$false;LastSendUtcMs=0L;LastSnapshotUtcMs=0L;Sequence=0L;Revision=-1L;Cells=$null;PendingRevision=-1L;PendingSinceUtcMs=0L;PendingCount=0;AppliedRevision=-1L;AppliedCount=0;Applications=0L;Spawned=0L;Removed=0L}
 Require ((Get-GameplayBlocksCommands $state $now) -like 'MineCome.GameplayBlocksBegin*') 'No begin command.'
 Accept-GameplayBlocksReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true})
 Require ((Get-GameplayBlocksCommands $state ($now+1)) -like '*Apply*{1,64,2}*') 'No apply command.'
 Refuses {Accept-GameplayBlocksReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='applied';result='mirrored';active=$true;revision=0;count=0})}
 Accept-GameplayBlocksReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='applied';result='mirrored';active=$true;revision=0;count=1;spawned=1;removed=0})
 Require ((Get-GameplayBlocksCommands $state ($now+2)) -ceq '') 'Unchanged revision resent.'
 Require ((Get-GameplayBlocksCommands $state ($now+251)) -like '*Heartbeat*') 'Missing lease heartbeat.';$passed++
 $v=Copy-Snapshot;$v.revision=1;Write-Snapshot $v;Refuses {Get-GameplayBlocksCommands $state ($now+252)};$passed++
 $v=Copy-Snapshot;$v.seq=2;$v.utc_ms=$now+252;$v.blocks=@(@{x=2;y=64;z=2;state='minecraft:stone'});Write-Snapshot $v
 Refuses {Get-GameplayBlocksCommands $state ($now+253)};$passed++
 Require ((Get-GameplayBlocksStopCommand $state) -like '*End*') 'Missing stop.'
 Accept-GameplayBlocksReceipt $state ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';result='explicit_stop';active=$false;count=0;timers_cancelled=$true;spawned=1;removed=1})
 Require ((Get-GameplayBlocksHostState $state).CleanupComplete) 'Cleanup not confirmed.';$passed++
 Write-Output "PASS $passed gameplay block host checks (no game/network)"
}finally{
 $resolved=[IO.Path]::GetFullPath($directory);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-blocks-*'){throw 'Refused unexpected fixture cleanup target.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
