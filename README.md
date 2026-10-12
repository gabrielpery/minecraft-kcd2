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
returns to the starting position. KCD2 keyboard/mouse forwarding, streaming
collision and general movement authority remain unfinished. See
[the movement lab](kcd2/MOVEMENT-LAB.md).
The separate Windows walking/mouse capture layer and strict Java input gate now
compile and pass standalone checks. Actual Windows registration, neutral recording
and cleanup pass; physical control delivery and Minecraft application are still
separate checks. See [Windows input capture](docs/research/WINDOWS-INPUT.md).

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
