# Existing tools world -> real sampled terrain -> HUD-world vanilla movement ->
# bounded KCD follower. This does not launch KCD or arm HUD composition.
[CmdletBinding()]
param([switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "HUD coupled movement lab failed with exit code $bootstrapExit."}
    return
}
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Test-CoupledMovement.ps1') -HudWorld -PreflightOnly:$PreflightOnly
