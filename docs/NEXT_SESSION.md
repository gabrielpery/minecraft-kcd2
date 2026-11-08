# Resume checkpoint — 8 November 2026

## Working capability and latest change

Follow docs/PRODUCT.md. Preserve the integrated persistent gameplay path: HUD,
inventory/chat, walking/Creative flight, Steve/hands, native F5/mouse look,
owned block shapes/outlines/building and camera collision. Survival/NPC combat,
Elytra, general block coverage and broader host collision are still required.
Do not restart completed manual control tests.

The latest batch reduces camera handoff delay and eliminates measured stationary
native-depth dropouts. WorldBlocks publishes gameplay-aim.json immediately after
its validated native ACK, then prefetches the next query while publishing the
legacy host-view.json. Every file retains original accepted seq/UTC; each gets
its own 250ms age check. One query remains outstanding at most; pose/cancellation
work runs between ACKs. Absolute ACK deadlines remain300ms.
The sample UTC is taken immediately before the actual HTTP sample dispatch,
after identity checks/earlier split commands. Target cadence is40ms, fallback
log flush15ms. Lua appends an immediate best-effort view delimiter, including
asynchronous receipts. No resampling or timestamp renewal from flushes.

Java wakes the camera reader on file changes (10ms fallback) and image publisher
on frames (5ms fallback). A new verified camera may capture after25ms; duplicates
retain50ms. Only a successful GPU enqueue consumes the opportunity. Opaque RGB
conversion avoids divisions; raw depth bits and transparent alpha stay exact.
Native addon/shader binaries were unchanged in this batch.

## Latest live evidence — no manual inputs required

runtime/evidence/gameplay-kcd-20261108-135115-2a216a227e374c5e9b779bb43700dadc

- PASS native walking: six strides in back and front views, travel4.013m/3.915m,
  max excursion0.808m, inventory suppression, first-person return, save/cleanup.
- PASS camera collision:235 back/100 front native samples, zero penetration.
- PASS strict stationary foliage depth:392/392 frames over4996ms inside12030ms
  dwell, zero readiness transitions or rejection reasons. Baseline was325/441,
  79 transitions. No claim that every foliage material is visually perfect.
- Request cadence74.63ms; request→renderer-file publication73.30ms, including
  ACK→publication14.36ms (last64 samples). These are NOT physical-input latency.
- Capture completed621/621 frames with no busy skips/fence timeouts.
- Scripts use guest key events through actual vanilla client/server and native
  bridge. They do not claim physical Windows input or new block placement proof.
- Preserve native-depth-addon.log, native-movement.log, host-depth-analysis.json,
  native-walking-verification.json, camera-collision-verification.json and
  foliage-depth-verification.json. The latter is immutable and checks identity,
  run clocks, cumulative counters and wholly contained stationary intervals.

Intermediate stationary failures are preserved in runs0fb461...,64e397...,17801...
under runtime/evidence/gameplay-kcd-20261108-*. Do not overwrite/relabel them.

## Remaining blocker and next renderer implementation

Moving-view foliage flashing is NOT fully fixed. Latest complete moving phases
had249/341 and439/459 ready frames. The latter had18 position,1 basis and1
camera-age failures; therefore timing alone cannot guarantee alignment.
MineComeMouseHud.fx currently compares guest/native depth at the same UV. The
next feature must reproject WORLD COLOUR AND DEPTH to the current native camera;
HUD/hands stay unchanged. Changing only depth UV or widening the3cm tolerance
would be incorrect. Do not renew source UTC or blindly replace it with capture UTC.

Concrete integration prerequisites established from pinned upstream:
1. Seal submitted native proofs at public addon_event::present, consume only the
   current presentation epoch, require a uniquely sampled selected source DSV.
   Current state.depth_sample fallback can retain proof250ms and draw sampling is
   tied to guest generations. Resource identity alone does not prove frame content.
2. Initially require GenericDepth DepthCopyBeforeClears=0 (current installed
   default, no DEPTH override). Pinned GenericDepth then copies the selected DSV
   at begin-effects. Modes1/2 need explicit preserved-copy provenance; their
   internal API copies do not emit add-on copy callbacks. Do not silently change
   the user's mode or borrow a previous epoch's matching camera.
3. Preserve reflected matrix row/column packing and full native projection/jitter;
   build transforms from actual guest/native camera bases. Keep original
   freshness; bounded camera deltas apply only when reprojection is active.
4. Forward-project colour+depth into an owned target with nearest-depth arbitration.
   Leave disoccluded holes transparent; reject bridges across depth discontinuities.
   Point scatter alone leaves pinholes and is only groundwork, not a finished fix.
5. Compare warped eye-depth with native depth, overlay unchanged HUD/hands. Test
   identity, translation, rotation, overlaps, silhouette holes, native foreground,
   invalid epoch/source and actual GPU budget before native deployment.

This is a separate renderer increment. Avoid another loop of small timing tweaks
or repeated human walking checks. Existing automation can verify the integration.

## Validation / deployment / resume

PASS Java assemble, wire230, stream458 (real Win32 included), blocks323;
Lua movement35; host-worker44; combined terrain/block worker6.
The combined fixture had a premature-cancel race: it now waits for expanded
pose AND block dispatch, within original3s bound, before strict ordering checks.
A source review found no blockers in the aim-first host pipeline.

Use Test-KcdThirdPersonWalking.ps1, Test-KcdCameraCollisionEvidence.ps1 and
Test-KcdFoliageDepthEvidence.ps1. Keep KCD2 focused; no F8/user countdown needed.
The walking fixture seeds eight magenta wall cells, has a12-second still interval,
then six strides each view, inventory and first-person return. A fresh process is
required after each WorldBlocks/chat arm (one accepted arm per KCD process).

Both games closed; no active test. Renderer baseline restored:
runtime/evidence/gameplay-hud-restore-20261108-135839-8844accf852f4ad28990997d3f50b865
Prepared bundle:runtime/hud-foliage-latency-20261108 (restored).
Addon415744bytes, SHA256012033848440ff090d22faa840c4221ad12e80c494f3df507fae54d8412ea0bc.
Proxy:f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab.
After native/profile edits build a FRESH bundle; never replace loaded renderer files.
Only exact official tools1.5.5 is supported; retail is not.
Latest used fixture:runtime/gameplay/foliage-latency-20261108-d/instance.
Fresh fixture source:runtime/gameplay/world-blocks-native-20261106/instance.
Use Prepare-NativeDepthFixture.ps1 with x{-1,0},y{65,66},z{2,-3},magenta_concrete.

JDK:C:/Program Files/Java/jdk-24; Gradle cache:minecraft/.gradle-user-home.
Bundled PowerShell7 is installed; no admin setup needed.
Branch:codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
Assets, runtimes and saves stay out of Git.

Do not replace File.Replace with File.Move(overwrite): the latter failed under
actual Windows reader contention despite a faster isolated benchmark.
A temporary native60FPS comparison did not improve camera-log visibility; the
original sys_MaxFPS=-1 was restored and verified (hud-gpu-budget-20261108-132508-*).

Separate later lifecycle follow-up: client may fall after collision detaches while
save/transport drains; server/resume checkpoint remains correct. Do not classify
terminal client-only Y drift as failed third-person walking.
