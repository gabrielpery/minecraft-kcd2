# Bounded HUD input v1

Separate reverse transport for the isolated vanilla UI lab. The proven image
stream remains unchanged. The exact host (or explicitly labelled standalone
fixture process) creates `Local\MineComeHudInput_<run>` and
`Local\MineComeHudInputLock_<run>`, refusing existing objects. The Minecraft
worker opens them and checks both process handles and creation FILETIMEs.
Mapping and mutex operations occur only on workers, with at most 5 ms mutex
waits. Abandonment, overflow, malformed input or identity changes end the session.

The mapping is exactly 2,816 bytes: a 256-byte header and a ring of 64 records,
40 bytes each. All integers are little-endian. Reserved fields must be zero.
The identity matches the paired image stream: producer means Minecraft, target
means host. A fixture must use its own actual process as the target.

| Offset | Type | Meaning |
|---|---|---|
| 0 | 8 bytes | ASCII `MCHUDI01` |
| 8 | u32 | Version 1 |
| 12 | u32 | Mapping bytes 2816 |
| 16 | 32 bytes | Run, lowercase hex |
| 48 | u32 | Minecraft producer PID |
| 52 | u32 | Host target PID |
| 56 | u64 | Minecraft creation FILETIME |
| 64 | u64 | Host creation FILETIME |
| 72 | u64 | Immutable expiry UTC milliseconds, same image lease |
| 80 | u64 | Last event sequence, starts at 0 |
| 88 | u64 | Host worker publication UTC milliseconds |
| 96 | u32 | Host state: 0 waiting, 1 armed, 2 closed |
| 100 | u32 | Retained records, min(last sequence,64) |
| 104..127 | bytes | Zero |
| 128 | u64 | Last event consumed by Minecraft client tick |
| 136 | u64 | Last Minecraft client-tick acknowledgement UTC milliseconds |
| 144 | u32 | Guest state: 0 waiting, 1 ready, 2 closed |
| 148 | u32 | Guest screen: 0 none, 1 actual vanilla inventory |
| 152 | u32 | Guest selected hotbar slot, 0..8 |
| 156..255 | bytes | Zero |

The host owns bytes 0..127 and all event records. The guest owns bytes 128..255.
Each writer preserves the other side's bytes under the shared mutex. A waiting
guest uses a zero acknowledgement area; ready/closed acknowledgements carry a
client-tick timestamp and sequence no later than the host's last event. Host
states only advance waiting -> armed -> closed (waiting -> closed also allowed).
Closed is terminal. One activation per process/session; no renewal or re-arm.

Record sequence N lives at `256 + ((N-1) % 64) * 40`:

| Record offset | Type | Meaning |
|---|---|---|
| 0 | u64 | Sequence, starts at 1 and increases exactly once per event |
| 8 | u64 | Capture UTC milliseconds |
| 16 | u32 | Kind: 1 key down, 2 key up, 3 pointer move, 4 button down, 5 button up, 6 wheel |
| 20 | u32 | Key: Windows VK 0x31..0x39, E=0x45, Escape=0x1b; button: 0 left, 1 right; otherwise 0 |
| 24 | f32 | Pointer x in normalized source canvas coordinates [0,1] |
| 28 | f32 | Pointer y in normalized source canvas coordinates [0,1] |
| 32 | i32 | Wheel notches -16..16, nonzero for wheel; otherwise 0 |
| 36 | u32 | Zero |

Coordinates must always be finite/in range. Key events use x=y=0. Mouse events
use the same inverse aspect-fit mapping as image composition; outside-canvas
clicks are rejected. Wheel has code=0; pointer move has code=value=0. Event
timestamps must be within 250 ms of receive time (up to 100 ms in the future).
No reader may skip missing sequences. A ring about to overwrite an event not yet
acknowledged closes instead. Repeated polls do not replay events. Duplicate downs,
unmatched ups and invalid key/button codes are rejected by the client input gate.

Both peers enforce the original image expiry and its initial monotonic remaining
lifetime (at most 180 seconds), plus exact process identities. Host heartbeat,
guest acknowledgement and client application have a 250 ms freshness limit.
An old publication/event releases all guest controls and ends activation; it
cannot resume on a new heartbeat. Acknowledgements come from the client tick,
never fabricated by the worker. An idle ready tick advances time but not sequence.

The live first slice is keyboard-only. An F8 edge arms only an already visible,
freshly composed stream with a fresh ready guest and neutral tracked keys. The
native renderer requests next-frame blocking before accepting later UI keys.
Focus loss, ReShade overlay, stale peer, stream closure, reset or 30 seconds after
arming ends ownership and stops requesting blocking. The F8 opener itself can
reach KCD. The game must be in its fresh test world with menus/console closed;
generic KCD menu/cutscene ownership is not yet established.

Mouse records exist for the standalone actual-Minecraft fixture. Live mouse
forwarding is disabled until KCD camera/input exclusivity and cursor visibility
are verified. ReShade6.8 DirectInput8 GetDeviceState preserves mouse axes while
blocking buttons; its public block call alone does not prove camera suppression.
Gamepad input and host physics are outside this bounded keyboard lab.
