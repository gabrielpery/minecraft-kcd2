#Requires -Version 7.3
# Original bounded vanilla UI control lab. Fixture mode never operates KCD2.
# Live mode arms an already-running, separately installed matching input profile.
[CmdletBinding()]
param(
    [ValidateSet('Fixture','Live')][string]$Mode='Fixture',
    [string]$JavaHome,[string]$BundleDirectory,[switch]$PreflightOnly,[switch]$DelayFixture,[switch]$BackgroundTrial,[switch]$OffscreenPresentation,[switch]$OffscreenTrial,[switch]$HostGpuBudget,[switch]$HideHostHud,[switch]$PointerFixture,[switch]$LiveMouse,[switch]$StoneFixture,[switch]$StoneLive,[switch]$WorldClicks,[switch]$SelectiveMouse,
    [ValidateSet(1,2,3)][int]$SelectiveRevision=1,
    [ValidateRange(320,1920)][int]$Width=1280,
    [ValidateRange(240,1080)][int]$Height=720,
    [ValidateRange(1,4)][int]$GuiScale=2
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$evidenceRoot=Join-Path $root 'runtime/evidence'
$fixturePath=Join-Path $root 'build/hud-input-offscreen-20261012/kcd2/hud/input/Release/minecome_hud_input_fixture.exe'
if($PointerFixture){$fixturePath=Join-Path $root 'build/hud-input-pointer-nullfix-20261013/kcd2/hud/input/Release/minecome_hud_input_fixture.exe'}
if($StoneFixture){$fixturePath=Join-Path $root 'build/hud-stone-20261013/kcd2/hud/input/Release/minecome_hud_input_fixture.exe'}
function Assert-Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked UI lab path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-Receipt([string]$Path){
    $null=Assert-Unlinked $Path
    $item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 64KB){throw 'Invalid bounded UI receipt.'}
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 16)
}
function Assert-LiveMouseReceipt([object]$Receipt,[bool]$Expected){
    if($Receipt.PSObject.Properties.Name -notcontains 'ui_input_live_mouse' -or $Receipt.ui_input_live_mouse -isnot [bool] -or $Receipt.ui_input_live_mouse -ne $Expected){throw 'UI producer/result live-mouse mode mismatch.'}
}
function Assert-HudStoneMode([object]$Receipt,[bool]$Expected,[bool]$LiveExpected=$false){
    if($Expected -and $LiveExpected){throw 'Live and fixture stone modes are mutually exclusive.'}
    $values=@{ui_input_stone_bridge=($Expected -or $LiveExpected);ui_input_stone_fixture=$Expected;ui_input_stone_live=$LiveExpected}
    foreach($field in $values.Keys){
        if($Receipt.PSObject.Properties.Name -notcontains $field -or $Receipt.$field -isnot [bool] -or $Receipt.$field -ne $values[$field]){throw 'Combined stone mode mismatch.'}
    }
}
function Assert-HudStoneConfiguration([string]$Mode,[bool]$StoneFixture,[bool]$StoneLive,[bool]$LiveMouse,[bool]$OffscreenPresentation,[bool]$OffscreenTrial,[bool]$HostGpuBudget,[bool]$PointerFixture,[bool]$DelayFixture,[bool]$BackgroundTrial,[bool]$HideHostHud,[bool]$WorldClicks=$false,[bool]$SelectiveMouse=$false,[ValidateSet(1,2,3)][int]$SelectiveRevision=1){
    if($SelectiveRevision -ge 2 -and -not $SelectiveMouse){throw 'A selective revision requires an explicit SelectiveMouse session.'}
    if($SelectiveMouse -and -not $WorldClicks){throw 'SelectiveMouse requires the explicit WorldClicks session and its separate capture profile.'}
    if($WorldClicks -and -not $StoneLive){throw 'WorldClicks requires the explicit capped StoneLive session.'}
    if($StoneFixture -and ($StoneLive -or $Mode -ne 'Fixture' -or -not $OffscreenTrial -or $PointerFixture -or $LiveMouse -or $DelayFixture -or $BackgroundTrial -or $HostGpuBudget -or $HideHostHud)){throw 'StoneFixture requires its separate standalone OffscreenTrial without other fixture/live modes.'}
    if($StoneLive -and ($StoneFixture -or $Mode -ne 'Live' -or -not $LiveMouse -or -not $OffscreenPresentation -or -not $HostGpuBudget -or $OffscreenTrial -or $PointerFixture -or $DelayFixture -or $BackgroundTrial)){throw 'StoneLive requires the capped live mouse profile without fixture modes.'}
}
function Assert-HudSelectiveArm($Receipt,[bool]$Expected,[ValidateSet(1,2,3)][int]$SelectiveRevision=1){
    # Arm-HudStream returns an ordered dictionary directly; stored JSON reads
    # as PSCustomObject. Validate keys in both representations without coercion.
    $fields=if($Receipt -is [Collections.IDictionary]){@($Receipt.Keys)}else{@($Receipt.PSObject.Properties.Name)}
    if($fields -notcontains 'selective_mouse' -or $Receipt.selective_mouse -isnot [bool] -or $Receipt.selective_mouse -ne $Expected){throw 'Selective mouse arming receipt does not match the requested capture mode.'}
    if($SelectiveRevision -ge 2){
        if(-not $Expected -or $fields -notcontains 'selective_revision' -or
           ($Receipt.selective_revision -isnot [int] -and $Receipt.selective_revision -isnot [long]) -or
           $Receipt.selective_revision -ne $SelectiveRevision){throw 'Selective arming receipt does not identify the requested integer revision.'}
    }elseif($fields -contains 'selective_revision'){throw 'Original capture mode cannot accept a revision-specific arming receipt.'}
}
function Assert-HudWorldClickGuest($Guest){
    Assert-HudStoneMode $Guest $false $true
    $proof=$Guest.lab_evidence.stone_bridge
    if($Guest.result -cne 'input_completed' -or $proof.kind -cne 'minecome_hud_stone_bridge_v1' -or $proof.save -cne $Guest.save){throw 'World click proof does not belong to the completed guest world.'}
    foreach($field in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged')){
        if($proof.$field -isnot [bool] -or -not $proof.$field){throw 'World click guest completion proof missing.'}
    }
    foreach($field in @('failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){
        if($proof.$field -isnot [bool] -or $proof.$field){throw 'World click guest did not finish with a clean empty target.'}
    }
    foreach($field in @('confirmed_places','confirmed_breaks')){
        if(($proof.$field -isnot [int] -and $proof.$field -isnot [long]) -or $proof.$field -lt 1 -or $proof.$field -gt 8){throw 'World click check needs at least one actual place and break.'}
    }
    if($proof.confirmed_places -ne $proof.confirmed_breaks){throw 'World click check left an unmatched placement.'}
    # Full request/confirmation/engine correlation is checked after relay cleanup.
    # Here distinguish valid vanilla refusal from a missing action or changed item.
    foreach($request in @($proof.requests)){
        if(($request.result -isnot [int] -and $request.result -isnot [long]) -or $request.result -lt 1 -or $request.result -gt 7){throw 'Unknown world click result.'}
        if($request.result -eq 1 -and $request.action -eq 1 -and ($request.selected_item -cne 'minecraft:stone' -or $request.selected_count -lt 1)){throw 'World placement did not use the selected stone stack.'}
    }
    if(@($proof.confirmations | Where-Object action -eq 1).Count -ne $proof.confirmed_places -or @($proof.confirmations | Where-Object action -eq 2).Count -ne $proof.confirmed_breaks){throw 'World click confirmation totals differ from the recorded actions.'}
}
function Assert-HudLiveArming($Proof,[bool]$WorldClicks){
    if($Proof.host_armed -isnot [bool] -or -not $Proof.host_armed -or
       ($Proof.input_events_applied -isnot [int] -and $Proof.input_events_applied -isnot [long]) -or
       $Proof.input_events_applied -lt 0 -or (-not $WorldClicks -and $Proof.input_events_applied -eq 0)){
        throw 'Live UI session closed without valid arming/input evidence.'
    }
    # Physical world clicks use their independently verified relay, not UI events.
}
function Test-HudStonePreviewEnginePlace($Native,[string]$RequestId){
    if(-not $Native -or $RequestId -cnotmatch '^[1-9][0-9]{0,15}$'){return $false}
    $results=@($Native.results);$events=@($Native.events);$acks=@($Native.engine_acks)
    if($results.Count -ne 1 -or $events.Count -ne 1 -or $acks.Count -ne 1){return $false}
    return [string]$results[0].request_id -ceq $RequestId -and $results[0].action -eq 1 -and $results[0].result -eq 1 -and $events[0].operation -eq 1 -and $events[0].result -ceq 'spawned' -and $acks[0].result -ceq 'spawned' -and [string]$events[0].session -ceq [string]$acks[0].session -and [string]$events[0].sequence -ceq [string]$acks[0].sequence
}
function Get-HudStonePreviewAction($State,[string]$ClientLog,[string]$Run,[long]$Now,[bool]$EnginePlaced=$false){
    if($Run -cnotmatch '^[0-9a-f]{32}$' -or $Now -lt 1){throw 'Invalid preview clock or run.'}
    if($State.Save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){throw 'Invalid owned HUD save in preview.'}
    if($ClientLog -match ('HUD_INPUT_TERMINAL run='+$Run+' ') -or $ClientLog -match ('HUD_STREAM_TERMINAL run='+$Run+' ')){return 0}
    if($State.ArmedAtMs -eq 0){
        if($ClientLog -notmatch ('HUD_INPUT_ARMED run='+$Run+' fixture=false')){return 0}
        $State.ArmedAtMs=$Now
    }
    if($Now -lt $State.ArmedAtMs){throw 'Preview clock moved backwards.'}
    if($Now-$State.ArmedAtMs -ge 20000){return 0}
    if($State.Stage -eq 0){
        if($Now-$State.ArmedAtMs -ge 2000 -and $ClientLog -match ('HUD_STONE_READY save='+[regex]::Escape($State.Save)+' ')){return 1}
    }elseif($State.Stage -eq 1){
        if($State.PlaceRequestId -cnotmatch '^[1-9][0-9]{0,15}$' -or $State.PlaceAtMs -lt $State.ArmedAtMs -or $Now -lt $State.PlaceAtMs){throw 'Invalid owned place request.'}
        $confirmed=$EnginePlaced -and $ClientLog -match ('HUD_STONE_CONFIRMED request='+$State.PlaceRequestId+' action=1 ')
        if(-not $confirmed -and $Now-$State.PlaceAtMs -gt 5000){throw 'Live preview placement lacked actual Minecraft confirmation.'}
        if($confirmed -and $State.ConfirmedAtMs -eq 0){$State.ConfirmedAtMs=$Now}
        if($State.ConfirmedAtMs -ne 0 -and ($State.ConfirmedAtMs -lt $State.PlaceAtMs -or $Now -lt $State.ConfirmedAtMs)){throw 'Invalid preview confirmation clock.'}
        if($confirmed -and $State.ConfirmedAtMs -ne 0 -and $Now-$State.ConfirmedAtMs -ge 10000){return 2}
    }elseif($State.Stage -ne 2){throw 'Invalid preview stage.'}
    return 0
}
function Assert-HudStoneLivePreview($Guest){
    function Integer($Value,[long]$Minimum,[long]$Maximum){
        if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum){throw 'Live stone integer proof invalid.'}
    }
    function Flag($Value,[bool]$Expected){if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Live stone Boolean proof invalid.'}}
    Assert-HudStoneMode $Guest $false $true
    $proof=$Guest.lab_evidence.stone_bridge
    if($Guest.run -isnot [string] -or $Guest.run -cnotmatch '^[0-9a-f]{32}$' -or $Guest.result -cne 'input_completed' -or
       $proof.kind -cne 'minecome_hud_stone_bridge_v1' -or $proof.save -isnot [string] -or $proof.save -cnotmatch '^MineCome-HudStream-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or $proof.save -cne $Guest.save){throw 'Live stone preview does not belong to the owned HUD world.'}
    Integer $proof.schema 1 1;Integer $proof.session 1 ([long]::MaxValue)
    foreach($field in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged')){
        if($proof.$field -isnot [bool] -or -not $proof.$field){throw 'Live stone proof incomplete.'}
    }
    foreach($field in @('failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){
        if($proof.$field -isnot [bool] -or $proof.$field){throw 'Live stone preview did not finish cleanly.'}
    }
    $expected=@{request_count=2;accepted_dispatches=2;confirmed_actions=2;confirmed_places=1;confirmed_breaks=1;block_events_queued=2;cancelled_pending=0;unavailable_results=0;stale_results=0;busy_results=0;omitted_requests=0;omitted_confirmations=0}
    foreach($field in $expected.Keys){
        if(($proof.$field -isnot [int] -and $proof.$field -isnot [long]) -or $proof.$field -ne $expected[$field]){throw 'Live stone preview did not complete one place/break cycle.'}
    }
    $requests=@($proof.requests);$confirmations=@($proof.confirmations)
    if($requests.Count -ne 2 -or $confirmations.Count -ne 2){throw 'Live stone preview action records incomplete.'}
    $previousId=0L
    for($i=0;$i -lt 2;$i++){
        $request=$requests[$i];$confirmation=$confirmations[$i]
        Integer $request.id 1 9007199254740991
        if($request.id -le $previousId){throw 'Live stone request IDs must increase.'};$previousId=$request.id
        Integer $request.action ($i+1) ($i+1);Integer $request.result 1 1
        Integer $request.selected_slot 0 8;Integer $request.selected_count 0 ([int]::MaxValue)
        if($request.selected_item -isnot [string] -or $request.selected_item -cnotmatch '^minecraft:[a-z0-9_./-]+$'){throw 'Live stone selected item invalid.'}
        if($i -eq 0 -and ($request.selected_item -cne 'minecraft:stone' -or $request.selected_count -lt 1)){throw 'Live stone placement did not use the actual selected stone.'}
        Flag $request.result_queued $true;Flag $request.actions_enabled $true;Flag $request.screen_open $false
        if($request.gate.reason -cne 'permitted'){throw 'Live stone action was not permitted by the guest gate.'}
        Integer $request.gate.transport_result 0 0
        Integer $confirmation.id $request.id $request.id;Integer $confirmation.action $request.action $request.action
        Integer $confirmation.selected_slot $request.selected_slot $request.selected_slot;Integer $confirmation.selected_count $request.selected_count $request.selected_count
        if($confirmation.selected_item -cne $request.selected_item){throw 'Live stone confirmation item differs from dispatch.'}
        Flag $confirmation.client_and_server $true;Flag $confirmation.inventory_mutated $false
        Integer $confirmation.server_age_ms 0 250
    }
}
function Read-HudPreviewClientLog([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){return ''}
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        if($stream.Length -gt 8MB){throw 'Preview client log exceeded its bound.'}
        $reader=[IO.StreamReader]::new($stream)
        try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
    }finally{$stream.Dispose()}
}
function Assert-HudStoneFixture([object]$Guest,[object]$Native,[object]$Peer,[string]$Run){
    function Number($Value,[long]$Expected){if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -ne $Expected){throw 'Stone fixture numeric evidence mismatch.'}}
    function Flag($Value,[bool]$Expected){if($Value -isnot [bool] -or $Value -ne $Expected){throw 'Stone fixture Boolean evidence mismatch.'}}
    Assert-HudStoneMode $Guest $true
    if($Guest.run -cne $Run -or $Native.run -cne $Run -or $Peer.run -cne $Run -or $Guest.result -cne 'input_passed' -or $Native.result -cne 'passed' -or $Peer.result -cne 'passed'){throw 'Stone fixture result/run mismatch.'}
    Flag $Native.stone_fixture $true;Flag $Native.stone_fixture_verified $true;Number $Native.stone_steps_completed 6
    Number $Native.events_sent 8;Flag $Native.all_events_acknowledged $true
    Number $Guest.lab_evidence.input_events_applied 8;Number $Guest.lab_evidence.input_consumed_sequence 8
    $proof=$Guest.lab_evidence.stone_bridge
    Number $Peer.schema 1;Number $Peer.steps 6;Number $Peer.block_events 4
    if($Peer.peer_kind -cne 'standalone_protocol_fixture'){throw 'Stone fixture peer type mismatch.'}
    foreach($name in @('auth_verified','synthetic_host_pose','guest_socket_closed')){Flag $Peer.$name $true}
    foreach($name in @('kcd_compositing_verified','physical_input_verified')){Flag $Peer.$name $false}
    if(($Peer.received_poses -isnot [int] -and $Peer.received_poses -isnot [long]) -or $Peer.received_poses -lt 1){throw 'Stone fixture received no actual Minecraft poses.'}
    $cell=@($Peer.fixed_cell);if($cell.Count -ne 3){throw 'Stone fixture lacks its fixed target.'}
    $coordinates=@('x','y','z')
    for($i=0;$i -lt 3;$i++){
        $coordinate=$proof.target.($coordinates[$i]);if(($coordinate -isnot [int] -and $coordinate -isnot [long]) -or $coordinate -lt [int]::MinValue -or $coordinate -gt [int]::MaxValue){throw 'Stone target coordinate invalid.'}
        Number $cell[$i] $coordinate
    }
    if($proof.kind -cne 'minecome_hud_stone_bridge_v1' -or $proof.save -cne $Guest.save){throw 'Stone fixture did not use the owned HUD save.'}
    foreach($name in @('baseline_confirmed','closed','vanilla_dispatch_inventory_unchanged')){Flag $proof.$name $true}
    foreach($name in @('failed','pending','confirmed_cell_stone','inventory_mutated','camera_mutated','engine_mirroring_verified','visual_verified')){Flag $proof.$name $false}
    foreach($name in @('cancelled_pending','stale_results','busy_results','omitted_requests','omitted_confirmations')){Number $proof.$name 0}
    Number $proof.request_count 6;Number $proof.accepted_dispatches 4;Number $proof.unavailable_results 2
    Number $proof.confirmed_actions 4;Number $proof.confirmed_places 2;Number $proof.confirmed_breaks 2;Number $proof.block_events_queued 4
    $requests=@($proof.requests);$confirmations=@($proof.confirmations)
    if($requests.Count -ne 6 -or $confirmations.Count -ne 4){throw 'Stone fixture action records incomplete.'}
    $actions=@(1,2,1,1,1,2);$results=@(1,1,2,2,1,1);$slots=@(0,1,1,0,0,0)
    $reasons=@('permitted','permitted','selected_item_not_stone','screen_open','permitted','permitted')
    for($i=0;$i -lt 6;$i++){
        $request=$requests[$i];Number $request.id ($i+1);Number $request.action $actions[$i];Number $request.result $results[$i];Number $request.selected_slot $slots[$i]
        $expectedItem=if($slots[$i] -eq 0){'minecraft:stone'}else{'minecraft:dirt'}
        if($request.selected_item -cne $expectedItem){throw 'Stone fixture used a different selected item.'}
        Number $request.selected_count $(if($slots[$i] -eq 0){64}else{32})
        Flag $request.result_queued $true;Flag $request.actions_enabled $true;Flag $request.screen_open ($i -eq 3)
        if($request.gate.reason -cne $reasons[$i]){throw 'Stone request completed for a different reason.'}
        Number $request.gate.transport_result 0
    }
    $ids=@(1,2,5,6)
    for($i=0;$i -lt 4;$i++){
        $confirmation=$confirmations[$i];$request=$requests[$ids[$i]-1]
        Number $confirmation.id $ids[$i];Number $confirmation.action $request.action
        Number $confirmation.selected_slot $request.selected_slot;Number $confirmation.selected_count $request.selected_count
        if($confirmation.selected_item -cne $request.selected_item){throw 'Stone confirmation item differs from actual dispatch.'}
        Flag $confirmation.client_and_server $true;Flag $confirmation.inventory_mutated $false
        if(($confirmation.server_age_ms -isnot [int] -and $confirmation.server_age_ms -isnot [long]) -or $confirmation.server_age_ms -lt 0 -or $confirmation.server_age_ms -gt 250){throw 'Stone confirmation server observation stale.'}
    }
    $items=@('stone','dirt','cobblestone','oak_planks','stick','apple','torch','diamond','iron_pickaxe');$counts=@(64,32,16,8,3,2,12,1,1)
    foreach($side in @('final_client_slots','final_server_slots')){
        $inventory=@($Guest.lab_evidence.$side);if($inventory.Count -ne 9){throw 'Stone fixture final inventory incomplete.'}
        for($i=0;$i -lt 9;$i++){
            Number $inventory[$i].slot $i;Number $inventory[$i].count $counts[$i]
            if($inventory[$i].item -cne ('minecraft:'+$items[$i])){throw 'Stone actions changed the inventory.'}
        }
    }
}
function Assert-LiveMouseGuestProof([object]$Proof,[bool]$RequirePointer=$true){
    if($Proof.live_mouse -isnot [bool] -or $Proof.live_mouse -ne $true -or ($Proof.pointer_events_applied -isnot [long] -and $Proof.pointer_events_applied -isnot [int]) -or $Proof.pointer_events_applied -lt 0 -or ($RequirePointer -and $Proof.pointer_events_applied -eq 0) -or $Proof.pointer_events_applied -gt $Proof.input_events_applied){throw 'Live mouse needs valid successfully applied guest pointer evidence.'}
    $neutral=$Proof.pointer_adapter_after_cleanup
    foreach($field in @('held_buttons','pending_releases','active_button')){
        $expected=if($field -ceq 'active_button'){-1}else{0}
        if(($neutral.$field -isnot [long] -and $neutral.$field -isnot [int]) -or $neutral.$field -ne $expected){throw 'Live mouse guest pointer cleanup was not neutral.'}
    }
    return [long]$Proof.pointer_events_applied
}
function Assert-HudWindowCleanup([object]$Visibility,[object]$Hidden,[bool]$MouseMode,[bool]$Offscreen,[string]$SessionMode,[bool]$ClientExited,[int]$ClientExitCode){
    if($Visibility.PSObject.Properties.Name -contains 'policy' -and ($Visibility.policy -isnot [string] -or $Visibility.policy -cnotin @('restore_original_visibility','hidden_until_process_exit'))){throw 'Unknown owned-window cleanup policy.'}
    $hiddenExit=$Visibility.PSObject.Properties.Name -contains 'policy' -and $Visibility.policy -ceq 'hidden_until_process_exit'
    if($hiddenExit){
        if(-not $MouseMode -or -not $Offscreen -or $SessionMode -cne 'Live' -or -not $ClientExited -or $ClientExitCode -ne 0){throw 'Hidden terminal window requires an explicitly owned live mouse client that exited normally.'}
        foreach($field in @('hidden_for_exit','cleanup_succeeded','window_identity_verified','layout_runtime_restore_skipped','layout_options_restored')){
            if($Visibility.$field -isnot [bool] -or $Visibility.$field -ne $true){throw "Hidden terminal window proof missing: $field"}
        }
        foreach($field in @('actual_visible','focus_requested','show_with_focus_disabled','process_exit_observed')){
            if($Visibility.$field -isnot [bool] -or $Visibility.$field -ne $false){throw "Hidden terminal window proof invalid: $field"}
        }
        if($Hidden.hide_verified -isnot [bool] -or $Hidden.hide_verified -ne $true -or $Hidden.owned_window_handle -isnot [string] -or $Hidden.owned_window_handle -cnotmatch '^[1-9][0-9]{0,19}$' -or
           $Visibility.expected_window_handle -isnot [string] -or $Visibility.actual_window_handle -isnot [string] -or $Visibility.expected_window_handle -cne $Hidden.owned_window_handle -or $Visibility.actual_window_handle -cne $Hidden.owned_window_handle){throw 'Hidden terminal window identity differs from the owned hidden guest.'}
        if($Visibility.original_focus_on_show -isnot [bool] -or $Visibility.actual_focus_on_show -isnot [bool] -or $Visibility.original_focus_on_show -ne $Visibility.actual_focus_on_show){throw 'Owned window focus-on-show setting was not restored.'}
        if($Visibility.original_visible -isnot [bool] -or $Visibility.restored -isnot [bool] -or $Visibility.restored -ne (-not $Visibility.original_visible)){throw 'Hidden window receipt misstates original visibility restoration.'}
        return
    }
    if(($Visibility.PSObject.Properties.Name -contains 'hidden_for_exit' -and $Visibility.hidden_for_exit -ne $false) -or
       $Visibility.restored -ne $true -or $Visibility.original_visible -ne $Visibility.actual_visible -or $Visibility.original_focus_on_show -ne $Visibility.actual_focus_on_show -or $Visibility.focus_requested -ne $false){throw 'Owned Minecraft visibility was not restored without requesting focus.'}
}
function Start-Child([string]$Executable,[string[]]$Arguments){
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$Executable;$start.WorkingDirectory=$root
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($argument in $Arguments){$start.ArgumentList.Add($argument)}
    return [Diagnostics.Process]::Start($start)
}
$null=Assert-Unlinked $evidenceRoot
Assert-HudStoneConfiguration $Mode ([bool]$StoneFixture) ([bool]$StoneLive) ([bool]$LiveMouse) ([bool]$OffscreenPresentation) ([bool]$OffscreenTrial) ([bool]$HostGpuBudget) ([bool]$PointerFixture) ([bool]$DelayFixture) ([bool]$BackgroundTrial) ([bool]$HideHostHud) ([bool]$WorldClicks) ([bool]$SelectiveMouse) $SelectiveRevision
if($LiveMouse -and ($Mode -ne 'Live' -or -not $HostGpuBudget -or -not $OffscreenPresentation -or $PointerFixture -or $DelayFixture -or $BackgroundTrial -or $OffscreenTrial)){throw 'LiveMouse requires Live mode, HostGpuBudget and OffscreenPresentation, with all fixture modes disabled.'}
if($DelayFixture -and $Mode -ne 'Fixture'){throw 'Controlled input delays require the standalone fixture.'}
if($PointerFixture -and ($Mode -ne 'Fixture' -or $DelayFixture -or $BackgroundTrial)){throw 'PointerFixture requires standalone Fixture mode without delay/background trials.'}
if($BackgroundTrial -and ($Mode -ne 'Fixture' -or $DelayFixture)){throw 'Background timing requires a standalone fixture without synthetic delays.'}
if($OffscreenTrial -and $Mode -ne 'Fixture'){throw 'Offscreen timing requires a standalone fixture.'}
if($OffscreenTrial){$OffscreenPresentation=$true}
if($HostGpuBudget -and ($Mode -ne 'Live' -or -not $OffscreenPresentation)){throw 'HostGpuBudget requires Live mode with OffscreenPresentation.'}
if($HideHostHud -and $Mode -ne 'Live'){throw 'HideHostHud requires the controlled Live lab.'}
if($OffscreenPresentation -and ($BackgroundTrial -or $DelayFixture)){throw 'Offscreen presentation cannot be combined with the baseline comparison or deliberate delays.'}
if($OffscreenPresentation -and $Mode -eq 'Fixture' -and -not $OffscreenTrial){throw 'Use OffscreenTrial to verify standalone offscreen presentation.'}
if($Width -lt 320*$GuiScale -or $Height -lt 240*$GuiScale){throw 'UI layout needs at least320x240 logical pixels.'}
$inventory=Read-Receipt (Join-Path $root 'runtime/environment.json')
if(-not $JavaHome){
    foreach($candidate in @($inventory.java.jdks | ForEach-Object home)){
        if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){$JavaHome=$candidate;break}
    }
}
if(-not $JavaHome){throw 'An installed tested JDK21 or24 is required.'}
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if(-not(Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")'){throw 'An installed tested JDK21 or24 is required.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {$_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')})
if($clients.Count){throw 'Existing MineCome Minecraft client preserved.'}
$fixtureHash=$null;$context=$null
if($Mode -eq 'Fixture'){
    $null=Assert-Unlinked $fixturePath
    if(-not(Test-Path -LiteralPath $fixturePath -PathType Leaf)){throw 'Build the separate HUD input fixture first.'}
    $fixtureHash=(Get-FileHash -LiteralPath $fixturePath).Hash.ToLowerInvariant()
    if($StoneFixture){$stoneNode=Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source}
}else{
    . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
    if($HostGpuBudget){. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')}
    if($HideHostHud){. (Join-Path $PSScriptRoot 'HudVisibility.ps1')}
    if($StoneLive){. (Join-Path $PSScriptRoot 'HudStoneRelay.ps1')}
    if($WorldClicks){. (Join-Path $PSScriptRoot 'HudWorldClicks.ps1')}
    $context=Get-MineComeProbeContext
    if($StoneLive){$null=Test-MineComeHudStoneRelayPreflight $context}
    if(-not $BundleDirectory){$BundleDirectory=Join-Path $root $(if($SelectiveMouse -and $SelectiveRevision -eq 3){'runtime/hud-compositor-selective-r3'}elseif($SelectiveMouse -and $SelectiveRevision -eq 2){'runtime/hud-compositor-selective-r2'}elseif($SelectiveMouse){'runtime/hud-compositor-selective'}elseif($WorldClicks){'runtime/hud-compositor-world'}elseif($LiveMouse){'runtime/hud-compositor-mouse'}else{'runtime/hud-compositor-input-waitfix'})}
    & (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -LiveMouse:$LiveMouse -StoneLive:$StoneLive -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision -BundleDirectory $BundleDirectory -OffscreenPresentation:$OffscreenPresentation -PreflightOnly
}
if($PreflightOnly){Write-Output "HUD_INPUT_PREFLIGHT_PASS mode=$Mode no_process_started=true";return}
$run=[guid]::NewGuid().ToString('N')
$directory=Assert-Unlinked (Join-Path $evidenceRoot ('hud-input-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
if(Test-Path -LiteralPath $directory){throw 'New UI evidence directory required.'}
[IO.Directory]::CreateDirectory($directory)|Out-Null
$expires=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+180000
$readyPath=Join-Path $directory 'capture/stream-ready.json'
$fixtureReady=Join-Path $directory 'fixture-ready.json'
$fixtureResult=Join-Path $directory 'fixture-result.json'
$fixture=$null;$client=$null;$producer=$null;$armEvidence=$null;$selectiveArmVerified=$false;$failure=$null;$passed=$false;$targetPid=0;$targetStart='';$guest=$null
$producerExitObserved=$false;$producerExitCode=$null
$stonePeer=$null;$stoneReady=$null;$stonePeerResult=$null
$stoneRelay=$null;$stoneRelayEvidence=$null
$worldClickState=$null;$worldClickEvidence=$null;$relayHealthCheckedAt=0L
$stonePreview=[pscustomobject]@{Stage=0;ArmedAtMs=0L;PlaceAtMs=0L;ConfirmedAtMs=0L;PlaceRequestId='';Save=''}
$bodyPassed=$false;$hostBudgetSession=$null;$hostBudgetEvidence=$null
$liveMouseGuestVerified=$false;$pointerEventsApplied=0
$hostHudSession=$null;$hostHudEvidence=$null
try{
    if($StoneLive){
        $stoneRelay=New-MineComeHudStoneRelay $context $directory $run $expires
        Start-MineComeHudStoneRelay $stoneRelay
    }
    if($StoneFixture){
        $stonePeer=Start-Child $stoneNode @((Join-Path $root 'tests/hud_stone_bridge_fixture.mjs'),$directory,$run,[string]$expires)
        $stoneReadyPath=Join-Path $directory 'stone-peer-ready.json';$stoneDeadline=[DateTime]::UtcNow.AddSeconds(5)
        while(-not(Test-Path -LiteralPath $stoneReadyPath)){
            if($stonePeer.HasExited -or [DateTime]::UtcNow -ge $stoneDeadline){throw 'Standalone stone peer did not become ready.'}
            Start-Sleep -Milliseconds 50
        }
        $stoneReady=Read-Receipt $stoneReadyPath
        if($stoneReady.schema -ne 1 -or $stoneReady.run -cne $run -or $stoneReady.pid -ne $stonePeer.Id -or $stoneReady.expires_utc_ms -ne $expires -or $stoneReady.peer_kind -cne 'standalone_protocol_fixture' -or $stoneReady.port -lt 1 -or $stoneReady.port -gt 65535){throw 'Standalone stone peer identity mismatch.'}
        $null=Assert-Unlinked (Join-Path $directory 'stone-bridge.token')
    }
    if($Mode -eq 'Fixture'){
        if((Get-FileHash -LiteralPath $fixturePath).Hash -ine $fixtureHash){throw 'Fixture changed before launch.'}
        $fixtureArguments=@('--run',$run,'--expires',[string]$expires,'--ready-output',$fixtureReady,'--guest-ready',$readyPath,'--output',$fixtureResult)
        if($DelayFixture){$fixtureArguments+=@('--prearm-delay-ms','1000')}
        if($BackgroundTrial){$fixtureArguments+=@('--background-trial','1')}
        if($OffscreenTrial){$fixtureArguments+=@('--offscreen-trial','1')}
        if($PointerFixture){$fixtureArguments+=@('--pointer-fixture','1')}
        if($StoneFixture){$fixtureArguments+=@('--stone-fixture','1')}
        $fixture=Start-Child $fixturePath $fixtureArguments
        $readyDeadline=[DateTime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath $fixtureReady)){
            if($fixture.HasExited -or [DateTime]::UtcNow -ge $readyDeadline){throw 'Fixture did not publish readiness.'}
            Start-Sleep -Milliseconds 50
        }
        $nativeReady=Read-Receipt $fixtureReady
        if($nativeReady.schema -ne 1 -or $nativeReady.kind -cne 'minecome_hud_input_fixture_ready_v1' -or $nativeReady.run -cne $run -or $nativeReady.host_pid -ne $fixture.Id -or [string]$nativeReady.host_start_filetime -cne $fixture.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -or $nativeReady.expires_utc_ms -ne $expires){throw 'Fixture process readiness mismatch.'}
        if($PointerFixture -and ($nativeReady.PSObject.Properties.Name -notcontains 'pointer_fixture' -or $nativeReady.pointer_fixture -isnot [bool] -or -not $nativeReady.pointer_fixture)){throw 'Native pointer fixture readiness mismatch.'}
        if($StoneFixture -and ($nativeReady.PSObject.Properties.Name -notcontains 'stone_fixture' -or $nativeReady.stone_fixture -isnot [bool] -or -not $nativeReady.stone_fixture)){throw 'Native stone fixture readiness mismatch.'}
        $targetPid=$fixture.Id;$targetStart=[string]$nativeReady.host_start_filetime
    }else{$targetPid=$context.GamePid;$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString()}
    $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-TargetPid',[string]$targetPid,'-TargetStart',$targetStart,'-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-Width',[string]$Width,'-Height',[string]$Height,'-GuiScale',[string]$GuiScale,'-InputMode')
    if($Mode -eq 'Fixture'){$arguments+='-InputFixture'}
    if($LiveMouse){$arguments+='-LiveMouse'}
    if($PointerFixture){$arguments+='-InputPointerFixture'}
    if($StoneFixture){$arguments+=@('-StoneFixture','-StoneTokenFile',(Join-Path $directory 'stone-bridge.token'),'-StonePort',[string]$stoneReady.port)}
    if($StoneLive){$arguments+=@('-StoneLive','-StoneTokenFile',$stoneRelay.TokenFile,'-StonePort',[string]$stoneRelay.Port)}
    if($DelayFixture){$arguments+='-InputDelayFixture'}
    if($BackgroundTrial){$arguments+='-InputBackgroundTrial'}
    if($OffscreenPresentation){$arguments+='-OffscreenPresentation'}
    if($OffscreenTrial){$arguments+='-InputOffscreenTrial'}
    $client=Start-Child (Join-Path $PSHOME 'pwsh.exe') $arguments
    Write-Output "HUD_INPUT_START mode=$Mode run=$run evidence=$directory"
    while(-not(Test-Path -LiteralPath $readyPath)){
        if($client.HasExited){throw "Minecraft exited before UI readiness: $($client.ExitCode)"}
        if($fixture -and $fixture.HasExited){throw 'Fixture exited before Minecraft readiness.'}
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires-45000){throw 'UI startup deadline reached.'}
        if($Mode -eq 'Live'){Assert-MineComeProbeContext $context}
        Start-Sleep -Milliseconds 100
    }
    $ready=Read-Receipt $readyPath
    Assert-HudStoneMode $ready ([bool]$StoneFixture) ([bool]$StoneLive)
    if($StoneLive){$stonePreview.Save=[string]$ready.save}
    Assert-LiveMouseReceipt $ready ([bool]$LiveMouse)
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_fixture' -or $ready.ui_input_fixture -isnot [bool] -or $ready.ui_input_fixture -ne ($Mode -eq 'Fixture')){throw 'UI producer fixture/live mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_pointer_fixture' -or $ready.ui_input_pointer_fixture -isnot [bool] -or $ready.ui_input_pointer_fixture -ne [bool]$PointerFixture){throw 'UI producer pointer-fixture mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_delay_fixture' -or $ready.ui_input_delay_fixture -isnot [bool] -or $ready.ui_input_delay_fixture -ne [bool]$DelayFixture){throw 'UI producer delay-fixture mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_background_trial' -or $ready.ui_input_background_trial -isnot [bool] -or $ready.ui_input_background_trial -ne [bool]$BackgroundTrial){throw 'UI producer background-trial mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_offscreen_trial' -or $ready.ui_input_offscreen_trial -isnot [bool] -or $ready.ui_input_offscreen_trial -ne [bool]$OffscreenTrial){throw 'UI producer offscreen-trial mode mismatch.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_offscreen_presentation' -or $ready.ui_input_offscreen_presentation -isnot [bool] -or $ready.ui_input_offscreen_presentation -ne [bool]$OffscreenPresentation){throw 'UI producer offscreen-presentation mode mismatch.'}
    if($ready.schema -ne 1 -or $ready.run -cne $run -or $ready.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or $ready.ui_input_protocol -ne 1 -or $ready.target_pid -ne $targetPid -or [string]$ready.target_start_filetime -cne $targetStart -or $ready.expires_utc_ms -ne $expires){throw 'Genuine UI producer readiness mismatch.'}
    $producer=Get-Process -Id $ready.producer_pid
    # Retain the actual Java kernel process handle through shutdown; the wrapper
    # finishing alone cannot prove that a deliberately hidden guest has exited.
    $null=$producer.Handle
    if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne [string]$ready.producer_start_filetime -or -not $producer.Path.Equals((Join-Path $JavaHome 'bin/java.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'Actual Minecraft process identity mismatch.'}
    if($HostGpuBudget){
        # Retain the cleanup handle before Begin can mutate the already-running host.
        # Guest startup consumes none of this unchanged 120-second engine lease.
        $hostBudgetSession=New-MineComeHudGpuBudget $context
        Start-MineComeHudGpuBudget $hostBudgetSession
        Write-Output "HUD_GPU_BUDGET_APPLIED run=$($hostBudgetSession.Probe.Run) original_fps=$($hostBudgetSession.Applied.original_fps) temporary_fps=60 expiry_ms=120000"
    }
    if($HideHostHud){
        # Whole-HUD visibility is opt-in and bounded to this controlled lab.
        # Preserve the cleanup handle before any engine-side write can occur.
        $hostHudSession=New-MineComeHudVisibility $context
        Start-MineComeHudVisibility $hostHudSession
        Write-Output "HUD_HOST_VISIBILITY_APPLIED run=$($hostHudSession.Probe.Run) original_hud=$($hostHudSession.Applied.original_hud) temporary_hud=0 expiry_ms=120000"
    }
    if($WorldClicks){$worldClickState=New-MineComeHudWorldClicks $context (Join-Path ([IO.Path]::GetDirectoryName($context.GamePath)) 'ReShade.log') $run}
    if($Mode -eq 'Live'){
        $armEvidence=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -LiveMouse:$LiveMouse -StoneLive:$StoneLive -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision -BundleDirectory $BundleDirectory -OffscreenPresentation:$OffscreenPresentation -ReadyManifest $readyPath
        Assert-HudSelectiveArm $armEvidence ([bool]$SelectiveMouse) $SelectiveRevision
        $selectiveArmVerified=[bool]$SelectiveMouse
    }
    Write-Output "HUD_INPUT_READY mode=$Mode run=$run"
    while(-not $client.HasExited -or -not $producer.HasExited -or ($fixture -and -not $fixture.HasExited) -or ($stonePeer -and -not $stonePeer.HasExited)){
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires+15000){throw 'UI shutdown deadline reached; any remaining processes are preserved.'}
        if($stoneRelay -and -not $producer.HasExited){
            $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            if(-not $WorldClicks -or $now-$relayHealthCheckedAt -ge 200){
                Assert-MineComeHudStoneRelay $stoneRelay;$relayHealthCheckedAt=$now
            }
            # Each physical dispatch repeats exact relay checks itself. Polling
            # the edge log more frequently need not reread full relay evidence.
            if($WorldClicks){Invoke-MineComeHudWorldClicks $worldClickState $stoneRelay}
            else{
                $enginePlaced=Test-HudStonePreviewEnginePlace $stoneRelay.Native $stonePreview.PlaceRequestId
                $action=Get-HudStonePreviewAction $stonePreview (Read-HudPreviewClientLog (Join-Path $directory 'client.log')) $run ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $enginePlaced
                if($action -ne 0){
                    $intent=Send-MineComeHudStoneIntent $stoneRelay -Action $action
                    if($action -eq 1){$stonePreview.Stage=1;$stonePreview.PlaceAtMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$stonePreview.PlaceRequestId=[string]$intent.request_id}
                    else{$stonePreview.Stage=2}
                }
            }
        }
        Start-Sleep -Milliseconds $(if($WorldClicks){20}else{200})
    }
    $producerExitObserved=$producer.HasExited;$producerExitCode=$producer.ExitCode
    if($client.ExitCode -ne 0 -or $producerExitCode -ne 0 -or ($fixture -and $fixture.ExitCode -ne 0)){throw 'UI client, actual Java producer or native fixture reported failure.'}
    $guest=Read-Receipt (Join-Path $directory 'capture/stream-result.json')
    Assert-HudStoneMode $guest ([bool]$StoneFixture) ([bool]$StoneLive)
    Assert-LiveMouseReceipt $guest ([bool]$LiveMouse)
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_fixture' -or $guest.ui_input_fixture -isnot [bool] -or $guest.ui_input_fixture -ne ($Mode -eq 'Fixture')){throw 'UI result fixture/live mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_pointer_fixture' -or $guest.ui_input_pointer_fixture -isnot [bool] -or $guest.ui_input_pointer_fixture -ne [bool]$PointerFixture){throw 'UI result pointer-fixture mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_delay_fixture' -or $guest.ui_input_delay_fixture -isnot [bool] -or $guest.ui_input_delay_fixture -ne [bool]$DelayFixture){throw 'UI result delay-fixture mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_background_trial' -or $guest.ui_input_background_trial -isnot [bool] -or $guest.ui_input_background_trial -ne [bool]$BackgroundTrial){throw 'UI result background-trial mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_offscreen_trial' -or $guest.ui_input_offscreen_trial -isnot [bool] -or $guest.ui_input_offscreen_trial -ne [bool]$OffscreenTrial){throw 'UI result offscreen-trial mode mismatch.'}
    if($guest.PSObject.Properties.Name -notcontains 'ui_input_offscreen_presentation' -or $guest.ui_input_offscreen_presentation -isnot [bool] -or $guest.ui_input_offscreen_presentation -ne [bool]$OffscreenPresentation){throw 'UI result offscreen-presentation mode mismatch.'}
    if($guest.run -cne $run -or $guest.ui_input_protocol -ne 1 -or $guest.published_frames -lt 1 -or $guest.closed_published -ne $true -or $guest.mapping_unmapped -ne $true -or $guest.mapping_handle_closed -ne $true -or $guest.mutex_handle_closed -ne $true){throw 'UI stream publication/closure evidence missing.'}
    if($guest.lab_evidence.input_handles_closed -ne $true -or $guest.lab_evidence.closed_acknowledgement_published -ne $true){throw 'UI input acknowledgement/handle closure evidence missing.'}
    $receiptIo=$guest.publication_timing.evidence_io
    if($receiptIo.stopped -ne $true -or $receiptIo.queued -ne 0 -or $receiptIo.completed -ne $receiptIo.submitted){throw 'UI receipt writer did not finish its bounded queue.'}
    if($OffscreenPresentation){
        $presentation=$guest.lab_evidence.offscreen_presentation
        if($presentation.enabled -ne $true -or $presentation.skipped_swaps -lt 1 -or $presentation.gl_flushes -ne $presentation.skipped_swaps -or $presentation.vanilla_flip_frame_preserved -ne $true){throw 'Offscreen presentation was not exercised with real GL submission.'}
        $restored=$guest.lab_evidence.presentation_restoration
        if($restored.restored -ne $true -or $restored.option_vsync -ne $restored.original_vsync -or $restored.actual_window_vsync -ne $restored.original_window_vsync -or $restored.option_max_fps -ne $restored.original_max_fps -or $restored.actual_window_max_fps -ne $restored.original_window_max_fps -or $restored.explicit_options_file_write -ne $false){throw 'Offscreen presentation settings were not restored.'}
        if($presentation.desktop_blits_skipped -lt 1 -or $presentation.desktop_clears_skipped -lt 1 -or $presentation.active_guest_fps_limit -ne 30 -or $presentation.frame_limit_applied -ne $true){throw 'Owned offscreen GPU workload reduction was not applied.'}
        $hidden=$guest.lab_evidence.offscreen_window
        $visibility=$guest.lab_evidence.window_restoration
        if($hidden.hide_requested -ne $true -or $hidden.hide_verified -ne $true -or $hidden.visible_after_hide -ne $false -or $hidden.hidden_unfocused_ticks -lt 1){throw 'Owned Minecraft window was not verified hidden and unfocused.'}
        if($hidden.focus_authority -cne 'minecraft_window_focus_callback' -or $hidden.focus_ready_observed -ne $true -or $hidden.client_focused_when_ready -ne $false -or $hidden.focus_ready_utc_ms -le 0){throw 'Hidden Minecraft readiness lacks genuine client focus evidence.'}
        if($hidden.client_focused_before_hide -eq $true -and $hidden.focus_loss_callbacks_after_hide -lt 1){throw 'Initially focused Minecraft did not receive a real focus-loss callback.'}
        Assert-HudWindowCleanup $visibility $hidden ([bool]$LiveMouse) ([bool]$OffscreenPresentation) $Mode $producerExitObserved $producerExitCode
    }
    if($Mode -eq 'Fixture'){
        $native=Read-Receipt $fixtureResult
        if($native.run -cne $run -or $native.kind -cne 'minecome_hud_input_fixture_result_v1' -or $native.result -cne 'passed' -or $guest.result -cne 'input_passed' -or $guest.lab_evidence.input_fixture -ne $true -or $guest.lab_evidence.inventory_opened -ne $true -or $guest.lab_evidence.inventory_closed -ne $true -or (-not $StoneFixture -and $guest.lab_evidence.selected_nine_verified -ne $true)){throw 'Real vanilla UI fixture evidence incomplete.'}
        $expectedEvents=if($StoneFixture){8}elseif($PointerFixture){43}else{31}
        if($PointerFixture){
            if($native.pointer_fixture -isnot [bool] -or $native.pointer_fixture -ne $true -or $native.pointer_gestures_verified -isnot [bool] -or $native.pointer_gestures_verified -ne $true -or $guest.lab_evidence.pointer_fixture -isnot [bool] -or $guest.lab_evidence.pointer_fixture -ne $true){throw 'Pointer fixture confirmation missing.'}
            $pointer=$guest.lab_evidence.pointer_evidence
            foreach($name in @('completed','right_split_verified','drag_distribution_verified','scroll_changed_verified','scroll_restored_verified','held_close_release_verified','reopened_screen_verified','late_release_consumed_verified','cursor_empty','server_inventory_verified')){
                if($pointer.PSObject.Properties.Name -notcontains $name -or $pointer.$name -isnot [bool] -or $pointer.$name -ne $true){throw "Real pointer evidence missing: $name"}
            }
            if($pointer.expected_events -ne $expectedEvents -or $native.events_sent -ne $expectedEvents -or $native.pointer_phase_receipts -ne 11 -or @($pointer.stages).Count -ne 11 -or $guest.lab_evidence.input_events_applied -ne $expectedEvents -or $guest.lab_evidence.input_consumed_sequence -ne $expectedEvents){throw 'Pointer gesture sequence did not complete exactly.'}
        }elseif($StoneFixture){
            if($stonePeer.ExitCode -ne 0){throw 'Standalone stone protocol peer reported failure.'}
            $stonePeerResult=Read-Receipt (Join-Path $directory 'stone-peer-result.json')
            Assert-HudStoneFixture $guest $native $stonePeerResult $run
        }elseif($guest.lab_evidence.server_swap_verified -ne $true){throw 'Real vanilla item-swap evidence missing.'}
        if($DelayFixture -and ($native.prearm_delay_fixture -ne $true -or $native.max_prearm_ack_age_ms -le 250 -or $native.prearm_recoveries -lt 1)){throw 'Controlled prearm delay/recovery was not observed.'}
        if($DelayFixture -and ($guest.lab_evidence.input_delay_fixture -ne $true -or $guest.lab_evidence.withheld_ready_ack_ticks -lt 1 -or $guest.lab_evidence.prearm_ack_delay_ms -le 250 -or $guest.lab_evidence.closed_ack_delay_ms -le 250)){throw 'Actual client-tick startup/closure delays were not observed.'}
        if($BackgroundTrial -and ($native.background_trial -ne $true -or $native.background_trial_completed -ne $true -or $native.background_trial_receipt -cne 'capture/background-trial-ready.json')){throw 'Actual background presentation phases were not completed.'}
        if($OffscreenTrial -and ($native.offscreen_trial -ne $true -or $native.offscreen_trial_completed -ne $true -or $native.offscreen_trial_receipt -cne 'capture/offscreen-trial-ready.json' -or $native.unfocused_events_verified -ne $true)){throw 'Actual unfocused offscreen timing and vanilla input proof missing.'}
        if($OffscreenTrial){
            $trial=$guest.lab_evidence.offscreen_trial
            $trialEvents=$guest.lab_evidence.offscreen_trial_events
            if($trial.completed -ne $true -or $trial.presentation_suppressed -ne $true -or $trial.duration_ms -lt 12000 -or $trial.focused_ticks -ne 0 -or $trial.unfocused_ticks -lt 1 -or $trial.skipped_swaps -lt 1 -or $guest.lab_evidence.render_timing.sampler_stopped -ne $true){throw 'Actual offscreen background observation or worker cleanup missing.'}
            if($trial.window_max_fps -ne 30){throw 'Owned offscreen rendering cap was not applied.'}
            if($trial.window_visible -ne $false -or $trial.window_client_focused -ne $false -or $trial.focus_authority -cne 'minecraft_window_focus_callback' -or $trial.framebuffer_size_preserved -ne $true){throw 'Hidden Minecraft framebuffer was not preserved.'}
            if($hidden.hidden_unfocused_events_applied -ne $expectedEvents -or $hidden.visible_events_applied -ne 0 -or $hidden.focused_events_applied -ne 0){throw 'UI events were not all applied in the hidden unfocused guest.'}
            if($trialEvents.unfocused_events_applied -ne $expectedEvents -or $trialEvents.focused_events_applied -ne 0 -or $trialEvents.focus_interruptions -ne 0){throw 'UI events were not all applied while unfocused.'}
        }
        if($BackgroundTrial){
            $trial=$guest.lab_evidence.background_trial
            $restored=$guest.lab_evidence.presentation_restoration
            $phases=@($trial.phases)
            if($trial.completed -ne $true -or $phases.Count -ne 2 -or $guest.lab_evidence.render_timing.sampler_stopped -ne $true){throw 'Background timing completion/worker cleanup evidence missing.'}
            for($phaseIndex=0;$phaseIndex -lt 2;$phaseIndex++){
                $phase=$phases[$phaseIndex]
                $expectedName=if($phaseIndex -eq 0){'baseline'}else{'trial'}
                if($phase.name -cne $expectedName -or $phase.duration_ms -lt 12000 -or $phase.focused_ticks -ne 0 -or $phase.unfocused_ticks -lt 1){throw 'Contiguous unfocused background phase evidence missing.'}
            }
            if($phases[1].vsync -ne $false -or $phases[1].max_fps -ne 60){throw 'Background trial settings mismatch.'}
            if($restored.restored -ne $true -or $restored.original_vsync -ne $phases[0].vsync -or $restored.original_max_fps -ne $phases[0].max_fps -or $restored.option_vsync -ne $restored.original_vsync -or $restored.actual_window_vsync -ne $restored.original_vsync -or $restored.option_max_fps -ne $restored.original_max_fps -or $restored.actual_window_max_fps -ne $restored.original_max_fps -or $restored.explicit_options_file_write -ne $false){throw 'Actual Minecraft presentation settings were not restored.'}
        }
    }else{
        if($guest.result -cne 'input_completed'){throw 'Live UI session did not complete cleanly.'}
        if($WorldClicks){Assert-HudWorldClickGuest $guest}
        elseif($StoneLive){Assert-HudStoneLivePreview $guest}
        if($LiveMouse){
            $pointerEventsApplied=Assert-LiveMouseGuestProof $guest.lab_evidence (-not [bool]$StoneLive)
            $liveMouseGuestVerified=$pointerEventsApplied -gt 0
        }
        Assert-HudLiveArming $guest.lab_evidence ([bool]$WorldClicks)
        Assert-MineComeProbeContext $context
    }
    $bodyPassed=$true;$passed=$true
}catch{$failure=$_.Exception.Message}
finally{
    try{
        if($stoneRelay){
            try{
                Stop-MineComeHudStoneRelay $stoneRelay
                if($bodyPassed){Assert-MineComeHudStoneRelayGuest $stoneRelay $guest}
                if($bodyPassed -and $WorldClicks){Assert-MineComeHudWorldClicks $worldClickState $stoneRelay}
                $stoneRelayEvidence=Get-MineComeHudStoneRelayEvidence $stoneRelay
                if($stoneRelayEvidence.failure){throw $stoneRelayEvidence.failure}
            }catch{
                $passed=$false;if(-not $failure){$failure=$_.Exception.Message}
                try{$stoneRelayEvidence=Get-MineComeHudStoneRelayEvidence $stoneRelay}catch{$stoneRelayEvidence=@{failure=$_.Exception.Message;engine_mirroring_verified=$false;cleanup_verified=$false}}
            }
        }
        if($worldClickState){
            try{$worldClickEvidence=Get-MineComeHudWorldClickEvidence $worldClickState $stoneRelay}
            catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}
        }
        if($StoneLive -and -not $stoneRelay){$passed=$false}
        if($hostHudSession){
            try{
                try{Stop-MineComeHudVisibility $hostHudSession}catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}
                $hostHudEvidence=Get-MineComeHudVisibilityEvidence $hostHudSession
                if(-not $hostHudSession.VisibilityValid -or $hostHudSession.Failure){
                    $passed=$false
                    if(-not $failure){$failure=if($hostHudSession.Failure){$hostHudSession.Failure}else{'Temporary host HUD visibility was not verified through restoration.'}}
                }
            }catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}
        }
        if($HideHostHud -and -not $hostHudSession){$passed=$false}
        if($hostBudgetSession){
            try{Stop-MineComeHudGpuBudget $hostBudgetSession}catch{$passed=$false;if(-not $failure){$failure=$_.Exception.Message}}
            $hostBudgetEvidence=Get-MineComeHudGpuBudgetEvidence $hostBudgetSession
            if(-not $hostBudgetSession.BudgetValid -or $hostBudgetSession.Failure){
                $passed=$false
                if(-not $failure){$failure=if($hostBudgetSession.Failure){$hostBudgetSession.Failure}else{'Temporary host GPU budget was not verified through restoration.'}}
            }
        }
        if($HostGpuBudget -and -not $hostBudgetSession){$passed=$false}
        [ordered]@{schema=1;kind='minecome_hud_input_controller_v1';run=$run;mode=$Mode;stone_fixture=[bool]$StoneFixture;stone_live=[bool]$StoneLive;world_clicks_requested=[bool]$WorldClicks;world_clicks=$worldClickEvidence;selective_mouse_requested=[bool]$SelectiveMouse;selective_mouse_enabled=$selectiveArmVerified;selective_revision_requested=$(if($SelectiveMouse){$SelectiveRevision}else{0});stone_live_preview=$(if($WorldClicks){$null}else{$stonePreview});stone_relay=$stoneRelayEvidence;stone_protocol_peer=$stonePeerResult;pointer_fixture=[bool]$PointerFixture;delay_fixture=[bool]$DelayFixture;background_trial=[bool]$BackgroundTrial;offscreen_presentation=[bool]$OffscreenPresentation;offscreen_trial=[bool]$OffscreenTrial;host_gpu_budget_requested=[bool]$HostGpuBudget;host_gpu_budget=$hostBudgetEvidence;host_hud_hidden_requested=[bool]$HideHostHud;host_hud_visibility=$hostHudEvidence;body_passed=$bodyPassed;result=$(if($passed){'passed'}else{'failed'});failure=$failure;evidence=$directory;target_pid=$targetPid;target_start_filetime=$targetStart;fixture_sha256=$fixtureHash;compositor_armed=[bool]$armEvidence;width=$Width;height=$Height;gui_scale=$GuiScale;kcd_launched=$false;kcd_stopped=$false;host_input_exclusivity_verified=$false;live_mouse_requested=[bool]$LiveMouse;live_mouse_enabled=[bool]($LiveMouse -and $armEvidence);live_mouse_guest_verified=$liveMouseGuestVerified;live_mouse_guest_pass=[bool]($LiveMouse -and $liveMouseGuestVerified -and $passed);pointer_events_applied=$pointerEventsApplied;live_mouse_visual_verified=$false;producer_exit_observed=$producerExitObserved;producer_exit_code=$producerExitCode;created_utc_ms=$expires-180000;expires_utc_ms=$expires} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    }finally{
        if($stonePeer){
            if(-not $stonePeer.HasExited){[IO.File]::WriteAllText((Join-Path $directory 'stone-peer-stop.request'),'Controller cleanup');$null=$stonePeer.WaitForExit(3000)}
            $stonePeer.Dispose()
        }
        if($stoneRelay -and $stoneRelay.Process){$stoneRelay.Process.Dispose()}
        if($producer){$producer.Dispose()};if($client){$client.Dispose()};if($fixture){$fixture.Dispose()}
    }
}
if(-not $passed){throw $(if($failure){$failure}else{'UI session did not pass.'})}
Write-Output "HUD_INPUT_COMPLETED mode=$Mode run=$run actual_minecraft=true host_input_exclusivity_verified=false"
