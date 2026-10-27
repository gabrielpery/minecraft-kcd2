# Resume checkpoint — 27 October 2026

The current objective is physical walking and Minecraft's real HUD working
together inside KCD2. Repeated physical movement now works in all directions
with the HUD, according to the user and a passing combined run. The user still
reports choppy motion with at most a small improvement. Camera delivery remains
fresh. Frame-cadence interpolation is implemented and passes technical checks;
remaining gaps and abrupt speed changes between segments need investigation.
Do not call this the final playable build or repeat the confirmed stone/HUD work.

## Implemented and verified

- Branch: `codex/initial-import`, public remote
  `gabrielpery/minecraft-kcd2`. The separate native walking bundle is unchanged;
  current changes are Java, Lua, scripts, tests and documentation. Both
  `a59403c` (camera/one-step baseline) and `f6f8ea9` (resumable walking/components)
  are pushed to the public default branch. The later frame-cadence interpolation
  is a working-tree change at this checkpoint, with autonomous and combined
  technical proof; inspect Git before assuming publication.
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
- Physical Lua following requests 1 ms timers and advances an immutable segment
  over 100 ms of engine time, with a later endpoint readback. Six or seven writes
  per moving segment are now observed at approximately 16 ms intervals. It skips
  stationary setters and retains intermediate write/observation timestamps.
  Pending targets coalesce without extending a selected target's 400 ms lifetime.
  Physical writes are capped at 512; legacy following retains its 200-write cap.

The 300 ms camera, 250 ms input, 400 ms follower and eight-second follower limits
are unchanged. Movement remains separate from the revision4 aimed/stone profile.
Native KCD physics remains enabled; full-world or exclusive movement is not proved.

## Latest completed attempt

HUD run: `725d69490f464ca989fccb3783a7cba4`.

Local evidence, excluded from Git:
`runtime/evidence/hud-walking-20261027-154252-c869ec4362fc44d69f6f10516665149a/`.

The controller reports `passed`: 49 server poses forwarded and 49 delayed KCD
applied readbacks, passing trace and verified restoration. It recorded 484 camera
publications with no stale discards. Camera resources closed and FPS restored.
Minecraft records four accepted movement edges, two boundary pauses and two
resumptions, equal client/server maximum displacement of 0.758 m, zero corrections
and 5.565 seconds of movement/settling. The user says it is "still choppy, maybe
a LITTLE better". Smooth or sustained walking is not established; machine
`visual_verified=false` remains separate from that user feedback.

The previous `0e14...` arm was archived after normal KCD closure. The fresh KCD
process 45644, started at 15:40:09 on 27 October, consumed its activation in this
latest run. Minecraft is closed after the check. Its owned arm is
`runtime/evidence/hud-walking-20261027-154252-c869ec4362fc44d69f6f10516665149a/capture/stream-arming.json`.
Another physical activation needs normal KCD closure, archival of that exact arm
and a fresh launch. Computer Use remains stopped by Escape in this turn; do not
retry stopped screen access. Recheck processes and receipts before acting.
The user authorized extensive implementation and autonomous checks, with any
human control test at the end. Do not start a timed physical-input window while
they are unavailable.

The new boundary-resume changes have the combined physical result above.
`Test-HudPhysicalMovementFixture.ps1` is an independent actual-Minecraft test with
scripted input, controller physics, inventory and HUD. It makes no KCD calls and
does not claim physical input or KCD composition. `Test-KcdPhysicalFollower.ps1`
uses small scripted KCD targets without Minecraft, HUD arming or physical keys.
The latest independent KCD follower probe passes five moving targets and one
stationary target, with six or seven setters per moving segment, normal-frame
observations about 16-21 ms apart, zero errors and actor/FPS restoration:
`runtime/evidence/physical-follower-scripted-20261027-153609-198d8a567af448718f191a4984127621/`.
The stationary target causes zero setters. Two earlier probes failed strict
cadence at about 34 ms while preserving exact positions/restoration. The separate
read-only timer probe `d9589118d00247bbb0690508e2968042` shows rearmed 1 ms timers
on consecutive native frame IDs. Polling changed while foreground confirmation
was delayed; improvement cannot be attributed solely to polling or focus.
Do not repeat completed component checks without a relevant change or failure.

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
The later combined physical run confirms resumed controls but exposes choppiness.

## Current timing diagnosis

`timing-analysis.json` in the latest evidence directory compares the new timed
interpolation with `0e14...`, using existing records and no game/API calls.
The new path has 18 moving segments and 125 setters, with median 16.07 ms and
maximum 16.90 ms within-segment intervals. All 31 stationary segments perform
zero setters; observed readback errors are zero. The old midpoint/endpoint
observations were median 48.10 ms apart.

Remaining stutter leads are specific: four of 14 transitions between consecutive
moving segments pause 47.19-64.32 ms between writes. Source captures remain median
101 ms apart, maximum 168 ms. A 0.575 m change over 167 ms is compressed into a
fixed 100 ms segment, then the next segment covers only 0.052 m. New maximum
recorded frame step is 0.093 m, versus 0.316 m between old observations, but input
patterns differ and this is not a controlled subjective comparison. Test source
cadence and temporal continuity without extending source leases or extrapolating
unverified future movement.

Camera delivery during movement is median 63 ms, maximum 98 ms, with no stale
discards. Endpoint camera-to-player offset changes are at most 2.7 mm; independent
samples also show no large offset jumps. This does not resemble the old camera
expiry failure. Moving target acceptance-to-ACK is median 132 ms, maximum 161 ms;
stationary ACKs take about one game frame. No video or physical key-edge timestamps
are available, so this is not input-to-photon latency or presentation proof.
Two boundary pauses and real input releases also interrupt motion deliberately.
The original 400 ms accepted-target lifetime, eight-second hard deadline,
two-metre sphere and guarded restoration remain unchanged.

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
- Updated Lua following passes 47 cases with simulated engine bindings;
  PowerShell interpolation proof passes 17 checks. These cover observed drift,
  immutable segments, expiry despite fresh later targets, interruption,
  stationary write suppression, restoration and legacy paths.
- The separate actual-KCD follower probe and both actual-Minecraft scripted
  fixtures pass as recorded above. Their scopes remain distinct; do not claim
  combined visual smoothness or physical input from those component results.

## Next action

1. Preserve the latest `725d...` technical pass and the user's still-choppy
   report. The previous `0e14...` all-direction result and `c398...` inch-like
   step remain historical evidence; do not repeat repaired input/camera work.
2. Investigate measured segment-transition gaps and irregular source timing.
   The follower already writes at game-frame cadence inside each segment.
   Keep source age, immutable accepted-target leases, sampled ground and
   restoration guards intact. Use focused autonomous tests for changed timing;
   existing Minecraft fixtures need not repeat unless their path changes.
3. Before another physical HUD test, close KCD normally, archive the exact
   `725d...` arm with `Archive-HudArm.ps1 -ReceiptPath`, and start a fresh world
   with `Start-Kcd2ToolsTest.ps1`. Process 45644 has already consumed activation.
   Recheck current process state and respect the stopped Computer Use session.
   Never load newer retail saves into this development build.
4. With the user present and the world warmed up, use
   `Start-HudWalkingLab.ps1 -PreflightOnly`, then the normal wrapper. Request
   physical input only after `HUD_WALKING_READY`. Use a short repeatable sequence
   and record both timing and the user's smoothness observation. The original
   five-second movement window remains; verify inventory suppression separately
   if a combined sequence would exhaust it.
5. Verify server trace completion, normal-frame interpolation observations,
   explicit restoration, camera cleanup, controls/collision release and FPS
   restoration. Technical success alone does not resolve the reported jitter.

The user authorizes routine implementation and launches without repeated
permission questions. Earlier physical Escape presses stopped Computer Use.
Use the actual current tool state on a future turn; do not infer that observing
the screen causes game failures. Keep commands in formatted chat messages and
avoid consuming the activation window with unrelated work.
