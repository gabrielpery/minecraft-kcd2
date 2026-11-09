#Requires -Version 7.3
# Internal child: persistent guest process, separate from every diagnostic save.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$EvidenceDirectory,[Parameter(Mandatory)][string]$InstanceDirectory,
 [Parameter(Mandatory)][string]$Run,[Parameter(Mandatory)][int]$TargetPid,
 [Parameter(Mandatory)][string]$TargetStart,[Parameter(Mandatory)][long]$Expires,
 [Parameter(Mandatory)][string]$JavaHome,[ValidateSet('','create','resume','walking','walking-resume','blocks','blocks-resume','blocks-survival','food','food-resume','drops','drops-resume','crafting','crafting-resume','tnt','tnt-resume','furnace','furnace-resume','respawn','respawn-resume','combat','terrain','terrain-resume','chat','chat-resume','flight','flight-resume','flight-fall','flight-fall-resume','hands','world-blocks','world-blocks-resume','shapes','shapes-resume','depth','connected','connected-resume','shape-walking','player')][string]$FixturePhase='',
 [switch]$Connected,[switch]$Movement,[switch]$Blocks,[switch]$Explore,[switch]$Chat,[switch]$Flight,[switch]$Hands,[switch]$WorldBlocks,[switch]$Combat,[switch]$BowCheck,[switch]$ProjectileCheck,[switch]$CombatCheck,[string]$GroundPatchFile,[switch]$ThirdPersonWalkingCheck,[switch]$DropsCheck,[switch]$CraftingCheck,[switch]$FurnaceCheck,[switch]$TntCheck,[switch]$TntCombatCheck,[switch]$RespawnCheck)
$ErrorActionPreference='Stop'
if($TntCombatCheck){$Combat=$true;$TntCheck=$true}
if($Combat -or $FixturePhase -eq 'combat'){$Combat=$true;$WorldBlocks=$true};if($WorldBlocks){$Hands=$true};if($Hands){$Flight=$true};if($Flight){$Chat=$true}
if($Explore -or $Chat){$Blocks=$true};if($Blocks){$Movement=$true}
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
if($BowCheck){if($Connected -or -not $Combat -or $FixturePhase -cne 'combat'){throw 'BowCheck requires isolated standalone combat.'};$arguments+='-PminecomeGameplayBowFixture'}
if($ProjectileCheck){if($Connected){if(-not $CombatCheck){throw 'Connected ProjectileCheck requires CombatCheck.'};$arguments+='-PminecomeGameplayProjectileCheck'}else{if(-not $BowCheck){throw 'Standalone ProjectileCheck requires BowCheck.'};$arguments+='-PminecomeGameplayProjectileFixture'}}
if($CombatCheck){if(-not $Connected -or -not $Combat -or $FixturePhase -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck -or $RespawnCheck){throw 'Native combat check requires connected Combat without another fixture.'};$arguments+='-PminecomeGameplayCombatCheck'}
if($RespawnCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck){throw "Native respawn check requires connected WorldBlocks without another fixture."};$arguments+="-PminecomeGameplayRespawnCheck"}
if($TntCombatCheck){$arguments+='-PminecomeGameplayTntCombatCheck'}
if($TntCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck -or $FurnaceCheck -or $RespawnCheck -or $CombatCheck){throw 'Native TNT check requires connected WorldBlocks without another fixture.'};$arguments+='-PminecomeGameplayTntCheck'}
if($FurnaceCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase -or $ThirdPersonWalkingCheck -or $DropsCheck -or $CraftingCheck){throw "Native furnace check requires connected WorldBlocks without another fixture."};$arguments+="-PminecomeGameplayFurnaceCheck"}
if($CraftingCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase -or $ThirdPersonWalkingCheck -or $DropsCheck){throw "Native crafting check requires connected WorldBlocks without another fixture."};$arguments+="-PminecomeGameplayCraftingCheck"}
if($DropsCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase -or $ThirdPersonWalkingCheck){throw "Native drops check requires connected WorldBlocks without another fixture."};$arguments+="-PminecomeGameplayDropsCheck"}
if($ThirdPersonWalkingCheck){if(-not $Connected -or -not $WorldBlocks -or $FixturePhase){throw 'Native walking check requires connected WorldBlocks without another fixture.'};$arguments+='-PminecomeGameplayThirdPersonWalkingCheck'}
if($Combat){$arguments+='-PminecomeGameplayCombat'}
if($Blocks){$arguments+='-PminecomeGameplayBlocks'}
if($Explore){$arguments+='-PminecomeGameplayExplore'}
if($Chat){$arguments+='-PminecomeGameplayChat'}
if($Flight){$arguments+='-PminecomeGameplayFlight'}
if($Hands){$arguments+='-PminecomeGameplayHands'};if($WorldBlocks){$arguments+='-PminecomeGameplayWorldBlocks'}
if($Movement){if(-not $GroundPatchFile){throw 'Movement requires its persistent captured terrain file.'};$arguments+=@('-PminecomeGameplayMovement',"-PminecomeGameplayGroundFile=$GroundPatchFile")}
$code=1
try{& (Join-Path $root 'minecraft/gradlew.bat') @arguments; $code=$LASTEXITCODE}
finally{[ordered]@{run=$Run;exit_code=$code;ended_utc=[DateTime]::UtcNow.ToString('o')}|
 ConvertTo-Json|Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-exit.json') -Encoding utf8NoBOM}
exit $code
