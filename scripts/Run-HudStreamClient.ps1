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
    [switch]$LiveMouse,
    [switch]$InputFixture,
    [switch]$InputPointerFixture,
    [switch]$StoneFixture,
    [switch]$StoneLive,
    [switch]$AimedStone,
    [string]$StoneTokenFile,
    [ValidateRange(1,65535)][int]$StonePort=38765,
    [switch]$InputDelayFixture,
    [switch]$InputBackgroundTrial,
    [switch]$OffscreenPresentation,
    [switch]$InputOffscreenTrial,
    [switch]$Standalone,
    [switch]$GroundMovementFixture,
    [string]$GroundPatchFile
)
$ErrorActionPreference='Stop'
function Assert-HudGroundChildMode([bool]$Fixture,[bool]$Standalone,[string]$Patch,[bool]$OtherMode) {
    if($Fixture -and (-not $Standalone -or -not $Patch -or $OtherMode)){throw 'Ground movement fixture requires standalone HUD stream and its synthetic patch only.'}
    if(-not $Fixture -and $Patch){throw 'Ground patch requires the explicit ground movement fixture.'}
}
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
    if($AimedStone -and (-not $StoneLive -or $StoneFixture)){throw 'Aimed stone requires the explicit live stone profile.'}
    if($StoneFixture -and ($StoneLive -or -not $InputFixture -or -not $InputOffscreenTrial -or $LiveMouse -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or -not $StoneTokenFile)){throw 'Stone fixture requires separate offscreen input fixture and explicit token.'}
    if($StoneLive -and ($StoneFixture -or -not $InputMode -or -not $LiveMouse -or -not $OffscreenPresentation -or $InputFixture -or $InputOffscreenTrial -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or -not $StoneTokenFile)){throw 'Live stone bridge requires the explicit live mouse profile and its owned relay token.'}
    if(-not $StoneFixture -and -not $StoneLive -and ($StoneTokenFile -or $PSBoundParameters.ContainsKey('StonePort'))){throw 'Stone connection arguments require an explicit stone mode.'}
    if($LiveMouse -and (-not $InputMode -or $InputFixture -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial -or -not $OffscreenPresentation)){throw 'Live mouse requires non-fixture input mode with OffscreenPresentation.'}
    if($InputFixture -and -not $InputMode){throw 'Input fixture requires the separate UI input mode.'}
    if($InputPointerFixture -and (-not $InputFixture -or $InputDelayFixture -or $InputBackgroundTrial)){throw 'Pointer fixture requires standalone input without delay/background trials.'}
    if($InputDelayFixture -and -not $InputFixture){throw 'Controlled input delays require the standalone fixture.'}
    if($InputBackgroundTrial -and (-not $InputFixture -or $InputDelayFixture)){throw 'Background timing requires a standalone fixture without synthetic delays.'}
    if($OffscreenPresentation -and (-not $InputMode -or $InputBackgroundTrial -or $InputDelayFixture)){throw 'Offscreen presentation requires UI input mode without other timing trials.'}
    if($InputOffscreenTrial -and (-not $InputFixture -or -not $OffscreenPresentation)){throw 'Offscreen timing requires an explicit offscreen standalone fixture.'}
    Assert-HudGroundChildMode ([bool]$GroundMovementFixture) ([bool]$Standalone) $GroundPatchFile ([bool]($InputMode -or $LiveMouse -or $InputFixture -or $InputPointerFixture -or $StoneFixture -or $StoneLive -or $AimedStone -or $InputDelayFixture -or $InputBackgroundTrial -or $OffscreenPresentation -or $InputOffscreenTrial))
    $arguments=@('-p',$minecraft,'--no-daemon','runClient','-PminecomeHudStreamLab',"-PminecomeHudStreamRun=$Run","-PminecomeHudStreamTargetPid=$TargetPid","-PminecomeHudStreamTargetStart=$TargetStart","-PminecomeHudStreamExpiresUtcMs=$ExpiresUtcMs","-PminecomeHudStreamDirectory=$producerDirectory","-PminecomeHudStreamWidth=$Width","-PminecomeHudStreamHeight=$Height","-PminecomeHudStreamGuiScale=$GuiScale")
    if($Standalone){$arguments+='-PminecomeHudStreamStandalone'}
    if($GroundMovementFixture){$arguments+=@('-PminecomeHudGroundMovementFixture',"-PminecomeGroundPatchFile=$GroundPatchFile")}
    if($InputMode){$arguments+='-PminecomeHudStreamInput'}
    if($LiveMouse){$arguments+='-PminecomeHudStreamLiveMouse'}
    if($InputFixture){$arguments+='-PminecomeHudStreamInputFixture'}
    if($InputPointerFixture){$arguments+='-PminecomeHudStreamInputPointerFixture'}
    if($StoneFixture){$arguments+=@('-PminecomeHudStoneBridge','-PminecomeHudStoneFixture',"-PminecomeTokenFile=$StoneTokenFile","-PminecomePort=$StonePort")}
    if($StoneLive){$arguments+=@('-PminecomeHudStoneBridge','-PminecomeHudStoneLive',"-PminecomeTokenFile=$StoneTokenFile","-PminecomePort=$StonePort")}
    if($AimedStone){$arguments+='-PminecomeHudAimedStoneBridge'}
    if($InputDelayFixture){$arguments+='-PminecomeHudStreamInputDelayFixture'}
    if($InputBackgroundTrial){$arguments+='-PminecomeHudStreamBackgroundTrial'}
    if($OffscreenPresentation){$arguments+='-PminecomeHudStreamOffscreenPresentation'}
    if($InputOffscreenTrial){$arguments+='-PminecomeHudStreamOffscreenTrial'}
    & (Join-Path $minecraft 'gradlew.bat') @arguments 2>&1 | Tee-Object -LiteralPath (Join-Path $EvidenceDirectory 'client.log')
    $exitCode=$LASTEXITCODE
} finally {
    [ordered]@{schema=1;run=$Run;exit_code=$exitCode;ended_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-exit.json') -Encoding utf8NoBOM
}
exit $exitCode
