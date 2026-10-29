# Actual Minecraft walks across two captured tiles in one owned HUD world.
# Does not move, launch or arm KCD2. Omit CorridorFile for the synthetic terrain fixture.
[CmdletBinding()]
param([string]$CorridorFile,[string]$JavaHome,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Corridor lab failed with exit code $code"};return
}
$ErrorActionPreference='Stop'
$options=@{Standalone=$true;GroundCorridorFixture=$true;PreflightOnly=[bool]$PreflightOnly}
if($CorridorFile){$options.GroundCorridorFile=$CorridorFile}
if($JavaHome){$options.JavaHome=$JavaHome}
& (Join-Path $PSScriptRoot 'Start-HudStreamLab.ps1') @options
