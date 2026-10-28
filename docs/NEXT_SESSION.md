# Resume checkpoint — 28 October 2026

## Current result and user preference

The user has returned and asked to continue. The combined walking/aimed-block
Minecraft fixture is now implemented and passes automatically on flat ground and
captured KCD terrain. **Combined physical controls in KCD2 are the next phase**;
do not repeat the completed guest work or enable the existing incompatible live
flags together. The prior 15-second walking/HUD live baseline remains verified,
with user feedback **"worked. still delay, but worked."** Keep its 200 ms buffer.

## New combined guest checkpoint

Command: `scripts/Test-HudPhysicalMovementFixture.ps1 -ExtendedWalking -AimedBlocks`.
This is explicitly standalone, scripted and yaw zero. It bootstraps a stone,
walks W/W/S, places/breaks top and west-side blocks, breaks the seed, reopens
inventory, verifies suppressed movement, then walks W/S again in the same session.

- Flat PASS `b5f250088e4841088fffebef1ea8cdb0`:
  `runtime/evidence/hud-physical-fixture-20261028-135417-b5f250088e4841088fffebef1ea8cdb0/`.
  15,504 ms, 158 trace records, 259 UI frames, six confirmed block actions,
  five walking pulses, 1.498988 m max walk, zero corrections. Receipt 36,537 bytes.
- Captured-terrain PASS `61868402650549db9387657daf1b8065`:
  `runtime/evidence/hud-physical-fixture-20261028-135545-61868402650549db9387657daf1b8065/`.
  15,508 ms, 158 records, 258 UI frames, six actions/five pulses, .637031 m max
  walk, zero corrections. Receipt 37,435 bytes. Same original terrain capture/hash
  as the prior captured-terrain fixture below. Both source manifests match all92
  files, both prove inventory suppression, resumed walking and exact support cleanup.
- Existing actual aiming regression PASS all28 scenarios:
  `runtime/evidence/aimed-stone-20261028-133833-c360373cce28416593baaaae60138c25/`.
- Compile/assemble PASS;96 build-region checks;336 physical-mode/input checks;
  196 PS fixture/profile checks;26 evidence-writer checks. No new native install.

New pure `HudBuildRegion` forbids edits to any imported collision cell or the
fixture's immutable support, caps confirmed ownership at16 and fixes seed±2 bounds.
Optional `AimedStoneArena(alignment,save,region)` keeps the existing confirmed
ledger/vanilla proof and applies this policy before dispatch and in server preproof.
`GroundCollision.matches` validates actual installed world/run/hash. The combined
helper requires fresh settled grounded client/server agreement and neutral keys.
It separately accounts for one fixture BEDROCK support setup/removal beside the
sampled footprint, with unchanged support and all AIR checks before cleanup.

Preserve two failed trials: `9e80ade...` confirmed six actions but hit the existing
100 ms camera-file atomic replacement retry limit before resumed walking; lock
holder unknown and no speculative camera change. `603803...` completed movement
but could not emit its oversized pretty JSON receipt. Combined-only compact JSON
with explicit nulls now retains all evidence within the unchanged64 KiB limit.
Neither trial is promoted to a full PASS. Their full paths/diagnostics are in
PROGRESS.md. All Minecraft clients have exited; KCD remains the earlier session.

## Latest full live PASS

- HUD `a673494c0d084564ac3c83e3fdcdd47d`, probe
  `e50b03b5a7eb4f1c92b58f42d3da012b`.
- Evidence: `runtime/evidence/hud-walking-20261028-131455-e50b03b5a7eb4f1c92b58f42d3da012b/`.
- **156/156 forwarded source points and delayed native readbacks**; guest 15,560 ms,
  158 trace records/121,488 bytes. Final source time 15,548.294922 ms.
- Native `explicit_end`, exact origin with zero error, 129 writes including
  restoration, 15,815.24609 ms. 174 receipts, all source crossings proved.
  Maximum recorded segment observation gap 17.1814 ms; zero readback error.
- All 611 camera samples fresh; resources/timers closed, FPS restored, Minecraft
  normal exit 0, input/mappings/proxies released. Client/server maximum walk 0.606181 m,
  zero corrections, 3 boundary pauses/2 resumptions.
- Four W/S/W/S presses paired to actual pre-vanilla bindings. Later presses at
  5.90 and 6.81 seconds prove the old five-second cutoff is gone. Median producer
  capture-to-receipt 33 ms, receipt-to-binding 0.1289 ms. No truncation/unmatched
  events. `timing-analysis.json` records seven original hashes and methods.
  Producer capture is not hardware actuation; no display/end-to-end latency claim.
- This final run did not open inventory. Inventory has separate automated proof
  below and user confirmation in the earlier focus-ended attempt.

## What changed

- `-ExtendedWalking` is opt-in on `Start-HudWalkingLab.ps1`, `Test-HudWalking.ps1`,
  `Test-HudPhysicalMovementFixture.ps1` and the child launcher.
- Java `HudMovementSession` selects 15s input + 1s settling, 256 KiB trace, same 200-record
  ceiling. First movement must start within 12s after F8; activation/inventory/
  boundary pauses never renew deadlines. Old 5+1s mode remains the default.
- New Lua `BeginExtendedBufferedPhysicalMovementFollower` selects 16s source time,
  fixed 18s native deadline, 2047 ordinary writes + restoration, 256 receipts with
  termination slots reserved. Profile state survives module reload; an older
  active follower gets only its original baseline limits.
- Explicit `movement_session="extended"` in ready/result/physical-ready/native
  receipts. Distinct trace kinds `live_kcd_hud_physical_movement_extended` and
  `standalone_hud_physical_movement_extended_fixture`; no profile borrowing.
- `HudWalkingSession.ps1` binds controller-selected budgets. Receiver/readers/
  timestamp and native ACK checks use the selected bounds. Completion must prove
  an integer 15,000–16,000 ms duration, not merely an extended label.
- Fixed 200 ms buffer, original server timestamps, 8 active points, 400 ms destination
  lease, 2m sphere/vertical bounds, sampled ground, delayed readbacks and rollback
  remain. No compositor installation or native renderer rebuild was needed.
- Lua source SHA256: `38E81FA00B6AC43607743275CD24E65E3A0411BB629FCC31D12018FFA26C8D7F`.

## Automated verification completed

Java compile/assemble; 327 input checks; 1547 ground/trace checks; 87 Lua cases;
101 buffered checks; 149 physical receiver checks; 87 warmup checks; 80 append-only/
coupled checks; 97 fixture receipt checks; 16 legacy receiver cases; 23 path checks.
Lua harness covers full 16s progression/161 ACKs, limits/reload/restoration; it is
not live-game proof. Do not repeat unchanged suites just to resume.

Actual Minecraft extended fixtures both pass five W/W/S/W/S pulses, inventory
reopened after6s with zero movement, then later walking and normal cleanup:

- Flat terrain: `runtime/evidence/hud-physical-fixture-20261028-130405-e0636c8c8087435588172cfe5513d343/`;
  15,593ms,159 records,255 UI frames,1.498988m walk,zero corrections.
- Captured KCD terrain: `runtime/evidence/hud-physical-fixture-20261028-131809-e13eb8ecdd1e4f69b4b12d740e1d92cf/`;
  15,517ms,158 records,252 UI frames,0.637031m walk,zero corrections,4 boundary
  pauses,12 reopened-inventory frames and zero client/server inventory movement.
  Original capture `ground-patch-20261028-131456-9f4aeb95285b4f3bbff56bc8c8f345e8/ground-patch.json`,
  SHA256 `93e1ced12e3f5340b2337fabeee885513055e42a76b9eb188485125967a4c23c`.
  Only numeric terrain samples are relabelled as a standalone fixture. No KCD
  commands, renderer arm or physical-input claim is made by either fixture.

## Keep the earlier incomplete run

First extended live attempt `a3735cb0c58f4ab6919ea481215ba453`:
`runtime/evidence/hud-walking-20261028-130751-a3735cb0c58f4ab6919ea481215ba453/`.
User said "all worked fine", but switched away 13,515 ms after F8. ReShade reports
`eligibility_lost`, foreground=false with fresh ACK/images. Guest ended STOPPED
~11s into motion. 109 sources/106 readbacks before cleanup; restoration and cleanup
passed. Preserve primary failed verification/post-run logs. This was expected
focus revocation, not a crash; no code change was needed for the successful retry.
Earlier short baseline `b850ba...` passed 57/57. Full historical evidence is in
[PROGRESS.md](PROGRESS.md); do not reinterpret failed trials as passes.

## Next implementation: walking and aimed blocks together

The ownership policy and combined guest fixture above are complete. Keep them;
do not weaken walking's AIR-cell invariants or repeat their implementation.

1. Add a distinct live walking/aimed controller derived from Test-HudWalking,
   integrating the existing HudWorldClicks/AimedWorldClicks/HudAimedRelay ledgers.
   Do not run Start-HudInputLab beside it. A separate compositor profile must
   combine physical movement (input protocol2) with selective world-click capture,
   keeping exact executable/config/bundle hashes and the old profiles strict.
2. Bind HudAimedStoneBridge's initial support/baseline and optional region to the
   active patch/save. Keep initial alignment immutable. Fixture support is not
   yet general placement directly onto imported KCD terrain.
3. Require released movement, fresh grounded guest client/server agreement and
   fresh native player/camera agreement after buffered playback settles before
   issuing a NEW aim permit. Recheck before dispatch; reject moving/stale clicks,
   rather than queueing them until later. Never widen .25m eye tolerance or rebase
   ray origins. Native bridge and arena both enforce this tolerance.
4. Reuse the walking camera sampler. The old aimed relay polls SamplePose every
   50ms, which would add redundant HTTP traffic beside movement and camera updates
   and could bring back delay. Add an explicit combined sampler mode instead.
5. Revoke aimed permits and resolve pending actions BEFORE native follower finish
   restores KCD's origin (the guest remains at its final position). Reserve action
   completion/cleanup time inside the bounded session; no clicks in the remaining
   HUD tail until a separate resynchronization contract is tested.

Only then run a combined KCD live check. Retail1.5.6 remains blocked by loader/
address-library prerequisites; official tools1.5.5 only. No user action is needed
to repeat guest fixtures, and the user is available when a new live check is ready.

## Current processes and later live restart

KCD PID 39628 remains open. Minecraft fixtures have exited normally. The successful
`e50b03...` HUD arm is consumed and unarchived. Older `a3735...`, `b850ba...`,
`4a7fb2...`, `6cd20f...`, `38d11...`, `2dd6...` arms are already archived.
Recheck processes and exact receipts before acting. Computer Use worked this turn
and closed only the owned previous test world normally via Alt+F4. Do not assume
an old Escape stop persists; respect any new stop reported by the tool.

After closing KCD normally, archive only the current arm and start a fresh world:

```powershell
$r = 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome'
& "$r/scripts/Archive-HudArm.ps1" -ReceiptPath "$r/runtime/evidence/hud-walking-20261028-131455-e50b03b5a7eb4f1c92b58f42d3da012b/capture/stream-arming.json"
& "$r/scripts/Start-Kcd2ToolsTest.ps1"
```

Only when another manual check is needed and the user has returned:

```powershell
& 'C:/Users/xephi/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe' -NoProfile -File 'C:/Users/xephi/Documents/ChatGPT/New project/MineCome/scripts/Test-HudWalking.ps1' -ExtendedWalking
```

Wait for HUD_WALKING_READY before the F8 prompt. Verify slot2, start walking soon,
and keep KCD foreground until HUD disappearance30s after F8. Movement returns at
~16s. No administrator mode, PowerShell setup or install is needed. Never load
retail1.5.6 saves into tools1.5.5. Routine development/launches/tests/Git pushes are
authorized; formatted commands precede question widgets when user action is needed.

Workspace: `C:/Users/xephi/Documents/ChatGPT/New project/MineCome`.
Public repo/default branch: `https://github.com/gabrielpery/minecraft-kcd2`,
`codex/initial-import`. Previous checkpoint `cdc272e82efa3171055bed751fc3c395ec40f7ed`;
inspect current Git log/status for the extended-mode commit rather than resetting.
