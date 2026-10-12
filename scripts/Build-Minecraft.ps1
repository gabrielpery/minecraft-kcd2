# Build/test only. Never launches a game, installs Java, or changes launcher files.
[CmdletBinding()]
param(
    [string]$JavaHome,
    [string]$InventoryPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraftRoot = Join-Path $projectRoot 'minecraft'
if (-not $InventoryPath) { $InventoryPath = Join-Path $projectRoot 'runtime\environment.json' }

function Get-CompatibleJdk {
    param([string]$Candidate)
    if (-not $Candidate -or -not (Test-Path -LiteralPath $Candidate -PathType Container)) { return $null }
    $resolved = (Resolve-Path -LiteralPath $Candidate).Path
    $release = Join-Path $resolved 'release'
    if (-not (Test-Path -LiteralPath $release -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $resolved 'bin\java.exe') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $resolved 'bin\javac.exe') -PathType Leaf)) { return $null }
    $match = [regex]::Match([System.IO.File]::ReadAllText($release), '(?m)^JAVA_VERSION="([^"]+)"')
    if (-not $match.Success) { return $null }
    $version = $match.Groups[1].Value
    $major = [int]($version.Split('.')[0].Split('+')[0].Split('-')[0])
    if ($major -ne 21 -and $major -ne 24) { return $null }
    return [pscustomobject]@{ Home = $resolved; Version = $version }
}

if ($JavaHome) {
    $selected = Get-CompatibleJdk -Candidate $JavaHome
    if (-not $selected) { throw '-JavaHome must identify an installed JDK 21 or 24 with java.exe, javac.exe and a release file. No installation was attempted.' }
} else {
    $candidates = @()
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    if (Test-Path -LiteralPath $InventoryPath -PathType Leaf) {
        $inventory = Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json
        $candidates += @($inventory.java.jdks | ForEach-Object { $_.home })
        $candidates += @($inventory.java.launcher_runtimes | ForEach-Object { $_.home })
    }
    $pathJava = Get-Command java.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathJava) { $candidates += Split-Path (Split-Path $pathJava.Source -Parent) -Parent }
    $selected = $null
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $selected = Get-CompatibleJdk -Candidate $candidate
        if ($selected) { break }
    }
    if (-not $selected) { throw 'No installed compatible JDK 21 or 24 was found in JAVA_HOME, environment inventory, or PATH. Pass -JavaHome; no installation was attempted.' }
}

$wrapper = Join-Path $minecraftRoot 'gradlew.bat'
if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw 'The checked-in Minecraft Gradle wrapper was not found.' }
$oldJavaHome = $env:JAVA_HOME
$oldGradleHome = $env:GRADLE_USER_HOME
try {
    $env:JAVA_HOME = $selected.Home
    $env:GRADLE_USER_HOME = Join-Path $minecraftRoot '.gradle-user-home'
    Write-Host ('Using installed Java ' + $selected.Version + ': ' + $selected.Home)
    Write-Host ('Workspace Gradle cache: ' + $env:GRADLE_USER_HOME)
    & $wrapper -p $minecraftRoot --no-daemon build
    if ($LASTEXITCODE -ne 0) { throw ('Fabric build failed with exit code ' + $LASTEXITCODE) }
    & (Join-Path $projectRoot 'protocol\java\build-test.ps1') -JavaHome $selected.Home
    Write-Host 'Fabric remap/build and standalone Java protocol tests passed. No game was launched.'
} finally {
    $env:JAVA_HOME = $oldJavaHome
    $env:GRADLE_USER_HOME = $oldGradleHome
}
