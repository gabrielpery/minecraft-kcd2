#Requires -Version 7.3
# Combined-mode admission/proof only. Dot sourcing does not start either game.
. (Join-Path $PSScriptRoot 'HudBufferedMovement.ps1')
. (Join-Path $PSScriptRoot 'AimedWorldClicks.ps1')
. (Join-Path $PSScriptRoot 'HudWorldClicks.ps1')

function New-HudWalkingAimedAdmission([string]$Run,[string]$ProbeRun,$LivePatch,$Context) {
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $ProbeRun -cnotmatch '^[0-9a-f]{32}$' -or
        $LivePatch.Run -cnotmatch '^[0-9a-f]{32}$' -or $LivePatch.Hash -cnotmatch '^[0-9a-f]{64}$') {throw 'Invalid combined controller identity.'}
    [pscustomobject]@{Run=$Run;ProbeRun=$ProbeRun;PatchRun=$LivePatch.Run;PatchHash=$LivePatch.Hash;
        TargetPid=$Context.GamePid;TargetStart=$Context.GameStartedUtc.ToFileTimeUtc().ToString();
        Ready=$null;Closed=$null;LastSample=$null;Stationary=[Collections.Generic.List[object]]::new();
        LastSourceMs=-1.0;LastTraceSeq=0L;LastViewSeq=0L;LastClock=0L;Stopping=$false}
}
function Assert-HudWalkingAimedIdentity($Receipt,$State,[string]$Save,[string]$Kind,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'schema') 'combined schema' 1 1)
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'utc_ms') 'combined receipt clock' $MinimumUtcMs ($NowUtcMs+50))
    if($Receipt.kind -cne $Kind -or $Receipt.run -cne $State.Run -or $Receipt.save -cne $Save -or
        $Receipt.patch_run -cne $State.PatchRun -or $Receipt.patch_sha256 -cne $State.PatchHash -or
        $Receipt.target_pid -ne $State.TargetPid -or $Receipt.target_start_filetime -cne $State.TargetStart){throw 'Combined receipt identity differs.'}
}
function Assert-HudWalkingAimedProducer($Receipt) {
    Assert-HudWalkingSession $Receipt -ExtendedWalking
    foreach($name in @('ui_input_walking_aimed','ui_input_physical_movement','ui_input_aimed_stone_bridge','ui_input_stone_bridge','ui_input_stone_live','ui_input_live_mouse','ui_input_offscreen_presentation')) {
        Assert-HudBufferedFlag (Get-HudBufferedField $Receipt $name) $name $true
    }
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'ui_input_protocol') 'combined UI protocol' 2 2)
    foreach($name in @('ui_physical_controller_fixture','ui_walking_aimed_fixture','scripted_input')) {
        $field=$Receipt.PSObject.Properties[$name]
        if($field -and ($name -ceq 'ui_physical_controller_fixture' -or $field.Value -isnot [bool] -or $field.Value)) {throw 'Fixture cannot authorize combined live input.'}
    }
    foreach($name in @('ui_input_fixture','ui_input_stone_fixture','ui_input_pointer_fixture','ui_input_delay_fixture','ui_input_background_trial','ui_input_offscreen_trial')) {
        Assert-HudBufferedFlag (Get-HudBufferedField $Receipt $name) $name $false
    }
}
function Set-HudWalkingAimedReady($State,$Receipt,$Receiver,[string]$Save,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    if($State.Ready -or $State.Stopping){throw 'Combined alignment cannot be replaced.'}
    Assert-HudWalkingAimedIdentity $Receipt $State $Save 'minecome_hud_walking_aim_ready_v1' $MinimumUtcMs $NowUtcMs
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'bootstrap_confirmed') 'bootstrap confirmation' $true
    foreach($name in @('initial_guest_feet','initial_guest_eye','host_anchor','host_player_anchor')) {
        [void](Get-HudBufferedVector (Get-HudBufferedField $Receipt $name) $name)
    }
    if((Get-HudBufferedDistance $Receipt.initial_guest_feet $Receiver.Anchor) -gt .01 -or
        (Get-HudBufferedDistance $Receipt.host_player_anchor $Receiver.Center) -gt .05 -or
        (Get-HudBufferedDistance $Receipt.host_anchor $Receipt.host_player_anchor) -gt 3 -or
        (Get-HudBufferedDistance $Receipt.initial_guest_eye $Receipt.initial_guest_feet) -gt 3){throw 'Combined alignment does not match the terrain/player anchors.'}
    $offer=$Receipt.arena_offer
    foreach($pair in @(@('minecraftAnchor','initial_guest_eye'),@('kcdAnchor','host_anchor'))) {
        if((Get-HudBufferedDistance (Get-HudBufferedVector (Get-HudBufferedField $offer $pair[0]) $pair[0]) $Receipt.($pair[1])) -gt .000001){throw 'Combined arena offer differs from its alignment.'}
    }
    [void](Get-HudBufferedNumber (Get-HudBufferedField $offer 'blocksPerUnit') 'combined scale' 1 1)
    $State.Ready=$Receipt
}
function Add-HudWalkingAimedSample($State,$Received,[double]$SourceMs) {
    if($Received.Kind -cne 'sample'){throw 'Combined admission requires an already validated source sample.'}
    $frame=$Received.Record
    [void](Get-HudBufferedNumber $SourceMs 'combined source time' 0 16000)
    if($frame.seq -le $State.LastTraceSeq -or $SourceMs -le $State.LastSourceMs){throw 'Combined trace order regressed.'}
    $sample=[pscustomobject]@{Record=$frame;Target=$Received.Target;SourceMs=$SourceMs}
    $stationary=$frame.phase -cin @('SETTLING','RESTING','WALKING')
    foreach($side in @('client','server')) {
        $pose=$frame.$side
        if(-not $pose.on_ground -or -not $pose.proxy_support -or
            [Math]::Sqrt($pose.vx*$pose.vx+$pose.vz*$pose.vz) -ge .03 -or [Math]::Abs($pose.vy) -ge .1){$stationary=$false}
    }
    if((Get-HudBufferedDistance $frame.client $frame.server) -gt .01){$stationary=$false}
    if($State.LastSample -and ($SourceMs-$State.LastSourceMs -gt 200 -or
        (Get-HudBufferedDistance $frame.client $State.LastSample.Record.client) -gt .01 -or
        (Get-HudBufferedDistance $frame.server $State.LastSample.Record.server) -gt .01)){$State.Stationary.Clear()}
    if(-not $stationary){$State.Stationary.Clear()}
    else {
        $State.Stationary.Add($sample)
        while($State.Stationary.Count -gt 8){$State.Stationary.RemoveAt(0)}
        # Compare the full retained window, not only adjacent tiny changes.
        while($State.Stationary.Count -gt 1 -and ((Get-HudBufferedDistance $frame.client $State.Stationary[0].Record.client) -gt .01 -or
            (Get-HudBufferedDistance $frame.server $State.Stationary[0].Record.server) -gt .01)){$State.Stationary.RemoveAt(0)}
    }
    $State.LastSample=$sample;$State.LastSourceMs=$SourceMs;$State.LastTraceSeq=[long]$frame.seq
}
function Get-HudWalkingAimedDecline($State,$View,$NativeView,[long]$NowUtcMs) {
    if($NowUtcMs -lt $State.LastClock){throw 'Combined admission clock regressed.'};$State.LastClock=$NowUtcMs
    if($State.Stopping -or $State.Closed){return 'aim_closing'}
    if(-not $State.Ready){return 'aim_bootstrap_pending'}
    if(-not $State.LastSample -or $State.Stationary.Count -lt 3){return 'guest_not_settled'}
    $latest=$State.LastSample;$first=$State.Stationary[0];$frame=$latest.Record
    $age=$NowUtcMs-[long]$frame.utc_ms
    if($age -lt 0 -or $age+$frame.server_age_ns/1000000.0 -gt 300){return 'guest_source_stale'}
    # Reserve three seconds of the unchanged15-second input authority. These
    # source times are original server times, never controller-receipt times.
    if($latest.SourceMs+$age+$frame.server_age_ns/1000000.0 -ge 12000){return 'completion_tail'}
    if($latest.SourceMs-$first.SourceMs -lt 200){return 'guest_not_settled'}
    if(-not $View -or -not $NativeView){return 'host_view_unavailable'}
    if($View.run -cne $State.Run -or $View.patch_run -cne $State.PatchRun -or $View.patch_sha256 -cne $State.PatchHash -or
        $View.target_pid -ne $State.TargetPid -or $View.target_start_filetime -cne $State.TargetStart -or
        $View.source_kind -cne 'live_kcd_hud_view_v1' -or $NativeView.run -cne $State.ProbeRun -or
        $NativeView.seq -ne $View.seq -or $NativeView.result -cne 'sampled' -or
        $NativeView.physical_movement -isnot [bool] -or -not $NativeView.physical_movement -or
        $NativeView.camera_basis_valid -isnot [bool] -or -not $NativeView.camera_basis_valid){throw 'Combined native view identity differs.'}
    [void](Get-HudBufferedInteger $View.seq 'combined view sequence' 1 1024)
    [void](Get-HudBufferedInteger $View.utc_ms 'combined view original clock' 1 ([long]::MaxValue))
    if($View.seq -lt $State.LastViewSeq){throw 'Combined view sequence regressed.'};$State.LastViewSeq=$View.seq
    if($NowUtcMs -lt $View.utc_ms -or $NowUtcMs-$View.utc_ms -gt 300){return 'host_view_stale'}
    # Require a native sample requested after the stationary source had time to
    # cross the existing200ms playback buffer. Matching coordinates alone cannot
    # certify that an old host view has caught up.
    if($View.utc_ms -lt $first.Record.utc_ms+200){return 'host_playback_not_settled'}
    $camera=Get-HudBufferedCamera $NativeView.camera 'combined native camera'
    $player=Get-HudBufferedVector $NativeView.player 'combined native player'
    foreach($part in @('forward','up')) {foreach($axis in @('x','y','z')){
        if($View.$part.$axis -ne $camera.$part.$axis){throw 'Combined published camera differs from its original receipt.'}
    }}
    if((Get-HudBufferedDistance $player $latest.Target) -gt .05){return 'host_player_not_settled'}
    $alignment=$State.Ready;$delta=[pscustomobject]@{x=$frame.server.x-$alignment.initial_guest_feet.x;y=$frame.server.y-$alignment.initial_guest_feet.y;z=$frame.server.z-$alignment.initial_guest_feet.z}
    $expected=[pscustomobject]@{x=$alignment.host_anchor.x+$delta.x;y=$alignment.host_anchor.y-$delta.z;z=$alignment.host_anchor.z+$delta.y}
    # Use the existing aimed-ray eye-origin allowance; the player's delayed
    # feet position still has the stricter.05m catch-up requirement above.
    if((Get-HudBufferedDistance $camera.position $expected) -gt .25){return 'host_camera_not_settled'}
    return $null
}
function Set-HudWalkingAimedClosed($State,$Receipt,[string]$Save,[long]$MinimumUtcMs,[long]$NowUtcMs) {
    if(-not $State.Ready -or $State.Closed){throw 'Combined closure requires one established alignment.'}
    Assert-HudWalkingAimedIdentity $Receipt $State $Save 'minecome_hud_walking_aim_closed_v1' $MinimumUtcMs $NowUtcMs
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'logical_closed') 'logical aim closure' $true
    Assert-HudBufferedFlag (Get-HudBufferedField $Receipt 'pending') 'pending aim request' $false
    [void](Get-HudBufferedInteger (Get-HudBufferedField $Receipt 'owned_count') 'remaining owned stones' 0 16)
    foreach($flag in @('guest_world_cleanup_complete','support_cleanup_complete')) {
        if((Get-HudBufferedField $Receipt $flag) -isnot [bool]){throw 'Combined cleanup evidence must be Boolean.'}
    }
    $State.Closed=$Receipt;$State.Stopping=$true
}
function Assert-HudWalkingAimedCleanup($State,$Relay,[bool]$FollowerFinishRequested) {
    if(-not $State.Closed -or -not $State.Stopping -or $State.Closed.owned_count -ne 0 -or
        -not $State.Closed.guest_world_cleanup_complete -or -not $State.Closed.support_cleanup_complete -or
        -not $Relay.ExitObserved -or $Relay.ExitCode -ne 0 -or -not $Relay.CleanupVerified -or -not $Relay.InputCleanupVerified -or
        $Relay.Failure -or $Relay.CleanupFailure -or $Relay.ReceiptAuditFailure){throw 'Combined aim authority/world cleanup is not complete.'}
    if($FollowerFinishRequested){throw 'Combined aim cleanup must be verified before follower restoration is requested.'}
}
function Initialize-HudWalkingAimedClicks($State,$Session){
    if($State.Run -cne $Session.Run){throw 'Aimed reader and relay runs differ.'}
    $path=Assert-MineComeHudStonePath $Session.Stdout
    $stream=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        $reader=[pscustomobject]@{Path=$path;Identity=(Get-MineComeHudWorldFileIdentity $stream);Offset=0L;ReadBytes=0L;Pending=[byte[]]@();DiscardInitialFragment=$false}
    }finally{$stream.Dispose()}
    $State | Add-Member NoteProperty AimedLedger (New-MineComeAimedClickLedger $State.Run)
    $State | Add-Member NoteProperty PermitReader $reader
}
function Get-HudWalkingAimedCurrentDecline($State,$Session,$Click,$Selection,[scriptblock]$SettledAdmission){
    $reason=Get-MineComeHudWorldCurrentDecline $State $Session $Click
    if($reason){return $reason}
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if($now -lt $Selection.installed_utc_ms -or $now -lt $Click.utc_ms){return 'clock_rollback'}
    if($now-$Selection.installed_utc_ms -gt 350){return 'permit_dispatch_expired'}
    if($now-$Click.utc_ms -gt 250){return 'stale_edge'}
    if(-not $SettledAdmission){throw 'Combined clicks require current settled admission.'}
    $reason=& $SettledAdmission $now
    if($reason){return [string]$reason}
    return $null
}
function Update-HudWalkingAimedPermitLedger($State){
    foreach($line in @(Read-MineComeHudWorldClickLines $State.PermitReader)){Add-MineComeAimedPermitLine $State.AimedLedger $line}
}
function Invoke-HudWalkingAimedClicks($State,$Session,[scriptblock]$SettledAdmission){
    if($State.Failure){throw 'Aimed world-click reader is already failed; input will not be retried.'}
    try{
        if($State.Run -cne $Session.Run -or $State.Context.GamePid -ne $Session.Context.GamePid -or $State.Context.GameStartedUtc -ne $Session.Context.GameStartedUtc){throw 'Aimed world-click relay owner differs.'}
        # Read acknowledgements first. Selection still requires their native
        # installation timestamp to precede the physical edge strictly.
        Update-HudWalkingAimedPermitLedger $State
        foreach($line in @(Read-MineComeHudWorldClickLines $State)){
            $click=ConvertFrom-MineComeHudWorldClick $line $State.Run $State.Sequence
            if($null -eq $click){continue}
            $State.Sequence=$click.sequence
            $record=[pscustomobject]@{sequence=$click.sequence;utc_ms=$click.utc_ms;action=$click.action;observed_utc_ms=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();status='pending';reason=$null;intent_ordinal=0;request_id=0L;arena_id=$null;permit_id=$null;installed_utc_ms=0L}
            $State.Clicks.Add($record)
            # Admission consumes every sequence, including foreground/lease
            # refusals; a selected permit is spent even if dispatch then fails.
            $selection=Select-MineComeAimedClickPermit $State.AimedLedger $click $record.observed_utc_ms
            if(-not $selection.accepted){$record.status='declined';$record.reason=$selection.reason;continue}
            $record.arena_id=$selection.arena;$record.permit_id=$selection.permit;$record.installed_utc_ms=$selection.installed_utc_ms
            $reason=Get-HudWalkingAimedCurrentDecline $State $Session $click $selection $SettledAdmission
            if($reason){$record.status='declined';$record.reason=$reason;continue}
            $receipt=Send-MineComeHudAimedIntent $Session $selection $click -BeforeDispatch {Get-HudWalkingAimedCurrentDecline $State $Session $click $selection $SettledAdmission}
            if(-not $receipt.accepted){$record.status='declined';$record.reason=$receipt.reason;continue}
            $record.status='sent';$record.intent_ordinal=$receipt.ordinal;$record.request_id=$receipt.request_id
        }
    }catch{$State.Failure=$_.Exception.Message;if($State.Clicks.Count -gt 0 -and $State.Clicks[-1].status -ceq 'pending'){$State.Clicks[-1].status='failed';$State.Clicks[-1].reason=$State.Failure};throw}
}
function Assert-HudWalkingAimedClicks($State,$Session){
    Assert-MineComeHudWorldClicks $State $Session
    if($State.AimedLedger.Failed -or $State.AimedLedger.LastClick -ne $State.Sequence){throw 'Aimed physical-edge ledger did not complete.'}
    $sent=@($State.Clicks | Where-Object status -CEQ 'sent')
    for($i=0;$i -lt $sent.Count;$i++){
        $click=$sent[$i];$intent=$Session.Intents[$i]
        if([string]$click.arena_id -cne [string]$intent.arena_id -or [string]$click.permit_id -cne [string]$intent.permit_id -or
           $click.sequence -ne $intent.sequence -or $click.sequence -ne $intent.request_id -or
           $click.utc_ms -ne $intent.edge_utc_ms -or $click.installed_utc_ms -ne $intent.installed_utc_ms -or
           $click.installed_utc_ms -ge $click.utc_ms){throw 'Aimed physical edge differs from its original installed permit.'}
    }
}
