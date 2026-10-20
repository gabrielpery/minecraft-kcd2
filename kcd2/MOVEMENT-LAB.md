# Sampled-ground movement lab

This opt-in prototype tests **real Minecraft walking, jumping and landing against
an approximate patch of sampled KCD2 ground**. The basic lab observes Minecraft;
the separate coupled test below also moves KCD2's player and verifies camera
following and restoration. Minecraft uses a new isolated Adventure save; no vanilla floor is
placed in it. The normal vanilla movement tick uses the imported collision slabs
on both the client and integrated server.

## Live test

Run these commands from the MineCome project folder in PowerShell7:

```powershell
.\scripts\Start-Kcd2ToolsTest.ps1
```

Let the fresh official development world finish loading. Stand still on a gentle
piece of ordinary ground, then run:

```powershell
.\scripts\Start-GroundMovementLab.ps1
```

The helper verifies the pinned development executable and its localhost endpoint,
captures25 ground samples around the current player, and starts a fresh Minecraft
lab. The lab applies a short forward input, releases it, then performs a vertical
jump and waits for landing. It closes normally after its bounded test duration.
Both client and server observations must pass; an HTTP response or initial
teleport does not count as a movement pass. The console prints the evidence folder.

An incomplete patch, steep ground, changed player identity, open menu, expired
input lease, missing server observation or server correction fails the probe.
Check that run's logs before repeating. The helper never launches, teleports or
stops KCD2.

The tools build is1.5.5; continue using its fresh test world, keeping existing
retail1.5.6 saves separate as in the earlier stone tests.

## Coupled player and camera test

With the fresh official development world already loaded, stand still on ordinary
gentle ground and run from MineCome in PowerShell7:

```powershell
.\scripts\Test-CoupledMovement.ps1
```

The helper captures a new terrain patch and starts its own isolated Minecraft lab.
Minecraft performs vanilla walking, jumping and landing; only fresh integrated-server
poses drive the bounded KCD follower. KCD2's existing camera follows the player.
The follower returns the player to the captured starting position, verifies that
readback on a later game frame, and cancels its timers. Minecraft saves its new
world and closes normally. The helper neither launches nor stops KCD2.

Success prints `COUPLED_MOVEMENT_PASS` with separate server-frame, delayed KCD
receipt and restoration evidence. A game-owned400ms input lease and fixed8s
deadline bound the follower independently of the helper. An unexpected actor,
state change or player movement ends the probe; restoration applies only while
the follower can prove it still owns the position. Inspect any failure receipts
before repeating. `-PreflightOnly` performs compatibility checks without game writes.

The2026-10-12 live run passed22 forwarded server frames,21 delayed KCD readbacks,
camera following and restoration. This test supplies scripted Minecraft input.
It does not yet make KCD2 keyboard/mouse actions control Minecraft, align view
rotation, disable native KCD physics, or provide full-world collision streaming.

## Coupled movement from the HUD world

The new opt-in wrapper reuses that follower with the same fresh Creative
Minecraft save that captures the HUD. It captures and authenticates a new
25-point KCD ground patch, checks actual client/server walking and jumping,
then forwards fresh server poses to KCD. The follower keeps its eight-second
hard deadline and 400 ms pose lease, verifies return to the starting position,
and ends before Minecraft's later 20-second inventory sequence.

Complete the [HUD receiver prerequisites](../minecraft/README.md#standalone-hud-ground-movement-lab)
first; the dated receiver binary is a local build artifact. Close any existing
MineCome Minecraft client. With the fresh supported KCD tools world loaded,
menus closed and the player stationary on gentle ground, run from the project root:

```powershell
& .\scripts\Start-HudCoupledMovementLab.ps1 -PreflightOnly
& .\scripts\Start-HudCoupledMovementLab.ps1
```

Windows PowerShell 5.1 automatically hands off to an installed PowerShell 7.
Preflight checks the running tools process without game writes. The test
supplies scripted Minecraft input: no F8 or human key sequence is needed.
Leave controls alone because KCD's normal input and physics remain active;
the helper does not claim exclusive movement authority or suppress those systems.

The helper temporarily caps KCD at 60 FPS, with an engine-owned 120-second
deadline, and verifies restoration of the previous cap. HUD frames are checked
by the standalone native receiver, **not composited inside KCD in this mode**.
Minecraft closes normally after its checks; KCD stays open. Follower, terrain,
HUD, process-exit and restoration evidence is retained together beneath
`runtime/evidence/coupled-movement-*/`. Live run
`391e9d463edc4789b6bb425eec84a183` passes 21 forwarded samples and 21 delayed
KCD readbacks, player/camera restoration, 435 accepted HUD frames, the four-state
inventory sequence and frame-cap restoration. The earlier coupled test and
standalone synthetic HUD fixture remain separate entry points.

## What this can establish

The sampler uses25 downward terrain-only rays in a5×5 grid with1m spacing. Each
quad becomes a flat slab at its four corners' average height. This4×4m patch is a
deliberate approximation: walls, buildings, bridges, ceilings, tunnels, vegetation
and general collision meshes are outside its scope. All underlying Minecraft
block cells remain air. Server flight validation is allowed only in the new lab
because that check reads literal block air; the Adventure player's flying ability
remains disabled and movement/gravity/jumping remain vanilla.

The collision hook is scoped to the exact owned client/server worlds. It does not
change the existing stone lab or ordinary Minecraft worlds. Terrain is a static
snapshot with a recorded source hash, not a streaming collision service.

To verify the Minecraft hook without KCD2, developers may explicitly run:

```powershell
.\scripts\Start-GroundMovementLab.ps1 -Fixture
```

That uses labelled synthetic slopes and proves only the real Minecraft collision
and movement path. It is not live KCD2 terrain evidence. A captured patch can be
reused with `-PatchFile <capture-folder>\ground-patch.json`; its adjacent capture
receipts, source snapshot and hashes must still match.

Research and remaining authority/input requirements are in
[MOVEMENT.md](../docs/research/MOVEMENT.md),
[KCD-MOVEMENT.md](../docs/research/KCD-MOVEMENT.md) and
[KCD-INPUT.md](../docs/research/KCD-INPUT.md).

## External-input Minecraft lab

`scripts/Start-ExternalInputLab.ps1 -Fixture` now verifies the next consumer stage:
fresh external records drive actual vanilla keys and view changes on the Minecraft
client thread. Client and server walking, jump/landing, yaw/pitch and terminal key
release passed in a new world, using labelled synthetic input and flat terrain.
This lab has no KCD follower. Physical KCD-focused W/Space/mouse input passed on
2026-10-12: both Minecraft sides walked, jumped, landed and changed yaw/pitch in
the fresh sampled world. Delayed samples were discarded and controls released at
the end. Procedure and limits are in
[setup](../docs/SETUP.md#external-input-applied-to-minecraft) and
[Windows input](../docs/research/WINDOWS-INPUT.md).

The input lab now seeds its initial orientation from a fresh, session-bound camera
snapshot and accepts `-Bindings` for explicit keys. Both Minecraft sides verify the
initial angles before input begins. The live physical run also verified the KCD
view seed; alternative remapped physical keys have only standalone validation.
This does not change the coupled follower's scope.

The lab now exports `minecraft-pose.ndjson` with both client/server movement and
view, projected server coordinates and forward vector, plus the initial Minecraft
baseline. The mapping is explicitly patch space: `KCD=(centerX+MCx, centerY-MCz,
centerZ+MCy-64)`. Its starting0.5/0.5 offset is recorded, not treated as the KCD
player's original position. The record's input dispatch watermark does not prove
server acknowledgement of that input. Every record is audit-only and ineligible
for the KCD follower. The controller verifies the completed stream after normal
Minecraft exit; output is bounded to512records/1MiB and written off the game thread.

The read-only `scripts/Test-KcdControlCapabilities.ps1` checks actual control API
availability in the already-running official tools world. It does not disable
input/physics, move the player, or start a timed physical-input test. Its live
findings and remaining ownership requirements are in
[KCD input research](../docs/research/KCD-INPUT.md#live-control-capability-inspection--2026-10-12).
