# Resume checkpoint — 8 November 2026

## Latest gameplay milestone: inventory and table crafting

WorldBlocks now supports actual vanilla 2×2 inventory crafting, placed/saved
crafting tables and server-opened 3×3 crafting through aimed right-click.
HudVanillaUiAdapter accepts the real CraftingScreen, preserves mouse routing and
movement suppression, checks handler ownership and closes through vanilla so
unused inputs return. Table use takes precedence over food, follows vanilla
sneaking rules and preserves ledger ownership/revision. Native binaries/pins
unchanged. Preserve the prior mining/drop/pickup/food path.

Automated actual-Minecraft two-launch PASS:
`runtime/evidence/gameplay-crafting-20261108-185511-4a0d8c55afe64ef6b62f1a7fd1b2c3db/verification.json`.
Three logs → twelve planks → table/four sticks → wooden pickaxe using 34 real UI
click pairs. Placement/opening, leftover return, suppression, saved table/items/
crafting statistics, reopening table and normal save all passed.

Coupled KCD2 PASS:
`runtime/evidence/gameplay-kcd-20261108-185158-2e27daa4e86a44c385f317e63dae89ae/native-crafting-verification.json`.
Real native terrain/camera, same recipe sequence, actual CraftingScreen pixels,
158 composed/reprojected frames during a 5,002ms sample inside the 11s screen
dwell, body restore and cleanup. Scripted guest inputs, no physical native mouse
or new post-composite screenshot claim. Avoid UI capture during strict leases.

Repeat scripts/Test-GameplayCrafting.ps1 for standalone+resume, or
scripts/Test-KcdCrafting.ps1 for live / -VerifyEvidenceDirectory for saved proof.
KCD2 closed normally; runtime/hud-crafting-20261108-a restored, nothing armed:
`runtime/evidence/gameplay-hud-restore-20261108-185502-f342a2d808184e869c16e79a1d916f78`.
Assemble and 328 focused block-policy checks pass. Other containers/furnaces,
enchanting and recipe-search text/modifier shortcuts remain outside this increment.

Next: continue integrated Survival gameplay (combat/death/respawn or required
host NPC interactions), preserving crafting/mining/food. KCD health/stamina bars
still need session-scoped suppression/restoration; selective widgets and
dialogue/subtitle behavior need verification before enabling. Elytra and wider
host collision also remain required. No reason to repeat manual control microtests.

## Previous milestone: dropped items and Survival pickup

WorldBlocks now renders actual tracked ItemEntity models with vanilla bob/spin
and stack copies into the shared world colour/depth layer. Collection is bounded
at 256 items within 64m/captured coverage; diagnostic metadata lists at most 32.
Production Survival mining creates the real drop; ordinary walking collects it.
No replacement entities or direct inventory grants. Preserve working food use.

Automated fractional-terrain mining/pickup/reload PASS:
`runtime/evidence/gameplay-drops-20261108-183802-bed59b1055f749559106d8404ce27d3f/verification.json`.
Server cobblestone UUID matched 5,006 colour/depth pixels. Two walking pulses
collected it; stack count 1, pickup statistic 1, pickaxe damage 1 and position all
survived reopen. Real server item recovery count 1 proves the fractional case.

Coupled KCD2 automated PASS:
`runtime/evidence/gameplay-kcd-20261108-183922-1660051bed414aacb5545059f86757a1/native-drops-verification.json`.
Actual native terrain/camera; 2,122 guest item colour/depth pixels; native world
composition/reprojection advanced 147 frames over 4,994ms within an 11s drop dwell;
one walking pulse picked up cobblestone. Pose acknowledgement, normal save,
body restoration and cleanup pass. First-person camera override was never used,
so camera_restored=false is correct when camera_override_changed=false.
Scripted guest aiming/keys, no physical native-input or new screenshot-level
post-occlusion acceptance claim. Avoid UI capture during active strict leases.

The first native attempt exposed initial drop embedding in fractional terrain.
GroundItemCollisionMixin now runs a server-only bounded recovery via Entity.move,
with exact installed-world/known-footprint and real-block obstruction checks.
It excludes only the injected slab during that move, restores collision state,
and retains the real item/stack/gravity/pickup. Older nonintersecting buried items
are not recovered. All 37 focused ownership/geometry checks and assemble pass.
Fixture gives first spawned observations at most 2 server ticks to settle.

Repeat scripts/Test-GameplayDrops.ps1; use scripts/Test-KcdDrops.ps1 for a new
native test, or -VerifyEvidenceDirectory to validate existing receipts. Native
checks require a new owned instance and one fresh WorldBlocks tools process.
All test games closed normally. Temporary bundle runtime/hud-drops-20261108-a
restored; nothing armed. Restore receipt:
`runtime/evidence/gameplay-hud-restore-20261108-184144-3bf33b9ba0184d81911c225bcdb3c1e5`.
Native binaries/pins unchanged. Source details and evidence are in PROGRESS.md.

Crafting is now implemented above; NPC combat, death/respawn and Elytra remain
required. User explicitly
reminded us that KCD health/stamina widgets still overlap Minecraft's HUD. Track
session-scoped hiding/restoration. wh_ui_ShowHud only verifies a whole-HUD toggle;
selective widget IDs or sustained leases/dialogue/subtitle/compass behavior need
verification before enabling. Do not restart manual control microtests.

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

## Previous renderer/walking native evidence

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
