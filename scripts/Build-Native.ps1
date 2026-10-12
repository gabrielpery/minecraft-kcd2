# Configure/build/test only. Does not install a loader or deploy to any game.
[CmdletBinding()]
param(
    [string]$BuildDirectory,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')][string]$Configuration = 'Release',
    [ValidateSet('Auto', 'On', 'Off')][string]$Kcse = 'Auto',
    [string]$LibKcd2Root,
    [string]$CMakePath,
    [string]$TestPython,
    [string]$LuaLibrary,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $projectRoot 'build\native' }
$BuildDirectory = [System.IO.Path]::GetFullPath($BuildDirectory)
if (-not $LibKcd2Root) { $LibKcd2Root = Join-Path $projectRoot 'external\libKCD2' }
$LibKcd2Root = [System.IO.Path]::GetFullPath($LibKcd2Root)

$vswhere = Get-Command vswhere.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$vswherePath = $(if ($vswhere) { $vswhere.Source } else { Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe' })
if (-not (Test-Path -LiteralPath $vswherePath)) { throw 'Visual Studio discovery requires vswhere (installed with Visual Studio Installer). No installation was attempted.' }
$instances = @(& $vswherePath -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json -utf8 | ConvertFrom-Json)
$instances = @($instances | Where-Object { $_.isComplete })
if (-not $instances.Count) { throw 'No complete Visual Studio installation with x64 C++ tools was discovered.' }
# Prefer the stable VS 2022 generator; use another supported installed release only if absent.
$selected = $instances | Where-Object { $_.installationVersion -match '^17\.' } | Sort-Object { [version]$_.installationVersion } -Descending | Select-Object -First 1
if (-not $selected) { $selected = $instances | Sort-Object { [version]$_.installationVersion } -Descending | Select-Object -First 1 }
$major = ([version]$selected.installationVersion).Major
$generators = @{ 16 = 'Visual Studio 16 2019'; 17 = 'Visual Studio 17 2022'; 18 = 'Visual Studio 18 2026' }
if (-not $generators.ContainsKey($major)) { throw ('No generator mapping for discovered Visual Studio major version ' + $major) }
$generator = $generators[$major]

if (-not $CMakePath) {
    $bundledCmake = Join-Path $selected.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (Test-Path -LiteralPath $bundledCmake) { $CMakePath = $bundledCmake }
    else {
        $command = Get-Command cmake.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { $CMakePath = $command.Source }
    }
}
if (-not $CMakePath -or -not (Test-Path -LiteralPath $CMakePath)) { throw 'CMake was absent from the selected Visual Studio installation and PATH.' }
$CMakePath = [System.IO.Path]::GetFullPath($CMakePath)
$cmakeVersion = @(& $CMakePath --version)
if ($LASTEXITCODE -ne 0) { throw 'CMake version query failed.' }
$match = [regex]::Match(($cmakeVersion -join "`n"), 'cmake version ([0-9]+\.[0-9]+\.[0-9]+)')
if (-not $match.Success -or [version]$match.Groups[1].Value -lt [version]'3.25.0') { throw 'MineCome requires CMake 3.25 or newer.' }
$availableGenerators = @(& $CMakePath --help) -join "`n"
if ($availableGenerators -notmatch [regex]::Escape($generator)) { throw ('Selected CMake does not support ' + $generator + '; select a matching CMake explicitly with -CMakePath.') }

$sdkAvailable = Test-Path -LiteralPath (Join-Path $LibKcd2Root 'include\KCSE\KCSEAPI.h') -PathType Leaf
if ($Kcse -eq 'On' -and -not $sdkAvailable) { throw 'KCSE build requested but external/libKCD2/include/KCSE/KCSEAPI.h was not found. Fetch the pinned source reference first.' }
$enableKcse = $Kcse -eq 'On' -or ($Kcse -eq 'Auto' -and $sdkAvailable)
$kcseFlag = $(if ($enableKcse) { 'ON' } else { 'OFF' })

$cachePath = Join-Path $BuildDirectory 'CMakeCache.txt'
if (Test-Path -LiteralPath $cachePath) {
    $cache = [System.IO.File]::ReadAllText($cachePath)
    $cacheMatch = [regex]::Match($cache, '(?m)^CMAKE_GENERATOR:INTERNAL=(.+)$')
    if ($cacheMatch.Success -and $cacheMatch.Groups[1].Value.Trim() -ne $generator) {
        throw ('Build directory uses another generator. Choose a new -BuildDirectory; existing build files were preserved.')
    }
}
$configureArguments = @('-S', $projectRoot, '-B', $BuildDirectory, '-G', $generator, '-A', 'x64', ('-DCMAKE_GENERATOR_INSTANCE=' + $selected.installationPath), '-DBUILD_TESTING=ON', ('-DMINECOME_BUILD_KCSE=' + $kcseFlag))
if ($enableKcse) { $configureArguments += '-DMINECOME_LIBKCD2_ROOT=' + $LibKcd2Root }
foreach ($testDependency in @(@('MINECOME_TEST_PYTHON', $TestPython), @('MINECOME_LUA_LIBRARY', $LuaLibrary))) {
    if ($testDependency[1]) {
        if (-not (Test-Path -LiteralPath $testDependency[1] -PathType Leaf)) { throw ('Existing test dependency not found: ' + $testDependency[0]) }
        $configureArguments += ('-D' + $testDependency[0] + '=' + (Resolve-Path -LiteralPath $testDependency[1]).Path)
    }
}
Write-Host ('Using ' + $selected.displayName + ' (' + $selected.installationVersion + '), ' + $cmakeVersion[0] + '; KCSE=' + $kcseFlag)
& $CMakePath @configureArguments
if ($LASTEXITCODE -ne 0) { throw ('Native configure failed with exit code ' + $LASTEXITCODE) }
& $CMakePath --build $BuildDirectory --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw ('Native build failed with exit code ' + $LASTEXITCODE) }
if (-not $SkipTests) {
    $ctest = Join-Path (Split-Path $CMakePath -Parent) 'ctest.exe'
    if (-not (Test-Path -LiteralPath $ctest)) { throw 'ctest.exe was not found alongside the selected CMake.' }
    & $ctest --test-dir $BuildDirectory -C $Configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw ('Native tests failed with exit code ' + $LASTEXITCODE) }
}
Write-Host ('Native ' + $Configuration + ' build completed' + $(if ($SkipTests) { '; tests were skipped.' } else { '; CTest passed.' }))
if ($enableKcse) { Write-Host 'The KCSE DLL is compiled only. This does not verify the loader, engine hooks, or a live game session.' }
