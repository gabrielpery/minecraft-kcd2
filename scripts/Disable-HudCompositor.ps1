#Requires -Version 5.1
# Original reversible tools-only rollback. Never starts/stops a game or deletes a file.
# Keeps the pinned proxy as dxgi.dll.minecome-disabled; configs, addon, shaders and logs remain.
[CmdletBinding()]
param([string]$BundleDirectory, [switch]$Preview, [switch]$LiveMouse, [switch]$WorldClicks, [switch]$SelectiveMouse)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if($WorldClicks -and -not $LiveMouse){throw 'World rollback requires explicit LiveMouse and WorldClicks.'}
if($SelectiveMouse -and (-not $WorldClicks -or -not $LiveMouse)){throw 'Selective rollback requires explicit LiveMouse and WorldClicks modes.'}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = Join-Path $projectRoot 'runtime'
if (-not $BundleDirectory) { $BundleDirectory = Join-Path $runtimeRoot $(if($SelectiveMouse){'hud-compositor-selective'}elseif($WorldClicks){'hud-compositor-world'}elseif($LiveMouse){'hud-compositor-mouse'}else{'hud-compositor'}) }
$BundleDirectory = [IO.Path]::GetFullPath($BundleDirectory)
$exeHash = 'a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
$proxyHash = '0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'
if($LiveMouse){. (Join-Path $PSScriptRoot 'HudMouseProfile.ps1');$mouseProfile=Get-MineComeMouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse;$proxyHash=$mouseProfile.runtime_sha256}
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-Unlinked([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked rollback path refused: $cursor" }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-BoundedJson([string]$Path) {
    $null = Assert-Unlinked $Path
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -lt 1 -or $stream.Length -gt 1MB) { throw "Unexpected rollback metadata size: $Path" }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $count = $stream.Read($bytes, $offset, $bytes.Length-$offset)
            if ($count -eq 0) { throw 'Rollback metadata was truncated during read.' }
            $offset += $count
        }
        if ($stream.ReadByte() -ne -1) { throw 'Rollback metadata grew during read.' }
        $text = $utf8.GetString($bytes)
        # Windows PowerShell5.1 Set-Content -Encoding UTF8 writes a BOM.
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $text = $text.Substring(1) }
        return ($text | ConvertFrom-Json)
    } finally { $stream.Dispose() }
}
function Assert-GameClosed {
    if (@(Get-Process -Name KingdomCome -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Close Kingdom Come normally before rollback. No process is stopped by this script.' }
}
function Assert-ExactToolsExe {
    $null = Assert-Unlinked $script:gameExe
    $version = (Get-Item -LiteralPath $script:gameExe).VersionInfo
    if ((Get-FileHash -LiteralPath $script:gameExe -Algorithm SHA256).Hash -ine $exeHash -or
        $version.FileVersion -cne '1.5.5.0' -or $version.ProductVersion -cne '1.5.5.0' -or
        $version.FileMajorPart -ne 1 -or $version.FileMinorPart -ne 0 -or $version.FileBuildPart -ne 0 -or $version.FilePrivatePart -ne 0) { throw 'Exact pinned fixed1.0.0.0/display1.5.5.0 official tools executable required.' }
}
function Assert-OwnedProxy([string]$Path) {
    $null = Assert-Unlinked $Path
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer -or $item.Length -ne $script:installedProxyBytes -or
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $proxyHash) { throw "File is not our exact installed ReShade6.8.0 proxy; preserved: $Path" }
}

$BundleDirectory = Assert-Unlinked $BundleDirectory
if (-not $BundleDirectory.StartsWith($runtimeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Bundle ownership receipt must remain inside this workspace runtime.' }
$inventory = Read-BoundedJson (Join-Path $runtimeRoot 'environment.json')
$tools = @($inventory.steam.relevant_apps | Where-Object { $_.role -ceq 'official_tools' -and $_.installed -eq $true -and $_.distribution -ceq 'Steam' -and $_.app_id -eq '2429020' })
if ($tools.Count -ne 1) { throw 'One discovered official Steam tools installation is required.' }
$bin = Assert-Unlinked (Join-Path $tools[0].install_path 'Bin\Win64ReleaseSteamLTO_DLL')
if (-not (Test-Path -LiteralPath $bin -PathType Container)) { throw 'Official tools binary directory is missing.' }
$gameExe = Join-Path $bin 'KingdomCome.exe'
Assert-GameClosed
Assert-ExactToolsExe
$installedReceiptPath = Join-Path $BundleDirectory 'installed.json'
$installed = Read-BoundedJson $installedReceiptPath
if($LiveMouse){Assert-MineComeMouseBundle (Read-BoundedJson (Join-Path $BundleDirectory 'bundle.json')) $mouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse}
if ($installed.schema -ne 1 -or $installed.kind -cne 'minecome_hud_install_v1' -or
    -not ([IO.Path]::GetFullPath($installed.target_exe).Equals($gameExe,[StringComparison]::OrdinalIgnoreCase)) -or
    $installed.exe_sha256 -ine $exeHash -or
    -not ([IO.Path]::GetFullPath($installed.bundle).Equals($BundleDirectory,[StringComparison]::OrdinalIgnoreCase))) { throw 'Installation receipt does not identify this owned official tools deployment.' }
$proxyRecords = @($installed.files | Where-Object { $_.path -ceq 'dxgi.dll' })
if ($proxyRecords.Count -ne 1 -or $proxyRecords[0].sha256 -cne $proxyHash -or
    ($proxyRecords[0].bytes -isnot [int] -and $proxyRecords[0].bytes -isnot [long]) -or
    $proxyRecords[0].bytes -lt 1 -or $proxyRecords[0].bytes -gt 64MB) { throw 'Installation receipt lacks the exact bounded owned DXGI proxy record.' }
$installedProxyBytes = [long]$proxyRecords[0].bytes
$source = Assert-Unlinked (Join-Path $bin 'dxgi.dll')
$destination = Assert-Unlinked (Join-Path $bin 'dxgi.dll.minecome-disabled')
# Verify final absolute move targets within the exact verified binary directory.
if (-not ([IO.Path]::GetDirectoryName($source).Equals($bin,[StringComparison]::OrdinalIgnoreCase)) -or
    -not ([IO.Path]::GetDirectoryName($destination).Equals($bin,[StringComparison]::OrdinalIgnoreCase))) { throw 'Rollback move target escaped the official tools binary directory.' }
$sourceExists = Test-Path -LiteralPath $source
$destinationExists = Test-Path -LiteralPath $destination
if ($sourceExists -and $destinationExists) { throw 'Both active and disabled proxy paths exist; both were preserved. Resolve that conflict explicitly.' }
if (-not $sourceExists -and -not $destinationExists) { throw 'Neither owned proxy path exists; no game file was changed.' }
if ($sourceExists) { Assert-OwnedProxy $source; $status = 'would_disable' }
else { Assert-OwnedProxy $destination; $status = 'already_disabled' }
if ($Preview) {
    [pscustomobject]@{schema=1;kind='minecome_hud_rollback_preview_v1';status=$status;source=$source;disabled_path=$destination;sha256=$proxyHash;game_closed=$true;files_changed=$false} | ConvertTo-Json -Depth 4
    Write-Output 'HUD_DISABLE_PREVIEW_PASS files_changed=false receipt_written=false'
    return
}
$evidenceRoot = Assert-Unlinked (Join-Path $runtimeRoot 'evidence')
$run = [guid]::NewGuid().ToString('N')
$receiptDirectory = Assert-Unlinked (Join-Path $evidenceRoot ('hud-rollback-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
if (-not $receiptDirectory.StartsWith($evidenceRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Rollback receipt escaped workspace evidence.' }
[IO.Directory]::CreateDirectory($receiptDirectory) | Out-Null
$renamed = $false
$failure = $null
try {
    Assert-GameClosed
    Assert-ExactToolsExe
    if ($sourceExists) {
        Assert-OwnedProxy $source
        if (Test-Path -LiteralPath $destination) { throw 'Disabled destination appeared during rollback; no overwrite attempted.' }
        # Two-argument File.Move is available on .NET Framework and never overwrites.
        [IO.File]::Move($source,$destination)
        $renamed = $true
    } elseif (Test-Path -LiteralPath $source) { throw 'An active proxy appeared during idempotent rollback; preserved it.' }
    Assert-OwnedProxy $destination
    $status = $(if ($renamed) { 'disabled' } else { 'already_disabled' })
} catch {
    $status = 'failed'; $failure = $_.Exception.Message
    throw
} finally {
    $receipt = [ordered]@{
        schema=1;kind='minecome_hud_rollback_v1';run=$run;utc=[DateTime]::UtcNow.ToString('o');status=$status
        tools_exe=$gameExe;tools_exe_sha256=$exeHash;installation_receipt=$installedReceiptPath
        installation_receipt_sha256=(Get-FileHash -LiteralPath $installedReceiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
        source=$source;disabled_path=$destination;proxy_sha256=$proxyHash;proxy_bytes=$installedProxyBytes;renamed=$renamed;failure=$failure
        game_launched=$false;game_stopped=$false;configs_deleted=$false;addon_deleted=$false;evidence_preserved=$true;default_startup_verified=$false
    }
    $bytes = $utf8.GetBytes(($receipt | ConvertTo-Json -Depth 5)+"`n")
    $receiptFile = Join-Path $receiptDirectory 'rollback.json'
    $file = [IO.FileStream]::new($receiptFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $file.Write($bytes,0,$bytes.Length);$file.Flush($true) } finally { $file.Dispose() }
}
Write-Output "HUD_COMPOSITOR_DISABLED status=$status renamed=$renamed default_startup_verified=false"
Write-Output "HUD_ROLLBACK_RECEIPT $(Join-Path $receiptDirectory 'rollback.json')"
