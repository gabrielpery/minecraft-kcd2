# MineCome progress — 2026-10-13

**A real Minecraft stone block is now visible in a loaded KCD2 development world.**
The user's 2026-10-11 screenshot and matching game logs verify this first live display,
alongside communication between both real games. A second user-provided screenshot
verifies the texture sharpness fix, with crisp front and side faces. Occlusion, parallax and full
coordinate calibration remain separate checks. Real Minecraft placement and breaking
have also made the stone appear and disappear in KCD2, confirmed by the user's live
observation. The final automated two-game run passes matching engine spawn,
deferred removal and cleanup acknowledgements with zero owned/pending replicas.
No retail native-engine hook is enabled.

**Combined HUD and stone guest: implemented, built and standalone verified.**
One owned Minecraft world now supplies genuine HUD pixels, selected inventory
items and vanilla block interactions through the existing authenticated protocol.
The fresh run `11f348f356984192a50f20d858d3ba30` passed eight UI events and six
requests: two placements, two breaks, and placement refusals for dirt selection
and an open inventory. All four changes had fresh client/server agreement; the
target ended as air, inventory stayed unchanged and Java exited normally.
The host peer was synthetic and KCD was closed. Live arming explicitly rejects
this fixture. The follow-on explicit `-StoneLive` controller now connects the same
guest to the real relay and verifies owned cleanup; its combined live check passes below.
See [combined guest evidence](research/HUD-COMPOSITOR.md#combined-hud-and-stone-guest--2026-10-13).

**Combined live controller implemented and built:** after physical F8 activation,
it sends one stone intent through KCD's existing console API, waits for both actual
Minecraft confirmation and a KCD engine spawn acknowledgement, then requests a break
after ten seconds. Exact process/session checks, an owned token, immutable deadline,
matching guest/native receipts and graceful relay cleanup are required. A fresh
standalone real-Minecraft regression passed after fixing a transient Windows file
sharing collision in the test peer.

**Combined live HUD and blocks verified:** run `a80522b281a64a238e8d66a61dee7fbe`
passes, and the user confirmed seeing both the HUD and stone appearance/removal.
The same guest's selected stone produced one client/server-confirmed place and
break; KCD acknowledged spawn, removal and zero-owned cleanup in one session.
The guest published 577 frames; KCD uploaded 559 and submitted 2,330 draws with no
upload drops. Java and relay exited normally, and the temporary 60 FPS cap restored
to -1. Focus loss ended input after 18.375 seconds, after the block cycle completed;
this is not another full 30-second test. Physical world-click actions remain unfinished.

**Current UI milestone: live Minecraft inventory mouse control inside KCD2.**
The user confirms the physical test worked. All 639 events were acknowledged,
including 635 pointer events with 20 clicks, 26 drag callbacks and 32 wheel calls.
The full 30-second activation ended on its timer, with KCD still in foreground,
fresh frames/ACKs and normal Minecraft exit 0. The hook recorded 1,535 immediate
state suppressions and matching drains, with zero drain failures. Its release
receipt still marked the final drain pending, so final native drain completion
and general host input exclusivity are not independently claimed.
The user noticed the guest window reappearing and lag during shutdown; cleanup
restored visibility before the seven-second save/exit path. The repair is now
compiled and independently reviewed: the explicit live-mouse guest stays hidden
through exit, with truthful cleanup evidence and actual Java exit verification.
Its automated checks and live hidden-window/process-exit diagnostics now pass in
the combined stone run. A separate user judgment of no-popup behavior was not requested.

**Inventory responsiveness:** mouse-enabled offscreen inventory now captures once
per rendered frame under the existing 30 FPS guest cap. A real isolated Minecraft
run completed all 43 pointer-fixture events and 11 inventory stages: successful
inventory captures averaged 32.9 ms apart (about 30 Hz), while hotbar captures kept
their existing cadence. All 692 focused Java checks and review pass. There were
no readback busy skips or fence-timeout polls; Minecraft exited normally. This is
standalone evidence, not a KCD display-rate or end-to-end latency measurement.
The next inventory session still needs to confirm perceived smoothness. The
combined stone run verifies hidden-exit diagnostics without opening inventory. See the dated evidence in
[HUD research](research/HUD-COMPOSITOR.md#inventory-capture-cadence--2026-10-13).

**Earlier keyboard milestone and accepted HUD size:** The user accepted the sizing in the earlier run
and now confirms "done, no kcd menu opened, worked" with the updated add-on.
Ten physical press/release events for 1, 2, 9, E and Escape were delivered and
acknowledged, including actual Creative inventory opening/closing. The latest
Minecraft run published 493 genuine frames and KCD uploaded 471. The hidden guest
and temporary 60 FPS host cap completed with real closed ACK, full cleanup and
restoration to the original uncapped KCD setting.

This verifies the short keyboard sequence, the reported absence of a KCD menu
during it, and live sizing. The diagnostic build records foreground loss after
15.766 seconds: KCD's window stayed valid/visible, but Explorer owned foreground;
ACK/image ages were only 19/47 ms. This is the intended focus-loss stop, and no
native gate fix is indicated. The later mouse run above now verifies the full
30-second duration; the earlier uninstrumented 10.47-second stop still has no established cause.
Minecraft saved and exited normally with code 0 in both runs.
All nine slots and server-confirmed stack swapping remain separately verified by
the standalone 31-event fixtures. Opt-in host HUD suppression is now implemented
and live setting/readback restoration passes; its combined visual result remains
unverified. General KCD input exclusivity and health integration remain unfinished.
Earlier failed runs and their evidence are preserved below.

The follow-on guest update handles vanilla drag ownership, wheel sensitivity,
and button releases across inventory closure. A separate opt-in 43-event fixture
now verifies real stack splitting, drag distribution, scrolling and held-button
close/reopen behavior, with fresh integrated-server inventory observations at all
11 stages. All events ran in the hidden, unfocused Minecraft guest. This is
standalone guest evidence. The separate physical mouse profile has now also
completed the live run summarized above.
The reviewed native first-close diagnostic build is now
installed and has supplied the live foreground-loss evidence above. See the
implementation record in [HUD research](research/HUD-COMPOSITOR.md).

A separate pinned ReShade 6.8.0 full-add-on source build now extends the existing
DirectInput hook with a 100 ms renewable inventory mouse lease. The add-on forwards
client-relative pointer positions, left/right clicks, drag and wheel events to
actual vanilla screens, and draws a cursor over the genuine Minecraft pixels.
Unknown devices/layouts, stale state or lost focus refuse or end capture. Closing
inventory releases the guest buttons before returning physical input to KCD.
The keyboard build remains separate.

The mouse profile passes five focused native/shader suites, 590 Java checks,
23 profile/rollback checks under both PowerShell 5.1 and 7, and a fresh real
43-event inventory fixture. That fixture ran with KCD closed: all 11 stages,
fresh server observations, 218 published/216 received frames and normal exit 0
passed. This is standalone evidence. The custom proxy/add-on were installed
unarmed after backing up 1,010 save/profile files and the previous renderer.
Live loading and inventory interaction now pass; general camera/input exclusivity
remains a separate qualification.
The installed configuration also skips ReShade's persistent tutorial prompt;
its brief startup/loading splash remains enabled.

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

**Current movement-input milestone: external records drive real Minecraft.** A fresh scripted
producer now passes actual client/server walking, jumping, landing, yaw/pitch changes
and terminal key release in a new isolated world. Physical KCD movement-input delivery remains
unverified. The new consumer lab has no KCD movement follower.
Explicit key bindings and a session-bound starting camera are now implemented.
The updated Minecraft lab adopted the supplied initial angles on both sides and
completed its movement/view proof; the new KCD capture path still awaits a live run.

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
| Windows walking/mouse source | Separate read-only C++20 helper and pure Java decoder/session gate compile; Fabric JAR reassembled |598 native state/wire checks and148 Java framing/identity/lease/mouse checks pass |Actual15s OS registration/cleanup and301 neutral records pass; Java validates the exact historical recording. Physical control delivery remains unverified |
| External input applied to Minecraft | Bounded daemon file reader, game-thread lab and PowerShell controller compile |266 reader checks with zero skips,148 decoder/gate and126 ground checks pass |Fresh scripted producer and synthetic flat ground drive real Minecraft client/server walking0.8571695m, jump/landing, yaw/pitch, terminal neutral controls, zero post-settle corrections and normal exit. No physical KCD input or coupled authority claim |
| Starting view and key bindings | Read-only Lua camera capture, strict Java view seed and configurable native capture built |75 Java view checks,23 simulated-engine Lua cases,125 binding checks plus598 state checks;16 PS binding and14 marker cases pass |Actual MC client/server adopted synthetic yaw45/pitch−10, walked1.0727511m, jumped/landed and applied mouse once. New KCD capture and physical remapped keys are not yet live verified |
| Minecraft block model/atlas | Actual BakedModel and GPU atlas exporter built | Six quads,24 vertices, atlas bounds checked | Real1024×512 atlas exported and visually inspected |
| CryEngine block asset | Original OBJ→FBX converter plus installed official RC | FBX→CGF and texture TIFF→DDS compile succeeded; pixels compared | User screenshots show Minecraft stone in KCD2 world and verify the sharpness revision |
| World position/scale/depth | Algebraic hypothesis/tests | Known basis and inverse tests | Live entity bounds span1×1×1 engine units; depth/parallax and cross-game calibration still unverified |
| Original saves protection | Backup script | 982 copied files SHA256 verified | Original saves were not opened for the tests |
| Static Minecraft UI composition | Actual vanilla capture and original ReShade D3D12 add-on built | 36 Java capture checks; reset and aspect-fit contracts pass | User confirmed HUD visible in KCD2; logs record all three snapshot submissions and lease expiry |
| Continuous vanilla UI transport | Java21/JNA producer, bounded Win32 channel and native receiver built | 168 Java stream checks and 146 native checks pass; existing 36 snapshot checks still pass | Fresh real Minecraft world sent 344 nontransparent frames, four vanilla UI states, pause/resumption and closed marker to standalone receiver; no KCD compositor was armed |
| Continuous KCD UI compositor | Separate exact-tools D3D12 add-on installed with aspect fit, persistent texture and fenced upload slots | Native contract/lifecycle review and checks pass | Latest live run uploaded 471 frames/submitted 1,973 draws with zero drops; earlier user-accepted HUD size preserved. KCD's duplicate HUD remains |
| Reverse HUD input and background presentation | Separate exact-identity input channel, bounded hidden/offscreen presentation and callback-based focus readiness built | Hidden fixtures pass all 31 events, nine slots, inventory open/close and server-confirmed swap | Ten physical 1/2/9/E/Escape press/release events acknowledged/applied; user confirms controls worked with no KCD menu. The later mouse run completed the full 30 seconds; general host exclusivity remains unverified |
| Render-driven inventory capture | Mouse-enabled offscreen inventory captures once per rendered frame with the existing 30 FPS cap; hotbar timer unchanged | 45 cadence checks plus 647 pointer/stream/input/cleanup checks pass; actual 43-event Minecraft fixture measured mean 32.9 ms inventory capture intervals with no PBO busy skips/timeouts | Updated inventory cadence awaits a live inventory check; the combined stone run verifies hidden-exit diagnostics and normal Java exit |
| Inventory pointer lifecycle | Single active drag button, screen-owned releases, vanilla wheel scaling and explicit live opt-in built | 45 pointer policy/state, 192 stream/receipt and 353 input checks pass; actual hidden 43-event fixture verifies splitting/drag/scroll/held-close at 11 stages | User-confirmed physical mouse interaction; 635 pointer events and actual click/drag/wheel callbacks applied |
| Combined HUD and stone guest | Existing HUD world and selection drive vanilla stone interactions; explicit live relay controller and guest profile built | Actual Minecraft passed eight UI events, six authenticated requests, two placements/two breaks with client/server agreement and two exact placement refusals; unchanged inventory, restored cell and normal exit. Live controller lifecycle/receipt tests and native relay integration pass separately | User confirmed combined HUD and stone appearance/removal. One real client/server place/break matched KCD spawn/remove/cleanup, with normal Java/relay exit and restored FPS. Physical block controls remain unfinished |
| Host inventory mouse capture | Original pinned ReShade hook, API, add-on and cursor shader built; exact bundle installed | 56 native capture/SDK adapter checks, 95 forwarding/diagnostic checks, 338 input checks and both FX compilations pass; 23 profile/rollback checks pass in PS5.1 and PS7 | Full 30-second live activation, 1,535 immediate suppressions/drains and zero drain failures; final drain completion/general exclusivity not independently verified |
| Temporary host GPU-budget comparison | Shared opt-in Lua/PowerShell helper and live controller integration reviewed | 22 simulated-engine Lua cases and 98 assertions across 11 simulated-console scenarios pass; capped standalone fixture passed | Latest combined live run passed with verified −1→60→−1 restoration through requested End before expiry and timer cancellation |
| Bounded host HUD suppression | Opt-in `-HideHostHud` in the Live input lab; documented whole-HUD CVar, engine-timer writes and independent finally restoration | 29 simulated-engine Lua cases and 397 controller checks pass, including both HUD/FPS cleanup after failure | Actual tools `wh_ui_ShowHud` readback passes 1→0→1 and timer cancellation. Combined visual scope, subtitles/dialogue behavior and health integration remain unverified |

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
have closed normally or been recovered as recorded. The user's then-loaded development
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
6–7. **UI foundation implemented; broader gameplay remains.** Static vanilla HUD
   display is live verified in KCD2. Continuous vanilla UI transport passes with
   real Minecraft and a standalone receiver; the installed streaming compositor
   now displays the HUD inside KCD2. Inventory input, hands, NPC/combat, terrain
   deformation, mobs and advanced features remain unfinished.

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

## External input applied to real Minecraft — 2026-10-12

The complete-line file reader and isolated game-thread consumer are implemented.
`scripts/Start-ExternalInputLab.ps1 -Fixture` starts a new UUID Adventure world,
waits for stable client/server grounding and reader readiness, then creates a fresh
scripted input producer. The input format tag is not source authentication:
`FixtureInput:true`, expected PID/creation identity1/1 and synthetic ground identify
this run explicitly. No KCD process is needed or moved by this mode.

The daemon reader validates the resolved evidence path before READY, requires a new
file, opens once and provides complete LF records through a copied bounded queue.
Partial EOF is neither an END nor a lease renewal. UTF-8/line/byte/record bounds,
overflow, replacement and truncation fail with neutral controls. All reader IO and
channel cleanup stay off the game thread; close signals the daemon without waiting.
The first focused run found that the installed Windows JDK's public fileKey is null.
The corrected Windows path opens through a private hard-link identity witness,
checks Files.isSameFile and removes its own link on daemon exit. Unsupported storage
fails closed. The final ownership guard never removes a link whose creation failed.

The opt-in lab applies held key bindings and ordinary vanilla look deltas on the
client thread. Sensitivity/invert follow inspected1.21.1 Mouse bytecode, including
Entity's own0.15 look factor. Toggle-sprint, smooth-camera and spyglass modes refuse.
World/player identity, Adventure mode, nonflying abilities, fresh server state,
sampled coverage, menus and post-settle corrections remain guarded. The normal
vanilla movement/collision tick owns walking and jumping after one startup teleport.
The existing ordinary Minecraft/stone modes are mutually exclusive with this lab.

Actual game evidence:
`runtime/evidence/external-input-20261012-191252-7ec0c61766434285b7a08582db61b80b`.
The new save was `MineCome-ExternalInput-d104c973-4af3-4391-836c-eaea8e0cc258`.
Both real client and integrated server walked0.8571695263m, became airborne, landed,
and agreed on final yaw94.5/pitch-1.8000002 versus initial90/0. One relative mouse
delta was consumed once. All six held controls were released after the terminal
record; the world was grounded and resting. Post-settle corrections were zero
(the two startup corrections formed the baseline). Minecraft saved and exited
normally; the owned launcher returned0 and no diagnostic identity link remained.

The fresh fixture contained90 complete records/31,417bytes. Input SHA256:
`f965a3b136ec9cf9c0313efa0038eab7a44eb48863019316daef9e7192354a5d`.
Patch SHA256:
`7dc5ff50109d0a0d0683088ea7e6eba2d3fd6bbc9538579725b76ff08c894fad`.
Lab source SHA256:
`14dc20a586725980daf78530c43a17fc6559bcb4fe735bf8884a56afacfd21c7`.
Reader source during that live run:
`734aa6a355636ddfe2b2b318eeb48c0845e6e42562de81af0d562284d1203a19`.
The subsequent witness-creation ownership guard is covered by the final focused
suite; the movement run was not repeated for that exceptional cleanup-only change.
Final reader source:
`a4d74da5f5ce8df2a85f099204383a45da34535d279674013cf6e5a4d43ecd42`.

Focused checks:148 decoder/session cases,126 ground/trace cases and266 file-reader
checks with zero skips; remapped JAR assembly succeeds. The file checks include
actual Windows hard-link cleanup while a writer remains open with no write/delete
sharing, plus replacement, truncation, UTF-8 fragmentation, bounds and symlinks.
That Windows-only test uses the tested JDK's ExtendedOpenOption; production code
uses ordinary Java file APIs. Final JAR166,148bytes, SHA256:
`85bb16a1ed19a8141e7dbc26927e65c3717b1fd467e69cc29b77ba2ba87d2ed8`.
The game run used Loom development classes; the packaged JAR is assembled, not
separately installed/live verified. No assets, saves, credentials or runtime evidence
are published to Git.

Physical KCD key/mouse delivery, explicit engine gameplay/menu state, configurable
bindings, view alignment and sustained authority remain. KCD native input/physics
stays active, so this consumer lab must remain separate from the player follower.
The non-fixture controller route captures ground and starts the existing scoped
Windows helper after readiness; its combined physical delivery still needs a human
input run. Procedure: `docs/SETUP.md#external-input-applied-to-minecraft`.

## Starting camera and configurable controls — 2026-10-12

The external-input lab now initializes Minecraft from an explicit starting camera
instead of fixed yaw90/pitch0. The new read-only `view_seed.lua` captures player
position plus camera forward/up using already-inspected Lua APIs. It preserves
raw player/id/API identity, copies vectors, checks that the player stayed within
0.1m and refuses invalid, non-unit, nonorthogonal, rolled or near-vertical views.
The player handle requirement matches the userdata observed in earlier actual
movement-capability receipts. The new module itself has not run in KCD; both games
were closed before this turn's owned Minecraft fixture.

`Capture-InputViewSeed.ps1` uses the existing exact tools process/hash/endpoint gate
and immutable unique source loading. It requires one fresh matching engine receipt
and ground-center agreement, then records patch hash, input run, target PID/start,
source provenance and capture time. Java's bounded strict parser verifies the same
identity and geometry association, converts KCD forward to Minecraft yaw/pitch,
and rechecks the60s snapshot age before the sole initial server teleport. Two stable
seconds of matching client/server angles are required before accepting controls.
Later camera motion remains ordinary Minecraft mouse handling. This is a starting
snapshot, not sustained KCD camera synchronization or input/physics ownership.

The native observer and both PowerShell entry points accept explicit six-key
bindings: forward/back/left/right/jump/sprint. Defaults are W,S,A,D,SPACE,LSHIFT;
allowed alternatives are uppercase letters, arrows, SPACE and left/right Shift/Ctrl.
Duplicate or unsupported keys reject before observation. F8 remains fixed for arming.
Configured keys drive both raw-event mapping and held-key suppression; wire records
remain semantic. KCD's own bindings/settings are not changed or automatically read.
The native helper acknowledges its selected bindings, checked by each controller.

Focused results: native Release builds;125 binding and598 state checks pass.
Java hostViewSeedTest passes75 cases and JAR assembly succeeds. The read-only Lua
probe passes23 cases in actual Lua5.2 with simulated engine bindings. PowerShell
binding validation passes16 cases;14 marker cases reject wrong/missing/duplicate
view hashes, source kinds and initial-view proof flags. Existing unrelated suites
were not rerun. The final controller marker guard was added after the live fixture;
it accepts that exact historical READY/PASS pair offline, without claiming a new run.

Actual Minecraft evidence:
`runtime/evidence/external-input-20261012-192835-1e69e789a42445fdbc12e064b93e7e15`.
Save: `MineCome-ExternalInput-98c93664-e00a-482a-a32c-d01a02eb852b`.
Both client/server initialized yaw45/pitch−10, walked1.0727510592m, jumped and landed,
then agreed on final yaw49.5/pitch−11.8 after one mouse application. All controls
were neutral at END, there were zero post-settle corrections and the owned launcher
exited0 after normal save/shutdown. The input, flat terrain and initial view were
explicit fixtures. Ninety records were received. The selected arrow/RCTRL binding
argument was recorded but not exercised by physical keys in this synthetic producer.

View file SHA256:
`1c53aa02ece04382dbd05daacff0fb7207d88d57ea4397317edba3a4d0190b9e`.
HostViewSeed source SHA256:
`153dcd19ee35c85c5be24413b71f86a294f7e6a5237fc5bb08146b4d6f79a847`.
ExternalInputLab source SHA256:
`f2223797d47b50831728340ce41c20fcfa6824e99bd0b32605ab79373d612b0c`.
Lua view source SHA256:
`e056562a837c267f7ace312096887d32376e4770c27eb6c999ebb15638c9c638`.
Native helper86,528bytes, SHA256:
`3ea4a9d81ec43eebc025df68d05320abb2933cafb99ff326dc48b6e76084aeb4`.
Fabric JAR175,548bytes, SHA256:
`1d2532cbcc0f6f2c522f14f2aa422c08364069f58f8173f20dee102f376f3872`.
Loom development classes provided the live Minecraft proof; the assembled JAR is
not separately installed/live verified. Runtime evidence, worlds and assets remain
ignored and local.

Source inspection found partial death/dialogue/save-load/calendar state getters,
but no established generic menu/cutscene getter or matching prior FreezeInput-state
getter. GameRules.IsFrozen is entity freeze, not input freeze. No native KCD input
or physics takeover was added. Physical KCD controls, live starting-camera capture,
ongoing view alignment and sustained world movement authority remain separate work.

## Physical-input readiness and focus-switch recovery — 2026-10-12

The combined lab now waits up to60s for the first sampled F8 arm before starting
its15–40s active interval (default30s). A focus loss/rearm never renews that timer.
The native optional wait and duration must sum to at most120s; the standalone
observer's default remains its original fixed duration. The lab's input105s,
world135s and global180s bounds allow this wait without changing the300ms input
lease,120s protocol session,20s producer-file creation deadline or bounded queues.
Fifteen new deadline cases join the native suite (613checks passed).

Two actual combined attempts captured fresh KCD terrain and camera and reached
matching initial Minecraft client/server views:
`runtime/evidence/external-input-20261012-194153-1748ddd8a2f74ad09d584733b248c7db`
and
`runtime/evidence/external-input-20261012-194550-e0d857bd357a4a1d8e900562bea55c12`.
Neither established physical movement delivery. The first stopped before arming
when a server observation was older than250ms; the native helper observed F8 later.
The second paused controls on that condition, then rejected a queued expired input
sample. Both failures released controls and saved/stopped the owned Minecraft
instance; only the owned input helper was terminated during controller cleanup.
KCD remained open. Failed attempts are retained rather than counted as successes.

The initial-view Lua module is now live verified on the pinned official tools
executable, PID54808, creation FILETIME134363039636611832. Its unchanged source
hash is `e056562a837c267f7ace312096887d32376e4770c27eb6c999ebb15638c9c638`.
The second view receipt is in
`runtime/evidence/input-view-20261012-194552-7414ffa6cc304421a58f85d6f7169890`.
Both sides started yaw−175.33249/pitch7.1751018, matching that captured view.

The owned Minecraft lab now calls public Mouse.unlockCursor while active to prevent
local foreground mouse motion from changing its camera. This method and Mouse.tick's
focus/cursor-lock guard were inspected in the exact cached Yarn1.21.1+build.3 merged
JAR (SHA256 `06a137a0b9597798455412349a45255ee37f351ceaa37d731096880be6c6a727`),
using javap. unlockCursor only changes cursor state and GLFW cursor mode; external
changeLookDirection still applies normally. See the primary method contract:
https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/Mouse.html#unlockCursor().

Fresh server observations remain required before applying controls. Scheduling gaps
pause input with a fresh-neutral barrier, skip proof collection, reset landing
settling and stop after2s without a fresh observation. The live consumer additionally
discards validated expired SAMPLE records, advancing only ordering/count state and
clearing all held/mouse state. They cannot renew a lease or replay motion. A new
fresh released-controls sample is required before normal input resumes. Strict
receive remains unchanged for other consumers; malformed, foreign, replayed, future,
stale BEGIN/END and over-budget records still close the live gate.

The first recovery fixture (`external-input-20261012-195039-8d5c9c276fbd4c6089733151d18b06b1`)
correctly discarded expired input but still missed movement while both renderers
were running. Observations previously depended on client requests; they now publish
an immutable sample directly from Fabric END_SERVER_TICK on the server thread, with
the same owned-world/player/proxy checks. The callback contract was inspected in the
cached fabric-lifecycle-events-v1 sources. Temporary lab settings disable window
vsync, cap rendering at60fps and reduce view/simulation distance to4/5; saved settings
restore at CLIENT_STOPPING without an options.write call. Exact cached Window and
GameOptions bytecode was inspected. Driver/swap blocking was a possible explanation
for earlier stalls, not an established engine diagnosis. An intervening fixture
`external-input-20261012-195445-32d0b91a1ba540d3955380ba1a8ecab4` exited normally before
world creation/readiness; it provides no movement proof.

Final recovery fixture passed in the actual Minecraft client/integrated server with
KCD also open:
`runtime/evidence/external-input-20261012-195840-452f657d7e4a4de6bdf3f17054bebb7b`.
The intentionally expired held-forward/mouse17,11 sample was discarded, then fresh
neutral input restored normal application. Both sides walked1.0727510592m, jumped,
landed and changed yaw45→49.5/pitch−10→−11.8. Only the one intended fresh mouse
application reached the player;91records were received, with zero post-settle
corrections or server-observation pauses. All controls were neutral at END. The
launcher exited0 and restoration was acknowledged (vsync true,120fps, distances12/12);
the local options file retained those original values. This is scripted-input proof,
not physical input proof. Focused Java decoder/session checks now pass194cases;
native state/deadline checks pass613 and Release/JAR builds succeed.

Final lab source SHA256:
`9da55e139a2e6c4f1d45b57335700c88f0e1792d05bbc24ad7b1acfd476afdd1`.
Session gate source SHA256:
`2994785325b0c8e1459b30d9b2bdb105050436d9c0bde201cb592c86d1053638`.
Native helper88,064bytes, SHA256:
`a11101b55755e82ac919ae70782bae12d62e8165e087dade38950b0ef72113c3`.
Fabric JAR177,788bytes, SHA256:
`65fecb6dabf9b3e5de93695f68f955e219c4d0979a895858441eda54f1dd0742`.
Actual game runs use Loom development classes; the packaged JAR remains assembled,
not separately installed/live verified. Assets, saves and runtime evidence stay local.

The final physical two-game check passed:
`runtime/evidence/external-input-20261012-195929-2fe9fb3d71534af7af29206cbd9d6d4e`.
The user confirmed the F8/W/Space/mouse actions. Fresh exact-process checks targeted
the restarted tools PID3004/creation FILETIME134363050534931108, not the earlier
PID54808. Captured KCD ground and camera seeded the new Minecraft world. Both client
and server walked0.4261759414m, jumped and landed, and changed yaw−170.09227→−143.39227
and pitch0→−49.800007. There were zero post-settle corrections and zero server
observation pauses. Fifteen expired samples were discarded without aborting or
replaying controls; this is functional forwarding proof, not a low-latency guarantee.

The immutable native helper produced1173records over58,607ms. Its first arm arrived
at28,600ms, followed by the complete30s active interval. There were121armed samples,
including6forward,5jump and38nonzero mouse samples; the real consumer reported
25mouse applications. All controls were neutral at END. Native registration removal
and foreground-observer unhook both passed, Minecraft restored settings and exited
normally, and the controller returned0. KCD was neither repositioned nor stopped.

The source-independent Java marker remains conservatively
`physicalInputVerified=false`; `physical-analysis.json` separately records the
human-confirmed actions plus owned native executable, process/run identity and real
client/server receipts that establish physical forwarding for this session. No source
tag alone is treated as physical authentication. Input SHA256:
`c1f31be2e136ba3eb4d42cf51c221966c10f0e236bd4726830db185574dcd350`.
View SHA256:
`e400a8660cf6892917e63633a1f85ab4fd63aa80f6f90d338d9789f088a5e4fb`.
Patch SHA256:
`110c039bc4aba0b89527be87cd9007daae00470df058bbb7627747dec54c94db`.
Sustained camera/input ownership, generic engine menu state, streaming collision and
combining the input consumer with the KCD follower remain unfinished. No unverified
native hook, KCD input suppression or physics takeover was introduced.

## External-input pose export and live control capabilities — 2026-10-12

The external-input lab now exports immutable client/server position, velocity,
grounding and yaw/pitch at up to10Hz. A bounded daemon writes a new NDJSON file;
Minecraft's game threads perform no output file operations. Samples require an
advancing server sequence and observed age at most250ms. The stream reserves its
terminal slot within512records/1MiB. A final fresh server sample and completed
flush/close are required before the lab reports success, within its existing4s
terminal deadline. Review caught and fixed a failure/completion read race.

Every record binds input run/process, patch/view hashes and the isolated world,
and explicitly remains audit-only/follower-ineligible. Coordinates are projected
in patch space, with the initial Minecraft baseline recorded separately. The input
dispatch watermark is not a server acknowledgement. This adds the position/view
output needed by a future coupled controller without changing the working follower.

The automatic actual-Minecraft run passed in
`runtime/evidence/external-input-20261012-202526-c1b240aa3bb340a687c2315fa97bd862`.
Client and integrated server both walked0.8571695116m, jumped, landed and changed
yaw45→49.5/pitch−10→−11.8. The deliberately expired input was discarded; one fresh
mouse application, zero post-settle corrections and terminal neutral input were
confirmed. Minecraft restored its prior settings and exited normally; KCD PID3004
remained running. This run uses synthetic input and ground, not new physical-input
proof. The earlier human-confirmed physical result remains valid for that version.

The new export contains59records/57server samples,76,136bytes, with a passed end
and matching final server sequence. Its source identity, framing, finite values,
coordinate/view projection and terminal fields also pass the final offline validator.
Recording SHA256: `23595374ed119fe6c66cdb1681d5491f00481fd0be9dbe610193c84876833209`.
Focused checks pass:1092 Java writer assertions,16 PowerShell validator cases and
21 Lua control-probe cases. The Fabric JAR assembles to192,880bytes, SHA256
`d92f87b76b4786ec68b0dd3e93bb2bc1efe1ad06d93751b2ae70e4707dff243c`.
The live run used Loom development classes; this packaged JAR was not separately
installed. `implementation-verification.json` records the final source/build hashes.

A separate read-only live probe passed against the pinned official tools executable:
`runtime/evidence/control-capabilities-20261012-201510-c8e580acb2e642e4b2caa6cb79bcf04d`.
It confirmed `ActionMapManager.EnableActionFilter` is absent, although its state
reader exists. `g_gameRules.game.FreezeInput` and `player.EnablePhysics` exist;
global `GameRules` and bound `IsFrozen` are absent. Nine partial state getters
returned actual booleans with stable actor/function identity. No mutation was
requested. Prior input/physics state and reliable restoration remain unproved, so
the physical-input consumer and KCD follower are still separate. See
[KCD input research](research/KCD-INPUT.md#live-control-capability-inspection--2026-10-12).

## Vanilla HUD/inventory renderer capture — 2026-10-12

The UI path now follows the inspected SkyCraft/EldenCraft renderer architecture:
normal vanilla rendering supplies captured UI pixels; an original ReShade D3D12
add-on supplies host composition. No separate desktop window or redrawn inventory
is used. The source pins and exact capture/render contracts are in
[HUD compositor research](research/HUD-COMPOSITOR.md).

The first automatic capture exposed a startup ordering issue: suppressing world
rendering before the terrain screen completed caused its 30-second fallback. The
fix lets normal terrain loading finish before the owned capture mode starts.
The corrected actual-Minecraft run passed, with normal process shutdown, in
`runtime/evidence/hud-export-20261012-204553-727d31c1b69241b6b8226bd0bb120df6`.
Its fresh save was `MineCome-Hud-987997db-0e12-44ae-a595-2126bb1a25c4` and run token
`efc51913f05740b7aacc9df2dabedfec`. All three 854×480 frames were rendered through
Minecraft 1.21.1's normal GUI path and copied using asynchronous OpenGL readback.

Actual client and integrated-server inventories agreed on nine item IDs/counts.
Frame 1 selected slot 0; frame 2 selected slot 1; frame 3 opened the actual
`CreativeInventoryScreen`. PNGs were visually inspected: crisp vanilla item icons,
counts, selection, chat/advancement toasts and Creative inventory were present.
Hotbar frames retained over 275,000 fully transparent pixels each; inventory retained
its normal translucent full-screen dimming. This is Creative UI proof, not a
Survival health/hunger or crafting-interaction proof.

Raw RGBA SHA256 values:

- Frame 1: `ab78df38db3b6901788f878e147ba0ed7ed509bf0aaa57702b368afc832dd2b9`.
- Frame 2: `ff3c4138f77a9ab985f10b94ed2aea544b3ae406535dd0e997f65ae6b1b85d35`.
- Frame 3: `302485c1c9fefeeb92db394516740f764d9e4ad5b7da902f65ef60e2fed54234`.

The final guest source assembles and passes 36 focused pixel/output checks. The
live run used Loom development classes; the assembled mod was not separately
installed. Existing movement/input/stone components were not changed.

KCD composition was unverified at this capture stage; the later live preview below
records the user's first visible HUD confirmation. Three captured snapshots cycle
only for the initial renderer proof. Continuous transport, physical inventory
controls, menu arbitration and sustained gameplay are subsequent implementation.

### Native compositor build and startup investigation

The original D3D12 ReShade add-on and FX now build. Final focused validation passes
117 native contract/lifecycle checks and all four DXBC shader entries at two
resolutions. The final add-on SHA256 is
`a9bb60999fb526df64b3c61975431aed7c0b85728dc21a30db91b41bfccea484`.
Final source review fixed reset cleanup using effect handles after ReShade had
destroyed them, and made the unarmed render path return before shader access.
The tests exercise invalidated handles, reset/reinitialization, repeated cleanup
and owned-resource release. This is offline validation, not a live crash fix.

The official ReShade 6.8.0 add-on runtime was hash-checked and extracted without
running its installer. The six-file private bundle was installed with KCD closed;
no original game executable or base asset was overwritten. Installation and the
rollback helper support Windows PowerShell 5.1. No preview arm file was created.
The first user-started process (PID 48224) registered the unarmed add-on, created a
2560×1440 SDR D3D12 runtime and compiled the actual HUD effect before crashing
during loading. There was no owned texture upload or submitted Minecraft frame.
Logs and the rollback record are preserved in
`runtime/evidence/hud-startup-crash-20261012-205804`.

After normal process exit, only the owned, pinned DXGI proxy was renamed to
`dxgi.dll.minecome-disabled`; the add-on, configuration and logs were retained.
The user then reported another loading crash with the hook disabled. Fresh game
logs in `runtime/evidence/loading-crash-hook-disabled-20261012-210223` end at the
same MFX collisions-loading line, and ReShade's log did not update. No corresponding
Application crash event, exception stack or process exit code was available.
The cause remains unproven. At this stage the fixed source bundle was staged in
`runtime/hud-compositor-resetfix`; the later deployment and preview are recorded below.

The new manual `Start-Kcd2ToolsDiagnostic.ps1` records the missing process exit code,
sampled modules and memory during a bounded 120-second launch. Windows PowerShell
5.1 parsing, read-only exact-executable/hook preflight and the public Windows memory
query pass. No game was started by those checks. A fresh user-run diagnostic is
now preserved in
`runtime/evidence/tools-startup-diagnostic-20261012-201214-1b3de6fc259a4282a316450302d68141`.
The user confirmed the same loading failure. PID 49532 exited after 28.462 seconds
with code 250 (`0x000000FA`). All six complete module snapshots omitted ReShade and
the MineCome add-on; CryRenderD3D12 was observed. Across 28 samples, peak game private
memory was 3,823,595,520 bytes and minimum available system commit was 5,373,673,472
bytes. There were no memory/module sampling errors. These results do not identify
the cause or establish continuous module absence between samples. The existing
launcher and working movement/stone code are unchanged.

The diagnostic now offers explicit `-WithoutMods` isolation through Warhorse's
documented empty mod-order list, with ownership-checked restoration after process
exit. It preserves existing mod orders and both installed mod packages. Windows
PowerShell 5.1 preflight, cached-helper compatibility and empty-file Win32 identity
checks pass. Default launching arguments remain unchanged; live mod exclusion is
not inferred from file creation and must be checked in the resulting game log.

The actual `-WithoutMods` run in
`runtime/evidence/tools-startup-diagnostic-20261012-202201-861e685726ac49efb65ca5bed6faa380`
also failed. Its fresh log explicitly reports `0 mods enabled`, with neither mod's
startup script loaded. PID 52160 exited with the same code 250 after 28.462 seconds;
minimum sampled available system commit was 5,098,078,208 bytes. The renderer hook
remained disabled. This rules out a requirement for either mod to reproduce this
failure, without identifying its cause. The helper conservatively retained its empty
list because the exited process was still enumerated while its handle remained open.
After all processes closed, the exact unchanged owned file was verified and removed;
`post-exit-mod-cleanup.json` records restoration of the previous mod-loading setup.
Cleanup now checks process exit state and disposes temporary process wrappers;
six focused cases cover live, exited, absent and inaccessible process states.

### Successful explicit PowerShell 7 launch

The user repeated the same zero-mod diagnostic through the installed bundled
PowerShell 7.6.5 executable and reported `world ready`. Evidence is preserved in
`runtime/evidence/tools-startup-diagnostic-20261012-204806-0878b89fc0bb475d9cfb2694a95e7e55`.
PID 48368 remained alive through the complete 120-second monitor. The official
Console API returned HTTP 200; the copied game log confirms `0 mods enabled`.
The renderer hook remained disabled and no debugger was attached. A separate
`user-confirmed-world-ready.json` records user confirmation, the running process
identity, the observed PowerShell 7 parent and module snapshot. The temporary
owned empty mod-order list remains pending cleanup after normal game closure.

The successful run produced 118 memory samples without errors. Peak private memory
was 11,389,657,088 bytes; minimum available system commit was 313,569,280 bytes.
It began with less available commit than either earlier failed diagnostic. Its
commit limit increased by 3,256,639,488 bytes at approximately 69 and 73 seconds,
after the earlier failures' 28-second point. This does not prove shell-version
causation or identify the original exit-250 cause. The working PowerShell 7 launch
path is retained; no memory settings or unrelated applications were changed.

A proposed CDB observer was tested only against an original local fixture. Exit
capture and second-chance AV capture passed, but running-timeout cleanup changed
the fixture's later exit code to `0x80000004`. It was never used on KCD. Its
unvalidated source and evidence were preserved under
`runtime/evidence/startup-debug-deferred-20261012` and removed from the user-facing
scripts. No debugger is installed or running as part of the working game session.

Both user launch helpers now forward Windows PowerShell 5.1 invocations to an
existing PowerShell 7 runtime, preferring the installed bundled executable. They
preserve the current console and bound arguments, including explicit false
switches, without installing anything or closing the caller. Future diagnostic
launch receipts record the actual shell path and version. Six non-game forwarding
cases and parsing under both shells pass; an actual PS5 preflight correctly
refuses while the existing PID 48368 remains open. Evidence is in
`runtime/evidence/powershell7-bootstrap-final-1296d58fce3b42dc9eee5b6ddf92fb18`.

`Update-HudCompositor.ps1` now prepares an ownership-checked update from the disabled
original installation to the staged reset fix. Read-only preflight verifies all
six old and new files; only the 299,008-byte add-on changes. The updater backs up
owned bytes, uses atomic replacement, checks closed-game/executable identity on
forward and rollback mutations, and re-enables the owned proxy last. Eight focused
filesystem cases pass under Windows PowerShell 5.1; independent source review
confirmed the rollback guards. Evidence is in
`runtime/evidence/hud-update-fixture-709a44bba6ec46d29d7d9c05e9382316`.

### First visible KCD HUD preview

With all KCD processes closed, the updater replaced the owned add-on with the
reset-fixed build and re-enabled the pinned DXGI proxy. Other bundle files were
unchanged. Backups and deployment receipts are in
`runtime/evidence/hud-update-20261012-210428-0718f9a4d7d749e383037d73b5e20701`.
The user then launched PID 55096 and confirmed `world ready`. Its loaded module
paths and hashes match the repaired installation, and the fresh ReShade log
records successful compilation of the actual HUD effect.

The existing genuine three-frame capture was armed for 40 seconds with run
`a5b34e65665d45f1b180fbdd0c1fc852`. Native receipts record accepted arming, created
resources, submissions of snapshots 1, 2 and 3, and lease expiry. The process
remained alive. The user confirmed that the Minecraft HUD appears when tabbing
into KCD2 and works, while reporting that it looks too small. This is user visual
confirmation of the HUD, not an agent screenshot inspection or separate visual
confirmation of every captured state. The native submission events cover all
three states. Evidence and the exact user report are preserved in
`runtime/evidence/hud-preview-arm-20261012-210833-a5b34e65665d45f1b180fbdd0c1fc852`.

The sizing issue is reproducible in `fit_rect`: 854×480 into 2560×1440 has a
limiting scale of about 2.998, which integer rounding reduces to 2. The resulting
1708×960 canvas begins at (426,240), explaining the inset appearance. The correction
removes that rounding, retaining aspect ratio and point sampling while using the
available backbuffer area. At this resolution the fit becomes 2560×1438.876 pixels,
leaving only the subpixel top/bottom margins required by the small aspect mismatch.
It builds in `build/hud-aspect-fit-20261012` and passes 131 focused contract checks,
including the actual resolution, noninteger scaling, aspect mismatch and bounds.
The new add-on SHA256 is
`819499b52971d5027745be24e136b4a428975d108870ee0f70c1edfdf60b69cb`.
The separate static bundle was staged in `runtime/hud-compositor-aspect-fit`;
verification is in `build/hud-aspect-fit-20261012/verification.json`. At that stage
the installed add-on and its original artifact remained unchanged. The later
continuous build below includes the same correction; live corrected sizing is
still unverified. The updater accepts this
exact build hash alongside the prior reset-fix hash, retaining its original defaults
and all ownership/rollback checks. Full script parsing and 17 focused hash-admission
checks pass in each of PowerShell 5.1 and 7.6.5; these execute only the extracted
allowlist/guard, not the updater. Evidence is in
`runtime/evidence/hud-update-admission-fcfd50ce37a54c5bb8cb70b71142d86a`.
The proposed static-only deployment was superseded by the continuous build below;
the separate aspect-fit bundle was not installed.

This run kept the owned empty mod list from the successful baseline so only the
renderer changed. No continuous UI stream, slot clicks, crafting or host input
suppression was exercised by this static preview. The subsequent deployment below
archived its expired arm after ownership verification.

## Continuous vanilla UI stream — 2026-10-12

The completed snapshot lab remains intact. A separate Java21/JNA mode captures
the normal vanilla GUI through the existing three PBOs, discards older completed
capture IDs and publishes the latest frame from a worker. The original channel
in `protocol/HUD_STREAM.md` uses a fresh named mapping and mutex, exact producer
and target PID/FILETIME identities, immutable expiry and bounded waits. Invalid,
closed or exited peers terminate reception; stale frames cannot refresh the
resident image. No engine offsets or game-thread mapping/file IO were introduced.

The real run in
`runtime/evidence/hud-stream-20261012-212421-479e9128381f425f8c6c3f9ae73bdc4d`
created `MineCome-HudStream-404335e7-563f-46b1-bf16-1d80005edfc9` and sent 344
nontransparent frames to the standalone native receiver. Both sides observed
hotbar selection 0, selection 1, the actual Creative inventory screen, and selection
2 after closing that screen. Fresh client/server inventories agreed before each
capture. The preserved PNG samples were visually inspected as actual vanilla UI.
The intentional publication pause made the receiver's freshness gate inactive;
fresh reception resumed afterward. The receiver observed the closed marker, and
Minecraft saved and exited normally. All mapping/mutex handles were released.
The target was the standalone controller process: no KCD compositor was armed,
and the receipt explicitly keeps `kcd_compositing_verified=false`.

Validation passes 168 Java stream checks, the existing 36 snapshot checks and
146 native checks. The separately frozen native build and review receipt is
`runtime/evidence/hud-stream-native-frozen-3bc7270598a34b42bc8738cb919966e2/verification.json`.
Its add-on SHA256 is
`d7ebc92b59f7971998f1eafb5afe433b5bc44b84a272bcfc9840c49e1d1e6fd8`.
The actual transport run records its own receiver hash; it is distinct from the
subsequently rebuilt frozen artifact. Compilation and standalone evidence do not
establish live D3D12 composition.

The stream add-on uses the aspect-fit correction, a persistent texture and three
fenced upload buffers. It checks the age of the frame actually uploaded, even
while newer frames arrive. Busy upload slots drop updates. ReShade's public APIs
can internally flush or wait; no absolute nonblocking renderer claim is made.
Expiry hides the layer, with GPU resources retained until safe reset/unload.
Independent review resolved a contended-callback lifetime race and confirmed
effect-handle invalidation, upload ordering and worker exception containment.

With every KCD process closed, the owned expired static arm was archived and the
updater replaced only the former add-on. The previous bytes and receipts were
backed up; the pinned owned proxy was enabled last. Preflight passed in PowerShell
5.1 and 7.6.5. The installed bundle is `runtime/hud-compositor-stream`, and
`runtime/evidence/hud-update-20261012-213418-25efcf776e664040bd9047eb4974aa82/update.json`
records `updated_unarmed`, no game launch and no preview arming. The unchanged
owned empty mod-order list remains for the controlled renderer comparison; its
ownership-checked restoration is still owed after that comparison and normal
closure.

The subsequent live check used a fresh user-started tools world and
`Start-HudStreamLab.ps1 -Composite` with the explicit installed stream bundle in
PowerShell 7.3 or later; its results follow below.
Physical slot selection, inventory clicks, crafting, held hands, survival HUD
coverage and KCD menu/input arbitration remain unfinished.

### First live continuous display

The user started tools PID 54196 and confirmed world readiness. Run
`3cd7ea7bb557436cba1f428b94f7b72d` then created a fresh Minecraft world and published
240 nontransparent frames. The native receiver observed all four UI states,
stale-frame hiding, fresh resumption and the closed marker. KCD's loaded stream
add-on accepted the same run, uploaded 200 fresh frames and submitted 1,882 draws,
with zero busy-slot drops or renderer failure events. Minecraft saved and exited
normally; KCD remained alive. These are renderer submission receipts, separately
from the user's visual evidence.

The user confirms seeing the HUD but reports it is now "a bit large" and that
KCD's own HUD remains. They did not separately confirm every slot transition or
the inventory opening/closing. The complete report, native log, process/artifact
identities and controller results are preserved under
`runtime/evidence/hud-stream-20261012-214338-3cd7ea7bb557436cba1f428b94f7b72d`.
The full-canvas fit and vanilla GUI scale are separate concerns: this capture is
854x480 at Minecraft GUI scale 2, enlarged to the host canvas. The GUI needs a
smaller presentation while preserving correct anchors. No KCD health publication
or native HUD suppression exists yet; this remains a Creative UI lab. The stream
is closed and its owned arm awaits cleanup after normal KCD closure.

## Vanilla inventory input and smaller layout — 2026-10-12

The separate input mode uses a 1280x720 capture at vanilla GUI scale 2, preserving
full-canvas aspect fit and pixel sampling. On a 2560x1440 host this changes effective
GUI scale from approximately 6 to 4. The isolated Minecraft window/options are
restored on shutdown. Live sizing still needs the user's observation.

The new reverse channel is documented in `protocol/HUD_INPUT.md`. Exact paired
process identities, a 64-record ordered ring, client-tick acknowledgements and
250 ms freshness bound input. Game calls remain on the Minecraft client thread.
The separate native `hud_input_addon.cpp` and `MineComeHudInput.ini` leave the
previous stream source/artifact intact. F8 enables one keyboard session of at most
30 seconds after a fresh composed image, ready guest and neutral controls. Only
1-9, E and Escape are forwarded. Focus loss, ReShade overlay, stale input, closure
or runtime reset ends ownership; the next-frame blocking request then stops.
This is not verified KCD input exclusivity or automatic host-menu arbitration.
Live mouse forwarding is disabled because the inspected ReShade DirectInput8
polling path preserves mouse axes. The test requires host menus/console closed.

The real fixture in
`runtime/evidence/hud-input-20261012-220732-28aaccdc10d74b0cb5a10ddb08eca7e3`
passed all 31 acknowledged events, selected all nine hotbar slots and opened/closed
the actual Creative inventory. Three ordinary vanilla slot clicks swapped stone64
and dirt32; final client and integrated-server inventories agree. It published
32 real UI frames and the native fixture received 30. Controls, image mapping and
input mapping were released, including a published terminal client ACK. Minecraft
saved and exited normally. The genuine 1280x720 PNG samples were visually inspected.
No KCD compositor or physical host input was exercised by this fixture.

The first run exposed image starvation when the snapshot proof gate waited for
every rapidly changing selected slot to agree with the server. Interactive mode
now renders normal client predictions while truthfully marking pending server
confirmation; authoritative final proofs still require server agreement. The
successful retry exercised 13 pending and 18 confirmed captures, retaining the
250 ms input freshness limit. The failed run remains in evidence under
`hud-input-20261012-220451-ae51df56f91f414089c83f9142ac6cf9`.

Validation passes 325 Java input checks, 174 stream/layout checks, the existing
36 snapshot checks and 216 native input checks. Independent review covered the
transport, UI calls, callback lifetime, controller and arm archival. Final native
build evidence is
`runtime/evidence/hud-input-native-frozen-4c924c5ffdbe4d5ca3f3e917d449ff51/verification.json`.
The input add-on SHA256 is
`d7de884b798c6480efc24981ce409821192a7fcd56f6c2361ff32ec2755eefca`.
Final Fabric JAR SHA256 is
`e9e89cac0e81d052538bd195a25d588769442c67ff7f912ab2c363b27c08863e`.

KCD subsequently closed normally with `WM_CLOSE`, exit code 0. The unchanged
diagnostic-owned empty mod-order file was removed only after matching its original
file identity, timestamps, size and hash. Ordinary mod discovery is restored;
both mod packages are unchanged. The cleanup receipt and normal-close log are in
`runtime/evidence/tools-startup-diagnostic-20261012-204806-0878b89fc0bb475d9cfb2694a95e7e55`.
The owned expired stream arm was archived beside its original arming receipt.
Before deployment, all 1,008 current save/profile files were backed up and hash
verified under `runtime/backups/20261012-230838`.

At this deployment, `runtime/hud-compositor-input` was installed unarmed. Both
PowerShell 5.1 and 7 preflight passed; only the owned add-on changed, its previous
bytes were backed up and the pinned proxy was enabled last. Deployment receipt:
`runtime/evidence/hud-update-20261012-220935-ae5ecddf2d944d7292c41c5fc7981447/update.json`.
No game launch was performed by that deployment. The subsequent user-started
live attempts are recorded below. KCD HUD suppression, health mapping, mouse
inventory controls, crafting and general gameplay ownership remain unfinished.

### First live keyboard attempt

The user started a fresh tools world and confirmed readiness. Run
`39d46065f12f450e8fe60dcbc57e618b` accepted the image arm, published 41 Minecraft
frames and uploaded 24 in KCD with 179 submitted draws. It ended before the F8
activation: no keyboard ownership and no input events were recorded. The native
receiver rejected a waiting-state acknowledgement as `ack_stale`. That build
combined old, future and regressed timestamps under this reason and recorded no
exact timing details, so the precise timestamp failure is not proven. Source
review found that both peers treated old readiness as terminal before ownership.

Minecraft saved and exited normally. KCD PID 45948 remained alive, and the user
confirmed the failed attempt. The guest released its handles but did not publish
its terminal client ACK within the original 250 ms cleanup rendezvous; the
controller correctly rejected this as a successful input run. Evidence, the copied
native log and host identity observation are preserved under
`runtime/evidence/hud-input-20261012-221347-39d46065f12f450e8fe60dcbc57e618b`.
Live keyboard behavior and satisfactory GUI sizing remain unverified. Its expired
owned input arm remains in place until normal KCD closure and verified cleanup.

### Waiting-state repair and delayed real-client regression

Waiting readiness now becomes temporarily ineligible when the real client ACK,
image or host heartbeat is old. It can recover only on fresh client observations;
F8 cannot acquire ownership during the gap. Armed input still expires at 250 ms,
and malformed, zero, future or regressed timestamps, changed identities and
immutable expiry remain terminal. Timestamp checks now use receipt time after
mutex work, and both peers recheck the lease there. This avoids interpreting a
newer real timestamp against a pre-wait clock sample. Worker diagnostics now
distinguish rejection reasons and record actual ACK ages/timestamps.

Closure releases controls immediately and gives the guest worker a separate
bounded one-second rendezvous for the client-generated closed ACK, including
mutex retries. The native add-on withdraws ownership before a final 1.5-second
ACK grace when the image stream ends. No timestamp is manufactured, no deadline
is renewed, and no closed session can resume input.

The actual regression run
`runtime/evidence/hud-input-20261012-222339-c67562e8e7734eaf958b9b9e6ef58b08`
deliberately withheld ready ACKs for 498 ms and the final client ACK for 550 ms.
The native peer observed a maximum prearm ACK age of 553 ms, 51 stale observations
and one recovery, then all 31 UI events, nine selections and real inventory
open/close passed. Stone/dirt swapping again agreed on client and server. Native
closed-ACK wait was 609 ms. The run published 65 UI frames, received 52 and saved
and exited normally with every cleanup flag true. KCD remained open but was not
the fixture target; this does not establish live physical input or live sizing.

The updated pure Java suite passes 353 checks and native suite 243; final Java and
native compilation/remapping passed, with independent review of waiting recovery,
active expiry, callback lifetime, fixture routing and cleanup. Frozen native
evidence is
`runtime/evidence/hud-input-waitfix-native-frozen-b8d6ba96e5cd437facf9bbdad9e21b15/verification.json`.
Add-on SHA256:
`56fb1cca6806a1cca41c9e1875da56ec1895e9781d0251bf6153d880cbd0bb80`.
Fabric JAR SHA256:
`1829334c03f050ef73aec6ddbdddeba911d4cc3dcd8638ac62f5c35fb6ef098b`.

After the user closed KCD, the owned expired input arm was archived and all 1,008
save/profile files were backed up again under `runtime/backups/20261012-232513`.
PowerShell 5.1 and 7 preflight passed. The updater installed only the repaired
owned add-on, preserving the previous bytes and enabling the pinned proxy last.
Current bundle and input-mode default: `runtime/hud-compositor-input-waitfix`.
Deployment receipt:
`runtime/evidence/hud-update-20261012-222531-279ecff953e3418591c3fa0276601090/update.json`.
It was installed unarmed before the second user-started live attempt below. The original input
and continuous stream artifacts remain available as separately verified builds.

### Second live keyboard attempt

Run `5854a3c5336448158a97e26b8bf42b57` used the repaired add-on in user-started
KCD PID 54424. Waiting recovered seven times, with a maximum prearm ACK age of
1,654 ms. F8 then activated both native and guest ownership. About 1.7 seconds
later the render gate closed ownership before any UI key events were sent.
The broad `ownership_closed` reason cannot identify its exact eligibility cause.
Closure was 256 ms after the last real ready ACK, which is consistent with the
250 ms freshness gate, but this alone does not establish the cause of the gap.

Minecraft published 220 frames; KCD uploaded 195 and submitted 1,746 draws. The
user confirmed seeing the HUD initially, then thought Minecraft had crashed.
Its logs instead show the controller's normal cancellation path, save and exit.
The closed client ACK and all handle releases succeeded. No inventory opening,
slot selection or host keyboard exclusivity was verified, and GUI size was not
accepted. KCD remained alive. Evidence and the copied native log are under
`runtime/evidence/hud-input-20261012-222727-5854a3c5336448158a97e26b8bf42b57`.

The recorded 1,031 ms callback gap and 1,135 ms image age are whole-run maxima,
not necessarily armed-phase measurements. The callback also skips overlays, so
it is not a direct measurement of every Minecraft tick. The inspected 1.21.1
render loop has no automatic background frame limiter in this path. VSync was
enabled and buffer swaps share the tick thread. At this stage a blocked
presentation was a hypothesis; the following diagnostic measured actual tick and
render stages to locate the stall without another physical F8 attempt.

### Background presentation diagnosis

The standalone real-client comparison
`runtime/evidence/hud-input-20261012-223940-b34b431d725246beb50153cec21f39d2`
completed two 12-second unfocused phases while the user kept KCD in front.
Minecraft tick observations and focus callbacks establish its unfocused state;
KCD foreground is user-reported, not independently sampled. One interrupted phase
was restarted before measurement. With original VSync/120 FPS settings the maximum
tick gap was 1,090 ms and desktop buffer swap took 1,047 ms. With VSync disabled
and a 60 FPS cap, those maxima were 701 ms and 679 ms. Every captured slow stack
was inside `GLFW.glfwSwapBuffers`; event-poll freeze was false and PBO operations
were short. This locates the stall in desktop presentation, but does not identify
the driver's underlying reason or establish that VSync alone causes it.

The following UI sequence failed the unchanged 250 ms ACK gate after six sent
events and five applied events; the armed tick gap reached 343 ms. It did not
verify the inventory. Minecraft saved and exited normally, published 590 frames,
released its mappings/handles and published its closed ACK. The native fixture
reported `ack_aged` and did not receive that final ACK before its failure exit.
Original VSync/120 FPS values were restored in both options and the actual Window;
the options file also retained those values. The controller correctly reports
failure, while the completed comparison remains useful diagnostic evidence.

The comparison adds bounded stage/tick/PBO timing and up to eight slow-thread
samples, captured outside the render thread. Pure timing tests pass 38 checks,
Java input tests 353, and the native diagnostic/receipt suite 259. A separately
compiled native add-on now records the first ownership-close cause and fixed
eligibility snapshot, without changing its gate. That add-on is not installed;
the KCD session at that time retained the previous waitfix build. Native build evidence:
`runtime/evidence/hud-input-timing-native-frozen-9018b84a73a2471a83a184e75d1fea0f`.

The first targeted follow-up kept the actual vanilla HUD framebuffer/PBO route
and skipped the separate desktop buffer swap in an explicit, bounded input mode.
No timeout relaxation or fabricated tick/ACK is involved. Its live and standalone
verification are tracked separately below when completed.

The first offscreen trial
`runtime/evidence/hud-input-20261012-224748-38ac40544c84474fbaa506e53c3b95b7`
completed 12,004 ms unfocused with 240 tick observations and no focus reset.
The maximum tick gap fell to 54 ms and the preserved swap wrapper took at most
0.831 ms; no slow stack samples occurred. VSync remained enabled and the original
120 FPS setting was retained. The trial skipped 1,411 desktop swaps and continued
publishing actual frames, demonstrating that offscreen presentation removes the
previous desktop stall in this measured interval.

The input sequence still failed: two events were applied, then the guest detected
`Own image publication stale`. Native sent three events and observed guest
closure. There were 605 published frames, 17 mailbox replacements, zero mutex
misses and zero stale-frame drops. The largest armed tick gap was only 50 ms.
Thus this attempt does not verify background inventory input. Image handles were
released and Minecraft saved/exited normally, but the failure path did not retain
the complete input cleanup proof. At that point publication and evidence work
shared one worker; the following repair separated them while preserving the
freshness limit.

The evidence-I/O separation passed 15 blocked-writer checks and the existing 174
stream checks. Control JSON now uses a separate bounded worker and PNG encoding
runs only after image-channel closure. The follow-up real run
`runtime/evidence/hud-input-20261012-225636-2ab9113cd7f44aa69659f08ab881e7ff`
still failed image freshness, after 15 applied events and eight observed slots.
Its new failure snapshot identifies the cause: all three PBO slots were pending,
the oldest was 251 ms old, and fence completion age reached 575 ms during the run.
The publication worker was waiting for a frame, with 280 ms since publication.
Pixel conversion took at most 6.72 ms, mapping writes 0.53 ms, and the completed
receipt write 1.51 ms. There were no stale-server capture skips; the server
observation was 33 ms old. Armed client tick gaps stayed at most 51 ms.

This confirms GPU readback backlog rather than evidence I/O as the remaining
cause in that run. The separation remains useful hardening. All 404 published
frames and truthful failure details were preserved; the real closed ACK,
input/image handle cleanup and evidence-worker shutdown succeeded. Minecraft
saved and exited normally. This motivated the following reduction in redundant
GPU work, with no change to the freshness limit.

### 2026-10-13: capped offscreen GPU workload trial

The scoped offscreen mode now caps the owned guest at 30 FPS and skips the unused
desktop framebuffer draw as well as the desktop swap. The inspected draw's GL
state epilogue is preserved; actual vanilla HUD rendering and PBO copies remain
active. Original option and Window settings are recorded separately and restored
on cleanup. Other modes retain their ordinary presentation behavior.

Actual run
`runtime/evidence/hud-input-20261012-230605-08c656378fc04555983218243fc6c9dc`
completed 12,063 ms unfocused at the verified 30 FPS setting, with 241 client tick
observations and no focus reset. Across the session, 517 desktop draws and swaps
were skipped and 517 GL flushes were issued. The run published 200 real hotbar
frames, of which the native fixture received 199. It applied 16 input events
unfocused; native sent 17 and observed eight selected slots. It did not open the
inventory or verify the ninth selection or stack swap.

The guest again closed with `Own image publication stale`. At the failure,
all three PBOs were pending, the oldest was 267 ms old, and the publisher was
waiting for a frame 294 ms after its last publication. Maximum fence completion
age reached 967 ms. There were no stale-server capture skips, and the server
observation was 18 ms old. Armed client tick gaps stayed at most 67 ms, with no
slow render-thread samples. Pixel conversion, mapping writes and receipt I/O
peaked at 5.98 ms, 0.35 ms and 1.97 ms respectively. The cap and blit omission
therefore did not resolve GPU readback completion delays in this run.

The guest released controls, published its real closed ACK, closed input/image
handles and stopped its evidence worker. The native fixture reported failure
and did not record the final ACK in its failure path. VSync remained enabled;
the original 120 FPS option and actual Window cap were restored without an
explicit options-file write. Minecraft saved all dimensions and exited with
code 0. The controller correctly reports failure. KCD was neither launched nor
stopped by this standalone check, and no compositor was armed. Physical KCD
input, live GUI sizing, host input exclusivity and host HUD/health integration
remain unfinished; further work is focused on the measured pending GPU fences.

### 2026-10-13: desktop clear omission and paired fence diagnosis

The opt-in offscreen helper now also omits the inspected outer
`MinecraftClient.render` clear at bytecode offset 330, before the owned framebuffer
is bound. It acts only for the exact color/depth mask 16640, a zero draw-framebuffer
binding, and the existing world/window/lease guard. The genuine HUD color and
vanilla depth clears on the owned framebuffer remain active. Paired fence
diagnostics place an additional fence immediately before `glReadPixels`, while
the original fence after that call remains the sole permission to map pixels.
Both use zero-timeout polling; the diagnostic fence cannot refresh the stream.

Actual run
`runtime/evidence/hud-input-20261012-231138-fb7f035c9abc4d4b8d5cd5c00376923d`
completed 12,007 ms unfocused with 240 tick observations at 30 FPS. It exercised
570 omitted desktop clears, 570 omitted draws/swaps and 570 GL flushes. The run
published 206 frames, with 205 received by native. It applied four unfocused
events from five sent and observed two selected slots, then failed with
`Own image publication stale`; the inventory was never opened.

At failure all three fences before readback were still pending, with observed
ages of 235, 168 and 100 ms. The publisher was waiting for a frame 263 ms after
its last publication. The largest observed pre-read fence age was 1,039 ms;
the largest additional interval between observing the pre-read and post-read
fences complete was 32 ms. These are CPU poll observations, not precise GPU
timer durations. They locate the long delay in GPU commands preceding readback,
rather than principally in mapping/copying pixels to CPU memory. They do not yet
identify the driver's scheduling reason or prove contention from another process.
Armed tick gaps remained at most 67 ms, server-stale skips were zero, map/copy
peaked at 7.76 ms and receipt I/O at 1.50 ms. Repeated end-of-frame flushes mean
a missing flush is not established as the cause.

The guest released controls, published its real closed ACK, closed input/image
handles and stopped the evidence worker. Native retained failure without recording
the final ACK in its failure path. Original enabled VSync and 120 FPS settings
were restored in options and the Window. Minecraft saved normally and exited
with code 0. The controller correctly reports failure; the helper remains opt-in,
all freshness limits are unchanged, and no new KCD compositing, physical input,
inventory or sizing result is claimed. Possible GPU contention is the next
investigation, not a verified explanation.

### 2026-10-13: bounded host frame-cap comparison prepared

`kcd2/probes/hud_gpu_budget_probe.lua` and `scripts/Test-HudGpuBudget.ps1` now
isolate whether reducing KCD's frame workload changes the existing offscreen
fixture result. The planned comparison changes the previously observed uncapped
`sys_MaxFPS=-1` to 60 while requiring `r_VSync=0`; the fresh run re-reads both
values. A positive cap already at or below 60 is rejected. The Minecraft fixture,
250 ms freshness limits and installed compositor remain unchanged.

The probe schedules its pause-updating expiry before the deferred cap write and
limits the engine-timer lease to 120 seconds. Exact run/state/timer identities
prevent stale callbacks from acting on a newer run. End and expiry restore only
the still-owned cap, preserve external changes and verify the original value by
readback. The controller always requests End in `finally`; a valid comparison
requires the requested nonexpired end, actual restoration and timer cancellation.
Engine stalls can delay script timers, so this is not an independent UTC watchdog.

The real Lua 5.2 VM passes 22 simulated-engine cases covering those paths,
including setter failures after mutation, logging failure, reload, external
changes and failed restoration. Independent source and wrapper review found no
blocker. These checks do not establish live CVar/timer behavior or GPU improvement.
The attempted live invocation stopped at preflight because the old KCD PID 54424
had closed; no host cap was changed and no Minecraft process was started.

`Archive-HudArm.ps1` archived the exact owned expired arm for run
`5854a3c5336448158a97e26b8bf42b57` while KCD was closed. Its receipt is
`runtime/evidence/hud-input-20261012-222727-5854a3c5336448158a97e26b8bf42b57/capture/arm-archive.json`.
The installed `runtime/hud-compositor-input-waitfix` artifact is unchanged and
unarmed. The user was then asked to restart with `scripts/Start-Kcd2ToolsTest.ps1`;
the resulting actual comparison is recorded below.

Once that world is ready, the controller command is:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudGpuBudget.ps1'
```

This runs the standalone Minecraft fixture against the existing KCD session's
temporary frame cap. It does not arm KCD input, launch or close KCD, or establish
physical hotbar/inventory interaction. A comparison result and verified host-cap
restoration are required before choosing the next implementation change.

### 2026-10-13: host cap restored, comparison invalid because focus never changed

The user-started KCD tools process is PID 46236, created at
`2026-10-13T11:43:27.2961094Z`. Host-budget run
`9354dbc5a9e3459e8c1ddfea711bb0f9` applied `sys_MaxFPS=60` from the exact original
value −1. Its 120-second timer then expired and restored −1 with readback success.
The controller records `restoration_verified=true` and `comparison_valid=false`;
expiry is deliberately not accepted as a valid completed comparison. Receipts are
under `runtime/evidence/hud-gpu-budget-20261013-124533-9354dbc5a9e3459e8c1ddfea711bb0f9`.

The paired Minecraft fixture `6c7341981e1344a2ae437816ae60403d` recorded 2,003
focused ticks and zero unfocused ticks. It never completed the required 12-second
unfocused phase, never armed input and sent/applied zero events. It reached its
100-second waiting limit, published 1,492 real HUD frames, then completed the
normal save/shutdown path. Real closed ACK and handle cleanup succeeded, and the
original enabled-VSync/120 FPS option and Window settings were restored. The native
fixture retained `guest_closed` failure and received 1,491 frames.

Maximum observed own-image age was 85 ms and pre-read fence age 39 ms, but those
measurements were obtained while Minecraft remained focused. They do not prove
that capping the host resolves the background GPU backlog. Full guest receipts
are under `runtime/evidence/hud-input-20261013-114534-6c7341981e1344a2ae437816ae60403d`.
The frozen 22-case source/test review receipt is
`runtime/evidence/hud-gpu-budget-native-frozen-b8c6c066d2d44500a62fda949f75f6b7/verification.json`.

The installed waitfix add-on remains unchanged and unarmed; this comparison did
not launch or stop KCD. At this point automatic hiding of the owned guest window
was being implemented to establish the required background condition without a
timed user handoff. Its first trial follows below. No new physical keyboard, inventory,
sizing or host-input exclusivity proof is claimed.

### 2026-10-13: owned window hidden, readiness blocked by the wrong focus check

The first hidden-window fixture,
`runtime/evidence/hud-input-20261013-115450-6d5b5e35855643f29a86824c671b3c10`,
verified `visible_after_hide=false` for the owned Minecraft window. Its raw GLFW
focus query reported true after hiding, while Minecraft's genuine focus state
was false: actual tick diagnostics recorded zero focused and 2,003 unfocused
ticks. The hidden-phase readiness condition nevertheless required the raw query
to become false, so its timer never completed. Input never armed and zero events
were sent or applied. The controller correctly retained failure after the
100-second waiting limit, with 1,496 genuine HUD frames published and received.

During that waiting phase the maximum client tick gap was 75 ms, readback age
38 ms, published capture age 48 ms and publication gap 91.8 ms. Those observations
are useful diagnostics, but the blocked gate prevented testing the input sequence.

The real closed ACK and all image/input handle cleanup succeeded. The guest
restored enabled VSync and 120 FPS in options and the Window, restored the
original visible/focus-on-show settings without requesting focus, and exited
normally with code 0. This verifies the bounded hide/restore path, not a successful
background inventory sequence or a resolution of GPU starvation. KCD was neither
armed, launched nor stopped by the fixture.

[GLFW 3.4's Win32 focus query](https://github.com/glfw/glfw/blob/3.4/src/win32_window.c#L1803-L1806)
compares against `GetActiveWindow`. Microsoft's
[API documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getactivewindow)
defines that result within the calling thread's message queue and distinguishes
the global foreground window. The exact bundled version was then verified as
GLFW 3.4.0 Win32 WGL within LWJGL 3.3.3. The narrow readiness correction uses the
genuine Minecraft focus callback together with verified hidden visibility and
retains the raw GLFW value as a diagnostic. It does not fabricate focus or change
the 250 ms freshness limits. Its completed standalone result follows.

### 2026-10-13: hidden, unfocused inventory fixture passes with KCD uncapped

The corrected, independently reviewed build has remapped JAR SHA256
`AB16828D0BF7C747D80A41DA6C99EFABBC0D85BF6BDE0CD8D8DD710E4B37EDB3`.
Actual fixture `ec8509f6af394e11a3e9ba5c8b062e5a` passes under
`runtime/evidence/hud-input-20261013-120534-ec8509f6af394e11a3e9ba5c8b062e5a`.
The host-settings receipt records KCD `sys_MaxFPS=-1` and `r_VSync=0`;
this successful trial did not require the temporary 60 FPS host cap. KCD's
foreground status was not independently recorded, so this does not establish the
same GPU scheduling conditions as a KCD-focused live test.

Minecraft was focused before its owned window was hidden. One genuine focus-loss
callback followed, and the 12,058 ms readiness phase recorded 241 unfocused ticks
and zero focused ticks, with unchanged framebuffer dimensions. Across the run,
276 ticks and all 31 applied events were hidden and unfocused, with no visible or
focused event applications. The native fixture acknowledged all 31 events,
observed all nine slots and inventory opening/closing; final integrated-server
proof confirms the stack swap.

The guest published 205 genuine HUD frames and the native receiver received 204.
Maximum own-image age was 155 ms and readback completion age 125 ms, with zero
fence-timeout polls. The existing 250 ms gates were unchanged. This is a successful
bounded background fixture, not a general GPU performance guarantee.

Real closed ACK, input/image handle cleanup and original enabled-VSync/120 FPS
option/Window restoration all passed. Original visibility and focus-on-show
settings were restored with focus disabled during showing and no focus request;
the client remained unfocused. The controller did not arm KCD, launch or stop it.
The installed waitfix add-on remains unchanged. The following separate live
check tests actual KCD-focused keyboard delivery; GUI sizing and host-input
exclusivity remain unverified.

### 2026-10-13: hidden live attempt still closes on stale GPU images

Live run `e63eeea7a7a54655b6871d8369993970`, at
`runtime/evidence/hud-input-20261013-120701-e63eeea7a7a54655b6871d8369993970`,
targeted the existing KCD PID 46236 and armed the installed waitfix compositor.
Both native and Minecraft ownership activated after F8, but no UI events were
applied. The guest reported stale own-image publication, and the controller
correctly recorded failure after 534 published frames. Maximum observed own-image
age was 466 ms; the failure snapshot shows the publisher awaiting a frame with
all three pre-read fences pending. Their maximum observed age was 469 ms, while
current server observation age was only 3 ms and no server-stale captures were
skipped. Hidden presentation has therefore not resolved the live GPU backlog.

The user reported that Minecraft appeared as a black window and then closed,
and the remaining keys did not work. The receipts show the controlled failure
cleanup and normal exit 0: real closed ACK, controls/handles released, visibility
and focus-on-show restored without requesting focus, and enabled VSync/120 FPS
restored in both options and the Window. KCD was neither launched nor stopped.
This run adds no physical hotbar/inventory, sizing or host-exclusivity proof.

The following diagnostic repeats the standalone hidden fixture under the bounded
60 FPS host cap. The preceding standalone pass remains valid within its recorded
conditions, without establishing live KCD GPU stability.

### 2026-10-13: capped hidden fixture passes with verified requested restoration

Host-budget run `febe0c161705407f9995f4207894bcd4` completed with
`fixture_passed=true`, `restoration_verified=true` and `comparison_valid=true`.
It changed KCD PID 46236 from `sys_MaxFPS=-1` to 60, then restored −1 through
`requested_end` before the 120-second lease expired; timer cancellation passed.
Receipts are at
`runtime/evidence/hud-gpu-budget-20261013-130919-febe0c161705407f9995f4207894bcd4`.

Its paired fixture, at
`runtime/evidence/hud-input-20261013-120919-60ce70cb803543d1a4decb5dbc2f8926`,
passes all 31 hidden/unfocused events, all nine slots, inventory opening/closing
and the integrated-server-confirmed stack swap. The 12,029 ms preparation phase
had 241 unfocused ticks and zero focused ticks; the complete run had 276 hidden/
unfocused ticks. Minecraft published 202 genuine frames and the receiver saw 201.
Maximum own-image age was 131 ms and readback completion age 43 ms, with zero
fence-timeout polls. Real closed ACK, handle cleanup, visibility/focus-on-show and
enabled-VSync/120 FPS restoration all passed, followed by normal exit 0.

The user was instructed to keep KCD in front, but no independent host-foreground
record was collected. This is a valid capped standalone fixture and restoration
result, not live compositing or proof that the cap fixes the earlier KCD-focused
failure. No physical inventory keys or host-input exclusivity are established.

The explicit `Start-HudInputLab.ps1 -Mode Live -OffscreenPresentation -HostGpuBudget`
option is now implemented. It applies the unchanged 60 FPS/120-second Lua lease
after Minecraft readiness and exact Java process validation, before compositor
arming. Shared `scripts/HudGpuBudget.ps1` also serves the fixture wrapper. Its
`finally` path checks restoration/readback; overall success requires a valid
budget, with `body_passed` recorded separately from that final verdict.

`tests/hud_gpu_budget.Tests.ps1` passes 98 assertions across 11 simulated-console
scenarios. The extracted helper also passed an actual −1→60→−1 check in KCD PID
46236, with cap, restoration and budget validity all true:
`runtime/evidence/hud-gpu-budget-20261013-131823-a11a2771df5c4b8789e69dbbe6ce5f17/budget-verification.json`.
Final independent controller review passed. No native add-on or Minecraft JAR
changed for this controller work. The user then restarted KCD with the unchanged
waitfix installation for the combined live check below.

### 2026-10-13: short live keyboard sequence and HUD size verified

Run `3f322ff93e6a4b35b1b64dd3f16410f4`, under
`runtime/evidence/hud-input-20261013-122232-3f322ff93e6a4b35b1b64dd3f16410f4`,
used the unchanged waitfix add-on in fresh KCD PID 48640, started at
`2026-10-13T12:20:51.6014572Z`. The user confirmed the HUD size was perfect and
all requested controls worked. Ten physical press/release events for 1, 2, 9,
E and Escape were sent, acknowledged and applied; the actual Creative inventory
opened and closed, with a captured inventory sample at selected slot index 8.
All nine slots and stack swapping remain standalone-fixture evidence.

The controller records `body_passed=true` and `result=passed`; the guest records
`input_completed`, `end_reason=host_closed` and no failure. It published 496 genuine
frames; native receipts show 478 uploads, 2,001 submissions and zero drops.
Maximum own-image age was 140 ms, measured readback age 46 ms and tick gap 108 ms.
The guest recorded 670 hidden/unfocused ticks and one actual focus-loss callback.
All ten events and the real closed ACK were acknowledged. Settings, visibility,
controls and image/input handles were restored/released; normal saves and exit 0
show that Minecraft's closing window was not a crash.

Native timestamps put keyboard arming at 13:23:27.197 and ownership closure at
13:23:37.670, approximately 10.47 seconds later. The installed add-on lacks the
new first-close diagnostics, so the exact trigger is unknown; neither 30-second
expiry nor focus loss is established. This is short live keyboard/sizing proof,
not full-duration operation or KCD menu/input exclusivity.

Host-budget run `11e7171fd8fb4966a351c72b2a7349ad` verified −1→60→−1 through
requested End before expiry, with timer cancellation and valid restoration:
`runtime/evidence/hud-gpu-budget-20261013-132304-11e7171fd8fb4966a351c72b2a7349ad/budget-verification.json`.
Next implementation work is full-session close diagnostics and mouse ownership;
KCD HUD suppression and health integration remain separate unfinished work.
