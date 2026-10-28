# Resume checkpoint — 28 October 2026

## Current result and user preference

Optional **15-second physical walking + real Minecraft HUD now passes live in KCD2**.
User feedback: **"worked. still delay, but worked."** Keep the intentional 200 ms
buffer and the verified short mode. Latest instruction: the user is AFK; continue
automated work only until they return. Do not start another F8 countdown or ask for
manual actions while they are away. The next feature is walking with aimed block
interactions; it is not yet implemented as a combined mode.

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

Do not just enable both existing profiles. Walking uses collision-only sampled
terrain with AIR-cell invariants; `AimedStoneArena` bootstrap expects real solid
Minecraft support. The walking compositor currently excludes world-click capture.

1. Define explicit ownership for placed blocks versus imported terrain, so
   movement collision checks tolerate only confirmed owned edits and clean them
   up without touching unrelated content.
2. Build a separate combined fixture/profile that starts from real sampled-ground
   walking and the actual vanilla interaction path. Keep existing modes intact.
3. Initially admit aimed clicks only after motion is settled and host/guest eye
   alignment is fresh. The200ms host lag can exceed the current0.25m eye-origin
   tolerance while walking; do not solve this by weakening reach/eye checks.
4. Add the combined compositor input capability and exact bundle/profile hashes
   only after guest terrain/interaction tests pass. Retail1.5.6 remains blocked
   by loader/address-library prerequisites; official tools1.5.5 only.

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
