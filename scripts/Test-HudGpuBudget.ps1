#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Compare the unchanged standalone HUD guest under a temporary, verified host cap.
# Uses only an already-running exact tools process; never launches or stops KCD.
[CmdletBinding()]
param([string]$JavaHome, [switch]$PreflightOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
$source=Join-Path $context.ProjectRoot 'kcd2/probes/hud_gpu_budget_probe.lua'
& (Join-Path $PSScriptRoot 'Start-HudInputLab.ps1') -Mode Fixture -OffscreenTrial -JavaHome $JavaHome -PreflightOnly
if($PreflightOnly){Write-Output 'HUD_GPU_BUDGET_PREFLIGHT_PASS no_setting_changed=true';return}
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$applied=$null;$capVerified=$false;$restored=$false;$comparisonValid=$false;$fixturePassed=$false;$failure=$null;$receipts=@();$fixtureRun=$null
function Read-BudgetReceipts {
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $fresh=Read-MineComeProbeLog $context $probe.Offset
    return @(Get-MineComeProbeReceipts $fresh 'MineComeHudGpuBudget' $probe.Run)
}
try {
    $probe=New-MineComeProbeRun $context 'hud-gpu-budget' $source 'BeginHudGpuBudget'
    Invoke-MineComeProbeConsole $context ("#MineCome.BeginHudGpuBudget('$($probe.Run)',120000,60)")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        $receipts=@(Read-BudgetReceipts)
        $appliedReceipts=@($receipts | Where-Object stage -eq 'applied')
        if($appliedReceipts.Count -eq 1){$applied=$appliedReceipts[0];break}
        Start-Sleep -Milliseconds 50
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $applied -or $applied.current_fps -ne 60 -or $applied.active -ne $true -or $applied.timer_armed -ne $true -or $applied.duration_ms -ne 120000){throw 'No verified temporary host frame cap; Minecraft was not started.'}
    if($applied.original_fps -gt 0 -and $applied.original_fps -le 60){throw 'Comparison requires an uncapped host or an original cap above 60 FPS.'}
    $capVerified=$true
    Write-Output "HUD_GPU_BUDGET_APPLIED run=$($probe.Run) original_fps=$($applied.original_fps) temporary_fps=60 expiry_ms=120000"
    & (Join-Path $PSScriptRoot 'Start-HudInputLab.ps1') -Mode Fixture -OffscreenTrial -JavaHome $JavaHome | ForEach-Object {
        $runMatch=[regex]::Match([string]$_,'^HUD_INPUT_START mode=Fixture run=([0-9a-f]{32}) ')
        if($runMatch.Success){$fixtureRun=$runMatch.Groups[1].Value}
        Write-Output $_
    }
    $fixturePassed=$true
} catch {$failure=$_.Exception.Message}
finally {
    if($probe){
        try {
            Invoke-MineComeProbeConsole $context ("#MineCome.EndHudGpuBudget('$($probe.Run)')")
            $deadline=[DateTime]::UtcNow.AddSeconds(4)
            do {
                $receipts=@(Read-BudgetReceipts)
                $ends=@($receipts | Where-Object { $_.stage -eq 'terminal' -and $_.restored -eq $true })
                if($ends.Count -ge 1){
                    $lastEnd=$ends[-1]
                    $restored=$lastEnd.active -eq $false -and $lastEnd.current_fps -eq $lastEnd.original_fps
                    $comparisonValid=$capVerified -and $null -ne $fixtureRun -and $restored -and $lastEnd.restore_result -ceq 'restored' -and $lastEnd.expired -eq $false -and $lastEnd.reason -ceq 'requested_end' -and $lastEnd.timer_cancelled -eq $true
                    break
                }
                Start-Sleep -Milliseconds 50
            } while([DateTime]::UtcNow -lt $deadline)
            Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') -Encoding utf8NoBOM
        } catch {if(-not $failure){$failure=$_.Exception.Message}}
        $receipts | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'receipts.json') -Encoding utf8NoBOM
        if(-not $comparisonValid -and -not $failure){$failure='Host cap did not remain owned until comparison completion.'}
        [ordered]@{schema=1;kind='minecome_hud_gpu_budget_comparison_v1';run=$probe.Run;fixture_run=$fixtureRun;game_pid=$context.GamePid;game_start_utc=$context.GameStartedUtc;game_hash=$context.GameHash;source_hash=$probe.SourceHash;snapshot_hash=$probe.SnapshotHash;fixture_passed=$fixturePassed;restoration_verified=$restored;comparison_valid=$comparisonValid;failure=$failure;kcd_launched=$false;kcd_stopped=$false;freshness_limits_changed=$false} |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
}
if(-not $restored){throw 'Host cap restoration was not verified; inspect the saved probe receipts before repeating.'}
if($failure){throw $failure}
Write-Output "HUD_GPU_BUDGET_COMPARISON_COMPLETED evidence=$($probe.Directory) host_setting_restored=true"
