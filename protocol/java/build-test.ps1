param([string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
if (-not $JavaHome) { throw 'Pass -JavaHome pointing to an installed JDK 21 or newer.' }
$outputPath = Join-Path $PSScriptRoot 'build/classes'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$sources = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'src') -Recurse -Filter '*.java' | ForEach-Object { $_.FullName }
& (Join-Path $JavaHome 'bin/javac.exe') --release 21 -d $outputPath $sources
if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
& (Join-Path $JavaHome 'bin/java.exe') -cp $outputPath dev.minecome.protocol.ProtocolTests
if ($LASTEXITCODE -ne 0) { throw 'Protocol tests failed' }
& (Join-Path $JavaHome 'bin/java.exe') -cp $outputPath dev.minecome.protocol.AimGeometryTests (Join-Path $PSScriptRoot '../../tests/fixtures/aim_geometry.txt')
if ($LASTEXITCODE -ne 0) { throw 'Aim geometry tests failed' }
