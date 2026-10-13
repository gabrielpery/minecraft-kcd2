# Real Minecraft-only aiming fixture. No host bridge, KCD launch, or KCD calls.
[CmdletBinding()]
param([string]$JavaHome='C:\Program Files\Java\jdk-24',[switch]$PreflightOnly)
. (Join-Path $PSScriptRoot 'powershell7.ps1')
if($PSVersionTable.PSVersion.Major -lt 7){
    $minecomeBootstrapExit=Invoke-MineComePowerShell7 -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    if($minecomeBootstrapExit -ne 0){throw "Forwarded aimed fixture failed with exit code $minecomeBootstrapExit."}
    return
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'AimedStoneReceipt.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
function Assert-Unlinked([string]$Path){
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked aimed fixture path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-Receipt([string]$Path){
    $null=Assert-Unlinked $Path;$item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -lt 2 -or $item.Length -gt 256KB){throw 'Invalid bounded aimed fixture receipt.'}
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 24
}
$JavaHome=Assert-Unlinked (Resolve-Path -LiteralPath $JavaHome).Path
if(-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or
   [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="24(?:[.+-]|")'){throw 'This isolated fixture requires the tested installed JDK24.'}
$null=Assert-Unlinked $minecraft
$existing=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Where-Object {
    $_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')
})
if($existing.Count){throw 'An existing MineCome development client is open; preserving it.'}
if($PreflightOnly){[ordered]@{schema=1;result='preflight_passed';java_home=$JavaHome;existing_clients=0;standalone=$true;kcd_calls=$false}|ConvertTo-Json;return}
$run=[guid]::NewGuid().ToString('N')
$directory=Join-Path $root ('runtime/evidence/aimed-stone-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$run)
$null=Assert-Unlinked $directory
New-Item -ItemType Directory -Path $directory | Out-Null
$sourcePaths=@(
    'minecraft/src/main/java/dev/minecome/AimedStoneLab.java',
    'minecraft/src/main/java/dev/minecome/MineComeClient.java',
    'protocol/java/src/main/java/dev/minecome/protocol/AimGeometry.java',
    'protocol/java/src/main/java/dev/minecome/protocol/Protocol.java',
    'minecraft/build.gradle','scripts/Start-AimedStoneLab.ps1','scripts/Run-AimedStoneClient.ps1','scripts/AimedStoneReceipt.ps1'
)
$sourcePaths+=@(Get-ChildItem -LiteralPath (Join-Path $minecraft 'src/main/java/dev/minecome/aim') -Filter '*.java' -File | ForEach-Object {[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')})
$sourceHashes=@($sourcePaths | ForEach-Object {[ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash.ToLowerInvariant()}})
[ordered]@{schema=1;run=$run;captured_utc=[DateTime]::UtcNow.ToString('o');files=$sourceHashes} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $directory 'source-hashes.json') -Encoding utf8NoBOM
$readyPath=Join-Path $directory 'aimed-ready.json';$resultPath=Join-Path $directory 'aimed-stone.json'
$client=$null;$producer=$null;$ready=$null;$failure=$null;$producerExit=$null
$start=[DateTime]::UtcNow
try {
    $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$root
    foreach($argument in @('-NoProfile','-File',(Join-Path $PSScriptRoot 'Run-AimedStoneClient.ps1'),'-EvidenceDirectory',$directory,'-Run',$run,'-JavaHome',$JavaHome)){$info.ArgumentList.Add($argument)}
    $client=[Diagnostics.Process]::Start($info)
    Write-Output "AIMED_STONE_START run=$run evidence=$directory"
    while(-not (Test-Path -LiteralPath $readyPath)){
        if($client.HasExited){throw "Minecraft wrapper exited before readiness: $($client.ExitCode)"}
        if(([DateTime]::UtcNow-$start).TotalSeconds -gt 90){throw 'Aimed Minecraft initialization deadline reached.'}
        Start-Sleep -Milliseconds 100
    }
    $ready=Read-Receipt $readyPath
    $expectedSave='MineCome-AimedStone-'+[guid]::ParseExact($run,'N').ToString('D')
    if($ready.schema -ne 1 -or $ready.kind -cne 'minecome_aimed_stone_fixture_v1' -or $ready.run -cne $run -or $ready.save -cne $expectedSave -or
       $ready.kcd_connected -isnot [bool] -or $ready.kcd_connected -or $ready.synthetic_host_rays -isnot [bool] -or -not $ready.synthetic_host_rays -or
       ($ready.producer_pid -isnot [int] -and $ready.producer_pid -isnot [long]) -or $ready.producer_pid -le 0 -or $ready.producer_start_filetime -isnot [string]){throw 'Aimed process readiness identity mismatch.'}
    $savePath=Join-Path $minecraft ('run/saves/'+$expectedSave)
    $null=Assert-Unlinked $savePath
    $producer=Get-Process -Id $ready.producer_pid
    $null=$producer.Handle
    if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $ready.producer_start_filetime -or
       -not $producer.Path.Equals((Join-Path $JavaHome 'bin/java.exe'),[StringComparison]::OrdinalIgnoreCase)){throw 'Aimed actual Minecraft process identity mismatch.'}
    Write-Output "AIMED_STONE_READY run=$run java_pid=$($producer.Id) save=$expectedSave"
    while(-not $client.HasExited -or -not $producer.HasExited){
        if(([DateTime]::UtcNow-$start).TotalSeconds -gt 200){throw 'Aimed Minecraft shutdown deadline reached.'}
        Start-Sleep -Milliseconds 100
    }
    $producerExit=$producer.ExitCode
    $exit=Read-Receipt (Join-Path $directory 'client-exit.json')
    if($client.ExitCode -ne 0 -or $producerExit -ne 0 -or $exit.run -cne $run -or $exit.exit_code -ne 0){throw 'Aimed Minecraft/Gradle process exited with failure.'}
    $receipt=Read-Receipt $resultPath
    Assert-MineComeAimedStoneReceipt $receipt $run $producer.Id $ready.producer_start_filetime
    foreach($source in $sourceHashes){if((Get-FileHash -LiteralPath (Join-Path $root $source.path) -Algorithm SHA256).Hash -ine $source.sha256){throw "Aimed fixture source changed during run: $($source.path)"}}
    if(-not (Test-Path -LiteralPath (Join-Path $savePath 'level.dat') -PathType Leaf)){throw 'Expected new isolated Minecraft save was not persisted.'}
    Write-Output "AIMED_STONE_VERIFIED run=$run scenarios=$(@($receipt.checks).Count) actual_client_server=true kcd_connected=false receipt=$resultPath"
}catch{$failure=$_.Exception.Message;throw}
finally{
    if($failure -and $client -and -not $client.HasExited){
        [IO.File]::WriteAllText((Join-Path $directory 'stop.request'),'Controller ending this owned standalone fixture.')
        # Cooperative request only; a stalled owned process is reported and preserved.
        $null=$client.WaitForExit(5000)
    }
    [ordered]@{schema=1;run=$run;result=$(if($failure){'failed'}else{'passed'});failure=$failure;java_exit_code=$producerExit;wrapper_exited=($null -ne $client -and $client.HasExited);java_exited=($null -ne $producer -and $producer.HasExited);kcd_connected=$false;ended_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'verification.json') -Encoding utf8NoBOM
    if($producer){$producer.Dispose()};if($client){$client.Dispose()}
}
