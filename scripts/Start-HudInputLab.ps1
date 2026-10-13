#Requires -Version 7.3
# Original bounded vanilla UI control lab. Fixture mode never operates KCD2.
# Live mode arms an already-running, separately installed matching input profile.
[CmdletBinding()]
param(
    [ValidateSet('Fixture','Live')][string]$Mode='Fixture',
    [string]$JavaHome,[string]$BundleDirectory,[switch]$PreflightOnly,[switch]$DelayFixture,[switch]$BackgroundTrial,[switch]$OffscreenPresentation,[switch]$OffscreenTrial,[switch]$HostGpuBudget,[switch]$HideHostHud,[switch]$PointerFixture,[switch]$LiveMouse,
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
function Assert-LiveMouseGuestProof([object]$Proof){
    if($Proof.live_mouse -isnot [bool] -or $Proof.live_mouse -ne $true -or ($Proof.pointer_events_applied -isnot [long] -and $Proof.pointer_events_applied -isnot [int]) -or $Proof.pointer_events_applied -le 0 -or $Proof.pointer_events_applied -gt $Proof.input_events_applied){throw 'Live mouse needs actual successfully applied guest pointer events.'}
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
}else{
    . (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
    if($HostGpuBudget){. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')}
    if($HideHostHud){. (Join-Path $PSScriptRoot 'HudVisibility.ps1')}
    $context=Get-MineComeProbeContext
    if(-not $BundleDirectory){$BundleDirectory=Join-Path $root $(if($LiveMouse){'runtime/hud-compositor-mouse'}else{'runtime/hud-compositor-input-waitfix'})}
    & (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -LiveMouse:$LiveMouse -BundleDirectory $BundleDirectory -OffscreenPresentation:$OffscreenPresentation -PreflightOnly
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
$fixture=$null;$client=$null;$producer=$null;$armEvidence=$null;$failure=$null;$passed=$false;$targetPid=0;$targetStart='';$guest=$null
$producerExitObserved=$false;$producerExitCode=$null
$bodyPassed=$false;$hostBudgetSession=$null;$hostBudgetEvidence=$null
$liveMouseGuestVerified=$false;$pointerEventsApplied=0
$hostHudSession=$null;$hostHudEvidence=$null
try{
    if($Mode -eq 'Fixture'){
        if((Get-FileHash -LiteralPath $fixturePath).Hash -ine $fixtureHash){throw 'Fixture changed before launch.'}
        $fixtureArguments=@('--run',$run,'--expires',[string]$expires,'--ready-output',$fixtureReady,'--guest-ready',$readyPath,'--output',$fixtureResult)
        if($DelayFixture){$fixtureArguments+=@('--prearm-delay-ms','1000')}
        if($BackgroundTrial){$fixtureArguments+=@('--background-trial','1')}
        if($OffscreenTrial){$fixtureArguments+=@('--offscreen-trial','1')}
        if($PointerFixture){$fixtureArguments+=@('--pointer-fixture','1')}
        $fixture=Start-Child $fixturePath $fixtureArguments
        $readyDeadline=[DateTime]::UtcNow.AddSeconds(10)
        while(-not(Test-Path -LiteralPath $fixtureReady)){
            if($fixture.HasExited -or [DateTime]::UtcNow -ge $readyDeadline){throw 'Fixture did not publish readiness.'}
            Start-Sleep -Milliseconds 50
        }
        $nativeReady=Read-Receipt $fixtureReady
        if($nativeReady.schema -ne 1 -or $nativeReady.kind -cne 'minecome_hud_input_fixture_ready_v1' -or $nativeReady.run -cne $run -or $nativeReady.host_pid -ne $fixture.Id -or [string]$nativeReady.host_start_filetime -cne $fixture.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -or $nativeReady.expires_utc_ms -ne $expires){throw 'Fixture process readiness mismatch.'}
        if($PointerFixture -and ($nativeReady.PSObject.Properties.Name -notcontains 'pointer_fixture' -or $nativeReady.pointer_fixture -isnot [bool] -or -not $nativeReady.pointer_fixture)){throw 'Native pointer fixture readiness mismatch.'}
        $targetPid=$fixture.Id;$targetStart=[string]$nativeReady.host_start_filetime
    }else{$targetPid=$context.GamePid;$targetStart=$context.GameStartedUtc.ToFileTimeUtc().ToString()}
    $arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-HudStreamClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-TargetPid',[string]$targetPid,'-TargetStart',$targetStart,'-ExpiresUtcMs',[string]$expires,'-JavaHome',$JavaHome,'-Width',[string]$Width,'-Height',[string]$Height,'-GuiScale',[string]$GuiScale,'-InputMode')
    if($Mode -eq 'Fixture'){$arguments+='-InputFixture'}
    if($LiveMouse){$arguments+='-LiveMouse'}
    if($PointerFixture){$arguments+='-InputPointerFixture'}
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
    if($Mode -eq 'Live'){$armEvidence=& (Join-Path $PSScriptRoot 'Arm-HudStream.ps1') -InputMode -LiveMouse:$LiveMouse -BundleDirectory $BundleDirectory -OffscreenPresentation:$OffscreenPresentation -ReadyManifest $readyPath}
    Write-Output "HUD_INPUT_READY mode=$Mode run=$run"
    while(-not $client.HasExited -or -not $producer.HasExited -or ($fixture -and -not $fixture.HasExited)){
        if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expires+15000){throw 'UI shutdown deadline reached; any remaining processes are preserved.'}
        Start-Sleep -Milliseconds 200
    }
    $producerExitObserved=$producer.HasExited;$producerExitCode=$producer.ExitCode
    if($client.ExitCode -ne 0 -or $producerExitCode -ne 0 -or ($fixture -and $fixture.ExitCode -ne 0)){throw 'UI client, actual Java producer or native fixture reported failure.'}
    $guest=Read-Receipt (Join-Path $directory 'capture/stream-result.json')
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
        if($native.run -cne $run -or $native.kind -cne 'minecome_hud_input_fixture_result_v1' -or $native.result -cne 'passed' -or $guest.result -cne 'input_passed' -or $guest.lab_evidence.input_fixture -ne $true -or $guest.lab_evidence.inventory_opened -ne $true -or $guest.lab_evidence.inventory_closed -ne $true -or $guest.lab_evidence.selected_nine_verified -ne $true){throw 'Real vanilla UI fixture evidence incomplete.'}
        $expectedEvents=if($PointerFixture){43}else{31}
        if($PointerFixture){
            if($native.pointer_fixture -isnot [bool] -or $native.pointer_fixture -ne $true -or $native.pointer_gestures_verified -isnot [bool] -or $native.pointer_gestures_verified -ne $true -or $guest.lab_evidence.pointer_fixture -isnot [bool] -or $guest.lab_evidence.pointer_fixture -ne $true){throw 'Pointer fixture confirmation missing.'}
            $pointer=$guest.lab_evidence.pointer_evidence
            foreach($name in @('completed','right_split_verified','drag_distribution_verified','scroll_changed_verified','scroll_restored_verified','held_close_release_verified','reopened_screen_verified','late_release_consumed_verified','cursor_empty','server_inventory_verified')){
                if($pointer.PSObject.Properties.Name -notcontains $name -or $pointer.$name -isnot [bool] -or $pointer.$name -ne $true){throw "Real pointer evidence missing: $name"}
            }
            if($pointer.expected_events -ne $expectedEvents -or $native.events_sent -ne $expectedEvents -or $native.pointer_phase_receipts -ne 11 -or @($pointer.stages).Count -ne 11 -or $guest.lab_evidence.input_events_applied -ne $expectedEvents -or $guest.lab_evidence.input_consumed_sequence -ne $expectedEvents){throw 'Pointer gesture sequence did not complete exactly.'}
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
        if($LiveMouse){
            $pointerEventsApplied=Assert-LiveMouseGuestProof $guest.lab_evidence
            $liveMouseGuestVerified=$true
        }
        if($guest.lab_evidence.host_armed -ne $true -or $guest.lab_evidence.input_events_applied -lt 1){throw 'Live UI session closed without observed arming and applied input.'}
        Assert-MineComeProbeContext $context
    }
    $bodyPassed=$true;$passed=$true
}catch{$failure=$_.Exception.Message}
finally{
    try{
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
        [ordered]@{schema=1;kind='minecome_hud_input_controller_v1';run=$run;mode=$Mode;pointer_fixture=[bool]$PointerFixture;delay_fixture=[bool]$DelayFixture;background_trial=[bool]$BackgroundTrial;offscreen_presentation=[bool]$OffscreenPresentation;offscreen_trial=[bool]$OffscreenTrial;host_gpu_budget_requested=[bool]$HostGpuBudget;host_gpu_budget=$hostBudgetEvidence;host_hud_hidden_requested=[bool]$HideHostHud;host_hud_visibility=$hostHudEvidence;body_passed=$bodyPassed;result=$(if($passed){'passed'}else{'failed'});failure=$failure;evidence=$directory;target_pid=$targetPid;target_start_filetime=$targetStart;fixture_sha256=$fixtureHash;compositor_armed=[bool]$armEvidence;width=$Width;height=$Height;gui_scale=$GuiScale;kcd_launched=$false;kcd_stopped=$false;host_input_exclusivity_verified=$false;live_mouse_requested=[bool]$LiveMouse;live_mouse_enabled=[bool]($LiveMouse -and $armEvidence);live_mouse_guest_verified=$liveMouseGuestVerified;live_mouse_guest_pass=[bool]($LiveMouse -and $liveMouseGuestVerified -and $passed);pointer_events_applied=$pointerEventsApplied;live_mouse_visual_verified=$false;producer_exit_observed=$producerExitObserved;producer_exit_code=$producerExitCode;created_utc_ms=$expires-180000;expires_utc_ms=$expires} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    }finally{if($producer){$producer.Dispose()};if($client){$client.Dispose()};if($fixture){$fixture.Dispose()}}
}
if(-not $passed){throw $(if($failure){$failure}else{'UI session did not pass.'})}
Write-Output "HUD_INPUT_COMPLETED mode=$Mode run=$run actual_minecraft=true host_input_exclusivity_verified=false"
