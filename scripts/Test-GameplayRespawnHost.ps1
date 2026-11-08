#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure parser/state/receipt/capture fixtures; no game or network access.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'GameplayMovementHost.ps1')
$directory=Join-Path ([IO.Path]::GetTempPath()) ('minecome-respawn-host-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $directory
$path=Join-Path $directory 'pose.json';$passed=0
$identity=[pscustomobject]@{Run='a'*32;WorldId='11111111-1111-4111-8111-111111111111';Pid=123;Start='133456789012345678';PatchRun='b'*32;PatchHash='c'*64;CameraOrigin=[pscustomobject]@{x=0.;y=0.;z=-64.}}
$bounds=[pscustomobject]@{MinX=-10.;MaxX=10.;MinY=-10.;MaxY=10.;MinZ=-10.;MaxZ=10.}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Refuses([scriptblock]$Action){$threw=$false;try{& $Action|Out-Null}catch{$threw=$true};Require $threw 'Invalid lifecycle accepted.'}
function Pose([string]$Phase='dead',[long]$Seq=1,[long]$Epoch=1,[double]$X=1){
    $p=[ordered]@{schema=1;kind='minecome_gameplay_pose_v1';run=$identity.Run;world_id=$identity.WorldId;target_pid=$identity.Pid;target_start_filetime=$identity.Start;patch_run=$identity.PatchRun;patch_sha256=$identity.PatchHash;seq=$Seq;utc_ms=$now;source_ms=$Seq*50;position=[pscustomobject]@{x=$X;y=2.;z=3.};perspective_request=0;camera_collision=@{generation=1;complete=$true;origin=$identity.CameraOrigin;boxes=''}}
    if($Phase -cne 'alive'){$p.lifecycle=$Phase;$p.respawn_epoch=$Epoch}
    if($Phase -ceq 'respawn'){$p.respawn_from=[pscustomobject]@{x=1.;y=2.;z=3.}}
    return [pscustomobject]$p
}
function Write-Pose($P){[IO.File]::WriteAllText($path,($P|ConvertTo-Json -Depth 6 -Compress))}
function Receipt($State){[pscustomobject]@{schema=1;run=$identity.Run;event='lifecycle';result='applied';active=$true;seq=$State.LastSequence;pose_seq=$State.LastSequence;applied_seq=$State.LastSequence;lifecycle=$State.Phase;respawn_epoch=$State.Epoch;from=$State.From;target=$State.Target;player=$State.Target}}
function Dead-State{
    $s=New-GameplayRespawnHostState;Update-GameplayRespawnHostPose $s (Pose) $now
    $null=Accept-GameplayRespawnReceipt $s (Receipt $s) $identity $now;return $s
}
try{
    foreach($phase in @('dead','respawn')){
        $p=Pose $phase;Write-Pose $p
        $read=Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true
        Require ($read.lifecycle -ceq $phase -and $read.respawn_epoch -eq 1) 'Lifecycle fields changed.'
        Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now}
        Require ($null -eq (Read-GameplayMovementPose $path $identity $bounds 1 50 $now $true)) 'Replay renewed lifecycle.'
        Require ($null -eq (Read-GameplayMovementPose $path $identity $bounds 0 -1 ($now+251) $true)) 'Stale death renewed lifecycle.'
    };$passed++
    foreach($epoch in @(0,-1,1.5,'1',$true,10000001)){$p=Pose;$p.respawn_epoch=$epoch;Write-Pose $p;Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true}};$passed++
    foreach($field in @('run','world_id','patch_run','patch_sha256','target_start_filetime')){
        $p=Pose 'respawn';$p.$field='wrong';Write-Pose $p;Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true}
    };$passed++
    foreach($from in @(@{x=1.;y=2.;z=3.;extra=1},@{x='1';y=2.;z=3.},@{x=1e10;y=2.;z=3.},@{x=1.;z=3.},$null)){
        $p=Pose 'respawn';$p.respawn_from=$from;Write-Pose $p;Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true}
    };$passed++
    $p=Pose 'respawn';$json=($p|ConvertTo-Json -Depth 6 -Compress).Replace('"respawn_from":{"x":1.0','"respawn_from":{"x":2,"x":1.0')
    Require ($json -match '"x":2,"x":1.0') 'Duplicate fixture did not mutate.'
    [IO.File]::WriteAllText($path,$json);Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true};$passed++
    $p=Pose 'respawn' 1 1 11;Write-Pose $p;Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true};$passed++
    $p=Pose;$p.lifecycle='alive';Write-Pose $p;Refuses {Read-GameplayMovementPose $path $identity $bounds 0 -1 $now $true};$passed++

    $s=New-GameplayRespawnHostState;Update-GameplayRespawnHostPose $s (Pose) $now
    Refuses {Update-GameplayRespawnHostPose $s (Pose 'alive' 2) $now}
    Refuses {Update-GameplayRespawnHostPose $s (Pose 'respawn' 2 1 8) $now}
    $ack=Accept-GameplayRespawnReceipt $s (Receipt $s) $identity $now
    Require ($ack.lifecycle -ceq 'dead' -and $ack.world_id -ceq $identity.WorldId -and $ack.patch_sha256 -ceq $identity.PatchHash) 'Dead receipt lost binding.'
    Refuses {Accept-GameplayRespawnReceipt $s (Receipt $s) $identity $now}
    Update-GameplayRespawnHostPose $s (Pose 'respawn' 2 1 8) $now
    Refuses {Update-GameplayRespawnHostPose $s (Pose 'alive' 3 1 8) $now}
    $ack=Accept-GameplayRespawnReceipt $s (Receipt $s) $identity $now
    Require ($ack.lifecycle -ceq 'respawn' -and $ack.from.x -eq 1 -and $ack.target.x -eq 8) 'Respawn receipt changed targets.'
    $temporary=Join-Path $directory 'respawn-ack.tmp';$destination=Join-Path $directory 'respawn-ack.json'
    [IO.File]::WriteAllText($temporary,($ack|ConvertTo-Json -Depth 5 -Compress));Publish-GameplayMovementView $temporary $destination
    Require ((([IO.File]::ReadAllText($destination)|ConvertFrom-Json).respawn_epoch) -eq 1) 'Acknowledgement publication differs.'
    Update-GameplayRespawnHostPose $s (Pose 'alive' 3 1 8) $now
    Refuses {Update-GameplayRespawnHostPose $s (Pose 'dead' 4 1 8) $now}
    Update-GameplayRespawnHostPose $s (Pose 'dead' 4 2 8) $now;Require ($s.Epoch -eq 2 -and -not $s.Acked) 'Second death did not advance epoch.';$passed++

    foreach($fault in @('epoch','origin','target','player','sequence','phase','run','active','expired','replay','unapplied','unobserved')){
        $s=Dead-State;Update-GameplayRespawnHostPose $s (Pose 'respawn' 2 1 8) $now;$r=Receipt $s;$at=$now
        switch($fault){
            epoch {$r.respawn_epoch=2};origin {$r.from=[pscustomobject]@{x=2.;y=2.;z=3.}}
            target {$r.target=[pscustomobject]@{x=7.;y=2.;z=3.}};player {$r.player=[pscustomobject]@{x=7.;y=2.;z=3.}}
            sequence {$r.seq=3};phase {$r.lifecycle='dead'};run {$r.run='d'*32};active {$r.active=$false}
            expired {$at+=2001};replay {$null=Accept-GameplayRespawnReceipt $s $r $identity $at}
            unapplied {$r.applied_seq=1};unobserved {$r.pose_seq=1}
        }
        Refuses {Accept-GameplayRespawnReceipt $s $r $identity $at}
    };$passed++
    # Real ca3f0e0e native death: the caller publishes doubles, KCD reports the
    # exact float32 target. Original doubles stay in the guest ACK unchanged.
    $requested=[pscustomobject]@{x=128.60006200907225;y=2035.143202911346;z=56.79007339477539}
    $native=[pscustomobject]@{x=128.60006713867188;y=2035.1431884765625;z=56.790073394775391}
    foreach($fault in @('none','interpolating','nearby','adjacent_float','replay','target_changed')){
        $s=New-GameplayRespawnHostState;$p=Pose 'dead' 174;$p.position=$requested;Update-GameplayRespawnHostPose $s $p $now
        $r=Receipt $s;$r.from=$native;$r.target=$native;$r.player=$native
        $p=Pose 'dead' 175;$p.position=$requested;Update-GameplayRespawnHostPose $s $p $now
        switch($fault){
            interpolating {$r.applied_seq=140;$r.player=[pscustomobject]@{x=128.59869384765625;y=2035.1328125;z=56.803638458251953}}
            nearby {$r.player=[pscustomobject]@{x=$native.x+0.000001;y=$native.y;z=$native.z}}
            adjacent_float {$r.target=[pscustomobject]@{x=[double][BitConverter]::Int32BitsToSingle([BitConverter]::SingleToInt32Bits([single]$native.x)+1);y=$native.y;z=$native.z}}
            target_changed {$r.target=$requested.PSObject.Copy();$r.target.x+=.01}
            replay {$null=Accept-GameplayRespawnReceipt $s $r $identity $now}
        }
        if($fault -ceq 'none'){$ack=Accept-GameplayRespawnReceipt $s $r $identity $now;Require (Test-GameplayRespawnPoint $ack.target $requested) 'Native rounding leaked into guest target identity.'}
        else {Refuses {Accept-GameplayRespawnReceipt $s $r $identity $now}}
    };$passed++
    foreach($fault in @('frozen','origin','epoch','reverse','target','expiry')){
        $s=Dead-State;$p=Pose 'respawn' 2 1 8;$at=$now
        switch($fault){
            frozen {$p=Pose 'dead' 2 1 1.1};origin {$p.respawn_from=[pscustomobject]@{x=1.1;y=2.;z=3.}}
            epoch {$p.respawn_epoch=2};reverse {Update-GameplayRespawnHostPose $s $p $now;$p=Pose 'dead' 3}
            target {Update-GameplayRespawnHostPose $s $p $now;$p=Pose 'respawn' 3 1 8.1}
            expiry {Update-GameplayRespawnHostPose $s $p $now;$p=Pose 'respawn' 3 1 8;$at+=2001}
        }
        Refuses {Update-GameplayRespawnHostPose $s $p $at}
    };$passed++
    $s=Dead-State;Update-GameplayRespawnHostPose $s (Pose 'respawn' 2 1 8) $now
    $null=Accept-GameplayRespawnReceipt $s (Receipt $s) $identity $now
    Update-GameplayRespawnHostPose $s (Pose 'dead' 3 2 8) $now
    Require ($s.Epoch -eq 2 -and $s.Phase -ceq 'dead' -and -not $s.Acked) 'Skipped alive publication broke next death.';$passed++

    $points=@(for($row=0;$row -lt 3;$row++){for($col=0;$col -lt 3;$col++){[pscustomobject]@{valid=$true;x=[double]$col;y=[double]$row;z=0.}}})
    $patchPath=Join-Path $directory 'patch.json';[IO.File]::WriteAllText($patchPath,(@{grid_size=3;spacing=1;points=$points}|ConvertTo-Json -Depth 5))
    $coverage=@(Get-GameplayRespawnCoverage ([pscustomobject]@{Path=$patchPath}))
    Require (Test-GameplayRespawnCoverage $coverage ([pscustomobject]@{x=1.;y=1.;z=0.})) 'Captured footprint refused.'
    Require (-not(Test-GameplayRespawnCoverage $coverage ([pscustomobject]@{x=.2;y=1.;z=0.}))) 'Partial footprint accepted.'
    [void]$coverage[0].Valid.Remove('1,1')
    Require (-not(Test-GameplayRespawnCoverage $coverage ([pscustomobject]@{x=1.;y=1.;z=0.}))) 'Unknown captured cell accepted.';$passed++
    Write-Output "PASS $passed respawn host parser/state/receipt checks (simulated; no game/network)"
}finally{
    # All created files are immediate children of this fresh unique temp folder.
    foreach($file in [IO.Directory]::EnumerateFiles($directory)){[IO.File]::Delete($file)}
    [IO.Directory]::Delete($directory)
}
