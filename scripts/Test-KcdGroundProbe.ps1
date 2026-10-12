#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# One read-only terrain diagnostic against an already-running, pinned tools build.
[CmdletBinding()]
param([switch]$PreflightOnly,[switch]$Patch)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$inventory=Get-Content -LiteralPath (Join-Path $projectRoot 'runtime/environment.json') -Raw | ConvertFrom-Json
$tools=@($inventory.steam.relevant_apps | Where-Object { $_.role -eq 'official_tools' -and $_.installed })
if($tools.Count -ne 1 -or $tools[0].distribution -ne 'Steam' -or $tools[0].app_id -ne '2429020') { throw 'One discovered official Steam tools installation is required.' }
$gameRoot=(Resolve-Path -LiteralPath $tools[0].install_path).Path
$gameExe=(Resolve-Path -LiteralPath (Join-Path $gameRoot 'Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe')).Path
$recorded=@($tools[0].binaries | Where-Object { $_.path -eq $gameExe })
$version=(Get-Item -LiteralPath $gameExe).VersionInfo
if($recorded.Count -ne 1 -or $recorded[0].file_version -ne '1.5.5.0' -or $recorded[0].product_version -ne '1.5.5.0' -or
    $version.FileVersion -ne '1.5.5.0' -or $version.ProductVersion -ne '1.5.5.0' -or
    $version.FileMajorPart -ne 1 -or $version.FileMinorPart -ne 0 -or $version.FileBuildPart -ne 0 -or $version.FilePrivatePart -ne 0) { throw 'The pinned fixed1.0.0.0/display1.5.5.0 tools executable is required.' }
$gameHash=(Get-FileHash -LiteralPath $gameExe).Hash
if($gameHash -ne $recorded[0].sha256) { throw 'The tools executable differs from its discovered hash; no request sent.' }
$games=@(Get-Process KingdomCome -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe })
if($games.Count -ne 1) { throw 'One already-running official tools test world is required; this script never launches a game.' }
$game=$games[0];$gameStarted=$game.StartTime.ToUniversalTime()
function Assert-OwnedEndpoint {
    $listeners=@(Get-NetTCPConnection -LocalPort 1403 -State Listen -ErrorAction Stop)
    if($listeners.Count -ne 1 -or $listeners[0].LocalAddress -ne '127.0.0.1' -or $listeners[0].OwningProcess -ne $game.Id) { throw 'The numeric loopback tools endpoint is not owned by the captured game; no request sent.' }
}
Assert-OwnedEndpoint
$moduleName=if($Patch){'ground_patch.lua'}else{'ground_probe.lua'}
$functionName=if($Patch){'SampleGroundPatch'}else{'ProbeGround'}
$receiptTag=if($Patch){'MineComeGroundPatch'}else{'MineComeGroundProbe'}
$source=(Resolve-Path -LiteralPath (Join-Path $projectRoot ('kcd2/probes/'+$moduleName))).Path
$sourceHash=(Get-FileHash -LiteralPath $source).Hash
$gameLog=Join-Path $gameRoot 'kcd.log'
if(-not (Test-Path -LiteralPath $gameLog)) { throw 'The current tools game log is missing.' }
if($PreflightOnly) { Write-Output 'Read-only preflight passed; no HTTP calls, module loads or process changes made.'; return }

. (Join-Path $projectRoot 'kcd2/tools-http.ps1')
Get-MineComeToolsConsoleBinding | Out-Null
$runToken=[Guid]::NewGuid().ToString('N')
$runDirectory=Join-Path $projectRoot ('runtime/evidence/'+$(if($Patch){'ground-patch-'}else{'ground-probe-'})+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+$runToken)
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$snapshot=Join-Path $runDirectory $moduleName
Copy-Item -LiteralPath $source -Destination $snapshot
$snapshotHash=(Get-FileHash -LiteralPath $snapshot).Hash
if($snapshotHash -ne $sourceHash) { throw 'Probe source changed while copying; no module load attempted.' }
(Get-Item -LiteralPath $snapshot).IsReadOnly=$true
$offset=(Get-Item -LiteralPath $gameLog).Length
$luaPath=$snapshot.Replace('\','/').Replace("'","\'")
$receipt=$null;$contract=$false;$failure=$null;$fresh='';$patchFile=$null;$patchHash=$null

function Assert-SameGame {
    $current=Get-Process -Id $game.Id -ErrorAction Stop
    if($current.Path -ne $gameExe -or $current.StartTime.ToUniversalTime() -ne $gameStarted) { throw 'The captured tools game process changed; diagnostic aborted.' }
}
function Read-FreshLog {
    $stream=[IO.FileStream]::new($gameLog,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        $length=$stream.Length
        if($length -lt $offset -or $length-$offset -gt 8388608) { throw 'The game log changed or exceeded the bounded8MiB diagnostic size.' }
        # Read only this captured extent. Concurrent new records wait for the
        # next poll rather than bypassing the byte cap through ReadToEnd().
        $stream.Position=$offset;$bytes=[byte[]]::new([int]($length-$offset));$read=0
        while($read -lt $bytes.Length) {
            $received=$stream.Read($bytes,$read,$bytes.Length-$read)
            if($received -eq 0) { throw 'The game log was truncated while reading.' }
            $read+=$received
        }
        [Text.Encoding]::UTF8.GetString($bytes)
    } finally { $stream.Dispose() }
}
function Send-Console([string]$Command) {
    Assert-SameGame;Assert-OwnedEndpoint
    Invoke-MineComeToolsRequest -PathAndQuery ('/api/System/Console/ExecuteString?command='+[Uri]::EscapeDataString($Command)) | Out-Null
}
try {
    # Unique immutable path avoids this build's cached LoadScript result. Only
    # our new diagnostic function changes; the live stone sink stays loaded.
    Send-Console ("#local old=MineCome and MineCome.$functionName; Script.LoadScript('$luaPath'); local ok=MineCome and type(MineCome.$functionName)=='function' and MineCome.$functionName~=old; System.LogAlways('[MineComeGroundContract] $runToken '..tostring(not not ok)); if ok then MineCome.$functionName('$runToken') end")
    # The engine can leave its newest log record unterminated. A read-only pose
    # log marker produces the next separator; HTTP200 alone is not a probe result.
    Send-Console ("#System.LogAlways('[MineComeGroundFlush] $runToken')")
    $deadline=[DateTime]::UtcNow.AddSeconds(4)
    do {
        Assert-SameGame;$fresh=Read-FreshLog
        $contract=$fresh -match ('\[MineComeGroundContract\] '+$runToken+' true(?:\r?\n|$)')
        if($fresh -match ('\[MineComeGroundContract\] '+$runToken+' false(?:\r?\n|$)')) { throw 'The unique probe snapshot did not replace its own function.' }
        foreach($match in [regex]::Matches($fresh,('\['+$receiptTag+'\] (\{[^\r\n]*\})\r?\n'))) {
            $candidate=$match.Groups[1].Value | ConvertFrom-Json
            $kindMatches=if($Patch){$candidate.approximate_heightfield -eq $true -and $candidate.full_collision_export_verified -eq $false}else{$candidate.diagnostic_only -eq $true -and $candidate.geometry_export_verified -eq $false}
            if($candidate.schema -eq 1 -and $candidate.run -eq $runToken -and $kindMatches) { $receipt=$candidate }
        }
        if($contract -and $receipt) { break }
        Start-Sleep -Milliseconds 50
    } while([DateTime]::UtcNow -lt $deadline)
    if(-not $contract -or -not $receipt) { throw 'No fresh matching engine probe receipt; HTTP dispatch is not verification.' }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'receipt.json')
    if($Patch) {
        $points=@([regex]::Matches($fresh,'\[MineComeGroundPatchPoint\] (\{[^\r\n]*\})\r?\n') | ForEach-Object { $_.Groups[1].Value | ConvertFrom-Json } | Where-Object { $_.schema -eq 1 -and $_.run -eq $runToken })
        $points | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'points.json')
        if($receipt.stable_player -ne $true -or $receipt.grid_size -ne 5 -or $receipt.spacing -ne 1 -or $receipt.point_count -ne 25 -or $receipt.valid_count -ne 25 -or $points.Count -ne 25 -or
            @($points | Where-Object { $_.valid -ne $true -or $_.approximate_heightfield -ne $true -or $_.full_collision_export_verified -ne $false }).Count -ne 0 -or
            @($points.index | Sort-Object -Unique).Count -ne 25 -or @($points | Where-Object { $_.index -lt 1 -or $_.index -gt 25 }).Count -ne 0) { throw 'The terrain patch was incomplete or the player changed; no movement input file published. See diagnostic receipts.' }
        $patchFile=Join-Path $runDirectory 'ground-patch.json'
        $receipt | Add-Member -NotePropertyName points -NotePropertyValue @($points | Sort-Object index)
        $receipt | Add-Member -NotePropertyName provenance -NotePropertyValue ([pscustomobject]@{kind='live_kcd_ground_patch';game_exe_hash=$gameHash;source_sha256=$snapshotHash;game_pid=$game.Id;game_started_utc=$gameStarted;captured_utc=[DateTime]::UtcNow.ToString('o')})
        $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $patchFile -Encoding utf8
        $patchHash=(Get-FileHash -LiteralPath $patchFile).Hash
        (Get-Item -LiteralPath $patchFile).IsReadOnly=$true
        Write-Output ([pscustomobject]@{GroundPatchFile=$patchFile;EvidenceDirectory=$runDirectory})
    }
    Write-Output ($receipt | ConvertTo-Json -Depth 8)
    Write-Output "Read-only engine diagnostic captured. Full collision export remains unverified. Evidence: $runDirectory"
} catch { $failure=$_.Exception.Message; throw }
finally {
    try { Read-FreshLog | Set-Content -LiteralPath (Join-Path $runDirectory 'fresh-kcd.log') }
    catch { $_.Exception.Message | Set-Content -LiteralPath (Join-Path $runDirectory 'capture-error.txt') }
    [pscustomobject]@{Kind='Read-only KCD2 ground-interface diagnostic';Patch=[bool]$Patch;GroundPatchFile=$patchFile;GroundPatchHash=$patchHash;Run=$runToken;GamePid=$game.Id;GameStartedUtc=$gameStarted;GamePath=$gameExe;GameHash=$gameHash;SourceHash=$sourceHash;SnapshotHash=$snapshotHash;FreshLogOffset=$offset;FunctionReloadVerified=$contract;EngineReceiptVerified=($null -ne $receipt);GeometryExportVerified=$false;PlayerMovementApplied=$false;Failure=$failure} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'verification.json')
}
