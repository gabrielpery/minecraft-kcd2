#Requires -Version 7.3
# Separate immutable arrow requests on the existing guarded combat worker.
# GameplayCombatHost.ps1 supplies strict number/JSON checks and atomic publication.
function Assert-GameplayProjectilePoint($Point){
    Assert-GameplayCombatKeys $Point @('x','y','z')
    foreach($axis in @('x','y','z')){if(-not(Test-GameplayCombatNumber $Point.$axis) -or [Math]::Abs($Point.$axis) -ge 10000000){throw 'Projectile point invalid.'}}
}
function Read-GameplayProjectileRequest([string]$Path,$Identity,[long]$Now){
    if(-not [IO.File]::Exists($Path)){return $null};$file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt 8192){throw 'Projectile request exceeds bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes);if($file.ReadByte() -ne -1){throw 'Projectile request changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);$doc=[Text.Json.JsonDocument]::Parse($json)
        try{Assert-GameplayCombatJson $doc.RootElement}finally{$doc.Dispose()}
        $v=$json|ConvertFrom-Json -Depth 8
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
    Assert-GameplayCombatKeys $v @('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','request')
    if(-not(Test-GameplayCombatInteger $v.schema 1 1) -or $v.kind -cne 'minecome_gameplay_projectiles_guest_v1' -or $v.run -cne $Identity.Run -or $v.world_id -cne $Identity.WorldId -or
        -not(Test-GameplayCombatInteger $v.target_pid 1 2147483647) -or $v.target_pid -ne $Identity.Pid -or $v.target_start_filetime -isnot [string] -or $v.target_start_filetime -cne $Identity.Start -or
        $v.patch_run -cne $Identity.PatchRun -or $v.patch_sha256 -cne $Identity.PatchHash){throw 'Projectile request identity differs.'}
    if(-not(Test-GameplayCombatInteger $v.seq 1 10000000) -or -not(Test-GameplayCombatInteger $v.utc_ms 1 ($Now+50))){throw 'Projectile request clock/sequence invalid.'}
    $r=$v.request;Assert-GameplayCombatKeys $r @('operation','projectile','segment','from','to','actor_token','damage_mc','damage_fraction')
    if($r.operation -cnotin @('trace','impact') -or $r.projectile -isnot [string] -or $r.projectile -cnotmatch '^[0-9a-f]{32}$' -or
        -not(Test-GameplayCombatInteger $r.segment 1 4096) -or -not(Test-GameplayCombatInteger $r.actor_token 0 256) -or
        -not(Test-GameplayCombatNumber $r.damage_mc) -or $r.damage_mc -lt 0 -or $r.damage_mc -gt 1000 -or
        -not(Test-GameplayCombatNumber $r.damage_fraction) -or $r.damage_fraction -lt 0 -or $r.damage_fraction -gt 50 -or
        [Math]::Abs($r.damage_mc/20-$r.damage_fraction) -gt .00001){throw 'Projectile request payload invalid.'}
    Assert-GameplayProjectilePoint $r.from;Assert-GameplayProjectilePoint $r.to
    $lengthSquared=0.;foreach($axis in @('x','y','z')){$d=$r.to.$axis-$r.from.$axis;$lengthSquared+=$d*$d}
    if($lengthSquared -le 0 -or $lengthSquared -gt 16.000001){throw 'Projectile segment length invalid.'}
    if(($r.operation -ceq 'trace' -and ($r.actor_token -ne 0 -or $r.damage_mc -ne 0 -or $r.damage_fraction -ne 0)) -or
        ($r.operation -ceq 'impact' -and ($r.actor_token -lt 1 -or $r.damage_mc -le 0 -or $r.damage_fraction -le 0))){throw 'Projectile operation payload differs.'}
    return $v
}
function New-GameplayProjectilesState($Identity,[string]$Directory){
    [pscustomobject]@{Identity=$Identity;SnapshotFile=(Join-Path $Directory 'projectiles.json');HostFile=(Join-Path $Directory 'host-projectiles.json');
        LastSequence=0L;LastUtcMs=0L;LastCanonical='';Pending=$null;PendingSinceUtcMs=0L;LastReceiptCanonical='';LastReply=$null;LastImpact=$null;LastScenery=$null;
        Timing=[ordered]@{Count=0L;TotalMs=0L;MaxMs=0L;DispatchWaitTotalMs=0L;DispatchWaitMaxMs=0L;NativeWaitTotalMs=0L;NativeWaitMaxMs=0L};
        TraceGrants=@{};Requests=0L;Traces=0L;Impacts=0L;Scenery=0L;Actors=0L;Damaged=0L;Rejected=0L;Abandoned=0L;AbandonedRequest=$null;AbandonedReceipt=$null;AbandonedReceiptCanonical='';TemporaryClean=$true;Stopped=$false}
}
function Get-GameplayProjectileCommands($State,[long]$Now){
    if($State.Stopped){return ''}
    foreach($projectile in @($State.TraceGrants.Keys)){if($Now-$State.TraceGrants[$projectile].At -gt 10000){$State.TraceGrants.Remove($projectile)}}
    if($State.Pending -and $Now-$State.PendingSinceUtcMs -gt 1500){throw 'Native projectile acknowledgement missing; operation will not be retried.'}
    $v=Read-GameplayProjectileRequest $State.SnapshotFile $State.Identity $Now;if(-not $v){return ''}
    $canonical=$v|ConvertTo-Json -Depth 8 -Compress
    if($v.seq -lt $State.LastSequence -or $v.utc_ms -lt $State.LastUtcMs -or ($v.seq -eq $State.LastSequence -and $canonical -cne $State.LastCanonical)){throw 'Projectile request changed or regressed.'}
    if($v.seq -eq $State.LastSequence){return ''}
    if($State.Pending -or $v.seq -ne $State.LastSequence+1){throw 'Projectile request advanced before acknowledgement or skipped a sequence.'}
    if($Now-$v.utc_ms -gt 500){throw 'Projectile request expired before dispatch.'}
    $r=$v.request
    if($r.operation -ceq 'impact'){
        $grant=$State.TraceGrants[$r.projectile]
        if(-not $grant -or $grant.Request.segment -ne $r.segment -or $grant.Actor -ne $r.actor_token){throw 'Projectile impact has no matching native contact.'}
        foreach($point in @('from','to')){foreach($axis in @('x','y','z')){if($r.$point.$axis -ne $grant.Request.$point.$axis){throw 'Projectile impact trajectory changed.'}}}
    }
    $State.LastSequence=[long]$v.seq;$State.LastUtcMs=[long]$v.utc_ms;$State.LastCanonical=$canonical;$State.Pending=$v;$State.PendingSinceUtcMs=$Now;$State.Requests++
    $run=$State.Identity.Run
    if($r.operation -ceq 'trace'){
        $values=@($v.seq,$r.segment,$r.from.x,$r.from.y,$r.from.z,$r.to.x,$r.to.y,$r.to.z)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
        return "MineCome.GameplayProjectileTrace('$run',$($values[0]),'$($r.projectile)',$([string]::Join(',',$values[1..7])))"
    }
    $fraction=([double]$r.damage_fraction).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    return "MineCome.GameplayProjectileImpact('$run',$($v.seq),'$($r.projectile)',$($r.segment),$($r.actor_token),$fraction)"
}
function Accept-GameplayProjectileReceipt($State,$Receipt,[long]$Now){
    $receiptCanonical=$Receipt|ConvertTo-Json -Depth 8 -Compress
    if($State.Stopped -and $State.AbandonedRequest){
        $abandoned=$State.AbandonedRequest;$r=$abandoned.request
        if($Receipt.schema -ne 1 -or $Receipt.run -cne $State.Identity.Run -or $Receipt.seq -ne $abandoned.seq -or $Receipt.projectile -cne $r.projectile -or $Receipt.segment -ne $r.segment -or
            $Receipt.event -cne ('projectile_'+$r.operation) -or ($State.AbandonedReceiptCanonical -and $State.AbandonedReceiptCanonical -cne $receiptCanonical)){throw 'Late projectile acknowledgement differs.'}
        # A response already queued before stop may arrive while the worker
        # drains its terminal log. Retain it as evidence, without publication or
        # another native call, and without claiming it reached the closed guest.
        $State.AbandonedReceipt=$Receipt;$State.AbandonedReceiptCanonical=$receiptCanonical;return
    }
    if(-not $State.Pending){if($State.LastReceiptCanonical -ceq $receiptCanonical){return};throw 'Unexpected projectile acknowledgement.'}
    $pending=$State.Pending;$request=$pending.request
    if($State.Stopped -or $Now-$State.PendingSinceUtcMs -gt 1500 -or $Receipt.schema -ne 1 -or $Receipt.run -cne $State.Identity.Run -or
        $Receipt.active -isnot [bool] -or -not $Receipt.active -or $Receipt.event -cne ('projectile_'+$request.operation) -or
        -not(Test-GameplayCombatInteger $Receipt.seq 1 10000000) -or $Receipt.seq -ne $pending.seq -or $Receipt.projectile -cne $request.projectile -or
        -not(Test-GameplayCombatInteger $Receipt.segment 1 4096) -or $Receipt.segment -ne $request.segment -or $Receipt.reason -isnot [string] -or $Receipt.reason.Length -gt 80 -or
        $Receipt.reason -cnotmatch '^[a-z_]*$' -or -not(Test-GameplayCombatInteger $Receipt.actor_token 0 256)){throw 'Projectile acknowledgement identity differs.'}
    Assert-GameplayProjectilePoint $Receipt.contact;Assert-GameplayProjectilePoint $Receipt.normal
    foreach($axis in @('x','y','z')){if([Math]::Abs($Receipt.normal.$axis) -gt 1.00001){throw 'Projectile normal invalid.'}}
    $allowed=if($request.operation -ceq 'trace'){@('clear','scenery','actor','rejected')}else{@('damaged','no_damage','rejected')}
    if($Receipt.result -cnotin $allowed -or ($Receipt.result -ceq 'rejected' -and -not $Receipt.reason) -or ($Receipt.result -cne 'rejected' -and $Receipt.reason)){throw 'Projectile result differs.'}
    if($Receipt.result -cne 'rejected'){
        $lengthSquared=0.;$along=0.;foreach($axis in @('x','y','z')){$d=$request.to.$axis-$request.from.$axis;$lengthSquared+=$d*$d;$along+=($Receipt.contact.$axis-$request.from.$axis)*$d}
        $progress=$along/$lengthSquared;if($progress -lt -.01 -or $progress -gt 1.01){throw 'Projectile contact leaves its segment.'}
        $offRay=0.;foreach($axis in @('x','y','z')){$closest=$request.from.$axis+$progress*($request.to.$axis-$request.from.$axis);$delta=$Receipt.contact.$axis-$closest;$offRay+=$delta*$delta}
        if($offRay -gt .0025){throw 'Projectile contact is not on its segment.'}
        $normalSquared=$Receipt.normal.x*$Receipt.normal.x+$Receipt.normal.y*$Receipt.normal.y+$Receipt.normal.z*$Receipt.normal.z
        if(($Receipt.result -ceq 'clear' -and ([Math]::Abs($progress-1) -gt .01 -or $normalSquared -gt .00001)) -or
            ($Receipt.result -cne 'clear' -and [Math]::Abs($normalSquared-1) -gt .05)){throw 'Projectile contact normal or clear endpoint differs.'}
    }
    $hasActor=$Receipt.result -ceq 'actor' -or $Receipt.result -cin @('damaged','no_damage') -or ($Receipt.result -ceq 'rejected' -and $Receipt.reason -ceq 'damage_unconfirmed')
    if($hasActor){
        $a=$Receipt.actor;Assert-GameplayCombatKeys $a @('token','x','y','z','width','height','health','max_health','alive')
        if(-not(Test-GameplayCombatInteger $a.token 1 256) -or $a.token -ne $Receipt.actor_token -or $a.alive -isnot [bool] -or ($Receipt.result -ceq 'actor' -and -not $a.alive)){throw 'Projectile actor identity invalid.'}
        foreach($field in @('x','y','z','width','height','health','max_health')){if(-not(Test-GameplayCombatNumber $a.$field)){throw 'Projectile actor numeric field invalid.'}}
        if([Math]::Abs($a.x) -ge 10000000 -or [Math]::Abs($a.y) -ge 10000000 -or [Math]::Abs($a.z) -ge 10000000 -or $a.width -lt .05 -or $a.width -gt 4 -or $a.height -lt .05 -or $a.height -gt 8 -or $a.max_health -le 0 -or $a.max_health -gt 1000000 -or $a.health -lt 0 -or $a.health -gt $a.max_health -or ($a.alive -and $a.health -le 0)){throw 'Projectile actor bounds invalid.'}
    }elseif($null -ne $Receipt.actor){throw 'Unexpected projectile actor snapshot.'}
    if($Receipt.result -cin @('clear','scenery') -and $Receipt.actor_token -ne 0){throw 'Scenery/clear projectile response identifies an actor.'}
    if($request.operation -ceq 'impact' -and $hasActor -and $Receipt.actor_token -ne $request.actor_token){throw 'Projectile impact actor changed.'}
    if($Receipt.result -cin @('damaged','no_damage')){
        if(-not(Test-GameplayCombatNumber $Receipt.before) -or -not(Test-GameplayCombatNumber $Receipt.after) -or $Receipt.before -lt 0 -or $Receipt.before -gt 1000000 -or $Receipt.after -lt 0 -or $Receipt.after -gt $Receipt.before+.01 -or [Math]::Abs($Receipt.actor.health-$Receipt.after) -gt .01 -or
            ($Receipt.result -ceq 'damaged' -and $Receipt.after -ge $Receipt.before) -or ($Receipt.result -ceq 'no_damage' -and $Receipt.after -ne $Receipt.before)){throw 'Projectile damage outcome invalid.'}
    }elseif($null -ne $Receipt.before -or $null -ne $Receipt.after){
        # A setter may throw after touching health. Preserve evidence without
        # claiming delivery or ever replaying the damage setter.
        if($Receipt.result -cne 'rejected' -or $Receipt.reason -cne 'damage_unconfirmed'){throw 'Unexpected projectile health outcome.'}
        foreach($value in @($Receipt.before,$Receipt.after)){if($null -ne $value -and (-not(Test-GameplayCombatNumber $value) -or $value -lt 0 -or $value -gt 1000000)){throw 'Unconfirmed projectile health invalid.'}}
    }
    $reply=[ordered]@{operation=$request.operation;projectile=$request.projectile;segment=$request.segment;result=$Receipt.result;reason=$Receipt.reason;actor_token=$Receipt.actor_token;contact=$Receipt.contact;normal=$Receipt.normal;actor=$Receipt.actor;before=$Receipt.before;after=$Receipt.after}
    $id=$State.Identity;$value=[ordered]@{schema=1;kind='minecome_gameplay_projectiles_host_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=$pending.seq;utc_ms=$Now;request_utc_ms=$pending.utc_ms;reply=$reply}
    $temp=$State.HostFile+'.tmp';$State.TemporaryClean=$false
    $published=$value|ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText($temp,$published,[Text.UTF8Encoding]::new($false));Publish-GameplayCombatFile $temp $State.HostFile
    # Keep detached publication snapshots; caller-owned native receipt objects
    # or subsequent replies cannot alter the historical impact/scenery evidence.
    $accepted=$published|ConvertFrom-Json -Depth 8
    # Count only the first accepted publication. Immutable request UTC includes
    # queue delay; PendingSince splits host dispatch wait from native/log wait.
    $total=$Now-[long]$pending.utc_ms;$dispatch=$State.PendingSinceUtcMs-[long]$pending.utc_ms;$native=$Now-$State.PendingSinceUtcMs
    $State.Timing.Count++;$State.Timing.TotalMs+=$total;$State.Timing.MaxMs=[Math]::Max($State.Timing.MaxMs,$total)
    $State.Timing.DispatchWaitTotalMs+=$dispatch;$State.Timing.DispatchWaitMaxMs=[Math]::Max($State.Timing.DispatchWaitMaxMs,$dispatch)
    $State.Timing.NativeWaitTotalMs+=$native;$State.Timing.NativeWaitMaxMs=[Math]::Max($State.Timing.NativeWaitMaxMs,$native)
    $State.TemporaryClean=$true;$State.LastReceiptCanonical=$receiptCanonical;$State.LastReply=$accepted;$State.Pending=$null
    if($request.operation -ceq 'impact'){$State.LastImpact=$published|ConvertFrom-Json -Depth 8}
    if($Receipt.result -ceq 'scenery'){$State.LastScenery=$published|ConvertFrom-Json -Depth 8}
    if($request.operation -ceq 'trace'){$State.Traces++;if($Receipt.result -ceq 'actor'){if($State.TraceGrants.Count -ge 16 -and -not $State.TraceGrants.ContainsKey($request.projectile)){throw 'Projectile native-contact capacity exceeded.'};$State.TraceGrants[$request.projectile]=[pscustomobject]@{Request=$request;Actor=$Receipt.actor_token;At=$Now}}else{$State.TraceGrants.Remove($request.projectile)}}else{$State.Impacts++;$State.TraceGrants.Remove($request.projectile)}
    switch -CaseSensitive ($Receipt.result){'scenery'{$State.Scenery++};'actor'{$State.Actors++};'damaged'{$State.Damaged++};'rejected'{$State.Rejected++}}
}
function Stop-GameplayProjectilesHost($State){
    $State.Stopped=$true;if($State.Pending){$State.Abandoned++;$State.AbandonedRequest=$State.Pending;$State.Pending=$null};$State.TraceGrants.Clear()
    try{[IO.File]::Delete($State.HostFile+'.tmp');$State.TemporaryClean=$true}catch{$State.TemporaryClean=$false;throw}
}
function Get-GameplayProjectilesHostState($State){
    [pscustomobject]@{Requests=$State.Requests;Traces=$State.Traces;Impacts=$State.Impacts;Scenery=$State.Scenery;Actors=$State.Actors;Damaged=$State.Damaged;Rejected=$State.Rejected;Abandoned=$State.Abandoned;AbandonedReceipt=$State.AbandonedReceipt;Timing=$State.Timing;Pending=($null -ne $State.Pending);LastReply=$State.LastReply;LastImpact=$State.LastImpact;LastScenery=$State.LastScenery;TemporaryClean=$State.TemporaryClean;CleanupComplete=($State.TemporaryClean -and ($State.Requests -eq 0 -or $State.Stopped) -and $null -eq $State.Pending)}
}
