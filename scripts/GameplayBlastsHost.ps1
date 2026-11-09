#Requires -Version 7.3
# Immutable owned-TNT prepare/commit on the existing guarded console owner.
function Read-GameplayBlastRequest([string]$Path,$Identity,[long]$Now){
    if(-not [IO.File]::Exists($Path)){return $null};$file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt 8192){throw 'Blast request exceeds bound.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes);if($file.ReadByte() -ne -1){throw 'Blast request changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);$doc=[Text.Json.JsonDocument]::Parse($json)
        try{Assert-GameplayCombatJson $doc.RootElement}finally{$doc.Dispose()};$v=$json|ConvertFrom-Json -Depth 8
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}finally{if($file){$file.Dispose()}}
    Assert-GameplayCombatKeys $v @('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','request')
    if(-not(Test-GameplayCombatInteger $v.schema 1 1) -or $v.kind -cne 'minecome_gameplay_blasts_guest_v1' -or $v.run -cne $Identity.Run -or $v.world_id -cne $Identity.WorldId -or
        -not(Test-GameplayCombatInteger $v.target_pid 1 2147483647) -or $v.target_pid -ne $Identity.Pid -or $v.target_start_filetime -isnot [string] -or $v.target_start_filetime -cne $Identity.Start -or
        $v.patch_run -cne $Identity.PatchRun -or $v.patch_sha256 -cne $Identity.PatchHash){throw 'Blast request identity differs.'}
    if(-not(Test-GameplayCombatInteger $v.seq 1 10000000) -or -not(Test-GameplayCombatInteger $v.utc_ms 1 ($Now+50))){throw 'Blast request sequence/clock invalid.'}
    $r=$v.request;Assert-GameplayCombatKeys $r @('operation','explosion','owner','prepare_seq','center','power','targets')
    if($r.operation -cnotin @('prepare','commit') -or $r.explosion -isnot [string] -or $r.explosion -cnotmatch '^[0-9a-f]{32}$' -or $r.owner -isnot [string] -or $r.owner -cnotmatch '^[0-9a-f]{32}$' -or
        -not(Test-GameplayCombatInteger $r.prepare_seq 0 10000000) -or -not(Test-GameplayCombatNumber $r.power) -or $r.power -ne 4 -or $r.targets -isnot [Array] -or $r.targets.Count -gt 8){throw 'Blast payload invalid.'}
    Assert-GameplayProjectilePoint $r.center
    if(($r.operation -ceq 'prepare' -and ($r.prepare_seq -ne 0 -or $r.targets.Count -ne 0)) -or ($r.operation -ceq 'commit' -and $r.prepare_seq -lt 1)){throw 'Blast phase payload differs.'}
    $seen=[Collections.Generic.HashSet[long]]::new()
    foreach($target in $r.targets){
        Assert-GameplayCombatKeys $target @('actor_token','damage_mc','damage_fraction')
        if(-not(Test-GameplayCombatInteger $target.actor_token 1 256) -or -not $seen.Add([long]$target.actor_token) -or -not(Test-GameplayCombatNumber $target.damage_mc) -or $target.damage_mc -le 0 -or $target.damage_mc -gt 1000 -or
            -not(Test-GameplayCombatNumber $target.damage_fraction) -or $target.damage_fraction -le 0 -or $target.damage_fraction -gt 50 -or [Math]::Abs($target.damage_mc/20-$target.damage_fraction) -gt .00001){throw 'Blast target damage invalid.'}
    }
    return $v
}
function New-GameplayBlastsState($Identity,[string]$Directory){
    [pscustomobject]@{Identity=$Identity;SnapshotFile=(Join-Path $Directory 'blasts.json');HostFile=(Join-Path $Directory 'host-blasts.json');Owner='';LastSequence=0L;LastUtcMs=0L;LastCanonical='';Pending=$null;PendingSinceUtcMs=0L;
        LastReceiptCanonical='';LastReply=$null;LastPrepare=$null;Completed=[Collections.Generic.Queue[object]]::new();Grants=@{};Seen=[Collections.Generic.HashSet[string]]::new();Requests=0L;Prepared=0L;Commits=0L;Damaged=0L;Rejected=0L;
        Abandoned=0L;AbandonedRequest=$null;AbandonedReceipt=$null;AbandonedReceiptCanonical='';TemporaryClean=$true;Stopped=$false}
}
function Get-GameplayBlastCommands($State,[long]$Now){
    if($State.Stopped){return ''}
    if($State.Pending -and $Now-$State.PendingSinceUtcMs -gt 1500){throw 'Native blast acknowledgement missing; operation will not be retried.'}
    $v=Read-GameplayBlastRequest $State.SnapshotFile $State.Identity $Now;if(-not $v){return ''};$canonical=$v|ConvertTo-Json -Depth 8 -Compress
    # Another TNT can reach detonation while the preceding blast awaits its
    # commit. Its frozen source UTC may therefore precede that commit's UTC.
    # Sequence ordering is global; source freshness is checked per request.
    if($v.seq -lt $State.LastSequence -or ($v.seq -eq $State.LastSequence -and $canonical -cne $State.LastCanonical)){throw 'Blast request changed or regressed.'}
    if($v.seq -eq $State.LastSequence){return ''}
    if($State.Pending -or $v.seq -ne $State.LastSequence+1){throw 'Blast request advanced before acknowledgement or skipped sequence.'}
    if($Now-$v.utc_ms -gt 500){throw 'Blast request expired before dispatch.'}
    $r=$v.request;if($State.Owner -and $State.Owner -cne $r.owner){throw 'Blast owner changed.'}
    foreach($key in @($State.Grants.Keys)){if($Now-$State.Grants[$key].At -gt 1000){$State.Grants.Remove($key)}}
    if($r.operation -ceq 'prepare'){
        if($State.Seen.Contains($r.explosion) -or $State.Seen.Count -ge 4096 -or $State.Grants.Count -ge 16){throw 'Blast UUID reused or capacity exceeded.'}
        [void]$State.Seen.Add($r.explosion)
    }else{
        $grant=$State.Grants[$r.explosion]
        if(-not $grant -or $grant.Reply.prepare_seq -ne $r.prepare_seq -or $grant.Reply.owner -cne $r.owner){throw 'Blast has no matching native prepare grant.'}
        foreach($axis in @('x','y','z')){if($grant.Reply.center.$axis -ne $r.center.$axis){throw 'Prepared blast centre changed.'}}
        foreach($target in $r.targets){if(@($grant.Reply.actors|Where-Object token -EQ $target.actor_token).Count -ne 1){throw 'Blast target lacks prepared native actor.'}}
        $State.Grants.Remove($r.explosion)
    }
    $State.Owner=$r.owner;$State.LastSequence=[long]$v.seq;$State.LastUtcMs=[long]$v.utc_ms;$State.LastCanonical=$canonical;$State.Pending=$v;$State.PendingSinceUtcMs=$Now;$State.Requests++
    $center=@($r.center.x,$r.center.y,$r.center.z)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)};$xyz=[string]::Join(',',$center);$run=$State.Identity.Run
    if($r.operation -ceq 'prepare'){return "MineCome.GameplayBlastPrepare('$run',$($v.seq),'$($r.explosion)','$($r.owner)',$xyz,4)"}
    $rows=@($r.targets|ForEach-Object {[string]$_.actor_token+':'+([double]$_.damage_fraction).ToString('R',[Globalization.CultureInfo]::InvariantCulture)})
    return "MineCome.GameplayBlastCommit('$run',$($v.seq),'$($r.explosion)','$($r.owner)',$($r.prepare_seq),$xyz,4,'$([string]::Join(';',$rows))')"
}
function Assert-GameplayBlastActor($Actor){
    Assert-GameplayCombatKeys $Actor @('token','x','y','z','width','height','health','max_health','alive','exposure')
    if(-not(Test-GameplayCombatInteger $Actor.token 1 256) -or $Actor.alive -isnot [bool] -or -not $Actor.alive){throw 'Prepared blast actor identity invalid.'}
    foreach($field in @('x','y','z','width','height','health','max_health')){if(-not(Test-GameplayCombatNumber $Actor.$field)){throw 'Prepared blast actor number invalid.'}}
    if([Math]::Abs($Actor.x) -ge 10000000 -or [Math]::Abs($Actor.y) -ge 10000000 -or [Math]::Abs($Actor.z) -ge 10000000 -or $Actor.width -lt .05 -or $Actor.width -gt 4 -or $Actor.height -lt .05 -or $Actor.height -gt 5 -or
        $Actor.health -le 0 -or $Actor.health -gt $Actor.max_health -or $Actor.max_health -le 0 -or $Actor.max_health -gt 1000000 -or $Actor.exposure -isnot [string] -or $Actor.exposure -cnotmatch '^[01]{1,128}$'){throw 'Prepared blast actor bounds invalid.'}
    $dx=1/(2*[double][float]$Actor.width+1);$dy=1/(2*[double][float]$Actor.height+1);$nx=0;$ny=0
    for($x=0.;$x -le 1;$x+=$dx){$nx++};for($y=0.;$y -le 1;$y+=$dy){$ny++}
    if($Actor.exposure.Length -ne $nx*$ny*$nx){throw 'Prepared blast exposure lattice differs.'}
}
function Accept-GameplayBlastReceipt($State,$Receipt,[long]$Now){
    $canonical=$Receipt|ConvertTo-Json -Depth 8 -Compress
    if($State.Stopped -and $State.AbandonedRequest){
        $abandoned=$State.AbandonedRequest;$r=$abandoned.request
        if($Receipt.schema -ne 1 -or $Receipt.run -cne $State.Identity.Run -or $Receipt.seq -ne $abandoned.seq -or $Receipt.explosion -cne $r.explosion -or $Receipt.owner -cne $r.owner -or
            $Receipt.event -cne ('blast_'+$r.operation) -or ($State.AbandonedReceiptCanonical -and $State.AbandonedReceiptCanonical -cne $canonical)){throw 'Late blast acknowledgement differs.'}
        $State.AbandonedReceipt=$Receipt;$State.AbandonedReceiptCanonical=$canonical;return
    }
    if(-not $State.Pending){if($State.LastReceiptCanonical -ceq $canonical){return};throw 'Unexpected blast acknowledgement.'}
    $pending=$State.Pending;$r=$pending.request;$prepare=if($r.operation -ceq 'prepare'){$pending.seq}else{$r.prepare_seq}
    if($State.Stopped -or $Now-$State.PendingSinceUtcMs -gt 1500 -or -not(Test-GameplayCombatInteger $Receipt.schema 1 1) -or $Receipt.run -cne $State.Identity.Run -or $Receipt.active -isnot [bool] -or -not $Receipt.active -or
        $Receipt.event -cne ('blast_'+$r.operation) -or -not(Test-GameplayCombatInteger $Receipt.seq 1 10000000) -or $Receipt.seq -ne $pending.seq -or $Receipt.explosion -cne $r.explosion -or $Receipt.owner -cne $r.owner -or
        -not(Test-GameplayCombatInteger $Receipt.prepare_seq 1 10000000) -or $Receipt.prepare_seq -ne $prepare -or -not(Test-GameplayCombatNumber $Receipt.power) -or $Receipt.power -ne 4 -or
        $Receipt.reason -isnot [string] -or $Receipt.reason -cnotmatch '^[a-z_]{0,80}$' -or $Receipt.actors -isnot [Array] -or $Receipt.outcomes -isnot [Array]){throw 'Blast acknowledgement identity differs.'}
    Assert-GameplayProjectilePoint $Receipt.center
    foreach($axis in @('x','y','z')){
        # The console parses numeric arguments as binary32; Lua then emits
        # %.12g. Bind to that exact float, allowing only its decimal formatting
        # error, not a generic world-space distance from the original double.
        $expected=[double][float]$r.center.$axis
        $tolerance=if($expected -eq 0){0.}else{.5*[Math]::Pow(10,[Math]::Floor([Math]::Log10([Math]::Abs($expected)))-11)+[Math]::Abs($expected)*2.220446049250313e-16}
        if([Math]::Abs($Receipt.center.$axis-$expected) -gt $tolerance){throw 'Blast acknowledgement centre differs.'}
    }
    $expected=if($r.operation -ceq 'prepare'){'prepared'}else{'applied'}
    if($Receipt.result -cnotin @($expected,'rejected') -or ($Receipt.result -ceq 'rejected' -and -not $Receipt.reason) -or ($Receipt.result -cne 'rejected' -and $Receipt.reason)){throw 'Blast result differs.'}
    if($Receipt.result -ceq 'rejected'){if($Receipt.actors.Count -or $Receipt.outcomes.Count){throw 'Rejected blast carried effects.'}}
    elseif($r.operation -ceq 'prepare'){
        if($Receipt.actors.Count -gt 8 -or $Receipt.outcomes.Count){throw 'Blast prepare counts differ.'};$seen=[Collections.Generic.HashSet[long]]::new()
        foreach($actor in $Receipt.actors){Assert-GameplayBlastActor $actor;if(-not $seen.Add([long]$actor.token)){throw 'Blast actor duplicated.'}
            if([Math]::Sqrt([Math]::Pow($actor.x-$r.center.x,2)+[Math]::Pow($actor.y-$r.center.y,2)+[Math]::Pow($actor.z-$r.center.z,2)) -gt 8.00001){throw 'Prepared blast actor outside radius.'}}
    }else{
        if($Receipt.actors.Count -or $Receipt.outcomes.Count -ne $r.targets.Count){throw 'Blast commit count differs.'}
        for($i=0;$i -lt $r.targets.Count;$i++){$outcome=$Receipt.outcomes[$i];Assert-GameplayCombatKeys $outcome @('actor_token','result','reason','before','after')
            if(-not(Test-GameplayCombatInteger $outcome.actor_token 1 256) -or $outcome.actor_token -ne $r.targets[$i].actor_token -or $outcome.result -cnotin @('damaged','no_damage','rejected') -or
                $outcome.reason -isnot [string] -or $outcome.reason -cnotmatch '^[a-z_]{0,80}$' -or ($outcome.result -ceq 'rejected' -and -not $outcome.reason) -or ($outcome.result -cne 'rejected' -and $outcome.reason)){throw 'Blast outcome identity differs.'}
            foreach($hp in @($outcome.before,$outcome.after)){if($null -ne $hp -and (-not(Test-GameplayCombatNumber $hp) -or $hp -lt 0 -or $hp -gt 1000000)){throw 'Blast health outcome invalid.'}}
            if($outcome.result -cne 'rejected'){
                if($null -eq $outcome.before -or $null -eq $outcome.after -or $outcome.after -gt $outcome.before -or ($outcome.result -ceq 'damaged' -and $outcome.after -ge $outcome.before) -or ($outcome.result -ceq 'no_damage' -and $outcome.after -ne $outcome.before)){throw 'Blast damage result differs.'}
            }elseif($outcome.reason -cne 'damage_unconfirmed' -and ($null -ne $outcome.before -or $null -ne $outcome.after)){throw 'Rejected blast target changed health.'}
        }
    }
    $reply=[ordered]@{operation=$r.operation;explosion=$r.explosion;owner=$r.owner;prepare_seq=$prepare;center=$r.center;power=4;result=$Receipt.result;reason=$Receipt.reason;actors=$Receipt.actors;outcomes=$Receipt.outcomes}
    $id=$State.Identity;$value=[ordered]@{schema=1;kind='minecome_gameplay_blasts_host_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;seq=$pending.seq;utc_ms=$Now;request_utc_ms=$pending.utc_ms;reply=$reply}
    $temp=$State.HostFile+'.tmp';$State.TemporaryClean=$false;$json=$value|ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText($temp,$json,[Text.UTF8Encoding]::new($false));Publish-GameplayCombatFile $temp $State.HostFile
    $accepted=$json|ConvertFrom-Json -Depth 8;$State.TemporaryClean=$true;$State.LastReceiptCanonical=$canonical;$State.LastReply=$accepted;$State.Pending=$null
    if($Receipt.result -ceq 'rejected'){$State.Rejected++}
    if($r.operation -ceq 'prepare'){$State.LastPrepare=$accepted;if($Receipt.result -ceq 'prepared'){$State.Prepared++;$State.Grants[$r.explosion]=[pscustomobject]@{At=$Now;Reply=$accepted.reply}}}
    else{$State.Commits++;if($State.Completed.Count -ge 32){$null=$State.Completed.Dequeue()};$State.Completed.Enqueue(($json|ConvertFrom-Json -Depth 8));foreach($outcome in $Receipt.outcomes){if($outcome.result -ceq 'damaged'){$State.Damaged++}elseif($outcome.result -ceq 'rejected'){$State.Rejected++}}}
}
function Stop-GameplayBlastsHost($State){
    $State.Stopped=$true;if($State.Pending){$State.Abandoned++;$State.AbandonedRequest=$State.Pending;$State.Pending=$null};$State.Grants.Clear()
    try{[IO.File]::Delete($State.HostFile+'.tmp');$State.TemporaryClean=$true}catch{$State.TemporaryClean=$false;throw}
}
function Get-GameplayBlastsHostState($State){
    [pscustomobject]@{Requests=$State.Requests;Prepared=$State.Prepared;Commits=$State.Commits;Damaged=$State.Damaged;Rejected=$State.Rejected;Abandoned=$State.Abandoned;AbandonedReceipt=$State.AbandonedReceipt;
        Pending=($null -ne $State.Pending);LastReply=$State.LastReply;LastPrepare=$State.LastPrepare;Completed=$State.Completed.ToArray();TemporaryClean=$State.TemporaryClean;CleanupComplete=($State.TemporaryClean -and ($State.Requests -eq 0 -or $State.Stopped) -and $null -eq $State.Pending)}
}
