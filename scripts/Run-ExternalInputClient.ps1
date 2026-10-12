#requires -Version 7.0
# SPDX-License-Identifier: GPL-3.0-or-later
# Internal foreground-independent launcher for one new owned Minecraft lab.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][string]$PatchFile,
    [Parameter(Mandatory)][string]$ViewSeedFile,
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$InputRun,
    [Parameter(Mandatory)][ValidateRange(1,4294967295)][long]$TargetPid,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$TargetStartFiletime,
    [Parameter(Mandatory)][string]$JavaHome,
    [switch]$Fixture
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$env:JAVA_HOME=(Resolve-Path -LiteralPath $JavaHome).Path
$env:GRADLE_USER_HOME=Join-Path $minecraft '.gradle-user-home'
$arguments=@('-p',$minecraft,'--no-daemon','runClient','-PminecomeExternalInputLab',
    "-PminecomeGroundPatchFile=$PatchFile","-PminecomeExternalInputViewFile=$ViewSeedFile","-PminecomeExternalInputFile=$InputFile",
    "-PminecomeExternalInputRun=$InputRun","-PminecomeExternalInputTargetPid=$TargetPid",
    "-PminecomeExternalInputTargetStartFiletime=$TargetStartFiletime")
if($Fixture) { $arguments+='-PminecomeExternalInputFixture' }
& (Join-Path $minecraft 'gradlew.bat') @arguments 2>&1 |
    Tee-Object -FilePath (Join-Path $EvidenceDirectory 'minecraft.log')
$code=$LASTEXITCODE
if($code -ne 0) { throw "Owned Minecraft lab exited with code $code." }
