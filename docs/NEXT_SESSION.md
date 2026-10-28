# Resume checkpoint — 28 October 2026

Physical walking and Minecraft's real HUD now pass together in KCD2, including
normal restoration and cleanup. The user says **"still delay, but smooth"**.
The warmup, native finish and fixed sampling comparison is complete; do not
repeat it merely to resume. A new input-phase repair is compiled and verified
in standalone Minecraft; its KCD2 comparison remains pending. The user's latest
instruction is **automated work only**; do not start a human F8 countdown without
renewed availability.

## New work after the live baseline

- `HudStreamLab` now consumes physical movement and UI events at START_CLIENT_TICK,
  before `HudPhysicalMovement.beforeTick` writes vanilla KeyBindings. Previously
  END_CLIENT_TICK consumption required an additional tick before application.
  Preserve whole-queue UI event ordering, freshness, ownership and cleanup gates.
  Other input profiles retain their original END path.
- The labelled physical fixture uses the same START phase. Setup, authoritative
  post-tick observations and final output remain at END.
- `HudMovementTiming` records original input capture UTC, JVM receipt time,
  accepted-down decisions and actual KeyBinding snapshots in final evidence at
  `physical_movement.input_timing`. `after_input_sequence` refers only to movement
  edges; batched down/up can cancel before polling. This is not native/display
  latency proof. Each series retains its first 32 entries with full counts and
  explicit truncation, leaving space in the unchanged 64 KiB stream receipt.
- Java24 `compileJava`, `assemble` and `hudPhysicalMovementTest` pass **299 checks**, including
  rejected/batched input, signed clocks, immutable exports and worst-width nested
  receipt-size coverage. The final 32-entry cap was tightened after the fixture;
  that fixture retained only 8 events/12 states, below the new cap.
- Actual Minecraft fixture `cf2fbd1c64b347d8951a27545f9e146b` passes:
  `runtime/evidence/hud-physical-fixture-20261028-121745-cf2fbd1c64b347d8951a27545f9e146b/`.
  Three W/W/S pulses, zero client/server inventory movement, 106 real HUD frames,
  58 trace records, 1.498988 m maximum walk on both sides, zero corrections,
  normal exit and all controls/proxies released. Scripted receive-to-KeyBinding
  delays are 8.9611/0.2784/0.2117 ms. This does not measure physical key capture,
  native mapping/focus, KCD motion or display latency.
- No compositor/Lua/controller buffer change or new installation is needed.
  Keep 200 ms; the next live comparison should isolate this earlier input phase.

## Repository and implementation

- Workspace: `C:\Users\xephi\Documents\ChatGPT\New project\MineCome`.
- Public default branch: `codex/initial-import`,
  `https://github.com/gabrielpery/minecraft-kcd2`.
- Live-validated implementation: `d150024667683ce6366f4800528528d8b9ab9f0b`
  (fixed 100 ms physical sampling schedule), on
  `c90da08973da9db54ad2c7a1c94d2def1b34cec0` (parser warmup/native finish).
  New START-phase changes follow those commits; inspect current Git status/log
  rather than resetting to the older live baseline.
- No new native installation, renderer rebuild, PowerShell setup or administrator
  session is needed. The installed walking bundle remains unchanged.
- Detailed history, prior failures and component checks are in [PROGRESS.md](PROGRESS.md).

## Latest passed physical evidence

HUD `650a8e00939c4831981f75828b79ff62`, probe
`38d11f6a4fb943348636cef27b855de9`:
`runtime/evidence/hud-walking-20261027-181108-38d11f6a4fb943348636cef27b855de9/`.

- Controller exits 0: **56/56** forwarded sources and delayed readbacks pass.
- Native `explicit_end` restores the exact origin with zero error, cancels timers,
  and completes in 5,830.59 ms with 137 writes including restoration.
- All 588 camera publications are fresh; camera resources, FPS and Minecraft
  clean up normally. Client/server maximum walk is 0.594376 m, with zero corrections.
- Eighty retained native readbacks each advance one frame: median 16.113 ms,
  maximum 16.960 ms, zero position errors and no intermediate source holds.
- This run did not open inventory. Earlier inventory and aimed-block results
  remain separate; unrestricted or continuous movement is not established.
- `verification.json` is the primary PASS; `latency-analysis.json` preserves
  derived metrics, source hashes, calibration rows and comparison limitations.

## Remaining delay and limits

First capture-to-dispatch is directly measured at 50 ms (later median 20 ms).
First sample validation/preparation/HTTP take 4.94/10.23/18.65 ms; diagnostic
warmup takes 744.63 ms before arming. Conditional clock alignment estimates first
capture-to-native acceptance at 68.4 ms and first actual write at 279.3 ms, versus
123.8/333.9 ms previously. These are separate runs with cached-frame uncertainty,
not physical keypress/display measurements or proof of a single change's effect.
Source capture is median 100.38 ms/max 133.98 ms; server-source gaps reach 151.43 ms.

Keep the intentional **200 ms buffer**. This run needs 97.812 ms for right-point
availability, but earlier replay `477...` needs 188.903 ms; 150 ms would underrun
that earlier trace. Do not lower it based only on the latest trial. Per-key
capture/application and display timestamps are absent, so measure those stages
before claiming input-to-photon latency or attributing improvement solely to
warmup/cadence. HTTP success alone is not native application proof.

The lab retains five seconds of input plus one second of settling inside the
30-second HUD session, sampled-ground coverage, a 2 m host sphere and the existing
freshness/write/trace bounds. Native Lua seals and finishes after its final
observed point; controller ACK polling no longer delays restoration. Preserve
these protections while planning longer walking or aimed-block integration.

## Current process state and any later test

Both games are closed as checked on 28 October. The `38d11...` HUD arm was
archived with its exact ownership receipt in this round; `capture/arm-archive.json`
and `capture/MineComeHudMovement.expired.ini` preserve it. The previous `2dd6...`
arm is also already archived; do not archive either again.
Recheck actual processes, arm receipts and Computer Use availability on resumption.
Earlier Escape presses stopped Computer Use; do not assume that persists forever
or that observing the screen causes game failures.

When the user is available for a new test, launch a fresh official tools world
from the current closed state:

```powershell
$mineComeRoot = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$mineComeRoot/scripts/Start-Kcd2ToolsTest.ps1"
```

Let the fresh world load. Do not load retail 1.5.6 saves into the 1.5.5 development
build. For a later walking trial, these exact commands use the installed PS7:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudWalking.ps1' -PreflightOnly
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudWalking.ps1'
```

Wait for `HUD_WALKING_READY` before prompting F8. Use the actual reported activation
window and a brief sequence suited to the new change; do not spend that window on
unrelated work. The return near six seconds and normal Minecraft shutdown are
intentional. Check source crossings, `explicit_end`, actor/FPS restoration and
camera/Minecraft cleanup separately from the user's responsiveness report.

Routine development, launches, tests and Git pushes are already authorized.
Keep commands formatted in chat before any question widget. Do not repeat
unchanged suites, reinstall working components or erase failed historical evidence.
