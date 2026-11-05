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
function Write-Receipt([string]$Tag,$Value){[IO.File]::AppendAllText($Context.GameLog,('['+$Tag+'] '+($Value|ConvertTo-Json -Depth 6 -Compress)+"`n"))}
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){
 $body=[Uri]::UnescapeDataString($PathAndQuery.Substring($PathAndQuery.IndexOf('command=')+8))
 if($body.Contains('GameplayBlocksEnd') -and $Context.FailBlockStop){throw 'simulated block stop dispatch failure'}
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
 elseif($body -match "GameplayBlocksApply\('[a-f0-9]+',(\d+),\{1,64,2\}\)"){$b.event='applied';$b.result='mirrored';$b.revision=[long]$Matches[1];$b.count=1;$b.spawned=1}
 elseif($body.Contains('GameplayBlocksEnd')){$b.event='terminal';$b.result='explicit_stop';$b.active=$false;$b.revision=0;$b.spawned=1;$b.removed=1;$b.timers_cancelled=$true}
 # Model a timer-produced terminal whose final line only becomes readable on
 # the next explicit cleanup log flush, after synchronous movement End.
 if($b.event -ceq 'terminal'){$script:pendingBlockStop=$b}
 elseif($b.event){Write-Receipt 'MineComeGameplayBlocks' $b}
 $script:fixtureSequence++;$utc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 $p=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$Identity.Run;world_id=$Identity.WorldId;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;seq=$script:fixtureSequence;utc_ms=$utc;source_ms=$script:fixtureSequence*10;position=@{x=1.;y=2.;z=3.}}
 [IO.File]::WriteAllText($PoseFile,($p|ConvertTo-Json -Depth 5 -Compress))
 $p.Remove('position');$p.Remove('source_ms');$p.kind='minecome_gameplay_blocks_v1';$p.revision=0;$p.blocks=@(@{x=1;y=64;z=2;state='minecraft:stone'})
 [IO.File]::WriteAllText($BlocksState.SnapshotFile,($p|ConvertTo-Json -Depth 6 -Compress))
}
'@
$passed=0
try{
 [IO.File]::WriteAllText((Join-Path $directory 'scripts/GameplayMovementHost.ps1'),$mock.Replace('__HELPER__',$helper))
 foreach($failStop in @($false,$true)){
  $fixtureHome=Join-Path $directory ([string]$failStop);$null=New-Item -ItemType Directory -Path $fixtureHome
  $gameLog=Join-Path $fixtureHome 'game.log';[IO.File]::WriteAllText($gameLog,'')
  $poseFile=Join-Path $fixtureHome 'pose.json';$viewFile=Join-Path $fixtureHome 'view.json'
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $blocks=[pscustomobject]@{Identity=$identity;SnapshotFile=(Join-Path $fixtureHome 'blocks.json');Bounds=[pscustomobject]@{MinX=-4;MaxX=3;MinZ=-4;MaxZ=3};Center=@{x=0.;y=0.;z=0.};ExpiresUtcMs=$now+10000;StartedUtcMs=$now;Probe=$null;
   BeginSent=$false;Begin=$null;Terminal=$null;Failure=$null;Stopping=$false;LastSendUtcMs=0L;LastSnapshotUtcMs=0L;Sequence=0L;Revision=-1L;Cells=$null;PendingRevision=-1L;PendingSinceUtcMs=0L;PendingCount=0;AppliedRevision=-1L;AppliedCount=0;Applications=0L;Spawned=0L;Removed=0L}
  $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new();$cancel=[Threading.CancellationTokenSource]::new()
  $runspace=[RunspaceFactory]::CreateRunspace();$pipeline=[PowerShell]::Create()
  try{
   $runspace.Open();$pipeline.Runspace=$runspace
   $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument([pscustomobject]@{GameLog=$gameLog;FailBlockStop=$failStop}).AddArgument($identity).AddArgument($bounds).AddArgument($poseFile).AddArgument($viewFile).AddArgument($now+10000).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($directory).AddArgument($blocks)
   $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
   do{
    if($shared.ContainsKey('Snapshot')){$s=$shared['Snapshot'];if($s.Stopped -or ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3 -and $s.Blocks.Applications -ge 1)){break}}
    Start-Sleep -Milliseconds 10
   }while($watch.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted)
   $cancel.Cancel();Require ($async.AsyncWaitHandle.WaitOne(4000)) 'Combined worker cleanup timed out.'
   $null=$pipeline.EndInvoke($async);Require ($pipeline.Streams.Error.Count -eq 0 -and ($failStop -or -not $pipeline.HadErrors)) ('Worker errors: '+($pipeline.Streams.Error|Out-String))
   $s=$shared['Snapshot'];Require ($s.Stopped -and $s.Terminal.result -ceq 'explicit_stop') 'Movement stop was lost behind block cleanup.'
   Require ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3 -and $s.Blocks.Applications -eq 1) ('Combined worker did not run: '+$s.Failure)
   if($failStop){Require ($s.Failure -ceq 'simulated block stop dispatch failure' -and -not $s.Blocks.CleanupComplete) 'Failed block stop was hidden.'}
   else{Require (-not $s.Failure -and $s.Blocks.CleanupComplete -and $s.Blocks.Removed -eq 1) ('Block cleanup failed: '+$s.Failure)}
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
