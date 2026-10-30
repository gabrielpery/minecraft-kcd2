#Requires -Version 7.0
# Real ephemeral Windows TCP listeners; no game process or HTTP request needed.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/KcdToolsProbeHelpers.ps1')
$script:checks=0
function Check([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function New-TestListener([string]$Address,[int]$Port=0){
    $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($Address),$Port)
    $listener.Server.ExclusiveAddressUse=$true
    try{$listener.Start();return $listener}catch{$listener.Stop();throw}
}
$testOwnerPid=[Environment]::ProcessId
$loopback=$null;$wildcard=$null;$otherLoopback=$null;$secondAddress=$null
try{
    $loopback=New-TestListener '127.0.0.1'
    $loopbackPort=([Net.IPEndPoint]$loopback.LocalEndpoint).Port
    Check ([MineCome.Probes.TcpOwner]::OwnsLoopback($loopbackPort,$testOwnerPid)) 'Exact live loopback listener owner rejected'
    Check (-not [MineCome.Probes.TcpOwner]::OwnsLoopback($loopbackPort,$testOwnerPid+1)) 'Wrong process accepted as listener owner'
    $wildcard=New-TestListener '0.0.0.0'
    Check (-not [MineCome.Probes.TcpOwner]::OwnsLoopback(([Net.IPEndPoint]$wildcard.LocalEndpoint).Port,$testOwnerPid)) 'Wildcard bind accepted as exact loopback'
    $otherLoopback=New-TestListener '127.0.0.2'
    Check (-not [MineCome.Probes.TcpOwner]::OwnsLoopback(([Net.IPEndPoint]$otherLoopback.LocalEndpoint).Port,$testOwnerPid)) 'Different loopback address accepted as 127.0.0.1'
    try{$secondAddress=New-TestListener '127.0.0.2' $loopbackPort}
    catch [Net.Sockets.SocketException]{
        if($_.Exception.SocketErrorCode -notin @([Net.Sockets.SocketError]::AddressAlreadyInUse,[Net.Sockets.SocketError]::AddressNotAvailable)){throw}
        Write-Output 'KCD_TCP_OWNER_MULTIBIND_UNSUPPORTED'
    }
    if($null -ne $secondAddress){
        Check (-not [MineCome.Probes.TcpOwner]::OwnsLoopback($loopbackPort,$testOwnerPid)) 'Two addresses sharing a port accepted as unique endpoint'
        $secondAddress.Stop();$secondAddress=$null
    }
    $loopback.Stop();$loopback=$null
    $until=[DateTime]::UtcNow.AddSeconds(1)
    do{
        $stillOwned=[MineCome.Probes.TcpOwner]::OwnsLoopback($loopbackPort,$testOwnerPid)
        if(-not $stillOwned){break};Start-Sleep -Milliseconds 20
    }while([DateTime]::UtcNow -lt $until)
    Check (-not $stillOwned) 'Stopped listener accepted as current endpoint owner'
}finally{
    foreach($listener in @($loopback,$wildcard,$otherLoopback,$secondAddress)){if($null -ne $listener){$listener.Stop()}}
}
Write-Output "KCD_TCP_OWNER_TESTS_PASS checks=$script:checks"
