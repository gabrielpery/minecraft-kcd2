#Requires -Version 5.1
# Fresh, explicitly combined15-second walking/aiming session and30-second HUD.
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
    if($LASTEXITCODE -ne 0){throw 'Combined walking/aimed controller failed.'}
    return
}
& (Join-Path $PSScriptRoot 'Test-HudWalkingAimed.ps1') @PSBoundParameters
