# Resume checkpoint — 8 November 2026

## Latest gameplay milestone: Survival food

Continue feature delivery, not camera microtuning. Main-hand food now works through
held right-click in the existing Blocks/Chat/Flight/Hands/WorldBlocks gameplay
profiles. Vanilla interactItem and a narrow input-cancellation redirect preserve
real eating duration, nutrition, consumption and healing. No use-key synthesis or
direct player-stat writes. Release, attack, menus, slot/item/mode or authority
changes cancel; a fresh press is needed afterward.

Automated actual-Minecraft food + food-resume PASS, no manual input:
`runtime/evidence/gameplay-food-20261108-175737-4ef70f7c300e42af90de52e819c84c7c/verification.json`.
Five interruptions passed; two bread raised hunger 11→16→20, regeneration raised
health 12→13, exact health/food/saturation/exhaustion/count survived reload. Scripted
guest/Hands-profile evidence only; native KCD eating acceptance can wait for the
next larger combined milestone. Repeat with scripts/Test-GameplayFood.ps1.
Survival mining regression also passed:
`runtime/evidence/gameplay-blocks-survival-20261108-175905-ffeeff34593640869c1ffec4abea5362/verification.json`.
All test games closed normally; KCD2 and its renderer installation were untouched.

Implementation: gameplay/GameplayFoodUse.java, GameplayBlocks food integration,
hud/GameplaySession authority hook and GameplayBlockBreakingMixin redirect.
New GameplayFoodFixture feeds a synthetic view lease before movement readiness;
do not omit this when extending standalone movement fixtures. No native rebuild
or installation is needed for this guest-side feature.

Next useful Survival work: render real dropped ItemEntity stacks in the world
layer and verify timed mining → drops → walking pickup → saved inventory, then
crafting. Preserve existing vanilla durability/mining; don't replace server drops
with direct inventory grants. NPC combat, death/respawn and Elytra remain required.

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

runtime/evidence/gameplay-kcd-20261108-174025-18808e2f96c445fd9ddfc31282ec97fa

- Walking PASS: six strides each view, 4.013m/3.915m, max excursion 0.808m,
  inventory suppression, first-person return and normal save/cleanup.
- Camera collision PASS: 297 back/99 front samples, zero penetration.
- Stationary depth/reprojection PASS: 165/165 over 5001ms inside 12041ms dwell.
- Walking-sequence reprojection: 370/372 (99.46%), 0 camera-age rejections;
  the two remaining rejections were perspective-basis transitions. The interval
  includes releases/inventory pauses; do not label all frames continuous motion.
- Actual guest key events through vanilla client/server and native bridge;
  no new physical-input latency or subjective foliage appearance proof.
- Existing renderer alignment acceptance is preserved; no repeat manual check needed.

Final build fa6093837f47869b4dabd22d36d2dfe6eb75ed7faa0a422e8aae6f59b1f6f13e,
495616 bytes, includes an allocation-free single-descriptor copy and opt-in CPU
profiling. Bundle: runtime/hud-depth-profile-20261108-c.
KCD2 exited normally; the temporary installation was restored, nothing is armed.
Restore receipt: runtime/evidence/gameplay-hud-restore-20261108-174230-a9de473677c4493488f30f63b9126240.
Raw logs and all four verification receipts are saved with the live evidence.

## Validation and next work

Native profiling is complete for this increment. Baseline 7fab3a... to optimized
7095d2... reduced sampled descriptor-copy hold time 2.879→2.286 microseconds
(20.6%); all observed copies were single-entry. Default profiling is disabled;
enable MINECOME_DEPTH_PROFILE=1 only in the diagnostic game environment. Counter
summaries and hashes are saved as depth-profile-summary.json in each live run.

GameplayMovementHost now skips the outer 10ms idle sleep only with a pending
prefetched view. No-query idle, 40ms query floor, 5ms receipt polls, outer pose/
cancellation pass and original deadlines remain intact. All 44 host worker
checks pass, with new behavioral sleep assertions; native lock/copy tests pass.
Receipts: runtime/evidence/depth-profile-native-checks-20261108/.

Final live comparison reduced HTTP→first-observed-log mean 46.66→37.38ms, but
request→aim mean stayed essentially unchanged (74.56→74.28ms, last 64 samples).
HTTP/dispatch/publication variation offset the local gain. Do not claim reduced
overall physical-input latency. Keep both bounded optimizations; do not restart
an open-ended micro-timing loop. Batch wider-turn/flight/build visual acceptance
with the next integrated gameplay milestone and continue PRODUCT.md scope.

Chat build and focused host-depth/copy tests pass. Actual compiled FX GPU suite
passes 440 checks (WARP pixel readback plus hardware timing); exact copy shaders
pass 45 positive/negative checks using local captures, no assets in Git.
Unloaded GPU medians 0.393/0.634ms (15%/100% occupancy); concurrent KCD/headless
medians 1.60/2.18ms, peak 2.20ms. These exclude upload/compile and are not native
whole-frame timings. Evidence: world-reprojection-gpu-20261108 and
native-reprojection-checks-20261108-1507 under runtime/evidence.

Renderer tracking retains complete serialized callbacks; native cadence remains
around 35Hz. Sampled draw/binding work dominates the measured tracker CPU cost;
changing its synchronization needs a separate justified design. Large turns,
projection changes/disocclusions,
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
