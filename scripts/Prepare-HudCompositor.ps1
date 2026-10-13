# Workspace staging only. Never executes the installer, writes into a game, or launches a process.
# Config keys inspected in ReShade v6.8.0 source/addon_manager.cpp, source/runtime.cpp
# and source/runtime_gui.cpp. TutorialProgress=4 skips the persistent first-run
# prompt; normal brief startup/loading notices remain enabled.
# Requires PowerShell7.3+ (.NET7 ReadExactly) for bounded HTTP streaming and UTF8 output.
# The bundle remains unarmed: its private addons directory contains no MineComeHud.ini.
# Root's separate controller supplies that short-lived preview configuration later.
#Requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AddonPath,
    [string]$ShaderPath,
    [string]$OutputDirectory,
    [string]$InstallerPath,
    [ValidateSet('Static','Stream','Input','Mouse','World')][string]$Mode='Static',
    [string]$CustomBuildReceipt
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = Join-Path $projectRoot 'runtime'
$sdkCommit = '18deaa52de0c425a78b329e9cb3c497281cd00ec'
$setupUrl = 'https://reshade.me/downloads/ReShade_Setup_6.8.0_Addon.exe'
$setupHash = 'afe4c8f13048306307983b8b3d41d5bf00a86820440b0e57dea10950e1176445'
$runtimeHash = '0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'
$maxArtifactBytes = 64MB
if($Mode -in @('Mouse','World')) {
    if(-not $CustomBuildReceipt -or $InstallerPath){throw 'Mouse/World mode requires its exact custom build receipt and no installer.'}
    . (Join-Path $PSScriptRoot 'HudMouseProfile.ps1')
    $mouseProfile=Get-MineComeMouseProfile -WorldClicks:($Mode -eq 'World')
    $runtimeHash=$mouseProfile.runtime_sha256
} elseif($CustomBuildReceipt){throw 'Custom renderer receipt requires explicit Mouse or World mode.'}
if (-not $ShaderPath) { $ShaderPath = Join-Path $projectRoot $(if($Mode -in @('Mouse','World')){'kcd2/hud/shaders/MineComeMouseHud.fx'}else{'kcd2/hud/shaders/MineComeHud.fx'}) }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $runtimeRoot $(if($Mode -eq 'World'){'hud-compositor-world'}elseif($Mode -eq 'Mouse'){'hud-compositor-mouse'}else{'hud-compositor'}) }
$AddonPath = [IO.Path]::GetFullPath($AddonPath)
$ShaderPath = [IO.Path]::GetFullPath($ShaderPath)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)

function Assert-WorkspaceRuntimePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($runtimeRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'HUD staging/cache destination must be inside this workspace runtime directory.'
    }
    # Refuse existing junction/symlink ancestors so a lexical runtime path cannot write elsewhere.
    $cursor = $full
    while ($cursor -and $cursor.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked HUD staging/cache path refused: $cursor" }
        }
        if ($cursor.Equals($projectRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Get-BytesHash([byte[]]$Bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Read-BoundedFile([string]$Path, [long]$Limit) {
    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt $Limit -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Unexpected artifact type/size: $Path" }
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -ne $item.Length) { throw 'Artifact size changed while opening.' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes)
        if ($stream.ReadByte() -ne -1) { throw 'Artifact changed while reading.' }
        return ,$bytes
    } finally { $stream.Dispose() }
}
function Write-NewOrSame([string]$Path, [byte[]]$Bytes) {
    $Path = Assert-WorkspaceRuntimePath $Path
    if (Test-Path -LiteralPath $Path) {
        $old = Read-BoundedFile $Path $maxArtifactBytes
        if ((Get-BytesHash $old) -cne (Get-BytesHash $Bytes)) { throw "Conflicting existing staging file; choose a new output directory: $Path" }
        return
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $file = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $file.Write($Bytes); $file.Flush($true) } finally { $file.Dispose() }
}
function Get-OfficialInstaller {
    if ($InstallerPath) {
        $bytes = Read-BoundedFile ([IO.Path]::GetFullPath($InstallerPath)) $maxArtifactBytes
        if ((Get-BytesHash $bytes) -cne $setupHash) { throw 'Explicit ReShade installer SHA256 mismatch.' }
        return ,$bytes
    }
    $cache = Assert-WorkspaceRuntimePath (Join-Path $runtimeRoot 'dependencies\reshade-6.8.0\ReShade_Setup_6.8.0_Addon.exe')
    if (Test-Path -LiteralPath $cache) {
        $bytes = Read-BoundedFile $cache $maxArtifactBytes
        if ((Get-BytesHash $bytes) -cne $setupHash) { throw 'Cached ReShade installer SHA256 mismatch; preserved the conflicting file.' }
        return ,$bytes
    }
    Write-Host 'Acquiring pinned official ReShade6.8.0 installer into workspace cache; installer will not execute.'
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false; $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(120)
    $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(120))
    $response = $null; $input = $null; $memory = [IO.MemoryStream]::new()
    try {
        $response = $client.GetAsync($setupUrl, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $deadline.Token).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200) { throw "Official ReShade acquisition returned HTTP$([int]$response.StatusCode); redirects refused." }
        if ($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt $maxArtifactBytes) { throw 'Official installer exceeds64MiB bound.' }
        $input = $response.Content.ReadAsStreamAsync($deadline.Token).GetAwaiter().GetResult()
        $buffer = [byte[]]::new(65536)
        while (($count = $input.ReadAsync($buffer, 0, $buffer.Length, $deadline.Token).GetAwaiter().GetResult()) -gt 0) {
            if ($memory.Length + $count -gt $maxArtifactBytes) { throw 'Official installer exceeds64MiB bound.' }
            $memory.Write($buffer, 0, $count)
        }
        $bytes = $memory.ToArray()
        if ((Get-BytesHash $bytes) -cne $setupHash) { throw 'Downloaded official installer SHA256 mismatch; no cache or bundle was written.' }
        Write-NewOrSame $cache $bytes
        return ,$bytes
    } finally {
        if ($input) { $input.Dispose() }; if ($response) { $response.Dispose() }
        $memory.Dispose(); $deadline.Dispose(); $client.Dispose()
    }
}
function Read-EmbeddedRuntime([byte[]]$Installer) {
    # The pinned installer contains a ZIP overlay; inspect/extract its bytes without executing PE code.
    $record = -1
    for ($index = $Installer.Length - 22; $index -ge [Math]::Max(0, $Installer.Length - 65557); $index--) {
        if ($Installer[$index] -eq 0x50 -and $Installer[$index+1] -eq 0x4b -and $Installer[$index+2] -eq 0x05 -and $Installer[$index+3] -eq 0x06) { $record = $index; break }
    }
    if ($record -lt 0 -or [BitConverter]::ToUInt16($Installer, $record+4) -ne 0 -or [BitConverter]::ToUInt16($Installer, $record+6) -ne 0) { throw 'Pinned installer embedded ZIP is unsupported.' }
    $size = [BitConverter]::ToUInt32($Installer, $record+12)
    $directoryOffset = [BitConverter]::ToUInt32($Installer, $record+16)
    $offset = [long]$record - $size - $directoryOffset
    $length = [long]$record + 22 + [BitConverter]::ToUInt16($Installer, $record+20) - $offset
    if ($offset -lt 0 -or $length -lt 22 -or $length -gt $maxArtifactBytes -or $offset+$length -gt $Installer.Length) { throw 'Invalid embedded ZIP bounds.' }
    $archiveBytes = [byte[]]::new([int]$length)
    [Array]::Copy($Installer, $offset, $archiveBytes, 0, $length)
    $stream = [IO.MemoryStream]::new($archiveBytes, $false)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $entries = @($archive.Entries | Where-Object { $_.FullName -ceq 'ReShade64.dll' })
        if ($entries.Count -ne 1 -or $entries[0].Length -lt 1 -or $entries[0].Length -gt $maxArtifactBytes) { throw 'Expected exactly one bounded ReShade64.dll in pinned installer.' }
        $runtimeBytes = [byte[]]::new([int]$entries[0].Length)
        $entryStream = $entries[0].Open()
        try { $entryStream.ReadExactly($runtimeBytes); if ($entryStream.ReadByte() -ne -1) { throw 'Embedded runtime length mismatch.' } } finally { $entryStream.Dispose() }
        if ((Get-BytesHash $runtimeBytes) -cne $runtimeHash) { throw 'Extracted ReShade64.dll SHA256 mismatch.' }
        return ,$runtimeBytes
    } finally { $archive.Dispose(); $stream.Dispose() }
}

$OutputDirectory = Assert-WorkspaceRuntimePath $OutputDirectory
$addon = Read-BoundedFile $AddonPath $maxArtifactBytes
if ([IO.Path]::GetExtension($AddonPath) -ine '.addon64') { throw 'Provide the built x64 MineCome HUD .addon64 artifact.' }
$shader = Read-BoundedFile $ShaderPath 1MB
$licensePath = Join-Path $projectRoot 'external\reshade\LICENSE.md'
$license = Read-BoundedFile $licensePath 64KB
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$shaderText = $utf8.GetString($shader)
if ($shaderText -notmatch '\btechnique\s+MineComeHud\b') { throw 'Expected original MineComeHud technique was absent.' }
if($Mode -in @('Mouse','World')) {
    $receiptBytes=Read-BoundedFile $CustomBuildReceipt 1MB
    if((Get-BytesHash $receiptBytes) -cne $mouseProfile.build_receipt_sha256){throw 'Custom build receipt differs from the frozen profile.'}
    $custom=$utf8.GetString($receiptBytes) | ConvertFrom-Json
    if($custom.kind -cne 'minecome_mouse_reshade_build_v1' -or $custom.status -cne 'built' -or
       $custom.commit -cne $sdkCommit -or $custom.output_sha256 -ine $runtimeHash -or
       $custom.generated_outputs_unchanged -ne $true){throw 'Verified pinned custom build required.'}
    $runtimeBytes=Read-BoundedFile $custom.output $maxArtifactBytes
    if((Get-BytesHash $runtimeBytes) -cne $runtimeHash -or (Get-BytesHash $addon) -cne $mouseProfile.addon_sha256 -or
       (Get-BytesHash $shader) -cne $mouseProfile.shader_sha256){throw 'Mouse build artifacts differ from the exact tested profile.'}
    # Preserve every upstream/dependency notice and the original patch license.
    $licenseRoot=Join-Path $custom.evidence 'licenses'
    $notices=[Text.StringBuilder]::new()
    foreach($entry in @($custom.license_files)){
        if([IO.Path]::IsPathRooted($entry.path) -or $entry.path -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Invalid custom license path.'}
        $bytes=Read-BoundedFile (Join-Path $licenseRoot $entry.path) 2MB
        if((Get-BytesHash $bytes) -ine $entry.sha256){throw 'Custom license changed after build.'}
        # This pinned upstream notice uses Windows-1252 curly apostrophes;
        # all other notices are strict UTF-8. Transcode without replacement.
        $encoding=if($entry.path.Replace('\','/') -ceq 'deps/d3d12on7/LICENSE.txt'){
            [Text.Encoding]::GetEncoding(1252,[Text.EncoderFallback]::ExceptionFallback,[Text.DecoderFallback]::ExceptionFallback)
        }else{$utf8}
        [void]$notices.AppendLine("===== $($entry.path) =====");[void]$notices.AppendLine($encoding.GetString($bytes))
    }
    if(@($custom.license_files).Count -lt 2){throw 'Custom build has no recorded dependency notices.'}
    $license=$utf8.GetBytes($notices.ToString())
    $licensePath=$licenseRoot
} else {$runtimeBytes = Read-EmbeddedRuntime (Get-OfficialInstaller)}
$relativeFiles = @('dxgi.dll', 'ReShade.ini', 'MineComeHudPreset.ini', 'ReShade-LICENSE.txt', 'bundle.json',
    'minecome-hud\addons\MineComeHudCompositor.addon64', 'minecome-hud\shaders\MineComeHud.fx')
if (Test-Path -LiteralPath $OutputDirectory) {
    foreach ($existing in Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -Force) {
        $relative = [IO.Path]::GetRelativePath($OutputDirectory, $existing.FullName)
        if ($relativeFiles -inotcontains $relative) { throw "Unmanaged file in HUD bundle; refusing mixed shaders/addons: $relative" }
    }
}
$config = @'
[ADDON]
AddonPath=.\minecome-hud\addons

[GENERAL]
EffectSearchPaths=.\minecome-hud\shaders
TextureSearchPaths=.\minecome-hud\textures
PresetPath=.\MineComeHudPreset.ini
PerformanceMode=0
SkipLoadingDisabledEffects=1
NoEffectCache=1

[OVERLAY]
TutorialProgress=4
'@
$preset = "Techniques=MineComeHud@MineComeHud.fx`nTechniqueSorting=MineComeHud@MineComeHud.fx`n"
$artifacts = [ordered]@{
    'dxgi.dll' = $runtimeBytes
    'ReShade.ini' = $utf8.GetBytes($config.Replace("`r`n", "`n") + "`n")
    'MineComeHudPreset.ini' = $utf8.GetBytes($preset)
    'ReShade-LICENSE.txt' = $license
    'minecome-hud\addons\MineComeHudCompositor.addon64' = $addon
    'minecome-hud\shaders\MineComeHud.fx' = $shader
}
# Check all conflicts before creating the first bundle file.
foreach ($relative in $artifacts.Keys) {
    $destination = Assert-WorkspaceRuntimePath (Join-Path $OutputDirectory $relative)
    if (Test-Path -LiteralPath $destination) {
        if ((Get-BytesHash (Read-BoundedFile $destination $maxArtifactBytes)) -cne (Get-BytesHash $artifacts[$relative])) { throw "Conflicting HUD bundle artifact: $destination" }
    }
}
$files = @()
foreach ($relative in $artifacts.Keys) { $files += [ordered]@{ path=$relative.Replace('\','/'); bytes=$artifacts[$relative].Length; sha256=(Get-BytesHash $artifacts[$relative]) } }
$manifest = [ordered]@{
    schema=1; kind='minecome_hud_compositor_bundle_v1'; tools_only=$true; game_installation_modified=$false; game_launched=$false
    runtime=[ordered]@{ version='6.8.0'; acquisition_url=$setupUrl; installer_sha256=$setupHash; reshade64_sha256=$runtimeHash; proxy_name='dxgi.dll'; full_addon_support=$true }
    sdk=[ordered]@{ expected_commit=$sdkCommit; source_root=(Join-Path $projectRoot 'external\reshade'); license_source=$licensePath; license_sha256=(Get-BytesHash $license) }
    original_addon_source=$AddonPath; original_shader_source=$ShaderPath; prepare_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    arm_config_relative_path=$(if($Mode -eq 'World'){'minecome-hud/addons/MineComeHudWorld.ini'}elseif($Mode -eq 'Mouse'){'minecome-hud/addons/MineComeHudMouse.ini'}elseif($Mode -eq 'Input'){'minecome-hud/addons/MineComeHudInput.ini'}elseif($Mode -eq 'Stream'){'minecome-hud/addons/MineComeHudStream.ini'}else{'minecome-hud/addons/MineComeHud.ini'}); preview_armed=$false; live_kcd_compositing_verified=$false
    files=$files
}
if($Mode -in @('Stream','Input','Mouse','World')) {$manifest.stream_protocol=1}
if($Mode -in @('Input','Mouse','World')) {$manifest.ui_input_protocol=1}
if($Mode -in @('Mouse','World')){
    $manifest.mouse_capture_api=1
    if($Mode -eq 'World'){$manifest.world_clicks=$true}
    $manifest.runtime=[ordered]@{version='6.8.0';custom_version=$custom.version;source_commit=$sdkCommit;reshade64_sha256=$runtimeHash;proxy_name='dxgi.dll';full_addon_support=$true;build_receipt=$CustomBuildReceipt;build_receipt_sha256=$mouseProfile.build_receipt_sha256}
    Assert-MineComeMouseBundle $manifest $mouseProfile -WorldClicks:($Mode -eq 'World')
}
$manifestBytes = $utf8.GetBytes(($manifest | ConvertTo-Json -Depth 8) + "`n")
if (Test-Path -LiteralPath (Join-Path $OutputDirectory 'bundle.json')) {
    if ((Get-BytesHash (Read-BoundedFile (Join-Path $OutputDirectory 'bundle.json') 1MB)) -cne (Get-BytesHash $manifestBytes)) { throw 'Conflicting HUD bundle provenance manifest.' }
}
foreach ($relative in $artifacts.Keys) { Write-NewOrSame (Join-Path $OutputDirectory $relative) $artifacts[$relative] }
[IO.Directory]::CreateDirectory((Assert-WorkspaceRuntimePath (Join-Path $OutputDirectory 'minecome-hud\textures'))) | Out-Null
Write-NewOrSame (Join-Path $OutputDirectory 'bundle.json') $manifestBytes
Write-Output "HUD_COMPOSITOR_BUNDLE_READY path=$OutputDirectory runtime=6.8.0 armed=false gameInstallationModified=false"
Write-Output "HUD_COMPOSITOR_BUNDLE_MANIFEST $(Join-Path $OutputDirectory 'bundle.json')"
