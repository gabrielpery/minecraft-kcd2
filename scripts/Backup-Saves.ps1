param([string]$SaveRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Saved Games/kingdomcome2'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $SaveRoot -PathType Container)) { throw "Save directory not found: $SaveRoot" }
$resolvedSource = (Resolve-Path -LiteralPath $SaveRoot).Path
$backupParent = Join-Path $projectRoot ('runtime/backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backupParent | Out-Null
$backupPath = Join-Path $backupParent 'kingdomcome2'
Copy-Item -LiteralPath $resolvedSource -Destination $backupPath -Recurse
$sourceFiles = @(Get-ChildItem -LiteralPath $resolvedSource -File -Recurse)
foreach ($file in $sourceFiles) {
    $relativePath = $file.FullName.Substring($resolvedSource.Length).TrimStart('\','/')
    $destinationFile = Join-Path $backupPath $relativePath
    if (-not (Test-Path -LiteralPath $destinationFile) -or (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash) {
        throw "Backup verification failed for $relativePath"
    }
}
[pscustomobject]@{ Source=$resolvedSource; Backup=$backupPath; Files=$sourceFiles.Count; Verified=$true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupParent 'backup.json') -Encoding UTF8
Write-Output "Verified $($sourceFiles.Count) saved-game/profile files in $backupPath"
