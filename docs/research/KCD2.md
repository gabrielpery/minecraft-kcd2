# KCD2 integration research

Evidence collected on 2026-10-11. Source inspection is not a live-game test.

## Pinned source references

- [libKCD2](https://github.com/JerryYOJ/libKCD2/tree/10d20f28faba462c4bf98a01abb48225cc51bb91), commit `10d20f28faba462c4bf98a01abb48225cc51bb91`.
- [KCSE loader](https://github.com/JerryYOJ/KCSE-for-kcd2/tree/47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec), commit `47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec`.
- [kcd2-mod-docs](https://github.com/muyuanjin/kcd2-mod-docs/tree/9cb067543245ec5cf4e27b3d21e32485a35db518), commit `9cb067543245ec5cf4e27b3d21e32485a35db518`. Its official-wiki snapshot is dated 2026-06-23; its Lua binding archive is dated 2025-01-14.
- [Official modding overview](https://www.deepsilver.com/games/kingdom-come-deliverance-ii/news/modding-in-kingdom-come-deliverance-2), [official tools article](https://warhorse.youtrack.cloud/articles/KM-A-55/The-Modding-Tools), [official mod structure](https://warhorse.youtrack.cloud/articles/KM-A-3/Structure-of-a-Mod), [official Lua article](https://warhorse.youtrack.cloud/articles/KM-A-15/Modifying-LUA-entities-and-scripts). The live YouTrack pages returned no article text to the web reader, so their contents were checked in the named offline snapshot and against locally installed tools.

## Installed build and compatibility

Read-only inspection found the Steam retail game under `C:/Program Files (x86)/Steam/steamapps/common/KingdomComeDeliverance2`. `KingdomCome.exe` reports `1.5.6.0`; `system.cfg` has `wh_sys_version = "1.5.6"`. `whdlversions.json` reports Assembly ID `15693`, branch `release_1_5`, and the retail binary configuration `kcd2_release_1_5_PC_Publishing_MasterMasterSteamPGO_1308617_856`. Steam reports build `23914554`.

This matches the version and binary configuration named in libKCD2's `Offsets/vtables/ISystem.h`. It is useful evidence, but it does not independently validate reverse-engineered addresses. Before enabling engine calls, compare the local `WHGame.dll` with the precise binary used to generate the address library and verify expected code/layout fingerprints.

libKCD2's [README](https://github.com/JerryYOJ/libKCD2/blob/10d20f28faba462c4bf98a01abb48225cc51bb91/README.md) targets **1.5.6** and warns that CryEngine's interfuscator shuffles virtual function order. Public CryEngine headers cannot simply be used as the binary ABI. The library has version-specific `Offsets::` interfaces and separate concrete layouts. Many slots remain unnamed or tentative. Do not call unnamed `_vfN` slots.

The KCSE version integer is packed as `major << 24 | minor << 16 | patch << 8`; 1.5.6 is **0x01050600**, as implemented in [dllmain.cpp](https://github.com/JerryYOJ/KCSE-for-kcd2/blob/47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec/src/dllmain.cpp).

## Loader and the immediate blocker

KCSE is a `dinput8.dll` proxy beside the retail executable. Its [plugin scanner](https://github.com/JerryYOJ/KCSE-for-kcd2/blob/47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec/src/PluginManager.cpp) discovers DLLs in `mods/<modid>/KCSE/Plugins` and `KCSE/Plugins`, using the process working directory as the game root. It loads each DLL to inspect `KCSEPlugin_Version`, then invokes `KCSEPlugin_Load`.

The loader resolves engine addresses and installs hooks **before** plugin compatibility checks. A plugin guard therefore does not make an incompatible loader safe. The loader needs a pre-hook compatibility gate, including distribution, build, and matching address-library availability.

[REL::IDDatabase](https://github.com/JerryYOJ/libKCD2/blob/10d20f28faba462c4bf98a01abb48225cc51bb91/src/REL/IDDatabase.cpp) expects `KCSE/addresslib/kcd_addresslib_<distribution>_<build>.bin`. For this installation, its naming logic selects:

```text
KCSE/addresslib/kcd_addresslib_steam_release_1_5-15693.bin
```

The file is required even for Steam; there is no built-in identity mapping. Missing or invalid maps terminate the entire process. Neither pinned source tree contains `.bin` address libraries. Both GitHub [KCSE releases](https://github.com/JerryYOJ/KCSE-for-kcd2/releases) and [libKCD2 releases](https://github.com/JerryYOJ/libKCD2/releases) showed no published releases during inspection. No installed `KCSE` directory or `dinput8.dll` was found at the expected retail locations.

**Current conclusion:** compiling a real KCSE plugin is feasible; deploying this loader is blocked by the missing verified address library. Do not manufacture an identity table from comments or install the loader without this prerequisite. The source refers to an `analysis/addresslib` registry outside the published tree; obtaining the maintainer's complete mapping or generating and validating it against the local binary is a separate research task.

## Real KCSE APIs and threading

[KCSEAPI.h](https://github.com/JerryYOJ/libKCD2/blob/10d20f28faba462c4bf98a01abb48225cc51bb91/include/KCSE/KCSEAPI.h) exposes plugin metadata, `GetGameVersion()`, `GetKCSEVersion()`, lifecycle messaging, and a task queue. It does not expose a ready-made player, camera, input, collision, or renderer interface.

```cpp
#include "KCSE/KCSEAPI.h"

KCSE_PLUGIN_INFO("Example", "MineCome contributors", 1);
KCSE_PLUGIN_LOAD(kcse) {
    if (kcse->GetGameVersion() != 0x01050600) return false;
    auto* messaging = kcse->GetMessagingInterface();
    if (!messaging) return false;
    return messaging->RegisterListener([](KCSE::Message* message) {
        if (message->type == KCSE::IMessagingInterface::kMessage_DataLoaded) {
            // Engine data is ready; do not perform socket I/O here.
        }
    });
}
```

The metadata should also explicitly list the allowed game version and required KCSE interface version; the convenience metadata macro alone leaves those fields zero.

[TaskInterface.cpp](https://github.com/JerryYOJ/KCSE-for-kcd2/blob/47ff1bd75c4df4a3a2145e7ba9908d5b2e7f7aec/src/TaskInterface.cpp) uses a mutex to enqueue tasks and swaps them into a local queue after `CCryAction::PostUpdate`. A task can enqueue its next invocation for the following frame. Network work belongs on a separate thread; engine reads/writes belong in queued tasks. Bound queues and copy values rather than passing entity pointers between threads. The current API has no plugin unload/shutdown lifecycle message.

## Candidate engine paths, not yet verified live

| Capability | Actual published API evidence | Current limitation |
|---|---|---|
| In-game logging | `SSystemGlobalEnvironment::GetInstance()->pLog->LogAlways(...)`; see `Projects/ConsoleRpgParam/src/plugin.cpp` | Requires the verified global address and the 1.5.6 ILog ABI. File logging works without engine calls. |
| Camera | `env->pSystem->GetViewCamera()` in `Offsets/vtables/ISystem.h`; `CCamera::m_Matrix`, `GetViewdir()`, `GetFov()` in `crysystem/CCamera.h` | Version-specific matrix/layout. The copied CryEngine `CCamera` layout is explicitly different. Validate FOV meaning/units and projection live. |
| Player position | `CCryAction::GetInstance()->GetClientEntity()`, then `entity->GetWorldPos(out)`; used by `Projects/Navigation/src/FastTravel.cpp` | Requires map for the singleton and verified vtable slots. `SetWorldTM` is marked tentative; movement authority is not established. |
| Input | `Offsets::IInput::AddEventListener(void*)`, `PostInputEvent(const void*, bool)`, `EnableEventPosting(bool)` | Opaque event/listener ABI requires independent verification. Existing horse handling hooks are narrow gameplay modifications. |
| Physics | `gEnv->pPhysicalWorld` is documented; the project labels raycasting verified | No published complete `Offsets::IPhysicalWorld` declaration was found. Public `IPhysics.h` order is not a compatible ABI guarantee. Full terrain mesh export is not implemented. |
| Rendering | `Offsets::IRenderer` plus some projection/debug interfaces | The majority of slots are `_vfN`. No verified shared GPU texture, swap-chain, depth export, or generic render-mesh submission bridge exists. A class named `CD3D9Renderer` does not establish the runtime graphics API. |
| Damage/NPCs | Reverse-engineered combat/entity classes and a floating-damage example exist | Read/display hooks do not establish safe attacks, damage injection, animation reactions, or quest preservation. |

The present framework is an actively researched hobby project, with substantial layout evidence and examples, but it is not a stable complete engine SDK. Keep version-sensitive bindings behind one adapter. Reuse the available read paths only after their prerequisites are verified.

## Official tools alternative

The installed tools are under `C:/Program Files (x86)/Steam/steamapps/common/KCD2Mod`. The official tools article describes a separate development build, loose-file support, CryEngine Sandbox, Lua binding docs, and a debug HTTP server restricted to localhost on **port 1403**. Tools have a separate Steam app ID (`2429020`). They are not ABI-compatible evidence for retail native hooks.

The installed tools executable reports **1.5.5.0**, while retail reports **1.5.6.0**. The original Lua diagnostic manifest explicitly allows both versions because it uses documented script APIs; the KCSE DLL remains restricted to retail 1.5.6. Allowing a script package to load is not evidence that it has been verified in both games.

Locally installed `Data/Libs/CryHttp/player/variantsPlayer/index.html` demonstrates these actual endpoints:

```text
GET /api/rpg/SoulList/PlayerSoul/Position
GET /api/System/Console/ExecuteString?command=<URL-encoded console command>
GET /api?info
```

The shipped page uses `#System.SetCVar(...player:GetWorldDir()...)` through `ExecuteString` to read direction. The installed `static/apiBrowser.html` builds `<object>?info`, `<object>?depth=1`, and method URLs, receiving XML. Discover the live bindings with the browser before implementing assumptions about response shape or camera paths.

The archived official Lua binding pages document:

```lua
System.LogAlways("[MineCome] Lua initialized")
local cameraPosition = System.GetViewCameraPos()
local cameraForward = System.GetViewCameraDir()
local cameraUp = System.GetViewCameraUpDir()
local cameraFov = System.GetViewCameraFov()
```

These calls provide a viable diagnostic package and, through the **tools-only** HTTP console path, a potential first genuine two-process state bridge while the retail native loader is blocked. Raw values should be logged before assigning scale, rotation conventions, or FOV units. Do not claim that polling this debug API delivers the required retail native plugin or renderer.

The official packaging convention loads `scripts/mods/<modid>.lua` after `scripts/main.lua`; retail data must be in uncompressed ZIP `.pak` archives with `mod.manifest` alongside. `mod.manifest` supports exact game-version strings matching `wh_sys_version`. A `minecome` Lua package can initialize and export read-only diagnostic functions without replacing base-game scripts.

`Script.SetTimerForFunction(milliseconds, functionName)` is documented in the archived official binding page `CScriptBind_Script__SetTimerForFunction@IFunctionHandler__@int@char__.html`. MineCome uses it only when `MineCome.StartDiagnostics(200)` is invoked. Logging is capped at 5 Hz and `MineCome.StopDiagnostics()` stops rescheduling. `MineCome.SamplePose()` produces a finite-number JSON line beginning `[MineComePose]`, preserving camera basis and FOV as **raw uncalibrated values**. It includes the player position only if the `player` entity global exists. `MineCome.Ping("MINECOME_PING")` produces `[MineComePing] MINECOME_PING` as an observable receipt through the existing game log.

Retail Lua plus a log reader can supply one-way position export without native hooks. A complete bidirectional route still requires a verified method to invoke script functions from outside the process; the tools HTTP console endpoint supplies that route in the development build. No general Lua socket or file IPC API is assumed. The retail build has not been demonstrated to expose the HTTP server.

## Licensing and source handling

libKCD2 and KCSE declare GPLv3. Their header/runtime use requires preserving licence notices and applying compatible distribution terms; MineCome should not advertise a permissive-only native binary while incorporating their code. The fetched reference archive also contains proprietary game scripts, tables, and binary snapshots; keep `external/` out of distributable artifacts and version control. It is reference material, not a redistributable SDK. Inspect installed bindings and produce original integration code without copying game assets. Any public mod package must also respect the official tools EULA and game asset restrictions.

## Smallest honest milestones

1. Compile MineCome's version-gated KCSE DLL against the real published API, linked to its own engine-independent transport; prove handshake in a standalone host harness.
2. Build an original Lua diagnostic package using the documented logging/camera APIs. Verify initialization in the tools game or retail game only after normal mod staging is explicitly undertaken and saves are protected.
3. Use the official tools debug server to validate real position/direction exchange, discovering API bindings live.
4. Obtain a verified 1.5.6 Steam address map and safely gated KCSE loader; prove initialization, file and engine logs, then camera/player export in retail.
5. Establish the renderer/device/depth integration in a small independent prototype before claiming a Minecraft block can be composited into the game.

The first visible block remains unproven. Native geometry, colour/depth compositing and GPU texture sharing each need an actual CryEngine rendering path; IPC success alone does not satisfy that milestone.

## Implementation evidence from this session

- `kcd2/src/kcse_plugin.cpp` compiled into `build/native/kcd2/Release/MineCome.dll`, using the actual pinned KCSE header and MineCome's transport. It performs no engine pointer dereferences. It accepts `MINECOME_HOME` (workspace root), `MINECOME_TOKEN_FILE`, `MINECOME_LOG_FILE` and optional `MINECOME_PORT`. A successful load pins the plugin module so network code/callbacks cannot be unloaded accidentally; explicit `MineCome_Shutdown` stops the worker outside DllMain. There is no DllMain implementation or shutdown join under the loader lock.
- `kcse_adapter_abi_and_lifecycle` passed through CTest in 0.10 seconds: required exports and game restriction metadata, incompatible version rejection, malformed/out-of-range port rejection, missing credential rejection, real loopback server startup on a separate test port, lifecycle callback logging, and explicit shutdown bounded to two seconds. Load/Shutdown are serialized and module pinning precedes listener registration. This uses a standalone KCSE interface fixture, not the game or KCSE loader.
- `kcd2/package_lua.ps1` produced `build/packages/minecome/mod.manifest` and `data/minecome.pak`. The ZIP entry `scripts/mods/minecome.lua` has equal compressed/uncompressed sizes (3846 bytes at packaging time), matching the required stored ZIP convention. No game installation was modified by this packaging script.
- No native loader, address map, engine call, or visual Minecraft block has been verified by these compilation/package checks.

## Live official-tools evidence

The parent task backed up saves, staged the original Lua diagnostic mod in the official tools installation and launched its development executable with `-devmode` (PID 45180). The actual tools game served `http://127.0.0.1:1403/api?info` with a `wh::shared::GameInterface` XML object. `/api/System/Console?info` returned the `ExecuteString(command)` binding, plus `GetCvarValue(name)` and `GetCvarHelp(name)`.

The game log confirmed mod loading and `[MineCome] Lua diagnostic initialized`. Sending the documented HTTP console command `#System.LogAlways('[MineComePing] MINECOME_PING_LIVE_TOOLS')` produced that exact receipt in `kcd.log`. `#MineCome.SamplePose()` produced fresh camera position `(0,0,0)`, forward `(0,1,0)`, up `(0,0,1)`, raw FOV `1.30899704`, and **player:null**. `/api/rpg/SoulList/PlayerSoul/Position` returned 404 and `/api/LevelManager/CurrentLevelInfo?depth=1` returned an empty level object. This establishes in-process script initialization, an actual camera read and an external command/receipt; it does not establish a playable world or movement.

An original C++20 `minecome_tools_host` now connects the official tools HTTP route and fresh game-log samples to MineCome's existing TCP bridge. It disables proxy use, redirects and remote destinations, bounds response/log sizes, and caps sampling at 5 Hz. It explicitly requires FOV units on the command line. By default it withholds world POSE messages until a valid player position exists; optional camera-only diagnostics mark only the camera valid. Coordinate calibration remains false.

The parent task's live Minecraft run connected to this adapter. `runtime/logs/tools-live-evidence.log` captured actual game log receipts `[MineComePing] MC_CONNECTED_AUTHENTICATED` and `[MineComePing] MC_POSE_RECEIVED count=2`. This is a genuine two-process communication test using a real Minecraft process and a real KCD2 **development build at its menu**, with an external official-tools adapter. It is not proof of retail KCSE, world/player synchronization or Minecraft rendering.

The wire camera-local basis is +X right, +Y up, -Z forward. Conversion builds the camera-to-KCD matrix columns `(right, up, -forward)`, where `right = normalize(forward × up)`. A known-direction test verifies KCD forward +Y/up +Z gives a +90-degree X quaternion; the protocol's KCD-to-Minecraft basis conversion then gives the identity camera. A quarter-turn and explicit FOV-unit conversion are also tested. The corrected adapter and `tools_pose_and_camera_basis` test compiled; the latter passed in 0.03 seconds. An earlier menu communication run used the previous camera-basis implementation; because no player was available and world poses were withheld, it must not be cited as orientation calibration.

A no-argument console `map` probe was an implementation mistake: in this build it attempted to load `nolevel` instead of displaying help, logging a failed map load and an unattended-mode exit message. No save was loaded by this probe. The old process was closed, and its replacement later exited. A requested single visible official-tools launch with `-devmode +map trosecko` was rejected before execution by automatic approval review with only `blocked by policy`; it did not launch a process or dispatch a map command. There is no known remaining game process from this test.

The adapter now invalidates previously valid world poses with flags `0` when the player disappears, the HTTP route fails, or no fresh valid world sample arrives for one second. It retries temporary HTTP failures a bounded five times and then shuts down the bridge gracefully. Initial camera-only diagnostics cannot resume menu pose publication after a world has been observed. In the user's later live test, closing KCD2 produced HTTP-unavailable invalidation and bounded recovery shutdown in the preserved relay log. Player-loss/world-transition behavior remains separately untested.

## Prepared native entity diagnostic

The installed `Data/Scripts.pak` was inspected read-only. `Scripts/Entities/Physics/BasicEntity.lua` uses `Properties.object_Model`, calls `LoadObject(0, model)` and only physicalizes when `Properties.Physics.bPhysicalize` is true. `Scripts/Entities/AI/AISpawner.lua` demonstrates `System.SpawnEntity` with class/name/position, then `LoadObject` and `GetLocalBBox`. These are script bindings, independent of an unverified C++ vtable. The archived official binding pages document `System.SpawnEntity(params)`, `System.RemoveEntity(entityId)`, `Entity.LoadObject(slot, filename)`, `Entity.DrawSlot(slot, enable)` and `Entity.GetLocalBBox()`; see [the pinned generated binding archive](https://github.com/muyuanjin/kcd2-mod-docs/tree/9cb067543245ec5cf4e27b3d21e32485a35db518/script_bind_2025_01_14) and [Crytek's binding reference](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756813/pages/23306601).

The original `MineCome.ShowStone()` function now requests a temporary `BasicEntity` three units forward from the real camera, loads the Minecraft-export-derived `objects/minecome/stone.cgf`, enables its render slot and logs actual game bounds. It withholds spawning without a valid player/camera. Physics is disabled. `MineCome.RemoveStone()` requests removal of the exact named entity ID created by the script. Neither function is called automatically, and there are no save commands. The optional exported no-save constant is guarded; if unavailable the log explicitly requires removal before saving.

`kcd2/package_lua.ps1 -AssetDataDirectory runtime/compiled-block/Data` produced a local stored ZIP containing the original Lua script (7631 bytes), compiled CGF (2356 bytes), MTL (435 bytes) and actual Minecraft atlas DDS (2097288 bytes), with each entry's compressed size equal to its original size. Asset compiler/source/output hashes are preserved in `runtime/compiled-block/provenance.json`. This is package/compiler evidence, not a live draw. The explicit HTTP helpers and manual visual checks are documented in `kcd2/TOOLS-TEST.md`; no additional game deployment was performed by this subtask.

## Later user-run world verification

The user launched the prepared Trosky helper successfully on2026-10-11 and provided
a4480×1440 screenshot showing Minecraft stone inside KCD2's actual forest world.
Matching game logs record spawn position `(121.156029,2043.59424,57.8071404)`,
bounds `(0,-1,0)` to `(1,0,1)`, authenticated Minecraft connection and both block
events. The final relay summary is449 world/player samples,1562 Minecraft poses
and2 events. The Minecraft log confirms actual integrated-server/client placement,
breaking and normal shutdown. This establishes loaded-world exchange and a visible
asset; it does not establish continuous block replication, shared-texture rendering,
physics, depth/parallax calibration or retail native loading. The initial material
looked blurred; its current texture revision is described in `ASSET_PIPELINE.md`.
