# MineCome

An experimental integration of real Minecraft Java Edition with the actual Kingdom
Come: Deliverance II engine. Original source lives here; fetched research repositories,
game assets, authentication tokens, isolated test worlds and build outputs stay local.

**Current result:** both native C++ and Fabric components compile. A real Minecraft
process connects to a live official KCD2 development build through its documented
localhost debug interface and an original Lua module. **A real Minecraft stone block
is visible in the loaded KCD2 development world**, verified by the user's screenshot
and matching engine logs. **The texture sharpness fix is also verified in a second
user-provided live screenshot**, showing crisp front and side faces. **Real vanilla
Minecraft placement and breaking now make the stone appear and disappear in KCD2**,
confirmed by the user's live observation. A subsequent automated two-game run passed
matching engine spawn, deferred removal and cleanup acknowledgements with zero
replicas left. An opt-in interactive prototype now compiles: KCD2 console commands
request real vanilla Minecraft placement/breaking in one fixed lab cell. Its new
controls pass standalone checks and now have actual two-game placement/removal
receipts. The user confirmed seeing the stone after the live log-framing fix.
**The first movement lab now passes:** real Minecraft walks, jumps and lands against
an approximate collision patch sampled from the actual KCD2 ground. Both client
and integrated server confirm the movement. **A bounded coupled run also passes:**
real Minecraft server poses move KCD2's player, its camera follows, and the player
returns to the starting position. Sustained input ownership, streaming
collision and general movement authority remain unfinished. See
[the movement lab](kcd2/MOVEMENT-LAB.md).
The separate Windows walking/mouse capture layer and strict Java input gate now
compile and pass standalone checks. Actual Windows registration, neutral recording
and cleanup pass. **External input now drives real Minecraft walking, jumping,
landing and view changes in an isolated lab**. A live two-game check now verifies
physical W/Space/mouse input from the focused KCD2 window reaching real Minecraft's
client and server, with neutral release and clean observer shutdown.
See [Windows input capture](docs/research/WINDOWS-INPUT.md).
The input lab now supports explicit key bindings and a starting view captured from
KCD's camera. The live KCD capture and matching Minecraft client/server starting
view are verified. This bounded input lab stays separate from the KCD player follower;
KCD's own input and physics remain active.
The input lab also exports server position and view with validated KCD coordinate
projections. This new output passed an automatic real-Minecraft run and remains
audit-only until KCD control ownership and restoration are established.

**Genuine UI capture now works:** a fresh Minecraft world exported its actual hotbar
with two selected slots and its real Creative inventory screen, with item contents
confirmed by the client and server. The renderer path follows SkyCraft/EldenCraft:
captured vanilla pixels feed a native host compositor. The first KCD D3D12/ReShade
component completed a bounded static-frame proof. **The user confirms seeing the
Minecraft HUD inside KCD2**, and native logs record submission of both hotbar
snapshots and the Creative inventory snapshot. **Continuous UI transport now also
passes with real Minecraft:** a fresh world sent 344 frames to the standalone
native receiver, including three selected slots and its actual Creative inventory.
The receiver verified stale-frame hiding, fresh resumption and orderly closure.
The continuous D3D12 add-on now displays the HUD inside KCD2 with user-accepted
sizing. Physical 1/2/9 hotbar selection and E/Escape inventory control are verified;
the user reports no KCD menu opening during that sequence. The latest run uploaded
471 frames and exited normally when KCD lost foreground. A separate automatic
real-Minecraft fixture verifies all nine hotbar selections and an item swap
confirmed by the integrated server. A separate 43-event fixture now also verifies
stack splitting, dragging, scrolling and held-button inventory closure/reopening
in the hidden guest. The accepted capture is 1280x720 at GUI scale2.
An optional bounded host-HUD switch also passes live shown/hidden/restored setting
readbacks; its combined visual appearance remains unverified. **Physical inventory
mouse control now works in KCD2**, confirmed by the user. The separate strict
DirectInput capture profile completed its full 30-second test: 639 events were
acknowledged, including clicks, dragging and scrolling, with normal Minecraft
shutdown. Inventory capture now follows the existing 30 FPS guest rendering cap;
a fresh automatic Minecraft run measured about 30 captures per second and passed
all 43 pointer actions. Combined inventory smoothness still awaits a live check;
the combined block run below verifies the hidden-through-exit policy and normal
process shutdown. General gameplay input ownership remains unfinished. See
[the HUD compositor](docs/research/HUD-COMPOSITOR.md).
**HUD and block actions now share one real Minecraft world in the standalone lab.**
The selected hotbar item controls vanilla stone placement; dirt selection and an
open inventory prevent placement. An automatic run verified two placements and
two breaks on both the client and integrated server, genuine HUD frames and normal
shutdown. An explicit live controller now connects this same guest to the existing
KCD relay, with a bounded automatic place/break preview after F8. **The combined
live check passed:** the user saw the hotbar and stone appear/disappear together;
both games confirmed the operations and cleanup. A separate World profile now
connects right-click/place and left-click/break to that same relay. **The physical
check passed:** four clicks produced two confirmed cycles in both games, with
the user's visual confirmation and normal cleanup. It intentionally
locks KCD mouse look and controls one nearby cell for up to 30 seconds. Free
aiming and continuous gameplay remain unfinished.
**Camera look now works alongside Minecraft inventory and stone controls.**
The user confirms the revision 3 test worked; it completed its full 30-second
activation, with 276 nonzero DirectInput motion observations passed through and
three confirmed place/break cycles. The fix admits pure mouse motion through
ReShade's registered helper-window route while preserving inventory capture.
Normal cleanup and FPS restoration pass. The original controller result remains
failed because it expected a Minecraft reply for a final request that the native
relay explicitly refused after disconnect. The corrected verifier passes a replay
of the unchanged live evidence. Earlier revisions' camera failures remain recorded.
The verified camera-locked profile remains available.
Shared aiming geometry is tested in Java and C++, but live targeting still uses
the fixed cell until the alignment handshake and live ray are connected.
**The actual Minecraft aimed-action component now passes its automatic lab:**
21 scenarios verify all six selection faces, side placement, nearest-block
selection, refused rays and a pending action remaining on its original target
after a camera turn. Four placements and four breaks have client/server proof,
followed by complete stone cleanup and normal exit. This uses synthetic host rays;
it does not yet enable aiming at different blocks from KCD. The separate read-only
KCD camera/obstruction probe is implemented and tested; its live sample and the
shared alignment/aimed-request protocol remain pending. See the
[standalone aimed-stone lab](minecraft/README.md#standalone-aimed-stone-lab).
Earlier tools launches crashed during world loading with the renderer unarmed and
with its hook disabled. A subsequent explicit PowerShell 7 launch reached the world,
confirmed by the user and a successful two-minute process/HTTP check, with the hook
and startup mods disabled. PowerShell 7 is the working launch path; the cause of the
earlier exits remains unresolved. The repaired compositor subsequently loaded in
a fresh world and completed its 40-second preview. The user reported the HUD
canvas was too small. The aspect-fit correction passes 131 focused checks and is
included in the new continuous compositor. The stream implementation passes 168
Java checks and 146 native checks; the existing 36 snapshot checks still pass.
Those earlier sizing issues are resolved by the accepted layout above. Selective
KCD widget suppression and health integration remain unfinished.

The retail KCSE route is blocked by a missing verified Steam 1.5.6 address library.
The installed official tools run a distinct 1.5.5 development build. Its working HTTP
prototype is not evidence that the retail native plugin or full gameplay works.

Start with [setup](docs/SETUP.md), [progress and evidence](docs/PROGRESS.md),
[architecture](docs/ARCHITECTURE.md), [known issues](docs/KNOWN_ISSUES.md) and the
[wire protocol](protocol/PROTOCOL.md). The research notes explain actual upstream
implementations and distinguish their claims from our tests.

For the next interactive session, use [the stone lab procedure](kcd2/TOOLS-TEST.md#interactive-stone-lab).
It uses an already-running fresh official development world and
`scripts/Start-InteractiveStoneLab.ps1`; then enter `minecome_place` and
`minecome_break` in KCD2's console. This is a bounded one-cell prototype, not the
final movement, inventory or persistent-world build.

```text
kcd2/       real KCSE adapter, original Lua diagnostics, official-tools host
minecraft/  actual Fabric mod; vanilla owns gameplay and model generation
protocol/   transport-independent C++ and Java wire codecs and coordinate math
tools/      environment discovery, explicitly simulated native host, asset tooling
tests/      malformed-packet, coordinate, ABI, parser and cross-language tests
scripts/    reproducible fetch/build, token generation, backup and mod staging
docs/       architecture, progress, risks, setup and source research
```

Basic local development:

```powershell
.\scripts\Fetch-References.ps1
.\scripts\Init-Session.ps1
.\scripts\Build-Native.ps1
.\scripts\Build-Minecraft.ps1
# See minecraft/README.md for an isolated real-client launch.
node .\tests\integration.mjs
```

All testing is single-player. Native adapter uses the real GPLv3 KCSE API; MineCome
source is GPL-3.0-or-later. Third-party attribution is in THIRD-PARTY-NOTICES.md.
No game executables, game textures/models, address maps, saves, launcher accounts or
SDK archives are distributed. You need your own legitimate game installations.

The private source repository is
[gabrielpery/minecraft-kcd2](https://github.com/gabrielpery/minecraft-kcd2).
Clone it with an account that has access, then run the setup commands from its root:

```powershell
git clone https://github.com/gabrielpery/minecraft-kcd2.git
Set-Location minecraft-kcd2
```

Build outputs, fetched dependencies, tokens, game assets and local test evidence
are ignored. A fresh clone requires dependency fetching, local credentials and
your legitimate game installations as described in setup.
