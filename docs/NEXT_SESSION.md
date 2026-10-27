# Resume checkpoint — 27 October 2026

## Start here next week

The user requested further offline progress before this handoff to conserve the
remaining usage allowance; the sampling fix below is now complete. **Do not launch
another demo until they resume.** Both games remain closed; `KingdomCome` and `java` were checked and
are closed. The replacement KCD process 48256 was closed by the user before a new
walking controller/HUD comparison started; this is not a new test failure.

- Latest implementation is committed as
  `d150024667683ce6366f4800528528d8b9ab9f0b` on public default branch
  `codex/initial-import`, remote `https://github.com/gabrielpery/minecraft-kcd2`.
  It adds fixed-schedule physical sampling on top of the finish/warmup fixes in
  `c90da08973da9db54ad2c7a1c94d2def1b34cec0`. This handoff is a subsequent
  documentation update; inspect `git log -3` and
  `git status --short` rather than resetting to the implementation commit.
- Workspace: `C:\Users\xephi\Documents\ChatGPT\New project\MineCome`.
- The old `2dd6...` movement arm was already archived at 17:40:47 UTC on
  27 October. Its `capture/arm-archive.json` and
  `capture/MineComeHudMovement.expired.ini` are present. The installed
  `MineComeHudMovement.ini` is absent. **Do not ask the user to close or archive
  that old session again.** Recheck process/file state before the next launch.
- No new native installation, renderer rebuild, PowerShell setup or administrator
  session is needed. The installed walking bundle is unchanged.
- The immediate live check outstanding is the combined physical comparison of
  parser warmup, native normal completion and the fixed sampling schedule.
  Neither `c90da08` nor `d150024` has been physically tested. The last user
  feedback remains: "a lot smoother", with delay.

### What is already proved

| Area | Evidence and practical limit |
|---|---|
| Walking with the real HUD | User confirmed repeated movement in all directions and later much smoother motion. Latest physical path passes 52/52 source observations. Its original overall result remains failed because the watchdog, rather than the normal finish path, performed the exact return. |
| Normal finish repair | `FinishBufferedMovementFollower` seals the timeline and restores after its final observed point on the game thread. A separate real-KCD replay passes 51/51, explicit end, exact restoration, timers and FPS cleanup. This did not use Minecraft/HUD or human input. |
| Parser delay reduction | Before arming, disposable diagnostic state warms the parser. Five fresh-process profiles improve first recorded-packet processing from 69.13 ms to 8.52 ms median. Its effect on live responsiveness is still unverified. |
| Sampling schedule | Physical and fixture profiles keep the first successful sample's 100 ms schedule instead of restarting the wait after every late callback. They skip missed slots, preserve actual timestamps and emit no backfill. A synthetic six-second comparison changes 59 samples/155 ms accumulated drift to 60 samples/55 ms lateness, within its 56 ms maximum callback interval. No live latency gain is claimed. |
| Regression checks | Java24 compile, ground/trace 807 and physical-controller 282 checks pass after the sampling change. Existing Lua 79, buffered proof 79, warmup 86 and physical receiver 119 checks remain unchanged. Do not repeat unchanged suites or confirmed stone/HUD tests merely to resume. |

The new sampler retains legacy GROUND/HUD_COUPLED behavior, the 250 ms server
freshness limit, 200-record/64 KiB trace bounds and reserved termination space.
Six-second tests with maximum-length run identifiers and long double values fit
57,069 bytes (physical) and 57,699 bytes (fixture), with 61 samples/63 records.
Forced final samples still need fresh advancing server observations and strictly
advancing actual time. The 200 ms native buffer and all movement limits are unchanged.

### Exact next action after the user resumes

1. Read `AGENTS.md`, this section, and the latest Git status. Preserve functioning
   code and local evidence. Keep the 200 ms playback buffer: an earlier trace
   requires about 189 ms of right-point availability, so 150 ms would underrun.
2. Confirm the user is ready before starting a timed comparison. Launch the fresh
   official tools world with the existing helper; it automatically selects PS7:

   ```powershell
   & 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-Kcd2ToolsTest.ps1'
   ```

   Allow loading to finish (previously about 90–150 seconds). Use the existing
   `Test-KcdMovementProbe.ps1 -Action Capabilities` if a read-only readiness check
   is needed. Never load retail 1.5.6 saves into this 1.5.5 development world.
3. Run the prepared controller using the already installed PS7 executable:

   ```powershell
   & 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudWalking.ps1'
   ```

   Wait for `HUD_WALKING_READY`, then promptly ask the user to switch to KCD,
   release controls and press F8 within the **actual reported** activation window.
   After half a second, briefly tap W, S, A and D with releases/gaps, all within
   the first five seconds. Compare the keypress delay and watch the hotbar.
   The return at about six seconds and Minecraft closing after the 30-second HUD
   session are intentional. Do not burn the countdown on unrelated work.
4. Inspect the new evidence directory: `verification.json`, `forwarded.json`,
   `dispatch-timings.json`, `kcd-receipts.json`, `movement.ndjson` and
   `view-timings.json`. Require every source crossing, `explicit_end` restoration,
   fresh camera delivery and normal Minecraft/FPS/resource cleanup. Separate
   measured validation/preparation/HTTP times from native readback and subjective
   responsiveness; HTTP success does not prove native application. Also measure
   actual source publication/server intervals and total trace bytes for the new
   cadence; its synthetic timing result is not a live performance result.
5. If it passes, record the user's result and pursue longer walking and integration
   with the already working aimed-block controls. If it fails, diagnose this run
   before another restart. Do not lower buffers, widen guards, or rewrite failed
   evidence merely to get a passing result.

Keep commands formatted in chat before any question widget. Routine development,
launches, tests and Git pushes are already authorized. Earlier Escape presses
stopped Computer Use; inspect the tool's actual state in the resumed turn rather
than assuming it is permanently unavailable. Screen access itself does not cause
the game failures. No scheduled task or reminder was created.

## Detailed checkpoint and historical evidence

The current objective is physical walking and Minecraft's real HUD working
together inside KCD2. The latest buffered run is user-confirmed "a lot smoother",
with noticeable keypress-to-movement delay. All 52 source points pass delayed
native readback proof and Minecraft completes its trace. Primary verification
still fails the normal-finish contract: the native watchdog restored the exact
origin before the expected explicit-end handshake. Actual restoration, FPS and
resource cleanup succeeded. The finish repair now passes a separate 51-point
autonomous KCD replay; no physical run of that repair is claimed. Preserve the
200 ms smoother baseline. Diagnostic warmup is implemented before arming and
reduces first-edge pure processing from a 69.13 ms cold median to 8.52 ms across
five fresh-process profiles. Its live responsiveness effect remains unverified;
actual dispatch-stage timing is now retained for that check. Do not repeat confirmed stone/HUD work or call this the final build.

## Implemented and verified

- Branch: `codex/initial-import`, public remote
  `gabrielpery/minecraft-kcd2`. The separate native walking bundle is unchanged;
  current changes are Java, Lua, scripts, tests and documentation. Commits
  `a59403c` (camera/one-step baseline), `f6f8ea9` (resumable walking/components)
  and `2e75faf` (frame-cadence interpolation and pacing evidence) are pushed to
  the public default branch. Source-time buffering, the phase correction and
  candidate documentation are pushed as `11b1b76fc8e5ccf053d7f96642ce3bffa88cd2c6`;
  the remote was verified and the worktree was clean at that checkpoint. Native
  normal completion, parser warmup, dispatch timing and their tests/docs are now
  pushed in `c90da08973da9db54ad2c7a1c94d2def1b34cec0`.
- `HudCameraDelivery.ps1` owns request/receipt/publication in a separate bounded
  runspace. Movement commands cannot stall it. Original request UTC is retained.
  A 110 ms monotonic cadence permits at most 1,019 requests in 112 seconds,
  within the unchanged Lua 1,024-sample budget.
- `HudWalkingReceipts.ps1 -KeepOpen` retains an unbuffered read handle. The
  camera worker and walking controller explicitly close it. Default callers
  still reopen per poll; closed cursors cannot reopen. Partial UTF-8 tails,
  atomic batch parsing, truncation and the 8 MiB extent bound remain enforced.
  Rotation cannot feed replacement-file acknowledgements into the retained cursor.
- `Initialize-HudBufferedMovementPipeline` now runs before arming/readiness. It
  validates the current patch and exercises only independent disposable parser
  state with three diagnostic in-memory records. No live receiver/source state,
  native follow session, source publication or clock rebase is involved.
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
- Physical Lua following now uses an immutable 200 ms source-time playback
  epoch, with source times derived from the actual server observation clock.
  Initial grounded source zero and the final point are both forwarded. The
  controller retains precise normalized times and explicit float32 wire times.
  It requires every source point to be acknowledged, validates the common epoch
  and per-ACK crossing index. The controller seals the submitted timeline as
  soon as the final source and passing trace end arrive. Native Lua waits for the
  final delayed observation and restores normally without controller ACK polling.
- The follower interpolates only between adjacent known source points, with at
  most eight active points and no extrapolation. The right point's original
  400 ms acceptance lease is immutable; old left points are historical geometry.
  It requests 1 ms timers and skips unchanged setters. Physical writes remain
  capped at 512, legacy writes at 200. Receipt serialization stays below 3,800
  bytes with bounded samples, factual total counts and explicit truncation.

The 300 ms camera, 250 ms input, 400 ms follower and eight-second follower limits
are unchanged. Movement remains separate from the revision4 aimed/stone profile.
Native KCD physics remains enabled; full-world or exclusive movement is not proved.

## Latest combined result and latency

HUD `fa370b398a9243e69ee15924cf777c4d`, probe
`2dd6df695d15485cb84082793245d970`:
`runtime/evidence/hud-walking-20261027-165506-2dd6df695d15485cb84082793245d970/`.
The user says it worked and was a lot smoother, but movement felt delayed. There
are 52 forwarded sources/52 valid readbacks, a passing 5,511 ms Minecraft trace,
equal client/server 0.594374 m maximum travel, four pauses/three resumptions,
zero corrections and two correctly labelled authoritative LANDING samples.
All 768 camera publications are fresh; camera resources, FPS and Minecraft
cleanup pass. Inventory was not opened in this run.

Primary `verification.json` remains failed. The terminal native receipt proves
exact restoration with zero error and cancelled timers, but its reason is
`frame_lease_expired`, not the required normal end. It occurs after 138 writes and
5,859 ms. `path-verification.json` independently passes all 52 buffered receipts;
it does not change the original failed normal-finish result. The native
end-of-stream repair passes autonomous replay `02e045ab5635428f99f7fd8614a3ab2b`
in `runtime/evidence/buffered-movement-replay-20261027-170751-02e045ab5635428f99f7fd8614a3ab2b/`:
51/51 scripted source points, `explicit_end`, 64 writes including restoration,
5,871.826 ms, zero restoration error, timers cancelled and FPS restored. It has
no Minecraft/HUD/physical input. No target lease extension or buffer change is
part of that repair; its combined physical check remains pending.

`latency-analysis.json` records 344 native observations, retaining 71. Every
retained readback advances one native frame, median 16.037 ms/max 16.296 ms, with
zero position error and no retained intermediate holds. Source capture intervals
are median 100.916 ms/max 166.572 ms; actual server-source gaps reach 201.099 ms,
and sampled server age is median 37.738 ms. No per-key timestamps are retained,
so physical keypress/display latency is not measured. Conditional clock alignment
estimates first capture-to-native acceptance at 124 ms, later captures at 35 ms
median, and first capture-to-native write at 334 ms; allow cached-frame clock
uncertainty. Native acceptance-to-first-write is directly measured at 210.068 ms,
including the intentional 200 ms buffer.

Preserve that buffer. Earlier autonomous replay `477...` needs 188.903 ms to have
every right point available at its bracket start; 150 ms would underrun despite
the latest run having more headroom. After normal finish works, measure first
trace read/validation/dispatch and warm only confirmed read-only setup before
activation. A pure profile in
`runtime/evidence/hud-source-cold-profile-fa370b-20261027/` replays the exact trace
twice in each of five fresh PowerShell processes. First-edge parse/normalization
costs median 69.13 ms cold versus 6.73 ms on a same-process second replay; no game
calls or physical timing claims. The implemented diagnostic warmup has now been
profiled in five additional fresh processes in
`runtime/evidence/hud-source-warmed-profile-fa370b-20261027/`. First archived
begin/sample/normalization after warmup costs median 8.52 ms (range 7.67–9.93 ms),
60.61 ms below the cold baseline. Warmup costs median 245.14 ms before arming.
All 52 exact source points/hashes reproduce in each pass. Its 86 tests and the
existing 79 buffered checks pass. The controller retains receive/validation/
preparation/request timing and checks source age after preparation at dispatch.
The live benefit still needs evidence.
Do not start native following early. Faster physical-only source sampling
requires a separate bounded comparison before reducing playback delay.

Process 33860 closed and its consumed arm was archived. The ownership receipt is
`runtime/evidence/hud-walking-20261027-165506-2dd6df695d15485cb84082793245d970/capture/stream-arming.json`;
the same directory now contains `arm-archive.json` and the expired INI. Replacement
process 48256 was launched, then closed by the user before a new comparison.
Both games are now closed and no movement arm is installed. Resume from the
instructions at the top; recheck actual process/receipt/tool state first.

## Previous combined buffered phase failure


HUD run `d838afda4ed44e9a855e5da65cb47c07`, probe
`d257ab3e82644a0b9e02612185d4db00`:
`runtime/evidence/hud-walking-20261027-163234-d257ab3e82644a0b9e02612185d4db00/`.
The controller fails after two forwarded sources because sequence 4 is labelled
RESTING while the authoritative server lacks `proxy_support` during a 0.0784 m
downhill transition. The client has already landed on the lower slab. Buffered
mode refuses to omit this waypoint. Java now reports the authoritative landing
phase; receiver freshness/ground/bounds guards remain unchanged. The compiled
correction passes 180 ground-patch, 282 physical-controller and 119 receiver
checks. Actual-Minecraft fixture `21862be610794462b3ed1437b7802477` passes on the
captured terrain: 103 published frames, 11 inventory frames, 31 walking frames,
W/W/S distances 0.446445/0.640961/0.640961 m on both client/server, zero inventory
movement/corrections and 5,524 ms duration. Its 100 ms source samples do not
include the unsupported transition; it does not cover that regression. Targeted
synthetic fixture `5750b05f92b64938ba7025140d8c33ad` is rejected before movement by
the unchanged 0.5 m adjacent-height bound. Revised synthetic fixture
`40b64199deda490893f786a0b42e7b27` passes: W/W/S distances
0.446445/0.640961/0.856736 m, 10 inventory frames, 32 walking frames, zero
inventory movement/corrections and 5,563 ms duration. It also emits no unsupported
`LANDING` sample. Keep those narrow fixture claims: the exact failed sequence 4
is covered by the Java regression and receiver checks plus read-only replay in
memory. All fixture folders are under
`runtime/evidence/hud-physical-fixture-20261027-*`, retaining explicit scripted
input and `standalone_ground_fixture` provenance. No more component fixtures are
needed for this narrow phase-label change. The subsequent `fa370b...` combined
path passes two authoritative LANDING samples.

The user reports that Minecraft closed immediately. Its actual exit code is zero
and the helper reports BUILD SUCCESSFUL: cancellation stopped the camera worker,
then the guest ended on camera lease expiry and saved/exited normally. Camera
records 579 publications with zero stale discards and closed resources. The native
terminal receipt is `rejected/explicit_end`, zero writes, unchanged origin, zero
player error and timers cancelled. The primary restoration flag is false because
no restoration event was needed; no actor movement was left unrecovered. FPS
restored. The original failure and separate `failure-analysis.json` retain this
distinction. This run provides no new smoothness result.

Process 34088 closed normally and its exact `d257...` arm was archived from
`runtime/evidence/hud-walking-20261027-163234-d257ab3e82644a0b9e02612185d4db00/capture/stream-arming.json`.
Fresh process 33860 subsequently ran the combined `fa370b...` check above and
consumed its activation. The phase correction is now verified through that
combined source path; see the newer completion/latency checkpoint above.

## Earlier buffered replay before the normal-finish repair

Run `477989b1edd34c10b5d90c437d8006fd` passes all 51 source points and observed
crossings, actor restoration and FPS restoration:
`runtime/evidence/buffered-movement-replay-20261027-162624-477989b1edd34c10b5d90c437d8006fd/`.
It replays the recorded `725d...` trajectory in real KCD with scripted source
positions. Minecraft, HUD composition and physical input were not active.
The 200 ms buffer adds intentional latency; this is not a smoothness or
physical-input result.

Its `timing-analysis.json` records 163 observations, 101 retained samples and
64 ordinary setters plus restoration. Each retained observation advances exactly
one native frame, median 34.42 ms and maximum 34.91 ms; do not label this replay
60 FPS. All actor readback errors are zero. Retained camera-offset changes are
median 0.26 mm, maximum 5.38 mm. Server-observation intervals are 97.77-201.27 ms,
and peak retained playback speed 3.688 m/s closely matches source speed 3.692 m/s.
There is no observed intermediate source hold; the final point is held normally.
Relative source-timeline-to-delayed-ACK time is median 254 ms, maximum 268 ms,
including buffer, crossing quantization and readback. This is not input-to-photon
time. All 59 matching lines from the rotated native log parse; the maximum full
line is 3,793 bytes. Per-line hashes/lengths are retained in the analysis.

## Last passing combined physical attempt

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

Process 45644 closed normally and its `725d...` arm was archived before the later
buffered attempt. Current consumed-arm state is recorded above.
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

## Earlier combined timing diagnosis

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
The source-time buffer addresses this timing compression while preserving the
original 400 ms accepted-target lifetime, eight-second hard deadline, two-metre
sphere and guarded restoration. The replay above has technical proof; the
successful combined result remains unverified.

## Failures already diagnosed

- Buffered replay `5ec108...` failed native JSON logging at about 4,095 bytes.
  Its separate `cleanup-verification.json` confirms exact actor restoration;
  FPS restoration also passed. Receipts now serialize below 3,800 bytes while
  retaining the final ACK observation and honest omitted-sample counts.
- Buffered replay `6ef373...` reached 50/51 points before the old 250 ms drain
  ended. It restored normally. The initial fix waited for the final ACK within
  400 ms. The current end-of-stream seal supersedes that controller ordering:
  seal immediately, then let native Lua observe the final point and restore.
  The original 400 ms target lease is unchanged.
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

- Current Java controller checks: 282; ground/trace checks: 807 after the
  fixed-schedule sampling regressions; reverse input: 353 (unchanged).
- PowerShell camera worker: 57; receipt cursor: 74; path protection: 23;
  physical profile: 119; fixture checks: 43; ground movement: 134; coupled proof: 80;
  legacy trace receiver: 16.
- Live camera-only checks maintained publication during ten 500 ms caller
  stalls; these did not start Minecraft or move KCD's player.
- The earlier no-input stream kept old-source age below 300 ms throughout; mean
  receipt lookup was 1.748 ms. This does not establish physical input latency.
- Independent reviews covered worker cleanup, bounds, braking and completion.
  No new native installation or native build is needed on this machine.
- Updated Lua following passes 79 cases with simulated engine bindings;
  buffered PowerShell proof passes 79 checks, diagnostic warmup 86 checks, and
  timed-follower proof 32 checks.
  These cover native precision, source clocks/brackets, no extrapolation,
  original leases, observed drift, bounded logs, interruption and restoration.
- The separate actual-KCD follower probe and both actual-Minecraft scripted
  fixtures pass as recorded above. Their scopes remain distinct; do not claim
  combined visual smoothness or physical input from those component results.

## Next action

1. Preserve the passing `02e045...` autonomous end-of-stream replay and the
   failed `fa370b...` physical normal-finish result with separate restoration/path
   evidence. Keep the 400 ms original target lease and 200 ms buffer unchanged.
   The end-of-stream repair still needs combined physical validation.
2. Preserve the user-confirmed smoother baseline. No per-key timestamp series
   exists in this run; instrument original capture/application and first
   trace-read/validation/dispatch stages before claiming physical latency.
   Preserve the implemented disposable diagnostic warmup, which reduces pure
   first-edge work to 8.52 ms median in fresh-process profiles. Measure the actual
   first handoff with the new metadata. Do not start native following early,
   publish synthetic sources or refresh timestamps.
3. Both games are closed; the `2dd6...` arm is already archived. On user resumption,
   recheck state and launch a fresh supported world. No new native bundle is
   needed. Respect the current Computer Use state and never load newer retail saves.
4. Preserve all 52-source path proof and the prior autonomous replay. That earlier
   trace needs 188.903 ms of right-point availability; a blanket 150 ms buffer
   would introduce a known underrun. The fixed 100 ms sampling schedule now has
   offline timing and byte/record-budget evidence, but its real source intervals
   still need measurement before considering any buffer reduction.
5. For the next combined check, verify all source crossings, normal restoration,
   FPS/camera/Minecraft cleanup and user-reported smoothness/responsiveness. Keep
   the five-second movement window and intentional playback latency explicit.

The user authorizes routine implementation and launches without repeated
permission questions. Earlier physical Escape presses stopped Computer Use.
Use the actual current tool state on a future turn; do not infer that observing
the screen causes game failures. Keep commands in formatted chat messages and
avoid consuming the activation window with unrelated work.
