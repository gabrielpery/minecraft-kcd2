# Genuine Minecraft UI inside KCD2

The required architecture is Minecraft's real HUD and screens captured as pixels,
then composited in the host renderer. There is no desktop overlay, hand-drawn
hotbar, web UI, or replacement inventory implementation.

## Inspected implementations

- [SkyCraft FrameExporter](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/FrameExporter.java)
  captures the normal hand/HUD/screens render path with three GPU staging slots;
  its [native Overlay.cpp](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Overlay.cpp)
  uploads and draws the UI on Skyrim's D3D11 backbuffer. Its world meshes use a
  separate path.
- [EldenCraft compositor](https://github.com/SocketByte/EldenCraft/tree/ba7591cdde9fb16e17552cfe53546f44d0fd856e/compositor)
  uses ReShade 6.8.0 and D3D12, with GPU sharing and a CPU shared-memory fallback.
  The host draws guest world and UI layers. Its me3 loader is Elden Ring specific.
- [ReShade 6.8.0 public API](https://github.com/crosire/reshade/tree/18deaa52de0c425a78b329e9cb3c497281cd00ec/include)
  supplies the host effect-runtime lifecycle and texture bindings. No guessed
  CryEngine addresses or KCSE ABI are involved in this HUD path.

The actual running official KCD2 development process was inspected and had
`CryRenderD3D12.dll` loaded. This makes EldenCraft's D3D12 compositor the closer
host-side precedent. Source inspection of either upstream is not a MineCome live
rendering result. Their Minecraft 26.3 adapters cannot be copied verbatim into
our pinned 1.21.1/Yarn 1.21.1+build.3 guest.

## First bounded implementation

`scripts/Start-HudExportLab.ps1` creates a new isolated Creative world. Actual
vanilla inventory packets populate nine slots; fresh client and integrated-server
observations must agree before capture. Frames contain selection 0, selection 1,
and an actual vanilla inventory screen. Minecraft's normal GameRenderer renders
each frame once. World/hand rendering is suppressed only after initial world
loading completes and only in that owned opt-in world.

The OpenGL adapter preserves render state, uses pixel-pack buffers and nonblocking
fence polls, and writes copied pixels on a daemon worker. The export is top-left,
straight RGBA8 with explicit dimensions, hashes, slot evidence and alpha counts.
Ordinary source-over alpha is accumulated while rendering onto transparent pixels;
RGB is normalized once for the straight-alpha file format. Runtime FAST graphics
avoids the opaque fancy vignette; previous graphics/HUD/focus options are restored
on shutdown. The initial scope omits the held hand and full survival HUD.

The original ReShade add-on reads one to three captured frames off the render
thread and composites them into the D3D12 backbuffer. This first proof is explicitly
`static_snapshot=true`: changing among captured states proves composition, not
continuous gameplay synchronization. Arming requires the exact supported tools
executable, PID/start identity, checked frame files and a maximum 45-second lease.
Other foreground windows, expiry and unsupported formats hide the layer.

The subsequent continuous transport implementation is recorded below. The next
input stage is host-to-vanilla UI control with focus/release handling. Drawing the inventory screen alone does not verify
clicking slots, crafting, or KCD menu/input arbitration. The existing movement and
stone labs remain independent while this rendering path is brought up.

## Validation and limits

The pure Java tests cover pixel orientation, alpha conversion, PNG encoding,
output ordering and bounds. The native contract tests cover malformed arming,
identity, expiry, dimensions and compositing math. `minecome_check_hud_fx` compiles
the actual FX using ReShade's DXBC 5.1 backend at two resolutions. These checks
cannot establish that the game loaded ReShade or presented the layer.

The initial offline build passed 36 Java pixel/output checks and 117 native contract
and lifecycle checks. Four shader entries compile through the pinned ReShade DXBC
backend. A source review found a reset-lifetime bug: ReShade destroys effect handles
before its `destroy_effect_runtime` callback. Cleanup now invalidates cached handles
without writing uniforms, removes semantic bindings and releases only owned GPU
resources. The disarmed rendering path returns before shader access. This fixes a
confirmed source defect, but does not establish the cause of the startup crashes.

On 2026-10-12, a user-started tools process loaded ReShade 6.8.0 and the initial
unarmed add-on, created its D3D12 runtime and compiled the HUD effect. It then exited
during world loading before any preview was armed or frame submitted. The owned
`dxgi.dll` was renamed to `dxgi.dll.minecome-disabled`. A second user-started run
also crashed at the same final game-log line (`[MFX] Loading FXLib 'collisions' ...`),
while ReShade's log stayed unchanged. Neither run yielded an exception stack or
exit code. The hook was disabled for the investigation; the repaired build was
installed later, as recorded below.

`scripts/Disable-HudCompositor.ps1` performs an ownership-checked reversible rollback
and supports a read-only `-Preview`. Installation and rollback support Windows
PowerShell 5.1. Preparation, guest capture and arming use the explicitly documented
PowerShell 7 requirements in their script headers; run them with a PowerShell 7
executable rather than assuming the user's current shell is PowerShell 7.

`scripts/Start-Kcd2ToolsDiagnostic.ps1` accepts an ordinary Windows PowerShell 5.1
invocation and selects an existing PowerShell 7 runtime. Its `-PreflightOnly` mode
checks the exact executable and disabled hook
without launching or writing evidence. The normal user-run mode starts a fresh
`trosecko` world, records process exit code, sampled module paths, private memory
and available system commit for up to 120 seconds, and preserves bounded game-log
tails under `runtime/evidence`. If the game survives, it is left running. Sampled
module absence and process survival do not establish successful world loading.
The first user-run diagnostic captured the repeated failure with exit code 250
after 28.462 seconds, six complete module snapshots without ReShade/the add-on and
over 5.37 GB available system commit in all memory samples. The exit code's game-
specific meaning remains unproven.

For a controlled comparison, the manual diagnostic also accepts `-WithoutMods`.
Warhorse's documented `Mods/mod_order.txt` list loads only the listed mods; an empty
list requests a run without mods. The helper refuses any existing list, creates a
new empty file and records its filesystem identity. After the game exits it removes
only that unchanged owned file, restoring the previous loading setup. If the game
is still running at the monitoring deadline, or ownership changes, the list remains
and the receipt explicitly requires cleanup after normal closure. No mod package
is renamed, overwritten or deleted. Actual exclusion must be confirmed in the fresh
game log; creating the list alone is not live verification.

## Working PowerShell 7 baseline

The user repeated the zero-mod diagnostic through the installed bundled PowerShell
7.6.5 and confirmed that the world loaded. The exact tools process survived the
full two-minute monitor and its official Console API returned HTTP 200. The hook
remained disabled. This restores a working baseline but does not prove which
shell/environment difference caused the earlier exit-250 failures.

Use the launch helpers through PowerShell 7. A direct command from an ordinary
PowerShell window is:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-Kcd2ToolsTest.ps1'
```

This command starts a fresh test world; close an existing game normally first.
The successful diagnostic's owned empty mod-order file remains until its
ownership-checked cleanup after normal game closure. Do not infer that MineCome
startup scripts are active during that isolated zero-mod session.

A proposed startup debugger did not pass its standalone timeout fixture and was
never attached to KCD. Its source and local evidence are retained under
`runtime/evidence/startup-debug-deferred-20261012`; it is not a supported test step.
The observed failure reinforces Microsoft's distinction between normal
[debugger detach](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/ending-a-debugging-session-in-cdb)
and [recovery after an abruptly ended debugger](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/reattaching-to-the-target-application).

## Repaired HUD preview restart

`Update-HudCompositor.ps1 -PreflightOnly` verifies the disabled owned installation
and the staged reset fix without changing files, including while KCD is open.
Its actual update requires every KCD process to be closed. Only the owned add-on
currently differs; the updater preserves the previous file and receipt, verifies
the replacement, and re-enables the pinned owned DXGI proxy last. It does not start
the game or arm the preview. Failed updates attempt ownership-checked restoration
and preserve their evidence under `runtime/evidence/hud-update-*`.

This one-time reset-fix update has already been applied. Do not rerun the original
update command against the active installation. The launch helper selects an
existing PowerShell 7 runtime automatically, so future launch instructions need
only call `Start-Kcd2ToolsTest.ps1` after normal game closure and any required
ownership-checked deployment/cleanup.

The update and fresh restart have now succeeded. PID 55096 loaded the repaired
add-on and compiled the effect. A 40-second preview submitted all three genuine
Minecraft snapshots and expired with KCD2 still running. The user confirmed
seeing the Minecraft HUD inside the game; their report did not separately identify
the selected-slot change or inventory frame. This establishes the first visible
HUD milestone, with the native logs separately proving submission of all states.

The user also reported an undersized canvas. The integer-scale fit selected 2×
for 854×480 into 2560×1440, leaving a 1708×960 inset. The aspect-fit correction now
builds and passes 131 focused contract checks, retaining point sampling. Its bundle
was staged at `runtime/hud-compositor-aspect-fit`. That separate static-only build
was not installed; the subsequently installed continuous add-on includes the same
correction. The later live report confirms the GUI is now too large; sizing needs
refinement. The updater keeps separate
exact static/stream build allowlists and refuses either existing arm filename.

The successful zero-mod diagnostic's owned empty mod list stays in place for this
renderer-only comparison. Its eventual restoration must verify the original file
identity and empty contents after game closure. This preview used `Arm-HudPreview.ps1`
with the existing verified three-frame Minecraft capture and the absolute path to
`runtime/hud-compositor-resetfix` as its bundle. No new Minecraft launch was needed
for the completed static display proof. Its expired config has since been archived
after ownership verification. Both add-on modes accept one arm per process.

The SDK, official runtime, generated captures and Minecraft assets remain local
under ignored directories. No original game executable is overwritten. Runtime
installation and a fresh game start are separate from compilation/capture. See
`docs/PROGRESS.md` for the latest actual evidence and remaining live checks.

## Continuous implementation and actual Minecraft evidence

`HudStreamLab` is a separate opt-in Creative lab; the completed snapshot mode stays
intact. Normal vanilla rendering supplies a 20-second sequence of hotbar selection
0, selection 1, the real Creative inventory, and selection 2 after closing it.
The existing three-PBO adapter retains original capture timestamps and rejects
out-of-order completed capture IDs. A latest-frame mailbox hands pixels to a worker
for conversion, transport and bounded evidence output. Java remains on its Java21
bytecode baseline and uses Minecraft's existing JNA 5.14.0 dependency.

The original [stream contract](../../protocol/HUD_STREAM.md) defines an 8,294,656-byte
pagefile-backed mapping and a separate Win32 mutex with fresh run-derived names.
The producer refuses existing objects; the receiver only opens existing objects.
Every header repeats the exact PID/creation FILETIME identities and immutable
expiry. Mutex waits are at most 5 ms, abandonment terminates the session, and
validation/conversion uses a private snapshot. A lease lasts at most 180 seconds;
replayed frames cannot refresh it or image freshness. Mapping and mutex APIs run
only on workers. The 65,536-byte gameplay socket protocol is unchanged.

`hud_stream_addon.cpp` follows the inspected EldenCraft upload pattern using public
ReShade APIs: one persistent texture, three aligned upload buffers, barriers and
copy fences. Semantic bindings change only on allocation/reload. Busy upload slots
drop updates, and the renderer separately expires the frame actually uploaded
500 ms after its local receiver observation. Closed, invalid or exited producers
hide the layer. Upload fences cover staging reads; safe lifecycle queue-idle
cleanup protects later texture draws. Effect handles are forgotten before reset
cleanup, and callback contention disables the layer through a fresh current
runtime handle without dereferencing shared service state.

ReShade's public signal and semantic APIs may internally flush or wait. The frame
path performs no file/mapping IO and never waits for a free upload slot, but is not
claimed to be entirely nonblocking. On expiry, GPU resources remain allocated
until runtime reset/unload rather than being freed while effects may still use them.

The fresh actual-Minecraft run in
`runtime/evidence/hud-stream-20261012-212421-479e9128381f425f8c6c3f9ae73bdc4d`
published and received 344 nontransparent frames. The native receiver saw all four
states, became inactive during an intentional publication pause, resumed on fresh
frames and observed closure. Client/server inventories agreed, saved PNG samples
were visually inspected, and Minecraft saved/exited normally. This run targeted
the standalone controller process; it did not arm or display the stream in KCD2.

Validation passes 168 Java stream checks, the existing 36 snapshot checks and
146 native checks. The separately frozen native build/review receipt is
`runtime/evidence/hud-stream-native-frozen-3bc7270598a34b42bc8738cb919966e2/verification.json`.
The real transport run and frozen build retain their own artifact hashes, keeping
actual process evidence distinct from the later reviewed/rebuilt add-on.

## Installed stream and live check

The continuous add-on, including the aspect-fit correction, was installed unarmed
from `runtime/hud-compositor-stream`. With KCD closed, the updater replaced only
the owned add-on, preserved its predecessor and enabled the pinned owned proxy
last. Both PowerShell 5.1 and 7.6.5 preflight passed. Deployment evidence is
`runtime/evidence/hud-update-20261012-213418-25efcf776e664040bd9047eb4974aa82/update.json`.
The old static arm was archived; the owned empty mod-order list remains for the
controlled renderer comparison and must be restored by ownership-checked cleanup
after the comparison and normal closure.

With a fresh user-started tools world ready,
`Start-HudStreamLab.ps1 -Composite` in PowerShell 7.3 or later starts the isolated
Minecraft stream and arms the already-loaded add-on. Pass the absolute
`runtime/hud-compositor-stream` path with `-BundleDirectory`. The controller never
starts, stops or controls KCD2. Its `-Standalone` mode runs actual Minecraft and the
native receiver without requiring KCD, and cannot be combined with `-Composite`.
`Arm-HudStream.ps1` checks the loaded owned artifacts and fresh genuine-producer
receipt before publishing a create-new arm file.

The first live run delivered 240 frames to the receiver and uploaded 200 fresh
frames in KCD, submitting 1,882 draws before normal closure. The user confirms
the HUD is visible but now too large, with the original KCD HUD still present.
The 854x480 source used vanilla GUI scale 2; GUI size needs adjustment separately
from the full-canvas aspect fit. Individual slot/inventory transitions were not
separately confirmed visually. Evidence is in
`runtime/evidence/hud-stream-20261012-214338-3cd7ea7bb557436cba1f428b94f7b72d`.

Next comes a
separate vanilla UI input mode with focus, release and host-menu arbitration.
The walking observer currently disarms on buttons/wheel, and the movement lab
rejects menus; neither controls inventory. Slot clicks, crafting, held hands,
survival HUD coverage, HDR and GPU sharing remain outside this lab.

## Host HUD and health are separate integrations

The pinned references both remove overlapping host HUD information, but they do
not use the same health authority. [SkyCraft's HUD controller](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Game.cpp#L331-L350)
hides Skyrim's player status/equipment widgets while preserving the compass,
interaction prompt and enemy health. Its [combat bridge](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Combat.cpp#L125-L169)
refunds Skyrim damage and forwards it into Minecraft, which owns player health.

[EldenCraft's native controller](https://github.com/SocketByte/EldenCraft/blob/ba7591cdde9fb16e17552cfe53546f44d0fd856e/native/src/host_hud.rs#L180-L235)
reversibly suppresses the host status/equipment HUD. Its [health display adapter](https://github.com/SocketByte/EldenCraft/blob/ba7591cdde9fb16e17552cfe53546f44d0fd856e/minecraft/src/client/java/dev/eldencraft/bridge/client/HostHealthDisplay.java#L32-L65)
maps actual Elden Ring HP/maxHP into Minecraft heart rendering and restores the
guest value immediately afterward; that display scope does not replace server
health authority. MineCome currently implements neither health bridge nor KCD
HUD suppression. Copying the rendering architecture does not choose a health
authority automatically, and foreign engine hooks cannot be reused in KCD.
