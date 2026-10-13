#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Owned official-tools relay lifecycle. Dot sourcing defines functions only.
# The caller retains New's session before Start and calls Stop in finally.
function Assert-MineComeHudStonePath([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    if($full.Contains('"')){throw 'Quoted relay paths are unsupported.'}
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked relay path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    $full
}
function Read-MineComeHudStoneText([string]$Path) {
    $null=Assert-MineComeHudStonePath $Path
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if($stream.Length -gt 2MB){throw 'Relay log exceeds its bounded extent.'}
        $reader=[IO.StreamReader]::new($stream)
        try{$reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Test-MineComeHudStoneRelayPreflight($Context) {
    Assert-MineComeProbeContext $Context
    if($Context.GameHash -ine 'a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a' -or (Get-FileHash -LiteralPath $Context.GamePath).Hash -ine $Context.GameHash){throw 'The exact tested official tools executable is required.'}
    if(Get-Process minecome_tools_host,minecome_host -ErrorAction SilentlyContinue){throw 'Another bridge relay is running; it was preserved.'}
    $deploymentPath=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot 'runtime/lua-deployment.json')
    $deployment=Get-Content -LiteralPath $deploymentPath -Raw | ConvertFrom-Json
    $mod=Assert-MineComeHudStonePath (Join-Path $Context.GameRoot 'Mods/minecome')
    $pak=Assert-MineComeHudStonePath (Join-Path $mod 'Data/minecome-diagnostics.pak');$manifest=Assert-MineComeHudStonePath (Join-Path $mod 'mod.manifest')
    if($deployment.ModPath -ine $mod -or (Get-FileHash -LiteralPath $pak).Hash -ine $deployment.PakHash -or (Get-FileHash -LiteralPath $manifest).Hash -ine $deployment.ManifestHash){throw 'Owned Lua/stone package differs from its deployment receipt.'}
    $native=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot 'build/native/kcd2/Release/minecome_tools_host.exe')
    if(-not(Test-Path -LiteralPath $native -PathType Leaf)){throw 'Build the official-tools relay first.'}
    Get-MineComeToolsConsoleBinding | Out-Null
    [pscustomobject]@{NativePath=$native;NativeHash=(Get-FileHash -LiteralPath $native).Hash.ToLowerInvariant();DeploymentPath=$deploymentPath;PakHash=$deployment.PakHash;ManifestHash=$deployment.ManifestHash}
}
function New-MineComeHudStoneRelay($Context,[string]$Directory,[string]$Run,[long]$ExpiresUtcMs,[ValidateRange(1,65535)][int]$Port=38765) {
    if($Run -cnotmatch '^[0-9a-f]{32}$'){throw 'Invalid HUD relay run.'}
    $directory=Assert-MineComeHudStonePath $Directory
    $root=Assert-MineComeHudStonePath (Join-Path $Context.ProjectRoot 'runtime/evidence')
    if(-not $directory.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $directory -PathType Container)){throw 'Relay evidence must use an existing owned HUD evidence directory.'}
    $relayHome=Join-Path $directory 'stone-relay'
    if(Test-Path -LiteralPath $relayHome){throw 'New relay home required; existing evidence preserved.'}
    [pscustomobject]@{
        Context=$Context;Directory=$directory;Run=$Run;ExpiresUtcMs=$ExpiresUtcMs;Port=$Port;Home=$relayHome
        TokenFile=(Join-Path $relayHome 'config/bridge.token');StopFile=(Join-Path $relayHome 'relay-stop.request')
        Stdout=(Join-Path $relayHome 'relay.log');Stderr=(Join-Path $relayHome 'relay-errors.log');Process=$null
        ProcessId=0;ProcessStart=$null;Preflight=$null;Probe=$null;StartAttempted=$false;StopAttempted=$false
        Ready=$false;CleanupVerified=$false;ExitObserved=$false;ExitCode=$null;EngineMirroringVerified=$false;TransportAuthVerified=$false
        Failure=$null;CleanupFailure=$null;GuestVerificationFailure=$null;LastIntentUtcMs=0L
        Intents=[Collections.Generic.List[object]]::new();Native=$null
    }
}
function ConvertFrom-MineComeHudStoneRelayLog([string]$Text) {
    if($Text.Length -gt 2MB){throw 'Relay text exceeds its bounded extent.'}
    $begins=[Collections.Generic.List[string]]::new();$ends=[Collections.Generic.List[string]]::new()
    $results=[Collections.Generic.List[object]]::new();$dispatches=[Collections.Generic.List[object]]::new();$events=[Collections.Generic.List[object]]::new();$acks=[Collections.Generic.List[object]]::new()
    $world=$false;$authenticated=$false;$summary=$null
    foreach($line in ($Text -split "`n" | Select-Object -SkipLast 1)){
        $line=$line.TrimEnd("`r")
        if($line -match '^STONE_BEGIN_ACK session=([1-9][0-9]{0,15})$'){$begins.Add($Matches[1])}
        elseif($line -match '^STONE_CLEANUP_ACK session=([1-9][0-9]{0,15})$'){$ends.Add($Matches[1])}
        elseif($line -match '^STONE_INPUT_DISPATCH request=([1-9][0-9]{0,15}) action=([12])$'){$dispatches.Add([pscustomobject]@{request_id=[long]$Matches[1];action=[int]$Matches[2]})}
        elseif($line -match '^STONE_INPUT_RESULT request=([1-9][0-9]{0,15}) action=([12]) result=([1-7])$'){$results.Add([pscustomobject]@{request_id=[long]$Matches[1];action=[int]$Matches[2];result=[int]$Matches[3]})}
        elseif($line -match '^STONE_ENGINE_ACK session=([1-9][0-9]{0,15}) sequence=([1-9][0-9]{0,15}) result=(spawned|already_present|removed|absent)$'){$acks.Add([pscustomobject]@{session=$Matches[1];sequence=$Matches[2];result=$Matches[3]})}
        elseif($line -match '^KCD2_LOG .*\[MineComeBlock\] (\{[^\r\n]*\})$'){
            $r=$Matches[1] | ConvertFrom-Json -Depth 8
            if($r.schema -eq 1 -and $r.result -cin @('spawned','already_present','removed','absent')){$events.Add($r)}
        }
        if($line -match '^KCD2_LOG .*\[MineComePose\] (\{[^\r\n]*\})$'){
            $r=$Matches[1] | ConvertFrom-Json -Depth 8
            if($r.schema -eq 1 -and $null -ne $r.player -and $null -ne $r.camera){$world=$true}
        }
        if($line -match '^KCD2_LOG .*\[MineComePing\] MC_CONNECTED_AUTHENTICATED$'){$authenticated=$true}
        if($line -match '^Stone engine acknowledgements: placed=([0-9]+) removed=([0-9]+) rejected=([0-9]+) cleanup_ack=(true|false; Lua lease remains responsible)$'){$summary=[pscustomobject]@{placed=[int]$Matches[1];removed=[int]$Matches[2];rejected=[int]$Matches[3];cleanup_ack=($Matches[4] -ceq 'true')}}
    }
    if($begins.Count -gt 16 -or $results.Count -gt 16 -or $dispatches.Count -gt 16 -or $events.Count -gt 16 -or $acks.Count -gt 16){throw 'Combined relay exceeded its sixteen-action evidence bound.'}
    [pscustomobject]@{begin_sessions=@($begins.ToArray());cleanup_sessions=@($ends.ToArray());dispatches=@($dispatches.ToArray());results=@($results.ToArray());events=@($events.ToArray());engine_acks=@($acks.ToArray());fresh_world=$world;authenticated=$authenticated;summary=$summary}
}
function Update-MineComeHudStoneRelayEvidence($Session) {
    if(Test-Path -LiteralPath $Session.Stdout){$Session.Native=ConvertFrom-MineComeHudStoneRelayLog (Read-MineComeHudStoneText $Session.Stdout)}
    $transportLog=Join-Path $Session.Home 'runtime/logs/tools-bridge.log'
    if(Test-Path -LiteralPath $transportLog){$Session.TransportAuthVerified=(Read-MineComeHudStoneText $transportLog) -match '(?m)^[0-9]+ HELLO authenticated; protocol 1\.1 session ready; peer role=minecraft\r?$'}
}
function Assert-MineComeHudStoneRelay($Session) {
    Assert-MineComeProbeContext $Session.Context
    if($Session.Failure -or -not $Session.Ready -or -not $Session.Process -or $Session.Process.HasExited -or [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $Session.ExpiresUtcMs){throw 'Owned HUD stone relay is unavailable or expired.'}
    if($Session.Process.Id -ne $Session.ProcessId -or $Session.Process.StartTime.ToUniversalTime() -ne $Session.ProcessStart){throw 'Owned relay process identity changed.'}
    if(-not [MineCome.Probes.TcpOwner]::OwnsLoopback($Session.Port,$Session.ProcessId)){throw 'Owned relay lost its exclusive loopback listener.'}
    Update-MineComeHudStoneRelayEvidence $Session
}
function Start-MineComeHudStoneRelay($Session) {
    if($Session.StartAttempted){throw 'HUD stone relay session already used.'}
    $Session.StartAttempted=$true
    try {
        $remaining=$Session.ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if($remaining -lt 45000 -or $remaining -gt 180000){throw 'HUD relay requires a fresh bounded 45–180 second deadline.'}
        $Session.Preflight=Test-MineComeHudStoneRelayPreflight $Session.Context
        [IO.Directory]::CreateDirectory((Join-Path $Session.Home 'config')) | Out-Null
        $token=[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
        [IO.File]::WriteAllText($Session.TokenFile,$token+"`n",[Text.UTF8Encoding]::new($false));$token=$null
        Copy-Item -LiteralPath $Session.Preflight.DeploymentPath -Destination (Join-Path $Session.Home 'lua-deployment.json')
        $Session.Probe=New-MineComeProbeRun $Session.Context 'hud-stone-source' (Join-Path $Session.Context.ProjectRoot 'kcd2/lua/data/scripts/mods/minecome.lua') 'BeginBlockSession'
        $tag=$Session.Run
        Invoke-MineComeProbeConsole $Session.Context ("#local s=MineCome._block_sink; local i=MineCome._interactive_input; System.LogAlways('[MineComeHudStoneContract] $tag '..tostring(not not (s and s.token_format=='decimal_text_v1' and i and i.input_format=='stone_action_v1' and i.commands_registered and type(MineCome.InteractiveIntent)=='function')))")
        Invoke-MineComeProbeConsole $Session.Context ("#System.LogAlways('[MineComeProbeFlush] $tag')")
        $deadline=[DateTime]::UtcNow.AddSeconds(2);$contract=$false
        do {
            $fresh=Read-MineComeProbeLog $Session.Context $Session.Probe.Offset
            $contract=$fresh -match ('\[MineComeHudStoneContract\] '+$tag+' true\r?\n')
            if($fresh -match ('\[MineComeHudStoneContract\] '+$tag+' false')){throw 'Current Lua token/input contract failed.'}
            if($contract){break};Start-Sleep -Milliseconds 50
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $contract){throw 'No fresh Lua token/input contract receipt.'}
        if((Get-FileHash -LiteralPath $Session.Preflight.NativePath).Hash -ine $Session.Preflight.NativeHash){throw 'Relay executable changed before launch.'}
        $arguments=@('--home',('"'+$Session.Home+'"'),'--game-log',('"'+$Session.Context.GameLog+'"'),'--stop-file',('"'+$Session.StopFile+'"'),'--fov-unit','radians','--seconds',[string][Math]::Min(180,[Math]::Ceiling(($Session.ExpiresUtcMs-[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())/1000)),'--port',[string]$Session.Port,'--interactive-stone')
        $Session.Process=Start-Process -FilePath $Session.Preflight.NativePath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $Session.Stdout -RedirectStandardError $Session.Stderr
        $null=$Session.Process.Handle;$Session.ProcessId=$Session.Process.Id;$Session.ProcessStart=$Session.Process.StartTime.ToUniversalTime()
        $deadline=[DateTime]::UtcNow.AddSeconds(10)
        do {
            Assert-MineComeProbeContext $Session.Context
            if($Session.Process.HasExited){throw 'Owned HUD stone relay exited before world readiness.'}
            Update-MineComeHudStoneRelayEvidence $Session
            $text=Read-MineComeHudStoneText $Session.Stdout
            if($text.Contains('Official tools console binding verified;') -and $Session.Native.fresh_world -and [MineCome.Probes.TcpOwner]::OwnsLoopback($Session.Port,$Session.ProcessId)){$Session.Ready=$true;break}
            Start-Sleep -Milliseconds 100
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $Session.Ready){throw 'No fresh engine player/camera receipt from the owned relay.'}
    }catch{$Session.Failure=$_.Exception.Message;throw}
}
function Send-MineComeHudStoneIntent($Session,[ValidateSet(1,2)][int]$Action,[scriptblock]$BeforeDispatch) {
    Assert-MineComeHudStoneRelay $Session
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($Session.Intents.Count -ge 16 -or $now-$Session.LastIntentUtcMs -lt 300){throw 'HUD stone intent capacity or spacing limit reached.'}
    # Physical callers recheck edge age and current foreground after relay health
    # checks. A normal admission decline owns no intent and never poisons a relay.
    if($BeforeDispatch){$decline=& $BeforeDispatch;if($decline){return [pscustomobject]@{accepted=$false;declined=$true;reason=[string]$decline}}}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $ordinal=$Session.Intents.Count+1;$offset=(Get-Item -LiteralPath $Session.Context.GameLog).Length
    $record=[pscustomobject]@{ordinal=$ordinal;request_id=0L;action=$Action;accepted=$false;sent_utc_ms=$now;failure=$null}
    $Session.Intents.Add($record);$Session.LastIntentUtcMs=$now
    try {
        Invoke-MineComeProbeConsole $Session.Context ("#local ok,id=MineCome.InteractiveIntent($Action); System.LogAlways('[MineComeHudStoneIntent] $($Session.Run) $ordinal $Action '..tostring(ok)..' '..tostring(id))")
        Invoke-MineComeProbeConsole $Session.Context ("#System.LogAlways('[MineComeProbeFlush] $($Session.Run)')")
        $deadline=[DateTime]::UtcNow.AddSeconds(2)
        do {
            $fresh=Read-MineComeProbeLog $Session.Context $offset
            $matches=[regex]::Matches($fresh,('\[MineComeHudStoneIntent\] '+$Session.Run+' '+$ordinal+' '+$Action+' (true|false) ([a-z_0-9]+)\r?\n'))
            if($matches.Count -gt 1){throw 'Ambiguous HUD stone intent receipt.'}
            if($matches.Count -eq 1){
                $m=$matches[0]
                if($m.Groups[1].Value -cne 'true' -or $m.Groups[2].Value -cnotmatch '^[1-9][0-9]{0,15}$'){throw 'Engine refused the bounded stone intent.'}
                $id=[long]$m.Groups[2].Value
                if($id -gt 9007199254740991 -or @($Session.Intents | Where-Object request_id -eq $id).Count){throw 'Invalid or repeated engine request ID.'}
                $record.request_id=$id;$record.accepted=$true;return $record
            }
            Start-Sleep -Milliseconds 50
        }while([DateTime]::UtcNow -lt $deadline)
        throw 'No fresh engine receipt for HUD stone intent; it will not be retried.'
    }catch{$record.failure=$_.Exception.Message;$Session.Failure=$_.Exception.Message;throw}
}
function Assert-MineComeHudStoneRelayGuest($Session,$Guest) {
    $Session.EngineMirroringVerified=$false
    try {
        function Flag($Value,[bool]$Expected){if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Relay/guest Boolean receipt invalid.'}}
        function Integer($Value){if($Value -isnot [int] -and $Value -isnot [long]){throw 'Relay/guest integer receipt invalid.'}}
        Update-MineComeHudStoneRelayEvidence $Session
        $native=$Session.Native;$proof=$Guest.lab_evidence.stone_bridge
        if($Session.Failure -or $Guest.result -cne 'input_completed'){throw 'Only a completed live guest run can verify engine mirroring.'}
        foreach($field in @('ui_input_stone_bridge','ui_input_stone_live','ui_input_live_mouse','ui_input_offscreen_presentation')){Flag $Guest.$field $true}
        foreach($field in @('ui_input_stone_fixture','ui_input_fixture','ui_input_pointer_fixture','ui_input_delay_fixture','ui_input_background_trial','ui_input_offscreen_trial')){Flag $Guest.$field $false}
        foreach($field in @('failed','pending','inventory_mutated','camera_mutated')){Flag $proof.$field $false}
        foreach($field in @('closed','vanilla_dispatch_inventory_unchanged')){Flag $proof.$field $true}
        foreach($field in @('cancelled_pending','request_count','omitted_requests','omitted_confirmations','confirmed_actions','block_events_queued')){Integer $proof.$field}
        if($Guest.run -cne $Session.Run -or $proof.kind -cne 'minecome_hud_stone_bridge_v1' -or $proof.save -cne $Guest.save -or $proof.failed -ne $false -or $proof.closed -ne $true -or $proof.pending -ne $false -or $proof.cancelled_pending -ne 0 -or $proof.vanilla_dispatch_inventory_unchanged -ne $true -or $proof.inventory_mutated -ne $false -or $proof.camera_mutated -ne $false){throw 'Combined guest ownership/action completion proof is invalid.'}
        if(-not $Session.ExitObserved -or $Session.ExitCode -ne 0 -or -not $Session.CleanupVerified -or -not $Session.TransportAuthVerified -or -not $native.fresh_world){throw 'Native relay shutdown, authentication, world or cleanup proof missing.'}
        $requests=@($proof.requests);$confirmations=@($proof.confirmations);$intents=@($Session.Intents.ToArray())
        if($intents.Count -lt 1 -or $requests.Count -ne $intents.Count -or $native.results.Count -ne $requests.Count -or $native.dispatches.Count -ne $requests.Count -or $proof.request_count -ne $requests.Count -or $proof.omitted_requests -ne 0 -or $proof.omitted_confirmations -ne 0){throw 'Relay/guest request count mismatch.'}
        for($i=0;$i -lt $requests.Count;$i++){
            $r=$requests[$i];$intent=$intents[$i];$dispatch=$native.dispatches[$i];$result=$native.results[$i]
            foreach($field in @('id','action','result')){Integer $r.$field};Flag $r.result_queued $true
            if($r.id -lt 1 -or $r.id -gt 9007199254740991 -or $r.action -notin @(1,2) -or $r.result -lt 1 -or $r.result -gt 7){throw 'Guest stone request fields exceed protocol bounds.'}
            if(-not $intent.accepted -or $r.id -ne $intent.request_id -or $r.action -ne $intent.action -or $r.result_queued -ne $true -or $dispatch.request_id -ne $r.id -or $dispatch.action -ne $r.action -or $result.request_id -ne $r.id -or $result.action -ne $r.action -or $result.result -ne $r.result){throw 'Relay intent/dispatch/result does not match the same guest request.'}
        }
        $accepted=@($requests | Where-Object result -eq 1)
        if($accepted.Count -lt 1 -or $confirmations.Count -ne $accepted.Count -or $native.engine_acks.Count -ne $accepted.Count -or $native.events.Count -ne $accepted.Count -or $proof.confirmed_actions -ne $accepted.Count -or $proof.block_events_queued -ne $accepted.Count){throw 'Relay engine event count differs from actual guest confirmations.'}
        for($i=0;$i -lt $accepted.Count;$i++){
            $r=$accepted[$i];$c=$confirmations[$i];$e=$native.events[$i];$ack=$native.engine_acks[$i]
            foreach($field in @('id','action','server_age_ms')){Integer $c.$field};Flag $c.client_and_server $true;Flag $c.inventory_mutated $false
            foreach($field in @('schema','session','sequence','operation')){Integer $e.$field};Flag $e.physics $false;Flag $e.live_draw_verified $false
            if($c.id -ne $r.id -or $c.action -ne $r.action -or $c.client_and_server -ne $true -or $c.inventory_mutated -ne $false -or $c.server_age_ms -lt 0 -or $c.server_age_ms -gt 250 -or $e.operation -ne $c.action -or [string]$e.session -cne $ack.session -or [string]$e.sequence -cne $ack.sequence -or $e.result -cne $ack.result -or $e.result -cne $(if($c.action -eq 1){'spawned'}else{'removed'}) -or $e.physics -ne $false -or $e.live_draw_verified -ne $false){throw 'KCD engine receipt does not match the confirmed vanilla operation.'}
            foreach($axis in @('x','y','z')){Integer $e.mc.$axis;Integer $proof.target.$axis;if($e.mc.$axis -ne $proof.target.$axis){throw 'KCD engine receipt used another Minecraft cell.'}}
            if($native.begin_sessions -cnotcontains $ack.session -or $native.cleanup_sessions -cnotcontains $ack.session){throw 'KCD event session lacks begin or cleanup acknowledgement.'}
        }
        if(-not $native.summary -or $native.summary.rejected -ne 0 -or ($native.summary.placed+$native.summary.removed) -ne $accepted.Count){throw 'Native engine summary does not account for guest operations.'}
        $Session.EngineMirroringVerified=$true
    }catch{$Session.GuestVerificationFailure=$_.Exception.Message;throw}
    finally {
        if(Test-Path -LiteralPath $Session.Home){Get-MineComeHudStoneRelayEvidence $Session | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $Session.Home 'relay-result.json') -Encoding utf8NoBOM}
    }
}
function Get-MineComeHudStoneRelayEvidence($Session) {
    Update-MineComeHudStoneRelayEvidence $Session
    [ordered]@{
        schema=1;kind='minecome_hud_stone_relay_v1';run=$Session.Run;home=$Session.Home;port=$Session.Port
        game_pid=$Session.Context.GamePid;game_start_utc=$Session.Context.GameStartedUtc;game_hash=$Session.Context.GameHash
        relay_pid=$Session.ProcessId;relay_start_utc=$Session.ProcessStart;expires_utc_ms=$Session.ExpiresUtcMs
        native_hash=$(if($Session.Preflight){$Session.Preflight.NativeHash}else{$null});lua_probe=$Session.Probe
        package_hash=$(if($Session.Preflight){$Session.Preflight.PakHash}else{$null});manifest_hash=$(if($Session.Preflight){$Session.Preflight.ManifestHash}else{$null})
        ready=$Session.Ready;exit_observed=$Session.ExitObserved;exit_code=$Session.ExitCode;cleanup_verified=$Session.CleanupVerified
        engine_mirroring_verified=$Session.EngineMirroringVerified;transport_auth_verified=$Session.TransportAuthVerified;visual_verified=$false;physical_block_input_verified=$false
        intents=@($Session.Intents.ToArray());native=$Session.Native;failure=$Session.Failure;cleanup_failure=$Session.CleanupFailure;guest_verification_failure=$Session.GuestVerificationFailure
        kcd_launched=$false;kcd_stopped=$false;other_processes_stopped=$false;credentials_recorded=$false
    }
}
function Stop-MineComeHudStoneRelay($Session) {
    if($Session.StopAttempted){return};$Session.StopAttempted=$true
    try {
        if($Session.Process){
            if(-not $Session.Process.HasExited){[IO.File]::WriteAllText($Session.StopFile,'Graceful stop requested by owning HUD controller.');$null=$Session.Process.WaitForExit(5000)}
            $Session.ExitObserved=$Session.Process.HasExited
            if($Session.ExitObserved){$Session.ExitCode=$Session.Process.ExitCode}else{throw 'Owned relay did not exit within cleanup deadline; bounded process preserved.'}
            Update-MineComeHudStoneRelayEvidence $Session
            $native=$Session.Native
            if(-not $native -or -not $native.summary -or -not $native.summary.cleanup_ack){throw 'Native relay did not acknowledge final engine cleanup.'}
            foreach($id in $native.begin_sessions){if($native.cleanup_sessions -cnotcontains $id){throw 'Native relay lacks cleanup for an acknowledged engine session.'}}
            $Session.CleanupVerified=$true
            if($native.begin_sessions.Count -gt 0 -and $Session.ExitCode -ne 0){throw 'Active relay session exited unsuccessfully.'}
        }
    }catch{$Session.CleanupFailure=$_.Exception.Message;if(-not $Session.Failure){$Session.Failure=$Session.CleanupFailure}}
    finally {
        if(Test-Path -LiteralPath $Session.Home){
            Get-MineComeHudStoneRelayEvidence $Session | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $Session.Home 'relay-result.json') -Encoding utf8NoBOM
        }
    }
}
