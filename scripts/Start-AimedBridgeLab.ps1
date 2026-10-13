# Actual Minecraft plus a synthetic C++ host. No KCD process or renderer calls.
[CmdletBinding()]
param([string]$JavaHome='C:\Program Files\Java\jdk-24',[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $bootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($bootstrapExit -ne 0){throw "Aimed bridge fixture failed with exit code $bootstrapExit."}
    return
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'AimedBridgeReceipt.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$nativePath=Join-Path $root 'build/native/Release/minecome_aimed_bridge_fixture.exe'
$port=38815
function Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked fixture path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Receipt([string]$Path){
    $null=Unlinked $Path;$file=Get-Item -LiteralPath $Path
    if($file.PSIsContainer -or $file.Length -lt 2 -or $file.Length -gt 256KB){throw 'Invalid bounded fixture receipt.'}
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 32
}
function Start-Owned([string]$Executable,[string[]]$Arguments){
    $info=[Diagnostics.ProcessStartInfo]::new($Executable)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$root
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $child=[Diagnostics.Process]::Start($info);$null=$child.Handle;return $child
}
$JavaHome=Unlinked (Resolve-Path -LiteralPath $JavaHome).Path
$null=Unlinked $minecraft;$null=Unlinked $nativePath
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or
   [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="24(?:[.+-]|")'){throw 'The fixture requires the tested installed JDK 24.'}
if(-not (Test-Path -LiteralPath $nativePath -PathType Leaf)){throw 'Build the minecome_aimed_bridge_fixture CMake target first.'}
$existing=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {
    $_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')
})
if($existing.Count){throw 'An existing MineCome development client is open; preserving it.'}
if(@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object Port -eq $port).Count){throw "Fixture port $port is already occupied."}
if($PreflightOnly){[ordered]@{result='preflight_passed';java_home=$JavaHome;port=$port;kcd_calls=$false}|ConvertTo-Json;return}
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/aimed-bridge-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run)
$null=Unlinked $directory;New-Item -ItemType Directory -Path $directory | Out-Null
$tokenFile=Join-Path $directory 'bridge.token'
$random=[byte[]]::new(32);$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($random)}finally{$rng.Dispose()}
[IO.File]::WriteAllText($tokenFile,([BitConverter]::ToString($random).Replace('-','').ToLowerInvariant()))
$sourcePaths=@('minecraft/src/main/java/dev/minecome/AimedBridgeLab.java','minecraft/src/main/java/dev/minecome/aim/AimedStoneArena.java',
    'minecraft/src/main/java/dev/minecome/MineComeClient.java','minecraft/build.gradle','protocol/src/protocol.cpp','protocol/include/minecome/protocol.hpp',
    'protocol/java/src/main/java/dev/minecome/protocol/Protocol.java','protocol/java/src/main/java/dev/minecome/protocol/BridgeClient.java',
    'protocol/java/src/main/java/dev/minecome/protocol/AimedSession.java','protocol/java/src/main/java/dev/minecome/protocol/AimGeometry.java',
    'kcd2/src/bridge.cpp','kcd2/include/minecome/bridge.hpp','tools/aimed_bridge_fixture.cpp',
    'scripts/Start-AimedBridgeLab.ps1','scripts/Run-AimedBridgeClient.ps1','scripts/AimedBridgeReceipt.ps1')
$hashes=@($sourcePaths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash.ToLowerInvariant()}})
$binaryHash=(Get-FileHash -LiteralPath $nativePath).Hash.ToLowerInvariant()
[ordered]@{schema=1;run=$run;files=$hashes;native_binary=$nativePath;native_sha256=$binaryHash} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $directory 'source-hashes.json') -Encoding utf8NoBOM
$native=$null;$client=$null;$java=$null;$failure=$null;$javaExit=$null;$started=[DateTime]::UtcNow
try {
    $native=Start-Owned $nativePath @('--token',$tokenFile,'--log',(Join-Path $directory 'native.log'),'--receipt',(Join-Path $directory 'native.json'),'--port',[string]$port,'--seconds','200')
    $client=Start-Owned (Join-Path $PSHOME 'pwsh.exe') @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-AimedBridgeClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-JavaHome',$JavaHome,'-TokenFile',$tokenFile,'-Port',[string]$port)
    Write-Output "AIMED_BRIDGE_START run=$run evidence=$directory"
    $readyPath=Join-Path $directory 'aimed-bridge-ready.json'
    while(-not (Test-Path -LiteralPath $readyPath)){
        if($native.HasExited -or $client.HasExited){throw 'Fixture process exited before Java readiness.'}
        if(([DateTime]::UtcNow-$started).TotalSeconds -gt 90){throw 'Minecraft initialization deadline reached.'}
        Start-Sleep -Milliseconds 100
    }
    $ready=Receipt $readyPath
    $save='MineCome-AimedStone-'+[guid]::ParseExact($run,'N').ToString('D')
    if($ready.schema -ne 1 -or $ready.run -cne $run -or $ready.save -cne $save -or $ready.kind -cne 'minecome_aimed_bridge_fixture_v1' -or
       $ready.kcd_connected -isnot [bool] -or $ready.kcd_connected -or $ready.synthetic_host -isnot [bool] -or -not $ready.synthetic_host -or
       ($ready.producer_pid -isnot [int] -and $ready.producer_pid -isnot [long]) -or $ready.producer_pid -le 0 -or $ready.producer_start_filetime -isnot [string]){throw 'Java readiness identity mismatch.'}
    $java=Get-Process -Id $ready.producer_pid;$null=$java.Handle
    if($java.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or
       -not $java.Path.Equals((Join-Path $JavaHome 'bin/java.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'Java PID/start/executable mismatch.'}
    Write-Output "AIMED_BRIDGE_READY run=$run java_pid=$($java.Id) native_pid=$($native.Id)"
    while(-not $java.HasExited -or -not $client.HasExited -or -not $native.HasExited){
        if(([DateTime]::UtcNow-$started).TotalSeconds -gt 215){throw 'Network fixture completion deadline reached.'}
        Start-Sleep -Milliseconds 100
    }
    $javaExit=$java.ExitCode;$exit=Receipt (Join-Path $directory 'client-exit.json')
    if($javaExit -ne 0 -or $client.ExitCode -ne 0 -or $native.ExitCode -ne 0 -or $exit.run -cne $run -or $exit.exit_code -ne 0){throw 'Minecraft, wrapper or native process exited with failure.'}
    $guest=Receipt (Join-Path $directory 'aimed-bridge.json');$hostReceipt=Receipt (Join-Path $directory 'native.json')
    Assert-MineComeAimedBridgeReceipt -Guest $guest -Native $hostReceipt -Run $run -ProducerPid $java.Id -ProducerStart $ready.producer_start_filetime
    $savePath=Unlinked (Join-Path $minecraft ('run/saves/'+$save+'/level.dat'))
    if(-not (Test-Path -LiteralPath $savePath -PathType Leaf)){throw 'New Minecraft save was not persisted.'}
    foreach($entry in $hashes){if((Get-FileHash -LiteralPath (Join-Path $root $entry.path)).Hash -ine $entry.sha256){throw "Source changed during fixture: $($entry.path)"}}
    if((Get-FileHash -LiteralPath $nativePath).Hash -ine $binaryHash){throw 'Native binary changed during fixture.'}
    Write-Output "AIMED_BRIDGE_VERIFIED run=$run actual_minecraft=true synthetic_host=true kcd_connected=false"
}catch{$failure=$_.Exception.Message;throw}
finally{
    if($failure){
        [IO.File]::WriteAllText((Join-Path $directory 'stop.request'),'Controller requested owned fixture shutdown.')
        if($client -and -not $client.HasExited){$null=$client.WaitForExit(5000)}
        if($native -and -not $native.HasExited){$null=$native.WaitForExit(5000)}
    }
    # The native fixture has its own 200-second deadline; never terminate unrelated games.
    [ordered]@{schema=1;run=$run;result=$(if($failure){'failed'}else{'passed'});failure=$failure;java_exit_code=$javaExit;
        java_exited=($null -ne $java -and $java.HasExited);wrapper_exited=($null -ne $client -and $client.HasExited);
        native_exited=($null -ne $native -and $native.HasExited);kcd_connected=$false;ended_utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    foreach($process in @($java,$client,$native)){if($process){$process.Dispose()}}
}
