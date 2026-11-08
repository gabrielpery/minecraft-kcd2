#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Standalone pose-file and worker transport fixture; no game or network calls.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-gameplay-host-test-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $directory 'scripts')
$poseFile=Join-Path $directory 'pose.json';$viewFile=Join-Path $directory 'view.json';$gameLog=Join-Path $directory 'game.log'
$identity=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64}
$bounds=[pscustomobject]@{MinX=-10.;MaxX=10.;MinY=-10.;MaxY=10.;MinZ=-10.;MaxZ=10.}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$valid=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$identity.Run;world_id=$identity.WorldId;target_pid=$identity.Pid;target_start_filetime=$identity.Start;patch_run=$identity.PatchRun;patch_sha256=$identity.PatchHash;seq=1;utc_ms=$now;source_ms=0;position=@{x=1.;y=2.;z=3.}}
$passed=0;$pipeline=$null;$runspace=$null;$cancel=$null
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Pose($Value){$Value|ConvertTo-Json -Depth 6 -Compress|Set-Content -LiteralPath $poseFile -Encoding utf8NoBOM}
function Copy-Pose{$copy=@{};foreach($key in $valid.Keys){$copy[$key]=$valid[$key]};return $copy}
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
        $v=Copy-Pose;$v.perspective_request=$perspective;Write-Pose $v
        $p=Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true
        Require ($p.perspective_request -eq $perspective) 'WorldBlocks perspective request changed.'
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now}
        Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 1 0 $now $true)) 'WorldBlocks duplicate renewed its request.'
        Require ($null -eq (Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 ($now+251) $true)) 'WorldBlocks stale request was admitted.'
    };$passed++
    foreach($perspective in @(-1,3,1.5,'1',$true,$null)){
        $v=Copy-Pose;$v.perspective_request=$perspective;Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    foreach($change in @(@{run='d'*32},@{world_id='other'},@{target_pid=999},@{target_start_filetime='different'},@{patch_run='e'*32},@{patch_sha256='f'*64},@{utc_ms=$now+51},@{source_ms=86400001},@{seq=0})){
        $v=Copy-Pose;$v.perspective_request=1;foreach($key in $change.Keys){$v[$key]=$change[$key]};Write-Pose $v
        Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true}
    };$passed++
    $v=Copy-Pose;$v.perspective_request=1
    $json=($v|ConvertTo-Json -Depth 6 -Compress).Replace('"perspective_request":1','"perspective_request":1,"perspective_request":2')
    [IO.File]::WriteAllText($poseFile,$json);Refuses {Read-GameplayMovementPose $poseFile $identity $bounds 0 -1 $now $true};$passed++

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
function Assert-MineComeProbeContext($Context){}
$script:fixtureSequence=0L
$script:fixtureUnterminated=$false
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){
    $body=[Uri]::UnescapeDataString($PathAndQuery.Substring($PathAndQuery.IndexOf('command=')+8))
    if($WorldBlocks){$Shared['FixtureCommands'].Enqueue($body)}
    # A native timer can emit its camera ACK after the request's flush. KCD's
    # latest log line then becomes readable only on a subsequent console flush.
    if($script:fixtureUnterminated){[IO.File]::AppendAllText($Context.GameLog,"`n");$script:fixtureUnterminated=$false}
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
        $ending=if($script:fixtureUnterminated){''}else{"`n"}
        [IO.File]::AppendAllText($Context.GameLog,('[MineComeGameplayMovement] '+($r|ConvertTo-Json -Depth 5 -Compress)+$ending))
    }
    $script:fixtureSequence++
    $p=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$Identity.Run;world_id=$Identity.WorldId;target_pid=$Identity.Pid;target_start_filetime=$Identity.Start;patch_run=$Identity.PatchRun;patch_sha256=$Identity.PatchHash;seq=$script:fixtureSequence;utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();source_ms=$script:fixtureSequence*10;position=@{x=1.;y=2.;z=3.}}
    if($WorldBlocks){$p.perspective_request=$Context.FixturePerspective}
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
        @{Perspective=1;Fault='cleanup_type'},@{Perspective=1;Fault='perspective_cleanup'},@{Perspective=0;Fault='buffered_view'})){
        [IO.File]::WriteAllText($gameLog,'');[IO.File]::Delete($poseFile);[IO.File]::Delete($viewFile)
        $aimFile=Join-Path $directory 'gameplay-aim.json';[IO.File]::Delete($aimFile)
        $shared=[Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
        $shared['FixtureCommands']=[Collections.Concurrent.ConcurrentQueue[string]]::new()
        $cancel=[Threading.CancellationTokenSource]::new();$runspace=[RunspaceFactory]::CreateRunspace();$runspace.Open()
        $pipeline=[PowerShell]::Create();$pipeline.Runspace=$runspace
        $context=[pscustomobject]@{GameLog=$gameLog;FixturePerspective=$case.Perspective;FixtureFault=$case.Fault}
        $expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+5000
        $null=$pipeline.AddScript((Get-GameplayMovementWorker).ToString()).AddArgument($context).AddArgument($identity).AddArgument($bounds).AddArgument($poseFile).AddArgument($viewFile).AddArgument($expires).AddArgument(0L).AddArgument($shared).AddArgument($cancel.Token).AddArgument($directory).AddArgument($null).AddArgument($null).AddArgument($false).AddArgument($true)
        $async=$pipeline.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
        do{
            if($shared.ContainsKey('Snapshot')){$s=$shared['Snapshot'];if($s.Stopped -or ($s.ViewCount -ge 3 -and $s.PoseCount -ge 3)){break}}
            Start-Sleep -Milliseconds 10
        }while($watch.ElapsedMilliseconds -lt 3000 -and -not $async.IsCompleted)
        $cancel.Cancel();Require ($async.AsyncWaitHandle.WaitOne(2000)) 'WorldBlocks worker cleanup timed out.'
        $null=$pipeline.EndInvoke($async);Require (-not $pipeline.HadErrors) ('WorldBlocks worker errors: '+[string]$pipeline.Streams.Error)
        $s=$shared['Snapshot'];Require ($s.Stopped -and $null -ne $s.Terminal) 'WorldBlocks did not return native cleanup acknowledgement.'
        $commands=@($shared['FixtureCommands'].ToArray())
        Require (@($commands|Where-Object {$_ -match "GameplayMovementBegin\('[a-f0-9]+',[^)]*,true,true\)"}).Count -eq 1) 'WorldBlocks begin did not enable flight and camera authority.'
        Require (@($commands|Where-Object {$_ -match "GameplayMovementPose\('[a-f0-9]+',\d+,[0-9.]+,1,2,3,$($case.Perspective)\)"}).Count -gt 0) 'WorldBlocks pose omitted its perspective request.'
        Require (@($commands|Where-Object {$_ -match "GameplayMovementSample\('[a-f0-9]+',\d+,true\)"}).Count -gt 0) 'WorldBlocks did not request native aim.'
        Require ($s.MaxRequestPathLength -le 2000) 'Perspective request exceeded console URL bound.'
        if($case.Fault.StartsWith('cleanup_')){
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
        }elseif($case.Fault -and $case.Fault -ne 'buffered_view'){
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
            Require ($aim.origin.x -eq 1 -and $aim.origin.y -eq 2 -and $aim.origin.z -eq 4.62 -and $aim.direction.x -eq 1 -and $aim.direction.y -eq 0) 'Interaction ray did not retain the player eye.'
            Require ($aim.camera_origin.y -eq -1 -and $aim.camera_direction.y -eq -1 -and $aim.camera_up.z -eq 1 -and $aim.vertical_fov -eq 1.2) 'Third-person render camera basis differs.'
            Require ($view.forward.y -eq 1 -and $view.up.z -eq 1 -and $aim.range -eq 4.5 -and $aim.known -and $aim.distance -eq 2.5 -and $aim.terrain_hit) 'Movement direction or native occlusion was lost.'
            if($case.Fault -eq 'buffered_view'){
                Require (@($commands|Where-Object {$_ -match 'MineComeGameplayViewFlush'}).Count -ge 3) 'Pending timer views were not flushed within their original acknowledgement deadline.'
            }
        }
        Require (-not [IO.File]::Exists($viewFile+'.'+$identity.Run+'.tmp') -and -not [IO.File]::Exists($aimFile+'.'+$identity.Run+'.tmp')) 'WorldBlocks temporary camera publication survived cleanup.'
        $pipeline.Dispose();$pipeline=$null;$runspace.Dispose();$runspace=$null;$cancel.Dispose();$cancel=$null;$passed++
    }
    Write-Output "PASS $passed gameplay host contract/worker checks (simulated transport; no game/network)"
}finally{
    if($cancel){$cancel.Cancel()};if($pipeline){$pipeline.Dispose()};if($runspace){$runspace.Dispose()};if($cancel){$cancel.Dispose()}
    $resolved=[IO.Path]::GetFullPath($directory);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved).StartsWith('minecome-gameplay-host-test-')){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
