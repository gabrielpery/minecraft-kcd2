# Resume checkpoint — 27 October 2026

Physical walking and Minecraft's real HUD now pass together in KCD2, including
normal restoration and cleanup. The user says **"still delay, but smooth"**.
The warmup, native finish and fixed sampling comparison is complete; do not
repeat it merely to resume. Continue with remaining latency measurement/tuning
or longer walking and integration with the already working aimed-block controls.

## Repository and implementation

- Workspace: `C:\Users\xephi\Documents\ChatGPT\New project\MineCome`.
- Public default branch: `codex/initial-import`,
  `https://github.com/gabrielpery/minecraft-kcd2`.
- Live-validated implementation: `d150024667683ce6366f4800528528d8b9ab9f0b`
  (fixed 100 ms physical sampling schedule), on
  `c90da08973da9db54ad2c7a1c94d2def1b34cec0` (parser warmup/native finish).
  Inspect current Git status/log rather than resetting to those commits.
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

KCD PID **50636 remains open**; Minecraft is closed. Its `38d11...` HUD arm is
consumed. The previous `2dd6...` arm is already archived; do not archive it again.
Recheck actual processes, arm receipts and Computer Use availability on resumption.
Earlier Escape presses stopped Computer Use; do not assume that persists forever
or that observing the screen causes game failures.

When a new test is needed, close KCD normally first, then archive the exact latest
expired arm and launch a fresh official tools world:

```powershell
$mineComeRoot = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$mineComeRoot/scripts/Archive-HudArm.ps1" -ReceiptPath "$mineComeRoot/runtime/evidence/hud-walking-20261027-181108-38d11f6a4fb943348636cef27b855de9/capture/stream-arming.json"
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
