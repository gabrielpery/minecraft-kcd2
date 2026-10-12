#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][ValidateSet('trosecko','kutnohorsko','klaster')][string]$Map,
    [ValidateRange(1,65535)][int]$Port = 1403
)
$ErrorActionPreference = 'Stop'
# This deliberately waits for the already running official-tools process.
# No launcher, save-loading, executable modification or native injection.
. (Join-Path $PSScriptRoot 'tools-http.ps1')
$binding = Get-MineComeToolsConsoleBinding -Port $Port
$commandPath = '/api/System/Console/ExecuteString?command=' + [Uri]::EscapeDataString("map $Map")
Write-Output "Dispatching explicit development-map load: map $Map"
try {
    $response = Invoke-MineComeToolsRequest -PathAndQuery $commandPath -Port $Port -TimeoutMilliseconds 10000
    Write-Output "Console request returned HTTP $($response.StatusCode); verify CurrentLevelInfo and player separately."
}
catch {
    Write-Warning 'Map loading can block HTTP; inspect the game log before repeating a request.'
    throw
}
