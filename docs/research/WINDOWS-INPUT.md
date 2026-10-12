# Scoped Windows input capture

The official tools game's timed Lua observer delivered jump presses but no watched
walking or mouse actions during actual player/view movement. The next source layer
therefore observes Windows input in a separate, original C++20 helper. It does not
use a game address map, replace KCD's input callback or suppress native input.
A separate opt-in Minecraft lab now consumes the format on its client thread.

## Public API route

[Microsoft's Raw Input overview](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input)
documents keyboard/mouse registration and relative device data. The helper registers
the keyboard and mouse top-level collections to its own message-only window using
`RIDEV_INPUTSINK | RIDEV_DEVNOTIFY`. It does not request `RIDEV_NOLEGACY`, install a
keyboard interceptor, inject keys or move a window. Registrations are process-local,
so the game's own registrations remain separate.
[RegisterRawInputDevices](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices)
defines that ownership and removal contract.

The wrapper first verifies the discovered official Steam tools executable's pinned
hash/version, PID/creation time and loopback listener owner. The helper pins an open
process handle, compares its exact creation FILETIME, and ends if that process exits.
Background packets are discarded before raw data is decoded. Foreground identity
is checked before and after
[GetRawInputData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getrawinputdata).
Only the six configured virtual keys (default W/A/S/D, Space and left Shift) plus
relative mouse deltas are retained. Device identities, other app metadata, typed text, mouse buttons and
wheel data do not enter the recording.

## Focus, release and arming

Capture begins disarmed. A fresh F8 press while the target is focused and controls
are released arms it; the first armed sample is neutral. Presses during that initial
handoff stay suppressed until release/repress. F8 repeat cannot rearm an old state.
Esc/backtick and unsupported nonmodifier keys, mouse buttons/wheel, ambiguous device
changes or malformed packets disarm capture. A focus change always disarms it.

The helper combines current-foreground checks with an out-of-context
[EVENT_SYSTEM_FOREGROUND observer](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwineventhook),
so a brief switch away and back cannot retain old armed state. Every foreground
event disarms; the callback does not log the other window's title or PID. The
observer is removed on its registering thread before helper exit.

Queued packets must belong after the latest focus/arming/neutral epoch and be
no more than100ms old. Equality at the coarse tick boundary is discarded. Prior-epoch
packets cannot extend that epoch; genuinely stale packets reset the baseline.
This prevents a high-frequency mouse queue from endlessly renewing suppression.
[GetMessageTime](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessagetime)
defines the message enqueue time used here.

Only the high bit of
[GetAsyncKeyState](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getasynckeystate)
seeds suppression for controls already held at focus gain. Its low bit is unreliable.
A zero result can also mean inaccessible desktop/UIPI conditions; this prototype
does not establish successful control capture in those conditions. F8 is a manual
capture latch, not proof of the game's menu, cutscene or gameplay state. It remains
visible to KCD because this helper does not intercept it.

## File and consumer contract

The helper creates a new, resolved file under workspace `runtime/evidence`, with
`CREATE_NEW`, a1MiB limit and fewer than2500 records. A64-message processing batch,
fixed50ms sample grid and independent absolute15–120s deadline prevent input floods
from extending the session. Output is flushed; partial/failed termination is not
reported as success. A final record is neutral. Only the owned helper is eligible
for wrapper recovery; KCD is never stopped.

Every NDJSON record contains exactly:

```text
schema:1, source_kind:"windows_raw_input_v1", kind:begin|sample|end,
run:lowercase32hex, seq:unsigned64, utc_ms:integer,
monotonic_ms:elapsed integer, target_pid:positive unsigned32,
target_start_filetime:canonical unsigned64 decimal string,
focused:boolean, armed:boolean,
held:{forward,back,left,right,jump,sprint}:booleans,
mouse_dx:integer[-32767,32767], mouse_dy:integer[-32767,32767]
```

End alone adds `reason:duration|target_exit|write_error|shutdown`. Begin requires
sequence1, elapsed0 and neutral/unfocused/disarmed state. Inactive records are
neutral; armed requires focused. Mouse counts are bounded relative data and consumed
once per snapshot, not calibrated camera angles. The source label is a format tag;
the controller's binary/source provenance supplies separate local evidence.

`ExternalInputDecoder` and `ExternalInputSessionGate` are pure Java components.
They check exact JSON fields/types, duplicate keys, bounded UTF-8/numbers, identity,
ordering and age. Any invalid/stale/replayed record closes the gate and clears
controls. A local monotonic lease accounts for the record's existing UTC age,
bounding emitted-record age to300ms; it is not an end-to-end physical-event latency
promise. Held state expires on timeout/menu/focus/end. Mouse deltas accumulate across
fresh unconsumed frames within bounds, are consumed once, and retain the earliest
pending delta's expiry. Restarting a session requires a new gate and a fresh neutral
armed sample.

`ExternalInputFileReader` performs all input-file IO on its own daemon, including
path validation, framing and close. It validates a new path inside resolved local
`runtime/evidence` before READY; the controller creates the writer only afterward.
It opens once, emits complete LF records through a128-entry copied mailbox, and
limits bytes, lines, records and per-tick drains. Partial EOF does not renew a lease
or terminate successfully. Truncation, replacement, malformed framing and overflow
clear queued input and close the consumer. Game-thread close only signals the daemon.

The installed Windows JDK returns null for BasicFileAttributes.fileKey. That path
uses a private UUID hard link in the same evidence directory as its identity witness,
opens through the witness, checks Files.isSameFile each poll, and removes the link
in daemon cleanup. Unsupported hard-link storage fails closed. This changes only
diagnostic-file link metadata. The trusted new producer, session nonce and controller
provenance remain necessary; neither the format tag nor file path authenticates a
hostile local process. The primary Java contracts are
[Files.createLink/isSameFile](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/file/Files.html)
and [BasicFileAttributes.fileKey](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/nio/file/attribute/BasicFileAttributes.html).

`ExternalInputLab` is mutually exclusive with the other development labs. It owns
a fresh UUID Adventure world and its client/server collision proxies. After stable
grounding, it consumes fresh records on START_CLIENT_TICK, sets vanilla held key
bindings, and calls the ordinary Entity.changeLookDirection path. The sensitivity
gain and invert setting follow the inspected cached1.21.1 Mouse bytecode; Entity
applies its own0.15 factor. Smooth camera, spyglass and toggle-sprint modes refuse.
Vanilla ticks alone perform walking, gravity, jumping and collision after the one
initial server teleport. Fresh server observations verify the result independently.
Menus, stale input/server samples, corrections, world changes and coverage exits
release controls and end the lab. Temporary pause-on-focus-loss state is restored.

## Verification and current limits

The current native state executable passes598 focused checks. The Java task
`externalInputTest` passes148 checks and the remapped Fabric JAR assembles. These
are standalone checks of state, framing and recovery, not physical-gameplay proof.

The actual15s OS lifecycle run against the pinned tools process produced301 records:
one begin,299 focused/disarmed samples, and one neutral duration end at15009ms.
It verified two own registrations, foreground-observer removal and device removal.
Java independently validated that exact historical file with recorded clocks.
All samples were neutral; physical walking/mouse delivery remains unverified.
That earlier run did not apply Minecraft controls. Evidence and hashes are in
[progress](../PROGRESS.md#windows-input-capture-layer--2026-10-12).

The first strict readback run rejected this Windows build's returned flags:
`GetRegisteredRawInputDevices` reported `0x100` although registration requested
`0x2100`. The final predicate permits only omission of `DEVNOTIFY`, retaining exact
two classes/own window and rejecting other flags. This is a measured local result,
not a documented universal normalization rule. `DEVNOTIFY` is still requested;
actual hot-unplug notification delivery has not been physically tested.

The new file-reader suite passes266 checks with zero skips, including real Windows
replacement/truncation, split UTF-8/LF framing, overflow, symlinks and identity-link
cleanup while a writer remains open without delete sharing. The existing148
decoder/gate checks and126 ground checks pass; JAR assembly
succeeds. A fresh scripted producer then drove an actual Minecraft client/server:
0.8571695m walking, jump/landing, yaw+4.5degrees, pitch-1.8degrees, one consumed mouse
delta and neutral terminal controls. There were zero post-settle corrections and
normal process exit. Both input and flat terrain were synthetic;90 input records
were delivered. See [progress](../PROGRESS.md#external-input-applied-to-real-minecraft--2026-10-12).

Next integration needs physical KCD input proof, explicit engine gameplay/menu
guards, binding configuration and KCD input/physics ownership before sustained control.
Existing Lua follower guards must remain active; physical KCD movement must not be
misrepresented as Minecraft-authoritative movement.

## Configurable bindings and initial view — 2026-10-12

The optional native `--bindings` argument and wrapper `-Bindings` parameter accept
six canonical keys in forward/back/left/right/jump/sprint order. The allowlist is
uppercase A–Z, UP/DOWN/LEFT/RIGHT, SPACE, LSHIFT/RSHIFT and LCTRL/RCTRL. Names must
be distinct; F8 stays reserved. Native capture validates independently, acknowledges
the selected mapping on stdout and uses it for both raw events and held-key
suppression. The wire retains semantic held fields. The observer does not read or
rewrite the game's effective binding configuration. Generic Shift uses the existing
MapVirtualKeyW scan-code translation; generic Ctrl is separated by its E0 prefix.
The focused native binding suite passes125 checks and the existing state suite598.
Physical remapped-key delivery has not been verified.

`Capture-InputViewSeed.ps1` loads a unique immutable copy of the original
`view_seed.lua` through the existing exact-tools gate. It requests one matching
player/camera receipt, records source/hash/process provenance and writes a new
session-bound view file. The probe only reads established GetWorldPos,
GetViewCameraDir and GetViewCameraUpDir APIs. It verifies stable raw player/id/API
references and copies vectors before subsequent reads. No input or physics state
is changed. Twenty-three Lua5.2 cases pass with simulated bindings; the new capture
path itself has not run in KCD.

`HostViewSeed` strictly checks bounded UTF-8/JSON, duplicate/exact fields, session
and process identity, ground SHA256, source kind, age≤60seconds (also rechecked at
the initial teleport), player distance≤0.1m from the patch center and camera basis.
Forward/up lengths must be within0.99–1.01, orthogonal within0.01, within1degree of
zero roll, with horizontal forward magnitude≥0.01. The existing axis mapping gives
MC forward=(KCD.x,KCD.z,−KCD.y), yaw=atan2(−KCD.x,−KCD.y), and
pitch=−atan2(KCD.z,hypot(KCD.x,KCD.y)), in degrees. Seventy-five Java checks pass.

Only the existing initial server teleport uses these angles. READY requires both
client/server angles within0.1degree for two stable seconds. The controller requires
matching view hash, source kind and both view verification flags on the run's READY
and PASS markers. Fourteen adversarial marker cases pass; the final guard also
accepts the exact latest historical live receipts offline. Sixteen PowerShell
binding cases pass. A real Minecraft fixture initialized yaw45/pitch−10, walked
1.0727511m, jumped/landed and ended at49.5/−11.8 with neutral controls and no
post-settle corrections. The custom binding argument in that fixture was configuration
only; scripted semantic input does not prove native arrow/Ctrl capture.

This is initial snapshot alignment. The user can move KCD's view afterward and its
mouse gain can differ from Minecraft's. Ongoing view ownership, engine menu state,
physical controls and native KCD physics remain separate integration work.
