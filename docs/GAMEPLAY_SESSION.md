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
walking in this new profile still needs acceptance. Block mirroring, Steve's body/hands, command typing
from KCD2, cross-game health/combat and flight remain unfinished in this sustained
path. Existing bounded gameplay labs remain separate.

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
