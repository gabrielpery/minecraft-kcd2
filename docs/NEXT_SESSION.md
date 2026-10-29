# Resume checkpoint — 29 October 2026

## Current capability

The fixed 12×8m corridor is implemented in the physical walking/HUD controller,
selected with `-CorridorWalking -ExtendedWalking`. It preserves the initial
settled player anchor and both tile hashes, installs collision on both Minecraft
threads, and releases the exact owned surface. The combined walking/aimed profile
now also accepts the corridor through `-CorridorWalking -RepeatSession` and has
passed automatic real-Minecraft checks on flat and captured terrain. Its native combined check crossed the old edge and placed on top, then failed at
aim-cutoff cleanup. Full combined live acceptance remains incomplete.
Foreground walking, HUD controls and inventory suppression now have user
acceptance within this corridor profile. The live run did not reach the old
X=4 edge. The existing repeat/aimed DLL is now installed; no native DLL was rebuilt.

The previous scripted corridor two-game walk passed in bf48df8. Its 20s source /
22s host contract is unchanged. The new physical profile uses 15s input + 1s
settling, an 18s host deadline, 200ms playback, 400ms lease, 200 records / 256KiB.
Bounds are X[-3.5,7.5], Z[-3.5,3.5]; raw Y[57.9,67.5] intersects the settled-anchor
relative range [-6.1,+3.5]. No freshness, braking or readback limit was relaxed.

## Combined live follow-up: cutoff cleanup failure

The user confirmed walking and top placement, then the Minecraft HUD disappeared.
Run 44fdf3a60e624f0c921598176f9ccb04 reached client/server X=5.8844196m, crossing
the old edge. 124 frames were forwarded with 119 readbacks; KCD player and FPS
restoration passed. Bootstrap and top placement were confirmed; no breaks arrived.

The top click arrived 11.155s after first movement. The fixed 12s aim cutoff closed
logical authority at 12.029s with two stones and incomplete owned-world cleanup.
Camera lease expiry at 12.802s followed shutdown; it is secondary. The prompt
incorrectly allowed about 15s. Full combined acceptance remains failed.

Evidence: runtime/evidence/hud-walking-aimed-20261029-233406-8c36e85079df4280baed80031ea905d0/.
Next: automate late placement at cutoff, then finish bounded cleanup before final
closure. No more live tests tonight; user is going to bed.

### Exact next investigation

First accepted W: 1793316894760; top click: 1793316905915.
`walking-aim-closed.json` at 1793316906789 reports logical_closed=true,
owned_count=2, guest_world_cleanup_complete=false, support_cleanup_complete=false.
The controller rejects cleanup before follower finish. Camera lease expiry at
1793316907562 and later server-identity errors follow shutdown. Keep the original
failed result; manual-acceptance.json records the partial human result separately.

Automate the late-place/owned-block-at-cutoff case, then ensure bounded cleanup
finishes before final closure and follower finish. Preserve ownership, imported
terrain protection and authority limits; do not just raise timeouts. Only then
schedule one live check with correct limits. Do not chase camera latency here.

The earlier preparation 232854-8e80ddc5c57846b0b3f32073c2c7c32c expired before the
assistant sent its F8 prompt; no human test occurred. Its exact-hash expired arm
was archived there, and the game was restarted. Avoid repeating this by sending
the prompt immediately on READY, with its live remaining-time bound.

## Earlier passing foreground evidence

    runtime/evidence/hud-walking-20261029-230705-6f95a1b3caab42aca886a805b844e9d9/manual-acceptance.json

Adjacent verification.json passed run `2a2b53983db449b59979f21dd60637d5` with
157 native readbacks, 862 HUD frames and exact restoration. User: “it worked all
fine, still a bit choppy/delayed but it's okay. continue”. Walking/HUD controls
and inventory suppression worked. Both players reached X=3.5762478m, so this is
not a foreground crossing of the old X=4 boundary. The replay below crossed
4.82378m. Batch any further live crossing with the next integrated milestone.
KCD PID52208 was closed normally after the accepted session.

## Latest passing automatic evidence

Combined corridor walking/blocks/inventory:

    runtime/evidence/hud-physical-fixture-20261029-232349-6016bca217f14dd68cb1cbf8619287d2/verification.json
    runtime/evidence/hud-physical-fixture-20261029-232502-3f46a989741d4bde982e7b1e522341b6/verification.json

Flat: maximum X4.961m, return0.0083m, 160 protected cells, 15 block HUD frames.
Captured: maximum X4.823781m, return0.117886m, 10 crossing/15 block HUD frames,
144 protected cells. Six vanilla actions (bootstrap, top placement/break, EAST
placement/break, seed break), inventory suppression, movement afterward, cleanup,
source hashes and trace verification passed. These are standalone scripted
fixtures, not native input/composition acceptance. The old zero-yaw constructor
assumption was repaired; both constructors and mode selection use -90 for corridor,
zero for legacy. Do not repeat these unchanged automatic checks.

Earlier physical-only captured-terrain fixture and native replay:

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
& './scripts/Test-HudPhysicalMovementFixture.ps1' -ExtendedWalking -CorridorWalking -AimedBlocks
& './scripts/Test-CoupledGroundCorridor.ps1' -PhysicalController -LaunchTestWorld
```

The final command captures current KCD terrain, runs Minecraft's controller with scripted
keys/view, then replays the recorded server path through the extended KCD follower.
It validates capture/fixture/source/trace hashes, crossing, source draining and
restoration. Omit LaunchTestWorld to preserve an existing loaded world. Optional
KeepTestWorld retains an owned launch for debugging; default closes it normally.

A fresh world can take about two minutes and may need its window brought forward
through Computer Use. One attempt timed out before RUNNING; another had a setup
HTTP timeout after capture. Neither reached movement. An empty startup-log race
was fixed. Keep the owned world open when diagnosing setup, instead of repeatedly
restarting it. No F8 countdown is needed for these automated checks.

## Installed state and next live check

Installed repeat/aimed bundle:
`runtime/hud-compositor-walking-corridor-aimed-20261029/installed.json`, using the
existing pinned `c5353e4bc21fd512838160cd3196f23f17b0fd6d0dc412178037dd56426c0196` addon.
`Update-HudCompositor.ps1 -WalkingAimed -RepeatSession -FromPhysicalMovement`
completed against `runtime/hud-compositor-walking-corridor-20261029`: all six
owned files verified; only the addon changed. Receipt:
`runtime/evidence/hud-update-20261029-232323-f10b39f3ff864a2594295efb575eba1d/update.json`.
The expired plain physical arm was archived in the previous live evidence as
`retired-MineComeHudMovement.ini`, with exact hash/dead-PID/expiry checks. Original
installation receipts remain immutable. Transition tests34 and profile tests171 passed.

KCD PID35908 was left open after the failed combined check; Minecraft closed
normally. Reinspect processes tomorrow. Escape stopped Computer Use this turn.
Do not run another live test tonight. The command below is for AFTER the cleanup fix.
The prepared entry point is:

```powershell
& './scripts/Start-HudWalkingAimed.ps1' -CorridorWalking -RepeatSession -Scenario TopFaceInventory -BundleDirectory './runtime/hud-compositor-walking-corridor-aimed-20261029'
```

Check for newer controller/arm evidence and actual process state before resuming
or starting another session. A second repeat session must use its printed
`-PreviousArmReceipt` path; do not reuse a consumed generation implicitly.

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
