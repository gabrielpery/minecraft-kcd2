# Exercise actual argument transport through an installed PowerShell 7 child.
# The child only writes a receipt; no game or build command is launched.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/powershell7.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$directory = Join-Path $root ('runtime/evidence/powershell-bootstrap-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$childPath = Join-Path $directory 'argument fixture.ps1'
$childSource = @'
[CmdletBinding()]
param(
    [string]$GameRoot,
    [string]$Level,
    [string]$JavaHome = 'default-jdk',
    [string]$BundleDirectory,
    [switch]$PreflightOnly,
    [switch]$WithoutMods
)
$ErrorActionPreference = 'Stop'
$receipt = [ordered]@{
    java_home = $JavaHome
    bundle_directory = $BundleDirectory
    level = $Level
    preflight_only = [bool]$PreflightOnly
    without_mods = [bool]$WithoutMods
    powershell_major = $PSVersionTable.PSVersion.Major
}
[IO.File]::WriteAllText((Join-Path $GameRoot 'child.json'), ($receipt | ConvertTo-Json))
if ($Level -eq 'return-failure') { exit 23 }
'@
[IO.File]::WriteAllText($childPath, $childSource)
$script:checks = 0
function Assert-Bootstrap([bool]$Passed, [string]$Name) {
    if (-not $Passed) { throw "PowerShell bootstrap check failed: $Name" }
    $script:checks++
}

# Spaces and shell-looking characters must remain literal data. An unknown key
# would be rejected by this child's CmdletBinding if forwarded accidentally.
$javaPath = 'C:\Program Files\Java\jdk-24 & literal $()'
$level = 'level with spaces & literal $()'
$exit = Invoke-MineComePowerShell7 -ScriptPath $childPath -BoundParameters @{
    GameRoot = $directory
    Level = $level
    JavaHome = $javaPath
    BundleDirectory = 'C:\Fixture bundle\literal & $()'
    PreflightOnly = $true
    WithoutMods = $false
    NotAForwardedOption = 'must remain omitted'
}
$receipt = Get-Content -LiteralPath (Join-Path $directory 'child.json') -Raw | ConvertFrom-Json
Assert-Bootstrap ($exit -eq 0) 'success and unknown option omitted'
Assert-Bootstrap ($receipt.java_home -ceq $javaPath) 'explicit JavaHome preserved'
Assert-Bootstrap ($receipt.bundle_directory -ceq 'C:\Fixture bundle\literal & $()') 'explicit BundleDirectory preserved'
Assert-Bootstrap ($receipt.level -ceq $level) 'literal Level preserved'
Assert-Bootstrap ($receipt.preflight_only -eq $true) 'true switch preserved'
Assert-Bootstrap ($receipt.without_mods -eq $false) 'false switch preserved'
Assert-Bootstrap ($receipt.powershell_major -ge 7) 'actual PowerShell 7 child'

# An omitted JavaHome must retain the target's default, and a child failure must
# not become a successful parent result.
$exit = Invoke-MineComePowerShell7 -ScriptPath $childPath -BoundParameters @{
    GameRoot = $directory
    Level = 'return-failure'
}
$receipt = Get-Content -LiteralPath (Join-Path $directory 'child.json') -Raw | ConvertFrom-Json
Assert-Bootstrap ($exit -eq 23) 'child failure exit code preserved'
Assert-Bootstrap ($receipt.java_home -ceq 'default-jdk') 'omitted JavaHome uses child default'
[ordered]@{
    result = 'passed'
    checks = $script:checks
    parent_powershell = $PSVersionTable.PSVersion.ToString()
    child_powershell_major = $receipt.powershell_major
    games_launched = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding UTF8
Write-Output "PowerShell bootstrap checks passed: $script:checks; evidence=$directory"
