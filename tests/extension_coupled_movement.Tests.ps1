#requires -Version 7.3
# Synthetic receiver/readback contract only. No game, process or renderer calls.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'scripts/HudGroundMovement.ps1')
. (Join-Path $root 'scripts/MovementTraceReceiver.ps1')
. (Join-Path $root 'scripts/HudGroundExtension.ps1')
. (Join-Path $root 'scripts/GroundExtensionMovementProof.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20}
$run='a'*32;$hudRun='b'*32;$world='12345678-1234-1234-1234-123456789abc';$save='MineCome-HudStream-'+$world
$utc=1700000000000L;$start='134363864241979118'
$dir=Join-Path $root ('runtime/evidence/extension-coupled-pure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
$path=Join-Path $dir 'extension.json';$trace=Join-Path $dir 'movement.ndjson'
$manifest=New-HudGroundExtensionFixture $run
# This fixture deliberately carries live labels solely to exercise the pure
# receiver. Real capture/process authentication remains the controller's job.
for($i=0;$i -lt 3;$i++){
    $tile=$manifest.tiles[$i].json | ConvertFrom-Json
    $tile.provenance.kind='live_kcd_ground_patch'
    $tile | Add-Member approximate_heightfield $true
    $tile | Add-Member full_collision_export_verified $false
    $manifest.tiles[$i].json=$tile | ConvertTo-Json -Depth 12 -Compress
    $manifest.tiles[$i].sha256=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($manifest.tiles[$i].json))
}
function Save-Extension($InputManifest){
    [IO.File]::WriteAllText($path,($InputManifest | ConvertTo-Json -Depth 12 -Compress),[Text.UTF8Encoding]::new($false))
    $first=$InputManifest.tiles[0].json | ConvertFrom-Json
    return [pscustomobject]@{Path=$path;Hash=(Get-FileHash $path).Hash.ToLowerInvariant();Run=$InputManifest.run;
        Anchor=$first.center;TileHashes=@($InputManifest.tiles.sha256);Captured=$true}
}
function Receiver($InputExtension,[switch]$Unused){New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -ExtensionWalking -Extension $InputExtension}
function Trace-Record($State,[string]$Kind,[int]$Seq,[string]$Phase='WALKING',[double]$X=.5){
    $r=[ordered]@{schema=1;kind=$Kind;run=$State.ExpectedRun;patch_sha256=$State.PatchHash;source_kind='hud_extension_walk_coupled';walking_area='extension';save=$save;world=$world;seq=$Seq;utc_ms=$utc;phase=$Phase}
    if($Kind -ceq 'begin'){
        $r.phase='SETTLING';$r.started_monotonic_ns=100L;$r.center=$State.Center;$r.anchor_mc=@{x=0;y=64;z=0}
        $r.approximate_heightfield=$true;$r.full_collision_export_verified=$false
    }elseif($Kind -ceq 'end'){$r.result='passed';$r.reason='';$r.last_server_seq=$Seq-2}
    else{
        $r.monotonic_ns=100L+($Seq-1)*90000000L;$r.server_seq=$Seq-1;$r.server_age_ns=0L
        foreach($side in @('client','server')){$r[$side]=@{x=$X;y=64;z=.5;vx=0;vy=0;vz=0;on_ground=$true;proxy_support=$true}}
    }
    return $r
}
function Receive($State,$Record,[long]$Now=$utc){Receive-MineComeMovementTrace $State ($Record | ConvertTo-Json -Depth 8 -Compress) $Now}
function Reject-Record($State,$Record,[string]$Message){
    $before=$State | ConvertTo-Json -Depth 12 -Compress
    Reject {Receive $State $Record} $Message
    Check (($State | ConvertTo-Json -Depth 12 -Compress) -ceq $before) 'Rejected extension record mutated receiver state'
}
function Begin($State){$null=Receive $State (Trace-Record $State begin 1)}
function Rehash-Tile($InputManifest,[int]$Index,$Tile){
    $InputManifest.tiles[$Index].json=$Tile | ConvertTo-Json -Depth 12 -Compress
    $InputManifest.tiles[$Index].sha256=Get-HudExtensionHash ([Text.Encoding]::UTF8.GetBytes($InputManifest.tiles[$Index].json))
}
try{
    $extension=Save-Extension $manifest
    $state=Receiver $extension
    Check ($state.Extension -eq $extension -and $state.Center.x -eq 120 -and -not $state.WideWalking) 'One fixed authenticated extension origin'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -WideWalking -ExtensionWalking -Extension $extension} 'Wide and extension combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -PhysicalMovement -ExtensionWalking -Extension $extension} 'Physical and extension combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -ScriptedHudCoupled -ExtensionWalking -Extension $extension} 'Legacy and extension combined'
    Reject {New-MineComeTraceReceiver -PatchFile $path -MinimumUtcMs $utc -ExpectedHudSave $save -Extension $extension} 'Extension implicitly selected'
    foreach($field in @('Hash','Run','Path')){$bad=Clone $extension;$bad.$field='different';Reject {Receiver $bad} "Unbound capture $field accepted"}
    $bad=Clone $extension;$bad.Captured=$false;Reject {Receiver $bad} 'Fixture admitted as captured extension'
    $bad=Clone $extension;$bad.Anchor.x+=4;Reject {Receiver $bad} 'Rebased authenticated origin accepted'
    foreach($mutation in @(
        {param($m)$m.tiles[1].sha256='0'*64},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.center.x+=1;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.points[0].z+=.01;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.points[80].x+=1;Rehash-Tile $m 1 $p},
        {param($m)$p=$m.tiles[1].json | ConvertFrom-Json;$p.provenance.kind='standalone_fixture';Rehash-Tile $m 1 $p},
        {param($m)$m | Add-Member unexpected $true}
    )){$bad=Clone $manifest;& $mutation $bad;$identity=Save-Extension $bad;Reject {Receiver $identity} 'Invalid extension geometry/provenance admitted'}
    $extension=Save-Extension $manifest;$state=Receiver $extension
    $record=Trace-Record $state begin 1;$record.anchor_mc.x=.5;Reject-Record $state $record 'Spawn silently became coordinate anchor'
    Begin $state
    foreach($axis in @('x','z','y')){
        $bad=Trace-Record $state sample 2
        $bad.server[$axis]=@{x=11.5001;z=3.5001;y=611.5001}[$axis]
        Reject-Record $state $bad "Extension upper $axis bound admitted"
        $bad.server[$axis]=@{x=-3.5001;z=-3.5001;y=57.8999}[$axis]
        Reject-Record $state $bad "Extension lower $axis bound admitted"
    }
    $bad=Trace-Record $state sample 2;$bad.monotonic_ns=20000000101L;Reject-Record $state $bad 'Source beyond20s accepted'
    $bad=Trace-Record $state sample 2;$bad.monotonic_ns=99;Reject-Record $state $bad 'Sample before source start accepted'
    $bad=Trace-Record $state sample 2;$bad.source_kind='live_kcd_ground_patch';Reject-Record $state $bad 'Legacy source admitted'
    $bad=Trace-Record $state sample 2;$bad.source_kind='hud_corridor_walk_coupled';Reject-Record $state $bad 'Corridor source admitted as extension'
    foreach($phase in @('JUMPING','LANDING')){Reject-Record $state (Trace-Record $state sample 2 $phase) 'Extension accepted jump/landing'}
    $bad=Trace-Record $state sample 2;$bad.walking_area='wide';Reject-Record $state $bad 'Legacy area admitted'
    $bad=Trace-Record $state sample 2;$bad.server_age_ns=250000001;Reject-Record $state $bad 'Stale real-server guard widened'
    $accepted=Receive $state (Trace-Record $state sample 2 WALKING 9.75)
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 129.75 -and $accepted.Target.y -eq 2039.5) 'Crossing maps through original C, not tile1 center'
    $stale=Receive $state (Trace-Record $state sample 3 RETURNING 3.5) ($utc+301)
    Check ($stale.Kind -ceq 'stale' -and -not $stale.PSObject.Properties['Target']) 'Late return never forwarded'
    $accepted=Receive $state (Trace-Record $state sample 4 RETURNING 3.0)
    Check ($accepted.Kind -ceq 'sample' -and $accepted.Target.x -eq 123) 'Fresh grounded return crosses seam'
    $accepted=Receive $state (Trace-Record $state sample 5 RETURN_REST .6)
    Check ($accepted.Kind -ceq 'sample') 'Return-rest remains visible to follower'
    $bad=Trace-Record $state sample 6;$bad.server_seq=4;Reject-Record $state $bad 'Repeated real-server sequence accepted'
    $null=Receive $state (Trace-Record $state sample 6 PASSED .6)
    $null=Receive $state (Trace-Record $state end 7 PASSED)
    Check $state.Ended 'Fresh terminal source succeeds'
    # Additional records/bytes are exclusive to this profile;200 was too small
    # to reserve an end record for the20-second source deadline.
    $longState=Receiver $extension;Begin $longState
    for($seq=2;$seq -le 201;$seq++){$null=Receive $longState (Trace-Record $longState sample $seq)}
    Check ($longState.Records -eq 201 -and $longState.Bytes -gt 65536) 'Extension uses bounded larger stream'
    $null=Receive $longState (Trace-Record $longState sample 202 PASSED)
    $null=Receive $longState (Trace-Record $longState end 203 PASSED)
    $reader=[pscustomobject]@{Path=$trace;Stream=$null;Bytes=[byte[]]::new(0)}
    [IO.File]::WriteAllText($trace,('x'*70000)+"`n")
    try{
        Reject {Read-CoupledTraceLines $reader} 'Legacy reader silently enlarged'
        Check (@(Read-CoupledExtensionTraceLines $reader).Count -eq 1) 'Extension bounded append reader accepts larger stream'
        [IO.File]::WriteAllText($trace,('y'*70000)+"`n")
        Reject {Read-CoupledExtensionTraceLines $reader} 'Extension reader accepted rewritten bytes'
    }finally{if($reader.Stream){$reader.Stream.Dispose()}}


    $ready=[pscustomobject]@{schema=1;run=$hudRun;source_kind='minecraft_vanilla_ui_stream_v1';mapping_bytes=8294656
        mapping_name='Local\MineComeHud_'+$hudRun;mutex_name='Local\MineComeHudLock_'+$hudRun;target_pid=321;target_start_filetime=$start
        producer_pid=123;producer_start_filetime=$start;save=$save;expires_utc_ms=$utc+180000;standalone=$true;ui_ground_extension_coupled=$true;walking_area='extension'}
    Assert-CoupledExtensionHudReady $ready 321 $start $utc
    Check $true 'Explicit extension readiness binds helper and source'
    foreach($change in @('area','helper','save','marker','mixed','expiry')){
        $bad=Clone $ready
        switch($change){area{$bad.walking_area='corridor'}helper{$bad.target_pid=320}save{$bad.save='MineCome-Ground-'+$world}marker{$bad.ui_ground_extension_coupled=$false}mixed{$bad|Add-Member ui_ground_corridor_coupled $true}expiry{$bad.expires_utc_ms=$utc-1}}
        Reject {Assert-CoupledExtensionHudReady $bad 321 $start $utc} "Reject extension readiness $change"
    }
    $delayed=Clone $ready;$delayed | Add-Member ui_ground_extension_delay_fixture $true
    Assert-CoupledExtensionHudReady $delayed 321 $start $utc -DelayHandoff
    Check $true 'Delayed extension readiness requires explicit selection'
    Reject {Assert-CoupledExtensionHudReady $delayed 321 $start $utc} 'Unrequested delayed readiness rejected'
    Reject {Assert-CoupledExtensionHudReady $ready 321 $start $utc -DelayHandoff} 'Delayed request cannot accept an ordinary run'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Test-CoupledGroundExtension.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
    $definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-CoupledExtensionHudArguments'},$true)
    Invoke-Expression $definition.Extent.Text
    $normalArguments=@(Get-CoupledExtensionHudArguments (Join-Path $root 'scripts') $path $trace $dir)
    $delayedArguments=@(Get-CoupledExtensionHudArguments (Join-Path $root 'scripts') $path $trace $dir -DelayHandoff)
    Check ('-GroundExtensionDelayFixture' -cnotin $normalArguments) 'Normal controller has no artificial handoff delay'
    Check (@($delayedArguments | Where-Object {$_ -ceq '-GroundExtensionDelayFixture'}).Count -eq 1) 'Delayed controller forwards exactly one explicit child selector'
    Check (($normalArguments -join '|') -ceq (($delayedArguments | Where-Object {$_ -cne '-GroundExtensionDelayFixture'}) -join '|')) 'Delay does not alter capture, source, trace or deadline arguments'
    $center=$extension.Anchor
    $frames=@(
        [pscustomobject]@{TraceSeq=2;Phase='WALKING';Target=[pscustomobject]@{x=120.5;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=3;Phase='WALKING';Target=[pscustomobject]@{x=129.8;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=4;Phase='RETURNING';Target=[pscustomobject]@{x=127.8;y=2039.5;z=56.0}}
        [pscustomobject]@{TraceSeq=5;Phase='RETURN_REST';Target=[pscustomobject]@{x=120.8;y=2039.5;z=56.0}}
    )
    $receipts=@([pscustomobject]@{schema=1;run=$run;event='begin';result='awaiting_first_pose';terminal=$false;player=$center;walking_area='extension'})
    foreach($frame in $frames){
        $target=[pscustomobject]@{x=[double][single]$frame.Target.x;y=[double][single]$frame.Target.y;z=[double][single]$frame.Target.z}
        $receipts+=[pscustomobject]@{schema=1;run=$run;event='applied';result='applied_readback';terminal=$false;seq=$frame.TraceSeq;target=$target;player=(Clone $target);readback=$true;follow_error=.01;walking_area='extension'}
    }
    $receipts+=[pscustomobject]@{schema=1;run=$run;event='restoring';result='restored_position_pending_camera';terminal=$false;readback=$true;end_result='explicit_end';target=$center;player=$center;walking_area='extension'}
    $receipts+=[pscustomobject]@{schema=1;run=$run;event='restored';result='restored';terminal=$true;readback=$true;timers_cancelled=$true;end_result='explicit_end';follow_error=.01;target=$center;player=$center;walking_area='extension'}
    Check (@(Assert-CoupledExtensionFollowerProof $receipts $frames $run $center).Count -eq 4) 'Native extension crossing, return and exact restoration proof accepted'
    foreach($mutation in @(
        {param($r,$f)$f[1].Phase='RETURNING'},
        {param($r,$f)$f[2].Phase='WALKING'},
        {param($r,$f)$f[3].Phase='RETURNING'},
        {param($r,$f)$f[1].Phase='JUMPING'},
        {param($r,$f)$r[-1].target.x+=.0001},
        {param($r,$f)$r[-2].target.x+=.0001},
        {param($r,$f)$r[-1].player.x+=.051},
        {param($r,$f)$r[-2].player.x+=.051},
        {param($r,$f)$r[2].target.x+=.01},
        {param($r,$f)$r[2].player.x+=.051},
        {param($r,$f)$r[2].walking_area='corridor'},
        {param($r,$f)$r[-1].end_result='input_expired'}
    )){$badReceipts=Clone $receipts;$badFrames=Clone $frames;& $mutation $badReceipts $badFrames;Reject {Assert-CoupledExtensionFollowerProof $badReceipts $badFrames $run $center} 'Unbound extension readback rejected'}
    Write-Output "EXTENSION_COUPLED_MOVEMENT_TESTS_PASS checks=$script:checks no_game_started=true"
}finally{if($reader -and $reader.Stream){$reader.Stream.Dispose()}}
