# Persistent gameplay session

This development path reuses one Minecraft world and keeps the HUD session alive
until explicit stop or loss of its peer. It has a separate protocol/profile from
the bounded movement labs. It is not yet the complete [product](PRODUCT.md).

The default save is
`runtime/gameplay/instance/saves/MineCome-Gameplay`. Its ownership marker holds a
stable world UUID. A new world starts in Creative, Normal difficulty, with commands
enabled and vanilla superflat ground. Reopening uses Minecraft's ordinary loader
and preserves its player state, inventory, game mode and game rules. An existing
unmarked or incomplete save is refused rather than adopted or reset.

**The superflat world is bootstrap ground, not imported KCD2 terrain.** The original
UI-only connected profile leaves walking with KCD2. A separate `-Movement` profile
now implements Minecraft-authoritative walking on captured host collision, with
KCD2's player and camera following actual Minecraft server observations. Scripted
Minecraft walking/resume and native sustained attachment/HUD pass; physical
walking in this new profile still needs acceptance. The `-Blocks` profile extends
it with persistent owned stones and a native mirror. `-Explore` adds on-demand
terrain tiles and persists the admitted coverage, using the same blocks bundle.
The separate `-Chat` profile adds Minecraft's real chat editor and commands to
walking and blocks; it can also be combined with `-Explore`.
The additional `-Flight`, `-Hands` and `-WorldBlocks` profiles described below add
Creative flight, first-person hands/items, a bounded palette of Minecraft models
and native perspective control with Steve. Unrestricted blocks, cross-game
health/combat and Elytra remain unfinished. Existing bounded gameplay labs remain
separate.

## Run the standalone guest

From the repository root on the configured development machine:

```powershell
& './scripts/Start-GameplayGuest.ps1'
```

This requires the built gameplay stream receiver and the installed JDK 24. The
script automatically selects existing PowerShell 7 when invoked from Windows
PowerShell 5.1. It does not install runtimes or require administrator mode. See
[setup](SETUP.md) for a machine that has not been configured.

Minecraft opens its own window with normal Minecraft controls. Chat/commands such
as `/gamemode survival`, `/gamemode creative` and `/give` are ordinary Minecraft
commands in that window. This entry does not connect to or launch KCD2.

Close Minecraft normally to save. Running the same command again reopens the same
world. Keep the terminal open until normal shutdown completes. Each launch creates
separate evidence under `runtime/evidence/gameplay-*`; evidence directories are not
the persistent world. The printed `stop_file` can also request a normal stop.

## Connect the sustained HUD to KCD2

The UI-only connected entry requires the v5 gameplay bundle and its matching
native component (input protocol 3, stream protocol 3). Older bounded HUD bundles
cannot read this protocol. Stage a fresh bundle and install it only while KCD2 is
closed:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

After the fresh official tools world has fully loaded, run:

```powershell
& './scripts/Start-GameplaySession.ps1' -BundleDirectory $bundle
```

The installer/launcher check the exact supported Steam official-tools 1.5.5 image
and prepared bundle. This is not a retail KCSE release. The session launcher expects
KCD2 already open and preserves its process; it starts the persistent Minecraft
guest and arms the dedicated gameplay HUD.

Focus KCD2 with controls released. Activation is automatic, with no F8 countdown.
The connected controls currently cover hotbar selection and inventory input.
**F8 stops and saves**; it is not the activation key for this profile. The terminal
also prints a session stop-file path. KCD2 remains running after the guest stops.
The finite outer identity lifetime is 24 hours; short frame/input freshness checks
still stop control forwarding promptly on peer loss.

This native profile currently accepts one session per KCD2 process; restart the
test world for the next connected launch. The Minecraft save survives. After
closing KCD2, `Install-GameplayHud.ps1 -BundleDirectory $bundle -Restore` restores
the previous renderer files. A restored bundle is immutable evidence; choose a
fresh bundle directory to install again.

UI-only connected startup, automatic input arming and sustained native composition
passed an automatic 40-second KCD2 check (host launched at 60 FPS). The hotbar was
visible in a captured KCD2 frame; 733 frames uploaded, zero drops, normal stop/save and input
cleanup passed. Receipt:
`runtime/evidence/gameplay-kcd-20261105-171621-b063422fa5d64d6fa67539bff318d787/verification.json`.
No input events were recorded, so inventory-control acceptance in this new profile
is still pending. This does not establish Minecraft-driven movement.

## Connect sustained walking and the HUD

`-Movement` selects a separate input-protocol-4 profile and matching native add-on;
its HUD stream still uses protocol 3. The UI-only protocol-3 bundle above cannot
be used for this entry. With KCD2 closed, run these commands from the repository
root. These scripts use existing PowerShell 7 automatically where required; no
administrator mode or additional runtime setup is needed on the configured
development machine.

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-movement-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -Movement -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -Movement -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

Once the fresh tools world loads, keep the player still and run:

```powershell
& './scripts/Start-GameplaySession.ps1' -Movement -BundleDirectory $bundle
```

The first attachment automatically captures a 9×9 grid covering one 8×8 metre
terrain patch around the KCD2 player. It copies that patch and its host-coordinate
origin into the owned Minecraft save. The first Minecraft position is placed on
the captured ground. Reopening uses the same patch bytes and world UUID, then
restores the last clean grounded position after both collision threads attach;
it does not reset inventory, health, hunger, game mode or abilities. The terrain
shapes are ephemeral collision only: their imported cells remain actual air and
are not written as blocks into the save.

Focus KCD2 with controls released to arm automatically. WASD and Space feed
Minecraft's vanilla movement alongside hotbar selection and inventory controls.
Movement is suppressed while inventory is open. There is no F8 start countdown,
15-second walking cutoff, or timed return to the starting point. F8 requests the
normal stop/save. Loss of fresh input or camera observations releases movement
controls; the captured boundary pauses movement before uncaptured terrain. This
is a sustained session on one fixed patch, **not continuous free roaming**.
Creative and Elytra flight are not connected in this profile; activating flight
pauses forwarded walking without changing the saved abilities. It also does not
yet connect block placement/breaking or command typing from KCD2.

Only one connected session is accepted per KCD2 process. Restart the tools world
before another connected launch; the owned Minecraft world and terrain mapping
survive. To restore the preceding renderer installation after closing KCD2:

```powershell
& './scripts/Install-GameplayHud.ps1' -Movement -BundleDirectory $bundle -Restore
```

A restored bundle remains immutable evidence; prepare a new bundle directory
before reinstalling. The profile is restricted to the exact official Steam tools
1.5.5 executable, as with the UI-only entry.

## Connect sustained building, walking and the HUD

`-Blocks` implies `-Movement` and selects input protocol 5. Use it consistently
when preparing, installing, starting and restoring its separate native bundle:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-blocks-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -Blocks -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -Blocks -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

After the fresh tools world loads, keep the player still and run:

```powershell
& './scripts/Start-GameplaySession.ps1' -Blocks -BundleDirectory $bundle
```

Activation is automatic. In a new Creative world, use E to select stone from the
normal inventory. Right-click places held stone on sampled ground or an owned
stone face; left-click mines owned stone. In Survival, placement consumes the
held stack and mining requires holding attack for the vanilla tool/break time;
releasing early cancels it. Native camera look remains active
outside inventory. Inventory mouse clicks are separate from world clicks, and
opening inventory releases world actions and movement. F8 stops and saves.

Placement and breaking use actual vanilla interaction packets and server-confirmed
block states. The session does not seed a demo cube or replenish inventory. Up to
64 owned stone blocks can persist within the captured 8×8m patch, Y56–80 in the
mapped Minecraft coordinates. Imported terrain remains temporary collision rather
than saved blocks. Placing the first stone occupies the air cell containing the
native terrain hit; sloping ground can partially cover that cube. Native terrain
mining and other block types are not implemented here.

`minecome-blocks.json` inside the owned save records construction ownership and
the exact terrain binding. Normal stop preserves Minecraft construction and
removes only the session's native display entities. Reopening reconciles that
ledger against the actual server world and republishes the remaining stones.
An expired native heartbeat also removes those owned display entities.

This profile retains the movement bounds and one-session-per-KCD-process
limitation described above. Use `-Explore` below to grow beyond the initial patch.
After closing KCD2, restore with:

```powershell
& './scripts/Install-GameplayHud.ps1' -Blocks -BundleDirectory $bundle -Restore
```

The paired automatic check runs actual Minecraft twice with scripted controls:

```powershell
& './scripts/Test-GameplayBlocks.ps1'
```

It verifies ground/top/side placement, breaking, walking, inventory suppression,
normal save/cleanup, then the same world's block, inventory and location on
reopen before breaking the retained block. This proves the Minecraft/controller
path; it does not claim physical KCD input or the complete product scope.

`Test-GameplayBlocksSurvival.ps1` runs a separate actual Minecraft check of
Survival placement consumption, early-release cancellation and held pickaxe
mining. It uses vanilla commands only to prepare its isolated fixture world;
command typing from the KCD2 window is still unfinished.

## Grow captured terrain during a session

`-Explore` implies both `-Blocks` and `-Movement`. It reuses the blocks native
bundle: input protocol 5 and HUD stream protocol 3. Prepare and install with
`-Blocks` as shown above; there is no separate Explore add-on or native rebuild.
If that matching bundle is already installed, keep using it. Once a fresh supported
KCD2 tools world is loaded, keep the player still and start:

```powershell
& './scripts/Start-GameplaySession.ps1' -Explore -BundleDirectory $bundle
```

Controls and stop/save behavior are unchanged. As the player approaches the
coverage frontier, the host requests neighbouring 8×8 metre terrain tiles on a
fixed grid around the original capture. Admission preserves the base coordinate
origin and requires matching shared edges. Both Minecraft collision threads and
the durable terrain cache must accept a tile before movement can enter it.
Unknown, steep or refused terrain remains a movement boundary; release movement
controls before trying an allowed direction after a boundary pause.

Coverage grows additively to at most **64 tiles including the base**, with tile
offsets limited to ±8 on either axis. Gaps and unadmitted corners remain closed.
The 64-stone capacity and mapped Minecraft Y56–80 limits remain, but owned blocks
may now occupy any admitted terrain cell. This is sampled terrain collision;
native buildings and other objects are not imported as full collision meshes.
There is no tile eviction or unlimited world streaming.

The owned save stores coverage in
`MineCome-Gameplay/minecome-terrain/coverage.json`, including the admitted tile
bytes, hashes and coverage identity. The base binding, saved player position and
block ledger retain the same coordinates. **Reopen an expanded world with
`-Explore` again.** Single-patch mode cannot restore the expanded coverage and
refuses saved positions or owned blocks beyond its original patch. The
one-session-per-KCD-process restriction still applies;
restart KCD2 before reconnecting and restore the installation with `-Blocks`.

The automatic check uses a separate owned instance and launches actual Minecraft
twice:

```powershell
& './scripts/Test-GameplayTerrain.ps1'
```

Passed receipt:
`runtime/evidence/gameplay-terrain-20261105-191017-ee2686489a414ba49e3ab306887d2b3e/verification.json`.
The first phase admits an east tile while walking, crosses the old X=4 boundary
to X=5.821, places two stones on new coverage, breaks the upper stone, suppresses
movement in inventory and resumes walking. It saves the player at X=5.179 and
retains the base stone at (7,64,0). The second phase restores both tiles, the player
and stone without a new admission, then walks again and breaks the retained stone.
Both launches save and clean up normally.

This proof uses explicitly synthetic terrain tiles and scripted input in actual
Minecraft. A separate live KCD2 capture check passes all 81 samples, shared-edge
validation, admission-file publication and native timer cleanup in 693ms:
`runtime/evidence/gameplay-terrain-capture-20261105-191937-77679be45b4d4619be9b208946fca580/verification.json`.
It uses a scripted frontier request without moving the native player or connecting
Minecraft. Coupled frontier-crossing and physical-control acceptance remain pending.

## Type Minecraft commands from KCD2

`-Chat` includes walking and blocks and selects input protocol 6. It uses a
separate native add-on with the existing pinned ReShade v5 proxy. The older
UI/movement/block profiles retain their input contracts. With KCD2 closed:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-chat-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -Chat -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -Chat -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

After the fresh tools world loads:

```powershell
& './scripts/Start-GameplaySession.ps1' -Chat -Explore -BundleDirectory $bundle
```

Activation is automatic. **T** opens Minecraft chat, **/** opens it with a slash,
**Enter** submits, and **Escape** cancels. These are actual vanilla `ChatScreen`
inputs, including its command parser, completion and history. Try
`/gamemode survival`, `/gamemode creative` or `/give @s minecraft:stone 64`.
Walking, mining and hotbar shortcuts pause while typing; held keys must be
released before they can resume gameplay. **F8 still stops and saves.**

This first chat path supports keyboard text and Backspace, Delete, arrows,
Home/End and Tab. It does not forward chat mouse clicks, clipboard shortcuts,
modifier-based selection, IME, dead-key composition or AltGr. Characters use the foreground keyboard
layout with Shift/Caps Lock; the protocol accepts Unicode scalars. Fresh release
edges recover short unmodified taps between frames. Injected Unicode/paste
packets are not an equivalent input test, and ambiguous modifier taps are ignored.

Commands execute normally in Minecraft, but they do not remove bridge limits:
terrain coverage, stone-only rendering and walking bounds still apply. Creative
flight requires the additional `-Flight` switch below. Elytra flight, teleporting
outside captured coverage, other dimensions and NPC combat are not connected by
the chat profile.

After stopping the session and closing KCD2, restore with the matching profile:

```powershell
& './scripts/Install-GameplayHud.ps1' -Chat -BundleDirectory $bundle -Restore
```

`Test-GameplayChat.ps1` automatically launches actual Minecraft twice. It passes
typed mode/item commands, Unicode editing, cancellation, invalid-command recovery,
movement suppression and resumed walking, then restores Survival mode, seven
stone and the saved player checkpoint on reopening. Receipt:
`runtime/evidence/gameplay-chat-20261105-194848-15b871e71c884ede940e105526e4f985/verification.json`.
This scripted UI check does not itself prove physical KCD keyboard capture.

A separate automated live KCD2 check used Computer Use key taps through the native
bridge to open `/`, type `/gamemode survival` and submit it. The integrated server
confirmed Survival, its feedback and hearts/hunger appeared in KCD2, and all 21
native events were acknowledged. The 206-second session saved and cleaned up
normally. Evidence and observation scope:
`runtime/evidence/gameplay-kcd-20261105-201229-cf98ac724f5f4ce2a7b84e588b1f4bee/chat-observation.json`.
This proves that command path; it is not a human typing-speed or flight check.

## Minecraft world blocks

`-WorldBlocks` includes `-Hands`, `-Flight`, `-Chat`, `-Blocks` and `-Movement`,
and combines with `-Explore`. It uses the same native Chat/Flight bundle. The
guest renders owned blocks with Minecraft's actual baked block-state models and
textures, aligned to the captured KCD camera position, basis and vertical FOV.
This profile disables the older native stone-only mirror to avoid double rendering.

Looking at an owned block within reach draws Minecraft's black selection outline.
The border follows the actual block outline shape and uses the same native ray,
reach, ownership and obstruction checks as mining. Camera projection and target
come from one sample. Inventory/chat, hidden HUD, stale aim and a
closer native obstruction suppress it. It shares the models' depth buffer, but
does not add KCD scenery depth to the transparent layer.

With KCD2 closed, prepare/install a fresh bundle and start the test world:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-world-blocks-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -WorldBlocks -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -WorldBlocks -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

Once the world has loaded:

```powershell
& './scripts/Start-GameplaySession.ps1' -WorldBlocks -Explore -BundleDirectory $bundle
```

Select a supported block from Creative inventory or obtain one through Minecraft
chat, for example `/give @s minecraft:oak_planks 64`. Right-click captured ground
or an owned block face to place; left-click to mine through the vanilla block
controller. Minecraft decides the placed state, including a log's axis. Block
identity and properties remain in the saved world and ownership ledger. Reopen
worlds containing these additional blocks with `-WorldBlocks`; the legacy stone
profile does not adopt unsupported saved states. Placement currently targets
captured terrain or owned blocks, not arbitrary KCD walls or other native objects.

The palette contains opaque full cubes: dirt/coarse dirt, common stone
and masonry variants, planks, ordinary and stripped logs, wool, concrete, mineral
blocks and obsidian. The exact list is in
[`GameplayBlocksPalette.java`](../minecraft/src/main/java/dev/minecome/gameplay/GameplayBlocksPalette.java).
It also includes 30 dry slab and 28 stair types across wood and masonry. Slabs
place in the upper/lower half and merge into double slabs; stairs use vanilla
facing, upside-down placement and inner/outer corner updates. Their model,
selection border and player collision use the actual shape. Standing support
and checkpoints use each collision box's height rather than the whole cell.
The ownership ledger retains neighbor-driven stair shapes across saves.
Dry connected blocks add 12 fence types (the eleven supported woods and nether
brick) and 10 masonry wall types. Vanilla updates their arms and wall posts when
neighbors change; the renderer, selection outline and saved ledger follow those
states. Their collision rises 1.5 blocks, including the portion above the visible
model. Fence gates, leads and NPC interaction are not included.
On captured ground, a short shape that would be buried is placed in the next
grid cell. This retains normal slab orientation and obstruction checks; the
block may sit above uneven ground because placement remains grid-aligned.
Fluids, waterlogged blocks, glass, leaves, other containers, redstone and other
blocks requiring transparency or additional behavior integration remain excluded.
The existing 64-block capacity, Minecraft Y56..80 bounds and captured-terrain
coverage remain. The new rendering layer does not create native KCD physics for
NPCs; Minecraft supplies the player's owned-block collision.

`./scripts/Test-GameplayShapes.ps1` runs an isolated Minecraft save twice. Real
chat items and controller clicks verify bottom/top slabs, same-cell merging,
stair facing, a neighbor-driven corner and its restoration after mining. It
checks client/server collision volumes and support heights, thirteen actual model/
outline PNGs, exact saved states and mining after reopening. A fractional-height
terrain case verifies that a buried slab moves up one cell, remains targetable
with the terrain obstruction check, and can be mined. Final evidence:
`runtime/evidence/gameplay-shapes-20261106-141741-e1dac345d69a466abfab38b4408ec546/verification.json`.
Collision queries are verified; this fixture does not walk the player on stairs.
The initial native KCD2 check observed one rendered half slab and exposed that
terrain case. A later automated KCD2 check placed above ground, merged and mined
the slab with the depth pass active. Native stairs, walking over partial shapes
and precisely isolated top-face merge input remain unverified.

`./scripts/Test-GameplayConnectedBlocks.ps1` places oak fences and cobblestone
walls through the actual controller, verifies reciprocal connections and removal,
checks ten model/outline images, then reopens the save and mines both remaining
posts. It validates all 22 registry IDs and 1,812 dry state combinations. Evidence:
`runtime/evidence/gameplay-connected-20261106-163159-b21f62d6c2cb471caeb7be0fcdedb051/verification.json`.

`./scripts/Test-GameplayShapeWalking.ps1` uses ordinary movement keys on actual
controller-placed blocks. Both client and server step onto a bottom slab, onto
a stair, back down to ground, and stop at a fence. A normal jump cannot cross
the fence; inventory W input leaves the player still on the stair. No fixture
position, velocity or block-state writes are used. This is automated Minecraft
acceptance with the world/HUD layer active, not native KCD walking acceptance.
Evidence: `runtime/evidence/gameplay-shape-walking-20261106-163317-1ae31f8068074029892b6de9bb052720/verification.json`.

World blocks use the aspect-fit compositor and a normal 20 FPS capture cadence.
A newly verified native camera can trigger capture after 25ms; repeated camera
samples retain the 50ms interval. Capture always preserves the camera's original
timestamp and exact rendered view. The
WorldBlocks profile now sends separate world colour, raw depth and foreground
hands/UI planes in schema3 format2; install the newly pinned Chat compositor and
shader together with the updated client. Older flat profiles remain format1.
World blocks depth-test against one another and the same
captured heightfield slabs used for player collision. The terrain pass writes
only depth, before block models and outlines; the hand pass clears depth again
so the actual hands and HUD remain visible. The immutable surface updates with
admitted terrain coverage. This is finite sampled-ground occlusion, not the
native scene depth buffer. An unsampled ground area or native object can still
be drawn behind a Minecraft block. Minecraft supplies model lighting; native
lighting/shadows and unrestricted building remain unfinished. Steve uses this
same world/depth layer in the perspective modes described below.

The native shader can additionally compare world depth with ReShade's selected
KCD2 depth buffer, leaving hands/UI untouched. It requires the exact executable
and proxy, reflected camera/projection constants, matching live camera and depth
source/backup identity. KCD2 uses DXIL, so reflection uses its hash-pinned shipped
compiler and actual remapped bindings rather than assuming the source register.
Unavailable or mismatched metadata leaves sampled ground as the fallback. Live
ordering is verified with a controlled opaque KCD object in front of and behind
a six-block Minecraft wall, including removal restoring the wall. Hands/HUD
remain foreground. This does not establish all foliage, transparent materials
or NPC cases. `Prepare-NativeDepthFixture.ps1` creates the isolated test save
through a vanilla load datapack; its seeded blocks are not placement/input proof.

`./scripts/Test-GameplayDepth.ps1` checks the production depth pass in actual
Minecraft using controlled render-only terrain boxes. Seven fixed-camera PNGs
verify no terrain colour, complete and partial occlusion of an owned block and
outline, no change with farther terrain, restoration, and preserved hands/HUD.
Real chat supplies the stone; normal controller placement/mining and save cleanup
are checked. It does not claim native scene-depth extraction. Evidence:
`runtime/evidence/gameplay-depth-20261106-143024-ca082235a246425b9920b905365d7ccc/verification.json`.

An automated native KCD2 session also observed the old buried slab hidden while
it remained in the ledger, with hands/HUD visible. It removed that test slab by
local chat command, placed/merged the corrected above-ground slab and mined it,
then saved normally with no remaining owned blocks. This verifies the captured
heightfield pass, not arbitrary native scenery depth. Evidence:
`runtime/evidence/gameplay-kcd-20261106-144335-b4b5531b272a4935a9b5bf42a72a9ba2/terrain-depth-observation.json`.

`./scripts/Test-GameplayWorldBlocks.ps1` launches isolated actual Minecraft twice.
Real ChatScreen commands supply items, then controller clicks place dirt, planks,
bricks and a sideways oak log. Fourteen captured PNGs verify model pixels, clear
surroundings, inventory with the blocks behind it, hidden hands, and restored
hands after closing inventory. Identical-camera captures check actual border
pixels on the targeted log, stale/obstructed/out-of-range suppression and return
after inventory. Projected edge bands exclude the crosshair, hand and hotbar.
The second launch checks exact saved states,
including `axis=x`, and mines all four blocks. Both normal saves and collision/
ownership cleanup pass. Evidence:
`runtime/evidence/gameplay-world-blocks-20261106-133430-88e40d3dc1904018b8fe47635874d13b/verification.json`.

Separate automated live KCD2 checks placed dirt on captured ground and bricks
on its top face, with actual server confirmation and visible models. The first
inventory open exposed a 380ms publication gap and correctly stopped the session.
The native WorldBlocks path now prepares the actual inventory before announcing
readiness; the 250ms freshness limit remains unchanged. A fresh session restored
both saved blocks, opened/closed inventory without losing the layer, then removed
each block with one aimed click. Its 104-second run published 1,830 frames with
a maximum publication gap of 77.98ms and saved/cleaned up normally. Observation:
`runtime/evidence/gameplay-kcd-20261106-131615-e75830f6a946424d8b4b232771114561/world-blocks-observation.json`.
These checks do not establish host depth occlusion or repeat walking/flight
acceptance with the new world layer.

The selection outline also passed an automated KCD2 visual/input check: brick
ground placement showed black edges, inventory closed back to the outlined
block, and an aimed click mined it with the HUD still present. The 121-second
session saved normally (2,284 outline frames; maximum publication gap 82.144ms).
Evidence:
`runtime/evidence/gameplay-kcd-20261106-133803-f26019fca51046919afbbf81a40eb7dc/outline-observation.json`.

After stopping the session with F8 and closing KCD2:

```powershell
& './scripts/Install-GameplayHud.ps1' -WorldBlocks -BundleDirectory $bundle -Restore
```

## Player rendering and perspective

WorldBlocks uses the installed Minecraft classic wide Steve skin for the owned
player's body, first-person arms and inventory preview. The real vanilla player
renderer supplies equipment and limb animation. Body geometry joins the same
world/depth layer as owned blocks; hands and UI keep their separate foreground
layer. No skin or model assets are shipped in this repository.

The automated check runs in a new isolated save:

```powershell
& './scripts/Test-GameplayPlayer.ps1'
```

It exercises vanilla front/back cameras, armor and a held sword obtained through
actual chat commands, third-person walking, inventory suppression and return to
first person. Captures include separate world pixels and float-depth coverage.
This fixture verifies actual Minecraft rendering independently of the native
integration check below.
The passing run contains nine stages/18 PNGs, matching 1.2915m client/server
walking, animated limbs and camera follow:
`runtime/evidence/gameplay-player-20261106-190337-1d5bd07bc530461584c97e10925786ab/verification.json`.

The earlier native camera-only check used the documented `CryAction.SetViewCamera` and
`CryAction.ResetToNormalCamera` pair behind the existing exact-tools guard.
Back 0.25m/300ms and front 2.5m/1000ms probes passed camera readback, unchanged
player feet and restoration. Their receipts are under
`runtime/evidence/perspective-probe-20261106-185859-488f32f8b87542a89f4f7334c3cc3e5d`
and `runtime/evidence/perspective-probe-20261106-185915-1383a49e9aca47fab5e38ab2d389201b`.

Native sessions start in first person and restore the guest's prior perspective
afterward. The implemented WorldBlocks input path uses **F5** to request first
person → back → front → first person while inventory/chat are closed. Minecraft
changes perspective only after receiving the native camera acknowledgement;
holding F5 does not repeat or change the selected hotbar slot.

The WorldBlocks pose includes `perspective_request` 0/1/2. Aim schema 3 carries
separate player-eye interaction and displaced render-camera data, admitted as one
sample. Block reach remains measured from the eye while Steve, blocks and their
depth use the actual camera. See the [snapshot contract](../protocol/HUD_STREAM.md#gameplay-pose-and-camera-snapshots).
Native mouse look uses the player's independent head direction, so the displaced
camera does not feed its own previous view back into aiming. KCD's head-position
getter freezes during the override; the bridge therefore preserves the local
eye offset observed before takeover, rotates it with live yaw and translates it
with the actual native feet. The acknowledged camera follows walking as well as
mouse look. Block interactions retain eye-based reach while the body, blocks,
outline and scene depth use that render view.

The 2.5m orbit clips against both physical KCD scenery and owned Minecraft
blocks. On the server thread, the bridge extracts vanilla camera collision
shapes from confirmed blocks, including partial shapes and fence gaps. Native
code sweeps against their boxes with 0.12m clearance and a further 0.03m surface
margin. Geometry is bounded to the existing 64 owned blocks and 512 voxel boxes;
coordinates must be exactly representable in sixteenths, and each box axis must
span at most 2m. Packed snapshots are installed atomically in bounded chunks.
Every pose names its required geometry generation. Missing, incomplete or
superseded geometry collapses the orbit to the eye until the complete matching
set is installed; it never drops excess boxes to continue through a wall.
Selection additionally checks actual owned voxel shapes from the render camera
to the eye-ray hit. A nearer visible block rejects a hidden target; slab and
fence gaps remain usable. This visibility check does not extend reach and remains
separate from the camera collision sweep.

While a third-person view is active, the bridge suppresses Henry's slot-0 body
with the documented render-only `DrawSlot` binding. This owned WorldBlocks path
explicitly establishes a visible slot-0 baseline and restores it on first-person
return or session cleanup. It does not preserve arbitrary hidden slot flags set
by another mod: no slot draw-flag getter is available. The player entity and its
physics are not hidden or disabled. Camera release is checked against the current
native head view; body draw restoration is recorded separately from visual
acceptance.

An automated live KCD2 back-view session passes visible Steve, native mouse yaw
and pitch, one block placement, two mined blocks and clean camera/body
restoration:
`runtime/evidence/gameplay-kcd-20261108-115405-eeaa84ce4ed44b948e9fb9b8b0bb3e65`.
The next native session observed front-view mouse look and inventory look
suppression. Its first-person return reached native camera acknowledgement but
exposed a delayed log-flush timeout; the host now flushes while waiting for that
receipt. Evidence:
`runtime/evidence/gameplay-kcd-20261108-120524-886c73ecc4424c8cab9a3bab93d87985`.

The repaired native session completed first person → back → front → first
person, with a fresh schema-3 acknowledgement of mode 0 and visible Minecraft
hand, hotbar and crosshair afterward. It stopped normally with no host or guest
failure and restored the native camera/body:
`runtime/evidence/gameplay-kcd-20261108-121206-2ea48f96077f4763a45f489df5863e51`.
It was manually stopped after those observations at 226.9 seconds. The launcher's
verification failed only the requested 240-second duration assertion; the full
duration smoke remains incomplete.
The subsequent combined walking/collision check passes in live KCD2:
`runtime/evidence/gameplay-kcd-20261108-124939-1ae7d0c08c614ae8b364b11f68b71051`.
Scripted guest key events drive vanilla Minecraft movement and the production
native pose follower through six strides in each third-person view: 4.01m
cumulative travel in back view and 3.91m in front, while remaining within 0.81m
of the start. Inventory keeps the player still, and first-person hand/HUD return,
save and camera/body cleanup pass. This verifies repeated integrated movement;
it does not claim physical Windows key routing or prolonged free roaming.

The same run passes independent native-camera clearance verification against
eight controlled magenta-concrete wall cells: 69 back and 66 front readbacks,
including clipped samples in both modes, with no penetration of the expanded
boxes. The source fixture was seeded through an isolated vanilla load datapack;
this camera test is not another placement-input acceptance. Partial-shape
geometry and malformed/chunked transport have focused automated coverage;
the live collision fixture currently uses full cubes.

With a fresh loaded KCD2 test world, installed WorldBlocks `$bundle` and isolated
`$instance`, the repeatable automated walking check is:

```powershell
& './scripts/Test-KcdThirdPersonWalking.ps1' -BundleDirectory $bundle -InstanceDirectory $instance
```

Keep KCD2 in front; no movement keys are needed. The wrapper checks all eight
image stages, repeated client/server/native displacement, inventory suppression
and normal cleanup. It also holds the back camera still for twelve seconds before
walking and records the interval for depth diagnostics. For the controlled eight-wall fixture, preserve that run's
native movement log and validate its saved geometry/readbacks with
`Test-KcdCameraCollisionEvidence.ps1 -EvidenceDirectory <saved-evidence-directory>`.
That verifier rejects changing geometry because a final snapshot alone cannot
prove earlier camera clearance. The receipts are `native-walking-verification.json`
and `camera-collision-verification.json` inside the run directory.

For foliage stability, also preserve the run's native addon log as
`native-depth-addon.log` and run
`Test-KcdFoliageDepthEvidence.ps1 -EvidenceDirectory <saved-evidence-directory>`.
It checks cumulative depth counters over intervals wholly inside the stationary
phase, requires at least four seconds and 120 frames, and fails on any missing
occlusion or readiness transition. Its immutable `foliage-depth-verification.json`
records failures as well as passes. This checks whole-frame depth stability;
it does not establish every foliage material's temporal appearance.

The WorldBlocks compositor now projects captured world colour **and** depth into
the current native camera. Each source pixel has an independent quad; nearest
depth wins overlaps and uncovered gaps remain transparent. HUD/hands are unchanged.
This profile requires a 1280×720 guest capture and current, unique native depth
provenance with GenericDepth `DepthCopyBeforeClears=0`. It reads that setting but
does not change it. Unsupported or unproven views retain the strict fallback.

The original source camera must be within 250ms of capture; the image and native
proof each have their own 250ms limit at presentation. The renderer also bounds
translation to 0.75m and rotation to 20°. These rendering rules do not renew any
input/movement lease or widen the fallback's camera-match tolerance. Large view
changes can still reject a frame until a corresponding new image arrives.

After the foliage verifier, run
`Test-KcdWorldReprojectionEvidence.ps1 -EvidenceDirectory <saved-evidence-directory>`.
Its immutable receipt requires nonzero native reprojection execution and reports
stationary and walking-sequence coverage separately. PASS does not itself claim
complete coverage, reduced physical-input latency, or perfect foliage appearance.

For developer CPU profiling, launch the test game with `MINECOME_DEPTH_PROFILE=1`
in that process's environment. Its run-filtered ReShade log then contains
`native_depth_profile` records with sampled callback mutex wait/hold times and
descriptor-copy sizes. Profiling is disabled by default. These samples measure
renderer tracking overhead, not end-to-end input latency or GPU frame time.

Input, pose, camera admission and cleanup also have automated contract/lifecycle
coverage. F5 applies only to WorldBlocks; legacy `-Hands` and flat-stream profiles
keep their first-person behavior.

## Minecraft hands and held items

`-Hands` includes `-Flight` (and therefore chat, walking and blocks). It reuses
the same native Chat/Flight bundle and adds the real Minecraft first-person hand
pass to the transparent HUD stream. It also combines with `-Explore`.

With KCD2 closed, prepare/install a fresh bundle and load a fresh test world:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-hands-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -Hands -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -Hands -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

Once the world has loaded:

```powershell
& './scripts/Start-GameplaySession.ps1' -Hands -Explore -BundleDirectory $bundle
```

Hotbar selection changes the actual vanilla held model. An empty slot shows the
saved player's Minecraft arm/skin. Inventory and chat hide the hand pass; it
returns after closing them. The vanilla renderer supplies models, equip/swing
animation, projection and lighting. This does not force a Steve skin, render a
third-person character or add NPC combat. `-Hands` alone keeps stone-only building;
use `-WorldBlocks` above for the additional palette.

Hands share the existing 20 FPS HUD capture and aspect-fit scaling. They are a
first-person overlay without host-world depth occlusion. Opaque skin, stone and
an unenchanted sword have pixel checks; translucent/glint/special item renderers
need further coverage. Ordinary Minecraft world rendering remains suppressed;
`-WorldBlocks` adds a separate pass for owned blocks.

`./scripts/Test-GameplayHands.ps1` runs one isolated actual-Minecraft session. It
captures seven PNGs covering empty hand, stone, sword, swing, inventory, restored
sword and return to empty hand; checks actual hand-pass visibility, transparency
and changed pixels; then verifies normal save and collision/ledger cleanup.
It uses vanilla chat/hotbar/UI actions and a scripted vanilla swing. It does not
claim native attack or NPC combat acceptance.

After stopping and closing KCD2:

```powershell
& './scripts/Install-GameplayHud.ps1' -Hands -BundleDirectory $bundle -Restore
```

## Creative flight

`-Flight` includes chat, walking and blocks and uses the chat native bundle.
It can combine with `-Explore` for on-demand captured terrain. Prepare and install
the rebuilt bundle with KCD2 closed, then start a fresh development world:

```powershell
$bundle = Join-Path (Get-Location) ('runtime/hud-gameplay-flight-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
& './scripts/Prepare-GameplayHud.ps1' -Flight -BundleDirectory $bundle
& './scripts/Install-GameplayHud.ps1' -Flight -BundleDirectory $bundle
& './scripts/Start-Kcd2ToolsTest.ps1'
```

Once the world has loaded:

```powershell
& './scripts/Start-GameplaySession.ps1' -Flight -Explore -BundleDirectory $bundle
```

Use `/gamemode creative`, then double-tap **Space** to toggle vanilla flying.
**Space** rises, **Shift** descends, **WASD** moves, and **Ctrl** enables sprint
flight. Inventory and chat release controls and stop aerial drift. **F8** stops
and saves; a valid airborne checkpoint reopens with the saved vanilla Creative
flight abilities. Reopening that airborne save requires `-Flight`.
Stopping after flight is disabled also records the falling position and accumulated
fall distance. On reopening, vanilla physics completes that fall before controls
attach. Minecraft's normal login damage protection still applies; the bridge does
not force damage during that protection period.

Flight uses Minecraft's abilities, input and collision, with the host following
the authoritative position. Coverage remains the captured ground heightfield
and owned Minecraft stone; native buildings, branches and other unsampled
obstacles are not complete collision. Feet stay below 18 metres above the original
capture origin. Unknown terrain stops movement; this is not unrestricted travel
or Elytra support. Modified flight speeds above Minecraft's default are unsupported.

After stopping and closing KCD2:

```powershell
& './scripts/Install-GameplayHud.ps1' -Flight -BundleDirectory $bundle -Restore
```

`./scripts/Test-GameplayFlight.ps1` runs actual Minecraft twice, using ordinary
jump/modifier input and real chat commands to exercise flight and airborne reload.
It does not force flight abilities or substitute scripted position changes.
Verification results and remaining live limits are recorded in `PROGRESS.md`.
The focused `./scripts/Test-GameplayFlight.ps1 -FixturePhase flight-fall` regression
switches from Creative flight to Survival, saves during the fall, then reopens
and checks restored fall distance, natural landing and vanilla login protection.

## Automatic sustained movement check

```powershell
& './scripts/Test-GameplayMovement.ps1'
```

The walking and reopen phases passed using one separate owned test instance and
the same explicit flat terrain fixture. The script launches actual Minecraft twice.
The first launch scripts early movement, inventory
suppression, resumed movement and another step after 21 seconds, then saves after
at least 35 seconds. The second launch checks the saved world/player identity,
game mode, abilities and location before walking again. It also checks both
collision threads, air-only imported cells, normal cleanup, and the bounded latest
server-pose file. This is standalone scripted input; even a passing result does
not establish physical KCD2 input or visible combined walking/HUD acceptance.

Combined evidence:
`runtime/evidence/gameplay-20261105-175426-6f1e55fbef314baabc1bb94deeec5011/walking-resume-verification.json`.
The 35-second phase produced 636 HUD frames; the saved location reopened exactly and
the player walked again. A decimal/float comparison bug in the fixture initially
rejected resume; only that shorter phase was repeated after fixing the validator.

The connected movement profile separately passed a 40-second native smoke with
live captured terrain, 601 poses, 401 camera samples and 734 HUD uploads/zero drops:
`runtime/evidence/gameplay-kcd-20261105-175248-793be9188b3642d9b4b8f793e4221e6e/verification.json`.
Its hotbar was visible in KCD and cleanup passed. No native input events were
recorded, so this does not prove physical walking in the new sustained profile.
The previous renderer installation was restored after the check.

## Crafting

The WorldBlocks gameplay profile uses Minecraft's actual recipes and crafting
handlers. Press **E** for Survival's 2×2 inventory grid. Craft a table from four
planks, select it and right-click captured ground to place it. Aim at the placed
table and right-click to open its 3×3 grid inside KCD2. Use the normal inventory
mouse controls to arrange ingredients and take the result; **E** or **Escape**
closes the screen and returns unused ingredients through the vanilla server.

Right-click uses a table before attempting placement or eating. Sneak with an
item held to place against it instead, following Minecraft's ordinary rule.
Ownership, reach and obstruction checks still apply. Movement, camera look and
world mouse actions pause while the crafting screen owns input. The placed table
and crafted inventory are saved in the existing persistent world.

This enables the inventory/table crafting workflow; storage containers,
enchanting and other block-entity systems remain separate features. Recipes and
ingredient/result updates are not reimplemented or replaced with item grants.

Automated checks use isolated worlds and real GUI clicks:

```powershell
& './scripts/Test-GameplayCrafting.ps1'
```

The check crafts logs into planks, a table, sticks and a wooden pickaxe, verifies
unused ingredients return when the table closes, and reopens the same save.
`Test-KcdCrafting.ps1` performs the corresponding connected check with scripted
guest inputs in a fresh supported tools world. It also accepts
`-VerifyEvidenceDirectory` to inspect saved receipts without rerunning a game.

## Furnace smelting

WorldBlocks also supports ordinary Minecraft furnaces. Select a furnace and
right-click captured ground to place it. Right-click the placed furnace to open
its actual screen, put ingredients in the top slot and fuel in the lower slot,
then take the smelted output. Minecraft owns the recipes, fuel duration, cooking
progress, inventory and experience. The world model follows the furnace's facing
and lit state.

**E** or **Escape** closes the screen. Ingredients, fuel and output stay in the
furnace, including across save/reopen; closing it does not return its contents
to the player. Movement and camera input are suppressed while its screen is
open. Sneak with an item held to place against a furnace instead of opening it.
Normal ownership, reach, captured-terrain and obstruction limits still apply.
Smokers, blast furnaces, storage containers and automation are separate work.

`Test-GameplayFurnace.ps1` uses real inventory clicks, waits for vanilla smelting,
and reopens the same saved furnace to finish another item. `Test-KcdFurnace.ps1`
exercises the connected path with scripted guest inputs and records native
composition while the furnace screen is open. Its -VerifyEvidenceDirectory
option checks an existing run without launching either game again.

## Dropped items and Survival pickup

The WorldBlocks profile also supports crafting tables; see
[crafting controls](#crafting) for the inventory and table workflow.

WorldBlocks now draws real tracked Minecraft item entities in the same world
colour/depth layer as blocks and Steve. Minecraft supplies the stack model,
bobbing, rotation, count-dependent copies and lighting. Drops inherit captured
terrain occlusion and the native scene-depth comparison. Rendering is bounded to
256 entities within 64 metres and the captured terrain footprint; this does not
delete or modify entities beyond that rendering scope.

In Survival, mine a placed stone with a suitable pickaxe, then walk over its
cobblestone drop. Vanilla owns loot generation, item physics, pickup delay,
inventory insertion, tool durability and saving. Collection removes the rendered
entity through Minecraft's normal entity tracking. No inventory grant substitutes
for pickup. Drop-only frames carry their own world pixels even with no owned
blocks or third-person Steve visible.

Automatic isolated mining/render/pickup/reload verification:

```powershell
& './scripts/Test-GameplayDrops.ps1'
```

The check matches the server drop UUID to rendered colour/depth pixels, waits for
the item to rest on captured collision, walks using released key pulses, verifies
pickup statistics and one point of pickaxe wear, then reopens the same save.
Its fractional-height test surface also forces a mined drop to start inside
captured ground. A server-side ItemEntity hook resolves that overlap with a
bounded vanilla movement call before normal item physics resumes. It preserves
the real entity and stack, refuses actual-block obstructions, and applies only
inside the installed terrain coverage; it does not grant items or teleport the
player. Recovery counts are included in the test evidence.
Scripted aiming and walking are explicit; physical mouse input is not claimed.
`Test-KcdDrops.ps1` runs the corresponding bounded check in an already-loaded,
exactly supported KCD2 tools world with a prepared WorldBlocks bundle and a new
isolated instance. Its native-only dwell verifies world composition advances
while the mined item exists, then releases native state and saves normally.
Use `-VerifyEvidenceDirectory '<saved evidence directory>'` to recheck receipts
without launching a game. This checks actual guest pixels, entity identity and
native composition progress; it does not assert physical input or native
post-occlusion screenshot visibility.

## Native health/stamina HUD

KCD2's health/stamina widgets still overlap Minecraft's HUD. They should be hidden
only while MineCome owns the session and restored afterward. The existing
`wh_ui_ShowHud` probe verified a reversible whole-HUD toggle, but selective
health/stamina element identities are not yet verified; hiding the whole HUD may
also affect dialogue, subtitles and the compass. The old helper's 120-second
lease is not suitable for sustained sessions. Selective hiding, or a renewable
lease with original-state restoration and dialogue checks, remains required UI
integration work.

## Survival food and regeneration

The gameplay block profiles also route held right-click to Minecraft food in
the selected main-hand slot. Use `/gamemode survival` and, for example,
`/give @s minecraft:bread 8`, select the food, then hold right-click. Vanilla
Minecraft decides whether the player can eat, the use duration, item consumption,
hunger/saturation and regeneration. No replacement health or hunger model is used.
The Hands/WorldBlocks profiles use the same real active-item state for rendering.

Releasing right-click, attacking, changing the slot or mode, opening a menu, or
losing gameplay authority cancels the held use. Resume with a fresh right-click.
Holding food does not interact with the block under the crosshair. This increment
supports main-hand food components; general item use, offhand controls, NPC combat,
cross-game combat remains separate work; crafting, furnaces and respawn are described above.

Run the automatic check without KCD2 or manual input:

```powershell
& './scripts/Test-GameplayFood.ps1'
```

It uses an isolated actual Minecraft world, sends setup commands through vanilla
client packets, exercises the production mouse controller and normally saves and
reopens the world. The receipt distinguishes this scripted guest verification
from native KCD2 input and visual acceptance.

## Automatic persistence check

```powershell
& './scripts/Test-GameplayPersistence.ps1'
```

This uses a separate instance under its evidence directory, leaving the default
gameplay world alone. It performs two actual Minecraft launches, with a normal
save/shutdown between them. The first session lasts at least 35 seconds, sends
commands through Minecraft's client packet path, and verifies matching client and
server state. The second reopens the same world and verifies persistence, then
switches Creative → Survival through vanilla commands again.

Passed evidence:
`runtime/evidence/gameplay-persistence-20261105-170217-435f802075d347c982b362d2e32c75d9/verification.json`.
The same world/player identity retained Survival mode, 17 apples, one iron pickaxe,
health 16/20, food 11/20 and the saved game rule. Creation lasted 35.215 seconds; both launches
closed normally and the native standalone receiver confirmed the stream closed.

This proves the persistent guest, command packet path and saved survival state.
It does not prove physical command typing in KCD2, actual flight, imported host
collision or damage exchange with native NPCs. Those remain required product work.

## Death and respawn

WorldBlocks accepts Minecraft's real death screen and Respawn button. Death
releases walking, mining and food controls; the button sends vanilla's respawn
packet. The new same-world player retains construction and terrain. Native
movement waits for an identity-bound relocation acknowledgment before returning
to ordinary controls. Default respawn uses the captured origin; unsupported or
blocked explicit spawn points stop safely rather than using flat-world spawn.

Dropped inventory remains vanilla. Collision stays installed until the integrated
server finishes saving, so items left in captured terrain retain their positions
across a normal shutdown. Uncaptured terrain still cannot support items.

To request a larger starting capture in an ordinary session, append
`-InitialTerrainRadius 1` to `Start-GameplaySession.ps1 -WorldBlocks`. It enables
Explore, samples eight neighboring tiles and retains each only after verified
admission. The resulting area is 24m square when all tiles succeed. Steep or
otherwise refused tiles stay unavailable; normal exploration limits still apply.

Automatic checks, without manual key sequences:

```powershell
& './scripts/Test-GameplayRespawn.ps1'
# Connected counterpart: installed WorldBlocks bundle and already loaded KCD2 world
& './scripts/Test-KcdRespawn.ps1' -BundleDirectory $bundle -InstanceDirectory $newTestInstance
```

The standalone check passed death, drops, actual button input, paired replacement,
walking, construction and two-launch persistence. The connected check additionally
passed native relocation and compositor progress through the death screen, with
all nine terrain tiles captured and acknowledged. These use scripted guest
inputs; they do not claim new physical mouse acceptance. Full design/evidence and
unsupported cases are in [respawn integration](RESPAWN_PLAN.md).

The sustained gameplay HUD accepts one session per KCD2 process. Restart KCD2
normally before another session; the launcher now detects an already consumed
session before starting Minecraft.

## NPC melee bridge

`-Combat` adds the experimental NPC adapter to WorldBlocks. Aim and left-click
an NPC to send an actual Minecraft primary melee attack. Minecraft calculates
weapon damage, attack cooldown, critical damage and durability; the bridge maps
the resulting damage fraction onto the native NPC's maximum health. Native
NPCs keep their identity, movement and AI. Block mining keeps its existing path
when the crosshair does not select an NPC. Inventory and chat suppress attacks.

This is an outgoing primary-melee increment, not complete combat. Native NPC
attacks are not yet routed into Minecraft health. Ranged attacks, sweep damage,
knockback and secondary enchantment effects are not transferred. Minecraft's
incoming armor/hurt logic is implemented and tested with synthetic host events;
a native pre-damage hook and safe ownership of the underlying player's health
are still required. See [native binding evidence](research/KCD-COMBAT.md).

The required combat model is free aiming and unrestricted movement. The adapter
does not request native targeting or combat mode. Disabling native target lock
under hostile NPC attacks still needs a verified policy; the current work does
not claim that hostile combat is ready.

The outgoing native call attributes damage using the player's native WUID and
requests hit reactions (`suppressHitreaction=false`). A basic native recoil was
visually observed on the owned test NPC; the suppressed control stayed upright.
This does not establish every enemy animation or hostile retaliation. The next
combat sequence is reciprocal NPC damage and free movement/aiming, then vanilla
bow projectiles (including charge, ammunition and native target collisions),
followed by crossbows and other ranged/secondary combat effects. Ranged items are
not yet connected to native NPC damage; equipping one does not establish support.

Automated checks use isolated saves and require no manual attack sequence:

```powershell
& './scripts/Test-GameplayCombat.ps1'
# Installed WorldBlocks bundle and a fresh, loaded KCD2 tools world:
& './scripts/Test-KcdCombat.ps1' -BundleDirectory $bundle
```

The standalone check uses real Minecraft attack packets, cooldowns, durability,
armor, inventory and HUD pixels, with explicitly synthetic native actors. The
connected check creates one temporary NPC using the official debug template,
strikes it through the same production bridge, then checks inventory and walking.
It also requires native composition/reprojection to keep advancing after walking,
and verifies the native camera stays horizontally still in inventory. The coupled
check passes on the supported tools build; see [progress evidence](PROGRESS.md).
Its NPC expires automatically within two minutes and is removed on normal or
failed cleanup. This fixture does not establish hostile NPC retaliation or
physical mouse acceptance.
