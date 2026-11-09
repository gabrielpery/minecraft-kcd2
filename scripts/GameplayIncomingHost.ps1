#Requires -Version 7.3
# Read-only parser for the native CombatDebug raw-GUID telemetry format.
# Source: pinned CombatDebug.StartLog plus actual eventlog captures under
# runtime/evidence/combat-stream-watch-0ba69e97163c4ec9b8ce3e6d1e681160.
# This module never enables logging, changes game health or infers losslessness.
# Callers must establish an immutable source cursor and exact native GUID mapping.
function Get-GameplayIncomingProperty($Object,[string]$Name){
    $value=[Text.Json.JsonElement]::new()
    if($Object.ValueKind -ne [Text.Json.JsonValueKind]::Object -or -not $Object.TryGetProperty($Name,[ref]$value)){throw "Native telemetry property missing: $Name"}
    return $value
}
function Get-GameplayIncomingString($Object,[string]$Name,[int]$Maximum=160){
    $value=Get-GameplayIncomingProperty $Object $Name
    if($value.ValueKind -ne [Text.Json.JsonValueKind]::String){throw "Native telemetry string invalid: $Name"}
    $text=$value.GetString();if($null -eq $text -or $text.Length -gt $Maximum){throw "Native telemetry string bound: $Name"};return $text
}
function Get-GameplayIncomingNumber($Object,[string]$Name,[double]$Minimum,[double]$Maximum){
    $value=Get-GameplayIncomingProperty $Object $Name
    if($value.ValueKind -ne [Text.Json.JsonValueKind]::Number){throw "Native telemetry number invalid: $Name"}
    $number=0.;if(-not $value.TryGetDouble([ref]$number) -or -not [double]::IsFinite($number) -or $number -lt $Minimum -or $number -gt $Maximum){throw "Native telemetry number bound: $Name"};return $number
}
function Get-GameplayIncomingGuid($Object){
    $guid=Get-GameplayIncomingString $Object 'guid' 36
    if($guid -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){throw 'Native telemetry GUID invalid.'};return $guid
}
function Assert-GameplayIncomingJson($Value,[int]$Depth=0){
    if($Depth -gt 16){throw 'Native telemetry nesting exceeded.'}
    if($Value.ValueKind -eq [Text.Json.JsonValueKind]::Object){
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($property in $Value.EnumerateObject()){
            if(-not $seen.Add($property.Name)){throw 'Duplicate native telemetry JSON field.'}
            Assert-GameplayIncomingJson $property.Value ($Depth+1)
        }
    }elseif($Value.ValueKind -eq [Text.Json.JsonValueKind]::Array){
        if($Value.GetArrayLength() -gt 4096){throw 'Native telemetry array exceeded.'}
        foreach($element in $Value.EnumerateArray()){Assert-GameplayIncomingJson $element ($Depth+1)}
    }
}
function ConvertFrom-GameplayIncomingTelemetry([string]$Text,[string]$VictimGuid,[string]$VictimName=''){
    if($VictimGuid -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -and ($VictimGuid -or -not $VictimName -or $VictimName.Length -gt 160)){throw 'Exact native victim GUID or validated entity name required.'}
    if($null -eq $Text -or $Text.Length -gt 1048576){throw 'Native telemetry exceeds1MiB.'}
    $options=[Text.Json.JsonDocumentOptions]::new();$options.MaxDepth=16
    $document=[Text.Json.JsonDocument]::Parse($Text,$options)
    try{
        $root=$document.RootElement
        if($root.ValueKind -ne [Text.Json.JsonValueKind]::Array -or $root.GetArrayLength() -gt 4096){throw 'Native telemetry must be a bounded event array.'}
        Assert-GameplayIncomingJson $root
        $result=[Collections.Generic.List[object]]::new();$index=0
        foreach($entry in $root.EnumerateArray()){
            $entryIndex=$index;$index++
            $cause=Get-GameplayIncomingProperty $entry 'cause'
            # Native SetState maintenance records have an exact empty cause.
            if($cause.ValueKind -eq [Text.Json.JsonValueKind]::Object -and @($cause.EnumerateObject()).Count -eq 0){continue}
            $causeName=Get-GameplayIncomingString $cause 'name'
            if($causeName -cne 'CombatHit'){continue}
            $victimObject=Get-GameplayIncomingProperty $cause 'victim';$victim=Get-GameplayIncomingGuid $victimObject
            $victimNameValue=$null;$attackerNameValue=$null
            if($VictimName){$victimNameValue=Get-GameplayIncomingString $victimObject 'name';if($victimNameValue -cne $VictimName){continue}}
            elseif($victim -cne $VictimGuid){continue}
            $attackerObject=Get-GameplayIncomingProperty $cause 'attacker';$attacker=Get-GameplayIncomingGuid $attackerObject
            if($VictimName){$attackerNameValue=Get-GameplayIncomingString $attackerObject 'name'}
            if($attacker -ceq $victim){throw 'Native combat hit has identical attacker and victim.'}
            $gameMs=Get-GameplayIncomingNumber $entry 'gt' 0 9007199254740991
            if($gameMs -ne [Math]::Floor($gameMs)){throw 'Native telemetry game time must be integer milliseconds.'}
            $playTime=Get-GameplayIncomingNumber $entry 'pt' 0 100000000
            $wallTime=Get-GameplayIncomingString $entry 't' 19;$date=[datetime]::MinValue
            if(-not [datetime]::TryParseExact($wallTime,'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Native telemetry wall time invalid.'}
            $attackType=Get-GameplayIncomingNumber $cause 'attackType' 0 1024;$damageType=Get-GameplayIncomingNumber $cause 'damageType' 0 1024
            if($attackType -ne [Math]::Floor($attackType) -or $damageType -ne [Math]::Floor($damageType)){throw 'Native telemetry attack classification invalid.'}
            $effects=Get-GameplayIncomingProperty $entry 'effects'
            if($effects.ValueKind -ne [Text.Json.JsonValueKind]::Array -or $effects.GetArrayLength() -gt 128){throw 'Native hit effects exceeded.'}
            $healthValues=[Collections.Generic.List[object]]::new();$healthStates=[Collections.Generic.List[object]]::new()
            foreach($effect in $effects.EnumerateArray()){
                # Native logger emits {} for some non-health effects (observed
                # after DmgR). Only that exact empty object may omit its name.
                if($effect.ValueKind -eq [Text.Json.JsonValueKind]::Object -and @($effect.EnumerateObject()).Count -eq 0){continue}
                $name=Get-GameplayIncomingString $effect 'name'
                if($name -cnotin @('HealthValue','SoulState')){continue}
                $soul=Get-GameplayIncomingGuid (Get-GameplayIncomingProperty $effect 'soul')
                if($soul -cne $victim){continue}
                if($name -ceq 'HealthValue'){
                    $opponent=Get-GameplayIncomingGuid (Get-GameplayIncomingProperty $effect 'opponent')
                    if($opponent -cne $attacker){throw 'Native health effect attacker differs.'}
                    $value=Get-GameplayIncomingNumber $effect 'value' -1000000 1000000
                    $reason=Get-GameplayIncomingString $effect 'deathReason'
                    if($reason -cne 'DR_Combat'){throw 'Native hit health effect is not combat damage.'}
                    $healthValues.Add([pscustomobject]@{Value=$value})
                }elseif((Get-GameplayIncomingString $effect 'selector') -ceq 'health'){
                    $before=Get-GameplayIncomingNumber $effect 'oldState' 0 1000000
                    $after=Get-GameplayIncomingNumber $effect 'newState' 0 1000000
                    $value=Get-GameplayIncomingNumber $effect 'value' -1000000 1000000
                    $healthStates.Add([pscustomobject]@{Before=$before;After=$after;Value=$value})
                }
            }
            # Do not turn ambiguous multiple effects into an invented aggregate.
            if($healthValues.Count -gt 1 -or $healthStates.Count -gt 1){throw 'Ambiguous native hit health effects.'}
            if($healthValues.Count -eq 0){if($healthStates.Count -and $healthStates[0].After -lt $healthStates[0].Before){throw 'Native health loss lacks an attributed HealthValue.'};continue}
            $attributed=-[double]$healthValues[0].Value
            if($attributed -le 0){if($healthStates.Count -and $healthStates[0].After -lt $healthStates[0].Before){throw 'Native health loss contradicts its attributed HealthValue.'};continue}
            $before=$null;$after=$null;$applied=$null;$stateValue=$null
            if($healthStates.Count){
                $before=[double]$healthStates[0].Before;$after=[double]$healthStates[0].After;$stateValue=[double]$healthStates[0].Value
                if($after -gt $before -or $stateValue -gt 0){throw 'Native hit mixes damage and health gain.'}
                $applied=$before-$after
                # Preserve the observed HealthValue independently of HP delta.
                # It is NOT guaranteed pre-clamp damage: live CombatHit events
                # at native HP1 reported HealthValue0 under immortality.
            }
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($entry.GetRawText()))).ToLowerInvariant()
            $result.Add([pscustomobject]@{Index=$entryIndex;CauseName=$causeName;GameMs=[long]$gameMs;PlayTime=$playTime;LoggedWallTime=$wallTime;AttackerGuid=$attacker;VictimGuid=$victim;
                AttackType=[int]$attackType;DamageType=[int]$damageType;AttackerName=$attackerNameValue;VictimName=$victimNameValue;AttributedDamage=$attributed;AppliedDamage=$applied;Before=$before;After=$after;SoulStateValue=$stateValue;EventSha256=$hash})
        }
        return [pscustomobject]@{TotalEvents=$root.GetArrayLength();Hits=$result.ToArray()}
    }finally{$document.Dispose()}
}
function New-GameplayIncomingReader([string]$VictimGuid,[long]$MinimumGameMs){
    if($VictimGuid -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or $MinimumGameMs -lt 0){throw 'Native reader identity invalid.'}
    [pscustomobject]@{VictimGuid=$VictimGuid;MinimumGameMs=$MinimumGameMs;Sources=@{};Incomplete=@{};Batches=0L;DuplicateBatches=0L;Hits=0L;OldHits=0L;AttributedDamage=0.;Stopped=$false}
}
function Add-GameplayIncomingTelemetryBatch($State,[string]$SourceId,[string]$Text,[long]$CapturedUtcMs){
    if($State.Stopped -or -not $SourceId -or $SourceId.Length -gt 512 -or $SourceId.IndexOfAny([char[]]@("`r","`n",[char]0)) -ge 0 -or $CapturedUtcMs -le 0){throw 'Native telemetry source identity invalid.'}
    if($null -eq $Text -or $Text.Length -gt 1048576){throw 'Native telemetry exceeds1MiB.'}
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
    if($State.Sources.ContainsKey($SourceId)){
        if($State.Sources[$SourceId].Hash -cne $hash){throw 'Native telemetry source cursor was overwritten; completeness cannot be established.'}
        $State.DuplicateBatches++;return @()
    }
    if($State.Sources.Count -ge 4096){throw 'Native telemetry source capacity exceeded.'}
    $batch=ConvertFrom-GameplayIncomingTelemetry $Text $State.VictimGuid
    $new=[Collections.Generic.List[object]]::new()
    foreach($hit in $batch.Hits){
        if($hit.GameMs -lt $State.MinimumGameMs){$State.OldHits++;continue}
        # Identity comes from an immutable native source offset/index, never
        # merely a payload hash: two actual identical hits must remain distinct.
        $hit|Add-Member -NotePropertyName SourceId -NotePropertyValue ($SourceId+'#'+$hit.Index)
        $hit|Add-Member -NotePropertyName CapturedUtcMs -NotePropertyValue $CapturedUtcMs
        $new.Add($hit);$State.Hits++;$State.AttributedDamage+=$hit.AttributedDamage
    }
    $State.Sources[$SourceId]=[pscustomobject]@{Hash=$hash;CapturedUtcMs=$CapturedUtcMs;TotalEvents=$batch.TotalEvents};$State.Batches++
    return $new.ToArray()
}
function Read-GameplayIncomingTelemetryFile($State,[string]$Path,[string]$SourceId,[long]$Now,[int]$IncompleteTimeoutMs=500){
    if($State.Stopped){throw 'Native telemetry reader stopped.'}
    if($IncompleteTimeoutMs -lt 1 -or $IncompleteTimeoutMs -gt 2000){throw 'Native telemetry incomplete deadline invalid.'}
    $file=$null;$text=$null;$incomplete=$false
    try{
        $file=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        if($file.Length -gt 1048576){throw 'Native telemetry file exceeds1MiB.'}
        $length=$file.Length;$bytes=[byte[]]::new([int]$length);$file.ReadExactly($bytes)
        if($length -lt 2 -or $file.Length -ne $length -or $file.ReadByte() -ne -1){$incomplete=$true}
        else{
            $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
            try{$doc=[Text.Json.JsonDocument]::Parse($text);$doc.Dispose()}catch [Text.Json.JsonException]{$incomplete=$true}
        }
    }catch [IO.IOException]{if(($_.Exception.HResult -band 0xffff) -in @(2,3,32,33,303)){$incomplete=$true}else{throw}}
    finally{if($file){$file.Dispose()}}
    if($incomplete){
        if(-not $State.Incomplete.ContainsKey($SourceId)){if($State.Incomplete.Count -ge 32){throw 'Native telemetry incomplete source capacity exceeded.'};$State.Incomplete[$SourceId]=$Now}
        if($Now-$State.Incomplete[$SourceId] -ge $IncompleteTimeoutMs){throw 'Native telemetry publication remained incomplete; source deadline not renewed.'}
        return [pscustomobject]@{Complete=$false;Hits=@()}
    }
    if($State.Incomplete.ContainsKey($SourceId) -and $Now-$State.Incomplete[$SourceId] -ge $IncompleteTimeoutMs){throw 'Native telemetry publication completed after its original deadline.'}
    $hits=@(Add-GameplayIncomingTelemetryBatch $State $SourceId $text $Now);$State.Incomplete.Remove($SourceId)
    return [pscustomobject]@{Complete=$true;Hits=$hits}
}

# This state consumes caller-proven closed directory snapshots. It never enables
# native logging and cannot prove the native writer actually closed a directory.
# Send/receive timestamps bracket the marker's native clock on the same host.
function New-GameplayIncomingEpochReader([string]$Run,[string]$VictimGuid,[double]$NativeClockMs,[long]$SentUtcMs,[long]$ReceivedUtcMs,[string]$VictimName=''){
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or ($VictimGuid -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -and ($VictimGuid -or -not $VictimName -or $VictimName.Length -gt 160)) -or
        -not [double]::IsFinite($NativeClockMs) -or $NativeClockMs -lt 0 -or $SentUtcMs -le 0 -or $ReceivedUtcMs -lt $SentUtcMs -or $ReceivedUtcMs-$SentUtcMs -gt 250){throw 'Incoming native clock anchor invalid or too uncertain.'}
    $anchors=[Collections.Generic.List[object]]::new()
    $anchors.Add([pscustomobject]@{NativeClockMs=$NativeClockMs;SentUtcMs=$SentUtcMs;ReceivedUtcMs=$ReceivedUtcMs})
    [pscustomobject]@{Run=$Run;VictimGuid=$VictimGuid;VictimName=$VictimName;MinimumGameMs=[long][Math]::Ceiling($NativeClockMs);Anchors=$anchors;
        LastSequence=0L;LastNativeClockMs=$NativeClockMs;LastManifest=$null;LastReceivedUtcMs=$ReceivedUtcMs;Hits=0L;OldHits=0L;AttributedDamage=0.}
}
function Add-GameplayIncomingClosedEpoch($State,[long]$Sequence,[double]$NativeClockMs,[long]$SentUtcMs,[long]$ReceivedUtcMs,[long]$ObservedUtcMs,[object[]]$Files){
    if($Sequence -le 0 -or $Sequence -lt $State.LastSequence -or $Sequence -gt $State.LastSequence+1 -or
        -not [double]::IsFinite($NativeClockMs) -or $NativeClockMs -lt $State.LastNativeClockMs -or
        $SentUtcMs -le 0 -or $ReceivedUtcMs -lt $SentUtcMs -or $ReceivedUtcMs-$SentUtcMs -gt 250 -or
        $ObservedUtcMs -lt $ReceivedUtcMs -or $ObservedUtcMs-$ReceivedUtcMs -gt 500 -or @($Files).Count -gt 16){throw 'Incoming closed epoch sequence/timing invalid.'}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $manifest=[Collections.Generic.List[string]]::new();$parsed=[Collections.Generic.List[object]]::new()
    foreach($file in @($Files)){
        if($file.Name -isnot [string] -or $file.Name.Length -gt 180 -or $file.Name -cnotmatch '^eventlog_[A-Za-z0-9_. -]+\.json$' -or -not $names.Add($file.Name) -or $file.Text -isnot [string] -or $file.Text.Length -gt 1048576){throw 'Incoming epoch file name/content invalid.'}
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($file.Text))).ToLowerInvariant()
        $manifest.Add($file.Name+'='+$hash)
        $batch=ConvertFrom-GameplayIncomingTelemetry $file.Text $State.VictimGuid $State.VictimName
        $parsed.Add([pscustomobject]@{Name=$file.Name;Batch=$batch})
    }
    $manifest.Sort([StringComparer]::Ordinal);$digest=[string]::Join("`n",$manifest)
    if($Sequence -eq $State.LastSequence){
        if($NativeClockMs -ne $State.LastNativeClockMs -or $digest -cne $State.LastManifest){throw 'Closed incoming epoch changed after publication.'}
        return @()
    }
    # Engine time is not a fixed offset from wall time: captured coupled play
    # drifted100ms over5.6s. Keep bounded local send/receipt anchors instead.
    $previous=$State.Anchors[$State.Anchors.Count-1]
    if($SentUtcMs -lt $previous.SentUtcMs -or $SentUtcMs-$previous.SentUtcMs -gt 1000 -or $ReceivedUtcMs -lt $State.LastReceivedUtcMs){throw 'Incoming native/host clock anchor gap or regression.'}
    $anchors=@($State.Anchors.ToArray())+@([pscustomobject]@{NativeClockMs=$NativeClockMs;SentUtcMs=$SentUtcMs;ReceivedUtcMs=$ReceivedUtcMs})
    $new=[Collections.Generic.List[object]]::new();$oldHits=0L;$damage=0.
    foreach($source in $parsed){
        foreach($hit in $source.Batch.Hits){
            if($hit.GameMs -lt $State.MinimumGameMs){$oldHits++;continue}
            if($hit.GameMs -gt $NativeClockMs){throw 'Incoming event lies after its native close receipt.'}
            $sourceClock=$null
            for($n=$anchors.Count-2;$n -ge 0;$n--){
                $before=$anchors[$n];$after=$anchors[$n+1]
                if($before.NativeClockMs -le $hit.GameMs -and $after.NativeClockMs -ge $hit.GameMs -and $after.NativeClockMs -gt $before.NativeClockMs){
                    $fraction=($hit.GameMs-$before.NativeClockMs)/($after.NativeClockMs-$before.NativeClockMs)
                    $sourceUtc=[long][Math]::Floor($before.SentUtcMs+$fraction*($after.SentUtcMs-$before.SentUtcMs))
                    $sourceClock=[pscustomobject]@{Before=$before;After=$after};break
                }
            }
            if(-not $sourceClock){throw 'Incoming event has no enclosing native clock anchors; extrapolation forbidden.'}
            if($ObservedUtcMs-$sourceUtc -gt 2000 -or $sourceUtc-$ObservedUtcMs -gt 50){throw 'Incoming original event too stale or future dated.'}
            $hit|Add-Member -NotePropertyName SourceId -NotePropertyValue ($State.Run+'/'+($Sequence-1).ToString('D6')+'/'+$source.Name+'#'+$hit.Index)
            $hit|Add-Member -NotePropertyName SourceUtcMs -NotePropertyValue $sourceUtc
            $hit|Add-Member -NotePropertyName SourceClock -NotePropertyValue $sourceClock
            $hit|Add-Member -NotePropertyName CapturedUtcMs -NotePropertyValue $ObservedUtcMs
            $new.Add($hit);$damage+=$hit.AttributedDamage
        }
    }
    # No state is committed until every file, timestamp and effect validates.
    $State.LastSequence=$Sequence;$State.LastNativeClockMs=$NativeClockMs;$State.LastReceivedUtcMs=$ReceivedUtcMs;$State.LastManifest=$digest
    $State.Anchors.Add($anchors[-1]);while($State.Anchors.Count -gt 32){$State.Anchors.RemoveAt(0)}
    $State.Hits+=$new.Count;$State.OldHits+=$oldHits;$State.AttributedDamage+=$damage
    return @($new.ToArray()|Sort-Object GameMs,SourceId)
}

function New-GameplayIncomingState([string]$Directory){
    [pscustomobject]@{Enabled=$false;Probe=$null;EpochRoot='';Begin=$null;BeginSentUtcMs=0L;Terminal=$null;Reader=$null;PlayerGuid='';Identity=$null;Identities=@{};
        LastRotateUtcMs=0L;Rotation=0L;RotationSentUtcMs=0L;RotationPending=$false;Closed=[Collections.Generic.Queue[object]]::new();Audits=[Collections.Generic.Queue[object]]::new();
        HurtSequence=0L;HurtAck=0L;LastSourceUtcMs=0L;Pending=[Collections.Generic.List[object]]::new();Events=0L;UnsupportedEvents=0L;AttributedDamage=0.;MaxAdmissionAgeMs=0L;
        AppliedAck=0L;AppliedPending=0L;AppliedPendingSinceUtcMs=0L;AppliedLastSentUtcMs=0L;AppliedNativeClocks=@{};AppliedReceipts=[Collections.Generic.Queue[object]]::new();
        Receipts=[Collections.Generic.Queue[object]]::new();SourceFiles=[Collections.Generic.Queue[object]]::new();EvidenceFile=(Join-Path $Directory 'incoming-hurts.jsonl')}
}
function Get-GameplayIncomingHostState($State){
    $i=$State.Incoming
    [pscustomobject]@{Enabled=$i.Enabled;Begin=$i.Begin;Terminal=$i.Terminal;HurtSequence=$i.HurtSequence;HurtAck=$i.HurtAck;Pending=$i.Pending.Count;Events=$i.Events;
        AppliedAck=$i.AppliedAck;AppliedPending=$i.AppliedPending;AppliedReceipts=@($i.AppliedReceipts.ToArray());
        AttributedDamage=$i.AttributedDamage;UnsupportedEvents=$i.UnsupportedEvents;MaxAdmissionAgeMs=$i.MaxAdmissionAgeMs;Failure=$State.Failure;EvidenceFile=$i.EvidenceFile;EpochRoot=$i.EpochRoot;Receipts=@($i.Receipts.ToArray());SourceFiles=@($i.SourceFiles.ToArray());ClockAnchors=$(if($i.Reader){@($i.Reader.Anchors.ToArray())}else{@()});
        CleanupComplete=(-not $i.Enabled -or $i.BeginSentUtcMs -eq 0 -or ($i.Terminal -and $i.Terminal.cvars_restored -is [bool] -and $i.Terminal.cvars_restored -eq $true -and $i.Terminal.buff_restored -is [bool] -and $i.Terminal.buff_restored -eq $true -and $i.Terminal.health_restored -is [bool] -and $i.Terminal.health_restored -eq $true))}
}
function Accept-GameplayIncomingReceipt($State,$Receipt,[long]$Now){
    $i=$State.Incoming
    if(-not $i.Enabled -or -not(Test-GameplayCombatInteger $Receipt.schema 1 1) -or $Receipt.run -cne $State.Identity.Run){throw 'Incoming receipt identity differs.'}
    switch -CaseSensitive ($Receipt.event){
        'begin'{
            if($i.Begin -or $i.BeginSentUtcMs -eq 0 -or $Receipt.player_name -isnot [string] -or -not $Receipt.player_name -or $Receipt.player_name.Length -gt 160 -or
                -not(Test-GameplayCombatNumber $Receipt.native_maximum) -or $Receipt.native_maximum -le 0 -or $Receipt.native_maximum -gt 1000000 -or
                -not(Test-GameplayCombatNumber $Receipt.native_clock_ms) -or $Receipt.path -cne ($i.EpochRoot+'/000000/')){throw 'Incoming begin differs.'}
            $i.Reader=New-GameplayIncomingEpochReader $State.Identity.Run '' $Receipt.native_clock_ms $i.BeginSentUtcMs $Now $Receipt.player_name
            $i.Begin=$Receipt;$i.LastRotateUtcMs=$Now
        }
        'identity'{
            if(-not $i.Begin -or $Receipt.player_name -cne $i.Begin.player_name -or -not(Test-GameplayCombatInteger $Receipt.seq ($State.PublishedSequence+1) $State.Sequence) -or
                -not(Test-GameplayCombatNumber $Receipt.native_clock_ms) -or @($Receipt.actors).Count -gt 8){throw 'Incoming actor identity sample differs.'}
            $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$tokens=[Collections.Generic.HashSet[int]]::new()
            foreach($a in @($Receipt.actors)){
                Assert-GameplayCombatKeys $a @('token','name','first_seen_ms')
                if(-not(Test-GameplayCombatInteger $a.token 1 256) -or -not $tokens.Add([int]$a.token) -or $a.name -isnot [string] -or -not $a.name -or $a.name.Length -gt 160 -or
                    -not $names.Add($a.name) -or $a.name -ceq $i.Begin.player_name -or -not(Test-GameplayCombatNumber $a.first_seen_ms) -or $a.first_seen_ms -lt $i.Begin.native_clock_ms -or $a.first_seen_ms -gt $Receipt.native_clock_ms+1){throw 'Incoming actor generation invalid.'}
            }
            $i.Identity=$Receipt
        }
        'closed_segment'{
            if(-not $i.RotationPending -or -not(Test-GameplayCombatInteger $Receipt.sequence $i.Rotation $i.Rotation) -or
                $Receipt.closed_path -cne ($i.EpochRoot+'/'+($i.Rotation-1).ToString('D6')+'/') -or $Receipt.next_path -cne ($i.EpochRoot+'/'+$i.Rotation.ToString('D6')+'/') -or
                -not(Test-GameplayCombatNumber $Receipt.native_clock_ms) -or $i.Closed.Count -ge 4){throw 'Incoming closed directory receipt differs.'}
            $i.Closed.Enqueue([pscustomobject]@{Receipt=$Receipt;Sent=$i.RotationSentUtcMs;Received=$Now});$i.RotationPending=$false
        }
        'applied'{
            if(-not $i.Begin -or -not(Test-GameplayCombatInteger $Receipt.ack 1 $i.HurtAck) -or -not(Test-GameplayCombatNumber $Receipt.native_clock_ms) -or $Receipt.native_clock_ms -lt $i.Begin.native_clock_ms){throw 'Incoming applied receipt differs.'}
            $ack=[long]$Receipt.ack
            if($i.AppliedNativeClocks.ContainsKey($ack)){
                if($i.AppliedNativeClocks[$ack] -ne $Receipt.native_clock_ms){throw 'Incoming repeated applied ACK renewed its native timestamp.'}
                return
            }
            if($ack -ne $i.AppliedPending -or $ack -le $i.AppliedAck){throw 'Incoming applied ACK was not pending.'}
            $i.AppliedAck=$ack;$i.AppliedPending=0L;$i.AppliedNativeClocks[$ack]=$Receipt.native_clock_ms
            $i.AppliedReceipts.Enqueue([pscustomobject]@{ack=$ack;native_clock_ms=$Receipt.native_clock_ms;requested_utc_ms=$i.AppliedPendingSinceUtcMs;received_utc_ms=$Now})
            while($i.AppliedReceipts.Count -gt 32){$expired=$i.AppliedReceipts.Dequeue();$i.AppliedNativeClocks.Remove([long]$expired.ack)}
        }
        'terminal'{$i.Terminal=$Receipt;if(-not $State.Stopping){throw 'Native incoming stream stopped unexpectedly.'}}
        default{throw 'Unknown incoming receipt event.'}
    }
}
function Bind-GameplayIncomingActors($State,$Receipt){
    $i=$State.Incoming;if(-not $i.Enabled -or -not $i.Begin){return}
    if(-not $i.Identity -or $i.Identity.seq -ne $Receipt.seq){throw 'Native actor geometry lacks its matching identity generation.'}
    foreach($identity in @($i.Identity.actors)){
        $actor=@($State.Actors|Where-Object {$_.token -eq $identity.token})
        if($actor.Count -ne 1){throw 'Incoming identity has no exact actor geometry.'}
        $known=$i.Identities[[int]$identity.token]
        if($known){if($known.Name -cne $identity.name -or $known.FirstSeenMs -ne $identity.first_seen_ms){throw 'Incoming actor token generation changed.'};$known.Actor=$actor[0]}
        else{$i.Identities[[int]$identity.token]=[pscustomobject]@{Token=[int]$identity.token;Name=$identity.name;FirstSeenMs=$identity.first_seen_ms;Guid='';Actor=$actor[0]}}
    }
    $i.Identity=$null
}
function Read-GameplayIncomingClosedFiles([string]$Path){
    $files=[Collections.Generic.List[object]]::new()
    foreach($entry in @(Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop)){
        if($entry.Extension -cne '.json' -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $entry.Length -gt 1048576 -or $files.Count -ge 16){throw 'Incoming native directory contents invalid.'}
        $stream=[IO.FileStream]::new($entry.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try{$bytes=[byte[]]::new([int]$stream.Length);$stream.ReadExactly($bytes);$text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes);$doc=[Text.Json.JsonDocument]::Parse($text);$doc.Dispose()}finally{$stream.Dispose()}
        $files.Add([pscustomobject]@{Name=$entry.Name;Text=$text})
    }
    return $files.ToArray()
}
function Get-GameplayIncomingDamageKind($Hit){
    # Pinned official Libs/Tables/combat/combat_attack_type.xml supplies the
    # base melee pairs; combat_damage_type_mapping.xml supplies weapon overrides
    # stab0->smash4 and slash1->stab5. Unknown telemetry is never guessed ranged.
    if($Hit.CauseName -cne 'CombatHit'){return ''}
    if(($Hit.AttackType -eq 0 -and $Hit.DamageType -in @(4,5)) -or
       ($Hit.AttackType -eq 1 -and $Hit.DamageType -in @(5,6)) -or
       ($Hit.AttackType -in @(2,4,5,6,7,9) -and $Hit.DamageType -eq 4)){return 'melee'}
    return ''
}
function Update-GameplayIncomingEpochs($State,[long]$Now){
    $i=$State.Incoming
    while($i.Closed.Count){
        $closed=$i.Closed.Peek();if($Now-$closed.Received -lt 20){break}
        $r=$closed.Receipt
        # Recheck recent published directories as subsequent epochs close; a
        # native late write or same-cursor replacement must terminate the lease.
        foreach($audit in $i.Audits){
            $current=@(Read-GameplayIncomingClosedFiles $audit.Path)
            $fingerprint=Get-GameplayIncomingFilesFingerprint $current
            if($fingerprint -cne $audit.Fingerprint){throw 'Native writer changed an already consumed incoming epoch.'}
        }
        try{$files=@(Read-GameplayIncomingClosedFiles $r.closed_path)}catch{
            $base=$_.Exception.GetBaseException()
            if(($base -is [IO.IOException] -or $base -is [Text.Json.JsonException]) -and $Now-$closed.Received -lt 500){break};throw
        }
        $hits=@(Add-GameplayIncomingClosedEpoch $i.Reader $r.sequence $r.native_clock_ms $closed.Sent $closed.Received $Now $files)
        $i.Audits.Enqueue([pscustomobject]@{Path=$r.closed_path;Fingerprint=(Get-GameplayIncomingFilesFingerprint $files)})
        while($i.Audits.Count -gt 8){$null=$i.Audits.Dequeue()}
        foreach($file in $files){$i.SourceFiles.Enqueue([pscustomobject]@{epoch=($r.sequence-1).ToString('D6');file=$file.Name;hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($file.Text))).ToLowerInvariant()});while($i.SourceFiles.Count -gt 128){$null=$i.SourceFiles.Dequeue()}}
        foreach($hit in $hits){
            $kind=Get-GameplayIncomingDamageKind $hit
            if(-not $kind){$i.UnsupportedEvents++;continue}
            if($i.PlayerGuid -and $i.PlayerGuid -cne $hit.VictimGuid){throw 'Native player GUID changed within incoming lease.'}
            $matches=@($i.Identities.Values|Where-Object {$_.Name -ceq $hit.AttackerName -and $_.FirstSeenMs -le $hit.GameMs}|Sort-Object FirstSeenMs -Descending)
            if(-not $matches.Count -or ($matches.Count -gt 1 -and $matches[0].FirstSeenMs -eq $matches[1].FirstSeenMs)){throw 'Incoming attacker has no unique proven generation.'}
            $source=$matches[0]
            if($source.Guid -and $source.Guid -cne $hit.AttackerGuid){throw 'Native attacker GUID changed within its known generation.'}
            $damage=$hit.AttributedDamage/[double]$i.Begin.native_maximum*20.
            if($damage -lt .001 -or $damage -gt 1000 -or $i.Pending.Count -ge 32 -or $hit.SourceUtcMs -lt $i.LastSourceUtcMs){throw 'Incoming native damage/queue/source ordering invalid.'}
            $i.PlayerGuid=$hit.VictimGuid;$source.Guid=$hit.AttackerGuid;$i.HurtSequence++
            $i.LastSourceUtcMs=$hit.SourceUtcMs
            $hurt=[pscustomobject]@{seq=$i.HurtSequence;attacker_token=$source.Token;damage=$damage;kind=$kind;source_utc_ms=$hit.SourceUtcMs}
            $record=[pscustomobject]@{seq=$i.HurtSequence;source_utc_ms=$hit.SourceUtcMs;attacker_token=$source.Token;kind=$kind;damage_mc=$damage;maximum=$i.Begin.native_maximum;source=$hit}
            $i.Pending.Add([pscustomobject]@{Hurt=$hurt;Actor=$source.Actor;AdmittedUtcMs=$Now});$i.Events++;$i.AttributedDamage+=$hit.AttributedDamage;$i.MaxAdmissionAgeMs=[Math]::Max($i.MaxAdmissionAgeMs,$Now-$hit.SourceUtcMs)
            $i.Receipts.Enqueue($record);while($i.Receipts.Count -gt 64){$null=$i.Receipts.Dequeue()}
            [IO.File]::AppendAllText($i.EvidenceFile,($record|ConvertTo-Json -Depth 8 -Compress)+"`n",[Text.UTF8Encoding]::new($false))
        }
        $null=$i.Closed.Dequeue()
        # The next native sample publishes the queue under a NEW host sequence.
        # Publishing here would mutate an already published sample sequence.
    }
}
function Get-GameplayIncomingFilesFingerprint([object[]]$Files){
    return (@($Files|ForEach-Object {$_.Name+'='+[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_.Text))) }|Sort-Object) -join "`n")
}
function Get-GameplayIncomingCommands($State,[long]$Now){
    $i=$State.Incoming;if(-not $i.Enabled){return ''}
    if(-not $i.Begin){
        if($i.BeginSentUtcMs){if($Now-$i.BeginSentUtcMs -gt 1500){throw 'Incoming native begin unacknowledged.'};return ''}
        $i.BeginSentUtcMs=$Now;$path=($i.EpochRoot+'/000000/').Replace("'","\'")
        return "MineCome.GameplayCombatIncomingBegin('$($State.Identity.Run)','$path')"
    }
    Update-GameplayIncomingEpochs $State $Now
    if($i.Pending.Count -and $Now-$i.Pending[0].AdmittedUtcMs -gt 10000){throw 'Incoming Minecraft acknowledgement expired.'}
    if($i.RotationPending){if($Now-$i.RotationSentUtcMs -gt 1000){throw 'Incoming closed epoch unacknowledged.'};return ''}
    if($Now-$i.LastRotateUtcMs -lt 250){return ''}
    $i.Rotation++;if($i.Rotation -gt 999999){throw 'Incoming native epoch capacity exhausted.'}
    [void][IO.Directory]::CreateDirectory($i.EpochRoot+'/'+$i.Rotation.ToString('D6'))
    $i.RotationPending=$true;$i.RotationSentUtcMs=$Now;$i.LastRotateUtcMs=$Now
    return "MineCome.GameplayCombatIncomingRotate('$($State.Identity.Run)',$($i.Rotation))"
}
function Accept-GameplayIncomingAck($State,[long]$Ack){
    $i=$State.Incoming
    if($Ack -lt $i.HurtAck -or $Ack -gt $i.HurtSequence){throw 'Unknown or regressed native hurt acknowledgement.'}
    $i.HurtAck=$Ack
    for($n=$i.Pending.Count-1;$n -ge 0;$n--){if($i.Pending[$n].Hurt.seq -le $Ack){$i.Pending.RemoveAt($n)}}
}
function Get-GameplayIncomingAppliedCommand($State,[long]$Now){
    $i=$State.Incoming;if(-not $i.Enabled -or -not $i.Begin -or $State.Stopping){return ''}
    if($i.AppliedPending){
        if($Now-$i.AppliedPendingSinceUtcMs -gt 1000){throw 'Incoming applied notification unacknowledged.'}
        if($Now-$i.AppliedLastSentUtcMs -lt 75){return ''}
    }elseif($i.HurtAck -gt $i.AppliedAck){
        # ACKs come only from the existing current-process/world guest packet;
        # retain this cumulative ACK until native confirms the same notification.
        $i.AppliedPending=$i.HurtAck;$i.AppliedPendingSinceUtcMs=$Now
    }else{return ''}
    $i.AppliedLastSentUtcMs=$Now
    return "MineCome.GameplayCombatIncomingApplied('$($State.Identity.Run)',$($i.AppliedPending))"
}
