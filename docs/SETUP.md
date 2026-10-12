# Reproducible Windows setup

Run commands from the MineCome directory in PowerShell 7 (installed here as 7.6.5).
The official-tools HTTP helpers require PowerShell 7. Paths in code are discovered
or supplied explicitly; the installed paths below are evidence from this computer.
No global installer or elevated dependency installation was needed.

## Discovered versions (2026-10-11)

| Component | Actual version/details |
|---|---|
| Windows | Windows11 Home x64, 10.0.26300 |
| Steam KCD2 retail | 1.5.6.0, Steam build23914554, assembly15693/release_1_5 |
| Official KCD2 tools game | Translated1.5.5.0, fixed version1.0.0.0, Steam build22816715, distinct engine ABI |
| Visual Studio used | 2022 Community17.14.37314.3, MSVC19.44.35227/v143 |
| Windows SDK selected | 10.0.28000.0 |
| CMake used | bundled3.31.6-msvc6; PATH had no cmake |
| Other VS | 2026 Community18.6.11822.322, bundled CMake4.2.3 |
| Java used for Fabric build/run | installed Oracle JDK24, bytecode release21 |
| Other Java | PATH26.0.2; launcher Java21.0.7 with javac also discovered |
| Minecraft chosen | 1.21.1, installed vanilla and Fabric profiles already existed |
| Fabric Loader/API | 0.16.14 / 0.116.17+1.21.1 |
| Yarn/Loom/Gradle | 1.21.1+build.3 / 1.10.5 / 8.14.3 |
| Graphics | RTX4070 Ti SUPER; official tools ships CryRenderD3D12.dll |

The inventory script writes actual executable hashes, manifests, tools and runtime
locations to ignored `runtime/environment.json`. It never reads launcher account tokens.

```powershell
.\tools\Discover-Environment.ps1 -IncludeHashes -OutputPath .\runtime\environment.json
.\scripts\Fetch-References.ps1
.\scripts\Init-Session.ps1
.\scripts\Build-Native.ps1
```

`Fetch-References` preserves existing mismatched source checkouts and fails rather
than resetting user changes. Only public source is downloaded. The default native
build uses the actual KCSE header if fetched, but does not install the KCSE loader.
To build just independent core/host, use `-Kcse Off`. Native outputs include:

```text
build/native/Release/minecome_host.exe               synthetic host
build/native/kcd2/Release/MineCome.dll               real KCSE adapter, undeployed
build/native/kcd2/Release/minecome_tools_host.exe    official debug HTTP adapter
```

## Fabric and codec

Use an installed compatible JDK, discovered by inventory. The tested JDK24 build
uses a workspace-local Gradle cache and the checked-in checksum-verified wrapper:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-24' # discovered on this machine
$env:GRADLE_USER_HOME = Join-Path $PWD 'minecraft/.gradle-user-home'
Push-Location minecraft
.\gradlew.bat --no-daemon build
Pop-Location
.\protocol\java\build-test.ps1 -JavaHome $env:JAVA_HOME
node .\tests\integration.mjs
```

The integration test uses port38770, an actual Java codec peer and
explicit synthetic C++/Node peers; it does not launch games. Node is already installed.
Fabric output: `minecraft/build/libs/minecome-fabric-0.1.0.jar` (not the sources JAR).

For a real isolated development Minecraft process, first start a host. In another
PowerShell window:

```powershell
Push-Location minecraft
.\gradlew.bat --no-daemon runClient `
  -PminecomeTokenFile="$((Resolve-Path '../config/bridge.token').Path)" `
  -PminecomeExportStone
Pop-Location
```

Minecraft saves/options/logs stay under `minecraft/run`. This is the standard Loom
development client named MineComeLab; it is not an authenticated launcher account.
It is used only for local single-player development. The normal launcher instance
and existing `.minecraft/saves` are untouched. For real account play later, use a
separate authenticated Fabric1.21.1 instance with the jar and Fabric API, and pass
`-Dminecome.tokenFile=<absolute token path>`. Account sign-in must be done by you.

Opt-in `-PminecomeSmokeWorld` creates a new uniquely named flat Creative world through
vanilla APIs, tests real placement/breaking and normal save/shutdown. It never uses an
existing world name. Read minecraft/README.md for current flags and emitted evidence.
No smoke-world automation runs in normal play unless explicitly requested by property.

## Official KCD2 development route

Before any launch/deployment, back up saves:

```powershell
.\scripts\Backup-Saves.ps1
# GameRoot must come from Discover-Environment, not an assumed location.
.\scripts\Stage-LuaDiagnostics.ps1 -GameRoot '<discovered official tools root>'
```

The staging script creates only a separate `Mods/minecome` directory, original
manifest and uncompressed Lua `.pak`; it refuses to overwrite an existing mod.
The deployment record and hash are in `runtime/lua-deployment.json`. No original
executables/base scripts or mod_order file are overwritten. The source manifest
allows script diagnostics on1.5.5 and1.5.6; this is not native ABI compatibility.

Launch the discovered official tools `Bin/Win64ReleaseSteamLTO_DLL/KingdomCome.exe`
with its root working directory and `-devmode`. Let it reach its menu; confirm
`127.0.0.1:1403/api/System/Console?info` exposes ExecuteString. Do not open current
retail1.5.6 saves in this older development build. A world load and visual checks may
need human interaction because native desktop control is unavailable in this session.

```powershell
.\build\native\kcd2\Release\minecome_tools_host.exe `
  --home "$PWD" --game-log '<discovered tools root>/kcd.log' `
  --fov-unit radians --seconds 120
```

The adapter requires explicit FOV units, requests `MineCome.SamplePose()` at5Hz and
parses fresh log lines. Default behavior withholds world poses until the player exists.
`--camera-only` allows menu-camera diagnostics, clearly marked camera-only. It confirms
actual Minecraft messages in the game log through `MineCome.Ping`. HTTP failure ends
the relay and closes TCP; Minecraft continues vanilla behavior and retries.

Do not send a bare `map` as a help probe: it tries loading a map. Only use an explicit
documented map name after confirming tools readiness. Do not kill unrelated games or
open a second test game while one is still running.

## Retail native route is gated

Do not copy a loader into the retail install yet. Required map:
`KCSE/addresslib/kcd_addresslib_steam_release_1_5-15693.bin`.
It must be generated/validated for the precise installed WHGame.dll; its file hashes
are in environment.json. Obtain a verified map and pre-hook loader compatibility gate,
then repeat the DLL ABI/network tests before game deployment. An existing compiled
MineCome.dll is not evidence of a working retail mod.

Session environment for the future native deployment is `MINECOME_HOME=<absolute
project root>`, optional `MINECOME_TOKEN_FILE`, `MINECOME_LOG_FILE`, `MINECOME_PORT`.
Do not call bridge shutdown from DllMain: KCSE lacks an unload lifecycle event and
the adapter intentionally pins its module after initialization.

Generated game assets and backups stay local. Remove only the exact files recorded
for a MineCome deployment when uninstalling; preserve other mods and saves.

## Prepared block-display test

The local compiled Minecraft asset is already staged with our original Lua module
under the discovered official tools root's `Mods/minecome`. The updated deployment
fingerprint is in `runtime/lua-deployment.json`; the previous owned package was
preserved under `runtime/packages/previous-*` before updating it. Default staging
still refuses to overwrite an existing mod. To reproduce asset compilation/staging:

```powershell
.\tools\Convert-BlockAsset.ps1 -PythonPath '<installed Python executable>'
.\scripts\Stage-LuaDiagnostics.ps1 -GameRoot '<official tools root>' -UpdateOwned -WithBlockAssets
```

Close KCD2 normally before staging; the script refuses replacement while a KCD2
process exists. The user has now verified a visible block in the Trosky test world.
The latest texture revision isolates and enlarges the actual stone pixels without
interpolation to reduce the initial blur. The user has verified the sharpness fix
in a second live screenshot; its evidence record is referenced in PROGRESS.md.

The engine launch could not be performed automatically: approval review rejected
`-devmode +map trosecko` with only `blocked by policy`. The user subsequently ran
this helper successfully. Run it directly from the MineCome directory for a retest:

```powershell
.\scripts\Start-Kcd2ToolsTest.ps1
```

Once the development world has finished loading:

```powershell
.\kcd2\request-tools-diagnostic.ps1 -Action Pose
.\kcd2\request-tools-diagnostic.ps1 -Action ShowStone
# After visual inspection, before any save:
.\kcd2\request-tools-diagnostic.ps1 -Action RemoveStone
```

ShowStone requires a real player and camera. It loads the actual Minecraft-derived
CGF three units ahead of the camera with physics disabled and reports engine bounds.
Check the revised stone texture, parallax, size and occlusion in the game window.
Successful dispatch or bounds is insufficient to verify the new material's appearance.
Full procedure and limitations: `kcd2/TOOLS-TEST.md`. No native loader is installed.

The Python path above was returned by this session's bundled-runtime discovery;
Python3.12.14/Pillow12.3.0 were used successfully. Rediscover/select an existing
interpreter on another machine; this path is not hardcoded in converter source.

## Prepared dynamic stone test

Stone placement/removal now has an original Lua sink and acknowledged native consumer.
After the fresh development map has loaded, run PowerShell7 with
`scripts/Start-BlockMirrorTest.ps1`. It starts `minecome_tools_host --mirror-stone`
and a new UUID Minecraft lab automatically; KCD2 must already be running. The real
Minecraft client places stone after fresh KCD player/camera state, holds it15 seconds
after authoritative client/server verification, then breaks it. Switch focus back
to KCD2 and verify appearance/removal. The exact commands and expected engine receipts
are in `kcd2/TOOLS-TEST.md`. Standalone tests and real Minecraft tests passed; live
KCD placement/removal was confirmed by the user's observation. The helper also
checks matching engine Begin/spawn/removal/cleanup receipts; a pending deletion is
complete only after the entity disappears from the engine lookup. Shared movement,
calibration and persistence are outside this diagnostic implementation.

The helper makes a hash-checked read-only snapshot of the original workspace Lua
module and loads its unique absolute path through documented Script.LoadScript
while the game remains open. It verifies a new BeginBlockSession function reference
and the decimal_text_v1 contract, then records both source and snapshot hashes.
ReloadScript did not replace functions in the actual engine. The installed package
keeps its separately recorded hash. After
closing KCD2 normally, stage the current module for later launches:

```powershell
.\scripts\Stage-LuaDiagnostics.ps1 -GameRoot '<discovered official tools root>' -UpdateOwned -WithBlockAssets
```

Do not replace the open package; the staging guard refuses that operation.

## Interactive stone lab

The next build adds two console commands to the proven stone mirroring path. With
the official development forest/player world already loaded, run:

```powershell
.\scripts\Start-InteractiveStoneLab.ps1
```

Use PowerShell7. The helper creates a new isolated UUID Minecraft world, enables
minor1 stone input and waits for fresh state. When its console reports
`INTERACTIVE_STONE_LAB_READY`, return to KCD2. Open the game console with the usual
tilde/backtick key, enter `minecome_place`, close the console and inspect the stone.
Enter `minecome_break` to remove it. Allow each action to finish before repeating.
This first lab uses one fixed cell in reach of the Minecraft player; leave that
player at its spawn while trying the KCD commands. Placement uses the existing
session-local KCD display island.

Close Minecraft normally to finish. The helper requests graceful relay cleanup
through its own stop file and preserves logs in `runtime/evidence/interactive-stone-*`.
The default relay deadline is one hour; `-Seconds` can shorten it. The helper never
launches KCD2. Live execution of these commands now has matching real game receipts; the
earlier automatic appearance/removal test is separate proof. Full procedure:
`kcd2/TOOLS-TEST.md`. General blocks and persistence remain later milestones.

## Sampled-ground and coupled movement labs

With a fresh official development world already loaded, use PowerShell7 from
MineCome and stand still on gentle ground:

```powershell
.\scripts\Test-CoupledMovement.ps1
```

This creates an isolated Minecraft Adventure world, captures approximate KCD ground,
and checks vanilla walking, jumping and landing. Fresh server poses briefly move
KCD2's player; delayed player/camera receipts and starting-position restoration
must pass before success. Minecraft closes normally. To observe Minecraft without
moving KCD2, use `scripts/Start-GroundMovementLab.ps1` instead.

Full procedure and limits: `kcd2/MOVEMENT-LAB.md`. KCD keyboard/mouse forwarding,
streaming collision and sustained movement authority remain unfinished.
