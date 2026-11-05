#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Real combined worker with simulated transport/receipts. Never touches a game.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-block-worker-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $directory 'scripts')
$identity=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$bounds=[pscustomobject]@{MinX=-10.;MaxX=10.;MinY=-10.;MaxY=10.;MinZ=-10.;MaxZ=10.}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$helper=(Join-Path $PSScriptRoot 'GameplayMovementHost.ps1').Replace("'","''")
$mock=@'
. '__HELPER__'
function Assert-MineComeProbeContext($Context){}
$script:fixtureSequence=0L
$script:pendingBlockStop=$null
$script:inBlockRead=$false
$script:originalReadBlocks=${function:Read-GameplayBlocksSnapshot}
function Read-GameplayBlocksSnapshot([string]$Path,$Identity,$Bounds,[long]$Now,$TerrainState=$null){
 # Deterministically publish the ack and new block snapshot AFTER the loop's
 # terrain command/ack pass but BEFORE the real block snapshot reader runs.
 if($Context.AckRace -and $TerrainState -and $TerrainState.Pending -and $TerrainState.Pending.Tile -and -not [IO.File]::Exists($TerrainState.AckFile)){
  $script:inBlockRead=$true;try{Invoke-MineComeToolsRequest '?command=' 150}finally{$script:inBlockRead=$false}
  $Shared['AckPublishedDuringBlockRead']=$true
 }
 & $script:originalReadBlocks $Path $Identity $Bounds $Now $TerrainState
}
function Write-Receipt([string]$Tag,$Value){
 $json=$Value|ConvertTo-Json -Depth 6 -Compress
 if($Tag -ceq 'MineComeGameplayTerrain'){
  $size=[Text.Encoding]::UTF8.GetByteCount($json);$Shared['TerrainReceiptBytes']=[Math]::Max($Shared['TerrainReceiptBytes'],$size)
  if($Value.event -ceq 'samples'){$Shared['TerrainBatchCount']++}
 }
 [IO.File]::AppendAllText($Context.GameLog,('['+$Tag+'] '+$json+"`n"))
}
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){
 $body=[Uri]::UnescapeDataString($PathAndQuery.Substring($PathAndQuery.IndexOf('command=')+8))
 if($body.Contains('GameplayBlocksEnd') -and $Context.FailBlockStop){throw 'simulated block stop dispatch failure'}
 if($body.Contains('GameplayTerrainEnd')){$Shared['TerrainStopAttempted']=$true;if($Context.FailTerrainStop){throw 'simulated terrain stop dispatch failure'}}
 if($body.Contains('GameplayCleanupFlush') -and $script:pendingBlockStop){
  Write-Receipt 'MineComeGameplayBlocks' $script:pendingBlockStop;$script:pendingBlockStop=$null
 }
 $r=[ordered]@{schema=1;run=$Identity.Run;event='';result='';seq=0;active=$true;camera_basis_valid=$true;forward=@{x=0.;y=1.;z=0.};up=@{x=0.;y=0.;z=1.};camera=@{x=1.;y=2.;z=4.6};aim=@{range=4.5;known=$true;distance=2.;terrain_hit=$true}}
 if($body.Contains('GameplayMovementBegin')){$r.event='begin';$r.result='ready'}
 elseif($body.Contains('GameplayMovementEnd')){$r.event='terminal';$r.result='explicit_stop';$r.active=$false}
 elseif($body -match "GameplayMovementSample\('[a-f0-9]+',(\d+),true\)"){$r.event='view';$r.result='sampled';$r.seq=[long]$Matches[1]}
 if($r.event){Write-Receipt 'MineComeGameplayMovement' $r}
 $b=[ordered]@{schema=1;run=$Identity.Run;event='';result='';active=$true;revision=-1;count=0;spawned=0;removed=0;timers_cancelled=$false}
 if($body.Contains('GameplayBlocksBegin')){$b.event='begin';$b.result='ready'}
 elseif($body -match "GameplayBlocksApply\('[a-f0-9]+',(\d+),\{([15]),64,2\}\)"){
  $b.event='applied';$b.result='mirrored';$b.revision=[long]$Matches[1];$b.count=1;$b.spawned=1
  if($Matches[2] -ceq '5'){if($TerrainState.Generation -ne 1){throw 'Expanded block dispatched before terrain ack'};$Shared['ExpandedBlockSent']=$true}
 }
 elseif($body.Contains('GameplayBlocksEnd')){$b.event='terminal';$b.result='explicit_stop';$b.active=$false;$b.revision=0;$b.spawned=1;$b.removed=1;$b.timers_cancelled=$true}
 # Model a timer-produced terminal whose final line only becomes readable on
 # the next explicit cleanup log flush, after synchronous movement End.
 if($b.event -ceq 'terminal'){$script:pendingBlockStop=$b}
 elseif($b.event){Write-Receipt 'MineComeGameplayBlocks' $b}
 if($Context.Explore){
  if($body.Contains('GameplayTerrainBegin')){Write-Receipt 'MineComeGameplayTerrain' ([ordered]@{schema=1;run=$Identity.Run;event='begin';result='ready';active=$true})}
  elseif($body -match "GameplayTerrainCapture\('[a-f0-9]+',(\d+),1,0\)"){
   $request=[long]$Matches[1];$tile=$Context.TileJson|ConvertFrom-Json -Depth 8
   for($i=0;$i -lt 81;$i+=9){Write-Receipt 'MineComeGameplayTerrain' ([ordered]@{schema=1;run=$Identity.Run;event='samples';result='sampling';active=$true;request=$request;tx=1;tz=0;ray_count=$i+9;mask=256;first=$i+1;count=9;points=@($tile.points[$i..($i+8)])})}
   Write-Receipt 'MineComeGameplayTerrain' ([ordered]@{schema=1;run=$Identity.Run;event='captured';result='sampled';active=$true;request=$request;tx=1;tz=0;ray_count=81;mask=256;anchor=@{x=0;y=0;z=0}})
  }elseif($body.Contains('GameplayTerrainEnd')){Write-Receipt 'MineComeGameplayTerrain' ([ordered]@{schema=1;run=$Identity.Run;event='terminal';result='explicit_stop';active=$false;timers_cancelled=$true})}
  if($body -match "GameplayMovementPose\('[a-f0-9]+',\d+,[^,]+,5,2,3\)"){
   if($TerrainState.Generation -ne 1){throw 'Expanded pose dispatched before terrain ack'};$Shared['ExpandedPoseSent']=$true
  }
  if([IO.File]::Exists($TerrainState.AdmissionFile) -and -not [IO.File]::Exists($TerrainState.AckFile) -and (-not $Context.AckRace -or $script:inBlockRead)){
   $admission=Read-GameplayTerrainJsonFile $TerrainState.AdmissionFile 131072
   if($TerrainState.Known.Count -ne 1 -or $TerrainState.Generation -ne 0){throw 'Coverage advanced before durable acknowledgement'}
   $ack=[ordered]@{schema=1;kind='minecome_gameplay_terrain_ack_v1';run=$Identity.Run;world_id=$Identity.WorldId;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;
    generation=1;tx=1;tz=0;tile_sha256=$admission.tile_sha256;status='admitted';coverage_digest=(Get-GameplayTerrainDigest $Identity.PatchHash @($TerrainState.Base,$TerrainState.Pending.Tile))}
   [IO.File]::WriteAllText($TerrainState.AckFile,($ack|ConvertTo-Json -Depth 5 -Compress))
   $Shared['AckWrittenBeforeExpandedSnapshots']=$true
  }
 }
 $script:fixtureSequence++;$utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 $expanded=$Context.Explore -and [IO.File]::Exists($TerrainState.AckFile)
 $x=if($expanded){5.}elseif($Context.Explore){[Math]::Min(.9,.3+.2*$script:fixtureSequence)}else{1.}
 $p=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$Identity.Run;world_id=$Identity.WorldId;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;seq=$script:fixtureSequence;utc_ms=$utc;source_ms=$script:fixtureSequence*10;position=@{x=$x;y=2.;z=3.}}
 [IO.File]::WriteAllText($PoseFile,($p|ConvertTo-Json -Depth 5 -Compress))
 $p.Remove('position');$p.Remove('source_ms');$p.kind='minecome_gameplay_blocks_v1';$p.revision=$(if($expanded){1}else{0});$p.blocks=@(@{x=$(if($expanded){5}else{1});y=64;z=2;state='minecraft:stone'})
 [IO.File]::WriteAllText($BlocksState.SnapshotFile,($p|ConvertTo-Json -Depth 6 -Compress))
}
'@
$passed=0
try{
 [IO.File]::WriteAllText((Join-Path $directory 'scripts/GameplayMovementHost.ps1'),$mock.Replace('__HELPER__',$helper))
 $cases=@(@{Explore=$false;FailBlockStop=$false;FailTerrainStop=$false},@{Explore=$false;FailBlockStop=$true;FailTerrainStop=$false},
  @{Explore=$true;FailBlockStop=$false;FailTerrainStop=$false},@{Explore=$true;FailBlockStop=$true;FailTerrainStop=$false},@{Explore=$true;FailBlockStop=$false;FailTerrainStop=$true},
  @{Explore=$true;FailBlockStop=$false;FailTerrainStop=$false;AckRace=$true})
 foreach($case in $cases){
  if(-not $case.ContainsKey('AckRace')){$case.AckRace=$false}
  $failStop=$case.FailBlockStop;$fixtureHome=Join-Path $directory ([string]$passed);$null=New-Item -ItemType Directory -Path $fixtureHome
  $gameLog=Join-Path $fixtureHome 'game.log';[IO.File]::WriteAllText($gameLog,'')
  $poseFile=Join-Path $fixtureHome 'pose.json';$viewFile=Join-Path $fixtureHome 'view.json'
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $terrain=$null
  if($case.Explore){
   $basePoints=@(for($row=0;$row -lt 9;$row++){for($col=0;$col -lt 9;$col++){[ordered]@{index=$row*9+$col+1;x=$col-4;y=$row-4;z=0;nx=0;ny=0;nz=1}}})
   $baseRaw=[ordered]@{schema=1;run=$identity.PatchRun;grid_size=9;spacing=1;walking_area='wide';center=@{x=0;y=0;z=0};points=$basePoints;provenance=@{kind='live_kcd_ground_patch';game_exe_hash='d'*64}}|ConvertTo-Json -Depth 8 -Compress
   $base=[pscustomobject]@{Tx=0;Tz=0;Json=$baseRaw;Sha256=(Get-GameplayTerrainHash $baseRaw);Data=($baseRaw|ConvertFrom-Json -Depth 8)}
   $identity.PatchHash=$base.Sha256;$coverage=Read-GameplayTerrainCoverage (Join-Path $fixtureHome 'missing.json') $identity $base
   $terrain=[pscustomobject]@{Identity=$identity;Context=@{GameHash='d'*64};Probe=@{SourceHash='e'*64};Base=$base;Tiles=$coverage.Tiles;Known=$coverage.Known;Generation=0;Digest=$coverage.Digest;
    CacheFile=(Join-Path $fixtureHome 'coverage.json');AdmissionFile=(Join-Path $fixtureHome 'admission.json');AckFile=(Join-Path $fixtureHome 'ack.json');ExpiresUtcMs=$now+10000;BeginSent=$false;Begin=$null;Terminal=$null;Stopping=$false;Failure=$null;
    LastSendUtcMs=0L;Sequence=0L;Pending=$null;LastPose=$null;Refused=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);LastRefusal=$null;CapacityReached=$false;Captures=0L;Admissions=0L}
   $tile=$baseRaw|ConvertFrom-Json -Depth 8;$tile.center.x=8;foreach($p in $tile.points){$p.x+=8};$case.TileJson=$tile|ConvertTo-Json -Depth 8 -Compress
  }else{$case.TileJson=$null}
  $blocks=[pscustomobject]@{Identity=$identity;SnapshotFile=(Join-Path $fixtureHome 'blocks.json');Bounds=[pscustomobject]@{MinX=-4;MaxX=3;MinZ=-4;MaxZ=3};Center=@{x=0.;y=0.;z=0.};ExpiresUtcMs=$now+10000;StartedUtcMs=$now;Probe=$null;
   BeginSent=$false;Begin=$null;Terminal=$null;Failure=$null;Stopping=$false;LastSendUtcMs=0L;LastSnapshotUtcMs=0L;Sequence=0L;Revision=-1L;Cells=$null;PendingRevision=-1L;PendingSinceUtcMs=0L;PendingCount=0;AppliedRevision=-1L;AppliedCount=0;Applications=0L;Spawned=0L;Removed=0L}
  $blocks|Add-Member NoteProperty TerrainState $terrain
  if($terrain){$blocks.Bounds=[pscustomobject]@{MinX=-68;MaxX=67;MinZ=-68;MaxZ=67}}
  $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new();$cancel=[Threading.CancellationTokenSource]::new()
  $shared['TerrainReceiptBytes']=0;$shared['TerrainBatchCount']=0
  $runspace=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
  try{
   $runspace.Open();$pipeline.Runspace=$runspace
   $case.GameLog=$gameLog
   $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument([pscustomobject]$case).AddArgument($identity).AddArgument($bounds).AddArgument($poseFile).AddArgument($viewFile).AddArgument($now+10000).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($directory).AddArgument($blocks).AddArgument($terrain)
   $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
   do{
    if($shared.ContainsKey('Snapshot')){$s=$shared['Snapshot'];if($s.Stopped -or ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3 -and $s.Blocks.Applications -ge $(if($case.Explore){2}else{1}))){break}}
    Start-Sleep -Milliseconds 10
   }while($watch.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted)
   $cancel.Cancel();Require ($async.AsyncWaitHandle.WaitOne(4000)) 'Combined worker cleanup timed out.'
   $null=$pipeline.EndInvoke($async);Require ($pipeline.Streams.Error.Count -eq 0 -and ($failStop -or $case.FailTerrainStop -or -not $pipeline.HadErrors)) ('Worker errors in case '+$passed+': '+($pipeline.Streams.Error|Out-String))
   $s=$shared['Snapshot'];Require ($s.Stopped -and $s.Terminal.result -ceq 'explicit_stop') 'Movement stop was lost behind block cleanup.'
   Require ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3 -and $s.Blocks.Applications -eq $(if($case.Explore){2}else{1})) ('Combined worker did not run: '+$s.Failure)
   if($failStop){Require ($s.Failure -ceq 'simulated block stop dispatch failure' -and -not $s.Blocks.CleanupComplete) 'Failed block stop was hidden.'}
   else{Require (($case.FailTerrainStop -or -not $s.Failure) -and $s.Blocks.CleanupComplete -and $s.Blocks.Removed -eq 1) ('Block cleanup failed: '+$s.Failure)}
   if($case.Explore){
    Require ($shared['TerrainReceiptBytes'] -gt 0 -and $shared['TerrainReceiptBytes'] -lt 4095 -and $shared['TerrainBatchCount'] -eq 9) 'Bounded terrain batches were not exercised.'
    Require ($s.Terrain.Generation -eq 1 -and $s.Terrain.Admissions -eq 1 -and $s.Terrain.TileCount -eq 2 -and $shared['AckWrittenBeforeExpandedSnapshots'] -and $shared['ExpandedPoseSent'] -and $shared['ExpandedBlockSent']) 'Terrain acknowledgement did not precede expanded poses and blocks.'
    Require ($shared['TerrainStopAttempted']) 'Block failure skipped terrain cleanup.'
    if($case.FailTerrainStop){Require ($s.Failure -ceq 'simulated terrain stop dispatch failure' -and -not $s.Terrain.CleanupComplete) 'Failed terrain stop was hidden.'}
    else{Require ($s.Terrain.CleanupComplete) 'Terrain cleanup not confirmed.'}
    if($case.AckRace){Require ($shared['AckPublishedDuringBlockRead']) 'Ack/block publication race was not exercised.'}
   }
   $aim=Get-Content -LiteralPath (Join-Path $fixtureHome 'gameplay-aim.json') -Raw|ConvertFrom-Json
   Require ($aim.kind -ceq 'minecome_gameplay_aim_v1' -and $aim.run -ceq $identity.Run -and $aim.world_id -ceq $identity.WorldId -and $aim.origin.z -eq 4.6 -and $aim.direction.y -eq 1 -and $aim.known -and $aim.terrain_hit) 'Published combined aim contract differs.'
   $passed++
  }finally{$cancel.Cancel();$pipeline.Dispose();$runspace.Dispose();$cancel.Dispose()}
 }
 Write-Output "PASS $passed combined gameplay worker/cleanup checks (simulated transport; no game/network)"
}finally{
 $resolved=[IO.Path]::GetFullPath($directory);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'minecome-block-worker-*'){throw 'Refused unexpected fixture cleanup target.'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
