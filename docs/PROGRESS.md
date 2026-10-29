# MineCome progress — 2026-10-29

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


## Corridor walking with aimed blocks — ACTUAL-MINECRAFT PASS; KCD LIVE PARTIAL

The explicit `-CorridorWalking -RepeatSession` combined profile is implemented.
It joins the existing extended walking controller, hotbar/inventory and aimed
stone bridge over the immutable 12×8m capture. A fixed owned support beside the
terrain places the seed at (-1, floor(initial player Y), -5); top and EAST-face
placement stay outside every protected imported cell. The host controller binds
the same capture, tile hashes, player anchor and corridor follower profile.
Live capture and standalone fixture provenance remain separate.

Both automatic actual-Minecraft fixtures passed:

- Flat run `6016bca217f14dd68cb1cbf8619287d2`: maximum X=4.961m, return within
  0.0083m, 160 protected cells and 15 HUD frames during block interactions.
- Captured-terrain run `3f46a989741d4bde982e7b1e522341b6`: maximum X=4.823781m,
  return within 0.117886m, 10 crossing HUD frames, 15 block-interaction HUD frames
  and 144 protected cells. Six vanilla actions confirmed bootstrap, top place,
  upper break, EAST place, side break and seed break. Inventory suppression,
  resumed movement, cleanup, source hashes and movement trace verification passed.

Evidence is in `runtime/evidence/hud-physical-fixture-20261029-232349-6016bca217f14dd68cb1cbf8619287d2/verification.json`
and `runtime/evidence/hud-physical-fixture-20261029-232502-3f46a989741d4bde982e7b1e522341b6/verification.json`.
These use scripted controls/rays and a standalone HUD receiver. They do not
establish physical input or HUD composition in KCD2. The first fixture exposed
an old zero-yaw assumption; mode validation and both constructors now share the
explicit -90-degree corridor heading while legacy fixtures retain zero degrees.
The original failed evidence remains intact.

The repeat/aimed bundle `runtime/hud-compositor-walking-corridor-aimed-20261029`
is now installed with the existing pinned `c5353e4b…` addon. The explicit
physical-to-repeat transition verified all six owned files and changed only the
addon; no DLL rebuild was required. Update receipt:
`runtime/evidence/hud-update-20261029-232323-f10b39f3ff864a2594295efb575eba1d/update.json`.
The expired plain physical arm was archived with exact hash and dead-process
checks. A fresh KCD2 world is open for `TopFaceInventory`; combined corridor live
acceptance did not pass; see the latest cutoff-cleanup result above.

## Physical corridor HUD and controls — LIVE USER ACCEPTANCE

Foreground run `2a2b53983db449b59979f21dd60637d5` passed 157 source points and
delayed native readbacks, 862 actual Minecraft HUD frames and exact player
restoration. The user reported: “it worked all fine, still a bit choppy/delayed
but it's okay. continue”. Walking with the HUD, hotbar controls and inventory
movement suppression worked. Remaining subjective choppiness is recorded.

Client/server maximum X was 3.5762478m. This check did **not** cross the original
X=4 edge. The earlier recorded-controller native replay reached 4.82378m; keep
that separate from foreground input/composition acceptance. Any further live
crossing check should be batched with the next integrated milestone.

Evidence:
`runtime/evidence/hud-walking-20261029-230705-6f95a1b3caab42aca886a805b844e9d9/manual-acceptance.json`
and its adjacent `verification.json`. KCD PID52208 was closed normally afterward.
At that point, the installed bundle was the plain physical profile in
`runtime/hud-compositor-walking-corridor-20261029`, with pinned addon `869fc9a8…`.
The repeat/aimed bundle in `runtime/hud-compositor-walking-corridor-aimed-20261029`
was staged only. Its subsequent installation is recorded above. The updater
passed 34 new transition checks and 171 existing profile checks without rebuilding
a DLL.

## Physical controller on expanded terrain — AUTOMATIC CONTROLLER/REPLAY PASS

Added an explicit extended physical walking/HUD corridor profile, preserving the
initial settled anchor, two-tile provenance, rectangular bounds, source timing
and exact collision cleanup. Combined corridor aimed blocks were added afterward,
as recorded above; the existing 8×8m combined live result remains valid.

Captured-terrain fixture `d8dfe1edd3724a999ecf91083f4fc6f2` passed: client/server
X=4.824m, return within0.118m, five W/S pulses, inventory movement suppression,
253 HUD frames including10 crossing frames, source hashes and cleanup. Native
replay `fbfc11b45b9843a9b2fc467ba2ae2275` passed156 forwarded/readback points,
actual KCD displacement4.824m, maximum actor error0.000031m, exact restoration
and FPS restoration. This validates recorded controller playback; it does not
claim foreground physical input, native HUD composition or visual smoothness.

The first captured test requested X=5.5 and hit the existing conservative coast
braking guard during a small descent. Its failed evidence97e91b7da1ee45f3adf16f10bf511513
is retained. The test now turns at X=4.5, fully beyond the original edge including
the whole player footprint. Production braking and all limits are unchanged.
The runner also handles empty startup logs and can retain an owned test world
for setup diagnosis, avoiding repeated reloads. KCD54112 was closed normally.

The physical bundle was staged separately with an exact repeat-to-physical
update preflight. Its subsequent installation and foreground acceptance are
recorded above; current installation state is in NEXT_SESSION.md.

## Expanded terrain drives KCD walking — AUTOMATIC TWO-GAME PASS

The new coupled corridor route follows real Minecraft server observations across
the two-tile 12×8m surface while preserving the original capture alignment.
It requires terrain from the exact running KCD process, exclusive mode/trace
identities and the inset rectangle; existing physical/native-HUD profiles are
unchanged. Paused Minecraft input still publishes advancing, fresh server
observations, preventing an unnecessary follower lease expiry.

Walking controller `3c51920138ab4cebab27a93304458ed8` passed: 36 forwarded frames,
35 delayed native movement readbacks, actual KCD X displacement 6.076m from the
capture origin, a return across the old X=4 edge, settled return and exact saved
origin restoration. Maximum camera error was 0.058m, below the unchanged 0.15m
limit. The native standalone receiver accepted 471 actual Minecraft HUD frames;
collision/input cleanup, normal Minecraft shutdown and original FPS restoration
passed. KCD PID31304 was then closed normally. No manual test was needed.

Evidence: `runtime/evidence/coupled-movement-20261029-215241-3c51920138ab4cebab27a93304458ed8/verification.json`.
Fresh terrain capture: `ground-corridor-20261029-215241-996020b00b0a4151aaace5cbe265de63`.
Run `scripts/Test-CoupledGroundCorridor.ps1 -LaunchTestWorld` to automate a fresh
world and both-game walking check; omit the launch flag to preserve an existing
loaded world. PowerShell 7 is selected automatically. This does not establish
physical input or native HUD composition over the corridor, or rolling terrain.

The optional `-IncludeJump` remains a failing diagnostic. Controllers
`608fc0a02eeb466c8d2ba61d3846de99` and `0522c94041d54470bfd3fce629a71254` completed
actor movement, return, restoration and Minecraft/HUD proof, but recorded native
camera-height deviations of 0.295m and 0.363m during landing. Actor readbacks matched
every target exactly. A single 1ms-cadence experiment did not solve it and was
reverted to the original 40ms cadence/budget. Both failures remain intact. The
explicit walking profile skips jump, rejects jump trace phases and uses a distinct
proof kind; all camera/position/freshness bounds remain unchanged.

Focused validation passed: Java terrain/trace 2264, mode 183, legacy physical 383;
Lua follower 96; PowerShell corridor follower 103, legacy coupled 97, trace receiver
16 groups, wide profile 68, corridor helpers 39 and legacy ground helpers 134.
An old-process capture was also rejected against the actual new KCD process.

The complete one-command fresh-world route then passed independently as controller
`123b870a55fe4ff1bdd40d64a8f45588`: 38 forwarded frames and native readbacks, maximum
actual X displacement 5.872m, camera error below 0.051m, 480 HUD frames, full
restoration and cleanup. The wrapper closed its owned KCD PID52588 normally;
no KCD or Minecraft client remained. Evidence:
`runtime/evidence/coupled-movement-20261029-215918-123b870a55fe4ff1bdd40d64a8f45588/verification.json`.

## Joined terrain with a fixed origin — STANDALONE ACTUAL-MINECRAFT PASS

Two overlapping wide captures now form one immutable 12×8m collision surface,
retaining the first capture's coordinate origin. Capture validates all 162 terrain
rays, stationary player, overlapping heights/normals, source snapshot, exact game
identity and both raw tile hashes. Minecraft builds the whole map before publishing
it and releases only its exact world/run/hash owner. Existing live bounds remain
unchanged; rolling replacement and live KCD following over the join are next work.

Real capture `5eb9ebb1940f49599ffd2b74e3ae9524` passed in KCD PID 41288, which was
then closed normally. Actual Minecraft run `bbbe7a8590f54996a14896d1a7e79e48`
passed on that capture: client/server walked 5.544m to X6.044 beyond the original
X4 edge, jumped/landed and returned within 0.063m. The standalone native receiver
accepted 321 real HUD frames, with 41 beyond the old edge and 23 during return.
No post-settle corrections; underlying vanilla cells remained air; both proxies
and held controls released. KCD compositing and physical input were not exercised.

Evidence:

- `runtime/evidence/ground-corridor-20261029-205630-5eb9ebb1940f49599ffd2b74e3ae9524/verification.json`
- `runtime/evidence/hud-stream-20261029-210115-bbbe7a8590f54996a14896d1a7e79e48/verification.json`

The first capture attempt timed out before sampling. Capture now performs bounded
readiness queries before its single module-load attempt and records preparation
failures. A synthetic actual run then stopped for client/server disagreement; the
first captured run crossed and jumped but stopped on an expired synthetic hold.
Corridor-only input backpressure and release-before-tick handling resolved those
specific failures without relaxing existing bounds. Original failed evidence is
retained. Passing focused checks: Java geometry/sequence 1827, mode 123, physical 383,
collision ownership 25; PowerShell capture 33, preparation 11, corridor proof 23 and
existing ground 134; Lua capture 8. No native addon change or manual test this turn.

## Wider-area gameplay and facing bootstrap — LIVE PASS

The user confirmed two combined runs worked in the same KCD2 process: the stone
appeared ahead, walking and top placement/breaks worked, inventory suppressed
movement, and walking resumed with the HUD visible. First run
`d2aece664fe444988e368d8d1b9860f0` passed156 movement frames/readbacks, restoration
and native retirement `generation=1 state=idle`:
`runtime/evidence/hud-walking-aimed-20261029-201902-52c493592de141e0b67dc87c5e97a35d/`.

Second run `2ed8bd8b0e6e4ea2aef1cf0ce3a01ae8` completed gameplay, wrote
`input_completed` and exited0. Its controller had already hit the112s limit,
roughly3s before that completion record arrived. It therefore withheld the
retirement proof, and native retirement reported `cleanup_timeout`. This confirms
same-process gameplay reuse, not final exhausted-state acceptance. Original failed
evidence is retained:
`runtime/evidence/hud-walking-aimed-20261029-202118-2cc13e07fda8437eb95a7a775735371a/`.
The separate `post-run-audit.json` passes nine existing retained-evidence checks,
including all156 readbacks, exact restoration, scenario completion and resource
cleanup. It preserves the original failure and grants no rearm authority.
Both games were closed normally afterward and the final expired arm archived.

The controller now permits up to5s of receipt-only waiting after trace completion,
aimed cleanup, stopped camera and native restoration. A117s limit measured before
the unchanged120s GPU lease preserves a3s restoration reserve; GPU restoration
also precedes JVM shutdown waiting. All238 focused controller checks pass.
Replaying the retained terminal and real result time fits a conservative budget
by906ms, although the old exact pre-budget timestamp was not recorded. No new live
retirement pass is claimed, and original input/freshness limits are unchanged.

## Facing bootstrap — IMPLEMENTED / COMPILED / MINECRAFT PASS

Wide walking/aiming now selects its initial owned stone support from the captured
footprint perimeter nearest a fresh validated host-camera heading. It retains
the existing height, reach, ownership and terrain protections. Narrow support
remains fixed at x2. The selected support and source heading are recorded in
`stone_bridge.build_support.selection`. No native repeat-session code changed.

The preceding live controller `0ee4decd20b24fe2b8bf35cb0208589c` registered F8 and
confirmed a native stone spawn, but the fixed eastward stone was outside the last
recorded view. Pressing F8 again cancelled normally; no crash or movement pass was
established. Evidence:
`runtime/evidence/hud-walking-aimed-20261029-195358-02a76a68a7334a3c94a6d6587267071b/`.

Actual Minecraft facing fixture `49ac63b83cfe43519c197ed0ca5e9c94` passed all six
vanilla block actions, walking, stationary inventory, resumed walking, complete
cleanup and source-hash verification. Its support was `(-1,63,4)`, with UP/NORTH
placement. Evidence:
`runtime/evidence/hud-physical-fixture-20261029-201042-49ac63b83cfe43519c197ed0ca5e9c94/verification.json`.
Optional standalone command:

```powershell
& './scripts/Test-HudPhysicalMovementFixture.ps1' -ExtendedWalking -WideWalking -AimedBlocks -FacingSeed
```

The first fixture `16494f36467843a0b4a2de33d46bf0a6` completed its six actions but
failed after Windows blocked a camera-file replacement. The fixture-only writer
now abandons that 100 ms-old publication and publishes a new sample on its next
update. Production's 300 ms reader allowance is unchanged. Java compilation,
ground-patch checks and physical-movement checks passed before the actual fixture.
The subsequent live runs above confirmed wider-area KCD composition and gameplay
reuse. Final native retirement acceptance remains pending.

## Repeat build startup — AUTOMATIC PASS

The installed repeat add-on loaded into a fresh pinned KCD2 process with its exact
module hash, successful registration, executable compatibility and HUD shader
compilation. The world reached RUNNING and a read-only 81-point terrain capture
passed. No arm file or accepted input/frame session appeared. The owned test world
closed normally. Evidence:
`runtime/evidence/hud-repeat-startup-20261028-25139366d6ed4d678c606c774269f31b/verification.json`.
The initial tail-only readiness observer missed the load marker amid log output;
the full fresh log plus terrain readback verified readiness instead. This confirms
startup only; live controls, composition and two-session retirement remain pending.

## Repeat-session installation — VERIFIED, LIVE ACCEPTANCE PENDING

With both games closed and no leftover arm files, the guarded updater verified
both six-file bundles, disabled the owned proxy, installed the staged repeat
add-on and re-enabled the proxy unarmed. Installed-profile verification passed
without further changes. Receipt:
`runtime/evidence/hud-update-20261028-182335-a328f8eca0994dd0927935076feb99e2/update.json`.
Both games were closed at that checkpoint; no new live result was claimed. NEXT_SESSION.md starts
with the exact launch commands and two-session acceptance steps. No new launcher
or repeated game test was needed for this preparation.

## Larger area — SCRIPTED TWO-GAME MOVEMENT AND COMBINED MINECRAFT PASS

The existing coupled harness now supports `-WideWalking`, retaining explicit
scripted provenance, authenticated live terrain, original deadlines and restoration.
Run `6615c9eb30984caa91463af12a5e5ac6` passed: 3.018 m client/server movement,
jump/landing, 25 forwarded poses, 24 confirmed KCD player/camera updates, restored
position and frame cap. Evidence:
`runtime/evidence/coupled-movement-20261028-173613-6615c9eb30984caa91463af12a5e5ac6/`.

Wide walking also supports `-AimedBlocks` in the actual Minecraft fixture. Run
`0c33d84d3f504c638765c9a9b3d74535` used the captured KCD terrain and passed 2.587 m
walking, six top/side placement/break confirmations, inventory suppression, resumed
walking, 71 walking HUD frames and complete cleanup. Imported terrain was unchanged;
source hashes matched. Evidence:
`runtime/evidence/hud-physical-fixture-20261028-174140-0c33d84d3f504c638765c9a9b3d74535/`.
The initial combined run exposed a diagnostic screenshot limit at cleanup; the
validated combined fixture now permits exactly its nine known stages, retaining
the existing eight-state limit for other modes. Focused Java, Lua and PS checks
pass. Both games closed normally; no installed addon or persistent setting changed.
Physical input, KCD HUD composition in the wider area, and the two-session addon
still need their batched live acceptance. These scripted results do not establish
continuous free roaming or those remaining checks.

## Larger fixed walking area — IMPLEMENTED / COMPILED / MINECRAFT PASS; KCD LIVE PENDING

Optional `-WideWalking` connects an 81-point KCD capture to Minecraft collision,
physical HUD input, trace admission and the KCD follower. The captured footprint
is 8×8 metres with a four-metre radial movement limit; default sessions retain
their previous area. Explicit area selection and matching receipts are required
throughout. Existing timing, vertical, inventory and restoration limits remain.
Combined aiming moves its owned support outside the larger imported terrain.

Automatic Minecraft fixture `997f5dd5373e46a1bccd7a0d954211d1` passed: client and
server each reached 3.234 metres, beyond the old two-metre limit; five input pulses,
72 walking HUD frames, zero inventory displacement, later movement and complete
cleanup. Evidence is in
`runtime/evidence/hud-physical-fixture-20261028-170749-997f5dd5373e46a1bccd7a0d954211d1/`.
No physical input or KCD composition is claimed by this fixture. Focused Java
checks (ground1567/physical345), Lua checks (ground16/movement90), wide PS checks58
and relevant existing controller/fixture checks pass. KCD was not launched; no
installed addon was changed. Live larger-area acceptance remains pending, and
continuous terrain streaming remains unfinished.

## Repeat sessions — IMPLEMENTED / COMPILED / OFFLINE VERIFIED; LIVE PENDING

The opt-in walking-repeat addon now integrates the existing two-generation policy:
fresh channels, queues, input gates and diagnostics; render-thread hide/capture
retirement; retained same-size GPU resources without a new GPU wait. Native input
faults, failed cleanup, stale identities, changed image size and a third session
cannot rearm. Controller completion is hashed and bound to the old arm/process;
the next explicit invocation archives that arm only after the native retirement ACK.
Existing installed artifacts and the frozen walking-aimed profile remain intact.

Built the new addon and staged `runtime/hud-compositor-walking-repeat`. Targeted
native input/movement/world/rearm tests pass. Controller checks179, repeat checks33
(including retained actual successful-run evidence), and profile checks155 pass.
These establish compilation and automated behavior, not a live two-session result.
No games were launched or installations changed for this work.

## First-use admission warm-up — OFFLINE PASS, LIVE COMPARISON PENDING

`Initialize-HudWalkingAimedAdmissionWarmup` now exercises the real snapshot reader,
foreground query and settled policy before Minecraft launches. It uses a separate
create-new `diagnostic-aim-view.json` and disposable synthetic policy state; query
results are discarded. It grants no authority, creates no permits or clicks, sends
no HTTP and never writes the live view path. Existing input clocks and limits stay
unchanged. Bounded per-click timing fields now separate selection, final admission,
send and total processing, including rejection/error paths, without per-click file IO.

Focused warm-up15 and controller179 checks pass. Retained offline measurements:
`runtime/evidence/hud-aim-admission-offline-20261028-161412-d64f9fe773c4410f80ae35f279f3e7c0/warmup-comparison.json`.
Snapshot first/repeated calls cost24.9087/1.7074 ms; settled policy56.2046/1.1871 ms;
foreground1.9812/.0408 ms. These are isolated startup/function measurements, not
game-input latency or proof that the live first-click failure is fixed. The latest
live comparison below predates this warm-up and remains failed.

## First-click comparison still expires; cleanup cutoff reached — FAILED

HUD `1ec548ae2a1f4e42b60c54c79ab3b771`, probe `18efa61cbae141d383077103d1a3c324`:
`runtime/evidence/hud-walking-aimed-20261028-160030-18efa61cbae141d383077103d1a3c324/`.
This comparison includes the duplicate-admission removal below. The first click
still gets stale result 3 before reaching the HUD arena. Controller observation to
dispatch takes 132 ms (physical edge to dispatch 176 ms); the second takes 33 ms and
places successfully from the same position. The subsequent break also succeeds.
The user confirms second-attempt placement without stepping back, then reports
that the HUD disappeared after breaking the added block.

The original seed remains when the existing 12-second aim cutoff closes. Closure
reports owned_count=1 and incomplete guest/support cleanup; the controller therefore
fails and stops the relay/HUD. It forwards 125 movement points, restores KCD's player
through failure cleanup and receives native removal/authority-cleanup acknowledgment.
Minecraft saves and exits with code 0; the complete scenario did not pass. Preserve the earlier
full side-face pass separately. No input lease or cutoff was enlarged. First-use
processing is under automated investigation; no latency improvement is established.

## Combined side-face placement, inventory and resumed walking — LIVE PASS

HUD `557a41b52b7142bfa9fd98e999074f08`, probe `af23ad5d4c154c0b8de845fee2508f9a`:
`runtime/evidence/hud-walking-aimed-20261028-154714-af23ad5d4c154c0b8de845fee2508f9a/`.
`SideFaceInventory` passes 156/156 movement updates and KCD readbacks, WEST-face
placement, added-block and seed breaks, inventory suppression and resumed walking.
The inventory window lasts 1994.2718 ms with 209 observations, zero client/server
displacement and a subsequent accepted S step of .222952 m on both sides. There
are 665 camera samples with no worker failure, full aimed/support cleanup before
follower restoration, zero remaining owned stones and Minecraft exit 0. Native
input closes normally at its 30,000 ms activation limit with 27/27 events acknowledged.

The user confirms it worked, but needed another placement click after stepping
back. Request 1 / permit 47 was rejected as stale (`input_unavailable`, result 3),
with permit-derived capture age 505.5376 ms against the existing 500 ms limit;
`vanilla_queued=false`. It never reached Minecraft's placement/collision check.
Request 2 / permit 75 placed successfully at age 303.225 ms, followed by two
confirmed breaks. Thus this proves the completed side-face sequence, not reliable
first-click placement. The user's feedback is separate from primary machine flags.

The retry includes the camera snapshot reader repair and exact prompt-deadline
metadata. Java maps the existing monotonic stream start to UTC once; controller
READY output reports absolute deadlines. `Read-HudInputPromptWindow` re-reads
identity, liveness and the current clock before a human prompt, preserving the
existing controller margin and all gameplay/freshness limits. It rejects legacy,
expired or too-short metadata. It does not claim to observe F8 activation itself.
The fresh pre-prompt check returned 32 seconds, and the user was offered 20 seconds.
Prompt checks29, controller checks159, Java compilation and inventory checks35 pass.

## First-click processing reduction — AUTOMATED PASS

The earlier side-face run's first click was captured at 15:48:20.006, observed by
the controller at 20.093 and dispatched at 20.196 UTC. Its permit was already
installed at 19.910. The 505.5376 ms guest value measures original permit-derived
age, not physical click age; the click itself spent 190 ms before dispatch. There
is no per-function timing evidence attributing all 103 ms of controller processing
to one check.

`Invoke-HudWalkingAimedClicks` performed the same settled/foreground admission
twice consecutively. It now performs it once in the sender's final BeforeDispatch
callback, preserving exact owner checks, original edge/permit timestamps and the
subsequent 250/350/500 ms freshness bounds. No denied edge is retried. Controller
169, relay 165 and permit 23 checks pass, including expiry during final admission
with no HTTP dispatch or intent recorded. This removes duplicate work; live
comparison results must establish whether first-click responsiveness improves.

## Repeatable session lifecycle — STANDALONE PREPARATION

`kcd2/hud/rearm_policy.hpp` now defines a single-owner policy for at most two
explicit sessions in one game process. A second session requires generation-bound
closed-input acknowledgment, empty event queues, retired renderer ownership,
released/drained mouse capture, producer exit and verified controller cleanup.
Replayed identities, changed image dimensions and incomplete retirement are
rejected; session failure prevents rearm. Owner snapshots are values, so an old
callback cannot silently inherit a later generation through a reference alias.

The dedicated `hud_explicit_rearm_policy` CTest builds and passes 363 assertions,
including setup assertions; independent review found and corrected the alias
hazard. This is not connected to any addon, arm script or live profile. KCD still
needs restarting between current tests. Integration requires generation-owned
worker/channel state and renderer retirement without a render-thread GPU wait.
Existing one-shot profiles and installed artifacts are unchanged.

## Side-face retry received a stale activation prompt — INCOMPLETE

HUD `ee5f7e5f0b704689ba94acec6ca987b9`, probe `5fa3810b938b4ff1bcd83158945b51b5`:
`runtime/evidence/hud-walking-aimed-20261028-153111-5fa3810b938b4ff1bcd83158945b51b5/`.
The controller's buffered READY line still advertised 42 seconds when retrieved
at 15:32:36 UTC. The user prompt was sent at 15:32:44.138 and promised 35 seconds,
but the guest ended its activation wait at 15:32:47.550: only 3.412 seconds later.
The user pressed F8 immediately, saw the hotbar, then saw it disappear after W.
This was an invalid test opportunity, not evidence of a new gameplay crash.

The guest records `waiting_60s_complete`, no accepted input or movement, and
normal Minecraft exit 0; KCD remained alive. There were 823 camera samples with
no camera worker failure. `user-feedback.json` preserves the user's observation;
`prompt-timing-diagnosis.json` matches the chat's question timestamp to native
closure, and `reshade.log` preserves the original native receipts. Primary machine
visual flags are unchanged. Do not infer successful side-face play from this run.

## Computer Use keyboard attempt did not activate the bridge — INCOMPLETE

HUD `8e968faa4bf340209f2c8b838d40de94`, probe `bd53c4362e0646b28c6540363e4a152e`:
`runtime/evidence/hud-walking-aimed-20261028-151957-bd53c4362e0646b28c6540363e4a152e/`.
This retry selected the default `WalkingBreak` scenario. Computer Use's
`@oai/sky` `press_key` calls returned for F8 at UTC-ms 1793200869912 and slot 2 at
1793200886465, but neither registered in the HUD input bridge. The guest finished
with `input_cancelled` / `waiting_60s_complete`, zero applied input events and
`host_armed=false`. There were 811 camera samples, zero forwarded movement points
and no started movement; Minecraft exited normally with code 0.

No camera snapshot read failure occurred in this run. Because the bridge never
activated, this is not a completed walking test or a live validation of the reader
repair during movement, and it supplies no side-face evidence. The reason the
keypresses did not register is undetermined. Computer Use has successfully closed
and relaunched the test games, but autonomous gameplay controls remain unverified.

## Combined side-face attempt stopped on a camera snapshot read — FAILED

`SideFaceInventory` run `aee7bfb17fa54dc18a665f767468af67`, probe
`0c7a45dd698f49ec990a414dfb3dc028`, evidence:
`runtime/evidence/hud-walking-aimed-20261028-150753-0c7a45dd698f49ec990a414dfb3dc028/`.
The controller's `Get-Content` read of `host-view.json` in `HudGroundMovement.ps1`
failed with a Windows sharing violation. Only 74 source points were forwarded and
70 delayed readbacks were retained; this is partial movement evidence, not a
successful side-face scenario. Failure cleanup restored KCD's player and stopped
the relay. Minecraft reported the stream failure, saved and exited with code 0;
KCD remained alive. The user reports **“didnt do anything just crashed.”** That
observation is saved separately in `user-feedback.json` without changing the
primary failed receipt.

A narrow snapshot reader using `FileShare.ReadWrite | FileShare.Delete` is now
implemented, with **138 camera checks and 159 controller checks passing**. It has
not yet passed a replacement live walking/side-face test. This read failure is
separate from the earlier fixture's exhausted 100 ms camera-file **replacement**
retry budget, whose lock holder remains unknown.
The successful top-face milestone below remains valid; side-face live coverage
is still pending.

The immediately preceding attempt,
`runtime/evidence/hud-walking-aimed-20261028-150658-1332a14ecd05467a9d707a9c19bb7dd0/`,
timed out on the debug HTTP request during probe initialization, before compositor
arming or the controller START message. Its folder contains only
`movement_probe.lua`; it is not a gameplay trial. Bringing KCD to the foreground
allowed the subsequent controller to initialize. These failures do not establish
a new input or face-targeting defect.

## Combined top-face placement, inventory and resumed walking in KCD2 — PASS

`TopFaceInventory` passes with HUD `17311ef5fda841d6869e9cbe3484af1f`, probe
`6a7cde05c377471e9c7b92bcfb091222`, evidence:
`runtime/evidence/hud-walking-aimed-20261028-150034-6a7cde05c377471e9c7b92bcfb091222/`.
The user confirms **“all worked!”** All **155 source points and delayed native
readbacks** match. Actual vanilla client/server records confirm a non-bootstrap
placement against the seed's UP face, removal of the added upper block, and seed
removal. Owned stones and support are cleaned up before follower restoration;
the client exits normally with code 0.

The actual inventory window lasts **1,850.4451 ms**, with 194 fresh observations,
zero client/server displacement and zero movement bindings. A fresh S press after
closing reaches the actual vanilla binding; both Minecraft sides then move
**0.859955 m**. Machine evidence records the face-action sequence and this separate
inventory/resumption interval. It does not timestamp block actions relative to
inventory, infer an OS keypress from a missing packet, or set visual proof flags.
The user's physical-control and display confirmation remains separate. E can open
and close inventory; Escape is not required for this check.

The combined controller now accepts explicit verification scenarios:
`WalkingBreak` remains the unchanged default, `TopFaceInventory` requires the
seed's UP face, and `SideFaceInventory` requires WEST. Each enhanced scenario
requires the added-block break, seed break, empty ownership/support cleanup and
an inventory interval followed by actual resumed walking. Side-face live coverage
is pending. Scenario selection changes proof requirements, not the renderer,
movement authority, leases or session duration.

`HudMovementInventoryEvidence` observes actual client screens, bindings and fresh
client/server positions only in the combined live/fixture modes. Its bounded
receipt retains at most four windows and 32 delivered movement edges. Verification
requires a naturally closed window of at least 250 ms, at least three fresh
observations and two server-sequence advances, grounded positions within .01 m,
no stale observations/nonzero bindings, and at least .05 m of actual client/server
movement after a new accepted post-close walking edge. A native-filtered W press
inside inventory is absent from the guest stream and is not invented as evidence.

The same collector also passes in actual standalone Minecraft run
`8fe454e8df144b17a0bc2a0b949e0c1d`, evidence:
`runtime/evidence/hud-physical-fixture-20261028-145757-8fe454e8df144b17a0bc2a0b949e0c1d/`.
All 95 pinned source hashes match. Supplemental `inventory-verification.json`
verifies two windows of 782.7226 ms and 803.7647 ms, both with zero drift and
subsequent client/server walking. Scripted inputs and synthetic host rays remain
explicit; this fixture does not prove KCD compositing or physical input. The 35
collector checks and 159 controller checks pass alongside the existing physical
and aimed checks. The 200 ms buffer, sampled terrain, 15-second movement session,
12-second aim cutoff, completion tail and 30-second HUD lifetime remain unchanged.

## First combined physical walking, aimed break and HUD in KCD2 — PASS

HUD `179b92e699de495880dec7d6f6ac7449`, probe `8cdbdbd02281412a86fb584a0dd9eab1`:
`runtime/evidence/hud-walking-aimed-20261028-142552-8cdbdbd02281412a86fb584a0dd9eab1/`.
User confirmation: **“Done, worked perfectly.”** The session performs a real W step,
settled aimed left-click removal, then an S step with the hotbar visible. Minecraft
and native KCD records confirm all 156 movement waypoints/readbacks and the one
network break; the bootstrap placement and break leave zero owned stones.

Guest movement 15,505ms, 158 trace records, maximum walk .847736m, zero post-settle
corrections. Two boundary pauses/one resumption retain the sampled-ground limits.
The stream published 909 HUD frames; 806 camera samples were fresh. Owned support
cleanup performs exactly two separate writes (BEDROCK setup/AIR removal). Aiming
closes before follower restoration, with both independent native input and engine
cleanup acknowledged; the follower restores, GPU cap restores, proxies/input/mappings
release, and Minecraft exits 0. Primary machine receipts retain visual_verified=false;
the separate user-feedback receipt records the human observation without rewriting them.

The new frozen compositor profile combines protocol 2 physical input and selective
world clicks in `MineComeHudWalkingAimed.ini`. Java pins the build support/patch/save,
withholds walking until vanilla bootstrap confirmation, requires fresh neutral
grounded client/server and mapped host agreement, stops new aiming 12s after first
movement, drains pending vanilla work, and emits identity-bound readiness/closure
through the evidence writer. The controller requires 200ms settled samples and exact
camera sequence correlation, consumes declined edges once, uses 150ms intent dispatch,
and stops the relay asynchronously before follower finish. Failure cleanup revokes
known aimed authority before ending movement. Older profiles stay separate.

The optional native external-pose mode reuses original walking camera receipts,
validates run/sequence/engine time/freshness and sends zero additional SamplePose
calls. It does not rebase rays, widen .25m eye tolerance, modify Lua or change the
200ms playback buffer. Five related native tests pass, including old relay modes
and an external-pose synthetic real-wire test. Java build/assemble, 24 new gate checks,
336 physical checks, 26 writer checks pass. New combined controller 77/profile 147
checks plus existing fixture 196/relay 165 and renderer/profile regressions pass.

Lifecycle review caught and fixed the unstarted `-1` movement timestamp being
mistaken for a cutoff; regression coverage includes that case. Stream metadata
explicitly marks scripted_input=false only for the new combined live mode. The
owned bundle update completed at
`runtime/evidence/hud-update-20261028-142142-ac73673d4aad41d4a94522d1bd2829e4/`.
Combined top placement/inventory is verified in the later milestone above.
Remaining: combined live side coverage, longer/persistent sessions and real terrain
placement. This is a verified bounded milestone, not a final retail build.

## Walking, aimed blocks and HUD together in actual Minecraft

**Earlier guest milestone: source implemented, compiled and standalone verified.**
`Test-HudPhysicalMovementFixture.ps1 -ExtendedWalking
-AimedBlocks` runs one owned world with fixed initial alignment: vanilla bootstrap,
W/W/S walking, top placement/upper break, west placement/west break, seed break,
inventory suppression, then resumed W/S movement. All six block actions have real
client and integrated-server confirmation; movement uses vanilla controls.

`HudBuildRegion` keeps imported collision cells and the fixture support out of
mutable ownership. `AimedStoneArena` applies the optional policy at selection,
queue, dispatch and server precheck while retaining its confirmed-stone ledger
and eye/reach checks. `GroundCollision.matches` binds the helper to the installed
world, patch run and hash. One BEDROCK support setup and cleanup write are recorded
separately from the arena's zero direct block writes. Actions require fresh,
grounded client/server agreement within .01m, neutral controls, horizontal speed
below .03 and bounded vertical residual velocity. Normal cleanup verifies edited
cells AIR, unchanged imported cells, support restoration, proxy/control release
and normal Minecraft exit.

Actual flat run **PASS**: `b5f250088e4841088fffebef1ea8cdb0`, evidence
`runtime/evidence/hud-physical-fixture-20261028-135417-b5f250088e4841088fffebef1ea8cdb0/`.
Duration15,504ms,158 trace records,259 UI frames including14 during aimed actions,
five pulses/six confirmed actions,1.498988m maximum walk and zero corrections.
Movement before and after interactions is .641819m each. Complete receipt36,537bytes.

Actual captured-terrain run **PASS**: `61868402650549db9387657daf1b8065`, evidence
`runtime/evidence/hud-physical-fixture-20261028-135545-61868402650549db9387657daf1b8065/`.
Duration15,508ms,158 records,258 UI frames including15 during aimed actions,
five pulses/six actions, .637031m maximum walk and zero corrections. Movement before
interactions .220139m, after .641819m. Complete receipt37,435bytes. The original
`ground-patch-20261028-131456-9f4aeb95285b4f3bbff56bc8c8f345e8/ground-patch.json`
hash remains `93e1ced12e3f5340b2337fabeee885513055e42a76b9eb188485125967a4c23c`.
Both runs verify zero inventory displacement, full cleanup and all92 source hashes.
Both use synthetic host rays; neither claims KCD compositing or physical input.

Validation: compilation/assembly;96 build-region checks;336 physical-mode/input
checks;196 fixture receipt/profile checks;26 evidence-writer checks. Existing
actual Minecraft aiming also passes all28 scenarios after the arena change:
`runtime/evidence/aimed-stone-20261028-133833-c360373cce28416593baaaae60138c25/`.

Two failed trials are preserved. `9e80ade840a24a25ab9b5732cf797c77` confirms six
block actions but stops before resumed walking when camera-file replacement is
denied for100ms. The lock holder is unknown; a scratch concurrent-reader test saw
transient denials but no exhausted retry budget. The unchanged retry
`6038039bc41144e4ace15a2ca72611a8` completes movement but exceeds the64KiB pretty
JSON result limit. Combined-only compact JSON now preserves all fields and explicit
nulls within the unchanged64KiB limit. Legacy formatting remains unchanged. Neither
failed trial counts as a full PASS; camera code has not been changed speculatively.

The later live milestones above use a dedicated controller/compositor capability,
settled host playback before issuing an aim permit, and revocation before native
movement restoration. The .25m eye tolerance is unchanged; rays are not rebased and
no second high-rate pose sampler runs beside the walking camera requests. The
verified live walking profile and 200 ms buffer remain unchanged.

## Optional 15-second walking mode

**Live PASS:** HUD `a673494c0d084564ac3c83e3fdcdd47d`, probe
`e50b03b5a7eb4f1c92b58f42d3da012b`, evidence:
`runtime/evidence/hud-walking-20261028-131455-e50b03b5a7eb4f1c92b58f42d3da012b/`.
All **156 forwarded source points and 156 delayed native readbacks** verify.
Guest duration is 15,560 ms with 158 trace records, client/server walk 0.606181 m,
zero corrections and three boundary pauses/two resumptions. All 611 camera views
are fresh; normal restoration, camera/resource cleanup, FPS restoration and Minecraft
exit pass. The user confirms "worked. still delay, but worked." This repeat used
W/S near the start and again after eight seconds; inventory evidence is separate.

Derived `timing-analysis.json` preserves seven source hashes. Four W/S/W/S presses
pair to actual bindings; the last two arrive at 5.90 and 6.81 seconds after the
first. Median producer capture-to-receipt is33 ms and receipt-to-binding0.1289 ms;
these are not hardware/display latency. The trace is121,488 bytes, native history
174 receipts; exact restoration occurs at15,815.24609 ms after129 writes including
restoration. All retained readback errors are zero; maximum segment observation
gap17.1814 ms. The original fixed200 ms playback buffer remains unchanged.

Implemented explicit `-ExtendedWalking` on the walking starter/controller and
standalone fixture. Short mode remains the default. The extended profile uses
15 seconds of input plus one second settling, 16-second source timestamps,
an 18-second native deadline, 2,047 ordinary writes plus restoration, 256 native
receipts and a 256 KiB trace. The 200-record ceiling and existing freshness,
geometry, input, fixed 200 ms buffer and restoration checks remain. Matching
session markers and distinct source kinds reject cross-profile evidence. A first
movement press must arrive within 12 seconds after F8 so completion fits the
unchanged 30-second HUD lifetime. Inventory and boundary pauses cannot renew it.

Validation: Java compilation/assembly; 327 input checks; 1,547 ground/trace checks;
87 Lua cases; 101 buffered controller checks; 149 physical receiver checks;
87 parser warmup checks; 80 append-only/coupled checks; 97 fixture receipt checks.
The Lua harness traverses a full 16-second source timeline with 161 delayed ACKs,
more than 511 writes and exact restoration. It also tests lease/deadline/source/
sequence/spatial/write/receipt limits and module reload for both new and older
active followers. These Lua checks use a harness, not a live game.

Actual Minecraft fixture `e0636c8c8087435588172cfe5513d343` passes in
`runtime/evidence/hud-physical-fixture-20261028-130405-e0636c8c8087435588172cfe5513d343/`:
five W/W/S/W/S pulses, inventory reopened after six seconds and held still,
later walking, 15,593 ms duration, 159 trace records, 255 real HUD/inventory
frames, client/server maximum walk 1.498988 m, zero corrections and normal exit.
This fixture does not arm the compositor or call KCD2.

An additional automated Minecraft fixture uses numeric samples from the actual
KCD terrain capture: `e13eb8ecdd1e4f69b4b12d740e1d92cf`, evidence
`runtime/evidence/hud-physical-fixture-20261028-131809-e13eb8ecdd1e4f69b4b12d740e1d92cf/`.
It passes all five pulses and the reopened-inventory checks:15,517 ms,158 records,
252 UI frames,0.637031 m client/server maximum walk,zero corrections,4 boundary
pauses,12 reopened-inventory frames and zero inventory movement. It preserves
original capture hash `93e1ced12e3f5340b2337fabeee885513055e42a76b9eb188485125967a4c23c`
while explicitly labelling the copy as a standalone fixture. It is not additional
live KCD proof. Legacy receiver16 cases and movement-path23 checks also pass.

First live extended attempt: HUD `3641392e225c4629a1fadabf05a996f3`, probe
`a3735cb0c58f4ab6919ea481215ba453`, evidence in
`runtime/evidence/hud-walking-20261028-130751-a3735cb0c58f4ab6919ea481215ba453/`.
The user reports "all worked fine", including later walking, inventory and HUD.
The recorded run is **not a full PASS**: KCD lost foreground focus 13,515 ms after
activation, ending input after about 11 seconds of movement. Native evidence
records `eligibility_lost`, foreground false, with fresh ACK and HUD publications.
Guest trace ends STOPPED; controller rejects incomplete movement. 109 sources
were forwarded, 106 had delayed ACKs before cleanup; restoration, camera shutdown
and FPS restoration succeeded. Original failed verification and post-run logs are
preserved. Its consumed arm was archived after normal Alt+F4 closure; the repeat
above passes full completion without code changes.

Walking plus aimed placement is still separate work. The current walking world
uses collision-only terrain and AIR-cell checks; aimed bootstrap expects a solid
Minecraft support block. The walking compositor also lacks world-click capture.
Integration needs an explicit owned-block/terrain contract and a settled-position
click barrier for the 200 ms host lag, preserving the existing eye/reach checks.

## Latest live PASS: earlier input and first-step descent

The user confirms **"it worked this time, but there is still a little delay."**
HUD `477d2e51c02a4c4fbd61815bcb45a7c2`, probe
`b850ba28250a4a0f8e90edb611996d89`, passes 57/57 source transfers and delayed KCD
readbacks in `runtime/evidence/hud-walking-20261028-124409-b850ba28250a4a0f8e90edb611996d89/`.
Normal `explicit_end` restores the exact origin with zero error after 167 writes
including restoration and 5,865.31 ms. All 467 camera publications are fresh;
timers, camera resources, FPS and Minecraft clean up normally. Maximum client/server
walk is 0.594361 m with zero corrections and four boundary pauses/resumptions.
The user verified slot 2 selection before moving. No inventory opening was tested.

New timing evidence pairs five accepted W/S/A/D/W presses to actual pre-vanilla
bindings: producer capture-to-receipt UTC delays 56/3/17/7/16 ms (median 16),
receipt-to-binding JVM delays 8.8987/0.1413/0.0837/0.1114/0.0865 ms (median 0.1114).
All five pair without cancellation or ambiguity; 16 edges/25 binding states are
untruncated. Three later presses are correctly blocked after five seconds.
First source capture-to-dispatch is 56 ms, subsequent median 17.5 ms.
`timing-analysis.json` includes original rows, six source hashes and methods.
Capture is the input producer's observation, not physical key actuation. These
are not native application/display latency or a measured before/after comparison.
The deliberate 200 ms playback buffer remains the largest known fixed delay;
keep this stable baseline while extending walking and integrating interactions.

Two earlier attempts this round remain failed historical evidence. `4a7fb2...`
never activated: native/guest both recorded zero input events, no movement trace
or forwarded positions, and normal guest timeout. The user's "almost no delay"
report from that attempt cannot establish integration performance. Its camera
request executed but returned no sample; the rejection reason was not recorded.
The request now emits a separate bounded, JSON-safe rejection receipt with exact
run/sequence, and the worker reports the reason promptly. Rejections never publish
views, retry or renew leases. Tests: camera delivery 72, receipt cursor 75, exact
generated Lua wrapper 33, all passing.

`6cd20f...` activated and received W, but its first motion sample was airborne on
a small descent. The validated grounded SETTLING anchor had not established
receiver ground provenance, so seq 3 became `observe`; the controller stopped
camera delivery and the guest's camera lease then expired. Native writes were
zero and the actor remained at the origin. Buffered physical mode now establishes
ground provenance from its fresh exact supported anchor; stale/invalid anchors
and legacy profiles retain previous behavior. Tests: physical receiver 137,
warmup 86, buffered proof 79. Read-only replay at the original recorded validation
times accepts seq 1–3 as begin/sample/sample. Original failed receipts are unchanged.
The controller also reports refused sequence/phase/kind instead of an ambiguous
expired-or-unsupported error. This repair and the earlier START phase are exercised
by the latest full live PASS above.

Current state: KCD PID 9224 remains open, Minecraft closed normally, `b850ba...`
arm consumed. Both failed arms and the prior `38d11...` arm are archived. Escape
stopped Computer Use this turn. The handoff has exact future cleanup/start commands.

## New input-phase repair: compiled and standalone verified

Physical input used to be consumed at the end of Minecraft's client tick, while
movement KeyBindings were written at the next tick's start. `HudStreamLab` now
consumes the complete ordered physical/UI queue at START before vanilla polling.
The standalone physical fixture uses the same phase; other HUD profiles retain
their original END path. Ownership, freshness, deadlines, inventory suspension,
post-tick server observations and cleanup remain enforced. This removes the
mandatory extra client tick in source. This was first verified standalone below;
the subsequent live result is recorded above.

Actual Minecraft run `cf2fbd1c64b347d8951a27545f9e146b` passes the updated verifier:
`runtime/evidence/hud-physical-fixture-20261028-121745-cf2fbd1c64b347d8951a27545f9e146b/`.
It performs three W/W/S pulses, holds both client and server still in inventory,
publishes 106 real HUD frames, and completes 58 trace records in 5,562 ms.
Client/server maximum walk is 1.498988 m with zero corrections. Proxies, camera
worker and controls release and Minecraft exits normally. Original scripted
receipt-to-KeyBinding delays are 8.9611/0.2784/0.2117 ms, from the shared JVM clock.
No native input mapping, KCD commands or renderer arming occurs in this fixture;
these are not physical input-to-display measurements.

Bounded `physical_movement.input_timing` now retains original capture UTC,
receipt monotonic/UTC time, accepted-down decisions and actual binding snapshots.
Movement-edge watermarks do not imply every consumed edge affected vanilla;
batched down/up can cancel. Diagnostics never drive movement or renew leases.
After the fixture, retention was capped at 32 entries per series with explicit
truncation/full counters. Its 8 events and 12 states fit that cap. Worst-width,
nested pretty JSON remains below 24 KiB, leaving at least 40 KiB of the stream
receipt for existing evidence. Final Java24 compilation, `assemble` and 299 physical-input
checks pass, including signed-clock, cancellation, export mutation and byte-bound
cases. The earlier 200 ms native buffer and working installed bundle are unchanged.

The user requested automated work only this round. Both games are closed; the
expired `38d11...` arm is now archived by its ownership receipt. The next human
comparison should assess this phase change and collect the new timing evidence,
without rerunning the already passed baseline below. See the updated handoff.

## Latest live result: walking and HUD pass with normal completion

The user reports **"still delay, but smooth"**. HUD run
`650a8e00939c4831981f75828b79ff62`, probe
`38d11f6a4fb943348636cef27b855de9`, passes fully:
`runtime/evidence/hud-walking-20261027-181108-38d11f6a4fb943348636cef27b855de9/`.
The controller exits 0 with 56 forwarded sources and 56 valid delayed readbacks.
Native `explicit_end` returns the actor to the exact origin, with zero error and
cancelled timers, after 137 writes including restoration and 5,830.59 ms.
All 588 camera publications remain fresh, camera resources close, FPS restores,
and Minecraft completes its trace and exits normally. Client/server maximum
walking distance is 0.594376 m, with four boundary pauses, three resumptions and
zero corrections. This run does not open inventory; that earlier evidence remains
separate.

The native path retains 80 readbacks, each one frame after its write: median
16.113 ms and maximum 16.960 ms, with zero position errors and no intermediate
source holds. First source capture-to-dispatch is directly measured at 50 ms;
later captures take median 20 ms (8–34 ms). First sample validation, preparation
and HTTP request cost 4.936/10.227/18.649 ms; the parser warmup costs 744.634 ms
before arming. Source capture intervals are median 100.381 ms/max 133.976 ms,
versus 100.916/166.572 ms in `fa370...`; actual server-source maximum gap falls
from 201.099 to 151.432 ms.

Conditional camera-clock alignment estimates first capture-to-native acceptance
at 68.4 ms versus 123.8 ms previously, and first actual position write at 279.3 ms
versus 333.9 ms. Those separate-run estimates include cached-frame uncertainty.
No physical key capture/application or display timestamp series is available;
this is not a measured key-to-photon improvement, nor proof that warmup or cadence
alone caused it. `latency-analysis.json` preserves the methods, original calibration
rows, source hashes and comparison limits without changing the primary PASS.

Implementation `d150024667683ce6366f4800528528d8b9ab9f0b` (fixed sampling) on
`c90da08973da9db54ad2c7a1c94d2def1b34cec0` (warmup/native finish) is now exercised
in a passed combined physical test. Keep the intentional 200 ms buffer: this
run's reconstructed right-point requirement is 97.812 ms, but earlier replay
`477...` requires 188.903 ms. A blanket 150 ms setting would underrun that earlier
trace. The next work is remaining latency measurement/tuning or longer walking
and integration with the already working aimed-block controls, not repeating
this passed comparison.

At that baseline's completion KCD PID 50636 remained open with its arm consumed.
It has since closed and the exact `38d11...` arm has been archived. The previous
`2dd6...` arm is already archived too. Recheck current process/tool state before acting.
The concise [NEXT_SESSION.md](NEXT_SESSION.md) contains exact commands and limits.

## Earlier implementation and evidence

**Additional offline implementation:** `MovementTraceSink` now anchors ordinary
HUD_PHYSICAL/HUD_PHYSICAL_FIXTURE publication to 100 ms slots from the first
successfully written sample. Late callbacks skip elapsed slots instead of moving
all subsequent deadlines. Actual capture/server timestamps remain untouched;
there are no synthetic catch-up records. Forced initial/final samples still obey
freshness and sequence checks, and physical timestamps must advance strictly.
Clock overflow is rejected before schedule state changes. Legacy GROUND and
HUD_COUPLED spacing remains unchanged.

Java24 `compileJava`, `groundPatchTest` (807 checks, including the trace cases) and
`hudPhysicalMovementTest` (282 checks) pass without launching either game.
In the deterministic synthetic six-second jitter test, legacy scheduling emits
59 samples and accumulates 155 ms drift; the fixed schedule emits 60 with maximum
55 ms lateness, within the test's 56 ms maximum callback interval. This measures
scheduling only, not physical keypress or display latency. Full six-second
initial/ordinary/forced-final/termination tests with 128-character run identifiers
and long double fields fit 57,069 bytes for physical and 57,699 for fixture traces:
61 samples, 63 records, intact 2 KiB end reserve and unchanged 64 KiB/200-record
limits. Independent review found no blocker. The 200 ms playback buffer and all
native limits are unchanged. The subsequent passed live comparison above records
actual cadence; it does not attribute the improvement to scheduling alone.

**Previous physical run: smoother movement, but the original normal-finish
verification failed.** The user reports that it worked and
was "a lot smoother", with a delay between keypress and movement. HUD run
`fa370b398a9243e69ee15924cf777c4d`, probe
`2dd6df695d15485cb84082793245d970`:
`runtime/evidence/hud-walking-20261027-165506-2dd6df695d15485cb84082793245d970/`.
All 52 forwarded sources receive 52 valid delayed readbacks. An independent
read-only proof accepts every source crossing and the immutable playback epoch;
`path-verification.json` preserves that narrower result. Minecraft completes its
trace in 5,511 ms with equal client/server maximum travel of 0.594374 m, four
boundary pauses, three resumptions and zero corrections. Two authoritative
`LANDING` samples pass through the combined path, covering the previous phase
failure. This run does not reopen inventory; earlier inventory evidence remains
separate.

The primary verification remains **failed**, with restoration not accepted by the
expected normal-finish contract. Its actual native terminal is `restored`, reason
`frame_lease_expired`: the watchdog returns the actor to the exact starting
position with zero readback error and cancels timers after 138 total writes and
5,859 ms. FPS restoration, all 768 fresh camera publications/resource closure and
Minecraft cleanup pass. This is a finish-handshake race, not missing actor
restoration. The original failed verification is unchanged. The native
end-of-stream repair now passes separate autonomous replay
`02e045ab5635428f99f7fd8614a3ab2b`:
`runtime/evidence/buffered-movement-replay-20261027-170751-02e045ab5635428f99f7fd8614a3ab2b/`.
It acknowledges all 51 scripted source points, then restores through
`explicit_end` with zero error, cancelled timers and FPS restoration. It takes
5,871.826 ms and 64 writes including restoration. The final source now triggers
normal restoration in the game without waiting for controller polling; the
original 400 ms target lease and 200 ms playback delay stay unchanged. Source
checks pass 79 Lua cases. This replay has no Minecraft, HUD or physical controls;
it does not turn the previous 52-source physical run into a clean normal-finish
pass. The later `650a...` physical run above verifies normal finish; the original
`fa370...` failed result remains unchanged.

`latency-analysis.json` retains the original timing data and its limitations.
The follower reports 344 observations, retaining 71; all retained readbacks occur
one native frame after their write, median 16.037 ms and maximum 16.296 ms, with
zero actor errors. There are 137 movement setters and one restoration setter,
with no retained intermediate source holds. Source capture intervals are median
100.916 ms, maximum 166.572 ms; actual server-source intervals reach 201.099 ms.
The sampled server observation is median 37.738 ms old.

Per-key capture/application timestamps are not persisted, so exact physical
keypress-to-motion or input-to-photon latency is unavailable. Nearby camera
request/receipt clock alignment estimates the first source capture reaches
native acceptance after about 124 ms, compared with 35 ms median for later
captures. The first native write is about 334 ms after that initial trace capture;
these are clock-alignment estimates with cached-frame uncertainty. The directly
measured native acceptance-to-first-write interval is 210.068 ms, including the
intentional 200 ms buffer. The 100 ms source sampler also limits onset timing
resolution; its delay cannot be assigned to individual keys from this evidence.

A pure offline profile now reproduces substantial first-use overhead in five
fresh PowerShell processes, each replaying the exact hashed 52-point trace twice.
The first edge's begin parse, first sample parse and source normalization cost
68.28–90.09 ms combined (median 69.13 ms); the second pass costs 6.36–8.13 ms
(median 6.73 ms). Median stage costs are 38.76/11.73/19.41 ms cold versus
2.58/3.88/0.318 ms warm. Receiver construction costs about 142 ms, but already runs
before activation and is not counted in that edge overhead. Original record UTC
is supplied only as a synthetic pure-parser clock. No game calls or physical
latency measurements are made. The reproducible script and five measurements
are in `runtime/evidence/hud-source-cold-profile-fa370b-20261027/`.

Diagnostic warmup is now implemented in
`Initialize-HudBufferedMovementPipeline`, before arming/readiness. It validates
the patch and uses independent disposable receiver/source state for three
explicitly diagnostic in-memory records; no source points are published and the
native follower is not started. Five new fresh-process profiles now measure the
first exact recorded begin/sample/normalization at 7.67–9.93 ms, median 8.52 ms,
compared with the earlier 69.13 ms cold median: 60.61 ms less pure processing.
Stage medians are 3.19/4.40/0.901 ms. Warmup itself costs median 245.14 ms before
arming. Each process then replays all 52 original points twice with unchanged
trace/patch hashes. Evidence is in
`runtime/evidence/hud-source-warmed-profile-fa370b-20261027/`; no game calls or
physical latency claims are made. Warmup's 86 checks and the existing 79 buffered
checks pass.

Keep the 200 ms smoother baseline. Actual dispatch metadata now records
receive/validation/preparation/request stages and original source age; source
freshness is checked after preparation at dispatch. The later `650a...` combined
run records actual timing without isolating the warmup's individual contribution.
Do not start the eight-second native follower early. Reducing the buffer to 150 ms would
outrun a known next-point arrival in the earlier autonomous replay by 38.903 ms;
the latest run alone would hide that regression. Faster physical-only source
sampling is a later bounded comparison, with existing byte/record and freshness
limits explicitly accounted for.

### Previous combined buffered phase failure

**Source-time playback passes its autonomous replay, but the first combined
buffered run stops at a terrain-transition phase mismatch.** HUD run
`d838afda4ed44e9a855e5da65cb47c07`, probe
`d257ab3e82644a0b9e02612185d4db00`, fails after two forwarded sources and before
any KCD position writes:
`runtime/evidence/hud-walking-20261027-163234-d257ab3e82644a0b9e02612185d4db00/`.
Sequence 4 is labelled `RESTING` while its authoritative server has
`on_ground=true`, `proxy_support=false` and a 0.0784 m descent; the client has
already landed on the lower sampled slab. Buffered playback correctly refuses
to omit that unsupported source point. Java now labels this authoritative
transition as `LANDING`; receiver bounds and physical motion remain unchanged.
The phase correction now compiles: 180 ground-patch and 282 physical-controller
checks pass, alongside 119 PowerShell receiver checks. Captured-terrain
actual-Minecraft fixture `21862be610794462b3ed1437b7802477` passes, with 103 published
frames, 11 inventory frames and 31 walking frames. Scripted W/W/S pulses move
client and server equally by 0.446445/0.640961/0.640961 m, with zero inventory
movement or corrections, then finish in 5,524 ms. Its 100 ms source samples do
not contain the brief unsupported transition, so this run does not establish
regression coverage. Evidence:
`runtime/evidence/hud-physical-fixture-20261027-164007-21862be610794462b3ed1437b7802477/`.

Targeted synthetic fixture `5750b05f92b64938ba7025140d8c33ad` is rejected before
movement because its modified terrain exceeds the existing 0.5 m adjacent-height
bound. That guard remains unchanged. Revised synthetic fixture
`40b64199deda490893f786a0b42e7b27` passes in 5,563 ms with W/W/S distances
0.446445/0.640961/0.856736 m on both client/server, 10 inventory frames and 32
walking frames, zero inventory movement/corrections and complete cleanup. It
also emits no unsupported `LANDING` source sample, so its coverage remains
limited to working movement over its labelled synthetic patch. Evidence:
`runtime/evidence/hud-physical-fixture-20261027-164644-40b64199deda490893f786a0b42e7b27/`.

The exact failed captured sequence 4 is covered by the Java regression and
PowerShell receiver tests plus a read-only replay of that record in memory.
Another fixture is not needed for this narrow phase-label correction; the next
check is the combined live retry. These fixtures use scripted controls and
separate terrain provenance. They neither arm KCD's renderer nor establish
combined smoothness.

The user's apparent immediate Minecraft closure is not a process crash: its
recorded exit code is zero and the helper reports `BUILD SUCCESSFUL`. Controller
cancellation stops the camera worker, then the guest fails its camera lease and
exits normally. All 579 camera publications were fresh and resources closed.
The native terminal receipt is `rejected/explicit_end`, with zero writes,
unchanged origin, zero player error and cancelled timers. The primary
`restoration_verified=false` flag means no restoration event was performed;
it does not indicate unrecovered actor movement. FPS restoration passes. These
facts and the original failed result are retained in `failure-analysis.json`.
No buffered smoothness result was obtained; the earlier still-choppy report
remains the last completed visual comparison.

The buffer intentionally adds 200 ms of playback latency to preserve the actual
server-observation timeline instead of compressing irregular arrivals into fixed
100 ms segments. No new native bundle is required.

Replay `477989b1edd34c10b5d90c437d8006fd` passes all 51 forwarded source points
and 51 corresponding observed crossings, with actor and FPS restoration:
`runtime/evidence/buffered-movement-replay-20261027-162624-477989b1edd34c10b5d90c437d8006fd/`.
This is scripted playback of the previous captured trajectory in real KCD.
Minecraft, HUD composition and physical input were not active. It is not a
combined visual or input-latency result.

Its `timing-analysis.json` records 163 observations, of which 101 are retained;
46 receipts explicitly omit intermediate samples to fit the native log budget.
There are 64 ordinary setters plus one restoration setter. All retained samples
advance exactly one native frame, median 34.42 ms and maximum 34.91 ms. The
aggregate reported observation gap reaches 35.16 ms. This is the measured native
frame cadence of this replay, not a claim of 60 FPS presentation or skipped
callbacks. Position readback errors are zero. Retained camera-to-player offset
changes are median 0.26 mm, maximum 5.38 mm; these snapshots do not prove rendered
smoothness.

Actual server-observation intervals span 97.77-201.27 ms. Playback source time
follows one immutable epoch without fixed-duration compression. The largest
measured movement speed between retained consecutive native frames is 3.688 m/s,
compared with 3.692 m/s on the source timeline. Only the final source point has
a retained hold observation; no intermediate underrun is observed in the retained
samples. The intended 200 ms delay is 199.951 ms in the native float32 clock.
Relative source-timeline-to-delayed-ACK time is median 254 ms, maximum 268 ms;
this includes crossing quantization and readback and is not input-to-photon time.

All 59 matching follower lines from the rotated native log parse, with a maximum
full-line length of 3,793 bytes, below the 3,800-byte serialization budget.
Per-line hashes and lengths are saved in the analysis. The first buffered replay
`5ec108...` failed when the native logger truncated a longer JSON line at about
4,095 bytes; its separate `cleanup-verification.json` confirms exact actor
restoration, and FPS restoration passed. Replay `6ef373...` reached 50/51 source
points before the old 250 ms controller drain ended; restoration passed. The
initial fix waited for the final source ACK within 400 ms. That controller order
is now superseded by immediate end-of-stream sealing: native Lua waits for the
final observation and restores without controller ACK polling. The original
400 ms target lease is unchanged.

Current validation passes 79 Lua cases, 79 buffered PowerShell checks,
86 diagnostic-warmup checks, 119 physical-profile checks, 134 ground-movement
checks, 80 coupled-proof checks and 32 timed-follower checks. `2e75faf` is pushed alongside the earlier checkpoints. The new buffered
implementation and phase correction are now pushed as `11b1b76`; its full hash
and verified publication state are recorded below.

### Previous combined physical result: fixed-duration interpolation

**Repeated physical walking works with the HUD; smoothness remains unfinished.**
Latest combined HUD run `725d69490f464ca989fccb3783a7cba4` passes 49 forwarded
Minecraft server poses, 49 delayed KCD applied readbacks, the movement trace,
player restoration, camera cleanup and temporary FPS restoration. The camera
worker published 484 samples with no stale discards. Minecraft records four
accepted movement edges, two boundary pauses and two resumptions, equal
client/server maximum displacement of 0.758 m, zero corrections and completion
in 5.565 seconds. The user's report remains decisive: "still choppy, maybe a
LITTLE better". This is a technical pass for bounded controls, not smooth,
continuous or exclusive movement.

Evidence, excluded from Git:
`runtime/evidence/hud-walking-20261027-154252-c869ec4362fc44d69f6f10516665149a/`.
Its `timing-analysis.json` compares the latest timed interpolation against the
previous two-step run `0e14e63e600849b1af0a70449369f3f1`:

- The latest follower executes 125 setters across 18 moving segments, with six
  or seven writes per segment. Within-segment write intervals are median
  16.07 ms, maximum 16.90 ms; retained normal-frame readback errors are zero.
  The older midpoint/endpoint observations were about 48.10 ms apart.
- All 31 stationary target segments perform zero setters. The new maximum
  recorded increment is 0.093 m, compared with a 0.316 m interval between old
  observations. Inputs differ, so this is not a controlled comparison of
  perceived smoothness.
- Four of 14 transitions between consecutive moving segments still pause
  47.19–64.32 ms between endpoint write and next first write. Source captures
  remain median 101 ms apart, maximum 168 ms. A 0.575 m source change over
  167 ms is replayed over a fixed 100 ms, followed by a segment only 0.052 m
  long. Sparse arrivals and abrupt segment-speed changes remain concrete leads.
- Camera request-to-publication during movement is median 63 ms, maximum 98 ms,
  with no stale discards. Receipt lookup is median 1.80 ms, maximum 5.18 ms.
  Endpoint camera-to-player offset changes are at most 2.7 mm, versus 17.0 mm
  in the older run. Independent sampled offsets also stay stable. These records
  show no large relative-camera jumps; they cannot exclude presentation stutter.
- Moving-target acceptance to delayed endpoint ACK is median 132 ms, maximum
  161 ms. Stationary ACKs take about one game frame. Neither measure is physical
  input-to-photon latency. Source records retain capture time, not dispatch time.

The two boundary pauses and real control releases intentionally interrupt
movement; they must remain distinct from rendering jitter. The earlier `0e14...`
run passed 51 forwarded/50 applied poses and 483 fresh camera samples; the user
confirmed all directions worked but described very choppy motion. Its original
receipts and separate `timing-analysis.json` remain preserved.

That fixed-duration follower requests a 1 ms timer and advances an immutable
selected segment over 100 ms of engine time. It skips stationary setters and
caps physical writes at 512; the legacy cap stays 200. The original 400 ms
accepted-target lifetime, eight-second deadline, two-metre sphere and restoration
guards remain unchanged. Source checks pass 47 Lua cases and 17 PowerShell
interpolation-proof checks.

An earlier autonomous probe also passes five nonzero segments and one stationary
target:
`runtime/evidence/physical-follower-scripted-20261027-153609-198d8a567af448718f191a4984127621/`.
Each moving segment has six or seven setters and six to eight later observations;
median observed gaps are 20.75 ms in the first segment and 16.11–16.36 ms
subsequently, maximum 21 ms. The stationary target has zero setters and a later
16.36 ms observation. All position errors are zero; actor and FPS restore.
Two earlier cadence probes (`bd3ce0a7...`, `152ce02b...`) retained exact positions
and restoration but failed strict cadence at about 34 ms. A read-only timer probe
`d9589118d00247bbb0690508e2968042` observes consecutive native frame IDs at about
16 ms for a rearmed 1 ms timer. Console flushing was reduced to every 100 ms and
the foreground request was confirmed belatedly; the improvement cannot be
attributed solely to polling or focus. These autonomous checks do not establish
subjective smoothness; the later combined run above still looks choppy.

Commits `a59403c`, `f6f8ea9` and `2e75faf` are pushed to the public default
branch. The fixed-duration implementation and its still-choppy combined result
are preserved there; the later source-time buffer is described above.

### Earlier technical pass and completed camera repairs

Live run `c398308550e6446db5d79bd176a1709b` passes five forwarded Minecraft
server poses, five matching delayed KCD readbacks and player restoration. The
movement trace passes, the camera worker closes its resources, and the temporary
FPS cap restores. This is the first completed technical check for this physical
HUD profile. The user's observation is narrower: they moved only a tiny distance,
the movement was jittery, and pressing W again did not work. The receipt keeps
`visual_verified=false` and does not establish usable or continuous walking.

Evidence, excluded from Git:
`runtime/evidence/hud-walking-20261027-142059-6cf16f5625e34739a9f1b77b5bc74200/`.
Local checkpoint `a59403c` preserves the camera and one-step baseline before the
following usability changes. KCD was subsequently closed normally with `WM_CLOSE`
and exit code 0; Minecraft was also closed before the independent checks.

### Camera and completion repairs verified by that run

`HudCameraDelivery.ps1` now requests and publishes camera samples in a bounded
worker, so arming or movement commands cannot suspend it. Profiling isolated the
remaining log cost: reopening a recently written file took several milliseconds
per poll. Retaining an unbuffered read handle reduced a saved 567-record append
benchmark from 9.09 ms median to 0.41 ms, with explicit cleanup and rotation tests.
This is a local component measurement, not player input latency. A live camera-only
check continued during ten 500 ms caller stalls without starting Minecraft or
moving KCD's player. Later live controller runs also stopped their workers cleanly.

The worker uses a 110 ms monotonic minimum interval: at most 1,019 requests within
112 seconds, below Lua's unchanged 1,024-sample limit. Original request timestamps,
the 300 ms camera lifetime, 250 ms input limit and 400 ms follower lease remain
unchanged. Temporary camera snapshots use atomic replacement without
a durable disk barrier; the source timestamp is never refreshed on publication.

Live run `e81cfb5cf4444a97a7d73ba964e120cd` recorded two matching delayed KCD
movement readbacks, no camera expiry, and verified player/FPS restoration. It
failed when walking downhill exceeded the existing 0.2 m descent bound. The new
input gate checks braking clearance across the sampled slabs before accepting
another tick of movement, using vanilla acceleration, drag and jump limits.
It releases input without writing Minecraft position or velocity.

The next active attempt, `f14d88a1da744fe8a6209dfcc9c0d004`, exposed a premature
completion check: the client had walked 0.15149 m while the fresh server sample
still reported 0.098 m. Completion now waits for 500 ms of continuous settled
observations before accepting or rejecting both displacement proofs, inside the
original one-second settling and six-second total limits. A focused regression
replays that lag, catch-up, insufficient movement and interrupted settlement.

Earlier run `3e315dd5cbab4ac3a2c626764346a11a` expired waiting for F8 while the user
was away. It received no activation or input, forwarded no movement, and does not
verify the completion repair. Its 781 camera publications had no stale discards;
maximum old-source age before the next publication was 282 ms, and mean receipt
lookup was 1.748 ms. The worker closed and the temporary FPS cap restored. The
controller reports failure because no actual input session completed. An intervening no-W run and a
pre-arm HTTP timeout likewise establish no walking success. These failures remain
part of the history; the later technical pass does not turn them into successes.

No-input evidence: `runtime/evidence/hud-walking-20261027-141302-a427385635e14bbf83c4c3a94350d5d9/`.
Baseline validation completed before the usability changes: Java suites passed
242 physical movement, 156 ground and 353 input checks. PowerShell suites pass
57 camera-worker, 74 receipt-cursor, 23 path, 90 physical-profile, 134 ground and
80 coupled checks. The installed native walking bundle remains unchanged.

### Walking usability components and the previous two-step follower

- A sampled-terrain boundary now pauses movement instead of ending the trial.
  Controls must be released before a fresh press can resume in an allowed
  direction. Repressing never renews the original five-second input window;
  there is still at most one further second for settling.
- The physical profile now permits vertical offsets from -1.5 m to +1.5 m inside
  the same 2 m follower sphere. Minecraft uses a 1.75 m predictive radius, a 1.8 m
  hard radius and a predictive vertical envelope of -1.45 m to +1.45 m, together
  with sampled-ground coverage. The legacy scripted follower keeps its original
  -0.2 m to +1.5 m limits.
- Physical KCD targets now use a midpoint write followed by the exact endpoint,
  on separate 40 ms timer ticks. The endpoint is acknowledged only after another
  normal game frame. Receipts retain both actual midpoint and endpoint
  observations; midpoint motion is not reported as an applied server target.
  New pending targets coalesce while a segment finishes. Each segment retains
  its own 400 ms lifetime from Lua acceptance; later arrivals cannot renew it.
  This is an arrival lifetime, not a claim about an absent cross-process source
  timestamp. The fixed eight-second follower deadline and restoration remain.

The updated Lua movement suite passes 40 cases in the real Lua 5.2 VM with
simulated engine bindings, including drift, expired segments, interruption,
restoration and unchanged legacy behavior. Visual smoothness is still unverified.

Two independent checks now pass so further diagnosis does not depend on
repeated short user-input windows. `Test-HudPhysicalMovementFixture.ps1` uses
explicitly scripted input with the actual Minecraft controller, physics,
inventory and HUD, without KCD composition or physical-input authority.
`Test-KcdPhysicalFollower.ps1` checks small scripted KCD targets and observed
midpoint/endpoint positions, without Minecraft, HUD arming or physical keys.
The independent KCD probe now passes at five scripted horizontal offsets:
+0.2 m, +0.4 m, +0.1 m, -0.1 m and back to the origin. All observed midpoint and
delayed endpoint errors were zero. Target receipt ages were 96.49–146.59 ms from
Lua acceptance; these are not physical-input latency measurements. The actor
returned to the original position, owned timers were cancelled and the temporary
FPS budget restored to -1. Evidence:
`runtime/evidence/physical-follower-scripted-20261027-144521-6d622dba7e2b42fd8b45a9e8ca5bd1fc/`.
No Minecraft, HUD or physical-input path was involved, and visual smoothness
remains unverified.

The actual-Minecraft flat fixture also passes, run
`70db9fa42a8a4e4c8dd48ad2b5974ef4`. Three scripted presses, W/W/S, moved both client
and integrated server approximately 0.857 m, 0.642 m and 0.857 m respectively,
with zero disagreement. The second W reached a boundary pause; after release,
S resumed movement away from it. The proof records one pause and one resumption.
W while inventory was open produced zero displacement on both sides. It captured
nine inventory and 32 walking HUD frames, published 102 frames, and wrote 52 trace
records. The movement completed in 5.536 seconds with zero corrections and clean
controls, collision proxies, camera worker and mapping teardown. Saved inventory
and hotbar PNGs were visually inspected and contain the expected actual UI.
Evidence:
`runtime/evidence/hud-physical-fixture-20261027-145207-70db9fa42a8a4e4c8dd48ad2b5974ef4/`.
This is actual Minecraft controller/physics/HUD evidence with scripted input and
flat fixture terrain, not physical input or composition inside KCD.

The captured-terrain replay also passes, run
`664e98c29ee14d94b2a6acf6e26192db`, using numeric samples from `c398...` and heading
-171.788791435144 degrees, relabelled with explicit fixture provenance. W/W/S
moved both client and server approximately 0.447 m, 0.641 m and 0.641 m with zero
disagreement. Maximum walking displacement was 1.088 m and the minimum vertical
offset was -0.154 m. Two boundary pauses and two resumptions are recorded, with
zero corrections and zero inventory-W movement on either side. The run captured
ten inventory and 31 walking HUD frames, published 103 frames and produced 52
trace records in 5.508 seconds. Controls, proxies, camera worker and mapping all
cleaned up; the temporary host FPS budget restored. Both fixture clients exited.
Evidence:
`runtime/evidence/hud-physical-fixture-20261027-145410-664e98c29ee14d94b2a6acf6e26192db/`.
This confirms the updated controller against the captured terrain values. It
still does not replay live physical input or compose the HUD in KCD.

Two earlier fixture failures are retained: run
`3f8a5c49d00a4133b87a87d255075423` hit the producer constructor's fixture-route
guard, and `50341a5ce8d040efb0386d748eabd26b` hit a Windows `AccessDenied` during
atomic camera-file replacement. The route guard is repaired. The fixture camera
publisher now retries the exact prepared bytes for at most 100 ms without
refreshing capture time, with a regression using a real Windows handle that
denies delete sharing. Updated validation passes 282 Java controller checks,
43 PowerShell fixture checks, 107 physical-profile checks and 16 legacy trace
checks, alongside the 40 Lua movement cases and actual-KCD probe above.
Ground checks (160) and reverse-input checks (353) also passed.

These changes require no replacement native bundle on the existing test machine.
Historical process sequence: 45644 closed normally and its `725d...` arm was archived. Process 34088
then consumed its activation in `d838...`/probe `d257...`; Minecraft exited. The
user has now closed 34088 normally and its exact `d257...` arm is archived.
KCD process 33860 then consumed its HUD activation in `fa370b...`/probe `2dd6...`.
It has since closed and that exact arm is archived. Replacement process 48256 was
also closed by the user before a new comparison. The subsequent `650a...` physical
run on process 50636 passes normal finish and the full combined path with warmup
and fixed sampling. KCD 50636 remains open, Minecraft is closed, and the exact
`38d11...` arm is consumed. Source-time buffering and the phase correction were
pushed in `11b1b76`, normal completion/warmup in `c90da08`, and fixed sampling in
`d150024`. The current handoff supersedes the older process state; recheck tools
and processes before any later test.

## 20 October 2026 checkpoint

**Wrap-up: partial physical walking reaches KCD; complete live check still fails.**
Latest run `c427a5fc08bf4874a00f5f3cc64b04f4` records actual Minecraft walking
of 0.75389 blocks on the client and 0.626906 on the integrated server before the
camera lease expires. Its four-record trace produces one forwarded server pose.
The saved KCD receipts contain one matching delayed `applied_readback`, sequence 3,
at approximately 0.2495 metres displacement, followed by verified `explicit_end`
restoration. The outer receipt reports `delayed_readbacks=0` because its success
counting stage was never reached; that field does not erase the underlying
applied receipt. This is partial movement evidence, not a completed walking pass.
The user reports that Minecraft appeared to crash after walking began.

The new diagnostic records camera sequence 290 at source age 322 ms: request
UTC 1792512591788, observed by Java at 1792512591979, rejected at 1792512592110.
Sequence 291 is published at 1792512592117, seven milliseconds after rejection.
The worker's last read is only 1 ms old and its maximum polling gap is 42 ms, so this
attempt does not indicate reader starvation. Incremental parsing fixed the
growing-history cost, but camera roundtrip/controller publication still takes
roughly 120–190 ms. The next step is to profile console HTTP, guard and path-validation
timing before another human retry. Keep the original 300 ms camera lifetime and
100 ms I/O retry bound; extending leases is not the planned repair.

Evidence:
`runtime/evidence/hud-walking-20261020-170855-731e410d62f944fc98f58fef5bd9b1b8/verification.json`
and its `kcd-receipts.json`. Work stops here for the user's requested wrap-up;
resume from this timing diagnosis. No further live test is claimed.

**Physical HUD walking implementation and earlier camera timing repair.**
The separate `Start-HudWalkingLab.ps1` connects physical WASD/Space events to
vanilla Minecraft movement in the same fresh world that supplies the HUD.
It captures real KCD ground, checks the owned client/server collision installations,
and uses fresh, session-bound KCD camera direction for Minecraft yaw and pitch.
Fresh integrated-server positions drive the bounded KCD follower while the
existing compositor displays Minecraft's actual UI.

This is an explicit walking profile with its own add-on and
`MineComeHudMovement.ini`, reusing the frozen revision4 renderer. Its input
protocol2 adds the five movement keys; protocol1 and the existing aimed/stone
profiles retain their original scope. It does not publish stone-click intents.
F8 requires all 16 watched keys to be neutral. Movement releases before inventory
transitions, on lost authority and at completion; closing inventory requires
neutral controls and a fresh press before movement can resume.

The lab accepts movement for up to five seconds from the first accepted movement
edge, followed by at most one second of neutral settling. It can stop earlier at
the sampled footprint or displacement limit. The HUD remains bounded to 30 seconds
after F8. The game-owned eight-second follower deadline and 400 ms lease remain;
the controller verifies delayed player readbacks and return to the owned starting
position. KCD camera look remains native. Neither `FreezeInput` nor a physics
enable/disable method is used, and full-world or exclusive movement authority
is not claimed. The temporary 60 FPS cap has its existing 120-second engine
deadline and must restore.

Native and Java sources compile and focused protocol, held-key, camera-file,
collision ownership, trace and lifecycle checks pass. Independent native review
passed. The four deployment/profile PowerShell suites pass 676 checks under
both Windows PowerShell 5.1 and PowerShell 7, including the new explicit walking
rollback and unchanged legacy profile cases. A startup failure caused by a
Windows camera-file sharing race is repaired with a bounded 100 ms filesystem
retry. Retrying retains the original sample and expiry; malformed data or wrong
identity is still terminal and no input or camera lease is extended.

Combined live check `1bbb94b95bf44903aec2ca23a1f64dcb` fails when the active
camera lease expires after W. The user confirms the HUD appears and inventory
works in the new profile, but walking does not. The controller records zero
forwarded poses and zero delayed movement readbacks, so the KCD follower never
starts. The temporary frame cap restores. The file-sharing exception is resolved;
HUD/inventory visibility does not establish composition during actual walking.

Investigation measured another timing cost: reparsing the growing camera log
history took about 101 ms at 336 samples. The controller now uses an incremental
cursor that parses each complete record once. It retains the unfinished UTF-8
tail until a newline arrives, enforces the existing 8 MiB probe-log bound, rejects
malformed records, and commits a batch to the cache only after parsing succeeds.
All 59 cursor regressions pass. An unchanged poll against the actual saved
335-record log measures 0.089 ms median and 0.26 ms at the 95th percentile.
These are local parser measurements, not end-to-end input latency.

The Java camera reader now polls every 5 ms and records the exact immutable sample,
original deadline and worker timing at rejection. Independent review confirms
these diagnostics grant no authority. The original 300 ms camera freshness and
100 ms filesystem retry limits remain unchanged; repeated bytes cannot refresh
either sample authority or its deadline. The later run above reaches partial
movement but still expires, so these timing repairs do not complete the walking
milestone.

The original failed receipt is preserved at
`runtime/evidence/hud-walking-20261020-170132-17025444a2274b4786836879fcb7bd41/verification.json`.
A complete physical walking pass remains unverified. The earlier scripted pass
below remains a separate milestone; this bounded lab is not the final continuous
playable build.

**HUD-world movement connected to the bounded KCD follower.** The new
`Start-HudCoupledMovementLab.ps1` captures fresh KCD terrain, creates a new
Minecraft HUD world over that patch, and forwards fresh integrated-server
positions during its scripted walk/jump/landing sequence. Its movement trace ends
before the later 20-second inventory sequence. The existing game-owned eight-second
deadline, 400 ms lease, actor guards and return-to-origin behavior are unchanged.
The HUD goes to the standalone native receiver; this mode does not arm composition
in KCD or forward physical walking controls.

Fresh two-game run `391e9d463edc4789b6bb425eec84a183` passes the complete
controller. Both Minecraft sides walk 1.291498509 blocks, jump and land on the
captured KCD ground without post-settle corrections. Twenty-one forwarded
server samples have 21 matching delayed KCD readbacks covering walking and
vertical jumping. The game-owned follower ends after 2.56 seconds, confirms the
player's return and delayed camera following, and cancels its timers.

HUD run `32757a254fbe4ebdbb31190c7c90a989` uses that exact Minecraft save and
25-record movement trace. Completed readbacks include six walking, two jumping
and 21 landing frames. The native receiver accepts 435 frames, all four expected
hotbar/inventory states, stale-frame hiding, resumption and closure. Both collision
installations and synthetic controls are released; Java/native/helper exit
normally. The temporary 60 FPS cap remains owned until completion and its original
value is restored. KCD stays open in the fresh test world.

The source compiled and passed 2,872 focused Java checks, 134 HUD movement
PowerShell checks, 80 coupled-proof checks, 16 receiver scenario groups and 68
existing aimed-controller checks. Independent review passed, and Windows
PowerShell 5.1 successfully handed preflight to PowerShell 7. This verifies the
bounded scripted connection from the actual HUD world to KCD, not sustained
movement authority, physical walking controls, placed-block collision or HUD
composition during movement.

Passing evidence:
`runtime/evidence/coupled-movement-20261020-162621-391e9d463edc4789b6bb425eec84a183/verification.json`.

The first two-game run, `010ae6c76ba342baa8716c79f7ff5b79`, fails the controller's
new target-correlation check after 21 applied KCD readbacks and confirmed player/
camera restoration. Minecraft's movement trace and HUD receiver independently
pass, and the temporary 60 FPS cap is restored. All 69 target coordinates in
21 applied and two heartbeat receipts exactly match the float32 conversion of
the forwarded positions. The new validator incorrectly compared against the
original double with a one-micrometre tolerance; the largest observed difference
is 0.00000376425 metres. Its original failed receipt is preserved. The corrected
comparison requires the exact float32 projection, rejecting unprojected doubles
and adjacent float32 values. The official `SetWorldPos(Vec3)` documentation and
inspected `Vec3_tpl<f32>`/script-value declarations corroborate that representation;
no native ABI calls or gameplay tolerances changed.

Evidence:
`runtime/evidence/coupled-movement-20261020-162157-010ae6c76ba342baa8716c79f7ff5b79/verification.json`.

**Walking, jumping and HUD capture verified in the same actual Minecraft world.**
The new opt-in `Start-HudGroundMovementLab.ps1` passes run
`bee8b2aae29f4b2787ba693c03994093`. It creates one fresh Creative save, imports
a synthetic 25-point flat ground patch into the existing collision adapter, and
uses ordinary Minecraft movement with scripted key states. Client and integrated
server both record 1.291498509 blocks of walking, an airborne phase and landing.
There are zero post-settle position corrections. Completed HUD readbacks include
six frames from the walking phase, two from jumping and 22 from landing.

After movement, the same world completes the normal hotbar/inventory sequence.
The native receiver accepts 434 nontransparent frames across all four expected
UI states and verifies stale-frame hiding, fresh resumption and closure. Client
and server release their own collision installation; synthetic controls are
released and Java/native processes exit normally. The saved inventory capture
was visually inspected. Movement-phase counts describe completed Minecraft
readbacks, not separate native verification of every phase.

This is standalone integration with synthetic ground and input. It does not
connect to KCD, prove collision against placed blocks, or enable shared walking.
The mode requires explicit standalone configuration, rejects competing labs and
cannot arm the live compositor. Existing HUD modes remain the default. Independent
review caught and resolved key cleanup after player replacement and missing
zero-valued phase counters. Compilation and 2,810 focused Java checks pass,
alongside 62 new PowerShell checks, 68 existing aimed-controller checks and the
new launcher's preflight, including its Windows PowerShell 5.1 handoff to
PowerShell 7.

Evidence:
`runtime/evidence/hud-stream-20261020-145651-bee8b2aae29f4b2787ba693c03994093/verification.json`.
The next integration work is connecting the HUD world's movement to the existing
KCD input and player-following paths, with ownership and cleanup kept explicit.

**Autonomous activation attempt inconclusive; normal desktop close verified.**
HUD run `1511d9ae36cd413595a072b9e73d8641` rendered in KCD, but Computer Use
sent F8 at 14:45:09.075 UTC, after Minecraft's 60-second prearm window had ended
at 14:45:05.384 UTC. No input session or stone action began. The original failed
controller receipt is retained; the attempt establishes neither working nor
broken F8 delivery. Java exited normally, and the temporary host frame cap was
restored. Computer Use subsequently closed the owned KCD test window with
Alt+F4, and process absence was confirmed. Its expired arm was archived.
Automated game input is still separate from the earlier successful human checks.

**Agent launch and visual access verified; desktop gameplay input remains
unverified.** On the user's request to enable autonomous demos, the normal
`Start-Kcd2ToolsTest.ps1` launch succeeded for the exact supported executable
(PID 47364). Computer Use selected the returned official-tools window, brought
it forward and captured the loaded Trosky test world. No permission settings,
renderer bounds or game files were changed. An initial `GetCursorPos` access
error cleared on the documented single recovery attempt. Escape dispatches
returned successfully but did not visibly open a menu, so this check does not
establish keyboard or mouse gameplay control. The next automation check should
verify hotbar/inventory input receipts before attempting precise world aiming;
the documented desktop API has no button-free relative mouse movement.

**Top-face targeting verified after correcting the entity rotation.** Live run
`7ab72119af9e4401bed3cbbb6337aa42` passes the intended three-action sequence:
one right-click hits the original seed's UP face and places directly above it;
the next two clicks break the upper block and seed. The user reports “worked
perfectly.” All three physical intents have matching original rays, canonical
requests/results, Minecraft client/server confirmations and KCD acknowledgements
(564, 629 and 674). There are no refusals, stale results or queue drops.
Minecraft finishes with zero owned or pending stones; Java/native exit normally,
and engine cleanup, independent input cleanup and frame-cap restoration pass.

Before that check, automatic live diagnostic
`e3eb3bbcfa9a45a68363f46355b0d1f5` verified zero rotation, actual world bounds and
exact shared faces for seed, top and west neighbours, then removed all three
temporary objects. This used the real KCD sink; it did not claim Minecraft input.
The physical check then verified placement on the original top, rather than the
earlier UP placement on an added side block. The HUD closed on foreground loss
11.062 seconds after activation, so this does not establish 30-second stability
or complete coverage of every face.

Evidence:
`runtime/evidence/stone-alignment-fix-20261020-152807-e3eb3bbcfa9a45a68363f46355b0d1f5/verification.json`
and
`runtime/evidence/hud-input-20261020-142820-7ab72119af9e4401bed3cbbb6337aa42/verification.json`.

**Visible targeting offset diagnosed in the live engine.** The top-only retry
`f074546edb4441f69c8951d727ba0b5c` reproduced the user's mismatch: aiming at the
visible top could place against the face toward the player. A subsequent bounded
automatic measurement found that `System.SpawnEntity` had given the stone a
world Z rotation of approximately -90 degrees. The source CGF and its local
bounds were correct, but the actual world bounds were shifted one unit toward
negative X from Minecraft's targeting box.

For the first saved click, the ray intersects the measured visible cube's top at
distance 1.006076 m. It reaches Minecraft's logical west face at 1.634615 m,
0.343107 m below its top. Sixty-one surrounding camera samples have unchanged
direction, ruling out camera turning during dispatch for this click. This
explains the user's report; earlier local-bounds and requested-position receipts
did not establish the object's actual world transform.

The diagnostic used the production stone sink, read actual world position,
angles, scale, slot transform and world bounds, then ended its own temporary
session. Engine cleanup confirms no active session, owned objects or pending
removals. Evidence:
`runtime/evidence/stone-world-bounds-20261020-151821-c2493cc15cef4baa8170cbb74166322f/fresh-kcd-complete.log`.
Both spawn paths now explicitly set the documented world angles to zero and
require the actual world bounds to match the mapped cell before acknowledging
success. Existing objects are rechecked before `already_present`; a mismatched
object enters the normal tracked cleanup path. All 64 Lua lifecycle cases pass,
including a mock of the observed -90-degree default, ignored/failed orientation
writes, malformed/shifted/scaled geometry and deferred cleanup.

Independent review passed. With KCD closed, the repaired Lua package was
installed and its source hash verified as
`3422859e62afafda5f5afb83d20ac6cf14c325b5031608ee6478b1781abd23a9`.
The previous package is backed up at `runtime/packages/previous-20261020-152428`.
The compiled stone asset is unchanged. The subsequent automatic world-bounds
measurement and visual top-face check above both pass.

The retry itself records two network placements, three breaks and final
Minecraft air with no owned/pending work. No permit-expiry rejection occurred;
the first request entered at 304.77 ms. Its original controller receipt remains
failed because it rejected three native `engine_session_unready` refusals while
earlier removals awaited engine acknowledgement. The audit repair accepts only
refusals inside a uniquely corroborated pending-removal-to-ACK interval and keeps
them separate from guest actions. It passes 165 PowerShell 7 checks, including
the Windows PowerShell 5.1 handoff, and five read-only saved-run replay
expectations. Original evidence hashes remain unchanged. This repairs evidence
classification, not visual alignment.

**Face-placement attempt: two faces confirmed in the records; full live check
failed.** Run `3c111cfc7ed242089dff99066a0ca7ae` confirms placement against the
seed's WEST face, then against the new block's UP face, followed by breaking both
added blocks. Requests 2, 3, 10 and 12 have matching original rays, Minecraft
client/server confirmations, adjacent cells and mapped KCD acknowledgements
(sequences 601, 643, 735 and 762). The user saw front-face placement and both
breaks, but did not identify a successful top placement. This does not verify
the intended top-first sequence or reliable response.

The first click reached Minecraft at an original-permit age of 508.3593 ms and
was refused before selection. Another request reached the adapter at 437.8217 ms
but expired before dispatch; three later placements were rejected by the vanilla
interaction. Repeated clicks exhausted the bounded physical-click allowance.
The final seed-break request was cancelled on closure, leaving one guest-owned
stone and one cancelled pending action. The original controller receipt remains
failed. Java and native exited normally; KCD replica cleanup, independent
input-end acknowledgement and frame-cap restoration succeeded. Replica cleanup
is not evidence of a Minecraft break.

Evidence:
`runtime/evidence/hud-input-20261020-135644-3c111cfc7ed242089dff99066a0ca7ae/verification.json`.
The renderer snapshot is preserved as `capture/reshade-observed.log`, SHA256
`898c2065de7ec0d4c4c81bea20582ba9a1152626ba10dde1bb2af47494b2c61a`.
The next live check isolates the original seed's top face with three actions:
place once, break the added upper block, then break the seed.

**Permit-install delay repair: built and simulated integration verified; live
retry pending.** Minecraft already issues permits every 100 ms. The native relay
also waited 100 ms between installations, adding a second scheduling delay while
the original permit aged. Native now installs the newest eligible permit without
that extra timer. Monotonic IDs prevent repeated installation; latest-only
selection coalesces backlog, and the retained records remain bounded at 16.
Original receipt times, generation checks, 500 ms expiry and single-use physical
capture are unchanged. This is a bounded work path, not a strict 10 HTTP calls
per second limit against an authenticated peer sending faster permits.

The release tools host builds and all three simulated HTTP suites pass (stone,
interactive stone and aimed input). Added integration checks cover one
installation per original ID, no installation while the peer is quiet despite
continued polling, and acknowledgement of a new permit without further peer
issuance. They do not measure live latency. Native executable SHA256:
`cfc98a194e1a50bb948f39a481a65926cabc89cacc5553a4bcb7bb50e3e091f0`.
The expired failed-run arm was archived with KCD closed; no renderer change or
game launch was needed for this repair.

**Hotbar changes after dispatch: implemented and verified in actual Minecraft.**
The aimed arena now checks the original slot's item/count on both client and
server during confirmation, independently of the currently selected slot.
Selection must still match before dispatch and immediately after the vanilla
call. Target, ownership, ray, reach, freshness and world/player checks remain.

Run `3e32c1486caf41e4ad1d712ed4e112e4` passes **28 standalone scenarios**:
switching before dispatch produces a normal refusal; switching after placement
or breaking preserves confirmation; the following action remains usable.
Both switched actions observed slot 1 selected on client and server while the
original slot 0 retained 64 stone. The main arena records 20 requests and
10 confirmed actions (five placements and five breaks), zero owned/pending
stones and final air at all four used cells.

A separate auxiliary arena places and breaks its seed through vanilla APIs,
then deliberately changes the original stack after dispatch. The expected
`selected_stack_changed_during_action` failure remains enforced. Its stale
ownership receipt is preserved; independent client/server air observations
prove the block is gone, and inventory restoration is verified before the main
scenarios start. No direct block writes are used.

The Fabric build/remap and existing automated suites pass, including 3,819
protocol checks. The receipt validator passes 98 checks in PowerShell 5.1 and 7.
The actual fixture recompiles the final sources, verifies their hashes, restores
options, saves the isolated world and exits normally. KCD is not connected to
this fixture; rapid slot switching during an aimed KCD action still needs live
coverage. Evidence:
`runtime/evidence/aimed-stone-20261020-143821-3e32c1486caf41e4ad1d712ed4e112e4/verification.json`.

**First-click aimed break verified after the latency repair.** Run
`dc93d381b60b4461952d024017b186c7` passes the bounded live controller: one physical
click, one captured ray, one canonical request, one confirmed Minecraft
client/server break and the matching KCD removal acknowledgement. There are no
native refusals, guest stale replies or queue drops. The user reports “barely any
delay.” The hitbox and original 500 ms permit lifetime were unchanged.
The controller observed the physical edge after 19 ms and sent its Lua capture
after 69 ms. Minecraft admitted it at an original-permit age of 371.975 ms;
the canonical request-to-result interval was 165.093 ms. These are separate
measured intervals, not a complete click-to-displayed-frame latency.

Java and native exit normally, the guest reports `input_completed`, world
cleanup and independent input-end acknowledgement pass, and the temporary
60 FPS cap is restored. The renderer recorded 108 uploaded frames and closed
on foreground loss to Explorer 6.7 seconds after F8. This verifies the single
break and prompt visual response; it does not establish 30-second stability,
input exclusivity, placement across block faces or shared movement.
Original evidence:
`runtime/evidence/hud-input-20261020-132449-dc93d381b60b4461952d024017b186c7/verification.json`.
The next targeting milestone is aimed placement and removal on multiple faces
without moving the player's feet.

**Earlier live aimed break confirmed after several refused clicks.** Run
`67b5fd8e70bc46ed97fc8f52d999489b` records physical click 6, its original permit 83,
the same-callback KCD camera ray, native `AIM_REQUEST`, a confirmed Minecraft
client/server break, the matching block event and KCD removal acknowledgement.
The user saw the stone disappear after trying several spots. There were seven
physical clicks: three native permit-expiry refusals, two unknown/consumed-permit
refusals, one guest transport stale refusal, and one confirmed break. No hitbox
change follows from these refusals: most never reached Minecraft selection.
An analytical check of the saved rays against the logged engine cube bounds
also finds that the first expired ray and the successful sixth ray intersect
that same cube. This calculation is not a substitute for Minecraft's raycast.

The guest reports `input_completed`; Java and native exit normally, and replica
cleanup, independent input-end acknowledgement and frame-cap restoration pass.
The renderer closes on foreground loss about 10.5 seconds after F8, so this is
not a full 30-second stability result. The original controller receipt remains
failed because its validator assumed every captured intent reached the guest.
The repaired validator passes 124 checks and a read-only replay of this run,
separating five native refusals and one transport stale reply from the actual
adapter action. An intermediate `cleanup_pending` receipt must match the exact
later removal session, sequence and cell; it is not a second action. Both earlier
zero-action runs remain rejected and original receipt hashes are unchanged.
Replay evidence is
`runtime/evidence/aimed-outcome-replay-20261020-e22930bbe4a340f9828d8322d8c1985f/verification.json`.

The lower-latency native path is now built and independently reviewed. It parses
only complete critical records through the existing bounded, end-anchored
parsers, processes each once, and retains the original age/reset history of
incomplete fragments. Aimed log polling runs every 5 ms; pose requests remain
at least 50 ms after completion of the previous request. Healthy endpoint/world
guards and original permit expiry remain intact. All three tools HTTP integration
suites pass, including a split closing brace, dispatch before any later newline,
and no replay when the separator finally arrives. The subsequent first-click
run above verifies prompt response in the actual games.

**First revision 4 live attempt: click capture passed; aimed break not verified.**
Run `0565b12d8af64ad7980a7999b870e844` admitted one physical break intent and
its KCD camera sample without the previous origin/capture rejection. The user
reported that the stone disappeared when clicked. However, native logged
`queued aim expired or reset` before any `AIM_REQUEST`; Minecraft received no
aimed action. The disappearance was engine-session cleanup after transport
closure, not a confirmed vanilla break. The guest exited normally with an
explicit failed-session receipt. Engine cleanup, independent input-end
acknowledgement and frame-cap restoration passed.

The saved log combines queue expiry, pose readiness and generation checks, so it
cannot establish which condition fired. The observed click-to-Lua dispatch was
80 ms, while permit installation to camera capture already took 275 ms.
The native repair now separates expired unsent intents from authority failure,
records original permit ages, and reduces the minor2 receive wait from 25 to 5 ms.
The bridge suite passes 1,806 checks, including a deterministic loopback case
that holds an admitted request beyond 500 ms, verifies no socket request/result
and retained arena/seed state, then completes a new fresh request. Stale authority
still closes the session. Simulated HTTP aimed integration also passes.
The PowerShell audit passes 88 checks and keeps local drops separate from guest
actions; the strict bounded live proof cannot certify a dropped intent.
A new live test is still required; no successful crosshair result is claimed
from this run.

**Aimed-control repair: actual Minecraft regression passed; revised renderer
awaits live KCD verification.** The interrupted October 13 run
`5334822edbd5464397d6131962ff576e` bootstrapped its seed stone, but confirmed no
aimed action. Four physical clicks reached native validation: three were refused
by the bridge and one was stale or unready. The three captured origins were
0.177945, 0.157205 and 0.150575 metres from the mapped guest eye, exceeding its
previous 0.15 allowance. The HUD ended after about 11 seconds with
`world_click_delivery_failed`; the saved renderer log also records capture
revocation for lock contention. The log does not identify the contending caller.
Java and native processes exited normally, engine cleanup and input-end
acknowledgements passed, and the temporary frame cap was restored.

Mapped request-view origins now allow 0.25 metres on both native and guest
paths. This preserves the captured ray, 0.15 anchor/current-host agreement,
4.5-unit range, original permit expiry, ownership and Minecraft's actual
interaction-reach checks. Specific native refusal reasons replace the previous
generic bridge refusal. Actual Minecraft run
`7291a5e04c4c44ec983f44be9e50447e` passes **25 scenarios**, including the measured
offset, the 0.25 boundary and rejection immediately beyond it. It retains four
confirmed placements and four breaks, final air, zero owned/pending work,
restored options and normal exits. Host rays are synthetic; KCD was not connected.

Selective renderer revision 4 separates read-query contention from failed
capture mutations. A busy query grants no authority and cannot extend the
original lease; forwarding waits for validated capture and neutral controls.
Capture request/release contention still revokes ownership. World-click
diagnostics record distinct refusal reasons without creating physical-input
records. The revised renderer has its own build and profile; revisions 1–3
remain frozen. See the [renderer repair record](research/HUD-COMPOSITOR.md#capture-query-contention--2026-10-20)
for deployment and verification status.

Revision 4 is now built, independently reviewed and installed unarmed, with both
changed revision 3 files backed up. Seven native renderer/input suites pass
1,897 checks; the revision matrix passes 369 checks under PowerShell 5.1 and 7.
Existing world/selective profiles pass 110/142 checks, and the aimed controller
passes 68. The native bridge and simulated HTTP aimed integration pass, as do
the full Fabric build/remap and 3,819 protocol checks. Build/installation
success does not establish live targeting.

With KCD closed on October 20, the expired arm from the failed run was preserved
in its original evidence directory using the default closed-game archival path.
No new KCD test has run during these repairs. The next manual check is one
stationary, aimed break of the seed stone; previously verified hotbar/inventory
and fixed-cell interactions do not need a separate repeat.

## Earlier implementation and verification

**Bounded aimed HUD controller: implemented; actual HUD adapter verified in
Minecraft. Actual KCD crosshair verification is next.** `Start-AimedHudLab.ps1`
initially selected the selective revision3 renderer, offscreen presentation and
temporary 60 FPS host cap. Its explicit mode routes physical click edges through
the original acknowledged Minecraft permit and validates separate guest, native
and engine receipts. Legacy fixed-cell defaults are preserved. Both the controller
and direct arming helper reject mismatched guest/profile combinations. No KCD
launch, renderer installation or frozen bundle replacement occurred for this work.

Actual Minecraft run `621e1eaf8c7d4de3970637fdfdc9667d`, in
`runtime/evidence/hud-aimed-bridge-20261013-201501-621e1eaf8c7d4de3970637fdfdc9667d`,
passes on its first attempt. A fresh `MineCome-HudStream-UUID` save exercises the
production `HudAimedStoneBridge`: one vanilla bootstrap placement, one aimed
network break, independent client/server confirmation, matching native result and
block events, then independently observed final air. It ends with zero owned
stones or pending work, restored options, a persisted save and normal
Java/wrapper/native exits. Source and native hashes stayed stable through the run.
Arming and host rays are synthetic; the fixture neither renders the HUD nor
connects to KCD or verifies physical input.
The final PowerShell validator also passes a read-only replay of this unchanged
receipt plus 20 tamper rejections. Its original snapshot and evidence remain
preserved; this validation required no repeat game run.

The Minecraft build/remap passes, including 3,819 protocol checks, aimed mode/proof
checks (9/49), and existing HUD gate/proof/mode checks (51/227/2,048). Controller
coverage passes 68 aimed cases and 1,009 legacy cases; the aimed relay passes 73.
Mouse/world/selective/revision profile regressions pass (23/110/142/269), with the
latter three also checked under PowerShell 5.1. The PowerShell bootstrap preserves
explicit Java/bundle paths and passes nine cases under both PowerShell versions.

Review found that replaying the growing relay JSON journal could take roughly
442 ms, exceeding the 250 ms physical-edge limit. Dispatch now checks ownership
and the exact original permit acknowledgement, followed immediately by foreground
and freshness checks. Full historical correlation runs outside that path. The
representative 289 KB journal test takes approximately 23 ms when warmed; external
ownership/HTTP calls are mocked, so this is not an end-to-end live latency claim.
Original native/guest permit expiry remains enforced. Native shutdown now waits
for both replica cleanup and the separate input-gate end acknowledgement; its
simulated-engine integration passes with the second acknowledgement delayed.

The next live check keeps the player still, turns to the seed stone and breaks it
with the crosshair. The seed lies along world +X, independently of the initial
camera direction. Automatic reseeding and rapid inventory changes during a
pending block action remain outside this first check. Commands and limits are in
[aimed controls](research/AIMED-CONTROLS.md).

The read-only host sampler now has an actual KCD receipt:
`runtime/evidence/aim-probe-20261013-202430-c09cec132527421f8f934ad8ba36f361`.
It verifies the current camera origin/forward and a known-clear 4.5-unit
`ent_all` segment with player exclusion in official tools PID2140. The source
snapshot matches its hash, and camera/obstruction share the same engine time.
No movement, block mutation or aimed action was dispatched; this sample does not
establish visual crosshair alignment.

Preflight then found the expired activation from run
`70ed9e3b395d44a48993f9d59c89dac5`. The newly started renderer logged
`config_target`, so that old PID/start pair had never activated this process.
The explicit `Archive-HudArm.ps1 -ExpiredPriorProcess` path now checks the exact
receipt/INI identities, expired lease, absent original target and producer IDs,
and the pinned newer official-tools process before preserving the file in its
original evidence directory. It passes 29 pure checks under PowerShell 5.1 and 7
and existing profile regressions. Actual archival passed with PID2140 left open,
and the aimed controller's preflight then passed. This does not permit a second
accepted HUD session in one game process; default closed-game archival is unchanged.

**Earlier aimed host-control milestone: implemented and compiled before the
bounded live controller above.**
The explicit tools-host aimed mode maps replicas through the exact acknowledged
arena, waits for the engine bootstrap receipt, then installs original Minecraft
permits in a separate Lua gate. A physical-click selector admits only an unused
permit acknowledged before that click. Lua samples camera and obstruction in the
same callback; native validation retains the original permit age and generation.
The new aimed HUD adapter uses actual Arena actions and a separate readiness/proof
contract. At this stage the existing live controller and fixed-cell controls were unchanged.
No KCD launch, add-on installation or frozen live-bundle replacement occurred.

The native Release build and all **30 CTest suites pass**, including existing
stone/input HTTP tests and the new simulated-engine aimed integration. The latter
checks exact alignment, bootstrap acknowledgement, original permits, matching
Lua receipts, stale/replayed/refused captures and replica cleanup. Lua intent
coverage passes 569 checks; the existing aim sampler passes 1,533. Physical-edge
admission passes 23 checks under both PowerShell 5.1 and 7. Guest mode and proof
contracts pass 9 and 48 checks; the proof validator replays exact owned cells
rather than accepting cleanup from action counts alone. These contracts do not
establish an actual integrated aimed HUD/KCD session.
The full Fabric build/remap also passes, with 3,819 protocol checks and the
existing HUD gate/proof/mode checks (51/227/2,048).

Actual Minecraft regression run `96d8cf1be9224d2d95dac6fc314c99e1`, in
`runtime/evidence/aimed-stone-20261013-200034-96d8cf1be9224d2d95dac6fc314c99e1`,
passes **22 scenarios** with synthetic host rays. The additional case queues a
valid break, revokes action authority before vanilla dispatch, then independently
checks unchanged cells on client and server. The run retains four confirmed
placements, four confirmed breaks, final air, zero ownership/pending work,
restored options and normal Java/wrapper exits. Source hashes are stable.
The updated receipt validator passes 37 checks in both PowerShell versions.

The later bounded controller joining these components and validating the
distinct guest, native and engine receipts is recorded above; actual KCD crosshair
verification remains outstanding. Two limits remain explicit: replica cleanup does not prove the
separate Lua input gate ended, and changing the selected slot/stack after vanilla
dispatch but before authoritative confirmation can end the experimental HUD
session under the existing Arena contract. See [aimed controls](research/AIMED-CONTROLS.md).

**Public source repository.** The user made `gabrielpery/minecraft-kcd2` public;
GitHub metadata confirms public visibility and the existing `codex/initial-import`
default branch. README, setup and known issues now describe public cloning, the
verified prototype scope and fresh-clone prerequisites. Historical local evidence
and staged game artifacts remain outside Git. The PowerShell 7 bootstrap now
preserves an explicit `-JavaHome`; eight argument/exit-code regression checks
pass under both PowerShell 5.1 and 7 without launching a game.

**Aligned aiming over the bridge: implemented, compiled and verified with actual
Minecraft and a synthetic native host.** Optional protocol minor2 adds one
immutable arena agreement, expiring single-use guest permits, aimed requests and
explicit client/server-confirmed results. Both sides validate current session,
fresh camera poses, bounds and ownership. The host acknowledges the alignment
only after the consumer acknowledges previous-session cleanup. Existing minor0/1
callers retain their behavior; the live controller did not enable minor2 at this stage.

Run `e78ba82a6d23467eba714c1a82871983`, in
`runtime/evidence/aimed-bridge-20261013-193528-e78ba82a6d23467eba714c1a82871983`,
passes on its first actual-game attempt. A fresh UUID Minecraft world confirms
an initial vanilla stone placement, then receives a native C++ BREAK request
with an issued permit and aligned ray. Minecraft's real outline raycast selects
the stone's WEST face; the vanilla break is confirmed independently by its client
and integrated server. The native host receives both the terminal result and
removal event before sending GOODBYE. Final observations confirm air, zero owned
stones, no pending action, two sent events with none dropped, restored options,
a persisted save and normal Java/wrapper/native exits. Source and native-binary
hashes remain unchanged through the run. This verifies a networked Minecraft
action, not live KCD aiming or an engine-rendered replica acknowledgement.
The receipt validator passes 226 synthetic rejection/correlation checks under
PowerShell 5.1 and 7. Additional ID bounds found by those checks also pass a
read-only revalidation of this unchanged actual-game evidence; the original
validator is preserved beside the run's receipts. No repeat game test was needed.

The full native Release build and all 28 CTest suites pass, including legacy
tools-host integration. Focused coverage includes 1,578 native session checks,
414 existing codec checks and 336 aimed/shared-golden checks. The Fabric build
and remapping pass with 3,819 Java protocol checks plus existing stone/HUD
gate, proof and mode checks (51/227/2,048). No installed game renderer or frozen
live-test bundle was replaced. The later optional host-control implementation
is recorded above. See [the networked lab](../minecraft/README.md#aimed-stone-network-lab).

**Camera movement with HUD controls: live verified in revision 3.** The user
reports "it worked!" for camera movement before/after inventory, inventory cursor
control and stone place/break. Run `70ed9e3b395d44a48993f9d59c89dac5` reaches its
full 30-second activation deadline. Diagnostics confirm 2,704 pure helper-window
motions passed and 276 nonzero DirectInput X/Y observations passed through.
Three place/break cycles have Minecraft client/server and KCD engine evidence;
220 UI events were applied. Java and relay exited 0, cleanup completed and the
temporary FPS cap restored. The overall controller result remains failed because
14 Lua-admitted intents produced 13 guest/native results; the native relay
explicitly refused the final intent after peer disconnect. The verifier did not
distinguish that undispatched refusal from a missing guest reply. The corrected
verifier passes 330 relay and 1,009 controller checks plus a read-only replay of
the unchanged live evidence. Explicit terminal refusals remain separate from
completed Minecraft actions. The raw failed result is preserved. Free aiming
and continuous gameplay remain unfinished.

**Minecraft aimed actions: implemented, compiled and actual-game standalone
verified.** `AimedStoneArena` now selects owned stones with Minecraft's real
outline raycast and passes the returned face/hit point to vanilla actions.
Run `d388905d36fa4865892a77ce69cc572d`, in
`runtime/evidence/aimed-stone-20261013-191056-d388905d36fa4865892a77ce69cc572d`,
passes all 21 scenarios. All six faces are selection-verified; placement is
verified on UP and EAST, not all six directions. Four placements and four breaks
are independently confirmed by the client and integrated server. The run checks
nearest-block selection, a miss, unowned floor, host obstruction/unavailability,
stale data, eye/alignment mismatch and rejection of a reused request ID. Turning
the view after queuing does not change the pending target. All four cells used by
the fixture are rechecked as air on both threads, with zero remaining ownership,
no pending action, restored options, a persisted fresh UUID save and Java/wrapper
exit 0. Host rays and fixture teleports are synthetic; KCD was not connected.

The component permits one bootstrap and at most 16 confirmed stones in a bounded
5×5×5 volume, with immutable alignment, a 4.5-unit/500 ms host ray limit and
0.15-block agreement with the actual player's eye. Review fixed a preproof
scheduling race, consumed rejected IDs and strengthened proof/chunk freshness.
The earlier run `ee3a0b858a0841b9b7d0847bde2a1575` completed the same gameplay
checks but failed controller validation because Gson omitted a null failure
field. Its failed evidence is preserved. The corrected writer produces the
fully verified run above; 31 receipt regression cases pass in both PowerShell
5.1 and 7. Fabric build/remap succeeds; existing protocol and stone gate/proof/
mode checks pass. The default bridge, live HUD controls and installed renderer
remain unchanged. Shared alignment and transport have since passed the network
lab above; the newer source integration and remaining live controller work are
recorded at the top of this page.

**Crosshair targeting groundwork: read-only host aim sample implemented and
standalone verified.** The new separate Lua probe captures camera origin/forward
and nearest host obstruction in one call. It checks every hit, distinguishes
unavailable data from clear space, and makes no game-state changes. Fourteen
mock-engine groups pass 1,533 checks; host receipt validation passes 343 checks.
Its caller preserves source/log evidence and pins the existing tools process.
This read-only probe alone does not verify a live ray sample or live KCD aimed
action. The separate minor2 alignment/network result is recorded above. See the
[aim sample contract](../protocol/PROTOCOL.md#read-only-host-aim-sample-implemented-no-aimed-request-enabled).

**Selective capture implementation and earlier checks.** A separate
API v2 renderer preserves DirectInput camera axes while capturing world buttons,
then captures the full mouse for Minecraft inventory. Screen transitions drain
old input and require matching UI acknowledgements and rendered screens before
forwarding clicks. The selective compositor compiles and its 107 forwarding
checks pass; the previous three input variants still compile independently.
The final native adapter passes 775 checks; Selective/World/Mouse profile suites
pass 142/110/23 under both PowerShell 5.1 and 7. The pinned custom runtime build
passed source/provenance checks. Installation changed only the owned proxy and
addon after a verified 1,013-file save/profile backup, initially unarmed.
The first live attempt loaded the runtime and received frames, then stopped
before F8 because the controller misread an ordered-dictionary arm receipt.
That controller-only fix now passes 1,008 checks, including direct and JSON
receipt representations. That first attempt exercised no selective controls.
The subsequent run `ef8f44bfc62944faaf2bfea7dda8c091` completed two place/break
cycles in both games and delivered 85 inventory/key events. The user confirmed
everything except camera movement worked. ReShade's window/raw-message filters
still block movement despite the DirectInput repair. A separate revision 2
admits only owned, settled world-motion messages while retaining button capture;
its 223 policy/adapter checks, three upstream-SDK compilation checks, addon and
full runtime builds pass. Live camera verification remains outstanding. The live controller also
correctly retained failure because its last target-absent receipt was lost on
graceful relay disconnect. Java exited normally, cleanup completed, and the
temporary FPS cap restored. This run is partial evidence, not an overall pass.
Revision 2 has now been installed through the human-run restart after a verified
1,015-file save/profile backup; the fresh host loads the motion add-on unarmed.
The repaired relay journals matched results before disconnect while preserving
all command and game-write reset gates. Its 1,086 native, 275 relay and 1,008
controller checks pass. Fresh run `27420095abc54651ae5d3ec5bbbc7369` passes the
controller and confirms one place/break cycle plus 97 UI events, with normal
cleanup and restored FPS. The user confirms inventory and stone interaction,
but camera look still fails. The new counters show 1,333 passed window-movement
messages and zero nonzero DirectInput X/Y observations. The registered raw-input
helper-window path is a source-backed repair target; its use by KCD is
not yet directly established. The user confirms normal KCD camera movement
returns after Minecraft closes. Revision 3 now binds the helper exception to
the same-call resolved owner and successful mouse registration while retaining
foreground, lease, mode and pure-relative-motion checks. It passes independent
review, 138 focused native checks and a fresh pinned runtime build. The separate
runtime 6.8.0.5/addon bundle is staged; 544 profile checks per PowerShell version
and 1,008 controller checks pass. The exact revision 2 to 3 update preflight
passes. The human-run restart verified a new 1,016-file save/profile backup and
installed revision 3 unarmed. The fresh host loads the raw-owner addon and HUD
shader; live preflight passes. The completed revision 3 result is recorded above.
This still operates the fixed stone cell. Shared Java/C++ aiming geometry passes
198/222 assertions against the same golden vectors, but no aiming protocol or
live crosshair interaction has been enabled. See the
[selective capture record](research/HUD-COMPOSITOR.md#selective-camera-capture--2026-10-13).

**Physical world clicks: implemented, built and live verified.** Run
`62b35872e09d44a3b6b3a5474131e24e` passed four physical clicks and two
place/break cycles, with the user's report: "it worked fine." Both games confirmed
the operations, final air and cleanup; Java/relay exited 0 and the temporary host
FPS cap restored to -1. No keyboard or inventory events were needed. Focus loss
ended activation after 13.719 seconds, so this is not a full 30-second endurance
or inventory-transition check. The separate World profile maps fresh right/left
presses to the existing authenticated place/break relay. It uses the actual
selected Minecraft stone stack and client/server confirmations, with no timed
placement sequence. Inventory transitions retain button ownership; held presses
cannot become world actions. The existing mouse-only profile is preserved.
The bounded check intentionally freezes KCD mouse look for up to 30 seconds and
still targets one verified nearby cell. Free aiming, arbitrary blocks and normal
continuous play remain unfinished. See the [World profile record](research/HUD-COMPOSITOR.md#physical-world-click-profile--2026-10-13).

**A real Minecraft stone block is now visible in a loaded KCD2 development world.**
The user's 2026-10-11 screenshot and matching game logs verify this first live display,
alongside communication between both real games. A second user-provided screenshot
verifies the texture sharpness fix, with crisp front and side faces. Occlusion, parallax and full
coordinate calibration remain separate checks. Real Minecraft placement and breaking
have also made the stone appear and disappear in KCD2, confirmed by the user's live
observation. The final automated two-game run passes matching engine spawn,
deferred removal and cleanup acknowledgements with zero owned/pending replicas.
No retail native-engine hook is enabled.

**Combined HUD and stone guest: implemented, built and standalone verified.**
One owned Minecraft world now supplies genuine HUD pixels, selected inventory
items and vanilla block interactions through the existing authenticated protocol.
The fresh run `11f348f356984192a50f20d858d3ba30` passed eight UI events and six
requests: two placements, two breaks, and placement refusals for dirt selection
and an open inventory. All four changes had fresh client/server agreement; the
target ended as air, inventory stayed unchanged and Java exited normally.
The host peer was synthetic and KCD was closed. Live arming explicitly rejects
this fixture. The follow-on explicit `-StoneLive` controller now connects the same
guest to the real relay and verifies owned cleanup; its combined live check passes below.
See [combined guest evidence](research/HUD-COMPOSITOR.md#combined-hud-and-stone-guest--2026-10-13).

**Combined live controller implemented and built:** after physical F8 activation,
it sends one stone intent through KCD's existing console API, waits for both actual
Minecraft confirmation and a KCD engine spawn acknowledgement, then requests a break
after ten seconds. Exact process/session checks, an owned token, immutable deadline,
matching guest/native receipts and graceful relay cleanup are required. A fresh
standalone real-Minecraft regression passed after fixing a transient Windows file
sharing collision in the test peer.

**Combined live HUD and blocks verified:** run `a80522b281a64a238e8d66a61dee7fbe`
passes, and the user confirmed seeing both the HUD and stone appearance/removal.
The same guest's selected stone produced one client/server-confirmed place and
break; KCD acknowledged spawn, removal and zero-owned cleanup in one session.
The guest published 577 frames; KCD uploaded 559 and submitted 2,330 draws with no
upload drops. Java and relay exited normally, and the temporary 60 FPS cap restored
to -1. Focus loss ended input after 18.375 seconds, after the block cycle completed;
this is not another full 30-second test. Physical world-click evidence is recorded
in the newer milestone above.

**Current UI milestone: live Minecraft inventory mouse control inside KCD2.**
The user confirms the physical test worked. All 639 events were acknowledged,
including 635 pointer events with 20 clicks, 26 drag callbacks and 32 wheel calls.
The full 30-second activation ended on its timer, with KCD still in foreground,
fresh frames/ACKs and normal Minecraft exit 0. The hook recorded 1,535 immediate
state suppressions and matching drains, with zero drain failures. Its release
receipt still marked the final drain pending, so final native drain completion
and general host input exclusivity are not independently claimed.
The user noticed the guest window reappearing and lag during shutdown; cleanup
restored visibility before the seven-second save/exit path. The repair is now
compiled and independently reviewed: the explicit live-mouse guest stays hidden
through exit, with truthful cleanup evidence and actual Java exit verification.
Its automated checks and live hidden-window/process-exit diagnostics now pass in
the combined stone run. A separate user judgment of no-popup behavior was not requested.

**Inventory responsiveness:** mouse-enabled offscreen inventory now captures once
per rendered frame under the existing 30 FPS guest cap. A real isolated Minecraft
run completed all 43 pointer-fixture events and 11 inventory stages: successful
inventory captures averaged 32.9 ms apart (about 30 Hz), while hotbar captures kept
their existing cadence. All 692 focused Java checks and review pass. There were
no readback busy skips or fence-timeout polls; Minecraft exited normally. This is
standalone evidence, not a KCD display-rate or end-to-end latency measurement.
The next inventory session still needs to confirm perceived smoothness. The
combined stone run verifies hidden-exit diagnostics without opening inventory. See the dated evidence in
[HUD research](research/HUD-COMPOSITOR.md#inventory-capture-cadence--2026-10-13).

**Earlier keyboard milestone and accepted HUD size:** The user accepted the sizing in the earlier run
and now confirms "done, no kcd menu opened, worked" with the updated add-on.
Ten physical press/release events for 1, 2, 9, E and Escape were delivered and
acknowledged, including actual Creative inventory opening/closing. The latest
Minecraft run published 493 genuine frames and KCD uploaded 471. The hidden guest
and temporary 60 FPS host cap completed with real closed ACK, full cleanup and
restoration to the original uncapped KCD setting.

This verifies the short keyboard sequence, the reported absence of a KCD menu
during it, and live sizing. The diagnostic build records foreground loss after
15.766 seconds: KCD's window stayed valid/visible, but Explorer owned foreground;
ACK/image ages were only 19/47 ms. This is the intended focus-loss stop, and no
native gate fix is indicated. The later mouse run above now verifies the full
30-second duration; the earlier uninstrumented 10.47-second stop still has no established cause.
Minecraft saved and exited normally with code 0 in both runs.
All nine slots and server-confirmed stack swapping remain separately verified by
the standalone 31-event fixtures. Opt-in host HUD suppression is now implemented
and live setting/readback restoration passes; its combined visual result remains
unverified. General KCD input exclusivity and health integration remain unfinished.
Earlier failed runs and their evidence are preserved below.

The follow-on guest update handles vanilla drag ownership, wheel sensitivity,
and button releases across inventory closure. A separate opt-in 43-event fixture
now verifies real stack splitting, drag distribution, scrolling and held-button
close/reopen behavior, with fresh integrated-server inventory observations at all
11 stages. All events ran in the hidden, unfocused Minecraft guest. This is
standalone guest evidence. The separate physical mouse profile has now also
completed the live run summarized above.
The reviewed native first-close diagnostic build is now
installed and has supplied the live foreground-loss evidence above. See the
implementation record in [HUD research](research/HUD-COMPOSITOR.md).

A separate pinned ReShade 6.8.0 full-add-on source build now extends the existing
DirectInput hook with a 100 ms renewable inventory mouse lease. The add-on forwards
client-relative pointer positions, left/right clicks, drag and wheel events to
actual vanilla screens, and draws a cursor over the genuine Minecraft pixels.
Unknown devices/layouts, stale state or lost focus refuse or end capture. Closing
inventory releases the guest buttons before returning physical input to KCD.
The keyboard build remains separate.

The mouse profile passes five focused native/shader suites, 590 Java checks,
23 profile/rollback checks under both PowerShell 5.1 and 7, and a fresh real
43-event inventory fixture. That fixture ran with KCD closed: all 11 stages,
fresh server observations, 218 published/216 received frames and normal exit 0
passed. This is standalone evidence. The custom proxy/add-on were installed
unarmed after backing up 1,010 save/profile files and the previous renderer.
Live loading and inventory interaction now pass; general camera/input exclusivity
remains a separate qualification.
The installed configuration also skips ReShade's persistent tutorial prompt;
its brief startup/loading splash remains enabled.

**Current build: interactive one-cell stone controls live verified.** KCD console
commands `minecome_place`/`minecome_break` now request real Minecraft vanilla
actions through an opt-in minor1 protocol. Both real games now confirm placement
and removal after the relay log-framing fix; the user confirmed seeing the stone.
Both games stayed open during repair.
The earlier visual milestone and automatic mirroring proof remain historical;
the separate recovered-session receipts verify the new control commands.

**Current movement milestone: bounded coupled movement live verified.** Real vanilla
Minecraft walking, jumping and landing use a static, approximate patch sampled
from live KCD2 terrain. Fresh integrated-server poses now move KCD2's player;
delayed player/camera readbacks and restoration pass. KCD-focused keyboard/mouse
forwarding and full-world movement authority remain unfinished.

**Current movement-input milestone: external records drive real Minecraft.** A fresh scripted
producer now passes actual client/server walking, jumping, landing, yaw/pitch changes
and terminal key release in a new isolated world. Physical KCD movement-input delivery remains
unverified. The new consumer lab has no KCD movement follower.
Explicit key bindings and a session-bound starting camera are now implemented.
The updated Minecraft lab adopted the supplied initial angles on both sides and
completed its movement/view proof; the new KCD capture path still awaits a live run.

## Evidence matrix

| Feature | Source/build | Standalone verification | Actual game verification |
|---|---|---|---|
| KCSE adapter/version metadata | MineCome.dll Release built against actual KCSE API | DLL exports, wrong-version refusal, load/lifecycle/shutdown passed | Not loaded in retail; map/loader prerequisite missing |
| C++/Java wire codecs | C++20 and Java21 bytecode built | Protocol/coordinate tests, adversarial framing/auth/timeout/reconnect test passed | Real Fabric client connected |
| Java checks | Updated Fabric build succeeds | 3,428 protocol/socket checks,25 smoke timing checks and17 input-gate checks passed | Earlier dynamic smoke and new real console-driven client/server placement/removal verified |
| C++/Lua tests | Updated Native Release succeeds | Eight CTest suites pass across focused runs:414 protocol checks,1,017 mailbox checks, stone mapping/receipt tests,57 real-Lua lifecycle cases, legacy and interactive HTTP fixtures | Lua/HTTP engine bindings in these tests are simulated |
| Cross-language state/events | Native host and actual Java codec | Final run:55 host poses,56 guest poses,1 synthetic block event in integration.mjs | Explicitly synthetic peers for this check |
| KCD Lua/debug integration | Original manifest/script and C++WinHTTP adapter | Parser, quaternion basis, explicit FOV tests passed | Official1.5.5 game initialized module; loaded Trosky player/camera, HTTP Ping and Minecraft receipts verified |
| PowerShell debug requests | PowerShell7 helpers implemented | Direct loopback, disabled proxies/redirects, capability checks, response limits and absolute body deadline regression passed | User invoked Ping, Pose and ShowStone successfully against the loaded world |
| Two real game processes | Fabric plus official tools relay | Transport shared with tested core | User-run world test:449 KCD player/camera samples,1562 Minecraft poses,2 block events; game log confirms both event receipts |
| Minecraft player/camera | Fabric snapshots on actual client ticks | Finite fields/space validation | Unique flat world, actual player/camera/eye positions sent to host |
| Vanilla placement/breaking | Uses vanilla Creative inventory/interaction packets | Test checks both client and integrated server | Server/client stone after placement, air after break; native harness received add/remove events |
| Transient stone mirroring | Native copied mailbox, console consumer and original Lua sink built; current source loaded separately from the open package | Ordered ACKs, deferred deletion, finite bounds, missing ACK, Begin rejection recovery, failed cleanup, reconnect, harness rejection and lease cases pass | User confirmed appearance/removal from vanilla MC placement/break. Final real two-game run passes exact Begin, spawn119, deferred removal442 and cleanup ACK with zero owned/pending replicas |
| Interactive stone input | Original Lua commands, minor1 codec/mailboxes, native relay and fixed-cell Creative lab compiled; log-framing fix built and relay replaced while games stayed open | Exact request/action/result, capacity, replay, expiry, generation, cancellation, stale HTTP backlog, unterminated engine log tails and action gates pass | Real commands drive vanilla client/server stone and air, with matching KCD spawned/removed receipts; user confirmed seeing placed stone |
| Read-only ground query | Separate original Lua probe and exact-version/process/hash/HTTP-owner-gated PowerShell controller implemented |13 focused cases pass in real Lua5.2 with simulated engine bindings | One actual terrain ray returned finite hit position/normal/distance; hit height exactly matched the independent terrain elevation query. No movement or geometry streaming verified |
| Sampled-ground movement lab | Fabric1.21.1 collision mixins, bounded25-point Lua sampler and isolated lab compile; remapped JAR assembled |85 parser/coordinate/shape/sequence checks and14 real-Lua sampler cases pass | Real KCD2 supplied25 valid terrain hits; real Minecraft client/server walked1.2915m, became airborne, and landed on imported approximate slabs with literal underlying blocks remaining air. KCD2 movement not applied |
| Bounded coupled movement | Java trace assembled; PowerShell receiver/controller and game-thread Lua follower implemented |126 Java ground/trace checks,25 Lua follower cases with simulated bindings,15 final receiver cases pass; final guards also validate the historical live trace offline | Real Minecraft vanilla client/server walking, jumping and landing;22 forwarded server frames,21 delayed KCD player/camera readbacks, exact starting-position restoration and normal Minecraft exit0 |
| Lua input observer | Short leased callback wrapper preserves original callback and restores only its own handler |20 simulated-binding Lua cases pass |Final timed human check captured three real jump/press/value1 callbacks,13.5983m player displacement and view changes; watched walking/mouse callbacks were absent. Callback restored. Full input forwarding remains unfinished |
| Windows walking/mouse source | Separate read-only C++20 helper and pure Java decoder/session gate compile; Fabric JAR reassembled |598 native state/wire checks and148 Java framing/identity/lease/mouse checks pass |Actual15s OS registration/cleanup and301 neutral records pass; Java validates the exact historical recording. Physical control delivery remains unverified |
| External input applied to Minecraft | Bounded daemon file reader, game-thread lab and PowerShell controller compile |266 reader checks with zero skips,148 decoder/gate and126 ground checks pass |Fresh scripted producer and synthetic flat ground drive real Minecraft client/server walking0.8571695m, jump/landing, yaw/pitch, terminal neutral controls, zero post-settle corrections and normal exit. No physical KCD input or coupled authority claim |
| Starting view and key bindings | Read-only Lua camera capture, strict Java view seed and configurable native capture built |75 Java view checks,23 simulated-engine Lua cases,125 binding checks plus598 state checks;16 PS binding and14 marker cases pass |Actual MC client/server adopted synthetic yaw45/pitch−10, walked1.0727511m, jumped/landed and applied mouse once. New KCD capture and physical remapped keys are not yet live verified |
| Minecraft block model/atlas | Actual BakedModel and GPU atlas exporter built | Six quads,24 vertices, atlas bounds checked | Real1024×512 atlas exported and visually inspected |
| CryEngine block asset | Original OBJ→FBX converter plus installed official RC | FBX→CGF and texture TIFF→DDS compile succeeded; pixels compared | User screenshots show Minecraft stone in KCD2 world and verify the sharpness revision |
| World position/scale/depth | Algebraic hypothesis/tests | Known basis and inverse tests | Live entity bounds span1×1×1 engine units; depth/parallax and cross-game calibration still unverified |
| Original saves protection | Backup script | 982 copied files SHA256 verified | Original saves were not opened for the tests |
| Static Minecraft UI composition | Actual vanilla capture and original ReShade D3D12 add-on built | 36 Java capture checks; reset and aspect-fit contracts pass | User confirmed HUD visible in KCD2; logs record all three snapshot submissions and lease expiry |
| Continuous vanilla UI transport | Java21/JNA producer, bounded Win32 channel and native receiver built | 168 Java stream checks and 146 native checks pass; existing 36 snapshot checks still pass | Fresh real Minecraft world sent 344 nontransparent frames, four vanilla UI states, pause/resumption and closed marker to standalone receiver; no KCD compositor was armed |
| Continuous KCD UI compositor | Separate exact-tools D3D12 add-on installed with aspect fit, persistent texture and fenced upload slots | Native contract/lifecycle review and checks pass | Latest live run uploaded 471 frames/submitted 1,973 draws with zero drops; earlier user-accepted HUD size preserved. KCD's duplicate HUD remains |
| Reverse HUD input and background presentation | Separate exact-identity input channel, bounded hidden/offscreen presentation and callback-based focus readiness built | Hidden fixtures pass all 31 events, nine slots, inventory open/close and server-confirmed swap | Ten physical 1/2/9/E/Escape press/release events acknowledged/applied; user confirms controls worked with no KCD menu. The later mouse run completed the full 30 seconds; general host exclusivity remains unverified |
| Render-driven inventory capture | Mouse-enabled offscreen inventory captures once per rendered frame with the existing 30 FPS cap; hotbar timer unchanged | 45 cadence checks plus 647 pointer/stream/input/cleanup checks pass; actual 43-event Minecraft fixture measured mean 32.9 ms inventory capture intervals with no PBO busy skips/timeouts | Updated inventory cadence awaits a live inventory check; the combined stone run verifies hidden-exit diagnostics and normal Java exit |
| Inventory pointer lifecycle | Single active drag button, screen-owned releases, vanilla wheel scaling and explicit live opt-in built | 45 pointer policy/state, 192 stream/receipt and 353 input checks pass; actual hidden 43-event fixture verifies splitting/drag/scroll/held-close at 11 stages | User-confirmed physical mouse interaction; 635 pointer events and actual click/drag/wheel callbacks applied |
| Combined HUD and stone guest | Existing HUD world and selection drive vanilla stone interactions; explicit live relay controller and guest profile built | Actual Minecraft passed eight UI events, six authenticated requests, two placements/two breaks with client/server agreement and two exact placement refusals; unchanged inventory, restored cell and normal exit. Live controller lifecycle/receipt tests and native relay integration pass separately | User confirmed combined HUD and stone appearance/removal. One real client/server place/break matched KCD spawn/remove/cleanup, with normal Java/relay exit and restored FPS. Physical block controls remain unfinished |
| Host inventory mouse capture | Original pinned ReShade hook, API, add-on and cursor shader built; exact bundle installed | 56 native capture/SDK adapter checks, 95 forwarding/diagnostic checks, 338 input checks and both FX compilations pass; 23 profile/rollback checks pass in PS5.1 and PS7 | Full 30-second live activation, 1,535 immediate suppressions/drains and zero drain failures; final drain completion/general exclusivity not independently verified |
| Temporary host GPU-budget comparison | Shared opt-in Lua/PowerShell helper and live controller integration reviewed | 22 simulated-engine Lua cases and 98 assertions across 11 simulated-console scenarios pass; capped standalone fixture passed | Latest combined live run passed with verified −1→60→−1 restoration through requested End before expiry and timer cancellation |
| Bounded host HUD suppression | Opt-in `-HideHostHud` in the Live input lab; documented whole-HUD CVar, engine-timer writes and independent finally restoration | 29 simulated-engine Lua cases and 397 controller checks pass, including both HUD/FPS cleanup after failure | Actual tools `wh_ui_ShowHud` readback passes 1→0→1 and timer cancellation. Combined visual scope, subtitles/dialogue behavior and health integration remain unverified |

## Current artifacts

- Native DLL: `build/native/kcd2/Release/MineCome.dll`.
- Fabric runtime mod: `minecraft/build/libs/minecome-fabric-0.1.0.jar`.
- Official development bridge: `build/native/kcd2/Release/minecome_tools_host.exe`.
- Actual Minecraft model: `minecraft/run/minecome-export/stone/stone.obj`, `stone.mtl`,
  `block-atlas.png`. Source is actual vanilla baked geometry, not a handmade cube.
- Compiled CryEngine model: `runtime/compiled-block/Data/objects/minecome/stone.cgf`,
  `stone.mtl`, `block-atlas.dds`, with hashed provenance and live_draw_verified=false
  for each new compilation. A separate human verification record confirms the
  latest revision's live display and sharp appearance; compilation alone never sets it.
- Actual gameplay image: `minecraft/run/screenshots/minecome-smoke-placement.png`.
- Preserved Minecraft proof: `minecraft/evidence/live-smoke-final.log`.
- Native receipt proof: `runtime/logs/minecraft-final-world-peer.log`.
  Final real Minecraft run sent901 poses and2 actual stone add/remove events to the
  explicitly simulated C++ host; this is not a loaded KCD2-world gameplay test.
- KCD game command receipts: `runtime/logs/tools-live-evidence.log` and preserved
  `runtime/logs/tools-before-map-restart.log`.
- User's actual world proof: `runtime/evidence/live-world-20261011/user-screenshot.png`
  (4480×1440, SHA256 `fb01d17104c41006439ca5193fa1ce0c3bfc2075d43d832989185da4ef7716f9`).
  That directory preserves Minecraft/relay logs, KCD command receipts, and the
  original blurred material's compilation/deployment fingerprints before revision.
  The screenshot is human-provided evidence, not an agent-controlled GPU capture.
- Sharpness proof: `runtime/evidence/sharp-stone-20261011/user-screenshot.png`
  (SHA256 `66e83cf7df3b59562652c7197ce5a6a07dec0d6c9c7eb81951eaafeae893d0b9`).
  That directory preserves compilation/deployment fingerprints and `verification.json`
  linking the user's explicit confirmation and image to the unchanged staged package.
- Machine-specific inventory/hashes: `runtime/environment.json`.
- Existing saves backup: `runtime/backups/20261011-145242/kingdomcome2` and backup.json.

Runtime assets, game logs, worlds, credentials and backups stay local and ignored.
Source docs retain reproducible commands and the evidence summary.

The official-tools `Mods/minecome` package was updated only after verifying its
existing SHA256 against our own deployment record; its prior package/manifest were
backed up. The updated package contains the original transient entity test and actual
compiled Minecraft assets. The user successfully ran `scripts/Start-Kcd2ToolsTest.ps1`
after the agent's live-world launch was rejected by automatic review. All initial test game/host processes
have closed normally or been recovered as recorded. The user's then-loaded development
world stayed open during the earlier automatic mirroring tests; owned Minecraft/relay
processes saved/exited normally. The user has since closed KCD2.

Earlier Java hardening followed the initial live gameplay test and was verified with standalone
and loopback regressions: strict UTF-8/HELLO lengths, absolute fragmented handshake
deadline, empty GOODBYE, stale host pose expiry, bounded event draining and rejection
of invalid outgoing space/role. Previous Fabric jar SHA256:
`1421924607162227f56018c2bab9161146e92915bb2c5c508b16cba8dee1a1f5`.
The user then launched the final development sources through Loom and verified
communication with the loaded KCD2 world. The fresh Minecraft log records
`VANILLA_SMOKE_PASS`, host poses received=57, and normal world saving/shutdown.

## Phase status

0. **Reconnaissance/architecture/build system: implemented.** All requested source
   projects inspected and pinned; game/tools/dependency versions discovered. Official
   native framework limitations and a working debug alternative documented.
1. **Communication: live verified through official tools.** Real Fabric mod and KCSE DLL built;
   standalone C++/Java and real loaded-world bridge pass. The retail KCSE game
   initialization test remains blocked by the missing validated address library.
2. **Read-only state: live verified.** Actual Minecraft world positions and loaded
   KCD player/camera sampled and exchanged. A local bounded Minecraft-to-KCD
   follower now passes live player/camera readback and restoration. General
   calibration, FOV/projection and sustained movement authority remain unverified.
3. **First block: visible in live KCD2.** Native asset compilation, real world loading
   and display are verified by the user's test. Material sharpness is now live verified;
   occlusion/parallax need targeted visual checks. The user performed the launch
   after automatic approval review rejected the agent's attempt.
4. **Transient stone updates: live observed.** Actual MC feed drives
   a bounded KCD stone sink via acknowledged engine-console commands. World/session
   changes clear/reauthenticate; failed removal is retained/retried. The user confirmed
   actual appearance/removal. The final live rerun passed exact Begin/spawn/removal/
   cleanup receipts after handling deferred deletion. Persistent and general blocks
   are not implemented. First console-controlled single-cell placement/breaking is
   now live verified through actual Minecraft client/server and KCD engine receipts.
5. **Initial collision/movement prototype live verified.** Real vanilla Minecraft
   uses approximate sampled ground on both game threads and briefly drives KCD2's
   player/camera. General collision streaming, KCD input and sustained authority remain.
6–7. **UI foundation implemented; broader gameplay remains.** Static vanilla HUD
   display is live verified in KCD2. Continuous vanilla UI transport passes with
   real Minecraft and a standalone receiver; the installed streaming compositor
   now displays the HUD inside KCD2. Inventory input, hands, NPC/combat, terrain
   deformation, mobs and advanced features remain unfinished.

## Next concrete verification

The sharper material was compiled and staged in the owned official-tools package
(SHA256 `a6ad4df11600b78ff9102f3386f58ce22a5a93a3e706b8146f9fa9e75489083e`).
All262,144 DDS pixels match the original16×16 stone pixels repeated32×32, and
all24 remapped UV corners select the same source colours/orientation. Three official
RC stages passed; the DDS is512×512/1,048,712bytes and the material470bytes.
The point-filter hint is included but may be ignored by stock Illum. The user has
verified this asset-level mitigation in a fresh live frame: crisp front and side
faces, with the explicit report "Fixed it!". The installed package matched
the hash above at that verification. Its Lua sink has since been updated; the current
package hash is in `runtime/lua-deployment.json`. Previous owned packages are preserved.

`scripts/Start-BlockMirrorTest.ps1` runs against the already-loaded fresh official
development world. Real MC creates a new UUID lab, waits for fresh KCD player/camera,
places stone, holds15 seconds after client/server confirmation, then breaks it. The
native host uses a session-local display island, with CALIBRATED still false. The
user has confirmed appearance/removal; the final ordered removal ACK retest passed.
Parallax, occlusion and distance/minification quality remain separate visual checks.
Do not use newer retail saves in this build. In parallel, obtain/generate a verified retail
Steam1.5.6 address map and add a pre-hook loader compatibility gate before enabling
native engine access. Do not call either route playable based on an asset build or
handshake alone.

## Stone mirroring continuation

Updated Fabric JAR SHA256:
`c825108bc4f6a5089d8a9f35135d9ff90c6df65d27f251d4b665e97f010ca237` (52,377bytes).
Native7/7CTest passed with the original HTTP/engine/Minecraft fixture explicitly
labelled simulated; its local evidence is `runtime/tools-stone-fixture-*/verification.json`.
Lua lifecycle tests now cover46 cases in the existing Wireshark Lua5.2 DLL without
installing anything. This DLL uses simulated engine bindings; live receipts are separate.
The owned development package was hash checked, backed up, and updated while KCD2
was closed. It retains the same sharp Minecraft CGF/MTL/DDS contents.

The new actual Minecraft dynamic smoke passed against the explicitly synthetic
native host on38773: client and integrated server confirmed stone at16:26:24,
vanilla break issued at16:26:39, and both confirmed air at16:26:41. The native host
received exactly two events17.097352seconds apart; Java queued2/sent2/dropped0.
Evidence is `minecraft/evidence/dynamic-smoke-20261011`. This validates Minecraft
and the new timing/session transport; it does not establish a live KCD sink.

## Live dynamic stone continuation

`runtime/evidence/block-mirror-20261011-165548` preserves the actual two-game run.
Fresh Minecraft UUID0d0ff987-a4f6-4fec-9a75-d7b92349239f sent add/remove sequences120/441
at(-5,-60,-4). Both client and integrated server confirmed stone at16:56:37, vanilla
break followed at16:56:52 after the15-second hold, and both confirmed air at16:56:54.
The client queued2/sent2/dropped0 and saved every dimension before exit0.

KCD accepted exact session1791734195516527 and spawned the actual stone geometry with
one-unit bounds. It reported cleanup_pending for sequence441, then ended with
owned_count0/pending_count0. The native host received747 live KCD player/camera samples,
1,820 Minecraft poses and2 block events. The user explicitly confirmed: "Yes, it
appeared and disappeared." This is human visual observation; no new KCD frame was
captured. The archived Minecraft screenshot is separate (SHA256
b440d1ff0dc8cd1426b49ecbbbc159309b07f88617972006b208a00ee5802461).

The strict test correctly remained false for ordered removal ACK, because it ended
the session on pending deletion. Lua now retains the original removal metadata and
emits removed exactly once after actual absence; the native consumer waits within
the original two-second deadline. Seven suites including46 Lua cases pass.

The real VM rounded the previous numeric session1791733572711306 to1791733520138240;
no Apply was sent after that mismatched Begin. IDs now remain canonical decimal text
across the float32 Lua boundary. The numeric-ID failure is preserved separately in
`runtime/evidence/block-mirror-20261011-164527`. The current workspace source hash and
installed open package fingerprint remain distinct in each run record.

The final run `runtime/evidence/block-mirror-20261011-170737` passed with fresh UUID
ab32daa1-3972-4454-be0e-6d010ac2fd60. Exact engine session1791734901712424 acknowledged
spawn sequence119 at MC(-4,-60,-7); removal sequence442 emitted cleanup_pending then
removed for the same session and sequence. Engine End returned ended with zero
owned/pending replicas, and the native consumer recorded the matching cleanup ACK.
Vanilla client/server confirmed stone17:08:23, break17:08:38 and air17:08:40. Minecraft
saved all dimensions and exited0. `run.json` reports VanillaSmokeVerified=true and
EngineMirroringAcknowledged=true. VisualVerified remains false for this final rerun;
the prior user's explicit visual observation is recorded only against its own run.
The relay expired normally with placed1/removed1/rejected0/cleanup_acktrue,
717 fresh KCD world/camera samples,1,803 Minecraft poses and exactly2 block events.
Only the user's existing KCD2 process remained open when that run finished; it is
closed at the current continuation.

The loaded Lua snapshot and source both hash to
`ca643cf32442336ec375131287ee73a3df12aee505cf95e0b4ea75e27d914a81`.
The helper uses a fresh read-only snapshot path with Script.LoadScript and proves
evaluation by a changed function reference plus decimal_text_v1. Actual old-path
ReloadScript left functions unchanged and is not used as reevaluation proof.
Native tools host hash:
`85099fd5066080cd5ee4f81a6334e078409139927af30635cb1ac4c1778261a9`.
The updated package is prepared locally with unchanged sharp assets (SHA256
`bd1443b067de51cd9d31423cbe505b0e5584b4af7954a7fb915633e00eb2fc95`), but the user's
open game retains its recorded older package. Stage the prepared source with the
owned staging helper only after KCD2 closes normally. Every new test helper invocation
loads and verifies the current original Lua snapshot without replacing that open pak.

## Interactive build continuation

The first interactive implementation is source-complete for a bounded one-cell lab:
Lua registers two console commands and emits exact decimal-text request IDs;
the official-tools relay forwards fresh intents; Java client ticks invoke vanilla
Creative placement/breaking in a new UUID flat save. It performs no automatic
actions and has no automatic Minecraft exit. The existing real block observer and
acknowledged Lua display sink handle resulting changes. Result1 establishes dispatch
only; separate client/integrated-server observations and KCD engine receipts are
required before a live action is considered verified.

Checks are focused on changed features: input format/negotiation,16-slot mailboxes,
ID replay, one-second expiry, stale world/session/reset, explicit cancellation,
HTTP outage backlog and vanilla action gates. A stale log backlog defect was caught
and fixed: recovery cannot make old console intentions new requests. The focused
native HTTP fixture passes and is explicitly simulated in
`runtime/tools-stone-fixture-hcBK4s/verification.json`. Default minor0 behavior and
the legacy fixture also pass. Eight native suites passed across those focused runs;
Lua57, native protocol414 and mailbox1,017 checks; Java3,428 plus25 timing and17
action-gate checks. No live game was launched for this new feature.

Current remapped Fabric JAR:72,239bytes, SHA256
`2247d13ed2df216b6214eac83193e0b968c641bd9c4667bd32bcbc90fa51e69b`.
Current native tools host SHA256:
`1a32bbfde616304ef98e3c88da5c0541d1e7fc81aa55eb9fc0b8c708c4e5b8b0`.
Current original Lua:33,634bytes, SHA256
`54167f3b6e2628e23db09ab19c970584a5c81ab65c67806e25e51bc53bee9aa6`.
Offline package `build/packages/interactive-stone-20261011/data/minecome.pak` hashes
to `5447e70ce9315668574385c75121d2e719de492bbfe90bbc4c559efdef014ac9`.
Its four entries match current source and the unchanged sharp CGF/MTL/DDS exactly.

With KCD2 closed, the owned staging helper verified the old package/manifest,
backed them up in `runtime/packages/previous-20261011-211052`, and staged the
interactive source. Installed pak SHA256:
`04d9bc27f32a91ca04ef655157989bf46b93bc4c1f4f4cb92302e783109578fc`;
manifest SHA remains `dbb73b2152507136b9c56ab7b8558feabef7c524c40009ea9247cd2d0e6cf776`.
Different archive timestamps make offline/staged pak hashes different; their
contained source/assets are checked independently. The earlier tested live snapshots
and packages retain their historical hashes above.

Use `scripts/Start-InteractiveStoneLab.ps1` after manually loading the fresh official
tools world. It verifies new Lua command registration and waits for
`INTERACTIVE_STONE_LAB_READY`. Try `minecome_place`, then `minecome_break`, in the
KCD console and close Minecraft normally. Its owned stop file requests native
cleanup and bounded shutdown. New evidence goes to `runtime/evidence/interactive-stone-*`.
The prepared `scripts/Test-BlockRelayLoss.ps1` is a separate expected-fault check
for actual engine lease expiry after stopping only its verified owned relay; live
execution remains pending. Its closed-game refusal and syntax were verified.

The requested first major objective—both real processes communicating with actual
Minecraft stone visible in KCD2—has been achieved. The recovered live session also
verifies the interactive commands. Next priorities are supported movement/camera
authority and KCD collision export. Then expand selection/blocks, inventory/HUD and world persistence before
calling a build broadly playable. NPC/combat and terrain deformation remain later
phases. A final release date is not defensible until movement and collision hooks
are demonstrated. Future checks follow changed features and milestone gates;
unchanged stone assets do not require repeated static display tests.

## Live interactive repair and verification

The user's first console test exposed actual log behavior absent from the initial
fixture: KCD commonly leaves its newest record without a final newline. The relay
kept a stale flag until its whole read buffer became empty; after a reconnect that
buffer never emptied, so healthy later intents were rejected as `stale_log_batch`.
All four original user inputs reached KCD Lua but were rejected before Java.

The relay now tracks stale provenance and first-byte age per carried line. Finishing
that old line releases its taint; independent later lines use their own batch's
age/generation. Partial old inputs and interruption backlogs still reject. The
focused fixture now uses prefix CRLF with an unterminated final record, matching
the real game. It passes fresh reconnect recovery, stale outage rejection, matching
actions/results and final cleanup. Bounded shutdown also performs a read-only
SamplePose so the final End receipt gets its next separator. Evidence:
`runtime/tools-stone-fixture-giijPd/verification.json`. Only changed behavior was
retested; the earlier eight-suite baseline remains recorded above.

The repaired host was first built separately while the old executable remained
running. The captured owned relay36964 then received its own graceful stop file;
its engine End acknowledged zero owned/pending entities. Both KCD PID54132 and
Minecraft PID42156 stayed open. The standard host was rebuilt only after the old
relay exited, and replacement relay18440 accepted the existing real Fabric client
without restarting its UUID world. Current standard native host SHA256:
`e66a839b4fb3f153281115ed9a0b74200f228263deb15d1e15326b788345cc6f`.
The separately built fixture host hashes to
`c458cdad3b9e1d8dc47e99a74d2cc81220ab82e3575b282a645b7b1abae25834`.
Both contain the same repaired source; different build paths produce different binaries.
Lua, Fabric and sharp assets were unchanged.

In the existing lab UUIDba028c54-81dd-45a9-b8f4-7a47286a2af7, request6 placed stone
at MC(0,-60,9). Real client and integrated server confirmed it at21:32:38. Native
sequence526 spawned the actual geometry in exact engine session1791750759087564
at approximately(124.57,2045.35,56.18). The user answered "Yes, I can see the stone."
Request10 broke it at21:33:31; both real Minecraft states confirmed air, and the
same engine session/sequence1514 progressed cleanup_pending→removed with zero owned
entities. Further request11 re-placed it with confirmed client/server state and
engine sequence2089. A stone was intentionally left for the user's manual controls.
Human appearance is verified; human removal observation was not separately requested.
Current session shutdown/lease-loss testing remains separate and pending.

`runtime/evidence/interactive-recovery-20261011-213123` preserves the old executable
and logs, new relay provenance, actual Minecraft/engine snapshots and verification.
A one-session owner observes only the captured Minecraft PID/path/creation time
and requests graceful relay stop through its own file when that client exits.
It never stops either game. The replacement relay itself has a30-minute deadline.
The original helper's record remains separate from this recovered live session.

## Movement milestone: first live ground-interface probe

The next playable milestone is KCD-focused input driving vanilla Minecraft walking,
jumping and collision, with KCD's player/camera following Minecraft's result.
At the time of the first probe it was not implemented. Exact1.21.1 bytecode and matching Yarn documentation
identify the vanilla input/collision paths in `docs/research/MOVEMENT.md`.
Installed KCD spawn scripts verify position and actor-view setters; their constraints
and unresolved guards are recorded in `docs/research/KCD-MOVEMENT.md`.
The pinned SkyCraft source targets a different Minecraft version and its hooks
cannot be copied directly.

`kcd2/probes/ground_probe.lua` is an original, explicitly invoked diagnostic outside
the installed mod package. It performs one8m downward ray, excludes the player,
uses only exported entity masks, checks bounded finite hit fields, and compares
`System.GetTerrainElevation`. Unknown return shapes are reported without geometry
claims. It does not move entities, install timers or reload the live stone sink.
Thirteen focused cases pass using the existing Lua5.2 library; engine functions in
those cases are simulated.

`scripts/Test-KcdGroundProbe.ps1` verifies the discovered official Steam tools
executable's exact hash/version, captures its process identity, and checks that it
owns the numeric loopback port1403 before each console dispatch. A unique immutable
source snapshot, changed function reference, fresh log offset and matching GUID
receipt distinguish actual evaluation from an HTTP200. Log capture is capped to a
fixed extent within8MiB. Its read-only preflight and actual execution passed while
both games remained open; no active binary or installed package was replaced.

At21:47:33 on2026-10-11, actual KCD PID54132 returned one `ent_terrain` hit beneath
player `(1.4335724,2005.4136963,72.3600693)`. The ray started1m above the player and
returned distance1m, normal `(0.0965667,-0.2414021,0.9656085)`, and hit Z equal to
terrain elevation72.3600693. This verifies one live ground query, not a complete
collision mesh, buildings, streaming coverage, movement authority or camera follow.
Probe SHA256:
`5eed5916204de8a5002ded81301cd02e4dc267c8aefaa1336e9b2a2f4f006829`.
Evidence: `runtime/evidence/ground-probe-20261011-214733-56fd0292a0634ca9a60b2ff2d2912fe7`
contains the source snapshot, fresh engine log, receipt and provenance.

Next implementation gate: bounded host-derived collision coverage in a separate
owned Minecraft lab, installed on both client and integrated-server threads; then
short leased input through the normal vanilla tick and measured walking/jumping.
Only after that proof should KCD position/camera authority follow the guest. General
terrain, structures, stale-coverage recovery and coordinate calibration remain work.

## Live sampled-ground movement lab — 2026-10-12

The new opt-in lab installs immutable, exact-world-scoped collision shapes on both
Minecraft game threads. It uses the inspected1.21.1 collision-shape call through
a MixinExtras0.4.1 wrapper, leaving the normal movement tick responsible for motion,
gravity, jumping and landing. The first launch exposed a mixin package error:
ordinary classes cannot share the reserved mixin package. The mixins were moved
to `dev.minecome.terrain.mixin`; the corrected actual game then initialized and
ran successfully. The failed launch created no world and its evidence is retained.

The new read-only sampler performs25 terrain-only rays in a5×5 grid, excludes the
player, and withholds every geometry result if player identity/position changes.
The controller loads a unique immutable snapshot, verifies the exact tools
executable/hash/PID and ownership of port1403, and combines only matching fresh
receipts. Complete delimited log records avoid premature parsing of a nested JSON
object from a partial write. Supplied live files must match their adjacent captured
verification, source snapshot, run token and content hashes; a provenance label
alone is insufficient. Fourteen focused real-Lua5.2 sampler cases passed, with
engine bindings simulated. The PowerShell scripts parse; their partial-record
regression and actual capture passed.

Each sampled quad becomes a0.5m-thick horizontal slab at its four corners' average
height, yielding16 slabs across4×4m. Minecraft receives the KCD basis
`(x-centerX,64+z-centerZ,-(y-centerY))`. This is an explicitly approximate heightfield,
not general terrain/structure geometry or a streaming collision service. The new
UUID save uses an empty flat Adventure world, with proxy cells confirmed as air on
both sides. Server flight validation is allowed only in that new lab because its
air-block check cannot recognize proxy support; the player's flying ability remains
false. No gameplay physics is reimplemented.

Both installations acknowledge before a single vanilla server teleport. Subsequent
ticks set only bounded held-key state, read immutable server observations, and
refuse stale coverage, expired input, menus, world changes and post-settle corrections.
Both client and server must record walking, becoming airborne, and landing with
proxy support. Query counts also include diagnostic support checks and alone do not
demonstrate movement. The previous pause-on-lost-focus option restores at shutdown.
The lab saves its new world and exits normally after40 seconds.

The first corrected run used a labelled fixture and proved only the real Minecraft
hook/path. Evidence:
`runtime/evidence/ground-movement-20261012-093200-1377d50698f7454eaa3fb68a553d06c9`.
It walked1.3339m and passed client/server airborne and landing checks, then exited0.

After the user loaded the official test world, actual KCD PID47092 produced25 valid
terrain hits around `(120.1787033,2040.6510010,56.2934151)` with stable player identity.
Capture:
`runtime/evidence/ground-patch-20261012-093530-c023b27019c74a3d920410e50e38116d`.
Probe SHA256:
`56b033ad1bc9dc1b6283ffcf1c626e3c479c4b8135dcb92dcdb0e48a1f0d6bdf`.
Captured patch SHA256:
`48a7af5b65a6de98a70cf7e96641b2dd2bdbd71f57075ab9e73fbbf24ba3514a`.

The real Minecraft lab consumed that exact patch. At09:35:56 Europe/London,
client and server both confirmed1.2914985m walking, airborne motion and landing.
Final feet were `(-0.7914985,64.1895218,0.5)` in the lab. Two initial position packets
were counted; none occurred after stable-ground handoff. The lab exited0 normally
at09:36:38. Evidence:
`runtime/evidence/ground-movement-20261012-093528-19984ff6a26a4d7a99b32e56ef32ca7c`.
KCD2 remained open and its player was never moved by this test.

The Fabric build passed85 new ground parser/transform/shape/sequence checks,
alongside the required3428 protocol,25 smoke timing and17 input-gate checks.
Following the runtime package fix, source classes ran successfully and the final
runtime JAR was reassembled:108,327bytes, SHA256
`6c2b4f9862828d40c6dc5f3cef3c2f114a91be5263b24b6871e6a2d6df64ebf4`.
The actual games ran development classes; this is not a separate packaged-JAR
installation test. Existing native binaries, installed Lua pak and stone assets
were not changed by this milestone.

At this milestone the next checks were KCD input delivery and bounded player/camera
following; the continuation below records their distinct outcomes. Stock action
names are known, but ordinary movement delivery to Lua is not yet established;
`docs/research/KCD-INPUT.md` distinguishes UI listeners from actual gameplay input.
Full terrain streaming, walls/ceilings, rebindable input, authority recovery and
retail native deployment remain outstanding. Reproduction: `kcd2/MOVEMENT-LAB.md`.

## Live coupled movement — 2026-10-12

The supported tools route now has a bounded, actual Minecraft-to-KCD follower.
`scripts/Test-CoupledMovement.ps1` authenticates the exact running tools executable,
process creation time and numeric loopback listener owner before dispatch. The
public Windows owner-PID TCP table avoids a slow per-frame network cmdlet. A unique
immutable Lua snapshot must change the expected function reference and produce
matching fresh game receipts. HTTP200 remains dispatch evidence only.

An initial capability probe verified the actual actor's userdata identity, `nil`
linked-entity contract, stationary velocity, ordinary camera and supported state
readers. A separate one-shot probe moved X by0.1m on the game thread, measured
camera following on later frames, restored the original position, and confirmed
timer cancellation. Evidence:
`runtime/evidence/movement-probe-20261012-100202-9d50f46e472c423491afe484af55aae4`.
This primitive alone was not Minecraft movement authority.

The full coupled run used KCD PID47092, started08:33:05.9483691Z, and the official
1.5.5.0 tools executable SHA256
`a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a`.
Its immutable follower source and current source both hash to
`d946fc75e1fac243799f50d347867da0ac6b928572189b7f1c45221e9a4a7ee8`.
Fresh25-ray ground capture:
`runtime/evidence/ground-patch-20261012-103223-1b86b4835fd048e7aff977bc0ff287ad`.
Patch SHA256:
`a7e6df101f0021bba7722ca8cfa3948ea7b8aab54e91f8a089bfb48e25a16f0c`.

At10:32:51 Europe/London, actual Minecraft save
`MineCome-Ground-bceaa18e-a33e-41ea-ae3c-9821176beae7` passed client/server walking
of1.2914985m, becoming airborne and landing against that exact patch. No position
corrections occurred after the stable-ground handoff. The trace contains26 complete
records, with separate client prediction and advancing server observations.

The controller forwarded22 fresh server frames;21 delayed KCD game-frame receipts
confirmed the corresponding player positions and ordinary camera following.
Target X spanned1.2914963m. Target Z spanned1.5264473m including both jumping and
ground-height differences. Maximum camera-offset error was0.0912572m against the
probe's0.15m tolerance. These are logged engine readbacks, not a human visual test
or a claim of smooth sustained gameplay.

The game-owned follower returned the player to the captured starting position
`(120.2775345,2044.7459717,56.0587387)` after2.573s. Its later terminal receipt
confirmed actual position readback, camera-offset error0.0417432m, explicit end
and all owned timers cancelled. The owned Minecraft helper40660 exited0 after
normal lab saving/shutdown. KCD stayed open at test completion. Primary evidence:
`runtime/evidence/coupled-movement-20261012-103222-acc3d355b4264e3f8d74076c47e54d3f`
contains the source snapshot, capabilities, NDJSON trace, forwarded frames, fresh
game log, delayed receipts, independent Minecraft log and `verification.json`.

The follower enforces a400ms arrival lease, fixed8s absolute deadline, identity
and state checks, small displacement bounds and guarded restoration. Native KCD
physics remains active; unexpected state/navigation relinquishes ownership rather
than promising a general rollback. The controller sends only the latest valid
server sample, with a150ms HTTP deadline; the game independently consumes queued
values on its own thread. Lua's initial first-pose deadline is800ms. No movement
callback, action map, native input freeze, original game executable, installed
package or native binary was replaced by this milestone.

Focused verification:126 Java ground/trace checks and remapped JAR assembly pass;
25 real-Lua5.2 follower cases and20 input-observer cases pass with simulated engine
bindings. The final receiver passes15 standalone PowerShell cases. Its final
compound-observation-age and successful-end correlation guards were added after
the live run. The recorded trace passes those guards in a separate offline replay
using per-record UTC times; all22 recorded dispatches also satisfy the final300ms
observation-age bound, with maximum82.9525ms measured at HTTP completion.
`offline-replay.json` explicitly records that this is historical validation, not
a second live run. Final receiver SHA256:
`0b7d42837c2fc438adc213b3fe666f6c13641f199e9315386c1516542911376c`.

Current Fabric JAR:118,812bytes, SHA256
`cefe3f945f97a913b0bdefc65af9bb12899b78850b395468c1587bd6f4d4664a`.
The actual Minecraft run used development classes; this hash identifies the built
artifact and does not claim a separately installed packaged-JAR test.

The temporary Lua input observer expired and restored its original callback.
The60s window recorded zero whitelisted events and55 stationary position/direction
samples. The user's "done" reply came afterward; a later capability sample showed
movement, so delivery of real movement/mouse actions to Lua remains inconclusive.
Evidence:
`runtime/evidence/input-probe-20261012-100653-d3e5a984d29744d29b152481c91e81dc`.
Observer source SHA256:
`583aea483f0f5d8931c324819aa915f83b3e85cea3d08f181a140c1abdd3d92f`.
The existing game callback was delegated unchanged; no input events were injected.

The next playable gate is KCD-focused keyboard/mouse intent driving Minecraft,
with focus/menu neutralization and release/timeout recovery. Streaming collision,
structures, rotation/FOV alignment and sustained exclusive movement authority
remain separate work. This result proves a short local follower over approximate
ground, not completion of those requirements or the final build. Reproduction:
`kcd2/MOVEMENT-LAB.md` and `scripts/Test-CoupledMovement.ps1`.

## Source repository and input recheck — 2026-10-12

The project now has its own local Git repository under MineCome, with origin
`https://github.com/gabrielpery/minecraft-kcd2.git`. The existing parent workspace
and unrelated `repbase` directory are outside this source repository. Publication
excludes `runtime`, `minecraft/evidence`, build outputs, token files, downloaded
references, SDKs, game assets and saves. The normal Gradle wrapper is retained
with its embedded Apache licence and existing third-party notice. Text attributes
keep the Unix Gradle launcher executable-compatible through LF line endings;
the local Git index also records its executable bit.

The reloaded official tools process50544 acknowledged a fresh60s input observer.
Its lease expired and restored the exact callback, with zero action receipts and
76 stationary position/direction samples. The capture remains inconclusive for
physical input delivery; an empty callback log alone does not prove that gameplay
actions are unavailable to Lua. Evidence:
`runtime/evidence/input-probe-20261012-143555-490f58f86d8841968ec0471601ef810d`.
The controller now waits for the matching asynchronous installation receipt
before reporting that the observer is armed.

The initial source import was pushed as commit `98acd75` on
`codex/initial-import`. A fresh remote read confirmed the exact local commit at
both that branch and remote HEAD; the local source working tree was clean.
At the initial import, the then-private source repository contained 119 files. The three personal
executable examples were replaced with portable PowerShell7/Python instructions.

The user reported that the first prompt was missed, so its zero-motion recording
must not be interpreted as a failed input route. The restarted observer was
announced visibly and the user replied "done" during the requested test. Final
evidence:
`runtime/evidence/input-probe-20261012-144246-5530fe25909c46969d6a6052bd1b1c9a`.
It contains77 position/view samples, maximum player displacement13.5983179m and
maximum change in the forward unit vector1.7893179. Three callbacks reported
`action:"jump", activation:"press", value:1`; no jump release, watched movement
or watched mouse action was captured. The60s game-owned lease restored the exact
original callback and the explicit end acknowledged restoration again. The
module hash remained `583aea483f0f5d8931c324819aa915f83b3e85cea3d08f181a140c1abdd3d92f`.

This is actual partial semantic-input proof. The player and view changed during
capture, so absence of the watched walking/mouse action names is now a meaningful
observation for this callback/build. It does not prove every Lua input interface
is incapable of reading them. The original `PhysicalInputDeliveryVerified:false`
field remains conservative for complete forwarding; `analysis.json` records
the separately proved jump callback and missing movement/camera callbacks.
Next implementation needs a supported walking/mouse capture path with focus/menu
neutralization, bindings and release/timeout handling. No further repetition of
this same callback test is needed before investigating that route.

## Windows input capture layer — 2026-10-12

`tools/input_capture` now contains an original standalone Windows Raw Input
helper and pure state machine. It observes literal W/A/S/D, Space and left Shift
plus relative mouse movement in the exact target process's foreground window.
It does not replace a game callback, suppress native input, inject keys or enable
Minecraft game-thread application. The exact pinned tools executable/process gate
remains in `scripts/Test-KcdRawInputCapture.ps1`; the helper additionally pins PID,
creation FILETIME and a live process handle. No game address map or engine offsets
are used by this route.

Focus changes disarm the helper through both current-foreground checks and a
same-thread out-of-context foreground-event observer. A fresh F8 press with
controls released is required to rearm; a neutral first sample prevents inherited
held inputs from resuming. Unsupported actions, device changes and malformed or
stale packets disarm. Prior-phase queued packets are discarded without renewing
the epoch, avoiding starvation from a rapid mouse stream. Mouse movement is
bounded and consumed once; no other app metadata or typed-text stream is recorded.
F8 is a manual latch, not proof of engine gameplay/menu state, and remains visible
to KCD2. Literal mappings and mouse gain still require integration/configuration.

The writer uses a new resolved local evidence path, a1MiB/2500-record bound,
fixed20Hz sampling, bounded message batches and an independent15–120s deadline.
Termination clears controls, unregisters the two own Raw Input classes, removes
the foreground observer and closes its own resources. The wrapper only recovers
the exact helper it created; it never stops KCD2.

`ExternalInputDecoder`, `ExternalInputRecord` and `ExternalInputSessionGate` are
pure Java receiver components, with no game calls. They validate exact fields,
finite/bounded values, duplicate keys, UTF-8, process/session identity, sequence,
record age and a local monotonic lease. Invalid, stale or replayed data closes the
session with neutral controls. Focus/menu/lease reset requires a new neutral
armed sample. Fresh mouse frames accumulate until consumption within bounds,
with the earliest pending delta's expiry retained; newer frames cannot extend
old mouse intent. Malicious decimal exponents are bounded before conversion.

Final focused verification: native Release builds, its state-test executable
passes598 checks, `externalInputTest` passes148 checks, and the remapped Fabric
JAR assembles. The first Windows lifecycle attempts refused startup because
this system's registration readback omitted the requested `DEVNOTIFY` bit.
The gate now permits only that omission: exact own window and two classes remain
required, and `NOLEGACY`, interception-related flags and all other flags fail.
Removal readback must report zero registrations. This is a measured local API
result, not a documented universal normalization rule. Actual hot-unplug event
delivery is not yet physically verified. Both refused-run logs remain local.

The final15s lifecycle against KCD PID50544 passed with299 focused/disarmed
samples plus one begin and one neutral end:301 complete records,111,960bytes,
terminal elapsed15009ms. Actual stdout confirms two own registrations, foreground
observer removal, zero remaining registrations and `duration` termination;
stderr is empty. This proves OS lifecycle and neutral capture while the actual
KCD window was foreground, not real key/mouse delivery or Minecraft control.
Evidence:
`runtime/evidence/raw-input-20261012-151641-cb88db680dfe4b1d847134dcc55adde3`.
Trace SHA256:
`edefa13040dcbad77db43e9d7ae7623c69d4508a21a2eeb06554465089e9b333`.
Immutable helper SHA256:
`0433db85ed4875b25704d01f7849a890798e721a547a3b8ab01781fcd09353a4`.
Native platform-source SHA256:
`94e5b431b41a2f5dd95b5fe67a22c1e32d31ccef48bfbfef87f591d13b22bead`.

The standalone Java historical-recording checker accepted that exact301-record
file, with299 samples and zero active samples. It uses recorded UTC and a fictional
local elapsed clock; its result is labelled `HISTORICAL_INPUT_RECORDING_VALIDATED`
and does not claim a fresh live session. Current Fabric JAR:140,601bytes, SHA256
`c94b8c51c0097c38400f4da32a7e8644086f436a7b4e3f830497542cbb39d8bd`.
It has not been installed or tested as a packaged mod. The existing Lua sink,
movement follower, installed assets and game executables were not changed.

Next: complete-line file reading and game-thread input application in an owned
Minecraft lab, followed by physical input proof and engine menu/input ownership.
Sustained coupled authority must keep the existing follower guards and account for
KCD's native physics/input remaining active. No additional repetition of the old
Lua callback test is needed. Reproduction and primary API sources:
`docs/research/WINDOWS-INPUT.md` and `scripts/Test-KcdRawInputCapture.ps1`.

## External input applied to real Minecraft — 2026-10-12

The complete-line file reader and isolated game-thread consumer are implemented.
`scripts/Start-ExternalInputLab.ps1 -Fixture` starts a new UUID Adventure world,
waits for stable client/server grounding and reader readiness, then creates a fresh
scripted input producer. The input format tag is not source authentication:
`FixtureInput:true`, expected PID/creation identity1/1 and synthetic ground identify
this run explicitly. No KCD process is needed or moved by this mode.

The daemon reader validates the resolved evidence path before READY, requires a new
file, opens once and provides complete LF records through a copied bounded queue.
Partial EOF is neither an END nor a lease renewal. UTF-8/line/byte/record bounds,
overflow, replacement and truncation fail with neutral controls. All reader IO and
channel cleanup stay off the game thread; close signals the daemon without waiting.
The first focused run found that the installed Windows JDK's public fileKey is null.
The corrected Windows path opens through a private hard-link identity witness,
checks Files.isSameFile and removes its own link on daemon exit. Unsupported storage
fails closed. The final ownership guard never removes a link whose creation failed.

The opt-in lab applies held key bindings and ordinary vanilla look deltas on the
client thread. Sensitivity/invert follow inspected1.21.1 Mouse bytecode, including
Entity's own0.15 look factor. Toggle-sprint, smooth-camera and spyglass modes refuse.
World/player identity, Adventure mode, nonflying abilities, fresh server state,
sampled coverage, menus and post-settle corrections remain guarded. The normal
vanilla movement/collision tick owns walking and jumping after one startup teleport.
The existing ordinary Minecraft/stone modes are mutually exclusive with this lab.

Actual game evidence:
`runtime/evidence/external-input-20261012-191252-7ec0c61766434285b7a08582db61b80b`.
The new save was `MineCome-ExternalInput-d104c973-4af3-4391-836c-eaea8e0cc258`.
Both real client and integrated server walked0.8571695263m, became airborne, landed,
and agreed on final yaw94.5/pitch-1.8000002 versus initial90/0. One relative mouse
delta was consumed once. All six held controls were released after the terminal
record; the world was grounded and resting. Post-settle corrections were zero
(the two startup corrections formed the baseline). Minecraft saved and exited
normally; the owned launcher returned0 and no diagnostic identity link remained.

The fresh fixture contained90 complete records/31,417bytes. Input SHA256:
`f965a3b136ec9cf9c0313efa0038eab7a44eb48863019316daef9e7192354a5d`.
Patch SHA256:
`7dc5ff50109d0a0d0683088ea7e6eba2d3fd6bbc9538579725b76ff08c894fad`.
Lab source SHA256:
`14dc20a586725980daf78530c43a17fc6559bcb4fe735bf8884a56afacfd21c7`.
Reader source during that live run:
`734aa6a355636ddfe2b2b318eeb48c0845e6e42562de81af0d562284d1203a19`.
The subsequent witness-creation ownership guard is covered by the final focused
suite; the movement run was not repeated for that exceptional cleanup-only change.
Final reader source:
`a4d74da5f5ce8df2a85f099204383a45da34535d279674013cf6e5a4d43ecd42`.

Focused checks:148 decoder/session cases,126 ground/trace cases and266 file-reader
checks with zero skips; remapped JAR assembly succeeds. The file checks include
actual Windows hard-link cleanup while a writer remains open with no write/delete
sharing, plus replacement, truncation, UTF-8 fragmentation, bounds and symlinks.
That Windows-only test uses the tested JDK's ExtendedOpenOption; production code
uses ordinary Java file APIs. Final JAR166,148bytes, SHA256:
`85bb16a1ed19a8141e7dbc26927e65c3717b1fd467e69cc29b77ba2ba87d2ed8`.
The game run used Loom development classes; the packaged JAR is assembled, not
separately installed/live verified. No assets, saves, credentials or runtime evidence
are published to Git.

Physical KCD key/mouse delivery, explicit engine gameplay/menu state, configurable
bindings, view alignment and sustained authority remain. KCD native input/physics
stays active, so this consumer lab must remain separate from the player follower.
The non-fixture controller route captures ground and starts the existing scoped
Windows helper after readiness; its combined physical delivery still needs a human
input run. Procedure: `docs/SETUP.md#external-input-applied-to-minecraft`.

## Starting camera and configurable controls — 2026-10-12

The external-input lab now initializes Minecraft from an explicit starting camera
instead of fixed yaw90/pitch0. The new read-only `view_seed.lua` captures player
position plus camera forward/up using already-inspected Lua APIs. It preserves
raw player/id/API identity, copies vectors, checks that the player stayed within
0.1m and refuses invalid, non-unit, nonorthogonal, rolled or near-vertical views.
The player handle requirement matches the userdata observed in earlier actual
movement-capability receipts. The new module itself has not run in KCD; both games
were closed before this turn's owned Minecraft fixture.

`Capture-InputViewSeed.ps1` uses the existing exact tools process/hash/endpoint gate
and immutable unique source loading. It requires one fresh matching engine receipt
and ground-center agreement, then records patch hash, input run, target PID/start,
source provenance and capture time. Java's bounded strict parser verifies the same
identity and geometry association, converts KCD forward to Minecraft yaw/pitch,
and rechecks the60s snapshot age before the sole initial server teleport. Two stable
seconds of matching client/server angles are required before accepting controls.
Later camera motion remains ordinary Minecraft mouse handling. This is a starting
snapshot, not sustained KCD camera synchronization or input/physics ownership.

The native observer and both PowerShell entry points accept explicit six-key
bindings: forward/back/left/right/jump/sprint. Defaults are W,S,A,D,SPACE,LSHIFT;
allowed alternatives are uppercase letters, arrows, SPACE and left/right Shift/Ctrl.
Duplicate or unsupported keys reject before observation. F8 remains fixed for arming.
Configured keys drive both raw-event mapping and held-key suppression; wire records
remain semantic. KCD's own bindings/settings are not changed or automatically read.
The native helper acknowledges its selected bindings, checked by each controller.

Focused results: native Release builds;125 binding and598 state checks pass.
Java hostViewSeedTest passes75 cases and JAR assembly succeeds. The read-only Lua
probe passes23 cases in actual Lua5.2 with simulated engine bindings. PowerShell
binding validation passes16 cases;14 marker cases reject wrong/missing/duplicate
view hashes, source kinds and initial-view proof flags. Existing unrelated suites
were not rerun. The final controller marker guard was added after the live fixture;
it accepts that exact historical READY/PASS pair offline, without claiming a new run.

Actual Minecraft evidence:
`runtime/evidence/external-input-20261012-192835-1e69e789a42445fdbc12e064b93e7e15`.
Save: `MineCome-ExternalInput-98c93664-e00a-482a-a32c-d01a02eb852b`.
Both client/server initialized yaw45/pitch−10, walked1.0727510592m, jumped and landed,
then agreed on final yaw49.5/pitch−11.8 after one mouse application. All controls
were neutral at END, there were zero post-settle corrections and the owned launcher
exited0 after normal save/shutdown. The input, flat terrain and initial view were
explicit fixtures. Ninety records were received. The selected arrow/RCTRL binding
argument was recorded but not exercised by physical keys in this synthetic producer.

View file SHA256:
`1c53aa02ece04382dbd05daacff0fb7207d88d57ea4397317edba3a4d0190b9e`.
HostViewSeed source SHA256:
`153dcd19ee35c85c5be24413b71f86a294f7e6a5237fc5bb08146b4d6f79a847`.
ExternalInputLab source SHA256:
`f2223797d47b50831728340ce41c20fcfa6824e99bd0b32605ab79373d612b0c`.
Lua view source SHA256:
`e056562a837c267f7ace312096887d32376e4770c27eb6c999ebb15638c9c638`.
Native helper86,528bytes, SHA256:
`3ea4a9d81ec43eebc025df68d05320abb2933cafb99ff326dc48b6e76084aeb4`.
Fabric JAR175,548bytes, SHA256:
`1d2532cbcc0f6f2c522f14f2aa422c08364069f58f8173f20dee102f376f3872`.
Loom development classes provided the live Minecraft proof; the assembled JAR is
not separately installed/live verified. Runtime evidence, worlds and assets remain
ignored and local.

Source inspection found partial death/dialogue/save-load/calendar state getters,
but no established generic menu/cutscene getter or matching prior FreezeInput-state
getter. GameRules.IsFrozen is entity freeze, not input freeze. No native KCD input
or physics takeover was added. Physical KCD controls, live starting-camera capture,
ongoing view alignment and sustained world movement authority remain separate work.

## Physical-input readiness and focus-switch recovery — 2026-10-12

The combined lab now waits up to60s for the first sampled F8 arm before starting
its15–40s active interval (default30s). A focus loss/rearm never renews that timer.
The native optional wait and duration must sum to at most120s; the standalone
observer's default remains its original fixed duration. The lab's input105s,
world135s and global180s bounds allow this wait without changing the300ms input
lease,120s protocol session,20s producer-file creation deadline or bounded queues.
Fifteen new deadline cases join the native suite (613checks passed).

Two actual combined attempts captured fresh KCD terrain and camera and reached
matching initial Minecraft client/server views:
`runtime/evidence/external-input-20261012-194153-1748ddd8a2f74ad09d584733b248c7db`
and
`runtime/evidence/external-input-20261012-194550-e0d857bd357a4a1d8e900562bea55c12`.
Neither established physical movement delivery. The first stopped before arming
when a server observation was older than250ms; the native helper observed F8 later.
The second paused controls on that condition, then rejected a queued expired input
sample. Both failures released controls and saved/stopped the owned Minecraft
instance; only the owned input helper was terminated during controller cleanup.
KCD remained open. Failed attempts are retained rather than counted as successes.

The initial-view Lua module is now live verified on the pinned official tools
executable, PID54808, creation FILETIME134363039636611832. Its unchanged source
hash is `e056562a837c267f7ace312096887d32376e4770c27eb6c999ebb15638c9c638`.
The second view receipt is in
`runtime/evidence/input-view-20261012-194552-7414ffa6cc304421a58f85d6f7169890`.
Both sides started yaw−175.33249/pitch7.1751018, matching that captured view.

The owned Minecraft lab now calls public Mouse.unlockCursor while active to prevent
local foreground mouse motion from changing its camera. This method and Mouse.tick's
focus/cursor-lock guard were inspected in the exact cached Yarn1.21.1+build.3 merged
JAR (SHA256 `06a137a0b9597798455412349a45255ee37f351ceaa37d731096880be6c6a727`),
using javap. unlockCursor only changes cursor state and GLFW cursor mode; external
changeLookDirection still applies normally. See the primary method contract:
https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/Mouse.html#unlockCursor().

Fresh server observations remain required before applying controls. Scheduling gaps
pause input with a fresh-neutral barrier, skip proof collection, reset landing
settling and stop after2s without a fresh observation. The live consumer additionally
discards validated expired SAMPLE records, advancing only ordering/count state and
clearing all held/mouse state. They cannot renew a lease or replay motion. A new
fresh released-controls sample is required before normal input resumes. Strict
receive remains unchanged for other consumers; malformed, foreign, replayed, future,
stale BEGIN/END and over-budget records still close the live gate.

The first recovery fixture (`external-input-20261012-195039-8d5c9c276fbd4c6089733151d18b06b1`)
correctly discarded expired input but still missed movement while both renderers
were running. Observations previously depended on client requests; they now publish
an immutable sample directly from Fabric END_SERVER_TICK on the server thread, with
the same owned-world/player/proxy checks. The callback contract was inspected in the
cached fabric-lifecycle-events-v1 sources. Temporary lab settings disable window
vsync, cap rendering at60fps and reduce view/simulation distance to4/5; saved settings
restore at CLIENT_STOPPING without an options.write call. Exact cached Window and
GameOptions bytecode was inspected. Driver/swap blocking was a possible explanation
for earlier stalls, not an established engine diagnosis. An intervening fixture
`external-input-20261012-195445-32d0b91a1ba540d3955380ba1a8ecab4` exited normally before
world creation/readiness; it provides no movement proof.

Final recovery fixture passed in the actual Minecraft client/integrated server with
KCD also open:
`runtime/evidence/external-input-20261012-195840-452f657d7e4a4de6bdf3f17054bebb7b`.
The intentionally expired held-forward/mouse17,11 sample was discarded, then fresh
neutral input restored normal application. Both sides walked1.0727510592m, jumped,
landed and changed yaw45→49.5/pitch−10→−11.8. Only the one intended fresh mouse
application reached the player;91records were received, with zero post-settle
corrections or server-observation pauses. All controls were neutral at END. The
launcher exited0 and restoration was acknowledged (vsync true,120fps, distances12/12);
the local options file retained those original values. This is scripted-input proof,
not physical input proof. Focused Java decoder/session checks now pass194cases;
native state/deadline checks pass613 and Release/JAR builds succeed.

Final lab source SHA256:
`9da55e139a2e6c4f1d45b57335700c88f0e1792d05bbc24ad7b1acfd476afdd1`.
Session gate source SHA256:
`2994785325b0c8e1459b30d9b2bdb105050436d9c0bde201cb592c86d1053638`.
Native helper88,064bytes, SHA256:
`a11101b55755e82ac919ae70782bae12d62e8165e087dade38950b0ef72113c3`.
Fabric JAR177,788bytes, SHA256:
`65fecb6dabf9b3e5de93695f68f955e219c4d0979a895858441eda54f1dd0742`.
Actual game runs use Loom development classes; the packaged JAR remains assembled,
not separately installed/live verified. Assets, saves and runtime evidence stay local.

The final physical two-game check passed:
`runtime/evidence/external-input-20261012-195929-2fe9fb3d71534af7af29206cbd9d6d4e`.
The user confirmed the F8/W/Space/mouse actions. Fresh exact-process checks targeted
the restarted tools PID3004/creation FILETIME134363050534931108, not the earlier
PID54808. Captured KCD ground and camera seeded the new Minecraft world. Both client
and server walked0.4261759414m, jumped and landed, and changed yaw−170.09227→−143.39227
and pitch0→−49.800007. There were zero post-settle corrections and zero server
observation pauses. Fifteen expired samples were discarded without aborting or
replaying controls; this is functional forwarding proof, not a low-latency guarantee.

The immutable native helper produced1173records over58,607ms. Its first arm arrived
at28,600ms, followed by the complete30s active interval. There were121armed samples,
including6forward,5jump and38nonzero mouse samples; the real consumer reported
25mouse applications. All controls were neutral at END. Native registration removal
and foreground-observer unhook both passed, Minecraft restored settings and exited
normally, and the controller returned0. KCD was neither repositioned nor stopped.

The source-independent Java marker remains conservatively
`physicalInputVerified=false`; `physical-analysis.json` separately records the
human-confirmed actions plus owned native executable, process/run identity and real
client/server receipts that establish physical forwarding for this session. No source
tag alone is treated as physical authentication. Input SHA256:
`c1f31be2e136ba3eb4d42cf51c221966c10f0e236bd4726830db185574dcd350`.
View SHA256:
`e400a8660cf6892917e63633a1f85ab4fd63aa80f6f90d338d9789f088a5e4fb`.
Patch SHA256:
`110c039bc4aba0b89527be87cd9007daae00470df058bbb7627747dec54c94db`.
Sustained camera/input ownership, generic engine menu state, streaming collision and
combining the input consumer with the KCD follower remain unfinished. No unverified
native hook, KCD input suppression or physics takeover was introduced.

## External-input pose export and live control capabilities — 2026-10-12

The external-input lab now exports immutable client/server position, velocity,
grounding and yaw/pitch at up to10Hz. A bounded daemon writes a new NDJSON file;
Minecraft's game threads perform no output file operations. Samples require an
advancing server sequence and observed age at most250ms. The stream reserves its
terminal slot within512records/1MiB. A final fresh server sample and completed
flush/close are required before the lab reports success, within its existing4s
terminal deadline. Review caught and fixed a failure/completion read race.

Every record binds input run/process, patch/view hashes and the isolated world,
and explicitly remains audit-only/follower-ineligible. Coordinates are projected
in patch space, with the initial Minecraft baseline recorded separately. The input
dispatch watermark is not a server acknowledgement. This adds the position/view
output needed by a future coupled controller without changing the working follower.

The automatic actual-Minecraft run passed in
`runtime/evidence/external-input-20261012-202526-c1b240aa3bb340a687c2315fa97bd862`.
Client and integrated server both walked0.8571695116m, jumped, landed and changed
yaw45→49.5/pitch−10→−11.8. The deliberately expired input was discarded; one fresh
mouse application, zero post-settle corrections and terminal neutral input were
confirmed. Minecraft restored its prior settings and exited normally; KCD PID3004
remained running. This run uses synthetic input and ground, not new physical-input
proof. The earlier human-confirmed physical result remains valid for that version.

The new export contains59records/57server samples,76,136bytes, with a passed end
and matching final server sequence. Its source identity, framing, finite values,
coordinate/view projection and terminal fields also pass the final offline validator.
Recording SHA256: `23595374ed119fe6c66cdb1681d5491f00481fd0be9dbe610193c84876833209`.
Focused checks pass:1092 Java writer assertions,16 PowerShell validator cases and
21 Lua control-probe cases. The Fabric JAR assembles to192,880bytes, SHA256
`d92f87b76b4786ec68b0dd3e93bb2bc1efe1ad06d93751b2ae70e4707dff243c`.
The live run used Loom development classes; this packaged JAR was not separately
installed. `implementation-verification.json` records the final source/build hashes.

A separate read-only live probe passed against the pinned official tools executable:
`runtime/evidence/control-capabilities-20261012-201510-c8e580acb2e642e4b2caa6cb79bcf04d`.
It confirmed `ActionMapManager.EnableActionFilter` is absent, although its state
reader exists. `g_gameRules.game.FreezeInput` and `player.EnablePhysics` exist;
global `GameRules` and bound `IsFrozen` are absent. Nine partial state getters
returned actual booleans with stable actor/function identity. No mutation was
requested. Prior input/physics state and reliable restoration remain unproved, so
the physical-input consumer and KCD follower are still separate. See
[KCD input research](research/KCD-INPUT.md#live-control-capability-inspection--2026-10-12).

## Vanilla HUD/inventory renderer capture — 2026-10-12

The UI path now follows the inspected SkyCraft/EldenCraft renderer architecture:
normal vanilla rendering supplies captured UI pixels; an original ReShade D3D12
add-on supplies host composition. No separate desktop window or redrawn inventory
is used. The source pins and exact capture/render contracts are in
[HUD compositor research](research/HUD-COMPOSITOR.md).

The first automatic capture exposed a startup ordering issue: suppressing world
rendering before the terrain screen completed caused its 30-second fallback. The
fix lets normal terrain loading finish before the owned capture mode starts.
The corrected actual-Minecraft run passed, with normal process shutdown, in
`runtime/evidence/hud-export-20261012-204553-727d31c1b69241b6b8226bd0bb120df6`.
Its fresh save was `MineCome-Hud-987997db-0e12-44ae-a595-2126bb1a25c4` and run token
`efc51913f05740b7aacc9df2dabedfec`. All three 854×480 frames were rendered through
Minecraft 1.21.1's normal GUI path and copied using asynchronous OpenGL readback.

Actual client and integrated-server inventories agreed on nine item IDs/counts.
Frame 1 selected slot 0; frame 2 selected slot 1; frame 3 opened the actual
`CreativeInventoryScreen`. PNGs were visually inspected: crisp vanilla item icons,
counts, selection, chat/advancement toasts and Creative inventory were present.
Hotbar frames retained over 275,000 fully transparent pixels each; inventory retained
its normal translucent full-screen dimming. This is Creative UI proof, not a
Survival health/hunger or crafting-interaction proof.

Raw RGBA SHA256 values:

- Frame 1: `ab78df38db3b6901788f878e147ba0ed7ed509bf0aaa57702b368afc832dd2b9`.
- Frame 2: `ff3c4138f77a9ab985f10b94ed2aea544b3ae406535dd0e997f65ae6b1b85d35`.
- Frame 3: `302485c1c9fefeeb92db394516740f764d9e4ad5b7da902f65ef60e2fed54234`.

The final guest source assembles and passes 36 focused pixel/output checks. The
live run used Loom development classes; the assembled mod was not separately
installed. Existing movement/input/stone components were not changed.

KCD composition was unverified at this capture stage; the later live preview below
records the user's first visible HUD confirmation. Three captured snapshots cycle
only for the initial renderer proof. Continuous transport, physical inventory
controls, menu arbitration and sustained gameplay are subsequent implementation.

### Native compositor build and startup investigation

The original D3D12 ReShade add-on and FX now build. Final focused validation passes
117 native contract/lifecycle checks and all four DXBC shader entries at two
resolutions. The final add-on SHA256 is
`a9bb60999fb526df64b3c61975431aed7c0b85728dc21a30db91b41bfccea484`.
Final source review fixed reset cleanup using effect handles after ReShade had
destroyed them, and made the unarmed render path return before shader access.
The tests exercise invalidated handles, reset/reinitialization, repeated cleanup
and owned-resource release. This is offline validation, not a live crash fix.

The official ReShade 6.8.0 add-on runtime was hash-checked and extracted without
running its installer. The six-file private bundle was installed with KCD closed;
no original game executable or base asset was overwritten. Installation and the
rollback helper support Windows PowerShell 5.1. No preview arm file was created.
The first user-started process (PID 48224) registered the unarmed add-on, created a
2560×1440 SDR D3D12 runtime and compiled the actual HUD effect before crashing
during loading. There was no owned texture upload or submitted Minecraft frame.
Logs and the rollback record are preserved in
`runtime/evidence/hud-startup-crash-20261012-205804`.

After normal process exit, only the owned, pinned DXGI proxy was renamed to
`dxgi.dll.minecome-disabled`; the add-on, configuration and logs were retained.
The user then reported another loading crash with the hook disabled. Fresh game
logs in `runtime/evidence/loading-crash-hook-disabled-20261012-210223` end at the
same MFX collisions-loading line, and ReShade's log did not update. No corresponding
Application crash event, exception stack or process exit code was available.
The cause remains unproven. At this stage the fixed source bundle was staged in
`runtime/hud-compositor-resetfix`; the later deployment and preview are recorded below.

The new manual `Start-Kcd2ToolsDiagnostic.ps1` records the missing process exit code,
sampled modules and memory during a bounded 120-second launch. Windows PowerShell
5.1 parsing, read-only exact-executable/hook preflight and the public Windows memory
query pass. No game was started by those checks. A fresh user-run diagnostic is
now preserved in
`runtime/evidence/tools-startup-diagnostic-20261012-201214-1b3de6fc259a4282a316450302d68141`.
The user confirmed the same loading failure. PID 49532 exited after 28.462 seconds
with code 250 (`0x000000FA`). All six complete module snapshots omitted ReShade and
the MineCome add-on; CryRenderD3D12 was observed. Across 28 samples, peak game private
memory was 3,823,595,520 bytes and minimum available system commit was 5,373,673,472
bytes. There were no memory/module sampling errors. These results do not identify
the cause or establish continuous module absence between samples. The existing
launcher and working movement/stone code are unchanged.

The diagnostic now offers explicit `-WithoutMods` isolation through Warhorse's
documented empty mod-order list, with ownership-checked restoration after process
exit. It preserves existing mod orders and both installed mod packages. Windows
PowerShell 5.1 preflight, cached-helper compatibility and empty-file Win32 identity
checks pass. Default launching arguments remain unchanged; live mod exclusion is
not inferred from file creation and must be checked in the resulting game log.

The actual `-WithoutMods` run in
`runtime/evidence/tools-startup-diagnostic-20261012-202201-861e685726ac49efb65ca5bed6faa380`
also failed. Its fresh log explicitly reports `0 mods enabled`, with neither mod's
startup script loaded. PID 52160 exited with the same code 250 after 28.462 seconds;
minimum sampled available system commit was 5,098,078,208 bytes. The renderer hook
remained disabled. This rules out a requirement for either mod to reproduce this
failure, without identifying its cause. The helper conservatively retained its empty
list because the exited process was still enumerated while its handle remained open.
After all processes closed, the exact unchanged owned file was verified and removed;
`post-exit-mod-cleanup.json` records restoration of the previous mod-loading setup.
Cleanup now checks process exit state and disposes temporary process wrappers;
six focused cases cover live, exited, absent and inaccessible process states.

### Successful explicit PowerShell 7 launch

The user repeated the same zero-mod diagnostic through the installed bundled
PowerShell 7.6.5 executable and reported `world ready`. Evidence is preserved in
`runtime/evidence/tools-startup-diagnostic-20261012-204806-0878b89fc0bb475d9cfb2694a95e7e55`.
PID 48368 remained alive through the complete 120-second monitor. The official
Console API returned HTTP 200; the copied game log confirms `0 mods enabled`.
The renderer hook remained disabled and no debugger was attached. A separate
`user-confirmed-world-ready.json` records user confirmation, the running process
identity, the observed PowerShell 7 parent and module snapshot. The temporary
owned empty mod-order list remains pending cleanup after normal game closure.

The successful run produced 118 memory samples without errors. Peak private memory
was 11,389,657,088 bytes; minimum available system commit was 313,569,280 bytes.
It began with less available commit than either earlier failed diagnostic. Its
commit limit increased by 3,256,639,488 bytes at approximately 69 and 73 seconds,
after the earlier failures' 28-second point. This does not prove shell-version
causation or identify the original exit-250 cause. The working PowerShell 7 launch
path is retained; no memory settings or unrelated applications were changed.

A proposed CDB observer was tested only against an original local fixture. Exit
capture and second-chance AV capture passed, but running-timeout cleanup changed
the fixture's later exit code to `0x80000004`. It was never used on KCD. Its
unvalidated source and evidence were preserved under
`runtime/evidence/startup-debug-deferred-20261012` and removed from the user-facing
scripts. No debugger is installed or running as part of the working game session.

Both user launch helpers now forward Windows PowerShell 5.1 invocations to an
existing PowerShell 7 runtime, preferring the installed bundled executable. They
preserve the current console and bound arguments, including explicit false
switches, without installing anything or closing the caller. Future diagnostic
launch receipts record the actual shell path and version. Six non-game forwarding
cases and parsing under both shells pass; an actual PS5 preflight correctly
refuses while the existing PID 48368 remains open. Evidence is in
`runtime/evidence/powershell7-bootstrap-final-1296d58fce3b42dc9eee5b6ddf92fb18`.

`Update-HudCompositor.ps1` now prepares an ownership-checked update from the disabled
original installation to the staged reset fix. Read-only preflight verifies all
six old and new files; only the 299,008-byte add-on changes. The updater backs up
owned bytes, uses atomic replacement, checks closed-game/executable identity on
forward and rollback mutations, and re-enables the owned proxy last. Eight focused
filesystem cases pass under Windows PowerShell 5.1; independent source review
confirmed the rollback guards. Evidence is in
`runtime/evidence/hud-update-fixture-709a44bba6ec46d29d7d9c05e9382316`.

### First visible KCD HUD preview

With all KCD processes closed, the updater replaced the owned add-on with the
reset-fixed build and re-enabled the pinned DXGI proxy. Other bundle files were
unchanged. Backups and deployment receipts are in
`runtime/evidence/hud-update-20261012-210428-0718f9a4d7d749e383037d73b5e20701`.
The user then launched PID 55096 and confirmed `world ready`. Its loaded module
paths and hashes match the repaired installation, and the fresh ReShade log
records successful compilation of the actual HUD effect.

The existing genuine three-frame capture was armed for 40 seconds with run
`a5b34e65665d45f1b180fbdd0c1fc852`. Native receipts record accepted arming, created
resources, submissions of snapshots 1, 2 and 3, and lease expiry. The process
remained alive. The user confirmed that the Minecraft HUD appears when tabbing
into KCD2 and works, while reporting that it looks too small. This is user visual
confirmation of the HUD, not an agent screenshot inspection or separate visual
confirmation of every captured state. The native submission events cover all
three states. Evidence and the exact user report are preserved in
`runtime/evidence/hud-preview-arm-20261012-210833-a5b34e65665d45f1b180fbdd0c1fc852`.

The sizing issue is reproducible in `fit_rect`: 854×480 into 2560×1440 has a
limiting scale of about 2.998, which integer rounding reduces to 2. The resulting
1708×960 canvas begins at (426,240), explaining the inset appearance. The correction
removes that rounding, retaining aspect ratio and point sampling while using the
available backbuffer area. At this resolution the fit becomes 2560×1438.876 pixels,
leaving only the subpixel top/bottom margins required by the small aspect mismatch.
It builds in `build/hud-aspect-fit-20261012` and passes 131 focused contract checks,
including the actual resolution, noninteger scaling, aspect mismatch and bounds.
The new add-on SHA256 is
`819499b52971d5027745be24e136b4a428975d108870ee0f70c1edfdf60b69cb`.
The separate static bundle was staged in `runtime/hud-compositor-aspect-fit`;
verification is in `build/hud-aspect-fit-20261012/verification.json`. At that stage
the installed add-on and its original artifact remained unchanged. The later
continuous build below includes the same correction; live corrected sizing is
still unverified. The updater accepts this
exact build hash alongside the prior reset-fix hash, retaining its original defaults
and all ownership/rollback checks. Full script parsing and 17 focused hash-admission
checks pass in each of PowerShell 5.1 and 7.6.5; these execute only the extracted
allowlist/guard, not the updater. Evidence is in
`runtime/evidence/hud-update-admission-fcfd50ce37a54c5bb8cb70b71142d86a`.
The proposed static-only deployment was superseded by the continuous build below;
the separate aspect-fit bundle was not installed.

This run kept the owned empty mod list from the successful baseline so only the
renderer changed. No continuous UI stream, slot clicks, crafting or host input
suppression was exercised by this static preview. The subsequent deployment below
archived its expired arm after ownership verification.

## Continuous vanilla UI stream — 2026-10-12

The completed snapshot lab remains intact. A separate Java21/JNA mode captures
the normal vanilla GUI through the existing three PBOs, discards older completed
capture IDs and publishes the latest frame from a worker. The original channel
in `protocol/HUD_STREAM.md` uses a fresh named mapping and mutex, exact producer
and target PID/FILETIME identities, immutable expiry and bounded waits. Invalid,
closed or exited peers terminate reception; stale frames cannot refresh the
resident image. No engine offsets or game-thread mapping/file IO were introduced.

The real run in
`runtime/evidence/hud-stream-20261012-212421-479e9128381f425f8c6c3f9ae73bdc4d`
created `MineCome-HudStream-404335e7-563f-46b1-bf16-1d80005edfc9` and sent 344
nontransparent frames to the standalone native receiver. Both sides observed
hotbar selection 0, selection 1, the actual Creative inventory screen, and selection
2 after closing that screen. Fresh client/server inventories agreed before each
capture. The preserved PNG samples were visually inspected as actual vanilla UI.
The intentional publication pause made the receiver's freshness gate inactive;
fresh reception resumed afterward. The receiver observed the closed marker, and
Minecraft saved and exited normally. All mapping/mutex handles were released.
The target was the standalone controller process: no KCD compositor was armed,
and the receipt explicitly keeps `kcd_compositing_verified=false`.

Validation passes 168 Java stream checks, the existing 36 snapshot checks and
146 native checks. The separately frozen native build and review receipt is
`runtime/evidence/hud-stream-native-frozen-3bc7270598a34b42bc8738cb919966e2/verification.json`.
Its add-on SHA256 is
`d7ebc92b59f7971998f1eafb5afe433b5bc44b84a272bcfc9840c49e1d1e6fd8`.
The actual transport run records its own receiver hash; it is distinct from the
subsequently rebuilt frozen artifact. Compilation and standalone evidence do not
establish live D3D12 composition.

The stream add-on uses the aspect-fit correction, a persistent texture and three
fenced upload buffers. It checks the age of the frame actually uploaded, even
while newer frames arrive. Busy upload slots drop updates. ReShade's public APIs
can internally flush or wait; no absolute nonblocking renderer claim is made.
Expiry hides the layer, with GPU resources retained until safe reset/unload.
Independent review resolved a contended-callback lifetime race and confirmed
effect-handle invalidation, upload ordering and worker exception containment.

With every KCD process closed, the owned expired static arm was archived and the
updater replaced only the former add-on. The previous bytes and receipts were
backed up; the pinned owned proxy was enabled last. Preflight passed in PowerShell
5.1 and 7.6.5. The installed bundle is `runtime/hud-compositor-stream`, and
`runtime/evidence/hud-update-20261012-213418-25efcf776e664040bd9047eb4974aa82/update.json`
records `updated_unarmed`, no game launch and no preview arming. The unchanged
owned empty mod-order list remains for the controlled renderer comparison; its
ownership-checked restoration is still owed after that comparison and normal
closure.

The subsequent live check used a fresh user-started tools world and
`Start-HudStreamLab.ps1 -Composite` with the explicit installed stream bundle in
PowerShell 7.3 or later; its results follow below.
Physical slot selection, inventory clicks, crafting, held hands, survival HUD
coverage and KCD menu/input arbitration remain unfinished.

### First live continuous display

The user started tools PID 54196 and confirmed world readiness. Run
`3cd7ea7bb557436cba1f428b94f7b72d` then created a fresh Minecraft world and published
240 nontransparent frames. The native receiver observed all four UI states,
stale-frame hiding, fresh resumption and the closed marker. KCD's loaded stream
add-on accepted the same run, uploaded 200 fresh frames and submitted 1,882 draws,
with zero busy-slot drops or renderer failure events. Minecraft saved and exited
normally; KCD remained alive. These are renderer submission receipts, separately
from the user's visual evidence.

The user confirms seeing the HUD but reports it is now "a bit large" and that
KCD's own HUD remains. They did not separately confirm every slot transition or
the inventory opening/closing. The complete report, native log, process/artifact
identities and controller results are preserved under
`runtime/evidence/hud-stream-20261012-214338-3cd7ea7bb557436cba1f428b94f7b72d`.
The full-canvas fit and vanilla GUI scale are separate concerns: this capture is
854x480 at Minecraft GUI scale 2, enlarged to the host canvas. The GUI needs a
smaller presentation while preserving correct anchors. No KCD health publication
or native HUD suppression exists yet; this remains a Creative UI lab. The stream
is closed and its owned arm awaits cleanup after normal KCD closure.

## Vanilla inventory input and smaller layout — 2026-10-12

The separate input mode uses a 1280x720 capture at vanilla GUI scale 2, preserving
full-canvas aspect fit and pixel sampling. On a 2560x1440 host this changes effective
GUI scale from approximately 6 to 4. The isolated Minecraft window/options are
restored on shutdown. Live sizing still needs the user's observation.

The new reverse channel is documented in `protocol/HUD_INPUT.md`. Exact paired
process identities, a 64-record ordered ring, client-tick acknowledgements and
250 ms freshness bound input. Game calls remain on the Minecraft client thread.
The separate native `hud_input_addon.cpp` and `MineComeHudInput.ini` leave the
previous stream source/artifact intact. F8 enables one keyboard session of at most
30 seconds after a fresh composed image, ready guest and neutral controls. Only
1-9, E and Escape are forwarded. Focus loss, ReShade overlay, stale input, closure
or runtime reset ends ownership; the next-frame blocking request then stops.
This is not verified KCD input exclusivity or automatic host-menu arbitration.
Live mouse forwarding is disabled because the inspected ReShade DirectInput8
polling path preserves mouse axes. The test requires host menus/console closed.

The real fixture in
`runtime/evidence/hud-input-20261012-220732-28aaccdc10d74b0cb5a10ddb08eca7e3`
passed all 31 acknowledged events, selected all nine hotbar slots and opened/closed
the actual Creative inventory. Three ordinary vanilla slot clicks swapped stone64
and dirt32; final client and integrated-server inventories agree. It published
32 real UI frames and the native fixture received 30. Controls, image mapping and
input mapping were released, including a published terminal client ACK. Minecraft
saved and exited normally. The genuine 1280x720 PNG samples were visually inspected.
No KCD compositor or physical host input was exercised by this fixture.

The first run exposed image starvation when the snapshot proof gate waited for
every rapidly changing selected slot to agree with the server. Interactive mode
now renders normal client predictions while truthfully marking pending server
confirmation; authoritative final proofs still require server agreement. The
successful retry exercised 13 pending and 18 confirmed captures, retaining the
250 ms input freshness limit. The failed run remains in evidence under
`hud-input-20261012-220451-ae51df56f91f414089c83f9142ac6cf9`.

Validation passes 325 Java input checks, 174 stream/layout checks, the existing
36 snapshot checks and 216 native input checks. Independent review covered the
transport, UI calls, callback lifetime, controller and arm archival. Final native
build evidence is
`runtime/evidence/hud-input-native-frozen-4c924c5ffdbe4d5ca3f3e917d449ff51/verification.json`.
The input add-on SHA256 is
`d7de884b798c6480efc24981ce409821192a7fcd56f6c2361ff32ec2755eefca`.
Final Fabric JAR SHA256 is
`e9e89cac0e81d052538bd195a25d588769442c67ff7f912ab2c363b27c08863e`.

KCD subsequently closed normally with `WM_CLOSE`, exit code 0. The unchanged
diagnostic-owned empty mod-order file was removed only after matching its original
file identity, timestamps, size and hash. Ordinary mod discovery is restored;
both mod packages are unchanged. The cleanup receipt and normal-close log are in
`runtime/evidence/tools-startup-diagnostic-20261012-204806-0878b89fc0bb475d9cfb2694a95e7e55`.
The owned expired stream arm was archived beside its original arming receipt.
Before deployment, all 1,008 current save/profile files were backed up and hash
verified under `runtime/backups/20261012-230838`.

At this deployment, `runtime/hud-compositor-input` was installed unarmed. Both
PowerShell 5.1 and 7 preflight passed; only the owned add-on changed, its previous
bytes were backed up and the pinned proxy was enabled last. Deployment receipt:
`runtime/evidence/hud-update-20261012-220935-ae5ecddf2d944d7292c41c5fc7981447/update.json`.
No game launch was performed by that deployment. The subsequent user-started
live attempts are recorded below. KCD HUD suppression, health mapping, mouse
inventory controls, crafting and general gameplay ownership remain unfinished.

### First live keyboard attempt

The user started a fresh tools world and confirmed readiness. Run
`39d46065f12f450e8fe60dcbc57e618b` accepted the image arm, published 41 Minecraft
frames and uploaded 24 in KCD with 179 submitted draws. It ended before the F8
activation: no keyboard ownership and no input events were recorded. The native
receiver rejected a waiting-state acknowledgement as `ack_stale`. That build
combined old, future and regressed timestamps under this reason and recorded no
exact timing details, so the precise timestamp failure is not proven. Source
review found that both peers treated old readiness as terminal before ownership.

Minecraft saved and exited normally. KCD PID 45948 remained alive, and the user
confirmed the failed attempt. The guest released its handles but did not publish
its terminal client ACK within the original 250 ms cleanup rendezvous; the
controller correctly rejected this as a successful input run. Evidence, the copied
native log and host identity observation are preserved under
`runtime/evidence/hud-input-20261012-221347-39d46065f12f450e8fe60dcbc57e618b`.
Live keyboard behavior and satisfactory GUI sizing remain unverified. Its expired
owned input arm remains in place until normal KCD closure and verified cleanup.

### Waiting-state repair and delayed real-client regression

Waiting readiness now becomes temporarily ineligible when the real client ACK,
image or host heartbeat is old. It can recover only on fresh client observations;
F8 cannot acquire ownership during the gap. Armed input still expires at 250 ms,
and malformed, zero, future or regressed timestamps, changed identities and
immutable expiry remain terminal. Timestamp checks now use receipt time after
mutex work, and both peers recheck the lease there. This avoids interpreting a
newer real timestamp against a pre-wait clock sample. Worker diagnostics now
distinguish rejection reasons and record actual ACK ages/timestamps.

Closure releases controls immediately and gives the guest worker a separate
bounded one-second rendezvous for the client-generated closed ACK, including
mutex retries. The native add-on withdraws ownership before a final 1.5-second
ACK grace when the image stream ends. No timestamp is manufactured, no deadline
is renewed, and no closed session can resume input.

The actual regression run
`runtime/evidence/hud-input-20261012-222339-c67562e8e7734eaf958b9b9e6ef58b08`
deliberately withheld ready ACKs for 498 ms and the final client ACK for 550 ms.
The native peer observed a maximum prearm ACK age of 553 ms, 51 stale observations
and one recovery, then all 31 UI events, nine selections and real inventory
open/close passed. Stone/dirt swapping again agreed on client and server. Native
closed-ACK wait was 609 ms. The run published 65 UI frames, received 52 and saved
and exited normally with every cleanup flag true. KCD remained open but was not
the fixture target; this does not establish live physical input or live sizing.

The updated pure Java suite passes 353 checks and native suite 243; final Java and
native compilation/remapping passed, with independent review of waiting recovery,
active expiry, callback lifetime, fixture routing and cleanup. Frozen native
evidence is
`runtime/evidence/hud-input-waitfix-native-frozen-b8d6ba96e5cd437facf9bbdad9e21b15/verification.json`.
Add-on SHA256:
`56fb1cca6806a1cca41c9e1875da56ec1895e9781d0251bf6153d880cbd0bb80`.
Fabric JAR SHA256:
`1829334c03f050ef73aec6ddbdddeba911d4cc3dcd8638ac62f5c35fb6ef098b`.

After the user closed KCD, the owned expired input arm was archived and all 1,008
save/profile files were backed up again under `runtime/backups/20261012-232513`.
PowerShell 5.1 and 7 preflight passed. The updater installed only the repaired
owned add-on, preserving the previous bytes and enabling the pinned proxy last.
Current bundle and input-mode default: `runtime/hud-compositor-input-waitfix`.
Deployment receipt:
`runtime/evidence/hud-update-20261012-222531-279ecff953e3418591c3fa0276601090/update.json`.
It was installed unarmed before the second user-started live attempt below. The original input
and continuous stream artifacts remain available as separately verified builds.

### Second live keyboard attempt

Run `5854a3c5336448158a97e26b8bf42b57` used the repaired add-on in user-started
KCD PID 54424. Waiting recovered seven times, with a maximum prearm ACK age of
1,654 ms. F8 then activated both native and guest ownership. About 1.7 seconds
later the render gate closed ownership before any UI key events were sent.
The broad `ownership_closed` reason cannot identify its exact eligibility cause.
Closure was 256 ms after the last real ready ACK, which is consistent with the
250 ms freshness gate, but this alone does not establish the cause of the gap.

Minecraft published 220 frames; KCD uploaded 195 and submitted 1,746 draws. The
user confirmed seeing the HUD initially, then thought Minecraft had crashed.
Its logs instead show the controller's normal cancellation path, save and exit.
The closed client ACK and all handle releases succeeded. No inventory opening,
slot selection or host keyboard exclusivity was verified, and GUI size was not
accepted. KCD remained alive. Evidence and the copied native log are under
`runtime/evidence/hud-input-20261012-222727-5854a3c5336448158a97e26b8bf42b57`.

The recorded 1,031 ms callback gap and 1,135 ms image age are whole-run maxima,
not necessarily armed-phase measurements. The callback also skips overlays, so
it is not a direct measurement of every Minecraft tick. The inspected 1.21.1
render loop has no automatic background frame limiter in this path. VSync was
enabled and buffer swaps share the tick thread. At this stage a blocked
presentation was a hypothesis; the following diagnostic measured actual tick and
render stages to locate the stall without another physical F8 attempt.

### Background presentation diagnosis

The standalone real-client comparison
`runtime/evidence/hud-input-20261012-223940-b34b431d725246beb50153cec21f39d2`
completed two 12-second unfocused phases while the user kept KCD in front.
Minecraft tick observations and focus callbacks establish its unfocused state;
KCD foreground is user-reported, not independently sampled. One interrupted phase
was restarted before measurement. With original VSync/120 FPS settings the maximum
tick gap was 1,090 ms and desktop buffer swap took 1,047 ms. With VSync disabled
and a 60 FPS cap, those maxima were 701 ms and 679 ms. Every captured slow stack
was inside `GLFW.glfwSwapBuffers`; event-poll freeze was false and PBO operations
were short. This locates the stall in desktop presentation, but does not identify
the driver's underlying reason or establish that VSync alone causes it.

The following UI sequence failed the unchanged 250 ms ACK gate after six sent
events and five applied events; the armed tick gap reached 343 ms. It did not
verify the inventory. Minecraft saved and exited normally, published 590 frames,
released its mappings/handles and published its closed ACK. The native fixture
reported `ack_aged` and did not receive that final ACK before its failure exit.
Original VSync/120 FPS values were restored in both options and the actual Window;
the options file also retained those values. The controller correctly reports
failure, while the completed comparison remains useful diagnostic evidence.

The comparison adds bounded stage/tick/PBO timing and up to eight slow-thread
samples, captured outside the render thread. Pure timing tests pass 38 checks,
Java input tests 353, and the native diagnostic/receipt suite 259. A separately
compiled native add-on now records the first ownership-close cause and fixed
eligibility snapshot, without changing its gate. That add-on is not installed;
the KCD session at that time retained the previous waitfix build. Native build evidence:
`runtime/evidence/hud-input-timing-native-frozen-9018b84a73a2471a83a184e75d1fea0f`.

The first targeted follow-up kept the actual vanilla HUD framebuffer/PBO route
and skipped the separate desktop buffer swap in an explicit, bounded input mode.
No timeout relaxation or fabricated tick/ACK is involved. Its live and standalone
verification are tracked separately below when completed.

The first offscreen trial
`runtime/evidence/hud-input-20261012-224748-38ac40544c84474fbaa506e53c3b95b7`
completed 12,004 ms unfocused with 240 tick observations and no focus reset.
The maximum tick gap fell to 54 ms and the preserved swap wrapper took at most
0.831 ms; no slow stack samples occurred. VSync remained enabled and the original
120 FPS setting was retained. The trial skipped 1,411 desktop swaps and continued
publishing actual frames, demonstrating that offscreen presentation removes the
previous desktop stall in this measured interval.

The input sequence still failed: two events were applied, then the guest detected
`Own image publication stale`. Native sent three events and observed guest
closure. There were 605 published frames, 17 mailbox replacements, zero mutex
misses and zero stale-frame drops. The largest armed tick gap was only 50 ms.
Thus this attempt does not verify background inventory input. Image handles were
released and Minecraft saved/exited normally, but the failure path did not retain
the complete input cleanup proof. At that point publication and evidence work
shared one worker; the following repair separated them while preserving the
freshness limit.

The evidence-I/O separation passed 15 blocked-writer checks and the existing 174
stream checks. Control JSON now uses a separate bounded worker and PNG encoding
runs only after image-channel closure. The follow-up real run
`runtime/evidence/hud-input-20261012-225636-2ab9113cd7f44aa69659f08ab881e7ff`
still failed image freshness, after 15 applied events and eight observed slots.
Its new failure snapshot identifies the cause: all three PBO slots were pending,
the oldest was 251 ms old, and fence completion age reached 575 ms during the run.
The publication worker was waiting for a frame, with 280 ms since publication.
Pixel conversion took at most 6.72 ms, mapping writes 0.53 ms, and the completed
receipt write 1.51 ms. There were no stale-server capture skips; the server
observation was 33 ms old. Armed client tick gaps stayed at most 51 ms.

This confirms GPU readback backlog rather than evidence I/O as the remaining
cause in that run. The separation remains useful hardening. All 404 published
frames and truthful failure details were preserved; the real closed ACK,
input/image handle cleanup and evidence-worker shutdown succeeded. Minecraft
saved and exited normally. This motivated the following reduction in redundant
GPU work, with no change to the freshness limit.

### 2026-10-13: capped offscreen GPU workload trial

The scoped offscreen mode now caps the owned guest at 30 FPS and skips the unused
desktop framebuffer draw as well as the desktop swap. The inspected draw's GL
state epilogue is preserved; actual vanilla HUD rendering and PBO copies remain
active. Original option and Window settings are recorded separately and restored
on cleanup. Other modes retain their ordinary presentation behavior.

Actual run
`runtime/evidence/hud-input-20261012-230605-08c656378fc04555983218243fc6c9dc`
completed 12,063 ms unfocused at the verified 30 FPS setting, with 241 client tick
observations and no focus reset. Across the session, 517 desktop draws and swaps
were skipped and 517 GL flushes were issued. The run published 200 real hotbar
frames, of which the native fixture received 199. It applied 16 input events
unfocused; native sent 17 and observed eight selected slots. It did not open the
inventory or verify the ninth selection or stack swap.

The guest again closed with `Own image publication stale`. At the failure,
all three PBOs were pending, the oldest was 267 ms old, and the publisher was
waiting for a frame 294 ms after its last publication. Maximum fence completion
age reached 967 ms. There were no stale-server capture skips, and the server
observation was 18 ms old. Armed client tick gaps stayed at most 67 ms, with no
slow render-thread samples. Pixel conversion, mapping writes and receipt I/O
peaked at 5.98 ms, 0.35 ms and 1.97 ms respectively. The cap and blit omission
therefore did not resolve GPU readback completion delays in this run.

The guest released controls, published its real closed ACK, closed input/image
handles and stopped its evidence worker. The native fixture reported failure
and did not record the final ACK in its failure path. VSync remained enabled;
the original 120 FPS option and actual Window cap were restored without an
explicit options-file write. Minecraft saved all dimensions and exited with
code 0. The controller correctly reports failure. KCD was neither launched nor
stopped by this standalone check, and no compositor was armed. Physical KCD
input, live GUI sizing, host input exclusivity and host HUD/health integration
remain unfinished; further work is focused on the measured pending GPU fences.

### 2026-10-13: desktop clear omission and paired fence diagnosis

The opt-in offscreen helper now also omits the inspected outer
`MinecraftClient.render` clear at bytecode offset 330, before the owned framebuffer
is bound. It acts only for the exact color/depth mask 16640, a zero draw-framebuffer
binding, and the existing world/window/lease guard. The genuine HUD color and
vanilla depth clears on the owned framebuffer remain active. Paired fence
diagnostics place an additional fence immediately before `glReadPixels`, while
the original fence after that call remains the sole permission to map pixels.
Both use zero-timeout polling; the diagnostic fence cannot refresh the stream.

Actual run
`runtime/evidence/hud-input-20261012-231138-fb7f035c9abc4d4b8d5cd5c00376923d`
completed 12,007 ms unfocused with 240 tick observations at 30 FPS. It exercised
570 omitted desktop clears, 570 omitted draws/swaps and 570 GL flushes. The run
published 206 frames, with 205 received by native. It applied four unfocused
events from five sent and observed two selected slots, then failed with
`Own image publication stale`; the inventory was never opened.

At failure all three fences before readback were still pending, with observed
ages of 235, 168 and 100 ms. The publisher was waiting for a frame 263 ms after
its last publication. The largest observed pre-read fence age was 1,039 ms;
the largest additional interval between observing the pre-read and post-read
fences complete was 32 ms. These are CPU poll observations, not precise GPU
timer durations. They locate the long delay in GPU commands preceding readback,
rather than principally in mapping/copying pixels to CPU memory. They do not yet
identify the driver's scheduling reason or prove contention from another process.
Armed tick gaps remained at most 67 ms, server-stale skips were zero, map/copy
peaked at 7.76 ms and receipt I/O at 1.50 ms. Repeated end-of-frame flushes mean
a missing flush is not established as the cause.

The guest released controls, published its real closed ACK, closed input/image
handles and stopped the evidence worker. Native retained failure without recording
the final ACK in its failure path. Original enabled VSync and 120 FPS settings
were restored in options and the Window. Minecraft saved normally and exited
with code 0. The controller correctly reports failure; the helper remains opt-in,
all freshness limits are unchanged, and no new KCD compositing, physical input,
inventory or sizing result is claimed. Possible GPU contention is the next
investigation, not a verified explanation.

### 2026-10-13: bounded host frame-cap comparison prepared

`kcd2/probes/hud_gpu_budget_probe.lua` and `scripts/Test-HudGpuBudget.ps1` now
isolate whether reducing KCD's frame workload changes the existing offscreen
fixture result. The planned comparison changes the previously observed uncapped
`sys_MaxFPS=-1` to 60 while requiring `r_VSync=0`; the fresh run re-reads both
values. A positive cap already at or below 60 is rejected. The Minecraft fixture,
250 ms freshness limits and installed compositor remain unchanged.

The probe schedules its pause-updating expiry before the deferred cap write and
limits the engine-timer lease to 120 seconds. Exact run/state/timer identities
prevent stale callbacks from acting on a newer run. End and expiry restore only
the still-owned cap, preserve external changes and verify the original value by
readback. The controller always requests End in `finally`; a valid comparison
requires the requested nonexpired end, actual restoration and timer cancellation.
Engine stalls can delay script timers, so this is not an independent UTC watchdog.

The real Lua 5.2 VM passes 22 simulated-engine cases covering those paths,
including setter failures after mutation, logging failure, reload, external
changes and failed restoration. Independent source and wrapper review found no
blocker. These checks do not establish live CVar/timer behavior or GPU improvement.
The attempted live invocation stopped at preflight because the old KCD PID 54424
had closed; no host cap was changed and no Minecraft process was started.

`Archive-HudArm.ps1` archived the exact owned expired arm for run
`5854a3c5336448158a97e26b8bf42b57` while KCD was closed. Its receipt is
`runtime/evidence/hud-input-20261012-222727-5854a3c5336448158a97e26b8bf42b57/capture/arm-archive.json`.
The installed `runtime/hud-compositor-input-waitfix` artifact is unchanged and
unarmed. The user was then asked to restart with `scripts/Start-Kcd2ToolsTest.ps1`;
the resulting actual comparison is recorded below.

Once that world is ready, the controller command is:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudGpuBudget.ps1'
```

This runs the standalone Minecraft fixture against the existing KCD session's
temporary frame cap. It does not arm KCD input, launch or close KCD, or establish
physical hotbar/inventory interaction. A comparison result and verified host-cap
restoration are required before choosing the next implementation change.

### 2026-10-13: host cap restored, comparison invalid because focus never changed

The user-started KCD tools process is PID 46236, created at
`2026-10-13T11:43:27.2961094Z`. Host-budget run
`9354dbc5a9e3459e8c1ddfea711bb0f9` applied `sys_MaxFPS=60` from the exact original
value −1. Its 120-second timer then expired and restored −1 with readback success.
The controller records `restoration_verified=true` and `comparison_valid=false`;
expiry is deliberately not accepted as a valid completed comparison. Receipts are
under `runtime/evidence/hud-gpu-budget-20261013-124533-9354dbc5a9e3459e8c1ddfea711bb0f9`.

The paired Minecraft fixture `6c7341981e1344a2ae437816ae60403d` recorded 2,003
focused ticks and zero unfocused ticks. It never completed the required 12-second
unfocused phase, never armed input and sent/applied zero events. It reached its
100-second waiting limit, published 1,492 real HUD frames, then completed the
normal save/shutdown path. Real closed ACK and handle cleanup succeeded, and the
original enabled-VSync/120 FPS option and Window settings were restored. The native
fixture retained `guest_closed` failure and received 1,491 frames.

Maximum observed own-image age was 85 ms and pre-read fence age 39 ms, but those
measurements were obtained while Minecraft remained focused. They do not prove
that capping the host resolves the background GPU backlog. Full guest receipts
are under `runtime/evidence/hud-input-20261013-114534-6c7341981e1344a2ae437816ae60403d`.
The frozen 22-case source/test review receipt is
`runtime/evidence/hud-gpu-budget-native-frozen-b8c6c066d2d44500a62fda949f75f6b7/verification.json`.

The installed waitfix add-on remains unchanged and unarmed; this comparison did
not launch or stop KCD. At this point automatic hiding of the owned guest window
was being implemented to establish the required background condition without a
timed user handoff. Its first trial follows below. No new physical keyboard, inventory,
sizing or host-input exclusivity proof is claimed.

### 2026-10-13: owned window hidden, readiness blocked by the wrong focus check

The first hidden-window fixture,
`runtime/evidence/hud-input-20261013-115450-6d5b5e35855643f29a86824c671b3c10`,
verified `visible_after_hide=false` for the owned Minecraft window. Its raw GLFW
focus query reported true after hiding, while Minecraft's genuine focus state
was false: actual tick diagnostics recorded zero focused and 2,003 unfocused
ticks. The hidden-phase readiness condition nevertheless required the raw query
to become false, so its timer never completed. Input never armed and zero events
were sent or applied. The controller correctly retained failure after the
100-second waiting limit, with 1,496 genuine HUD frames published and received.

During that waiting phase the maximum client tick gap was 75 ms, readback age
38 ms, published capture age 48 ms and publication gap 91.8 ms. Those observations
are useful diagnostics, but the blocked gate prevented testing the input sequence.

The real closed ACK and all image/input handle cleanup succeeded. The guest
restored enabled VSync and 120 FPS in options and the Window, restored the
original visible/focus-on-show settings without requesting focus, and exited
normally with code 0. This verifies the bounded hide/restore path, not a successful
background inventory sequence or a resolution of GPU starvation. KCD was neither
armed, launched nor stopped by the fixture.

[GLFW 3.4's Win32 focus query](https://github.com/glfw/glfw/blob/3.4/src/win32_window.c#L1803-L1806)
compares against `GetActiveWindow`. Microsoft's
[API documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getactivewindow)
defines that result within the calling thread's message queue and distinguishes
the global foreground window. The exact bundled version was then verified as
GLFW 3.4.0 Win32 WGL within LWJGL 3.3.3. The narrow readiness correction uses the
genuine Minecraft focus callback together with verified hidden visibility and
retains the raw GLFW value as a diagnostic. It does not fabricate focus or change
the 250 ms freshness limits. Its completed standalone result follows.

### 2026-10-13: hidden, unfocused inventory fixture passes with KCD uncapped

The corrected, independently reviewed build has remapped JAR SHA256
`AB16828D0BF7C747D80A41DA6C99EFABBC0D85BF6BDE0CD8D8DD710E4B37EDB3`.
Actual fixture `ec8509f6af394e11a3e9ba5c8b062e5a` passes under
`runtime/evidence/hud-input-20261013-120534-ec8509f6af394e11a3e9ba5c8b062e5a`.
The host-settings receipt records KCD `sys_MaxFPS=-1` and `r_VSync=0`;
this successful trial did not require the temporary 60 FPS host cap. KCD's
foreground status was not independently recorded, so this does not establish the
same GPU scheduling conditions as a KCD-focused live test.

Minecraft was focused before its owned window was hidden. One genuine focus-loss
callback followed, and the 12,058 ms readiness phase recorded 241 unfocused ticks
and zero focused ticks, with unchanged framebuffer dimensions. Across the run,
276 ticks and all 31 applied events were hidden and unfocused, with no visible or
focused event applications. The native fixture acknowledged all 31 events,
observed all nine slots and inventory opening/closing; final integrated-server
proof confirms the stack swap.

The guest published 205 genuine HUD frames and the native receiver received 204.
Maximum own-image age was 155 ms and readback completion age 125 ms, with zero
fence-timeout polls. The existing 250 ms gates were unchanged. This is a successful
bounded background fixture, not a general GPU performance guarantee.

Real closed ACK, input/image handle cleanup and original enabled-VSync/120 FPS
option/Window restoration all passed. Original visibility and focus-on-show
settings were restored with focus disabled during showing and no focus request;
the client remained unfocused. The controller did not arm KCD, launch or stop it.
The installed waitfix add-on remains unchanged. The following separate live
check tests actual KCD-focused keyboard delivery; GUI sizing and host-input
exclusivity remain unverified.

### 2026-10-13: hidden live attempt still closes on stale GPU images

Live run `e63eeea7a7a54655b6871d8369993970`, at
`runtime/evidence/hud-input-20261013-120701-e63eeea7a7a54655b6871d8369993970`,
targeted the existing KCD PID 46236 and armed the installed waitfix compositor.
Both native and Minecraft ownership activated after F8, but no UI events were
applied. The guest reported stale own-image publication, and the controller
correctly recorded failure after 534 published frames. Maximum observed own-image
age was 466 ms; the failure snapshot shows the publisher awaiting a frame with
all three pre-read fences pending. Their maximum observed age was 469 ms, while
current server observation age was only 3 ms and no server-stale captures were
skipped. Hidden presentation has therefore not resolved the live GPU backlog.

The user reported that Minecraft appeared as a black window and then closed,
and the remaining keys did not work. The receipts show the controlled failure
cleanup and normal exit 0: real closed ACK, controls/handles released, visibility
and focus-on-show restored without requesting focus, and enabled VSync/120 FPS
restored in both options and the Window. KCD was neither launched nor stopped.
This run adds no physical hotbar/inventory, sizing or host-exclusivity proof.

The following diagnostic repeats the standalone hidden fixture under the bounded
60 FPS host cap. The preceding standalone pass remains valid within its recorded
conditions, without establishing live KCD GPU stability.

### 2026-10-13: capped hidden fixture passes with verified requested restoration

Host-budget run `febe0c161705407f9995f4207894bcd4` completed with
`fixture_passed=true`, `restoration_verified=true` and `comparison_valid=true`.
It changed KCD PID 46236 from `sys_MaxFPS=-1` to 60, then restored −1 through
`requested_end` before the 120-second lease expired; timer cancellation passed.
Receipts are at
`runtime/evidence/hud-gpu-budget-20261013-130919-febe0c161705407f9995f4207894bcd4`.

Its paired fixture, at
`runtime/evidence/hud-input-20261013-120919-60ce70cb803543d1a4decb5dbc2f8926`,
passes all 31 hidden/unfocused events, all nine slots, inventory opening/closing
and the integrated-server-confirmed stack swap. The 12,029 ms preparation phase
had 241 unfocused ticks and zero focused ticks; the complete run had 276 hidden/
unfocused ticks. Minecraft published 202 genuine frames and the receiver saw 201.
Maximum own-image age was 131 ms and readback completion age 43 ms, with zero
fence-timeout polls. Real closed ACK, handle cleanup, visibility/focus-on-show and
enabled-VSync/120 FPS restoration all passed, followed by normal exit 0.

The user was instructed to keep KCD in front, but no independent host-foreground
record was collected. This is a valid capped standalone fixture and restoration
result, not live compositing or proof that the cap fixes the earlier KCD-focused
failure. No physical inventory keys or host-input exclusivity are established.

The explicit `Start-HudInputLab.ps1 -Mode Live -OffscreenPresentation -HostGpuBudget`
option is now implemented. It applies the unchanged 60 FPS/120-second Lua lease
after Minecraft readiness and exact Java process validation, before compositor
arming. Shared `scripts/HudGpuBudget.ps1` also serves the fixture wrapper. Its
`finally` path checks restoration/readback; overall success requires a valid
budget, with `body_passed` recorded separately from that final verdict.

`tests/hud_gpu_budget.Tests.ps1` passes 98 assertions across 11 simulated-console
scenarios. The extracted helper also passed an actual −1→60→−1 check in KCD PID
46236, with cap, restoration and budget validity all true:
`runtime/evidence/hud-gpu-budget-20261013-131823-a11a2771df5c4b8789e69dbbe6ce5f17/budget-verification.json`.
Final independent controller review passed. No native add-on or Minecraft JAR
changed for this controller work. The user then restarted KCD with the unchanged
waitfix installation for the combined live check below.

### 2026-10-13: short live keyboard sequence and HUD size verified

Run `3f322ff93e6a4b35b1b64dd3f16410f4`, under
`runtime/evidence/hud-input-20261013-122232-3f322ff93e6a4b35b1b64dd3f16410f4`,
used the unchanged waitfix add-on in fresh KCD PID 48640, started at
`2026-10-13T12:20:51.6014572Z`. The user confirmed the HUD size was perfect and
all requested controls worked. Ten physical press/release events for 1, 2, 9,
E and Escape were sent, acknowledged and applied; the actual Creative inventory
opened and closed, with a captured inventory sample at selected slot index 8.
All nine slots and stack swapping remain standalone-fixture evidence.

The controller records `body_passed=true` and `result=passed`; the guest records
`input_completed`, `end_reason=host_closed` and no failure. It published 496 genuine
frames; native receipts show 478 uploads, 2,001 submissions and zero drops.
Maximum own-image age was 140 ms, measured readback age 46 ms and tick gap 108 ms.
The guest recorded 670 hidden/unfocused ticks and one actual focus-loss callback.
All ten events and the real closed ACK were acknowledged. Settings, visibility,
controls and image/input handles were restored/released; normal saves and exit 0
show that Minecraft's closing window was not a crash.

Native timestamps put keyboard arming at 13:23:27.197 and ownership closure at
13:23:37.670, approximately 10.47 seconds later. The installed add-on lacks the
new first-close diagnostics, so the exact trigger is unknown; neither 30-second
expiry nor focus loss is established. This is short live keyboard/sizing proof,
not full-duration operation or KCD menu/input exclusivity.

Host-budget run `11e7171fd8fb4966a351c72b2a7349ad` verified −1→60→−1 through
requested End before expiry, with timer cancellation and valid restoration:
`runtime/evidence/hud-gpu-budget-20261013-132304-11e7171fd8fb4966a351c72b2a7349ad/budget-verification.json`.
Next implementation work is full-session close diagnostics and mouse ownership;
KCD HUD suppression and health integration remain separate unfinished work.
