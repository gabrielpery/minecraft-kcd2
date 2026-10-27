# Resume checkpoint — 27 October 2026

The current objective is physical walking and Minecraft's real HUD working
together inside KCD2. The camera delivery repair is implemented and measured;
one bounded physical run now passes the technical controller check. The user
still reports a tiny jittery step and no response to a later W press. The current
work addresses repeated input, downhill clearance and smoother KCD updates.
Do not call this the final playable build or repeat the confirmed stone/HUD work.

## Implemented and verified

- Branch: `codex/initial-import`, public remote
  `gabrielpery/minecraft-kcd2`. The separate native walking bundle is unchanged;
  current changes are Java, Lua, scripts, tests and documentation. Local checkpoint
  `a59403c` preserves the camera and one-step baseline before the usability work.
- `HudCameraDelivery.ps1` owns request/receipt/publication in a separate bounded
  runspace. Movement commands cannot stall it. Original request UTC is retained.
  A 110 ms monotonic cadence permits at most 1,019 requests in 112 seconds,
  within the unchanged Lua 1,024-sample budget.
- `HudWalkingReceipts.ps1 -KeepOpen` retains an unbuffered read handle. The
  camera worker and walking controller explicitly close it. Default callers
  still reopen per poll; closed cursors cannot reopen. Partial UTF-8 tails,
  atomic batch parsing, truncation and the 8 MiB extent bound remain enforced.
  Rotation cannot feed replacement-file acknowledgements into the retained cursor.
- Evidence-path checks use .NET attribute/parent APIs without weakening ancestor
  reparse-point rejection. Camera snapshots use atomic replacement and
  `Flush(false)`; durable evidence is not relabelled or retimestamped.
- `HudMovementBoundary` checks next-tick acceleration and braking clearance
  across sampled slabs before accepting input. It releases keys without changing
  Minecraft position or velocity. The latest change pauses at a boundary instead
  of ending the trial. A balanced release followed by a fresh press may resume in
  an allowed direction, without renewing the original five-second deadline.
- `HudMovementCompletion` waits for 500 ms of continuous grounded settlement
  before checking client AND server walking proof. Instability resets this timer.
  Existing one-second settling and six-second total deadlines still apply.
- The physical-only vertical envelope is now -1.5 m to +1.5 m within the unchanged
  2 m KCD follower sphere. Java uses a 1.75 m predictive radius, 1.8 m hard radius,
  -1.45 m to +1.45 m predictive vertical clearance and sampled-ground coverage.
  The legacy scripted follower retains -0.2 m to +1.5 m.
- Physical Lua following now writes a midpoint and then the exact endpoint on
  separate 40 ms ticks. Only the following-frame endpoint observation is an
  applied acknowledgement. That receipt also contains the actual midpoint
  observation and error. Waiting targets coalesce, but later arrivals cannot
  extend an in-flight segment's own 400 ms lifetime from Lua acceptance.

The 300 ms camera, 250 ms input, 400 ms follower and eight-second follower limits
are unchanged. Movement remains separate from the revision4 aimed/stone profile.
Native KCD physics remains enabled; full-world or exclusive movement is not proved.

## Latest completed attempt

HUD run: `c398308550e6446db5d79bd176a1709b`.

Local evidence, excluded from Git:
`runtime/evidence/hud-walking-20261027-142059-6cf16f5625e34739a9f1b77b5bc74200/`.

The controller reports `passed`: five server frames forwarded, five delayed KCD
applied readbacks, passing trace and verified restoration. It recorded 477 camera
publications with no stale discards. Camera resources closed and the temporary FPS
cap restored. The user described an inch-like jittery step and later W presses
doing nothing. Keep this technical pass separate from usability: the controller
still records `visual_verified=false`, and sustained walking is not established.

Afterward KCD was closed normally through `WM_CLOSE` with exit code 0; Minecraft
was also closed. The old `c398...` arm was archived before the next KCD launch.
The fresh tools process is PID 49616, started at 14:43:45 on 27 October, and was
left open for the independent checks. Recheck current processes and newer
evidence before resuming; these process details are a checkpoint, not authority.
This fresh KCD process has no HUD arm or native activation. The standalone
fixtures do not consume a physical arm, so the current world can be used for the
next physical check without another restart if its state is unchanged.
The latest `Test-HudWalking.ps1 -PreflightOnly` passes for PID 49616, no add-on
`.ini` arm files are present, and only KCD remains open.
The user is away cooking and explicitly authorized continued implementation and
autonomous testing. Do not start another short physical-input window without them.

The new boundary-resume changes have no combined physical live result yet.
`Test-HudPhysicalMovementFixture.ps1` is an independent actual-Minecraft test with
scripted input, controller physics, inventory and HUD. It makes no KCD calls and
does not claim physical input or KCD composition. `Test-KcdPhysicalFollower.ps1`
uses small scripted KCD targets without Minecraft, HUD arming or physical keys.
The independent KCD follower passes five scripted targets, with zero observed
midpoint and delayed endpoint errors, verified actor restoration, cancelled
timers and FPS restoration. Target ages were 96.49–146.59 ms after Lua acceptance,
not physical-input latency. Evidence:
`runtime/evidence/physical-follower-scripted-20261027-144521-6d622dba7e2b42fd8b45a9e8ca5bd1fc/`.
Do not repeat that completed component check without a new change or failure.

The actual-Minecraft flat fixture passes, run
`70db9fa42a8a4e4c8dd48ad2b5974ef4`. Scripted W/W/S presses move client and server
approximately 0.857 m, 0.642 m and 0.857 m, with zero disagreement. The second W
pauses at a boundary and S resumes after release. Inventory W moves neither
side. Nine inventory and 32 walking HUD frames, 102 published frames and 52 trace
records are recorded; movement completes in 5.536 seconds with zero corrections.
Controls, collision proxies, camera worker and mapping clean up. Saved actual
inventory/hotbar PNGs were inspected. Evidence:
`runtime/evidence/hud-physical-fixture-20261027-145207-70db9fa42a8a4e4c8dd48ad2b5974ef4/`.

The captured-terrain fixture also passes, run
`664e98c29ee14d94b2a6acf6e26192db`. It replays numeric terrain from `c398...`, with
heading -171.788791435144 degrees and separate fixture provenance. W/W/S moves
both sides approximately 0.447 m, 0.641 m and 0.641 m; maximum walking displacement
is 1.088 m and minimum vertical offset -0.154 m. It records two boundary pauses
and two resumptions, zero corrections/disagreement and zero inventory-W movement.
Ten inventory and 31 walking HUD frames, 103 published frames and 52 trace records
complete in 5.508 seconds. All cleanup and host FPS restoration pass. Evidence:
`runtime/evidence/hud-physical-fixture-20261027-145410-664e98c29ee14d94b2a6acf6e26192db/`.
Both fixture clients exited. These checks prove the actual Minecraft controller
with scripted input; neither proves physical KCD controls or composition there.
Only the combined physical response/visual check remains for the current changes.

## Failures already diagnosed

- `e81cfb5cf4444a97a7d73ba964e120cd`: two actual KCD applied readbacks, zero
  position error and explicit restoration; failed on 0.371 m downhill descent.
  The initial braking gate kept the 0.2 m descent limit, but ended after a tiny
  step. The current physical-only envelope and resumable pause address that
  usability problem; legacy scripted bounds remain unchanged.
- `26b570c2e51846e9aee2ced58b77b376`: inventory worked, but no movement edge
  was accepted. The old 90 ms cadence reached the 1,024 camera-sample budget.
  The cadence is now 110 ms; this run does not establish walking.
- `f14d88a1da744fe8a6209dfcc9c0d004`: one accepted movement tick, client
  0.15149 m and server 0.098 m; proof was rejected before the server caught up.
  The new completion gate replays that lag/catch-up in a focused regression.
- `ac7c108a97f24b0e8c9e3c5a57526180`: pre-arm HTTP timeout during early world
  startup, with cleanup and no compositor activation. Let the fresh world finish
  warming up before starting another lab.
- `3e315dd5cbab4ac3a2c626764346a11a`: expired waiting for F8 while the user was
  away. It forwarded no poses and had no readbacks; it is not movement evidence.
  Its 781 camera publications had no stale discards, with maximum old-source age
  of 282 ms. Camera resources and FPS restoration completed.
- Fixture `3f8a5c49d00a4133b87a87d255075423` failed the new route's producer
  constructor guard. That routing is repaired.
- Fixture `50341a5ce8d040efb0386d748eabd26b` hit Windows `AccessDenied` while
  atomically replacing its camera file. `HudFixtureCameraFiles` now retries the
  exact prepared bytes for at most 100 ms without refreshing capture time.
  A real Windows handle denying delete sharing exercises this regression.
- The 20 October camera-expiry failure and its original receipts remain in
  `docs/PROGRESS.md`; do not erase or reinterpret them as successful runs.

## Validation and remaining checks

- Current Java controller checks: 282; ground checks: 160; reverse input: 353.
- PowerShell camera worker: 57; receipt cursor: 74; path protection: 23;
  physical profile: 107; fixture checks: 43; ground movement: 134; coupled proof: 80;
  legacy trace receiver: 16.
- Live camera-only checks maintained publication during ten 500 ms caller
  stalls; these did not start Minecraft or move KCD's player.
- The earlier no-input stream kept old-source age below 300 ms throughout; mean
  receipt lookup was 1.748 ms. This does not establish physical input latency.
- Independent reviews covered worker cleanup, bounds, braking and completion.
  No new native installation or native build is needed on this machine.
- Updated Lua following passes 40 cases in Lua 5.2 with simulated engine
  bindings. These include actual observed drift in receipts, immutable segments,
  expiry despite fresh later targets, interruption, restoration and legacy paths.
- The separate actual-KCD follower probe and both actual-Minecraft scripted
  fixtures pass as recorded above. Their scopes remain distinct; do not claim
  combined visual smoothness or physical input from those component results.

## Next action

1. Inspect newer verification and current processes. Preserve the completed
   `c398...` technical pass and its negative usability feedback.
2. Do not repeat the completed flat fixture, captured-terrain fixture or scripted
   KCD follower probe unless a new change or failure warrants it. The next check
   is physical walking with the HUD inside KCD. Ask the user to reply “ready”
   when back, then use the current fresh game. Do not start the F8 activation
   timer while they are away.
3. Reuse fresh KCD PID 49616 if unchanged: it is open and has no HUD arm/native
   activation. The standalone fixtures did not use that arm. The prior physical
   run's owned receipt is
   `runtime/evidence/hud-walking-20261027-142059-6cf16f5625e34739a9f1b77b5bc74200/capture/stream-arming.json`.
   It was archived before PID 49616 was launched. Inspect any newer arm first;
   do not close/restart this fresh world unnecessarily. If the process or arm
   state has changed, follow the normal owned-arm lifecycle instead.
   `Archive-HudArm.ps1` takes `-ReceiptPath`. `Start-Kcd2ToolsTest.ps1` starts a
   fresh official 1.5.5 development world when needed. Never open newer retail saves.
4. With the user present and the world warmed up, run
   `Start-HudWalkingLab.ps1 -PreflightOnly`, then the normal wrapper. It handles
   PowerShell 7; no replacement add-on is needed. Request input only after
   `HUD_WALKING_READY`. Verify a brief W press, release and second press while
   the hotbar remains visible. A fresh press away from a boundary is allowed only
   within the original five-second input window. Check inventory suppression
   separately if combining every action would consume that window.
5. Verify server trace completion, actual midpoint/endpoint observations,
   explicit-end restoration, camera cleanup, control/collision release and FPS
   restoration. Record the user's response on responsiveness and HUD visibility
   separately. A passing receipt alone does not settle the reported jitter.

The user authorizes routine implementation and launches without repeated
permission questions. Earlier physical Escape presses stopped Computer Use.
Use the actual current tool state on a future turn; do not infer that observing
the screen causes game failures. Keep commands in formatted chat messages and
avoid consuming the activation window with unrelated work.
