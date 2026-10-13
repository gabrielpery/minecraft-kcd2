# Genuine Minecraft UI inside KCD2

The required architecture is Minecraft's real HUD and screens captured as pixels,
then composited in the host renderer. There is no desktop overlay, hand-drawn
hotbar, web UI, or replacement inventory implementation.

**Current result:** the user has verified live 1/2/9 hotbar selection, E/Escape
inventory control and accepted HUD size in KCD2. Ten physical press/release events
were acknowledged; the temporary host cap and guest state were restored, and
Minecraft exited normally. The subsequent diagnostic run confirms the same
controls with no KCD menu reported, and records a foreground-loss stop after
15.766 seconds. Bounded host HUD suppression is implemented with live CVar
restoration verified. The separate strict mouse profile has now completed a full
30-second physical test, with user-confirmed inventory interaction. Combined
host-HUD appearance, general input exclusivity and health integration remain unverified. Detailed evidence
and the earlier failed runs are recorded below.

## Selective camera capture — 2026-10-13

The separate `-SelectiveMouse -WorldClicks` profile uses API v2 and its own
`MineComeHudSelective.ini` arm file. World mode suppresses DirectInput buttons
while preserving X/Y/Z motion. Inventory mode suppresses the complete mouse.
The verified API v1 mouse/world binaries and profiles remain frozen.

The native runtime still gates the exact foreground game window, canonical
relative mouse layout, owner token and 100 ms renewable lease. Full/button mode
changes increment generation, retain ownership and suppress all input until
each device drains its prior state and buffered queue. The addon never forwards
world or inventory pointer events during that drain. E/Escape requests full
capture before forwarding the key. Returning from inventory requires its
acknowledgement, a matching uploaded screen and two neutral frames. Input that
contradicts an unfinished mode switch closes the bounded session; pause briefly
after closing inventory before clicking.

Buttons-only buffered input uses a bounded FIFO of axis records. It preserves
order, timestamps, application data, DX3/full layouts and repeated PEEK semantics
while consuming suppressed physical button records. Capacity or unknown-layout
failure revokes capture instead of silently dropping movement. Only owned,
settled buttons mode permits the existing cursor-position/clipping hooks to
pass through; keyboard, raw mouse messages and window-message blocks retain
the inspected ReShade behavior. The exact pinned upstream patch is separately
built, with no engine offsets or additional game APIs.

The selective compositor and all three existing input variants compile in
`build/hud-selective-20261013`. Forwarding ownership and mode boundaries pass
107 assertions; controller configuration/receipt checks pass 976. These are
automated source/build checks, not proof of live KCD camera behavior. The same
30-second activation and sixteen-click bounds still apply. The Minecraft guest
is unchanged and still interacts with the fixed verified stone cell.

Pure shared aiming geometry additionally passes 198 Java and 222 C++ assertions
using 22 common golden vectors. `protocol/PROTOCOL.md` records the proposed
future alignment/ray handshake, owned stone cluster and host occlusion check.
The wire version, actual vanilla interaction path and live targeting are
unchanged; crosshair aiming is not yet enabled.

The final native adapter passes 775 checks, including expiry/focus/mode changes
during original device calls. Review found and fixed a late immediate-state
publication race before accepting the runtime. The cursor patch also covers
ReShade's direct per-frame clip call, retaining the game's saved cursor boundary
only while settled buttons ownership is active. Selective/World/Mouse profile
checks pass 142/110/23 under both PowerShell 5.1 and 7.

The accepted 53.28-second runtime build is recorded at
`runtime/dependencies/reshade-selective-6.8.0/evidence/20261013-173502-b0870f4dcc4e4a1da528e43eae2f4138/verification.json`.
Source, generated-output, reference and installed-proxy checks all pass;
bit-for-bit build reproducibility is not claimed. An earlier build correctly
failed its final source-change check while the review fix was applied; that
output was never staged or installed.

- Runtime SHA256: `2157f25f36baebe1c577cb3c6d8a485691fbacc727262d1a4bc09f9265522511`.
- Addon SHA256: `15f3ac12101f0a1f36aa731c89f5df9018dc8d0b43d1e966117f78d138fba4de`.
- Frozen profile: `config/hud-selective-profile.json`.

After verifying a backup of 1,013 save/profile files, the previous owned World
arm was archived and its proxy disabled. Update
`runtime/evidence/hud-update-20261013-163734-14f01c89ad8b47bf83bda88c4d500d5f/update.json`
records replacement of only `dxgi.dll` and the addon, with exact old-file backups
and an unarmed enabled installation. No game was launched or stopped. The user
restart and a combined camera/inventory/world-click check are still pending.

## Physical world click profile — 2026-10-13

The new explicit `-WorldClicks` controller removes the timed demonstration and
admits physical right/left presses as place/break requests. It requires the same
actual HUD guest, `-Mode Live -LiveMouse -StoneLive -OffscreenPresentation
-HostGpuBudget`, and the separately pinned World renderer. The original mouse
profile and prior successful combined preview remain preserved.

The render callback samples fresh button edges into a fixed queue, with two
neutral captured frames before entering world controls. Inventory transitions
still require matching guest ACK and uploaded screen. The worker checks the
same active mouse lease/window/token/generation, live image and UI acknowledgement
before emitting a bounded run-tagged record. It waits for preceding hotbar key
events to be acknowledged. A stale queued edge closes activation instead of
skipping its sequence. At most sixteen presses are emitted per activation.

The controller pins ReShade.log's file identity and starting offset before
arming, retains partial UTF-8 lines, and validates exact run and sequence.
Expired, too-rapid and out-of-focus edges are explicitly declined. Each admitted
edge is linked to its Lua request ID and the existing guest/native confirmation
chain; ambiguous commands are never retried. Occupied/absent/vanilla-failed
results are now retained alongside the existing transport refusals. An input
acknowledgement is not evidence of a changed block.

This first mode deliberately holds the existing full mouse-capture lease while
the inventory is closed, freezing KCD mouse look. It controls the verified nearby
cell; it does not raycast or implement free crosshair targeting. The 30-second
limit, exact official-tools executable gate and focus-loss shutdown remain.

Native policy/queue, mouse forwarding, UI channel and strict capture checks pass
623 assertions. The World profile/mode/old-install ownership checks pass 110
under both PowerShell 5.1 and 7; the original mouse checks still pass 23.
Native addon SHA256:
`8d65235dcb59bf0f27300164c46ecb357983513d41150df69055b21614265cdb`.
The existing proxy, shader and mouse ABI are unchanged.

Controller checks pass 939 assertions; click-reader/relay checks pass 85/221 and
the existing window cleanup checks pass 45. Java stone-proof/stream checks pass
227/209 and `remapJar` succeeds. A completion fix recognizes actual confirmed
live block actions when no hotbar key was pressed; the mode flag alone cannot
turn an idle, refused or failed session into success. The rebuilt JAR SHA256 is
`316fee561768ac33a51ca012ee5e4b2655010ce8d6e5e61ae2369d9f6764755d`.

After verifying a backup of 1,012 save/profile files, the previous receipt-owned
expired arm was archived. The six-file ownership preflight passed; only the
addon changed in the installed World bundle. Installation is unarmed and recorded
at `runtime/evidence/hud-update-20261013-160448-76f8582832284464b12ae8336241d5fb`.
No game was launched or stopped during installation.

**Live result:** run `62b35872e09d44a3b6b3a5474131e24e` passed against official
KCD PID 45788. The user answered "it worked fine." Four native click records
with actions place/break/place/break matched Lua requests 1–4, four successful
guest dispatches and client/server confirmations (66/66/67/66 ms server ages).
The selected slot stayed 0 with 64 stone. KCD session `1791907693381701` spawned
and removed the same cell `(4,-60,2)` twice near `(122.05,2045.23,56.29)`.
Final air, no pending/cancelled requests or inventory mutation, engine cleanup,
normal Java/relay exit0 and restoration of the temporary FPS cap to -1 all pass.

This live run exercised **zero UI key or inventory pointer events**, verifying
that confirmed physical world actions can complete independently. It published
575 genuine frames; KCD uploaded 557 and submitted 2,325 draws with zero drops.
Strict capture recorded 854 immediate-state suppressions and 854 drains, with
zero drain failures. No buffered/peek calls were exercised, and the release
receipt still marked final drain pending; general input exclusivity remains a
separate claim. Inventory transitions and rejected clicks were not live retested.

The native first-close record identifies foreground loss after 13.719 seconds,
with fresh ACK/image state. This was a protective closure, not a crash or the
30-second timer. The bounded one-cell interaction is verified; normal mouse
look, crosshair targeting and continuous play remain unfinished.
Evidence, exact-run native log and separate user observation are preserved at
`runtime/evidence/hud-input-20261013-160712-62b35872e09d44a3b6b3a5474131e24e`.
Raw machine receipts retain their conservative visual/physical claim flags;
`live-analysis.json` records the combined correlation and direct user report.

## Combined live relay controller — 2026-10-13

**Live result:** run `a80522b281a64a238e8d66a61dee7fbe` passed in official KCD PID
49776. The user answered "i indeed saw both" to the combined hotbar/stone preview.
Actual guest request IDs 1/2 each returned accepted and had fresh client/server
confirmation (33/32 ms server ages). Minecraft cell `(2,-60,-10)` was mirrored at
approximately KCD `(121.20,2045.23,56.29)`. Native session `1791906257712605`
acknowledged spawn sequence429, removal sequence640 and final cleanup with zero
owned/pending entities. The guest ended with air, no pending action and no failures.

The guest published 577 genuine frames; KCD uploaded 559, submitted 2,330 draws and
dropped zero uploads. Both physical `1` key edges were applied and acknowledged.
No inventory pointer actions were requested or claimed. Native input ended after
18.375 seconds when KCD lost foreground; ACKs remained fresh and the resident image
was 47 ms old. The block cycle had already completed. This verifies the combined
cycle and focus-loss cleanup, not a full thirty-second activation.

The exact owned guest window remained hidden under `hidden_until_process_exit`,
then the controller observed actual Java exit0. The relay also exited0 after its
cleanup ACK. The temporary host FPS cap restored from60 to its original -1 and
cancelled its timer. These are live shutdown diagnostics; no separate no-popup or
inventory-smoothness judgment was requested. KCD was left running after that test. Evidence,
run-scoped native logs and the verbatim user report are under
`runtime/evidence/hud-input-20261013-154322-a80522b281a64a238e8d66a61dee7fbe`.
Machine-only receipts retain `visual_verified=false`; `live-analysis.json` records
the separate user observation.

The new explicit `-StoneLive` profile connects the existing `HudStoneBridge` in the
HUD world to the original native official-tools relay. It requires Live mode,
the mouse profile, offscreen presentation and the temporary 60 FPS host budget;
fixture modes remain mutually exclusive. Java and readiness/arming metadata
independently enforce those choices. The installed renderer is unchanged.

`HudStoneRelay.ps1` checks the pinned KCD executable, process identity, loopback
owner and staged Lua/stone package. It reloads a unique read-only source snapshot
through the existing engine API and verifies the changed function and token/input
contracts. The existing native relay starts with a new evidence-local home and
random token, a bounded deadline and an owned stop file. It never starts or stops
KCD. The same actual Minecraft instance produces UI pixels and block events.

The controller waits for that run's physical F8 activation and the exact HUD save's
authenticated stone readiness. After two seconds it calls the existing Lua
`InteractiveIntent(1)` through the console API, without typing into the game.
Both actual Minecraft confirmation and matching KCD spawn event/ACK must arrive.
After ten seconds of confirmed dwell it sends the break intent. Dispatch stops
after twenty seconds or observed HUD closure; the normal thirty-second input
limit remains. The preview expects one accepted placement and one accepted break.
It does not forward physical world mouse clicks or introduce new targeting.

For this block preview, pressing `1` after F8 provides an actual UI event and keeps
stone selected. Inventory mouse gestures are optional; zero pointer events do not
claim mouse verification, and neutral pointer cleanup is still required. The
ordinary mouse test continues to require real pointer events. Keep inventory
closed and stone selected until the preview finishes.

Completion correlates engine-generated request IDs, protocol results, actual
client/server confirmations and native engine events for the same cell. It also
requires authenticated protocol1.1 Minecraft-role transport, native begin/end
acknowledgements, normal relay/Java exits and host FPS restoration. The relay is
stopped in `finally` even after startup or arming failure; diagnostic failures do
not skip the independent host HUD/FPS cleanup. Ambiguous console dispatch is
recorded once and never retried. Partial engine or guest proof fails the run.

Java compilation/remapping and 2,869 mode, lifecycle, stream and input checks pass.
PowerShell checks pass 887 controller/shared relay cases, 206 relay lifecycle and
receipt cases, 385 existing fixture cases and 45 window cleanup cases. The same
live receipt is exercised through both production validators to keep their
terminal and mode contracts aligned.
The original native interactive relay also passes its simulated HTTP/engine/peer
integration (`runtime/tools-stone-fixture-AgTAMz`). Those are build and standalone
results; the separate combined live display evidence is recorded above.
The built JAR SHA256 is
`880a495c2243773ee807a1e2c7b59d6bdf50ec4a91ba2e3ac3b2f062bee77961`.

The first actual Minecraft regression run
`3ce29211ba0a4bdcb3cea6698fdcddf6` completed its first placement, then failed because
the Node test peer read a step file while the native writer still held it. The
Windows `EBUSY` collision now retries only pending-step reads within the existing
hard deadline; malformed, oversized, consumed/replayed files and other errors
still fail. All 136 Node checks pass, including transient and persistent contention.
The failed receipt is preserved. The subsequent real run
`27abc962974c423d91021a479407d440` passed all eight UI edges and six requests,
including four client/server-confirmed changes, 209 genuine frames and normal
shutdown. Its evidence is in
`runtime/evidence/hud-input-20261013-153925-27abc962974c423d91021a479407d440`.

## Combined HUD and stone guest — 2026-10-13

`HudStoneBridge` reuses the HUD lab's exact client world, player, integrated server
and save. The existing authenticated minor1 bridge sends real Minecraft poses
and accepts stone requests. The bridge owns one cell beside the player; it creates
no second world and does not change inventory or camera. UI events apply before
block requests in the same client tick, so selection and screen state govern the
actual vanilla interaction. Breaking remains valid with dirt selected in Creative.

Dispatch requires fresh armed HUD state, no open screen/overlay, a loaded reachable
cell, solid support and a matching authoritative server observation. Placement
also requires selected stone and matching server slot/item/count. Vanilla
`interactBlock`/`attackBlock` execute on the client thread. A block event follows
only after fresh client and integrated-server agreement. Ownership changes,
transport loss or unexpected cell changes close the bridge. Pending actions and
diagnostic records are bounded; final proof requires no outstanding action and
the cell restored to air.

This first combined mode is deliberately standalone: `Start-HudInputLab.ps1
-Mode Fixture -OffscreenTrial -StoneFixture` starts an isolated Minecraft instance,
a native reverse-UI fixture and an explicitly synthetic localhost protocol host.
The peer uses a fresh token, bounded run-scoped receipts and an immutable expiry;
it maintains synthetic host poses until the real guest closes. Live arming rejects
the stone-fixture markers. The installed KCD renderer and live mouse profile are
unchanged. Connecting the combined guest to the actual KCD relay, general block
targeting and physical world clicks remain unfinished.

Run `11f348f356984192a50f20d858d3ba30` passed with evidence under
`runtime/evidence/hud-input-20261013-151830-11f348f356984192a50f20d858d3ba30`:

| Step | Real guest state | Request and verified result |
|---|---|---|
| 1 | Stone selected, inventory closed | Place accepted; client/server stone |
| 2 | Dirt selected, inventory closed | Break accepted; client/server air |
| 3 | Dirt selected, inventory closed | Place refused: `selected_item_not_stone` |
| 4 | Stone selected, inventory open | Place refused: `screen_open` |
| 5 | Stone selected, inventory closed | Place accepted; client/server stone |
| 6 | Stone selected, inventory closed | Break accepted; client/server air |

All eight UI key edges were acknowledged and applied in the hidden, unfocused
guest. Four block events matched the fixed cell `(-8,-60,2)`; server observation
ages were 33, 67, 34 and 66 ms. All nine inventory stacks matched their original
client/server contents. The guest published 209 genuine frames and the native
receiver received 208, with zero mailbox replacements, PBO busy skips or fence
timeout polls. Maximum readback age was 54 ms, client tick gap 111 ms and own-image
age 108 ms. The closed ACK took 47 ms. Guest, native fixture, protocol peer and
controller all passed; the actual Java process exited normally with code 0.
KCD was closed, so these results do not establish host composition or physical input.

The build passes 51 gate checks, 74 terminal-proof checks and 692 existing focused
Java checks (817 total). Native fixture checks pass 181 new plus 338 existing
cases; the protocol peer passes 120 checks. All 373 PowerShell receipt checks pass, validating the
exact request reasons, selected items, server observations, unchanged inventory
and explicit standalone scope. Independent implementation review passed.
The built JAR SHA256 is
`d0e1cb000b33856bbb76cb7ae38ca93d1a5f7393864747f7be245c86f9b4af5f`;
the native input fixture SHA256 is
`1feab52b14dc608622a8b2256d915a3a47264b4b2588d2055fac66a77a4cb35c`.

Two earlier actual runs remain failed receipts. Run
`0e64fe9b04254508905be8aa081e64f3` refused its first request before any block change.
Inspection found a snapshot/clock-ordering race; observations are now acquired
before their age is measured, retaining strict negative-age and freshness checks.
That original receipt did not identify the exact failing predicate. Run
`99c035f3db434934837f84bc90d98b60` completed the block sequence but failed the old
terminal requirement to select all nine slots. A separate `HudStoneProof` validator
now checks the combined sequence without weakening the existing inventory fixtures.

## Inventory capture cadence — 2026-10-13

The 50 ms capture minimum combined with the 30 FPS guest cap skipped alternate
rendered inventory frames. `HudCaptureCadence` now permits one capture per render
only for actual supported vanilla inventory screens with input, mouse forwarding,
offscreen presentation and the applied cap. Hotbar, keyboard-only, visible-window
and automated snapshot modes retain the 50 ms minimum. The render cap, capture
ordering, three bounded PBO slots, freshness/ACK checks and native profile are
unchanged. There is no catch-up loop or additional timer.

The 45 new regression checks exercise the 30 FPS/50 ms scheduling interaction,
scope restrictions and independent per-screen timing. Together with the existing
pointer, stream, input and window-cleanup suites, 692 focused Java checks pass;
compilation/remapping and independent review also pass. The built JAR SHA256 is
`104a827a4b398d855892d0e54a399e2336113c784fdaa4cab6ea8e8e6f5ef4fe`.

The actual Minecraft `Fixture -OffscreenTrial -PointerFixture` run
`e58de09d9e734576b723f2f6c852d1b3` passes, with evidence in
`runtime/evidence/hud-input-20261013-144908-e58de09d9e734576b723f2f6c852d1b3`.
All 43 events and 11 server-observed inventory stages completed while hidden and
unfocused, including splitting, dragging, scrolling and held-button closure.
Minecraft published 241 genuine frames; the standalone receiver received 240.
The 46 successful inventory captures had 44 adjacent same-screen intervals,
averaging 32.914 ms, maximum 36.294 ms. The hotbar mean was 67.061 ms. These are
capture-enqueue measurements, not displayed FPS or end-to-end click latency.

No PBO busy skips or fence-timeout polls occurred. Maximum readback completion
age was 44 ms, client tick gap 103 ms and own-image age 133 ms. Normal Java exit 0,
closed ACK and ordinary fixture window/settings/handle restoration passed.
KCD was closed and no compositor was armed. This does not live-verify the earlier
hidden-until-exit policy, which intentionally applies only to explicit live mouse
sessions. Combined KCD smoothness and no-popup behavior remain pending.

## First live inventory mouse check — 2026-10-13

The user launched the updated tools world, PID 18468, and confirmed it ready.
Run `78b4a2ef7c6d4fa39e24152be460952f` at
`runtime/evidence/hud-input-20261013-142525-78b4a2ef7c6d4fa39e24152be460952f`
passes. The user reports that the mouse test worked, with a reappearing Minecraft
window and some lag there after Escape. ReShade loaded the custom proxy/addon,
compiled the cursor shader and recognized one eligible mouse. F8 activated the
original 30-second gate; the final close cause is `activation_expired`, elapsed
exactly 30,000 ms, with all focus/freshness predicates passing.

All 639 events were acknowledged/applied, including 635 pointer events. The real
vanilla adapter recorded 20 clicks, 20 releases, 26 drag calls and 32 wheel calls.
Held buttons, pending releases and active-button state were neutral before and
after cleanup. Minecraft published 774 genuine frames; KCD uploaded 499, submitted
2,091 draws and dropped no uploads while eligible. Maximum client tick gap was 122 ms,
own-image age 151 ms and client ACK age 157 ms, all within the unchanged guards.

Native mouse ownership recorded 1,535 immediate state suppressions and 1,535 drains,
zero drain failures, and no buffered/PEEK suppressions observed in this run. The
release receipt at 15:26:39.799 marked its final drain pending; no later snapshot
certifies that final drain. This is evidence for the observed immediate DI path,
not general host input exclusivity. Run-scoped native receipts are saved in
`native-mouse.log`, with the user statement and bounded analysis in
`live-analysis.json` beside the controller receipt.

Minecraft acknowledged closure, restored controls/handles/settings, saved and
exited normally with code 0. The temporary host FPS budget restored −1 after 60:
`runtime/evidence/hud-gpu-budget-20261013-152550-f2880897bf244dd1bfa19ad5fe8cd302`.
No KCD process was started or stopped by the controller. The popup was explained
by the existing `restoreOwnedWindow` call showing the guest before `scheduleStop`;
the process then spent about seven seconds saving/exiting. The narrow hidden-exit
repair below is now compiled for the explicit live-mouse profile. No native rebuild is needed.

Separate timing analysis observes 14.8–15 content uploads per second and about
62 composited frames per second. The 50 ms capture minimum with a 30 FPS guest
skips alternate capture opportunities. The later capture-per-render change is
recorded above; this live run did not measure true end-to-end click latency.
Cadence was unchanged in the initial shutdown-window repair. No PBO busy skips, readback fence timeouts, mailbox
replacements or native upload drops occurred in this successful run.

### Guest shutdown-window repair

`HudWindowCleanup` retains the same verified owned GLFW window hidden only for
explicit non-fixture live mouse input with offscreen presentation. Repeated
terminal/CLIENT_STOPPING cleanup does not show it. Saved options and presentation
settings are restored, while native resize/fullscreen transitions are deferred
until process destruction. Inspection of the pinned Minecraft option callback
and `Window.toggleFullscreen`/`swapBuffers` bytecode verifies that cancelling the
pending logical fullscreen flag prevents an implicit native transition. Fixture
and keyboard profiles preserve their existing visibility-restoration behavior.

The receipt uses `policy=hidden_until_process_exit`, `hidden_for_exit=true` and
`restored=false` when the original window was visible. It identifies the same
owned hidden window, records actual visibility/focus attributes and explicitly
does not claim process exit from inside the guest. The controller retains the
exact Java process handle, waits independently of its Gradle wrapper and requires
an observed normal Java exit before accepting this policy. Missing legacy policy
is allowed only under the prior ordinary-restoration checks; unknown declared
policies are rejected.

The JAR for that repair was
`1e82715a15dbc130fe31fc153489b19ca27cb21ca266ac941e8f788de9d349ff`.
Compilation/remapping, 57 cleanup operation/policy checks, 45 pointer checks,
focused controller receipt checks and all 397 existing cleanup checks pass.
Independent review passed. This repair has source/build/automated evidence;
physical no-popup behavior awaits the next session. The working native profile,
capture cadence and freshness limits were unchanged.

## Physical inventory mouse implementation — 2026-10-13

The separate `minecome_hud_mouse_compositor` target retains the accepted 1280x720,
GUI-scale-2 canvas. ReShade's actual client-coordinate cursor is mapped through
the same aspect-fit rectangle used for composition. Left/right edges, held drags
and wheel events travel through the existing reverse channel to real vanilla
screen callbacks. An original arrow cursor is composited because the OS cursor
is absent from Minecraft's framebuffer; the inventory/hotbar remain captured pixels.

The original extension in `kcd2/reshade` reuses the pinned DirectInput8 A/W hook
chain. Every observed mouse must have the same host HWND, a canonical relative
DIMOUSESTATE/2 layout and an actual relative-axis property readback. Other HWNDs,
unknown formats or aliases, action maps, failed classification and capacity loss
refuse capability. No guessed engine method or offset is introduced. The render
API uses nonblocking state access and a process/window/token-bound 100 ms lease.
Only device callbacks invoke the original COM methods. Successful captured state
and buffered polls suppress axes/buttons/wheel, including PEEK, and drain both
immediate and buffered input. Failed original HRESULTs are preserved. Generation
changes, focus loss and lease expiry withdraw ownership. Detailed contracts and
SDK hook slots are in `kcd2/reshade/README.md`.

The add-on requires capability before accepting its one-shot F8 activation.
Inventory transitions wait for both the guest ACK and an uploaded matching screen.
Two neutral captured frames prevent held-button entry clicks. E/Escape first
releases forwarded guest buttons; capture remains until the closed-screen ACK
and neutral physical buttons. The original 30-second activation limit and frame/
ACK freshness checks remain intact. The keyboard target retains its original
profile. Mouse receipts use a fixed 32-record queue; formatting and ReShade's
synchronous log writes run on the worker, with counted diagnostic overflow.
A release receipt arriving after worker completion can wait until addon unload;
an absent receipt is never evidence of successful live restoration.

`Build-MouseReShade.ps1` uses a fresh private checkout and the verified pristine
build's generated GLAD files, with no object/DLL reuse or generator-network
fallback. The exact four patched source files, staged tree/diff, generated files,
exports and 29 license records are verified. The pristine build/reference and
installed proxy were unchanged during this build. Final receipt:
`runtime/dependencies/reshade-mouse-6.8.0/evidence/20261013-151144-f602cd6d508544929cc2688478ee9648/verification.json`.
The DLL is 5,606,912 bytes, version `6.8.0.2 MINECOME MOUSE UNOFFICIAL`, SHA256
`1798af0815f1e3ad6b7ba86d0a065181158dbaaf0dcaf600ea2981642217118f`.
The final addon SHA256 is
`e947533ec27e70a4782fa3c4e40df4d2fc69d85b00d768393bd1c43345fb34ca`.
`config/hud-mouse-profile.json` pins the runtime, addon, shader, build receipt,
patch and ABI. Staging aggregates all verified notices, explicitly transcoding
the pinned Direct3D12-on-7 Windows-1252 notice without replacement characters.
No game assets or third-party source/binaries are committed.

Five focused CTest suites pass: 56 capture/real-SDK-adapter checks, 95 pointer/
diagnostic checks, 338 transport checks and both original/mouse FX shaders compiled
to DXBC. Both addon targets compile. The Java update passes 590 focused checks;
explicit live mouse and fixture modes cannot be mixed. The controller requires
matching Boolean readiness/result fields and reports `live_mouse_guest_pass`
separately from still-false host-exclusivity and visual claims. Its production
cleanup harness retains all 397 passing checks. Independent native, guest and
deployment reviews passed. Profile/artifact rejection and actual owned-file
replace/rollback tests pass 23 checks each in PowerShell 5.1 and 7.

Fresh real Minecraft regression:
`runtime/evidence/hud-input-20261013-141618-2a7f426275374735a38b9a1f0870916f`.
All 43 hidden/unfocused events passed across 11 stages, including actual 32/32
split/drag results and Creative scrolling. The guest published 218 genuine frames;
the native fixture received 216. Stage server ages were 3–49 ms, max client tick
gap 109 ms and max own-image age 154 ms. The real closed ACK arrived in 31 ms;
pointer state, settings, window and handles restored, then Minecraft exited 0.
KCD was closed, no compositor was armed and no physical host input was involved.

After verifying a fresh backup of 1,010 save/profile files at
`runtime/backups/20261013-151955`, the expired old arm was archived and the exact
owned six-file installation updated. Receipt:
`runtime/evidence/hud-update-20261013-142112-0a6ed12e8fa84d51b989be9810d1cdd2/update.json`.
`runtime/hud-compositor-mouse` is installed **unarmed**. It includes the tutorial
prompt setting below. No KCD launch occurred. Live loading, cursor mobility,
drag/scroll delivery and camera suppression remain the next physical checks.

Once a fresh test world is ready, the controller command is:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-HudInputLab.ps1' -Mode Live -LiveMouse -OffscreenPresentation -HostGpuBudget -JavaHome 'C:/Program Files/Java/jdk-24'
```

This must precede the user's F8 instruction; do not start its short countdown while
the user is still launching KCD. Mouse mode defaults to the exact mouse bundle.
If a startup rollback is needed after KCD closes, `Disable-HudCompositor.ps1
-LiveMouse` disables only that owned proxy and preserves its installation files.

## Real inventory pointer fixture — 2026-10-13

The separate `-PointerFixture` option uses 43 records and 11 independently checked
stages. Actual vanilla Creative screen calls split a 64-stone stack with right
click, restore and pick it up, distribute 32 stones into each of two empty hotbar
slots by dragging, scroll the real Creative item grid and restore its position.
Closing while a button is held releases the original screen. Reopening creates
a new screen, and the late button-up event is consumed without releasing that
new screen. Targets come from actual screen/slot geometry; no inventory mechanics
are reimplemented. Each stage compares all nine client/server slots, fresh server
observation age, cursor contents and actual adapter callback counters. The
Creative cursor is a client observation, not a server cursor claim.

The first actual run, `hud-input-20261013-132250-9180f7b941264fccbdd655d31ea84e2d`,
passed splitting, dragging and scrolling but failed native receipt validation at
event 38. Gson omitted the explicit null scroll position of the closed screen.
Pointer-only serialization now preserves that null, covered by real disk-writer
regression checks; ordinary mode serialization is unchanged. The native reader
still requires the field and now saves bounded, escaped exception details.

The repaired run passed:
`runtime/evidence/hud-input-20261013-133209-73736e8cbcff406db59857d5657d9870`.
It published 219 genuine Minecraft frames, received 217, acknowledged all 43
events and validated every stage. All events occurred while hidden/unfocused;
the preceding actual offscreen observation lasted 12.019 seconds. Stage server
ages were 0–48 ms, maximum client-tick gap 107 ms and maximum own-image age
166 ms, within the unchanged 250 ms gates. Closed ACK took 47 ms; Minecraft
saved/exited normally with code 0 and restored its window/presentation settings.
The temporary host 60 FPS cap restored to its original -1 setting, recorded in
`runtime/evidence/hud-gpu-budget-20261013-143208-11aada23b7764eaf8d5078415146d645`.

Frozen guest JAR SHA256:
`2c1286291f37b254b6f5df722fec45a4825160644cdbdd68403e569ca9e1638d`.
Native fixture SHA256:
`f5c945ec5e8b5bba6007892fb9636eb84c6f0ddbe0c1ef198664bf2ef2729cce`.
Focused checks pass: 338 native, 353 Java input, 37 pointer-state, 20 evidence
writer, and 397 PowerShell host-HUD lifecycle checks. Independent cross-language
review passed. No KCD compositor was armed and no physical KCD mouse input was
sent. Live mouse ownership, cursor presentation and camera suppression remain
the next implementation work.

The unchanged baseline native executable was also rerun against the updated
guest: `runtime/evidence/hud-input-20261013-133334-2fd34faafe88466c9797b36889a7bc1f`.
All 31 original events and the real server-confirmed stack swap passed, with 203
frames published and 202 received. All events ran hidden/unfocused, Minecraft
exited with code 0, and guest presentation/window plus host FPS restoration
passed. This preserves the earlier working path independently of the richer
pointer fixture.

## Private ReShade build prerequisite — 2026-10-13

`scripts/Build-CustomReShade.ps1` now builds the pinned 6.8.0 Release/x64
full-add-on baseline in an isolated workspace checkout. It preserves the original
`external/reshade` reference and the installed proxy, rejects linked build paths,
locks all 11 submodule commits, uses a private Python environment, and records
commands, wheel hashes, generated inputs/outputs, tool versions and licenses.
Output is explicitly labelled `6.8.0 UNOFFICIAL`; no tracked upstream hook code
is changed. This is a compiled prerequisite for the DirectInput extension
described in [KCD input research](KCD-INPUT.md), not an implemented ownership hook.

The initial build compiled but GLAD fetched two platform headers from moving
upstream branches. Enabling its reproducible mode then exposed an older bundled
Vulkan XML without `VK_KHR_maintenance9`. The final script generates a narrow,
recorded process-local resolver: the three XML inputs come from ReShade's pinned
Khronos files, and platform headers come from the pinned GLAD package. There is
no network fallback in this generation step. The script also refreshes and
hash-checks the two extra headers that upstream GLAD preserves across its clean
target; an intermediate build still retained cached headers until this was fixed.
The source checkouts remain clean.
Earlier attempt evidence is retained; the final build supersedes those outputs.

Final evidence:
`runtime/dependencies/reshade-minecome-6.8.0/evidence/20261013-144246-738fad0aba6d40429d81f011fcd6a1c6`.
The output is 5,586,944 bytes, SHA256
`61efb31523f38f3559c3382a55c0678ca2b8c4440706c772aed81e1d39207f5f`,
version 6.8.0.1, built with VS2022 MSBuild/v143 and Windows SDK 10.0.26100.0.
The evidence includes 28 license/notice files and all provenance hashes.
Static inspection confirms x64, add-on registration and DirectInput8Create exports.
The installed proxy and reference checkout are unchanged. No deployment or game
launch occurred. Bit-for-bit repeat-build reproducibility and live behavior of
this locally compiled binary have not been verified.

## ReShade first-run banner — 2026-10-13

Future bundles now include `[OVERLAY] TutorialProgress=4`. In the pinned ReShade
6.8.0 `source/runtime_gui.cpp`, lines 316–317 load that setting and line 805 keeps
the installation prompt visible while the tutorial index is zero. The stock skip
action sets the index to 4. This removes the persistent "Press Home" tutorial
prompt shown in the user's screenshot. The normal brief startup/loading splash
still follows ReShade's own loading and five-second rules; this is not complete
splash suppression. The source configuration and PowerShell parser checks pass.
The currently loaded game configuration has not been changed; the setting takes
effect in the next prepared and installed bundle.

## Optional host HUD suppression — 2026-10-13

`Start-HudInputLab.ps1 -Mode Live -HideHostHud` now temporarily sets the exact
`wh_ui_ShowHud` CVar to 0 after real Minecraft readiness and before arming the
compositor. Installed tools `Data/Scripts.pak` contains stock commands using 0
and 1 in `Scripts/CommandExecutor/sample_terrain.xml:18` and
`sample_terrain_default.xml:14`, also present in pinned docs commit
`9cb067543245ec5cf4e27b3d21e32485a35db518`. The pinned System.GetCVar/SetCVar
binding pages document the paired read/write API. No native offset is used.

The new Lua probe and PowerShell helper retain the original strict numeric 0/1
value, create an immutable pause-updating engine expiry before a deferred hide,
and verify readback. An already-hidden HUD incurs zero writes. End also defers
restoration through an engine timer. Restoration requires the same owned reader
and setter and preserves an observed external value; changed readback functions
cannot produce a success claim. Engine stalls can delay the timer, and equal-value
external writes are not detectable by a CVar. The feature is therefore opt-in
for this controlled lab. There is no startup mutation or persisted user setting.

The controller retains its session before Begin, restores the HUD in finally,
then restores the independent FPS budget even if HUD cleanup/evidence fails.
Both restorations affect the final pass result. Repeated terminal receipts from
expiry followed by End are accepted only with consistent ownership/outcome
fields; restored-but-expired sessions remain invalid. Standalone coverage passes
29 Lua cases with simulated engine bindings, plus 397 PowerShell checks across
36 lifecycle and seven actual production-finally scenarios. Independent review
passed after correcting duplicate-terminal handling and replaced-reader evidence.

One actual helper-only check used the already-open exact tools PID 28844:
`runtime/evidence/hud-visibility-20261013-140202-332ec774885045858826ce6f76590862`.
Fresh source loading and receipt readback verify shown 1 → hidden 0 → restored 1,
requested End before the 10-second expiry, cancelled timer, no remaining active
lease and no game launch/stop. Lua source/snapshot SHA256 is
`ca3c85f7e9ca85d0f606beb7e0c130ca194ffa06d7b8494e80294e3d18fdcf6b`.
This proves the engine setting transition, not the combined visual appearance.

The switch hides the whole host HUD. Retail source describes that element as
including subtitles/dialogue widgets and hints as well as stats/compass; exact
tools visual scope still needs validation. This is not selective widget hiding,
gameplay input suppression or KCD-health-to-Minecraft synchronization. The helper
is restored at session completion; it is not yet tied to individual inventory
open/close transitions. Use the verified temporary host frame cap and hidden
guest for the eventual combined check, and preserve the accepted 1280×720/GUI2
layout.

## Live first-close diagnosis — 2026-10-13

The user installed the reviewed diagnostic add-on and restarted the exact tools
game (PID 28844, start `2026-10-13T12:45:38.7482732Z`). Its loaded module path and
SHA256 match `ef224499d2c5a331e5f8ee011761e4bced2a3709fb2ba3b6471aa598ea07ab74`.
Evidence is in
`runtime/evidence/hud-input-20261013-124816-c1a1f7ce1a9d428eaabe392bca1ab583`;
the exact user reply, native run lines and foreground process correlation are
preserved in `user-observation.json` and `native-session.log`.

The user confirmed "done, no kcd menu opened, worked". All ten physical 1/2/9/E/Esc
events were sent, acknowledged and applied, with actual Creative inventory
opening/closing. Minecraft published 493 frames; the host uploaded 471/submitted
1,973 with zero drops. All ten events were applied hidden/unfocused. Cleanup,
closed ACK and normal exit 0 passed; the temporary host cap was restored from 60
to the original -1 by requested End before expiry.

The immutable `first_input_close` receipt reports `eligibility_lost` at
15,766 ms after activation. All six window checks were sampled; only foreground
failed (mask 32). The KCD HWND still matched its runtime, was valid, belonged to
KCD, remained visible and was not minimized. Recorded foreground PID 16560 was
identified read-only as Explorer, with a start time preceding this run. ACK age
was 19 ms, observed ACK age 0 ms, and publication/resident image ages 47 ms.
The composition gate also stopped drawing because foreground had changed.
No stale-input/image, overlay, second-F8, settling-key or expiry failure occurred.

This is the intended focus-loss shutdown, so no input-rule change is indicated.
The evidence does not establish why focus changed, explain the earlier
uninstrumented 10.47-second stop, or verify a full uninterrupted 30-second run.
The user's menu observation covers this keyboard sequence; mouse/camera ownership
and general host-menu exclusivity remain separate work.

## Inventory pointer lifecycle and first-close diagnostics — 2026-10-13

The guest now follows pinned Minecraft 1.21.1's single active drag button instead
of dragging every held button. Closing or replacing inventory releases buttons
against their original Screen; later physical ups are consumed without releasing
a newly opened screen. Wheel events apply the actual discrete-scroll and mouse
wheel sensitivity options before calling vanilla `mouseScrolled`. The consumed
input sequence and successfully applied event count are recorded separately, so
a rejected UI call cannot inflate the applied count. No new transport or live
mouse flag was introduced.

Independent source reviews passed for the guest and native changes. The guest's
34 new pure gesture checks and 353 input checks pass; its remapped JAR is
`f4d613b0d382bcb70df5ea2c39c49a39427fc94f6e81dc7086cc5e7b48233617`.
The real 31-event fixture also passes in
`runtime/evidence/hud-input-20261013-124127-3beccc22f27543c785251f91308bb54b`:
203 published frames, all nine selections, actual Creative inventory open/close,
and matching fresh client/server item swap. All 31 events were applied while the
guest was hidden and unfocused; cleanup and normal exit passed. The temporary
host cap comparison in
`runtime/evidence/hud-gpu-budget-20261013-134126-ab67a4427623439bb7219cd76f5b0b47`
verified restoration to the original uncapped setting. This fixture covers the
existing click sequence; it does not claim real drag/split/scroll verification or
KCD input exclusivity.

The native first-close receipt now separates runtime HWND match, valid HWND,
owned process, non-minimized state, visibility and foreground status. Skipped
short-circuit observations are null, not false. Foreground PID is resolved only
from the actual observed foreground HWND when closure occurs; no window titles
are collected. The snapshot also records elapsed time since F8 activation.
Ownership rules, single-session lifetime and 250 ms freshness limits are unchanged.
The focused native contract/channel suite passed 294 checks, including slot/E/Esc
ownership and immutable first-close context. Add-on SHA256
`ef224499d2c5a331e5f8ee011761e4bced2a3709fb2ba3b6471aa598ea07ab74` is staged in
`runtime/hud-compositor-input-close-diagnostics`, with its exact hash supported
by the owned update script. It was subsequently installed and verified in the
live first-close diagnosis above.

Pointer capture must still address host input ownership, as the reference projects
do. Pinned ReShade implementation returns client coordinates despite its header
describing screen coordinates, and maps mouse indexes 0/1/2 to left/right/middle.
Its DirectInput8 `GetDeviceState` suppression preserves X/Y/wheel axes. Thus public
blocking alone does not establish camera/wheel isolation in KCD. EldenCraft also
disables its exact live pad polling; SkyCraft filters its host player/menu consumers.
Neither foreign engine hook can be copied into KCD. The paired KCD ownership API
remains unresolved; see [the KCD input research](KCD-INPUT.md).

Primary inspected sources:
[ReShade coordinates](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/input_windows.cpp#L162-L169),
[DirectInput8 suppression](https://github.com/crosire/reshade/blob/18deaa52de0c425a78b329e9cb3c497281cd00ec/source/windows/dinput8.cpp#L18-L70),
[EldenCraft input ownership](https://github.com/SocketByte/EldenCraft/blob/ba7591cdde9fb16e17552cfe53546f44d0fd856e/native/src/input_capture.rs#L46-L94),
[SkyCraft input ownership](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/skse/src/Input.cpp#L112-L247).

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
The old static arm was archived. The owned empty mod-order list was retained for
that controlled renderer comparison, then removed with ownership checks after
normal closure before the later input deployment.

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

A separate vanilla UI input mode is now implemented below; host-menu arbitration
remains unfinished.
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

## Separate keyboard UI mode

`Start-HudInputLab.ps1 -Mode Fixture` starts an isolated real Minecraft client and
a standalone native reverse-input peer. Its successful 31-event run selected all
nine hotbar slots, opened/closed the real Creative inventory and used normal slot
clicks to swap two stacks, with final integrated-server confirmation. Source
capture is now 1280x720 at GUI scale 2; full-canvas placement is unchanged. The
live appearance of this smaller layout was subsequently accepted in the final
short keyboard check recorded below.

Rendering and server proof have distinct timing: during ordinary client prediction
the interactive stream continues rendering with `client_server_inventory_confirmed`
false. The fixture's final item/selection proof still waits for server agreement.
The actual retry exercised this path and passed with 32 published frames.

The separate input add-on is installed from `runtime/hud-compositor-input-waitfix`, with
the previous stream bundle preserved. `Arm-HudStream.ps1 -InputMode` requires a
genuine live-mode ready receipt and publishes only `MineComeHudInput.ini`. Fixture
receipts cannot arm KCD. Both image and input channels use exact PID/FILETIME
identities and a shared immutable expiry; input ACKs originate on client ticks.
See [the reverse input contract](../../protocol/HUD_INPUT.md).

After a user starts the fresh tools world, the controller command in PowerShell 7
is `Start-HudInputLab.ps1 -Mode Live`. This starts Minecraft, verifies readiness and
arms the already-loaded add-on. The user must keep KCD focused, close its menus and
console, release controls, then press F8. After half a second, 1-9 select slots,
E opens/closes Minecraft's inventory and Escape closes it. Ownership lasts at most
30 seconds and ends on focus loss, stale data, ReShade overlay or renderer reset.
F8 itself can reach KCD; complete host keyboard exclusivity is still a live check.

This mode does not forward the mouse. ReShade's inspected DirectInput8 polling
implementation preserves mouse axes while blocking buttons, so its public block
request does not establish camera suppression. Host menu/cutscene detection,
gamepad ownership and KCD physics control are also absent. KCD's own HUD and health
remain active pending a separately verified health/display integration.

Before the first input deployment, the prior stream arm and diagnostic-owned
empty mod-order file were cleaned up after normal KCD closure with exact ownership
verification, restoring normal mod discovery. That installation was unarmed,
with save and add-on backups. Subsequent user-started live attempts are recorded
below and in `docs/PROGRESS.md`, alongside exact receipts and hashes.

The first live keyboard attempt ended before F8 with zero events: a stale
waiting-state ACK was treated as terminal. KCD remained alive. Waiting readiness
now becomes ineligible and can recover on fresh real observations, while armed
input retains the 250 ms cutoff. Receipt-time sampling and a separate bounded
closed-ACK rendezvous address timing races without refreshing timestamps or
granting ownership during waiting/closure. `Start-HudInputLab.ps1 -Mode Fixture
-DelayFixture` verified a deliberate 498 ms prearm ACK delay and a 550 ms delayed
closed ACK in actual Minecraft, followed by the same authoritative inventory
proof. Delayed fixtures are explicitly marked and cannot arm Live mode. The
repaired native build was installed unarmed before the second live attempt below.
The latest live KCD session used this waitfix build; newer native first-close
diagnostics remain undeployed. Exact results and deployment receipts are in
`docs/PROGRESS.md`.

## Background desktop presentation

The second live input attempt acquired F8 ownership but closed before any UI keys
were applied. A real standalone A/B comparison then located long render-thread
stalls inside `GLFW.glfwSwapBuffers` while Minecraft was unfocused. Disabling VSync
and setting 60 FPS did not prevent gaps longer than the 250 ms input limit. Both
comparison phases completed, but the following UI sequence failed. VSync and FPS
were restored and the game shut down normally; this was not a Minecraft crash.

`Start-HudInputLab.ps1 -Mode Fixture -BackgroundTrial` preserves that diagnostic.
It requires two 12-second unfocused phases, records bounded render/tick/PBO timing
and slow stacks, and marks its receipts so they cannot arm KCD. Native and guest
both validate exact identities, expiry and trial mode.

The opt-in `-OffscreenPresentation` input mode omits the desktop swap inside the
inspected Minecraft 1.21.1 `RenderSystem.flipFrame(J)V`, the separate desktop
framebuffer draw, and the outer desktop clear in `MinecraftClient.render(Z)V`.
The clear is omitted only for mask 16640 with draw-framebuffer binding 0 under
the same ownership/lease guard; later clears on the genuine HUD framebuffer
remain active. The draw's resulting GL/cache state is preserved. The real vanilla
GUI framebuffer, PBO readback and image
stream remain active; `glFlush` submits their work, while `flipFrame` retains both
event polls, queued render work and Tessellator cleanup. These hooks require the
owned world/player/server/window, explicit mode and unexpired wall/monotonic lease.
Controlled client cleanup and normal host closure have at most 1.5 seconds of
presentation-only grace for the real closed ACK, without input ownership or
renewed freshness. The owned offscreen guest is temporarily capped at 30 FPS;
original option and actual Window settings are restored separately. VSync is not
changed by this mode. Other HUD modes retain ordinary desktop presentation.

Guest pacing also appears in the pinned references.
[SkyCraft's frame loop](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/client/java/dev/skycraft/client/SkyClient.java#L402-L449)
follows Skyrim's frame sequence with a bounded wait, disables VSync and hides the
guest window. Its 260 FPS setting leaves pacing to that host sequence.
[EldenCraft's policy](https://github.com/SocketByte/EldenCraft/blob/ba7591cdde9fb16e17552cfe53546f44d0fd856e/minecraft/src/main/java/dev/eldencraft/bridge/FramePipeline.java#L7-L14)
caps host-linked rendering at 60 FPS and bounds frame age. MineCome's 30 FPS
experiment adapts pacing to its inspected 1.21.1 CPU readback path; those projects
use different Minecraft rendering APIs and EldenCraft also has shared GPU transport.

`Start-HudInputLab.ps1 -Mode Fixture -OffscreenTrial` implies the offscreen option
and requires 12 seconds unfocused before the ordinary 31-event inventory fixture.
Focus gain after readiness invalidates the run. Final proof must include all 31
unfocused applications, server-confirmed stack swapping, real published images
and complete cleanup. This remains distinct from physical keyboard input and
compositing inside KCD; see `docs/PROGRESS.md` for measured results.

Live opt-in is `Start-HudInputLab.ps1 -Mode Live -OffscreenPresentation` after the
normal exact-installation and fresh-session checks. Live behavior, keyboard
exclusivity, GUI size and host HUD integration still require their own evidence.

Control receipts now use a separate bounded four-entry I/O queue. Up to eight
captured state samples are retained within the existing image-size limits and
encoded to PNG only after the image channel closes. Active pixel publication
therefore performs neither disk writes nor PNG compression. Queue overflow,
writer failure or incomplete shutdown invalidates success; owned input failures
retain their first snapshot and complete the existing real closed-ACK rendezvous.
Producer-stage, publication-gap, capture-server-age and PBO fence diagnostics
separate possible causes of image starvation without changing any timeout. In
offscreen mode, a diagnostic fence immediately before `glReadPixels` distinguishes
earlier queued GPU work from the existing post-read fence. Only the post-read
fence authorizes pixel mapping; zero-timeout polls add no wait or freshness credit.

As of 2026-10-13, the capped offscreen trial
`08c656378fc04555983218243fc6c9dc` still failed: 16 unfocused events were applied
from 17 sent, before inventory opening. The publisher was waiting for a frame
while all three PBO fences were pending; the oldest was 267 ms old at failure,
and completion age reached 967 ms. Client ticks, pixel conversion and receipt
writes remained short. The guest restored the original 120 FPS cap and enabled-VSync
settings, completed real ACK/handle cleanup, saved and exited normally. The
controller retained failure.

The next trial, `fb7f035c9abc4d4b8d5cd5c00376923d`, exercised 570 desktop-clear
omissions but failed after four applied events from five sent. At failure all
three fences before readback were pending. Maximum observed pre-read fence age
was 1,039 ms, compared with at most 32 ms from observing that fence complete to
observing post-read completion. These coarse CPU poll observations locate the
long wait before the pixel transfer; they are not GPU timer measurements or
proof of the underlying scheduling cause. The real closed ACK/handle cleanup,
restoration to enabled VSync/120 FPS, normal save and exit all completed. Possible
host GPU contention remained under investigation at this stage. Neither
standalone run adds live KCD input, sizing or exclusivity
proof. Detailed measurements and full evidence paths are in `docs/PROGRESS.md`.

## Host frame-cap comparison

`Test-HudGpuBudget.ps1` now wraps the unchanged standalone offscreen fixture in a
temporary KCD frame-cap comparison. It targets only an already-running exact
tools process. The intended baseline is the previously observed uncapped
`sys_MaxFPS=-1` with `r_VSync=0`; fresh values are checked before the probe applies
60 FPS. It refuses a positive original cap at or below 60 and does not change
VSync. This tests a possible host GPU workload contribution, which remains a
hypothesis.

The Lua probe arms a pause-updating 120-second engine-timer lease before its
deferred write. Run/state/timer identity checks reject stale callbacks. End and
expiry restore only a still-owned value, preserve external changes and check
actual readback. The controller's `finally` requests End and accepts comparison
validity only after a requested, nonexpired, verified restoration with timer
cancellation. An engine stall can delay timer execution; the lease is not an
independent wall-clock watchdog.

Twenty-two cases pass in the real Lua 5.2 VM with simulated engine bindings, and
the probe/wrapper have independent source review. The frozen receipt is
`runtime/evidence/hud-gpu-budget-native-frozen-b8c6c066d2d44500a62fda949f75f6b7/verification.json`.
The first invocation stopped at preflight after KCD PID 54424 had closed,
without changing the cap or launching Minecraft. Its owned expired input arm
`5854a3c5336448158a97e26b8bf42b57` has been archived with the receipt at
`runtime/evidence/hud-input-20261012-222727-5854a3c5336448158a97e26b8bf42b57/capture/arm-archive.json`.
The installed waitfix add-on is unchanged and unarmed; newer native diagnostics
remain undeployed.

The user subsequently started a fresh tools world with
`scripts/Start-Kcd2ToolsTest.ps1`. The comparison command explicitly uses the
installed PowerShell 7 runtime:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudGpuBudget.ps1'
```

The controller starts the isolated Minecraft fixture and records its run alongside
the host-cap receipts and restoration verdict. It neither arms KCD input nor
launches/stops KCD.

Actual host run `9354dbc5a9e3459e8c1ddfea711bb0f9`, under
`runtime/evidence/hud-gpu-budget-20261013-124533-9354dbc5a9e3459e8c1ddfea711bb0f9`,
used user-started KCD PID 46236 (created `2026-10-13T11:43:27.2961094Z`). It applied
60 FPS from −1, then verified restoration to −1 when the 120-second timer expired.
The controller correctly reports restoration success but comparison invalidity.

Its paired guest run `6c7341981e1344a2ae437816ae60403d` remained focused for all
2,003 observed ticks, with zero unfocused ticks. It reached the 100-second waiting
limit without completing the unfocused phase or sending/applying any events.
Minecraft published 1,492 genuine HUD frames, completed real ACK/handle cleanup,
restored its enabled-VSync/120 FPS settings and shut down normally. Maximum image
age was 85 ms and pre-read fence age 39 ms; these focused measurements cannot
establish a fix for the background backlog. Guest evidence is at
`runtime/evidence/hud-input-20261013-114534-6c7341981e1344a2ae437816ae60403d`.

The same waitfix installation remains unarmed. Automatic hiding of the owned
guest window was then implemented to remove the manual focus handoff. Its first
trial is recorded below; a valid comparison and physical hotbar/inventory control
remain pending.

## Hidden-window readiness correction

Run `6d5b5e35855643f29a86824c671b3c10`, at
`runtime/evidence/hud-input-20261013-115450-6d5b5e35855643f29a86824c671b3c10`,
verified the owned guest window was hidden (`visible_after_hide=false`). The raw
GLFW focus query still reported true after hiding, whereas Minecraft's actual
callback-driven focus state was false. Tick diagnostics recorded 2,003 unfocused
and zero focused ticks. The hidden-phase timer wrongly required the raw query to
clear, so it never completed and input never armed. After the 100-second waiting
limit the controller reported failure: 1,496 real frames were published/received,
but no input events were sent or applied.

Waiting-phase maxima were 75 ms for client tick gaps, 38 ms for readback age,
48 ms for published capture age and 91.8 ms for publication gaps. These are
diagnostic observations without input-sequence proof.

Actual cleanup restored the original visibility and focus-on-show setting without
requesting focus, restored enabled VSync/120 FPS, published the real closed ACK,
released the handles and completed normal exit 0. This establishes hide/restore
behavior only; it does not verify inventory interaction or resolve the prior GPU
backlog.

The inspected [GLFW 3.4 Win32 implementation](https://github.com/glfw/glfw/blob/3.4/src/win32_window.c#L1803-L1806)
queries `GetActiveWindow`, whose [documented scope](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getactivewindow)
is the calling thread's message queue. That is distinct from the global foreground
window. The bundled native DLL was verified as GLFW 3.4.0 Win32 WGL within
LWJGL 3.3.3. The implemented and reviewed correction uses the real Minecraft focus
callback plus observed hidden visibility for the trial gate, retaining the raw
query as diagnostic evidence. No focus state is fabricated and no freshness
timeout is relaxed.

## Hidden background fixture verified

Run `ec8509f6af394e11a3e9ba5c8b062e5a`, at
`runtime/evidence/hud-input-20261013-120534-ec8509f6af394e11a3e9ba5c8b062e5a`,
passes with the corrected build. The owned window was genuinely focused before
hiding, then emitted one real focus-loss callback. Its 12,058 ms readiness phase
contained 241 unfocused ticks and zero focused ticks; framebuffer dimensions were
preserved. The complete run recorded 276 hidden/unfocused ticks and applied all
31 events while hidden and unfocused, with no focus interruptions or focused/
visible event applications.

All nine hotbar slots, actual Creative inventory opening/closing and the
integrated-server-confirmed stack swap passed. The guest published 205 genuine
frames; the receiver saw 204 and acknowledged every event plus the real closed
marker. Maximum own-image age was 155 ms and readback completion age 125 ms,
with zero fence-timeout polls. Original enabled-VSync/120 FPS settings, visibility
and focus-on-show behavior were restored, with no focus request and complete
handle cleanup.

`host-settings.log` records KCD uncapped at `sys_MaxFPS=-1`, with `r_VSync=0`.
The 60 FPS host cap was not needed for this successful bounded run, but KCD's
foreground status was not independently recorded. This is standalone background
input/rendering proof under the existing 250 ms gates; it neither establishes
general GPU stability nor demonstrates physical keyboard delivery or live KCD
compositing.

## Hidden live attempt remains unsuccessful

The subsequent live run `e63eeea7a7a54655b6871d8369993970`, at
`runtime/evidence/hud-input-20261013-120701-e63eeea7a7a54655b6871d8369993970`,
armed the unchanged waitfix add-on in KCD PID 46236. F8 activated both native and
guest ownership, but zero UI events were applied before stale own-image
publication closed the session. Minecraft published 534 frames; maximum image
age reached 466 ms, and the failure snapshot had all three pre-read fences
pending, with maximum observed age 469 ms. No server-stale capture skip was
recorded. The hidden-window work has not resolved this live GPU backlog.

The user saw a black Minecraft window appear and close, with no response to the
remaining keys. Logs and receipts establish the normal failure shutdown path,
exit 0, actual closed ACK, complete handle/control cleanup and restoration of
visibility, focus-on-show and enabled-VSync/120 FPS settings without requesting
focus. The controller retained failure; KCD stayed outside its launch/stop scope.

The subsequent temporary 60 FPS host-cap comparison is recorded below. Physical
keyboard delivery, accepted GUI size and host-input exclusivity remain unverified.
The standalone pass above is preserved with its narrower recorded conditions.

## Capped hidden comparison completed

Host run `febe0c161705407f9995f4207894bcd4`, at
`runtime/evidence/hud-gpu-budget-20261013-130919-febe0c161705407f9995f4207894bcd4`,
records a passed fixture, verified restoration and `comparison_valid=true`.
The actual cap changed from −1 to 60 and was restored to −1 through the requested
End before expiry, with its timer cancelled. The installed add-on was unchanged.

Paired guest run `60ce70cb803543d1a4decb5dbc2f8926`, at
`runtime/evidence/hud-input-20261013-120919-60ce70cb803543d1a4decb5dbc2f8926`,
passed all 31 hidden/unfocused events, all nine slots, inventory opening/closing
and the authoritative stack swap. Its 12,029 ms preparation phase had 241
unfocused ticks; the complete run recorded 276. It published 202 genuine frames
and the receiver saw 201. Maximum own-image age was 131 ms and readback completion
age 43 ms, with zero fence-timeout polls. Real closed ACK, handles, settings and
visibility restoration all passed, followed by normal exit 0.

The user was told to keep KCD in front, but host foreground state was not
independently recorded. This is successful capped standalone input/rendering and
rollback evidence, not a live compositor check or proof that the cap resolves
the preceding KCD-focused failure.

The explicit live option is implemented through shared `scripts/HudGpuBudget.ps1`:
after Minecraft readiness and exact Java process validation, it applies the
unchanged 60 FPS/120-second lease before arming. `finally` restores and checks the
original cap; final success requires budget validity, separately from `body_passed`.
The helper passes 98 assertions across 11 simulated-console scenarios and an
actual −1→60→−1 check, recorded at
`runtime/evidence/hud-gpu-budget-20261013-131823-a11a2771df5c4b8789e69dbbe6ce5f17/budget-verification.json`.

After a fresh KCD restart, the opt-in command is:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Start-HudInputLab.ps1' -Mode Live -OffscreenPresentation -HostGpuBudget
```

Final independent controller review passed. The user restarted with the same
installed waitfix add-on for the live check below; this controller change required
no new native or JAR build.

## Short live keyboard sequence and sizing verified

Run `3f322ff93e6a4b35b1b64dd3f16410f4`, at
`runtime/evidence/hud-input-20261013-122232-3f322ff93e6a4b35b1b64dd3f16410f4`,
passes against fresh KCD PID 48640 with the unchanged waitfix installation.
The user accepted the HUD size and controls. Ten physical press/release events
for 1, 2, 9, E and Escape were acknowledged/applied, and the actual Creative
inventory opened and closed. Minecraft published 496 real frames; KCD uploaded
478 and submitted 2,001 draws with zero drops. Maximum image/readback ages were
140/46 ms. All-nine-slot and server stack-swap proof remains standalone only.

The guest ended with `input_completed`/`host_closed`, no failure, real closed ACK,
complete cleanup, normal saves and exit 0; the closing Minecraft window was not
a crash. Native ownership lasted about 10.47 seconds, from 13:23:27.197 to
13:23:37.670. Its exact close trigger is unavailable in the installed build;
this does not prove full 30-second operation or KCD menu/input exclusivity.

Budget run `11e7171fd8fb4966a351c72b2a7349ad` restored −1 after the temporary
60 FPS cap through requested End before expiry, with its timer cancelled. Its
receipt is at
`runtime/evidence/hud-gpu-budget-20261013-132304-11e7171fd8fb4966a351c72b2a7349ad/budget-verification.json`.
The next work is full-session close diagnostics and mouse ownership. Host HUD
suppression and health integration remain separate unfinished integrations.
