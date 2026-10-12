#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only API/partial-state inspection. Does not acquire input or physics ownership.
[CmdletBinding()]
param([switch]$PreflightOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$context=Get-MineComeProbeContext
$source=Join-Path $context.ProjectRoot 'kcd2/probes/control_capabilities.lua'
if($PreflightOnly) { Write-Output 'Exact tools process/version/hash/endpoint preflight passed; no Lua or world changes made.';return }
Get-MineComeToolsConsoleBinding | Out-Null
$probe=$null;$receipt=$null;$verified=$false;$failure=$null
try {
    $probe=New-MineComeProbeRun $context 'control-capabilities' $source 'ProbeControlCapabilities'
    Invoke-MineComeProbeConsole $context ("#MineCome.ProbeControlCapabilities('$($probe.Run)')")
    Invoke-MineComeProbeConsole $context ("#System.LogAlways('[MineComeProbeFlush] $($probe.Run)')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        $fresh=Read-MineComeProbeLog $context $probe.Offset
        $found=@(Get-MineComeProbeReceipts $fresh 'MineComeControlCapabilities' $probe.Run)
        if($found.Count -gt 1) { throw 'Duplicate matching control-capability receipts.' }
        if($found.Count -eq 1) { $receipt=$found[0];break }
        Start-Sleep -Milliseconds 50
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $receipt) { throw 'No fresh matching control-capability receipt.' }
    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $probe.Directory 'capabilities.json')
    foreach($field in @('identity_stable','references_stable','ownership_verified','restoration_verified','is_frozen_is_input_state')) {
        if($receipt.$field -isnot [bool]) { throw "Missing or non-boolean capability field: $field" }
    }
    if($receipt.ownership_verified -or $receipt.restoration_verified -or $receipt.is_frozen_is_input_state) {
        throw 'Read-only capability inspection cannot prove input ownership/restoration.'
    }
    $luaTypes=@('nil','boolean','number','string','function','table','userdata','thread')
    foreach($owner in @('action_map_manager','global_game_rules','game_rules_game','player')) {
        $methods=switch($owner) {
            'action_map_manager' { @('owner_type','EnableActionFilter','IsFilterEnabled','EnableActionMapManager') }
            'player' { @('owner_type','EnablePhysics') }
            default { @('owner_type','FreezeInput','IsFrozen') }
        }
        foreach($method in $methods) {
            if($receipt.function_types.$owner.$method -notin $luaTypes) { throw "Invalid Lua type descriptor: $owner.$method" }
        }
    }
    foreach($name in @('dead','unconscious','sitting','laying','mounted','in_dialog','loading_engine_save','world_time_paused','game_started')) {
        $guard=$receipt.guards.$name
        if($null -eq $guard -or $guard.ok -isnot [bool] -or $guard.method_type -notin $luaTypes -or
            $guard.value_type -notin ($luaTypes+@('error'))) { throw "Invalid guard descriptor: $name" }
        if($guard.ok) {
            if($guard.method_type -ne 'function' -or $guard.value_type -ne 'boolean' -or $guard.value -isnot [bool]) { throw "Invalid successful boolean guard: $name" }
        } elseif($null -ne $guard.value) { throw "Unknown guard must have a null value: $name" }
    }
    if($receipt.entity_id_type -cne 'userdata' -or -not $receipt.identity_stable -or -not $receipt.references_stable) { throw 'Actor identity or captured API references could not be verified.' }
    $verified=$true
    Write-Output ($receipt | ConvertTo-Json -Depth 10)
    Write-Output "Read-only control capabilities captured. Input/physics ownership remains unverified. Evidence: $($probe.Directory)"
} catch { $failure=$_.Exception.Message;throw }
finally {
    if($probe) {
        try { Read-MineComeProbeLog $context $probe.Offset | Set-Content -LiteralPath (Join-Path $probe.Directory 'fresh-kcd.log') }
        catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $probe.Directory 'capture-error.txt') }
        [pscustomobject]@{
            Run=$probe.Run;GamePid=$context.GamePid;GamePath=$context.GamePath;GameStartedUtc=$context.GameStartedUtc
            GameHash=$context.GameHash;SourceHash=$probe.SourceHash;SnapshotHash=$probe.SnapshotHash
            FreshLogOffset=$probe.Offset;FunctionReloadVerified=$probe.FunctionReloadVerified
            CapabilitiesVerified=$verified;InputOrPhysicsMutationRequested=$false
            ControlOwnershipVerified=$false;RestorationVerified=$false;Failure=$failure
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $probe.Directory 'verification.json')
    }
}
