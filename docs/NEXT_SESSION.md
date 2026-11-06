# Resume checkpoint — 6 November 2026

## Direction

Deliver docs/PRODUCT.md in integrated feature batches. User prioritizes progress,
automated tests and minimal manual checks. Preserve working controls and labs.
Creative flight and first-person hands now work; do not repeat their completed
acceptance sequences. General block rendering, third-person Steve, complete host
collision, Minecraft Survival/NPC combat and Elytra remain required.

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

Extend real Minecraft content rendering to general placed blocks, preserving
saved block identity, shape, collision and existing aimed interactions. Inspect
current block/aim ownership before altering it. Current KCD world representation
is still stone-only (64 owned blocks, Y56..80); rendering other held items does
not expand placeable block support. First-person overlay does not solve world
camera projection/depth or third-person Steve. Reuse the existing transparent
capture/native compositor where valid; avoid creating one KCD asset per item.
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
Both games closed; hands test world saved. Prior renderer restored:
`runtime/evidence/gameplay-hud-restore-20261106-125202-73f3bd9a73ac4f9ab6e9da674a05f0da`.
Bundle runtime/hud-gameplay-hands-20261106 is restored; do not reuse its receipt.
Use a fresh BundleDirectory after changes. Assets/runtimes/saves stay out of Git.
Exact official tools1.5.5 exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.
Native addon361472bytes SHA256:
3ab80c4ea675716a4d1e8a09d143beec6b9858a5d6d8c14dcef7bb2ce9950628.
Pinned config config/hud-gameplay-chat-profile-v5.json. Retail unsupported.
