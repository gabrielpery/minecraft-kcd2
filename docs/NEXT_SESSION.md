# Resume checkpoint — 5 November 2026

## Direction

Deliver docs/PRODUCT.md: Steve/hands/equipment, Minecraft Survival/combat,
general blocks, commands, Creative flight and Elytra. Prioritize integrated
features and automated checks. No manual test was requested this iteration.
Preserve bounded labs and the existing sustained profiles.

## New command milestone

`-Chat` implies Blocks+Movement and combines with `-Explore`. Prepare/Install/
Start/Restore must all use -Chat. New config hud-gameplay-chat-profile-v5.json,
addon target minecome_hud_gameplay_chat_compositor, input6/HUD3 on the SAME pinned
ReShade v5 proxy. No proxy rebuild. Native openers T/slash, text scalar kind9,
edit down/up10/11. ACK screen2 means chat but rendered HUD screen remains1.
Java uses actual owned vanilla ChatScreen: charTyped and keyPressed, not a direct
command API. Movement/mining/hotbar forwarding pauses during chat. Screen and
lease transitions drain keys; older profiles retain their allowlists.

Paired actual Minecraft PASS:
`runtime/evidence/gameplay-chat-20261105-194848-15b871e71c884ede940e105526e4f985/verification.json`.
142 text events,14 editor actions: Unicode and deletion, cancel, Survival mode,
/give stone7, invalid-command recovery, Creative and Survival again. Twenty chat
suppression ticks, then0.642m walking. Reopen retains player/world UUID, Survival,
7 stone and checkpoint; commands/walking work again. Both save/cleanup pass.
Runner scripts/Test-GameplayChat.ps1. No physical/native input claim from fixture.

Java wire185 and legacy input353 checks plus assemble pass. Native chat648 checks
and legacy gameplay/input suites pass. PS launcher parsing/bootstrap pass.
Chat is keyboard-only: no clipboard, modifier selection, IME/dead-key composition,
AltGr or chat mouse clicks. Creative flight is NOT connected merely by switching
mode; GameplayMovement.beforeTick still excludes actual flying/fall-flying.

## Console transport bug fixed

First combined Chat+Explore native run failed idle before any input:
`runtime/evidence/gameplay-kcd-20261105-195328-5cef5bd5d2cc496f9250bb9b1ecd87c7`.
Preserved parser excerpt, exact harmless length-probe requests/logs and diagnosis
show URL-encoded console requests truncate. Original failing batch bytes were
not recorded; do not invent its exact length. Probes: encoded path2110 succeeds,
2162 truncates. GameplayMovementHost now bounds encoded path+flush at2000 and
splits ONLY between complete generated calls; single oversized calls fail before
sending any batch. LastDispatch/RequestCount/MaxRequestPathLength now recorded.
No Lua/freshness relaxation. tests/gameplay_console_batch.Tests.ps1:17 PASS,
including actual production worker/runspace, four simultaneous calls, full
64-block snapshot, ordering and cleanup.

Repaired combined native run PASS:
`runtime/evidence/gameplay-kcd-20261105-200138-efb79224a520488c99a493134b2a3a50/verification.json`.
89.538s,1595 uploaded HUD frames,941 poses,764 camera views,1231 requests,
maximum encoded path1728, normal save and all movement/block/terrain cleanup.
HUD visually seen in KCD. Computer Use press_key T/slash/2 yielded zero native
events; chat-observation.json explicitly marks keyboard delivery unverified.
Public is_key_pressed cannot recover sub-frame taps because it requires down.
The final addon recovers fresh release edges for short unmodified taps between
eligible up samples; it suppresses ambiguous modifier taps and transition replay.

Final native command check PASS:
`runtime/evidence/gameplay-kcd-20261105-201229-cf98ac724f5f4ce2a7b84e588b1f4bee/chat-observation.json`.
Computer Use key taps opened slash, typed /gamemode survival, then Enter. Actual
server logged Survival; KCD visibly displayed command feedback and hearts/hunger.
All21 native events acknowledged,17 text scalars,one submit.206.458s sustained,
3737 HUD uploads/zero drops,2947 bounded console requests; normal save/all cleanup.
This proves automated native command entry, not human typing speed or flight.
Generic host_command_typing_verified remains false by design; the separate
observation receipt records the explicitly observed command proof.

## Prior working terrain milestone

-Explore requests additive8x8m captures near an uncovered edge, max64 tiles,
offsets[-8,8], stable base origin/hash/run plus separate coverage generation/digest.
Both Minecraft collision owners install and coverage.json persists before ack.
Native capture emits nine small sample batches plus header; KCD logs truncate
long lines. Never restore one81-point log line or intermediate rounded XY math.
Actual MC paired terrain PASS: gameplay-terrain-20261105-191017-ee2686489a414ba49e3ab306887d2b3e.
Live read-only capture PASS: gameplay-terrain-capture-20261105-191937-77679be45b4d4619be9b208946fca580.
Coupled physical frontier crossing still pending. General rendering remains stone
only, max64 owned blocks and Y56..80; this is not full-world collision/free flight.

## Next implementation

Creative flight with explicit vertical/collision/save handling; continue general
blocks, Steve/hands, cross-game Survival/NPC combat and Elytra. Do not retest the
already-passing manual stone/inventory sequences without a relevant change.

## Environment

Branch codex/initial-import; public github.com/gabrielpery/minecraft-kcd2.
JDK C:/Program Files/Java/jdk-24; offline Gradle cache minecraft/.gradle-user-home.
CMake/CTest under Visual Studio2022 Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin.
Exact official tools1.5.5 exe SHA256:
a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a.
Use fresh BundleDirectory for each install; old installed/restored receipts are
immutable. Native gameplay currently accepts one session per KCD process.
KCD2 is closed; previous renderer restored. Latest chat bundle
runtime/hud-gameplay-chat-20261105-taps is restored (do not reuse its receipt).
Final addon SHA256 efd6ea835b63564d72df9955be5629629b8c934d34abdb64cc412fc1488fba2a.
Restore receipt: runtime/evidence/gameplay-hud-restore-20261105-201650-35088de36730476c973e23a0c4045609.
