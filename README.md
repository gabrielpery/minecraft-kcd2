# MineCome

**Minecraft × Kingdom Come: Deliverance II**

[![Platform: Windows x64](https://img.shields.io/badge/platform-Windows_x64-0078D4?style=flat)](docs/SETUP.md)
[![Status: experimental](https://img.shields.io/badge/status-experimental-orange?style=flat)](docs/PROGRESS.md)
[![Minecraft Java: 1.21.1](https://img.shields.io/badge/Minecraft_Java-1.21.1-62B47A?style=flat)](minecraft/gradle.properties)
[![Mod loader: Fabric](https://img.shields.io/badge/loader-Fabric-DBB790?style=flat)](minecraft/README.md)
[![KCD2 development build: 1.5.5](https://img.shields.io/badge/KCD2_dev-1.5.5-8A6D3B?style=flat)](kcd2/TOOLS-TEST.md)
[![Code license: GPL-3.0-or-later](https://img.shields.io/badge/code-GPL--3.0--or--later-brightgreen?style=flat)](LICENSE)

MineCome brings real Minecraft Java Edition gameplay and UI into KCD2. Minecraft
owns its blocks, inventory and interactions; KCD2 provides the host world. The
architecture draws on [SkyCraft and EldenCraft](docs/research/MASHUPS.md), including
capturing Minecraft's actual HUD and inventory pixels for display in the host renderer.

**Status: experimental development prototype.** Several bounded two-game tests
work, but this is not yet a complete playable mod or a ready-to-install release.
The public repository contains source, build scripts and development procedures.

## What works today

| Capability | Verified scope |
|---|---|
| Minecraft stone in KCD2 | Actual Minecraft-derived stone appears and disappears in the official KCD2 development world after vanilla placement/breaking. |
| Hotbar and Creative inventory | Minecraft's real UI is composited inside KCD2. Physical slot selection, inventory opening/closing, clicks, dragging and scrolling have passed live tests. |
| Camera and block controls together | KCD camera look works outside inventory and stays still inside it. Right-click/place and left-click/break work in one fixed nearby cell during a bounded live session. |
| Minecraft aiming | After fixing KCD's default stone rotation, a live right-click places on the original block's top face and the next two clicks break both blocks, with matching Minecraft/KCD records and user confirmation. The standalone actual-Minecraft lab passes 28 targeting/control scenarios with synthetic host rays, including hotbar changes while an action finishes. |
| Movement groundwork | In an automatic two-game test, KCD follows walking/jumping from the Minecraft HUD world over sampled KCD ground, then returns the player to the starting position. The same save completes its HUD/inventory sequence. This bounded scripted mode uses a standalone HUD receiver; continuous shared movement remains unfinished. |

A separate [physical HUD walking lab](kcd2/MOVEMENT-LAB.md#physical-walking-with-the-hud-in-kcd)
is implemented, compiled and checked automatically. The latest live attempt
records actual Minecraft walking, one applied KCD movement and restoration,
but camera freshness still ends the test before a complete pass. It adds
WASD/Space to the HUD session using sampled ground and fresh KCD camera direction.
Movement lasts at most six seconds, including neutral settling, inside the
30-second HUD check. The next work is reducing camera delivery delay.

Live checks above use the **official KCD2 1.5.5 development build**. The native
**retail 1.5.6 route remains blocked** by its verified address-library/loader
prerequisites. A successful development-world test does not establish retail support.

General block rendering, reliable aiming across block faces, continuous shared movement,
world persistence, survival integration and multiplayer remain unfinished. KCD's
own HUD and health systems still exist; selective widget replacement and showing
KCD health in Minecraft's HUD are separate work. Current sessions are isolated,
single-player development labs with explicit time and scope limits.

See [progress and evidence](docs/PROGRESS.md) for source/build/standalone/live
verification, including earlier failures, and [known issues](docs/KNOWN_ISSUES.md)
for current limitations. Evidence files, game assets and saves referenced there are
local test artifacts and are not included in a clone.

## Get the source

The repository is public. Cloning over HTTPS does not require a GitHub account or
private-repository access:

```powershell
git clone https://github.com/gabrielpery/minecraft-kcd2.git
Set-Location minecraft-kcd2
```

Follow [Windows setup](docs/SETUP.md) for prerequisites, environment discovery and
builds. The tested stack uses Windows x64, PowerShell 7, Visual Studio C++ tools,
Minecraft 1.21.1/Fabric and JDK 24. Build helpers also accept JDK 21; the automated
aiming lab currently requires JDK 24. No game, launcher account, SDK archive or
prebuilt game-ready package is supplied.

After installing the prerequisites, the source build starts with:

```powershell
.\tools\Discover-Environment.ps1 -IncludeHashes -OutputPath .\runtime\environment.json
.\scripts\Fetch-References.ps1
.\scripts\Init-Session.ps1
.\scripts\Build-Native.ps1
.\scripts\Build-Minecraft.ps1
```

These steps fetch pinned source dependencies, create a local bridge token, and
build/test the components. They do not install MineCome into a game. Game tests
require your own legitimate installations and separate test worlds. Back up saves
before deployment, and do not load newer retail saves in the older development game.

## Development guides

- [Setup and source builds](docs/SETUP.md)
- [Architecture](docs/ARCHITECTURE.md) and [wire protocol](protocol/PROTOCOL.md)
- [Standalone Minecraft aiming lab](minecraft/README.md#standalone-aimed-stone-lab)
- [Native-to-Minecraft aiming lab](minecraft/README.md#aimed-stone-network-lab)
- [Aimed controls and bounded live test](docs/research/AIMED-CONTROLS.md)
- [KCD stone display and console controls](kcd2/TOOLS-TEST.md)
- [HUD compositor and physical controls](docs/research/HUD-COMPOSITOR.md)
- [Automatic movement and HUD lab](minecraft/README.md#standalone-hud-ground-movement-lab)
- [HUD-world movement connected to KCD](minecraft/README.md#hud-world-coupled-movement-test)
- [Physical walking with the HUD in KCD](kcd2/MOVEMENT-LAB.md#physical-walking-with-the-hud-in-kcd)
- [Sampled-ground movement labs](kcd2/MOVEMENT-LAB.md)
- [Current progress](docs/PROGRESS.md) and [known issues](docs/KNOWN_ISSUES.md)

| Directory | Purpose |
|---|---|
| `kcd2/` | KCSE adapter, original Lua integration and official-tools host |
| `minecraft/` | Fabric mod, vanilla gameplay integration and isolated labs |
| `protocol/` | C++/Java codecs, coordinate math and transport contracts |
| `tools/` | Environment discovery, asset conversion and synthetic host tooling |
| `scripts/` | Dependency fetching, builds, deployment and bounded test controllers |
| `tests/` | Protocol, parser, lifecycle and cross-language checks |
| `docs/` | Architecture, setup, research and verification history |

Bug reports and contributions are welcome through
[GitHub issues](https://github.com/gabrielpery/minecraft-kcd2/issues) and pull
requests. Include the revision, exact game build, test procedure and relevant log
excerpt. Keep game assets, tokens, account data and saves out of submissions.
For code changes, read [the engineering rules](AGENTS.md) and distinguish automated
checks from observations in the actual games.

## License and credits

MineCome's original source is **GPL-3.0-or-later**; see [LICENSE](LICENSE).
[Third-party notices](THIRD-PARTY-NOTICES.md) cover KCSE/libKCD2, ReShade,
Fabric/Gradle and architectural references including SkyCraft and EldenCraft.
Dependency and game-asset licenses remain their own. Minecraft and KCD2 executables,
textures, models, saves, account credentials and proprietary SDK archives are not
distributed in this repository.
