#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Pure receipt/lifecycle regression. No game, HTTP request or input generation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudAimedRelay.ps1')
$script:checks=0
function Check($Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Body,[string]$Message){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed $Message}
function Clone($Value){$Value|ConvertTo-Json -Depth 32|ConvertFrom-Json -Depth 32}
$run='0123456789abcdef0123456789abcdef'
$save='MineCome-HudStream-01234567-89ab-cdef-0123-456789abcdef'
function Valid-Stone {
    $anchor=[ordered]@{x=10.5;y=65.62;z=20.5};$hostAnchor=[ordered]@{x=100;y=200;z=51.7};$seed=[ordered]@{x=12;y=64;z=20}
    $baseline=[ordered]@{client_eye=$anchor;server_eye=$anchor;seed=$seed;seed_air=$true;support_solid_up=$true;selected_slot=0;selected_count=64;selected_item='minecraft:stone';observation_age_ns=1000}
    Clone ([ordered]@{
        schema=1;kind='minecome_hud_aimed_stone_bridge_v1';protocol_minor=2;save=$save;session=1;world=1;reset=1
        baseline_confirmed=$true;arena_acknowledged=$true;bootstrap_confirmed=$true;closed=$true;failed=$false;pending=$false;cancelled_pending=0
        inventory_mutated=$false;camera_mutated=$false;engine_mirroring_verified=$false;visual_verified=$false
        arena_offer=@{arenaId=1;minecraftAnchor=$anchor;kcdAnchor=$hostAnchor;blocksPerUnit=1;seed=$seed;minimum=@{x=10;y=62;z=18};maximum=@{x=14;y=66;z=22}}
        initial_baseline=$baseline;pre_bootstrap_baseline=$baseline
        request_count=1;confirmed_actions=2;confirmed_network_actions=1;confirmed_places=1;confirmed_breaks=1;block_events_queued=2;owned_count=0;guest_world_cleanup_complete=$true
        requests=@(@{wire=@{arenaId=1;requestId=2;permitId=7;action=2;origin=$hostAnchor;direction=@{x=1;y=0;z=0};range=4.5;occlusion=1;nearestDistance=0};session=1;world=1;reset=1;component_request_id=2;result=1;result_queued=$true;client_and_server=$true;actions_enabled=$true;vanilla_queued=$true;captured_age_ns=1000})
        confirmations=@(@{component_request_id=1;wire_request_id=0;action=1;bootstrap=$true;client_and_server=$true;block_event_queued=$true;target=$seed;hit_block=@{x=12;y=63;z=20}},@{component_request_id=2;wire_request_id=2;action=2;bootstrap=$false;client_and_server=$true;block_event_queued=$true;target=$seed;hit_block=$seed})
        arena=@{owned_count=0;owned_cells=@();alignment=@{minecraft_anchor=$anchor;host_anchor=$hostAnchor;blocks_per_host_unit=1}}
    })
}
function Valid-Guest {
    Clone ([ordered]@{
        run=$run;save=$save;result='input_completed';ui_input_aimed_stone_bridge=$true;ui_input_stone_bridge=$true;ui_input_stone_live=$true;ui_input_live_mouse=$true;ui_input_offscreen_presentation=$true
        ui_input_stone_fixture=$false;ui_input_fixture=$false;ui_input_pointer_fixture=$false;ui_input_delay_fixture=$false;ui_input_background_trial=$false;ui_input_offscreen_trial=$false
        lab_evidence=@{aimed_stone_bridge=$true;live_mouse=$true;host_armed=$true;input_fixture=$false;input_events_applied=0;input_consumed_sequence=0;stone_bridge=(Valid-Stone)}
    })
}
function Valid-Log {
    $lines=@(
        'KCD2_LOG prefix [MineComePose] {"schema":1,"player":{"x":100,"y":200,"z":50},"camera":{"x":100,"y":200,"z":51.7}}',
        'STONE_BEGIN_ACK session=100',
        'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":100,"sequence":5,"operation":1,"mc":{"x":12,"y":64,"z":20},"position":{"x":101.5,"y":200.5,"z":50.08},"result":"spawned","physics":false,"live_draw_verified":false}',
        'STONE_ENGINE_ACK session=100 sequence=5 result=spawned',
        ('KCD2_LOG prefix [MineComeAimSession] {"schema":1,"run":"'+$run+'","arena":"1","event":"begin","result":"accepted","engine_time":1,"expires_engine_time":61}'),
        "AIM_INPUT_BEGIN_ACK run=$run arena=1",
        ('KCD2_LOG prefix [MineComeAimPermit] {"schema":1,"run":"'+$run+'","arena":"1","permit":"7","result":"installed","engine_time":2,"expires_engine_time":2.5}'),
        "AIM_PERMIT_READY run=$run arena=1 permit=7 installed_utc_ms=1000",
        ('KCD2_LOG prefix [MineComeAimInput] {"schema":1,"run":"'+$run+'","arena":"1","request":"2","permit":"7","click":"2","action":2,"result":"sampled","reason":"none","permit_engine_time":2,"engine_time":2.1,"completed_engine_time":2.11,"origin":{"x":100,"y":200,"z":51.7},"direction":{"x":1,"y":0,"z":0},"range":4.5,"occlusion":1,"nearest_distance":0}'),
        "AIM_INPUT_DISPATCH run=$run arena=1 request=2 permit=7 click=2 action=2",
        'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":100,"sequence":9,"operation":2,"mc":{"x":12,"y":64,"z":20},"position":null,"result":"removed","physics":false,"live_draw_verified":false}',
        'STONE_ENGINE_ACK session=100 sequence=9 result=removed',
        "AIM_INPUT_RESULT run=$run arena=1 request=2 action=2 result=1",
        "AIM_INPUT_CANCEL run=$run arena=1 authority_revoked=true sent_requests_recallable=false",
        ('KCD2_LOG prefix [MineComeAimSession] {"schema":1,"run":"'+$run+'","arena":"1","event":"end","result":"ended","engine_time":3,"expires_engine_time":null}'),
        "AIM_INPUT_END_ACK run=$run arena=1",
        'STONE_CLEANUP_ACK session=100',
        'Stone engine acknowledgements: placed=1 removed=1 rejected=0 cleanup_ack=true'
    )
    ($lines -join "`n")+"`n"
}
function Valid-Audit {
    "100 HELLO authenticated; protocol 1.2 session ready; peer role=minecraft`n101 AIM_ARENA_ACK arena=1 connection=1 reset=1`n110 AIM_REQUEST arena=1 request=2 permit=7`n120 AIM_RESULT arena=1 request=2 result=1`n130 session ended: graceful peer goodbye`n"
}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $project ('runtime/evidence/aimed-hud-relay-tests-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($root)|Out-Null
$context=[pscustomobject]@{ProjectRoot=$project;GamePid=42;GameStartedUtc=[DateTime]'2026-10-13T00:00:00Z';GameHash=('a'*64)}
function New-Case {
    $directory=Join-Path $root ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($directory)|Out-Null
    $session=New-MineComeHudAimedRelay $context $directory $run ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000)
    [IO.Directory]::CreateDirectory((Join-Path $session.Home 'runtime/logs'))|Out-Null
    [IO.File]::WriteAllText($session.Stdout,(Valid-Log));[IO.File]::WriteAllText((Join-Path $session.Home 'runtime/logs/tools-bridge.log'),(Valid-Audit))
    $session.Process=[pscustomobject]@{HasExited=$false;ExitCode=0;WaitCalls=0;WillExit=$true}
    $session.Process|Add-Member ScriptMethod WaitForExit {param($ms);$this.WaitCalls++;$this.HasExited=$this.WillExit;return $this.HasExited}
    $session.Ready=$true
    $session.Intents.Add([pscustomobject]@{ordinal=1;request_id=2;sequence=2;arena_id=1;permit_id=7;action=2;edge_utc_ms=1050L;installed_utc_ms=1000L;sent_utc_ms=1100L;accepted=$true;failure=$null})
    $session
}
$stone=Valid-Stone;Assert-MineComeHudAimedBridgeProof $stone;Check $true 'Valid isolated adapter proof accepted'
$refused=Valid-Stone
$refused.requests[0].result=3;$refused.requests[0].client_and_server=$false;$refused.requests[0].captured_age_ns=600000000L
$refused.requests[0].component_request_id=0;$refused.requests[0].vanilla_queued=$false
$refused.confirmations=@($refused.confirmations[0]);$refused.confirmed_actions=1;$refused.confirmed_network_actions=0;$refused.confirmed_breaks=0;$refused.block_events_queued=1
$refused.owned_count=1;$refused.guest_world_cleanup_complete=$false;$refused.arena.owned_count=1;$refused.arena.owned_cells=@($refused.arena_offer.seed)
Assert-MineComeHudAimedBridgeProof $refused;Check $true 'Legitimate stale refusal records old ray and retained guest stone truthfully'
foreach($case in @('legacy','false_server','wrong_world','wrong_reset','wrong_arena','same_permit','bad_component','bad_bootstrap','bad_owned','fraction_cell','outside','bad_balance','bad_alignment','bad_baseline','stale_baseline','stale_ray','bad_ray','pending','claimed_visual','unmatched_result','no_result','bad_count','oversized_id')){
    $s=Valid-Stone
    switch($case){
        'legacy'{$s.protocol_minor=1};'false_server'{$s.requests[0].client_and_server=$false};'wrong_world'{$s.requests[0].world=2};'wrong_reset'{$s.requests[0].reset=2};'wrong_arena'{$s.requests[0].wire.arenaId=2}
        'same_permit'{$s.requests+=Clone $s.requests[0];$s.requests[1].wire.requestId=3;$s.request_count=2};'bad_component'{$s.confirmations[1].component_request_id=1};'bad_bootstrap'{$s.confirmations[0].target.x=11}
        'bad_owned'{$s.arena.owned_cells=@(@{x=12;y=64;z=20})};'fraction_cell'{$s.confirmations[1].target.x=12.5};'outside'{$s.confirmations[1].target.x=99};'bad_balance'{$s.owned_count=1}
        'bad_alignment'{$s.arena.alignment.host_anchor.x=101};'bad_baseline'{$s.initial_baseline.selected_item='minecraft:dirt'};'stale_baseline'{$s.initial_baseline.observation_age_ns=500000001};'stale_ray'{$s.requests[0].captured_age_ns=500000001}
        'bad_ray'{$s.requests[0].wire.direction.x=0};'pending'{$s.pending=$true};'claimed_visual'{$s.visual_verified=$true};'unmatched_result'{$s.requests[0].result=3;$s.requests[0].client_and_server=$false};'no_result'{$s.requests[0].result_queued=$false};'bad_count'{$s.confirmed_actions=1};'oversized_id'{$s.requests[0].wire.permitId=9007199254740992L}
    }
    Reject {Assert-MineComeHudAimedBridgeProof $s} "Reject malformed component proof: $case"
}
$native=ConvertFrom-MineComeHudAimedRelayLog (Valid-Log) $run -Completed
Check ($native.captures.Count -eq 1 -and $native.permits.Count -eq 1 -and $native.engine_acks.Count -eq 2 -and $native.input_ends.Count -eq 1) 'Strict native receipts retained separately'
$audit=ConvertFrom-MineComeHudAimedAudit (Valid-Audit) -Completed
Check ($audit.authenticated -and $audit.requests.Count -eq 1 -and $audit.results.Count -eq 1 -and $audit.ended) 'Canonical wire audit authenticated and complete'
foreach($case in @('minor','harness','twice','noanchor','partial','wrongarena','replay','missingresult','postend','badcode','backwards')){
    $text=Valid-Audit
    switch($case){
        'minor'{$text=$text.Replace('protocol 1.2','protocol 1.1')};'harness'{$text=$text.Replace('role=minecraft','role=harness')};'twice'{$text=$text.Replace('101 AIM_ARENA_ACK',"100 HELLO authenticated; protocol 1.2 session ready; peer role=minecraft`n101 AIM_ARENA_ACK")}
        'noanchor'{$text=$text -replace '(?m)^101 .*\n',''};'partial'{$text=$text.TrimEnd("`n")};'wrongarena'{$text=$text.Replace('AIM_REQUEST arena=1','AIM_REQUEST arena=2')};'replay'{$text=$text.Replace('130 session',"121 AIM_REQUEST arena=1 request=2 permit=8`n130 session")}
        'missingresult'{$text=$text -replace '(?m)^120 .*\n',''};'postend'{$text+="140 AIM_REQUEST arena=1 request=3 permit=8`n"};'badcode'{$text=$text.Replace('result=1','result=11')};'backwards'{$text=$text.Replace('120 AIM_RESULT','109 AIM_RESULT')}
    }
    Reject {ConvertFrom-MineComeHudAimedAudit $text -Completed} "Reject bad canonical audit: $case"
}
Reject {ConvertFrom-MineComeHudAimedRelayLog ((Valid-Log).Replace('"request":"2"','"request":"2","request":"2"')) $run -Completed} 'Duplicate JSON keys rejected'
Reject {ConvertFrom-MineComeHudAimedRelayLog ((Valid-Log).Replace('permit=7 installed','permit=9007199254740992 installed')) $run -Completed} 'Oversized permit rejected'
Reject {ConvertFrom-MineComeHudAimedRelayLog ((Valid-Log).Replace("AIM_INPUT_RESULT run=$run",('AIM_INPUT_RESULT run='+('f'*32)))) $run -Completed} 'Wrong native run rejected'
Reject {ConvertFrom-MineComeHudAimedRelayLog ((Valid-Log).TrimEnd("`n")) $run -Completed} 'Completed partial native line rejected'
$s=New-Case;Stop-MineComeHudAimedRelay $s;Assert-MineComeHudAimedRelayGuest $s (Valid-Guest)
Check ($s.CleanupVerified -and $s.InputCleanupVerified -and $s.EngineMirroringVerified -and $s.GuestWorldCleanupComplete) 'Engine cleanup, independent input end and real guest proof correlated'
Stop-MineComeHudAimedRelay $s;Check ($s.Process.WaitCalls -eq 1) 'Stop remains idempotent'
foreach($case in @('missing_input_end','missing_cleanup','missing_lua_permit','missing_lua_end','wrong_lua_begin','renewed_permit','expired_capture','numeric_lua_token','wrong_permit','late_permit','bad_ray','wrong_position','wrong_cell','wrong_action','no_native_result','bad_audit_result','bad_count','same_ms','stale_edge','invented_permit','wrong_run','bootstrap_only','wrong_polled','unavailable_capture')){
    $s=New-Case;$g=Valid-Guest;$text=Valid-Log;$journal=Valid-Audit
    switch($case){
        'missing_input_end'{$text=$text -replace '(?m)^AIM_INPUT_END_ACK.*\n',''};'missing_cleanup'{$text=$text -replace '(?m)^STONE_CLEANUP_ACK.*\n',''};'missing_lua_permit'{$text=$text -replace '(?m)^KCD2_LOG.*\[MineComeAimPermit\].*\n',''}
        'missing_lua_end'{$text=$text -replace '(?m)^KCD2_LOG.*"event":"end".*\n',''};'wrong_lua_begin'{$text=$text.Replace('"event":"begin"','"event":"end"')};'renewed_permit'{$text=$text.Replace('"permit_engine_time":2','"permit_engine_time":2.05')};'expired_capture'{$text=$text.Replace('"completed_engine_time":2.11','"completed_engine_time":2.6')};'numeric_lua_token'{$text=$text.Replace('"request":"2"','"request":2')}
        'wrong_permit'{$g.lab_evidence.stone_bridge.requests[0].wire.permitId=8};'late_permit'{$text=$text.Replace('installed_utc_ms=1000','installed_utc_ms=1100')};'bad_ray'{$text=$text.Replace('"direction":{"x":1','"direction":{"x":0.5')}
        'wrong_position'{$text=$text.Replace('"x":101.5','"x":104.5')};'wrong_cell'{$text=$text.Replace('"mc":{"x":12','"mc":{"x":13')};'wrong_action'{$text=$text.Replace('click=2 action=2','click=2 action=1')}
        'no_native_result'{$journal=$journal -replace '(?m)^120 .*\n',''};'bad_audit_result'{$journal=$journal.Replace('result=1','result=3')};'bad_count'{$text=$text.Replace('placed=1 removed=1','placed=2 removed=1')}
        'same_ms'{$s.Intents[0].edge_utc_ms=1000L};'stale_edge'{$s.Intents[0].sent_utc_ms=1400L};'invented_permit'{$s.Intents[0].permit_id=8};'wrong_run'{$g.run='f'*32};'bootstrap_only'{$g.lab_evidence.stone_bridge.confirmed_network_actions=0};'wrong_polled'{$text=$text.Replace('request=2 action=2 result=1','request=2 action=2 result=3')};'unavailable_capture'{$text=$text.Replace('"result":"sampled"','"result":"unavailable"')}
    }
    [IO.File]::WriteAllText($s.Stdout,$text);[IO.File]::WriteAllText((Join-Path $s.Home 'runtime/logs/tools-bridge.log'),$journal)
    Stop-MineComeHudAimedRelay $s
    Reject {Assert-MineComeHudAimedRelayGuest $s $g} "Reject mismatched live chain: $case"
}
# Failed shutdown preserves the owned bounded process; no broad Stop-Process.
$s=New-Case;$s.Process.WillExit=$false;Stop-MineComeHudAimedRelay $s
Check (-not $s.ExitObserved -and $s.CleanupFailure -and -not $s.Process.HasExited) 'Unresponsive relay preserved with failed cleanup evidence'
# A physical edge must not replay the entire growing journal before dispatch.
# Mock external process/HTTP checks only; retain the production Send fast path.
$assertDefinition=${function:Assert-MineComeHudAimedRelay}
Check (-not $assertDefinition.ToString().Contains('Update-MineComeHudAimedRelayEvidence')) 'Live process assertion does not reparse historical JSON'
function Assert-MineComeHudAimedRelay($Session){}
function Invoke-MineComeProbeConsole($Context,[string]$Command){$script:lastSent=$Command}
$parserDefinition=${function:ConvertFrom-MineComeHudAimedRelayLog}
function ConvertFrom-MineComeHudAimedRelayLog {throw 'Historical parser must not run on live edge.'}
$s=New-Case;$s.Intents.Clear()
$pose='KCD2_LOG prefix [MineComePose] {"schema":1,"player":{"x":100,"y":200,"z":50},"camera":{"x":100,"y":200,"z":51.7}}'
$largeText=(($pose+"`n")*1600)+((('KCD2_LOG prefix [MineComeAimPermit] {"schema":1,"run":"'+$run+'","arena":"1","permit":"1","result":"installed","engine_time":1,"expires_engine_time":1.5}')+"`n")*600)
foreach($attempt in 1..3){
    $s.Intents.Clear();$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$install=$now-20;$edge=$now-10
    [IO.File]::WriteAllText($s.Stdout,($largeText+"AIM_PERMIT_READY run=$run arena=1 permit=7 installed_utc_ms=$install`n"))
    $click=[pscustomobject]@{sequence=2;action=2;utc_ms=$edge}
    $selection=[pscustomobject]@{accepted=$true;run=$run;arena='1';permit='7';sequence=2;action=2;edge_utc_ms=$edge;installed_utc_ms=$install;command="#MineCome.AimedIntent('$run','1','7','2',2)"}
    $watch=[Diagnostics.Stopwatch]::StartNew();$receipt=Send-MineComeHudAimedIntent $s $selection $click;$watch.Stop()
    Check ($receipt.accepted -and $script:lastSent -ceq $selection.command) 'Bounded original permit dispatch avoids cumulative JSON parser'
    $fastMs=$watch.Elapsed.TotalMilliseconds
}
${function:Assert-MineComeHudAimedRelay}=$assertDefinition
${function:ConvertFrom-MineComeHudAimedRelayLog}=$parserDefinition
Write-Output ("AIMED_HUD_RELAY_FAST_PATH journal_bytes={0} warmed_ms={1:F2}" -f $largeText.Length,$fastMs)
Write-Output "AIMED_HUD_RELAY_TESTS_PASS checks=$script:checks"
