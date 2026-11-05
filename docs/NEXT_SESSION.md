# Resume checkpoint — 5 November 2026

## Direction

Deliver [PRODUCT.md](PRODUCT.md): Steve/hands/equipment, Minecraft Survival/combat,
general blocks, commands, Creative flight and Elytra. Prefer integrated progress
and automatic checks. Defer manual acceptance to a larger milestone; do not return
to repeated F8 countdowns. Preserve existing bounded walking/block labs.

## Current implementation

`GameplaySession` reuses `MineCome-Gameplay`, preserving vanilla world/player state.
The new `-Movement` path adds `GameplayMovement`, persistent `minecome-terrain`
binding, temporary client/server collision and ongoing host pose/view exchange.
Movement input is protocol 4 (`MCHUDI04`), HUD remains schema 3. Existing UI-only
protocol 3 is separate. Automatic neutral activation; F8 stops/saves, not starts.
No 15-second movement cutoff or timed return to origin. Finite 24h identity and
short input/view/pose leases remain. Inventory suppresses walking.

New native module `kcd2/gameplay/movement_session.lua` follows absolute server
positions with 100ms interpolation and 400ms lease, stopping at the last position.
`GameplayMovementHost.ps1` owns console/log worker, current pose and live camera.
Launcher uses an early atomic `gameplay-stopping.json` notice to cancel the host
before final guest cleanup exceeds its pose lease. Do not wait for final report.

First launch automatically captures one 8×8m heightfield; its exact origin/bytes and
last clean grounded checkpoint are saved. Reopen installs collision then restores
the checkpoint, preserving mode/abilities. Failed sessions retain the last good
checkpoint. Frontier braking pauses before leaving captured coverage. This is
not rolling terrain, complete geometry or unrestricted roaming. Active Creative/
Elytra flight is paused; blocks, commands, combat and Steve are not connected here.

## Verified this iteration

Actual Minecraft 35.038s walking + inventory + post 21-second step PASS; 636 HUD
frames, both collision threads, no terrain BlockState writes, normal save/exit.
Reopen restored X1.291498509/Y64/Z0 exactly and walked another 1.2915m; 130 HUD frames.
Combined proof:
`runtime/evidence/gameplay-20261105-175426-6f1e55fbef314baabc1bb94deeec5011/walking-resume-verification.json`.
The first paired run's resume validator had a Gson float/decimal equality bug.
Fixed typed comparisons and repeated only resume. Preserve the earlier first-pass
evidence; do not rerun it merely to erase the failed validation record.

Actual KCD2 sustained attachment/HUD PASS (60FPS process-only cap):
`runtime/evidence/gameplay-kcd-20261105-175248-793be9188b3642d9b4b8f793e4221e6e/verification.json`.
41.717s guest, 601 poses, 401 live camera samples, 734 uploads/zero drops/2487 submits.
CUA showed hotbar/crosshair; explicit stop, timer cleanup, checkpoint and exit pass.
**Zero native input events: no new physical walking claim.** Late CUA W tap landed
after automatic stop. Earlier bounded physical walking/block acceptance stands.

Focused Java/native/Lua/PowerShell checks pass; see latest PROGRESS.md. Runtime
fixes: bounded Windows atomic-sharing retries preserve original timestamps; the
ground capture reuses exact-process listener-table ownership instead of CIM's
unreliable listener-state filter on this machine.

## Next work

Bring the verified owned block ledger/aim control into sustained GameplaySession,
then add rolling terrain admission using the stable saved origin. Preserve HUD,
inventory and save behavior. Build one combined automatic fixture first; defer
manual testing. Then connect host chat/commands and Creative flight, followed by
the remaining required rendering/Survival/NPC/Elytra scope. One native gameplay
session per KCD process remains a limitation; old repeat-session lab is separate.

## Environment and end state

Both games closed normally. All six prior renderer files restored/hash-verified:
`runtime/evidence/gameplay-hud-restore-20261105-175526-28eada4f3a554adabf82d57466a0edea`.
Movement v5 bundle remains staged at `runtime/hud-compositor-gameplay-movement`,
but its installed/restored receipts make it immutable. Use a fresh
`-BundleDirectory` with Prepare/Install/Start-GameplaySession all using `-Movement`.
Exact commands: [GAMEPLAY_SESSION.md](GAMEPLAY_SESSION.md). Native movement world:
`runtime/gameplay/walking-instance`; default UI world is `runtime/gameplay/instance`.

JDK `C:/Program Files/Java/jdk-24`, Gradle cache `minecraft/.gradle-user-home`.
Public remote `gabrielpery/minecraft-kcd2`, branch `codex/initial-import`.
Exact official Steam tools2429020/display1.5.5 exe only; retail route unverified.
No retail saves. Routine edits, tests, launches and pushes are authorized.
