#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Opt-in whole-HUD visibility lease for the controlled tools lab. No work on load.
# Callers retain the session before Start and always Stop in finally.
function New-MineComeHudVisibility($Context,[ValidateRange(2,120000)][int]$DurationMs=120000) {
    [pscustomobject]@{
        Context=$Context;DurationMs=$DurationMs;Probe=$null;Applied=$null;Terminal=$null;Receipts=@()
        StartAttempted=$false;StopAttempted=$false;HiddenVerified=$false
        RestorationVerified=$false;VisibilityValid=$false;Failure=$null;RestorationFailure=$null
        AppliedUtcMs=0L;StoppedUtcMs=0L
    }
}
function Test-MineComeHudVisibilityValue($Value) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) -and ($Value -eq 0 -or $Value -eq 1)
}
function Test-MineComeHudVisibilityFlags($Record,[hashtable]$Expected) {
    foreach($name in $Expected.Keys){
        $property=$Record.PSObject.Properties[$name]
        if($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $Expected[$name]){return $false}
    }
    return $true
}
function Read-MineComeHudVisibilityReceipts($Session) {
    Invoke-MineComeProbeConsole $Session.Context ("#System.LogAlways('[MineComeProbeFlush] $($Session.Probe.Run)')")
    $fresh=Read-MineComeProbeLog $Session.Context $Session.Probe.Offset
    return @(Get-MineComeProbeReceipts $fresh 'MineComeHudVisibility' $Session.Probe.Run)
}
function Start-MineComeHudVisibility($Session) {
    if($Session.StartAttempted -or $Session.StopAttempted){throw 'This HUD visibility session was already used or closed.'}
    $Session.StartAttempted=$true
    try {
        Get-MineComeToolsConsoleBinding | Out-Null
        $source=Join-Path $Session.Context.ProjectRoot 'kcd2/probes/hud_visibility_probe.lua'
        $Session.Probe=New-MineComeProbeRun $Session.Context 'hud-visibility' $source 'BeginHudVisibility'
        Invoke-MineComeProbeConsole $Session.Context ("#MineCome.BeginHudVisibility('$($Session.Probe.Run)',$($Session.DurationMs))")
        $deadline=[DateTime]::UtcNow.AddSeconds(4)
        do {
            $Session.Receipts=@(Read-MineComeHudVisibilityReceipts $Session)
            $applied=@($Session.Receipts | Where-Object stage -eq 'applied')
            if($applied.Count -gt 1){throw 'Duplicate HUD visibility application receipts.'}
            if($applied.Count -eq 1){$Session.Applied=$applied[0];break}
            if(@($Session.Receipts | Where-Object {$_.stage -in @('rejected','terminal')}).Count){throw 'HUD visibility ended before application.'}
            Start-Sleep -Milliseconds 50
        } while([DateTime]::UtcNow -lt $deadline)
        $r=$Session.Applied
        if(-not $r -or -not(Test-MineComeHudVisibilityValue $r.original_hud) -or -not(Test-MineComeHudVisibilityValue $r.current_hud) -or $r.current_hud -ne 0 -or -not(Test-MineComeHudVisibilityValue $r.requested_hud) -or $r.requested_hud -ne 0 -or -not(Test-MineComeHudVisibilityFlags $r @{active=$true;applied=$true;timer_armed=$true}) -or ($r.duration_ms -isnot [int] -and $r.duration_ms -isnot [long]) -or $r.duration_ms -ne $Session.DurationMs){throw 'No verified bounded HUD suppression; dependent work was not started.'}
        $alreadyHidden=$r.original_hud -eq 0
        if(-not(Test-MineComeHudVisibilityFlags $r @{already_hidden=$alreadyHidden;owned_write=(-not $alreadyHidden);write_attempted=(-not $alreadyHidden)})){throw 'HUD visibility write ownership mismatch.'}
        if(@($Session.Receipts | Where-Object stage -eq 'terminal').Count){throw 'HUD visibility ended before dependent work could start.'}
        $Session.HiddenVerified=$true;$Session.AppliedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } catch {$Session.Failure=$_.Exception.Message;throw}
}
function Get-MineComeHudVisibilityEvidence($Session) {
    $probe=$Session.Probe;$applied=$Session.Applied
    [ordered]@{
        schema=1;kind='minecome_hud_visibility_session_v1';enabled=$true;cvar='wh_ui_ShowHud';scope='whole_hud_controlled_lab'
        run=$(if($probe){$probe.Run}else{$null});evidence=$(if($probe){$probe.Directory}else{$null})
        game_pid=$Session.Context.GamePid;game_start_utc=$Session.Context.GameStartedUtc;game_hash=$Session.Context.GameHash
        source_hash=$(if($probe){$probe.SourceHash}else{$null});snapshot_hash=$(if($probe){$probe.SnapshotHash}else{$null})
        hidden_verified=$Session.HiddenVerified;restoration_verified=$Session.RestorationVerified;visibility_valid=$Session.VisibilityValid
        failure=$Session.Failure;restoration_failure=$Session.RestorationFailure
        original_hud=$(if($applied){$applied.original_hud}else{$null});already_hidden=$(if($applied){$applied.already_hidden}else{$null})
        requested_hud=0;duration_ms=$Session.DurationMs;applied_utc_ms=$Session.AppliedUtcMs;stopped_utc_ms=$Session.StoppedUtcMs
        terminal=$Session.Terminal;engine_timer_lease=$true;same_value_external_writes_detectable=$false
        kcd_launched=$false;kcd_stopped=$false;visual_suppression_verified=$false;input_suppression_provided=$false
    }
}
function Stop-MineComeHudVisibility($Session) {
    if($Session.StopAttempted){return}
    $Session.StopAttempted=$true
    if(-not $Session.Probe){return}
    try {
        Invoke-MineComeProbeConsole $Session.Context ("#MineCome.EndHudVisibility('$($Session.Probe.Run)')")
        $deadline=[DateTime]::UtcNow.AddSeconds(4)
        do {
            $Session.Receipts=@(Read-MineComeHudVisibilityReceipts $Session)
            $ends=@($Session.Receipts | Where-Object stage -eq 'terminal')
            if($ends.Count -ge 1){
                # End can re-emit an expired terminal state. Permit repeated snapshots
                # while requiring their immutable ownership/outcome fields to agree.
                foreach($end in $ends){foreach($name in @('original_hud','requested_hud','already_hidden','owned_write','write_attempted','reason','expired','restore_result')){
                    if($end.$name -cne $ends[0].$name -or $end.$name.GetType() -ne $ends[0].$name.GetType()){throw 'Contradictory HUD visibility terminal ownership.'}
                }}
                $Session.Terminal=$ends[-1];$last=$Session.Terminal
                $sameOriginal=$null -eq $Session.Applied -or $last.original_hud -eq $Session.Applied.original_hud
                $Session.RestorationVerified=(Test-MineComeHudVisibilityValue $last.original_hud) -and (Test-MineComeHudVisibilityValue $last.current_hud) -and (Test-MineComeHudVisibilityFlags $last @{restored=$true;active=$false}) -and $last.current_hud -eq $last.original_hud -and $sameOriginal
                $ownedEnd=if($last.original_hud -eq 0){(Test-MineComeHudVisibilityFlags $last @{already_hidden=$true;owned_write=$false;write_attempted=$false}) -and $last.restore_result -ceq 'already_hidden'}else{(Test-MineComeHudVisibilityFlags $last @{already_hidden=$false;owned_write=$true;write_attempted=$true}) -and $last.restore_result -ceq 'restored'}
                $sameContract=(Test-MineComeHudVisibilityValue $last.requested_hud) -and $last.requested_hud -eq 0 -and ($last.duration_ms -is [int] -or $last.duration_ms -is [long]) -and $last.duration_ms -eq $Session.DurationMs
                $Session.VisibilityValid=$Session.HiddenVerified -and $Session.RestorationVerified -and $ownedEnd -and $sameContract -and (Test-MineComeHudVisibilityFlags $last @{expired=$false;timer_cancelled=$true}) -and $last.reason -ceq 'requested_end'
                break
            }
            Start-Sleep -Milliseconds 50
        } while([DateTime]::UtcNow -lt $deadline)
        if(-not $Session.RestorationVerified){$Session.RestorationFailure='Host HUD restoration was not verified; inspect the saved visibility receipts.'}
        elseif(-not $Session.VisibilityValid){$Session.RestorationFailure='Host HUD visibility was not verified through controlled completion.'}
    } catch {$Session.RestorationFailure=$_.Exception.Message}
    finally {
        $Session.StoppedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if(-not $Session.Failure -and $Session.RestorationFailure){$Session.Failure=$Session.RestorationFailure}
        try {
            Read-MineComeProbeLog $Session.Context $Session.Probe.Offset | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'fresh-kcd.log') -Encoding utf8NoBOM
            $Session.Receipts | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'receipts.json') -Encoding utf8NoBOM
            Get-MineComeHudVisibilityEvidence $Session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'visibility-verification.json') -Encoding utf8NoBOM
        } catch {
            $Session.RestorationFailure='Host HUD visibility evidence could not be saved: '+$_.Exception.Message
            if(-not $Session.Failure){$Session.Failure=$Session.RestorationFailure}
            throw
        }
    }
}
