#Requires -Version 7.3
# Production relay parsing, guest correlation and stop lifecycle; no game access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudStoneRelay.ps1')
$script:checks=0
function Check($Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Body,[string]$Message){$failed=$false;try{& $Body}catch{$failed=$true};Check $failed $Message}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot=Join-Path $project ('runtime/evidence/hud-stone-relay-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot)|Out-Null
$context=[pscustomobject]@{ProjectRoot=$project;GamePid=42;GameStartedUtc=[DateTime]'2026-10-13T00:00:00Z';GameHash=('a'*64)}
$run='b'*32
function New-Case {
    $directory=Join-Path $testRoot ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($directory)|Out-Null
    $s=New-MineComeHudStoneRelay $context $directory $run ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000)
    [IO.Directory]::CreateDirectory($s.Home)|Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $s.Home 'runtime/logs'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $s.Home 'runtime/logs/tools-bridge.log'),(Valid-Audit))
    $s.Process=[pscustomobject]@{HasExited=$false;ExitCode=0;WaitCalls=0;WillExit=$true}
    $s.Process | Add-Member ScriptMethod WaitForExit {param($ms);$this.WaitCalls++;$this.HasExited=$this.WillExit;return $this.HasExited}
    $s.Ready=$true
    $s.Intents.Add([pscustomobject]@{ordinal=1;request_id=7L;action=1;accepted=$true;sent_utc_ms=1L;failure=$null})
    $s.Intents.Add([pscustomobject]@{ordinal=2;request_id=8L;action=2;accepted=$true;sent_utc_ms=1001L;failure=$null})
    $s
}
function Valid-Log {
    $lines=@(
        'Official tools console binding verified; waiting for fresh in-game diagnostic log receipt',
        'KCD2_LOG prefix [MineComePose] {"schema":1,"player":{"x":1,"y":2,"z":3},"camera":{"x":1,"y":2,"z":4}}',
        'KCD2_LOG prefix [MineComePing] MC_CONNECTED_AUTHENTICATED',
        'STONE_INPUT_DISPATCH request=7 action=1',
        'STONE_INPUT_RESULT request=7 action=1 result=1',
        'STONE_BEGIN_ACK session=1790000000000000',
        'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":1790000000000000,"sequence":10,"operation":1,"mc":{"x":-8,"y":-60,"z":2},"position":{"x":1,"y":2,"z":3},"result":"spawned","physics":false,"live_draw_verified":false}',
        'STONE_ENGINE_ACK session=1790000000000000 sequence=10 result=spawned',
        'STONE_INPUT_DISPATCH request=8 action=2',
        'STONE_INPUT_RESULT request=8 action=2 result=1',
        'KCD2_LOG prefix [MineComeBlock] {"schema":1,"session":1790000000000000,"sequence":12,"operation":2,"mc":{"x":-8,"y":-60,"z":2},"position":{"x":1,"y":2,"z":3},"result":"removed","physics":false,"live_draw_verified":false}',
        'STONE_ENGINE_ACK session=1790000000000000 sequence=12 result=removed',
        'STONE_CLEANUP_ACK session=1790000000000000',
        'Stone engine acknowledgements: placed=1 removed=1 rejected=0 cleanup_ack=true'
    )
    ($lines -join "`r`n")+"`r`n"
}
function Valid-Audit {
    "123 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft`n"+
    "124 STONE_INPUT_AUDIT_SESSION schema=1 connection=1 reset=3`n"+
    "200 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=1 sequence=10 request=7 action=1 result=1`n"+
    "300 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=2 sequence=12 request=8 action=2 result=1`n"
}
function Write-Audit($Session,[string]$Text){[IO.File]::WriteAllText((Join-Path $Session.Home 'runtime/logs/tools-bridge.log'),$Text,[Text.UTF8Encoding]::new($false))}
function Valid-Guest {
    [pscustomobject]@{
        run=$run;result='input_completed';save='MineCome-HudStream-owned'
        ui_input_stone_bridge=$true;ui_input_stone_live=$true;ui_input_live_mouse=$true;ui_input_offscreen_presentation=$true
        ui_input_stone_fixture=$false;ui_input_fixture=$false;ui_input_pointer_fixture=$false;ui_input_delay_fixture=$false;ui_input_background_trial=$false;ui_input_offscreen_trial=$false
        lab_evidence=[pscustomobject]@{stone_bridge=[pscustomobject]@{
            kind='minecome_hud_stone_bridge_v1';save='MineCome-HudStream-owned';failed=$false;closed=$true;pending=$false;cancelled_pending=0
            vanilla_dispatch_inventory_unchanged=$true;inventory_mutated=$false;camera_mutated=$false
            request_count=2;omitted_requests=0;omitted_confirmations=0;confirmed_actions=2;block_events_queued=2
            target=[pscustomobject]@{x=-8;y=-60;z=2}
            requests=@([pscustomobject]@{id=7L;action=1;result=1;result_queued=$true},[pscustomobject]@{id=8L;action=2;result=1;result_queued=$true})
            confirmations=@([pscustomobject]@{id=7L;action=1;client_and_server=$true;inventory_mutated=$false;server_age_ms=50},[pscustomobject]@{id=8L;action=2;client_and_server=$true;inventory_mutated=$false;server_age_ms=20})
        }}
    }
}
function Write-Log($Session,[string]$Text){[IO.File]::WriteAllText($Session.Stdout,$Text,[Text.UTF8Encoding]::new($false))}
$audit=ConvertFrom-MineComeHudStoneReceiptAudit (Valid-Audit) -Completed
Check ($audit.authenticated -and $audit.completed -and $audit.session.connection_generation -ceq 1UL -and $audit.session.reset_generation -ceq 3UL) 'Canonical receipt is bound to authenticated connection/reset provenance'
Check ($audit.results.Count -eq 2 -and $audit.results[1].receive_order -ceq 2UL -and $audit.results[1].wire_sequence -ceq 12UL -and $audit.results[1].request_id -ceq 8L) 'Canonical receipt preserves exact wire/order/request provenance'
foreach($code in 1..7){$a=ConvertFrom-MineComeHudStoneReceiptAudit ((Valid-Audit).Replace('request=8 action=2 result=1',"request=8 action=2 result=$code")) -Completed;Check ($a.results[1].result -eq $code) 'All protocol outcomes have canonical receipts'}
$partialAudit=ConvertFrom-MineComeHudStoneReceiptAudit ((Valid-Audit).TrimEnd("`n"))
Check ($partialAudit.results.Count -eq 1 -and -not $partialAudit.completed) 'Live partial audit line cannot become a receipt'
Check (-not (ConvertFrom-MineComeHudStoneReceiptAudit '').authenticated) 'Empty startup journal is not authentication evidence'
foreach($case in @('missing_anchor','missing_hello','legacy_hello','harness_hello','duplicate_hello','duplicate_anchor','duplicate_id','gap_order','duplicate_order','duplicate_sequence','backwards_sequence','hello_sequence','wrong_connection','wrong_reset','wrong_schema','wrong_action','wrong_result','large_id','overflow_generation','negative_sequence','zero_sequence','extra_field','prefix','backwards_time','post_disconnect','partial','oversized')){
    $text=Valid-Audit
    switch($case){
        missing_anchor {$text=$text.Replace("124 STONE_INPUT_AUDIT_SESSION schema=1 connection=1 reset=3`n",'')}
        missing_hello {$text=$text.Replace("123 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft`n",'')}
        legacy_hello {$text=$text.Replace('protocol 1.1','protocol 1.0')}
        harness_hello {$text=$text.Replace('peer role=minecraft','peer role=harness')}
        duplicate_hello {$text+="400 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft`n"}
        duplicate_anchor {$text+="400 STONE_INPUT_AUDIT_SESSION schema=1 connection=1 reset=3`n"}
        duplicate_id {$text=$text.Replace('request=8','request=7')}
        gap_order {$text=$text.Replace('order=2','order=3')}
        duplicate_order {$text=$text.Replace('order=2','order=1')}
        duplicate_sequence {$text=$text.Replace('sequence=12','sequence=10')}
        backwards_sequence {$text=$text.Replace('sequence=12','sequence=9')}
        hello_sequence {$text=$text.Replace('sequence=10','sequence=1')}
        wrong_connection {$text=$text.Replace('connection=1 reset=3 order=2','connection=2 reset=3 order=2')}
        wrong_reset {$text=$text.Replace('reset=3 order=2','reset=4 order=2')}
        wrong_schema {$text=$text.Replace('AUDIT schema=1','AUDIT schema=2')}
        wrong_action {$text=$text.Replace('action=2','action=3')}
        wrong_result {$text=$text.Replace('result=1','result=8')}
        large_id {$text=$text.Replace('request=8','request=9007199254740992')}
        overflow_generation {$text=$text.Replace('connection=1','connection=18446744073709551616')}
        negative_sequence {$text=$text.Replace('sequence=12','sequence=-12')}
        zero_sequence {$text=$text.Replace('sequence=12','sequence=0')}
        extra_field {$text=$text.Replace('request=8 action=2 result=1','request=8 action=2 result=1 trusted=true')}
        prefix {$text=$text.Replace('300 STONE_INPUT_AUDIT','prefix 300 STONE_INPUT_AUDIT')}
        backwards_time {$text=$text.Replace('300 STONE_INPUT_AUDIT','199 STONE_INPUT_AUDIT')}
        post_disconnect {$text=$text.Replace('300 STONE_INPUT_AUDIT',"250 session ended: graceful peer goodbye`n300 STONE_INPUT_AUDIT")}
        partial {$text=$text.TrimEnd("`n")}
        oversized {$text='x'*(2MB+1)}
    }
    Reject {ConvertFrom-MineComeHudStoneReceiptAudit $text -Completed} "${case}: invalid canonical receipt audit rejected"
}
$many="1 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft`n2 STONE_INPUT_AUDIT_SESSION schema=1 connection=1 reset=3`n"
foreach($i in 1..17){$many+="$($i+2) STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=$i sequence=$($i+1) request=$i action=1 result=6`n"}
Reject {ConvertFrom-MineComeHudStoneReceiptAudit $many -Completed} 'Canonical receipt audit is bounded to sixteen actions'
Assert-MineComeHudStoneReceiptOverlap $audit.results @([pscustomobject]@{request_id=8L;action=2;result=1}) -Completed
Check $true 'Polled results may be a strict ordered subset of durable results'
foreach($case in @('duplicate','unknown','action','result','order')){
    $poll=@([pscustomobject]@{request_id=7L;action=1;result=1},[pscustomobject]@{request_id=8L;action=2;result=1})
    switch($case){duplicate {$poll+=@($poll[0])} unknown {$poll[1].request_id=9L} action {$poll[1].action=1} result {$poll[1].result=6} order {$poll=@($poll[1],$poll[0])}}
    Reject {Assert-MineComeHudStoneReceiptOverlap $audit.results $poll -Completed} "${case}: polled audit overlap rejected"
}
Assert-MineComeHudStoneReceiptOverlap @() @([pscustomobject]@{request_id=7L;action=1;result=1})
Check $true 'Cross-file flush race is deferred until final audit'
$parsed=ConvertFrom-MineComeHudStoneRelayLog (Valid-Log)
Check ($parsed.fresh_world -and $parsed.authenticated -and $parsed.begin_sessions.Count -eq 1 -and $parsed.cleanup_sessions.Count -eq 1) 'Fresh native identity/world/session parsed'
Check ($parsed.results.Count -eq 2 -and $parsed.dispatches.Count -eq 2 -and $parsed.engine_acks.Count -eq 2 -and $parsed.events.Count -eq 2) 'Complete native action chain parsed'
Check ($parsed.results[0].request_id -ceq 7L -and $parsed.events[0].session -ceq 1790000000000000L) 'Exact numeric request/session retained'
Check ($parsed.summary.placed -eq 1 -and $parsed.summary.removed -eq 1 -and $parsed.summary.cleanup_ack) 'Actual shutdown summary parsed'
foreach($code in 1..7){$r=ConvertFrom-MineComeHudStoneRelayLog "STONE_INPUT_RESULT request=7 action=1 result=$code`n";Check ($r.results.Count -eq 1 -and $r.results[0].result -eq $code) 'All valid physical-click protocol results retained'}
$partial=ConvertFrom-MineComeHudStoneRelayLog ((Valid-Log).TrimEnd("`r","`n"))
Check ($null -eq $partial.summary) 'Unterminated terminal receipt cannot prove cleanup'
$partial=ConvertFrom-MineComeHudStoneRelayLog ('STONE_BEGIN_ACK session=123')
Check ($partial.begin_sessions.Count -eq 0) 'Unterminated engine ACK ignored'
$partial=ConvertFrom-MineComeHudStoneRelayLog ('STONE_INPUT_RESULT request=7 action=1 res')
Check ($partial.results.Count -eq 0) 'Growing polled result tail is deferred before strict record validation'
Reject {ConvertFrom-MineComeHudStoneRelayLog 'STONE_INPUT_RESULT request=7 action=1 res' -Completed} 'Completed truncated polled result is invalid'
Reject {ConvertFrom-MineComeHudStoneRelayLog "STONE_INPUT_RESULT request=7 action=1 res`n"} 'Malformed complete polled result is invalid'
$prefixed=ConvertFrom-MineComeHudStoneRelayLog ("untrusted-prefix STONE_BEGIN_ACK session=123`n")
Check ($prefixed.begin_sessions.Count -eq 0) 'Native ACK requires full anchored line'
Reject {ConvertFrom-MineComeHudStoneRelayLog ('x'*(2MB+1))} 'Bounded log enforced'
Reject {ConvertFrom-MineComeHudStoneRelayLog (('STONE_INPUT_RESULT request=7 action=1 result=1'+"`n")*17)} 'Action evidence capacity enforced'
Reject {ConvertFrom-MineComeHudStoneRelayLog "KCD2_LOG prefix [MineComeBlock] {bad}`n"} 'Malformed engine JSON rejected'
$s=New-Case;Write-Log $s (Valid-Log);Stop-MineComeHudStoneRelay $s
Check ($s.ExitObserved -and $s.ExitCode -eq 0 -and $s.CleanupVerified -and $s.Process.WaitCalls -eq 1) 'Graceful stop observes exit and cleanup'
Check (Test-Path -LiteralPath $s.StopFile) 'Graceful stop uses owned stop file'
Assert-MineComeHudStoneRelayGuest $s (Valid-Guest)
Check $s.EngineMirroringVerified 'Matching actual-guest/native evidence verifies engine mirroring'
# The worker accepted a final absent result immediately before GOODBYE. Its
# canonical receipt survives even though the host poll never drained the queue.
$last=New-Case;$last.Intents.Add([pscustomobject]@{ordinal=3;request_id=9L;action=2;accepted=$true;sent_utc_ms=2000L;failure=$null})
Write-Log $last ((Valid-Log)+"STONE_INPUT_DISPATCH request=9 action=2`n")
Write-Audit $last ((Valid-Audit)+"400 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=3 sequence=15 request=9 action=2 result=6`n401 session ended: graceful peer goodbye`n402 bridge stopped`n")
Stop-MineComeHudStoneRelay $last;$g=Valid-Guest;$g.lab_evidence.stone_bridge.request_count=3
$g.lab_evidence.stone_bridge.requests+=@([pscustomobject]@{id=9L;action=2;result=6;result_queued=$true})
Assert-MineComeHudStoneRelayGuest $last $g
Check ($last.EngineMirroringVerified -and $last.Native.results.Count -eq 3 -and $last.Native.polled_results.Count -eq 2) 'Final validated absent result survives graceful disconnect without inventing engine events'
$old=New-Case;Write-Log $old (Valid-Log);Write-Audit $old "123 HELLO authenticated; protocol 1.1 session ready; peer role=minecraft`n200 stone input result accepted id=7`n300 stone input result accepted id=8`n"
Stop-MineComeHudStoneRelay $old;Reject {Assert-MineComeHudStoneRelayGuest $old (Valid-Guest)} 'Old unversioned run cannot acquire retrospective audit proof'
Check (-not $old.EngineMirroringVerified -and $old.CleanupVerified -and $old.ReceiptAuditFailure) 'Missing audit does not prevent cleanup and cannot prove gameplay'
Write-Audit $old (Valid-Audit);Reject {Assert-MineComeHudStoneRelayGuest $old (Valid-Guest)} 'Later replacement cannot erase observed audit failure'
$missing=New-Case;Write-Log $missing (Valid-Log);Stop-MineComeHudStoneRelay $missing;Assert-MineComeHudStoneRelayGuest $missing (Valid-Guest)
$journal=Join-Path $missing.Home 'runtime/logs/tools-bridge.log'
[IO.File]::Move($journal,(Join-Path $missing.Home 'runtime/logs/tools-bridge-preserved.log'))
$missingEvidence=Get-MineComeHudStoneRelayEvidence $missing
Check (-not $missingEvidence.engine_mirroring_verified -and -not $missingEvidence.transport_auth_verified -and $missingEvidence.receipt_audit_failure) 'Missing completed journal clears a previous success claim while preserving the journal for inspection'
# An authentic occupied/absent/other vanilla refusal has a request/result, but no
# block event. Successful actions still require the complete engine proof chain.
foreach($code in 2..7){
    $declined=New-Case;$declined.Intents.Add([pscustomobject]@{ordinal=3;request_id=9L;action=1;accepted=$true;sent_utc_ms=2000L;failure=$null})
    $text=(Valid-Log)+"STONE_INPUT_DISPATCH request=9 action=1`nSTONE_INPUT_RESULT request=9 action=1 result=$code`n"
    Write-Audit $declined ((Valid-Audit)+"400 STONE_INPUT_AUDIT schema=1 connection=1 reset=3 order=3 sequence=15 request=9 action=1 result=$code`n")
    Write-Log $declined $text;Stop-MineComeHudStoneRelay $declined
    $g=Valid-Guest;$g.lab_evidence.stone_bridge.request_count=3
    $g.lab_evidence.stone_bridge.requests+=@([pscustomobject]@{id=9L;action=1;result=$code;result_queued=$true})
    Assert-MineComeHudStoneRelayGuest $declined $g
    Check $declined.EngineMirroringVerified 'Normal guest refusal does not invent or require an engine block event'
}
$evidence=Get-MineComeHudStoneRelayEvidence $s
Check (-not $evidence.visual_verified -and -not $evidence.physical_block_input_verified -and -not $evidence.kcd_launched -and -not $evidence.kcd_stopped -and -not $evidence.credentials_recorded) 'Evidence never invents physical, visual, game launch or credential claims'
Stop-MineComeHudStoneRelay $s;Check ($s.Process.WaitCalls -eq 1) 'Stop is idempotent'
foreach($case in @('missing_cleanup','missing_summary','cleanup_false','exit_nonzero','still_running','duplicate_event','wrong_cell','wrong_result','wrong_request','wrong_action','wrong_sequence','wrong_session','unexpected_rejection','wrong_summary','string_engine_boolean','legacy_auth','harness_auth')){
    $s=New-Case;$text=Valid-Log
    switch($case){
        missing_cleanup {$text=$text.Replace("STONE_CLEANUP_ACK session=1790000000000000`r`n",'')}
        missing_summary {$text=$text.Replace("Stone engine acknowledgements: placed=1 removed=1 rejected=0 cleanup_ack=true`r`n",'')}
        cleanup_false {$text=$text.Replace('cleanup_ack=true','cleanup_ack=false; Lua lease remains responsible')}
        exit_nonzero {$s.Process.ExitCode=3}
        still_running {$s.Process.WillExit=$false}
        duplicate_event {$text+="STONE_ENGINE_ACK session=1790000000000000 sequence=12 result=removed`n"}
        wrong_cell {$text=$text.Replace('"x":-8','"x":-7')}
        wrong_result {$text=$text.Replace('request=7 action=1 result=1','request=7 action=1 result=2')}
        wrong_request {$text=$text.Replace('request=7','request=9')}
        wrong_action {$text=$text.Replace('request=7 action=1','request=7 action=2')}
        wrong_sequence {$text=$text.Replace('sequence=10','sequence=11')}
        wrong_session {$text=$text.Replace('sequence=10 result=spawned','sequence=10 result=spawned').Replace('"session":1790000000000000','"session":1790000000000001')}
        unexpected_rejection {$text=$text.Replace('rejected=0','rejected=1')}
        wrong_summary {$text=$text.Replace('placed=1 removed=1','placed=2 removed=1')}
        string_engine_boolean {$text=$text.Replace('"physics":false','"physics":"false"')}
        legacy_auth {[IO.File]::WriteAllText((Join-Path $s.Home 'runtime/logs/tools-bridge.log'),"123 HELLO authenticated; protocol 1.0 session ready; peer role=minecraft`n")}
        harness_auth {[IO.File]::WriteAllText((Join-Path $s.Home 'runtime/logs/tools-bridge.log'),"123 HELLO authenticated; protocol 1.1 session ready; peer role=harness`n")}
    }
    Write-Log $s $text;Stop-MineComeHudStoneRelay $s
    Reject {Assert-MineComeHudStoneRelayGuest $s (Valid-Guest)} "${case}: invalid native chain rejected"
    Check (-not $s.EngineMirroringVerified) "${case}: no engine success claim"
    if($case -eq 'still_running'){Check (-not $s.ExitObserved -and -not $s.CleanupVerified -and $s.Process.WaitCalls -eq 1) 'Unresponsive owned process preserved after bounded wait'}
}
$guestMutations=@(
    {$args[0].run='c'*32},{$args[0].result='input_failed'},{$args[0].result='input_passed'},{$args[0].save='Another-save'},{$args[0].lab_evidence.stone_bridge.failed=$true},
    {$args[0].lab_evidence.stone_bridge.closed=$false},{$args[0].lab_evidence.stone_bridge.pending=$true},
    {$args[0].lab_evidence.stone_bridge.cancelled_pending=1},{$args[0].lab_evidence.stone_bridge.inventory_mutated=$true},
    {$args[0].lab_evidence.stone_bridge.camera_mutated=$true},{$args[0].lab_evidence.stone_bridge.request_count=3},
    {$args[0].lab_evidence.stone_bridge.omitted_requests=1},{$args[0].lab_evidence.stone_bridge.omitted_confirmations=1},
    {$args[0].lab_evidence.stone_bridge.confirmed_actions=1},{$args[0].lab_evidence.stone_bridge.block_events_queued=1},
    {$args[0].lab_evidence.stone_bridge.requests[0].id=9},{$args[0].lab_evidence.stone_bridge.requests[0].result=2},
    {$args[0].lab_evidence.stone_bridge.requests[0].result_queued=$false},{$args[0].lab_evidence.stone_bridge.requests[0].action=2},
    {$args[0].lab_evidence.stone_bridge.confirmations[0].id=9},{$args[0].lab_evidence.stone_bridge.confirmations[0].action=2},
    {$args[0].lab_evidence.stone_bridge.confirmations[0].client_and_server=$false},{$args[0].lab_evidence.stone_bridge.confirmations[0].inventory_mutated=$true},
    {$args[0].lab_evidence.stone_bridge.confirmations[0].server_age_ms=-1},{$args[0].lab_evidence.stone_bridge.confirmations[0].server_age_ms=251},
    {$args[0].lab_evidence.stone_bridge.target.z=3},{$args[0].lab_evidence.stone_bridge.requests=@()},
    {$args[0].lab_evidence.stone_bridge.confirmations=@()},{$args[0].lab_evidence.stone_bridge.failed='false'},
    {$args[0].lab_evidence.stone_bridge.requests[0].id='7'},{$args[0].lab_evidence.stone_bridge.confirmations[0].server_age_ms='50'},
    {$args[0].lab_evidence.stone_bridge.target.x='-8'}
)
foreach($mutation in $guestMutations){$s=New-Case;Write-Log $s (Valid-Log);Stop-MineComeHudStoneRelay $s;$g=Valid-Guest;& $mutation $g;Reject {Assert-MineComeHudStoneRelayGuest $s $g} 'Malformed guest evidence rejected';Check (-not $s.EngineMirroringVerified) 'Rejected guest cannot retain success'}
foreach($field in @('ui_input_stone_bridge','ui_input_stone_live','ui_input_live_mouse','ui_input_offscreen_presentation','ui_input_stone_fixture','ui_input_fixture','ui_input_pointer_fixture','ui_input_delay_fixture','ui_input_background_trial','ui_input_offscreen_trial')){
    foreach($mutation in @('inverted','string','missing')){
        $s=New-Case;Write-Log $s (Valid-Log);Stop-MineComeHudStoneRelay $s;$g=Valid-Guest
        switch($mutation){inverted {$g.$field=-not $g.$field} string {$g.$field=[string]$g.$field} missing {$g.PSObject.Properties.Remove($field)}}
        Reject {Assert-MineComeHudStoneRelayGuest $s $g} "${field}/${mutation}: live relay mode mismatch rejected"
        Check (-not $s.EngineMirroringVerified) 'Mode mismatch cannot retain success'
    }
}
# Failed startup can still own a process. Stop must clean it and preserve Start's reason.
$s=New-Case;$s.Ready=$false;$s.StartAttempted=$true;$s.Failure='simulated startup failure';Write-Log $s (Valid-Log);Stop-MineComeHudStoneRelay $s
Check ($s.CleanupVerified -and $s.Failure -ceq 'simulated startup failure') 'Failed startup cleanup retains original failure'
Reject {Start-MineComeHudStoneRelay $s} 'Session cannot start twice'
$s=New-Case;$s.Process=$null;Stop-MineComeHudStoneRelay $s
Check (-not $s.CleanupVerified -and -not $s.ExitObserved -and -not(Test-Path -LiteralPath $s.StopFile)) 'Prelaunch failure never claims exit or mutates stop state'
Reject {New-MineComeHudStoneRelay $context $testRoot 'not-a-run' 0} 'Malformed run rejected'
Reject {New-MineComeHudStoneRelay $context $project $run 0} 'Evidence outside owned runtime refused'
# Only the OS/game boundary is replaced for actual production intent dispatch.
function Assert-MineComeHudStoneRelay($Session){if($Session.Failure){throw 'Simulated health rejects a failed session'}}
function Invoke-MineComeProbeConsole($Context,[string]$Command){
    $script:sentCommands.Add($Command)
    if($Command -notmatch 'InteractiveIntent'){return}
    if($script:intentCase -eq 'transport_failure'){throw 'Simulated ambiguous transport failure'}
    if($Command -notmatch '\[MineComeHudStoneIntent\] ([a-f0-9]{32}) ([0-9]+) ([12]) '){throw 'Missing owned intent correlation tag'}
    $tag=$Matches[1];$ordinal=$Matches[2];$action=$Matches[3]
    $value=switch($script:intentCase){'refused' {'false rate_limited'} 'invalid_id' {'true 9007199254740992'} default {'true 11'}}
    $receipt="[MineComeHudStoneIntent] $tag $ordinal $action $value`n"
    if($script:intentCase -eq 'ambiguous'){$receipt+=$receipt}
    [IO.File]::AppendAllText($Context.GameLog,$receipt)
}
function Read-MineComeProbeLog($Context,[long]$Offset){[IO.File]::ReadAllText($Context.GameLog).Substring([int]$Offset)}
foreach($case in @('success','refused','invalid_id','ambiguous','transport_failure','repeated_id','capacity','too_soon')){
    $s=New-Case;$s.Intents.Clear();$s.Context=$context.PSObject.Copy()
    $gameLog=Join-Path $s.Home 'simulated-game.log';[IO.File]::WriteAllText($gameLog,'');$s.Context | Add-Member NoteProperty GameLog $gameLog
    $script:intentCase=$case;$script:sentCommands=[Collections.Generic.List[string]]::new()
    if($case -eq 'repeated_id'){$s.Intents.Add([pscustomobject]@{request_id=11L})}
    if($case -eq 'capacity'){for($i=0;$i -lt 16;$i++){$s.Intents.Add([pscustomobject]@{request_id=[long]$i})}}
    if($case -eq 'too_soon'){$s.LastIntentUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
    if($case -eq 'success'){
        $receipt=Send-MineComeHudStoneIntent $s -Action 1
        Check ($receipt.request_id -ceq 11L -and $receipt.action -ceq 1 -and $receipt.accepted -ceq $true -and $s.Intents.Count -eq 1) 'Engine intent returns same owned exact request ID'
        Reject {Send-MineComeHudStoneIntent $s -Action 2} 'Rapid second intent refused without dispatch'
        Check ($script:sentCommands.Count -eq 2) 'Only one intent and its log flush were sent'
    }else{
        Reject {Send-MineComeHudStoneIntent $s -Action 1} "${case}: invalid intent refuses success"
        if($case -in @('capacity','too_soon')){Check ($script:sentCommands.Count -eq 0) "${case}: gate runs before console write"}
        else {
            Check ($null -ne $s.Failure -and -not $s.Intents[-1].accepted) "${case}: failed request remains owned and unaccepted"
            $sent=$script:sentCommands.Count;Reject {Send-MineComeHudStoneIntent $s -Action 1} "${case}: failed session cannot retry ambiguous action"
            Check ($script:sentCommands.Count -eq $sent) "${case}: no duplicate console send"
        }
    }
}
$s=New-Case;$s.Intents.Clear();$s.Context=$context.PSObject.Copy();$gameLog=Join-Path $s.Home 'admission-game.log';[IO.File]::WriteAllText($gameLog,'');$s.Context|Add-Member NoteProperty GameLog $gameLog
$script:sentCommands=[Collections.Generic.List[string]]::new();$script:intentCase='success'
$r=Send-MineComeHudStoneIntent $s -Action 1 -BeforeDispatch {'stale_edge'}
Check (-not $r.accepted -and $r.declined -and $r.reason -ceq 'stale_edge' -and $s.Intents.Count -eq 0 -and $script:sentCommands.Count -eq 0 -and $null -eq $s.Failure) 'Physical admission decline sends nothing and preserves healthy relay'
$r=Send-MineComeHudStoneIntent $s -Action 1 -BeforeDispatch {$null}
Check ($r.accepted -and $r.request_id -eq 11 -and $s.Intents.Count -eq 1) 'Healthy relay can dispatch a later newly admitted physical edge'
Write-Output "HUD_STONE_RELAY_TEST_PASS checks=$script:checks simulated_receipts_only=true no_game_actions=true evidence=$testRoot"
