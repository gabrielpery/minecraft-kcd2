#requires -Version 7.0
# Run only against an already-running official tools world. Never launches KCD2.
[CmdletBinding()]
param([string]$GameRoot, [string]$JavaHome,
    [ValidateRange(150,3600)][int]$Seconds=180,
    [ValidateRange(1,65535)][int]$Port=38765,
    [switch]$Interactive)
$ErrorActionPreference='Stop'
if($Interactive -and -not $PSBoundParameters.ContainsKey('Seconds')) { $Seconds=3600 }
function Read-MineComeSharedText([string]$Path) {
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reader=[IO.StreamReader]::new($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
}
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inventoryPath=Join-Path $projectRoot 'runtime/environment.json'
$inventory=Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
if (-not $GameRoot) {
    $GameRoot=($inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed } | Select-Object -First 1).install_path
}
if (-not $GameRoot) { throw 'Official development game was not discovered.' }
$GameRoot=(Resolve-Path -LiteralPath $GameRoot).Path
$gameExe=Join-Path $GameRoot 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe'
$games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe })
if ($games.Count -ne 1) { throw 'Start the official tools test world with scripts/Start-Kcd2ToolsTest.ps1 and let it finish loading first.' }
if ((Get-Item -LiteralPath $gameExe).VersionInfo.FileVersion -ne '1.5.5.0') { throw 'This tested helper requires the discovered official 1.5.5.0 development build.' }
if (Get-Process minecome_tools_host,minecome_host -ErrorAction SilentlyContinue) { throw 'Another bridge test is running; let it finish first.' }
$deployment=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime/lua-deployment.json') -Raw | ConvertFrom-Json
$pak=Join-Path $GameRoot 'Mods/minecome/Data/minecome-diagnostics.pak'
if ($deployment.ModPath -ne (Join-Path $GameRoot 'Mods/minecome') -or (Get-FileHash -LiteralPath $pak).Hash -ne $deployment.PakHash) { throw 'The installed owned package differs from its recorded staged build.' }
if ((Get-FileHash -LiteralPath (Join-Path $GameRoot 'Mods/minecome/mod.manifest')).Hash -ne $deployment.ManifestHash) { throw 'The installed owned manifest differs from its staged build.' }
. (Join-Path $projectRoot 'kcd2/tools-http.ps1')
Get-MineComeToolsConsoleBinding | Out-Null
# Refresh only our tested original module through the documented LoadScript API.
# The live game keeps its open package; replacement is deferred until it closes.
$sourceLua=(Resolve-Path -LiteralPath (Join-Path $projectRoot 'kcd2/lua/data/scripts/mods/minecome.lua')).Path
$sourceLuaHash=(Get-FileHash -LiteralPath $sourceLua).Hash
$snapshotDirectory=Join-Path $projectRoot ('runtime/hotload/'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $snapshotDirectory | Out-Null
$sourceLuaSnapshot=Join-Path $snapshotDirectory 'minecome.lua'
Copy-Item -LiteralPath $sourceLua -Destination $sourceLuaSnapshot
$snapshotLuaHash=(Get-FileHash -LiteralPath $sourceLuaSnapshot).Hash
if ($snapshotLuaHash -ne $sourceLuaHash) { throw 'The original Lua source changed while its snapshot was copied; no reload attempted.' }
(Get-Item -LiteralPath $sourceLuaSnapshot).IsReadOnly=$true
$gameLog=Join-Path $GameRoot 'kcd.log'
$reloadOffset=(Get-Item -LiteralPath $gameLog).Length
$luaPath=$sourceLuaSnapshot.Replace('\','/').Replace("'","\'")
$functionReloadVerified=$false
$reloadProofPattern='(?m)\[MineComeTokenContract\] decimal_text_v1 function_reload_verified\r?$'
# A cached contract flag alone does not prove this source was evaluated again.
# Compare functions without altering preserved entity ownership or timer state.
# The inspected live build cached the previous path and ReloadScript left its
# function unchanged. A unique read-only path uses LoadScript's first-load route.
$reloadCommand="#local oldBegin=MineCome and MineCome.BeginBlockSession; Script.LoadScript('$luaPath'); local reloadVerified=MineCome and type(MineCome.BeginBlockSession)=='function' and MineCome.BeginBlockSession~=oldBegin and MineCome._block_sink and MineCome._block_sink.token_format=='decimal_text_v1'; System.LogAlways('[MineComeTokenContract] '..(reloadVerified and 'decimal_text_v1 function_reload_verified' or 'failed_function_reload'))"
if($Interactive) {
    $reloadCommand+="; local i=MineCome._interactive_input; System.LogAlways('[MineComeInteractiveContract] '..(i and i.input_format=='stone_action_v1' and i.commands_registered and 'stone_action_v1 commands_registered' or 'unavailable'))"
}
Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($reloadCommand)) | Out-Null
$reloadUntil=[DateTime]::UtcNow.AddSeconds(3)
$reloadText=''
do {
    $gameStream=[IO.FileStream]::new($gameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if ($gameStream.Length -lt $reloadOffset) { throw 'Game log was replaced during module reload.' }
        $gameStream.Position=$reloadOffset
        $gameReader=[IO.StreamReader]::new($gameStream)
        try { $reloadText=$gameReader.ReadToEnd() } finally { $gameReader.Dispose() }
    } finally { $gameStream.Dispose() }
    if ($reloadText -match '(?m)\[MineComeTokenContract\] failed_function_reload\r?$') { throw 'The Lua module did not replace its session function with the expected token contract; no Minecraft test launched.' }
    if ($reloadText -match $reloadProofPattern) {
        $functionReloadVerified=$true
        if(-not $Interactive -or $reloadText -match '(?m)\[MineComeInteractiveContract\] stone_action_v1 commands_registered\r?$') { break }
    }
    Start-Sleep -Milliseconds 100
} while ([DateTime]::UtcNow -lt $reloadUntil)
if (-not $functionReloadVerified) { throw 'The updated exact-token Lua module did not confirm a new session function; no Minecraft test launched.' }
if($Interactive -and $reloadText -notmatch '(?m)\[MineComeInteractiveContract\] stone_action_v1 commands_registered\r?$') { throw 'The interactive console commands did not confirm registration; no Minecraft test launched.' }
if (-not $JavaHome) {
    foreach ($candidate in @($env:JAVA_HOME)+@($inventory.java.jdks | ForEach-Object { $_.home })) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'release'))) {
            $release=[IO.File]::ReadAllText((Join-Path $candidate 'release'))
            if ($release -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { $JavaHome=$candidate; break }
        }
    }
}
if (-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe'))) { throw 'Pass an installed JDK 21 or 24 using -JavaHome.' }
$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path
if ([IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') { throw 'Use the tested JDK 21 or 24.' }
$hostExe=Join-Path $projectRoot 'build/native/kcd2/Release/minecome_tools_host.exe'
if (-not (Test-Path -LiteralPath $hostExe)) { throw 'Build the native tools host first.' }
$runDirectory=Join-Path $projectRoot ('runtime/evidence/'+$(if($Interactive){'interactive-stone-'}else{'block-mirror-'})+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$stdout=Join-Path $runDirectory 'relay.log';$stderr=Join-Path $runDirectory 'relay-errors.log'
$stopFile=Join-Path $runDirectory 'relay-stop.request'
$arguments=@('--home',('"'+$projectRoot+'"'),'--game-log',('"'+(Join-Path $GameRoot 'kcd.log')+'"'),'--stop-file',('"'+$stopFile+'"'),'--fov-unit','radians','--seconds',$Seconds,'--port',$Port,$(if($Interactive){'--interactive-stone'}else{'--mirror-stone'}))
$oldJavaHome=$env:JAVA_HOME;$oldGradleHome=$env:GRADLE_USER_HOME
$relay=$null;$engineVerified=$false;$minecraftExit=$null;$minecraftLaunched=$false;$minecraftStartedAt=$null;$vanillaVerified=$false;$interactiveReady=$false
try {
    $env:JAVA_HOME=$JavaHome;$env:GRADLE_USER_HOME=Join-Path $projectRoot 'minecraft/.gradle-user-home'
    $wrapper=Join-Path $projectRoot 'minecraft/gradlew.bat'
    # Prepare source outputs before the relay deadline starts.
    & $wrapper -p (Join-Path $projectRoot 'minecraft') --no-daemon classes
    if ($LASTEXITCODE -ne 0) { throw 'Minecraft class/resource preparation failed.' }
    $relay=Start-Process -FilePath $hostExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $until=[DateTime]::UtcNow.AddSeconds(5)
    do {
        if ($relay.HasExited) { throw ('Relay startup failed: '+(Read-MineComeSharedText $stderr)) }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $until -and (Read-MineComeSharedText $stdout) -notmatch 'Official tools console binding verified')
    if ((Read-MineComeSharedText $stdout) -notmatch 'Official tools console binding verified') { throw 'Relay startup deadline expired.' }
    $worldUntil=[DateTime]::UtcNow.AddSeconds(10)
    while ((Read-MineComeSharedText $stdout) -notmatch 'KCD2_LOG .*\[MineComePose\] \{"schema":1,"player":\{') {
        if ($relay.HasExited -or [DateTime]::UtcNow -gt $worldUntil) { throw 'No fresh KCD player/world receipt; load the fresh test map before running this helper.' }
        Start-Sleep -Milliseconds 100
    }
    Write-Host 'Creating a fresh isolated Minecraft lab world. Return focus to KCD2 and look roughly forward.'
    if($Interactive) {
        Write-Host 'After the lab reports ready, use minecome_place and minecome_break in the KCD2 console.'
        Write-Host 'This controls one stone cell through vanilla Minecraft. Close Minecraft normally to end the lab.'
    } else { Write-Host 'After fresh poses arrive: stone appears after about 8 seconds, remains 15 seconds, then disappears. No ShowStone command is needed.' }
    $minecraftLaunched=$true
    $minecraftStartedAt=[DateTime]::UtcNow
    $minecraftArguments=@('-p',(Join-Path $projectRoot 'minecraft'),'--no-daemon','runClient',"-PminecomeTokenFile=$(Join-Path $projectRoot 'config/bridge.token')","-PminecomePort=$Port")
    if($Interactive) { $minecraftArguments+='-PminecomeInteractiveStoneLab' }
    else { $minecraftArguments+=@('-PminecomeDynamicBridgeSmoke','-PminecomeExitAfterSeconds=120') }
    & $wrapper @minecraftArguments 2>&1 | Tee-Object -FilePath (Join-Path $runDirectory 'minecraft-console.log')
    $minecraftExit=$LASTEXITCODE
    Write-Host "Minecraft exited with code $minecraftExit. Relay evidence: $stdout"
    if ($minecraftExit -ne 0) { throw 'The Minecraft test process failed; inspect minecraft-console.log.' }
    $latestMinecraftLog=Join-Path $projectRoot 'minecraft/run/logs/latest.log'
    if (-not (Test-Path -LiteralPath $latestMinecraftLog) -or (Get-Item -LiteralPath $latestMinecraftLog).LastWriteTimeUtc -lt $minecraftStartedAt) { throw 'No Minecraft game log from this invocation.' }
    $minecraftText=Read-MineComeSharedText $latestMinecraftLog
    $vanillaVerified=$minecraftText -match 'VANILLA_SMOKE_PASS' -and $minecraftText -notmatch 'VANILLA_SMOKE_FAIL'
    $interactiveReady=$minecraftText -match 'INTERACTIVE_STONE_LAB_READY'
    if($Interactive) { if(-not $interactiveReady) { throw 'This invocation did not initialise its interactive Minecraft lab.' } }
    elseif (-not $vanillaVerified) { throw 'This invocation did not pass authoritative vanilla placement/removal checks.' }
    $ackUntil=[DateTime]::UtcNow.AddSeconds(5)
    do {
        $relayText=Read-MineComeSharedText $stdout
        $engineVerified=$false
        foreach($spawn in [regex]::Matches($relayText,'STONE_ENGINE_ACK session=([1-9][0-9]*) sequence=[1-9][0-9]* result=spawned')) {
            $engineSession=$spawn.Groups[1].Value
            if($relayText -match ('STONE_ENGINE_ACK session='+$engineSession+' sequence=[1-9][0-9]* result=removed') -and $relayText -match ('STONE_CLEANUP_ACK session='+$engineSession+'(?:\r?\n|$)')) { $engineVerified=$true;break }
        }
        if ($engineVerified) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $ackUntil)
    if (-not $engineVerified -and -not $Interactive) { throw 'KCD engine placement/removal/cleanup acknowledgements were incomplete. This run has not verified block mirroring.' }
    if ($relay.HasExited -and $relay.ExitCode -ne 0) { throw ('Native relay failed with exit code '+$relay.ExitCode) }
    if($engineVerified) { Write-Host 'KCD engine acknowledged spawn, removal and cleanup. Confirm the visible appearance/removal separately.' }
    else { Write-Host 'Interactive lab closed; no complete placement/removal cycle was verified in this invocation.' }
    Write-Host 'The relay cleans up on Minecraft disconnect and exits at its configured deadline.'
} finally {
    $env:JAVA_HOME=$oldJavaHome;$env:GRADLE_USER_HOME=$oldGradleHome
    if($relay -and -not $relay.HasExited) {
        [IO.File]::WriteAllText($stopFile,'Graceful stop requested by the owning test helper.')
        if(-not $relay.WaitForExit(5000)) { Write-Warning 'The relay has not completed graceful cleanup yet; inspect relay.log. Its runtime remains bounded.' }
    }
    if ($minecraftLaunched -and (Test-Path -LiteralPath (Join-Path $projectRoot 'minecraft/run/logs/latest.log')) -and (Get-Item -LiteralPath (Join-Path $projectRoot 'minecraft/run/logs/latest.log')).LastWriteTimeUtc -ge $minecraftStartedAt) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'minecraft/run/logs/latest.log') -Destination (Join-Path $runDirectory 'minecraft.log')
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'runtime/lua-deployment.json') -Destination $runDirectory
    $reloadText | Set-Content -LiteralPath (Join-Path $runDirectory 'lua-reload-receipt.log')
    $runtimeHashes=@(foreach ($outputRoot in @('minecraft/build/classes/java/main','minecraft/build/resources/main')) {
        $absoluteRoot=Join-Path $projectRoot $outputRoot
        if (Test-Path -LiteralPath $absoluteRoot) { Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File | ForEach-Object { [pscustomobject]@{Path=$_.FullName.Substring($projectRoot.Length+1);Hash=(Get-FileHash -LiteralPath $_.FullName).Hash} } }
    })
    [pscustomobject]@{Kind='Live stone lab; visual result requires observation';InteractiveMode=[bool]$Interactive;InteractiveLabReady=$interactiveReady;GamePid=$games[0].Id;RelayPid=$(if($relay){$relay.Id}else{$null});LoadedLuaSource=$sourceLua;LoadedLuaSnapshot=$sourceLuaSnapshot;LoadedLuaHash=$sourceLuaHash;LoadedLuaSnapshotHash=$snapshotLuaHash;LuaTokenContract='decimal_text_v1';FunctionReloadVerified=$functionReloadVerified;MinecraftLaunched=$minecraftLaunched;MinecraftStartedAtUtc=$minecraftStartedAt;MinecraftExit=$minecraftExit;VanillaSmokeVerified=$vanillaVerified;EngineMirroringAcknowledged=$engineVerified;ReferenceJarHash=(Get-FileHash -LiteralPath (Join-Path $projectRoot 'minecraft/build/libs/minecome-fabric-0.1.0.jar')).Hash;LoomClassResourceHashes=$runtimeHashes;NativeHash=(Get-FileHash -LiteralPath $hostExe).Hash;VisualVerified=$false} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'run.json')
}
