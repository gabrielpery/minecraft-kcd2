# Native combat evidence

Inspected source: `external/kcd2-mod-docs` commit
`9cb067543245ec5cf4e27b3d21e32485a35db518`, checked against the installed official
tools `Data/Scripts.pak`. No executable offsets or original game assets are added
to this repository. Native commands use the existing exact executable/process
and loopback-owner guard and execute through the game console on its game thread.

## Implemented outgoing melee adapter

- `System.GetEntitiesInSphere(center,radius)` returns entity tables. The bridge
  samples at most eight nearby actors with bounded world AABBs, native health and
  maximum health. Tokens are assigned once per entity/soul generation (up to256
  per session); a reused entity ID cannot retarget a queued hit.
- `Entity.GetWorldBBox()` returns two world vectors. This return shape is also
  used by `Scripts/Entities/EntityCommon.lua:950` and
  `Scripts/Entities/Doors/AnimDoor.lua:444`.
- `Entity.GetRawId()`, `soul:GetId()`, `soul:GetState('health')` and
  `actor:GetMaxHealth()` provide identity/health checks. These are individual
  binding pages in `script_bind_2025_01_14`.
- `soul:DealDamage(stamina,health,attackerId,suppressHitreaction,bodyPart)` uses
  **stamina first** and **health second**, as documented by
  `C_ScriptBindSoul__DealDamage@IFunctionHandler__@float@float.html`.
  The adapter calls `(0, healthDamage, player.id, false)`, scales Minecraft damage
  by the target's real maximum health, caps at remaining health, and reports
  actual before/after health. It never retries a setter after an ambiguous result.
- `Physics.RayWorldIntersection(origin,direction,capacity,mask,skip1,skip2,hits)`
  is used in installed `Scripts/Entities/Physics/PressurizedObject.lua:308-315`.
  A fresh native scene ray excludes player and target, checks all returned
  distances, and refuses obstruction/unknown results. Hits also require a sample
  no older than300ms, a current matching entity/soul generation, native eye/aim
  agreement and at most4.5m reach (Creative maximum). The guest's conservative
  square proxy supplies an aim point; native code intersects its ray with the
  actual rectangular AABB and traces scenery all the way to that real contact.
- Native actor generation, wall obstruction, replay, stale aim, unknown setter
  outcomes and cleanup are covered by standalone Lua simulations. Host tests
  cover strict identity, nested duplicate JSON keys, numeric bounds, freshness,
  single pending attack, acknowledgement and atomic publication. These do not
  alone establish native NPC damage or playable hostile combat.

## Live read-only observations (official tools1.5.5.0, 2026-11-08)

The loaded test world's player reported100 health/100 maximum health; native
GetRawId and both AABB vectors returned valid values. Soul identity is an opaque
WUID userdata. There were no other actor+soul entities within512m of the default
start, so an isolated NPC fixture is required for real damage checks.

`combat_fixture.lua` uses the official
`Scripts/Debug/PathfindDebugUtils.lua:30-58` template:
`XGenAIModule.SpawnEntity` with `ClassName='NPC'`, shared soul
`88bee0ec-f164-4282-ae1e-6576a76b9bac`, `Properties`, `Pos`, `Rot` and the two
documented perception fields. The fixture has a unique run name, maximum120s
lifetime, exact name/ID/entity/soul ownership checks and cleanup. A post-create
error is cleaned up only when the newly named NPC can be independently identified;
unknown ownership is reported as unconfirmed, never as successful removal.
Native `RemoveEntity` is deferred: cleanup issues removal once, then polls exact
ownership/disappearance for at most40 timer callbacks (50ms each). Actual native
spawn, enumeration with health100/max100, stable soul identity, and confirmed
deferred removal were verified in
`runtime/evidence/combat-filter-native-20261108-203126-574d932a1ab847ba93e7e4d0429113cc`.

The official dummy is intentionally short lived. Its
`Scripts/AI/haste/test_pathfollower_dummy.xml` behavior waits3s, moves toward the
destination returned by `PathfindDebugUtils.FindDataTable` (fallback: the player),
waits10×1s, then calls `<Despawn DeSpawnedEntity="$this.id"/>`. Spawning it before
Minecraft's roughly24s startup therefore produced empty, correctly filtered
actor snapshots. The coupled fixture must spawn **after Minecraft is ready**,
immediately before the native host starts, and verify the attack early. Its AI
and natural self-removal are retained; the120s ownership timer is an upper cleanup
bound, not a promise that this debug NPC will live for120s.
For the connected check, the fixture temporarily wraps the inspected
`PathfindDebugUtils.FindDataTable(entityId)` function: only its exact owned actor
receives its own spawn position as the destination. This prevents the debug
fallback from walking into/pushing the native player during the test. Other
entities forward to the original function and `PathfindDebugUtils.Data` is never
modified. Cleanup verifies restoration of the exact original function; the
production combat adapter does not install this wrapper or change NPC behavior.

`scripts/Test-KcdNativeCombat.ps1 -ExpectedPid <exact-tools-pid>` now verifies the
real native adapter before a coupled launch. On2026-11-08 its production-path
sample and `.35` health-fraction hit changed the owned NPC from100 to65 HP. A
duplicate sequence left65 HP. Both lock observations were false, movement writes
were zero, all movement/combat timers canceled, and the NPC's removal was
confirmed. Evidence:
`runtime/evidence/combat-native-20261108-204151-78f062aac0ca47669d56ed2a803c6f0f/result.json`.
This proves native damage and deduplication; it is not yet the coupled Minecraft
attack proof or a hostile NPC/free-camera/reciprocal-damage acceptance test.

The later coupled production-path check also passed:
`runtime/evidence/gameplay-kcd-20261108-215647-d4359c30548545cbb27c6f5ccca282ba/native-combat-verification.json`.
Minecraft's real diamond-sword packet produced 7 damage, native HP changed 100→65,
one hit was acknowledged, and sword durability advanced once. Inventory held both
players still; subsequent walking and native composition/reprojection continued.
Normal save, timer cleanup, owned NPC removal and original path-function restoration
were confirmed. The passive NPC's lock observations remained false; hostile lock
suppression and native reciprocal damage remain unverified.

## Incoming damage and unrestricted camera remain separate requirements

`Scripts/GameRules/SinglePlayer.lua:291-298` forwards `Client.OnHit(hit)` to
`hit.target.Client.OnHit`. Live bindings expose this dispatcher, while the player
initially has no `Client.OnHit` callback. This is a **notification**, not evidence
that native melee damage can be intercepted before health/death handling.

GameRules exposes `SetInvulnerability`, `IsInvulnerable` and `ServerHit`; however,
the actual `g_gameRules.game:IsInvulnerable(player.id)` call returned nil. A safe
baseline/restore contract is therefore not established. The adapter does not
enable invulnerability, spoof incoming damage, heal/revive the native player, or
claim full reciprocal combat. Host `hurts` stays empty until a real inbound hook
is verified.

A source-supported protection experiment remains available without changing the
unknown GameRules baseline. Official `Libs/Tables/rpg/buff.xml:150` defines
`player_immortality_nonpersistent` (`44e1ccc9-9252-48a9-922d-2ae4523c69a3`,
`imm=1,upr=1`); training combat applies it in
`Scripts/Quests/Final/Barbora/utils/combat/traininggroundmanager.xml:154`.
`Scripts/Scripts/Debug/CombatDebug.lua:207-212` demonstrates retaining the instance
returned by `soul:AddBuff` and removing that exact instance with `RemoveBuff`.
Its `IdExclusive` rule (`buff_exclusivity.xml:5`) requires a confirmed absent
baseline before ownership can be claimed. Next test: on an isolated owned actor,
verify damage/death behavior and whether real hit notifications survive the buff,
then remove the owned instance. This has not been run or enabled in gameplay;
immortality must not be treated as proof of damage interception or combat unlock.

`player:IsLockedToOpponent(entityId)` is documented as checking melee target
lock. The adapter records optional `locked_before`/`locked_after` on real damage
receipts. No supported direct unlock setter was found. Official
`Scripts/Debug/CombatDebug.lua:1324-1339` lists player-specific lock CVars. Live
read-only values were `wh_cs_playermaxopponentdistancetolock=4`,
`wh_cs_playermaxopponentdistancetounlock=7`, `wh_cs_playerunlocktimeout=3`.
Changing these to zero might disable locking, but that behavior has not been
verified and is not enabled based on the names alone. A subsequent owned CVar
policy must verify effectiveness, retain native NPC AI/attacks, and restore the
exact prior values; the current adapter does not freeze NPCs or force native
melee mode.
