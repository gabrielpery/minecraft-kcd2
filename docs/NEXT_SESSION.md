# Resume checkpoint — 9 November 2026

## Current work: connected bows and confirmed arrow smoothing

Outgoing actual Minecraft primary melee → native NPC damage is already verified,
as are native visible hit reactions. Preserve the WUID attribution fix:
`player.this.id` for DealDamage, `player.id` for entity/ray APIs. Do not repeat
passive dummy reaction or Lua callback experiments.

This continuation adds owned player target-lock suppression to `-Combat`.
Official CombatDebug.TestLock identifies three player CVars; the session reads
all baselines before applying zero and restores exact owned values on stop/expiry.
Foreign values are preserved and unconfirmed cleanup refuses another session.
The host requires typed active/restored receipts. Native paired proof:
- Baseline real hostile NPC: health100→93.58099365, target lock observed.
  `runtime/evidence/combat-retaliation-20261109-092231-dbc5b712a46c49bb866e59922dc844e1/result.json`.
- Production free-aim policy: health100→78.81308746, target lock never observed,
  attacks continued; exact NPC/buff/callback/timer/CVar cleanup passed.
  `runtime/evidence/combat-retaliation-20261109-093152-cb6830f053b344efb5fdba6e6918683c/result.json`.
This proves native target-lock suppression, not the physical mouse or complete
hostile HUD experience. Native player protection remains fixture-only.

Real hostile attacks also produced zero Client.OnHit callbacks and a nil
hitReaction brain variable. These routes are closed for incoming damage; no more
passive probes. Native combat logging is promising: CombatDebug.StartLog with
LogType0 exposes exact actor GUIDs and CombatHit/SoulState/HealthValue damage.
A temporary .125s logging interval delivered five separate punches while active;
all seven prior logging settings were restored and the game exited normally.
Evidence: `runtime/evidence/combat-telemetry-stream-20261109-093151-edf1a91bfc464a4b87bfe58776aee321/cleanup.json`
and `runtime/evidence/combat-stream-watch-0ba69e97163c4ec9b8ce3e6d1e681160`.
Do not claim .125s delivery latency. Before production use, verify same-second
filename overwrite/loss, duplicate/partial-write handling, exact native actor
GUID mapping and raw damage at the immortality1HP clamp. IncomingDamageImplemented
remains false. Runtime observer scripts are ignored experiments, not a deployed
bridge. See `docs/research/KCD-COMBAT.md` for pinned sources and SDK limits.

Connected `-Combat` now enables bows. `GameplayProjectiles` gates actual vanilla
arrow ticks with native swept-segment replies through `GameplayProjectilesHost`
and the existing combat worker. UUID/shooter/weapon identity, initial native-eye
admission, endpoint continuity, actor generations, freshness and cached results
protect the separate projectile trace/impact route. Never send distant arrow
contacts through current-eye melee. Preserve vanilla charge/ammo/durability,
critical damage, embedding/pickup and nonfiring cancellation.

Coupled automatic PASS:
`runtime/evidence/gameplay-kcd-20261109-102336-74a2a3b6292f4a73bfc4a9c7f7c2b060/native-combat-verification.json`.
Actual vanilla arrow damage8 reduced native NPC health100→60; a second arrow
embedded in actual native ground after the owned NPC was removed. Its exact UUID
supplied838 isolated colour/depth pixels. Inventory suppression,0.641m walking,
advancing HUD composition/reprojection and normal save/cleanup passed. No human
attack sequence was needed. The fixture removal request now publishes atomically;
its final refinement compiled after the run. Exact scenery-UUID isolation was
also checked against the passing evidence and is now required by the runner.

Standalone actual-Minecraft synthetic contact PASS:
`runtime/evidence/gameplay-combat-20261109-100811-5b6142dbeb444767850ea2c70761bc36/verification.json`.
Native direct segments/deduplication/ground PASS:
`runtime/evidence/combat-native-20261109-100254-d5dbc257ee044dd196c2d9b2b8028e77`.
Focused Combat280, World37, projectile-host45, existing combat-host and Lua combat
checks passed; final assemble passed. Native actor ray/impact bounds include the
source-inspected vanilla0.3f projectile margin, leaving scenery and melee unchanged.
Do not regress this to raw native AABBs: the first horizontal shot grazed above
the NPC head. Aim slightly downward through the torso before a coupled check;
ordinary native mouse input established that aim for the passing run.

**Latest arrow smoothing PASS:**
`runtime/evidence/gameplay-kcd-20261109-104526-49ec8754f44c48deb5ea46253c110830/native-combat-verification.json`.
Preserve immediate next-segment publication from actual vanilla state, the urgent
projectile dispatch inside the same worker's camera-ACK wait, and render-only
confirmed-segment playback. The latter follows corners, caps lag at100ms and
resets immediately for contact/removal/respawn/discontinuities; it never changes
physics or predicts through unchecked scenery. Exact client entity generations
own playback; server snapshots are immutable.

Actual native run:8 traces,6 clear,1 actor,1 scenery, damage8/native100→60HP,
32 actual intermediate render samples,24 waiting server ticks (previously27),
inventory suppression,0.641m walking,194 further composition/reprojection frames,
normal save and cleanup. All6 clear segments prequeued.9 requests averaged135.8ms
publication→receipt:43.8ms dispatch wait +92.0ms native/log wait; maximum186ms.
This improves presentation but does not establish vanilla flight speed or human
smoothness acceptance. Any further substantial speed work must reduce native
round trips or safely batch checked paths; do not spend another iteration on
tiny interpolation tuning or repeat hitbox/manual checks.

Standalone actual Minecraft/synthetic host also passes:
`runtime/evidence/gameplay-combat-20261109-104430-ab15d62b37c145cc94b59f54d15a3712/verification.json`.
It records7 intermediate samples,3 waits across5 traces, intact damage/scenery
and cleanup. Compile +308 combat checks (28 interpolation),46 projectile-host,
existing combat-host and movement-worker checks passed. The mocked actual worker
regression returns the projectile reply in53ms during a180ms camera ACK, without
renewing deadlines or retrying. Both actual runners now require intermediate
render samples; the coupled result stores Minecraft counters alongside native
timing. Preserve immutable timestamps, ownership and duplicate protection.
Current bounds:16 active flights,64 retained records,4m segments,64m travel,10s.
Spectral/tipped bow arrows share the same base path but their special native
effects and separate live acceptance remain open; crossbows/piercing are absent.

The user also asked about TNT. After arrow smoothness, explosion work should
first destroy Minecraft-owned blocks and damage native NPCs. Arbitrary KCD2
building/terrain destruction has not been established; do not promise native
geometry destruction without inspecting actual support. Incoming native attacks
into Minecraft health remains the distinct blocker described above.

Latest earlier coupled melee proof:
`runtime/evidence/gameplay-kcd-20261108-215647-d4359c30548545cbb27c6f5ccca282ba/native-combat-verification.json`:
actual diamond-sword damage7, native100→65HP, durability, inventory suppression,
walking, advancing HUD composition/reprojection and normal cleanup. Native visual
reaction proof is `runtime/evidence/combat-reaction-20261108-221429-6f97fea063714c77a1f942e14b235b8c/visual-observation.json`.
Preserve immediate validated attack dispatch and unchanged freshness deadlines.
Windows sharing failures must not refresh stale snapshot timestamps.

Native test worlds closed normally. The latest temporary WorldBlocks installation
(`runtime/hud-projectile-smoothing-20261109`) is restored and unarmed:
`runtime/evidence/gameplay-hud-restore-20261109-104644-9fae40fc94f748d2969a7f6870cd6211`.
For a relevant coupled change, prepare/install a fresh owned WorldBlocks bundle
and run `scripts/Test-KcdCombat.ps1 -BundleDirectory $bundle -ProjectileCheck` in a fresh loaded
tools world. It starts Minecraft, owns/spawns/removes its passive NPC, fires at
the NPC and scenery, checks inventory/walking/HUD and saves normally without human input. Spawn the
short-lived path-follower only AFTER Minecraft readiness. One sustained session
per native process; verify receipts/PID rather than assuming an old installation.

## Latest gameplay milestone: death, respawn and preserved drops

Death/respawn is now implemented, superseding the earlier design-only status
below. The real DeathScreen and its enabled Respawn button use the existing HUD
pointer path. Same-UUID replacement players rebind movement, block ownership and
UI on their owning threads. Captured-ground spawn selection and separate native
death/relocation acknowledgements preserve ordinary pose speed/freshness guards.
The owned same-world loading screen closes only after acknowledged replacement,
received full chunk and matching destination; it cannot bypass a foreign world.

Actual-Minecraft two-launch PASS:
`runtime/evidence/gameplay-respawn-20261108-195728-3e5a1e52c4f743f0974f5adcd5fb77e0/verification.json`.
The fixture places a table, walks away, uses vanilla `kill @s`, observes health
zero and three dropped diamonds, clicks the actual Respawn button, verifies new
client/server players with health/food 20, and walks again. Reopen retains the
table, death statistic, player checkpoint and the same diamond UUID, count and
position. Actual death/HUD images and normal save/cleanup passed; inputs are
scripted, with no physical native-input claim.
The final rerun includes the corrected respawn world-render branch and requires
captured `world_camera` metadata, so UI-only frames cannot establish this pass.

Preserve the shutdown fix: server terrain collision remains installed through
world save and is released at SERVER_STOPPED. The session disconnects the owned
player/world before collecting final cleanup evidence. Earlier premature removal
let dropped items fall before saving. Also preserve the nine-tile prefetch:
vanilla death scatter can travel beyond the original 4m patch. Standalone admits
eight translated flat fixture tiles through the production admission/ack path;
native requires eight genuine neighbouring captures. Resume reuses saved tiles.

Final assemble passed. Focused checks passed: GroundPatch 3,726; acknowledgement
parser 171; Lua movement 42; PowerShell respawn host 13; terrain host 12.
Repeat `scripts/Test-GameplayRespawn.ps1` for
create/reload and `scripts/Test-KcdRespawn.ps1` for the connected check.
The early single-arm retry guard rejects a consumed tools process before the
60-second activation wait or launching Minecraft; use a fresh tools session.

Connected KCD2 automated PASS:
`runtime/evidence/gameplay-kcd-20261108-200330-a3cf004de7e04f23b48173bab56547f2/native-respawn-verification.json`.
Both lifecycle acknowledgements and client replacement reached epoch 1 with no
pending transition. Nine actual captured tiles reached generation 8 without
refusals. Native composition/reprojection advanced 162 frames during the 11s
death-screen dwell. Actual Respawn button, health/food 20, later walking, retained
table/drop, normal guest exit and host body restoration passed. Inputs were
scripted; no physical-input or post-composition screenshot acceptance is claimed.

Preserve native point matching: exact requested coordinates or their exact
float32 representation, not a distance tolerance. A lifecycle receipt waits for
completed interpolation (`f == 1`), exact SetWorldPos/readback and
`applied_seq == pose_seq == seq`. Fresh dead-state heartbeats renew freshness
without restarting interpolation.

KCD2 closed normally; the temporary HUD installation was restored and is unarmed:
`runtime/evidence/gameplay-hud-restore-20261108-200522-bde3690e29a64d6993e50835c2c9ac99`.
Existing furnace create/save/reopen regression also passed after the shared
shutdown change:
`runtime/evidence/gameplay-furnace-20261108-200547-d8d32b0078754b07816a9776763f4230/verification.json`.
Next concrete milestone: native NPC combat with Minecraft-authoritative damage.
Elytra and selective KCD health/stamina suppression remain required, alongside
preserving working crafting/smelting/food/mining/camera controls. Dedicated
already-dead startup, immediate autorespawn and cross-dimension travel remain
unverified. No manual microtest is needed now.

## Previous milestone: furnace smelting

WorldBlocks now supports actual furnaces, including facing/lit model states,
aimed right-click, FurnaceScreen input and vanilla fuel/recipes/output. Closing
keeps slots inside the actual FurnaceBlockEntity. Workstation use and saved
ownership tolerate lit-only changes; live entity replacement or changed facing/
type fails closed. Preserve the existing crafting, food and mining controls.

Actual-Minecraft two-launch PASS:
`runtime/evidence/gameplay-furnace-20261108-190913-834b94abeeff40838604653fe6774655/verification.json`.
First launch smelts/collects one stone, then saves second cobblestone inside
with 1,374 burn ticks and 17 cook ticks. Reopen completes/collects stone two,
leaving empty input/output and retained remaining fuel. Actual GUI clicks,
vanilla 200-tick recipe, movement suppression, images, save and cleanup passed.
Assemble and 350 block-policy checks pass. Repeat Test-GameplayFurnace.ps1;
Test-KcdFurnace.ps1 supports live execution or -VerifyEvidenceDirectory.

Connected KCD2 automated PASS:
`runtime/evidence/gameplay-kcd-20261108-191255-2832045e36df4fab887f159310a14a61/native-furnace-verification.json`.
Real native terrain/camera, both smelts/collection, closed-screen contents,
actual UI, suppression, save/body restore/cleanup passed. Composition/reprojection
advanced 134 frames over 4,997ms inside the 11s UI dwell. Scripted guest inputs,
no new physical mouse or post-composite screenshot claim. Furnace particles were
not newly verified. Avoid UI capture during active strict leases.
KCD2 closed normally; runtime/hud-furnace-20261108-a was restored, nothing armed:
`runtime/evidence/gameplay-hud-restore-20261108-191430-f362d7bb2d6e4ff0928eb8879a34d8bb`.

Next coordinated Survival work is [death/respawn](RESPAWN_PLAN.md). This is a
source-inspected implementation plan, not implemented code: real death UI,
same-UUID replacement on both game threads, safe captured spawn and acknowledged
native relocation are all needed. Do not relax ordinary pose velocity/freshness
guards. NPC combat, Elytra and selective KCD health/stamina suppression remain
required. Other containers/smokers/blast furnaces are not enabled by this increment.

## Previous milestone: inventory and table crafting

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
