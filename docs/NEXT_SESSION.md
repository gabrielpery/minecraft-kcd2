# Resume checkpoint — 28 October 2026

## Current result

The combined live walking/aimed-block/HUD profile passes in KCD2. The user took a
W step, aimed and broke the seed, then walked S with the hotbar visible and confirmed
**“Done, worked perfectly.”** Preserve this working milestone. Do not repeat its
implementation or retune the verified 200 ms buffer. Free roaming remains unfinished.

## Latest combined live PASS

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

1. Exercise top/side placement and inventory transitions in the new combined live
   mode. They already pass separately and in the combined scripted fixture. Keep
   each check short enough to remove every stone before the existing12s aim cutoff.
2. Design persistent-session and terrain-streaming ownership before expanding bounds
   or removing automatic restoration. Current finite footprint/deadlines are intentional.
3. Add general terrain-face placement with an explicit terrain/support policy. The
   owned lab support does not prove arbitrary placement against KCD terrain.

Official tools1.5.5 only. Retail1.5.6 remains gated by loader/address-library work.

## Process state and next live launch

KCD PID49756 is the current tools world. Minecraft exited normally. New179b92... arm
is consumed and unarchived. Olde50b03... arm was archived before the bundle update.
Recheck processes and exact receipts. No Computer Use was invoked during the new
combined phase; do not assume a historical Escape stop persists in a new turn.

After closing KCD normally, archive only this owned expired arm and start fresh:

```powershell
$r = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$r/scripts/Archive-HudArm.ps1" -ReceiptPath "$r/runtime/evidence/hud-walking-aimed-20261028-142552-8cdbdbd02281412a86fb584a0dd9eab1/capture/stream-arming.json"
& "$r/scripts/Start-Kcd2ToolsTest.ps1"
```

Only when another manual check is needed and the user is ready:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-HudWalkingAimed.ps1'
```

Wait for HUD_WALKING_AIMED_READY before the F8 prompt. Wait for the stone, start
walking soon, and keep KCD foreground until HUD disappearance30s after F8. Movement
returns about16s after first step. No administrator mode, PowerShell setup or further
installation is needed on this machine. Never load retail1.5.6 saves in tools1.5.5.
Routine implementation, launches, tests and Git pushes are authorized. Give formatted
commands before a question widget when user action is necessary.

Workspace: `C:/Users/xephi/Documents/ChatGPT/New project/MineCome`.
Public repo: `https://github.com/gabrielpery/minecraft-kcd2`, branch `codex/initial-import`.
Prior guest checkpoint42afa66. Inspect current Git log/status for the combined live
commit; never reset functioning work to an old checkpoint.
