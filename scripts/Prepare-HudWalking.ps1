#Requires -Version 7.3
# Stage only: reuse the exact frozen r4 runtime and notices with a separately built add-on.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AddonPath,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'HudPhysicalMovement.ps1')
. (Join-Path $PSScriptRoot 'HudGroundMovement.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$profile=Get-MineComePhysicalMovementProfile
$base=Join-Path $root 'runtime/hud-compositor-selective-r4'
$manifest=Get-Content -LiteralPath (Join-Path $base 'bundle.json') -Raw | ConvertFrom-Json
$baseProfile=Get-MineComeMouseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
Assert-MineComeMouseBundle $manifest $baseProfile -WorldClicks -SelectiveMouse -SelectiveRevision 4
if(-not $OutputDirectory){$OutputDirectory=Join-Path $root 'runtime/hud-compositor-walking'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith((Join-Path $root 'runtime')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Walking bundle must remain in workspace runtime.'}
foreach($path in @($OutputDirectory,$AddonPath,$base)){
    $cursor=[IO.Path]::GetFullPath($path)
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Linked staging path refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Existing walking bundle preserved; choose a fresh output directory.'}
if((Get-FileHash -LiteralPath $AddonPath).Hash -ine $profile.addon_sha256){throw 'Walking add-on does not match its frozen build.'}
$files=@()
$expected=@('dxgi.dll','ReShade.ini','MineComeHudPreset.ini','ReShade-LICENSE.txt','minecome-hud/addons/MineComeHudCompositor.addon64','minecome-hud/shaders/MineComeHud.fx')
if((@($manifest.files.path | Sort-Object) -join '|') -cne (($expected | Sort-Object) -join '|')){throw 'Unexpected r4 bundle paths.'}
foreach($entry in $manifest.files){
    $source=Join-Path $base $entry.path
    $cursor=[IO.Path]::GetFullPath($source)
    while($cursor){
        if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked r4 staging source refused.'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if((Get-Item -LiteralPath $source).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $source).Hash -ine $entry.sha256){throw 'Prepared r4 artifact changed.'}
    if($entry.path -ceq 'minecome-hud/addons/MineComeHudCompositor.addon64'){$source=$AddonPath}
    $target=Join-Path $OutputDirectory $entry.path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy($source,$target,$false)
    $files+= [pscustomobject]@{path=$entry.path;bytes=(Get-Item -LiteralPath $target).Length;sha256=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant()}
}
foreach($field in @('world_clicks','selective_mouse','selective_revision')){$manifest.PSObject.Properties.Remove($field)}
$manifest.ui_input_protocol=2
$manifest.arm_config_relative_path='minecome-hud/addons/MineComeHudMovement.ini'
$manifest.original_addon_source=[IO.Path]::GetFullPath($AddonPath)
$manifest.prepare_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
$manifest | Add-Member -NotePropertyName base_bundle -NotePropertyValue 'hud-compositor-selective-r4'
$manifest.files=$files
$manifest | Add-Member -NotePropertyName physical_movement -NotePropertyValue $true
Assert-MineComePhysicalMovementBundle $manifest $profile
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'bundle.json') -Encoding utf8NoBOM
Write-Output "HUD_WALKING_PREPARED bundle=$OutputDirectory no_game_changes=true"
