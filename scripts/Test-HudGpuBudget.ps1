#Requires -Version 7.3
# SPDX-License-Identifier: GPL-3.0-or-later
# Compare the unchanged standalone HUD guest under a temporary, verified host cap.
# Uses only an already-running exact tools process; never launches or stops KCD.
[CmdletBinding()]
param([string]$JavaHome, [switch]$PreflightOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'HudGpuBudget.ps1')
$context=Get-MineComeProbeContext
& (Join-Path $PSScriptRoot 'Start-HudInputLab.ps1') -Mode Fixture -OffscreenTrial -JavaHome $JavaHome -PreflightOnly
if($PreflightOnly){Write-Output 'HUD_GPU_BUDGET_PREFLIGHT_PASS no_setting_changed=true';return}
$session=New-MineComeHudGpuBudget $context
$comparisonValid=$false;$fixturePassed=$false;$failure=$null;$fixtureRun=$null
try {
    Start-MineComeHudGpuBudget $session
    Write-Output "HUD_GPU_BUDGET_APPLIED run=$($session.Probe.Run) original_fps=$($session.Applied.original_fps) temporary_fps=60 expiry_ms=120000"
    & (Join-Path $PSScriptRoot 'Start-HudInputLab.ps1') -Mode Fixture -OffscreenTrial -JavaHome $JavaHome | ForEach-Object {
        $runMatch=[regex]::Match([string]$_,'^HUD_INPUT_START mode=Fixture run=([0-9a-f]{32}) ')
        if($runMatch.Success){$fixtureRun=$runMatch.Groups[1].Value}
        Write-Output $_
    }
    $fixturePassed=$true
} catch {$failure=$_.Exception.Message}
finally {
    try{Stop-MineComeHudGpuBudget $session}catch{if(-not $failure){$failure=$_.Exception.Message}}
    $comparisonValid=$session.BudgetValid -and $null -ne $fixtureRun
    if(-not $failure -and $session.Failure){$failure=$session.Failure}
    if($session.Probe){
        $probe=$session.Probe
        if(-not $comparisonValid -and -not $failure){$failure='Host cap did not remain owned until comparison completion.'}
        [ordered]@{schema=1;kind='minecome_hud_gpu_budget_comparison_v1';run=$probe.Run;fixture_run=$fixtureRun;game_pid=$context.GamePid;game_start_utc=$context.GameStartedUtc;game_hash=$context.GameHash;source_hash=$probe.SourceHash;snapshot_hash=$probe.SnapshotHash;fixture_passed=$fixturePassed;restoration_verified=$session.RestorationVerified;comparison_valid=$comparisonValid;failure=$failure;kcd_launched=$false;kcd_stopped=$false;freshness_limits_changed=$false} |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
}
if(-not $session.RestorationVerified){throw 'Host cap restoration was not verified; inspect the saved probe receipts before repeating.'}
if($failure){throw $failure}
Write-Output "HUD_GPU_BUDGET_COMPARISON_COMPLETED evidence=$($session.Probe.Directory) host_setting_restored=true"
