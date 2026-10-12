#Requires -Version 7.3
# Original child-process entry point; starts only the isolated Minecraft HUD lab.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$Run,
    [Parameter(Mandatory)][uint32]$TargetPid,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$TargetStart,
    [Parameter(Mandatory)][long]$ExpiresUtcMs,
    [Parameter(Mandatory)][string]$JavaHome,
    [ValidateRange(320,1920)][int]$Width=1280,
    [ValidateRange(240,1080)][int]$Height=720,
    [ValidateRange(1,4)][int]$GuiScale=2,
    [switch]$InputMode,
    [switch]$InputFixture
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$minecraft=Join-Path $root 'minecraft'
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $EvidenceDirectory.StartsWith((Join-Path $root 'runtime\evidence')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Child evidence must remain in workspace runtime/evidence.'}
if(-not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) {throw 'Controller must create the evidence directory.'}
$env:JAVA_HOME=$JavaHome
$env:GRADLE_USER_HOME=Join-Path $minecraft '.gradle-user-home'
$producerDirectory=Join-Path $EvidenceDirectory 'capture'
$exitCode=1
try {
    if($InputFixture -and -not $InputMode){throw 'Input fixture requires the separate UI input mode.'}
    $arguments=@('-p',$minecraft,'--no-daemon','runClient','-PminecomeHudStreamLab',"-PminecomeHudStreamRun=$Run","-PminecomeHudStreamTargetPid=$TargetPid","-PminecomeHudStreamTargetStart=$TargetStart","-PminecomeHudStreamExpiresUtcMs=$ExpiresUtcMs","-PminecomeHudStreamDirectory=$producerDirectory","-PminecomeHudStreamWidth=$Width","-PminecomeHudStreamHeight=$Height","-PminecomeHudStreamGuiScale=$GuiScale")
    if($InputMode){$arguments+='-PminecomeHudStreamInput'}
    if($InputFixture){$arguments+='-PminecomeHudStreamInputFixture'}
    & (Join-Path $minecraft 'gradlew.bat') @arguments 2>&1 | Tee-Object -LiteralPath (Join-Path $EvidenceDirectory 'client.log')
    $exitCode=$LASTEXITCODE
} finally {
    [ordered]@{schema=1;run=$Run;exit_code=$exitCode;ended_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-exit.json') -Encoding utf8NoBOM
}
exit $exitCode
