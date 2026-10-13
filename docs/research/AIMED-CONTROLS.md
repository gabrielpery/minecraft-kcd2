# Connecting host clicks to Minecraft aiming

This is an opt-in development path. The verified live HUD still uses its existing
fixed-cell controls. The new path is not enabled by `Start-HudInputLab.ps1` yet;
it needs a bounded controller that validates the new guest proof and carries
the acknowledged permit into each physical click. Loading these source modules
does not install or activate them in KCD2.

## One alignment, one captured intent

The optional minor2 [wire protocol](../../protocol/PROTOCOL.md#optional-minor2-aimed-stone-arena)
agrees on Minecraft and KCD camera anchors before the first stone event. The new
`--aimed-stone --aimed-run <run>` tools-host mode maps replicas through that exact
agreement. It must not use the legacy display island placed in front of the camera.
The initial Minecraft seed remains two cells toward Minecraft +X, which maps to
KCD world +X; this is independent of the direction the host camera currently faces.

The separate Lua modules are loaded in order: `aim_probe.lua`, then
`aim_intent.lua`. The latter pins the sampler function and provides
`BeginAimedInput`, `InstallAimedPermit`, `AimedIntent` and `EndAimedInput`.
They use decimal strings for IDs because the inspected game uses float32 Lua
numbers. Loading or reloading the module revokes permits and begins no session.

1. Minecraft issues a single-use permit with a 500 ms lifetime measured by its
   own monotonic clock. The native relay retains the original receipt and generation.
2. After the first stone's engine acknowledgement, the relay installs a permit
   in Lua. Only a matching Lua acknowledgement produces `AIM_PERMIT_READY`.
   Its UTC time records when the native relay observed that acknowledgement.
3. The physical-edge selector in `scripts/AimedWorldClicks.ps1` accepts only an
   unused acknowledgement strictly earlier than the edge. Equal millisecond
   timestamps do not establish ordering. It rejects stale edges, changed runs,
   reordered IDs and observed clock rollback, and spends the permit before dispatch.
4. `AimedIntent` consumes that exact installed permit and samples camera position,
   direction and nearest `ent_all` obstruction in one synchronous Lua call.
   This sample occurs at the engine callback after the physical edge; it does
   not claim to capture the original renderer input frame. Missing obstruction
   data means unavailable, never clear space.
5. The relay validates the original permit, generation, sample and engine time
   interval. It normalizes only small float32 direction rounding before strict
   wire encoding. It never replaces the permit with a newly issued one.
6. Minecraft selects the actual block/face using its OUTLINE raycast and executes
   vanilla interaction APIs. Client/server confirmation, block events and KCD
   replica acknowledgements remain separate evidence.

## HUD integration boundary

The `minecomeHudAimedStoneBridge` development property selects a separate guest
adapter in the existing live stone HUD profile. Its readiness marker and action
proof differ from the fixed-cell profile. The old controller must not accept it
as a completed fixed-cell test. General walking, survival state and placing on
unrepresented KCD terrain are outside this bounded stone-cluster mode.

The arena pins the exact owned HUD save. A queued action that has not reached
vanilla is cancelled when HUD authority ends or an inventory screen opens.
An already-dispatched action still requires authoritative observation; stopping
does not convert an uncertain action into a successful result.

The Arena still requires the selected slot/stack to match through authoritative
confirmation. Changing it after vanilla dispatch but before that confirmation
can end this experimental HUD session, even when the block transition succeeds.
The integrated controller needs a focused transition check before this mode can
claim normal rapid slot switching during block actions.

On shutdown, native request authority is revoked before ending the Lua session.
Requests already written to the guest cannot be recalled. A stone cleanup ACK
proves replica removal; the separate `AIM_INPUT_END_ACK` proves the Lua input gate
ended. Shutdown can finish reading after stone cleanup before a late gate ACK
arrives, so those receipts must not be treated as interchangeable. The bounded
Lua lease remains a fallback if its end receipt is unavailable.

See [progress](../PROGRESS.md) for the current build, simulated-engine and actual
Minecraft results. A real KCD crosshair test is still required before claiming
live aimed placement or breaking.
