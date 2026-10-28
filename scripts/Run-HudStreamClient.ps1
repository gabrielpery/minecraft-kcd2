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
    [switch]$GroundMovementCoupled,
    [string]$GroundPatchFile,
    [string]$MovementTraceFile,
    [switch]$PhysicalMovement,
    [switch]$PhysicalMovementFixture,
    [switch]$ExtendedWalking,
    [switch]$WideWalking,
    [switch]$AimedBlocks,
    [switch]$WalkingAimed,
    [ValidateRange(-180,180)][double]$PhysicalFixtureYaw=0,
    [string]$HostViewFile
)
$ErrorActionPreference='Stop'
function Assert-HudGroundChildMode([bool]$Fixture,[bool]$Standalone,[string]$Patch,[bool]$OtherMode,[bool]$Coupled=$false,[string]$Trace='') {
    if(($Fixture -and $Coupled) -or (($Fixture -or $Coupled) -and (-not $Standalone -or -not $Patch -or $OtherMode))){throw 'Ground movement requires exactly one standalone HUD movement mode and its patch.'}
    if(-not ($Fixture -or $Coupled) -and $Patch){throw 'Ground patch requires explicit HUD ground movement.'}
    if(($Coupled -and -not $Trace) -or (-not $Coupled -and $Trace)){throw 'Movement trace requires explicit coupled HUD mode.'}
}
function Assert-HudWalkingAimedChildMode([bool]$AimedBlocks,[bool]$Standalone,[bool]$PhysicalFixture,[bool]$ExtendedWalking,[bool]$OtherMode,[double]$Yaw=0) {
    if($AimedBlocks -and (-not $Standalone -or -not $PhysicalFixture -or -not $ExtendedWalking -or $OtherMode -or -not [double]::IsFinite($Yaw) -or $Yaw -ne 0)){
        throw 'Combined aimed blocks require only the standalone extended physical controller fixture at zero yaw.'
    }
}
function Assert-HudWalkingAimedLiveChildMode([bool]$WalkingAimed,[bool]$ExtendedWalking,[bool]$InputMode,[bool]$LiveMouse,[bool]$OffscreenPresentation,[bool]$OtherMode,[string]$Patch,[string]$Trace,[string]$View,[string]$Token) {
    if($WalkingAimed -and (-not $ExtendedWalking -or -not $InputMode -or -not $LiveMouse -or -not $OffscreenPresentation -or $OtherMode -or
        -not $Patch -or -not $Trace -or -not $View -or -not $Token)){throw 'Combined live walking/aiming requires its explicit extended input, terrain, view and owned relay profile.'}
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
    Assert-HudWalkingAimedLiveChildMode ([bool]$WalkingAimed) ([bool]$ExtendedWalking) ([bool]$InputMode) ([bool]$LiveMouse) ([bool]$OffscreenPresentation) ([bool]($Standalone -or $PhysicalMovement -or $PhysicalMovementFixture -or $AimedBlocks -or $StoneFixture -or $StoneLive -or $AimedStone -or $GroundMovementFixture -or $GroundMovementCoupled -or $InputFixture -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial)) $GroundPatchFile $MovementTraceFile $HostViewFile $StoneTokenFile
    Assert-HudWalkingAimedChildMode ([bool]$AimedBlocks) ([bool]$Standalone) ([bool]$PhysicalMovementFixture) ([bool]$ExtendedWalking) ([bool]($PhysicalMovement -or $InputMode -or $LiveMouse -or $OffscreenPresentation -or $GroundMovementFixture -or $GroundMovementCoupled -or $InputFixture -or $InputPointerFixture -or $StoneFixture -or $StoneLive -or $AimedStone -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial)) $PhysicalFixtureYaw
    if($ExtendedWalking -and -not ($PhysicalMovement -or $PhysicalMovementFixture -or $WalkingAimed)){throw 'Extended walking requires an explicit physical movement profile.'}
    if($WideWalking -and -not ($PhysicalMovement -or $PhysicalMovementFixture -or $WalkingAimed -or $GroundMovementCoupled)){throw 'Wide walking requires an explicit physical or scripted coupled HUD movement profile.'}
    if($WideWalking -and $PhysicalMovementFixture -and -not $ExtendedWalking){throw 'Wide walking fixture requires ExtendedWalking.'}
    if($AimedStone -and (-not $StoneLive -or $StoneFixture)){throw 'Aimed stone requires the explicit live stone profile.'}
    if($StoneFixture -and ($StoneLive -or -not $InputFixture -or -not $InputOffscreenTrial -or $LiveMouse -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or -not $StoneTokenFile)){throw 'Stone fixture requires separate offscreen input fixture and explicit token.'}
    if($StoneLive -and ($StoneFixture -or -not $InputMode -or -not $LiveMouse -or -not $OffscreenPresentation -or $InputFixture -or $InputOffscreenTrial -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or -not $StoneTokenFile)){throw 'Live stone bridge requires the explicit live mouse profile and its owned relay token.'}
    if(-not $StoneFixture -and -not $StoneLive -and -not $WalkingAimed -and ($StoneTokenFile -or $PSBoundParameters.ContainsKey('StonePort'))){throw 'Stone connection arguments require an explicit stone mode.'}
    if($LiveMouse -and (-not $InputMode -or $InputFixture -or $InputPointerFixture -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial -or -not $OffscreenPresentation)){throw 'Live mouse requires non-fixture input mode with OffscreenPresentation.'}
    if($InputFixture -and -not $InputMode){throw 'Input fixture requires the separate UI input mode.'}
    if($InputPointerFixture -and (-not $InputFixture -or $InputDelayFixture -or $InputBackgroundTrial)){throw 'Pointer fixture requires standalone input without delay/background trials.'}
    if($InputDelayFixture -and -not $InputFixture){throw 'Controlled input delays require the standalone fixture.'}
    if($InputBackgroundTrial -and (-not $InputFixture -or $InputDelayFixture)){throw 'Background timing requires a standalone fixture without synthetic delays.'}
    if($OffscreenPresentation -and (-not $InputMode -or $InputBackgroundTrial -or $InputDelayFixture)){throw 'Offscreen presentation requires UI input mode without other timing trials.'}
    if($InputOffscreenTrial -and (-not $InputFixture -or -not $OffscreenPresentation)){throw 'Offscreen timing requires an explicit offscreen standalone fixture.'}
    if($PhysicalMovementFixture){
        if(-not $Standalone -or -not $GroundPatchFile -or -not $MovementTraceFile -or -not $HostViewFile -or
            $PhysicalMovement -or $InputMode -or $LiveMouse -or $OffscreenPresentation -or $GroundMovementFixture -or $GroundMovementCoupled -or $InputFixture -or $InputPointerFixture -or $StoneFixture -or $StoneLive -or $AimedStone -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial){
            throw 'Scripted physical controller fixture requires its separate standalone ground/view profile without live input or composition.'
        }
    }elseif($PhysicalMovement){
        if(-not $InputMode -or -not $LiveMouse -or -not $OffscreenPresentation -or -not $GroundPatchFile -or -not $MovementTraceFile -or -not $HostViewFile -or
            $Standalone -or $GroundMovementFixture -or $GroundMovementCoupled -or $InputFixture -or $InputPointerFixture -or $StoneFixture -or $StoneLive -or $AimedStone -or $InputDelayFixture -or $InputBackgroundTrial -or $InputOffscreenTrial){
            throw 'Physical movement requires its separate live HUD input/ground/view profile.'
        }
    }elseif(-not $WalkingAimed){
        if($HostViewFile){throw 'HostViewFile requires explicit physical movement.'}
        Assert-HudGroundChildMode ([bool]$GroundMovementFixture) ([bool]$Standalone) $GroundPatchFile ([bool]($InputMode -or $LiveMouse -or $InputFixture -or $InputPointerFixture -or $StoneFixture -or $StoneLive -or $AimedStone -or $InputDelayFixture -or $InputBackgroundTrial -or $OffscreenPresentation -or $InputOffscreenTrial)) ([bool]$GroundMovementCoupled) $MovementTraceFile
    }
    $arguments=@('-p',$minecraft,'--no-daemon','runClient','-PminecomeHudStreamLab',"-PminecomeHudStreamRun=$Run","-PminecomeHudStreamTargetPid=$TargetPid","-PminecomeHudStreamTargetStart=$TargetStart","-PminecomeHudStreamExpiresUtcMs=$ExpiresUtcMs","-PminecomeHudStreamDirectory=$producerDirectory","-PminecomeHudStreamWidth=$Width","-PminecomeHudStreamHeight=$Height","-PminecomeHudStreamGuiScale=$GuiScale")
    if($Standalone){$arguments+='-PminecomeHudStreamStandalone'}
    if($GroundMovementFixture){$arguments+=@('-PminecomeHudGroundMovementFixture',"-PminecomeGroundPatchFile=$GroundPatchFile")}
    if($GroundMovementCoupled){$arguments+=@('-PminecomeHudGroundMovementCoupled',"-PminecomeGroundPatchFile=$GroundPatchFile","-PminecomeMovementTraceFile=$MovementTraceFile")}
    if($PhysicalMovement){$arguments+=@('-PminecomeHudPhysicalMovement',"-PminecomeGroundPatchFile=$GroundPatchFile","-PminecomeMovementTraceFile=$MovementTraceFile","-PminecomeHudHostViewFile=$HostViewFile")}
    if($WalkingAimed){$arguments+=@('-PminecomeHudWalkingAimed','-PminecomeHudPhysicalMovement','-PminecomeHudStoneBridge','-PminecomeHudStoneLive','-PminecomeHudAimedStoneBridge',"-PminecomeGroundPatchFile=$GroundPatchFile","-PminecomeMovementTraceFile=$MovementTraceFile","-PminecomeHudHostViewFile=$HostViewFile","-PminecomeTokenFile=$StoneTokenFile","-PminecomePort=$StonePort")}
    if($ExtendedWalking){$arguments+='-PminecomeHudPhysicalMovementExtended'}
    if($WideWalking){$arguments+='-PminecomeHudWideWalking'}
    if($AimedBlocks){$arguments+='-PminecomeHudWalkingAimedFixture'}
    if($PhysicalMovementFixture){$arguments+=@('-PminecomeHudPhysicalMovementFixture',"-PminecomeGroundPatchFile=$GroundPatchFile","-PminecomeMovementTraceFile=$MovementTraceFile","-PminecomeHudHostViewFile=$HostViewFile",('-PminecomeHudPhysicalFixtureYaw='+$PhysicalFixtureYaw.ToString([Globalization.CultureInfo]::InvariantCulture)))}
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
