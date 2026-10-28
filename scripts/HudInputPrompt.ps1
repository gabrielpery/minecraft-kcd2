# Read-only admission for a human prompt. Buffered console output is never a clock.
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
function Assert-HudInputPromptInteger($Value,[string]$Name){
    if(($Value -isnot [int] -and $Value -isnot [long]) -or $Value -le 0){throw "Invalid HUD prompt $Name."}
}
function Get-HudInputPromptWindow($Ready,$PhysicalReady,$Prompt,[string]$ExpectedRun,[long]$NowUtcMs,
    [ValidateRange(1,60)][int]$MinimumSeconds=15){
    if($ExpectedRun -cnotmatch '^[a-f0-9]{32}$' -or $Ready.run -cne $ExpectedRun -or
        $PhysicalReady.run -cne $ExpectedRun -or $Prompt.run -cne $ExpectedRun){throw 'HUD prompt run identity mismatch.'}
    if($Ready.schema -ne 1 -or $PhysicalReady.schema -ne 1 -or $Prompt.schema -ne 1 -or
        $PhysicalReady.kind -cne 'minecome_hud_physical_ready_v1' -or $Prompt.kind -cne 'minecome_hud_input_prompt_v1' -or
        $PhysicalReady.ready -isnot [bool] -or -not $PhysicalReady.ready -or
        $Ready.ui_input_walking_aimed -isnot [bool] -or -not $Ready.ui_input_walking_aimed -or
        $Ready.movement_session -cne 'extended' -or $PhysicalReady.movement_session -cne 'extended' -or
        $PhysicalReady.save -cne $Ready.save -or $PhysicalReady.target_pid -ne $Ready.target_pid -or
        $PhysicalReady.target_start_filetime -cne $Ready.target_start_filetime){throw 'HUD prompt readiness identity is invalid.'}
    foreach($field in @('stream_started_utc_ms','activation_deadline_utc_ms','utc_ms')){
        if(-not $PhysicalReady.PSObject.Properties[$field]){throw "HUD prompt requires exact guest metadata: $field."}
        Assert-HudInputPromptInteger $PhysicalReady.$field $field
    }
    foreach($field in @('sampled_utc_ms','controller_deadline_utc_ms')){Assert-HudInputPromptInteger $Prompt.$field $field}
    Assert-HudInputPromptInteger $Ready.expires_utc_ms 'lease expiry'
    Assert-HudInputPromptInteger $NowUtcMs 'current UTC'
    $started=[long]$PhysicalReady.stream_started_utc_ms;$activation=[long]$PhysicalReady.activation_deadline_utc_ms
    if($activation-$started -ne 60000 -or $PhysicalReady.utc_ms -lt $started -or
        $PhysicalReady.utc_ms -gt $Prompt.sampled_utc_ms -or $Prompt.sampled_utc_ms -gt $NowUtcMs -or
        $Prompt.controller_deadline_utc_ms -le $Prompt.sampled_utc_ms -or $Ready.expires_utc_ms -le $started){
        throw 'HUD prompt clock regressed, contains future readiness, or changed the guest activation budget.'
    }
    # Retain the existing controller's35-second cleanup/full-session margin.
    $effective=[long][Math]::Min($activation,[Math]::Min([long]$Ready.expires_utc_ms-35000,[long]$Prompt.controller_deadline_utc_ms-35000))
    $remaining=[int][Math]::Floor(($effective-$NowUtcMs)/1000.0)
    [pscustomobject]@{schema=1;kind='minecome_hud_input_prompt_window_v1';run=$ExpectedRun;
        sampled_utc_ms=$NowUtcMs;stream_started_utc_ms=$started;activation_deadline_utc_ms=$activation;
        effective_deadline_utc_ms=$effective;remaining_seconds=[Math]::Max(0,$remaining);
        minimum_seconds=$MinimumSeconds;activation_state_checked=$false;can_prompt=($remaining -ge $MinimumSeconds);
        decline_reason=$(if($remaining -lt $MinimumSeconds){'activation_window_too_short'}else{$null})}
}
function Read-HudInputPromptWindow([Parameter(Mandatory)][string]$CaptureDirectory,
    [Parameter(Mandatory)][string]$ExpectedRun,[ValidateRange(1,60)][int]$MinimumSeconds=15,
    [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent)){
    $capture=Resolve-HudMovementEvidencePath $CaptureDirectory $ProjectRoot
    $ready=Read-HudMovementJson (Resolve-HudMovementEvidencePath (Join-Path $capture 'stream-ready.json') $ProjectRoot)
    $physical=Read-HudMovementJson (Resolve-HudMovementEvidencePath (Join-Path $capture 'physical-ready.json') $ProjectRoot)
    $prompt=Read-HudMovementJson (Resolve-HudMovementEvidencePath (Join-Path $capture 'input-prompt.json') $ProjectRoot)
    # Sample the clock AFTER reading. A copied READY line cannot renew this window.
    $null=Get-HudInputPromptWindow $ready $physical $prompt $ExpectedRun ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $MinimumSeconds
    $decline=$null
    foreach($name in @('stream-result.json','walking-aim-ready.json')){
        if(Test-Path -LiteralPath (Join-Path $capture $name)){$decline='session_already_active_or_terminal'}
    }
    foreach($role in @('producer','target')){
        $idField=$role+'_pid';$startField=$role+'_start_filetime';$process=$null
        try{
            $process=Get-Process -Id $ready.$idField -ErrorAction Stop
            if($process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.$startField){throw 'Process identity changed.'}
        }catch{$decline='session_process_not_alive'}
        finally{if($process){$process.Dispose()}}
    }
    # Process inspection can be slow; never return the budget sampled before it.
    $window=Get-HudInputPromptWindow $ready $physical $prompt $ExpectedRun ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $MinimumSeconds
    foreach($name in @('stream-result.json','walking-aim-ready.json')){
        if(Test-Path -LiteralPath (Join-Path $capture $name)){$decline='session_already_active_or_terminal'}
    }
    if($decline){$window.can_prompt=$false;$window.decline_reason=$decline}
    return $window
}
