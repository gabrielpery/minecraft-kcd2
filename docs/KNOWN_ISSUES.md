# Known issues and blockers

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
launches remain subject to the same review limitation.

Never load newer retail1.5.6 saves into this older1.5.5 development game. Backups of
982 existing save/profile files were copied and SHA256 verified before testing.

## Gameplay scope

- General input forwarding, full collision export, NPC/combat synchronization,
  mining terrain and persistence are not implemented.
- Physical W/Space/mouse forwarding and starting-camera alignment now pass in the
  isolated4×4m Minecraft lab. Fifteen delayed samples were discarded during the
  successful run; low-latency sustained control is not yet established. KCD still
  handles its own input/physics. The input lab must remain separate from the KCD
  player follower until exclusive control and engine menu state are established.
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
- Shared textures/frame synchronization, host depth compositing and native dynamic
  block submission are future work. Official tool build ships D3D12, so Skyrim's
  D3D11 render code cannot be used directly.
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
The hook remains disabled while startup is investigated. A separate confirmed
add-on reset-lifetime defect has been fixed and tested offline; that repaired build
is staged but not installed, and its relationship to the crashes is unproven.
No KCD HUD/inventory frame, continuous UI transport or inventory interaction has
been verified. Genuine Minecraft-side hotbar and Creative screen capture passed.
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
shell/environment difference caused the prior exits. The HUD hook is still disabled;
successful baseline loading does not verify the repaired compositor.

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
