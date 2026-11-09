# Native attacks and Minecraft health

The incoming adapter consumes actual KCD2 RPG `CombatHit` records. It does not
infer attacks from health polling or manufacture hits in the acceptance fixture.
Minecraft applies the admitted damage on its server thread with its own armor,
hurt cooldown, Creative immunity and death/respawn behavior.

## Native source and identity

Inspected official `CombatDebug.StartLog`/`StopLog` code supports local RPG logging,
`SetCVar` and `wh_rpg_ResetLogging`. The installed tools binary documents target2
as local files; target1 is remote telemetry and is not used. LogType2 includes
both persistent soul GUIDs and exact runtime entity names. Live evidence confirms
that these names match `entity:GetName()`, including the unique fixture name.

Entity GUIDs and soul runtime IDs are **not** telemetry soul GUIDs. Actual probes
returned a numeric entity-GUID table and `[soul-593]` for the player, whereas the
telemetry contained a different persistent GUID. Do not substitute those IDs.

Each native sample binds a unique runtime name to its existing exact
entity/soul/generation token and first-observed native clock. The reader matches
that name, rejects pre-generation events, then pins the telemetry GUID. Nearby
duplicate names, including the player's name, cannot be used for attribution.
Melee admission includes the official weapon-table pairs stab0→4/5,
slash1→5/6, smash2→4 and unarmed4/5/6/7/9→4. Actual longsword captures
corroborate slash1/6 and stab0/5. Unknown classifications remain unsupported.
Native projectile admission remains disabled until a real ranged event establishes
its cause/effect schema. The Minecraft adapter is ready, but native ranged combat
has not passed an integrated check.

## Damage and native health

`HealthValue` is the attributed native health loss, **not pre-clamp weapon damage**.
A live hit at protected native HP1 produced value0. Keeping the native player
immortal at1HP therefore cannot provide continuing incoming damage.

During the owned combat lease, official `Soul.SetState('health', value)` keeps
the native player at its maximum health, with an owned official immortality buff
as a death guard. Official feature tests also use this setter. Minecraft health
is never replenished by that operation. The adapter restores the original native
health, its own buff instance and all nine logging CVars on cleanup while their
identities remain owned. The actual normalized hit is native loss/native maximum
times20; native armor already participates in that native loss, and Minecraft
armor then processes the translated hit. This is an initial damage balance,
not a claim of exact vanilla weapon parity or complete native status-effect sync.

Armed native hits also need session-owned injury protection. Without it, a
successful sword check left native bleeding running after the health guard ended.
The official nonpersistent `bleeding_protection` buff sets `hin=0`
(`Inter_HitInjury`), separately from `hlh` (`Inter_HealthLossHit`). The adapter
requires an absent baseline, owns the returned buff instance and removes that
exact instance on cleanup. It never clears pre-existing injuries. Its effect on
actual hit telemetry and post-session health is checked separately from presence.

Incoming damage carries an immutable `melee` or `projectile` kind through its
queue. Minecraft uses its normal mob-attack source for melee and its actual
`DamageSources.arrow` source for admitted native projectiles. The latter uses a
short-lived, unspawned arrow solely for source attribution; it never flies or
renders a duplicate native arrow. A `finally` block discards it. This preserves
vanilla projectile tags, armor and Projectile Protection. An actual Minecraft
fixture measured6.464 armored damage versus4.396 with Projectile Protection IV
for the same8-point hit, with two adapters created/removed and none left active.

## Transport and replay

Each rotation closes an epoch into a unique directory. Reusing the default
same-second filename can overwrite batches, so it is unsuitable as an event
queue. Buffered events may land in a later epoch: enforce the session/generation
lower bounds, not the preceding epoch's clock. Actual captures showed roughly
0.36–0.60 seconds from hit to closed batch. This path is not instantaneous.

An event cursor is epoch/file/array-index with immutable content hashes. Two
identical-looking attacks at different cursors remain separate events. Bounded
send/receipt brackets anchor native event time to UTC. KCD2's game clock can drift
from Windows time; a fixed session offset failed in live testing. The adapter
keeps32 recent anchors and converts each event using its enclosing native-clock
pair once, without extrapolation. Original timestamps survive publication and
retry; stale first admission fails. Pending hits retain
their attacker snapshot until Minecraft acknowledges them. Minecraft preserves
source intervals without resetting vanilla hurt cooldowns and discards old-life
hits across respawn.

Native actor discovery covers32m, with the existing eight-actor limit. Ranged
NPCs can retreat beyond the old16m radius before firing. Enlarging discovery
does not increase melee reach or permit damage from an unidentified attacker.

Native health upkeep may generate empty-cause healing records. They are ignored;
only attributed CombatHit health losses can produce Minecraft damage.

## Native hit reactions

The movement adapter tolerates a native horizontal hit impulse up to3m/s for at
most500ms after observed native health loss, under the same exact combat and
movement owner. It retains the vertical-velocity and0.35m position guards. This
allowance never creates a Minecraft hit or resets velocity. Repeated health reads
cannot extend it.

Minecraft processes the hit after native log delivery, so its knockback can arrive
after that initial window. The guarded host forwards the consumed-hurt ACK before
the next movement pose. Each new cumulative ACK grants a separate750ms window;
duplicates replay the original receipt and cannot renew it. Physical caps and
position-drift checks remain unchanged. The automatic fixture uses nine captured
tiles to accommodate real knockback instead of bypassing the terrain boundary.

Moving camera snapshots validate their actual orthonormal basis and derive
movement yaw/pitch from forward. They no longer reuse the initial teleport
seed's1-degree roll restriction. Native recoil legitimately rolls the camera;
world rendering and depth reprojection keep its full original up vector. The
initial seed contract and native camera settings remain unchanged.

## Evidence

Runtime evidence stays outside Git:

- **Final sword acceptance with injury protection PASS:**
  `gameplay-kcd-20261109-150004-56894fe8881d4de883f7197ce853ef65`:
  Minecraft health20→17.45866,11.25 seconds of post-hit HUD composition,
  144 composition/reprojection advances, normal save/exit and both protection
  instances, health, logging, NPC and movement restored.
- **Native injury prevention PASS:**
  `armed-capture-20261109-144045-340a9b993c8e40829232d71cfe04ae52`:
  actual sword losses8.92498/8.88051/7.94642, no new native injuries, HP100
  stable for five seconds after both guards were removed.
- **Actual Minecraft projectile regression PASS:**
  `gameplay-combat-20261109-143250-0ec06c3e506f411baa67018b07048563`:
  four incoming hits, projectile protection, adapter cleanup and outgoing bow
  flight/scenery/NPC impact checks. Incoming host events are explicitly synthetic.
- **Sword coupled acceptance PASS:**
  `gameplay-kcd-20261109-142935-aef9646234a34d53bf99504bb695c23a`:
  an actual native longsword slash caused8.92364 native damage and1.784728
  Minecraft damage, health20→18.215271. The native HUD continued composing
  for11.25 seconds after removal, with202 composition/reprojection advances.
  Save/exit and native health, buff, logging, NPC and movement cleanup passed.
- `armed-capture-20261109-142738-5b495f41eaee4d0c887b21f20187361e`:
  nine actual native sword hits, slash1/6 and stab0/5, with complete cleanup.
- **Coupled acceptance PASS:**
  `gameplay-kcd-20261109-141001-8462b86ec10c4c6cafb563d0467dccd7`:
  two real native hits6.342/3.2095, Minecraft20→18.7316→18.0897, ACK2;
  inventory damage, NPC removal, three captures and11.25s continued HUD passed.
  Native composition/reprojection advanced201 frames, and original native health,
  protection, logging and movement state were restored. Source-to-Minecraft
  application was913/923ms in this run. No physical keyboard/mouse claim.
- `incoming-validation-20261109-131516-bbc1a2c79a1147dbbc666fd4c426b194`:
  disproved pre-clamp damage and direct runtime-ID/GUID equivalence.
- `incoming-validation-20261109-132611-ba094725ea6243ac9f720d0df8a6effc`:
  exact runtime names, three actual native hits and health upkeep; repeated file
  hashes did not change. The isolated helper conservatively refused its final
  health restore after a last injury, which is not a production cleanup PASS.
- `incoming-production-20261109-133308-c738a60381ad4744aee071b25b39b626`:
  actual native production Begin/Sample/End, with health/buff/CVar restoration.
- `gameplay-combat-20261109-131936-d14966f718914b9f998713a4d05e8ac4`:
  actual standalone Minecraft health20→12; armored20→13.536, armor wear2;
  exactly two immutable incoming receipts and normal cleanup. Source events in
  this standalone check were synthetic.

Use `Test-KcdIncomingCombat.ps1` for the connected acceptance check and its
`-VerifyEvidenceDirectory` option to recheck saved evidence without starting
either game. Default `-IncomingWeapon unarmed` waits for two real hostile attacks,
including a hit in inventory. `-IncomingWeapon sword` needs one real armed hit,
then removes the attacker and checks continuing HUD composition; requiring another
armed hit could kill the test player. Verification binds the observation to the
original source event, acknowledged damage and authoritative Minecraft health.

`bow` and `crossbow` are unfinished diagnostic modes. Native fixtures equipped
real weapons/ammunition, but neither consumed ammunition nor produced a shot.
Bow loading overflowed native animation queues. Crossbow actors faced the player
with weapons drawn, retreated to about26m and sometimes reached a loaded
animation. Grounded placement, foreground operation, courage30, explicit ammo
equipping, backup-weapon removal and45-second capture did not establish a hit.
Offense/defence/forced-melee context checks were false. Final evidence:
`armed-capture-20261109-145735-53c9c8c3bed341158e10fff49b448157`.
Lua and observed REST metadata exposed no documented per-actor context setter or
direct shot method. A real configured archer/behavior and actual projectile
telemetry are still required; do not infer a schema from equipment alone.
