# Installs an adjacent terrain tile during actual Minecraft walking in an owned HUD world.
# Does not launch, move or arm KCD2. Omit ExtensionFile for synthetic geometry.
[CmdletBinding()]
param([string]$ExtensionFile,[string]$JavaHome,[switch]$PreflightOnly,[switch]$DelayHandoff)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $code=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($code -ne 0){throw "Terrain extension lab failed with exit code $code"};return
}
$ErrorActionPreference='Stop'
$options=@{Standalone=$true;GroundExtensionFixture=$true;PreflightOnly=[bool]$PreflightOnly}
if($DelayHandoff){$options.GroundExtensionDelayFixture=$true}
if($ExtensionFile){$options.GroundExtensionFile=$ExtensionFile}
if($JavaHome){$options.JavaHome=$JavaHome}
& (Join-Path $PSScriptRoot 'Start-HudStreamLab.ps1') @options
