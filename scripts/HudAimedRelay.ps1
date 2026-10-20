#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit minor-2 relay; dot sourcing never loads Lua or starts a process.
. (Join-Path $PSScriptRoot 'HudStoneRelay.ps1')

function Assert-MineComeAimedInteger($Value,[long]$Minimum=0,[long]$Maximum=9007199254740991) {
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Aimed receipt integer invalid.'}
}
function Assert-MineComeAimedFlag($Value,[bool]$Expected) {
    if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Aimed receipt Boolean invalid.'}
}
function ConvertFrom-MineComeAimedJson([string]$Text) {
    # ConvertFrom-Json alone accepts repeated keys. Recursively reject them first.
    $document=[Text.Json.JsonDocument]::Parse($Text)
    function Visit-AimedJson($Node) {
        if($Node.ValueKind -eq [Text.Json.JsonValueKind]::Object){
            $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($property in $Node.EnumerateObject()){if(-not $names.Add($property.Name)){throw 'Repeated aimed JSON key.'};Visit-AimedJson $property.Value}
        }elseif($Node.ValueKind -eq [Text.Json.JsonValueKind]::Array){foreach($item in $Node.EnumerateArray()){Visit-AimedJson $item}}
    }
    try{Visit-AimedJson $document.RootElement;$Text | ConvertFrom-Json -Depth 32}finally{$document.Dispose()}
}
function ConvertFrom-MineComeHudAimedRelayLog([string]$Text,[string]$Run,[switch]$Completed) {
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $Text.Length -gt 2MB){throw 'Invalid aimed relay log identity or extent.'}
    if($Completed -and $Text.Length -gt 0 -and -not $Text.EndsWith("`n")){throw 'Completed aimed relay log has a partial line.'}
    $collections=@{}
    foreach($name in @('begin_sessions','cleanup_sessions','input_begins','input_ends','permits','captures','dispatches','results','rejections','events','engine_acks','lua_sessions','lua_permits','input_cancels')){$collections[$name]=[Collections.Generic.List[object]]::new()}
    $world=$false;$summary=$null;$lineNumber=0
    foreach($line in ($Text -split "`n" | Select-Object -SkipLast 1)){
        $line=$line.TrimEnd("`r");$lineNumber++
        if($line -cmatch '^STONE_(BEGIN|CLEANUP)_ACK session=([1-9][0-9]{0,15})$'){
            $kind=$Matches[1];$id=[long]$Matches[2];Assert-MineComeAimedInteger $id 1
            $collections[$(if($kind -ceq 'BEGIN'){'begin_sessions'}else{'cleanup_sessions'})].Add($id)
        }elseif($line -cmatch '^AIM_INPUT_(BEGIN|END)_ACK run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15})$'){
            $kind=$Matches[1];$runValue=$Matches[2];$arena=[long]$Matches[3];Assert-MineComeAimedInteger $arena 1
            if($runValue -cne $Run){throw 'Aimed input ACK run differs.'}
            $collections[$(if($kind -ceq 'BEGIN'){'input_begins'}else{'input_ends'})].Add([pscustomobject]@{arena=$arena;line=$lineNumber})
        }elseif($line -cmatch '^AIM_PERMIT_READY run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15}) installed_utc_ms=([1-9][0-9]{0,18})$'){
            $runValue=$Matches[1];$arena=[long]$Matches[2];$permit=[long]$Matches[3];$utc=[long]$Matches[4]
            Assert-MineComeAimedInteger $arena 1;Assert-MineComeAimedInteger $permit 1
            if($runValue -cne $Run){throw 'Aimed permit run differs.'}
            $collections.permits.Add([pscustomobject]@{arena=$arena;permit=$permit;installed_utc_ms=$utc;line=$lineNumber})
        }elseif($line -cmatch '^AIM_INPUT_DISPATCH run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15}) request=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15}) click=([1-9][0-9]{0,15}) action=([12])$'){
            $fields=@(1..6|ForEach-Object{$Matches[$_]});if($fields[0] -cne $Run){throw 'Aimed dispatch run differs.'}
            foreach($n in $fields[1..4]){Assert-MineComeAimedInteger ([long]$n) 1}
            $collections.dispatches.Add([pscustomobject]@{arena=[long]$fields[1];request_id=[long]$fields[2];permit_id=[long]$fields[3];click=[long]$fields[4];action=[int]$fields[5];line=$lineNumber})
        }elseif($line -cmatch '^AIM_INPUT_RESULT run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15}) request=([1-9][0-9]{0,15}) action=([12]) result=(10|[1-9])$'){
            $fields=@(1..5|ForEach-Object{$Matches[$_]});if($fields[0] -cne $Run){throw 'Aimed result run differs.'}
            Assert-MineComeAimedInteger ([long]$fields[1]) 1;Assert-MineComeAimedInteger ([long]$fields[2]) 1
            $collections.results.Add([pscustomobject]@{arena=[long]$fields[1];request_id=[long]$fields[2];action=[int]$fields[3];result=[int]$fields[4];line=$lineNumber})
        }elseif($line -cmatch '^AIM_INPUT_REJECTED reason=([a-z_]+)(?: run=([0-9a-f]{32}) request=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15}))?$'){
            $reason=$Matches[1];$runValue=$null;$id=$null;$permit=$null
            if($Matches.ContainsKey(2)){
                $runValue=$Matches[2];$id=[long]$Matches[3];$permit=[long]$Matches[4]
                if($runValue -cne $Run){throw 'Aimed rejection run differs.'}
                Assert-MineComeAimedInteger $id 1;Assert-MineComeAimedInteger $permit 1
            }
            $collections.rejections.Add([pscustomobject]@{reason=$reason;run=$runValue;request_id=$id;permit_id=$permit;line=$lineNumber})
        }elseif($line -cmatch '^AIM_INPUT_CANCEL run=([0-9a-f]{32}) arena=([1-9][0-9]{0,15}) authority_revoked=true sent_requests_recallable=false$'){
            if($Matches[1] -cne $Run){throw 'Aimed cancellation run differs.'}
            $collections.input_cancels.Add([pscustomobject]@{arena=[long]$Matches[2];line=$lineNumber})
        }elseif($line -cmatch '^STONE_ENGINE_ACK session=([1-9][0-9]{0,15}) sequence=([1-9][0-9]{0,15}) result=(spawned|already_present|removed|absent)$'){
            $collections.engine_acks.Add([pscustomobject]@{session=[long]$Matches[1];sequence=[long]$Matches[2];result=$Matches[3];line=$lineNumber})
        }elseif($line -cmatch '^KCD2_LOG .*\[(MineComeAimInput|MineComeAimSession|MineComeAimPermit|MineComeBlock)\] (\{[^\r\n]*\})$'){
            $tag=$Matches[1];$record=ConvertFrom-MineComeAimedJson $Matches[2];$record|Add-Member NoteProperty journal_line $lineNumber
            $name=switch($tag){'MineComeAimInput'{'captures'};'MineComeAimSession'{'lua_sessions'};'MineComeAimPermit'{'lua_permits'};'MineComeBlock'{'events'}}
            $collections[$name].Add($record)
        }elseif($line -cmatch '^KCD2_LOG .*\[MineComePose\] (\{[^\r\n]*\})$'){
            if(-not $world){$record=ConvertFrom-MineComeAimedJson $Matches[1];if($record.schema -eq 1 -and $null -ne $record.player -and $null -ne $record.camera){$world=$true}}
        }elseif($line -cmatch '^Stone engine acknowledgements: placed=([0-9]+) removed=([0-9]+) rejected=([0-9]+) cleanup_ack=(true|false; Lua lease remains responsible)$'){
            if($summary){throw 'Duplicate aimed engine summary.'}
            $summary=[pscustomobject]@{placed=[int]$Matches[1];removed=[int]$Matches[2];rejected=[int]$Matches[3];cleanup_ack=($Matches[4] -ceq 'true')}
        }elseif($line -match '^(AIM_(INPUT_(BEGIN_ACK|END_ACK|DISPATCH|RESULT|REJECTED|CANCEL)|PERMIT_READY)|STONE_(BEGIN_ACK|CLEANUP_ACK|ENGINE_ACK))\b' -or $line -match '\[(MineComeAimInput|MineComeAimSession|MineComeAimPermit|MineComeBlock)\]'){
            throw 'Malformed aimed relay receipt.'
        }
    }
    $result=[ordered]@{fresh_world=$world;summary=$summary}
    foreach($name in $collections.Keys){
        $limit=if($name -in @('permits','lua_permits')){1800}elseif($name -eq 'lua_sessions'){2}elseif($name -eq 'events'){33}elseif($name -eq 'engine_acks'){17}else{16}
        if($collections[$name].Count -gt $limit){throw 'Aimed relay receipt bound exceeded.'}
        $result[$name]=@($collections[$name].ToArray())
    }
    [pscustomobject]$result
}

function ConvertFrom-MineComeHudAimedAudit([string]$Text,[switch]$Completed) {
    if($Text.Length -gt 2MB -or ($Completed -and $Text.Length -gt 0 -and -not $Text.EndsWith("`n"))){throw 'Aimed audit extent or final line invalid.'}
    $hello=0;$anchor=$null;$ended=$false;$lastTime=0L;$requests=[Collections.Generic.List[object]]::new();$results=[Collections.Generic.List[object]]::new();$queueDrops=[Collections.Generic.List[object]]::new()
    $lastId=0L;$permits=[Collections.Generic.HashSet[long]]::new()
    foreach($line in ($Text -split "`n"|Select-Object -SkipLast 1)){
        $line=$line.TrimEnd("`r")
        if($line -notmatch '(HELLO authenticated|AIM_|session ended)'){continue}
        if($line -cnotmatch '^([1-9][0-9]{0,18}) (.+)$'){throw 'Malformed aimed audit timestamp.'}
        $stamp=[long]$Matches[1];$body=$Matches[2]
        if($stamp -lt $lastTime){throw 'Aimed audit clock moved backwards.'};$lastTime=$stamp
        if($body -ceq 'HELLO authenticated; protocol 1.2 session ready; peer role=minecraft'){
            if(++$hello -ne 1 -or $ended){throw 'Aimed audit reconnected.'}
        }elseif($body -cmatch '^AIM_ARENA_ACK arena=([1-9][0-9]{0,15}) connection=([1-9][0-9]{0,15}) reset=([1-9][0-9]{0,15})$'){
            if($hello -ne 1 -or $anchor -or $ended){throw 'Aimed audit arena lacks unique authentication.'}
            $values=@(1..3|ForEach-Object{[long]$Matches[$_]});foreach($n in $values){Assert-MineComeAimedInteger $n 1}
            $anchor=[pscustomobject]@{arena=$values[0];connection=$values[1];reset=$values[2]}
        }elseif($body -cmatch '^AIM_REQUEST arena=([1-9][0-9]{0,15}) request=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15})$'){
            $arena=[long]$Matches[1];$id=[long]$Matches[2];$permit=[long]$Matches[3];foreach($n in @($arena,$id,$permit)){Assert-MineComeAimedInteger $n 1}
            if(-not $anchor -or $ended -or $arena -ne $anchor.arena -or $id -le $lastId -or -not $permits.Add($permit) -or $requests.Count -ne $results.Count -or $requests.Count+$queueDrops.Count -ge 16){throw 'Aimed audit dispatch identity/order invalid.'}
            $requests.Add([pscustomobject]@{arena=$arena;request_id=$id;permit_id=$permit});$lastId=$id
        }elseif($body -cmatch '^AIM_QUEUE_DROPPED arena=([1-9][0-9]{0,15}) request=([1-9][0-9]{0,15}) permit=([1-9][0-9]{0,15}) reason=permit_expired admission_age_us=(0|[1-9][0-9]{0,18}) dispatch_age_us=([1-9][0-9]{0,18})$'){
            $arena=[long]$Matches[1];$id=[long]$Matches[2];$permit=[long]$Matches[3];$admission=[long]$Matches[4];$dispatch=[long]$Matches[5]
            foreach($n in @($arena,$id,$permit)){Assert-MineComeAimedInteger $n 1}
            Assert-MineComeAimedInteger $admission 0 500000;Assert-MineComeAimedInteger $dispatch 500001 ([long]::MaxValue)
            if(-not $anchor -or $ended -or $arena -ne $anchor.arena -or $id -le $lastId -or -not $permits.Add($permit) -or $requests.Count -ne $results.Count -or $requests.Count+$queueDrops.Count -ge 16){throw 'Aimed audit queue-drop identity/order invalid.'}
            # This consumes an unsent intent, never a guest request or result.
            $queueDrops.Add([pscustomobject]@{arena=$arena;request_id=$id;permit_id=$permit;reason='permit_expired';admission_age_us=$admission;dispatch_age_us=$dispatch});$lastId=$id
        }elseif($body -cmatch '^AIM_RESULT arena=([1-9][0-9]{0,15}) request=([1-9][0-9]{0,15}) result=(10|[1-9])$'){
            $arena=[long]$Matches[1];$id=[long]$Matches[2];$code=[int]$Matches[3]
            if(-not $anchor -or $ended -or $arena -ne $anchor.arena -or $requests.Count -ne $results.Count+1 -or $id -ne $requests[-1].request_id){throw 'Aimed audit result lacks current dispatched request.'}
            $results.Add([pscustomobject]@{arena=$arena;request_id=$id;result=$code})
        }elseif($body -cmatch '^session ended: (.+)$'){
            if(-not $anchor -or $ended){throw 'Ambiguous aimed audit end.'};$ended=$true
        }else{throw 'Malformed or wrong-protocol aimed audit record.'}
    }
    if($Completed -and ($hello -ne 1 -or -not $anchor -or $requests.Count -ne $results.Count)){throw 'Incomplete aimed canonical audit.'}
    [pscustomobject]@{authenticated=($hello -eq 1 -and $null -ne $anchor);arena=$anchor;requests=@($requests.ToArray());results=@($results.ToArray());queue_drops=@($queueDrops.ToArray());ended=$ended;completed=[bool]$Completed}
}

function New-MineComeHudAimedRelay($Context,[string]$Directory,[string]$Run,[long]$ExpiresUtcMs,[ValidateRange(1,65535)][int]$Port=38765) {
    $session=New-MineComeHudStoneRelay $Context $Directory $Run $ExpiresUtcMs $Port
    $session|Add-Member NoteProperty AimProbes @()
    $session|Add-Member NoteProperty InputCleanupVerified $false
    $session|Add-Member NoteProperty GuestWorldCleanupComplete $false
    $session
}
function Update-MineComeHudAimedRelayEvidence($Session) {
    try{
        if(Test-Path -LiteralPath $Session.Stdout){$Session.Native=ConvertFrom-MineComeHudAimedRelayLog (Read-MineComeHudStoneText $Session.Stdout) $Session.Run -Completed:$Session.ExitObserved}
        elseif($Session.ExitObserved){throw 'Completed aimed relay log missing.'}
        $path=Join-Path $Session.Home 'runtime/logs/tools-bridge.log'
        if(Test-Path -LiteralPath $path){$Session.ReceiptAudit=ConvertFrom-MineComeHudAimedAudit (Read-MineComeHudStoneText $path) -Completed:$Session.ExitObserved;$Session.TransportAuthVerified=$Session.ReceiptAudit.authenticated}
        elseif($Session.ExitObserved){throw 'Completed aimed audit missing.'}
    }catch{if(-not $Session.ReceiptAuditFailure){$Session.ReceiptAuditFailure=$_.Exception.Message};$Session.EngineMirroringVerified=$false;$Session.TransportAuthVerified=$false}
}
function Assert-MineComeHudAimedRelay($Session) {
    Assert-MineComeProbeContext $Session.Context
    if($Session.Failure -or -not $Session.Ready -or -not $Session.Process -or $Session.Process.HasExited -or [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $Session.ExpiresUtcMs){throw 'Owned aimed relay unavailable or expired.'}
    if($Session.Process.Id -ne $Session.ProcessId -or $Session.Process.StartTime.ToUniversalTime() -ne $Session.ProcessStart -or -not [MineCome.Probes.TcpOwner]::OwnsLoopback($Session.Port,$Session.ProcessId)){throw 'Owned aimed relay identity/listener changed.'}
    # This runs on the physical-edge path. Replaying the growing pose/permit
    # journal here can exhaust the 250 ms edge lease. Full receipt validation is
    # performed at startup/shutdown; native input authority stays independently
    # bounded and Send rechecks the exact acknowledged original permit below.
    if($Session.ReceiptAuditFailure){throw $Session.ReceiptAuditFailure}
}
function Start-MineComeHudAimedRelay($Session) {
    if($Session.StartAttempted){throw 'Aimed relay session already used.'};$Session.StartAttempted=$true
    try{
        $remaining=$Session.ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if($remaining -lt 45000 -or $remaining -gt 180000){throw 'Aimed relay requires a fresh 45–180 second deadline.'}
        $Session.Preflight=Test-MineComeHudStoneRelayPreflight $Session.Context
        [IO.Directory]::CreateDirectory((Join-Path $Session.Home 'config'))|Out-Null
        $token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
        [IO.File]::WriteAllText($Session.TokenFile,$token+"`n",[Text.UTF8Encoding]::new($false));$token=$null
        Copy-Item -LiteralPath $Session.Preflight.DeploymentPath -Destination (Join-Path $Session.Home 'lua-deployment.json')
        $Session.Probe=New-MineComeProbeRun $Session.Context 'hud-aimed-stone-source' (Join-Path $Session.Context.ProjectRoot 'kcd2/lua/data/scripts/mods/minecome.lua') 'BeginBlockSession'
        $probe=New-MineComeProbeRun $Session.Context 'hud-aimed-ray-source' (Join-Path $Session.Context.ProjectRoot 'kcd2/probes/aim_probe.lua') 'CaptureAimSample'
        $intent=New-MineComeProbeRun $Session.Context 'hud-aimed-intent-source' (Join-Path $Session.Context.ProjectRoot 'kcd2/probes/aim_intent.lua') 'AimedIntent'
        $Session.AimProbes=@($probe,$intent)
        if((Get-FileHash -LiteralPath $Session.Preflight.NativePath).Hash -ine $Session.Preflight.NativeHash){throw 'Aimed relay executable changed before launch.'}
        $arguments=@('--home',('"'+$Session.Home+'"'),'--game-log',('"'+$Session.Context.GameLog+'"'),'--stop-file',('"'+$Session.StopFile+'"'),'--fov-unit','radians','--seconds',[string][Math]::Min(180,[Math]::Ceiling(($Session.ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())/1000)),'--port',[string]$Session.Port,'--aimed-stone','--aimed-run',$Session.Run)
        $Session.Process=Start-Process -FilePath $Session.Preflight.NativePath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $Session.Stdout -RedirectStandardError $Session.Stderr
        $null=$Session.Process.Handle;$Session.ProcessId=$Session.Process.Id;$Session.ProcessStart=$Session.Process.StartTime.ToUniversalTime()
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do{
            Assert-MineComeProbeContext $Session.Context
            if($Session.Process.HasExited){throw 'Owned aimed relay exited before readiness.'}
            Update-MineComeHudAimedRelayEvidence $Session
            if($Session.ReceiptAuditFailure){throw $Session.ReceiptAuditFailure}
            if($Session.Native -and $Session.Native.fresh_world -and [MineCome.Probes.TcpOwner]::OwnsLoopback($Session.Port,$Session.ProcessId)){$Session.Ready=$true;break}
            Start-Sleep -Milliseconds 100
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $Session.Ready){throw 'No fresh aimed engine world/camera receipt.'}
    }catch{$Session.Failure=$_.Exception.Message;throw}
}
function Send-MineComeHudAimedIntent($Session,$Selection,$Click,[scriptblock]$BeforeDispatch) {
    Assert-MineComeHudAimedRelay $Session
    Assert-MineComeAimedFlag $Selection.accepted $true
    foreach($name in @('sequence','action','utc_ms')){Assert-MineComeAimedInteger $Click.$name 1 ([long]::MaxValue)}
    foreach($name in @('sequence','action','edge_utc_ms','installed_utc_ms')){Assert-MineComeAimedInteger $Selection.$name 1 ([long]::MaxValue)}
    if($Selection.run -cne $Session.Run -or $Selection.arena -cnotmatch '^[1-9][0-9]{0,15}$' -or $Selection.permit -cnotmatch '^[1-9][0-9]{0,15}$' -or $Selection.sequence -ne $Click.sequence -or $Selection.action -ne $Click.action -or $Selection.edge_utc_ms -ne $Click.utc_ms){throw 'Aimed selection differs from physical edge.'}
    $arena=[long]$Selection.arena;$permit=[long]$Selection.permit
    Assert-MineComeAimedInteger $arena 1;Assert-MineComeAimedInteger $permit 1;Assert-MineComeAimedInteger $Click.sequence 1 16;Assert-MineComeAimedInteger $Click.action 1 2
    $command="#MineCome.AimedIntent('$($Session.Run)','$arena','$permit','$($Click.sequence)',$($Click.action))"
    if($Selection.command -cne $command -or $Session.Intents.Count -ge 16 -or @($Session.Intents|Where-Object{ $_.request_id -ge $Click.sequence -or $_.permit_id -eq $permit }).Count){throw 'Aimed command, replay or capacity invalid.'}
    $text=Read-MineComeHudStoneText $Session.Stdout
    $readyLine="AIM_PERMIT_READY run=$($Session.Run) arena=$arena permit=$permit installed_utc_ms=$($Selection.installed_utc_ms)"
    $ready=[regex]::Matches($text,('(?m)^'+[regex]::Escape($readyLine)+"`r?`n"))
    if($BeforeDispatch){$decline=& $BeforeDispatch;if($decline){return [pscustomobject]@{accepted=$false;declined=$true;reason=[string]$decline}}}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($ready.Count -ne 1 -or $Selection.installed_utc_ms -ge $Click.utc_ms -or $Click.utc_ms -gt $now -or $now-$Click.utc_ms -gt 250 -or $now-$Selection.installed_utc_ms -gt 350){return [pscustomobject]@{accepted=$false;declined=$true;reason='expired_or_unacknowledged_permit'}}
    $record=[pscustomobject]@{ordinal=$Session.Intents.Count+1;request_id=$Click.sequence;sequence=$Click.sequence;arena_id=$arena;permit_id=$permit;action=$Click.action;edge_utc_ms=$Click.utc_ms;installed_utc_ms=$Selection.installed_utc_ms;sent_utc_ms=$now;accepted=$false;failure=$null}
    $Session.Intents.Add($record);$Session.LastIntentUtcMs=$now
    try{Invoke-MineComeProbeConsole $Session.Context $command;$record.accepted=$true;return $record}
    catch{$record.failure=$_.Exception.Message;$Session.Failure=$record.failure;throw}
}

function Assert-MineComeHudAimedBridgeProof($Stone) {
    function Cell($Value) {
        foreach($axis in @('x','y','z')){Assert-MineComeAimedInteger $Value.$axis ([int]::MinValue) ([int]::MaxValue)}
        "$($Value.x),$($Value.y),$($Value.z)"
    }
    function Number($Value,[double]$Minimum=-10000000,[double]$Maximum=10000000) {
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or [double]::IsNaN($Value) -or [double]::IsInfinity($Value) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Aimed finite numeric proof invalid.'}
    }
    function Near($A,$B,[double]$Tolerance=0.000001){Number $A;Number $B;if([Math]::Abs($A-$B) -gt $Tolerance){throw 'Aimed alignment differs.'}}
    if($Stone.kind -cne 'minecome_hud_aimed_stone_bridge_v1' -or $Stone.save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){throw 'Wrong aimed guest proof kind/save.'}
    Assert-MineComeAimedInteger $Stone.schema 1 1;Assert-MineComeAimedInteger $Stone.protocol_minor 2 2
    Assert-MineComeAimedInteger $Stone.session 1;Assert-MineComeAimedInteger $Stone.world;Assert-MineComeAimedInteger $Stone.reset
    foreach($name in @('baseline_confirmed','arena_acknowledged','bootstrap_confirmed','closed')){Assert-MineComeAimedFlag $Stone.$name $true}
    foreach($name in @('failed','pending','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){Assert-MineComeAimedFlag $Stone.$name $false}
    Assert-MineComeAimedInteger $Stone.cancelled_pending 0 0
    $offer=$Stone.arena_offer;Assert-MineComeAimedInteger $offer.arenaId 1
    $seed=Cell $offer.seed;$null=Cell $offer.minimum;$null=Cell $offer.maximum
    Number $offer.blocksPerUnit 1 1
    foreach($axis in @('x','y','z')){
        if($offer.minimum.$axis -ne $offer.seed.$axis-2 -or $offer.maximum.$axis -ne $offer.seed.$axis+2){throw 'Aimed arena bounds differ from seed.'}
        Number $offer.minecraftAnchor.$axis;Number $offer.kcdAnchor.$axis
        Near $Stone.arena.alignment.minecraft_anchor.$axis $offer.minecraftAnchor.$axis
        Near $Stone.arena.alignment.host_anchor.$axis $offer.kcdAnchor.$axis
    }
    Number $Stone.arena.alignment.blocks_per_host_unit 1 1
    foreach($baseline in @($Stone.initial_baseline,$Stone.pre_bootstrap_baseline)){
        if((Cell $baseline.seed) -cne $seed){throw 'Aimed baseline seed differs.'}
        Assert-MineComeAimedFlag $baseline.seed_air $true;Assert-MineComeAimedFlag $baseline.support_solid_up $true
        Assert-MineComeAimedInteger $baseline.selected_slot 0 8;Assert-MineComeAimedInteger $baseline.selected_count 1 64
        if($baseline.selected_item -cne 'minecraft:stone'){throw 'Aimed bootstrap selected another item.'}
        Assert-MineComeAimedInteger $baseline.observation_age_ns 0 500000000
        foreach($axis in @('x','y','z')){Near $baseline.client_eye.$axis $baseline.server_eye.$axis 0.05;Near $baseline.client_eye.$axis $offer.minecraftAnchor.$axis 0.05}
    }
    $requests=@($Stone.requests);$confirmations=@($Stone.confirmations)
    Assert-MineComeAimedInteger $Stone.request_count $requests.Count $requests.Count
    Assert-MineComeAimedInteger $Stone.confirmed_actions $confirmations.Count $confirmations.Count
    Assert-MineComeAimedInteger $Stone.block_events_queued $confirmations.Count $confirmations.Count
    if($requests.Count -gt 16 -or $confirmations.Count -gt 17){throw 'Aimed proof action bound exceeded.'}
    $wireIds=@{};$permits=[Collections.Generic.HashSet[long]]::new();$lastWire=0L;$confirmed=0
    foreach($request in $requests){
        $wire=$request.wire
        Assert-MineComeAimedInteger $wire.requestId 1;Assert-MineComeAimedInteger $wire.permitId 1;Assert-MineComeAimedInteger $wire.arenaId $offer.arenaId $offer.arenaId
        Assert-MineComeAimedInteger $wire.action 1 2;Assert-MineComeAimedInteger $request.result 1 10
        Assert-MineComeAimedInteger $request.component_request_id
        foreach($name in @('session','world','reset')){Assert-MineComeAimedInteger $request.$name $Stone.$name $Stone.$name}
        if($wire.requestId -le $lastWire -or -not $permits.Add($wire.permitId)){throw 'Aimed request order/permit replay invalid.'};$lastWire=$wire.requestId
        Assert-MineComeAimedFlag $request.result_queued $true;Assert-MineComeAimedFlag $request.client_and_server ($request.result -eq 1)
        if($request.result -eq 1){
            Assert-MineComeAimedFlag $request.actions_enabled $true;Assert-MineComeAimedFlag $request.vanilla_queued $true
            Assert-MineComeAimedInteger $request.component_request_id 1;$confirmed++
        }
        # Refusals can truthfully report an old capture; only confirmed actions
        # require freshness. A stale-result receipt does not renew authority.
        Assert-MineComeAimedInteger $request.captured_age_ns 0 $(if($request.result -eq 1){500000000}else{[long]::MaxValue})
        Assert-MineComeAimedInteger $wire.occlusion 0 2;Number $wire.range 0.000001 4.5;Number $wire.nearestDistance 0 4.5
        $norm=0.0
        foreach($axis in @('x','y','z')){Number $wire.origin.$axis;Number $wire.direction.$axis -1 1;$norm+=$wire.direction.$axis*$wire.direction.$axis}
        if([Math]::Abs($norm-1) -gt 0.000001 -or ($wire.occlusion -ne 2 -and $wire.nearestDistance -ne 0)){throw 'Aimed wire ray invalid.'}
        $wireIds[[long]$wire.requestId]=$request
    }
    $owned=[Collections.Generic.HashSet[string]]::new();$matched=[Collections.Generic.HashSet[long]]::new();$components=[Collections.Generic.HashSet[long]]::new()
    $lastComponent=0L;$places=0;$breaks=0;$bootstrap=0
    foreach($confirmation in $confirmations){
        Assert-MineComeAimedInteger $confirmation.component_request_id 1;Assert-MineComeAimedInteger $confirmation.wire_request_id
        Assert-MineComeAimedInteger $confirmation.action 1 2
        Assert-MineComeAimedFlag $confirmation.client_and_server $true;Assert-MineComeAimedFlag $confirmation.block_event_queued $true
        if($confirmation.bootstrap -isnot [bool] -or -not $components.Add($confirmation.component_request_id) -or $confirmation.component_request_id -le $lastComponent){throw 'Aimed confirmation component invalid.'}
        $lastComponent=$confirmation.component_request_id;$target=Cell $confirmation.target;$null=Cell $confirmation.hit_block
        foreach($axis in @('x','y','z')){if($confirmation.target.$axis -lt $offer.minimum.$axis -or $confirmation.target.$axis -gt $offer.maximum.$axis){throw 'Aimed confirmation outside arena.'}}
        if($confirmation.bootstrap){
            if(++$bootstrap -ne 1 -or $components.Count -ne 1 -or $confirmation.action -ne 1 -or $confirmation.wire_request_id -ne 0 -or $target -cne $seed){throw 'Aimed bootstrap confirmation invalid.'}
        }else{
            $request=$wireIds[[long]$confirmation.wire_request_id]
            if(-not $request -or -not $matched.Add($confirmation.wire_request_id) -or $request.result -ne 1 -or $request.component_request_id -ne $confirmation.component_request_id -or $request.wire.action -ne $confirmation.action){throw 'Aimed confirmation lacks matching result1 request.'}
        }
        if($confirmation.action -eq 1){$places++;if(-not $owned.Add($target) -or $owned.Count -gt 16){throw 'Aimed placement duplicated/exceeded owned cells.'}}
        else{$breaks++;if(-not $owned.Remove($target)){throw 'Aimed break was not owned.'}}
    }
    if($bootstrap -ne 1 -or $matched.Count -ne $confirmed){throw 'Aimed bootstrap or confirmed request count differs.'}
    Assert-MineComeAimedInteger $Stone.confirmed_network_actions $confirmed $confirmed
    Assert-MineComeAimedInteger $Stone.confirmed_places $places $places;Assert-MineComeAimedInteger $Stone.confirmed_breaks $breaks $breaks
    Assert-MineComeAimedInteger $Stone.owned_count $owned.Count $owned.Count;Assert-MineComeAimedInteger $Stone.arena.owned_count $owned.Count $owned.Count
    Assert-MineComeAimedFlag $Stone.guest_world_cleanup_complete ($owned.Count -eq 0)
    $observed=[Collections.Generic.HashSet[string]]::new()
    foreach($cell in @($Stone.arena.owned_cells)){if(-not $observed.Add((Cell $cell))){throw 'Duplicate aimed owned cell.'}}
    if(-not $owned.SetEquals($observed)){throw 'Aimed owned cells differ from confirmed transitions.'}
}

function Assert-MineComeHudAimedRelayGuest($Session,$Guest) {
    $Session.EngineMirroringVerified=$false;$Session.InputDisposition=$null
    function SampleNumber($Value,[double]$Minimum,[double]$Maximum) {
        if(($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) -or
            [double]::IsNaN([double]$Value) -or [double]::IsInfinity([double]$Value) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Aimed capture finite number invalid.'}
    }
    try{
        Update-MineComeHudAimedRelayEvidence $Session
        if($Session.Failure -or $Session.ReceiptAuditFailure -or -not $Session.ExitObserved -or $Session.ExitCode -ne 0 -or -not $Session.CleanupVerified -or -not $Session.InputCleanupVerified -or -not $Session.TransportAuthVerified){throw 'Aimed native completion/cleanup/authentication proof missing.'}
        if($Guest.run -cne $Session.Run -or $Guest.result -cne 'input_completed'){throw 'Aimed guest run incomplete or changed.'}
        foreach($name in @('ui_input_aimed_stone_bridge','ui_input_stone_bridge','ui_input_stone_live','ui_input_live_mouse','ui_input_offscreen_presentation')){Assert-MineComeAimedFlag $Guest.$name $true}
        foreach($name in @('ui_input_stone_fixture','ui_input_fixture','ui_input_pointer_fixture','ui_input_delay_fixture','ui_input_background_trial','ui_input_offscreen_trial')){Assert-MineComeAimedFlag $Guest.$name $false}
        $proof=$Guest.lab_evidence;$stone=$proof.stone_bridge
        foreach($name in @('aimed_stone_bridge','live_mouse','host_armed')){Assert-MineComeAimedFlag $proof.$name $true};Assert-MineComeAimedFlag $proof.input_fixture $false
        Assert-MineComeAimedInteger $proof.input_events_applied;Assert-MineComeAimedInteger $proof.input_consumed_sequence $proof.input_events_applied $proof.input_events_applied
        Assert-MineComeHudAimedBridgeProof $stone
        if($stone.save -cne $Guest.save -or $stone.confirmed_network_actions -lt 1){throw 'Live aimed check lacks an actual confirmed physical interaction.'}
        $native=$Session.Native;$audit=$Session.ReceiptAudit;$requests=@($stone.requests);$intents=@($Session.Intents.ToArray());$offer=$stone.arena_offer
        if($audit.queue_drops.Count){throw 'Bounded aimed verification contains an expired unsent intent; no guest action is claimed for it.'}
        if(-not $native.fresh_world -or -not $audit.completed -or $audit.arena.arena -ne $offer.arenaId -or $intents.Count -gt 16 -or
            $native.captures.Count -ne $intents.Count -or $native.dispatches.Count+$native.rejections.Count -ne $intents.Count -or
            $audit.requests.Count -ne $native.dispatches.Count -or $audit.results.Count -ne $native.dispatches.Count -or $requests.Count -gt $native.dispatches.Count){throw 'Aimed source/dispatch/canonical guest count or arena mismatch.'}
        if($native.input_begins.Count -ne 1 -or $native.input_ends.Count -ne 1 -or $native.input_cancels.Count -ne 1 -or $native.input_begins[0].arena -ne $offer.arenaId -or $native.input_ends[0].arena -ne $offer.arenaId -or $native.input_cancels[0].arena -ne $offer.arenaId -or $native.input_begins[0].line -ge $native.input_cancels[0].line -or $native.input_cancels[0].line -ge $native.input_ends[0].line){throw 'Aimed independent input begin/revocation/end chain differs.'}
        if($native.lua_sessions.Count -ne 2){throw 'Aimed input lifecycle lacks exact Lua begin/end records.'}
        for($i=0;$i -lt 2;$i++){
            $lua=$native.lua_sessions[$i];$ack=if($i -eq 0){$native.input_begins[0]}else{$native.input_ends[0]}
            Assert-MineComeAimedInteger $lua.schema 1 1
            if($lua.run -isnot [string] -or $lua.run -cne $Session.Run -or $lua.arena -isnot [string] -or $lua.arena -cne [string]$offer.arenaId -or $lua.event -cne $(if($i -eq 0){'begin'}else{'end'}) -or $lua.result -cne $(if($i -eq 0){'accepted'}else{'ended'}) -or $lua.journal_line -ge $ack.line){throw 'Aimed Lua lifecycle record differs from native ACK.'}
            if($i -eq 1 -and $lua.journal_line -le $native.input_cancels[0].line){throw 'Aimed end receipt precedes authority revocation.'}
        }
        $used=[Collections.Generic.HashSet[long]]::new();$lastId=0L;$lastOutcomeLine=0;$sentIndex=0;$guestIndex=0
        $dispositions=[Collections.Generic.List[object]]::new();$nativeRefused=0;$protocolRefused=0
        for($i=0;$i -lt $intents.Count;$i++){
            $intent=$intents[$i];$capture=$native.captures[$i]
            Assert-MineComeAimedFlag $intent.accepted $true
            foreach($name in @('ordinal','request_id','sequence','arena_id','permit_id','edge_utc_ms','installed_utc_ms','sent_utc_ms')){Assert-MineComeAimedInteger $intent.$name 1}
            Assert-MineComeAimedInteger $intent.action 1 2
            if($intent.failure -or $intent.ordinal -ne $i+1 -or $intent.arena_id -ne $offer.arenaId -or $intent.request_id -le $lastId -or $intent.request_id -ne $intent.sequence -or $intent.sequence -gt 16 -or -not $used.Add($intent.permit_id)){throw 'Aimed controller intent ordering/replay invalid.'};$lastId=$intent.request_id
            $dispatches=@($native.dispatches|Where-Object{$_.request_id -eq $intent.request_id})
            $rejections=@($native.rejections|Where-Object{$_.request_id -eq $intent.request_id})
            if($dispatches.Count+$rejections.Count -ne 1){throw 'Aimed capture lacks one exclusive native dispatch or rejection.'}
            $outcome=if($dispatches.Count){$dispatches[0]}else{$rejections[0]}
            $permits=@($native.permits|Where-Object{ $_.arena -eq $intent.arena_id -and $_.permit -eq $intent.permit_id -and $_.installed_utc_ms -eq $intent.installed_utc_ms })
            if($permits.Count -ne 1 -or $intent.installed_utc_ms -ge $intent.edge_utc_ms -or $intent.edge_utc_ms -gt $intent.sent_utc_ms -or $intent.sent_utc_ms-$intent.edge_utc_ms -gt 250 -or $intent.sent_utc_ms-$intent.installed_utc_ms -gt 350){throw 'Aimed controller lacks original pre-click permit.'}
            $permit=$permits[0];$luaPermits=@($native.lua_permits|Where-Object{ $_.run -ceq $Session.Run -and $_.arena -ceq [string]$intent.arena_id -and $_.permit -ceq [string]$intent.permit_id -and $_.result -ceq 'installed' })
            if($luaPermits.Count -ne 1 -or $luaPermits[0].journal_line -ge $permit.line -or $permit.line -ge $capture.journal_line -or
                $capture.journal_line -le $lastOutcomeLine -or $capture.journal_line -le $native.input_begins[0].line -or
                $capture.journal_line -ge $outcome.line -or $outcome.line -ge $native.input_cancels[0].line){throw 'Aimed original Lua permit/capture/outcome order invalid.'}
            $lastOutcomeLine=$outcome.line
            foreach($name in @('run','arena','request','permit','click','result')){if($capture.$name -isnot [string]){throw 'Aimed Lua identifiers must remain exact decimal text.'}}
            foreach($name in @('permit_engine_time','engine_time','completed_engine_time')){
                SampleNumber $capture.$name 0 1e12
            }
            if([Math]::Abs($capture.permit_engine_time-$luaPermits[0].engine_time) -gt 0.000001 -or $capture.engine_time -lt $capture.permit_engine_time -or $capture.completed_engine_time -lt $capture.engine_time -or $capture.completed_engine_time-$capture.engine_time -gt 0.25 -or $capture.completed_engine_time-$capture.permit_engine_time -gt 0.5){throw 'Aimed capture renewed or exceeded original Lua permit.'}
            if($capture.schema -ne 1 -or $capture.run -cne $Session.Run -or $capture.arena -cne [string]$intent.arena_id -or
                $capture.request -cne [string]$intent.request_id -or $capture.permit -cne [string]$intent.permit_id -or $capture.click -cne [string]$intent.sequence -or
                $capture.action -ne $intent.action -or $capture.result -cne 'sampled' -or $capture.reason -cne 'none'){throw 'Aimed Lua sample differs from physical intent.'}
            SampleNumber $capture.range 4.5 4.5;SampleNumber $capture.nearest_distance 0 $capture.range
            Assert-MineComeAimedInteger $capture.occlusion 1 2
            $norm=0.0
            foreach($axis in @('x','y','z')){
                SampleNumber $capture.origin.$axis -10000000 10000000;SampleNumber $capture.direction.$axis -1.00001 1.00001
                $norm+=$capture.direction.$axis*$capture.direction.$axis
            }
            if([Math]::Abs($norm-1) -gt 0.00001 -or ($capture.occlusion -ne 2 -and $capture.nearest_distance -ne 0)){throw 'Aimed captured ray or obstruction invalid.'}
            if($rejections.Count){
                # These exact pre-wire refusals consume the observed intent but
                # cannot be treated as Minecraft requests, results or actions.
                if($outcome.run -cne $Session.Run -or $outcome.permit_id -ne $intent.permit_id -or
                    $outcome.reason -cnotin @('original_permit_expired','unknown_or_consumed_permit')){throw 'Aimed native rejection identity or reason cannot certify a refusal.'}
                if(@($audit.requests|Where-Object{$_.request_id -eq $intent.request_id}).Count -or
                    @($requests|Where-Object{$_.wire.requestId -eq $intent.request_id}).Count){throw 'Aimed rejected intent also claims a wire or guest request.'}
                $nativeRefused++
                $dispositions.Add([pscustomobject]@{request_id=$intent.request_id;permit_id=$intent.permit_id;action=$intent.action;outcome='native_rejected';reason=$outcome.reason;guest_result=$null})
                continue
            }
            $dispatch=$outcome;$sent=$audit.requests[$sentIndex];$result=$audit.results[$sentIndex];$sentIndex++
            if($dispatch.arena -ne $intent.arena_id -or $dispatch.permit_id -ne $intent.permit_id -or $dispatch.click -ne $intent.sequence -or $dispatch.action -ne $intent.action -or
                $sent.request_id -ne $intent.request_id -or $sent.permit_id -ne $intent.permit_id -or $result.request_id -ne $intent.request_id){throw 'Aimed dispatched physical/canonical identities differ.'}
            $guestMatches=@($requests|Where-Object{$_.wire.requestId -eq $intent.request_id})
            if($guestMatches.Count -eq 0){
                # AimedSession.receive can return AIM_STALE before the request
                # reaches the adapter. Require the actual canonical reply plus
                # its independent polled action; never synthesize adapter proof.
                $polledStale=@($native.results|Where-Object{$_.request_id -eq $intent.request_id})
                if($result.result -ne 3 -or $polledStale.Count -ne 1 -or $polledStale[0].arena -ne $intent.arena_id -or
                    $polledStale[0].action -ne $intent.action -or $polledStale[0].result -ne 3 -or $polledStale[0].line -le $dispatch.line -or
                    $polledStale[0].line -ge $native.input_cancels[0].line){throw 'Aimed wire request lacks adapter proof or an exact guest protocol stale refusal.'}
                $protocolRefused++
                $dispositions.Add([pscustomobject]@{request_id=$intent.request_id;permit_id=$intent.permit_id;action=$intent.action;outcome='guest_protocol_refused';reason='stale';guest_result=3})
                continue
            }
            if($guestMatches.Count -ne 1 -or $requests[$guestIndex].wire.requestId -ne $intent.request_id){throw 'Aimed adapter request order or identity differs.'}
            $request=$requests[$guestIndex];$wire=$request.wire;$guestIndex++
            if($wire.requestId -ne $intent.request_id -or $wire.permitId -ne $intent.permit_id -or $wire.arenaId -ne $intent.arena_id -or $wire.action -ne $intent.action -or
               $dispatch.request_id -ne $wire.requestId -or $dispatch.permit_id -ne $wire.permitId -or $dispatch.arena -ne $wire.arenaId -or $dispatch.click -ne $intent.sequence -or $dispatch.action -ne $wire.action -or
               $sent.request_id -ne $wire.requestId -or $sent.permit_id -ne $wire.permitId -or $result.request_id -ne $wire.requestId -or $result.result -ne $request.result){throw 'Aimed physical/native/wire/result identities differ.'}
            if($capture.schema -ne 1 -or $capture.run -cne $Session.Run -or $capture.arena -cne [string]$wire.arenaId -or $capture.request -cne [string]$wire.requestId -or $capture.permit -cne [string]$wire.permitId -or $capture.click -cne [string]$intent.sequence -or $capture.action -ne $wire.action -or $capture.result -cne 'sampled' -or $capture.occlusion -ne $wire.occlusion -or $capture.range -ne $wire.range -or [Math]::Abs($capture.nearest_distance-$wire.nearestDistance) -gt 0.000001){throw 'Aimed Lua sample differs from guest wire request.'}
            foreach($axis in @('x','y','z')){if([Math]::Abs($capture.origin.$axis-$wire.origin.$axis) -gt 0.000001 -or [Math]::Abs($capture.direction.$axis-$wire.direction.$axis) -gt 0.00001){throw 'Aimed camera ray changed during relay.'}}
            $dispositions.Add([pscustomobject]@{request_id=$intent.request_id;permit_id=$intent.permit_id;action=$intent.action;outcome='guest_adapter_result';reason=$null;guest_result=$request.result})
        }
        if($guestIndex -ne $requests.Count -or $sentIndex -ne $audit.requests.Count){throw 'Unmatched aimed guest or canonical request.'}
        # Polled results may lose the last sample during disconnect; the canonical
        # wire journal is complete and authoritative. Any polled overlap must match.
        $polled=[Collections.Generic.HashSet[long]]::new()
        foreach($result in $native.results){
            if(-not $polled.Add($result.request_id)){throw 'Duplicate polled aimed result.'}
            $matches=@($audit.results|Where-Object{$_.request_id -eq $result.request_id});$dispatches=@($native.dispatches|Where-Object{$_.request_id -eq $result.request_id})
            if($matches.Count -ne 1 -or $dispatches.Count -ne 1 -or $result.arena -ne $offer.arenaId -or $result.action -ne $dispatches[0].action -or $result.result -ne $matches[0].result -or
                $result.line -le $dispatches[0].line -or $result.line -ge $native.input_cancels[0].line){throw 'Polled aimed result differs from canonical guest result.'}
        }
        $confirmations=@($stone.confirmations)
        $terminalEvents=@($native.events|Where-Object{$_.result -cin @('spawned','removed')})
        $pendingEvents=@($native.events|Where-Object{$_.result -ceq 'cleanup_pending'})
        if($native.begin_sessions.Count -ne 1 -or $native.cleanup_sessions.Count -ne 1 -or $native.begin_sessions[0] -ne $native.cleanup_sessions[0] -or
            $terminalEvents.Count -ne $confirmations.Count -or $native.engine_acks.Count -ne $confirmations.Count -or
            $terminalEvents.Count+$pendingEvents.Count -ne $native.events.Count){throw 'Aimed replica action/session counts differ.'}
        $lastSequence=0L;$lastAckLine=0;$matchedPending=0
        for($i=0;$i -lt $confirmations.Count;$i++){
            $confirmation=$confirmations[$i];$event=$terminalEvents[$i];$ack=$native.engine_acks[$i]
            Assert-MineComeAimedInteger $event.schema 1 1;Assert-MineComeAimedInteger $event.sequence 1;Assert-MineComeAimedInteger $event.session 1
            Assert-MineComeAimedFlag $event.physics $false;Assert-MineComeAimedFlag $event.live_draw_verified $false
            $expected=if($confirmation.action -eq 1){'spawned'}else{'removed'}
            if($event.sequence -le $lastSequence -or $event.session -ne $native.begin_sessions[0] -or $event.operation -ne $confirmation.action -or $event.result -cne $expected -or $ack.session -ne $event.session -or $ack.sequence -ne $event.sequence -or $ack.result -cne $expected -or $event.journal_line -ge $ack.line){throw 'Aimed engine ACK lacks preceding same confirmed operation.'}
            foreach($axis in @('x','y','z')){Assert-MineComeAimedInteger $event.mc.$axis ([int]::MinValue) ([int]::MaxValue);if($event.mc.$axis -ne $confirmation.target.$axis){throw 'Aimed replica used another Minecraft cell.'}}
            $expectedPosition=@{x=$offer.kcdAnchor.x+$event.mc.x-$offer.minecraftAnchor.x;y=$offer.kcdAnchor.y-($event.mc.z-$offer.minecraftAnchor.z);z=$offer.kcdAnchor.z+$event.mc.y-$offer.minecraftAnchor.y}
            # Removed receipts legitimately report null position after entity deletion.
            if($confirmation.action -eq 1){foreach($axis in @('x','y','z')){if($null -eq $event.position -or [double]::IsNaN([double]$event.position.$axis) -or [Math]::Abs($event.position.$axis-$expectedPosition[$axis]) -gt 0.01){throw 'Aimed replica transform differs from agreed arena.'}}}
            $pending=@($pendingEvents|Where-Object{$_.sequence -eq $event.sequence})
            if($pending.Count -gt 1){throw 'Repeated aimed removal-pending receipt.'}
            if($pending.Count){
                $phase=$pending[0]
                Assert-MineComeAimedInteger $phase.schema 1 1;Assert-MineComeAimedInteger $phase.session $event.session $event.session
                Assert-MineComeAimedInteger $phase.sequence $event.sequence $event.sequence;Assert-MineComeAimedInteger $phase.operation 2 2
                Assert-MineComeAimedFlag $phase.physics $false;Assert-MineComeAimedFlag $phase.live_draw_verified $false
                if($confirmation.action -ne 2 -or $phase.event -cne 'remove' -or $phase.journal_line -le $lastAckLine -or $phase.journal_line -ge $event.journal_line){throw 'Aimed pending removal lacks a later matching terminal removal.'}
                foreach($axis in @('x','y','z')){
                    Assert-MineComeAimedInteger $phase.mc.$axis $event.mc.$axis $event.mc.$axis
                    SampleNumber $phase.position.$axis -10000000 10000000
                    if([Math]::Abs($phase.position.$axis-$expectedPosition[$axis]) -gt 0.01){throw 'Aimed pending removal position differs from agreed arena.'}
                }
                $matchedPending++
            }
            $lastSequence=$event.sequence;$lastAckLine=$ack.line
        }
        if($matchedPending -ne $pendingEvents.Count){throw 'Unmatched aimed pending removal receipt.'}
        if(-not $native.summary -or $native.summary.rejected -ne 0 -or $native.summary.placed -ne $stone.confirmed_places -or $native.summary.removed -ne $stone.confirmed_breaks){throw 'Aimed engine summary differs from confirmed guest actions.'}
        $Session.InputDisposition=[pscustomobject]@{captured_intents=$intents.Count;native_refused=$nativeRefused;wire_requests=$sentIndex;guest_protocol_refused=$protocolRefused;guest_adapter_results=$guestIndex;confirmed_network_actions=$stone.confirmed_network_actions;removal_pending_receipts=$matchedPending;outcomes=@($dispositions.ToArray())}
        $Session.GuestWorldCleanupComplete=$stone.guest_world_cleanup_complete;$Session.EngineMirroringVerified=$true
    }catch{$Session.GuestVerificationFailure=$_.Exception.Message;throw}
    finally{if(Test-Path -LiteralPath $Session.Home){Get-MineComeHudAimedRelayEvidence $Session|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $Session.Home 'relay-result.json') -Encoding utf8NoBOM}}
}

function Get-MineComeHudAimedRelayEvidence($Session) {
    Update-MineComeHudAimedRelayEvidence $Session
    [ordered]@{
        schema=1;kind='minecome_hud_aimed_relay_v1';run=$Session.Run;home=$Session.Home;port=$Session.Port
        game_pid=$Session.Context.GamePid;game_start_utc=$Session.Context.GameStartedUtc;game_hash=$Session.Context.GameHash
        relay_pid=$Session.ProcessId;relay_start_utc=$Session.ProcessStart;expires_utc_ms=$Session.ExpiresUtcMs
        native_hash=$(if($Session.Preflight){$Session.Preflight.NativeHash}else{$null});lua_probe=$Session.Probe;aim_probes=$Session.AimProbes
        ready=$Session.Ready;exit_observed=$Session.ExitObserved;exit_code=$Session.ExitCode;cleanup_verified=$Session.CleanupVerified;input_cleanup_verified=$Session.InputCleanupVerified;guest_world_cleanup_complete=$Session.GuestWorldCleanupComplete
        engine_mirroring_verified=$Session.EngineMirroringVerified;transport_auth_verified=$Session.TransportAuthVerified;visual_verified=$false;physical_block_input_verified=$false
        intents=@($Session.Intents.ToArray());input_disposition=$Session.InputDisposition;native=$Session.Native;receipt_audit=$Session.ReceiptAudit;receipt_audit_failure=$Session.ReceiptAuditFailure;failure=$Session.Failure;cleanup_failure=$Session.CleanupFailure;guest_verification_failure=$Session.GuestVerificationFailure
        kcd_launched=$false;kcd_stopped=$false;other_processes_stopped=$false;credentials_recorded=$false
    }
}
function Stop-MineComeHudAimedRelay($Session) {
    if($Session.StopAttempted){return};$Session.StopAttempted=$true
    try{
        if($Session.Process){
            if(-not $Session.Process.HasExited){[IO.File]::WriteAllText($Session.StopFile,'Graceful aimed stop requested by owning HUD controller.');$null=$Session.Process.WaitForExit(5000)}
            $Session.ExitObserved=$Session.Process.HasExited
            if($Session.ExitObserved){$Session.ExitCode=$Session.Process.ExitCode}else{throw 'Owned aimed relay did not exit in cleanup deadline; bounded process preserved.'}
            Update-MineComeHudAimedRelayEvidence $Session;$native=$Session.Native
            if(-not $native -or -not $native.summary -or -not $native.summary.cleanup_ack){throw 'Aimed relay engine cleanup unacknowledged.'}
            foreach($id in $native.begin_sessions){if(@($native.cleanup_sessions|Where-Object{$_ -eq $id}).Count -ne 1){throw 'Aimed engine session lacks unique cleanup.'}}
            $Session.CleanupVerified=$true
            if($native.input_begins.Count -eq 1 -and $native.input_ends.Count -eq 1 -and $native.input_cancels.Count -eq 1 -and $native.input_begins[0].arena -eq $native.input_ends[0].arena -and $native.input_ends[0].arena -eq $native.input_cancels[0].arena -and $native.input_begins[0].line -lt $native.input_cancels[0].line -and $native.input_cancels[0].line -lt $native.input_ends[0].line){$Session.InputCleanupVerified=$true}
            elseif($native.input_begins.Count -gt 0){throw 'Aimed Lua input gate has no independent end acknowledgement.'}
            if($Session.ExitCode -ne 0){throw 'Owned aimed relay exited unsuccessfully.'}
        }
    }catch{$Session.CleanupFailure=$_.Exception.Message;if(-not $Session.Failure){$Session.Failure=$Session.CleanupFailure}}
    finally{if(Test-Path -LiteralPath $Session.Home){Get-MineComeHudAimedRelayEvidence $Session|ConvertTo-Json -Depth 32|Set-Content -LiteralPath (Join-Path $Session.Home 'relay-result.json') -Encoding utf8NoBOM}}
}
