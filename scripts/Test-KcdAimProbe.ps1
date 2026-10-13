#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# One camera/obstruction sample in an already-running, exactly pinned tools world.
[CmdletBinding()]
param([switch]$PreflightOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
. (Join-Path $PSScriptRoot 'AimProbeReceipt.ps1')
$context=Get-MineComeProbeContext
$source=Join-Path $context.ProjectRoot 'kcd2/probes/aim_probe.lua'
if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw 'The original aim probe source is missing.'}
if($PreflightOnly){Write-Output 'AIM_PROBE_PREFLIGHT_PASS no_http=true no_game_changes=true';return}
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$receipt=$null;$known=$false;$failure=$null
try {
    $probe=New-MineComeProbeRun $context 'aim-probe' $source 'ProbeAim'
    Invoke-MineComeProbeConsole $context ("#MineCome.ProbeAim('$($probe.Run)')")
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        Assert-MineComeProbeContext $context
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $receipts=@(Get-MineComeProbeReceipts $fresh 'MineComeAimProbe' $probe.Run)
        if($receipts.Count -gt 1){throw 'Multiple aim receipts for one requested sample.'}
        if($receipts.Count -eq 1){$receipt=$receipts[0];break}
        Start-Sleep -Milliseconds 50
    }while([DateTime]::UtcNow -lt $deadline)
    if(-not $receipt){throw 'No matching fresh engine aim receipt; HTTP dispatch alone is not verification.'}
    # Keep the raw engine response even when its availability/contract fails.
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $probe.Directory 'receipt.json') -Encoding utf8NoBOM
    Assert-MineComeAimReceipt $receipt $probe.Run
    $known=$true
    Write-Output ("AIM_PROBE_CAPTURED result=$($receipt.result) known=true range=4.5 evidence=$($probe.Directory)")
}catch{$failure=$_.Exception.Message;throw}
finally {
    if($probe){
        try{Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') -Encoding utf8NoBOM}
        catch{$_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt')}
        [ordered]@{
            schema=1;kind='minecome_readonly_aim_probe_v1';run=$probe.Run
            game_pid=$context.GamePid;game_path=$context.GamePath;game_hash=$context.GameHash;game_started_utc=$context.GameStartedUtc
            source_sha256=$probe.SourceHash;snapshot_sha256=$probe.SnapshotHash;fresh_log_offset=$probe.Offset
            function_reload_verified=$probe.FunctionReloadVerified;engine_receipt_received=($null -ne $receipt)
            obstruction_sample_verified=$known;ray_range=4.5;game_launched=$false;game_stopped=$false
            player_movement_applied=$false;block_mutation_applied=$false;aimed_action_dispatched=$false
            crosshair_alignment_verified=$false;failure=$failure
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json') -Encoding utf8NoBOM
    }
}
