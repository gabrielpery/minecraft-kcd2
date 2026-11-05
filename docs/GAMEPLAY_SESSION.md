# Persistent gameplay session foundation

This development path reuses one Minecraft world and keeps the HUD session alive
until explicit stop or loss of its peer. It has a separate protocol/profile from
the bounded movement labs. It is not yet the complete [product](PRODUCT.md).

The default save is
`runtime/gameplay/instance/saves/MineCome-Gameplay`. Its ownership marker holds a
stable world UUID. A new world starts in Creative, Normal difficulty, with commands
enabled and vanilla superflat ground. Reopening uses Minecraft's ordinary loader
and preserves its player state, inventory, game mode and game rules. An existing
unmarked or incomplete save is refused rather than adopted or reset.

**The superflat world is bootstrap ground, not imported KCD2 terrain.** In the
connected profile, KCD2 still controls walking and the camera; Minecraft supplies
its actual HUD and inventory. Minecraft-driven movement, block mirroring, Steve's
body/hands, command typing from KCD2, cross-game health/combat and flight remain
unfinished in this new profile. Existing bounded gameplay labs remain separate.

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

The connected entry requires the v5 gameplay bundle and its matching native
component. Older bounded HUD bundles cannot read this protocol. The verified demo
installation was restored after the automatic check. Stage a fresh bundle and
install it only while KCD2 is closed:

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

Connected startup, automatic input arming and sustained native composition passed
an automatic40-second KCD2 check (host launched at60FPS). The hotbar was visible in
a captured KCD2 frame;733 frames uploaded, zero drops, normal stop/save and input
cleanup passed. Receipt:
`runtime/evidence/gameplay-kcd-20261105-171621-b063422fa5d64d6fa67539bff318d787/verification.json`.
No input events were recorded, so inventory-control acceptance in this new profile
is still pending. This does not establish Minecraft-driven movement.

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
