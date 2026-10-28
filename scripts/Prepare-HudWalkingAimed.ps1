#Requires -Version 7.3
# Workspace staging only; reuses the frozen selective r4 runtime and notices.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AddonPath,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'HudWalkingAimedProfile.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profile=Get-MineComeWalkingAimedProfile
$base=Join-Path $root 'runtime/hud-compositor-selective-r4'
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'runtime/hud-compositor-walking-aimed'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith((Join-Path $root 'runtime')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Walking aimed bundle must remain in workspace runtime.'}
function Assert-StagingPath([string]$Path){
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked walking aimed staging path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
foreach($path in @($OutputDirectory,$AddonPath,$base)){Assert-StagingPath $path}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Existing walking aimed bundle preserved; choose a fresh output directory.'}
$manifestPath=Join-Path $base 'bundle.json';Assert-StagingPath $manifestPath
if((Get-Item -LiteralPath $manifestPath).Length -gt 64KB){throw 'Base bundle metadata exceeds64KiB.'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$baseProfile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
Assert-MineComeMouseBundle $manifest $baseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
$addon=Get-Item -LiteralPath $AddonPath
if($addon.PSIsContainer -or $addon.Length -lt 1 -or $addon.Length -gt 64MB -or $addon.Extension -ine '.addon64' -or
    (Get-FileHash -LiteralPath $AddonPath).Hash -ine $profile.addon_sha256){throw 'Walking aimed add-on differs from its frozen build.'}
$expected=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
if((@($manifest.files.path | Sort-Object) -join '|') -cne (($expected | Sort-Object) -join '|')){throw 'Unexpected r4 bundle paths.'}
# Validate every source before creating anything; no existing destination is overwritten.
$entries=@()
foreach($entry in $manifest.files){
    $source=Join-Path $base $entry.path;Assert-StagingPath $source
    $item=Get-Item -LiteralPath $source
    if($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt 64MB -or $item.Length -ne $entry.bytes -or
        (Get-FileHash -LiteralPath $source).Hash -ine $entry.sha256){throw 'Frozen r4 staging source differs.'}
    $hash=$entry.sha256;$bytes=$entry.bytes
    if($entry.path -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'){$source=$AddonPath;$hash=$profile.addon_sha256;$bytes=$addon.Length}
    $entries += [pscustomobject]@{path=$entry.path;source=$source;sha256=$hash;bytes=$bytes}
}
$manifest.ui_input_protocol=2
$manifest.arm_config_relative_path='minecome-hud/addons/MineComeHudWalkingAimed.ini'
$manifest.original_addon_source=[IO.Path]::GetFullPath($AddonPath)
$manifest.prepare_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
$manifest | Add-Member -NotePropertyName base_bundle -NotePropertyValue 'hud-compositor-selective-r4'
$manifest | Add-Member -NotePropertyName physical_movement -NotePropertyValue $true
$manifest | Add-Member -NotePropertyName walking_aimed -NotePropertyValue $true
$manifest.files=@($entries | ForEach-Object {[pscustomobject]@{path=$_.path;bytes=$_.bytes;sha256=$_.sha256}})
Assert-MineComeWalkingAimedBundle $manifest $profile
foreach($entry in $entries){
    $target=Join-Path $OutputDirectory $entry.path;Assert-StagingPath $target
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy($entry.source,$target,$false)
    if((Get-Item -LiteralPath $target).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $target).Hash -ine $entry.sha256){throw 'Copied walking aimed artifact differs.'}
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'bundle.json') -Encoding utf8NoBOM
Write-Output "HUD_WALKING_AIMED_PREPARED bundle=$OutputDirectory no_game_changes=true"
