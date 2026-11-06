# Resume checkpoint — 6 November 2026

## Direction

Deliver docs/PRODUCT.md in integrated feature batches. User prioritizes progress,
automated tests and minimal manual checks. Preserve working controls and labs.
Creative flight, first-person hands and a bounded non-stone building palette now
work; do not repeat their completed acceptance sequences. Full block coverage,
third-person Steve, complete host collision, Survival/NPC combat and Elytra remain
required. The requested hovered-block wireframe now works and is verified.

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
would still bury it after the lift. Full-height placement is unchanged. Native
merge/stair/mining acceptance remains unverified;
the session ended normally on focus loss before further input. No crash.

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
Capacity64, Y56..80, captured terrain coverage remain. No KCD scenery depth.

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

Expand host-world depth/collision as integrated feature work; reuse real models,
no per-block KCD assets. Include corrected slab selection in the next combined
native milestone, rather than restarting a small manual acceptance loop.
Player collision with owned blocks and placement directly on captured ground
already exist. Arbitrary KCD walls/trees/objects are not captured as buildable
surfaces, and KCD NPCs do not collide with these composited blocks. Native depth
occlusion and third-person Steve remain unfinished.
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
Both games closed; WorldBlocks native world saved with one bottom oak slab at
(0,63,-4), placed before the ground-height fix. It is below the sampled surface;
do not use it as acceptance of the corrected placement. Slot3 contains oak slab.
Prior renderer restored:
`runtime/evidence/gameplay-hud-restore-20261106-140812-b77922cd41144c4f91f456cade45eb51`.
Bundle runtime/hud-gameplay-shapes-20261106 is restored; do not reuse its receipt.
Use a fresh BundleDirectory after changes. Assets/runtimes/saves stay out of Git.
Exact official tools1.5.5 exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.
Native addon361472bytes SHA256:
3ab80c4ea675716a4d1e8a09d143beec6b9858a5d6d8c14dcef7bb2ce9950628.
Pinned config config/hud-gameplay-chat-profile-v5.json. Retail unsupported.
