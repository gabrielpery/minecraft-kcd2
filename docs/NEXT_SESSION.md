# Resume checkpoint — 29 October 2026

## Current capability

Expanded terrain now drives real KCD player/camera walking automatically. Two
captured tiles form one 12×8m surface under a fixed origin; Minecraft walks beyond
the original X=4 edge and back, KCD follows actual server observations, then both
sides release their resources and KCD returns to its saved origin.

The passing walking route uses scripted Minecraft keys and a standalone HUD
receiver. Physical input and native HUD composition still use the previous 8×8m
profile. Do not present corridor walking as already integrated into that profile.
The previous 8×8m controls/blocks/inventory worked twice in one KCD process.

## Latest evidence

Walking controller 3c51920138ab4cebab27a93304458ed8 passed:

    runtime/evidence/coupled-movement-20261029-215241-3c51920138ab4cebab27a93304458ed8/verification.json

36 forwarded frames, 35 delayed native movement readbacks, maximum actual KCD X
displacement 6.076m from the capture origin, return across the original edge and
exact saved-origin restoration. Maximum camera error 0.058m versus the unchanged
0.15m limit. 471 real HUD frames, collision/input cleanup, normal Minecraft exit
and original FPS restoration passed. KCD PID31304 was closed normally afterward.
Fresh capture: ground-corridor-20261029-215241-996020b00b0a4151aaace5cbe265de63.

The one-command fresh-world check also PASSED:

    runtime/evidence/coupled-movement-20261029-215918-123b870a55fe4ff1bdd40d64a8f45588/verification.json

38 forwarded frames/readbacks, actual KCD displacement 5.872m, maximum camera error
0.051m, 480 real HUD frames, restoration/cleanup/FPS restoration passed. The wrapper
closed its owned KCD PID52588 normally. Both games are now closed. Its complete log
is runtime/corridor-one-command-20261029.log; recheck processes before another launch.
All evidence stays local under runtime/evidence; game assets/saves stay out of Git.

## Automated entry point

From the repository root (PowerShell 7 is selected automatically):

    ./scripts/Test-CoupledGroundCorridor.ps1 -LaunchTestWorld

This launches a fresh pinned official world, captures both tiles, runs actual
Minecraft and KCD following, validates crossing/return/HUD/cleanup and closes only
its owned KCD process normally. Omit LaunchTestWorld to use an already-loaded,
stationary world and leave it open. No F8 countdown or user controls are required.

The default is explicit walk-only mode. It has distinct readiness/proof/trace
identities and rejects jump phases. IncludeJump selects the separate diagnostic
below; never relabel its failures as walking passes.

## Known jump-camera issue — do not extend a tuning loop

Full-jump controllers 608fc0a02eeb466c8d2ba61d3846de99 and
0522c94041d54470bfd3fce629a71254 passed actor following, return/restoration and
Minecraft/HUD proof, but failed the unchanged camera-offset criterion during
LANDING: deviations 0.295m and 0.363m. Actor positions exactly matched the targets.
One supported 1ms follower-cadence trial did not fix it and was reverted. Current
corridor cadence is 40ms with 549 ordinary writes plus restoration. Preserve the
failed evidence. No new engine camera API or offset was invented.

## Next implementation

1. Bring the fixed corridor geometry/provenance into the physical-input/native-HUD
   route. Add an explicit profile; preserve existing verified profiles and bounds.
   Automate its source-side and coupled-game checks before one batched human check
   for actual foreground composition/input/feel.
2. Extend toward rolling terrain with explicit ownership/replacement. The corridor
   is one immutable joined surface, not streaming or unrestricted roaming.
3. General terrain-face placement remains unfinished. Current owned lab support
   does not establish arbitrary building against KCD terrain.

Current contracts: fixed MC anchor(0,64,0); inset X[-3.5,7.5],Z[-3.5,3.5],
Y[57.9,67.5]; 20s source/22s host, 400ms host lease, 256-record/256KiB trace.
Client/server freshness and position/camera limits remain intact. Paused input
still publishes advancing fresh server snapshots so the follower can hold safely.

Focused checks passed: Java terrain/trace 2264, mode 183, legacy physical 383;
Lua follower 96; PS corridor follower 103, legacy coupled 97, receiver 16 groups,
wide 68, corridor helpers 39, old ground 134. Do not rerun unchanged suites.

## Other retained work

Repeat-session gameplay reuse passed live, but final generation 2 exhausted-state
and third-session refusal remain unverified after the completion-tail repair.
The original second run's late receipt/native cleanup_timeout remains a failure;
its separate post-run audit does not authorize rearm. See docs/PROGRESS.md and
Git 87217b9. Bundle remaining acceptance with a useful feature check, not another
isolated replay of already-proven inventory/block controls.

## Environment

Workspace: C:/Users/xephi/Documents/ChatGPT/New project/MineCome
Public repo: https://github.com/gabrielpery/minecraft-kcd2
Branch: codex/initial-import; inspect current Git status/log before editing.
Official Steam tools 2429020/build 1.5.5 only; retail 1.5.6 remains gated. Never load
retail saves in tools. Existing repeat addon stays installed; no native addon was
changed this round. Routine changes, launches, tests and Git pushes are authorized.
JDK: C:/Program Files/Java/jdk-24
Gradle cache: minecraft/.gradle-user-home
Bundled PS7: C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe
Lua tests: C:/Program Files/Wireshark/lua52.dll

Follow AGENTS.md: integrated progress, focused automation, minimal manual requests,
concise handoffs. Use exact owned identities/receipts; never guess a latest arm or
reuse failed cleanup. Format commands separately before any question widget.
