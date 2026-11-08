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
frame while holding the mutex; the reader copies and validates the private
256-byte header before copying its bounded payload under the same mutex. Pixel
validation and conversion happen after release. No cross-language atomic assumptions.

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

## Gameplay schema 3 and layered format 2

The explicit gameplay stream uses `MCHUDS03`, schema 3, and a matching schema 3
arm. It retains PID/start/run ownership, immutable expiry, sequence, terminal
state and freshness rules above. Its outer lease is at most 24 hours. This
version allocates exactly **24,883,456 bytes** (256 plus 1920×1080×12), including
when a gameplay producer selects flat format 1. Schema 1 keeps its original
8,294,656-byte mapping and never accepts format 2. A smaller gameplay mapping is
rejected before frame reads; producer and receiver must be deployed together.

Format at offset 112 is immutable from the first valid waiting or frame header.
Format 1 retains one straight RGBA8 plane and zero bytes 128..255. Format 2 is
accepted only in schema 3. Width/height describe the logical viewport, row pitch
is still width×4, and payload bytes must equal width×height×12. Three contiguous
top-left planes, each width×height×4 bytes, are published atomically:

1. Hands, HUD and screen overlay, straight RGBA8.
2. Minecraft world models/outlines, straight RGBA8.
3. World OpenGL depth, IEEE754 little-endian float32 in [0,1].

The first two planes are premultiplied independently by the native worker.
Depth bytes remain unchanged; NaN, infinity and values outside [0,1] terminate
the channel. Depth is never treated as color or alpha, including in the
standalone receiver's nontransparent-frame checks. Uploading the three planes
as an atlas does not change the viewport dimensions used for fitting or input.

Format 2 framed headers carry the camera that rendered those same planes:

| Offset | Type | Value |
|---|---|---|
| 128 | u64 | Camera sample Unix UTC milliseconds; 0 disables native depth comparison |
| 136 | float32×3 | Native KCD camera position |
| 148 | float32×3 | Native camera forward direction |
| 160 | float32×3 | Native camera up direction |
| 172 | float32 | Vertical field of view in radians |
| 176 | float32 | Guest projection near plane (currently 0.05) |
| 180 | float32 | Guest projection far plane (currently 512) |
| 184..255 | bytes | Zero |

Vectors and lens values must be finite. Forward/up must be unit length within
0.01 squared-length tolerance, and their dot product must be within 0.05 of
zero. Vertical FOV is strictly between 0.05 and π−0.05; near is positive and far
greater than near. A nonzero camera timestamp must be no later than capture+50ms
and no older than capture−1000ms. Timestamp 0 permits standalone fixtures. If
there is no fresh world view, it also permits the explicit overlay-only sentinel:
position, forward, up and FOV all zero, with finite positive near and far greater
than near; the world plane is transparent and depth is 1. A partial zero camera
or a timestamped zero camera is invalid. Timestamp 0 does not authorize native
depth comparison; the compositor must separately
validate current host projection/camera agreement before clipping world pixels.

Waiting and closed-before-first-frame format 2 headers keep bytes 128..255 zero.
Closure after a frame repeats its complete camera and lens fields, with only
state changed; its old capture timestamp still does not refresh the channel.
Changing format, dimensions or immutable identity cannot renew or reconnect it.

### Gameplay pose and camera snapshots

The sustained host worker exchanges bounded, atomically published JSON files
alongside the image stream. `gameplay-pose.json` keeps schema 1 and kind
`minecome_gameplay_pose_v1`: `run`, `world_id`, `target_pid`, string
`target_start_filetime`, `patch_run`, `patch_sha256`, `seq`, `utc_ms`, `source_ms`
and native-coordinate feet `position`. WorldBlocks additionally **requires**
numeric `perspective_request` 0/1/2 (first/back/front); legacy poses reject this
extra field. Identity, exact keys, finite bounds, monotonic sequence/source time
and the 250 ms freshness limit remain enforced. A duplicate or stale pose cannot
renew a camera request. F5 changes the request, not the acknowledged view.

WorldBlocks publishes `gameplay-aim.json` with schema 3 and kind
`minecome_gameplay_aim_v3`. It repeats the run/world/patch/target identity, `seq`
and original capture `utc_ms`, then carries:

| Fields | Meaning |
|---|---|
| `origin`, `direction` | Player-eye interaction ray, independent of camera displacement |
| `range`, `known`, `distance`, `terrain_hit` | Native obstruction result; range remains at most 4.5 |
| `camera_origin`, `camera_direction`, `camera_up`, `vertical_fov` | Actual native render camera and vertical FOV in radians |
| `perspective` | Native acknowledgement: 0 first person, 1 back, 2 front |

The guest admits rendering and interaction together from one fresh sample.
Block reach and native occlusion use the eye ray; world/Steve rendering and format 2
camera metadata use the render camera. Displacement therefore does not extend
reach. Exact keys/types, identity, sequence, unit/orthogonal basis and FOV are
validated. Camera-to-eye separation is at most 4 metres; perspective 0 also
requires matching origins within 0.1 metres and aligned directions. Aim schema 1
remains the legacy ray format; schema 2 is accepted as first-person view data,
but cannot acknowledge third person. These file schemas do not change the image
mapping layout or input ABI. Third-person selection also checks the segment from
the render camera to the eye-ray hit against owned blocks' actual outline shapes.
This rejects a hidden target without extending eye reach or treating slab/fence
gaps as full cubes. It does not yet move the orbit camera around Minecraft blocks.
Native acceptance and remaining limits are recorded in `docs/PROGRESS.md`.
