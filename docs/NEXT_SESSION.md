# Resume checkpoint — 5 November 2026

## Direction

Deliver [PRODUCT.md](PRODUCT.md): Steve/hands/equipment, Minecraft Survival/combat,
general blocks, commands, Creative flight and Elytra. Prefer integrated progress
and automatic checks; defer manual acceptance to a larger milestone. Preserve
the old verified bounded labs. No manual countdowns were needed this turn.

## Current implementation

`GameplaySession` reuses `MineCome-Gameplay` with stable world UUID and vanilla
player/inventory/mode persistence. `-Movement` uses a saved captured 8×8m patch,
temporary collision on both Minecraft threads and last clean grounded checkpoint.
No 15-second walking cutoff or return to origin; native interpolation is 100ms,
short input/view/pose leases remain, outer identity is 24h. Inventory stops movement.

New `-Blocks` implies movement and selects input protocol 5 (`MCHUDI05`); HUD
schema remains 3. UI-only input3 and movement-only input4 binaries are unchanged.
World mouse kinds7/8 are separate from inventory kinds4/5. Native buttons-only
capture preserves camera look. `GameplayBlocks` uses real vanilla placement/mining,
server admission/confirmation, and persistent ownership `minecome-blocks.json`
in the owned save. First placement targets sampled native ground; no seeded
cube or inventory reset. Capacity64 stones, mapped X/Z[-4,3], Y[56,80]. Survival
placement consumes items; held vanilla mining and early-release cancellation
work. Scoped `handleBlockBreaking` mixin prevents vanilla cancelling an admitted
Survival hold each tick. Server tick observation continues through shutdown drain.

`GameplayMovementHost.ps1` owns the one console/log worker. It publishes exact
camera/rays (`gameplay-aim.json`) and reconciles server snapshots
(`gameplay-blocks.json`) through `GameplayBlocksHost.ps1` and
`kcd2/gameplay/blocks_session.lua`. Dual native rays distinguish terrain from
obstructions; unknown/stale rays refuse actions. Native stones use verified
corner pivot (0,-1,0)..(1,0,1), zero angles. Stop saves MC construction and removes
only owned native display entities; a 2s lease also cleans those up. Early atomic
`gameplay-stopping.json` stops the host before final guest cleanup.

## Verified this iteration

Actual Minecraft paired Creative check PASS first attempt:
`runtime/evidence/gameplay-blocks-20261105-182327-bc99a613c7d245f0849181bd7549a97c/verification.json`.
Ground/top/side placement3, breaks2, zero rejections, early/later walking,
22 inventory suppression ticks, saved1 stone. Reopen preserved block, world/player
identity, inventory and location, then broke the retained stone. Normal saves
and collision/ledger cleanup passed. Scripted controls, not physical KCD input.

Actual Survival check PASS first attempt:
`runtime/evidence/gameplay-blocks-survival-20261105-183226-f248758e20ea483394859d689b53ada4/verification.json`.
Placement consumed64→63 stones, early attack release retained block, next held
iron-pickaxe attack broke it;10 preserved vanilla ticks. Clean save/exit.

Native HUD/camera ran92.242s:1,650 uploads, zero drops,1,045 poses,826 aim samples.
CUA saw HUD and moved native camera down; terrain ray classified true at1.79m.
Two mouse edges acknowledged; empty-world attack rejected. E tap not recorded:
no keyboard/inventory or coupled placement claim.
`runtime/evidence/gameplay-kcd-20261105-182859-d32d4ea23f7d42b7874b830b3a280ecc`.
**Overall native receipt FAILED cleanup readback**, despite actual KCD terminal
count0/timers cancelled. Timer-produced last log line lacked LF until another
message. Worker now emits read-only100ms cleanup flush; regression passes.
Keep original failed receipt. Do not rerun90s merely to erase it.

Native mirror follow-up PASS1.004s:
`runtime/evidence/gameplay-block-mirror-20261105-183456-8ca9a1db2e6a49be986c9b889a85bf76/verification.json`.
2 synthetic cells, actual local/world bounds and angles correct; remove1 then
explicit stop removed2 total, count0, timers cancelled. Native component proof,
not actual MC placement. `Test-GameplayBlocksMirror.ps1` takes a live patch file;
do not overlap its console work with the sustained host worker.

Build/assemble passes. Java blocks/aim61, wire56, movement14, world21; native
gameplay328/input397; Lua movement11/blocks7; PS host9/blocks9/combined worker2.
Do not repeat prior35-second walking/resume check, already passed in
`runtime/evidence/gameplay-20261105-175426-6f1e55fbef314baabc1bb94deeec5011`.

## Next work

Expand sustained terrain using existing corridor/extension admission and stable
saved origin. Expand block bounds/ledger/mirror contracts together: all currently
bound one patch. Then integrate chat/vanilla commands and Creative flight,
followed by general rendering/Steve/Survival/NPC/Elytra scope. Avoid another timed
demo. Use one larger automatic feature check before combined manual acceptance.
New profile still accepts one session per KCD process; old repeat labs remain
separate. Active flight pauses walking; no continuous free roaming yet.

## Environment and end state

Both games closed normally. Six prior renderer files restored/hash-verified:
`runtime/evidence/gameplay-hud-restore-20261105-183621-994152be36fc4bbe891dc2ef1a9d0a4f`.
`runtime/hud-compositor-gameplay-blocks` is staged but installed/restored receipts
make it immutable. Use a fresh BundleDirectory and `-Blocks` consistently for
Prepare/Install/Start/Restore. Commands: [GAMEPLAY_SESSION.md](GAMEPLAY_SESSION.md).
Native save: `runtime/gameplay/blocks-instance` (empty construction, Creative,
bound to real capture). Existing walking-instance/default UI instance preserved.

JDK `C:/Program Files/Java/jdk-24`; Gradle cache `minecraft/.gradle-user-home`.
Public remote `gabrielpery/minecraft-kcd2`, branch `codex/initial-import`.
Exact official Steam tools2429020/display1.5.5 exe only; retail route unverified.
No retail saves. Routine edits, tests, launches and pushes are authorized.
