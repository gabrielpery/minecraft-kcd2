#Requires -Version 7.3
# Original bounded stream arm. Input mode still requires a physical F8 latch.
# No game launch, movement or process injection.
[CmdletBinding()]
param([string]$ReadyManifest, [string]$BundleDirectory, [switch]$PreflightOnly, [switch]$InputMode, [switch]$OffscreenPresentation, [switch]$LiveMouse, [switch]$StoneLive, [switch]$WorldClicks, [switch]$SelectiveMouse, [ValidateSet(1,2)][int]$SelectiveRevision=1)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($OffscreenPresentation -and -not $InputMode){throw 'Offscreen presentation requires explicit input mode.'}
if($LiveMouse -and (-not $InputMode -or -not $OffscreenPresentation)){throw 'Live mouse requires explicit input mode and offscreen presentation.'}
if($StoneLive -and (-not $LiveMouse -or -not $InputMode -or -not $OffscreenPresentation)){throw 'Combined stone arming requires the explicit live mouse profile.'}
if($WorldClicks -and (-not $LiveMouse -or -not $StoneLive)){throw 'World clicks require explicit LiveMouse and StoneLive modes.'}
if($SelectiveMouse -and (-not $WorldClicks -or -not $LiveMouse)){throw 'Selective mouse requires explicit LiveMouse and WorldClicks modes.'}
if($SelectiveRevision -eq 2 -and -not $SelectiveMouse){throw 'Selective revision 2 arming requires explicit SelectiveMouse mode.'}
. (Join-Path $PSScriptRoot 'KcdToolsProbeHelpers.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot=Join-Path $root 'runtime'
$evidenceRoot=Join-Path $runtimeRoot 'evidence'
if(-not $BundleDirectory) {$BundleDirectory=Join-Path $runtimeRoot $(if($SelectiveMouse -and $SelectiveRevision -eq 2){'hud-compositor-selective-r2'}elseif($SelectiveMouse){'hud-compositor-selective'}elseif($WorldClicks){'hud-compositor-world'}elseif($LiveMouse){'hud-compositor-mouse'}elseif($InputMode){'hud-compositor-input-waitfix'}else{'hud-compositor-stream'})}
$expectedArm=if($SelectiveMouse){'minecome-hud/addons/MineComeHudSelective.ini'}elseif($WorldClicks){'minecome-hud/addons/MineComeHudWorld.ini'}elseif($LiveMouse){'minecome-hud/addons/MineComeHudMouse.ini'}elseif($InputMode){'minecome-hud/addons/MineComeHudInput.ini'}else{'minecome-hud/addons/MineComeHudStream.ini'}
$exeHash='a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a'
$proxyHash='0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'
if($LiveMouse){. (Join-Path $PSScriptRoot 'HudMouseProfile.ps1');$mouseProfile=Get-MineComeMouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision;$proxyHash=$mouseProfile.runtime_sha256}
$expected=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
function Assert-Unlinked([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path);$cursor=$full
    while($cursor) {
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw "Linked stream path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}
function Read-Receipt([string]$Path) {
    $null=Assert-Unlinked $Path
    if((Get-Item -LiteralPath $Path).Length -gt 64KB) {throw 'Stream metadata exceeds64KiB.'}
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 10)
}
function Assert-Artifact([string]$Path,$Record) {
    $null=Assert-Unlinked $Path
    if($Record.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $Record.bytes -lt 1 -or $Record.bytes -gt 64MB) {throw 'Invalid stream artifact record.'}
    $item=Get-Item -LiteralPath $Path
    if($item.PSIsContainer -or $item.Length -ne $Record.bytes -or (Get-FileHash -LiteralPath $Path).Hash -ine $Record.sha256) {throw "Stream artifact hash/size mismatch: $Path"}
}
$BundleDirectory=Assert-Unlinked $BundleDirectory
if(-not $BundleDirectory.StartsWith($runtimeRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Stream bundle must remain in workspace runtime.'}
$bundle=Read-Receipt (Join-Path $BundleDirectory 'bundle.json')
if($LiveMouse){Assert-MineComeMouseBundle $bundle $mouseProfile -WorldClicks:$WorldClicks -SelectiveMouse:$SelectiveMouse -SelectiveRevision $SelectiveRevision}
elseif($bundle.PSObject.Properties.Name -contains 'mouse_capture_api' -or $bundle.PSObject.Properties.Name -contains 'world_clicks' -or $bundle.PSObject.Properties.Name -contains 'selective_mouse' -or $bundle.PSObject.Properties.Name -contains 'selective_revision'){throw 'Mouse/world/selective bundle requires its explicit mode.'}
if($bundle.schema -ne 1 -or $bundle.kind -cne 'minecome_hud_compositor_bundle_v1' -or $bundle.stream_protocol -ne 1 -or $bundle.tools_only -ne $true -or $bundle.runtime.version -cne '6.8.0' -or $bundle.runtime.reshade64_sha256 -cne $proxyHash -or $bundle.arm_config_relative_path -cne $expectedArm -or @($bundle.files).Count -ne 6) {throw 'An exact prepared stream bundle is required.'}
if($InputMode){if($bundle.PSObject.Properties.Name -notcontains 'ui_input_protocol' -or $bundle.ui_input_protocol -ne 1){throw 'Input mode requires explicit protocol1 provenance.'}}
elseif($bundle.PSObject.Properties.Name -contains 'ui_input_protocol'){throw 'Input bundle requires explicit InputMode.'}
$context=Get-MineComeProbeContext
if($context.GameHash -ine $exeHash) {throw 'Pinned official tools executable required.'}
$bin=Assert-Unlinked ([IO.Path]::GetDirectoryName($context.GamePath))
$installed=Read-Receipt (Join-Path $BundleDirectory 'installed.json')
if($installed.kind -cne 'minecome_hud_install_v1' -or $installed.exe_sha256 -cne $exeHash -or -not ([IO.Path]::GetFullPath($installed.target_exe).Equals($context.GamePath,[StringComparison]::OrdinalIgnoreCase)) -or @($installed.files).Count -ne 6) {throw 'Owned stream installation receipt required.'}
foreach($relative in $expected) {
    $records=@($bundle.files | Where-Object {$_.path -ceq $relative})
    $owned=@($installed.files | Where-Object {$_.path -ceq $relative})
    if($records.Count -ne 1 -or $owned.Count -ne 1 -or $owned[0].sha256 -cne $records[0].sha256 -or $owned[0].bytes -ne $records[0].bytes) {throw 'Bundle and installed stream receipts differ.'}
    Assert-Artifact (Join-Path $BundleDirectory $relative) $records[0]
    Assert-Artifact (Join-Path $bin $relative) $records[0]
}
$addonRecord=@($bundle.files | Where-Object {$_.path -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'})[0]
Assert-Artifact $bundle.original_addon_source $addonRecord
$addonPath=Join-Path $bin 'minecome-hud/addons/MineComeHudCompositor.addon64'
$proxyPath=Join-Path $bin 'dxgi.dll'
function Assert-LoadedStream {
    Assert-MineComeProbeContext $context
    $game=Get-Process -Id $context.GamePid
    try {
        $modules=@($game.Modules)
        if(@($modules | Where-Object {$_.FileName -ieq $addonPath}).Count -ne 1 -or @($modules | Where-Object {$_.FileName -ieq $proxyPath}).Count -ne 1 -or @($modules | Where-Object {$_.ModuleName -ieq 'CryRenderD3D12.dll' -and $_.FileName.StartsWith($context.GameRoot+'\',[StringComparison]::OrdinalIgnoreCase)}).Count -ne 1) {throw 'Prepared stream addon, pinned proxy and official D3D12 renderer must already be loaded.'}
    } finally {$game.Dispose()}
    Assert-Artifact $addonPath $addonRecord
}
Assert-LoadedStream
$armPath=Assert-Unlinked (Join-Path $bin $bundle.arm_config_relative_path)
foreach($name in @('MineComeHud.ini','MineComeHudStream.ini','MineComeHudInput.ini','MineComeHudMouse.ini','MineComeHudWorld.ini','MineComeHudSelective.ini')){
    if(Test-Path -LiteralPath (Join-Path $bin ('minecome-hud/addons/'+$name))){throw 'Existing HUD arm preserved; ownership-checked cleanup is required first.'}
}
if($PreflightOnly) {Write-Output 'HUD_STREAM_ARM_PREFLIGHT_PASS no_changes=true';return}
if(-not $ReadyManifest) {throw 'A fresh actual Minecraft stream-ready.json is required.'}
$ReadyManifest=Assert-Unlinked $ReadyManifest
if(-not $ReadyManifest.StartsWith($evidenceRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($ReadyManifest) -cne 'stream-ready.json') {throw 'Readiness must come from workspace stream evidence.'}
$ready=Read-Receipt $ReadyManifest
if($InputMode){
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_protocol' -or $ready.ui_input_protocol -ne 1){throw 'Input mode requires explicit genuine guest readiness.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_fixture' -or $ready.ui_input_fixture -isnot [bool] -or $ready.ui_input_fixture -ne $false){throw 'Fixture producer cannot arm live KCD input.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_delay_fixture' -or $ready.ui_input_delay_fixture -isnot [bool] -or $ready.ui_input_delay_fixture -ne $false){throw 'Delay fixture cannot arm live KCD input.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_background_trial' -or $ready.ui_input_background_trial -isnot [bool] -or $ready.ui_input_background_trial -ne $false){throw 'Background trial cannot arm live KCD input.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_offscreen_trial' -or $ready.ui_input_offscreen_trial -isnot [bool] -or $ready.ui_input_offscreen_trial -ne $false){throw 'Offscreen fixture trial cannot arm live KCD input.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_offscreen_presentation' -or $ready.ui_input_offscreen_presentation -isnot [bool] -or $ready.ui_input_offscreen_presentation -ne [bool]$OffscreenPresentation){throw 'Offscreen presentation requires matching explicit input mode.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_pointer_fixture' -or $ready.ui_input_pointer_fixture -isnot [bool] -or $ready.ui_input_pointer_fixture -ne $false){throw 'Pointer fixture cannot arm live KCD input.'}
    if($ready.PSObject.Properties.Name -notcontains 'ui_input_live_mouse' -or $ready.ui_input_live_mouse -isnot [bool] -or $ready.ui_input_live_mouse -ne [bool]$LiveMouse){throw 'Live mouse requires matching explicit guest readiness.'}
    foreach($field in @('ui_input_stone_bridge','ui_input_stone_fixture','ui_input_stone_live')){
        $expectedStone=$field -ne 'ui_input_stone_fixture' -and [bool]$StoneLive
        if($ready.PSObject.Properties.Name -notcontains $field){if($StoneLive){throw 'Live stone readiness marker missing.'};continue}
        if($ready.$field -isnot [bool] -or $ready.$field -ne $expectedStone){throw 'Combined HUD stone readiness does not match explicit live mode.'}
    }
}
elseif($ready.PSObject.Properties.Name -contains 'ui_input_protocol'){throw 'Input producer requires explicit InputMode.'}
$start=$context.GameStartedUtc.ToFileTimeUtc().ToString()
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
if($ready.schema -ne 1 -or $ready.run -cnotmatch '^[0-9a-f]{32}$' -or $ready.source_kind -cne 'minecraft_vanilla_ui_stream_v1' -or $ready.mapping_bytes -ne 8294656 -or $ready.mapping_name -cne ('Local\MineComeHud_'+$ready.run) -or $ready.mutex_name -cne ('Local\MineComeHudLock_'+$ready.run) -or [string]$ready.target_pid -cne [string]$context.GamePid -or [string]$ready.target_start_filetime -cne $start -or $ready.expires_utc_ms -le $now -or $ready.expires_utc_ms-$now -gt 180000 -or [string]$ready.producer_start_filetime -cnotmatch '^[1-9][0-9]{0,19}$') {throw 'Fresh stream session identity/lease mismatch.'}
$producer=Get-Process -Id $ready.producer_pid
try {
    if($producer.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne [string]$ready.producer_start_filetime -or $producer.ProcessName -cne 'java') {throw 'Actual Minecraft producer identity changed.'}
} finally {$producer.Dispose()}
$processInfo=Get-CimInstance Win32_Process -Filter "ProcessId=$([uint32]$ready.producer_pid)"
if($processInfo.CommandLine -notmatch 'net\.fabricmc\.devlaunchinjector\.Main' -or $processInfo.CommandLine -notlike ('*'+(Join-Path $root 'minecraft')+'*')) {throw 'Readiness producer is not this workspace Fabric client.'}
$text=@('[HudStream]','Schema=1',"Run=$($ready.run)","TargetPid=$($context.GamePid)","TargetStart=$start","ProducerPid=$($ready.producer_pid)","ProducerStart=$($ready.producer_start_filetime)","ExpiresUtcMs=$($ready.expires_utc_ms)") -join "`n"
$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text+"`n")
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
$evidenceDirectory=[IO.Path]::GetDirectoryName($ReadyManifest)
$receipt=[ordered]@{schema=1;kind='minecome_hud_stream_arm_v1';run=$ready.run;game_pid=$context.GamePid;game_start_filetime=$start;producer_pid=$ready.producer_pid;producer_start_filetime=$ready.producer_start_filetime;expires_utc_ms=$ready.expires_utc_ms;arm_path=$armPath;arm_sha256=$hash;bundle=$BundleDirectory;addon_sha256=$addonRecord.sha256;visual_verified=$false;interactive_inventory_verified=$false;game_launched=$false}
$receipt.live_mouse=[bool]$LiveMouse
$receipt.stone_live=[bool]$StoneLive
$receipt.world_clicks=[bool]$WorldClicks
$receipt.selective_mouse=[bool]$SelectiveMouse
if($SelectiveRevision -eq 2){$receipt.selective_revision=2}
$receiptPath=Join-Path $evidenceDirectory 'stream-arming.json'
if(Test-Path -LiteralPath $receiptPath) {throw 'Existing stream arm receipt preserved.'}
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
$temporary=$armPath+'.'+$ready.run+'.tmp'
try {
    $file=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$file.Write($bytes);$file.Flush($true)} finally {$file.Dispose()}
    Assert-LoadedStream
    if([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $ready.expires_utc_ms) {throw 'Stream expired before atomic arming.'}
    [IO.File]::Move($temporary,$armPath,$false)
} finally {
    if((Test-Path -LiteralPath $temporary) -and (Get-FileHash -LiteralPath $temporary).Hash -ieq $hash) {Remove-Item -LiteralPath $temporary}
}
Write-Output $receipt
