# Resume checkpoint — 8 November 2026

## Working capability

Follow PRODUCT.md. Preserve the persistent HUD/inventory/chat, walking/Creative
flight, Steve/hands, F5/mouse look, block shapes/outlines/building and camera
collision. Survival/NPC combat, Elytra, broader blocks and host collision remain
product work. Do not restart completed manual control tests.

## Current renderer increment

World colour AND depth are now reprojected to the current native camera by the
actual MineComeWorldHud.fx. Independent source-pixel quads and reciprocal-depth
MAX arbitration preserve separate surfaces; holes remain transparent. HUD/hands
stay unchanged. Exact source size 1280×720, native projection/jitter retained,
0.75m/20° bound. Strict same-UV fallback remains at 3cm.

Source camera UTC must be valid within 250ms AT CAPTURE. Image and unique current
native proof each remain within 250ms at presentation. No timestamp renewal and
no changes to input, movement or strict-fallback leases. This separation removed
the measured source-camera-age dropouts after valid capture.

Current native proof uses actual D3D12 descriptor tables/root CBVs, complete
command recordings, current present epoch/backbuffer/selected DSV. GenericDepth
DepthCopyBeforeClears must remain 0 (read only). Distinct CBV candidates reject;
identical aliases are revalidated. Stale/replayed/cross-present commands and
unknown depth writers poison proof. The exact fingerprinted depth-copy pair has
bounded source/SRV/sampler/draw checks; real auxiliary copies rescale 1707×960 to
2560×1440 and are deliberately rejected without blocking the selected DSV.
Accepted copy propagation has unit coverage, not live acceptance.

## Latest completed native evidence

runtime/evidence/gameplay-kcd-20261108-151825-4f3bbaf2222645ac9fd7366f5e11a058

- Walking PASS: six strides each view, 4.013m/3.915m, max excursion 0.808m,
  inventory suppression, first-person return and normal save/cleanup.
- Camera collision PASS: 238 back/100 front samples, zero penetration.
- Stationary depth/reprojection PASS: 186/186 over 5008ms inside 12049ms dwell.
- Walking-sequence reprojection: 354/356 (99.44%), 0 camera-age rejections;
  the two remaining rejections were perspective-basis transitions. The interval
  includes releases/inventory pauses; do not label all frames continuous motion.
- Actual guest key events through vanilla client/server and native bridge;
  no new physical-input latency or subjective foliage appearance proof.
- Previous run 13fcbb... reached 345/360 before capture/presentation lease separation.

Final build 502c21063fce305c21665a9fd9af6e2c6749ec8f84ef1e03e9ad483734d5858b,
489472 bytes, passed the final automated regression including ambiguous-binding
and reused-command guards. Bundle: runtime/hud-world-reproject-20261108-f.
KCD2 exited normally; the temporary installation was restored, nothing is armed.
Restore receipt: runtime/evidence/gameplay-hud-restore-20261108-152153-2c264f7825c9463dbe4722f88817fc7b.
Raw logs and all four verification receipts are saved with the live evidence.

## Validation and next work

Chat build and focused host-depth/copy tests pass. Actual compiled FX GPU suite
passes 440 checks (WARP pixel readback plus hardware timing); exact copy shaders
pass 45 positive/negative checks using local captures, no assets in Git.
Unloaded GPU medians 0.393/0.634ms (15%/100% occupancy); concurrent KCD/headless
medians 1.60/2.18ms, peak 2.20ms. These exclude upload/compile and are not native
whole-frame timings. Evidence: world-reprojection-gpu-20261108 and
native-reprojection-checks-20261108-1507 under runtime/evidence.

Renderer tracking currently serializes native recording callbacks and measured
native frame cadence is around 35Hz in these coupled runs. Profile that cost
before another timing rewrite; host request→aim publication remained ~71ms and
is not physical-input latency. Large turns, projection changes/disocclusions,
foliage transparency/TAA and general scenes need broader visual acceptance.
Batch any human check with the next visible gameplay milestone.

Use Test-KcdThirdPersonWalking.ps1, then preserve raw run-filtered ReShade.log as
native-depth-addon.log and kcd.log as native-movement.log. Run the saved-evidence
camera-collision, foliage-depth and world-reprojection verifiers. Their receipts
are immutable. World-reprojection PASS means nonzero actual execution; coverage
and subjective appearance remain separate. Keep KCD2 focused and avoid UI calls
during the active automated fixture. One WorldBlocks arm per fresh KCD process.

After closing KCD2 normally, restore the installed bundle BEFORE changing profile
pins. Build/stage a FRESH bundle. Original executables and retail saves untouched.
Only the exact official tools 1.5.5 executable is supported. Proxy unchanged:
f0552e7cc1ea8f1490e2953d562639843e13c478502ab40eb2c315beb1ecfeab.
JDK 24: C:/Program Files/Java/jdk-24. Existing bundled PowerShell 7, no admin needed.
Fixture source: runtime/gameplay/world-blocks-native-20261106/instance; seed eight
magenta_concrete cells at x{-1,0},y{65,66},z{2,-3} with Prepare-NativeDepthFixture.

Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
Keep runtime/evidence, saves, downloaded SDKs and game shaders outside Git.
Do not replace File.Replace with File.Move(overwrite): actual reader contention
failed that earlier optimization. Unchanged Java/Lua/host suites already passed
before this renderer batch; do not rerun unrelated tests without a new reason.
