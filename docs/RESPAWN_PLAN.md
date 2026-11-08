# Proposed death and respawn integration

Status: **design only; not implemented or verified**. Inspected 8 November 2026
against the installed Minecraft 1.21.1/Yarn build. Death/respawn requires a
coordinated guest and native movement change; accepting a replacement player
object alone would leave spawn positioning and host movement unsafe.

## Current blockers

- `GameplayMovement.beforeTick` rejects a replacement client player before the
  session's end-tick transition handling. Its server ownership check and
  `GameplayBlocks.observe` also reject the replacement server player.
- `HudVanillaUiAdapter` rejects `DeathScreen`; respawn's brief
  `DownloadingTerrainScreen` needs bounded transition handling too.
- `kcd2/gameplay/movement_session.lua` rejects an ordinary pose displacement
  exceeding `0.5 + max_speed * elapsed` as `source_velocity_invalid`. Preserve
  that guard; respawn must use a separate acknowledged relocation.
- Vanilla's default flat-world spawn is unrelated to captured host terrain.
  Injected collision leaves terrain block states as air, so ordinary vanilla
  spawn searches cannot establish a safe KCD2-world respawn position.

## Proposed implementation

1. Observe Fabric `ServerPlayerEvents.AFTER_RESPAWN(oldPlayer, newPlayer, alive)`.
   Accept only `alive == false`, the exact owned integrated server/Overworld,
   same UUID/network handler, previously owned dead player and expected live
   replacement. Publish an immutable transition record; rebind each controller
   on its own game thread. Keep collision installation, construction ledger and
   terrain origin unchanged for a same-world respawn.
2. During death, release movement, mining, food and UI holds. Continue publishing
   an explicit frozen-pose state while fresh server observations still confirm
   the owned dead player and the actual death screen owns input. Do not renew
   stale source timestamps or relax transport leases. Route mouse input through the
   existing UI state and retain the vanilla Respawn button/packet behavior.
3. Admit a clear respawn point inside captured terrain, honoring a supported
   explicit spawn if available. Verify footprint, support height, owned block
   collision and head clearance. Refuse uncaptured or blocked destinations;
   never silently fall back to the unrelated flat-world spawn.
4. Add a one-use native relocation epoch containing old/new target and exact
   run/world identity, with an explicit acknowledgment. Bound its lifetime and
   reject replay, unrelated players and arbitrary pose jumps. Ordinary poses
   retain their existing velocity/freshness checks.
5. After native relocation and both replacement identities agree, clear old
   observations, aim and pending actions, rebind UI, and wait for position/ground
   stability and fresh camera evidence. Resume only released/repressed controls.
   Bound the terrain-loading transition; unrelated world/dimension changes stay
   unsupported instead of becoming general identity exceptions.

## Inspected APIs and evidence

Local bytecode/source evidence is under ignored
`runtime/evidence/respawn-source-20261108/`:

- `PlayerManager.txt`, `respawnPlayer` (line 953): constructs a replacement
  `ServerPlayerEntity`, retains game profile/network handler/id, copies vanilla
  state and publishes the replacement UUID map entry.
- `ClientPlayNetworkHandler.txt`, `onPlayerRespawn` (line 2398): same-dimension
  respawn retains `ClientWorld`, creates/replaces `ClientPlayerEntity`, and starts
  the terrain-loading transition.
- `ServerPlayNetworkHandler.txt`, `onClientStatus` (line 4592): dead-player
  respawn calls `respawnPlayer(old, false, KILLED)`.
- `ServerPlayerEntity.txt`, `getRespawnTarget` (line 1776): default/explicit spawn
  selection; forced air-spawn checks use block states rather than injected
  support height.
- `DeathScreen.txt`, Respawn button callback (line 508): invokes
  `ClientPlayerEntity.requestRespawn()`.
- `ServerPlayerEvents.java`: installed Fabric `AFTER_RESPAWN` callback signature
  and `alive` semantics.

These are inspection references, not proof that any proposed hook or transition
has been implemented. No guessed native engine offsets or methods are needed.

## Focused verification

Reuse the actual damage setup from `Test-GameplayFlight.ps1`, item identity and
pickup checks from `Test-GameplayDrops.ps1`, and existing two-launch persistence
fixtures. One integrated sequence should verify death/drop state, genuine button
respawn, safe native relocation, resumed walking/crafting, item recovery and
save/reopen. Cover mismatched UUID/server/world, living replacement, replayed
relocation and blocked spawn with focused rejection tests. Physical input and
subjective visual acceptance remain distinct from scripted coupled-game proof.
