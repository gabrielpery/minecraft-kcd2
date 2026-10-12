param([string]$OutputDirectory = '', [string]$AssetDataDirectory = '')
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\packages\minecome'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path (Join-Path $resolvedOutput 'data') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lua\mod.manifest') -Destination (Join-Path $resolvedOutput 'mod.manifest') -Force
Add-Type -AssemblyName System.IO.Compression
$archivePath = Join-Path $resolvedOutput 'data\minecome.pak'
$archiveStream = [IO.File]::Open($archivePath, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    $archive = [IO.Compression.ZipArchive]::new($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        $entry = $archive.CreateEntry('scripts/mods/minecome.lua', [IO.Compression.CompressionLevel]::NoCompression)
        $entryStream = $entry.Open()
        $sourceStream = [IO.File]::OpenRead((Join-Path $PSScriptRoot 'lua\data\scripts\mods\minecome.lua'))
        try { $sourceStream.CopyTo($entryStream) }
        finally { $sourceStream.Dispose(); $entryStream.Dispose() }
        if ($AssetDataDirectory) {
            $assetRoot = (Resolve-Path -LiteralPath $AssetDataDirectory).Path
            foreach ($assetName in @('stone.cgf','stone.mtl','block-atlas.dds')) {
                $assetPath = Join-Path $assetRoot "objects/minecome/$assetName"
                if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) { throw "Missing compiled asset: $assetPath" }
                $assetEntry = $archive.CreateEntry("objects/minecome/$assetName", [IO.Compression.CompressionLevel]::NoCompression)
                $assetInput = [IO.File]::OpenRead($assetPath)
                $assetOutput = $assetEntry.Open()
                try { $assetInput.CopyTo($assetOutput) }
                finally { $assetInput.Dispose(); $assetOutput.Dispose() }
            }
        }
    }
    finally { $archive.Dispose() }
}
finally { $archiveStream.Dispose() }
Write-Output "Original Lua diagnostics and requested local assets packaged at $resolvedOutput"
Write-Output 'This script packages only; it does not deploy to either game.'
