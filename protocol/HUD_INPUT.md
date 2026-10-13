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
Before the host is armed, an old but structurally valid ready acknowledgement
makes the peer unavailable for activation; it does not close the waiting session.
Only a genuinely fresh client-tick acknowledgement restores readiness. Zero,
excessively future, regressed or malformed acknowledgement fields remain fatal.
Once armed, an old publication/event or acknowledgement releases all guest
controls and ends activation; it cannot resume on a new heartbeat. After closure,
the host may keep the closed mapping while the paired image stream remains alive.
When the image channel ends, its worker permits at most another 1,500 ms, capped
by the original lease, to observe a real final client acknowledgement. The
standalone fixture caps its final ACK wait at 1,500 ms after closing input.
Neither grace restores input ownership. Acknowledgements
come from the client tick, never fabricated by the worker. An idle ready tick
advances time but not sequence.

An F8 edge arms only an already visible,
freshly composed stream with a fresh ready guest and neutral tracked keys. The
native renderer requests next-frame blocking before accepting later UI keys.
Focus loss, ReShade overlay, stale peer, stream closure, reset or 30 seconds after
arming ends ownership and stops requesting blocking. The F8 opener itself can
reach KCD. The game must be in its fresh test world with menus/console closed;
generic KCD menu/cutscene ownership is not yet established.

The separate live mouse profile forwards these pointer records only to actual
vanilla inventory screens. Its pinned custom ReShade build adds a renewable
100 ms strict mouse lease; state, buffered and peek paths suppress mouse input
and drain on release. The public ReShade block call alone is insufficient.
Inventory screen transitions require the guest ACK and uploaded image to agree
before pointer ownership resumes. Two neutral captured frames prevent held
buttons from carrying into another screen. Live inventory interaction passed;
general host input exclusivity and final native drain completion remain separate
qualifications in `docs/PROGRESS.md`.

The explicit World profile adds **no new UI wire kinds**. With the inventory
closed, fresh right/left presses become place/break intents for the existing
authenticated stone protocol. A bounded native queue passes run-tagged records
to the controller through ReShade's worker log:

```text
[MineComeWorldInput] {"schema":1,"run":"<32 lowercase hex>","sequence":1,"utc_ms":<capture time>,"action":1}
```

The controller starts reading at the log's current end before arming, validates
the file identity and exact run/sequence, and declines expired or too-rapid
clicks. At most 16 presses can be emitted. It checks the captured KCD process
and foreground immediately before dispatch; ambiguous dispatches are never
retried. Each dispatched click is correlated with the Lua request ID, guest
result, client/server block confirmation and KCD engine acknowledgement.
An input ACK alone is never block confirmation.

World mode retains the strict mouse lease throughout the 30-second activation,
including the closed inventory: **KCD camera movement is intentionally frozen**.
The target remains the verified nearby cell; this is not crosshair targeting.
Gamepad input, normal mouse look, host physics and arbitrary block types remain
outside this bounded check. The frozen mouse-only profile remains available.
