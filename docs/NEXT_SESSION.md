# Resume checkpoint — 30 October 2026

## User direction

Continue automated implementation and testing only. The user explicitly deferred
manual tests to a larger milestone. Do not request another F8/visual comparison
while continuing this phase. Preserve the verified physical corridor behavior;
no further delay tuning or repeated inventory/face checks are needed.

## Working capability

The physical 12×8m corridor combines Minecraft walking, HUD/inventory and aimed
stone placement in KCD2. Its cutoff cleanup repair passed the focused native check
and the user reported “worked fine”. Evidence:
`runtime/evidence/hud-walking-aimed-20261030-135944-4e85c9966916415fa1b48be044b86054/verification.json`
and its separate `manual-acceptance.json`. Earlier top/side/repeat evidence remains
valid; see PROGRESS.md rather than repeating it.

New: an automatic terrain-extension profile adds a third captured tile during
actual Minecraft walking, growing collision coverage from 12×8 to 16×8m. The origin
and all original collision cells stay unchanged. The server installs first; the
client waits for a fresh matching observation before its own publication. Movement
resumes to X>=9.5, then returns. Each thread cleans up its exact generation. Fresh
movement observations keep KCD's follower alive during admission waits.

All three tiles are pre-captured. This is one bounded additive admission, not yet
repeated streaming, tile eviction or integration with physical input/owned blocks.
The experiment uses scripted controls and a standalone HUD receiver; new physical
controls and visible KCD HUD composition are not claimed.

## Actual automatic evidence

- Minecraft/HUD on captured KCD terrain passed:
  `runtime/evidence/hud-stream-20261030-141708-0f1698cc05b742ae865fbef561b6abda/verification.json`.
  Both threads reached X=10.044m; 2/34/43 HUD frames covered handoff/crossing/return;
  all 190 imported cells remained air; zero corrections; normal Minecraft exit.
- Normal coupled KCD follower passed:
  `runtime/evidence/coupled-ground-extension-20261030-141952-bc914da302d44129b61d2202ebcb02a8/verification.json`.
  50 real-server frames / 50 native receipts; restoration and cleanup passed.
- Delayed handoff passed after fixing missing pause-time trace updates:
  `runtime/evidence/coupled-ground-extension-20261030-142552-c0239cd2416e439f9d2955f733ad642c/verification.json`.
  604.25ms wait with 5 advancing samples; 56 frames/receipts; X=10.030m;
  11/35/44 HUD frames across handoff/extended area/return. Normal Minecraft exit,
  exact KCD restoration and original FPS restoration passed.

Java data 235, aggregate ground/trace 2727, ownership 25 and final mode 254 checks
passed. PS capture 37, input 25, proof 51, extension 83 and existing corridor 103,
physical 161, corridor-walking 57 checks passed. Lua movement 104 and new capture 8
simulated-binding cases passed. `remapJar` succeeded. Logs:
`runtime/terrain-extension-*.log`. Do not rerun unchanged suites.

## Next implementation

Move the admission contract into the physical walking controller and keep the
owned-block ledger and imported-cell protection valid across the change. Batch
walking, HUD, blocks and inventory in automatic Minecraft fixtures before any
later combined native acceptance. Then extend acquisition to subsequent adjacent
tiles/directions, retaining the original origin and bounded residency. A single
pre-captured admission is not complete rolling-world support.

Useful code: `GroundExpansion`, `GroundCollision.replace`,
`HudGroundMovementFixture.extensionHandoff`, `GroundMovementSequence.acceptExpansion`,
`HudGroundMovementMode.EXTENSION[_COUPLED]`, and dedicated extension branches in
`MovementTraceSink`, `MovementTraceReceiver.ps1` and `movement_probe.lua`.

Automatic commands from repo root, after loading a fresh official tools world:

```powershell
& './scripts/Test-CoupledGroundExtension.ps1'
& './scripts/Test-CoupledGroundExtension.ps1' -DelayHandoff
```

These need no F8/physical input. Minecraft-only entry:
`Start-HudGroundExtensionLab.ps1`, optionally with an absolute authenticated
`-ExtensionFile`. Entry points select installed PowerShell 7 automatically. See
[movement lab](../kcd2/MOVEMENT-LAB.md#terrain-extension) for scope and bounds.

## State and constraints

No game/helper is left running; the assistant-owned KCD PID 47568 closed normally
after restoration. No native DLL/installed bundle changed. The physical bundle
remains `runtime/hud-compositor-walking-corridor-aimed-20261029/installed.json`, addon
SHA256 `c5353e4bc21fd512838160cd3196f23f17b0fd6d0dc412178037dd56426c0196`.
Inspect actual processes/arms before any later native run.

Physical corridor: 15s input + 1s settle, 18s host deadline, 200ms playback,
400ms lease, X[-3.5,7.5], Z[-3.5,3.5]. Scripted extension: X[-3.5,11.5],
20s trace / 22s native lifetime, 256 records / 256KiB, 2s handoff deadline.
No old profile was widened. Terrain is an approximate heightfield; arbitrary
host-terrain placement and jump landing remain unfinished. Generation 2 exhaustion
and third-session refusal still need native acceptance, deferred with manual tests.

Workspace: C:/Users/xephi/Documents/ChatGPT/New project/MineCome
Public repo: https://github.com/gabrielpery/minecraft-kcd2; branch codex/initial-import.
Official Steam tools 2429020/build 1.5.5 only; never load retail 1.5.6 saves.
JDK: C:/Program Files/Java/jdk-24; Gradle cache: minecraft/.gradle-user-home.
Routine edits/tests/launches/pushes authorized; follow AGENTS.md.
