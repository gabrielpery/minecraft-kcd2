# Build local Minecraft-derived assets only; no game deployment or installers.
[CmdletBinding()]
param(
    [string]$SourceDirectory,
    [string]$OutputDirectory,
    [string]$ResourceCompiler,
    [string]$PythonPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $SourceDirectory) { $SourceDirectory = Join-Path $projectRoot 'minecraft\run\minecome-export\stone' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'runtime\compiled-block' }
if (-not $ResourceCompiler) {
    $environmentSnapshot = & (Join-Path $PSScriptRoot 'Discover-Environment.ps1') -AsObject
    $officialTools = $environmentSnapshot.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed } | Select-Object -First 1
    if ($officialTools) { $ResourceCompiler = Join-Path $officialTools.install_path 'Tools\rc\rc.exe' }
}
if (-not $ResourceCompiler -or -not (Test-Path -LiteralPath $ResourceCompiler -PathType Leaf)) { throw 'The installed official KCD2 Resource Compiler was not found. Use -ResourceCompiler to select it; no installation was attempted.' }
if (-not $PythonPath) {
    $pythonCommand = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonCommand) { $PythonPath = $pythonCommand.Source }
}
if (-not $PythonPath -or -not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Python 3.10+ with Pillow is required. Select it with -PythonPath; no installation was attempted.' }
& $PythonPath (Join-Path $PSScriptRoot 'Convert-BlockAsset.py') --source $SourceDirectory --output $OutputDirectory --rc $ResourceCompiler
if ($LASTEXITCODE -ne 0) { throw ('Asset compilation failed with exit code ' + $LASTEXITCODE) }
