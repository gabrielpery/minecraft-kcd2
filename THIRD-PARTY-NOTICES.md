# Third-party notices

MineCome's original source is GPL-3.0-or-later. The real KCSE API header used at build
time comes from JerryYOJ/libKCD2 (GPLv3); KCSE loader is also GPLv3. LICENSE contains
the unmodified GNU GPLv3 licence text. Their source references are pinned by
scripts/Fetch-References.ps1, retained in ignored external directories and not bundled
as a game-asset SDK. No loader or address-library binary is bundled.

SkyCraft (chasmlol, MIT) and Universal Modder (rehan-remade, MIT) informed architecture
through source inspection. No Skyrim engine bindings or their game assets are copied
into this project. Upstream commit details and author/source links are in research.

EldenCraft (SocketByte, MIT), pinned at ba7591cdde9fb16e17552cfe53546f44d0fd856e,
also informed the renderer-level HUD architecture. Its Elden Ring loader and game
bindings are not used. The original MineCome compositor builds against ReShade
6.8.0 public headers (crosire/reshade, BSD-3-Clause, copyright Patrick Mours), pinned
at 18deaa52de0c425a78b329e9cb3c497281cd00ec. The offline shader checker compiles
ReShade's effect compiler sources from that local checkout. Preserve ReShade's full
LICENSE.md with any redistributed runtime/compiler binary. SDK and runtime files
remain in ignored local directories; see docs/research/HUD-COMPOSITOR.md.

Fabric Loader, Fabric API, Yarn and Loom are retrieved from Fabric's Maven repository
as declared build/runtime dependencies under their respective licences. The Gradle
wrapper and distribution originate from Gradle (Apache-2.0), with a pinned distribution
checksum. Preserve dependency licence metadata when distributing a runtime package.

Minecraft code/assets and Kingdom Come assets/tools are proprietary and remain in
legitimate user-local installations/caches. Exported vanilla models/atlases, compiled
engine assets, isolated worlds and save backups are runtime test data only. They are
excluded from version control and distributable source archives.

The kcd2-mod-docs repository contains proprietary reference scripts, headers and
snapshots in addition to documentation. It is inspected locally, not redistributed.
Official tool use and any future mod package must follow the game's tool/asset terms.
Universal Modder's optional hosted fal MCP was inspected but not installed or used.
