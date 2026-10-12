#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][int]$Port,
    [Parameter(Mandatory=$true)][int]$ObserverPort
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools-http.ps1')
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Fails([scriptblock]$Action, [string]$Expected) {
    $failed = $false
    try { & $Action | Out-Null }
    catch {
        $failed = $true
        if ($_.Exception.Message -notmatch $Expected) { throw "Unexpected failure: $($_.Exception.Message)" }
    }
    Assert-True $failed 'Expected the unsafe/invalid request to fail'
}
# An observable proxy target must receive zero requests, even with these settings.
$env:HTTP_PROXY = "http://127.0.0.2:$ObserverPort"
$env:HTTPS_PROXY = $env:HTTP_PROXY
$env:ALL_PROXY = $env:HTTP_PROXY
$env:NO_PROXY = ''
$result = Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/body'
Assert-True ($result.StatusCode -eq 200 -and $result.Body -eq 'diagnostic-body') 'HTTP status/body were not preserved'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery 'http://example.invalid/api' } 'relative'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '//example.invalid/api' } 'relative'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/body#fragment' } 'fixed'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/redirect' } 'HTTP 302'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/status-error' } 'HTTP 500'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/oversized-fixed' -MaximumResponseBytes 16 } 'bounded'
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/oversized-stream' -MaximumResponseBytes 16 } 'bounded'
$watch = [Diagnostics.Stopwatch]::StartNew()
Assert-Fails { Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/slow-body' -TimeoutMilliseconds 300 } 'absolute timeout'
$watch.Stop()
Assert-True ($watch.ElapsedMilliseconds -ge 200 -and $watch.ElapsedMilliseconds -lt 2000) 'Body did not respect the absolute deadline'
Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/missing-binding' | Out-Null
Assert-Fails { Get-MineComeToolsConsoleBinding -Port $Port } 'ExecuteString binding'
Assert-Fails { & (Join-Path (Split-Path -Parent $PSScriptRoot) 'request-tools-diagnostic.ps1') -Port $Port -Action Ping } 'ExecuteString binding'
$stats = (Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/stats').Body | ConvertFrom-Json
Assert-True ($stats.commands.Count -eq 0) 'A command was sent without a valid Console binding'
Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/valid-binding' | Out-Null
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'request-tools-diagnostic.ps1') -Port $Port -Action Ping | Out-Null
& (Join-Path (Split-Path -Parent $PSScriptRoot) 'request-tools-map.ps1') -Port $Port -Map trosecko | Out-Null
$stats = (Invoke-MineComeToolsRequest -Port $Port -PathAndQuery '/api/test/stats').Body | ConvertFrom-Json
Assert-True ($stats.observer_requests -eq 0) 'A proxy or redirect target was contacted'
Assert-True ($stats.commands.Count -eq 2 -and $stats.commands[0] -eq "#MineCome.Ping('MINECOME_PING_MANUAL')" -and $stats.commands[1] -eq 'map trosecko') 'Helper command encoding/dispatch changed'
Write-Output "PowerShell helpers passed: fixed loopback, proxy bypass, redirect rejection, status/body, bounded fixed/chunked bodies, absolute body deadline ($($watch.ElapsedMilliseconds) ms), capability gate and command encoding. No game was launched."
