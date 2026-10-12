# Direct human launch helper. Prepare/build/package first; does not bypass review or protection.
[CmdletBinding()]
param([string]$GameRoot, [ValidateSet('trosecko','kutnohorsko','klaster')][string]$Level='trosecko')
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $minecomeBootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($minecomeBootstrapExit -ne 0){throw "Forwarded PowerShell 7 helper failed with exit code $minecomeBootstrapExit."}
    return
}
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GameRoot) {
    $inventory = & (Join-Path $projectRoot 'tools/Discover-Environment.ps1') -AsObject
    $toolsGame = $inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed } | Select-Object -First 1
    if ($toolsGame) { $GameRoot = $toolsGame.install_path }
}
if (-not $GameRoot) { throw 'Official tools game was not discovered. No installation was attempted.' }
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$exe = Join-Path $GameRoot 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Expected official development executable not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'Mods/minecome/Data/minecome-diagnostics.pak'))) { throw 'Stage the original Lua package and compiled block assets first.' }
if (Get-Process KingdomCome -ErrorAction SilentlyContinue) { throw 'A KCD2 process already exists. Preserve that game and close it normally before starting this test.' }
$version = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
Write-Output "Starting official development KCD2 $version at $GameRoot, level $Level."
Write-Output 'Use this test session; do not load newer retail saves in an older development build.'
$process = Start-Process -FilePath $exe -WorkingDirectory $GameRoot -ArgumentList @('-devmode','+map',$Level) -WindowStyle Normal -PassThru
Write-Output "Started process $($process.Id). Let its window finish loading. No save or block-spawn command was sent."
Write-Output 'After the world loads, run ./kcd2/request-tools-diagnostic.ps1 -Action ShowStone; see kcd2/TOOLS-TEST.md.'
