#Requires -Version 7.3
# Native NPC bridge on the existing exact-process guarded console worker.
# This helper owns no network loop, starts no game, and never changes native AI.
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
. (Join-Path $PSScriptRoot 'GameplayProjectilesHost.ps1')
. (Join-Path $PSScriptRoot 'GameplayBlastsHost.ps1')

function Test-GameplayCombatNumber($Value){$Value -is [ValueType] -and $Value -isnot [bool] -and [double]::IsFinite([double]$Value)}
function Test-GameplayCombatInteger($Value,[long]$Min,[long]$Max){(Test-GameplayCombatNumber $Value) -and $Value -eq [Math]::Floor([double]$Value) -and $Value -ge $Min -and $Value -le $Max}
function Assert-GameplayCombatKeys($Value,[string[]]$Keys){
    if($null -eq $Value -or (($Value.PSObject.Properties.Name|Sort-Object)-join ',') -cne (($Keys|Sort-Object)-join ',')){throw 'Gameplay combat fields differ.'}
}
function Assert-GameplayCombatJson($Element){
    if($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($p in $Element.EnumerateObject()){if(-not $seen.Add($p.Name)){throw 'Duplicate combat JSON field.'};Assert-GameplayCombatJson $p.Value}
    }elseif($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($v in $Element.EnumerateArray()){Assert-GameplayCombatJson $v}}
}
function Read-GameplayCombatSnapshot([string]$Path,$Identity,[long]$Now){
    if(-not [IO.File]::Exists($Path)){return $null};$file=$null
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -lt 2 -or $file.Length -gt 8192){throw 'Combat snapshot exceeds8192 bytes.'}
        $bytes=[byte[]]::new([int]$file.Length);$file.ReadExactly($bytes);if($file.ReadByte() -ne -1){throw 'Combat snapshot changed size.'}
        $json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);$doc=[Text.Json.JsonDocument]::Parse($json)
        try{Assert-GameplayCombatJson $doc.RootElement}finally{$doc.Dispose()}
        $v=$json|ConvertFrom-Json -Depth 8
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){return $null};throw}
    finally{if($file){$file.Dispose()}}
    Assert-GameplayCombatKeys $v @('schema','kind','run','world_id','target_pid','target_start_filetime','patch_run','patch_sha256','seq','utc_ms','hurt_ack','hit')
    if(-not(Test-GameplayCombatInteger $v.schema 1 1) -or $v.kind -cne 'minecome_gameplay_combat_guest_v1' -or $v.run -cne $Identity.Run -or $v.world_id -cne $Identity.WorldId -or
        -not(Test-GameplayCombatInteger $v.target_pid 1 2147483647) -or $v.target_pid -ne $Identity.Pid -or $v.target_start_filetime -isnot [string] -or $v.target_start_filetime -cne $Identity.Start -or
        $v.patch_run -cne $Identity.PatchRun -or $v.patch_sha256 -cne $Identity.PatchHash){throw 'Combat snapshot identity differs.'}
    if(-not(Test-GameplayCombatInteger $v.seq 1 10000000) -or -not(Test-GameplayCombatInteger $v.utc_ms 1 ($Now+50)) -or -not(Test-GameplayCombatInteger $v.hurt_ack 0 10000000)){throw 'Combat clock/sequence invalid.'}
    if($null -ne $v.hit){
        $h=$v.hit;Assert-GameplayCombatKeys $h @('seq','token','damage_mc','damage_fraction','weapon','source_seq','origin','target')
        if(-not(Test-GameplayCombatInteger $h.seq 1 10000000) -or -not(Test-GameplayCombatInteger $h.token 1 256) -or -not(Test-GameplayCombatInteger $h.source_seq 1 10000000) -or
            -not(Test-GameplayCombatNumber $h.damage_mc) -or $h.damage_mc -le 0 -or $h.damage_mc -gt 1000 -or -not(Test-GameplayCombatNumber $h.damage_fraction) -or
            $h.damage_fraction -le 0 -or $h.damage_fraction -gt 50 -or [Math]::Abs($h.damage_mc/20-$h.damage_fraction) -gt .00001 -or
            $h.weapon -isnot [string] -or $h.weapon -cnotmatch '^[a-z0-9_.-]+:[a-z0-9_./-]+$' -or $h.weapon.Length -gt 160){throw 'Combat melee payload invalid.'}
        foreach($point in @($h.origin,$h.target)){Assert-GameplayCombatKeys $point @('x','y','z');foreach($axis in @('x','y','z')){if(-not(Test-GameplayCombatNumber $point.$axis) -or [Math]::Abs($point.$axis) -ge 10000000){throw 'Combat vector invalid.'}}}
    }
    if($Now-$v.utc_ms -gt 500){return $null}
    return $v
}
function New-GameplayCombatState($Identity,[string]$Directory,[long]$ExpiresUtcMs){
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($Identity.Run -cnotmatch '^[0-9a-f]{32}$' -or $Identity.WorldId -cnotmatch '^[0-9a-f-]{36}$' -or $Identity.PatchRun -cnotmatch '^[0-9a-f]{32}$' -or $Identity.PatchHash -cnotmatch '^[0-9a-f]{64}$' -or
        -not(Test-GameplayCombatInteger $Identity.Pid 1 2147483647) -or $Identity.Start -isnot [string] -or $Identity.Start -cnotmatch '^[0-9]{16,20}$' -or $ExpiresUtcMs-$now -lt 1000 -or $ExpiresUtcMs-$now -gt 86400000){throw 'Combat identity/expiry invalid.'}
    [pscustomobject]@{Identity=$Identity;Directory=$Directory;SnapshotFile=(Join-Path $Directory 'combat.json');HostFile=(Join-Path $Directory 'host-combat.json');ExpiresUtcMs=$ExpiresUtcMs;StartedUtcMs=$now;Probe=$null;
        BeginSent=$false;Begin=$null;Terminal=$null;Failure=$null;Stopping=$false;LastSendUtcMs=0L;Sequence=0L;PublishedSequence=0L;LastSampleUtcMs=0L;SampleTimes=@{};Actors=@();Projectiles=(New-GameplayProjectilesState $Identity $Directory);Blasts=(New-GameplayBlastsState $Identity $Directory);
        GuestSequence=0L;GuestUtcMs=0L;GuestCanonical='';LastGuestUtcMs=0L;HitAck=0L;PendingHit=$null;PendingSinceUtcMs=0L;LastHit=$null;HitCount=0L;DamageCount=0L;RejectedCount=0L;LastPublicationUtcMs=0L;TemporaryClean=$true}
}
function New-GameplayCombatHost {
    param($Context,$Identity,[string]$Directory,[long]$ExpiresUtcMs)
    Assert-MineComeProbeContext $Context
    if($Identity.Pid -ne $Context.GamePid -or $Identity.Start -cne $Context.GameStartedUtc.ToFileTimeUtc().ToString()){throw 'Combat target process differs.'}
    $Directory=Resolve-HudMovementEvidencePath $Directory $Context.ProjectRoot
    if(-not [IO.Directory]::Exists($Directory)){throw 'Combat gameplay directory missing.'}
    $s=New-GameplayCombatState $Identity $Directory $ExpiresUtcMs
    $s.Probe=New-MineComeProbeRun $Context 'gameplay-combat' (Join-Path $Context.ProjectRoot 'kcd2/gameplay/combat_session.lua') 'GameplayCombatBegin' -PrepareOnly
    return $s
}
function Publish-GameplayCombatFile([string]$Temporary,[string]$Destination,[ValidateRange(1,100)][int]$RetryMilliseconds=100){
    # Mirror Publish-GameplayMovementView's bounded Windows replacement policy.
    # Retry only the rename with the exact original bytes/UTC, never a native hit.
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        try{
            if([IO.File]::Exists($Destination)){[IO.File]::Replace($Temporary,$Destination,[NullString]::Value)}else{[IO.File]::Move($Temporary,$Destination,$false)}
            return
        }catch{
            $cause=$_.Exception.GetBaseException();$code=$cause.HResult -band 0xffff
            if((($cause -isnot [IO.IOException] -and $cause -isnot [UnauthorizedAccessException]) -or $code -notin @(5,32,33,1175)) -or $watch.ElapsedMilliseconds -ge $RetryMilliseconds){
                throw [IO.IOException]::new("Combat snapshot publication failed (Win32 $code, $($watch.ElapsedMilliseconds) ms): $($cause.Message)",$cause)
            }
            Start-Sleep -Milliseconds ([int][Math]::Max(0,[Math]::Min(5,$RetryMilliseconds-$watch.ElapsedMilliseconds)))
        }
    }
}
function Remove-GameplayCombatTemporary($State){
    try{[IO.File]::Delete($State.HostFile+'.tmp');$State.TemporaryClean=$true}catch{$State.TemporaryClean=$false;if(-not $State.Failure){$State.Failure='Combat temporary snapshot cleanup failed.'}}
}
function Write-GameplayCombatSnapshot($State,[long]$Now){
    $id=$State.Identity
    $value=[ordered]@{schema=1;kind='minecome_gameplay_combat_host_v1';run=$id.Run;world_id=$id.WorldId;target_pid=$id.Pid;target_start_filetime=$id.Start;patch_run=$id.PatchRun;patch_sha256=$id.PatchHash;
        seq=$State.PublishedSequence;utc_ms=$Now;actors=@($State.Actors);hurts=@();hit_ack=$State.HitAck}
    $temp=$State.HostFile+'.tmp';$State.TemporaryClean=$false
    [IO.File]::WriteAllText($temp,($value|ConvertTo-Json -Depth 8 -Compress),[Text.UTF8Encoding]::new($false));Publish-GameplayCombatFile $temp $State.HostFile
    $State.TemporaryClean=$true
    $State.LastPublicationUtcMs=$Now
}
function Get-GameplayCombatCommands($State,[long]$Now){
    if($State.Failure){throw $State.Failure};if($State.Stopping){return ''};if($Now -ge $State.ExpiresUtcMs){throw 'Combat identity expired.'}
    $run=$State.Identity.Run
    if(-not $State.BeginSent){$State.BeginSent=$true;$State.LastSendUtcMs=$Now;return "MineCome.GameplayCombatBegin('$run',$([Math]::Min(86400000,$State.ExpiresUtcMs-$Now)),16,8)"}
    if(-not $State.Begin){if($Now-$State.LastSendUtcMs -gt 1500){throw 'Native combat begin unacknowledged.'};return ''}
    if($State.PendingHit -and $Now-$State.PendingSinceUtcMs -gt 1500){throw 'Native combat damage acknowledgement missing; attack will not be retried.'}
    $snapshot=Read-GameplayCombatSnapshot $State.SnapshotFile $State.Identity $Now
    $commands=[Collections.Generic.List[string]]::new()
    if($snapshot){
        $canonical=$snapshot|ConvertTo-Json -Depth 8 -Compress
        if($snapshot.seq -lt $State.GuestSequence -or $snapshot.utc_ms -lt $State.GuestUtcMs -or ($snapshot.seq -eq $State.GuestSequence -and $canonical -cne $State.GuestCanonical)){throw 'Combat guest sequence changed or regressed.'}
        if($snapshot.hurt_ack -ne 0){throw 'Unknown native hurt acknowledgement.'}
        $State.GuestSequence=[long]$snapshot.seq;$State.GuestUtcMs=[long]$snapshot.utc_ms;$State.GuestCanonical=$canonical;$State.LastGuestUtcMs=$Now
        $h=$snapshot.hit
        if($h -and $h.seq -gt $State.HitAck){
            if($State.PendingHit){if(($h|ConvertTo-Json -Depth 5 -Compress) -cne ($State.PendingHit|ConvertTo-Json -Depth 5 -Compress)){throw 'Pending melee request changed.'}}
            else{
                $sample=$State.SampleTimes[[long]$h.source_seq]
                if($null -eq $sample -or $Now-[long]$sample -gt 300){$State.HitAck=[long]$h.seq;$State.RejectedCount++;$State.LastHit=[pscustomobject]@{seq=$h.seq;result='stale_source'} }
                else{
                    $State.PendingHit=$h;$State.PendingSinceUtcMs=$Now
                    $values=@($h.seq,$h.token,$h.source_seq,$h.damage_fraction,$h.origin.x,$h.origin.y,$h.origin.z,$h.target.x,$h.target.y,$h.target.z)|ForEach-Object {([double]$_).ToString('R',[Globalization.CultureInfo]::InvariantCulture)}
                    $commands.Add("MineCome.GameplayCombatHit('$run',$([string]::Join(',',$values)))")
                }
            }
        }
    }
    if($Now-$State.LastSendUtcMs -ge 100){
        if($State.Sequence-$State.PublishedSequence -gt 3 -or ($State.LastSampleUtcMs -gt 0 -and $Now-$State.LastSampleUtcMs -gt 1500)){throw 'Native combat samples expired.'}
        $State.Sequence++;$State.LastSendUtcMs=$Now;$commands.Add("MineCome.GameplayCombatSample('$run',$($State.Sequence))")
    }
    $projectileCommand=Get-GameplayCombatUrgentCommands $State $Now;if($projectileCommand){$commands.Add($projectileCommand)}
    return [string]::Join(';',$commands)
}
function Get-GameplayCombatUrgentCommands($State,[long]$Now){
    # Projectile flight waits for native collision, so it may use the existing
    # console owner's camera-ACK wait. Do not advance melee/sample cadence here.
    if($State.Failure){throw $State.Failure};if($State.Stopping){return ''};if($Now -ge $State.ExpiresUtcMs){throw 'Combat identity expired.'}
    if(-not $State.Begin){return ''}
    $blast=Get-GameplayBlastCommands $State.Blasts $Now
    $projectile=Get-GameplayProjectileCommands $State.Projectiles $Now
    return (@($blast,$projectile)|Where-Object {$_}) -join ';'
}
function Accept-GameplayCombatReceipt($State,$Receipt,[long]$Now){
    if(-not(Test-GameplayCombatInteger $Receipt.schema 1 1) -or $Receipt.run -cne $State.Identity.Run){throw 'Combat receipt identity differs.'}
    if($Receipt.event -cin @('projectile_trace','projectile_impact')){Accept-GameplayProjectileReceipt $State.Projectiles $Receipt $Now;return}
    if($Receipt.event -cin @('blast_prepare','blast_commit')){Accept-GameplayBlastReceipt $State.Blasts $Receipt $Now;return}
    switch -CaseSensitive ($Receipt.event){
        'begin'{if($State.Begin -or $Receipt.result -cne 'ready' -or $Receipt.active -ne $true -or $Receipt.lock_policy_active -isnot [bool] -or $Receipt.lock_policy_active -ne $true){throw 'Combat begin differs.'};$State.Begin=$Receipt}
        'sample'{
            if($Receipt.result -cne 'sampled' -or $Receipt.active -ne $true -or -not(Test-GameplayCombatInteger $Receipt.seq ($State.PublishedSequence+1) $State.Sequence) -or @($Receipt.actors).Count -gt 8 -or -not(Test-GameplayCombatInteger $Receipt.hit_ack 0 $State.HitAck)){throw 'Combat sample differs.'}
            $seen=[Collections.Generic.HashSet[int]]::new();$actors=[Collections.Generic.List[object]]::new()
            foreach($a in @($Receipt.actors)){
                Assert-GameplayCombatKeys $a @('token','x','y','z','width','height','health','max_health','alive')
                if(-not(Test-GameplayCombatInteger $a.token 1 256) -or -not $seen.Add([int]$a.token) -or $a.alive -isnot [bool]){throw 'Native combat actor token differs.'}
                foreach($f in @('x','y','z','width','height','health','max_health')){if(-not(Test-GameplayCombatNumber $a.$f)){throw 'Native combat actor geometry/health invalid.'}}
                if([Math]::Abs($a.x) -ge 10000000 -or [Math]::Abs($a.y) -ge 10000000 -or [Math]::Abs($a.z) -ge 10000000 -or $a.width -lt .05 -or $a.width -gt 4 -or $a.height -lt .05 -or $a.height -gt 5 -or $a.max_health -le 0 -or $a.max_health -gt 1000000 -or $a.health -lt 0 -or $a.health -gt $a.max_health -or ($a.alive -and $a.health -le 0)){throw 'Native combat actor bounds invalid.'}
                $actors.Add($a)
            }
            $State.PublishedSequence=[long]$Receipt.seq;$State.LastSampleUtcMs=$Now;$State.SampleTimes[[long]$Receipt.seq]=$Now;$State.Actors=$actors.ToArray()
            foreach($key in @($State.SampleTimes.Keys)){if($Now-$State.SampleTimes[$key] -gt 300 -or [long]$key -lt $State.PublishedSequence-4){$State.SampleTimes.Remove($key)}}
            Write-GameplayCombatSnapshot $State $Now
        }
        'hit'{
            if(-not $State.PendingHit -or $Receipt.seq -ne $State.PendingHit.seq -or $Receipt.hit_ack -ne $Receipt.seq -or $Receipt.active -ne $true -or
                $Receipt.result -cnotin @('damaged','no_damage','invalid_hit','stale_target','target_changed','view_changed','out_of_reach','aim_changed','occlusion_unknown','occluded','damage_unconfirmed')){throw 'Combat hit acknowledgement differs.'}
            if($Receipt.result -cin @('damaged','no_damage') -and (-not(Test-GameplayCombatNumber $Receipt.before) -or -not(Test-GameplayCombatNumber $Receipt.after) -or $Receipt.before -lt 0 -or $Receipt.after -lt 0 -or $Receipt.after -gt $Receipt.before+.01)){throw 'Native damage outcome invalid.'}
            $State.HitAck=[long]$Receipt.seq;$State.LastHit=$Receipt;$State.PendingHit=$null;$State.HitCount++
            if($Receipt.result -ceq 'damaged'){$State.DamageCount++}elseif($Receipt.result -cne 'no_damage'){$State.RejectedCount++}
        }
        'terminal'{$State.Terminal=$Receipt;Remove-GameplayCombatTemporary $State;if(-not $State.Stopping -or $Receipt.result -cne 'explicit_stop' -or $Receipt.timers_cancelled -ne $true -or $Receipt.lock_policy_restored -isnot [bool] -or $Receipt.lock_policy_restored -ne $true){$State.Failure='Native combat stopped or lock settings not restored: '+$Receipt.result}}
        default{throw 'Unknown combat receipt event.'}
    }
}
function Get-GameplayCombatStopCommand($State){$State.Stopping=$true;Remove-GameplayCombatTemporary $State;Stop-GameplayProjectilesHost $State.Projectiles;Stop-GameplayBlastsHost $State.Blasts;return "MineCome.GameplayCombatEnd('$($State.Identity.Run)')"}
function Get-GameplayCombatHostState($State){
    [pscustomobject]@{Run=$State.Identity.Run;Begin=$State.Begin;Terminal=$State.Terminal;Failure=$State.Failure;Samples=$State.PublishedSequence;Actors=@($State.Actors).Count;Hits=$State.HitCount;Damaged=$State.DamageCount;Rejected=$State.RejectedCount;HitAck=$State.HitAck;LastHit=$State.LastHit;
        Projectiles=(Get-GameplayProjectilesHostState $State.Projectiles);Blasts=(Get-GameplayBlastsHostState $State.Blasts);IncomingDamageImplemented=$false;TemporaryClean=$State.TemporaryClean;CleanupComplete=($State.TemporaryClean -and (Get-GameplayProjectilesHostState $State.Projectiles).CleanupComplete -and (Get-GameplayBlastsHostState $State.Blasts).CleanupComplete -and (-not $State.BeginSent -or ($State.Terminal -and $State.Terminal.result -ceq 'explicit_stop' -and $State.Terminal.timers_cancelled -eq $true -and $State.Terminal.lock_policy_restored -is [bool] -and $State.Terminal.lock_policy_restored -eq $true)))}
}
