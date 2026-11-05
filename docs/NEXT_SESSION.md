# Resume checkpoint — 5 November 2026

## Direction

Deliver docs/PRODUCT.md: Steve/hands/equipment, Minecraft Survival/combat,
general blocks, commands, Creative flight and Elytra. User prioritizes integrated
progress and automatic checks; defer manual acceptance to a larger milestone.
Preserve working bounded labs. No manual test was requested this iteration.

## Current implementation

Sustained `GameplaySession` reuses MineCome-Gameplay, with vanilla player/inventory/
mode persistence. `-Movement` attaches one saved8×8m capture. `-Blocks` adds vanilla
stone placement/mining, exact native aiming, server-confirmed persistent ledger
and native entity mirror. Ground/top/side, Survival mining/item consumption,
walking/inventory and block persistence already passed actual Minecraft checks.
Input5/HUD3 native component; inventory/world mouse events separate. See PROGRESS.

NEW `-Explore` implies Blocks+Movement and reuses the same blocks native bundle.
On-demand8×8m tile acquisition uses the existing single GameplayMovementHost loop,
not a competing HTTP worker. Directional server movement within3.25m of an unknown
edge requests its neighbor. Base origin/hash/run remain unchanged. Surface
coverage has a separate generation/digest, max64 tiles including base, tile
coordinates[-8,8], global cell coordinates[-68,67]. Stone capacity remains64,
Y56..80. Missing/steep/nonmatching terrain is a nonfatal boundary. No eviction,
object collision, full-world traversal or flight claimed.

GameplayTerrain is immutable/additive. GameplayTerrainAdmission parses off-thread;
GameplayMovement installs collision on each owning game thread, pauses controls,
updates block coverage, persists raw terrain/hash/generation, then acknowledges.
GameplayTerrainBinding reloads coverage before validating the saved position.
`minecome-terrain/coverage.json` belongs to the owned save. Use -Explore on resume
for expanded terrain; base-only mode cannot restore outside positions/blocks.

Wire: terrain-admission.json -> terrain-ack.json. Exact run/world/process/base
identity, generation+1, raw tile_json+SHA, original request UTC max5s. Only matching
durable acknowledgement grows host pose/block admission. Host rereads ack after
reading block snapshot bytes to cover a concurrent publication race.
Native terrain_session.lua samples9 rays/timer, emits nine small sequential
samples receipts then a compact captured header. KCD truncates logs around4095B;
DO NOT restore the single81-point record. Request XY uses one combined integer
offset before adding the anchor, avoiding native float intermediate rounding.
No validation tolerance was relaxed. Capture/blocks/movement all clean up
independently, with a read-only flush for asynchronous final log delimiters.

## Verified now

Paired actual Minecraft PASS:
`runtime/evidence/gameplay-terrain-20261105-191017-ee2686489a414ba49e3ab306887d2b3e/verification.json`.
Synthetic east tile admitted mid-session; both collision generations1, crossed
X4 to5.821; ground/top placement and upper break at(7,64,0);20 inventory suppression
ticks; later walking; savedX5.179 plus base. Reopen retained two-tile digest,
world/player/location/base without another admission, walked and broke base.
Zero block rejections; both saves and collision/ledger cleanup passed.

Live native capture PASS693ms:
`runtime/evidence/gameplay-terrain-capture-20261105-191937-77679be45b4d4619be9b208946fca580/verification.json`.
81 actual rays, complete batches, shared-edge validation, one admission published,
explicit stop/timers cancelled. Scripted frontier request; no native movement or
coupled Minecraft admission. New runner: scripts/Test-GameplayTerrainCapture.ps1
with a newly captured GroundPatchFile. Preserve earlier failed receipts.

Tests: Java terrain42/admission42/blocks68/movement14/world21 and assemble pass;
PS terrain9/movement9/blocks9 and combined worker6 pass; Lua movement11/blocks8/
terrain8 pass through CTest. Admission shutdown-drain and stale-pending races fixed.
Do not rerun old manual sequences or broad tests without a relevant new change.

## Next implementation

Integrate chat/vanilla command typing from KCD and Creative flight in the sustained
path, then continue general block rendering/Steve/Survival/NPC/Elytra scope.
Keep terrain capture and block ledger aligned; capped additive terrain is not
unlimited free roaming. Combined physical Explore acceptance is still pending;
batch it with the next useful gameplay milestone, not another countdown demo.

## Environment / end state

KCD was launched automatically in the pinned1.5.5 tools executable, then closed
normally through Computer Use. Minecraft paired fixtures saved/exited normally.
No renderer installation changed this iteration; prior restoration remains valid.
Native profile still accepts one session per KCD process. Old repeat labs separate.
Use a fresh BundleDirectory for any install; old installed/restored receipts are
immutable. Prepare/Install use -Blocks, Start uses -Explore. See GAMEPLAY_SESSION.

Branch codex/initial-import, public github.com/gabrielpery/minecraft-kcd2.
JDK C:/Program Files/Java/jdk-24; offline Gradle cache minecraft/.gradle-user-home.
PowerShell7 bootstrap already installed. CTest lives under Visual Studio2022
Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/ctest.exe.
Exact tools exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.