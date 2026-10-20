# Connecting host clicks to Minecraft aiming

This is an opt-in development path. The verified live HUD still uses its existing
fixed-cell controls by default. The explicit `-AimedStone` controller mode now
validates the distinct guest proof and carries the acknowledged permit into each
physical click. `Start-AimedHudLab.ps1` selects the required capped, offscreen,
selective revision4 profile and automatically uses the installed PowerShell 7.
It requires an already-running official KCD2 test world and the matching installed
renderer bundle. It starts only the separate Minecraft client; no KCD launcher or
renderer installation is part of this controller.

Revision4 has been built, independently reviewed and installed unarmed on the
development machine, with the previous runtime/add-on backed up. It has not yet
been verified in a live KCD session. Existing revision3 artifacts and the earlier
fixed-cell test evidence remain preserved.

If preflight finds an expired arm from an earlier game process,
`Archive-HudArm.ps1 -ReceiptPath <its stream-arming.json> -ExpiredPriorProcess`
can preserve it in that run's evidence directory without restarting the new game.
This explicit option checks the exact file and receipt, expiry, absence of both
old process IDs, and one newer official-tools process started after expiry. It
cannot rearm a process that already accepted a session. The default archive path
still requires KCD to be closed.

## One alignment, one captured intent

The optional minor2 [wire protocol](../../protocol/PROTOCOL.md#optional-minor2-aimed-stone-arena)
agrees on Minecraft and KCD camera anchors before the first stone event. The new
`--aimed-stone --aimed-run <run>` tools-host mode maps replicas through that exact
agreement. It must not use the legacy display island placed in front of the camera.
The initial Minecraft seed remains two cells toward Minecraft +X, which maps to
KCD world +X; this is independent of the direction the host camera currently faces.

The separate Lua modules are loaded in order: `aim_probe.lua`, then
`aim_intent.lua`. The latter pins the sampler function and provides
`BeginAimedInput`, `InstallAimedPermit`, `AimedIntent` and `EndAimedInput`.
They use decimal strings for IDs because the inspected game uses float32 Lua
numbers. Loading or reloading the module revokes permits and begins no session.

1. Minecraft issues a single-use permit with a 500 ms lifetime measured by its
   own monotonic clock. The native relay retains the original receipt and generation.
2. After the first stone's engine acknowledgement, the relay installs a permit
   in Lua. Only a matching Lua acknowledgement produces `AIM_PERMIT_READY`.
   Its UTC time records when the native relay observed that acknowledgement.
3. The physical-edge selector in `scripts/AimedWorldClicks.ps1` accepts only an
   unused acknowledgement strictly earlier than the edge. Equal millisecond
   timestamps do not establish ordering. It rejects stale edges, changed runs,
   reordered IDs and observed clock rollback, and spends the permit before dispatch.
   The dispatch path checks owned processes/listeners and the exact original
   acknowledgement without replaying historical JSON. It rechecks foreground and
   freshness immediately before sending; full receipt correlation follows shutdown.
4. `AimedIntent` consumes that exact installed permit and samples camera position,
   direction and nearest `ent_all` obstruction in one synchronous Lua call.
   This sample occurs at the engine callback after the physical edge; it does
   not claim to capture the original renderer input frame. Missing obstruction
   data means unavailable, never clear space.
5. The relay validates the original permit, generation, sample and engine time
   interval. It normalizes only small float32 direction rounding before strict
   wire encoding. It never replaces the permit with a newly issued one.
6. Minecraft selects the actual block/face using its OUTLINE raycast and executes
   vanilla interaction APIs. Client/server confirmation, block events and KCD
   replica acknowledgements remain separate evidence.

The mapped request origin may be up to 0.25 Minecraft blocks from the actual
guest eye. The immutable arena anchors still require 0.15-unit agreement, and
the captured origin must remain within 0.15 KCD units of the current fresh host
camera pose. The original ray, vanilla reach, ownership and 500 ms permit lifetime
are unchanged. Native refusals now identify the failed check, including
`bridge_guest_view_origin` and `bridge_host_pose_origin`, with separate
pre-dispatch reasons such as `original_permit_expired`.

## Latest verification and remaining live check

The saved KCD run `5334822edbd5464397d6131962ff576e` produced seven physical
edges and four forwarded captures, but no `AIM_REQUEST` or `AIM_RESULT`.
Its native journal records three `bridge_refused` entries and one
`stale_or_unready_capture`. The three bridge-refused rays map to guest-eye
offsets of approximately 0.177945, 0.157205 and 0.150575 blocks, exceeding the old
0.15-block limit. Those captured values explain a concrete rejection condition;
they do not establish why the camera origin changed or which branch rejected
the fourth capture. Bootstrap replica cleanup and the separate Lua input-end
acknowledgement succeeded, but no aimed action was verified.

The native and guest request-view allowance is now 0.25 blocks. Native regression
tests use the three saved ray origins, exact/over-limit boundaries and unchanged
current-host/anchor limits. The actual Minecraft standalone run
`7291a5e04c4c44ec983f44be9e50447e` passes 25 scenarios, including measured-offset
and boundary selection checks. Its synthetic host rays produce the same 17
request records and eight confirmed actions as before: four placements and four
breaks, followed by empty ownership and normal Java/wrapper exit.

The revision4 capture-contention repair passes seven native test suites and
requires two neutral input frames after capture observation recovers. These
automated results do not establish live KCD targeting or identify the exact
thread/caller responsible for the earlier capture contention.

## HUD integration boundary

The `minecomeHudAimedStoneBridge` development property selects a separate guest
adapter in the existing live stone HUD profile. Its readiness marker and action
proof differ from the fixed-cell profile. Both the controller and direct arming
helper reject mismatched profiles, including an aimed guest presented as a
fixed-cell test. General walking, survival state and placing on
unrepresented KCD terrain are outside this bounded stone-cluster mode.

The arena pins the exact owned HUD save. A queued action that has not reached
vanilla is cancelled when HUD authority ends or an inventory screen opens.
An already-dispatched action still requires authoritative observation; stopping
does not convert an uncertain action into a successful result.

The Arena still requires the selected slot/stack to match through authoritative
confirmation. Changing it after vanilla dispatch but before that confirmation
can end this experimental HUD session, even when the block transition succeeds.
The integrated controller needs a focused transition check before this mode can
claim normal rapid slot switching during block actions.

On shutdown, native request authority is revoked before ending the Lua session.
Requests already written to the guest cannot be recalled. A stone cleanup ACK
proves replica removal; the separate `AIM_INPUT_END_ACK` proves the Lua input gate
ended. Shutdown now waits up to two seconds for both independent receipts; a
late input-gate acknowledgement is covered by a simulated-engine regression.
The bounded Lua lease remains a fallback if its end receipt is unavailable,
but the live controller does not certify cleanup without the acknowledgement.

## Running the bounded controller

From the repository root, after the matching selective revision4 profile
has loaded in a fresh official development world:

```powershell
& .\scripts\Start-AimedHudLab.ps1 -PreflightOnly
& .\scripts\Start-AimedHudLab.ps1
```

Keep the player stationary for this first alignment check. When `HUD_INPUT_READY`
appears, focus KCD2, close menus/console and press F8 to begin the existing 30-second
input lease. Wait for the bootstrap stone, turn the camera to aim at it, then
left-click once to break it. The seed is two Minecraft cells along world +X from
the guest player; its direction is independent of where the KCD camera initially
faces. This first check needs one confirmed aimed action. An empty cluster does
not automatically recreate its seed. Minecraft closes at the end, and the
controller checks original permits, guest results, engine replica receipts and
both shutdown acknowledgements separately. Visual crosshair alignment still
requires observation in KCD2.

The separate automatic adapter check is:

```powershell
& .\scripts\Start-HudAimedBridgeLab.ps1
```

It creates a fresh `MineCome-HudStream-UUID` world and runs the actual
`HudAimedStoneBridge` against a synthetic C++ host. Programmatic arming and host
rays are declared fixture inputs. It checks the adapter's vanilla bootstrap,
aimed break, client/server proof, native result/event receipt and final air.
It does not render the HUD in KCD2 or verify physical clicks. The fixture stops
ticking the live adapter after its completed action while it verifies the
synthetic host's normal shutdown; production disconnect handling stays unchanged.

See [progress](../PROGRESS.md) for the current build, simulated-engine and actual
Minecraft results. A real KCD crosshair test is still required before claiming
live aimed placement or breaking.
