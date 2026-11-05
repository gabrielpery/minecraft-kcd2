#Requires -Version 7.3
# Internal child: persistent guest process, separate from every diagnostic save.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceDirectory,[Parameter(Mandatory)][string]$InstanceDirectory,
 [Parameter(Mandatory)][string]$Run,[Parameter(Mandatory)][int]$TargetPid,
 [Parameter(Mandatory)][string]$TargetStart,[Parameter(Mandatory)][long]$Expires,
 [Parameter(Mandatory)][string]$JavaHome,[ValidateSet('','create','resume')][string]$FixturePhase='',
 [switch]$Connected)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$env:JAVA_HOME=$JavaHome
$env:GRADLE_USER_HOME=Join-Path $root 'minecraft/.gradle-user-home'
$arguments=@('-p',(Join-Path $root 'minecraft'),'--offline','runClient','--console=plain',
 '-PminecomeGameplay',"-PminecomeGameplayInstance=$InstanceDirectory",
 "-PminecomeHudStreamDirectory=$(Join-Path $EvidenceDirectory 'capture')",
 "-PminecomeHudStreamRun=$Run","-PminecomeHudStreamTargetPid=$TargetPid",
 "-PminecomeHudStreamTargetStart=$TargetStart","-PminecomeHudStreamExpiresUtcMs=$Expires")
if(-not $Connected){$arguments+='-PminecomeGameplayStandalone'}
if($FixturePhase){$arguments+="-PminecomeGameplayFixture=$FixturePhase"}
$code=1
try{& (Join-Path $root 'minecraft/gradlew.bat') @arguments; $code=$LASTEXITCODE}
finally{[ordered]@{run=$Run;exit_code=$code;ended_utc=[DateTime]::UtcNow.ToString('o')}|
 ConvertTo-Json|Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-exit.json') -Encoding utf8NoBOM}
exit $code
