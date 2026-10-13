# MineCome wire protocol 1.0 and optional 1.1 stone input

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
| 6 | 2 | minor version 0 by default, or negotiated stone-input minor 1 |
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
| 1 | HELLO | role u32, capabilities u32=0, name byte length u16, credential byte length u16, UTF-8 name, UTF-8 credential |
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
capability1 and a real Minecraft role. No state is exchanged before authentication.
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

## Proposed aimed stone arena (not a negotiated or implemented wire extension)

The implemented minor 1 fixed-cell request remains unchanged. `AimGeometry`
(Java) and `aim_geometry.hpp` (C++) contain pure alignment and reference-ray
math only. Their shared fixture `tests/fixtures/aim_geometry.txt` checks 22
identical map, orientation and hit/miss vectors. Passing these tests does not
demonstrate crosshair targeting, KCD camera calibration, engine ray capture or
new gameplay. Actual Minecraft target selection must use its world raycast,
not the reference cube picker.

The next coherent feature is a bounded, visible **stone cluster**. A bootstrap
stone is placed through the existing real vanilla action path and mirrored by
the acknowledged KCD sink. Thereafter a fresh camera ray selects any owned
stone: left click breaks it, and right click places adjacent to the returned
face. Proposed limits are 16 owned cells, a 4.5 KCD-unit ray, and Minecraft's
actual interaction-reach checks. An empty cluster has no invented support.
The ordinary superflat floor is not rendered in KCD and must not be an aimed
placement surface. The earlier captured 5×5 terrain patch is injected only
into `BlockCollisionSpliterator`; it provides neither Minecraft block state,
OUTLINE raycast shapes nor vanilla block-item support. Host terrain placement
requires a separate, explicit support representation and is not part of this
cluster feature.

Proposed negotiation and ordering for minor 2:

1. Add an explicit aimed-stone capability and new message schemas; retain the
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
3. Capture the camera origin/forward and nearest physical host obstruction in
   the same Lua aim-intent call, tied to the original click/request and arena
   ID. The proposed request carries that immutable ray and bounded obstruction
   distance/availability, or references an already acknowledged exact sample
   ID. Do not combine an action with an unrelated latest 5 Hz pose. Bound
   capture-to-dispatch age, reject duplicate IDs, and never retry ambiguous
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

Inspected implementation seams are `StoneConsumer::update` in
`kcd2/src/tools_http_host.cpp` (currently anchors on the first event),
`StoneAlignment::create/map` in `kcd2/src/stone_mirror.cpp`,
`HudStoneBridge.initializeCell/dispatch/readServer` (currently one cell and
hard-coded UP face), and the action-only protocol/mailboxes. Minecraft 1.21.1
named bytecode confirms `Entity.raycast` uses `RaycastContext.ShapeType.OUTLINE`
and `World.raycast`; the same cached classes expose `interactBlock` and
`attackBlock`. Existing `kcd2/probes/ground_probe.lua` documents the inspected
official `Physics.RayWorldIntersection(origin, direction*range, maxHits, mask,
skipPlayerId, nil, privateHits)` call and checked `pos/normal/dist` fields.
An aimed occlusion probe must use the actually exported `ent_all` mask to
include host obstacles; the terrain-only sampler cannot establish wall
occlusion. Mirrored stones currently have `physics=false`, so the host ray
does not replace Minecraft selection of those stones.

Live work still needed before this feature can be claimed: shared-alignment
handshake, exact sample/intent pairing, client/server selection agreement,
host occlusion, and visual checks of centre-ray alignment on several block
faces while turning/stepping. Existing orientation algebra tests and stone
model bounds do not prove those camera timing, eye/feet or gameplay outcomes.

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

This establishes a host sample contract, not click/sample pairing or shared
alignment. A future aimed request must capture this data with that click; it
cannot reuse the most recent diagnostic sample. Alignment must be agreed before
bootstrap, using the actual guest camera and sampled host camera for the first
turn-only lab. Inverting the existing four-unit display offset would place the
ray origin away from the actual Minecraft player and invalidate reach assumptions.

### Standalone Minecraft aimed arena (no wire change)

`AimedStoneArena` implements the guest selection/action portion independently of
the existing fixed-cell bridge. It pins one immutable alignment and a fresh
Creative world, allows at most 16 confirmed owned stones within a 5×5×5 cell
volume, and requires a host ray no longer than 4.5 units and no older than 500 ms.
The mapped origin must agree with the actual Minecraft player's eye within
0.15 blocks on both the client and integrated server. Host obstruction is
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
An aimed wire capability, shared alignment acknowledgement, paired live host
click/sample and KCD replica integration still need implementation.
