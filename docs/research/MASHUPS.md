# Mashup research: source evidence and a route for MineCome

Research date: 2026-10-11 (Europe/London). This note records **source inspection**, upstream **creator reports**, and **proposals for MineCome** separately. Neither SkyCraft nor the GTA V example was built or run in this research task. Their screenshots, README claims, and field notes are not evidence that MineCome works in KCD2.

## Repositories and exact revisions

| Repository | Revision inspected | Local research checkout | License |
|---|---|---|---|
| [chasmlol/SkyCraft](https://github.com/chasmlol/SkyCraft) | `bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32` | `external/SkyCraft` | MIT, copyright 2026 chasmlol |
| [rehan-remade/universal-modder](https://github.com/rehan-remade/universal-modder) | `2c2201437ca676fb4e5f06a18fff6e8db99eef0f` | `external/universal-modder` | MIT, copyright 2026 Rehan and universal-modder contributors |

The checkouts were shallow clones of public source, used only as references. SkyCraft's CommonLibSSE-NG submodule was not fetched. No toolkit, game loader, hook, fal connection, or executable from these projects was installed or run. Commit-qualified links below remain useful if their default branches change.

## SkyCraft: the draft and the current implementation differ

The [design document](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/docs/DESIGN.md) is labelled draft v0.1, dated 2026-09-29. It proposes offscreen world colour/depth, GPU texture transport, frame lockstep, collision VoxelShapes, and separate slots for interiors. The current 0.1.2 source implements a different world rendering path: **Minecraft builds and exports meshes and an atlas; Skyrim draws them**. The design is useful for intent, but its proposed GPU frame transport must not be described as the implemented architecture.

### Fabric and build dependencies actually declared

The [Gradle properties](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/gradle.properties), [build script](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/build.gradle), and [wrapper configuration](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/gradle/wrapper/gradle-wrapper.properties) declare:

| Dependency | Declared value |
|---|---|
| Minecraft | 26.3 |
| Fabric Loader | 0.19.5 |
| Fabric API | 0.161.0+26.3 |
| Loom | 1.18-SNAPSHOT (moving dependency, not a reproducible release pin) |
| Gradle distribution | 9.7.1 |
| Java compile release / source / target | 25 |
| Mod version | 0.1.2 |
| JUnit BOM | 5.11.4 |
| e4mc | Runtime-only Modrinth artifact `AouleFRY`; build comment identifies 6.2.2 |

The [native CMake](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/CMakeLists.txt) requires CMake 3.25 and C++23, CommonLibSSE-NG, and D3D11/DXGI/D3DCompiler. Its [vcpkg manifest](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/vcpkg.json) lists DirectXMath, DirectXTK, fmt, nlohmann-json, rapidcsv, SimpleIni, spdlog, toml11, and xbyak, with no manifest baseline in that file. The README's Visual Studio 2026 and tested Skyrim runtime 1.7.104 are creator requirements/reports. These dependencies are **upstream's**, not the detected versions on this PC and not an automatic MineCome choice. MineCome should select a guest version supported by the locally available JDK and verified Fabric artifacts and then pin it separately. e4mc and upstream multiplayer are unnecessary for this offline project.

### Shared memory and lifecycle

The [protocol header](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/protocol/skycraft_protocol.h) is the C++ layout authority, mirrored by Java `Proto.java`. The name is `Local\SkyCraft_v1` but the current header protocol version is **11**, not 1. The header has magic `0x43594B53`, both PIDs, and heartbeats based on Win32 `GetTickCount64`. Coordinates on the wire are Minecraft block space unless explicitly stated. Struct sizes have C++ `static_assert`s. Multi-byte values are little-endian.

The mapping contains latest-value player/world/actor state using sequence counters, a 4096-entry input ring, a 512-entry guest event ring, a **32 MiB collision byte ring**, a **64 MiB render byte ring**, a table of up to 256 actors, and a three-slot RGBA overlay (maximum 3840 x 2160). The shared block is roughly 191 MiB with these maxima. It is not just a small position pipe. Ring fullness and retry paths matter when transferring geometry.

The [C++ link](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Link.cpp) creates pagefile-backed Win32 shared memory and supplies access rules for the current user/system/administrators at medium integrity. It reinitializes host-owned rings on restart; Java recognizes a changed host PID as a new generation and resends caches. C++ uses atomic references and acquire/release operations. [Java SkyLink](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/main/java/dev/skycraft/link/SkyLink.java) calls kernel32 using the Java foreign-function API, polls mapping discovery at most once per second, and uses VarHandles for acquire/release. Its heartbeat tolerance is 8 seconds to permit loading stalls; C++'s guest timeout is 3 seconds. Named events in the draft are not the communication path shown by these files.

Overlay ownership uses an atomic three-buffer exchange: each participant has a private front/back slot and exchanges a middle slot with a dirty flag. This differs from merely cycling three mutable buffers and hoping the reader finishes in time. The IPC layouts and game-specific payloads should remain separate in MineCome; host pointers, Skyrim FormIDs, and engine addresses have no valid meaning in KCD2.

### Coordinates, player and camera

Upstream maps Skyrim Z-up to Minecraft Y-up with `mc = (sky.x/70, sky.z/70, -sky.y/70)`, so one block is 70 Skyrim units. This is a Skyrim-specific calibration. **MineCome must measure CryEngine axes, metres-per-block, eye versus feet offsets, quaternion conventions, near/far planes, FOV convention, and runtime camera timing.** An initial configurable `host = origin + scale * (mc.x, -mc.z, mc.y)` is a coordinate hypothesis, not a verified KCD2 transform. A round-trip unit test proves algebra only. Runtime reference points and camera captures are required to prove the calibration.

[Game.cpp](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Game.cpp) carries substantial player-puppet and camera-specific work. State includes previous/current raw 20 Hz Minecraft positions, shared performance-counter timing, eye heights, bob phases, camera modes and distances. The host interpolates on its own frame clock. A post-camera hook compares candidate camera axes for 240 samples before accepting its orientation mapping. This is evidence that camera agreement is a measured integration problem, rather than a yaw sign copied from another engine.

MineCome should begin with KCD2 authoritative for movement/camera and only **read** its state, preserving ordinary play during the first rendering slice. Minecraft movement authority comes after host collision and safe handover are demonstrated. Retaining the real KCD2 player entity is needed for NPC targeting, location triggers and quests, but whether the controller can be safely disabled/puppeted remains a KCD2-specific research item.

### Collision: vanilla systems plus an actual custom triangle pass

[Collision.cpp](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Collision.cpp) inspects loaded Havok bodies and shapes, transforms/triangulates triangles, primitives and compressed collections, and sends triangles and voxel data. Its reverse-engineered Havok shape layout reads and units are Skyrim-specific. None may be moved to CryPhysics unchanged.

The common [BlockCollisionsMixin](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/main/java/dev/skycraft/mixin/BlockCollisionsMixin.java) appends host VoxelShapes to vanilla collision queries. **However**, the current local-player [EntityCollideMixin](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/mixin/EntityCollideMixin.java) modifies the return from vanilla `Entity.collide` through [SkyCollider](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/SkyCollider.java) and [TriCollider](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/main/java/dev/skycraft/world/TriCollider.java). This performs substepped horizontal sliding, slope/ground snapping and triangle collision, then queries Minecraft blocks again. It retains real Minecraft movement inputs, gravity and game logic but does not leave all collision resolution unchanged.

For an initial MineCome collision phase, prefer bounded AABB/VoxelShape proxies injected into **both client and integrated-server** collision queries so Minecraft resolves them. Raycast columns are an intermediate approximation that misses thin objects/overhangs; document that scope. Exact CryPhysics mesh export and continuous slopes are later work. Blocks also need collision in KCD2 for NPCs, independently of the player's collision in Minecraft.

### Actual world rendering

[WorldExporter.java](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/render/WorldExporter.java) queries Minecraft's block-state model set and calls Minecraft's `BlockModelRenderer.tesselateBlock`; fluids use the fluid renderer. It captures positions, atlas UVs, per-vertex colour, lighting and flags through its mesh builder. It sends changed section triangle lists, texture pixels/patches, selection boxes, light emitters and solidity/dig bitsets. Full rings cause dirty sections to be retried. This is a credible precedent for a block whose model and texture genuinely come from the running guest.

[SkyAtlas.java](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/render/SkyAtlas.java) builds an atlas from Minecraft's runtime resources and observes resource reloads/animated sprites. The assets need not be shipped with the mod.

[WorldRender.cpp](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/WorldRender.cpp) uploads geometry to D3D11 vertex buffers and draws with camera-relative host matrices, native depth, lighting, fog and captured sun shadow cascades. It has a host-world-render hook before post-processing plus a Present fallback. The call sites are Skyrim relocation IDs and validated call instructions. They are not portable CryEngine hooks. The source backs up/restores rendering state and has separate standard/reversed-Z depth states. Advanced lighting and shadow behavior are creator implementations not reproduced here.

[FrameExporter.java](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/FrameExporter.java) captures **hand, HUD and screens only** using three asynchronous GPU staging buffers, copies the newest completed result to shared CPU memory, and skips frames if all staging buffers are busy. [Overlay.cpp](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Overlay.cpp) uploads it to D3D11 and draws on the host back buffer. There is no basis here for claiming a proven zero-copy shared GPU world texture.

### Input and combat

The host captures input and arbitrates menus. [InputBridge.java](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/InputBridge.java) replays SDL scancodes and mouse/text events into Minecraft's keyboard/mouse handlers, with a virtual held-key state and explicit release-all behavior. This code targets 26.3's input APIs; earlier Minecraft versions require different adapters. World/server changes are scheduled to the integrated server instead of performed on the IPC/render thread.

Native actor records are mirrored as invisible Minecraft `LivingEntity` proxies (`SkyrimActorEntity`, `SkyCombat`). This allows Minecraft weapons and damage modifiers to run in Minecraft. Resulting hit events carry host actor IDs back; native combat, crime, hit reaction and death need engine-specific handlers. KCD2's combat/stamina/crime/quest rules cannot use Skyrim scaling or Skyrim damage calls. Initial MineCome must keep combat disabled until entity identity, damage ownership and destruction lifetime are explicit.

## Universal Modder: the GTA V frame route

The [example](https://github.com/rehan-remade/universal-modder/tree/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough) runs a real Fabric guest, with a ScriptHookV ASI state/control adapter and a ReShade add-on on the host. Unlike current SkyCraft, its world content is transported as **rendered colour and depth**, plus a separate hand/HUD overlay.

| Item | Actual declaration or creator report |
|---|---|
| Guest code pins | Minecraft 26.3, Loader 0.19.5, API 0.161.0+26.3, Loom 1.18-SNAPSHOT, Java 25 |
| WebSocket library | Java-WebSocket 1.6.0, included in the guest mod |
| Control listener | `127.0.0.1:25599`, configurable system property |
| Frame mapping | `Local\MCPassthroughFrame`, magic `0x5450434D`, version 1 |
| Frame slots | 3; each world RGBA8 + float32 depth + overlay RGBA8; maximum 3840 x 2160 allocation |
| Host API baseline | ReShade headers/runtime 6.8.0 |
| Creator's initial live test | GTA V Legacy Steam build 3889; ScriptHookV 3889.0; September 2026 |

These pins come from [guest build files](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/build.gradle) and the example README, not from a test of KCD2. The [field note](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/knowledge/games/gta-v/minecraft-passthrough.md) also reports a second Windows/AMD run on 2026-10-09 with JDK 25.0.4.1, VS 2022, Gradle 9.7.1 and resolved Loom 1.18.3. It limits that report: basic live connection/compositing was observed, but gameplay features were not individually retested and no recording was made.

### WebSocket and thread handover

[HostLink.java](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/HostLink.java) accepts JSON camera, ground, input, slot, viewport and command messages. It sends a hello with protocol version, mapping name and PID. Camera snapshots are immutable records published through a volatile reference; guest input is dispatched with `Minecraft.execute`, and server operations use a separate world bridge. The listener binds loopback and has no authentication token. MineCome should use a distinct port/session, bound payloads, explicit hello/capability negotiation, strict state machines, no unrestricted server-command relay, and a documented timeout.

[HostState.java](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/HostState.java) freezes the chosen pose once per render frame, times out after two seconds without camera data, and echoes the host frame number. GTA supplies player/camera authority during ordinary movement; Minecraft drives special elytra flight only. This is not a complete precedent for Minecraft-authoritative movement everywhere.

### CPU frame sharing and depth

[FrameExporter.java](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/FrameExporter.java) captures the world before the hand/HUD pass, clears colour for the overlay, and copies all layers asynchronously into GPU readback buffers. Completed layers, their camera, near/far planes, depth conventions and frame IDs are published together to a pagefile-backed Win32 mapping. It is **GPU readback, CPU shared-memory copy, host texture upload**, rather than GPU handle sharing. Three maximum-sized slots reserve about 285 MiB. At 1920 x 1080 the raw three-layer payload is 24,883,200 bytes per frame, about 1.49 GB/s at 60 frames/s **before additional copy/upload traffic**; this is arithmetic, not measured performance.

[GameRendererMixin.java](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/mixin/GameRendererMixin.java) suppresses sky and splits world/overlay capture. [GlCommandEncoderMixin.java](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/mc/src/client/java/dev/rehan/passthrough/client/mixin/GlCommandEncoderMixin.java) repairs an upstream 26.3 OpenGL read-buffer-state problem after depth readback. That repair is specific to the inspected guest backend/version and should not be blindly applied to another guest version.

[compositor.cpp](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/gta/src/compositor.cpp) discovers the mapping, uploads layer textures through ReShade, and maintains camera history. [MCPassthrough.fx](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/examples/minecraft-gta5-passthrough/gta/shaders/MCPassthrough.fx) linearizes both engines' depth before comparison and uses pose reprojection to hide guest delay. The initial GTA mapping is `(x,z+offset,-y)`, one metre per block; angle rules and host near/far defaults are GTA-specific. The compositor defaults to a pose lag of zero; the field note describes an earlier one-frame lead. Use the actual configured lag and capture evidence for KCD2 instead of trusting either value.

Frame relighting from blurred host pixels is an approximation. It cannot produce real CryEngine sun shadows on blocks. Late composition can occlude pixels but does not automatically insert guest depth into CryEngine's earlier particles, fog, AO, transparencies or TAA. Pose reprojection may create holes/disocclusion artifacts and cannot replace matching projection/coordinate calibration. Native scene insertion is preferable where its ABI and lifetime are proven.

### Useful development and verification tools

The example includes `host/fakehost.py` (synthetic geometry plus real guest frames), `gta/tests/fakegta.cpp` (a D3D11 reversed-Z host using the actual compositor), `gta/tests/ws_test.cpp`, block-placement and TNT scripts, plus a JSON director and recording pipeline. A protocol peer or D3D fixture is valuable before live testing, but it proves only the tested surface. The WebSocket check's substring match for `explosion` is insufficient as a semantic event oracle for MineCome.

Relevant toolkit commands are `um scan`, `um backup`, `um kb search`, `um win`, `um publish check`, and `um video`. These were inspected as tooling, not run here. Its [evidence guidance](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/knowledge/techniques/evidence-levels-for-mashup-claims.md) distinguishes reports, source reading, synthetic tests and live runs. Its [frame guidance](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/knowledge/techniques/frame-compositing-depth-and-pose-sync.md) identifies stale frames over host menus, depth cleared too early, MSAA resources, mismatched camera timing, invalid layer flags and sequence checks after upload as recurring problems. For MineCome, validate a bounded CPU snapshot before scheduling upload and discard stale frames/menu content explicitly.

## Codex integration: inspected, not installed

The [README](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/README.md) advertises `codex plugin marketplace add rehan-remade/universal-modder` followed by `codex plugin add universal-modder@universal-modder`. This is the repository's instruction, not a claim that the installed Codex CLI supports those commands. They were not executed.

The [.codex-plugin manifest](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/.codex-plugin/plugin.json) declares version 0.2.0, `./skills/`, and `./.mcp.json`. The clone also contains `.agents/skills`, `.codex/config.toml`, an agent guidance file, engine playbooks, and source examples. The MCP declaration connects to **hosted `https://mcp.fal.ai/mcp` with `FAL_KEY`**, not a local game integration service. It adds a remote asset-generation dependency, unnecessary for the Phase 1 IPC and Minecraft block milestone. No key was read or service contacted.

[pyproject.toml](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/pyproject.toml) declares Python >=3.10, Pillow >=10, NumPy >=1.24, PyYAML >=6, and the `um` entry point. `uv tool install git+...`/`pipx install` would install a package and dependencies. The clone's Bash launcher uses `uv run --project` when available, which may create a virtual environment/download dependencies on first use. Its checked-in SessionStart PATH hook is Claude-oriented and writes `CLAUDE_ENV_FILE`; the Codex manifest does not declare that hook, so Codex PATH behavior should be verified rather than assumed.

The [mashup-mods skill](https://github.com/rehan-remade/universal-modder/blob/2c2201437ca676fb4e5f06a18fff6e8db99eef0f/skills/mashup-mods/SKILL.md) and supporting notes were read directly as references. Their useful workflow is to specify ownership, units, lifecycle and fullness/timeout behavior before the first slice, then validate one real guest object against a host-only wall and light. Reading the clone gives these instructions and examples without changing global plugin/configuration state. The user's explicit instruction to run real Minecraft offline governs this task if generic toolkit wording about online-capable guest games would otherwise conflict.

## Recommended first architecture for KCD2

This section is an **engineering proposal inferred from inspected source**. It is not a proven KCD2 rendering solution.

1. **Build a transport-independent two-process core now.** A bounded, versioned loopback TCP stream or named pipe is simpler to debug than shared memory for hello/heartbeat/player/camera/basic events. Frame lengths, limits, sequence numbers, finite numeric validation, connection lifecycle and thread dispatch are mandatory. Use synthetic C++/Java peers to test fragmented/coalesced packets, mismatched versions, restart and disconnect. Add shared-memory mesh/atlas or frame channels only when bulk payloads justify them.
2. **Separate host loading from engine access.** A KCSE plugin can initialize and exchange diagnostics before it reads engine memory. `libKCD2` must be gated by the installed executable and WHGame module identity plus exact supported version/hash, not merely a DLL successfully loading. Its documented 1.5.6 target is not evidence of later-build compatibility. No Skyrim relocation IDs or shape layouts belong in MineCome. The KCD2 framework research note supplies its specific interfaces and limitations.
3. **Keep KCD2 authoritative for the first visible slice.** Read current host camera/player and advertise availability explicitly. The Fabric guest uses a separate offline single-player world/profile and produces a **Minecraft block model from Minecraft's runtime block renderer**. Export model vertices, UVs, colours, relevant texture pixels, Minecraft block-state ID and revision. There is no copyrighted atlas in the source/distribution.
4. **Preferred visual route: Minecraft mesh export and verified native scene drawing.** First prove a tiny native render fixture at a fixed player-relative anchor, then replace its placeholder with the guest-produced mesh/atlas. If CryEngine stat-object/render-mesh/material APIs can be correctly reconstructed for the verified build, let the engine handle native perspective/depth and eventually lighting. If only safe D3D11 frame access is available, draw the mesh with the actual host view/projection/depth and restore all GPU state. A generic host cube only proves the host draw seam; it is not the Minecraft block milestone.
5. **Fallback visual route: actual guest colour/depth compositing.** Build a small-resolution CPU shared-memory fixture first, with frame+pose atomic publication and stale-frame hiding. Use a ReShade add-on or supported render seam only after observing the actual KCD2 renderer, opaque depth, projection, MSAA, transparency and device-reset behavior. This avoids some CryEngine geometry ABI work but still needs real camera/world reading and depth validation. It does not solve NPC/world collision or movement authority.
6. **Defer GPU handle sharing until measured copy cost requires it.** Neither inspected bridge demonstrates it as the current world transport. [DXGI shared resources](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgiresource1-createsharedhandle) require correctly created shared resources and handle/lifetime management. [WGL_NV_DX_interop2](https://registry.khronos.org/OpenGL/extensions/NV/WGL_NV_DX_interop2.txt) is an optional extension with resource/device restrictions; its presence and a GL/D3D11 interop sample must be tested on this GPU. Vulkan external memory is relevant only if the selected Minecraft backend actually uses Vulkan. Shared colour texture alone does not solve depth-space conversion, synchronization, adapter matching or stale frames.

| Rendering route | Real Minecraft source of content | Main unresolved KCD2 dependency | First proof needed |
|---|---|---|---|
| CryEngine native mesh/material | Guest tessellator and runtime texture | Compatible render mesh/stat-object/material ABI, allocation/lifetime and game/render-thread scheduling | Host wall occludes guest block; material loads; no state/resource corruption |
| D3D11 mesh insertion | Same guest export | Verified scene pass, camera matrices, depth convention/resource, render-state restoration | World-fixed block during camera turn/strafe, native wall occlusion |
| Colour/depth CPU composite | Guest renderer frame | Camera sync plus readable host depth and compositing seam | Tagged guest block frame aligns/occludes with a host-only pillar |
| Shared GPU textures | Guest renderer frame | Above plus actual backend/driver interop and synchronization | Two-process colour/depth sample, timeout/restart/device-reset recovery |

The minimum credible live milestone requires logs from **both actual games**, a guest-produced block payload or frame, and a capture showing the block remains anchored while KCD2 camera/player move and a KCD2 wall hides it. A successful compiler, synthetic peer, generic cube or separate preview window does not meet it. Until a matching KCD2 engine adapter is demonstrated, advertise communication as transport-tested and rendering as blocked/pending, not in-game working.

## Licensing and asset handling

Both research repositories' top-level source is MIT; substantial copied code must retain copyright and permission notices. Copying a renamed helper still needs attribution. SkyCraft [third-party notices](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/THIRD-PARTY-NOTICES.md) identify CommonLibSSE-NG/spdlog/fmt/SimpleIni as MIT, xbyak as BSD-3-Clause, Fabric API as Apache-2.0, and its bundled Prism Launcher as GPL-3.0. Minecraft, Java, Fabric Loader, Skyrim, SKSE and address-library content are not included by that notice. MineCome does not need SkyCraft's launcher bundle.

Universal Modder's GTA example fetches ScriptHookV and ReShade rather than redistributing them; GTA native names/hashes come from the separately credited NativeDB. The example bundles Java-WebSocket 1.6.0 in its guest, so retain its separate upstream notices if reused. [ReShade 6.8.0](https://github.com/crosire/reshade/blob/v6.8.0/README.md) documents BSD-3-Clause overall with selected MIT dual-licensed files. Upstream license terms still need checking for each dependency/artifact before packaging; a project's MIT license does not grant rights to game assets, unrelated SDKs or bundled software.

Keep retail game assets in the user's game/launcher cache or ephemeral runtime IPC. Do not commit Minecraft/KCD2 jars, atlases, extracted/decompiled game source, copyrighted saves or SDKs with uncertain redistribution permission. Build the bridge source and converters; the user's owned games provide their own resources. Research checkouts and generated caches should be excluded from the MineCome distribution.
