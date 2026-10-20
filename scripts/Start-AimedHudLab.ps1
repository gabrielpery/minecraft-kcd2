# Bounded live crosshair lab using the already-installed selective revision4 renderer.
# Starts only an isolated Minecraft client; KCD2 must already be in its fresh test world.
[CmdletBinding()]
param([string]$JavaHome,[string]$BundleDirectory,[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "Aimed HUD lab failed with exit code $bootstrapExit."}
    return
}
$ErrorActionPreference='Stop'
$options=@{
    Mode='Live';LiveMouse=$true;StoneLive=$true;WorldClicks=$true;SelectiveMouse=$true
    SelectiveRevision=4;AimedStone=$true;OffscreenPresentation=$true;HostGpuBudget=$true
    Width=1280;Height=720;GuiScale=2;PreflightOnly=[bool]$PreflightOnly
}
if($JavaHome){$options.JavaHome=$JavaHome}
if($BundleDirectory){$options.BundleDirectory=$BundleDirectory}
& (Join-Path $PSScriptRoot 'Start-HudInputLab.ps1') @options
