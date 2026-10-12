# Scoped Windows input capture

The official tools game's timed Lua observer delivered jump presses but no watched
walking or mouse actions during actual player/view movement. The next source layer
therefore observes Windows input in a separate, original C++20 helper. It does not
use a game address map, replace KCD's input callback, suppress native input or apply
any Minecraft controls yet.

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
Only literal virtual-key W/A/S/D, Space and left Shift plus relative mouse deltas
are retained. Device identities, other app metadata, typed text, mouse buttons and
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
armed sample. No Minecraft game-thread application is registered yet.

## Verification and current limits

The current native state executable passes598 focused checks. The Java task
`externalInputTest` passes148 checks and the remapped Fabric JAR assembles. These
are standalone checks of state, framing and recovery, not physical-gameplay proof.

The actual15s OS lifecycle run against the pinned tools process produced301 records:
one begin,299 focused/disarmed samples, and one neutral duration end at15009ms.
It verified two own registrations, foreground-observer removal and device removal.
Java independently validated that exact historical file with recorded clocks.
All samples were neutral; physical walking/mouse delivery and Minecraft application
remain unverified. Evidence and hashes are in
[progress](../PROGRESS.md#windows-input-capture-layer--2026-10-12).

The first strict readback run rejected this Windows build's returned flags:
`GetRegisteredRawInputDevices` reported `0x100` although registration requested
`0x2100`. The final predicate permits only omission of `DEVNOTIFY`, retaining exact
two classes/own window and rejecting other flags. This is a measured local result,
not a documented universal normalization rule. `DEVNOTIFY` is still requested;
actual hot-unplug notification delivery has not been physically tested.

Next integration needs a complete-line file reader and game-thread handoff in an
owned Minecraft lab, explicit engine gameplay/menu guards, binding/sensitivity
configuration and KCD input/physics ownership before sustained coupled control.
Existing Lua follower guards must remain active; physical KCD movement must not be
misrepresented as Minecraft-authoritative movement.
