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
development machine, with the previous runtime/add-on backed up. A subsequent
live session confirms prompt first-click breaking after a log-latency repair.
Existing revision3 artifacts and the earlier
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
   in Lua. The guest paces issuance at 100 ms; native installs each newest eligible
   ID without a second 100 ms scheduling gate. Latest-only selection, monotonic
   IDs and at most 16 retained records bound the work without renewing receipts.
   This is not a strict HTTP rate limit against a faster authenticated peer.
   Only a matching Lua acknowledgement produces `AIM_PERMIT_READY`.
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

### Corrected top placement verified

Automatic production-sink run `e3eb3bbcfa9a45a68363f46355b0d1f5` verifies actual
zero world angles and matching world bounds for seed, UP and WEST neighbours.
The upper block's minimum Z equals the seed's maximum Z; the west neighbour's
maximum X equals the seed's minimum X. All temporary objects then clean up.
This confirms live engine transforms, separately from Minecraft interactions.

The next physical run `7ab72119af9e4401bed3cbbb6337aa42` passes:

| Request/permit | Minecraft selection and action | KCD ACK sequence |
|---|---|---|
| 1/51 | UP of original seed `(-8,-60,0)`; place at `(-8,-59,0)` | 564 |
| 2/70 | Break upper block `(-8,-59,0)`, hit WEST | 629 |
| 3/83 | Break original seed `(-8,-60,0)`, hit UP | 674 |

The first hit is near the centre of the original top:
`(-7.500625767,-59,0.500734634)`. All three original captured rays match the
immutable guest plans; only direction normalization at float32 precision occurs.
Canonical results, client/server proof and mapped KCD acknowledgements agree.
There are exactly three physical intents and three confirmed network actions,
with no native or guest refusals. The guest has zero owned/pending stones;
both processes exit normally, and engine/input cleanup and cap restoration pass.
The user reports “worked perfectly.”

The renderer closes on foreground loss at 11.062 seconds and records 187 uploaded
frames. This verifies the intended sequence and visible targeting; it does not
establish 30-second stability or every other face. Renderer snapshot SHA256:
`f380af4210c3812aaee6e9cf08dd9e3626507b42331e7dab53f820f4cec9162e`.

### Rendered cube offset — 2026-10-20

The top-only retry `f074546edb4441f69c8951d727ba0b5c` again produced a WEST
placement followed by UP on the added side block. The user reported aiming at
the visible original top. The next automatic diagnostic measured the actual
production sink object:

| Property | Measured value |
|---|---|
| Requested and actual entity position | `(121.68408203125,2041.2486572265625,56.279521942138672)` |
| World angles | `(0,0,-1.5707962512969971)` |
| Entity/slot scale | `1` / `1` |
| Slot position/angles | Zero |
| Local bounds | `(0,-1,0)` to `(1,0,1)` |
| Actual world bounds | `(120.68408203125,2040.2486572265625,56.279521942138672)` to `(121.68408203125,2041.2486572265625,57.279521942138672)` |
| Intended world X interval | `121.68408203125` to `122.68408203125` |

The engine's default entity rotation therefore shifts this asymmetric local cube
one unit in negative X. The saved first-click ray hits the visible top at
`(121.159468249,2040.738715266,57.279521942)`, distance 1.006076452 m. The same
ray hits the logical WEST face 0.343107 m below its top at distance 1.634615 m.
Camera direction is stable across 61 surrounding pose samples, including at
least 1.1289 seconds before and 2.7206 seconds after the capture; camera-origin
sway is at most 7.26 mm. This is a measured render/pick offset, not a rounding
tie or dispatch-time camera turn.

Installed CGF bytes match the compiled asset. Its 24 vertices, 36 indices,
outward triangle winding and identity node transform are correct. The installed
BasicEntity script adds no transform. A separate read-only forward projection
sample lands near the virtual screen centre, but `System.ProjectToScreen`
explicitly lacks guarantees outside the renderer and is not alignment proof.

The diagnostic's bounded sink session `1792505901202000` cleaned up successfully.
Its source commands, fresh readbacks and cleanup are preserved in
`runtime/evidence/stone-world-bounds-20261020-151821-c2493cc15cef4baa8170cbb74166322f/`.
The full live game log snapshot is `capture/kcd-observed.log` under the f074 run,
SHA256 `8a593d90b2d845995aaf60596e02881cc5a9cbae041e3e1f73949e495e61050d`.
The renderer snapshot SHA256 is
`bd07be4df7536c7e31e3008f9fccd8728fa79977c24857473173aa1d6d325de1`.

The fix uses documented `Entity.SetWorldAngles(vAngles)` with zero angles and
checks actual world bounds before success. The inspected binding is
`external/kcd2-mod-docs/script_bind_2025_01_14/CScriptBindEntity__SetWorldAngles@IFunctionHandler__@Ang3.html:60`;
the shipped `AnimObject.lua:614` also calls this API. No renderer hook or hitbox
tolerance change is needed. Both spawn paths share the repair, and
`already_present` revalidates existing geometry without silently moving it.
The world and local endpoints must match within 0.01 m; malformed/unknown
readbacks reject placement and retain cleanup ownership. All 64 Lua cases pass.
The reviewed source is installed with the old package backed up and the compiled
CGF unchanged. The later live bounds and top-face checks above pass.

The f074 guest completed with five confirmed network actions and zero owned or
pending stones. Three extra clicks were refused while the preceding removal
awaited engine acknowledgement. A repaired audit accepts this narrow busy case
only with a unique same-session pending/removed/ACK interval, later validated
against the full guest/event/cell/ownership chain. Its 165 checks and five
read-only replays preserve original evidence; the original controller receipt
remains failed. The separate corrected run above verifies the orientation repair.

### Earlier face and latency checks

Run `3c111cfc7ed242089dff99066a0ca7ae` is an incomplete face-placement attempt.
The user saw placement on the face toward them and both added blocks breaking,
but did not identify top placement. The recorded confirmed actions are:

| Request | Minecraft selection/action | KCD acknowledgement |
|---|---|---|
| 2 | WEST of seed `(8,-60,1)`; place at `(7,-60,1)` | 601 |
| 3 | UP of added block `(7,-60,1)`; place at `(7,-59,1)` | 643 |
| 10 | Break upper added block `(7,-59,1)` | 735 |
| 12 | Break lower added block `(7,-60,1)` | 762 |

Each has matching original captured ray, canonical request/result, client/server
confirmation and mapped engine event. The UP placement was on the added side
block, not the original seed's top. Request 1 expired at 508.3593 ms before guest
selection; request 4 entered at 437.8217 ms but expired before vanilla dispatch.
Three further placements returned `vanilla_dispatch_rejected`. These outcomes
do not establish a hitbox error.

Repeated attempts reached the physical-click limit; closure cancelled the final
seed-break request. The guest retained one owned stone and one cancelled pending
action. The controller remains failed even though native/Java exited normally and
KCD cleanup, independent input-end acknowledgement and cap restoration passed.
The next check isolates one placement on the original seed's UP face, then breaks
the added block and seed, waiting for each visible result.

The redundant native installation timer has been removed and the release tools
host rebuilt. All three simulated HTTP suites pass, including new checks that
quiet-peer polling cannot reinstall a permit and a new ID receives exactly one
installation without further peer issuance. Original expiry and single-use
authority remain unchanged. This repair awaits the top-only live retry; the
simulated checks make no end-to-end latency claim.

Run `dc93d381b60b4461952d024017b186c7` passes the live controller with one physical
click, one wire request, one actual Minecraft client/server break and its KCD
removal acknowledgement. No native refusals, guest stale replies or queue drops
occurred; the user reported “barely any delay.” The guest closes normally with
`input_completed`; engine cleanup, separate input-end acknowledgement and frame-cap
restoration pass. The renderer uploaded 108 frames, then closed on foreground
loss to Explorer 6.7 seconds after F8, so this is not a 30-second stability result.
The later face-placement attempt above does not yet complete that milestone.

Run `67b5fd8e70bc46ed97fc8f52d999489b` confirms physical request6/permit83 through
the canonical socket journal, actual Minecraft client/server break, block event
and engine removal acknowledgement. The user reported multiple clicks before
disappearance. The other outcomes are native refusals (requests1–4 and7) and a
guest transport stale refusal (request5), not confirmed actions. Original
controller verification remains failed because it required every capture to
produce an adapter request. The repaired validator passes 124 checks and a
read-only replay of this evidence while preserving the original receipts.
Earlier zero-action runs remain rejected. Native refusals, transport stale
replies and confirmed adapter actions stay separate; any intermediate
`cleanup_pending` receipt must match the later removal and acknowledgement.
This establishes one aimed break, not reliable
responsiveness or alignment on every block face.

Revision4 run `0565b12d8af64ad7980a7999b870e844` admitted one physical click and
captured ray, but native then reported `queued aim expired or reset` before
writing any `AIM_REQUEST`. The user saw the stone disappear; the native ledger
shows this was session cleanup, with no confirmed guest break. The original
aggregate error cannot isolate permit expiry from pose/generation failure.
The mouse/camera rejection did not recur on that click. Cleanup and frame-cap
restoration passed, but the overall live check failed.

The native queue repair now consumes expired unsent intents without destroying
an otherwise valid arena, and journals their original permit ages separately.
It polls minor2 outbound work every 5 ms while preserving the 500 ms lifetime.
Deterministic loopback regression verifies no write/result for an expired queued
intent and successful processing of a later fresh request. Generation or stale
pose authority still terminates. The bounded live validator reports any local
drop explicitly and does not count it as a Minecraft action.

KCD's latest log record can be complete JSON without a following newline. The
aimed relay now processes such critical receipts immediately using its existing
strict 4096-byte parsers. It retains the exact processed tail until the separator
arrives, skips it once and invalidates changed suffixes. Incomplete fragments
retain their original age and connection/reset history. Aimed log polling is
5 ms; pose sampling remains at least 50 ms after the previous HTTP call
completes. The simulated aimed, stone and interactive HTTP suites pass, followed
by the successful first-click live check above.

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

Selection must match through the pre-dispatch proof and the immediate return
from the vanilla call. After dispatch, confirmation checks the original slot's
unchanged item/count on client and server, independently of current selection.
A harmless hotbar switch therefore does not invalidate an action already underway.
Changing the original stack still fails confirmation.

Actual Minecraft run `3e32c1486caf41e4ad1d712ed4e112e4` passes 28 standalone
scenarios, including refusal before dispatch, successful placement/breaking with
selection changed afterward, and a subsequent action. Both switched confirmations
observed the new selection on client and server. A separate expected-failure
arena verifies original-stack mutation is still rejected, with independent
client/server air and inventory-restoration proof. These synthetic-host tests
do not establish rapid slot switching during an aimed KCD session.

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
Minecraft results. First-click aimed breaking is now verified in KCD; aimed
placement across different faces remains the next live check.
