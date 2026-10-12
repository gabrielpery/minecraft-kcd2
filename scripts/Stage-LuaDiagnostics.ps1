param([Parameter(Mandatory=$true)][string]$GameRoot, [switch]$UpdateOwned, [switch]$WithBlockAssets)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$resolvedGame = (Resolve-Path -LiteralPath $GameRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $resolvedGame 'system.cfg'))) { throw 'Not a discovered KCD2 game/tools root' }
if (Get-Process KingdomCome -ErrorAction SilentlyContinue) { throw 'Close KCD2 normally before replacing the MineCome package; the engine may hold or cache its assets' }
$modSource = Join-Path $projectRoot 'kcd2/lua'
$modDestination = Join-Path $resolvedGame 'Mods/minecome'
$recordPath = Join-Path $projectRoot 'runtime/lua-deployment.json'
if (Test-Path -LiteralPath $modDestination) {
    if (-not $UpdateOwned -or -not (Test-Path -LiteralPath $recordPath)) { throw "Preserving existing mod at $modDestination; use -UpdateOwned only for our recorded deployment" }
    $previous = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
    $installedPak = Join-Path $modDestination 'Data/minecome-diagnostics.pak'
    if ($previous.ModPath -ne $modDestination -or -not (Test-Path -LiteralPath $installedPak) -or (Get-FileHash -LiteralPath $installedPak -Algorithm SHA256).Hash -ne $previous.PakHash) {
        throw 'Existing mod does not match our deployment record; preserving it'
    }
    $installedManifestHash = (Get-FileHash -LiteralPath (Join-Path $modDestination 'mod.manifest') -Algorithm SHA256).Hash
    $expectedManifestHash = $previous.ManifestHash
    if (-not $expectedManifestHash) { $expectedManifestHash = (Get-FileHash -LiteralPath (Join-Path $modSource 'mod.manifest') -Algorithm SHA256).Hash }
    if ($installedManifestHash -ne $expectedManifestHash) { throw 'Existing manifest was modified; preserving it' }
    $previousBackup = Join-Path $projectRoot ('runtime/packages/previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $previousBackup | Out-Null
    Copy-Item -LiteralPath $installedPak -Destination $previousBackup
    Copy-Item -LiteralPath (Join-Path $modDestination 'mod.manifest') -Destination $previousBackup
}
$pakDirectory = Join-Path $projectRoot 'runtime/packages'
New-Item -ItemType Directory -Force -Path $pakDirectory | Out-Null
$pakPath = Join-Path $pakDirectory 'minecome-diagnostics.pak'
Add-Type -AssemblyName System.IO.Compression
$zipStream = [System.IO.File]::Open($pakPath, [System.IO.FileMode]::Create)
$archive = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $dataRoots = @((Resolve-Path -LiteralPath (Join-Path $modSource 'data')).Path)
    if ($WithBlockAssets) {
        $assetData = Join-Path $projectRoot 'runtime/compiled-block/Data'
        foreach ($requiredAsset in @('objects/minecome/stone.cgf','objects/minecome/stone.mtl','objects/minecome/block-atlas.dds')) {
            if (-not (Test-Path -LiteralPath (Join-Path $assetData $requiredAsset))) { throw "Compile actual Minecraft assets first: $requiredAsset" }
        }
        $dataRoots += (Resolve-Path -LiteralPath $assetData).Path
    }
    foreach ($sourceData in $dataRoots) {
        foreach ($file in Get-ChildItem -LiteralPath $sourceData -Recurse -File) {
            $entryName = $file.FullName.Substring($sourceData.Length).TrimStart('\','/').Replace('\','/')
            $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::NoCompression)
            $inputStream = [System.IO.File]::OpenRead($file.FullName)
            $outputStream = $entry.Open()
            try { $inputStream.CopyTo($outputStream) } finally { $inputStream.Dispose(); $outputStream.Dispose() }
        }
    }
} finally { $archive.Dispose(); $zipStream.Dispose() }
New-Item -ItemType Directory -Path (Join-Path $modDestination 'Data') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $modSource 'mod.manifest') -Destination $modDestination
Copy-Item -LiteralPath $pakPath -Destination (Join-Path $modDestination 'Data/minecome-diagnostics.pak')
[pscustomobject]@{ ModPath=$modDestination; PakHash=(Get-FileHash -LiteralPath $pakPath -Algorithm SHA256).Hash; ManifestHash=(Get-FileHash -LiteralPath (Join-Path $modDestination 'mod.manifest') -Algorithm SHA256).Hash; CreatedFiles=@('mod.manifest','Data/minecome-diagnostics.pak'); ContainsLocalMinecraftAssets=[bool]$WithBlockAssets; Kind='Original Lua diagnostics and optional transient block display; no native loader/hooks' } | ConvertTo-Json | Set-Content -LiteralPath $recordPath -Encoding UTF8
Write-Output "Staged original Lua diagnostics at $modDestination. Deployment record: $recordPath"
