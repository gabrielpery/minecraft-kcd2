# Resume checkpoint — 5 November 2026

## User direction

Deliver the full scope in [PRODUCT.md](PRODUCT.md): Steve/hands/equipment,
Minecraft survival/combat and general blocks, commands, Creative flight and Elytra.
Prefer integrated implementation and automatic tests. Manual acceptance is deferred
to a larger milestone; do not resume repeated F8 countdowns.

## New persistent session foundation

`GameplayWorld` owns `MineCome-Gameplay` with stable world identity and ordinary
vanilla save/reopen. `GameplaySession` is separate from diagnostic labs, retains
inventory/mode/player state, emits schema3 HUD and accepts schema3 UI input.
Regular lifetime is stop/peer closure with a finite24h identity; it has no30s demo
cutoff. Hidden-window rendering/cleanup reuses the existing proven path.

Actual two-launch persistence PASS:
`runtime/evidence/gameplay-persistence-20261105-170217-435f802075d347c982b362d2e32c75d9/verification.json`.
35.2s first session; same world/player reopened with17 apples, iron pickaxe,
Survival, health16, food11 and saved regeneration rule. Vanilla command packets
switch Creative/Survival abilities. Both clients save/exit normally.
Standalone bootstrap is vanilla superflat, not imported KCD collision.

New native gameplay addon + selective-keyboard v5 proxy compile. Automatic neutral
activation, F8 stop, short frame/input/keyboard leases. UI keys/inventory only;
KCD retains native world walking/camera outside inventory. **Minecraft movement,
terrain, block mirroring and command typing are NOT connected in this new path.**
Do not describe this as sustained Minecraft-authoritative gameplay yet.

Native composition/lifecycle PASS (host60FPS):
`runtime/evidence/gameplay-kcd-20261105-171621-b063422fa5d64d6fa67539bff318d787/verification.json`.
40.546s, automatic input arming,733 uploads/zero drops/2498 submissions; actual
CUA frame showed Minecraft hotbar over KCD. Stop/save, input cleanup and hidden
guest exit passed. No events recorded, so new inventory controls remain unverified.

Entry points: `Start-GameplayGuest.ps1`, `Start-GameplaySession.ps1`,
`Test-GameplayPersistence.ps1`; see [GAMEPLAY_SESSION.md](GAMEPLAY_SESSION.md).
The new bundle is staged at `runtime/hud-compositor-gameplay`. Exact pinned
v5 staging/install/restore scripts preserve the old six-file installation.
After restoring a bundle, restaging/reinstall uses a fresh `-BundleDirectory`.
Native v5 currently accepts one session per KCD process; same-process rearm is
not implemented for gameplay. Do not confuse it with the old two-session lab.

## Next implementation

Connect the verified walking/terrain/controller and owned block ledger to
GameplaySession, replacing lab-only time/arena limits while retaining freshness,
server authority and orderly native control return. Then general visuals/blocks,
chat commands and Creative flight; follow Survival/NPC combat and Elytra.
The retail loader/access route remains unverified; current integration uses the
exact official Steam tools2429020/display1.5.5 executable and console/log interface.

## Preserve existing working behavior

Bounded physical corridor HUD/walking/inventory/aimed stone remains user-verified.
Latest acceptance: cutoff cleanup “worked fine”. New physical controller admission
passes actual Minecraft on captured KCD terrain:
`runtime/evidence/hud-physical-fixture-20261105-161657-96911b0ddfd345fabdbc5851d073af57/verification.json`.
Both threads reach X8.836764818; return error0.029064m; seed survives admission;
six block actions, inventory/resumed walking pass; all190 imported cells remain air.
This is scripted Minecraft + standalone HUD, not a new native physical-input pass.
The old October30 failure was a validator bug (valid held-key release/reapply on
admission), already fixed. Do not repeat it.

`Test-CoupledPhysicalExtension.ps1` is implemented, not yet run end-to-end; use only
if needed for next integration. Existing15s input+1s settle,18s native lifetime,
400ms lease,200ms playback, three pre-captured tiles remain diagnostic limits.

## Environment

JDK C:/Program Files/Java/jdk-24; Gradle cache minecraft/.gradle-user-home.
Public remote gabrielpery/minecraft-kcd2, branch codex/initial-import.
No retail saves. Routine edits/tests/launches/pushes authorized.
Old verified bundle: runtime/hud-compositor-walking-corridor-aimed-20261029.
Check the latest PROGRESS.md section and process/install receipts before native work.

End state: both test games closed normally. All six original renderer files were
restored and hash-verified; v5 is not currently installed. Restore receipt:
`runtime/evidence/gameplay-hud-restore-20261105-171912-4d3a36f146104ac39d8e9572351fbc04`.
Gameplay native smoke used +sys_MaxFPS60 only for that process. Investigate an
ongoing GPU budget before promising long unrestricted sessions. No manual input
was requested. Default persistent Minecraft world now exists under runtime/gameplay.
