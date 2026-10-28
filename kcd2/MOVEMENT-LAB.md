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

## Physical walking with the HUD in KCD

`Start-HudWalkingLab.ps1` is a separate opt-in lab that sends physical WASD/Space
to the actual Minecraft world supplying KCD's HUD. It uses a fresh 25-point KCD
terrain capture, ordinary Minecraft movement/gravity/jumping on client and server,
and fresh KCD camera direction for walking orientation. Only fresh server poses
drive the KCD follower. Source compilation and automated contract/lifecycle checks
pass. Camera delivery now uses a separate bounded worker and retained log handle.
The latest optional extended run passes all 156 source transfers,
delayed native readbacks, normal `explicit_end` restoration and cleanup. The user
reports "worked. still delay, but worked." The actor returns to its exact starting
position, timers cancel, FPS restores and Minecraft exits normally. All 611
camera publications stay fresh. Parser warmup, native finish and fixed sampling
are now exercised together in this live pass; repeating that comparison is not
the next milestone. Integration with aimed blocks is next; remaining latency is deferred.
This remains a bounded development test with an intentional 200 ms playback
buffer. See [the current evidence](../docs/PROGRESS.md) for practical limits.

This requires the separately prepared and installed `hud-compositor-walking`
bundle. The normal revision4 aimed-stone add-on cannot accept walking input.
The walking profile reuses that frozen renderer but has its own add-on, protocol2
key channel and `MineComeHudMovement.ini`. Preparing/installing a bundle is
separate from starting the lab; a source clone does not contain these artifacts.
The deployment helpers use explicit `-PhysicalMovement` mode. See the
[HUD guide](../docs/research/HUD-COMPOSITOR.md) for the renderer prerequisites.

With the matching add-on loaded in a fresh supported KCD tools world, menus closed,
the player stationary on gentle ground and any older MineCome client closed, run
from the repository root:

```powershell
& .\scripts\Start-HudWalkingLab.ps1 -PreflightOnly
& .\scripts\Start-HudWalkingLab.ps1
```

The wrapper finds an installed PowerShell 7 when invoked from Windows PowerShell
5.1; no administrator mode is required. Wait for `HUD_WALKING_READY` before using
F8. Keep KCD focused, release all controls and press F8 once. Briefly press and
release W to walk; WASD and Space are the supported movement keys. Keep movements
small: the collision patch covers only 4×4 metres. The lab checks braking
clearance across its sampled slabs and pauses input before its footprint, descent
or displacement limits. Release the held controls before pressing again in an
allowed direction. A boundary pause does not restart the five-second input
window, and repeating a press into the same boundary cannot make it pass.
Completion requires
walking on both Minecraft sides followed by 500 ms of grounded stability. Optional
jumping has separate observations and is not a completed live milestone.

Default movement accepts new held input for at most five seconds from the first
accepted edge; `-ExtendedWalking` selects fifteen seconds. Both allow at most one
additional second for neutral settling. The HUD can
continue for up to 30 seconds after F8. E opens inventory and Escape closes it;
inventory transitions release movement, and a held key cannot silently resume
when inventory closes. Native camera look remains available outside inventory.
This profile does not publish block placement/breaking clicks.

The physical follower permits vertical offsets of -1.5 m to +1.5 m within a
2 m sphere around the start. Minecraft's predictive gate uses a 1.75 m radius
and -1.45 m to +1.45 m vertical clearance, with a 1.8 m hard radius and sampled
ground coverage. This physical-only descent change does not alter the legacy
scripted follower's -0.2 m to +1.5 m range.

Physical source publication now uses 100 ms slots anchored at its first accepted
sample. Late callbacks skip missed slots without shifting future deadlines or
backfilling records; original timestamps and freshness checks are preserved.
Legacy ground/coupled profiles keep their previous scheduling. The change passes
offline timing and full six-second byte-budget checks, but has not run in the
combined physical lab yet. Do not infer a live latency improvement from it.

The physical follower uses a fixed 200 ms source-time buffer. It derives each
server observation's original time from `monotonic_ns - server_age_ns`, anchors
the first grounded settling sample at zero, and preserves all subsequent timing
through the final source sample. Precise normalized time is retained separately
from the exact float32 wire value. A 1 ms timer advances playback on ordinary
native frames. The actor is interpolated only between known adjacent source
points; there is no extrapolation. Holding an already reached point avoids
unnecessary setters. The first point must match the native starting position.

The buffer intentionally adds 200 ms of playback latency. At most eight active
source points, 512 physical writes including restoration, six seconds of source
time, the original 400 ms destination acceptance lease and the eight-second
follower deadline remain enforced. A historical left bracket is path geometry;
a new point cannot renew the right bracket's original acceptance lease. Legacy
following retains its existing cadence and 200-write cap.

An applied receipt identifies the highest crossed source point separately from
the actual interpolated requested position and delayed actor/camera observation.
Crossing a source timestamp does not imply its exact endpoint was written. The
proof validates source brackets, fractions, native numeric precision, later-frame
observations and each crossed-point count. After submitting the final source and
receiving the passing trace end, the controller immediately seals the timeline.
Native Lua observes and acknowledges the final point, then restores normally;
controller ACK polling no longer delays the finish request. The original 400 ms
target lease is unchanged. Receipts retain only as many observations as fit below 3,800
bytes, with original counts and explicit truncation. Unrecorded frames are not
claimed as measured.

An autonomous replay in real KCD passes all 51 captured source points and restores
actor/FPS state. Minecraft, HUD composition and physical input were not active in
that replay. The later combined `fa370b...` run forwards all 52 sources, including
two authoritative LANDING samples, and the user confirms substantially smoother
motion. It retains 71 of 344 native observations: all advance one native frame,
median 16.037 ms, with zero position error. No intermediate source hold is
retained. The original primary result remains failed because restoration comes
from `frame_lease_expired`; the native receipt confirms the exact origin, zero
error and cancelled timers. A native end-of-stream drain now passes autonomous
replay `02e045...`, restoring through `explicit_end` after all 51 scripted points,
with zero restoration error and verified FPS restoration. It restores after the
final observation without waiting for controller polling. This does not extend
the 400 ms target lease. The subsequent `650a8e...` physical run passes all 56
source points and normal `explicit_end` restoration. Its 80 retained readbacks
each advance one native frame, median 16.113 ms/max 16.960 ms, with zero errors
and no intermediate holds. The earlier `fa370b...` failure remains historical.

Keep the 200 ms buffer as the current smoother baseline. Latest source capture
intervals are median 100.381 ms/max 133.976 ms; server-source gaps reach 151.432 ms.
First capture-to-dispatch is measured at 50 ms, later median 20 ms. Conditional
clock alignment estimates first capture-to-native acceptance/write at
68.4/279.3 ms, versus 123.8/333.9 ms previously. These separate runs have
cached-frame uncertainty and no per-key or display timestamps, so they are not
input-to-photon measurements or an isolated warmup/cadence effectiveness test.
Warmup runs only in disposable diagnostic state before arming; it takes 744.634 ms
in this live session. It never publishes synthetic points or starts native following.
This run needs 97.812 ms for right-point availability, but an earlier replay
needs 188.903 ms. A blanket 150 ms buffer would underrun that earlier trace.
Measure remaining latency before reducing playback delay, and preserve trace
budgets and sampled-ground safeguards when extending walking or adding aimed-block
integration. Continuous movement is still unfinished.

The subsequent START-phase repair consumes the whole physical/UI input queue
before vanilla polls movement KeyBindings. It removes the previous mandatory
END-to-next-START wait without changing source timing, native interpolation or
leases. The same phase passes an actual Minecraft scripted fixture with repeated
W/W/S, zero inventory displacement, HUD frames and normal cleanup. It does not
exercise the native physical input mapping. A later full live run `b850ba...`
now passes 57/57 transfers/readbacks with exact normal restoration and cleanup.
It also repairs the receiver's first-step descent: the fresh, exact supported
SETTLING anchor now supplies ground provenance before an immediate airborne
sample. No waypoint is omitted; stale/invalid anchors retain their guards.
Final evidence now includes `physical_movement.input_timing` with original capture
UTC, receipt timestamps and actual binding snapshots (32 retained rows per
series, explicit counts/truncation). The watermark is the latest movement-edge
sequence, not a guarantee that a batched edge reached vanilla. Use these clocks
to distinguish queue/application delay from the unchanged 200 ms native buffer;
they do not measure physical input-to-display latency. The live run records median
producer capture-to-receipt 16 ms and receipt-to-binding 0.1114 ms, with five paired
presses and no truncated histories. The user confirms it works with a little
delay; keep this baseline while extending bounded gameplay. See PROGRESS for evidence.

The KCD follower retains its independent eight-second deadline and actor/position
guards. Normal completion requires delayed readbacks
and verified return to the starting position; restoration only applies while
the probe still owns that actor/position. The helper also verifies release of
Minecraft controls/collision installations and restoration of the temporary
60 FPS cap, whose engine deadline remains 120 seconds. The probe does not change
KCD physics or call `FreezeInput`.

Camera requests run no faster than one per 110 ms on a monotonic clock, permitting
at most 1,019 requests within the worker's 112-second lifetime. Lua's 1,024-sample
budget, the 300 ms camera lease and the original capture timestamps are unchanged.
The current repairs change Java, Lua and scripts; an already installed matching
walking bundle does not need another native build or installation.

Evidence is retained under `runtime/evidence/hud-walking-*/`. A controller
`HUD_WALKING_PASS` must be reported separately from visual observations and
physical-input exclusivity. The file-sharing startup repair retries filesystem
reads for at most 100 ms without refreshing the original camera sample deadline.
This remains a short development test; sustained movement, expanding terrain
coverage, collision with placed blocks and a combined walking/aimed-stone mode
remain unfinished.

## Independent walking component checks

`scripts/Test-HudPhysicalMovementFixture.ps1` exercises the actual Minecraft
movement controller, vanilla client/server physics, inventory suppression and HUD
capture with explicitly scripted input. It makes no KCD calls and does not arm
the compositor or claim physical input. A supplied `-GroundPatchFile` is copied
as numeric fixture data with separate fixture provenance; it is not a live terrain
capture. Fixture output is excluded from the live follower route.

`scripts/Test-KcdPhysicalFollower.ps1` is a separate PowerShell 7.3+ probe for an
already loaded supported KCD tools world. It sends small scripted position offsets
and checks timed intermediate observations, exact endpoint readback,
stationary write suppression and restoration. It does not start Minecraft, arm the HUD, or press physical controls.
The unchanged follower lease and deadline remain active. Keep the player still
and use only the fresh development test world.

`scripts/Test-KcdBufferedReplay.ps1` replays a captured movement trace using its
original server-observation timing and the new buffered follower. It makes no
Minecraft connection, does not arm the HUD and uses explicitly scripted source
positions. The latest real-KCD replay passes 51 source points and restoration.
Its retained readbacks cover one native frame each at about 34 ms in that run;
no combined visual smoothness or physical input is claimed.

Current source checks pass 68 Lua cases, 79 buffered PowerShell checks and 32
timed-follower checks. The earlier fixed-duration component probe separately
passed five moving targets and one stationary target with zero position errors,
actor restoration and FPS restoration. These scoped results do not replace a
combined physical test of the new buffered mode.

The actual-Minecraft flat fixture also passes scripted W/W/S presses, moving both
client and server approximately 0.857 m, 0.642 m and 0.857 m with zero disagreement.
The second W pauses at the boundary; S resumes after release. Inventory W causes
zero movement, and actual inventory/hotbar frames are captured and inspected.
Controls, proxies, camera worker and HUD mapping are cleaned up afterward. A
second fixture replays the captured `c398...` terrain values and heading, with
approximately 0.447 m, 0.641 m and 0.641 m movement on both sides, two boundary
pauses and two resumptions, zero corrections and zero movement in inventory.
Its terrain remains labelled fixture data. These standalone fixtures never arm
KCD's HUD;
an already loaded fresh, unarmed KCD world can stay open for the later physical
check. Neither independent component establishes the full physical walking/HUD
experience or visual smoothness.

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
## Optional extended walking session

`scripts/Start-HudWalkingLab.ps1 -ExtendedWalking` selects 15 seconds of input
plus at most one second of settling, within the same 30-second HUD session.
Without the switch, the verified five-second input mode remains the default.
Begin movement within 12 seconds of F8. Inventory and boundary pauses consume
wall time; they cannot restart either deadline. Stay in KCD2 until the HUD closes:
switching away revokes input and ends the trace, even if the controls worked.

The extension uses explicit matching session markers in readiness, completion
and native receipts, with distinct live/fixture trace source kinds. Its native
entry point is `BeginExtendedBufferedPhysicalMovementFollower`, with a 16-second
source timeline, fixed 18-second deadline, 2,047 writes plus restoration and 256
receipts. Trace capacity is 256 KiB with the same 200-record ceiling. The old
profile retains its original budgets. Neither profile accepts the other's data.
The 200 ms buffer, original timestamps, eight-point queue, 400 ms destination
lease, sampled terrain, two-metre sphere and delayed readback checks are unchanged.
No renderer installation is needed: the guarded controller loads the Lua probe.

The extended standalone Minecraft fixture passes five W/W/S/W/S pulses, including
movement after the old cutoff and inventory reopened after walking. Its 15,593 ms
run records 159 trace records, 255 real UI frames, zero inventory displacement and
zero client/server corrections. This is actual Minecraft proof, not KCD proof.
See [progress](../docs/PROGRESS.md) for live outcomes and current evidence.
