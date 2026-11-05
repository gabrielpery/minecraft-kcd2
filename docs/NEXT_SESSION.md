# Resume checkpoint — 5 November 2026

## Direction

Deliver docs/PRODUCT.md in integrated feature batches. User prioritizes progress,
automated tests and no repeated F8/manual checks. Preserve existing labs. Required
remaining scope includes Steve/hands/equipment, general blocks, complete host
collision, Minecraft Survival/NPC combat, Elytra and the broader systems checklist.
Creative flight is now connected; do not redo its already-passed native sequence.

## Working Creative flight milestone

-Flight implies Chat+Blocks+Movement and can combine with -Explore. Prepare,
Install, Start and Restore accept -Flight, using the rebuilt Chat addon (input6,
HUD3, unchanged pinned ReShade v5 proxy). Vanilla double-Space toggles flight,
Space/Shift rises/descends, WASD moves and Ctrl sprints. Native input forwards
Shift/Ctrl and recovers short Space taps; a bounded Java edge queue makes vanilla
consume separate jump edges. No direct flying/allowFlying writes.

Flight remains inside captured heightfield/owned-stone collision, with feet
ceiling Minecraft Y82 (18m above original capture origin), default fly speed only.
Inventory/chat/lease loss/frontier admission release input and cancel flight
inertia. Native Lua follower accepts24m/s only with explicit Flight (walking12).
This is not complete native obstacle collision, unrestricted roaming or Elytra.

Actual Minecraft paired flight PASS:
`runtime/evidence/gameplay-flight-20261105-202840-dbf5c73f022645229d03dd00213087c4/verification.json`.
Takeoff/ascent/descent/horizontal/sprint, UI suppression, actual chat mode changes,
landing, second takeoff and save/reopen airborne. Same world/player/checkpoint
(0.502,67.619,1.602), saved vanilla abilities, later ascent/descent/landing; normal
cleanup. Runner scripts/Test-GameplayFlight.ps1. Earlier attempts stopped near the
8m fixture edge; fixed fixture by recentering with real S input, no relaxed bounds.

Automated native KCD2 PASS:
`runtime/evidence/gameplay-kcd-20261105-203016-5755cf27bbf549a3a956968e384a247a/flight-observation.json`.
Computer Use double-Space takeoff, later Space ascent, hover, E inventory open/close,
double-Space landing with HUD.1300 client/server flight ticks,2.438m maximum
altitude,15/15 native events ACKed,2130 HUD uploads/zero drops,125 native position
writes; normal save and all cleanup. No native horizontal/sprint/held-Shift,
airborne reconnect or frontier-crossing acceptance claimed by this sequence.

Review caught clean stop during a fall after mode change. Final checkpoint now
captures current actual abilities/position on the owning server cleanup task,
not a cached50ms observation; optional falling/fall_distance tags preserve fall state.
Reopen restores checkpoint position/distance, validates saved abilities and lets
vanilla land before controls attach. No ability/damage writes. Vanilla server player
constructor grants60ticks join invulnerability, so immediate Survival landing on
reopen correctly retainshealth20. Preserve this rule; don't force damage to satisfy
an incorrect test expectation. Focused actual Minecraft fall/save/reopen PASS:
`runtime/evidence/gameplay-flight-fall-20261105-203651-2903172718104064b8ae261d787ddf7d/fall-continuation-verification.json`.
Same untouched checkpointY67.274/fallDistance4.844 restored, accumulated7.539,
landed atplayerage26/health20, then saved groundcheckpoint with fullcleanup.
Original pair's incorrect damage-expectation failure is preserved; only resume
repeated. Final assemble/movement37 passed. All test games are now closed.

## Prior verified foundations

- Chat: native typed /gamemode survival, real vanilla feedback/hearts/hunger,
  normal save/cleanup. Evidence gameplay-kcd-20261105-201229-cf98ac724f5f4ce2a7b84e588b1f4bee.
  Real ChatScreen methods; keyboard-only, no clipboard/IME/dead-key/AltGr.
- Explore: additive8x8 captures, max64tiles/offsets[-8,8], fixedorigin, persisted
  coverage. Both Minecraft collision owners install before acknowledgement.
  Actual MC paired admission/build/reopen PASS gameplay-terrain-20261105-191017-ee2686489a414ba49e3ab306887d2b3e.
  Live capture PASS gameplay-terrain-capture-20261105-191937-77679be45b4d4619be9b208946fca580.
  Native coupled frontier crossing still unverified. Stone only, max64,Y56..80.
- Console dispatch splits only between complete calls at2000 encoded path chars,
  including flush overhead. Do not remove: KCD console truncates longer requests.
- Native gameplay addon accepts one session per KCD process currently; bounded
  diagnostic repeat-session behavior is separate.

## Checks / next work

Native chat/input1425 and legacy suites PASS; Java movement37,wire193,HudInput353;
Lua gameplay movement and console batching17 PASS. Final fall regression/review
passed as above. Avoid broad repeated tests without a changed concern.

Next integrated feature: general Minecraft rendering for hands/held items/Steve
and blocks, reusing real Minecraft content instead of adding one KCD asset per
item. Preserve sustained commands/flight/world ownership. Elytra remains required
but needs faster/3D collision admission; do not just raise a position/speed limit.

## Environment / deployment

Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
JDK C:/Program Files/Java/jdk-24; offline Gradle cache minecraft/.gradle-user-home.
CMake/CTest under Visual Studio2022 Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin.
Exact official tools1.5.5 exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.
KCD2 closed; previous renderer restored. Latest bundle
runtime/hud-gameplay-flight-20261105 is restored (do not reuse its receipt).
Restore receipt gameplay-hud-restore-20261105-203542-39a8a3005fc14292b98ce41f91b09092.
Final addon361472bytes SHA256:
3ab80c4ea675716a4d1e8a09d143beec6b9858a5d6d8c14dcef7bb2ce9950628.
Pinned config config/hud-gameplay-chat-profile-v5.json. Always use a fresh
BundleDirectory after source/binary changes. Assets/runtimes/saves stay out of Git.
