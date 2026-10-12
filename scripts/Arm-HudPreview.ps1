#Requires -Version 7.3
# Original bounded STATIC Minecraft UI preview. No game launch, Lua request, input, or movement calls.
# Writes only the config beside our exact installed addon after all process/artifact gates pass.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CaptureManifest,
    [string]$BundleDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$evidenceRoot = Join-Path $projectRoot 'runtime\evidence'
if (-not $BundleDirectory) { $BundleDirectory = Join-Path $projectRoot 'runtime\hud-compositor' }
$BundleDirectory = [IO.Path]::GetFullPath($BundleDirectory)
$CaptureManifest = [IO.Path]::GetFullPath($CaptureManifest)
$runtimeHash = '0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'
$expectedExeHash = 'a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
$expectedFiles = @('dxgi.dll', 'ReShade.ini', 'MineComeHudPreset.ini', 'ReShade-LICENSE.txt',
    'minecome-hud/addons/MineComeHudCompositor.addon64', 'minecome-hud/shaders/MineComeHud.fx')
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Assert-UnlinkedPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked path refused: $cursor" }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Assert-ConfinedEvidence([string]$Path) {
    $full = Assert-UnlinkedPath $Path
    if (-not $full.StartsWith($evidenceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Capture files must remain inside this workspace runtime/evidence.' }
    return $full
}
function Read-BoundedArtifact([string]$Path, [long]$Limit) {
    $null = Assert-UnlinkedPath $Path
    $file = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($file.Length -lt 1 -or $file.Length -gt $Limit) { throw "Artifact exceeds its byte bound: $Path" }
        $bytes = [byte[]]::new([int]$file.Length)
        $file.ReadExactly($bytes, 0, $bytes.Length)
        if ($file.ReadByte() -ne -1) { throw 'Artifact length changed during read.' }
        return ,$bytes
    } finally { $file.Dispose() }
}
function Get-ArtifactHash([byte[]]$Bytes) { return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant() }
function Read-JsonArtifact([string]$Path, [long]$Limit) {
    $bytes = Read-BoundedArtifact $Path $Limit
    $text = $utf8.GetString($bytes)
    if ($text.Length -eq 0 -or $text[0] -eq [char]0xfeff) { throw 'Unexpected empty/BOM JSON artifact.' }
    return [pscustomobject]@{ Bytes=$bytes; Hash=(Get-ArtifactHash $bytes); Value=($text | ConvertFrom-Json -Depth 20) }
}
function Assert-Integer($Value, [long]$Min, [long]$Max, [string]$Name) {
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Min -or $Value -gt $Max) { throw "Expected bounded integer: $Name" }
}
function Assert-Bool($Value, [bool]$Expected, [string]$Name) {
    if ($Value -isnot [bool] -or $Value -ne $Expected) { throw "Unexpected boolean contract: $Name" }
}

$null = Assert-UnlinkedPath $evidenceRoot
$CaptureManifest = Assert-ConfinedEvidence $CaptureManifest
$null = Assert-UnlinkedPath $BundleDirectory
if (-not $BundleDirectory.StartsWith((Join-Path $projectRoot 'runtime') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Bundle must be inside this workspace runtime.' }
$captureFile = Read-JsonArtifact $CaptureManifest 64KB
$capture = $captureFile.Value
Assert-Integer $capture.schema 1 1 'capture.schema'
Assert-Integer $capture.frames 3 3 'capture.frames'
if ($capture.source_kind -cne 'minecraft_vanilla_ui_v1' -or $capture.run -cnotmatch '^[0-9a-f]{32}$' -or
    $capture.world -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
    $capture.save -cne ('MineCome-Hud-' + $capture.world) -or $capture.minecraft_version -cne '1.21.1' -or
    $capture.yarn_mappings -cne '1.21.1+build.3' -or $capture.capture_backend -cne 'opengl_three_pixel_pack_buffers' -or
    $capture.alpha_mode -cne 'straight_rgba8' -or $capture.pixel_format -cne 'rgba8' -or $capture.origin -cne 'top_left' -or
    $capture.graphics_mode -cne 'fast' -or $capture.ordinary_alpha_blend -cne 'source_over' -or $capture.result -cne 'passed' -or
    @($capture.frame_records).Count -ne 3) { throw 'Unsupported genuine HUD capture manifest contract.' }
foreach ($field in @('vanilla_render_path', 'world_render_suppressed', 'hand_render_suppressed')) { Assert-Bool $capture.$field $true $field }
Assert-Bool $capture.kcd_compositing_verified $false 'capture.kcd_compositing_verified'
$captureParent = [IO.Path]::GetDirectoryName($CaptureManifest)
$framePaths = @(); $frameHashes = @(); $frameProof = @(); $width = 0; $height = 0
$states = @('hotbar_slot0','hotbar_slot1','inventory_screen')
$items = @('minecraft:stone','minecraft:dirt','minecraft:cobblestone','minecraft:oak_planks','minecraft:stick','minecraft:apple','minecraft:torch','minecraft:diamond','minecraft:iron_pickaxe')
$counts = @(64,32,16,8,3,2,12,1,1)
for ($i = 0; $i -lt 3; $i++) {
    $frame = $capture.frame_records[$i]
    Assert-Integer $frame.frame_id ($i+1) ($i+1) 'frame_id'
    Assert-Integer $frame.width 1 1920 'frame.width'; Assert-Integer $frame.height 1 1080 'frame.height'
    Assert-Integer $frame.row_pitch ($frame.width*4) ($frame.width*4) 'frame.row_pitch'
    $selected = $(if ($i -eq 0) { 0 } else { 1 })
    Assert-Integer $frame.selected_slot $selected $selected 'frame.selected_slot'
    if ($frame.state -cne $states[$i] -or ($i -lt 2 -and $frame.screen_kind -cne 'none') -or
        ($i -eq 2 -and $frame.screen_kind -cnotin @('InventoryScreen','CreativeInventoryScreen'))) { throw 'Frame state/screen order changed.' }
    Assert-Bool $frame.client_server_inventory_confirmed $true 'client_server_inventory_confirmed'
    Assert-Bool $frame.no_world_pixels $true 'no_world_pixels'; Assert-Bool $frame.hand_pixels $false 'hand_pixels'
    if ($i -eq 0) { $width=$frame.width; $height=$frame.height }
    elseif ($width -ne $frame.width -or $height -ne $frame.height) { throw 'All three preview frames must have identical canvas dimensions.' }
    foreach ($inventoryField in @('client_slots','server_slots')) {
        $slots = @($frame.$inventoryField)
        if ($slots.Count -ne 9) { throw 'Expected nine actual vanilla inventory slots.' }
        for ($slot = 0; $slot -lt 9; $slot++) {
            Assert-Integer $slots[$slot].slot $slot $slot 'inventory.slot'
            Assert-Integer $slots[$slot].count $counts[$slot] $counts[$slot] 'inventory.count'
            if ($slots[$slot].item -cne $items[$slot]) { throw 'Actual client/server inventory metadata differs from the captured fixture.' }
        }
    }
    $prefix = 'hud-{0:D4}' -f ($i+1)
    if ($frame.rgba_file -cne ($prefix+'.rgba') -or $frame.png_file -cne ($prefix+'.png') -or
        $frame.rgba_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $frame.png_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Frame names/hashes are not canonical.' }
    $rawPath = Assert-ConfinedEvidence (Join-Path $captureParent $frame.rgba_file)
    $raw = Read-BoundedArtifact $rawPath (1920*1080*4)
    if ($raw.Length -ne $width*$height*4 -or (Get-ArtifactHash $raw) -cne $frame.rgba_sha256) { throw 'Raw captured RGBA bytes/size/SHA256 differ.' }
    $pngPath = Assert-ConfinedEvidence (Join-Path $captureParent $frame.png_file)
    $png = Read-BoundedArtifact $pngPath 16MB
    if ((Get-ArtifactHash $png) -cne $frame.png_sha256) { throw 'Captured companion PNG SHA256 differs.' }
    $pixels = [long]$width*$height
    foreach ($countName in @('transparent_pixels','partial_alpha_pixels','opaque_pixels')) { Assert-Integer $frame.$countName 0 $pixels $countName }
    if ($frame.transparent_pixels+$frame.partial_alpha_pixels+$frame.opaque_pixels -ne $pixels -or
        ($i -lt 2 -and ($frame.transparent_pixels -lt $pixels/2 -or $frame.partial_alpha_pixels+$frame.opaque_pixels -eq 0))) { throw 'Captured alpha counts violate transparent HUD bounds.' }
    $framePaths += $rawPath; $frameHashes += $frame.rgba_sha256
    $frameProof += [ordered]@{ id=$i+1; raw_path=$rawPath; raw_bytes=$raw.Length; raw_sha256=$frame.rgba_sha256; png_sha256=$frame.png_sha256; state=$frame.state; selected_slot=$selected }
}

$bundleFile = Read-JsonArtifact (Join-Path $BundleDirectory 'bundle.json') 64KB
$bundle = $bundleFile.Value
Assert-Integer $bundle.schema 1 1 'bundle.schema'; Assert-Bool $bundle.tools_only $true 'bundle.tools_only'
if ($bundle.kind -cne 'minecome_hud_compositor_bundle_v1' -or $bundle.runtime.version -cne '6.8.0' -or
    $bundle.runtime.reshade64_sha256 -cne $runtimeHash -or @($bundle.files).Count -ne $expectedFiles.Count -or
    $bundle.arm_config_relative_path -cne 'minecome-hud/addons/MineComeHud.ini') { throw 'Unexpected pinned HUD bundle contract.' }
$context = Get-MineComeProbeContext
if ($context.GameHash -ine $expectedExeHash) { throw 'The native HUD add-on requires the exact pinned tools executable, regardless of the environment inventory.' }
$bin = [IO.Path]::GetDirectoryName($context.GamePath)
$null = Assert-UnlinkedPath $bin
$installedHashes = [ordered]@{}
foreach ($relative in $expectedFiles) {
    $records = @($bundle.files | Where-Object { $_.path -ceq $relative })
    if ($records.Count -ne 1 -or $records[0].sha256 -cnotmatch '^[0-9a-f]{64}$') { throw "Missing/duplicate bounded bundle artifact: $relative" }
    $record = $records[0]; Assert-Integer $record.bytes 1 64MB 'bundle.artifact.bytes'
    $staged = Read-BoundedArtifact (Join-Path $BundleDirectory $relative) 64MB
    $installed = Read-BoundedArtifact (Join-Path $bin $relative) 64MB
    if ($staged.Length -ne $record.bytes -or $installed.Length -ne $record.bytes -or
        (Get-ArtifactHash $staged) -cne $record.sha256 -or (Get-ArtifactHash $installed) -cne $record.sha256) { throw "Staged/installed artifact SHA256 differs: $relative" }
    $installedHashes[$relative] = $record.sha256
}
if ($installedHashes['dxgi.dll'] -cne $runtimeHash) { throw 'Installed DXGI proxy differs from pinned official runtime.' }
$builtAddon = Read-BoundedArtifact $bundle.original_addon_source 64MB
if ((Get-ArtifactHash $builtAddon) -cne $installedHashes['minecome-hud/addons/MineComeHudCompositor.addon64']) { throw 'Addon differs from the original built artifact recorded at preparation.' }
$expectedProxy = [IO.Path]::GetFullPath((Join-Path $bin 'dxgi.dll'))
$expectedAddon = [IO.Path]::GetFullPath((Join-Path $bin 'minecome-hud/addons/MineComeHudCompositor.addon64'))
$moduleProof = $null
function Assert-LoadedHudModules {
    Assert-MineComeProbeContext $context
    $process = Get-Process -Id $context.GamePid -ErrorAction Stop
    try { $modules = @($process.Modules) } catch { throw 'Cannot enumerate exact graphics modules; preview remains unarmed.' }
    $proxy = @($modules | Where-Object { [IO.Path]::GetFullPath($_.FileName).Equals($expectedProxy,[StringComparison]::OrdinalIgnoreCase) })
    $addon = @($modules | Where-Object { [IO.Path]::GetFullPath($_.FileName).Equals($expectedAddon,[StringComparison]::OrdinalIgnoreCase) })
    $renderer = @($modules | Where-Object { $_.ModuleName -ieq 'CryRenderD3D12.dll' })
    if ($proxy.Count -ne 1 -or $addon.Count -ne 1 -or $renderer.Count -ne 1) { throw 'Exact installed ReShade/addon and CryRenderD3D12 must already be loaded; no game is launched.' }
    $rendererPath = Assert-UnlinkedPath $renderer[0].FileName
    if (-not $rendererPath.StartsWith($context.GameRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Renderer module lies outside the verified official tools installation.' }
    if ((Get-FileHash -LiteralPath $expectedProxy -Algorithm SHA256).Hash -ine $runtimeHash -or
        (Get-FileHash -LiteralPath $expectedAddon -Algorithm SHA256).Hash -ine $installedHashes['minecome-hud/addons/MineComeHudCompositor.addon64']) { throw 'Loaded graphics module path no longer has the pinned file bytes.' }
    return [ordered]@{ proxy=$expectedProxy; proxy_sha256=$runtimeHash; addon=$expectedAddon; addon_sha256=$installedHashes['minecome-hud/addons/MineComeHudCompositor.addon64']; renderer=$rendererPath; renderer_sha256=(Get-FileHash -LiteralPath $rendererPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$moduleProof = Assert-LoadedHudModules
$armPath = Assert-UnlinkedPath (Join-Path ([IO.Path]::GetDirectoryName($expectedAddon)) 'MineComeHud.ini')
if (Test-Path -LiteralPath $armPath) { throw 'Existing HUD arm configuration preserved. This native preview accepts one run per game process; use the separate ownership-aware cleanup before a later process.' }
$run = [guid]::NewGuid().ToString('N')
$createdUtc = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$expiresUtc = $createdUtc + 40000
$startFiletime = $context.GameStartedUtc.ToFileTimeUtc().ToString([Globalization.CultureInfo]::InvariantCulture)
$configLines = @('[HudPreview]','Schema=1',"Run=$run","TargetPid=$($context.GamePid)","TargetStart=$startFiletime","ExpiresUtcMs=$expiresUtc",'FrameCount=3',"Width=$width","Height=$height")
for ($i=0;$i -lt 3;$i++) { $configLines += "Frame$($i+1)=$($framePaths[$i])"; $configLines += "Sha256_$($i+1)=$($frameHashes[$i])" }
$configBytes = $utf8.GetBytes(($configLines -join "`n") + "`n")
if ($configBytes.Length -gt 32768) { throw 'Preview config exceeds native32KiB contract.' }
$directory = Assert-ConfinedEvidence (Join-Path $evidenceRoot ('hud-preview-arm-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+$run))
[IO.Directory]::CreateDirectory($directory) | Out-Null
$evidence = [ordered]@{
    schema=1; kind='minecome_hud_preview_arm_v1'; run=$run; captured_run=$capture.run; captured_world=$capture.world
    game_pid=$context.GamePid; game_start_filetime=$startFiletime; game_path=$context.GamePath; game_sha256=$context.GameHash.ToLowerInvariant()
    capture_manifest=$CaptureManifest; capture_manifest_sha256=$captureFile.Hash; bundle=$BundleDirectory; bundle_manifest_sha256=$bundleFile.Hash
    arm_path=$armPath; arm_sha256=(Get-ArtifactHash $configBytes); created_utc_ms=$createdUtc; expires_utc_ms=$expiresUtc; lease_ms=40000
    modules=$moduleProof; installed_hashes=$installedHashes; frames=$frameProof; width=$width; height=$height
    static_snapshot=$true; visual_verified=$false; live_streaming_verified=$false; interactive_inventory_verified=$false; movement_or_input_applied=$false; game_launched=$false
}
[IO.File]::WriteAllBytes((Join-Path $directory 'arming.json'),$utf8.GetBytes(($evidence|ConvertTo-Json -Depth 10)+"`n"))
$temporary = Assert-UnlinkedPath ($armPath+'.'+$run+'.tmp')
try {
    $file = [IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $file.Write($configBytes, 0, $configBytes.Length); $file.Flush($true) } finally { $file.Dispose() }
    $null = Assert-LoadedHudModules
    if ((Get-FileHash -LiteralPath $context.GamePath -Algorithm SHA256).Hash -ine $context.GameHash -or [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $expiresUtc) { throw 'Process artifact changed or preview expired before atomic arming.' }
    # No overwrite: the consumer sees either no config or the complete verified original config.
    [IO.File]::Move($temporary,$armPath,$false)
} finally {
    if (Test-Path -LiteralPath $temporary) {
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ieq $evidence.arm_sha256) { Remove-Item -LiteralPath $temporary }
    }
}
Write-Output "HUD_PREVIEW_ARMED run=$run target_pid=$($context.GamePid) lease_ms=40000 static_snapshot=true visual_verified=false"
Write-Output "HUD_PREVIEW_ARM_EVIDENCE $directory"
