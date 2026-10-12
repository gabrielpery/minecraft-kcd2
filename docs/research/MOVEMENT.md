# Minecraft movement authority and host collision: inspected targets

Research snapshot: 2026-10-11. This note identifies a possible implementation path; movement forwarding and KCD terrain collision are **not implemented or live verified**. The existing interactive stone lab remains separate. No game calls or builds were performed for this research.

MineCome pins Minecraft **1.21.1**, Yarn **1.21.1+build.3**, Fabric Loader **0.16.14**, and Fabric API **0.116.17+1.21.1**. No Minecraft source JAR was present in the Loom cache. Inspection therefore used the actual cached named bytecode with `javap -c -p`, cross-checked against the matching primary Yarn API documentation. Yarn names/documentation are not a substitute for an inspected method body.

## Exact 1.21.1 targets

| Target | Verified behavior and proposed use |
|---|---|
| `ClientPlayerEntity.input` | Public `Input` field. `ClientPlayerEntity.tickMovement()` calls `Input.tick(boolean,float)` and consumes movement axes, jumping and sneaking. An owned `Input` subclass is possible if explicit input ownership becomes necessary. |
| `KeyboardInput.tick(boolean,float)` | Reads `GameOptions.forwardKey`, `backKey`, `leftKey`, `rightKey`, `jumpKey`, and `sneakKey` through `KeyBinding.isPressed()`. Opposing directions cancel; vanilla applies the supplied slowdown factor. |
| `KeyBinding.setPressed(boolean)` | Public setter. The smallest movement-input bridge can set held states on `ClientTickEvents.START_CLIENT_TICK`; sprint additionally uses `GameOptions.sprintKey`, which `ClientPlayerEntity.tickMovement()` reads separately. |
| `Entity.move(MovementType,Vec3d)` | Uses the private `adjustMovementForCollisions(Vec3d)` path. That path collects block/entity/world-border collision shapes and applies vanilla movement and step handling. Let the existing tick call it; calling movement methods again would add an extra simulation step. |
| `BlockCollisionSpliterator.computeNext()` | Invokes `BlockState.getCollisionShape(BlockView,BlockPos,ShapeContext)` before offsetting the returned local shape into world coordinates. This is the verified candidate for merging bounded host shapes with vanilla shapes. |
| `ServerPlayerEntity.teleport(ServerWorld,double,double,double,float,float)` / `ServerPlayNetworkHandler.requestTeleport(double,double,double,float,float)` | Existing server-side teleport APIs for an explicit join/host-teleport handoff. Calls belong on the server thread. Normal vanilla teleport confirmation and an extension-level generation acknowledgement must be respected. |

Primary documentation: [Input](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/input/Input.html), [KeyboardInput](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/input/KeyboardInput.html), [ClientPlayerEntity](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/network/ClientPlayerEntity.html), [KeyBinding](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/client/option/KeyBinding.html), [Entity](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/entity/Entity.html), [BlockCollisionSpliterator](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/world/BlockCollisionSpliterator.html), [CollisionView](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/world/CollisionView.html), [ServerPlayerEntity](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/server/network/ServerPlayerEntity.html), [ServerPlayNetworkHandler](https://maven.fabricmc.net/docs/yarn-1.21.1+build.3/net/minecraft/server/network/ServerPlayNetworkHandler.html).

The collision invocation descriptor in the inspected constant pool is:

```text
Lnet/minecraft/block/BlockState;getCollisionShape(Lnet/minecraft/world/BlockView;Lnet/minecraft/util/math/BlockPos;Lnet/minecraft/block/ShapeContext;)Lnet/minecraft/util/shape/VoxelShape;
```

Important limit: `computeNext()` applies boundary filters and, when `forEntity` is true, a `shouldSuffocate` filter **before** that invocation. A shape wrapper alone does not cover every air-cell query. Movement, suffocation, ray picking, friction/support behavior and block placement support must be assessed separately. Collision on only the client is insufficient: the integrated server also validates movement.

## Reproducible inspection

Run from the MineCome repository root with the already installed JDK; these commands only read cached classes:

```powershell
$javap = 'C:/Program Files/Java/jdk-24/bin/javap.exe'
$cache = 'minecraft/.gradle-user-home/caches'
$namedJar = (Get-ChildItem "$cache/fabric-loom/minecraftMaven/net/minecraft/minecraft-merged" -Recurse -Filter '*.jar' | Select-Object -First 1).FullName
& $javap -classpath $namedJar -c -p net.minecraft.client.input.Input net.minecraft.client.input.KeyboardInput net.minecraft.client.network.ClientPlayerEntity
& $javap -classpath $namedJar -c -p net.minecraft.world.BlockCollisionSpliterator net.minecraft.world.CollisionView net.minecraft.entity.Entity
& $javap -classpath $namedJar -p net.minecraft.client.option.KeyBinding net.minecraft.server.network.ServerPlayerEntity net.minecraft.server.network.ServerPlayNetworkHandler
Get-FileHash -LiteralPath $namedJar -Algorithm SHA256
```

Inspected artifact identities, recording the local cache state rather than promising identical Loom output elsewhere:

- Named Minecraft artifact: `minecraft-merged-1.21.1-net.fabricmc.yarn.1_21_1.1.21.1+build.3-v2.jar`; SHA256 `06A137A0B9597798455412349A45255EE37F351CEAA37D731096880BE6C6A727`.
- Yarn mapping artifact: `net.fabricmc:yarn:1.21.1+build.3:v2`, cache directory `53c8c9729c0dd52e3549c04f16eca89a15818822`; SHA256 `4EC570889585CB958B7D3C9DD94CE4064B16AB797DFFEC152BC8486C59A4010B`.

## What the pinned SkyCraft establishes

Inspected commit: [`bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32`](https://github.com/chasmlol/SkyCraft/tree/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32). Its [InputBridge](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/InputBridge.java) replays host input through vanilla handlers and releases held input on loss. [BlockCollisionsMixin](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/main/java/dev/skycraft/mixin/BlockCollisionsMixin.java) merges host voxel shapes into block collision queries. [SkyClient](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/SkyClient.java) separates explicit teleport handoff from ongoing Minecraft movement, with collision epochs and teleport acknowledgements. Its triangle collider is a later, more complex option.

That pinned source targets **Minecraft 26.3**, Mojang-style names, SDL input, Loader **0.19.5** and Fabric API **0.161.0+26.3**. MineCome uses **1.21.1/Yarn/GLFW**. In particular, its SDL keyboard/mouse calls and newer collision invocation signatures cannot be copied into this project. These sources establish architecture, not compatible hooks or KCD APIs.

## Supported minimum architecture and next probe

The proposed authority split is: KCD supplies input/look and verified geometry; Minecraft computes feet position, velocity, jumping, ground state and collision response. Continuous host-to-Minecraft position copying would override that simulation. Initial anchoring and actual host teleports require explicit handoff.

A future negotiated extension needs world/transform identities, collision epochs, bounded geometry coverage, sequenced held-input state with a short lease and release-all, and authoritative Minecraft snapshots carrying tick/input acknowledgements and the installed collision epoch. The current 128-byte pose and stone requests do not provide this contract. Matching client/server geometry installation must be acknowledged before movement is enabled. Stale or missing coverage must revoke authority and preserve a safe hold; releasing keys alone does not stop gravity.

The next stage should be a **bounded probe**, in a new owned movement lab: install a small floor/wall proxy set, verify installation on both game threads, apply a short forward/jump input lease through vanilla, and record displacement, ground state, server corrections and stop behavior. A synthetic proxy validates the Minecraft hook only. Claiming actual host collision additionally requires verified KCD-derived geometry, measured axes/scale/feet alignment, and a real-world floor/wall comparison. Smooth slopes, general terrain streaming, ray picking, camera authority, KCD character-controller adoption and recovery across world changes remain separate requirements.
