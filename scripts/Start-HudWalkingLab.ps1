#Requires -Version 5.1
# Explicit bounded physical WASD/Space + actual Minecraft HUD, in a fresh test world.
[CmdletBinding()]
param([switch]$PreflightOnly,[string]$JavaHome,[string]$BundleDirectory)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -lt 7){
    . (Join-Path $PSScriptRoot 'powershell7.ps1')
    $pwsh=Get-MineComePowerShell7
    $arguments=@('-NoProfile','-File',$PSCommandPath)
    if($PreflightOnly){$arguments+='-PreflightOnly'}
    if($JavaHome){$arguments+=@('-JavaHome',$JavaHome)}
    if($BundleDirectory){$arguments+=@('-BundleDirectory',$BundleDirectory)}
    & $pwsh @arguments
    if($LASTEXITCODE -ne 0){throw 'HUD walking controller failed.'}
    return
}
& (Join-Path $PSScriptRoot 'Test-HudWalking.ps1') @PSBoundParameters
