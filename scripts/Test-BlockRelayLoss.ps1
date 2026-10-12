#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Opt-in loss test. It never launches/stops KCD2 or stops Minecraft.
[CmdletBinding()]
param([string]$GameRoot,[string]$PowerShellPath,[string]$JavaHome,
    [ValidateRange(1,65535)][int]$Port=38765,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inventory=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime/environment.json') -Raw | ConvertFrom-Json
if (-not $GameRoot) { $GameRoot=($inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed } | Select-Object -First 1).install_path }
if (-not $GameRoot) { throw 'Official tools were not discovered; no process launched.' }
$GameRoot=(Resolve-Path -LiteralPath $GameRoot).Path
$gameExe=Join-Path $GameRoot 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe'
$games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe })
if ($games.Count -ne 1) { throw 'An already-running official tools world is required. No helper, Minecraft or relay was launched or stopped.' }
$game=$games[0];$gameStarted=$game.StartTime.ToUniversalTime()
$version=(Get-Item -LiteralPath $gameExe).VersionInfo
if ($version.FileMajorPart -ne 1 -or $version.FileMinorPart -ne 0 -or $version.FileBuildPart -ne 0 -or $version.FilePrivatePart -ne 0 -or $version.FileVersion -ne '1.5.5.0' -or $version.ProductVersion -ne '1.5.5.0') { throw 'The tested fixed1.0.0.0/display1.5.5.0 development executable is required.' }
if (Get-Process minecome_tools_host,minecome_host -ErrorAction SilentlyContinue) { throw 'Another bridge host exists; preserving every process.' }
$deploymentPath=Join-Path $projectRoot 'runtime/lua-deployment.json'
$deployment=Get-Content -LiteralPath $deploymentPath -Raw | ConvertFrom-Json
$pak=Join-Path $GameRoot 'Mods/minecome/Data/minecome-diagnostics.pak'
$pakHash=(Get-FileHash -LiteralPath $pak).Hash
$manifestHash=(Get-FileHash -LiteralPath (Join-Path $GameRoot 'Mods/minecome/mod.manifest')).Hash
if ($deployment.ModPath -ne (Join-Path $GameRoot 'Mods/minecome') -or -not $deployment.ContainsLocalMinecraftAssets -or $pakHash -ne $deployment.PakHash -or $manifestHash -ne $deployment.ManifestHash) { throw 'The installed owned sharp-asset package/manifest does not match its recorded build.' }
if ($PreflightOnly) { Write-Output 'Read-only preflight passed; no HTTP calls or process changes made.'; return }
if (-not $PowerShellPath) {
    $PowerShellPath=(Get-Process -Id $PID).Path
    if ([IO.Path]::GetFileName($PowerShellPath) -ne 'pwsh.exe') { $PowerShellPath=($inventory.tool_commands | Where-Object name -eq 'pwsh.exe' | Select-Object -First 1).executable.path }
}
$PowerShellPath=(Resolve-Path -LiteralPath $PowerShellPath).Path
if ([IO.Path]::GetFileName($PowerShellPath) -ne 'pwsh.exe' -or (Get-Item -LiteralPath $PowerShellPath).VersionInfo.FileMajorPart -lt 7) { throw 'Pass an existing PowerShell7 pwsh.exe.' }
$hostExe=(Resolve-Path -LiteralPath (Join-Path $projectRoot 'build/native/kcd2/Release/minecome_tools_host.exe')).Path
$hostHash=(Get-FileHash -LiteralPath $hostExe).Hash
$helperPath=Join-Path $PSScriptRoot 'Start-BlockMirrorTest.ps1'
$helperHash=(Get-FileHash -LiteralPath $helperPath).Hash
$gameLog=Join-Path $GameRoot 'kcd.log'
$nativeLog=Join-Path $projectRoot 'runtime/logs/tools-live-evidence.log'
$gameOffset=(Get-Item -LiteralPath $gameLog).Length
$nativeOffset=if(Test-Path -LiteralPath $nativeLog){(Get-Item -LiteralPath $nativeLog).Length}else{0}
$evidenceRoot=Join-Path $projectRoot 'runtime/evidence'
$priorRuns=@(Get-ChildItem -LiteralPath $evidenceRoot -Directory -Filter 'block-mirror-*' -ErrorAction SilentlyContinue | ForEach-Object FullName)
$runToken=[Guid]::NewGuid().ToString('N')
$runDirectory=Join-Path $evidenceRoot ('relay-loss-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$runToken)
New-Item -ItemType Directory -Path $runDirectory | Out-Null
. (Join-Path $projectRoot 'kcd2/tools-http.ps1')

function Read-Fresh([string]$Path,[long]$Offset) {
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if ($stream.Length -lt $Offset) { throw "Log replaced/truncated: $Path" }
        if ($stream.Length-$Offset -gt 8388608) { throw "Fresh diagnostic log exceeded8MiB: $Path" }
        $stream.Position=$Offset;$reader=[IO.StreamReader]::new($stream)
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
}
function Assert-SameGame {
    $current=Get-Process -Id $game.Id -ErrorAction Stop
    if ($current.Path -ne $gameExe -or $current.StartTime.ToUniversalTime() -ne $gameStarted) { throw 'The original development game process changed; test aborted.' }
}
function Find-OwnedRelay {
    if($helper.HasExited) { throw 'The captured helper parent has exited; no relay will be stopped.' }
    $currentParent=Get-Process -Id $helper.Id -ErrorAction Stop
    if($currentParent.Path -ne $PowerShellPath -or $currentParent.StartTime.ToUniversalTime() -ne $helper.StartTime.ToUniversalTime()) { throw 'The captured helper parent PID/path/creation time changed; preserving every process.' }
    $hosts=@(Get-CimInstance Win32_Process -Filter "Name='minecome_tools_host.exe' OR Name='minecome_host.exe'")
    if ($hosts.Count -eq 0) { return $null }
    if ($hosts.Count -ne 1 -or $hosts[0].Name -ne 'minecome_tools_host.exe' -or $hosts[0].ParentProcessId -ne $helper.Id -or $hosts[0].ExecutablePath -ne $hostExe) { throw 'Host ownership is ambiguous; no relay will be stopped.' }
    $process=Get-Process -Id $hosts[0].ProcessId
    if ($process.Path -ne $hostExe -or $process.StartTime.ToUniversalTime() -lt $helper.StartTime.ToUniversalTime() -or (Get-FileHash -LiteralPath $hostExe).Hash -ne $hostHash) { throw 'Owned relay image/creation/hash verification failed.' }
    [pscustomobject]@{Process=$process;Pid=$process.Id;ParentPid=$helper.Id;Started=$process.StartTime.ToUniversalTime();Path=$process.Path;Hash=$hostHash}
}
function Probe-Status([string]$Phase,[DateTime]$Deadline) {
    $offset=(Get-Item -LiteralPath $gameLog).Length
    $command='#do local s=MineCome.BlockSinkStatus(); System.LogAlways(string.format(''[MineComeLeaseStatus] {"schema":1,"run":"RUN_TOKEN","probe":"PROBE_PHASE","active_session":%s,"last_session":%s,"last_sequence":%s,"owned_count":%d,"pending_count":%d,"timer_pending":%s}'', s.active_session or ''null'', s.last_session or ''0'', s.last_sequence or ''null'', s.owned_count, s.pending_count, tostring(s.timer_pending))); end'
    $command=$command.Replace('RUN_TOKEN',$runToken).Replace('PROBE_PHASE',$Phase)
    $timeout=[Math]::Max(1,[Math]::Min(1000,[int]($Deadline-[DateTime]::UtcNow).TotalMilliseconds))
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($command)) -TimeoutMilliseconds $timeout | Out-Null
    while ([DateTime]::UtcNow -lt $Deadline) {
        Assert-SameGame
        foreach ($match in [regex]::Matches((Read-Fresh $gameLog $offset),'(?m)\[MineComeLeaseStatus\] (\{[^\r\n]*\})\r?$')) {
            $status=$match.Groups[1].Value | ConvertFrom-Json
            if ($status.run -eq $runToken -and $status.probe -eq $Phase) { return $status }
        }
        Start-Sleep -Milliseconds 50
    }
    throw "No fresh read-only $Phase sink status receipt."
}

$helper=$null;$owned=$null;$session=$null;$sequence=$null;$helperEvidence=$null
$faultInjected=$false;$cleanupPassed=$false;$helperExpectedFailure=$false;$minecraftExit=$null;$failure=$null;$stoppedAt=$null
try {
    Get-MineComeToolsConsoleBinding | Out-Null
    $arguments=@('-NoProfile','-File',('"'+$helperPath+'"'),'-GameRoot',('"'+$GameRoot+'"'),'-Seconds','150','-Port',"$Port")
    if ($JavaHome) { $arguments+=@('-JavaHome',('"'+$JavaHome+'"')) }
    $helper=Start-Process -FilePath $PowerShellPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runDirectory 'helper.log') -RedirectStandardError (Join-Path $runDirectory 'helper-errors.log')
    $startupDeadline=[DateTime]::UtcNow.AddSeconds(75)
    do {
        Assert-SameGame
        if ($helper.HasExited) { throw 'The normal helper exited before the intended fault.' }
        $candidate=Find-OwnedRelay;if($candidate){$owned=$candidate}
        $freshNative=Read-Fresh $nativeLog $nativeOffset;$freshGame=Read-Fresh $gameLog $gameOffset
        if ($owned -and $freshGame -match '(?m)\[MineComeTokenContract\] decimal_text_v1 function_reload_verified\r?$') {
            foreach ($ack in [regex]::Matches($freshNative,'(?m)^STONE_ENGINE_ACK session=([0-9]+) sequence=([0-9]+) result=spawned\r?$')) {
                foreach ($receipt in [regex]::Matches($freshGame,'(?m)\[MineComeBlock\] (\{[^\r\n]*\})\r?$')) {
                    $block=$receipt.Groups[1].Value | ConvertFrom-Json
                    if ($block.schema -eq 1 -and $block.event -eq 'place' -and $block.operation -eq 1 -and $block.result -eq 'spawned' -and [string]$block.session -eq $ack.Groups[1].Value -and [string]$block.sequence -eq $ack.Groups[2].Value) { $session=$ack.Groups[1].Value;$sequence=$ack.Groups[2].Value;break }
                }
                if ($session) { break }
            }
        }
        if ($session) { break };Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $startupDeadline)
    if (-not $session) { throw 'No matching fresh real-engine/native spawn acknowledgement; no fault injected.' }
    $before=Probe-Status 'before' ([DateTime]::UtcNow.AddSeconds(3))
    if ([string]$before.active_session -ne $session -or [string]$before.last_session -ne $session -or [string]$before.last_sequence -ne $sequence -or $before.owned_count -ne 1 -or $before.pending_count -ne 0 -or $before.timer_pending -ne $true) { throw 'The expected single owned active stone was not confirmed; no fault injected.' }
    $rechecked=Find-OwnedRelay
    if (-not $rechecked -or $rechecked.Pid -ne $owned.Pid -or $rechecked.Started -ne $owned.Started -or $rechecked.Path -ne $owned.Path -or $rechecked.Hash -ne $owned.Hash) { throw 'Relay PID/image/creation changed; preserving every process.' }
    $postStopOffset=(Get-Item -LiteralPath $gameLog).Length
    Stop-Process -InputObject $rechecked.Process -Force -ErrorAction Stop
    if (-not $rechecked.Process.WaitForExit(2000)) { throw 'Owned relay did not stop within the deadline.' }
    $faultInjected=$true;$stoppedAt=[DateTime]::UtcNow
    $leaseDeadline=$stoppedAt.AddSeconds(12);$expired=$false;$ended=$false
    do {
        Assert-SameGame
        foreach ($receipt in [regex]::Matches((Read-Fresh $gameLog $postStopOffset),'(?m)\[MineComeBlockSession\] (\{[^\r\n]*\})\r?$')) {
            $state=$receipt.Groups[1].Value | ConvertFrom-Json
            if ([string]$state.session -ne $session) { continue }
            if ($state.event -eq 'end') { throw 'Explicit End contaminated lease-expiry evidence.' }
            if ($state.event -eq 'expired') { $expired=$true }
            if ($expired -and ($state.event -in @('expired','cleanup')) -and $state.result -eq 'ended' -and $state.owned_count -eq 0 -and $state.pending_count -eq 0) { $ended=$true }
        }
        if ($expired -and $ended) { break };Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $leaseDeadline)
    if (-not $expired -or -not $ended) { throw 'Matching engine lease expiry and zero cleanup were not confirmed within12seconds; do not retest.' }
    $after=Probe-Status 'after' $leaseDeadline
    $cleanupPassed=$null -eq $after.active_session -and [string]$after.last_session -eq $session -and $null -eq $after.last_sequence -and $after.owned_count -eq 0 -and $after.pending_count -eq 0 -and $after.timer_pending -eq $false
    if (-not $cleanupPassed) { throw 'The real engine sink is not idle/empty/timer-off; do not retest.' }
    Write-Output 'Expected relay loss confirmed: real engine lease expired and all owned blocks were removed.'
    $finishDeadline=[DateTime]::UtcNow.AddSeconds(140)
    while (-not $helper.HasExited -and [DateTime]::UtcNow -lt $finishDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not $helper.HasExited) { throw 'Normal helper/Minecraft shutdown still pending after140seconds; no game process was stopped.' }
    $newRuns=@(Get-ChildItem -LiteralPath $evidenceRoot -Directory -Filter 'block-mirror-*' | Where-Object { $_.FullName -notin $priorRuns })
    if ($newRuns.Count -ne 1) { throw 'Cannot identify one helper evidence directory.' }
    $helperEvidence=$newRuns[0].FullName
    $normalRun=Get-Content -LiteralPath (Join-Path $helperEvidence 'run.json') -Raw | ConvertFrom-Json
    if ($normalRun.RelayPid -ne $owned.Pid -or $normalRun.GamePid -ne $game.Id -or -not $normalRun.FunctionReloadVerified -or $normalRun.LoadedLuaHash -ne $normalRun.LoadedLuaSnapshotHash) { throw 'Helper provenance did not match the captured run.' }
    $minecraftExit=$normalRun.MinecraftExit
    $minecraftLog=Get-Content -LiteralPath (Join-Path $helperEvidence 'minecraft.log') -Raw
    $helperExpectedFailure=$helper.ExitCode -eq 1 -and $minecraftExit -eq 0 -and -not $normalRun.VanillaSmokeVerified -and $minecraftLog -match 'VANILLA_SMOKE_FAIL'
    if (-not $helperExpectedFailure) { throw 'The deliberate loss did not produce the expected helper failure and normal Minecraft exit.' }
    Write-Output "Fault test passed; normal mirror pass remains false. Evidence: $runDirectory"
} catch { $failure=$_.Exception.Message; throw }
finally {
    foreach($capture in @(@($gameLog,$gameOffset,'fresh-kcd.log'),@($nativeLog,$nativeOffset,'fresh-native.log'))) {
        try { Read-Fresh $capture[0] $capture[1] | Set-Content -LiteralPath (Join-Path $runDirectory $capture[2]) }
        catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $runDirectory ($capture[2]+'.capture-error')); if(-not $failure){$failure=$_.Exception.Message} }
    }
    if(-not $helperEvidence) {
        $newRuns=@(Get-ChildItem -LiteralPath $evidenceRoot -Directory -Filter 'block-mirror-*' | Where-Object { $_.FullName -notin $priorRuns })
        if($newRuns.Count -eq 1){$helperEvidence=$newRuns[0].FullName}
    }
    Copy-Item -LiteralPath $deploymentPath -Destination $runDirectory
    [pscustomobject]@{Kind='Live relay-loss test; separate from normal mirror pass';ExpectedFault=$true;FaultInjected=$faultInjected;CleanupPassed=$cleanupPassed;HelperExpectedFailure=$helperExpectedFailure;StandardMirrorPass=$false;GamePid=$game.Id;GameStartedUtc=$gameStarted;HelperPid=$(if($helper){$helper.Id}else{$null});RelayPid=$(if($owned){$owned.Pid}else{$null});RelayParentPid=$(if($owned){$owned.ParentPid}else{$null});RelayStartedUtc=$(if($owned){$owned.Started}else{$null});RelayPath=$hostExe;NativeHash=$hostHash;HelperHash=$helperHash;PakHash=$pakHash;ManifestHash=$manifestHash;Session=$session;SpawnSequence=$sequence;StoppedAtUtc=$stoppedAt;FreshGameLogOffset=$gameOffset;FreshNativeLogOffset=$nativeOffset;HelperEvidence=$helperEvidence;MinecraftExit=$minecraftExit;Failure=$failure} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'fault.json')
}
