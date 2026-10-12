#requires -Version 7.0
param(
    [Parameter(Mandatory=$true)][ValidateSet('Ping','Pose','ShowStone','RemoveStone')][string]$Action,
    [ValidateRange(1,65535)][int]$Port = 1403
)
$ErrorActionPreference = 'Stop'
$commands = @{
    Ping = "#MineCome.Ping('MINECOME_PING_MANUAL')"
    Pose = '#MineCome.SamplePose()'
    ShowStone = '#MineCome.ShowStone()'
    RemoveStone = '#MineCome.RemoveStone()'
}
. (Join-Path $PSScriptRoot 'tools-http.ps1')
$binding = Get-MineComeToolsConsoleBinding -Port $Port
$command = $commands[$Action]
$commandPath = '/api/System/Console/ExecuteString?command=' + [Uri]::EscapeDataString($command)
$response = Invoke-MineComeToolsRequest -PathAndQuery $commandPath -Port $Port -TimeoutMilliseconds 5000
Write-Output "Console request returned HTTP $($response.StatusCode): $command"
Write-Output 'A successful HTTP response is dispatch evidence; inspect fresh game logs and the live frame for the outcome.'
