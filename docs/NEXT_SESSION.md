# Resume checkpoint — 8 November 2026

## Completed milestone

Deliver docs/PRODUCT.md in integrated batches with minimal manual testing.
Preserve HUD/inventory, walking, commands, Creative flight, Steve/hands,
block shapes/outlines, placement on captured ground and native depth composition.
Full block coverage, broader host collision, Survival/NPC combat and Elytra remain
required. Do not restart completed small-control acceptance sequences.

F5 native first/back/front perspective, mouse yaw/pitch, eye-based aiming,
placement/mining and camera/body restoration already passed native acceptance.
The latest work adds owned Minecraft block camera collision and fixes native
third-person eye following during walking.

Server-confirmed getCameraCollisionShape boxes are packed on a sixteenth grid,
bounded to 64 owned blocks / 512 boxes, installed atomically in chunks and bound
to each pose by generation. Native camera sweep uses 0.12m clearance plus 0.03m
margin and combines with KCD scenery raycasts. Unavailable geometry collapses
the orbit to the eye; it never truncates obstacles. Reach remains 4.5m from eye.

KCD GetHeadPos froze under the camera override while native feet moved. The
camera now derives its eye from the bounded initial local head offset, actual
native feet and live yaw. A separate Java race falsely rejected a concurrently
published observation as future data and could clear W; observation is now read
before its monotonic clock check, retaining the 250ms expiry.

## Live automated acceptance

PASS: runtime/evidence/gameplay-kcd-20261108-124939-1ae7d0c08c614ae8b364b11f68b71051.
- Six strides each in back/front view: 4.013m / 3.915m cumulative, max excursion
  0.808m. Inventory suppression, first-person return, save and cleanup pass.
- 12 movement presses / 36 held ticks, no source pause interrupted held input.
- Eight capture stages / 16 PNGs. Input is scripted through the guest key
  adapter and vanilla client/server, not physical Windows key delivery.
- Independent camera verifier: 69 back / 66 front native readbacks, 45 / 66
  clipped, zero penetration into the eight expanded fixture cubes.
- Fixture writes no position/velocity/camera; the ordinary production bridge
  still performs its owned native pose writes. Wall seeding is not placement proof.

Scripts: Test-KcdThirdPersonWalking.ps1 and Test-KcdCameraCollisionEvidence.ps1.
The walking fixture now includes a 12-second stationary back-view interval with
UTC start/end evidence for depth diagnosis, then the unchanged 12-stride check.
Keep KCD2 in front; no manual keys or countdown required. The camera verifier
needs the matching run lines preserved as native-movement.log and the exact
8-wall fixture; it rejects changing geometry without historical snapshots.

Failed live attempts remain preserved: 33f9667359a04903968ddb5f69a64d06 exposed the
frozen eye, 31f1499086f54a3ba18e3b39386108bc exposed early walking-image timing and
the freshness race. Do not relabel them as passes.

## Foliage flashing investigation

The user's leaf/grass flashing against Steve is not yet fully resolved. Fixed a
real metadata bug: auxiliary depth targets could overwrite the selected depth
resource's proof. The addon now retains bounded per-resource samples.
The first moving run still had only 629/1248 eligible depth-ready frames:
37 no_sample, 582 bad_view, zero bad_source. Therefore do not claim the source
fix alone cured foliage flicker. Exact diagnostics now separate sample age,
camera age, position, basis and projection rejection without loosening thresholds.
Frame-time admission is implemented and compiled: the same client-thread helper
updates perspective/aim before clicks and at render-frame start, pins the sample
through the whole frame, and preserves its UTC. Ten focused regressions pass
(215 wire checks total). This removes up to 50ms of tick waiting.

Final live run also PASSES walking/collision:
runtime/evidence/gameplay-kcd-20261108-130101-5e1f8cec43244b5199caeffe9976f712.
It lasted 31.469s, included 12.046s still in back view, repeated all 12 strides and
checked 177 back / 65 front camera readbacks with zero penetration; cleanup passed.
The stationary five-second interval had 325/441 depth-ready frames, 116 failures
solely camera_age, 79 ready changes and zero source/position/basis/projection
mismatches. host-depth-analysis.json and native-depth-addon.log preserve this.

Next rendering fix: reduce actual native ACK-to-guest-frame age; do not merely
renew timestamps or loosen the 250ms/3cm limits. Sample acquisition, log-flush
delay, guest readback and upload remain in the path. Stationary evidence isolates
expiry rather than geometric z-fighting. Temporal alpha/jitter artifacts may
still need assessment after fixing expiry. Do not claim foliage fixed yet.

## Validation and deployment

Java assemble passes; wire tests 215, block tests 323, movement 42. Lua movement 33 cases and
host-worker 39 groups pass. Native depth reflection/projection regressions pass.
WorldBlocks/chat allows one accepted arm per KCD process; restart for another
session. Use fresh bundles after an addon/profile hash change, and restore the
installed old bundle before repinning its profile. Never modify a loaded addon.

Current diagnostic bundle: runtime/hud-camera-depth-20261108. Addon 415744 bytes,
SHA256 012033848440ff090d22faa840c4221ad12e80c494f3df507fae54d8412ea0bc.
Proxy unchanged: f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab.
Only exact official tools 1.5.5 is supported; retail is not.
JDK C:/Program Files/Java/jdk-24; Gradle cache minecraft/.gradle-user-home.
Bundled PowerShell 7 is installed; no admin setup is needed.
Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
Assets, runtimes and saves stay out of Git.

Both games closed; no active test remains. Renderer baseline restored:
runtime/evidence/gameplay-hud-restore-20261108-130327-0461c330d7f344349c5a0792b2abafa0.
The latest disposable 8-wall instance is runtime/gameplay/camera-collision-20261108-d/instance.
Use its source runtime/gameplay/world-blocks-native-20261106/instance for another
fresh fixture if needed. Preserve original save/evidence rather than overwriting.

Known separate lifecycle follow-up: after collision detaches during shutdown,
the client can fall while transport/save drains. Server/resume checkpoint remains
correct. Fix later with a focused stop/reopen fixture; do not misdiagnose terminal
client-only Y drift as failed third-person walking.
