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
  The adapter calls `(0, healthDamage, player.this.id, false)`, scales Minecraft damage
  by the target's real maximum health, caps at remaining health, and reports
  actual before/after health. It never retries a setter after an ambiguous result.
  Official `Scripts/AI/special/hostageSituation/maleHoldsTiedFemale_kidnapper.xml`
  uses `player.this.id` for this argument. This is the player's WUID, distinct
  from the entity handle `player.id` used for rays and entity lookup. The session
  captures both identities and rejects missing/replaced WUIDs before damage.
  The earlier entity-handle call changed HP, but that alone did not validate
  correct attacker attribution or native hit reactions.
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
were confirmed. The passive NPC's lock observations remained false; that check
did not establish hostile lock suppression or native reciprocal damage.

## Native hit reactions

The corrected WUID call passed the production native adapter check: HP100→65,
duplicate acknowledgement without repeated damage, zero movement writes and
exact cleanup:
`runtime/evidence/combat-native-20261108-221428-7cc1bb949525489495c705b993dece07/result.json`.

`Test-KcdCombatReaction.ps1` compares fresh owned NPCs with reactions enabled and
suppressed, samples only documented getters and records separate native HP
evidence. With the correct WUID, both cases took35HP damage, while
`GetCurrentAnimationState()` still reported `MotionIdle`, `GetCurAnimation()` was
nil, and the read-only `hitReaction` brain variable was nil. Those getters cannot
prove or disprove a layered flinch in this fixture:
`runtime/evidence/combat-reaction-20261108-221429-6f97fea063714c77a1f942e14b235b8c/result.json`.

Timed native-window screenshots were then inspected automatically, without user
input. The enabled case visibly recoiled (torso/head bend and arms moving); the
suppressed control stayed upright. The production default with no explicit body
part also recoiled. All three runs recorded100→65HP and exact timer/NPC/path
cleanup. `visual-observation.json` beside the result above records this separate
visual observation; the log-only runner deliberately continues to report
`visual_animation_verified=false`. This confirms a basic native reaction on the
owned debug NPC, not every enemy/stagger variation or a new coupled-HUD visual
acceptance. No animation was forced and no native combat lock was requested.

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

A bounded protection experiment now runs without changing the unknown GameRules
baseline. Official `Libs/Tables/rpg/buff.xml:150` defines
`player_immortality_nonpersistent` (`44e1ccc9-9252-48a9-922d-2ae4523c69a3`,
`imm=1,upr=1`); training combat applies it in
`Scripts/Quests/Final/Barbora/utils/combat/traininggroundmanager.xml:154`.
`Scripts/Scripts/Debug/CombatDebug.lua:207-212` demonstrates retaining the instance
returned by `soul:AddBuff` and removing that exact instance with `RemoveBuff`.
Its `IdExclusive` rule (`buff_exclusivity.xml:5`) requires a confirmed absent
baseline before ownership can be claimed.

On an isolated owned NPC, `Test-KcdCombatProtection.ps1` observed native health
100→90 after nonlethal damage, then 90→1 after lethal damage, with the actor alive.
`HasBuffDebug` returned false before admission and true after `AddBuff`; the
returned instance was removed, the original callback table restored, and the NPC
and path wrapper cleaned up. Evidence:
`runtime/evidence/combat-protection-20261108-221837-f34ba64258f84048ba23c422e0c3bb50/result.json`.
This final run uses the corrected stable WUID and records
`attacker_identifier_kind='wuid'`. The earlier220441 run used the entity handle;
it remains historical evidence, not the basis for corrected attribution claims.
The player's health, buffs and camera were not changed. Its read-only buff
baseline was also false. This establishes a candidate native death guard, not
incoming damage interception or hostile camera behavior.

Neither corrected-WUID `DealDamage` nor the source-supported legacy
`g_gameRules:CreateHit(...,'normal')` route produced a `Client.OnHit` callback.
The latter did not change native health at all (100→100→100), correctly leaving
`protection_observed=false`:
`runtime/evidence/combat-protection-20261108-220756-6a028ad533e449869c38778c496e7452/result.json`.
Do not use that ignored legacy route or infer callbacks from health changes.
No native player protection is enabled in gameplay yet.

Official player and NPC root AI behaviors store their native `hitReaction` inbox
in a variable of the same name. `XGenAIModule.GetBrainVariable(wuid,name)` is a
documented read-only candidate, but the public bindings expose no Lua inbox
subscription or event sequence. A snapshot alone cannot distinguish repeated
identical hits; do not turn it into an incoming damage stream without proof of
freshness and event identity. The owned path-follower NPC returned nil throughout
both corrected-WUID reaction comparisons. Do not keep polling that fixture as
though it supplied a damage event stream.

## Hostile NPC and scoped target-lock policy (2026-11-09)

The fixture's optional `hostile` mode uses the official `combatEnemy_3` soul,
`d2a3c045-2d43-491c-80a4-96137fcb99de`, with its native `npc_basic` brain and enemy
faction. The [official CombatDebug routine](https://github.com/muyuanjin/kcd2-mod-docs/blob/9cb067543245ec5cf4e27b3d21e32485a35db518/Scripts/Scripts/Debug/CombatDebug.lua#L539)
supplies the soul; its novice profile and unarmed preset are applied only to the
owned NPC. Unlike the passive fixture, this mode installs no path-follower
wrapper and does not disable perception. Exact identity and deferred removal
remain required.

`Test-KcdRetaliation.ps1` observed actual native attacks reducing player health
100→93.58099365, with `lock_seen=true`:
`runtime/evidence/combat-retaliation-20261109-092231-dbc5b712a46c49bb866e59922dc844e1/result.json`.
The preserved `Client.OnHit` observer received zero callbacks and the player's
`hitReaction` brain variable stayed nil. Thus the receipt's callback-based
`attack_observed=false` does not mean no attack occurred. The temporary player
immortality instance was removed after confirmed hostile removal; no direct
player damage, health refund or movement write was used.

The production combat session now owns three settings listed by
[CombatDebug.TestLock](https://github.com/muyuanjin/kcd2-mod-docs/blob/9cb067543245ec5cf4e27b3d21e32485a35db518/Scripts/Scripts/Debug/CombatDebug.lua#L1324):
`wh_cs_playermaxopponentdistancetolock`,
`wh_cs_playermaxopponentdistancetounlock`, and `wh_cs_playerunlocktimeout`.
It captures all finite baselines before writes, sets them to0, verifies continued
ownership, and restores exact prior values on stop/failure/lease expiry. Unknown
or foreign values are not overwritten; unconfirmed cleanup blocks another session.

The `-FreeAim` comparison retained native attacks (100→78.81308746HP) while
`lock_seen=false`; original values4/7/3 were restored, with confirmed timer,
callback, buff and NPC cleanup:
`runtime/evidence/combat-retaliation-20261109-093152-cb6830f053b344efb5fdba6e6918683c/result.json`.
This verifies the observed target-lock state while the NPC attacks. It does not
establish physical mouse feel, unrestricted walking during hostile combat, or a
coupled Minecraft HUD acceptance. Incoming Minecraft damage is still disabled.

## Native combat telemetry candidate

[CombatDebug.StartLog](https://github.com/muyuanjin/kcd2-mod-docs/blob/9cb067543245ec5cf4e27b3d21e32485a35db518/Scripts/Scripts/Debug/CombatDebug.lua#L1295)
documents file logging through `wh_rpg_LogTarget`, `LogLevel`, `LogType`,
`LogReasons`, `LogInterval`, `LogSize`, `TelemetryLimitedToPlayline` and
`wh_rpg_ResetLogging`. A temporary owned comparison used raw GUID mode
(`LogType=0`) and `LogInterval=0.125`. It captured five actual punch events with
`cause.name='CombatHit'`, attacker/victim GUIDs, and `SoulState`/`HealthValue`
health effects. Their deltas total21.18691, matching the observed native HP loss.
Snapshots are in
`runtime/evidence/combat-stream-watch-0ba69e97163c4ec9b8ce3e6d1e681160`;
logging restoration and normal game exit are confirmed in
`runtime/evidence/combat-telemetry-stream-20261109-093151-edf1a91bfc464a4b87bfe58776aee321/cleanup.json`.

This is a promising event source, not production retaliation. Before connecting
it to `hurts`, verify same-second file replacement/loss, duplicate delivery,
damage representation at the immortality1HP clamp, and exact GUID-to-live-actor
generation mapping. The0.125 setting alone does not prove125ms delivery latency.
The native log reader must establish event identity and completeness rather than
infer damage from polled player health.

If telemetry cannot meet those requirements, the inspected retail SDK exposes
`C_CombatActor::ConnectOnHitReceivedSignal` and raw `S_HitInfo.damage`; the
Floating Damage example also observes `S_DamageEventData::Dispatch`. Those are
retail1.5.6 APIs, not tools1.5.5 compatibility evidence. The installed retail
build still lacks the verified KCSE address map and loader; see the
[native backend prerequisites](KCD2.md#loader-and-the-immediate-blocker).

## Bow projectile collision and damage (2026-11-09)

The projectile bridge uses separate trace/impact identities; distant arrow
contacts never enter the melee route's current-eye check. The real server arrow
owns a UUID, shooter and bow weapon. Native admission checks its initial segment
against the current player eye/direction, then requires continuous endpoints,
bounded travel and the same combat lease. Each reply retains its original receipt
time; duplicates return cached results and cannot refresh an expired impact.

Native `Physics.RayWorldIntersection` checks scenery along each actual segment.
Nearby NPCs come from `System.GetEntitiesInSphere`; their exact live AABBs and
generation-bound actor tokens determine the nearest actor contact. Scenery in
front wins. Impact rechecks identity, current geometry and obstruction before
consuming the contact and calling attributed `DealDamage` once. A failed or
uncertain setter is never retried as a new hit. The existing NPC binding and
player WUID attribution sources above remain applicable.

The pinned Minecraft1.21.1 / Yarn1.21.1+build.3 implementations were inspected in
`PersistentProjectileEntity.tick`, `getEntityCollision`, `onEntityHit`,
`onBlockHit`, and `ProjectileUtil.getEntityCollision`. The latter's six-argument
overload supplies a0.3f entity margin; native projectile actor checks use the
same margin, including impact revalidation. This does not enlarge scenery or
melee hitboxes. Source inspection is saved locally under
`runtime/evidence/projectile-impact-source-20261109/`.

Minecraft still executes its actual impact pipeline, including charge, critical
randomization and weapon effects on the proxy. Only the resulting health damage
fraction is transferred to KCD2; native knockback, potion effects, Flame and
spectral highlighting are not implemented. Normal, tipped and spectral bow
entities enter the same base-class collision hook; crossbows and piercing do not.
The scenery hook supplies a real vanilla block-hit result without placing fake
Minecraft blocks, preserving embedding, aging, save and pickup.

The file transport currently gates every flight tick on a native segment reply.
It is bounded to16 active flights,4m segments,64m cumulative travel and10s per
flight. This establishes checked collision rather than vanilla-speed flight;
travel latency remains a performance limitation. Exact-owner client arrows
mirror the authoritative server trajectory while replies are pending.
The controller now dispatches the next clear segment immediately after vanilla's
completed tick, using its actual new position/velocity. This overlaps the request
with the normal interval between ticks without simulating unverified motion.
It applies only to the sole airborne arrow to avoid monopolizing the transport.
