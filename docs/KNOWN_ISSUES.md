# Known issues and blockers

## Latest combined input limitations

The combined side-face/walking/inventory check now passes in KCD2, including all
156 movement updates/readbacks. Its first placement request nevertheless expired
at 505.5376 ms against the 500 ms permit lifetime, before vanilla placement was
queued; a second request succeeded. This specific rejection was not player
collision. Reducing that transport/permit delay remains work; do not widen the
freshness limit or replay an expired click as a repair.

Removing duplicate pre-dispatch validation passes automated checks, but the next
live comparison still rejected its first click as stale. A second click placed
without moving. The added block was broken, but the seed remained at the 12-second
aim cutoff, so the lab ended through failure cleanup before the 30-second HUD limit.
Consistent first-click responsiveness remains unresolved. Do not classify that
comparison as a full pass or as a player-hitbox failure.

Startup now prewarms camera parsing and settled-state validation on disposable
diagnostic data, and records per-click processing stages. Offline checks pass;
the warmed live first-click path still needs verification.

A preceding retry was spoiled by a stale buffered READY countdown: a prompt
promised 35 seconds with only 3.412 seconds remaining. Exact guest deadlines and
the fresh `Read-HudInputPromptWindow` check now replace that workflow. A console
line's reported remaining time must never be reused as a current countdown.

## Public source, experimental game support

The [public repository](https://github.com/gabrielpery/minecraft-kcd2) contains
source and development procedures. It does not include a ready-to-install retail
release, prepared game assets, local test evidence or runtime bundles. Follow
[setup](SETUP.md) for a fresh clone; references to a staged package or installed
tool in historical reports describe the development machine.

Current live HUD, inventory, camera and fixed-cell stone tests use the official
KCD2 1.5.5 development game. Retail 1.5.6 support remains gated below. Actual
Minecraft aiming passes isolated automatic tests, including an aimed break from
the native C++ host through the new optional protocol. That host supplies synthetic
coordinates. The optional KCD relay, Lua intent capture, permit selector and aimed
HUD guest are connected through an explicit bounded controller. The actual HUD
adapter also passes an automatic Minecraft run with a synthetic host. A single
live KCD crosshair click now has client/server confirmation and engine removal,
with barely any delay reported after the log-latency repair. Face tests exposed
KCD's default spawned-entity rotation moving the visible cube one unit in
negative X from the logical targeting box. Both spawn paths now explicitly set
zero world rotation and verify actual world bounds. The repair passes 64 Lua
tests and automatic live bounds/adjacency checks. A fresh live check confirms
one click places on the original seed's top and the next two clicks break both
blocks, with no refusals and complete cleanup; the user reports “worked perfectly.”
Complete coverage of every face and sustained-session stability remain pending.
Continuous shared movement, general block rendering,
persistence, survival integration and multiplayer remain unfinished.

Hotbar changes after aimed-action dispatch no longer invalidate confirmation
solely because selection moved. Actual Minecraft passes 28 standalone scenarios,
including placement and breaking while switching slots and rejection of an
altered original stack. Rapid switching during an aimed KCD session still needs
live coverage.

The first integrated aimed attempt produced no confirmed action. Captured
camera origins exceeded the previous mapped-eye allowance, and the HUD later
stopped with a click-delivery failure and logged capture lock contention.
The origin check now allows 0.25 metres while retaining Minecraft reach and
current-host agreement checks; actual Minecraft passes 25 synthetic-host
scenarios. Selective revision 4 repairs busy read-query handling and input
recovery. One run confirmed a break after several refused clicks; processing
complete log records without waiting for another newline then allowed the next
live test to confirm its first click, without extending permit expiry.

Earlier failures below are retained for diagnosis. The latest verification status
is in [progress and evidence](PROGRESS.md); successful bounded tests do not remove
the remaining gameplay limits.

The combined walking/aimed fixture passes in actual Minecraft on flat and captured
KCD terrain, including top/side placement, breaking, inventory and resumed walking.
The separate combined live profile passes walking, a settled aimed break and
resumed walking with the HUD: its first run has 156/156 movement readbacks and
the user reports “worked perfectly.” The newer `TopFaceInventory` scenario also
passes top placement, added-block and seed breaks, inventory and resumed walking:
155/155 readbacks, 1.85 seconds of zero client/server inventory displacement,
cleanup before restoration and normal exit. The user reports “all worked!”
Clicks require fresh host/guest agreement after the 200 ms playback buffer settles.
Aiming closes 12s after first movement and drains before KCD's automatic restoration,
since the guest remains at its final position. All stones must be removed before
that cutoff. The dedicated support is beside the imported terrain; general placement
directly against KCD terrain remains unverified. `SideFaceInventory` requires the
seed's WEST face and is still pending live verification in this combined profile;
that adjacent cell must be outside the imported collision cells. Other faces and
sustained sessions remain unverified. The new bounded inventory collector proves
observed immobility, zero movement bindings and actual movement after closing.
It cannot establish a physical W attempt from a missing event: the native input
filter normally suppresses W before Minecraft receives it. User confirmation of
that attempted control stays separate from machine receipts, whose physical-input
and visual proof flags remain false. E toggles the inventory open and closed.

The subsequent `SideFaceInventory` attempt `aee7bfb17fa54dc18a665f767468af67`
failed when the controller's `Get-Content` camera snapshot read encountered a
sharing violation on `host-view.json`. It retained only 74 forwards/70 readbacks;
KCD restoration succeeded, then Minecraft saved and exited 0 after relay/stream
closure. KCD itself remained alive. The user's “didnt do anything just crashed”
report is preserved separately. A snapshot reader with explicit read/write/delete
sharing now passes 138 automated camera checks and 159 controller checks. The
following Computer Use attempt read 811 camera samples without that error, but
never activated input or started movement, so it does not verify the repair during
walking. Side-face coverage remains pending. An earlier debug HTTP timeout
occurred during probe initialization before arming, and supplies no gameplay proof.
See [the exact failure receipts](PROGRESS.md#combined-side-face-attempt-stopped-on-a-camera-snapshot-read--failed).

One combined trial stopped when Windows denied camera-file replacement for the
existing100ms retry budget. The lock holder is unknown; later unchanged camera
code passes flat and captured-terrain runs. Retain the original failure evidence
rather than treating this intermittent file-sharing issue as resolved. This older
writer-side failure is distinct from the later controller snapshot read failure.

## Stone texture blur resolved in the verified close view

The user's screenshot now verifies actual Minecraft stone in the loaded official
development world, with engine bounds spanning one unit per axis. Its texture is
visibly blurred in the first test. The initial material left filtering at the engine default; stock
Illum uses a global smooth sampler. The point-filter XML hint may be ignored.
The converter now isolates the exact16×16 stone sprite from the actual atlas,
remaps the original face UVs, and repeats each pixel32×32 into a512×512 texture
without interpolation. This reduces filtering transitions while preserving source
colours. It is an asset-level mitigation, not an exact point-sampling shader or a
change to game graphics settings. The user's second screenshot and explicit "Fixed it!"
confirm crisp front and side faces. Depth/parallax, distant minification and the exact
runtime sampler state remain separate checks.

## Retail KCSE deployment prerequisite

The installed retail game1.5.6.0 matches libKCD2's target, but the exact validated
Steam address map is absent. KCSE performs engine hooks before plugin Load/version
checks, so the loader must gain a pre-hook build/hash/map gate before deployment.
Required file: `kcd_addresslib_steam_release_1_5-15693.bin`. No matching public release
was found in either repository. No loader or unverified offset was installed.

## Official development game and live tests

The official tools game1.5.5 is distinct from retail1.5.6. Original Lua module startup,
localhost1403 HTTP command/receipt, real menu camera sampling and real Minecraft
pose receipt were verified in its actual process. The user's later test also verified
loaded Trosky player/camera,1562 Minecraft poses and two actual block-event receipts.
The early menu run preceded the corrected camera-basis conversion and is not
orientation calibration. Current corrected basis is tested against known vectors.

A bare `map` command used as a probe attempted `nolevel`, which failed and stalled
the development process. This was an implementation mistake; no save was opened by
it. Logs were preserved before recovery of that owned test process. A subsequent
restart stopped at the launcher single-instance check and then closed. Do not assume
a launcher dialog is visible based only on a process and log entry.

Automatic approval review rejected the next explicit visible launch with
`-devmode +map trosecko`, reporting only **blocked by policy**. The action was not
performed or retried through another route. The user subsequently launched the
prepared helper successfully and provided a live frame. Further agent-controlled
launches had remained manual until the 2026-10-20 access check. In that check the
standard `Start-Kcd2ToolsTest.ps1` command succeeded under the current session
permissions, using the exact supported executable. Computer Use then brought the
game forward and captured its loaded test world. No permission settings were
changed. The historical denial is not evidence that every current launch is
blocked; evaluate the actual result and never work around a fresh denial.

Desktop input is not yet verified for autonomous gameplay. Computer Use accepted
Escape key dispatches, but no pause menu appeared in the subsequent captures.
The subsequent F8 attempt missed the guest's 60-second activation window by four
seconds, so it provides no evidence about F8 delivery. Alt+F4 did close the owned
KCD test window normally, with process absence confirmed.
In that access check, its documented interface lacked button-free relative mouse
movement and a configurable key-hold duration. Window access does not establish that
FPS aiming or all game controls work. Future automated input must be recorded as
Computer Use input, separately from human physical-input verification.

The 2026-10-28 Computer Use retry `8e968faa4bf340209f2c8b838d40de94` returned from
`@oai/sky` F8 and slot-2 key calls, but the bridge recorded neither: zero input
events, `host_armed=false`, and cancellation after the 60-second activation wait.
No movement began; Minecraft exited 0. There were 811 camera samples and no camera
read error, but no walking or side-face proof. Computer Use can close and relaunch
the test games; delivery of these gameplay keys remains unverified. The cause is
unknown, and successful tool calls alone do not establish input receipt.

Never load newer retail1.5.6 saves into this older1.5.5 development game. Backups of
982 existing save/profile files were copied and SHA256 verified before testing.

## Gameplay scope

- Optional `-ExtendedWalking` now passes live: 15 seconds of input plus settling,
  156/156 delayed native source readbacks, exact restoration and normal cleanup.
  The user reports "worked. still delay, but worked." Default short mode remains
  available. Start movement within 12 seconds of F8 and keep KCD foreground until
  the 30-second HUD ends; an early focus loss correctly aborts incomplete movement.
  Spatial/sampled-terrain limits and the 200 ms buffer remain. The distinct
  `Start-HudWalkingAimed.ps1` profile now verifies walking/aimed breaking together;
  simply enabling both older modes remains prohibited.
- The earlier-input repair and first-step descent fix now pass live in `b850ba...`:
  57/57 source readbacks, exact restoration and normal cleanup. The user confirms
  walking/HUD work with a little delay remaining. Accepted keys reach pre-vanilla
  bindings at median 0.1114 ms after receipt; producer capture-to-receipt is median
  16 ms. This is not native application/display latency. The 200 ms buffer remains.
  A freshly validated buffered anchor now supplies ground provenance for an
  immediate airborne descent, while stale/invalid anchors and legacy modes keep
  their guards. Earlier attempt `6cd20f...` rejected that transition; `4a7fb2...`
  never activated at all. Neither is a successful responsiveness measurement.
- The prior 27 October physical HUD run passes normal completion and cleanup:
  `650a8e00939c4831981f75828b79ff62`: 56/56 source readbacks, native `explicit_end`,
  exact origin restoration, cancelled timers, FPS restoration and normal Minecraft
  cleanup. All 588 camera publications are fresh. The user says "still delay,
  but smooth"; remaining responsiveness is the current issue. Earlier failed
  `fa370...` finish verification stays historical and unchanged in PROGRESS.
  Inventory was not opened in this latest run; its earlier proof is separate.
  The intentional 200 ms source buffer remains unchanged. First capture-to-dispatch
  is measured at 50 ms, later median 20 ms. Conditional clock estimates put first
  capture-to-native acceptance/write at 68.4/279.3 ms, versus 123.8/333.9 ms
  previously. No per-key/display timestamps are retained, so these are not
  key-to-photon measurements or proof that any one change caused the difference.
  Parser warmup, native finish and fixed 100 ms sampling are now exercised together
  in the passed physical run. Source capture intervals are median 100.38 ms/max
  133.98 ms; actual server-source gaps reach 151.43 ms. The sampler skips missed
  slots without backfill or timestamp changes. Its individual live contribution
  is not isolated by this comparison.
  This run needs 97.812 ms of right-point availability, but an earlier replay
  needs 188.903 ms. Reducing globally to 150 ms would underrun that earlier trace.
  Keep the smoother 200 ms baseline while measuring remaining latency or planning
  aimed-block integration. The optional longer mode above has separate fixed
  session budgets and retains freshness and spatial bounds.
  The previous buffered phase failure `d838...` is repaired: the latest combined
  trace passes two authoritative LANDING samples. Earlier independent fixtures
  passed but missed that brief transition; their claims remain narrower.
  Continuous, exclusive or unrestricted movement is not established. Boundary
  pauses require release and a fresh press without restarting the selected input
  window. Physical travel remains within the 2 m host sphere and -1.5 m/+1.5 m
  vertical envelope, with tighter Java prediction and sampled ground coverage.
  The lab allows one further second for settling. Camera delivery remains
  independent, uses original timestamps and stays within its 1,024-sample budget.

- The same Minecraft world now passes scripted walking/jumping/landing on a
  synthetic ground patch while capturing the HUD, followed by its inventory
  sequence. This standalone fixture makes no KCD calls and does not establish
  continuous shared movement or collision against placed Minecraft blocks.
- A separate coupled mode now uses fresh sampled KCD terrain and drives the
  bounded KCD follower from that HUD world's server positions. It passes 21
  delayed movement readbacks, player/camera restoration, the subsequent inventory
  sequence and frame-cap restoration. Its HUD is checked by the standalone native
  receiver; this earlier scripted mode does not exercise composition during
  movement or physical walking controls. Native KCD input and physics remain
  active in that mode.
- General input forwarding, full collision export, NPC/combat synchronization,
  mining terrain and persistence are not implemented.
- HUD selection and stone actions now share an actual Minecraft world in a
  standalone fixture. Placement requires selected stone and a closed inventory;
  client/server-confirmed placement and breaking pass in one fixed cell. This
  combined guest now has an explicit live relay controller; the user confirmed
  the HUD and stone appearance/removal together, with matching engine and cleanup
  receipts. Live arming still refuses fixture markers. General
  targeting and other block types remain unfinished. Physical world clicks and
  camera look subsequently passed in the fixed-cell live profile. The new
  aimed-stone component passes actual Minecraft raycast/action checks with synthetic
  host rays and now confirms one-click KCD crosshair breaking. Aimed placement on
  several faces and longer continuous sessions remain unverified in KCD.
- Physical W/Space/mouse forwarding and starting-camera alignment now pass in the
  isolated4×4m Minecraft lab. Fifteen delayed samples were discarded during the
  successful run; low-latency sustained control is not yet established. KCD still
  handles its own input/physics. That older input lab remains separate from the
  follower; the new bounded physical HUD profile uses its own capture and
  release guards rather than granting that lab movement authority.
- Read-only live inspection confirms `ActionMapManager.EnableActionFilter` is
  absent from the official1.5.5 Lua runtime despite documentation for it.
  `g_gameRules.game.FreezeInput` and `player.EnablePhysics` exist, but their prior
  state and reversible ownership remain unproved. The probe does not call them.
- An isolated real Minecraft lab now walks, jumps and lands against approximate
  slabs sampled from live KCD2 terrain, confirmed on client and server. It uses a
  static4×4m heightfield. A separate bounded follower now applies actual server
  poses to KCD2's player, with delayed player/camera readbacks and restoration
  verified in the live tools game. It does not forward KCD controls, handle
  buildings/walls/tunnels, or stream changing coverage. Native KCD physics remains
  active; this short probe does not prove sustained or exclusive movement authority.
- The final timed Lua observer captured real jump press callbacks while the
  player and view changed. Watched walking and mouse action names did not appear;
  no jump release was captured. The original callback restored correctly.
  This is partial input proof; a complete control bridge still needs a supported
  walking/mouse capture path, bindings and focus/menu/release handling.
- A separate Windows Raw Input helper and Java decoder/session gate now compile
  and pass focused checks. The actual OS lifecycle and historical recording pass
  with neutral data. A new isolated Minecraft lab also passes actual client/server
  walking, jumping, landing, view changes and neutral release using fresh scripted
  input and synthetic ground. Physical KCD key/mouse delivery subsequently passed;
  engine menu detection remains unverified. Its F8 latch is manual arming; explicit key mappings
  are supported but KCD's effective bindings are not discovered automatically.
  A read-only camera capture seeds Minecraft's initial view; the KCD capture and
  matching client/server angles passed in the physical two-game run.
  This is one starting snapshot, not sustained camera alignment.
  Minecraft uses its ordinary sensitivity/invert settings and refuses
  smooth-camera, spyglass and toggle-sprint modes. Native KCD input remains active;
  the new lab does not drive KCD or establish coupled movement authority.
  The Windows file reader requires hard-link support in local runtime/evidence
  because JDK21/24 returns a null public fileKey. A private identity link is checked
  with Files.isSameFile and removed on reader exit; unsupported storage fails closed.
- First interactive stone controls are compiled and live verified after the log
  framing fix. `minecome_place`/`minecome_break` request vanilla actions in one fixed
  cell of a new Creative lab, requiring optional protocol minor1/capability1. They
  do not select an arbitrary cell under the KCD crosshair or provide mouse/keyboard
  controls, inventory UI or survival gameplay. Request acceptance is dispatch only.
  Commands accumulated during a network/HTTP interruption are rejected and need
  to be entered again after recovery. An already-dispatched action cannot be recalled.
- Minecraft remains vanilla-authoritative in its isolated world. Only the opt-in
  coupled movement lab drives the KCD2 player through fresh server observations.
  Ordinary wire-v1 host state remains diagnostic; the lab trace is separate file IPC.
- Block changes are observed locally within four blocks at10Hz, not acknowledged
  authoritative world replication. Stone-only transient KCD creation/removal is
  implemented and live observed: the user confirmed that vanilla placement made
  stone appear in KCD2 and breaking made it disappear. Engine spawn and final cleanup
  receipts also passed. The original strict test rejected deferred removal before
  its later frame completed; the final live rerun now passes matching spawn,
  deferred removal and cleanup acknowledgements with zero replicas left.
  Registry replacement emits remove/add; property-only
  changes do not. World/dimension changes and overflow reset authentication/session.
  There is no initial-world snapshot, chunk streaming, general block renderer,
  world namespace or persistent resync in wirev1.
- The new sink has128 owned/pending entities,16-block MC anchor radius and32-unit
  KCD player radius. Physics is disabled. Without an exported ENTITY_FLAG_NO_SAVE,
  absence from user/automatic game saves cannot be guaranteed; use a fresh test map.
- Menu validity flags must not be treated as a player at0,0,0. No transform is marked
  calibrated. Provisional1block/unit and axis math require live measurements.
- Minecraft sends configured vertical FOV, excluding transient renderer modifiers.
- GPU-shared textures, host depth compositing and native dynamic block submission
  are future work. Bounded CPU shared-memory UI transport now passes with real
  Minecraft and a standalone receiver; the user also confirms live KCD2 HUD
  visibility and accepted GUI sizing. Optional whole-host-HUD suppression passes
  live setting/readback restoration; its combined visual result remains unverified.
  The official tool build ships D3D12, so Skyrim's D3D11 code cannot be used directly.
- Current local token authentication does not authenticate host identity or defend
  against an attacker who already has access to the user's files.
- Java stream writes lack a separate deadline. Networking runs on a daemon and
  shutdown closes the socket after its bounded join, so gameplay is unaffected;
  future movement/render authority must add deadline-aware output.

## Development/runtime observations

The 2026-10-12 official-tools launches crashed during fresh-world loading both with
the new HUD renderer installed but unarmed and after the owned DXGI hook was
disabled. Both game logs end at `[MFX] Loading FXLib 'collisions' ...`; this is a
last observed log line, not an identified failing subsystem. No exception stack
or exit code was captured. ReShade's log did not change in the hook-disabled run.
The hook was disabled for the startup investigation. A separate confirmed add-on
reset-lifetime defect was fixed and tested offline; its relationship to the crashes
is unproven. The repaired build has since been installed and reached the world.
Genuine Minecraft-side hotbar and Creative screen capture passed; the user now
confirms the static HUD is visible inside KCD2. Continuous UI transport now passes
with real Minecraft and a standalone native receiver; a subsequent user report
also confirms the continuous HUD visible inside KCD2. Later physical 1/2/9 and
E/Escape checks verify slot selection and inventory opening/closing, with no KCD
menu reported. A later full 30-second live mouse run passed clicks, dragging and
scrolling, with user confirmation. The guest window reappeared during shutdown;
the hidden-through-exit repair now has live visibility/process-exit evidence in the
combined stone run. Faster inventory capture has automated evidence; inventory was
not opened in that run, so combined inventory smoothness remains unverified.
The subsequent bounded user-run diagnostic captured exit code 250 (`0x000000FA`)
after 28.462 seconds. Six complete module snapshots omitted ReShade and the add-on;
available system commit remained above 5.37 GB in all 28 memory samples. The meaning
of this exit code in the pinned game remains unresolved.
A later fresh run with the official empty mod list confirms `0 mods enabled` and
reproduces the same exit code during loading. The temporary list has been removed
after ownership verification, restoring the previous mod-loading setup. Neither
MineCome nor the pre-existing multiplayer mod is required to reproduce the failure.

The same zero-mod diagnostic subsequently reached the world when the user invoked
it through the bundled PowerShell 7.6.5 executable. The user confirmed world readiness;
the game survived the full two-minute monitor and its official Console API responded.
Use the working PowerShell 7 launch path. This outcome does not yet establish which
shell/environment difference caused the prior exits. A later user-started session
with the repaired hook enabled also reached the world. Its 40-second preview
submitted all three captured UI states and expired with the game still running.
The user's visual report confirms the HUD but does not separately confirm the
inventory snapshot or selected-slot transition.

The first visible HUD occupied only 1708×960 pixels within the 2560×1440 host
backbuffer: integer upscaling rounded the 854×480 source's fit factor from about
2.998 down to 2. The aspect-fit correction builds and passes 131 focused checks,
including that exact resolution regression. The continuous compositor includes
this correction. The subsequent oversized GUI report was resolved by the accepted
1280x720 capture at GUI scale 2, preserving full-canvas anchors. The zero-mod
comparison's owned empty mod-order file requires ownership-checked cleanup after
normal game closure when that comparison is complete.

The continuous lab is a 20-second scripted Creative UI sequence, not an interactive
inventory. Real Minecraft sent 344 nontransparent frames to the standalone native
receiver, which observed all four states, the intentional pause, freshness expiry,
resumption and closed marker. No KCD compositor was armed in that run. The native
add-on subsequently uploaded 200 fresh frames inside live KCD2, with user-confirmed
HUD visibility and clean stream closure. KCD's original HUD remains visible by
default. A later bounded optional whole-HUD hide passes live readback/restoration;
selective widget hiding and KCD health display integration remain unfinished.
The current walking observer disarms on buttons/wheel and the
movement lab rejects menus, so neither is an inventory input bridge.

Stream sessions have one immutable lease of at most 180 seconds and accept one
producer per process. Frames expire 500 ms after receiver observation; a busy GPU
upload slot drops updates without refreshing the resident image's age. ReShade's
public signal and semantic APIs can internally flush or wait, so this is not a
claim of a completely nonblocking render path. Expiry hides the layer; owned GPU
resources remain until safe runtime reset/unload cleanup. HDR, GPU sharing, held
hands, survival HUD coverage and crafting remain outside this lab. The separate
reverse-input fixture now performs real vanilla slot clicks and verifies a stack
swap on the integrated server. Its original keyboard-only live mode forwards 1-9, E and Escape
after an F8 latch, for at most 30 seconds. Physical KCD key blocking remains
unverified. ReShade's DirectInput8 polling path preserves mouse axes, so this mode
does not forward mouse input or claim camera suppression. The separate live mouse
profile now forwards actual inventory mouse actions with a bounded ownership lease;
general host input exclusivity and its final native drain remain unverified. Generic KCD menus and
cutscenes are not detected; this bounded check requires a fresh world with menus
and console closed. The original KCD HUD and health systems remain active.

The official tools EXE has translated FileVersion/ProductVersion1.5.5.0 but fixed
numeric version1.0.0.0. The native gate checks both, plus the expected distribution
path and actual running process image; checking only fixed1.5.5 incorrectly refused
the supported build before any stone writes.

The actual KCD Lua VM rounds numeric session IDs to float32 precision. Session and
sequence identifiers now cross the console boundary as validated canonical decimal
strings, stay textual in Lua, and return as exact JSON digits. The standalone Lua5.2
runtime uses doubles, so its numeric-ID tests alone did not reveal this engine behavior.
Minecraft cell coordinates are limited to±16,777,215 at this Lua boundary.

CryEngine entity deletion can complete on a later frame. `cleanup_pending` retains
ownership and the original removal event until absence is confirmed; it does not
count as a removal acknowledgement. Queued placements remain blocked and the native
two-second event deadline remains bounded.

While KCD2 is open, the test helper loads a read-only snapshot of the original
workspace Lua module through documented Script.LoadScript and requires a changed
function reference plus the expected token contract. The snapshot SHA must match
the workspace source SHA. The actual ReloadScript call left existing functions
unchanged, so each snapshot uses a fresh unique absolute path. The evidence records
these source hashes separately from the installed package. The open package is
replaced only after normal game closure.

Loom's first asset download failed with a duplicate asset hash lock. Copying relevant
content-addressed assets from the existing legitimate launcher cache into the local
Loom cache resolved it; original launcher files were unchanged. Java24 built and ran
Minecraft1.21.1 successfully but older LWJGL emitted a JNI compatibility warning;
ordinary authenticated play should use the discovered Java21 runtime. Builds stay
pinned to the tested JDK24/Gradle8.14.3 combination or explicitly validated Java21.

The first RC help probe wrote the compiler's own log in Tools/rc due its default
logprefix. Later conversions use explicit project-local log/output paths. No game
executable or base-data asset was overwritten. Generated proprietary textures/models
remain ignored user-local data and must not be included in public source packages.

On Windows, do not rebuild an executable while its test process is running. One
rebuild hit LNK1104 for that reason; rebuilding after normal host shutdown succeeded.
