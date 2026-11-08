#Requires -Version 7.3
# Standalone acquisition/cache/admission checks; no game or network calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayTerrainHost.ps1')
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-terrain-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$passed=0;$now=1000000L
function Require([bool]$c,[string]$m){if(-not $c){throw $m}}
function Refuses([scriptblock]$action){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Require $failed 'Invalid terrain record accepted.'}
function New-Tile([int]$tx,[int]$tz,[double]$height=56){
 $points=@(for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){[ordered]@{index=$row*9+$col+1;x=120+8*$tx+$col-4;y=2040-8*$tz+$row-4;z=$height;nx=0;ny=0;nz=1}}})
 $j=[ordered]@{schema=1;run='b'*32;grid_size=9;spacing=1;walking_area='wide';center=[ordered]@{x=120+8*$tx;y=2040-8*$tz;z=56};points=$points;provenance=@{kind='live_kcd_ground_patch';game_exe_hash='d'*64}}|ConvertTo-Json -Depth 8 -Compress
 [pscustomobject]@{Tx=$tx;Tz=$tz;Json=$j;Sha256=(Get-GameplayTerrainHash $j);Data=($j|ConvertFrom-Json -Depth 8)}
}
$base=New-Tile 0 0;$id=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash=$base.Sha256}
function New-State{
 $coverage=Read-GameplayTerrainCoverage (Join-Path $directory 'missing.json') $id $base
 [pscustomobject]@{Identity=$id;Context=@{GameHash='d'*64};Probe=@{SourceHash='e'*64};Base=$base;Tiles=$coverage.Tiles;Known=$coverage.Known;Generation=0;Digest=$coverage.Digest;
 CacheFile=(Join-Path $directory 'coverage.json');AdmissionFile=(Join-Path $directory 'admission.json');AckFile=(Join-Path $directory 'ack.json');ExpiresUtcMs=$now+86400000;BeginSent=$false;Begin=$null;Terminal=$null;Stopping=$false;Failure=$null;
 LastSendUtcMs=0L;Sequence=0L;Pending=$null;LastPose=$null;Refused=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);LastRefusal=$null;CapacityReached=$false;Captures=0L;Admissions=0L}
}
function Pose([int]$seq,[double]$x,[double]$z){[pscustomobject]@{seq=$seq;utc_ms=$now+50*$seq;position=@{x=120+$x;y=2040-$z;z=56}}}
function Write-Json([string]$file,$object){[IO.File]::WriteAllText($file,($object|ConvertTo-Json -Depth 10 -Compress),[Text.UTF8Encoding]::new($false))}
try{
 $s=New-State
 foreach($pair in @(@(1,0),@(-1,0),@(0,1),@(0,-1))){$t=New-Tile $pair[0] $pair[1];$tile=ConvertTo-GameplayTerrainTile $t.Tx $t.Tz $t.Json $t.Sha256 $base;Require (Test-GameplayTerrainConnection $s.Known $tile) 'Cardinal edge failed.'}
 Require (-not(Test-GameplayTerrainConnection $s.Known (New-Tile 1 0 56.001))) 'Changed edge accepted.'
 Require (-not(Test-GameplayTerrainConnection $s.Known (New-Tile 2 0))) 'Disconnected tile accepted.';$passed++
 $t=New-Tile 1 0;Refuses {ConvertTo-GameplayTerrainTile 2 0 $t.Json $t.Sha256 $base};Refuses {ConvertTo-GameplayTerrainTile 1 0 $t.Json ('f'*64) $base}
 $bad=$t.Data;$bad.points[0].nz=.1;$raw=$bad|ConvertTo-Json -Depth 8 -Compress;Refuses {ConvertTo-GameplayTerrainTile 1 0 $raw (Get-GameplayTerrainHash $raw) $base}
 Refuses {ConvertFrom-GameplayTerrainJson '{"schema":1,"schema":2}'};$passed++
 # Actual KCD ray positions cross float32 precision boundaries. Match only
 # the exact float representation; the neighboring float is still refused.
 $rounded=New-Tile 1 -1;$rounded.Data.center.y=2048.6510009765625
 foreach($point in $rounded.Data.points){$row=[Math]::Floor(($point.index-1)/9);$point.y=[double][single]($rounded.Data.center.y+$row-4)}
 $roundedBase=New-Tile 0 0;$roundedBase.Data.center.y=2040.6510009765625
 $raw=$rounded.Data|ConvertTo-Json -Depth 8 -Compress
 [void](ConvertTo-GameplayTerrainTile 1 -1 $raw (Get-GameplayTerrainHash $raw) $roundedBase)
 $point=$rounded.Data.points[36];$point.y=[double][BitConverter]::Int32BitsToSingle([BitConverter]::SingleToInt32Bits([single]$point.y)+1)
 $raw=$rounded.Data|ConvertTo-Json -Depth 8 -Compress;Refuses {ConvertTo-GameplayTerrainTile 1 -1 $raw (Get-GameplayTerrainHash $raw) $roundedBase}
 Require (-not(Test-GameplayTerrainCoordinate 2048.65085 2048.6510009765625)) 'Off-grid near-float hit accepted.';$passed++
 Require (Test-GameplayTerrainCell $s -4 3) 'Base corner rejected.';Require (-not(Test-GameplayTerrainCell $s 4 0)) 'Unknown cell accepted.'
 Require (Test-GameplayTerrainPose $s (Pose 1 3.68 0)) 'Covered footprint rejected.';Require (-not(Test-GameplayTerrainPose $s (Pose 1 3.70 0))) 'Uncovered footprint accepted.';$passed++
 Require ($null -eq (Find-GameplayTerrainFrontier $s (Pose 1 0 0))) 'Initial idle capture.'
 Require ($null -eq (Find-GameplayTerrainFrontier $s (Pose 2 0 0))) 'Stationary capture.'
 Require ($null -eq (Find-GameplayTerrainFrontier $s (Pose 3 .70 0))) 'Capture too early.'
 $next=Find-GameplayTerrainFrontier $s (Pose 4 .80 0);Require ($next.Tx -eq 1 -and $next.Tz -eq 0) 'East frontier not requested before boundary braking.'
 $s.LastPose=Pose 5 0 -1.4;$next=Find-GameplayTerrainFrontier $s (Pose 6 0 -1.6);Require ($next.Tx -eq 0 -and $next.Tz -eq -1) 'North coordinate sign differs.';$passed++
 $s=New-State;Require ((Get-GameplayTerrainCommands $s $now) -like '*Begin*120,2040,56*') 'Begin command differs.'
 Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true}) $now
 [void](Get-GameplayTerrainCommands $s ($now+50) (Pose 1 1.4 0));$command=Get-GameplayTerrainCommands $s ($now+100) (Pose 2 1.6 0)
 Require ($command -like '*Capture*1,1,0*') 'Motion did not request tile.';Require ($s.Generation -eq 0) 'Request admitted early.'
 $t=New-Tile 1 0;$receipt=[pscustomobject]@{schema=1;run=$id.Run;event='captured';result='sampled';active=$true;request=1;tx=1;tz=0;ray_count=81;mask=256;anchor=$base.Data.center}
 Refuses {Accept-GameplayTerrainReceipt $s $receipt ($now+200)}
 for($i=0;$i -lt 81;$i+=9){
  $batch=[pscustomobject]@{schema=1;run=$id.Run;event='samples';result='sampling';active=$true;request=1;tx=1;tz=0;ray_count=$i+9;mask=256;first=$i+1;count=9;points=@($t.Data.points[$i..($i+8)])}
  $batch.first++;Refuses {Accept-GameplayTerrainReceipt $s $batch ($now+250)};$batch.first--
  Accept-GameplayTerrainReceipt $s $batch ($now+250);Refuses {Accept-GameplayTerrainReceipt $s $batch ($now+251)}
  Require (-not [IO.File]::Exists($s.AdmissionFile)) 'Partial terrain batch published.'
 }
 Accept-GameplayTerrainReceipt $s $receipt ($now+300)
 $ad=Read-GameplayTerrainJsonFile $s.AdmissionFile 131072;Require ($ad.utc_ms -eq $now+100 -and $ad.generation -eq 1 -and $ad.tile_sha256 -ceq $s.Pending.Tile.Sha256) 'Capture identity or original time changed.'
 Require ($s.Known.Count -eq 1 -and $s.Generation -eq 0) 'Capture admitted before durable ack.'
 [void](Get-GameplayTerrainCommands $s ($now+301) (Pose 3 1.8 0));Require ($s.Sequence -eq 1) 'Second capture raced pending admission.';$passed++
 $ack=[ordered]@{schema=1;kind='minecome_gameplay_terrain_ack_v1';run=$id.Run;world_id=$id.WorldId;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;target_pid=$id.Pid;target_start_filetime=$id.Start;generation=1;tx=1;tz=0;tile_sha256=$s.Pending.Tile.Sha256;status='admitted';coverage_digest=(Get-GameplayTerrainDigest $id.PatchHash @($base,$s.Pending.Tile))}
 $ack.tile_sha256='f'*64;Write-Json $s.AckFile $ack;Refuses {Read-GameplayTerrainAck $s};$ack.tile_sha256=$s.Pending.Tile.Sha256
 Write-Json $s.AckFile $ack;[void](Get-GameplayTerrainCommands $s ($now+302));Require ($s.Generation -eq 1 -and $s.Known.Count -eq 2 -and $null -eq $s.Pending) 'Matching durable ack did not advance.'
 Require (Test-GameplayTerrainPose $s (Pose 5 4 0)) 'Admitted seam remains blocked.';Read-GameplayTerrainAck $s;Require ($s.Generation -eq 1) 'Duplicate ack advanced generation.';$passed++
 $cache=[ordered]@{schema=1;kind='minecome_gameplay_coverage_v1';world_id=$id.WorldId;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;generation=1;digest=$s.Digest;tiles=@(@{tx=1;tz=0;sha256=$s.Tiles[1].Sha256;json=$s.Tiles[1].Json})}
 Write-Json $s.CacheFile $cache;$reopen=Read-GameplayTerrainCoverage $s.CacheFile $id $base;Require ($reopen.Known.Count -eq 2 -and $reopen.Digest -ceq $s.Digest) 'Owned cache reopen differs.'
 $cache.world_id='foreign';Write-Json $s.CacheFile $cache;Refuses {Read-GameplayTerrainCoverage $s.CacheFile $id $base};$cache.world_id=$id.WorldId
 $cache.tiles[0].sha256='f'*64;Write-Json $s.CacheFile $cache;Refuses {Read-GameplayTerrainCoverage $s.CacheFile $id $base};$passed++
 $wrongBuild=New-Tile 1 0;$wrongBuild.Data.provenance.game_exe_hash='f'*64;$raw=$wrongBuild.Data|ConvertTo-Json -Depth 8 -Compress
 Refuses {ConvertTo-GameplayTerrainTile 1 0 $raw (Get-GameplayTerrainHash $raw) $base};$passed++
 $s=New-State;$s.BeginSent=$true;$s.Begin=@{active=$true};$s.Pending=[pscustomobject]@{Request=1;Tx=-1;Tz=0;RequestedUtcMs=$now;Tile=$null}
 Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='refused';result='terrain_miss';active=$true;request=1;tx=-1;tz=0;ray_count=1;mask=256}) ($now+100)
 Require ($s.Refused.Contains('-1,0') -and $null -eq $s.Pending -and -not $s.Failure) 'Unknown terrain stopped valid session.'
 [void](Get-GameplayTerrainStopCommand $s);Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='terminal';result='explicit_stop';active=$false;timers_cancelled=$true}) ($now+101)
 Require ((Get-GameplayTerrainHostState $s).CleanupComplete) 'Cleanup unconfirmed.';$passed++
 # Optional initial ring uses the SAME capture chunks, admission and durable
 # acknowledgement path while the player remains still. No fabricated tiles.
 foreach($file in @('ack.json','admission.json')){[IO.File]::Delete((Join-Path $directory $file))}
 $s=New-State;$s|Add-Member -NotePropertyName InitialTerrainRadius -NotePropertyValue 1
 [void](Get-GameplayTerrainCommands $s $now)
 Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='begin';result='ready';active=$true}) $now
 Require ((Get-GameplayTerrainHostState $s).InitialCaptureMissing.Count -eq 8) 'Initial ring hid unknown tiles.'
 for($round=1;$round -le 8;$round++){
  $at=$now+500*$round;$command=Get-GameplayTerrainCommands $s $at (Pose $round 0 0)
  Require ($command -like '*GameplayTerrainCapture*' -and $s.Pending.Request -eq $round) 'Idle ring did not capture serially.'
  $p=$s.Pending;$t=New-Tile $p.Tx $p.Tz
  Require (Test-GameplayTerrainConnection $s.Known $t) 'Initial request disconnected from acknowledged coverage.'
  for($i=0;$i -lt 81;$i+=9){
   Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='samples';result='sampling';active=$true;request=$p.Request;tx=$p.Tx;tz=$p.Tz;ray_count=$i+9;mask=256;first=$i+1;count=9;points=@($t.Data.points[$i..($i+8)])}) ($at+50)
  }
  Accept-GameplayTerrainReceipt $s ([pscustomobject]@{schema=1;run=$id.Run;event='captured';result='sampled';active=$true;request=$p.Request;tx=$p.Tx;tz=$p.Tz;ray_count=81;mask=256;anchor=$base.Data.center}) ($at+100)
  [void](Get-GameplayTerrainCommands $s ($at+110) (Pose ($round+20) 0 0))
  Require ($s.Known.Count -eq $round -and $s.Sequence -eq $round -and $null -ne $s.Pending) 'Initial capture skipped durable admission.'
  $next=@($s.Tiles.ToArray())+@($p.Tile)
  $ack=[ordered]@{schema=1;kind='minecome_gameplay_terrain_ack_v1';run=$id.Run;world_id=$id.WorldId;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;target_pid=$id.Pid;target_start_filetime=$id.Start;generation=$round;tx=$p.Tx;tz=$p.Tz;tile_sha256=$p.Tile.Sha256;status='admitted';coverage_digest=(Get-GameplayTerrainDigest $id.PatchHash $next)}
  Write-Json $s.AckFile $ack;Read-GameplayTerrainAck $s
 }
 $status=Get-GameplayTerrainHostState $s
 Require ($status.InitialCaptureComplete -and $status.TileCount -eq 9 -and $status.Generation -eq 8 -and $status.InitialCaptureMissing.Count -eq 0) 'Initial ring did not finish with nine acknowledged tiles.'
 Require ($null -eq (Find-GameplayTerrainInitialFrontier $s)) 'Completed ring requested duplicates.'
 Require (Test-GameplayTerrainPose $s (Pose 30 8 8)) 'Captured ring corner remains blocked.'
 $s.LastPose=Pose 31 8.70 0;$frontier=Find-GameplayTerrainFrontier $s (Pose 32 8.80 0)
 Require ($frontier.Tx -eq 2 -and $frontier.Tz -eq 0) 'Ordinary exploration did not continue after initial ring.'
 $cache=[ordered]@{schema=1;kind='minecome_gameplay_coverage_v1';world_id=$id.WorldId;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;generation=$s.Generation;digest=$s.Digest;tiles=@($s.Tiles|Select-Object -Skip 1|ForEach-Object {@{tx=$_.Tx;tz=$_.Tz;sha256=$_.Sha256;json=$_.Json}})}
 Write-Json $s.CacheFile $cache;$reopen=Read-GameplayTerrainCoverage $s.CacheFile $id $base
 Require ($reopen.Known.Count -eq 9 -and $reopen.Generation -eq 8 -and $reopen.Digest -ceq $s.Digest) 'Initial coverage cache did not reopen.';$passed++
 $s=New-State;$s|Add-Member -NotePropertyName InitialTerrainRadius -NotePropertyValue 1
 [void]$s.Refused.Add('1,0');$frontier=Find-GameplayTerrainInitialFrontier $s;$status=Get-GameplayTerrainHostState $s
 Require ($frontier.Tx -eq -1 -and $frontier.Tz -eq 0 -and -not $status.InitialCaptureComplete -and $status.InitialCaptureRefused -eq 1 -and $s.Known.Count -eq 1) 'Refused initial terrain retried or became known.';$passed++
 Write-Output "PASS $passed gameplay terrain host checks (no game/network)"
}finally{
 $resolved=[IO.Path]::GetFullPath($directory);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-terrain-*'){throw 'Refused unexpected fixture cleanup target.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
