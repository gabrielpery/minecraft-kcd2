# Native scenery explosions — deferred, 9 November 2026

The user allowed environmental destruction by TNT and other explosions to be
omitted if costly. It is optional and must not delay the playable release.
The working TNT path destroys Minecraft construction and damages KCD2 NPCs.

## Reference projects

SkyCraft's pinned
[SkyDigBlast.java](https://github.com/chasmlol/SkyCraft/blob/bfcaf178524b92c2cdeb88e4ce0f13ef9ded6f32/fabric/src/main/java/dev/skycraft/world/SkyDigBlast.java)
uses material resistance to excavate native ground and rock with Minecraft
explosions. Buildings receive resistance1200 and remain intact. Its native
DigMesh/Clip system rebuilds geometry; DigPhysics removes collision contacts in
dug cells. This is a separate geometry/collision subsystem, not simply calling
the host game's explosion function. Geometry must be available to the host.

EldenCraft's pinned
[progression design](https://github.com/SocketByte/EldenCraft/blob/ba7591cdde9fb16e17552cfe53546f44d0fd856e/docs/progression-design.md#loot-supplies-and-gathering)
explicitly keeps native terrain intact under its current gathering model.
Its native world_bridge explosion handler translates damage to actors/player;
it does not implement SkyCraft-style terrain excavation.

## Inspected KCD2 support

Installed tools `Data/Scripts.pak`, read-only; normalized inspection copies are
ignored under `runtime/research/scenery-destruction/Scripts/Entities/`:

- `Physics/DestroyableObject.lua:492–581`: `Server.OnHit` accepts explosion hits
  and honors vulnerability, invulnerability, thresholds and player-only settings.
- Lines350–443 and463–488: native Die/Dead/Explode flow calls BreakToPieces,
  swaps and physicalizes the destroyed model, or hides the original. Native
  save/load records health, death, explosion state and slot selection.
- `EntityCommon.lua:126–214` supplies the killable health wrapper.
- `Physics/BasicEntity.lua` deliberately omits MakeKillable. Ordinary static
  brushes and terrain do not inherit the DestroyableObject damage path.
- Real installed assets include barrel_a.cgf and barrel_broken.cgf under
  `Objects/manmade/common_furniture/barrels/`. Their presence supports a native
  model-swap fixture, not a claim that existing world barrels are breakable
  entities or contain authored fracture fragments.
- Physics.SimulateExplosion is documented as physical forces without gameplay
  damage, but has no documented actor exclusion list. General static-geometry
  fracture, terrain craters and EnvironmentModule.MakeHole semantics were not
  established. Do not invent bindings or replace this with generic entity deletion.

No live count of existing DestroyableObject scenery, destruction fixture or
blast was performed before the user changed priorities. The fresh tools world
was closed and the temporary HUD installation restored.

## Preserved experiment, not production

Partial changes explored extending the existing immutable blast grant with
native prop exposure and typed scenery outcomes. Minecraft would compute real
damage against invisible shape proxies; the native prop callback would run once
after NPC damage, preserving pre-explosion cover. The experiment excluded props
with secondary native explosions to avoid duplicated NPC damage.

It is incomplete and unverified. Archive:
`runtime/deferred/tnt-scenery-20261109/work-in-progress.patch`, based on commit
`389854301efbc97dfab576bf1a19a23b8097cead`, 52,680 bytes, SHA256
`99d84ab8e8668936351dac82370d9734128878886284c7aeb7c9b40d06f234fd`.
All production source files were restored to that verified commit. Revisit only
after a deliberate scope decision; do not resume the patch merely because it exists.
