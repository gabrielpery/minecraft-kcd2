# Standalone real-Minecraft terrain/movement/HUD integration. No KCD calls.
[CmdletBinding()]
param([string]$JavaHome,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "HUD ground movement lab failed with exit code $bootstrapExit."}
    return
}
$ErrorActionPreference='Stop'
$options=@{Standalone=$true;GroundMovementFixture=$true;PreflightOnly=[bool]$PreflightOnly}
if($JavaHome){$options.JavaHome=$JavaHome}
& (Join-Path $PSScriptRoot 'Start-HudStreamLab.ps1') @options
