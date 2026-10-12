param([switch]$Rotate)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$configDir = Join-Path $projectRoot 'config'
$tokenPath = Join-Path $configDir 'bridge.token'
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot 'runtime/logs') | Out-Null
if ($Rotate -or -not (Test-Path -LiteralPath $tokenPath)) {
    $randomBytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $tokenValue = [BitConverter]::ToString($randomBytes).Replace('-', '').ToLowerInvariant()
    [System.IO.File]::WriteAllText($tokenPath, $tokenValue + "`n", [System.Text.Encoding]::ASCII)
}
$existingToken = [System.IO.File]::ReadAllText($tokenPath).Trim()
if ($existingToken -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid token file. Use -Rotate after closing both peers.' }
Write-Output "Local session token prepared at $tokenPath (value withheld)"
