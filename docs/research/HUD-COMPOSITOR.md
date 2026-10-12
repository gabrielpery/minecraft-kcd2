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

Next stages are continuous bounded frame transport and host-to-vanilla UI input
with focus/release handling. Drawing the inventory screen alone does not verify
clicking slots, crafting, or KCD menu/input arbitration. The existing movement and
stone labs remain independent while this rendering path is brought up.

## Validation and limits

The pure Java tests cover pixel orientation, alpha conversion, PNG encoding,
output ordering and bounds. The native contract tests cover malformed arming,
identity, expiry, dimensions and compositing math. `minecome_check_hud_fx` compiles
the actual FX using ReShade's DXBC 5.1 backend at two resolutions. These checks
cannot establish that the game loaded ReShade or presented the layer.

The final offline build passes 36 Java pixel/output checks and 117 native contract
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
exit code. The hook remains disabled; the fixed build is staged locally and has
not been installed. Host visual composition is still unverified.

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

After closing KCD normally, the user can run this block in their existing PowerShell
window. The launch helper selects an existing PowerShell 7 runtime automatically.
Any terminating update error stops the block before game launch:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    & 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Update-HudCompositor.ps1'
    & 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-Kcd2ToolsTest.ps1'
}
```

The successful zero-mod diagnostic's owned empty mod list stays in place for this
renderer-only comparison. Its eventual restoration must verify the original file
identity and empty contents after game closure. Once the new world is ready, use
`Arm-HudPreview.ps1` with the existing verified three-frame Minecraft capture and
`-BundleDirectory runtime/hud-compositor-resetfix`. No new Minecraft launch is needed
for this static display proof. A new user-confirmed host frame is still required;
the previous guest capture and successful baseline launch do not establish it.

The SDK, official runtime, generated captures and Minecraft assets remain local
under ignored directories. No original game executable is overwritten. Runtime
installation and a fresh game start are separate from compilation/capture. See
`docs/PROGRESS.md` for the latest actual evidence and remaining live checks.
