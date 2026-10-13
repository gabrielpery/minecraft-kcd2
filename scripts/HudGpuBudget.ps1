#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared lifecycle for the unchanged, engine-timed120s sys_MaxFPS=60 probe.
# Dot sourcing only defines functions. Callers must retain the session before Start
# and invoke Stop in finally; no function launches or stops a game.
function New-MineComeHudGpuBudget($Context) {
    [pscustomobject]@{
        Context=$Context;Probe=$null;Applied=$null;Terminal=$null;Receipts=@()
        StartAttempted=$false;StopAttempted=$false;CapVerified=$false
        RestorationVerified=$false;BudgetValid=$false;Failure=$null;RestorationFailure=$null
        AppliedUtcMs=0L;StoppedUtcMs=0L
    }
}
function Read-MineComeHudGpuBudgetReceipts($Session) {
    Invoke-MineComeProbeConsole $Session.Context ("#System.LogAlways('[MineComeProbeFlush] $($Session.Probe.Run)')")
    $fresh=Read-MineComeProbeLog $Session.Context $Session.Probe.Offset
    return @(Get-MineComeProbeReceipts $fresh 'MineComeHudGpuBudget' $Session.Probe.Run)
}
function Start-MineComeHudGpuBudget($Session) {
    if($Session.StartAttempted){throw 'This host GPU budget session was already used.'}
    $Session.StartAttempted=$true
    try {
        Get-MineComeToolsConsoleBinding | Out-Null
        $source=Join-Path $Session.Context.ProjectRoot 'kcd2/probes/hud_gpu_budget_probe.lua'
        $Session.Probe=New-MineComeProbeRun $Session.Context 'hud-gpu-budget' $source 'BeginHudGpuBudget'
        Invoke-MineComeProbeConsole $Session.Context ("#MineCome.BeginHudGpuBudget('$($Session.Probe.Run)',120000,60)")
        $deadline=[DateTime]::UtcNow.AddSeconds(4)
        do {
            $Session.Receipts=@(Read-MineComeHudGpuBudgetReceipts $Session)
            $applied=@($Session.Receipts | Where-Object stage -eq 'applied')
            if($applied.Count -eq 1){$Session.Applied=$applied[0];break}
            Start-Sleep -Milliseconds 50
        } while([DateTime]::UtcNow -lt $deadline)
        $receipt=$Session.Applied
        if(-not $receipt -or $receipt.current_fps -ne 60 -or $receipt.active -ne $true -or $receipt.timer_armed -ne $true -or $receipt.duration_ms -ne 120000){throw 'No verified temporary host frame cap; dependent work was not started.'}
        if($receipt.original_fps -gt 0 -and $receipt.original_fps -le 60){throw 'Host GPU budget requires an uncapped host or an original cap above60FPS.'}
        if(@($Session.Receipts | Where-Object stage -eq 'terminal').Count){throw 'Host frame cap ended before dependent work could start.'}
        $Session.CapVerified=$true;$Session.AppliedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } catch {$Session.Failure=$_.Exception.Message;throw}
}
function Get-MineComeHudGpuBudgetEvidence($Session) {
    $probe=$Session.Probe;$applied=$Session.Applied
    [ordered]@{
        schema=1;kind='minecome_hud_gpu_budget_session_v1';enabled=$true
        run=$(if($probe){$probe.Run}else{$null});evidence=$(if($probe){$probe.Directory}else{$null})
        game_pid=$Session.Context.GamePid;game_start_utc=$Session.Context.GameStartedUtc;game_hash=$Session.Context.GameHash
        source_hash=$(if($probe){$probe.SourceHash}else{$null});snapshot_hash=$(if($probe){$probe.SnapshotHash}else{$null})
        cap_verified=$Session.CapVerified;restoration_verified=$Session.RestorationVerified;budget_valid=$Session.BudgetValid
        failure=$Session.Failure;restoration_failure=$Session.RestorationFailure
        original_fps=$(if($applied){$applied.original_fps}else{$null});requested_fps=60;duration_ms=120000
        applied_utc_ms=$Session.AppliedUtcMs;stopped_utc_ms=$Session.StoppedUtcMs
        terminal=$Session.Terminal;engine_timer_lease=$true;kcd_launched=$false;kcd_stopped=$false;freshness_limits_changed=$false
    }
}
function Stop-MineComeHudGpuBudget($Session) {
    if($Session.StopAttempted){return}
    $Session.StopAttempted=$true
    if(-not $Session.Probe){return} # No Begin was dispatched without a retained probe.
    try {
        Invoke-MineComeProbeConsole $Session.Context ("#MineCome.EndHudGpuBudget('$($Session.Probe.Run)')")
        $deadline=[DateTime]::UtcNow.AddSeconds(4)
        do {
            $Session.Receipts=@(Read-MineComeHudGpuBudgetReceipts $Session)
            $ends=@($Session.Receipts | Where-Object stage -eq 'terminal')
            if($ends.Count -ge 1){
                $Session.Terminal=$ends[-1];$last=$Session.Terminal
                $sameOriginal=$null -eq $Session.Applied -or $last.original_fps -eq $Session.Applied.original_fps
                $Session.RestorationVerified=$last.restored -eq $true -and $last.active -eq $false -and $last.current_fps -eq $last.original_fps -and $sameOriginal
                $Session.BudgetValid=$Session.CapVerified -and $Session.RestorationVerified -and $last.restore_result -ceq 'restored' -and $last.expired -eq $false -and $last.reason -ceq 'requested_end' -and $last.timer_cancelled -eq $true
                break
            }
            Start-Sleep -Milliseconds 50
        } while([DateTime]::UtcNow -lt $deadline)
        if(-not $Session.RestorationVerified){$Session.RestorationFailure='Host cap restoration was not verified; inspect the saved probe receipts before repeating.'}
        elseif(-not $Session.BudgetValid){$Session.RestorationFailure='Host cap did not remain owned and unexpired until controlled completion.'}
    } catch {$Session.RestorationFailure=$_.Exception.Message}
    finally {
        $Session.StoppedUtcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if(-not $Session.Failure -and $Session.RestorationFailure){$Session.Failure=$Session.RestorationFailure}
        try {
            Read-MineComeProbeLog $Session.Context $Session.Probe.Offset | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'fresh-kcd.log') -Encoding utf8NoBOM
            $Session.Receipts | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'receipts.json') -Encoding utf8NoBOM
            Get-MineComeHudGpuBudgetEvidence $Session | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Session.Probe.Directory 'budget-verification.json') -Encoding utf8NoBOM
        } catch {
            $Session.RestorationFailure='Host budget evidence could not be saved: '+$_.Exception.Message
            if(-not $Session.Failure){$Session.Failure=$Session.RestorationFailure}
            throw
        }
    }
}
