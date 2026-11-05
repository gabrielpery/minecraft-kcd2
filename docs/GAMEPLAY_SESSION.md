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
General blocks, Steve's body/hands, command typing from KCD2, cross-game
health/combat and flight remain
unfinished in this sustained path. Existing bounded gameplay labs remain separate.

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
