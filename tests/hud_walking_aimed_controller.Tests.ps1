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
$script:edgeLines=[Collections.Generic.List[string]]::new();$script:allow=$false;$script:dispatches=0;$script:checksAtSend=0;$script:revokeAtSend=$false
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
$admission={param($Now) if(-not $script:allow){'guest_not_settled'}}
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($case.State.Sequence -eq 1 -and $case.State.Clicks[0].status -ceq 'declined' -and $case.State.AimedLedger.Permits[0].used -and $script:dispatches -eq 0) 'Moving edge was not permanently consumed'
$script:allow=$true
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($script:dispatches -eq 0 -and $case.State.Clicks.Count -eq 1) 'Rejected edge retried after settlement'
$case=ClickCase;Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission;Assert-HudWalkingAimedClicks $case.State $case.Relay
Check ($script:dispatches -eq 1 -and $case.State.Clicks[0].status -ceq 'sent') 'Fresh settled edge not correlated to its original permit'
$case=ClickCase;$script:revokeAtSend=$true
Invoke-HudWalkingAimedClicks $case.State $case.Relay $admission
Check ($script:dispatches -eq 1 -and $case.State.Clicks[0].status -ceq 'declined' -and $script:checksAtSend -eq 2) 'Settlement was not checked again at dispatch'
# Actual shared sender: only combined external-pose sessions use150ms HTTP;
# retained legacy profile still calls its existing console boundary.
$script:httpTimeout=0;$script:legacySend=0;$script:contextChecks=0;$script:dispatchText='';$script:permitText=''
function Assert-MineComeHudAimedRelay($Session){}
function Assert-MineComeProbeContext($Context){$script:contextChecks++}
function Read-MineComeHudStoneText([string]$Path){$script:permitText}
function Invoke-MineComeToolsRequest([string]$PathAndQuery,[int]$TimeoutMilliseconds){$script:httpTimeout=$TimeoutMilliseconds;$script:dispatchText=$PathAndQuery}
function Invoke-MineComeProbeConsole($Context,[string]$Command){$script:legacySend++}
function SenderCase([bool]$External){
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$ledger=New-MineComeAimedClickLedger $run
    $script:permitText="AIM_PERMIT_READY run=$run arena=1 permit=1 installed_utc_ms=$($now-50)`n"
    Add-MineComeAimedPermitLine $ledger $script:permitText.TrimEnd("`n")
    $click=[pscustomobject]@{sequence=1L;action=2L;utc_ms=$now};$selection=Select-MineComeAimedClickPermit $ledger $click $now
    $session=[pscustomobject]@{Run=$run;Context=$context;ExternalPhysicalPoseRun=$(if($External){$probe}else{''});Intents=[Collections.Generic.List[object]]::new();LastIntentUtcMs=0L;Stdout='mock';Failure=$null}
    [pscustomobject]@{Session=$session;Selection=$selection;Click=$click}
}
$c=SenderCase $true;$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check ($r.accepted -and $script:httpTimeout -eq 150 -and $script:contextChecks -eq 1 -and $script:legacySend -eq 0) 'Combined intent lacked bounded HTTP/current ownership check'
$c=SenderCase $false;$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check ($r.accepted -and $script:legacySend -eq 1 -and $script:contextChecks -eq 1) 'Legacy aimed dispatch behavior changed'
$c=SenderCase $true;$c.Click.utc_ms-=251;$c.Selection.edge_utc_ms=$c.Click.utc_ms
$r=& $productionSend $c.Session $c.Selection $c.Click {$null}
Check (-not $r.accepted -and $c.Session.Intents.Count -eq 0) 'Expired combined edge dispatched'
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
Write-Output "HUD_WALKING_AIMED_CONTROLLER_TESTS_PASS checks=$checks no_game_started=true"
