# Resume checkpoint — 20 October 2026

The user requested a wrap-up because usage was nearly exhausted. Do not start
another demo automatically on resume until the remaining camera-delivery delay
has been investigated. The current task is to make physical walking and the
real Minecraft HUD work together in KCD2.

## Current state

- Branch: `codex/initial-import`, remote `gabrielpery/minecraft-kcd2`.
- The separate physical walking profile is implemented and installed locally.
  Its frozen hashes are in `config/hud-physical-movement-profile.json`.
  The known working revision4 stone/aimed profile remains separate.
- The physical profile uses actual Minecraft HUD pixels, protocol2 WASD/Space,
  fresh sampled KCD terrain, vanilla client/server movement, and the bounded KCD
  follower. Movement is limited to five seconds plus at most one second settling;
  the HUD lasts up to 30 seconds after F8.
- Inventory releases movement and requires neutral controls and a fresh press
  afterward. This profile intentionally does not publish stone-click intents.
- The user confirmed HUD/inventory in this profile. A complete physical walking
  session has **not passed**. Do not call this the final playable build.

## Latest live attempt

HUD run: `c427a5fc08bf4874a00f5f3cc64b04f4`.

Local evidence, excluded from Git:
`runtime/evidence/hud-walking-20261020-170855-731e410d62f944fc98f58fef5bd9b1b8/`.

The user reported Minecraft appeared to crash after starting to walk.
The logs instead show controlled failure and normal Minecraft shutdown
(`BUILD SUCCESSFUL`), triggered by `Physical HUD camera lease expired`.

- Actual Minecraft client/server walking reached approximately 0.754/0.627 m.
- One server pose was sent to KCD and one delayed applied readback matched it:
  trace sequence 3, approximately 0.250 m from the original position.
- `kcd-receipts.json` proves that readback. The summary's `delayed_readbacks:0`
  is the count assigned only during final success validation, which this failed
  attempt never reached; it must not be interpreted as no underlying readback.
- Explicit-end restoration returned KCD to its original position, cancelled its
  timers, and verified the camera basis. The temporary FPS cap restored to -1.
- Minecraft released held controls and both collision installations, saved the
  owned test world and exited. No active follower or Minecraft client remains.
  KCD itself was still open at wrap-up; its expired arm requires the normal
  archive/restart lifecycle before another F8 activation.

## What was fixed and what remains

1. Windows camera-file sharing races now retry for at most 100 ms. Unchanged bytes
   retain their original source time and deadline. Malformed data remains fatal.
2. Repeated parsing of growing camera history cost about 101 ms at 336 records.
   `HudWalkingReceipts.ps1` now parses complete records once, retains partial
   UTF-8 tails, and commits batches atomically. Saved-log unchanged polls measured
   0.089 ms median / 0.26 ms p95. This improvement did not eliminate the live delay.
3. The Java file reader now polls every 5 ms and freezes precise rejection
   diagnostics. The latest failure was **not** a long reader stall:
   last read was about 1 ms old; maximum poll gap was 42 ms.
4. Camera sequence 290 was requested at UTC 1792512591788, published at 1978,
   observed at 1979, then rejected at 2110 with source age 322 ms. Sequence 291 was
   requested at 2040 but published at 2117, seven milliseconds after rejection.
   These suffixes share the same epoch prefix. Full values are in
   `view-timings.json` and `capture/stream-result.json`.

Next work: profile the remaining controller stages separately—process/listener
guards, console HTTP round trip, receipt lookup, path validation and atomic
publication—then remove the measured delivery bottleneck. Request-to-publication
still reached roughly 120–190 ms. `Test-HudWalking.ps1` currently issues each
camera request serially and waits for its acknowledged log record. Consider
delivery scheduling only with precise request/receipt association preserved.
Do not refresh old timestamps or loosen the 300 ms camera, 250 ms input, 400 ms
follower, eight-second follower, or spatial limits to make a test pass.

## Validation already completed

- Native compilation and four focused native suites: 2769 checks.
- Lua movement probe: 33 cases.
- Latest Java compilation, physical movement 134 and reverse input 353 checks.
  Earlier ground, HUD stream, stone, aimed and trace suites also passed.
- Physical profile/trace 90, rollback 52 and receipt-cursor 59 PowerShell checks.
- Four deployment/profile suites: 676 checks under both PowerShell 5.1 and 7.
- Existing mouse, ground, coupled, archive and trace receiver regressions passed.
- Independent reviews covered native forwarding, Java freshness/cleanup, Lua,
  the controller, and the incremental log cursor.

Run only checks justified by the next change. Preserve all failed evidence.
Do not repeat the already confirmed HUD, inventory or stone milestones.

## Relaunch and user interaction

Use the existing `Start-Kcd2ToolsTest.ps1` for a fresh official 1.5.5 tools world;
never load the user's newer retail saves. `Start-HudWalkingLab.ps1` bootstraps
PowerShell 7 automatically and is the explicit combined test entry point.
Before its next invocation, archive the expired arm using the last run's
`capture/stream-arming.json` and `Archive-HudArm.ps1`, with KCD closed.
No add-on rebuild/reinstall is needed for Java/controller-only fixes.

The user authorizes routine launches, restarts and implementation without
repeated permission questions. Computer Use was stopped by their Escape press
during this turn; no further UI input was sent afterward. Screen observation
itself did not cause the HUD failure. The available Computer Use API has no
documented timed key hold, so one short human W hold may still be necessary.
Only request it after `HUD_WALKING_READY`; explain the bounded test and avoid
another blind retry before resolving the measured delivery delay.
