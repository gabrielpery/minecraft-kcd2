# Resume checkpoint — 8 November 2026

## Direction

Deliver docs/PRODUCT.md in integrated feature batches. The user prioritizes
playable progress, automated tests and minimal manual checks. Preserve working
HUD/inventory, movement, commands, Creative flight, hands, block shapes/outlines,
placement on captured ground and native depth composition. Full block coverage,
broader host collision, Survival/NPC combat and Elytra remain required.

## Latest milestone: native third-person Steve and aiming

F5 now cycles requested first/back/front perspective in WorldBlocks. Input profile
6 forwards a balanced edge only on the world screen; existing profiles stay
unchanged. The request is written as perspective_request in gameplay-pose.json.
Native schema 3 aim samples acknowledge the actual camera/perspective and carry
separate player-eye and render-camera rays. Minecraft changes perspective only
from that acknowledgement, keeping block reach tied to the eye.

Native camera following uses the observed player head direction, including mouse
yaw/pitch. Scene raycasts clip the 2.5m orbit camera. Henry's character slot 0 is
suppressed using DrawSlot while third person owns a visible baseline; no entity
Hide/Invisible or physics changes. Cleanup resets camera and restores that known
visible baseline. Host cleanup now requires explicit_stop and exact restoration
proof; it cannot report success after a camera/body restore failure.
An unresolved terminal camera/body restore obligation also blocks later Begin
with prior_cleanup_incomplete; successful cleanup still permits a later session.

First integrated native run PASS, via Computer Use without user testing:
- F5 back view displayed Steve, Henry was hidden, and mouse yaw/pitch worked.
- Actual oak-slab placement and aimed mining worked: one place/two breaks,
  zero rejections. One magenta fixture-wall cell was mined during a CUA drag.
- 243,069ms active, 11,072 player-render frames, 4,267 captures; normal save/exit.
- Terminal explicit_stop, camera_restored=true, body_restore_dispatched=true,
  body_hidden=false.

Evidence: runtime/evidence/gameplay-kcd-20261108-115405-eeaa84ce4ed44b948e9fb9b8b0bb3e65
(verification.json, gameplay-session.json, capture/stream-result.json), plus
runtime/evidence/gameplay-movement-20261108-115432-4def0261e48b421fba1b1fdfbf78b8d8/verification.json.
The isolated instance is runtime/gameplay/native-perspective-20261108/instance;
its remaining wall is a disposable visual fixture, not the user's construction.

Subsequent Computer Use observations verified front Steve, front mouse yaw/pitch,
inventory mouse-look suppression and the complete F5 cycle 0→1→2→0 with the
first-person hand/crosshair/hotbar restored. Returning to first person initially
exposed a buffered-log ACK: native mode 0 arrived within 120ms, but its log tail was
not flushed before the host deadline. The host now sends a flush-only marker
every 50ms during the same 300ms wait. No timestamp renewal or deadline relaxation.
The regression reproduces the old failure and passes; the final live return works.

Final evidence: runtime/evidence/gameplay-kcd-20261108-121206-2ea48f96077f4763a45f489df5863e51
(native-perspective-observation.json, saved back/front/first-person-return aim
receipts and host-movement.json). Normal shutdown, no session/host failure,
camera/body restored. The agent stopped after 226,920ms, before the requested 240s;
verification.json correctly fails that duration assertion. Preserve it; report
perspective acceptance, not an overall 240s smoke PASS. The earlier front/inventory
run with the original ACK failure remains at gameplay-kcd-20261108-120524-886c73ecc4424c8cab9a3bab93d87985.

## Next implementation and limits

Add orbit-camera collision with owned Minecraft blocks. Target visibility is
already protected using actual voxel shapes between render camera and eye-ray
hit, including gaps, but the camera can still enter blocks. Native scenery
clipping is implemented. Keep the eye-based 4.5m reach and authoritative selection.
Then progress broader host collision and Minecraft combat/Elytra; avoid repeating
completed small HUD/control tests.

Sustained native third-person walking is unverified. Brief CUA W presses produced
zero movement events, so neither pass nor failure can be inferred. Actual-Minecraft
player/walking acceptance passed separately (gameplay-player-20261108-114203-c9f9e299830e417bbfc3a41b776a8ca4,
nine stages/18 PNGs, matching 1.2915m client/server movement). Batch native walking
with the next larger acceptance instead of requiring user input now.

Known lifecycle follow-up: after collision release during shutdown, the client can
fall while the save/transport drains. The server/resume checkpoint retains the
correct position and the next launch restores it. Consider keeping collision
attached until disconnect, with a real stop/reopen fixture; do not mistake the
terminal client-only Y change for third-person walking drift.

WorldBlocks/chat permits only one accepted arm per KCD process; a same-process
retry correctly never armed. Restart KCD for this profile. Both games are closed
and renderer baseline restored (gameplay-hud-restore-20261108-121748-7a1474e0745449b7adc531ebdfc6fd63).
The fresh bundle is runtime/hud-perspective-20261108. No active test remains.

## Checks and deployment

Java assemble passed: HUD input 353, gameplay wire 205, blocks 300, movement 37.
Native input 397 and gameplay-chat 1,729 checks pass. Lua movement 26 cases and the
other focused lifecycle suites pass.
PowerShell 7 Test-GameplayMovementHost.ps1 passes 29 groups, including legacy
transport, schema 3 eye/render separation, requests 0/1/2, buffered ACK and cleanup failures.
Protocol/session documentation and launcher F5 text are updated. Exact native
visual/input acceptance is limited to the observations recorded above.

Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
JDK C:/Program Files/Java/jdk-24; offline Gradle cache minecraft/.gradle-user-home.
Use the bundled PowerShell7 path from existing launcher scripts; no admin needed.
Pinned config: config/hud-gameplay-chat-profile-v5.json. Addon SHA256 now
4ae823f4fcf1076de33210b806a148223fbfdebff102fabb477f70d3f8fe6ed0 (414,208 bytes).
Proxy remains f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab.
The exact official tools 1.5.5 guard remains unchanged; retail is unsupported.
Use a fresh prepared bundle after changes; don't reuse an old install receipt.
Assets, runtimes and saves stay out of Git. These sources and docs are delivered
together; check git status/log before resuming rather than rebuilding old edits.

Historical completed milestones and detailed evidence are in docs/PROGRESS.md;
launch/profile instructions are in docs/GAMEPLAY_SESSION.md. Do not restart from
old checkpoints that still described native F5 as unimplemented.
