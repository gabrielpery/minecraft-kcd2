# Official tools visual diagnostic

This route uses the installed KCD2 development build (1.5.5.0), its documented localhost HTTP console and an original Lua script. Retail 1.5.6 native loading is blocked by the missing exact KCSE address map. The user's test successfully loaded Trosky, exchanged actual player/camera messages with Minecraft, and displayed the Minecraft stone entity. The initial texture was blurred; a second live screenshot verifies crisp front and side faces after the texture revision.

## Package

From the MineCome project directory, after exporting Minecraft content and compiling it with `tools/Convert-BlockAsset.ps1`:

```powershell
.\kcd2\package_lua.ps1 -AssetDataDirectory .\runtime\compiled-block\Data
```

The resulting local-only package is `build/packages/minecome/mod.manifest` plus `data/minecome.pak`. The stored ZIP includes the original Lua script, the compiled `objects/minecome/stone.cgf`, its MTL and the Minecraft atlas DDS. Assets originate from the actual Minecraft exporter; their provenance is recorded in `runtime/compiled-block/provenance.json`. Do not publish game textures as part of a public package. This command only creates the package; deployment and save backups are separate steps.

## Run against the official development build

The game must be running normally and its `/api/System/Console?info` binding must be available on localhost port 1403. To request a fresh development map without opening newer retail saves, the documented CryEngine post-initialization command is `+map trosecko`, together with `-devmode` on the installed official tools executable. Use the tools root as its working directory. [Crytek documents the command-line syntax](https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1114113/pages/12746775). The user verified this route successfully on2026-10-11.

The native `--mirror-stone` gate verifies the running development executable's exact
path and observed version resource: fixed numeric version `1.0.0.0`, with both translated
FileVersion and ProductVersion strings `1.5.5.0`. It checks these before sending console
mutations. The retail 1.5.6 executable does not satisfy this gate. Simulated engine
fixtures require an explicit flag, a separate fixture log and a non1403 port.

The PowerShell request helpers require PowerShell 7 (installed locally as 7.6.5). They connect directly to `127.0.0.1`, disable proxies and redirects, require HTTP 200 and the Console `ExecuteString` binding, limit responses to 1 MiB and impose one deadline across response headers and body.

If a running tools game is already at its menu and the HTTP API is ready, use:

```powershell
.\kcd2\request-tools-map.ps1 -Map trosecko
.\kcd2\request-tools-diagnostic.ps1 -Action Ping
.\kcd2\request-tools-diagnostic.ps1 -Action Pose
```

Inspect fresh `kcd.log` output. A usable world sample has a non-null player position, finite camera vectors and a nonzero camera basis. A menu camera at `(0,0,0)` with `player:null` does not satisfy this prerequisite. Do not send a no-argument `map`: in the installed build it attempts `nolevel` and fails. Do not load existing retail 1.5.6 saves into the older tools executable.

## Explicit temporary entity

Once a world is loaded, invoke:

```powershell
.\kcd2\request-tools-diagnostic.ps1 -Action ShowStone
```

`MineCome.ShowStone()` creates a `BasicEntity` three world units along the actual camera direction, requests `objects/minecome/stone.cgf` in slot 0 and enables drawing. Physics is disabled because this compiled asset has no physics proxy. It logs the actual local bounds returned by the game. A successful dispatch or nonzero bounds does not prove that the entity reached a visible frame.

Check the live KCD2 view for the actual Minecraft stone texture, correct face UVs, about one-metre bounds, and normal depth occlusion against KCD2 geometry. Move the camera to check parallax. Preserve a live frame and the corresponding fresh `[MineComeVisual]` log line before claiming the visual milestone. This is an asset-import test; it does not establish shared-texture/depth compositing or continuous block streaming.

Remove the entity explicitly before any save:

```powershell
.\kcd2\request-tools-diagnostic.ps1 -Action RemoveStone
```

The script uses an exported no-save flag only if the game actually supplies it. It makes no save calls and never spawns automatically. Entity cleanup only removes the named entity whose ID was created by this script.

## HTTP helper regression

```powershell
node .\kcd2\tests\tools_http_test_server.mjs (Get-Command pwsh).Source
```

This test launches an original local HTTP test double and a PowerShell test process. It passed without launching either game: valid status/body and command encoding, missing-capability rejection, non-200/redirect rejection, fixed-length and chunked response limits, and a 300 ms absolute body deadline (observed 311 ms). A distinct loopback observer received zero redirect or proxy requests, including with proxy environment variables set. These checks verify helper behavior; they do not establish a loaded KCD2 world or visible entity.

## Pose relay

```powershell
.\build\native\kcd2\Release\minecome_tools_host.exe `
  --home (Get-Location).Path `
  --game-log 'C:\Program Files (x86)\Steam\steamapps\common\KCD2Mod\kcd.log' `
  --fov-unit radians --seconds 120
```

The host requires `config/bridge.token` and caps sampling at 5 Hz. It publishes world poses only after fresh valid player samples. After a valid world disappears or stops producing fresh samples for one second, it clears every validity flag; it also clears flags on HTTP failure and shuts down after bounded recovery attempts. Optional `--camera-only` diagnostics are limited to the initial menu state, before any world is observed. Coordinate calibration remains false.

## New stone placement/removal test

The owned mod includes the original bounded Lua stone sink. In the earlier live run,
the user confirmed that the real stone appeared in KCD2 and disappeared after the
15-second hold. The strict native summary was `placed=1 removed=0 cleanup_ack=true`:
deferred engine deletion first returned `cleanup_pending`, which that revision
treated as an error. Human visual confirmation and session cleanup are valid evidence,
but did not prove an individual removal acknowledgement. The final repeat with
updated deferred-ACK handling passed: exact session1791734901712424 acknowledged
spawn119, remove442 pending→removed, and cleanup with zero owned/pending entities.
The native summary is `placed=1 removed=1 rejected=0 cleanup_ack=true`; Minecraft
saved and exited0. Evidence is `runtime/evidence/block-mirror-20261011-170737`.
The ShowStone screenshot remains separate static asset evidence; human observation
of dynamic appearance/removal is attached only to the earlier165548 run.

1. Run `scripts/Start-Kcd2ToolsTest.ps1` from MineCome and wait for the forest/player
   view in the fresh Trosky map. Keep the camera roughly horizontal. Use this test
   session without loading retail saves. ShowStone is unnecessary for this test.
2. Run PowerShell7 (the locally bundled interpreter is shown below), then execute
   `scripts/Start-BlockMirrorTest.ps1`. The helper requires the already-running
   official1.5.5.0 world, checks both staged fingerprints and the debug binding,
   loads a hash-checked snapshot of the original workspace Lua module, and verifies a fresh function/contract
   marker. It prepares Minecraft classes before starting the native host deadline,
   waits for a fresh KCD player receipt, and launches a new isolated Minecraft lab.
3. Return focus to KCD2. Once both players are valid, Minecraft waits6 seconds,
   places real stone, and verifies its client and integrated server. The KCD entity
   should appear roughly4 units in front of the initial camera. Minecraft holds
   the confirmed block15 seconds, then breaks it. Verify the KCD block disappears.
4. Compare against real terrain for depth/parallax and capture a live frame during
   the hold. Evidence goes to `runtime/evidence/block-mirror-<timestamp>`; look for
   `STONE_BEGIN_ACK`, `STONE_ENGINE_ACK ... result=spawned`, the matching removal
   receipt, and `STONE_CLEANUP_ACK`. `STONE_REMOVAL_PENDING` is intermediate: Lua must
   later report `removed` with the same session/sequence after confirmed absence.
   HTTP200 and Java socket writes alone are not ACKs. The helper also requires this
   invocation's `VANILLA_SMOKE_PASS`, without `VANILLA_SMOKE_FAIL`.
5. Minecraft exits/saves its isolated UUID lab normally. The relay clears its session
   on disconnect; the helper requests graceful stop through its own stop file.
   The relay also has a180-second deadline. Wait for cleanup before leaving the test
   map. No game save commands are sent; no-save is requested only when the engine
   exports that binding, so do not assume these entities are excluded from every save.

From the project folder in PowerShell7:

```powershell
.\scripts\Start-Kcd2ToolsTest.ps1
# After the forest/player view loads, in the same PowerShell window:
.\scripts\Start-BlockMirrorTest.ps1
```

While KCD2 is open, the helper copies only the original workspace Lua to a unique
read-only `runtime/hotload/<timestamp-GUID>/minecome.lua` snapshot. It verifies the
snapshot/source hashes match, then calls documented `Script.LoadScript` on this
fresh absolute path. The actual tools build's old-path `ReloadScript` probe left
the function unchanged, so that probe is not used as proof of reevaluation. The
helper compares previous/new `MineCome.BeginBlockSession` references without clearing
ownership or timer state. Only a changed function plus the expected contract produces
the fresh `[MineComeTokenContract] decimal_text_v1 function_reload_verified` marker;
a failed load stops the test before Minecraft starts. `run.json` records
`LoadedLuaSource`, `LoadedLuaSnapshot`, both matching hashes and
`FunctionReloadVerified` separately from the installed package's fingerprint. The
game retains its older open package and assets; close it normally before using the
owned staging script to update that package.

Session and sequence IDs are passed to Lua as quoted canonical decimal strings,
because the live numeric boundary rounds like float32. Lua keeps them textual and
emits exact digits in JSON receipts. MC cell coordinates are limited to ±16777215.
An asynchronous removal stays owned and blocks later events until the matching
final receipt; missing confirmation ends the session, with cleanup still required.

The map uses a local translated display island, not shared movement calibration:
MC anchor is actual player position at the first event, KCD anchor is4 units along
horizontal camera forward at player Z, and cells map by `(x,-z,y)` at scale1.
CALIBRATED stays false. Only stone changes within16 blocks of that MC anchor are
accepted; Lua bounds entities to32 units from the KCD player and128 owned/pending
records. Physics is disabled. This is an observation feed with no initial snapshot,
chunk streaming or persistence. World/dimension changes and overflow reset the
authenticated session; cleanup failures retain ownership and block re-anchoring.

All seven native/Lua suites passed, including the original HTTP/engine fixture and
46 lifecycle cases in an existing Lua 5.2 library with simulated engine bindings.
To enable that optional Lua
test elsewhere, pass existing paths to `Build-Native.ps1 -TestPython ... -LuaLibrary ...`.
The actual Minecraft dynamic smoke also passed against the synthetic native peer;
these tests do not replace the live KCD display check.

## Interactive stone lab

This first control prototype is compiled and live verified after correcting how
the relay handles KCD's final unterminated log record. Real Minecraft client/server
and matching KCD receipts confirm placement/removal; the user confirmed seeing the
placed stone. No repeat of the static ShowStone test is needed for unchanged assets.

1. Start the official tools fresh world with `scripts/Start-Kcd2ToolsTest.ps1` and
   wait for the forest/player view. Use the test map without retail saves.
2. In PowerShell7 from MineCome, run `scripts/Start-InteractiveStoneLab.ps1`. It
   verifies the owned package and fresh Lua registration contract, starts the
   native `--interactive-stone` relay and a new UUID Creative Minecraft lab.
3. Wait for `INTERACTIVE_STONE_LAB_READY` in the launch terminal. Return to KCD2,
   open its console with the usual tilde/backtick key, enter `minecome_place` and
   close the console. The first lab targets one fixed cell near Minecraft spawn;
   it uses the established local display alignment rather than the KCD crosshair.
4. After the stone appears, enter `minecome_break`. Wait for removal before trying
   another placement. Keep the Minecraft player near its spawn during this lab.
5. Close Minecraft normally. The owning helper requests native shutdown and cleanup
   without stopping KCD2. Wait for `STONE_CLEANUP_ACK` before leaving the test map.

From the project folder in PowerShell7:

```powershell
.\scripts\Start-Kcd2ToolsTest.ps1
# After the forest/player view loads:
.\scripts\Start-InteractiveStoneLab.ps1
```

No action happens automatically. The original Lua commands only emit
`[MineComeInput]` intents with exact request digits and a250ms rate limit. The host
rejects replayed, stale or obsolete-generation log batches and requires fresh states
from both games plus negotiated minor1/capability1. Queued work is cancelled when
either session/world is lost. A sent action cannot be recalled; retry only after
the lab is ready again. Result1 in relay/Java logs means vanilla dispatch, while
`STONE_INPUT_VANILLA_CONFIRMED` records client/integrated-server state. KCD's separate
spawn/removal/cleanup receipts establish the display result. Visual observation
must still be recorded separately.

Evidence is `runtime/evidence/interactive-stone-<timestamp>` with fresh Minecraft,
relay and Lua reload logs. `InteractiveLabReady` alone is not a gameplay pass;
`EngineMirroringAcknowledged` requires matching spawn/removal/cleanup in one session.
`VisualVerified` defaults false. The relay has a one-hour default deadline and
gracefully stops after normal Minecraft exit. Arbitrary cell selection, movement,
collision, inventory/HUD and persistent blocks remain future work.

## Current launch limitation

The first tools process was closed after a failed `nolevel` probe. A replacement process subsequently exited. The later requested visible launch with `-devmode +map trosecko` was rejected before execution by automatic approval review, which reported only `blocked by policy`. The user subsequently ran the helper successfully. Further agent-controlled launches remain subject to review.

## Retest the sharper stone

The user has completed this retest successfully. The procedure remains available
for future revisions; distance, parallax and occlusion still need targeted checks.

The updated asset is already staged. Its source16×16 sprite was isolated from the
actual Minecraft atlas and each pixel repeated32×32 without interpolation. This
narrows smooth-sampling transitions while preserving pixel colours and original UV
insets. The material's point-filter hint alone may be ignored by stock Illum.

Restart the official development game with `scripts/Start-Kcd2ToolsTest.ps1`, wait
for the test world, then invoke ShowStone. Minecraft and the relay do not need to
run for this asset-only retest. Compare the same front face and a side face close
up; record a fresh screenshot. Check depth/parallax separately. RemoveStone before
saving/quitting. If softness remains, record the game graphics options and compare
stationary versus moving views before changing any settings.
