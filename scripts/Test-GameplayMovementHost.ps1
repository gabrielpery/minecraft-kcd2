#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Standalone pose-file and worker transport fixture; no game or network calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
if(-not ('MineCome.Tests.DelayedGameplayLog' -as [type])){Add-Type -TypeDefinition @'
using System;using System.IO;using System.Threading.Tasks;using System.Collections.Concurrent;
namespace MineCome.Tests { public static class DelayedGameplayLog {
 static readonly ConcurrentBag<Task> jobs=new ConcurrentBag<Task>();
 public static void Append(string path,string text,int delay){jobs.Add(Task.Run(async()=>{await Task.Delay(delay);File.AppendAllText(path,text);}));}
 public static void Drain(){Task job;while(jobs.TryTake(out job))job.GetAwaiter().GetResult();}
}}
'@}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-gameplay-host-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $directory 'scripts')
$poseFile=Join-Path $directory 'pose.json';$viewFile=Join-Path $directory 'view.json';$gameLog=Join-Path $directory 'game.log'
$identity=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64;CameraOrigin=[pscustomobject]@{x=0.;y=0.;z=-64.}}
$bounds=[pscustomobject]@{MinX=-10.;MaxX=10.;MinY=-10.;MaxY=10.;MinZ=-10.;MaxZ=10.}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$valid=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$identity.Run;world_id=$identity.WorldId;target_pid=$identity.Pid;target_start_filetime=$identity.Start;patch_run=$identity.PatchRun;patch_sha256=$identity.PatchHash;seq=1;utc_ms=$now;source_ms=0;position=@{x=1.;y=2.;z=3.}}
$passed=0;$pipeline=$null;$runspace=$null;$cancel=$null;$cadenceAverage=$null;$bufferedAverage=$null
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Pose($Value){$Value|ConvertTo-Json -Depth 6 -Compress|Set-Content -LiteralPath $poseFile -Encoding utf8NoBOM}
function Copy-Pose{$copy=@{};foreach($key in $valid.Keys){$copy[$key]=$valid[$key]};return $copy}
function New-CameraCollision{[ordered]@{generation=1;complete=$true;origin=@{x=0.;y=0.;z=-64.};boxes='000004000000001004100010'}}
function Copy-WorldPose{$copy=Copy-Pose;$copy.perspective_request=1;$copy.camera_collision=New-CameraCollision;return $copy}
function Refuses([scriptblock]$Action){$threw=$false;try{& $Action|Out-Null}catch{$threw=$true};Require $threw 'Invalid pose was accepted.'}
try{
    Write-Pose $valid
    $p=Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now
    Require ($p.seq -eq 1 -and $p.position.z -eq 3) 'Fresh pose read differs.';$passed++
    Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 1 0 $now)) 'Duplicate pose was renewed.'
    Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 ($now+251))) 'Stale pose was renewed.';$passed++
    foreach($change in @(@{run='d'*32},@{target_pid=999},@{seq=0},@{utc_ms=$now+51},@{source_ms=86400001},@{schema='1'},@{target_start_filetime=123})){
        $v=Copy-Pose;foreach($key in $change.Keys){$v[$key]=$change[$key]};Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now}
    };$passed++
    Write-Pose $valid;Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 2 5 $now}
    $v=Copy-Pose;$v.seq=2;Write-Pose $v;Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 1 0 $now};$passed++
    $v=Copy-Pose;$v.position=@{x=11.;y=2.;z=3.};Write-Pose $v
    Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now};$passed++
    $json=($valid|ConvertTo-Json -Depth 6 -Compress).Replace('"seq":1','"seq":1,"seq":2')
    [IO.File]::WriteAllText($poseFile,$json);Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now};$passed++
    [IO.File]::WriteAllText($poseFile,' '*4097);Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now};$passed++

    # Perspective is an explicit WorldBlocks request. Legacy consumers retain
    # their exact field set, clocks and identity instead of silently opting in.
    Write-Pose $valid;Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    foreach($perspective in @(0,1,2)){
        $v=Copy-WorldPose;$v.perspective_request=$perspective;Write-Pose $v
        $p=Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true
        Require ($p.perspective_request -eq $perspective) 'WorldBlocks perspective request changed.'
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now}
        Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 1 0 $now $true)) 'WorldBlocks duplicate renewed its request.'
        Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 ($now+251) $true)) 'WorldBlocks stale request was admitted.'
    };$passed++
    foreach($perspective in @(-1,3,1.5,'1',$true,$null)){
        $v=Copy-WorldPose;$v.perspective_request=$perspective;Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    foreach($change in @(@{run='d'*32},@{world_id='other'},@{target_pid=999},@{target_start_filetime='different'},@{patch_run='e'*32},@{patch_sha256='f'*64},@{utc_ms=$now+51},@{source_ms=86400001},@{seq=0})){
        $v=Copy-WorldPose;foreach($key in $change.Keys){$v[$key]=$change[$key]};Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    $v=Copy-WorldPose
    $json=($v|ConvertTo-Json -Depth 6 -Compress).Replace('"perspective_request":1','"perspective_request":1,"perspective_request":2')
    [IO.File]::WriteAllText($poseFile,$json);Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true};$passed++

    # Packed collision geometry is allowed only on WorldBlocks, with exact
    # captured-origin binding and no partial, malformed or oversized boxes.
    foreach($complete in @($true,$false)){$v=Copy-WorldPose;$v.camera_collision.complete=$complete;$v.camera_collision.boxes='';Write-Pose $v
        $p=Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true;Require ($p.camera_collision.complete -eq $complete) 'Empty collision completeness changed.'};$passed++
    foreach($change in @(@{generation=0},@{generation=1.5},@{generation='1'},@{generation=10000001},@{complete='true'},@{complete=$false},@{boxes='g'*24},@{boxes='F'*24},@{boxes='0000'},@{boxes='0'*24},@{boxes='000004000000002104100010'},@{boxes='000004000000001004100010'*513},@{boxes=$null},@{extra=1})){
        $v=Copy-WorldPose;foreach($key in $change.Keys){$v.camera_collision[$key]=$change[$key]};Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    foreach($origin in @(@{x=0.1;y=0.;z=-64.},@{x='0';y=0.;z=-64.},@{x=0.;y=0.;z=-63.},@{x=0.;y=0.;z=-64.;extra=1},@{x=1e10;y=0.;z=-64.})){
        $v=Copy-WorldPose;$v.camera_collision.origin=$origin;Write-Pose $v;Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    foreach($duplicate in @('"generation":1,"generation":2','"complete":true,"complete":false','"boxes":"","boxes":""')){
        $v=Copy-WorldPose;$v.camera_collision.boxes='';$json=$v|ConvertTo-Json -Depth 6 -Compress
        $name=$duplicate.Split(':')[0];$pattern=switch($name){'"generation"' {'"generation":1'};'"complete"' {'"complete":true'};'"boxes"' {'"boxes":""'}}
        [IO.File]::WriteAllText($poseFile,$json.Replace($pattern,$duplicate));Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    }
    $v=Copy-WorldPose;$json=($v|ConvertTo-Json -Depth 6 -Compress).Replace('"origin":{','"origin":{"x":0,')
    [IO.File]::WriteAllText($poseFile,$json);Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true};$passed++
    $v=Copy-WorldPose;$v.camera_collision.boxes='000004000000001004100010'*512;Write-Pose $v
    Require ((Get-Item -LiteralPath $poseFile).Length -gt 4096) 'Large camera fixture did not exercise the extended file bound.'
    Require ((Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true).camera_collision.boxes.Length -eq 12288) 'Maximum512 camera boxes rejected.'
    Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now}
    [IO.File]::WriteAllText($poseFile,(' '*20481));Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true};$passed++

    # Windows ReplaceFile can report the deletion phase as 1175 instead of a
    # normal sharing violation. Only that replacement error preserves both
    # paths; 1176/1177 must still fail closed even when wrapped by PowerShell.
    foreach($code in @(5,32,33,1175,1176,1177,2,87)){
        $io=[IO.IOException]::new('publication fixture',([int](-2147024896+$code)))
        $wrapped=[Reflection.TargetInvocationException]::new($io)
        Require ((Test-GameplayPublicationRetry $wrapped) -eq ($code -in @(5,32,33,1175))) "Wrong publication retry policy for Win32 $code."
    };$passed++

    # Exercise the actual Windows sharing conflict. Failed attempts retain the
    # original bytes/UTC and bounded retry succeeds after the reader releases.
    $replaceTarget=Join-Path $directory 'sharing-view.json';$replaceTemp=$replaceTarget+'.tmp'
    [IO.File]::WriteAllText($replaceTarget,'old');$original='{"utc_ms":123,"seq":4}'
    [IO.File]::WriteAllText($replaceTemp,$original)
    $held=[IO.FileStream]::new($replaceTarget,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $watch=[Diagnostics.Stopwatch]::StartNew();Refuses {Publish-GameplayMovementView $replaceTemp $replaceTarget -RetryMilliseconds 25}
        Require ($watch.ElapsedMilliseconds -lt 500 -and [IO.File]::ReadAllText($replaceTemp) -ceq $original) 'Sharing retry was unbounded or rewrote original capture.'
    }finally{$held.Dispose()}
    $held=[IO.FileStream]::new($replaceTarget,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $release=[PowerShell]::Create();$signal=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
    try{
        $null=$release.AddScript('param($held,$signal);$signal["ready"]=$true;Start-Sleep -Milliseconds 40;$held.Dispose()').AddArgument($held).AddArgument($signal)
        $releaseAsync=$release.BeginInvoke();$until=[Diagnostics.Stopwatch]::StartNew()
        while(-not $signal.ContainsKey('ready') -and $until.ElapsedMilliseconds -lt 1000){Start-Sleep -Milliseconds 1}
        Require ($signal.ContainsKey('ready')) 'Sharing release worker did not start.'
        Publish-GameplayMovementView $replaceTemp $replaceTarget
        $null=$release.EndInvoke($releaseAsync)
        Require ([IO.File]::ReadAllText($replaceTarget) -ceq $original -and -not [IO.File]::Exists($replaceTemp)) 'Retried replacement lost original capture or atomic temp.'
    }finally{$held.Dispose();$release.Dispose()};$passed++

    # The real worker runs in a separate runspace against a simulated console/log.
    # Only this private fixture overrides the exact-process gate and transport.
    $helper=(Join-Path $PSScriptRoot 'GameplayMovementHost.ps1').Replace("'","''")
    $mock=@'
. '__HELPER__'
function Start-Sleep([int]$Milliseconds){
    if($WorldBlocks -and $Context.FixtureFault -in @('pipeline','sample_cadence','buffered_view') -and $stage -eq 'running'){
        $Shared['FixtureSleeps'].Enqueue([pscustomobject]@{Milliseconds=$Milliseconds;PendingView=($null -ne $pendingViewRequest)})
    }
    Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds
}
function Assert-MineComeProbeContext($Context){
    if($WorldBlocks -and $Context.FixtureFault -eq 'dispatch_delay' -and $request.Command -match "GameplayMovementSample\('[a-f0-9]+',(\d+)(,true)?\)"){
        $script:fixtureGateStarted=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Start-Sleep -Milliseconds 80
        $script:fixtureGateFinished=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    }
    if($WorldBlocks -and $Context.FixtureFault -eq 'prefetch_slow' -and $request.Command -match "GameplayMovementSample\('[a-f0-9]+',(\d+)(,true)?\)" -and [long]$Matches[1] -ge 2){Start-Sleep -Milliseconds 220}
}
$script:originalPublish=${function:Publish-GameplayMovementView}
function Publish-GameplayMovementView([string]$Temporary,[string]$Destination,[int]$RetryMilliseconds=100){
    $capture=$null;$started=0L
    if($WorldBlocks -and $Context.FixtureFault -eq 'pipeline' -and $Destination -in @($ViewFile,$aimFile)){
        $capture=[IO.File]::ReadAllText($Temporary)|ConvertFrom-Json;$started=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if($Destination -ceq $ViewFile){
            if($capture.seq -ge 6){$Shared['FixtureCancellationWasPending']=$Shared['FixtureSamples'].ContainsKey([string]($capture.seq+1));$Shared['FixtureCancel'].Cancel()}
            Start-Sleep -Milliseconds 70
        }
    }
    & $script:originalPublish $Temporary $Destination $RetryMilliseconds
    if($capture){$queueKey=if($Destination -ceq $ViewFile){'FixturePublications'}else{'FixtureAimPublications'};$Shared[$queueKey].Enqueue([pscustomobject]@{Sequence=[long]$capture.seq;UtcMs=[long]$capture.utc_ms;StartedUtc=$started;CompletedUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()})}
}
$script:fixtureSequence=0L
$script:fixtureUnterminated=$false
$script:fixtureBufferedSequence=0L
$script:fixtureGateStarted=0L;$script:fixtureGateFinished=0L
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){
    $body=[Uri]::UnescapeDataString($PathAndQuery.Substring($PathAndQuery.IndexOf('command=')+8))
    if($WorldBlocks){$Shared['FixtureCommands'].Enqueue($body)}
    # A native timer can emit its camera ACK after the request's flush. KCD's
    # latest log line then becomes readable only on a subsequent console flush.
    if($script:fixtureUnterminated){
        [IO.File]::AppendAllText($Context.GameLog,"`n");$script:fixtureUnterminated=$false
        if($WorldBlocks){$Shared['FixtureFlushes'][[string]$script:fixtureBufferedSequence]=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
    }
    $r=[ordered]@{schema=1;run=$Identity.Run;event='';result='';seq=0;active=$true;camera_basis_valid=$true;forward=@{x=0.;y=1.;z=0.};up=@{x=0.;y=0.;z=1.}}
    if($body.Contains('GameplayMovementBegin')){$r.event='begin';$r.result='ready'}
    elseif($body.Contains('GameplayMovementEnd')){
        $r.event='terminal';$r.result='explicit_stop';$r.active=$false
        if($WorldBlocks){
            $r.camera_override_changed=$Context.FixturePerspective -ne 0;$r.camera_restored=$Context.FixturePerspective -ne 0
            $r.body_visible_baseline_owned=$true;$r.body_restore_dispatched=$true;$r.body_hidden=$false
            switch($Context.FixtureFault){
                'cleanup_result' {$r.result='camera_restore_failed:explicit_stop'}
                'cleanup_active' {$r.active=$true}
                'cleanup_camera' {$r.camera_restored=$false}
                'cleanup_body' {$r.body_restore_dispatched=$false}
                'cleanup_hidden' {$r.body_hidden=$true}
                'cleanup_missing' {$r.Remove('body_restore_dispatched')}
                'cleanup_type' {$r.camera_restored='true'}
                'perspective_cleanup' {$r.camera_restored=$false}
            }
        }
    }
    elseif($body -match "GameplayMovementSample\('[a-f0-9]+',(\d+)(,true)?\)"){
        $r.event='view';$r.result='sampled';$r.seq=[long]$Matches[1]
        if($WorldBlocks){
            $Shared['FixtureSamples'][[string]$r.seq]=[pscustomobject]@{GateStarted=$script:fixtureGateStarted;GateFinished=$script:fixtureGateFinished;RequestedUtc=$requestedUtc;ExecutedUtc=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
            # Simulate a late receipt after one good sample. The worker must
            # retain sample1's UTC, even when the transport returns sample2.
            if($Context.FixtureFault -eq 'receipt_delay' -and $r.seq -ge 2){Start-Sleep -Milliseconds 270}
            $r.eye=@{x=1.;y=2.;z=4.62};$r.aim_direction=@{x=1.;y=0.;z=0.}
            $r.camera=@{x=1.;y=-1.;z=4.62};$r.camera_forward=@{x=0.;y=-1.;z=0.};$r.camera_up=@{x=0.;y=0.;z=1.}
            $r.perspective=$Context.FixturePerspective;$r.fov=1.2
            $r.aim=@{range=4.5;known=$true;distance=2.5;terrain_hit=$true}
            switch($Context.FixtureFault){
                'perspective' {$r.perspective=3}
                'perspective_cleanup' {$r.perspective=3}
                'fov' {$r.fov=0.0}
                'sequence' {$r.seq++}
            }
        }
    }
    if($r.event){
        $script:fixtureUnterminated=$WorldBlocks -and $Context.FixtureFault -eq 'buffered_view' -and $r.event -eq 'view'
        if($script:fixtureUnterminated){$script:fixtureBufferedSequence=$r.seq}
        $ending=if($script:fixtureUnterminated){''}else{"`n"}
        $line='[MineComeGameplayMovement] '+($r|ConvertTo-Json -Depth 5 -Compress)+$ending
        if($WorldBlocks -and $Context.FixtureFault -in @('pipeline','prefetch_slow') -and $r.event -eq 'view'){[MineCome.Tests.DelayedGameplayLog]::Append($Context.GameLog,$line,60)}else{[IO.File]::AppendAllText($Context.GameLog,$line)}
    }
    $script:fixtureSequence++
    $p=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$Identity.Run;world_id=$Identity.WorldId;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;seq=$script:fixtureSequence;utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();source_ms=$script:fixtureSequence*10;position=@{x=1.;y=2.;z=3.}}
    if($WorldBlocks){
        $p.perspective_request=$Context.FixturePerspective
        $p.camera_collision=[ordered]@{generation=1;complete=$true;origin=@{x=0.;y=0.;z=-64.};boxes=('000004000000001004100010'*$Context.FixtureBoxCount)}
        if($Context.FixtureCameraFault -eq 'incomplete'){$p.camera_collision.complete=$false;$p.camera_collision.boxes=''}
        if($Context.FixtureCameraFault -eq 'regress'){$p.camera_collision.generation=2}
        if($script:fixtureSequence -ge 5){
            switch($Context.FixtureCameraFault){
                'mutate' {$p.camera_collision.boxes='001004000000002004100010'}
                'regress' {$p.camera_collision.generation=1}
                'fresh' {$p.camera_collision.generation=2;$p.camera_collision.boxes='001004000000002004100010'}
            }
        }
    }
    [IO.File]::WriteAllText($PoseFile,($p|ConvertTo-Json -Depth 5 -Compress))
}
'@
    [IO.File]::WriteAllText((Join-Path $directory 'scripts/GameplayMovementHost.ps1'),$mock.Replace('__HELPER__',$helper))
    [IO.File]::WriteAllText($gameLog,'');[IO.File]::Delete($poseFile)
    $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new();$cancel=[Threading.CancellationTokenSource]::new()
    $runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open();$pipeline=[PowerShell]::Create();$pipeline.Runspace=$runspace
    $expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+5000
    $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument([pscustomobject]@{GameLog=$gameLog}).AddArgument($identity).AddArgument($bounds).AddArgument($poseFile).AddArgument($viewFile).AddArgument($expires).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($directory)
    $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
    do{
        if($shared.ContainsKey('Snapshot')){$s=$shared['Snapshot'];if($s.Stopped -or ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3)){break}}
        Start-Sleep -Milliseconds 10
    }while($watch.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted)
    $cancel.Cancel();Require ($async.AsyncWaitHandle.WaitOne(2000)) 'Fixture worker cleanup timed out.'
    $null=$pipeline.EndInvoke($async)
    Require (-not $pipeline.HadErrors) ('Worker errors: '+[string]$pipeline.Streams.Error)
    $s=$shared['Snapshot'];Require ($s.Stopped -and -not $s.Failure) ('Worker failed: '+$s.Failure)
    Require ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3) 'Worker did not continue refreshing pose and view.'
    Require ($s.Terminal.result -eq 'explicit_stop') 'Worker omitted native stop acknowledgement.'
    $view=Get-Content -LiteralPath $viewFile -Raw|ConvertFrom-Json
    Require ($view.run -ceq $identity.Run -and $view.source_kind -ceq 'live_kcd_hud_view_v1' -and $view.utc_ms -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) 'Published live-view contract differs.'
    Require (-not [IO.File]::Exists($viewFile+'.'+$identity.Run+'.tmp')) 'Atomic publication temp file survived.';$passed++
    $pipeline.Dispose();$pipeline=$null;$runspace.Dispose();$runspace=$null;$cancel.Dispose();$cancel=$null

    # Run the production worker in all three requested perspectives. Deliberately
    # distinct eye/render rays catch accidental use of the orbit camera for reach.
    foreach($case in @(@{Perspective=0;Fault=''},@{Perspective=1;Fault=''},@{Perspective=2;Fault=''},
        @{Perspective=1;Fault='perspective'},@{Perspective=1;Fault='fov'},@{Perspective=1;Fault='sequence'},
        @{Perspective=1;Fault='cleanup_result'},@{Perspective=1;Fault='cleanup_active'},@{Perspective=1;Fault='cleanup_camera'},
        @{Perspective=1;Fault='cleanup_body'},@{Perspective=1;Fault='cleanup_hidden'},@{Perspective=1;Fault='cleanup_missing'},
        @{Perspective=1;Fault='cleanup_type'},@{Perspective=1;Fault='perspective_cleanup'},@{Perspective=0;Fault='buffered_view'},
        @{Perspective=1;Fault='dispatch_delay'},@{Perspective=1;Fault='receipt_delay'},@{Perspective=1;Fault='sample_cadence'},@{Perspective=1;Fault='pipeline'},@{Perspective=1;Fault='prefetch_slow'},
        @{Perspective=1;Fault='';Boxes=512},@{Perspective=1;Fault='';CameraFault='incomplete'},
        @{Perspective=1;Fault='';CameraFault='mutate'},@{Perspective=1;Fault='';CameraFault='regress'},@{Perspective=1;Fault='';CameraFault='fresh'})){
        [IO.File]::WriteAllText($gameLog,'');[IO.File]::Delete($poseFile);[IO.File]::Delete($viewFile)
        $aimFile=Join-Path $directory 'gameplay-aim.json';[IO.File]::Delete($aimFile)
        $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
        $shared['FixtureCommands']=[Collections.Concurrent.ConcurrentQueue[string]]::new()
        $shared['FixtureSamples']=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
        $shared['FixtureFlushes']=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
        $shared['FixturePublications']=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $shared['FixtureAimPublications']=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $shared['FixtureSleeps']=[Collections.Concurrent.ConcurrentQueue[object]]::new()
        $cancel=[Threading.CancellationTokenSource]::new();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open()
        $shared['FixtureCancel']=$cancel
        $pipeline=[PowerShell]::Create();$pipeline.Runspace=$runspace
        $boxCount=if($case.ContainsKey('Boxes')){[int]$case['Boxes']}else{1}
        $cameraFault=if($case.ContainsKey('CameraFault')){[string]$case['CameraFault']}else{''}
        $minimumPoses=if($boxCount -gt 32){[int][Math]::Ceiling($boxCount/32.0)+3}elseif($cameraFault){6}else{3}
        $minimumViews=if($case.Fault -eq 'sample_cadence'){12}elseif($case.Fault -eq 'pipeline'){6}else{3}
        $context=[pscustomobject]@{GameLog=$gameLog;FixturePerspective=$case.Perspective;FixtureFault=$case.Fault;FixtureBoxCount=$boxCount;FixtureCameraFault=$cameraFault}
        $expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+5000
        $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument($context).AddArgument($identity).AddArgument($bounds).AddArgument($poseFile).AddArgument($viewFile).AddArgument($expires).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($directory).AddArgument($null).AddArgument($null).AddArgument($false).AddArgument($true)
        $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
        do{
            if($shared.ContainsKey('Snapshot')){$s=$shared['Snapshot'];if($s.Stopped -or ($s.ViewCount -ge $minimumViews -and $s.PoseCount -ge $minimumPoses) -or ($case.Fault -eq 'receipt_delay' -and $s.LastView -and $s.LastView.seq -ge 2) -or ($case.Fault -eq 'prefetch_slow' -and $s.LastView)){break}}
            Start-Sleep -Milliseconds 10
        }while($watch.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted)
        $cancel.Cancel();Require ($async.AsyncWaitHandle.WaitOne(2000)) 'WorldBlocks worker cleanup timed out.'
        $null=$pipeline.EndInvoke($async);Require (-not $pipeline.HadErrors) ('WorldBlocks worker errors: '+[string]$pipeline.Streams.Error)
        [MineCome.Tests.DelayedGameplayLog]::Drain()
        $s=$shared['Snapshot'];Require ($s.Stopped -and $null -ne $s.Terminal) 'WorldBlocks did not return native cleanup acknowledgement.'
        $commands=@($shared['FixtureCommands'].ToArray())
        Require (@($commands|Where-Object {$_ -match "GameplayMovementBegin\('[a-f0-9]+',[^)]*,true,true\)"}).Count -eq 1) 'WorldBlocks begin did not enable flight and camera authority.'
        Require (@($commands|Where-Object {$_ -match "GameplayMovementPose\('[a-f0-9]+',\d+,[0-9.]+,1,2,3,$($case.Perspective),[12]\)"}).Count -gt 0) 'WorldBlocks pose omitted its perspective request/collision generation.'
        Require (@($commands|Where-Object {$_ -match "GameplayMovementSample\('[a-f0-9]+',\d+,true\)"}).Count -gt 0) 'WorldBlocks did not request native aim.'
        Require ($s.MaxRequestPathLength -le 2000) 'Perspective request exceeded console URL bound.'
        $geometry=@(foreach($command in $commands){foreach($m in [regex]::Matches($command,"GameplayCameraGeometry\('[a-f0-9]+',(\d+),(\d+),(\d+),0,0,-64,(true|false),'([0-9a-f]*)'\)")){
            [pscustomobject]@{Generation=[int]$m.Groups[1].Value;Index=[int]$m.Groups[2].Value;Count=[int]$m.Groups[3].Value;Complete=$m.Groups[4].Value;Boxes=$m.Groups[5].Value}
        }})
        Require ($geometry.Count -gt 0) 'WorldBlocks never dispatched camera geometry.'
        foreach($chunk in $geometry){Require ($chunk.Boxes.Length -le 768 -and $chunk.Boxes.Length%24 -eq 0) 'Camera dispatch split a box or exceeded32 boxes.'}
        if($cameraFault -in @('mutate','regress')){
            Require ($s.Failure -ceq 'Gameplay camera collision generation regressed or changed.') "Camera $cameraFault was admitted: $($s.Failure)"
            Require ($geometry.Count -eq 1) 'Changed/replayed camera generation was partially dispatched.'
        }elseif($case.Fault.StartsWith('cleanup_')){
            $expected=switch($case.Fault){
                'cleanup_result' {'Native gameplay cleanup acknowledgement differs: camera_restore_failed:explicit_stop'}
                'cleanup_active' {'Native gameplay cleanup acknowledgement differs: explicit_stop'}
                'cleanup_camera' {'Native gameplay camera cleanup incomplete.'}
                'cleanup_body' {'Native gameplay body cleanup incomplete.'}
                'cleanup_hidden' {'Native gameplay body cleanup incomplete.'}
                'cleanup_missing' {'Native gameplay camera/body cleanup proof missing.'}
                'cleanup_type' {'Native gameplay camera/body cleanup proof missing.'}
            }
            Require ($s.Failure -ceq $expected -and $s.ViewCount -ge 3 -and $s.PoseCount -ge 3) "Native cleanup fault $($case.Fault) was accepted: $($s.Failure)"
        }elseif($case.Fault -eq 'receipt_delay'){
            Require (-not $s.Failure -and $s.ViewCount -eq 1 -and $s.LastView.seq -ge 2) 'Late receipt did not exercise the original250ms publication limit.'
            $aim=Get-Content -LiteralPath $aimFile -Raw|ConvertFrom-Json;$view=Get-Content -LiteralPath $viewFile -Raw|ConvertFrom-Json
            $first=$shared['FixtureSamples']['1']
            Require ($view.seq -eq 1 -and $aim.seq -eq 1 -and $view.utc_ms -eq $aim.utc_ms -and $view.utc_ms -le $first.ExecutedUtc) 'Late receipt renewed or replaced the previous camera sample.'
        }elseif($case.Fault -eq 'prefetch_slow'){
            Require (-not $s.Failure -and $s.ViewCount -eq 0 -and $s.LastView.seq -ge 1 -and $shared['FixtureSamples'].Count -ge 2) 'Slow prefetch did not complete/cancel its pending native query normally.'
            Require (-not [IO.File]::Exists($viewFile) -and [IO.File]::Exists($aimFile)) 'Slow prefetch did not retain the earlier fresh aim while rejecting the expired legacy view.'
            $aim=Get-Content -LiteralPath $aimFile -Raw|ConvertFrom-Json;$first=$shared['FixtureSamples']['1'];$firstTiming=@($s.ViewTiming.Samples|Where-Object Sequence -eq 1)[0]
            Require ($aim.seq -eq 1 -and $aim.utc_ms -eq $first.RequestedUtc -and $firstTiming.AimPublished -and $firstTiming.AimPublicationUtcMs-$aim.utc_ms -le 250 -and -not $firstTiming.Published) 'Early aim publication renewed its original timestamp or exceeded expiry.'
        }elseif($case.Fault -and $case.Fault -notin @('buffered_view','dispatch_delay','sample_cadence','pipeline')){
            $expected=switch($case.Fault){'perspective' {'Native gameplay perspective missing.'};'perspective_cleanup' {'Native gameplay perspective missing.'};'fov' {'World block camera FOV unavailable.'};'sequence' {'Native gameplay view acknowledgement differs.'}}
            Require ($s.Failure -ceq $expected -and -not [IO.File]::Exists($aimFile)) "Malformed native $($case.Fault) was published: $($s.Failure)"
        }else{
            Require (-not $s.Failure -and $s.ViewCount -ge 3 -and $s.PoseCount -ge 3) ('WorldBlocks worker failed: '+$s.Failure)
            $aim=Get-Content -LiteralPath $aimFile -Raw|ConvertFrom-Json
            $view=Get-Content -LiteralPath $viewFile -Raw|ConvertFrom-Json
            Require ($aim.schema -eq 3 -and $aim.kind -ceq 'minecome_gameplay_aim_v3' -and $aim.perspective -eq $case.Perspective) 'WorldBlocks schema/perspective acknowledgement differs.'
            foreach($field in @('run','world_id','patch_run','patch_sha256','target_pid','target_start_filetime')){
                Require ($aim.$field -ceq $valid[$field]) "WorldBlocks aim identity differs: $field"
            }
            Require ($aim.seq -eq $view.seq -and $aim.utc_ms -eq $view.utc_ms -and $aim.utc_ms -le [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) 'WorldBlocks aim renewed or mismatched camera capture.'
            $sampleTiming=$shared['FixtureSamples'][[string]$view.seq]
            Require ($view.utc_ms -le $sampleTiming.ExecutedUtc) 'View capture UTC was restamped after the actual sample executed.'
            if($case.Fault -eq 'dispatch_delay'){
                Require ($sampleTiming.GateFinished-$sampleTiming.GateStarted -ge 70 -and $view.utc_ms -ge $sampleTiming.GateFinished) 'View UTC includes pre-dispatch identity-gate delay.'
            }
            Require ($aim.origin.x -eq 1 -and $aim.origin.y -eq 2 -and $aim.origin.z -eq 4.62 -and $aim.direction.x -eq 1 -and $aim.direction.y -eq 0) 'Interaction ray did not retain the player eye.'
            Require ($aim.camera_origin.y -eq -1 -and $aim.camera_direction.y -eq -1 -and $aim.camera_up.z -eq 1 -and $aim.vertical_fov -eq 1.2) 'Third-person render camera basis differs.'
            Require ($view.forward.y -eq 1 -and $view.up.z -eq 1 -and $aim.range -eq 4.5 -and $aim.known -and $aim.distance -eq 2.5 -and $aim.terrain_hit) 'Movement direction or native occlusion was lost.'
            if($case.Fault -eq 'buffered_view'){
                Require (@($shared['FixtureSleeps'].ToArray()|Where-Object {$_.Milliseconds -eq 5 -and $_.PendingView}).Count -ge 1) 'Pending receipt polling no longer yields for5ms.'
                Require (@($commands|Where-Object {$_ -match 'MineComeGameplayViewFlush'}).Count -ge 1) 'Pending timer view fallback was never exercised.'
                $flushDelays=@(foreach($key in $shared['FixtureFlushes'].Keys){[long]$shared['FixtureFlushes'][$key]-[long]$shared['FixtureSamples'][$key].ExecutedUtc})
                $bufferedAverage=($flushDelays|Measure-Object -Average).Average
                Require ($flushDelays.Count -ge 3 -and $bufferedAverage -lt 45) "Buffered camera ACKs still waited for the old50ms fallback: average=$bufferedAverage ms."
            }
            if($case.Fault -eq 'sample_cadence'){
                Require (@($shared['FixtureSleeps'].ToArray()|Where-Object {$_.Milliseconds -eq 10 -and -not $_.PendingView}).Count -ge 1) 'No-query worker loop lost its idle wait.'
                $samples=@($shared['FixtureSamples'].Values|Sort-Object ExecutedUtc)
                # Skip two warm-up dispatches, then distinguish the new live
                # cadence from the former90ms floor without timing one frame.
                $cadenceAverage=($samples[-1].ExecutedUtc-$samples[2].ExecutedUtc)/[double]($samples.Count-3)
                Require ($samples.Count -ge 12 -and $cadenceAverage -lt 85) "Native camera samples retain the old cadence: average=$cadenceAverage ms."
            }
            if($case.Fault -eq 'pipeline'){
                Require (@($shared['FixtureSleeps'].ToArray()|Where-Object {$_.Milliseconds -eq 10 -and $_.PendingView}).Count -eq 0) 'Prefetched camera query was delayed by the outer idle wait.'
                $publications=@($shared['FixturePublications'].ToArray());$aimPublications=@($shared['FixtureAimPublications'].ToArray());$overlaps=0;$shortIntervals=0;$poseGaps=0
                foreach($publication in $publications){
                    $sample=$shared['FixtureSamples'][[string]$publication.Sequence]
                    Require ($publication.UtcMs -eq $sample.RequestedUtc -and $publication.UtcMs -le $sample.ExecutedUtc) 'Pipelined publication mixed its sequence or original capture UTC.'
                    $earlyAim=@($aimPublications|Where-Object Sequence -eq $publication.Sequence)
                    Require ($earlyAim.Count -eq 1 -and $earlyAim[0].UtcMs -eq $publication.UtcMs -and $earlyAim[0].CompletedUtc -le $publication.StartedUtc) 'Renderer camera was not published before legacy view work.'
                    $nextKey=[string]($publication.Sequence+1)
                    if($shared['FixtureSamples'].ContainsKey($nextKey)){
                        $next=$shared['FixtureSamples'][$nextKey]
                        Require ($earlyAim[0].CompletedUtc -le $next.ExecutedUtc) 'Next camera dispatch delayed publication of the current renderer camera.'
                        if($next.ExecutedUtc -le $publication.StartedUtc -and $next.ExecutedUtc+60 -gt $publication.StartedUtc -and $next.ExecutedUtc -lt $publication.CompletedUtc){$overlaps++}
                        if($next.ExecutedUtc-$sample.ExecutedUtc -lt 125){$shortIntervals++}
                    }
                }
                for($n=2;$n -lt $s.ViewCount;$n++){
                    $previous=-1;$next=-1
                    for($i=0;$i -lt $commands.Count;$i++){if($commands[$i].Contains("GameplayMovementSample('$($identity.Run)',$n,true)")){$previous=$i};if($commands[$i].Contains("GameplayMovementSample('$($identity.Run)',$($n+1),true)")){$next=$i}}
                    if($previous -ge 0 -and $next -gt $previous+1 -and @($commands[($previous+1)..($next-1)]|Where-Object {$_ -match 'GameplayMovementPose'}).Count){$poseGaps++}
                }
                Require ($overlaps -ge 2 -and $shortIntervals -ge 2) "Camera pipeline did not overlap60ms native ACK waits with70ms publication: overlaps=$overlaps short_intervals=$shortIntervals."
                Require ($poseGaps -ge 2 -and $s.PoseCount -ge $s.ViewCount) 'Pipelined ACKs starved the outer pose loop.'
                Require ($shared['FixtureCancellationWasPending'] -and $shared['FixtureSamples'].Count -gt $s.ViewCount -and $s.Terminal.result -ceq 'explicit_stop') 'Cancellation did not exercise cleanup with a prefetched view outstanding.'
                Write-Output "HOST_PIPELINE overlaps=$overlaps shortened_intervals=$shortIntervals pose_gaps=$poseGaps"
            }
        }
        if(-not $case.Fault -and $cameraFault -notin @('mutate','regress')){
            if($cameraFault -eq 'fresh'){
                Require ($geometry.Count -eq 2 -and $geometry[0].Generation -eq 1 -and $geometry[1].Generation -eq 2 -and $geometry[0].Boxes -cne $geometry[1].Boxes) 'Fresh geometry replacement was lost or repeated.'
            }else{
                $expectedChunks=if($cameraFault -eq 'incomplete'){1}else{[int][Math]::Ceiling($boxCount/32.0)}
                Require ($geometry.Count -eq $expectedChunks) 'Stable geometry was resent or chunks were lost.'
                for($i=0;$i -lt $geometry.Count;$i++){Require ($geometry[$i].Index -eq $i+1 -and $geometry[$i].Count -eq $expectedChunks -and $geometry[$i].Generation -eq 1) 'Camera staging order/count/generation differed.'}
                $expectedPacked=if($cameraFault -eq 'incomplete'){''}else{'000004000000001004100010'*$boxCount}
                Require (($geometry.Boxes -join '') -ceq $expectedPacked) 'Atomic camera chunks changed or dropped packed geometry.'
                Require ($geometry[0].Complete -ceq $(if($cameraFault -eq 'incomplete'){'false'}else{'true'})) 'Camera completeness flag changed.'
            }
        }
        Require (-not [IO.File]::Exists($viewFile+'.'+$identity.Run+'.tmp') -and -not [IO.File]::Exists($aimFile+'.'+$identity.Run+'.tmp')) 'WorldBlocks temporary camera publication survived cleanup.'
        $pipeline.Dispose();$pipeline=$null;$runspace.Dispose();$runspace=$null;$cancel.Dispose();$cancel=$null;$passed++
    }
    Write-Output "PASS $passed gameplay host contract/worker checks (simulated transport; no game/network)"
    Write-Output ("HOST_TIMING sample_interval_average_ms={0:F1} buffered_ack_average_ms={1:F1}" -f $cadenceAverage,$bufferedAverage)
}finally{
    [MineCome.Tests.DelayedGameplayLog]::Drain()
    if($cancel){$cancel.Cancel()};if($pipeline){$pipeline.Dispose()};if($runspace){$runspace.Dispose()};if($cancel){$cancel.Dispose()}
    $resolved=[IO.Path]::GetFullPath($directory);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('minecome-gameplay-host-test-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
