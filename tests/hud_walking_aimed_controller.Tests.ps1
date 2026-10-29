#Requires -Version 7.3
# Pure combined controller admission/cleanup regression; no game or input.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/HudWalkingAimed.ps1')
. (Join-Path $PSScriptRoot '../scripts/HudAimedRelay.ps1')
$checks=0
function Check($Value,[string]$Why){$script:checks++;if(-not $Value){throw $Why}}
function Reject([scriptblock]$Action,[string]$Why){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Why}
function Clone($Value){$Value|ConvertTo-Json -Depth 24|ConvertFrom-Json -Depth 24}
function Parse([string]$Path){$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $Path),[ref]$tokens,[ref]$errors);Check ($errors.Count -eq 0) "Syntax invalid: $Path";$ast}
$controller=Parse '../scripts/Test-HudWalkingAimed.ps1';$null=Parse '../scripts/Start-HudWalkingAimed.ps1';$child=Parse '../scripts/Run-HudStreamClient.ps1'
$node=$child.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Assert-HudWalkingAimedLiveChildMode'},$true)
. ([scriptblock]::Create($node.Extent.Text))
function ChildArgs {@{WalkingAimed=$true;ExtendedWalking=$true;InputMode=$true;LiveMouse=$true;OffscreenPresentation=$true;OtherMode=$false;Patch='patch';Trace='trace';View='view';Token='token'}}
$c=ChildArgs;Assert-HudWalkingAimedLiveChildMode @c;Check $true 'Explicit combined child accepted'
foreach($name in @('ExtendedWalking','InputMode','LiveMouse','OffscreenPresentation')){$c=ChildArgs;$c[$name]=$false;Reject {Assert-HudWalkingAimedLiveChildMode @c} "Missing $name accepted"}
foreach($name in @('Patch','Trace','View','Token')){$c=ChildArgs;$c[$name]='';Reject {Assert-HudWalkingAimedLiveChildMode @c} "Missing $name accepted"}
$c=ChildArgs;$c.OtherMode=$true;Reject {Assert-HudWalkingAimedLiveChildMode @c} 'Another profile accepted'
$run='a'*32;$probe='b'*32;$patch='c'*32;$hash='d'*64;$save='MineCome-HudStream-01234567-89ab-cdef-0123-456789abcdef'
$context=[pscustomobject]@{GamePid=42;GameStartedUtc=[datetime]'2026-10-28T12:00:00Z'}
$live=[pscustomobject]@{Run=$patch;Hash=$hash}
$receiver=[pscustomobject]@{Anchor=[pscustomobject]@{x=0;y=64;z=0};Center=[pscustomobject]@{x=100;y=200;z=50}}
function Alignment {
    Clone @{schema=1;kind='minecome_hud_walking_aim_ready_v1';run=$run;save=$save;patch_run=$patch;patch_sha256=$hash;target_pid=42;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();utc_ms=1000;
        bootstrap_confirmed=$true;initial_guest_feet=@{x=0;y=64;z=0};initial_guest_eye=@{x=0;y=65.62;z=0};host_player_anchor=@{x=100;y=200;z=50};host_anchor=@{x=100;y=200;z=51.7};
        arena_offer=@{blocksPerUnit=1;minecraftAnchor=@{x=0;y=65.62;z=0};kcdAnchor=@{x=100;y=200;z=51.7}}}
}
function State {
    $s=New-HudWalkingAimedAdmission $run $probe $live $context
    Set-HudWalkingAimedReady $s (Alignment) $receiver $save 900 1100
    $s
}
function Sample([long]$Seq,[long]$Utc,[double]$X=.2,[double]$Velocity=0,[string]$Phase='RESTING') {
    Clone @{Kind='sample';Record=@{seq=$Seq;utc_ms=$Utc;server_age_ns=1000000;phase=$Phase;client=@{x=$X;y=64;z=0;vx=$Velocity;vy=-.0784;vz=0;on_ground=$true;proxy_support=$true};server=@{x=$X;y=64;z=0;vx=$Velocity;vy=-.0784;vz=0;on_ground=$true;proxy_support=$true}};Target=@{x=100+$X;y=200;z=50}}
}
function Settled {
    $s=State
    Add-HudWalkingAimedSample $s (Sample 2 1200) 500
    Add-HudWalkingAimedSample $s (Sample 3 1300) 600
    Add-HudWalkingAimedSample $s (Sample 4 1400) 700
    $s
}
function View {Clone @{schema=1;source_kind='live_kcd_hud_view_v1';run=$run;patch_run=$patch;patch_sha256=$hash;target_pid=42;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();seq=4;utc_ms=1420;forward=@{x=1;y=0;z=0};up=@{x=0;y=0;z=1}}}
function NativeView {Clone @{schema=1;run=$probe;seq=4;sampled_engine_seconds=10.5;result='sampled';physical_movement=$true;camera_basis_valid=$true;player=@{x=100.2;y=200;z=50};camera=@{position=@{x=100.2;y=200;z=51.7};forward=@{x=1;y=0;z=0};up=@{x=0;y=0;z=1};fov=1.2}}}
$s=Settled;Check ($null -eq (Get-HudWalkingAimedDecline $s (View) (NativeView) 1450)) 'Fresh settled guest and delayed mapped host denied'
$s=State;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1450) -ceq 'guest_not_settled') 'Bootstrap substituted for actual guest trace'
$s=Settled;$s.Stopping=$true;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1450) -ceq 'aim_closing') 'Closing admitted input'
$s=Settled;$s.Ready=$null;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1450) -ceq 'aim_bootstrap_pending') 'Missing bootstrap admitted input'
$s=Settled;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1700) -ceq 'guest_source_stale') 'Server age omitted from freshness'
$s=Settled;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1399) -ceq 'guest_source_stale') 'Future guest clock accepted'
$s=Settled;Add-HudWalkingAimedSample $s (Sample 5 1500 .2 .03) 800;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1510) -ceq 'guest_not_settled') 'Threshold movement admitted'
$s=Settled;$p=Sample 5 1500;$p.Record.server.on_ground=$false;Add-HudWalkingAimedSample $s $p 800;Check ($s.Stationary.Count -eq 0) 'Airborne guest retained settlement'
$s=Settled;$p=Sample 5 1500;$p.Record.client.proxy_support=$false;Add-HudWalkingAimedSample $s $p 800;Check ($s.Stationary.Count -eq 0) 'Unproven terrain retained settlement'
$s=Settled;$p=Sample 5 1500;$p.Record.client.x=.22;Add-HudWalkingAimedSample $s $p 800;Check ($s.Stationary.Count -eq 0) 'Client/server disagreement accepted'
$s=Settled;Add-HudWalkingAimedSample $s (Sample 5 1500 .211) 800;Check ($s.Stationary.Count -eq 1) 'Moved target retained previous settlement'
$s=Settled;Add-HudWalkingAimedSample $s (Sample 5 1601) 901;Check ($s.Stationary.Count -eq 1) 'Missing source interval bridged settlement'
$s=Settled;Reject {Add-HudWalkingAimedSample $s (Sample 4 1500) 800} 'Trace replay admitted';Reject {Add-HudWalkingAimedSample $s (Sample 5 1500) 700} 'Source time replay admitted'
$s=Settled;$s.LastSample.SourceMs=11950;Check ((Get-HudWalkingAimedDecline $s (View) (NativeView) 1450) -ceq 'completion_tail') 'Completion tail admitted using fresh receipt time'
$s=Settled;Check ((Get-HudWalkingAimedDecline $s $null (NativeView) 1450) -ceq 'host_view_unavailable') 'Missing view admitted'
foreach($field in @('run','patch_run','patch_sha256','target_start_filetime','source_kind')){
    $s=Settled;$v=View;$v.$field='wrong';Reject {Get-HudWalkingAimedDecline $s $v (NativeView) 1450} "Wrong published $field accepted"
}
$s=Settled;$v=View;$v.utc_ms=1100;Check ((Get-HudWalkingAimedDecline $s $v (NativeView) 1450) -ceq 'host_view_stale') 'Old host view renewed'
$s=Settled;$v=View;$v.utc_ms=1399;Check ((Get-HudWalkingAimedDecline $s $v (NativeView) 1450) -ceq 'host_playback_not_settled') 'Pre-buffer camera accepted at matching coordinates'
$s=Settled;$v=View;$v.utc_ms=1451;Check ((Get-HudWalkingAimedDecline $s $v (NativeView) 1450) -ceq 'host_view_stale') 'Future host view admitted'
$s=Settled;$n=NativeView;$n.seq=5;Reject {Get-HudWalkingAimedDecline $s (View) $n 1450} 'Different native sample paired to published view'
$s=Settled;$n=NativeView;$n.player.x=100.26;Check ((Get-HudWalkingAimedDecline $s (View) $n 1450) -ceq 'host_player_not_settled') 'Host player mismatch admitted'
$s=Settled;$n=NativeView;$n.camera.position.z=51.951;Check ((Get-HudWalkingAimedDecline $s (View) $n 1450) -ceq 'host_camera_not_settled') 'Host camera mismatch admitted'
$s=Settled;$n=NativeView;$n.camera.position.z=51.95;Check ($null -eq (Get-HudWalkingAimedDecline $s (View) $n 1450)) 'Established aimed eye-origin allowance was narrowed'
$s=Settled;$v=View;$v.forward.x=.99;Reject {Get-HudWalkingAimedDecline $s $v (NativeView) 1450} 'Camera basis substituted'
$s=Settled;$null=Get-HudWalkingAimedDecline $s (View) (NativeView) 1450;Reject {Get-HudWalkingAimedDecline $s (View) (NativeView) 1449} 'Controller rollback accepted'
$s=Settled;Reject {Set-HudWalkingAimedReady $s (Alignment) $receiver $save 900 1500} 'Alignment replaced'
foreach($name in @('run','save','patch_run','patch_sha256','target_start_filetime')){$s=New-HudWalkingAimedAdmission $run $probe $live $context;$a=Alignment;$a.$name='wrong';Reject {Set-HudWalkingAimedReady $s $a $receiver $save 900 1500} "Alignment accepted wrong $name"}
$s=New-HudWalkingAimedAdmission $run $probe $live $context;$a=Alignment;$a.host_player_anchor.x+=.051;Reject {Set-HudWalkingAimedReady $s $a $receiver $save 900 1500} 'Terrain anchor mismatch accepted'
$s=New-HudWalkingAimedAdmission $run $probe $live $context;$a=Alignment;$a.initial_guest_feet.y+=.011;Reject {Set-HudWalkingAimedReady $s $a $receiver $save 900 1500} 'Guest anchor mismatch accepted'
function Closure {Clone @{schema=1;kind='minecome_hud_walking_aim_closed_v1';run=$run;save=$save;patch_run=$patch;patch_sha256=$hash;target_pid=42;target_start_filetime=$context.GameStartedUtc.ToFileTimeUtc().ToString();utc_ms=13000;logical_closed=$true;pending=$false;owned_count=0;guest_world_cleanup_complete=$true;support_cleanup_complete=$true}}
function RelayDone {Clone @{ExitObserved=$true;ExitCode=0;CleanupVerified=$true;InputCleanupVerified=$true;Failure=$null;CleanupFailure=$null;ReceiptAuditFailure=$null}}
$s=Settled;Set-HudWalkingAimedClosed $s (Closure) $save 900 13100;Assert-HudWalkingAimedCleanup $s (RelayDone) $false;Check $true 'Closed empty arena/native authority verified before restore'
Reject {Assert-HudWalkingAimedCleanup $s (RelayDone) $true} 'Cleanup accepted after restoration request'
foreach($name in @('ExitObserved','CleanupVerified','InputCleanupVerified')){$r=RelayDone;$r.$name=$false;Reject {Assert-HudWalkingAimedCleanup $s $r $false} "Missing relay $name accepted"}
foreach($name in @('guest_world_cleanup_complete','support_cleanup_complete')){$s=Settled;$c=Closure;$c.$name=$false;Set-HudWalkingAimedClosed $s $c $save 900 13100;Reject {Assert-HudWalkingAimedCleanup $s (RelayDone) $false} "Missing $name accepted"}
$s=Settled;$c=Closure;$c.owned_count=1;Set-HudWalkingAimedClosed $s $c $save 900 13100;Reject {Assert-HudWalkingAimedCleanup $s (RelayDone) $false} 'Unremoved block accepted as clean'
$s=Settled;$c=Closure;$c.pending=$true;Reject {Set-HudWalkingAimedClosed $s $c $save 900 13100} 'Pending request accepted as closed'
$line="EXTERNAL_PHYSICAL_POSE_ACCEPTED run=$probe seq=3 sampled_engine_seconds=13.125`n"
$r=ConvertFrom-MineComeHudAimedRelayLog $line $run -ExternalPhysicalPoseRun $probe;Check ($r.fresh_world -and $r.external_physical_pose.seq -eq 3) 'Exact external native pose accepted'
Reject {ConvertFrom-MineComeHudAimedRelayLog $line $run} 'Legacy relay accepted external profile'
Reject {ConvertFrom-MineComeHudAimedRelayLog $line $run -ExternalPhysicalPoseRun $run} 'Other external probe accepted'
Reject {ConvertFrom-MineComeHudAimedRelayLog ($line+$line) $run -ExternalPhysicalPoseRun $probe} 'External acknowledgement replay accepted'
Reject {ConvertFrom-MineComeHudAimedRelayLog ($line.Replace('13.125','NaN')) $run -ExternalPhysicalPoseRun $probe} 'Nonfinite external camera accepted'
$legacy="KCD2_LOG prefix [MineComePose] {`"schema`":1,`"player`":{},`"camera`":{}}`n"
$r=ConvertFrom-MineComeHudAimedRelayLog $legacy $run -ExternalPhysicalPoseRun $probe;Check (-not $r.fresh_world) 'Legacy SamplePose established external authority'
# Exercise actual routing with only file/foreground/HTTP boundaries replaced.
# The first rejection spends its permit and sequence permanently; a later poll
# cannot revive it after the positions become settled.
$productionSend=(Get-Command Send-MineComeHudAimedIntent).ScriptBlock
$script:edgeLines=[Collections.Generic.List[string]]::new();$script:allow=$false;$script:dispatches=0;$script:checksAtSend=0;$script:revokeAtSend=$false;$script:settledChecks=0;$script:admissionFault=$false
function Read-MineComeHudWorldClickLines($Reader){if($Reader -is [string]){return};$lines=$script:edgeLines.ToArray();$script:edgeLines.Clear();$lines}
function Get-MineComeHudWorldCurrentDecline($State,$Session,$Click){return $null}
function Send-MineComeHudAimedIntent($Session,$Selection,$Click,[scriptblock]$BeforeDispatch){
    $script:checksAtSend++
    if($script:revokeAtSend){$script:allow=$false}
    $reason=& $BeforeDispatch
    if($reason){return [pscustomobject]@{accepted=$false;reason=$reason}}
    $script:dispatches++
    $intent=[pscustomobject]@{accepted=$true;ordinal=$Session.Intents.Count+1;request_id=$Click.sequence;sequence=$Click.sequence;action=$Click.action;arena_id=[long]$Selection.arena;permit_id=[long]$Selection.permit;edge_utc_ms=$Click.utc_ms;installed_utc_ms=$Selection.installed_utc_ms}
    $Session.Intents.Add($intent);$intent
}
function ClickCase {
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $state=[pscustomobject]@{Run=$run;Context=$context;Sequence=0L;Failure=$null;Clicks=[Collections.Generic.List[object]]::new();AimedLedger=(New-MineComeAimedClickLedger $run);PermitReader='permit-reader'}
    Add-MineComeAimedPermitLine $state.AimedLedger "AIM_PERMIT_READY run=$run arena=1 permit=1 installed_utc_ms=$($now-50)"
    $script:edgeLines.Add('[MineComeWorldInput] '+(@{schema=1;run=$run;sequence=1;utc_ms=$now;action=2}|ConvertTo-Json -Compress))
    $relay=[pscustomobject]@{Run=$run;Context=$context;Intents=[Collections.Generic.List[object]]::new()}
    [pscustomobject]@{State=$state;Relay=$relay}
}
$case=ClickCase
$admission={param($Now) $script:settledChecks++;if($script:admissionFault){throw 'diagnostic admission fault'};if(-not $script:allow){'guest_not_settled'}}
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($case.State.Sequence -eq 1 -and $case.State.Clicks[0].status -ceq 'declined' -and $case.State.AimedLedger.Permits[0].used -and $script:dispatches -eq 0) 'Moving edge was not permanently consumed'
Check ($case.State.Clicks[0].timings.admission_calls -eq 1 -and $case.State.Clicks[0].timings.processing_ms -ge 0) 'Declined physical edge lost bounded timing diagnostics'
Check ($script:settledChecks -eq 1 -and $script:checksAtSend -eq 1) 'Moving rejection must use the final dispatch admission once'
$script:allow=$true
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($script:dispatches -eq 0 -and $case.State.Clicks.Count -eq 1) 'Rejected edge retried after settlement'
Check ($script:settledChecks -eq 1) 'Consumed edge performed another settled lookup'
$case=ClickCase;Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission;Assert-HudWalkingAimedClicks $case.State $case.Relay
Check ($script:dispatches -eq 1 -and $case.State.Clicks[0].status -ceq 'sent') 'Fresh settled edge not correlated to its original permit'
foreach($field in @('selection_ms','admission_ms','send_including_admission_ms','send_excluding_admission_ms','processing_ms')){Check ($case.State.Clicks[0].timings.$field -ge 0) "Invalid per-click timing $field"}
Check (-not $case.State.Clicks[0].timings.game_input_latency_measured -and $case.State.Clicks[0].timings.admission_calls -eq 1) 'Diagnostic timings invented input latency or repeated admission'
Check ($script:settledChecks -eq 2 -and $script:checksAtSend -eq 2) 'Fresh edge repeated the expensive admission before dispatch'
$case=ClickCase;$script:revokeAtSend=$true
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($script:dispatches -eq 1 -and $case.State.Clicks[0].status -ceq 'declined' -and $script:checksAtSend -eq 3 -and $script:settledChecks -eq 3) 'Settlement was not checked at the final dispatch boundary'
Check ($case.State.AimedLedger.Permits[0].used -and $case.Relay.Intents.Count -eq 0) 'Final rejection restored the permit or created an intent'
$case=ClickCase;$script:admissionFault=$true;$script:revokeAtSend=$false
Reject {Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission} 'Admission error was swallowed'
Check ($case.State.Clicks[0].status -ceq 'failed' -and $case.State.Clicks[0].timings.admission_calls -eq 1 -and
    $case.State.Clicks[0].timings.processing_ms -ge $case.State.Clicks[0].timings.admission_ms -and $script:dispatches -eq 1) 'Admission error lost timing or dispatched input'
$script:admissionFault=$false
# Actual shared sender: only combined external-pose sessions use150ms HTTP;
# retained legacy profile still calls its existing console boundary.
$script:httpTimeout=0;$script:httpDispatches=0;$script:legacySend=0;$script:contextChecks=0;$script:dispatchText='';$script:permitText=''
function Assert-MineComeHudAimedRelay($Session){}
function Assert-MineComeProbeContext($Context){$script:contextChecks++}
function Read-MineComeHudStoneText([string]$Path){$script:permitText}
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){$script:httpDispatches++;$script:httpTimeout=$TimeoutMilliseconds;$script:dispatchText=$PathAndQuery}
function Invoke-MineComeProbeConsole($Context,[string]$Command){$script:legacySend++}
function SenderCase([bool]$External,[int]$PermitAge=50){
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$ledger=New-MineComeAimedClickLedger $run
    $script:permitText="AIM_PERMIT_READY run=$run arena=1 permit=1 installed_utc_ms=$($now-$PermitAge)`n"
    Add-MineComeAimedPermitLine $ledger $script:permitText.TrimEnd("`n")
    $click=[pscustomobject]@{sequence=1L;action=2L;utc_ms=$now};$selection=Select-MineComeAimedClickPermit $ledger $click $now
    $session=[pscustomobject]@{Run=$run;Context=$context;ExternalPhysicalPoseRun=$(if($External){$probe}else{''});Intents=[Collections.Generic.List[object]]::new();LastIntentUtcMs=0L;Stdout='mock';Failure=$null}
    [pscustomobject]@{Session=$session;Selection=$selection;Click=$click;Ledger=$ledger}
}
$c=SenderCase $true;$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check ($r.accepted -and $script:httpTimeout -eq 150 -and $script:contextChecks -eq 1 -and $script:legacySend -eq 0) 'Combined intent lacked bounded HTTP/current ownership check'
$c=SenderCase $false;$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check ($r.accepted -and $script:legacySend -eq 1 -and $script:contextChecks -eq 1) 'Legacy aimed dispatch behavior changed'
$c=SenderCase $true;$c.Click.utc_ms-=251;$c.Selection.edge_utc_ms=$c.Click.utc_ms
$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check (-not $r.accepted -and $c.Session.Intents.Count -eq 0) 'Expired combined edge dispatched'
# Real final sender clocks, with a slow admission boundary only. The selected
# timestamps stay immutable; an initially fresh edge/permit expires naturally.
foreach($expiry in @('edge','permit')){
    $c=SenderCase $true $(if($expiry -ceq 'permit'){300}else{50})
    $originalEdge=$c.Click.utc_ms;$originalPermit=$c.Selection.installed_utc_ms;$httpBefore=$script:httpDispatches
    $script:freshAtFinalAdmission=$false
    $r=& $productionSend $c.Session $c.Selection $c.Click {
        $at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $script:freshAtFinalAdmission=($at-$c.Click.utc_ms -le 250 -and $at-$c.Selection.installed_utc_ms -le 350)
        Start-Sleep -Milliseconds $(if($expiry -ceq 'edge'){270}else{100})
        return $null
    }
    Check $script:freshAtFinalAdmission "The $expiry boundary test did not begin fresh"
    Check (-not $r.accepted -and $r.reason -ceq 'expired_or_unacknowledged_permit' -and $c.Session.Intents.Count -eq 0 -and $script:httpDispatches -eq $httpBefore) "$expiry expired during admission but still dispatched"
    Check ($c.Ledger.Permits[0].used -and $c.Click.utc_ms -eq $originalEdge -and $c.Selection.installed_utc_ms -eq $originalPermit) "$expiry expiration renewed its timestamps or restored its permit"
}
# Pending native stop polling returns immediately without wait/parse; once exit
# is observed, the independent cancellation/end receipts are still mandatory.
$script:stopParses=0;$script:badStopOrder=$false
function Update-MineComeHudAimedRelayEvidence($Session){
    $script:stopParses++
    $Session.Native=Clone @{summary=@{cleanup_ack=$true};begin_sessions=@(2);cleanup_sessions=@(2);input_begins=@(@{arena=1;line=1});input_cancels=@(@{arena=1;line=2});input_ends=@(@{arena=1;line=$(if($script:badStopOrder){1}else{3})})}
}
function StoppingRelay {
    [pscustomobject]@{AsyncStopRequested=$true;AsyncStopVerified=$false;Process=[pscustomobject]@{HasExited=$false;ExitCode=0};StopAttempted=$false;ExitObserved=$false;ExitCode=$null;Native=$null;ReceiptAuditFailure=$null;CleanupVerified=$false;InputCleanupVerified=$false;CleanupFailure=$null;Failure=$null}
}
$r=StoppingRelay;Check (-not (Complete-MineComeHudAimedRelayStop $r) -and $script:stopParses -eq 0 -and -not $r.StopAttempted) 'Pending asynchronous stop blocked or parsed'
$r.Process.HasExited=$true;Check ((Complete-MineComeHudAimedRelayStop $r) -and $script:stopParses -eq 1 -and $r.InputCleanupVerified) 'Exited async stop lacks independent cleanup proof'
$null=Complete-MineComeHudAimedRelayStop $r;Check ($script:stopParses -eq 1) 'Completed stop reparsed while movement active'
$r=StoppingRelay;$r.Process.HasExited=$true;$script:badStopOrder=$true;Reject {Complete-MineComeHudAimedRelayStop $r} 'Input end before cancellation accepted'

# Synthetic proof validation only. These records cannot establish physical input,
# real Minecraft execution, host rendering, or delayed native application.
function InventoryEvidence {
    Clone @{schema=1;kind='minecome_hud_movement_inventory_v1';max_windows=4;max_events=32;window_count=1;event_count=1;failure=$null;truncated=$false;capture_finished=$true;capture_complete=$true;
        events=@(@{input_sequence=7;kind=1;key=83;captured_utc_ms=2990;received_utc_ms=3000;received_monotonic_ns=3000000000L;accepted_down=$true;inventory_open=$false;window_id=0;context_observed=$true});
        windows=@(@{id=1;opened_utc_ms=1000;opened_monotonic_ns=1000000000L;closed_utc_ms=2000;closed_monotonic_ns=2000000000L;complete=$true;
            samples=20;server_sequence_advances=19;stale_samples=0;max_sample_gap_ns=50000000;max_server_age_ns=50000000;max_client_displacement=.002;max_server_displacement=.002;client_server_max_error=.002;
            all_grounded=$true;nonzero_binding_samples=0;bindings_or=0;immobility_verified=$true;
            resumed_movement=@{input_sequence=7;key=83;captured_utc_ms=2990;received_utc_ms=3000;received_monotonic_ns=3000000000L;binding_observed=$true;stale_samples=0;client_displacement=.15;server_displacement=.15;client_displacement_from_close=.15;server_displacement_from_close=.15;verified=$true}})}
}
function ScenarioGuest([string]$Face='UP',[long]$SeedX=2,[long]$SeedZ=0) {
    $seed=@{x=$SeedX;y=64;z=$SeedZ};$support=@{x=$SeedX;y=63;z=$SeedZ};$added=@{x=$SeedX;y=64;z=$SeedZ}
    switch -CaseSensitive ($Face){UP{$added.y++}WEST{$added.x--}EAST{$added.x++}NORTH{$added.z--}SOUTH{$added.z++}default{throw 'Unsupported scenario fixture face'}}
    $targets=@($seed,$added,$added,$seed);$hits=@($support,$seed,$added,$seed);$actions=@(1,1,2,2);$faces=@('UP',$Face,'WEST','WEST')
    $rows=@();$components=@();$requests=@()
    for($i=0;$i -lt 4;$i++) {
        $rows+=@{component_request_id=$i+1;wire_request_id=$i;action=$actions[$i];target=$targets[$i];hit_block=$hits[$i];face=$faces[$i];bootstrap=($i -eq 0);client_and_server=$true;block_event_queued=$true}
        $components+=@{id=$i+1;action=$actions[$i];target=$targets[$i];hit_block=$hits[$i];face=$faces[$i];bootstrap=($i -eq 0);client_and_server=$true;status='confirmed'}
        if($i -gt 0){$requests+=@{wire=@{requestId=$i;action=$actions[$i]};component_request_id=$i+1;result=1;actions_enabled=$true;vanilla_queued=$true;client_and_server=$true;result_queued=$true}}
    }
    Clone @{lab_evidence=@{inventory_opened=$true;inventory_closed=$true;
        stone_bridge=@{arena_offer=@{seed=$seed};confirmations=$rows;requests=$requests;confirmed_network_actions=3;owned_count=0;guest_world_cleanup_complete=$true;logical_closed_before_restore=$true;pending=$false;build_support=@{cleanup_complete=$true};
            arena=@{confirmations=$components;owned_count=0;pending=$false;omitted_receipts=0;block_writes=0;inventory_writes=0;camera_writes=0;owned_cells=@()}};
        physical_movement=@{inventory_evidence=(InventoryEvidence);input_timing=@{truncated=$false;
            events=@(@{input_sequence=7;kind=1;key=83;captured_utc_ms=2990;received_utc_ms=3000;received_monotonic_ns=3000000000L;accepted_down=$true});
            binding_states=@(@{after_input_sequence=7;monotonic_ns=3010000000L;mask=2;stage='before_vanilla_poll'})}}}}
}
$proof=Assert-HudWalkingAimedScenario -Guest $null
Check ($proof.scenario -ceq 'WalkingBreak' -and $proof.result -ceq 'passed' -and $null -eq $proof.inventory) 'Default scenario gained new inventory or face requirements'
$proof=Assert-HudWalkingAimedScenario -Guest $null -Scenario walkingbreak
Check ($proof.result -ceq 'passed') 'Case-insensitive ValidateSet changed default behavior'
$proof=Assert-HudWalkingAimedScenario -Guest (ScenarioGuest) -Scenario topfaceinventory
Check ($proof.requested_face -ceq 'UP') 'Case-insensitive scenario selected wrong face'
foreach($case in @(@('TopFaceInventory','UP'),@('SideFaceInventory','WEST'))) {
    $g=ScenarioGuest $case[1];$proof=Assert-HudWalkingAimedScenario -Guest $g -Scenario $case[0]
    Check ($proof.requested_face -ceq $case[1] -and $proof.confirmed_network_actions -eq 3 -and $proof.inventory.verified_windows.Count -eq 1) 'Scenario did not establish exact face and resumed walking'
    Check (-not $proof.physical_w_attempt_verified -and -not $proof.physical_w_denial_verified -and -not $proof.visual_verified) 'Scenario fabricated physical W or visual proof'
}
$g=ScenarioGuest 'WEST';Reject {Assert-HudWalkingAimedScenario $g TopFaceInventory} 'Front-facing placement counted as top-face placement'
$g=ScenarioGuest 'UP';Reject {Assert-HudWalkingAimedScenario $g SideFaceInventory} 'Top-face placement counted as WEST placement'
$g=ScenarioGuest 'EAST' -1 -5
$corridorScenario=Assert-HudWalkingAimedScenario $g SideFaceInventory -CorridorWalking
Check ($corridorScenario.requested_face -ceq 'EAST') 'Corridor side scenario must stay outside the captured north perimeter'
Reject {Assert-HudWalkingAimedScenario $g SideFaceInventory} 'Corridor face selection leaked into the legacy perimeter policy'
$g=ScenarioGuest 'SOUTH' -1 -5
Check ((Assert-HudWalkingAimedScenario $g SideFaceInventory).requested_face -ceq 'SOUTH') 'Legacy nearest face policy changed for north seed'
Reject {Assert-HudWalkingAimedScenario $g SideFaceInventory -CorridorWalking} 'Corridor side proof accepted placement toward captured terrain'
foreach($case in @(@('WEST',4,0),@('EAST',-5,0),@('NORTH',0,4),@('SOUTH',0,-5))){
    $face=$case[0];$x=$case[1];$z=$case[2]
    $g=ScenarioGuest $face $x $z
    $proof=Assert-HudWalkingAimedScenario $g SideFaceInventory
    Check ($proof.requested_face -ceq $face) "Perimeter seed must select origin-facing $face"
    $topProof=Assert-HudWalkingAimedScenario (ScenarioGuest 'UP' $x $z) TopFaceInventory
    Check ($topProof.requested_face -ceq 'UP') 'Top-face scenario must remain independent of horizontal perimeter'
    foreach($other in @('WEST','EAST','NORTH','SOUTH') | Where-Object {$_ -cne $face}){
        $bad=ScenarioGuest $other $x $z
        Reject {Assert-HudWalkingAimedScenario $bad SideFaceInventory} "Wrong near face $other must not pass for $face seed"
    }
    $bad=ScenarioGuest $face $x $z
    foreach($row in @($bad.lab_evidence.stone_bridge.confirmations[1],$bad.lab_evidence.stone_bridge.arena.confirmations[1])){$row.target.y++}
    Reject {Assert-HudWalkingAimedScenario $bad SideFaceInventory} 'Correct face cannot admit a wrong adjacent cell'
}
foreach($case in @(@('WEST',4,4),@('EAST',-5,-5),@('NORTH',3,4),@('SOUTH',-4,-5))){
    $proof=Assert-HudWalkingAimedScenario (ScenarioGuest $case[0] $case[1] $case[2]) SideFaceInventory
    Check ($proof.requested_face -ceq $case[0]) 'Seed-center dominance and exact X tie break must be deterministic'
}
$mutations=@(
    {param($g)$g.lab_evidence.stone_bridge.confirmations[1].target.x++},
    {param($g)$g.lab_evidence.stone_bridge.confirmations[1].hit_block.y++},
    {param($g)$g.lab_evidence.stone_bridge.confirmations[2].target.y--},
    {param($g)$g.lab_evidence.stone_bridge.confirmations[3].target.y++},
    {param($g)$g.lab_evidence.stone_bridge.confirmations[1].client_and_server=$false},
    {param($g)$g.lab_evidence.stone_bridge.arena.confirmations[1].face='WEST'},
    {param($g)$g.lab_evidence.stone_bridge.arena.confirmations[1].status='pending'},
    {param($g)$g.lab_evidence.stone_bridge.requests[0].vanilla_queued=$false},
    {param($g)$g.lab_evidence.stone_bridge.requests[0].component_request_id=9},
    {param($g)$g.lab_evidence.stone_bridge.confirmations[2].wire_request_id=1},
    {param($g)$g.lab_evidence.stone_bridge.owned_count=1},
    {param($g)$g.lab_evidence.stone_bridge.arena.owned_cells=@(@{x=2;y=64;z=0})},
    {param($g)$g.lab_evidence.stone_bridge.build_support.cleanup_complete=$false},
    {param($g)$g.lab_evidence.stone_bridge.arena.block_writes=1},
    {param($g)$g.lab_evidence.stone_bridge.arena.omitted_receipts=1},
    {param($g)$g.lab_evidence.inventory_closed=$false},
    {param($g)$g.lab_evidence.physical_movement.PSObject.Properties.Remove('inventory_evidence')},
    {param($g)$g.lab_evidence.physical_movement.input_timing.events[0].received_monotonic_ns++},
    {param($g)$g.lab_evidence.physical_movement.input_timing.events[0].accepted_down=$false},
    {param($g)$g.lab_evidence.physical_movement.input_timing.binding_states[0].mask=0},
    {param($g)$g.lab_evidence.physical_movement.input_timing.binding_states[0].stage='release'},
    {param($g)$g.lab_evidence.physical_movement.input_timing.binding_states[0].monotonic_ns=2990000000L},
    {param($g)$g.lab_evidence.physical_movement.input_timing.truncated=$true}
)
foreach($mutate in $mutations){$g=ScenarioGuest;& $mutate $g;Reject {Assert-HudWalkingAimedScenario $g TopFaceInventory} 'Malformed/unsupported scenario evidence passed'}
$inventoryMutations=@(
    {param($e)$e.kind='other'}, {param($e)$e.truncated=$true}, {param($e)$e.windows=@()},
    {param($e)$e.capture_finished=$false}, {param($e)$e.capture_complete=$false},
    {param($e)$e.window_count=2}, {param($e)$e.event_count=2}, {param($e)$e.failure='clock_regressed'},
    {param($e)$e.windows=@($e.windows[0]) * 5}, {param($e)$e.events=@($e.events[0]) * 33},
    {param($e)$e.windows[0].complete=$false}, {param($e)$e.windows[0].id=2},
    {param($e)$e.windows[0].closed_monotonic_ns=1249999999}, {param($e)$e.windows[0].closed_monotonic_ns=999999999},
    {param($e)$e.windows[0].samples=2}, {param($e)$e.windows[0].stale_samples=1},
    {param($e)$e.windows[0].server_sequence_advances=1},
    {param($e)$e.windows[0].max_sample_gap_ns=250000001}, {param($e)$e.windows[0].max_server_age_ns=250000001},
    {param($e)$e.windows[0].max_client_displacement=.01001}, {param($e)$e.windows[0].max_server_displacement=.01001},
    {param($e)$e.windows[0].client_server_max_error=.01001}, {param($e)$e.windows[0].all_grounded=$false},
    {param($e)$e.windows[0].nonzero_binding_samples=1}, {param($e)$e.windows[0].bindings_or=1},
    {param($e)$e.windows[0].immobility_verified=$false}, {param($e)$e.windows[0].max_client_displacement=[double]::NaN},
    {param($e)$e.windows[0].resumed_movement.received_monotonic_ns=2000000000L},
    {param($e)$e.windows[0].resumed_movement.captured_utc_ms=1999},
    {param($e)$e.windows[0].resumed_movement.key=32}, {param($e)$e.windows[0].resumed_movement.binding_observed=$false},
    {param($e)$e.windows[0].resumed_movement.client_displacement=.04999}, {param($e)$e.windows[0].resumed_movement.server_displacement=.04999},
    {param($e)$e.windows[0].resumed_movement.stale_samples=1},
    {param($e)$e.windows[0].resumed_movement.client_displacement_from_close=.04999}, {param($e)$e.windows[0].resumed_movement.server_displacement_from_close=.04999},
    {param($e)$e.windows[0].resumed_movement.verified=$false}, {param($e)$e.events[0].accepted_down=$false},
    {param($e)$e.events[0].inventory_open=$true}, {param($e)$e.events[0].received_monotonic_ns++}, {param($e)$e.events[0].captured_utc_ms++},
    {param($e)$e.events[0].context_observed=$false}, {param($e)$e.events[0].window_id=1},
    {param($e)$e.events+=@($e.events[0])}
)
foreach($mutate in $inventoryMutations){$e=InventoryEvidence;& $mutate $e;Reject {Assert-HudWalkingInventoryEvidence $e} 'Invalid inventory/resumption evidence passed'}
$e=InventoryEvidence;$proof=Assert-HudWalkingInventoryEvidence $e
Check ($proof.verified_windows.Count -eq 1 -and -not $proof.physical_w_attempt_verified -and $e.events.Count -eq 1) 'Native-filtered W absence was falsely required or represented as proof'
$e=InventoryEvidence;$e.windows[0].closed_monotonic_ns=1250000000
$null=Assert-HudWalkingInventoryEvidence $e;Check $true 'Exactly 250ms inventory window rejected'
foreach($path in @('../scripts/Start-HudWalkingAimed.ps1','../scripts/Test-HudWalkingAimed.ps1')){
    $ast=Parse $path;$scenario=@($ast.ParamBlock.Parameters | Where-Object {$_.Name.VariablePath.UserPath -ceq 'Scenario'})
    Check ($scenario.Count -eq 1 -and $scenario[0].DefaultValue.Value -ceq 'WalkingBreak') 'Wrapper/controller scenario default changed'
}
$controllerText=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/Test-HudWalkingAimed.ps1') -Raw
Check ($controllerText.IndexOf('Initialize-HudWalkingAimedAdmissionWarmup $directory') -lt $controllerText.IndexOf('$helper=Start-Process')) 'Admission warmup must precede Minecraft launch'
$tailNode=$controller.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-HudWalkingCompletionTail'},$true)
. ([scriptblock]::Create($tailNode.Extent.Text))
$tailState=[pscustomobject]@{TracePassed=$true;AimCleaned=$true;AimClosed=$true;FollowerFinishRequested=$true;CameraStopped=$true;CameraResourcesClosed=$true}
$tailTerminal=[pscustomobject]@{event='restored';result='restored';end_result='explicit_end';physical_movement=$true;camera_basis_valid=$true;terminal=$true;timers_cancelled=$true;readback=$true;player_readback_error=0.0}
$tail=Get-HudWalkingCompletionTail 113000 1000 113000 $tailState $tailTerminal
Check ($tail.deadline_utc_ms -eq 118000 -and $tail.maximum_tail_ms -eq 5000) 'Restored gameplay may wait at most five seconds for terminal HUD receipt'
Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 112999 $tailState $tailTerminal)) 'Receipt tail cannot alter the normal active loop'
Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 118000 $tailState $tailTerminal)) 'Receipt tail cannot renew itself at expiry'
$tail=Get-HudWalkingCompletionTail 116000 1000 116000 $tailState $tailTerminal
Check ($tail.deadline_utc_ms -eq 118000) 'GPU restoration reserve must truncate receipt tail'
Check ($null -eq (Get-HudWalkingCompletionTail 119000 1000 119000 $tailState $tailTerminal)) 'No receipt tail may consume final three seconds of GPU lease'
foreach($field in $tailState.PSObject.Properties.Name){
    foreach($badValue in @($false,'true')){
        $bad=Clone $tailState;$bad.$field=$badValue
        Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $bad $tailTerminal)) "Missing verified completion cannot admit receipt tail: $field"
    }
}
foreach($field in @('physical_movement','camera_basis_valid','terminal','timers_cancelled','readback')){
    $bad=Clone $tailTerminal;$bad.$field=$false
    Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $tailState $bad)) "Incomplete native restoration cannot admit receipt tail: $field"
}
foreach($badError in @(-.001,.151,[double]::NaN,'0')){
    $bad=Clone $tailTerminal;$bad.player_readback_error=$badError
    Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $tailState $bad)) 'Invalid native readback error cannot admit receipt tail'
}
$bad=Clone $tailTerminal;$bad.end_result='deadline'
Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $tailState $bad)) 'Deadline restoration is not normal explicit completion'
Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $tailState @())) 'Missing restoration cannot admit receipt tail'
Check ($null -eq (Get-HudWalkingCompletionTail 113000 1000 113000 $tailState @($tailTerminal,$tailTerminal))) 'Duplicate restoration cannot admit receipt tail'
# Retained second-session result arrived3210ms after the declared deadline. Use the
# whole UTC second preceding probe creation as a conservative replay estimate;
# the old run did not retain the new exact pre-budget timestamp.
$tail=Get-HudWalkingCompletionTail 1793305393884 1793305281000 1793305393884 $tailState $tailTerminal
Check ($tail.deadline_utc_ms -eq 1793305398000 -and 1793305397094 -lt $tail.deadline_utc_ms) 'Recorded legitimate HUD completion fits bounded restored-gameplay tail'
Check ($controllerText.IndexOf('Stop-MineComeHudGpuBudget $budget') -lt $controllerText.IndexOf('$exitDeadline=')) 'Host GPU budget must restore before waiting for JVM shutdown'
Write-Output "HUD_WALKING_AIMED_CONTROLLER_TESTS_PASS checks=$checks no_game_started=true"
