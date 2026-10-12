# Bounded UI stream v1

Original CPU shared-memory transport for genuine vanilla UI pixels. This is separate
from the gameplay socket protocol and from the completed static snapshot proof.
All Win32 mapping/mutex access happens on workers, never a game/render thread.

The producer creates a pagefile-backed mapping named
`Local\MineComeHud_<run>` and a mutex named `Local\MineComeHudLock_<run>`, where
`run` is exactly 32 lowercase hexadecimal ASCII characters. Existing named objects
are refused by the producer. The reader opens existing objects only. Both sides
acquire the mutex with a bounded wait (at most 5 ms); busy means skip, and an
abandoned mutex terminates the session. The producer writes a complete header and
frame while holding the mutex; the reader copies both while holding it, then
validates and processes its private copy. No cross-language atomic assumptions.

The mapping is exactly 8,294,656 bytes: a 256-byte header and at most
1920 * 1080 * 4 bytes. All integers are unsigned little-endian. Reserved bytes are
zero. Header offsets:

| Offset | Type | Value |
|---|---|---|
| 0 | 8 bytes | ASCII `MCHUDS01` |
| 8 | u32 | Schema 1 |
| 12 | u32 | Header length 256 |
| 16 | 32 bytes | ASCII run token |
| 48 | u32 | Producer PID |
| 52 | u32 | Target PID |
| 56 | u64 | Producer creation FILETIME |
| 64 | u64 | Target creation FILETIME |
| 72 | u64 | Immutable session expiry, Unix UTC milliseconds |
| 80 | u64 | Strictly increasing frame sequence, first frame 1 |
| 88 | u64 | Capture UTC milliseconds |
| 96 | u32 | Width, 1..1920 |
| 100 | u32 | Height, 1..1080 |
| 104 | u32 | Row pitch, width * 4 |
| 108 | u32 | Pixel bytes, width * height * 4 |
| 112 | u32 | Format 1: straight RGBA8, top-left |
| 116 | u32 | State: 0 waiting, 1 frame, 2 closed |
| 120 | u32 | Selected hotbar slot, 0..8 |
| 124 | u32 | Screen: 0 none, 1 vanilla inventory |
| 128..255 | bytes | Zero |
| 256.. | bytes | Frame payload; unused trailing capacity ignored |

State 0 repeats valid immutable identity and format 1, but sequence, capture time,
dimensions, pitch, payload length, selected slot and screen are all zero. State 2
repeats the last published header with only state changed to 2 (or the waiting
header if no frame was published); it requires no fresh timestamp or new sequence
and its payload is ignored. Identity and reserved-byte checks apply in every state.
Waiting after an accepted frame and any publication after closed are rejected.

Immutable identity comes from a controller-created fresh session and a producer
ready receipt. A renderer arm supplies run, producer/target PID and creation time,
and expiry. Initial remaining lifetime must be positive and at most 180 seconds;
the receiver also imposes that initial remaining lifetime on its monotonic clock.
It never accepts renewal or a second producer in one session. Dimensions become
fixed on the first frame. Every frame repeats exact immutable identity, and its
capture timestamp must be no later than receipt UTC + 250 ms and no older than
1000 ms. Zero/replayed/decreasing sequences cannot refresh freshness. Sequence may
skip because both sides keep only the newest frame.

A rendered frame expires 500 ms after its local receiver observation. Closed,
invalid, expired or exited producer immediately hides the layer. Source pixels
are converted to premultiplied RGBA once by the native worker. The renderer owns
persistent textures and three fenced upload slots; a busy GPU drops updates,
never waits for a free slot. The renderer separately checks freshness of the
frame actually uploaded, even if newer publications keep arriving.

The first continuous lab uses a new isolated Creative world, normal vanilla GUI
rendering and the existing three-PBO readback. It changes actual selected slots
and opens/closes the actual vanilla inventory on the client thread. This proves
continuous pixels, not physical inventory input or KCD menu suppression.
