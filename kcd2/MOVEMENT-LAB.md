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
This lab has no KCD follower. The physical KCD capture mode is implemented but its
combined physical delivery remains unverified. Procedure and limits are in
[setup](../docs/SETUP.md#external-input-applied-to-minecraft) and
[Windows input](../docs/research/WINDOWS-INPUT.md).

The input lab now seeds its initial orientation from a fresh, session-bound camera
snapshot and accepts `-Bindings` for explicit keys. Both Minecraft sides verify the
initial angles before input begins. The new capture/consumer contract has standalone
checks and a real-Minecraft synthetic-view run; its new KCD view capture and physical
remapped keys remain unverified. This does not change the coupled follower's scope.
