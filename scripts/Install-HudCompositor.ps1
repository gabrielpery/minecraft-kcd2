#requires -Version 5.1
# SPDX-License-Identifier: GPL-3.0-or-later
# Explicit tools-only deployment. Does not start/stop games or replace existing files.
[CmdletBinding()]
param([string]$BundleDirectory,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $BundleDirectory){$BundleDirectory=Join-Path $root 'runtime/hud-compositor'}
$BundleDirectory=(Resolve-Path -LiteralPath $BundleDirectory).Path
$inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw|ConvertFrom-Json
$tools=@($inventory.steam.relevant_apps|Where-Object {$_.role -eq 'official_tools' -and $_.installed -and $_.app_id -eq '2429020' -and $_.distribution -eq 'Steam'})
if($tools.Count -ne 1){throw 'One discovered official Steam tools installation is required.'}
$bin=(Resolve-Path -LiteralPath (Join-Path $tools[0].install_path 'Bin/Win64ReleaseSteamLTO_DLL')).Path
$exe=Join-Path $bin 'KingdomCome.exe'
$expectedExe='A32D077E6B54E5CD0C5A5F3194F473779706FF266A711E4745CCDB598843340A'
$version=(Get-Item -LiteralPath $exe).VersionInfo
if((Get-FileHash -LiteralPath $exe).Hash -cne $expectedExe -or $version.FileVersion -ne '1.5.5.0' -or $version.ProductVersion -ne '1.5.5.0') {throw 'Unsupported tools executable; no deployment performed.'}
function Assert-Unlinked([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked path refused: $cursor"}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
Assert-Unlinked $BundleDirectory
Assert-Unlinked $bin
$manifestPath=Join-Path $BundleDirectory 'bundle.json'
if((Get-Item -LiteralPath $manifestPath).Length -gt 1MB){throw 'Oversized bundle manifest.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$expected=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
if($manifest.schema -ne 1 -or $manifest.kind -cne 'minecome_hud_compositor_bundle_v1' -or $manifest.tools_only -ne $true -or
    @($manifest.files).Count -ne $expected.Count -or $manifest.runtime.version -cne '6.8.0' -or
    $manifest.runtime.reshade64_sha256 -cne '0cee63f9c9f13f3ac909c5b4903f4dbb4b719a7ab3b4f13b0deaf83c814b94f7'){throw 'Unexpected compositor bundle contract.'}
$entries=@()
foreach($relative in $expected){
    $record=@($manifest.files|Where-Object {$_.path -ceq $relative})
    if($record.Count -ne 1 -or $record[0].sha256 -cnotmatch '^[0-9a-f]{64}$' -or $record[0].bytes -lt 1 -or $record[0].bytes -gt 64MB){throw "Invalid bundle record: $relative"}
    $source=Join-Path $BundleDirectory $relative;$target=Join-Path $bin $relative
    Assert-Unlinked $source;Assert-Unlinked $target
    if((Get-Item -LiteralPath $source).Length -ne $record[0].bytes -or (Get-FileHash -LiteralPath $source).Hash -ine $record[0].sha256){throw "Bundle artifact differs: $relative"}
    if($relative -ceq 'dxgi.dll' -and $record[0].sha256 -cne $manifest.runtime.reshade64_sha256){throw 'Runtime record differs from the pinned DLL.'}
    if(Test-Path -LiteralPath $target){throw "Existing game file preserved; resolve the conflict before deployment: $target"}
    $entries+=[pscustomobject]@{Source=$source;Target=$target;Hash=$record[0].sha256;Relative=$relative}
}
if(Test-Path -LiteralPath (Join-Path $bin 'minecome-hud')){throw 'Existing MineCome HUD directory preserved; refusing a mixed installation.'}
if($PreflightOnly){Write-Output "HUD_INSTALL_PREFLIGHT_PASS target=$bin files=$($entries.Count) no_changes=true";return}
if(@(Get-Process KingdomCome -ErrorAction SilentlyContinue|Where-Object {$_.Path -ieq $exe}).Count){throw 'Close the official tools game normally before installing the renderer component. No files were changed.'}
if((Get-FileHash -LiteralPath $exe).Hash -cne $expectedExe){throw 'Tools executable changed during preflight.'}
$created=[Collections.Generic.List[string]]::new()
try {
    foreach($entry in $entries){
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($entry.Target))|Out-Null
        [IO.File]::Copy($entry.Source,$entry.Target,$false);$created.Add($entry.Target)
        if((Get-FileHash -LiteralPath $entry.Target).Hash -ine $entry.Hash){throw "Installed file hash differs: $($entry.Relative)"}
    }
    [ordered]@{schema=1;kind='minecome_hud_install_v1';installed_utc=[DateTime]::UtcNow.ToString('o');target_exe=$exe;exe_sha256=$expectedExe;bundle=$BundleDirectory;files=$manifest.files;armed=$false;game_launched=$false;live_kcd_compositing_verified=$false}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $BundleDirectory 'installed.json') -Encoding utf8
    Write-Output "HUD_INSTALLED_UNARMED target=$bin files=$($entries.Count) game_launched=false"
} catch {
    # Remove only exact files just created by this invocation, never a pre-existing file.
    foreach($path in $created){
        $resolved=[IO.Path]::GetFullPath($path)
        if(-not $resolved.StartsWith($bin+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Rollback path escaped the verified game binary directory.'}
        $entry=@($entries|Where-Object {$_.Target -ceq $resolved})
        if((Test-Path -LiteralPath $resolved) -and $entry.Count -eq 1 -and (Get-FileHash -LiteralPath $resolved).Hash -ieq $entry[0].Hash){Remove-Item -LiteralPath $resolved}
    }
    throw
}
