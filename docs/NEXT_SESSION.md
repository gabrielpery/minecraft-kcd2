# Resume checkpoint — 29 October 2026

## Current capability

The fixed 12×8m corridor is implemented in the physical walking/HUD controller,
selected with `-CorridorWalking -ExtendedWalking`. It preserves the initial
settled player anchor and both tile hashes, installs collision on both Minecraft
threads, and releases the exact owned surface. This separate walking/inventory
profile excludes aimed blocks. The verified combined profile still uses 8×8m.
Foreground physical input/native HUD composition across the corridor remains
unverified. No native DLL was rebuilt or installed this round.

The previous scripted corridor two-game walk passed in bf48df8. Its 20s source /
22s host contract is unchanged. The new physical profile uses 15s input + 1s
settling, an 18s host deadline, 200ms playback, 400ms lease, 200 records / 256KiB.
Bounds are X[-3.5,7.5], Z[-3.5,3.5]; raw Y[57.9,67.5] intersects the settled-anchor
relative range [-6.1,+3.5]. No freshness, braking or readback limit was relaxed.

## Latest passing automatic evidence

Captured-terrain Minecraft fixture:

    runtime/evidence/hud-physical-fixture-20261029-223141-d8dfe1edd3724a999ecf91083f4fc6f2/verification.json

Both players reached X=4.824, fully crossing the old X=4 edge, and returned within
0.118m. Five W/S pulses, inventory suppression before/after walking, 253 real HUD
frames (10 crossing frames), 158 trace records, source hashes and cleanup passed.

Native replay of those actual server observations:

    runtime/evidence/buffered-movement-replay-20261029-223230-fbfc11b45b9843a9b2fc467ba2ae2275/verification.json

156 forwarded / 156 native readbacks passed. Actual KCD displacement reached
4.824m; maximum actor error was 0.000031m. Every buffered source point drained,
exact starting-position restoration and the original FPS restoration passed.
This was recorded controller replay, not simultaneous physical input or native
HUD composition. KCD PID54112 was closed normally afterward; both games closed.
Complete log: runtime/physical-corridor-coupled-running.log.

Earlier captured fixture 97e91b7da1ee45f3adf16f10bf511513 failed its original X=5.5
turnaround: conservative airborne-coast braking released W during a small slab
descent, stopping at X=5.083. Fresh server samples and 27 crossing frames ruled out
a crash or CPU delay. The fixture now turns at X=4.5, placing the whole 0.6m player
footprint outside the old edge. Production limits stayed unchanged. Preserve the
failed evidence. Flat fixture44e56ce3c6f84bab81888968bdaf0ab4 passed before this fix.

Focused checks: Java terrain/trace2290, mode183, physical418; Lua99; PS corridor57,
buffered114, physical161, wide68, scripted corridor103, fixture227, replay24 and
update profile171. Do not rerun unchanged suites.

## Automatic entry points

From repository root (wrappers select PowerShell7 automatically):

```powershell
& './scripts/Test-HudPhysicalMovementFixture.ps1' -ExtendedWalking -CorridorWalking
& './scripts/Test-CoupledGroundCorridor.ps1' -PhysicalController -LaunchTestWorld
```

The second captures current KCD terrain, runs Minecraft's controller with scripted
keys/view, then replays the recorded server path through the extended KCD follower.
It validates capture/fixture/source/trace hashes, crossing, source draining and
restoration. Omit LaunchTestWorld to preserve an existing loaded world. Optional
KeepTestWorld retains an owned launch for debugging; default closes it normally.

A fresh world can take about two minutes and may need its window brought forward
through Computer Use. One attempt timed out before RUNNING; another had a setup
HTTP timeout after capture. Neither reached movement. An empty startup-log race
was fixed. Keep the owned world open when diagnosing setup, instead of repeatedly
restarting it. No F8 countdown is needed for these automated checks.

## Next foreground check

Fresh bundle staged; exact six-file update preflight passed:
`runtime/hud-compositor-walking-corridor-20261029` (not installed).
Installed repeat/aimed addon remains
`c5353e4bc21fd512838160cd3196f23f17b0fd6d0dc412178037dd56426c0196`.
The staged physical addon is the existing pinned
`869fc9a8c3d56cb2db16974184ccfffee7548d1f97366a7e3074f75d5520e657`.
With KCD closed, the prepared explicit transition is:

```powershell
$r = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$r/scripts/Disable-HudCompositor.ps1" -WalkingAimed -RepeatSession -BundleDirectory "$r/runtime/hud-compositor-walking-repeat"
& "$r/scripts/Update-HudCompositor.ps1" -PhysicalMovement -FromWalkingAimedRepeat -PreviousBundleDirectory "$r/runtime/hud-compositor-walking-repeat" -BundleDirectory "$r/runtime/hud-compositor-walking-corridor-20261029"
& "$r/scripts/Start-Kcd2ToolsTest.ps1"
```

Once loaded:

```powershell
& "$r/scripts/Start-HudWalkingLab.ps1" -ExtendedWalking -CorridorWalking -BundleDirectory "$r/runtime/hud-compositor-walking-corridor-20261029"
```

Batch one foreground check: cross the old edge, release/return, inventory W
suppression, walking afterward with the HUD visible. No aimed blocks in this
profile. The updater validates the exact old repeat profile only with the explicit
FromWalkingAimedRepeat flag; the default r4-to-physical transition is unchanged.
Old installation receipts remain immutable. Do not claim replay as this acceptance.

## Retained unfinished work

Rolling terrain and arbitrary placement against KCD terrain remain unfinished.
The corridor is one immutable map. Earlier jump-camera landing errors0.295/0.363m
remain failures; the 1ms cadence trial did not fix them and was reverted. Do not
reopen that tuning loop. Repeat gameplay worked twice, but final generation2
exhaustion and third-session refusal remain unverified after repair87217b9.

Workspace: C:/Users/xephi/Documents/ChatGPT/New project/MineCome
Public repo: https://github.com/gabrielpery/minecraft-kcd2; branch codex/initial-import.
Official Steam tools2429020/build1.5.5 only; never load retail1.5.6 saves.
JDK: C:/Program Files/Java/jdk-24; Gradle cache: minecraft/.gradle-user-home.
PS7: C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe
Routine changes/tests/launches/pushes are authorized. Follow AGENTS.md: integrated
progress, focused automation, minimal manual requests; format commands separately
from questions. Inspect Git status/log and process state before resuming.
