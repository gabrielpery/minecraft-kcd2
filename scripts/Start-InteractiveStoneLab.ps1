#requires -Version 7.0
# Uses an already-running official development world; never launches KCD2.
[CmdletBinding()]
param([string]$GameRoot,[string]$JavaHome,[ValidateRange(150,3600)][int]$Seconds=3600,
    [ValidateRange(1,65535)][int]$Port=38765)
& (Join-Path $PSScriptRoot 'Start-BlockMirrorTest.ps1') @PSBoundParameters -Interactive
