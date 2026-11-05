# Resume checkpoint — 5 November 2026

## User direction

Prioritize a finished playable product and less time/usage. Read [PRODUCT.md](PRODUCT.md):
Steve/hands/equipment, Minecraft survival/combat, general blocks, commands (including
`/gamemode survival`), Creative flight and Elytra/rockets are required. These are
product goals, not implemented claims. Manual testing stays deferred to a larger
milestone. Do not resume repeated F8 countdowns or small already-proven checks.

## Working checkpoint

Existing bounded native corridor walking/HUD/inventory/stone controls remain
verified. Latest user acceptance was cutoff cleanup: “worked fine”. See PROGRESS.md.

New controller integration passes actual Minecraft on previously captured KCD terrain:
`runtime/evidence/hud-physical-fixture-20261105-161657-96911b0ddfd345fabdbc5851d073af57/verification.json`.
Both sides reach X=8.836764818m, return within 0.029064m, preserve the seed through
admission, complete six block actions and inventory/resumed walking. All 190
imported cells remain air; source hashes/trace and cleanup pass. Scripted input and
standalone HUD receiver only; new native physical acceptance is not claimed.

The October30 failure was a validator bug: a held key releases/reapplies during
admission, incorrectly rejected as multiple bindings. Fixed and covered; November5
fresh run passes. Do not redo that investigation. Existing failed receipt untouched.

## Next implementation: sustained gameplay

Stop adding separate short profiles. Reuse the controller/input/HUD in a persistent
world/session with owned blocks and ongoing terrain acquisition. Separate gameplay
lifetime from diagnostic duration: ordinary play must not expire after 15 seconds
or teleport back to its initial position. Retain freshness/ownership and clean host
control handover on disconnect. Keep bounded labs for regression.

Resolve the supported KCD2 release/access path early. Current actual access is the
official development game's console/log interface; the retail KCSE route remains
unverified. Avoid building the product around an unproven retail loader.

Then general Minecraft visuals/blocks, commands/mode changes and Creative flight;
follow with Survival/NPC combat and Elytra. Concrete gaps: renderHand is cancelled,
world rendering suppressed, BlockModelExport/stone_mirror accept only stone,
AimedStoneArena requires Creative, HudStreamLab creates disposable Creative/Peaceful
saves, and the protocol has no NPC/damage exchange. These are required product work.

## Pending automatic native verification

`Test-CoupledPhysicalExtension.ps1` is implemented but not run end to end. It captures
three tiles, runs the combined Minecraft fixture and replays its server trace in
KCD2, restoring FPS and position. Lua/PS checks pass. Use only if needed for the
next gameplay integration; it needs an already-open exact tools world, no F8.
Sequential replay does not establish simultaneous native HUD/physical input.

Physical extension retains 15s input+1s settle, 18s native lifetime, 400ms lease,
200ms playback, X[-3.5,11.5], Z[-3.5,3.5]. Legacy corridor stays X[-3.5,7.5].
Three tiles are pre-captured; one admission is not rolling terrain streaming.

## State

The November5 fixture closed normally; no game/helper remains from it. No installed
native DLL changed. Existing bundle:
`runtime/hud-compositor-walking-corridor-aimed-20261029/installed.json`, addon SHA256
`c5353e4bc21fd512838160cd3196f23f17b0fd6d0dc412178037dd56426c0196`.
Inspect processes/arms before native work. Official Steam tools2429020/display1.5.5
only; never load retail1.5.6 saves. JDK: C:/Program Files/Java/jdk-24.
Gradle cache: minecraft/.gradle-user-home. Public repo: gabrielpery/minecraft-kcd2,
branch codex/initial-import. Routine edits/tests/launches/pushes remain authorized.
