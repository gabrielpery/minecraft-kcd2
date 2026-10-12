# MineCome progress — 2026-10-12

**A real Minecraft stone block is now visible in a loaded KCD2 development world.**
The user's 2026-10-11 screenshot and matching game logs verify this first live display,
alongside communication between both real games. A second user-provided screenshot
verifies the texture sharpness fix, with crisp front and side faces. Occlusion, parallax and full
coordinate calibration remain separate checks. Real Minecraft placement and breaking
have also made the stone appear and disappear in KCD2, confirmed by the user's live
observation. The final automated two-game run passes matching engine spawn,
deferred removal and cleanup acknowledgements with zero owned/pending replicas.
No retail native-engine hook is enabled.

**Current build: interactive one-cell stone controls live verified.** KCD console
commands `minecome_place`/`minecome_break` now request real Minecraft vanilla
actions through an opt-in minor1 protocol. Both real games now confirm placement
and removal after the relay log-framing fix; the user confirmed seeing the stone.
Both games stayed open during repair.
The earlier visual milestone and automatic mirroring proof remain historical;
the separate recovered-session receipts verify the new control commands.

**Current movement milestone: bounded coupled movement live verified.** Real vanilla
Minecraft walking, jumping and landing use a static, approximate patch sampled
from live KCD2 terrain. Fresh integrated-server poses now move KCD2's player;
delayed player/camera readbacks and restoration pass. KCD-focused keyboard/mouse
forwarding and full-world movement authority remain unfinished.

## Evidence matrix

| Feature | Source/build | Standalone verification | Actual game verification |
|---|---|---|---|
| KCSE adapter/version metadata | MineCome.dll Release built against actual KCSE API | DLL exports, wrong-version refusal, load/lifecycle/shutdown passed | Not loaded in retail; map/loader prerequisite missing |
| C++/Java wire codecs | C++20 and Java21 bytecode built | Protocol/coordinate tests, adversarial framing/auth/timeout/reconnect test passed | Real Fabric client connected |
| Java checks | Updated Fabric build succeeds | 3,428 protocol/socket checks,25 smoke timing checks and17 input-gate checks passed | Earlier dynamic smoke and new real console-driven client/server placement/removal verified |
| C++/Lua tests | Updated Native Release succeeds | Eight CTest suites pass across focused runs:414 protocol checks,1,017 mailbox checks, stone mapping/receipt tests,57 real-Lua lifecycle cases, legacy and interactive HTTP fixtures | Lua/HTTP engine bindings in these tests are simulated |
| Cross-language state/events | Native host and actual Java codec | Final run:55 host poses,56 guest poses,1 synthetic block event in integration.mjs | Explicitly synthetic peers for this check |
| KCD Lua/debug integration | Original manifest/script and C++WinHTTP adapter | Parser, quaternion basis, explicit FOV tests passed | Official1.5.5 game initialized module; loaded Trosky player/camera, HTTP Ping and Minecraft receipts verified |
| PowerShell debug requests | PowerShell7 helpers implemented | Direct loopback, disabled proxies/redirects, capability checks, response limits and absolute body deadline regression passed | User invoked Ping, Pose and ShowStone successfully against the loaded world |
| Two real game processes | Fabric plus official tools relay | Transport shared with tested core | User-run world test:449 KCD player/camera samples,1562 Minecraft poses,2 block events; game log confirms both event receipts |
| Minecraft player/camera | Fabric snapshots on actual client ticks | Finite fields/space validation | Unique flat world, actual player/camera/eye positions sent to host |
| Vanilla placement/breaking | Uses vanilla Creative inventory/interaction packets | Test checks both client and integrated server | Server/client stone after placement, air after break; native harness received add/remove events |
| Transient stone mirroring | Native copied mailbox, console consumer and original Lua sink built; current source loaded separately from the open package | Ordered ACKs, deferred deletion, finite bounds, missing ACK, Begin rejection recovery, failed cleanup, reconnect, harness rejection and lease cases pass | User confirmed appearance/removal from vanilla MC placement/break. Final real two-game run passes exact Begin, spawn119, deferred removal442 and cleanup ACK with zero owned/pending replicas |
| Interactive stone input | Original Lua commands, minor1 codec/mailboxes, native relay and fixed-cell Creative lab compiled; log-framing fix built and relay replaced while games stayed open | Exact request/action/result, capacity, replay, expiry, generation, cancellation, stale HTTP backlog, unterminated engine log tails and action gates pass | Real commands drive vanilla client/server stone and air, with matching KCD spawned/removed receipts; user confirmed seeing placed stone |
| Read-only ground query | Separate original Lua probe and exact-version/process/hash/HTTP-owner-gated PowerShell controller implemented |13 focused cases pass in real Lua5.2 with simulated engine bindings | One actual terrain ray returned finite hit position/normal/distance; hit height exactly matched the independent terrain elevation query. No movement or geometry streaming verified |
| Sampled-ground movement lab | Fabric1.21.1 collision mixins, bounded25-point Lua sampler and isolated lab compile; remapped JAR assembled |85 parser/coordinate/shape/sequence checks and14 real-Lua sampler cases pass | Real KCD2 supplied25 valid terrain hits; real Minecraft client/server walked1.2915m, became airborne, and landed on imported approximate slabs with literal underlying blocks remaining air. KCD2 movement not applied |
| Bounded coupled movement | Java trace assembled; PowerShell receiver/controller and game-thread Lua follower implemented |126 Java ground/trace checks,25 Lua follower cases with simulated bindings,15 final receiver cases pass; final guards also validate the historical live trace offline | Real Minecraft vanilla client/server walking, jumping and landing;22 forwarded server frames,21 delayed KCD player/camera readbacks, exact starting-position restoration and normal Minecraft exit0 |
| Lua input observer | Short leased callback wrapper preserves original callback and restores only its own handler |20 simulated-binding Lua cases pass |Final timed human check captured three real jump/press/value1 callbacks,13.5983m player displacement and view changes; watched walking/mouse callbacks were absent. Callback restored. Full input forwarding remains unfinished |
| Windows walking/mouse source | Separate read-only C++20 helper and pure Java decoder/session gate compile; Fabric JAR reassembled |598 native state/wire checks and148 Java framing/identity/lease/mouse checks pass |Actual15s OS registration/cleanup and301 neutral records pass; Java validates the exact historical recording. Physical control delivery and Minecraft application not yet verified |
| Minecraft block model/atlas | Actual BakedModel and GPU atlas exporter built | Six quads,24 vertices, atlas bounds checked | Real1024×512 atlas exported and visually inspected |
| CryEngine block asset | Original OBJ→FBX converter plus installed official RC | FBX→CGF and texture TIFF→DDS compile succeeded; pixels compared | User screenshots show Minecraft stone in KCD2 world and verify the sharpness revision |
| World position/scale/depth | Algebraic hypothesis/tests | Known basis and inverse tests | Live entity bounds span1×1×1 engine units; depth/parallax and cross-game calibration still unverified |
| Original saves protection | Backup script | 982 copied files SHA256 verified | Original saves were not opened for the tests |

## Current artifacts

- Native DLL: `build/native/kcd2/Release/MineCome.dll`.
- Fabric runtime mod: `minecraft/build/libs/minecome-fabric-0.1.0.jar`.
- Official development bridge: `build/native/kcd2/Release/minecome_tools_host.exe`.
- Actual Minecraft model: `minecraft/run/minecome-export/stone/stone.obj`, `stone.mtl`,
  `block-atlas.png`. Source is actual vanilla baked geometry, not a handmade cube.
- Compiled CryEngine model: `runtime/compiled-block/Data/objects/minecome/stone.cgf`,
  `stone.mtl`, `block-atlas.dds`, with hashed provenance and live_draw_verified=false
  for each new compilation. A separate human verification record confirms the
  latest revision's live display and sharp appearance; compilation alone never sets it.
- Actual gameplay image: `minecraft/run/screenshots/minecome-smoke-placement.png`.
- Preserved Minecraft proof: `minecraft/evidence/live-smoke-final.log`.
- Native receipt proof: `runtime/logs/minecraft-final-world-peer.log`.
  Final real Minecraft run sent901 poses and2 actual stone add/remove events to the
  explicitly simulated C++ host; this is not a loaded KCD2-world gameplay test.
- KCD game command receipts: `runtime/logs/tools-live-evidence.log` and preserved
  `runtime/logs/tools-before-map-restart.log`.
- User's actual world proof: `runtime/evidence/live-world-20261011/user-screenshot.png`
  (4480×1440, SHA256 `fb01d17104c41006439ca5193fa1ce0c3bfc2075d43d832989185da4ef7716f9`).
  That directory preserves Minecraft/relay logs, KCD command receipts, and the
  original blurred material's compilation/deployment fingerprints before revision.
  The screenshot is human-provided evidence, not an agent-controlled GPU capture.
- Sharpness proof: `runtime/evidence/sharp-stone-20261011/user-screenshot.png`
  (SHA256 `66e83cf7df3b59562652c7197ce5a6a07dec0d6c9c7eb81951eaafeae893d0b9`).
  That directory preserves compilation/deployment fingerprints and `verification.json`
  linking the user's explicit confirmation and image to the unchanged staged package.
- Machine-specific inventory/hashes: `runtime/environment.json`.
- Existing saves backup: `runtime/backups/20261011-145242/kingdomcome2` and backup.json.

Runtime assets, game logs, worlds, credentials and backups stay local and ignored.
Source docs retain reproducible commands and the evidence summary.

The official-tools `Mods/minecome` package was updated only after verifying its
existing SHA256 against our own deployment record; its prior package/manifest were
backed up. The updated package contains the original transient entity test and actual
compiled Minecraft assets. The user successfully ran `scripts/Start-Kcd2ToolsTest.ps1`
after the agent's live-world launch was rejected by automatic review. All initial test game/host processes
have closed normally or been recovered as recorded. The user's current development
world stayed open during the earlier automatic mirroring tests; owned Minecraft/relay
processes saved/exited normally. The user has since closed KCD2.

Earlier Java hardening followed the initial live gameplay test and was verified with standalone
and loopback regressions: strict UTF-8/HELLO lengths, absolute fragmented handshake
deadline, empty GOODBYE, stale host pose expiry, bounded event draining and rejection
of invalid outgoing space/role. Previous Fabric jar SHA256:
`1421924607162227f56018c2bab9161146e92915bb2c5c508b16cba8dee1a1f5`.
The user then launched the final development sources through Loom and verified
communication with the loaded KCD2 world. The fresh Minecraft log records
`VANILLA_SMOKE_PASS`, host poses received=57, and normal world saving/shutdown.

## Phase status

0. **Reconnaissance/architecture/build system: implemented.** All requested source
   projects inspected and pinned; game/tools/dependency versions discovered. Official
   native framework limitations and a working debug alternative documented.
1. **Communication: live verified through official tools.** Real Fabric mod and KCSE DLL built;
   standalone C++/Java and real loaded-world bridge pass. The retail KCSE game
   initialization test remains blocked by the missing validated address library.
2. **Read-only state: live verified.** Actual Minecraft world positions and loaded
   KCD player/camera sampled and exchanged. A local bounded Minecraft-to-KCD
   follower now passes live player/camera readback and restoration. General
   calibration, FOV/projection and sustained movement authority remain unverified.
3. **First block: visible in live KCD2.** Native asset compilation, real world loading
   and display are verified by the user's test. Material sharpness is now live verified;
   occlusion/parallax need targeted visual checks. The user performed the launch
   after automatic approval review rejected the agent's attempt.
4. **Transient stone updates: live observed.** Actual MC feed drives
   a bounded KCD stone sink via acknowledged engine-console commands. World/session
   changes clear/reauthenticate; failed removal is retained/retried. The user confirmed
   actual appearance/removal. The final live rerun passed exact Begin/spawn/removal/
   cleanup receipts after handling deferred deletion. Persistent and general blocks
   are not implemented. First console-controlled single-cell placement/breaking is
   now live verified through actual Minecraft client/server and KCD engine receipts.
5. **Initial collision/movement prototype live verified.** Real vanilla Minecraft
   uses approximate sampled ground on both game threads and briefly drives KCD2's
   player/camera. General collision streaming, KCD input and sustained authority remain.
6–7. **Not implemented.** NPC/combat, terrain deformation, HUD/hands, mobs and
   advanced features await those foundations.

## Next concrete verification

The sharper material was compiled and staged in the owned official-tools package
(SHA256 `a6ad4df11600b78ff9102f3386f58ce22a5a93a3e706b8146f9fa9e75489083e`).
All262,144 DDS pixels match the original16×16 stone pixels repeated32×32, and
all24 remapped UV corners select the same source colours/orientation. Three official
RC stages passed; the DDS is512×512/1,048,712bytes and the material470bytes.
The point-filter hint is included but may be ignored by stock Illum. The user has
verified this asset-level mitigation in a fresh live frame: crisp front and side
faces, with the explicit report "Fixed it!". The installed package matched
the hash above at that verification. Its Lua sink has since been updated; the current
package hash is in `runtime/lua-deployment.json`. Previous owned packages are preserved.

`scripts/Start-BlockMirrorTest.ps1` runs against the already-loaded fresh official
development world. Real MC creates a new UUID lab, waits for fresh KCD player/camera,
places stone, holds15 seconds after client/server confirmation, then breaks it. The
native host uses a session-local display island, with CALIBRATED still false. The
user has confirmed appearance/removal; the final ordered removal ACK retest passed.
Parallax, occlusion and distance/minification quality remain separate visual checks.
Do not use newer retail saves in this build. In parallel, obtain/generate a verified retail
Steam1.5.6 address map and add a pre-hook loader compatibility gate before enabling
native engine access. Do not call either route playable based on an asset build or
handshake alone.

## Stone mirroring continuation

Updated Fabric JAR SHA256:
`c825108bc4f6a5089d8a9f35135d9ff90c6df65d27f251d4b665e97f010ca237` (52,377bytes).
Native7/7CTest passed with the original HTTP/engine/Minecraft fixture explicitly
labelled simulated; its local evidence is `runtime/tools-stone-fixture-*/verification.json`.
Lua lifecycle tests now cover46 cases in the existing Wireshark Lua5.2 DLL without
installing anything. This DLL uses simulated engine bindings; live receipts are separate.
The owned development package was hash checked, backed up, and updated while KCD2
was closed. It retains the same sharp Minecraft CGF/MTL/DDS contents.

The new actual Minecraft dynamic smoke passed against the explicitly synthetic
native host on38773: client and integrated server confirmed stone at16:26:24,
vanilla break issued at16:26:39, and both confirmed air at16:26:41. The native host
received exactly two events17.097352seconds apart; Java queued2/sent2/dropped0.
Evidence is `minecraft/evidence/dynamic-smoke-20261011`. This validates Minecraft
and the new timing/session transport; it does not establish a live KCD sink.

## Live dynamic stone continuation

`runtime/evidence/block-mirror-20261011-165548` preserves the actual two-game run.
Fresh Minecraft UUID0d0ff987-a4f6-4fec-9a75-d7b92349239f sent add/remove sequences120/441
at(-5,-60,-4). Both client and integrated server confirmed stone at16:56:37, vanilla
break followed at16:56:52 after the15-second hold, and both confirmed air at16:56:54.
The client queued2/sent2/dropped0 and saved every dimension before exit0.

KCD accepted exact session1791734195516527 and spawned the actual stone geometry with
one-unit bounds. It reported cleanup_pending for sequence441, then ended with
owned_count0/pending_count0. The native host received747 live KCD player/camera samples,
1,820 Minecraft poses and2 block events. The user explicitly confirmed: "Yes, it
appeared and disappeared." This is human visual observation; no new KCD frame was
captured. The archived Minecraft screenshot is separate (SHA256
b440d1ff0dc8cd1426b49ecbbbc159309b07f88617972006b208a00ee5802461).

The strict test correctly remained false for ordered removal ACK, because it ended
the session on pending deletion. Lua now retains the original removal metadata and
emits removed exactly once after actual absence; the native consumer waits within
the original two-second deadline. Seven suites including46 Lua cases pass.

The real VM rounded the previous numeric session1791733572711306 to1791733520138240;
no Apply was sent after that mismatched Begin. IDs now remain canonical decimal text
across the float32 Lua boundary. The numeric-ID failure is preserved separately in
`runtime/evidence/block-mirror-20261011-164527`. The current workspace source hash and
installed open package fingerprint remain distinct in each run record.

The final run `runtime/evidence/block-mirror-20261011-170737` passed with fresh UUID
ab32daa1-3972-4454-be0e-6d010ac2fd60. Exact engine session1791734901712424 acknowledged
spawn sequence119 at MC(-4,-60,-7); removal sequence442 emitted cleanup_pending then
removed for the same session and sequence. Engine End returned ended with zero
owned/pending replicas, and the native consumer recorded the matching cleanup ACK.
Vanilla client/server confirmed stone17:08:23, break17:08:38 and air17:08:40. Minecraft
saved all dimensions and exited0. `run.json` reports VanillaSmokeVerified=true and
EngineMirroringAcknowledged=true. VisualVerified remains false for this final rerun;
the prior user's explicit visual observation is recorded only against its own run.
The relay expired normally with placed1/removed1/rejected0/cleanup_acktrue,
717 fresh KCD world/camera samples,1,803 Minecraft poses and exactly2 block events.
Only the user's existing KCD2 process remained open when that run finished; it is
closed at the current continuation.

The loaded Lua snapshot and source both hash to
`ca643cf32442336ec375131287ee73a3df12aee505cf95e0b4ea75e27d914a81`.
The helper uses a fresh read-only snapshot path with Script.LoadScript and proves
evaluation by a changed function reference plus decimal_text_v1. Actual old-path
ReloadScript left functions unchanged and is not used as reevaluation proof.
Native tools host hash:
`85099fd5066080cd5ee4f81a6334e078409139927af30635cb1ac4c1778261a9`.
The updated package is prepared locally with unchanged sharp assets (SHA256
`bd1443b067de51cd9d31423cbe505b0e5584b4af7954a7fb915633e00eb2fc95`), but the user's
open game retains its recorded older package. Stage the prepared source with the
owned staging helper only after KCD2 closes normally. Every new test helper invocation
loads and verifies the current original Lua snapshot without replacing that open pak.

## Interactive build continuation

The first interactive implementation is source-complete for a bounded one-cell lab:
Lua registers two console commands and emits exact decimal-text request IDs;
the official-tools relay forwards fresh intents; Java client ticks invoke vanilla
Creative placement/breaking in a new UUID flat save. It performs no automatic
actions and has no automatic Minecraft exit. The existing real block observer and
acknowledged Lua display sink handle resulting changes. Result1 establishes dispatch
only; separate client/integrated-server observations and KCD engine receipts are
required before a live action is considered verified.

Checks are focused on changed features: input format/negotiation,16-slot mailboxes,
ID replay, one-second expiry, stale world/session/reset, explicit cancellation,
HTTP outage backlog and vanilla action gates. A stale log backlog defect was caught
and fixed: recovery cannot make old console intentions new requests. The focused
native HTTP fixture passes and is explicitly simulated in
`runtime/tools-stone-fixture-hcBK4s/verification.json`. Default minor0 behavior and
the legacy fixture also pass. Eight native suites passed across those focused runs;
Lua57, native protocol414 and mailbox1,017 checks; Java3,428 plus25 timing and17
action-gate checks. No live game was launched for this new feature.

Current remapped Fabric JAR:72,239bytes, SHA256
`2247d13ed2df216b6214eac83193e0b968c641bd9c4667bd32bcbc90fa51e69b`.
Current native tools host SHA256:
`1a32bbfde616304ef98e3c88da5c0541d1e7fc81aa55eb9fc0b8c708c4e5b8b0`.
Current original Lua:33,634bytes, SHA256
`54167f3b6e2628e23db09ab19c970584a5c81ab65c67806e25e51bc53bee9aa6`.
Offline package `build/packages/interactive-stone-20261011/data/minecome.pak` hashes
to `5447e70ce9315668574385c75121d2e719de492bbfe90bbc4c559efdef014ac9`.
Its four entries match current source and the unchanged sharp CGF/MTL/DDS exactly.

With KCD2 closed, the owned staging helper verified the old package/manifest,
backed them up in `runtime/packages/previous-20261011-211052`, and staged the
interactive source. Installed pak SHA256:
`04d9bc27f32a91ca04ef655157989bf46b93bc4c1f4f4cb92302e783109578fc`;
manifest SHA remains `dbb73b2152507136b9c56ab7b8558feabef7c524c40009ea9247cd2d0e6cf776`.
Different archive timestamps make offline/staged pak hashes different; their
contained source/assets are checked independently. The earlier tested live snapshots
and packages retain their historical hashes above.

Use `scripts/Start-InteractiveStoneLab.ps1` after manually loading the fresh official
tools world. It verifies new Lua command registration and waits for
`INTERACTIVE_STONE_LAB_READY`. Try `minecome_place`, then `minecome_break`, in the
KCD console and close Minecraft normally. Its owned stop file requests native
cleanup and bounded shutdown. New evidence goes to `runtime/evidence/interactive-stone-*`.
The prepared `scripts/Test-BlockRelayLoss.ps1` is a separate expected-fault check
for actual engine lease expiry after stopping only its verified owned relay; live
execution remains pending. Its closed-game refusal and syntax were verified.

The requested first major objective—both real processes communicating with actual
Minecraft stone visible in KCD2—has been achieved. The recovered live session also
verifies the interactive commands. Next priorities are supported movement/camera
authority and KCD collision export. Then expand selection/blocks, inventory/HUD and world persistence before
calling a build broadly playable. NPC/combat and terrain deformation remain later
phases. A final release date is not defensible until movement and collision hooks
are demonstrated. Future checks follow changed features and milestone gates;
unchanged stone assets do not require repeated static display tests.

## Live interactive repair and verification

The user's first console test exposed actual log behavior absent from the initial
fixture: KCD commonly leaves its newest record without a final newline. The relay
kept a stale flag until its whole read buffer became empty; after a reconnect that
buffer never emptied, so healthy later intents were rejected as `stale_log_batch`.
All four original user inputs reached KCD Lua but were rejected before Java.

The relay now tracks stale provenance and first-byte age per carried line. Finishing
that old line releases its taint; independent later lines use their own batch's
age/generation. Partial old inputs and interruption backlogs still reject. The
focused fixture now uses prefix CRLF with an unterminated final record, matching
the real game. It passes fresh reconnect recovery, stale outage rejection, matching
actions/results and final cleanup. Bounded shutdown also performs a read-only
SamplePose so the final End receipt gets its next separator. Evidence:
`runtime/tools-stone-fixture-giijPd/verification.json`. Only changed behavior was
retested; the earlier eight-suite baseline remains recorded above.

The repaired host was first built separately while the old executable remained
running. The captured owned relay36964 then received its own graceful stop file;
its engine End acknowledged zero owned/pending entities. Both KCD PID54132 and
Minecraft PID42156 stayed open. The standard host was rebuilt only after the old
relay exited, and replacement relay18440 accepted the existing real Fabric client
without restarting its UUID world. Current standard native host SHA256:
`e66a839b4fb3f153281115ed9a0b74200f228263deb15d1e15326b788345cc6f`.
The separately built fixture host hashes to
`c458cdad3b9e1d8dc47e99a74d2cc81220ab82e3575b282a645b7b1abae25834`.
Both contain the same repaired source; different build paths produce different binaries.
Lua, Fabric and sharp assets were unchanged.

In the existing lab UUIDba028c54-81dd-45a9-b8f4-7a47286a2af7, request6 placed stone
at MC(0,-60,9). Real client and integrated server confirmed it at21:32:38. Native
sequence526 spawned the actual geometry in exact engine session1791750759087564
at approximately(124.57,2045.35,56.18). The user answered "Yes, I can see the stone."
Request10 broke it at21:33:31; both real Minecraft states confirmed air, and the
same engine session/sequence1514 progressed cleanup_pending→removed with zero owned
entities. Further request11 re-placed it with confirmed client/server state and
engine sequence2089. A stone was intentionally left for the user's manual controls.
Human appearance is verified; human removal observation was not separately requested.
Current session shutdown/lease-loss testing remains separate and pending.

`runtime/evidence/interactive-recovery-20261011-213123` preserves the old executable
and logs, new relay provenance, actual Minecraft/engine snapshots and verification.
A one-session owner observes only the captured Minecraft PID/path/creation time
and requests graceful relay stop through its own file when that client exits.
It never stops either game. The replacement relay itself has a30-minute deadline.
The original helper's record remains separate from this recovered live session.

## Movement milestone: first live ground-interface probe

The next playable milestone is KCD-focused input driving vanilla Minecraft walking,
jumping and collision, with KCD's player/camera following Minecraft's result.
At the time of the first probe it was not implemented. Exact1.21.1 bytecode and matching Yarn documentation
identify the vanilla input/collision paths in `docs/research/MOVEMENT.md`.
Installed KCD spawn scripts verify position and actor-view setters; their constraints
and unresolved guards are recorded in `docs/research/KCD-MOVEMENT.md`.
The pinned SkyCraft source targets a different Minecraft version and its hooks
cannot be copied directly.

`kcd2/probes/ground_probe.lua` is an original, explicitly invoked diagnostic outside
the installed mod package. It performs one8m downward ray, excludes the player,
uses only exported entity masks, checks bounded finite hit fields, and compares
`System.GetTerrainElevation`. Unknown return shapes are reported without geometry
claims. It does not move entities, install timers or reload the live stone sink.
Thirteen focused cases pass using the existing Lua5.2 library; engine functions in
those cases are simulated.

`scripts/Test-KcdGroundProbe.ps1` verifies the discovered official Steam tools
executable's exact hash/version, captures its process identity, and checks that it
owns the numeric loopback port1403 before each console dispatch. A unique immutable
source snapshot, changed function reference, fresh log offset and matching GUID
receipt distinguish actual evaluation from an HTTP200. Log capture is capped to a
fixed extent within8MiB. Its read-only preflight and actual execution passed while
both games remained open; no active binary or installed package was replaced.

At21:47:33 on2026-10-11, actual KCD PID54132 returned one `ent_terrain` hit beneath
player `(1.4335724,2005.4136963,72.3600693)`. The ray started1m above the player and
returned distance1m, normal `(0.0965667,-0.2414021,0.9656085)`, and hit Z equal to
terrain elevation72.3600693. This verifies one live ground query, not a complete
collision mesh, buildings, streaming coverage, movement authority or camera follow.
Probe SHA256:
`5eed5916204de8a5002ded81301cd02e4dc267c8aefaa1336e9b2a2f4f006829`.
Evidence: `runtime/evidence/ground-probe-20261011-214733-56fd0292a0634ca9a60b2ff2d2912fe7`
contains the source snapshot, fresh engine log, receipt and provenance.

Next implementation gate: bounded host-derived collision coverage in a separate
owned Minecraft lab, installed on both client and integrated-server threads; then
short leased input through the normal vanilla tick and measured walking/jumping.
Only after that proof should KCD position/camera authority follow the guest. General
terrain, structures, stale-coverage recovery and coordinate calibration remain work.

## Live sampled-ground movement lab — 2026-10-12

The new opt-in lab installs immutable, exact-world-scoped collision shapes on both
Minecraft game threads. It uses the inspected1.21.1 collision-shape call through
a MixinExtras0.4.1 wrapper, leaving the normal movement tick responsible for motion,
gravity, jumping and landing. The first launch exposed a mixin package error:
ordinary classes cannot share the reserved mixin package. The mixins were moved
to `dev.minecome.terrain.mixin`; the corrected actual game then initialized and
ran successfully. The failed launch created no world and its evidence is retained.

The new read-only sampler performs25 terrain-only rays in a5×5 grid, excludes the
player, and withholds every geometry result if player identity/position changes.
The controller loads a unique immutable snapshot, verifies the exact tools
executable/hash/PID and ownership of port1403, and combines only matching fresh
receipts. Complete delimited log records avoid premature parsing of a nested JSON
object from a partial write. Supplied live files must match their adjacent captured
verification, source snapshot, run token and content hashes; a provenance label
alone is insufficient. Fourteen focused real-Lua5.2 sampler cases passed, with
engine bindings simulated. The PowerShell scripts parse; their partial-record
regression and actual capture passed.

Each sampled quad becomes a0.5m-thick horizontal slab at its four corners' average
height, yielding16 slabs across4×4m. Minecraft receives the KCD basis
`(x-centerX,64+z-centerZ,-(y-centerY))`. This is an explicitly approximate heightfield,
not general terrain/structure geometry or a streaming collision service. The new
UUID save uses an empty flat Adventure world, with proxy cells confirmed as air on
both sides. Server flight validation is allowed only in that new lab because its
air-block check cannot recognize proxy support; the player's flying ability remains
false. No gameplay physics is reimplemented.

Both installations acknowledge before a single vanilla server teleport. Subsequent
ticks set only bounded held-key state, read immutable server observations, and
refuse stale coverage, expired input, menus, world changes and post-settle corrections.
Both client and server must record walking, becoming airborne, and landing with
proxy support. Query counts also include diagnostic support checks and alone do not
demonstrate movement. The previous pause-on-lost-focus option restores at shutdown.
The lab saves its new world and exits normally after40 seconds.

The first corrected run used a labelled fixture and proved only the real Minecraft
hook/path. Evidence:
`runtime/evidence/ground-movement-20261012-093200-1377d50698f7454eaa3fb68a553d06c9`.
It walked1.3339m and passed client/server airborne and landing checks, then exited0.

After the user loaded the official test world, actual KCD PID47092 produced25 valid
terrain hits around `(120.1787033,2040.6510010,56.2934151)` with stable player identity.
Capture:
`runtime/evidence/ground-patch-20261012-093530-c023b27019c74a3d920410e50e38116d`.
Probe SHA256:
`56b033ad1bc9dc1b6283ffcf1c626e3c479c4b8135dcb92dcdb0e48a1f0d6bdf`.
Captured patch SHA256:
`48a7af5b65a6de98a70cf7e96641b2dd2bdbd71f57075ab9e73fbbf24ba3514a`.

The real Minecraft lab consumed that exact patch. At09:35:56 Europe/London,
client and server both confirmed1.2914985m walking, airborne motion and landing.
Final feet were `(-0.7914985,64.1895218,0.5)` in the lab. Two initial position packets
were counted; none occurred after stable-ground handoff. The lab exited0 normally
at09:36:38. Evidence:
`runtime/evidence/ground-movement-20261012-093528-19984ff6a26a4d7a99b32e56ef32ca7c`.
KCD2 remained open and its player was never moved by this test.

The Fabric build passed85 new ground parser/transform/shape/sequence checks,
alongside the required3428 protocol,25 smoke timing and17 input-gate checks.
Following the runtime package fix, source classes ran successfully and the final
runtime JAR was reassembled:108,327bytes, SHA256
`6c2b4f9862828d40c6dc5f3cef3c2f114a91be5263b24b6871e6a2d6df64ebf4`.
The actual games ran development classes; this is not a separate packaged-JAR
installation test. Existing native binaries, installed Lua pak and stone assets
were not changed by this milestone.

At this milestone the next checks were KCD input delivery and bounded player/camera
following; the continuation below records their distinct outcomes. Stock action
names are known, but ordinary movement delivery to Lua is not yet established;
`docs/research/KCD-INPUT.md` distinguishes UI listeners from actual gameplay input.
Full terrain streaming, walls/ceilings, rebindable input, authority recovery and
retail native deployment remain outstanding. Reproduction: `kcd2/MOVEMENT-LAB.md`.

## Live coupled movement — 2026-10-12

The supported tools route now has a bounded, actual Minecraft-to-KCD follower.
`scripts/Test-CoupledMovement.ps1` authenticates the exact running tools executable,
process creation time and numeric loopback listener owner before dispatch. The
public Windows owner-PID TCP table avoids a slow per-frame network cmdlet. A unique
immutable Lua snapshot must change the expected function reference and produce
matching fresh game receipts. HTTP200 remains dispatch evidence only.

An initial capability probe verified the actual actor's userdata identity, `nil`
linked-entity contract, stationary velocity, ordinary camera and supported state
readers. A separate one-shot probe moved X by0.1m on the game thread, measured
camera following on later frames, restored the original position, and confirmed
timer cancellation. Evidence:
`runtime/evidence/movement-probe-20261012-100202-9d50f46e472c423491afe484af55aae4`.
This primitive alone was not Minecraft movement authority.

The full coupled run used KCD PID47092, started08:33:05.9483691Z, and the official
1.5.5.0 tools executable SHA256
`a32d077e6b54e5cd0c5a5f3194f473779706ff266a711e4745ccdb598843340a`.
Its immutable follower source and current source both hash to
`d946fc75e1fac243799f50d347867da0ac6b928572189b7f1c45221e9a4a7ee8`.
Fresh25-ray ground capture:
`runtime/evidence/ground-patch-20261012-103223-1b86b4835fd048e7aff977bc0ff287ad`.
Patch SHA256:
`a7e6df101f0021bba7722ca8cfa3948ea7b8aab54e91f8a089bfb48e25a16f0c`.

At10:32:51 Europe/London, actual Minecraft save
`MineCome-Ground-bceaa18e-a33e-41ea-ae3c-9821176beae7` passed client/server walking
of1.2914985m, becoming airborne and landing against that exact patch. No position
corrections occurred after the stable-ground handoff. The trace contains26 complete
records, with separate client prediction and advancing server observations.

The controller forwarded22 fresh server frames;21 delayed KCD game-frame receipts
confirmed the corresponding player positions and ordinary camera following.
Target X spanned1.2914963m. Target Z spanned1.5264473m including both jumping and
ground-height differences. Maximum camera-offset error was0.0912572m against the
probe's0.15m tolerance. These are logged engine readbacks, not a human visual test
or a claim of smooth sustained gameplay.

The game-owned follower returned the player to the captured starting position
`(120.2775345,2044.7459717,56.0587387)` after2.573s. Its later terminal receipt
confirmed actual position readback, camera-offset error0.0417432m, explicit end
and all owned timers cancelled. The owned Minecraft helper40660 exited0 after
normal lab saving/shutdown. KCD stayed open at test completion. Primary evidence:
`runtime/evidence/coupled-movement-20261012-103222-acc3d355b4264e3f8d74076c47e54d3f`
contains the source snapshot, capabilities, NDJSON trace, forwarded frames, fresh
game log, delayed receipts, independent Minecraft log and `verification.json`.

The follower enforces a400ms arrival lease, fixed8s absolute deadline, identity
and state checks, small displacement bounds and guarded restoration. Native KCD
physics remains active; unexpected state/navigation relinquishes ownership rather
than promising a general rollback. The controller sends only the latest valid
server sample, with a150ms HTTP deadline; the game independently consumes queued
values on its own thread. Lua's initial first-pose deadline is800ms. No movement
callback, action map, native input freeze, original game executable, installed
package or native binary was replaced by this milestone.

Focused verification:126 Java ground/trace checks and remapped JAR assembly pass;
25 real-Lua5.2 follower cases and20 input-observer cases pass with simulated engine
bindings. The final receiver passes15 standalone PowerShell cases. Its final
compound-observation-age and successful-end correlation guards were added after
the live run. The recorded trace passes those guards in a separate offline replay
using per-record UTC times; all22 recorded dispatches also satisfy the final300ms
observation-age bound, with maximum82.9525ms measured at HTTP completion.
`offline-replay.json` explicitly records that this is historical validation, not
a second live run. Final receiver SHA256:
`0b7d42837c2fc438adc213b3fe666f6c13641f199e9315386c1516542911376c`.

Current Fabric JAR:118,812bytes, SHA256
`cefe3f945f97a913b0bdefc65af9bb12899b78850b395468c1587bd6f4d4664a`.
The actual Minecraft run used development classes; this hash identifies the built
artifact and does not claim a separately installed packaged-JAR test.

The temporary Lua input observer expired and restored its original callback.
The60s window recorded zero whitelisted events and55 stationary position/direction
samples. The user's "done" reply came afterward; a later capability sample showed
movement, so delivery of real movement/mouse actions to Lua remains inconclusive.
Evidence:
`runtime/evidence/input-probe-20261012-100653-d3e5a984d29744d29b152481c91e81dc`.
Observer source SHA256:
`583aea483f0f5d8931c324819aa915f83b3e85cea3d08f181a140c1abdd3d92f`.
The existing game callback was delegated unchanged; no input events were injected.

The next playable gate is KCD-focused keyboard/mouse intent driving Minecraft,
with focus/menu neutralization and release/timeout recovery. Streaming collision,
structures, rotation/FOV alignment and sustained exclusive movement authority
remain separate work. This result proves a short local follower over approximate
ground, not completion of those requirements or the final build. Reproduction:
`kcd2/MOVEMENT-LAB.md` and `scripts/Test-CoupledMovement.ps1`.

## Source repository and input recheck — 2026-10-12

The project now has its own local Git repository under MineCome, with origin
`https://github.com/gabrielpery/minecraft-kcd2.git`. The existing parent workspace
and unrelated `repbase` directory are outside this source repository. Publication
excludes `runtime`, `minecraft/evidence`, build outputs, token files, downloaded
references, SDKs, game assets and saves. The normal Gradle wrapper is retained
with its embedded Apache licence and existing third-party notice. Text attributes
keep the Unix Gradle launcher executable-compatible through LF line endings;
the local Git index also records its executable bit.

The reloaded official tools process50544 acknowledged a fresh60s input observer.
Its lease expired and restored the exact callback, with zero action receipts and
76 stationary position/direction samples. The capture remains inconclusive for
physical input delivery; an empty callback log alone does not prove that gameplay
actions are unavailable to Lua. Evidence:
`runtime/evidence/input-probe-20261012-143555-490f58f86d8841968ec0471601ef810d`.
The controller now waits for the matching asynchronous installation receipt
before reporting that the observer is armed.

The initial source import was pushed as commit `98acd75` on
`codex/initial-import`. A fresh remote read confirmed the exact local commit at
both that branch and remote HEAD; the local source working tree was clean.
The private source repository contains119 files at its root. The three personal
executable examples were replaced with portable PowerShell7/Python instructions.

The user reported that the first prompt was missed, so its zero-motion recording
must not be interpreted as a failed input route. The restarted observer was
announced visibly and the user replied "done" during the requested test. Final
evidence:
`runtime/evidence/input-probe-20261012-144246-5530fe25909c46969d6a6052bd1b1c9a`.
It contains77 position/view samples, maximum player displacement13.5983179m and
maximum change in the forward unit vector1.7893179. Three callbacks reported
`action:"jump", activation:"press", value:1`; no jump release, watched movement
or watched mouse action was captured. The60s game-owned lease restored the exact
original callback and the explicit end acknowledged restoration again. The
module hash remained `583aea483f0f5d8931c324819aa915f83b3e85cea3d08f181a140c1abdd3d92f`.

This is actual partial semantic-input proof. The player and view changed during
capture, so absence of the watched walking/mouse action names is now a meaningful
observation for this callback/build. It does not prove every Lua input interface
is incapable of reading them. The original `PhysicalInputDeliveryVerified:false`
field remains conservative for complete forwarding; `analysis.json` records
the separately proved jump callback and missing movement/camera callbacks.
Next implementation needs a supported walking/mouse capture path with focus/menu
neutralization, bindings and release/timeout handling. No further repetition of
this same callback test is needed before investigating that route.

## Windows input capture layer — 2026-10-12

`tools/input_capture` now contains an original standalone Windows Raw Input
helper and pure state machine. It observes literal W/A/S/D, Space and left Shift
plus relative mouse movement in the exact target process's foreground window.
It does not replace a game callback, suppress native input, inject keys or enable
Minecraft game-thread application. The exact pinned tools executable/process gate
remains in `scripts/Test-KcdRawInputCapture.ps1`; the helper additionally pins PID,
creation FILETIME and a live process handle. No game address map or engine offsets
are used by this route.

Focus changes disarm the helper through both current-foreground checks and a
same-thread out-of-context foreground-event observer. A fresh F8 press with
controls released is required to rearm; a neutral first sample prevents inherited
held inputs from resuming. Unsupported actions, device changes and malformed or
stale packets disarm. Prior-phase queued packets are discarded without renewing
the epoch, avoiding starvation from a rapid mouse stream. Mouse movement is
bounded and consumed once; no other app metadata or typed-text stream is recorded.
F8 is a manual latch, not proof of engine gameplay/menu state, and remains visible
to KCD2. Literal mappings and mouse gain still require integration/configuration.

The writer uses a new resolved local evidence path, a1MiB/2500-record bound,
fixed20Hz sampling, bounded message batches and an independent15–120s deadline.
Termination clears controls, unregisters the two own Raw Input classes, removes
the foreground observer and closes its own resources. The wrapper only recovers
the exact helper it created; it never stops KCD2.

`ExternalInputDecoder`, `ExternalInputRecord` and `ExternalInputSessionGate` are
pure Java receiver components, with no game calls. They validate exact fields,
finite/bounded values, duplicate keys, UTF-8, process/session identity, sequence,
record age and a local monotonic lease. Invalid, stale or replayed data closes the
session with neutral controls. Focus/menu/lease reset requires a new neutral
armed sample. Fresh mouse frames accumulate until consumption within bounds,
with the earliest pending delta's expiry retained; newer frames cannot extend
old mouse intent. Malicious decimal exponents are bounded before conversion.

Final focused verification: native Release builds, its state-test executable
passes598 checks, `externalInputTest` passes148 checks, and the remapped Fabric
JAR assembles. The first Windows lifecycle attempts refused startup because
this system's registration readback omitted the requested `DEVNOTIFY` bit.
The gate now permits only that omission: exact own window and two classes remain
required, and `NOLEGACY`, interception-related flags and all other flags fail.
Removal readback must report zero registrations. This is a measured local API
result, not a documented universal normalization rule. Actual hot-unplug event
delivery is not yet physically verified. Both refused-run logs remain local.

The final15s lifecycle against KCD PID50544 passed with299 focused/disarmed
samples plus one begin and one neutral end:301 complete records,111,960bytes,
terminal elapsed15009ms. Actual stdout confirms two own registrations, foreground
observer removal, zero remaining registrations and `duration` termination;
stderr is empty. This proves OS lifecycle and neutral capture while the actual
KCD window was foreground, not real key/mouse delivery or Minecraft control.
Evidence:
`runtime/evidence/raw-input-20261012-151641-cb88db680dfe4b1d847134dcc55adde3`.
Trace SHA256:
`edefa13040dcbad77db43e9d7ae7623c69d4508a21a2eeb06554465089e9b333`.
Immutable helper SHA256:
`0433db85ed4875b25704d01f7849a890798e721a547a3b8ab01781fcd09353a4`.
Native platform-source SHA256:
`94e5b431b41a2f5dd95b5fe67a22c1e32d31ccef48bfbfef87f591d13b22bead`.

The standalone Java historical-recording checker accepted that exact301-record
file, with299 samples and zero active samples. It uses recorded UTC and a fictional
local elapsed clock; its result is labelled `HISTORICAL_INPUT_RECORDING_VALIDATED`
and does not claim a fresh live session. Current Fabric JAR:140,601bytes, SHA256
`c94b8c51c0097c38400f4da32a7e8644086f436a7b4e3f830497542cbb39d8bd`.
It has not been installed or tested as a packaged mod. The existing Lua sink,
movement follower, installed assets and game executables were not changed.

Next: complete-line file reading and game-thread input application in an owned
Minecraft lab, followed by physical input proof and engine menu/input ownership.
Sustained coupled authority must keep the existing follower guards and account for
KCD's native physics/input remaining active. No additional repetition of the old
Lua callback test is needed. Reproduction and primary API sources:
`docs/research/WINDOWS-INPUT.md` and `scripts/Test-KcdRawInputCapture.ps1`.
