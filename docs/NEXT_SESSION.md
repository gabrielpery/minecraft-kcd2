# Resume checkpoint — 29 October 2026

## Current capability

Verified live in the previous round: 8×8m walking, actual Minecraft HUD,
top placement/breaks, inventory suppression and later walking worked twice in one
KCD2 process. Preserve these profiles. The remaining repeat-lifecycle issue is
final retirement after the completion-record timing fix, described below.

New this round: two overlapping terrain tiles form an immutable 12×8m corridor
under one fixed coordinate origin. Actual Minecraft automatically crossed the old
edge, jumped/landed, returned and completed its real HUD sequence on captured KCD
terrain. This is standalone Minecraft verification, not live KCD following across
the corridor. No native addon changed or manual test was requested. Both games
are closed; recheck processes before the next launch.

## New evidence and implementation

Capture run 5eb9ebb1940f49599ffd2b74e3ae9524: 162 rays, two 9×9 tiles, unchanged player,
pinned tools executable and matching overlap. Directory:

    runtime/evidence/ground-corridor-20261029-205630-5eb9ebb1940f49599ffd2b74e3ae9524/

Passing HUD run bbbe7a8590f54996a14896d1a7e79e48:

    runtime/evidence/hud-stream-20261029-210115-bbbe7a8590f54996a14896d1a7e79e48/verification.json

Client/server walked 5.544m to X6.044 (original edge X4), jumped/landed and returned
within 0.063m.321 accepted HUD frames,41 crossing frames and 23 return frames.
No post-settle corrections; both collision proxies and controls released; vanilla
cells remained air. The input fixture paused 17 ticks and safely released one
expired 150ms hold. It preserves the 250ms stall/freshness, 1m disagreement and 1s
synchronization bounds; all legacy modes are unchanged.

GroundSurface/GroundCorridor preserve the first tile anchor; bounds are
X[-4,8],Z[-4,4]. The two raw tile JSON strings and SHA256 hashes are embedded in a
bounded manifest. GroundCollision builds the complete map before installation,
requires a free corridor slot and releases exact world/run/hash ownership.
This is fixed adjoining terrain, not rolling transactional replacement.

Entry points (automatically select configured PowerShell 7):

    ./scripts/Test-KcdGroundCorridor.ps1
    ./scripts/Start-HudGroundCorridorLab.ps1 -CorridorFile <capture-directory>/ground-corridor.json

The first requires an already-loaded tools world and stationary player. Close KCD
normally before the second to avoid GPU competition. Omitting CorridorFile selects
explicit synthetic terrain. Keep recorded capture files together; source/engine
provenance is checked before replay. See kcd2/MOVEMENT-LAB.md for commands.

Focused checks passed: Java geometry/sequence 1827, mode 123, physical 383, collision
ownership 25; PowerShell capture 33, preparation 11, corridor 23, old ground 134; Lua 8.
Do not rerun unchanged suites. Earlier failed capture/synthetic/captured runs
remain intact; the final passing run is the authority. docs/PROGRESS.md summarizes
the failures and fixes. Read specific evidence fields, not complete old logs.

## Next implementation

1. Integrate the immutable corridor into the automatic two-game movement path,
   with explicit new bounds/provenance and the same fixed alignment. Preserve
   existing live profiles. Do not merely widen their old radius or extend timers.
2. Exercise KCD player/camera following and restoration across the original edge
   automatically before offering a batched live controls/composition acceptance.
3. Then address rolling terrain ownership and general terrain-face placement.
   Current lab support does not establish arbitrary building against KCD terrain.

The corridor currently rejects physical/coupled/aimed modifiers and live HUD arms.
Those integrations are unfinished, not enabled by changing a command-line flag.

## Remaining repeat-session acceptance

Previous live first run d2aece664fe444988e368d8d1b9860f0 passed 156 source frames/
readbacks and retired generation 1 idle. Second run 2ed8bd8b0e6e4ea2aef1cf0ce3a01ae8
completed gameplay and exited 0, but its receipt arrived about 3s after the original
controller deadline; native retirement reported cleanup_timeout. Its separate
post-run audit passes, but does not authorize rearm or replace the original failure.
Detailed evidence and timing repair are retained in docs/PROGRESS.md and Git 87217b9.
The bounded completion-only tail (at most 5s, ending by 117s before a 120s GPU lease)
and early FPS restoration have automated coverage. Final generation 2 exhausted
and third-session refusal remain unverified live. Bundle that acceptance with a
future useful feature check; do not repeat proven block/inventory exercises alone.
Use only an exact successful previous arm receipt, never a guessed latest arm.

## Environment and workflow

Official Steam tools 2429020/build 1.5.5 only; retail 1.5.6 remains gated. Never load
retail saves in tools. Existing repeat addon remains installed. Routine changes,
launches, tests and Git pushes are authorized. Prefer normal owned-process window
close; no Computer Use or administrator mode was needed this round.

Workspace: C:/Users/xephi/Documents/ChatGPT/New project/MineCome
Public repo: https://github.com/gabrielpery/minecraft-kcd2
Branch: codex/initial-import; inspect current Git status/log before editing.
JDK: C:/Program Files/Java/jdk-24
Gradle cache: minecraft/.gradle-user-home (not runtime/gradle-user-home).
Bundled PS7: C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe
Lua tests can use C:/Program Files/Wireshark/lua52.dll.

Follow AGENTS.md: integrated progress, focused automated checks, minimal human
requests and concise handoffs. Only ask for foreground input/composition/feel when
needed. Prefer user-started sessions; never start a countdown while asking whether
the user is available. Format commands separately before any question widget.
