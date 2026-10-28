# Resume checkpoint — 28 October 2026

## Delivery priority — user correction

The user says progress per time/usage is too poor and wants less reliance on manual
testing. Apply the delivery workflow in AGENTS.md. Do not start this session with
another first-click countdown. The warm-up below is implemented; its live validation
can be included in the next feature acceptance session.

Next deliverable: integrate repeatable sessions in the same KCD process, rather
than stopping at the existing standalone rearm policy. Then develop longer playable
sessions with explicit terrain/ownership handling. Keep the verified current profile
available. Reserve human input for the final foreground/composition check; use the
existing actual-Minecraft fixtures and coupled-game checks for ordinary regression.

## Current result

**Newest implementation, not yet live verified:** startup now prewarms the real
camera reader, foreground query and pure settled policy using disposable diagnostic
state before Minecraft starts. No input/permits/HTTP are generated. Per-click stage
timings are recorded in memory. Warm-up15/controller179 checks pass; offline snapshot
first/repeat24.91/1.71 ms, policy56.20/1.19 ms. Retained evidence:
`runtime/evidence/hud-aim-admission-offline-20261028-161412-d64f9fe773c4410f80ae35f279f3e7c0/warmup-comparison.json`.
Validate this warmed path with the next feature milestone; do not repeat the
duplicate-admission removal or make another isolated manual comparison a blocker.

Latest comparison HUD `1ec548ae2a1f4e42b60c54c79ab3b771`, probe
`18efa61cbae141d383077103d1a3c324`, at
`runtime/evidence/hud-walking-aimed-20261028-160030-18efa61cbae141d383077103d1a3c324/`
did NOT pass: first click still stale, second placed without moving, added block
broke, seed remained at the 12-second cutoff. Controller failed cleanup admission,
then restored KCD and removed native authority/stones; Minecraft exited with code 0.
Duplicate-admission removal alone did not solve the delay. First observed-to-send
processing was 132 ms versus 33 ms for the next click. Preserve the prior full pass.

The combined live walking/aimed-block/HUD profile now passes both top-face and
side-face placement, both breaks, inventory and resumed walking in KCD2. Preserve
these milestones and the 200 ms buffer. Free roaming remains unfinished. The
latest side-face run exposed an intermittent stale-permit rejection on the first
click, before vanilla placement; a second click completed the sequence.

Latest HUD `557a41b52b7142bfa9fd98e999074f08`, probe `af23ad5d4c154c0b8de845fee2508f9a`:
`runtime/evidence/hud-walking-aimed-20261028-154714-af23ad5d4c154c0b8de845fee2508f9a/`.
156/156 movement updates/readbacks, WEST placement, both breaks, 1.994 seconds of
stationary inventory, resumed S, full cleanup and exit 0. First request's permit
age was 505.5376 ms (limit 500), `vanilla_queued=false`; second was 303.225 ms.
This is not evidence of player-collision rejection. See PROGRESS.md and separate
user-feedback.json. The camera reader repair now has a complete live pass.

A preceding run `ee5f7e5f0b704689ba94acec6ca987b9` expired before F8: buffered
READY output was stale and a 35-second prompt was sent with only 3.412 seconds
remaining. Exact guest deadline metadata and `Read-HudInputPromptWindow` now
prevent relying on that stale countdown. Check current receipts immediately
before prompting, allow message-delivery time, and refuse a short window. The
helper checks liveness and timestamps, not whether F8 has already been pressed.

## Latest top-face PASS and side-face failure

- Top HUD `17311ef5fda841d6869e9cbe3484af1f`, probe `6a7cde05c377471e9c7b92bcfb091222`.
  Evidence: `runtime/evidence/hud-walking-aimed-20261028-150034-6a7cde05c377471e9c7b92bcfb091222/`.
  155/155 source/readback pairs, UP-face placement and both breaks, zero owned
  stones, support removed before restoration, Minecraft exit0. Inventory lasts
  1850.4451ms/194 observations/36 distinct server advances with zero displacement
  or bindings; post-close S moves both sides .859955m. User feedback is separate;
  primary machine visual/physical-W-attempt flags stay false.
- `-Scenario WalkingBreak|TopFaceInventory|SideFaceInventory` selects proof requirements.
  Default WalkingBreak is unchanged. Enhanced modes require exact UP/WEST placement,
  added-block and seed breaks, closed inventory, and fresh accepted resumed movement.
  E toggles inventory both ways, so Escape is unnecessary.
- New actual Minecraft fixture `8fe454e8df144b17a0bc2a0b949e0c1d`:
  `runtime/evidence/hud-physical-fixture-20261028-145757-8fe454e8df144b17a0bc2a0b949e0c1d/`.
  95 source hashes matched before the later PowerShell camera-reader change.
  Two stationary inventory windows (.783/.804s) and subsequent walking pass the
  supplemental inventory proof. This is scripted input, not KCD compositing proof.
  Java checks: inventory35, movement336, aim24; controller159.
- Side HUD `aee7bfb17fa54dc18a665f767468af67`, probe `0c7a45dd698f49ec990a414dfb3dc028`.
  Evidence: `runtime/evidence/hud-walking-aimed-20261028-150753-0c7a45dd698f49ec990a414dfb3dc028/`.
  Windows denied Get-Content(host-view.json); parent stopped relay, then Minecraft
  failed its stream and saved/exited0. Only74 forwards/70 readbacks; KCD restored
  and remained alive. User: “didnt do anything just crashed.” Preserve failed evidence.
  Initial150658/1332a14ecd05467a9d707a9c19bb7dd0 attempt timed out during debug HTTP
  probe setup, before arming; foregrounding KCD allowed initialization.
- Narrow repair in HudCameraDelivery.ps1 uses one bounded opened snapshot with
  ReadWrite|Delete sharing. Only transient missing/sharing/delete-pending races
  yield unavailable; the current aim edge is declined, never replayed. Malformed,
  oversized, invalid UTF-8 and access failures remain fatal. No wait or lease change.
  Camera138 and controller159 checks pass, including concurrent production writer
  replacement, exclusive-lock decline and recovery. This does not establish a fix
  for the older 100ms camera-writer lock issue.
- Computer Use attempt: HUD `8e968faa4bf340209f2c8b838d40de94`, probe
  `bd53c4362e0646b28c6540363e4a152e`, evidence
  `runtime/evidence/hud-walking-aimed-20261028-151957-bd53c4362e0646b28c6540363e4a152e/`.
  F8 and2 press_key calls returned successfully, but MineCome registered zero events.
  Guest cancelled after60s waiting and exited0; no movement began. 811 camera samples,
  no camera read error, but no repaired full walking/side-face proof. Supplemental
  computer-use-intent/outcome.json records explicit automated-input provenance.
  Cause of missed keys is not isolated. CU can close/relaunch games; do not claim
  the full interactive test can currently be completed autonomously.

## Earlier combined walking-break PASS

- HUD `179b92e699de495880dec7d6f6ac7449`, probe `8cdbdbd02281412a86fb584a0dd9eab1`.
- Evidence: `runtime/evidence/hud-walking-aimed-20261028-142552-8cdbdbd02281412a86fb584a0dd9eab1/`.
- 156/156 source points, applied readbacks and source crossings. Guest 15,505 ms,
  158 trace records, .847736 m maximum walk, zero corrections. Native restoration
  after 15,772.553 ms, 62 writes, zero readback error and timers cancelled.
- Exactly one physical left-click break: original edge sequence1, arena1/request1/
  permit48; original permit installed35ms before edge. Confirmed vanilla client/server
  WEST-face break at (2,64,0), KCD removal sequence748, no rejections. Bootstrap
  placement is automatic; this run does not prove user placement.
- Guest closure UTC1793197642600, native cleanup verified1793197643060, follower
  finish requested1793197646094. Zero owned stones, support removed, all input/proxy/
  mapping resources released. GPU cap60 restored to-1. Minecraft exit0.
- 909 HUD frames with no drops, 806 fresh camera samples. Two sampled-footprint
  boundary pauses/one resumption: this is bounded W/S, not unrestricted movement.
- Separate user-feedback.json records the visual confirmation. Primary machine
  receipts retain visual_verified=false and must not be rewritten.
- Independent audit matches recorded Lua snapshots/sources, trace, ready/closed
  receipts, native executable, installed compositor, terrain and exact game hashes.
  This live directory has no complete Java source manifest; keep the tested commit.

## Implemented architecture and limits

Use only `scripts/Start-HudWalkingAimed.ps1` for this combined profile. Its new
protocol2 physical-input/selective-world-click compositor is separate from the old
walking and stone profiles. Never combine their old flags or run two controllers.

Java pins build support, patch and save; walking waits for vanilla bootstrap.
Aiming requires neutral grounded client/server agreement, 200 ms stationary source
history and matched original native camera/player evidence. Fixed initial alignment,
.25 m eye tolerance, .05 m feet agreement and original timestamps remain unchanged.
Declined edges are consumed once and never replayed when the player later settles.

The relay's explicit `--external-physical-pose-run` consumes walking camera samples
with strict run/sequence/engine-clock/freshness checks. It disables extra SamplePose
HTTP polling, including cleanup. The synthetic test verifies zero calls; the live
claim follows from its logged mode and matched binary, not a packet capture.

Start walking within12s of F8. Aiming ends12s after first movement; remove every
owned stone before that cutoff. Pending actions drain and support/native authority
clean up before follower finish at about16s. HUD remains until30s. No movement or
leftover stones cannot report a full pass. No actions are accepted after restoration.
Combined intent dispatch is bounded150ms; relay shutdown is asynchronous so movement
forwarding continues. Failure cleanup revokes known aimed authority before ending
movement. Startup must recognize the unstarted movement timestamp -1, not treat it
as an elapsed cutoff; this has regression coverage.

Installed bundle: `runtime/hud-compositor-walking-aimed`.
Profile: `config/hud-walking-aimed-profile.json`.
Addon SHA256 `18090d6ad5dda2cecc7f5dae9127c1360a7e8ad748d8070d86f8aaf19d01905b`.
Native host SHA256 `E160DB6C052B84D5604CE43C56AC32FBF7848B19A70972BD636FD39C3E27D45F`.
Update evidence: `runtime/evidence/hud-update-20261028-142142-ac73673d4aad41d4a94522d1bd2829e4/`.

## Validation and earlier milestones

Build/assemble passes. New Java gate24, existing physical336/writer26 checks pass.
Combined controller77/profile147 checks and legacy fixture196/relay165 plus renderer/
profile regressions pass. Five related native CTests pass, including old fixed,
interactive and aimed modes and new external-pose real-wire integration.

The actual Minecraft combined fixture already passes flat ground and captured
terrain: `Test-HudPhysicalMovementFixture.ps1 -ExtendedWalking -AimedBlocks`.
It bootstraps, walks W/W/S, places/breaks top and west-side blocks, breaks the seed,
reopens inventory, verifies movement suppression, then walks W/S again. All six
vanilla block actions and cleanup are confirmed; both manifests match92 files.
- Flat: `runtime/evidence/hud-physical-fixture-20261028-135417-b5f250088e4841088fffebef1ea8cdb0/`.
- Captured: `runtime/evidence/hud-physical-fixture-20261028-135545-61868402650549db9387657daf1b8065/`.
- Existing real aiming lab28 scenarios PASS: `runtime/evidence/aimed-stone-20261028-133833-c360373cce28416593baaaae60138c25/`.

Earlier physical walking baseline: HUD `a673494c0d084564ac3c83e3fdcdd47d`, evidence
`runtime/evidence/hud-walking-20261028-131455-e50b03b5a7eb4f1c92b58f42d3da012b/`.
156/156 readbacks, normal restoration; user “worked. still delay, but worked.”
Keep failed trials documented in PROGRESS.md. In particular, camera replacement
once exhausted its existing100ms retry budget; its external lock holder remains
unknown. Later unchanged camera code passed. Do not mark that intermittent issue fixed.

## Next work

1. Integrate explicit same-process rearm in a separate opt-in profile. A standalone
   `rearm_policy.hpp` and dedicated CTest now pass 363 assertions; it admits at most
   two generations only after verified, identity-bound cleanup. Nothing uses it
   live yet. Replace one-shot session objects, retire render ownership, and avoid
   `release()`/GPU wait on ordinary render callbacks. Keep current profile intact.
   Terrain streaming follows: current GroundPatch captures remap to local zero and
   GroundCollision.install replaces a singleton map, so longer timers alone cannot
   provide free roaming. Design immutable alignment and transactional proxy ownership
   before expanding bounds or removing restoration.
2. Extend toward a longer playable session through that terrain/ownership work.
   Do not merely increase timers over the current tiny sampled footprint.
3. Add general terrain-face placement with an explicit terrain/support policy. The
   owned lab support does not prove arbitrary placement against KCD terrain.

Keep the intermittent first-click expiry tracked, with original timestamps and
freshness limits intact. The duplicate admission and startup warm-up are already
implemented. Revisit measured residual delays if they block the milestone; validate
the warmed path in its batched acceptance check. Do not repeat completed face and
inventory implementation just to obtain another equivalent recording.

Reuse these automated entry points when relevant (do not run all for every edit):

- `scripts/Test-HudPhysicalMovementFixture.ps1 -ExtendedWalking -AimedBlocks`:
  actual Minecraft movement, inventory, top/side placement and cleanup; optional
  `-GroundPatchFile` covers recorded KCD ground.
- `scripts/Start-AimedStoneLab.ps1`: actual Minecraft aiming scenarios.
- `scripts/Test-CoupledMovement.ps1 -HudWorld`: automatic two-game movement and
  restoration with an already-loaded KCD world. This does not prove native HUD
  composition or physical input capture.

Use the narrow unit/contract tests for a localized fix. No extra test framework is
needed merely to change the workflow. The remaining human-only acceptance scope
is the actual foreground input/composition boundary and subjective responsiveness.

Official tools1.5.5 only. Retail1.5.6 remains gated by loader/address-library work.

## Process state and next live launch

KCD29300 hosted the successful side-face test; KCD24480 hosted the later comparison.
Both were closed normally after Minecraft exited0. Their557a... and1ec5... arms
are archived, as are the previous8e968... and expired-ee5f... arms. Both games are
closed. Recheck process/receipt state before continuing.
Computer Use works for close/restart through node_repl @oai/sky; no
user-stop was reported in this phase. Never infer a historical Escape stop applies
to a new turn. Follow the installed skill and record automation provenance.

The latest arm has already been archived. Start a fresh test world when needed:

```powershell
$r = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$r/scripts/Start-Kcd2ToolsTest.ps1"
```

Only when another manual check is needed and the user is ready:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-HudWalkingAimed.ps1' -Scenario SideFaceInventory
```

Wait for HUD_WALKING_AIMED_READY, then use Read-HudInputPromptWindow against that
run's capture directory immediately before the F8 prompt. Never repeat the old
console countdown. Wait for the stone, start
walking soon, and keep KCD foreground until HUD disappearance30s after F8. Movement
returns about16s after first step. No administrator mode, PowerShell setup or further
installation is needed on this machine. Never load retail1.5.6 saves in tools1.5.5.
Routine implementation, launches, tests and Git pushes are authorized. Give formatted
commands before a question widget when user action is necessary.

Workspace: `C:/Users/xephi/Documents/ChatGPT/New project/MineCome`.
Public repo: `https://github.com/gabrielpery/minecraft-kcd2`, branch `codex/initial-import`.
Prior guest checkpoint42afa66. Inspect current Git log/status for the combined live
commit; never reset functioning work to an old checkpoint.
