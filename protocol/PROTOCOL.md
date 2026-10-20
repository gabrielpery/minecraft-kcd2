# MineCome wire protocol 1.0, fixed-cell 1.1 and aimed 1.2

TCP IPv4 loopback only, default `127.0.0.1:38765`. This is a control/state prototype;
large render payloads are intentionally excluded. The host owns the listener, one
client session at a time. Every reconnect repeats authentication and resets sequence
numbers. A cryptographically random 256-bit local token is stored as 64 lowercase hex
characters in `config/bridge.token`, never sent to remote addresses or printed.

All integers and IEEE-754 doubles are little endian. Every frame begins with:

| Offset | Bytes | Meaning |
|---|---:|---|
| 0 | 4 | ASCII `MCME` |
| 4 | 2 | major version 1 |
| 6 | 2 | minor version 0 by default, fixed-cell input 1, or separately opted-in aimed input 2 |
| 8 | 2 | message type |
| 10 | 2 | flags, must be zero |
| 12 | 4 | payload length, at most 65,536 |
| 16 | 8 | nonzero sequence, strictly increasing in this connection/direction |
| 24 | 8 | sender monotonic microseconds, not a shared clock or wall time |

The receiver validates the header before allocating/decoding payloads. An incomplete
frame has a six-second deadline. Invalid version, type, sequence, sizes, credentials
or payloads close the session. Heartbeats are sent after one second without traffic;
six seconds without a complete valid frame disconnects. Java retries after one second.
Mailbox snapshots are copied under a lock/atomic reference; no engine objects cross
the network thread boundary. Snapshot messages are at most 20 Hz, with latest-value
coalescing. Event queues are bounded; this feed is diagnostic, not a reliable world
replication log. World persistence and full block resynchronization remain future work.

| Type | Name | Payload |
|---:|---|---|
| 1 | HELLO | role u32, capabilities u32, name byte length u16, credential byte length u16, UTF-8 name, UTF-8 credential |
| 2 | HEARTBEAT | empty |
| 3 | KCD_POSE | 128-byte pose, space=1 |
| 4 | MC_POSE | 128-byte pose, space=2 |
| 5 | BLOCK_EVENT | operation u32 (1 added, 2 removed), x/y/z i32, registry ID byte length u16, UTF-8 ID |
| 6 | ERROR | reserved; current receivers disconnect on this type |
| 7 | GOODBYE | empty; terminate gracefully |

Client sends HELLO first, role 2 (Minecraft) or 3 (explicit test harness), credential
equal to the local token. Host responds HELLO role 1, empty credential. Names are
1–128 UTF-8 bytes; credentials at most 128 bytes. Capability extensions need a version
change; minor0 supports only zero. The opt-in minor1 extension below requires
capability1 and a real Minecraft role. Optional minor2 requires capability2 and the
real Minecraft role; it does not combine capability1 and capability2. Existing
host callers disable minor2 unless explicitly enabled. No state is exchanged before authentication.
The token protects against accidental local peers, not an attacker who can read the
user's files. Host identity is not cryptographically authenticated in this prototype.

Pose payload:

| Offset | Bytes | Field |
|---|---:|---|
| 0 | 24 | player position, three doubles |
| 24 | 24 | camera position, three doubles |
| 48 | 32 | camera-to-world unit quaternion x/y/z/w, four doubles |
| 80 | 8 | vertical FOV in radians, strictly between 0 and pi |
| 88 | 24 | proposed KCD world origin, three doubles |
| 112 | 8 | positive finite Minecraft blocks per KCD coordinate unit |
| 120 | 4 | space: 1 KCD, 2 Minecraft |
| 124 | 4 | validity flags: 1 player, 2 camera, 4 calibrated transform, 8 loaded world |

Every number is finite, quaternion squared magnitude must be within 0.001 of one.
Flags zero means unavailable state, not a real player at the origin. Camera local axes
are +X right, +Y up and -Z forward. Native forward/up vectors must be converted to
that basis; a CryEngine quaternion must not be copied blindly. Minecraft's render
camera quaternion comes from `Camera.getRotation()`; current FOV is the configured
vertical FOV and does not yet include transient sprint/zoom/death modifiers.

## Coordinate hypothesis, not live calibration

Let `o` be a KCD origin and `s` Minecraft blocks per KCD unit. Assuming KCD has
right-handed +Z up, +X right, +Y forward:

```text
mc.x = (kcd.x - o.x) * s
mc.y = (kcd.z - o.z) * s
mc.z = -(kcd.y - o.y) * s
kcd.x = mc.x / s + o.x
kcd.y = -mc.z / s + o.y
kcd.z = mc.y / s + o.z
```

This is a proper rotation (determinant +1), so winding remains unchanged. Convert a
camera-to-KCD quaternion by left-multiplying rotation X(-pi/2). The inverse uses
X(+pi/2). Unit tests check signed axes, origin, scale, inverse and a known camera
basis. They establish algebraic correctness, not game scale or player eye height.
Default `s=1` is provisional. Never set the calibrated flag until live measurements
confirm axes, distances, world identity and FOV. World/level IDs, physics/camera
authority, collision geometry, general input, texture/mesh payloads and frame synchronization
require later versioned extensions.

Cached received poses expire after one second even if heartbeats continue. The
aimed extension additionally requires player/camera/in-world validity and poses
no older than 500 ms; it does not extend the legacy pose lifetime. The
official-tools adapter also clears validity after world loss, stale sampling or
HTTP failure. Java HELLO reception has an absolute six-second deadline independent
of fragmented arrivals. Java socket writes currently use blocking stream output;
the daemon does not block gameplay, and shutdown closes its socket after a bounded
wait, but a future movement/render transport needs explicit write deadlines.

## Transient stone consumer, unchanged wirev1

BLOCK_EVENT retains its18-byte fixed prefix plus UTF-8 ID; no world ID or ACK has
been added to the wire. MC world/dimension changes force fresh authentication.
Outgoing event entries carry local connection generations, and overflow resets the
socket rather than continuing after a lost event. Native receipt mailboxes retain
wire sequence, connection/reset generation and valid MC pose at receipt. Capacity256,
drain<=64; overflow clears the previous queue and raises a reset token. Harness role3
can still exercise/count the protocol but cannot produce engine writes.

The optional official-tools stone consumer requires session Begin/Apply/End log
receipts from original Lua before claiming engine acknowledgement. Those receipts
are local diagnostic data, not a protocol ACK returned to Minecraft. Reset is
acknowledged only after confirmed Lua cleanup. Display alignment is session-local
and never sets CALIBRATED; future persistent/world-aware replication requires a
versioned protocol extension and explicit authoritative snapshots/resync.

Before enabling real console writes, this consumer verifies the running development
image path and its actual resource combination: fixed version `1.0.0.0`, translated
FileVersion and ProductVersion `1.5.5.0`. The combined test loads an original,
hash-matched Lua snapshot from a unique read-only workspace path through
`Script.LoadScript`. A fresh contract marker requires a changed session-start
function reference; snapshot/source hashes and the proof are local evidence,
not additional wire fields. The installed package is updated only after KCD2 closes.

The development game's Lua/console numeric boundary rounds like float32. The native
adapter sends session IDs and wire sequences as quoted canonical decimal strings,
for example `#MineCome.BeginBlockSession('1791733572711306')`. Lua compares their
length and digits, without numeric coercion, and preserves them in ownership and
pending-removal records. Tokens must be 1–9007199254740991, without leading zeroes.
Receipts emit the validated digits as bare JSON numbers; native parsing uses the
original decimal text and `stoull`, so float32 never handles these identifiers.
Wire sequence fields remain u64 and BLOCK_EVENT coordinates remain i32. The current
Lua consumer additionally rejects MC coordinates outside ±16777215, the chosen exact
integer range for numeric console arguments.

A remove receipt with `cleanup_pending` is intermediate. Lua's cleanup timer retries
the owned deletion and emits `removed` with the same session and original sequence
only after both ID/name lookups confirm the owned entity is absent. The native
consumer holds the next event until this final receipt or its existing bounded
deadline; timeout ends the session and waits for cleanup. End/cleanup receipts are
not counted as successful individual removals, and old-session receipts cannot
acknowledge a current event. The combined test reports vanilla gameplay, engine
acknowledgements and human visual verification separately.

## Optional minor1 stone input

The interactive lab requests minor1 with `CAP_STONE_INPUT=1` in HELLO, role2 only.
The host echoes minor1/capability1. All later frames must use that negotiated minor.
Minor0 and harness sessions retain capability0 and cannot receive stone input.
Unknown capability bits, minor1 without capability1 and mismatched session minors
are rejected. Existing pose and block-event payloads are unchanged.

| Type | Name | Payload |
|---:|---|---|
| 8 | STONE_INPUT_REQUEST | request ID u64, action u32: 1 place stone, 2 break stone; exactly12 bytes |
| 9 | STONE_INPUT_RESULT | request ID u64, action u32, result u32; exactly16 bytes |

IDs must be1–9007199254740991 and increase within each authenticated connection.
Result codes are1 dispatch accepted,2 unavailable,3 stale,4 busy,5 occupied,
6 absent and7 vanilla failed. Accepted establishes vanilla API dispatch only;
it is not a client/server state confirmation or KCD engine acknowledgement.
The native result must match an outstanding request's ID/action. Late, unmatched
and duplicate results are ignored. The existing block observer and acknowledged
Lua sink provide separate world-change evidence.

Native queued/inflight/undrained results share16 slots. Requests and inflight
responses expire after one second. Native and Java mailboxes carry local
connection/reset/world generations and clear on loss, reset, overflow and shutdown.
Explicit native cancellation clears pending work without resetting replay history.
It waits for any network dispatch already in progress; sent actions cannot be recalled.
The host rejects intent log batches older than one second or crossing a connection/
reset boundary, and atomically rechecks captured generations when queueing.

KCD commands `minecome_place` and `minecome_break` call original Lua intent code
on its engine console. Lua requires a valid player and finite engine clock, shares
a250ms rate limit, retains exact decimal-text request IDs across module reloads,
and registers only those two command names. It does not change any entity itself.
The tools adapter forwards fresh log intents only in `--interactive-stone` mode,
after a fresh KCD player/camera and reset-acknowledged real-Minecraft world pose.

Java actions run on Minecraft's client tick, confined to a newly created UUID
Creative save and one fixed reachable cell. It checks session age, host validity,
Creative mode, chunks, solid support, occupied/air state and one pending action
immediately before using vanilla inventory/interaction APIs. Integrated-server
state is observed on its own thread. No movement, keybinding override, general
input, persistence or initial-world snapshot is added by this extension.

## Optional minor2 aimed stone arena

The optional minor2/capability2 extension is implemented in the C++/Java codecs
and bridges. Existing minor0/1 callers and live fixed-cell controls remain on their
original paths. The new `AimedBridgeLab` connects actual Minecraft to an explicitly
synthetic C++ host; its automatic two-process run passes an exact arena ACK,
confirmed bootstrap, aimed network break, separate removal/result and cleanup.
The tools-host's explicit `--aimed-stone --aimed-run <run>` mode now uses the
extension and the agreed replica alignment. Its Lua permit/capture route passes
simulated-engine integration tests. The explicit bounded aimed controller joins
the HUD guest and physical-edge permit selector. An actual Minecraft fixture
verifies the production HUD adapter against a synthetic native host; actual KCD
crosshair verification is still outstanding. See
[aimed controls](../docs/research/AIMED-CONTROLS.md).

The implemented minor1 fixed-cell request remains unchanged. `AimGeometry`
(Java) and `aim_geometry.hpp` (C++) contain pure alignment and reference-ray
math only. Their shared fixture `tests/fixtures/aim_geometry.txt` checks 22
identical map, orientation and hit/miss vectors. Passing these tests does not
demonstrate crosshair targeting, KCD camera calibration, engine ray capture or
new gameplay. Actual Minecraft target selection must use its world raycast,
not the reference cube picker.

The intended live feature is a bounded, visible **stone cluster**. A bootstrap
stone is placed through the real vanilla action path. The optional aimed KCD
sink uses this arena's alignment to display the cluster; its live verification
is outstanding.
Thereafter a fresh camera ray selects an owned stone for breaking, or adjacent
placement using the returned face. Implemented limits are 16 owned cells, a
5×5×5 cell volume, a 4.5 KCD-unit ray, and Minecraft's
actual interaction-reach checks. An empty cluster has no invented support.
The ordinary superflat floor is not rendered in KCD and must not be an aimed
placement surface. The earlier captured 5×5 terrain patch is injected only
into `BlockCollisionSpliterator`; it provides neither Minecraft block state,
OUTLINE raycast shapes nor vanilla block-item support. Host terrain placement
requires a separate, explicit support representation and is not part of this
cluster feature.

### Message layout and lifecycle

HELLO selects exactly minor2/`CAP_AIMED_STONE=2`, role2. A minor2 frame may contain
base types1–7 or new types10–14; fixed-cell types8–9 are rejected. Unknown or combined
capabilities, changed minors and harness role3 with this capability are rejected.

| Type | Name | Exact little-endian payload |
|---:|---|---|
| 10 | ARENA_OFFER | arena ID u64; Minecraft anchor xyz f64; KCD anchor xyz f64; scale f64; seed xyz i32; minimum xyz i32; maximum inclusive xyz i32: 100 bytes |
| 11 | ARENA_ACK | Byte-for-byte copy of the 100-byte ARENA_OFFER payload |
| 12 | AIMED_STONE_REQUEST | arena ID u64; request ID u64; permit ID u64; action u32; occlusion u32; host origin xyz f64; unit direction xyz f64; range f64; nearest obstruction distance f64: 96 bytes |
| 13 | AIMED_STONE_RESULT | arena ID u64; request ID u64; action u32; result u32: 24 bytes |
| 14 | AIM_PERMIT | arena ID u64; permit ID u64: 16 bytes |

IDs are 1–9007199254740991. Arena bounds must equal seed±2 on each axis, and
scale must be exactly1 in this initial extension. Coordinates, mapped bounds and
ray endpoints are finite and limited to ±10,000,000. Ray direction squared length
must differ from1 by no more than1e-9; range is greater than0 and at most4.5.
Actions remain1 place/2 break. Occlusion is0 unavailable,1 clear,2 hit. Only a hit
may carry a nonzero nearest distance, within the ray range; unavailable cannot act.

Minor2 result1 means **confirmed on the Minecraft client and integrated server**,
unlike minor1's dispatch-only result1. Other codes are2 unavailable,3 stale,4 busy,
5 occupied,6 absent,7 vanilla failed,8 invalid target,9 host obstructed,10 out of
reach. A result must match the outstanding arena/request/action and connection.
It does not acknowledge a KCD engine entity; actual block events and engine
receipts remain separate evidence.

The guest offers one immutable arena per authenticated connection. The host checks
fresh player/camera/world poses and both anchors, waits for its local consumer reset
acknowledgement, and writes the exact arena ACK before admitting events/permits.
Changed or duplicate offers/ACKs fail; an unacknowledged offer expires after six
seconds. Reset, world loss and disconnect revoke the arena and its requests.

Anchor agreement at negotiation remains within 0.15 units in each anchor's
coordinate system. A captured request origin must also remain within 0.15 KCD
units of the current fresh host camera pose. Separately, its mapped Minecraft
origin may differ from the actual guest eye by at most 0.25 blocks. The native
bridge checks this against the guest pose; Minecraft repeats it during client
selection, authoritative prestate observation and client predispatch. This
request-view allowance does not move either anchor, clamp or replace the ray,
or extend vanilla interaction reach.

After ACK, the guest issues one-use, increasing permits with a 500 ms local lifetime.
At most16 permits are retained. The host captures a ray only after receiving its
permit and requires fresh poses plus a matching session, arena and permit immediately
before dispatch. The guest measures age from its own permit issue time, so queue
and network transit are included without comparing clocks across processes. Reused,
expired or unavailable samples cannot become vanilla actions. Only one aimed
request is pending; the host's matching result deadline is three seconds. The
guest's output mailbox is bounded and overflow closes the session.

If an admitted native request expires before any socket write while arena,
generation and pose authority remain valid, the host consumes and discards that
unsent request without disconnecting the healthy arena. It records
`AIM_QUEUE_DROPPED` with the original permit's admission/dispatch ages. This is
local diagnostic evidence, not an `AIM_REQUEST` or a Minecraft result. A later
physical click needs a new request ID and permit. Generation/authority failures
still terminate the session. Minor2 polls for local outbound work every 5 ms;
minor0/1 retain their 25 ms cadence. No expiry has been extended.

Native minor2 block events are stone-only, inside the agreed bounds, with the first
placement at the seed. Duplicate additions, removal of unowned cells, more than16
owned cells or events before the reset/arena ACK are rejected. Neither network
peer is permitted to create a Minecraft block state directly.

### Gameplay ordering and remaining KCD integration

1. Negotiate the explicit aimed-stone capability and message schemas; retain the
   existing minor 0/1 semantics and reject capability/version mismatches. Do
   not extend the 12-byte minor 1 request in place or reinterpret raw pose
   calibration fields.
2. Before bootstrap, exchange one immutable arena ID, Minecraft anchor, KCD
   anchor, blocks per KCD unit and finite cell bounds. Both peers acknowledge
   that exact alignment before accepting aimed requests or displaying seed
   events. Only one alignment is allowed per authenticated connection; reset,
   world loss or replacement requires full cleanup and a new connection.
   The KCD sink must use this alignment rather than creating a different one
   when the first block event happens to arrive. A translated display island
   is not global terrain/player calibration, so the `CALIBRATED` pose bit stays
   clear until that separate measurement is complete.
3. **Implemented; one live aimed break verified:** capture the camera origin/forward and nearest
   physical host obstruction in the same Lua aim-intent call, tied to the original
   click/request and arena ID. The implemented request carries the immutable ray,
   obstruction availability and distance plus its one-use permit ID. Do not combine
   an action with an unrelated latest 5 Hz pose. Bound capture-to-dispatch age,
   reject duplicate IDs, and never retry ambiguous
   dispatch. An absent/invalid host occlusion sample is not evidence of clear
   space.
4. On the actual Minecraft client thread, map the captured ray into the arena
   and call `World.raycast(new RaycastContext(start,end,OUTLINE,NONE,player))`.
   Require the hit block to be an owned stone; use its actual `BlockHitResult`
   face and hit point with `interactBlock`, or its block/face with `attackBlock`.
   Refuse a closer host obstruction, outside-arena/out-of-reach target,
   inventory screen, stale sample, unsupported selected item, or occupied
   destination. Observe the chosen cell/support on the integrated-server
   thread and require fresh agreement before dispatch and after the change.
5. Retain separate evidence for request admission, vanilla dispatch,
   authoritative block transition and KCD engine acknowledgement. The pending
   action must pin target/support/face and its immutable alignment rather than
   re-reading a moving crosshair while waiting for server confirmation. Each
   block event remains an actual Minecraft state transition; no native or Lua
   aim code may synthesize a gameplay block mutation.

For anchors `M` (Minecraft) and `K` (KCD), and scale `s` blocks/KCD unit:

```text
KCD(p) = K + ((p.x-M.x)/s, -(p.z-M.z)/s, (p.y-M.y)/s)
MC(q)  = M + ((q.x-K.x)*s, (q.z-K.z)*s, -(q.y-K.y)*s)
MC direction = (KCD direction.x, KCD direction.z, -KCD direction.y)
MC ray length = KCD ray length * s
```

The camera quaternion maps local −Z to world forward; no FOV is needed for the
centre ray. The pure reference AABB helper marks origins inside a box and uses
stable XYZ ordering on equal-distance cell hits. Minecraft's actual shape
raycast remains authoritative for real face/edge behavior.

Implementation seams are `StoneConsumer::update` and `AimedInputRelay` in
`kcd2/src/tools_http_host.cpp`, `StoneAlignment::from_arena/map` in
`kcd2/src/stone_mirror.cpp`, the separate `HudAimedStoneBridge`, and
`AimedStoneArena`. Legacy `HudStoneBridge` retains its one-cell/UP-face actions
and original protocol/mailboxes. Minecraft 1.21.1
named bytecode confirms `Entity.raycast` uses `RaycastContext.ShapeType.OUTLINE`
and `World.raycast`; the same cached classes expose `interactBlock` and
`attackBlock`. Existing `kcd2/probes/ground_probe.lua` documents the inspected
official `Physics.RayWorldIntersection(origin, direction*range, maxHits, mask,
skipPlayerId, nil, privateHits)` call and checked `pos/normal/dist` fields.
An aimed occlusion probe must use the actually exported `ent_all` mask to
include host obstacles; the terrain-only sampler cannot establish wall
occlusion. Mirrored stones currently have `physics=false`, so the host ray
does not replace Minecraft selection of those stones.

The bounded controller now loads the Lua modules, forwards physical clicks with
their original acknowledged permits, and validates the separate aimed HUD proof.
KCD run `67b5fd8e70bc46ed97fc8f52d999489b` confirms one physical aimed break
through Minecraft client/server state and the matching engine removal. Earlier
clicks were mostly refused before selection because their permits expired.
The lower-latency log reader passes HTTP integration tests; first-click
responsiveness still needs live verification.
Centre-ray alignment on several block faces while turning, and any later movement
support, remain unverified. Standalone Minecraft selection and
transport checks do not prove host camera timing, eye/feet alignment or KCD gameplay.

### Read-only host aim sample implemented (no aimed request enabled)

`kcd2/probes/aim_probe.lua` now samples the actual camera origin and normalized
forward plus one `ent_all` obstruction ray in the same synchronous engine call.
Its range is 4.5 units; it skips the player and uses a private, bounded hit table.
All reported hits must have finite positions/distances consistent with the ray.
The nearest valid hit is selected even when the binding returns unsorted hits.
Missing bindings, malformed hits, a saturated buffer, changed player identity,
clock rollback or a sample lasting over 0.25 seconds produce `unavailable`.
Only a valid zero-hit result claims clear space. Engine time is not UTC.

The separate `scripts/Test-KcdAimProbe.ps1` caller pins the existing tools process,
loads an immutable source snapshot, verifies its unique function reference and
requires a fresh matching engine receipt. It performs no block action, movement,
input capture or game launch. Mock engine tests pass 14 groups/1,533 checks, and
the strict host-side receipt validator passes 343 checks for numeric types,
finite vectors, unit/scaled rays, timing, hit geometry and availability flags.
The probe is not yet live verified. KCD was closed after the successful camera test.

This establishes a host sample contract. The separate `aim_intent.lua` now pins
this sampler and consumes an installed one-use permit when capturing a click's
ray. That capture occurs at the later Lua callback, not at the renderer input
frame; it cannot reuse the most recent diagnostic sample. Alignment must be agreed before
bootstrap, using the actual guest camera and sampled host camera for the first
turn-only lab. Inverting the existing four-unit display offset would place the
ray origin away from the actual Minecraft player and invalidate reach assumptions.

### Standalone Minecraft aimed arena

`AimedStoneArena` implements the guest selection/action portion independently of
the existing fixed-cell bridge. It pins one immutable alignment and a fresh
Creative world, allows at most 16 confirmed owned stones within a 5×5×5 cell
volume, and requires a host ray no longer than 4.5 units and no older than 500 ms.
The mapped request origin must agree with the actual Minecraft player's eye within
0.25 blocks on both the client and integrated server; the captured ray and
vanilla player-reach checks remain unchanged. Host obstruction is
explicitly clear, hit, or unavailable; unavailable samples cannot act.

Selection calls Minecraft's real `World.raycast` with `OUTLINE` and `NONE`.
Only an owned stone can be selected. The returned block, face and hit point are
retained through server prestate observation and client revalidation, then used
by vanilla `interactBlock` or `attackBlock`. A later camera turn cannot redirect
the pending action. Ownership changes only after client/server agreement on the
result. Rejected request IDs are consumed, and a deadline, changed world, missing
chunk or unexplained owned-cell transition prevents further actions.

The only floor-support exception is one explicit initial vanilla bootstrap.
Removing the last owned stone leaves an empty arena; there is no automatic seed
or invented terrain support. Minecraft's ordinary placement collision checks
remain active. The bounded volume and entity collisions may refuse some adjacent
placements even when the selected face itself is valid.

`Start-AimedStoneLab.ps1` exercises this component in a separate actual Minecraft
process, using synthetic host rays, a fresh UUID flat world and declared fixture
teleports. It opens no bridge connection and makes no KCD calls. The default
minor 0/1 path, live fixed-cell controls and installed renderer are unchanged.
This original standalone lab does not enable the new minor2 wire extension.
Paired live host click/sample and KCD replica verification remain unfinished.

The 2026-10-20 standalone run `7291a5e04c4c44ec983f44be9e50447e` passes
25 scenarios with actual client/server observations and synthetic host rays.
Added selection-only cases accept a measured 0.17794543-block request-origin
offset and the 0.25-block boundary, and reject 0.250001 blocks. The fixture still
retains 17 request records, eight confirmed actions, four placements/four breaks and
final empty ownership. It makes no KCD connection.

### Actual-Minecraft network fixture

The separate `AimedBridgeLab` opt-in uses minor2 against
`minecome_aimed_bridge_fixture`, an explicitly synthetic native host. Run
`e78ba82a6d23467eba714c1a82871983` passes with actual Minecraft and the native
process, followed by Java/wrapper/native exit0. It leaves the original standalone
fixture, default bridge and installed HUD profiles separate. See the
[network lab procedure](../minecraft/README.md#aimed-stone-network-lab).

It creates a fresh UUID Creative save, obtains matching client/server eye,
selected stone stack, seed air and solid UP support, then connects. Its outgoing
pose uses the actual gameplay eye rather than an interpolated render camera.
The immutable offer maps this eye to the synthetic host camera. After the exact
ACK it rechecks the baseline, performs one genuine vanilla bootstrap, and emits
the confirmed placement event. A permit-bound synthetic host ray then requests
breaking that stone through the same actual Minecraft raycast/action component.

Only client/server-confirmed air produces the removal event and terminal result1.
The native fixture must receive both before sending GOODBYE. The guest checks that
exact session, zero owned/pending stones and a final air observation on both threads,
restores its changed options and exits normally. Receipts identify the fresh save,
process, immutable offer, permit, network request, local action and separate block
events. The verified run confirms exactly one bootstrap and one network break;
wire request ID1 maps to component request ID2 because the local bootstrap used ID1.
Both peers agree on removal/result1, the guest records host GOODBYE for session1,
and final client/server reads show air with no owned stones. Source hashes stayed
unchanged during the run. This is transport validation with actual Minecraft,
not live KCD targeting or proof of network placement on every face.
