# Resume checkpoint — 30 October 2026

## Current capability and next decision

The fixed 12×8m corridor combines Minecraft walking, HUD/inventory and aimed
stone placement in KCD2. Physical walking/HUD/inventory has user acceptance.
The 29 October combined run crossed the old edge and placed on top, but failed
at block cleanup. That bug now passes automatic real-Minecraft regression and
a focused live KCD2 check; the user reported **“worked fine”**. Do not repeat
cutoff acceptance, the full top/side/inventory sequence or latency tuning.

Latest run `c79b036835ea489a9183166bbb2b99ee` passed: one top placement, two-stone
automatic cleanup, 156 forwarded frames / 156 native readbacks, 144 protected
imported cells, player/FPS restoration and normal MC exit. The user confirmed
both blocks disappeared with the HUD visible and later walking worked. This
focused northward run did not recross the old east boundary or repeat inventory.
Evidence and separate user report:
`runtime/evidence/hud-walking-aimed-20261030-135944-4e85c9966916415fa1b48be044b86054/verification.json`
and `manual-acceptance.json` in the same directory.

The official tools world was left open (PID 48080); Minecraft has exited normally.
The successful arm receipt is in that evidence directory's `capture/stream-arming.json`.
A subsequent same-process session needs that receipt via `-PreviousArmReceipt`.
Inspect actual processes/arms first. No controller is running; no native DLL changed.
The installed repeat/aimed bundle remains:
`runtime/hud-compositor-walking-corridor-aimed-20261029/installed.json`
with addon SHA256 `c5353e4bc21fd512838160cd3196f23f17b0fd6d0dc412178037dd56426c0196`.
Reinspect actual processes and arm files before resuming.

## Current live follow-up

The shared TCP ownership check was repaired: the listener-only API returned the
correct unique loopback/PID row but inconsistent state 0/1, so the redundant
state==2 comparison rejected a working debug API. Listening now comes from the
documented listener-only table selection. All endpoint/process/hash/start-time
pins remain. Six real ephemeral listener tests passed; native preflight passed.
See `runtime/evidence/cutoff-startup-20261030-134317/diagnosis.json`.

The assistant-started run `b0ca8e2fffef45ba92f5a11cf6b6c868` expired without F8:
zero inputs, zero movement frames, normal MC exit, original FPS restored. Its
READY line reached the prompt check with only 6 seconds left, so it was not sent
to the user. Preserve the result in:
`runtime/evidence/hud-walking-aimed-20261030-135251-daff777e3805480e8b1ff19755b86db5/`.
That arm is archived. Prefer the command the user now has: local cyan READY cue
and direct F8 response, with no assistant countdown. The following user-started
run passed above; no repetition is required. Neither timeout nor startup refusal
changes the previous passing automated cutoff result.

## Repair and automatic evidence

Production `AimedStoneArena.cleanupOwned` freezes the exact confirmed-owned
set (at most 16), validates the prepared/imported region and identities on both
owning threads, removes only those stones on the server, then awaits matching
client/server AIR. The support requires a fresh observation after stone cleanup.
`HudAimedStoneBridge` emits final closure only after both cleanups. HUD/camera
publication continues; the 12s active / 3s drain, leases and native limits remain
unchanged. Cleanup is separate from gameplay breaks. Final Java/PowerShell proof
balances the owned ledger and binds the early closed snapshot to final evidence.

Actual captured-terrain late-cutoff fixture passed:
`runtime/evidence/hud-physical-fixture-20261030-132516-1e3cd9bdc0f14acdb02a255888f9887f/verification.json`

- Upper placement confirmed at 11.235s after first movement.
- Cutoff at 12.009s with two stones; clean closure at 12.143s.
- Two HUD frames during cleanup; 144 imported cells unchanged.
- Client/server maximum X=4.823781m; inventory suppression and 0.995m later walking passed.

Normal six-action captured-terrain regression also passed:
`runtime/evidence/hud-physical-fixture-20261030-132657-f8d29441c7dd49f7b8141d4a0579ad2d/verification.json`

Maximum X=5.082572m, 11 crossing/16 block HUD frames, 144 protected cells. Top and side
placement/breaking, inventory and subsequent walking passed. Both runs verified
source hashes, trace, cleanup and normal Minecraft exit. They use scripted input
and rays; they do not claim native composition/input acceptance.

Java compiled; focused checks passed: physical 454, aim gate 32, aimed proof 67.
PS fixture 253, relay/closure 238, controller 257, corridor entry 27. Do not rerun
unchanged tests. Logs: `runtime/cutoff-java-checks.log`,
`runtime/cutoff-actual-fixture.log`, `runtime/cutoff-normal-regression.log`.

Automatic entry point from repo root (PowerShell 7 selected automatically):

```powershell
& './scripts/Test-HudPhysicalMovementFixture.ps1' -ExtendedWalking -CorridorWalking -AimedBlocks -LateCutoff
```

Optional `-GroundPatchFile` takes an ABSOLUTE manifest path. The captured source
used above is `runtime/evidence/ground-corridor-20261029-230706-cf12bc71de6841fbb21ad1fe2b33b4ff/ground-corridor.json`.
Omit `-LateCutoff` for the ordinary six-action fixture. Legacy profiles remain unchanged.

## Completed live check — reproduction only

This check has passed; retain the command for a future relevant regression.
After a fresh official tools world is loaded, use:

```powershell
& './scripts/Start-HudWalkingAimed.ps1' -CorridorWalking -RepeatSession -Scenario CutoffCleanup -BundleDirectory './runtime/hud-compositor-walking-corridor-aimed-20261029'
```

Use the user-started entry and its local cyan READY cue; do not add a chat
countdown. F8 once, find the north-side seed, face it and take a small step toward it.
Release W, then place once on its TOP within ten seconds of first movement.
Leave both stones. They should disappear around 12s while HUD remains. Take a
short later step before 15s, then keep KCD2 focused until HUD closes at 30s.
No manual breaking/inventory repetition is needed. This scenario proves exact
two-stone automatic cleanup, rather than counting teardown as gameplay breaks.
A second same-process session needs its printed `-PreviousArmReceipt` path.

Preserve original failed evidence:
`runtime/evidence/hud-walking-aimed-20261029-233406-8c36e85079df4280baed80031ea905d0/`
Run 44fdf3a60e624f0c921598176f9ccb04: maximum X=5.8844196m; 124 forwarded/119 readbacks;
top click at 11.155s, premature closure at 12.029s with owned_count=2. Camera lease expiry
12.802s was secondary to shutdown. Player/FPS restoration passed. The user saw
walking and placement before HUD disappeared. Keep its failure unchanged.

## Next implementation

Move on to rolling terrain beyond the fixed two-tile corridor. Start with a bounded
adjacent-tile handoff that preserves the world origin, imported collision and
owned-block ledger. Reuse the captured-terrain Minecraft fixture and native replay
for automatic coverage before requesting another physical check. Keep the current
working corridor profile intact. Arbitrary KCD terrain placement and jump landing
remain separate unfinished features; do not divert into delay tuning.

## Bounds, installed state and unfinished work

Physical contract: 15s input + 1s settle, 18s host deadline, 200ms playback, 400ms
lease, 200 records/256KiB. Corridor X[-3.5,7.5], Z[-3.5,3.5]; raw Y[57.9,67.5]
intersects anchor-relative[-6.1,+3.5]. Two immutable 9×9 captures: 117 unique
samples/96 slabs. Fixed support (-1,floor(initialY)-1,-5); imported cells protected.

Installed update receipt:
`runtime/evidence/hud-update-20261029-232323-f10b39f3ff864a2594295efb575eba1d/update.json`.
Earlier physical live acceptance:
`runtime/evidence/hud-walking-20261029-230705-6f95a1b3caab42aca886a805b844e9d9/manual-acceptance.json`.
The earlier 8×8m combined/repeat results remain valid. Rolling terrain and
placement against arbitrary host terrain remain unfinished. Jump-camera landing
errors remain recorded failures; do not reopen that tuning loop. Generation 2
exhaustion/third-session refusal still needs native acceptance after 87217b9.

Workspace: C:/Users/xephi/Documents/ChatGPT/New project/MineCome
Public repo: https://github.com/gabrielpery/minecraft-kcd2; branch codex/initial-import.
Official Steam tools 2429020/build 1.5.5 only; never load retail 1.5.6 saves.
JDK: C:/Program Files/Java/jdk-24; Gradle cache: minecraft/.gradle-user-home.
PS7: C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe
Routine edits/tests/launches/pushes authorized. Follow AGENTS.md: integrated
progress, focused automation, minimal human tests; commands separate from questions.
