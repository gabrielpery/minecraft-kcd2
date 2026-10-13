# Child entry point for the opt-in Minecraft/network fixture; never accesses KCD.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$Run,
    [Parameter(Mandatory)][string]$JavaHome,
    [Parameter(Mandatory)][string]$TokenFile,
    [Parameter(Mandatory)][ValidateRange(1024,65535)][int]$Port
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $EvidenceDirectory.StartsWith((Join-Path $root 'runtime\evidence')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
   -not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)){throw 'Controller-created evidence directory required.'}
if([IO.Path]::GetFullPath($TokenFile) -cne (Join-Path $EvidenceDirectory 'bridge.token')){throw 'Fixture-local token required.'}
$env:JAVA_HOME=$JavaHome
$env:GRADLE_USER_HOME=Join-Path $minecraft '.gradle-user-home'
$exitCode=1
try {
    $arguments=@('-p',$minecraft,'--no-daemon','runClient','-PminecomeAimedBridgeLab',"-PminecomeAimedBridgeRun=$Run",
        "-PminecomeAimedBridgeDirectory=$EvidenceDirectory","-PminecomeAimedBridgeTokenFile=$TokenFile","-PminecomePort=$Port")
    & (Join-Path $minecraft 'gradlew.bat') @arguments 2>&1 | Tee-Object -LiteralPath (Join-Path $EvidenceDirectory 'client.log')
    $exitCode=$LASTEXITCODE
}finally{
    [ordered]@{schema=1;run=$Run;exit_code=$exitCode;ended_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-exit.json') -Encoding utf8NoBOM
}
exit $exitCode
