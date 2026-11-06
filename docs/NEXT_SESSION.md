# Resume checkpoint — 6 November 2026

## Direction

Deliver docs/PRODUCT.md in integrated feature batches. User prioritizes progress,
automated tests and minimal manual checks. Preserve working controls and labs.
Creative flight, first-person hands and a bounded non-stone building palette now
work; do not repeat their completed acceptance sequences. Full block coverage,
third-person Steve, complete host collision, Survival/NPC combat and Elytra remain
required. The requested hovered-block wireframe now works and is verified.

## Latest milestone: connected fences/walls and actual shape walking

WorldBlocks now supports 22 dry fence/wall block IDs and 1,812 canonical connected
states. Vanilla neighbor updates determine fence arms, wall heights and posts;
the existing ownership ledger preserves those states across saves. Models,
selection outlines and collision use their actual partial geometry. Gates,
waterlogged states and other dynamic/transparent blocks remain outside this batch.

Automated actual-Minecraft connected-block placement, neighbor restoration,
model/outline pixels and save/reopen PASS, with ten PNGs:
`runtime/evidence/gameplay-connected-20261106-163159-b21f62d6c2cb471caeb7be0fcdedb051/verification.json`.
The actual-Minecraft walking fixture also PASS (13,355ms): ordinary input ascends
controller-placed bottom slabs and stair treads, inventory suppresses W while
standing on the stair, S descends to ground, and fences block walking and a normal
jump. Both client/server feet and support heights agree; no direct position,
velocity or block-state writes are used. Normal save and collision cleanup pass:
`runtime/evidence/gameplay-shape-walking-20261106-163317-1ae31f8068074029892b6de9bb052720/verification.json`.
Offline assemble, 252 block checks and 37 movement checks PASS.

Native oak-fence placement/render/outline/mining PASS via Computer Use. Selected
from Creative inventory, placed against the existing full block and mined; one
place/one break, revisions 14→15→16, original six-cell fixture wall preserved.
348,389ms active, 40/40 events acknowledged, 6,052 uploads/zero drops, normal save:
`runtime/evidence/gameplay-kcd-20261106-164555-e4a786edaca946908957c3dfad578c43/native-fence-observation.json`.
Native walls and walking over partial shapes remain unverified; standalone
walking does not establish native camera-follow behavior.

Known follow-up: place and break each needed a second automated click; two
controller rejections lack cause history. Computer Use text entry delivered zero
chat characters, so use Creative inventory for automated item selection. Earlier
native attempt ended after 167s on mouse+keyboard 100ms lease expiry (mask 3072), with
fresh frames/ACK and foreground. Specific stall unknown; not a Minecraft crash
or the previously repaired BUSY revocation. Same-process rearm did not activate;
fresh KCD succeeded. Preserve deadline guards; diagnose cause before changing.
Both clients are closed, renderer restored using bundle
`runtime/hud-connected-blocks-20261106`; receipt
`runtime/evidence/gameplay-hud-restore-20261106-165259-d72ea05e646f47a7b285a45cb719f705`.

**Next product priority:** third-person Steve/body/equipment and camera support
in the same gameplay session. Preserve completed controls, first-person hands,
connected construction and depth integration. Batch native shape walking with
broader collision acceptance when needed; do not repeat the completed inventory,
mouse, controlled occlusion or connected-block fixture sequences. Broader host
collision, full block coverage, Survival/NPC combat and Elytra remain required.

## Previous milestone: separate world layers and native scene depth

**Completed native acceptance:** the mouse is reconnected and KCD initializes it.
Controlled opaque native geometry correctly hides overlapping Minecraft blocks;
blocks in front remain visible and removing the native occluder restores the
wall. Hands/hotbar remain foreground. Automated Computer Use performed the checks;
no user input was needed after reconnecting the physical mouse.

Also fixed a live BUSY mouse-renewal race in the coordinated proxy/addon. A busy
same-mode renewal now pauses forwarding without extending its proven deadline;
fresh validation and neutral recovery are required. Busy release, transitions
and expiry still fail closed. The new behavior requires the exact rebuilt proxy
hash. Chat profile pins and build receipt are updated. Focused native tests pass.

The final 180-second native run PASS: 183,181ms active, three actual BUSY renewals
recovered, 18/18 input events acknowledged, inventory mouse clicks working before
and after recovery, 3,141 uploads/zero drops and normal save/client exit. Receipt:
`runtime/evidence/gameplay-kcd-20261106-161735-3ee10184931741c48178183b37841036/native-depth-mouse-observation.json`.
This verifies controlled opaque geometry, not every foliage/NPC/material path.
The six-cell wall was seeded into a disposable copied save by the new
`scripts/Prepare-NativeDepthFixture.ps1`; original source hashes are unchanged.
Do not use the fixture as evidence of player placement or walking.

At completion of this prior depth milestone, both game clients were closed,
the temporary native cube removed and all renderer bundles restored, most recently
`runtime/evidence/gameplay-hud-restore-20261106-162248-762efa63dc7246fa816d3632eff9d9bb`.
Current Chat proxy SHA starts `f0552e7cc1ea8f14`,
addon `a7ee1019bb43e131`; exact hashes are in the profile.

WorldBlocks now streams same-frame foreground RGBA, owned-world RGBA and raw
float depth under one GPU fence (schema3 format2). Hands/HUD remain foreground;
owned models/outlines can be compared against KCD depth. Captured-ground depth
remains the fallback. Flat profiles preserve format1. Mapping capacity is
24,883,456 bytes; logical viewport/input coordinates are unchanged.

Native reader reflects actual KCD DXIL through the game's hash-pinned DXC DLL,
resolves engine-remapped CB registers/spaces, and reads CPU-visible upload buffers
through public ReShade callbacks. Depth use requires current camera/lens/viewport
and exact GenericDepth original/backup association, behind the pinned proxy hash.
No guessed engine offsets or near/far constants. See docs/PROGRESS.md and
protocol/HUD_STREAM.md for implementation/guards.

Automated Java assemble/456 checks, native transport/reflection and real FX
compiler tests PASS. Actual Minecraft plane separation and paired model/outline/
inventory/save fixtures PASS (151022-fba9233a74bb4c4fad770063eca892a9 and
151408-6da5602ad31f4809969fd27774dc5585 under runtime/evidence).

Earlier projection-only evidence and missing-device failures are preserved in
docs/PROGRESS.md. Their empty scenes were not visible occlusion acceptance; the
final combined native receipt above supersedes that pending milestone.

## Previous milestone: captured-terrain depth

WorldBlocks now writes the immutable collision surface's finite slabs into depth
before owned models/outlines, using the same view/projection. No terrain colour,
no native binary/protocol changes. Render state restores and hands clear depth
afterwards. Sampled terrain occlusion only: objects/NPCs, unsampled ground and
full underground volume remain unsupported.

Actual-Minecraft fixture PASS first run, seven fixed-camera PNGs:
`runtime/evidence/gameplay-depth-20261106-143024-ca082235a246425b9920b905365d7ccc/verification.json`.
Near/partial/far controlled render-only boxes fully hide/partly hide/retain the
same block+outline. No stray terrain colour; hand/HUD intact; real placement,
mining and save cleanup. Offline build/181 checks and paired shape + cube/
inventory/save regressions PASS (143130-7c1c9b72f46e46229fc1d089ed760d48,
143230-3652ede30e8f4c3abad192d942d5f983).

Native automated visual/input PASS, no manual check:
`runtime/evidence/gameplay-kcd-20261106-144335-b4b5531b272a4935a9b5bf42a72a9ba2/terrain-depth-observation.json`.
Saved buried slab hidden; hands/HUD visible. Real local chat removed the old
slab, two right-click placements produced a visible double slab at (0,64,-4),
and left-held camera drag mined it. Corrected above-ground placement confirmed;
isolated top-face input, native stairs and walking over shapes remain unverified.
192s, 3,405 publications, max gap79.7135ms, 11,180 depth frames, normal save/cleanup.

First native attempt found aim-file ReplaceFile Win32 1175. Added it to the
existing bounded 100ms sharing retry without renewing timestamps; 1176/1177 stay
terminal. Host checks PASS10, combined worker PASS6 (also fixed its mock trajectory
ending before frontier tracking started). No freshness/guard changes. Another
attachment timed out while KCD was loading; wait for actual world readiness.

The subsequent milestone above implements the separate planes and native-depth
reader identified here. Initial pinned source refs and API inspection:
`runtime/evidence/terrain-depth-source-20261106/host-depth-notes.txt`.

## Latest milestone: slabs and stairs

WorldBlocks now supports 30 dry slab and 28 stair types. Vanilla placement context
handles same-cell slab merging, half/facing and stair corner updates. Placement
collision and standing support use actual shapes instead of full-cell bounds.
Owned neighbor changes persist through the existing server reconciliation.
No native protocol/binary or GroundCollision mixin change. Legacy cubes preserved.

Final paired actual-Minecraft run PASS:
`runtime/evidence/gameplay-shapes-20261106-141741-e1dac345d69a466abfab38b4408ec546/verification.json`.
Real chat/clicks: bottom slab, merge double, top slab, straight stair, outer-right
corner, remove neighbor back to straight. Client/server shape volumes and support
heights verified; 13 PNGs include raised-slab placement/mining above ground Y64.6
with a ray checked against the fixture heightfield. Exact save/reopen and
remaining mining/normal cleanup pass. Offline assemble and 181 checks pass.
This verifies collision queries, not actual walking over the shapes. Waterlogged
states, other partial blocks, transparency and dynamic behavior remain excluded.

Native visual/input check placed and saved one bottom oak slab:
`runtime/evidence/gameplay-kcd-20261106-135937-1280e71f3aff4dd190245e8e70b6a848/shapes-observation.json`.
It exposed a buried-ground case: slab top63.5 below native hit63.614/captured
ground63.689. Obstruction correctly suppressed selection. Ground placement now
lifts an otherwise buried shape one grid cell, preserving vanilla half/facing
and obstruction checks. Reject if the allowed native/sample height mismatch
would still bury it after the lift. Full-height placement is unchanged. That
initial session ended normally on focus loss, without a crash. The newer native
check above confirms corrected placement/merge/mining; stairs remain unverified.

## Latest milestone: hovered-block outline

WorldBlocks draws the actual vanilla shape using the standard black/0.4 line
layer. A read-only selection uses the same fresh admitted mining ray, server
ownership, reach and native obstruction checks. One camera/ray publication feeds
both model projection and targeting. UI/hidden HUD/third person/stale or blocked
aim suppress the border. No native binary changes.

Paired actual-Minecraft PASS (14 PNGs, saved four-type blocks and reopen/mining):
`runtime/evidence/gameplay-world-blocks-20261106-133430-88e40d3dc1904018b8fe47635874d13b/verification.json`.
Same-scene edge pixels verify hover, stale/blocked/miss suppression and return
after inventory; crosshair/hands/HUD excluded. Offline build and 117 checks pass.
Native automated visual/input PASS, no manual test:
`runtime/evidence/gameplay-kcd-20261106-133803-f26019fca51046919afbbf81a40eb7dc/outline-observation.json`.
Bricks placed on ground with visible border, inventory closed back to outline,
aimed mining succeeded. Two placements/two breaks, no remaining blocks. 121s,
2,284 outline frames, 2,143 publications, max gap 82.144ms, normal save/cleanup.
Camera drag also mines: do not use it as look-away-only proof. No new walking/
flight/host-depth claim. Preserve and move on; do not repeat acceptance.

## Latest milestone: actual Minecraft world blocks

`-WorldBlocks` implies Hands+Flight+Chat+Blocks+Movement; optional Explore. It uses
the unchanged Chat native bundle. GameplayWorldRenderer draws confirmed owned
states through vanilla BlockRenderManager with native camera origin, basis and
vertical FOV. Aim schema2 carries those together; legacy stone paths retain v1.
WorldBlocks disables the native stone mirror. Actual canonical states persist,
including log axes and item BLOCK_STATE placement components. Opaque full cubes
only: dirt, masonry, planks, logs, wool, concrete and mineral blocks. See palette.
Capacity64, Y56..80, captured terrain coverage remain. Captured terrain now has
the depth pass described above; full native scenery depth remains unfinished.

Automated paired Minecraft PASS, nine PNGs:
`runtime/evidence/gameplay-world-blocks-20261106-131410-b90d6a6eca0246ed8d1c5c426c107399/verification.json`.
Real chat items, four vanilla placements (dirt/planks/bricks/log axis=x), inventory
open/close, exact save/reopen, four breaks and normal cleanup. 117 unit checks,
9 host checks, Lua movement lifecycle, compile and script parse also passed.

Native visual/input proof, no manual testing:
`runtime/evidence/gameplay-kcd-20261106-131615-e75830f6a946424d8b4b232771114561/world-blocks-observation.json`.
Prior run fa1a258a27f748c3b0d7a75d9e7be0f9 placed dirt directly on captured ground
and bricks on top. Its first inventory produced a380ms publication gap and the
250ms guard stopped it; both blocks saved. Fixed by rendering real inventory
before publication/READY in native WorldBlocks startup (12frames/750ms minimum,
10s deadline), not by weakening freshness. Retry restored both, passed inventory
and hand transitions, then single aimed clicks broke each. 104s,1830 publications,
max publication gap78ms, normal save/cleanup. An intermediate attempt started
before KCD finished loading and timed out pre-arm; no feature failure inferred.
No walking/flight/frontier/host-depth claims from this stationary native check.

## New working milestone: actual Minecraft hands

-Hands implies Flight+Chat+Blocks+Movement, optionally Explore. Prepare, Install,
Start and Restore accept -Hands and reuse the unchanged Chat/Flight native bundle.
The normal GameRenderer/HeldItemRenderer path renders actual player skin, selected
item model and equip/swing animation. Transparent clear moved before hands; GUI
preserves their pixels. GameplayHandRenderState supplies depth, lighting and
renderer-dispatcher prerequisites skipped with WorldRenderer. Exact pinned
1.21.1 bytecode was inspected under runtime/evidence/hands-source-20261106.
Inventory/chat/third person hide hands; legacy HUD-only paths retain behavior.

Actual Minecraft fixture PASS first run:
`runtime/evidence/gameplay-hands-20261106-124151-40b756f8a9a74603aeb42bfa6702df55/verification.json`.
Seven PNGs: empty, stone, diamond sword, swing, inventory, restored sword, empty.
Real chat item commands, client/server agreement, actual hand-pass markers and
transparent image regions; 92 readbacks, zero busy skips, normal save/cleanup.
Runner scripts/Test-GameplayHands.ps1; hands-restored.png shows the full sword.
Swing is scripted through vanilla animation/packet API, not native combat proof.

Automated live KCD2 PASS:
`runtime/evidence/gameplay-kcd-20261106-124608-4bcb28a9873c418fa72fbf184702f769/hands-observation.json`.
Computer Use observed empty arm, typed /give minecomelab stone, observed held
stone over terrain, chat/inventory hiding and item restoration after E close.
282s session, 6524 actual hand passes, 1985 captured hand frames, 5010 native HUD
uploads/zero drops, 40/40 input events acknowledged. Normal save and full cleanup.
No walking/flight/frontier/native attack claims from this stationary visual check.
The native log's visual_verified=false is intentionally separate from the
explicit Computer Use observation receipt. No human testing was needed.

Offline assemble, launcher PowerShell parse and diff checks passed. Focused
independent review found no launcher/gating regression. No native rebuild needed.
Hands inherit 20 FPS capture and aspect-fit, have no host depth occlusion, and use
the saved player's skin rather than forcing Steve. Special translucent/glint item
renderers and host lighting are unverified. These are documented limitations.

## Next integrated feature

Complete native-depth visual acceptance and expand host-world collision beyond
the captured-heightfield pass; reuse real models, no per-block KCD assets. The
world/overlay transport and live projection reader are now implemented above.
Batch native checks rather than restarting a small manual acceptance loop.
Player collision with owned blocks and placement directly on captured ground
already exist. Arbitrary KCD walls/trees/objects are not captured as buildable
surfaces, and KCD NPCs do not collide with these composited blocks. Native depth
visual acceptance and third-person Steve remain unfinished.
Elytra still needs faster/3D collision admission, not just raised speed limits.

## Prior foundations — preserve, do not redo

- Sustained saves and movement, Blocks, Explore, Chat and Flight: docs/GAMEPLAY_SESSION.md.
- Flight double-Space, Space/Shift, WASD/Ctrl uses vanilla abilities; 18m feet
  ceiling above original capture origin, captured heightfield/owned stone only.
  Actual-Minecraft paired save/reopen PASS:
  gameplay-flight-20261105-202840-dbf5c73f022645229d03dd00213087c4.
  Native takeoff/ascent/hover/inventory/landing PASS:
  gameplay-kcd-20261105-203016-5755cf27bbf549a3a956968e384a247a.
- Falling checkpoint captures current server state/fall distance on cleanup.
  Reopen respects vanilla 60-tick join invulnerability. PASS:
  gameplay-flight-fall-20261105-203651-2903172718104064b8ae261d787ddf7d.
- Native typed /gamemode survival and hearts/hunger PASS:
  gameplay-kcd-20261105-201229-cf98ac724f5f4ce2a7b84e588b1f4bee.
- Explore uses additive 8x8 tiles, max64/offsets[-8,8], fixed origin, persisted
  coverage; both MC collision owners install before ACK. Paired MC PASS:
  gameplay-terrain-20261105-191017-ee2686489a414ba49e3ab306887d2b3e.
  Live capture PASS gameplay-terrain-capture-20261105-191937-77679be45b4d4619be9b208946fca580.
  Native coupled frontier crossing remains unverified.
- Console dispatch splits only between complete calls at 2000 encoded path chars,
  including flush overhead; KCD truncates longer requests.
- Native gameplay accepts one session per KCD process; bounded repeat labs differ.

## Environment / deployment

Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
JDK C:/Program Files/Java/jdk-24; offline Gradle cache minecraft/.gradle-user-home.
Both games closed; WorldBlocks native world saved with no remaining owned blocks.
The pre-fix buried slab was removed through a local Minecraft command. The new
raised/merged slab was mined normally. Slot3 contains oak slab.
Prior renderer restored:
`runtime/evidence/gameplay-hud-restore-20261106-154102-5c8f3fda52834d8799461c59f58415ce`.
Bundle runtime/hud-gameplay-native-depth-r3-20261106 is restored; do not reuse its receipt.
Use a fresh BundleDirectory after changes. Assets/runtimes/saves stay out of Git.
Exact official tools1.5.5 exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.
Native addon413696bytes SHA256:
11f132a8502adee7a8a27cb27266aa727871c7f77904070ec301f10fcb3bc9ca.
Native effect4696bytes SHA256:
54e4bbd996d25e17fdb8e654fa7d0ffdbe453000ba557c3b635a8ed64ac59c81.
Pinned config config/hud-gameplay-chat-profile-v5.json. Retail unsupported.
