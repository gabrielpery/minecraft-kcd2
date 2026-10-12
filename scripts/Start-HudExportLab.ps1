#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Captures genuine vanilla UI in a new owned Minecraft world; never launches KCD.
[CmdletBinding()]
param([string]$JavaHome=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
if(-not $JavaHome) {
    $inventory=Get-Content -LiteralPath (Join-Path $root 'runtime/environment.json') -Raw|ConvertFrom-Json
    foreach($candidate in @($inventory.java.jdks|ForEach-Object home)) {
        if((Test-Path -LiteralPath (Join-Path $candidate 'release')) -and
            [IO.File]::ReadAllText((Join-Path $candidate 'release')) -match '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') {$JavaHome=$candidate;break}
    }
}
if(-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/javac.exe')) -or
    [IO.File]::ReadAllText((Join-Path $JavaHome 'release')) -notmatch '(?m)^JAVA_VERSION="(?:21|24)(?:[.+-]|")') {throw 'An installed tested JDK21 or24 is required.'}
$clients=@(Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'"|Where-Object {
    $_.CommandLine -match 'net\.fabricmc\.devlaunchinjector\.Main' -and $_.CommandLine -like ('*'+$minecraft+'*')
})
if($clients.Count) {throw 'An existing MineCome development client is open; preserving it.'}
$directory=Join-Path $root ('runtime/evidence/hud-export-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory|Out-Null
$capture=Join-Path $directory 'capture'
$oldJava=$env:JAVA_HOME;$oldGradle=$env:GRADLE_USER_HOME
try {
    $env:JAVA_HOME=$JavaHome;$env:GRADLE_USER_HOME=Join-Path $minecraft '.gradle-user-home'
    Write-Output "Capturing three genuine vanilla UI states in a fresh world. Evidence: $directory"
    & (Join-Path $minecraft 'gradlew.bat') -p $minecraft --no-daemon runClient '-PminecomeHudExportLab' "-PminecomeHudExportDirectory=$capture" 2>&1 | Tee-Object -LiteralPath (Join-Path $directory 'client.log')
    if($LASTEXITCODE -ne 0) {throw "Minecraft/Gradle exited with code $LASTEXITCODE; see client.log."}
    $manifestPath=Join-Path $capture 'hud-export.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($manifest.schema -ne 1 -or $manifest.result -ne 'passed' -or $manifest.frames -ne 3 -or
        $manifest.source_kind -ne 'minecraft_vanilla_ui_v1' -or $manifest.alpha_mode -ne 'straight_rgba8' -or $manifest.origin -ne 'top_left' -or
        $manifest.kcd_compositing_verified -ne $false) {throw 'Minecraft HUD capture did not complete its three-state proof.'}
    foreach($frame in $manifest.frame_records) {
        if($frame.rgba_file -cne ('hud-{0:d4}.rgba' -f [int]$frame.frame_id)) {throw 'Unexpected capture file name.'}
        $raw=Join-Path $capture $frame.rgba_file
        if((Get-Item -LiteralPath $raw).Length -ne ([long]$frame.width*$frame.height*4) -or
            (Get-FileHash -LiteralPath $raw).Hash -ine $frame.rgba_sha256 -or $frame.client_server_inventory_confirmed -ne $true) {throw 'HUD capture hash, dimensions or actual inventory evidence differs.'}
    }
    Write-Output "HUD_EXPORT_VERIFIED manifest=$manifestPath frames=3 kcd_compositing_verified=false"
} finally {$env:JAVA_HOME=$oldJava;$env:GRADLE_USER_HOME=$oldGradle}
