# Elytra bridge implementation

Pinned target: Minecraft Java 1.21.1, Yarn build 3. Inspected mapped jar SHA-256:
`06a137a0b9597798455412349a45255ee37f351ceaa37d731096880be6c6a727`.
Local bytecode evidence is under `runtime/evidence/elytra-source-20261117/`.

- `ClientPlayerEntity.tickMovement`: a fresh jump edge calls `checkFallFlying`
  and sends `START_FALL_FLYING`; the bridge forwards input, never sets that flag.
- `PlayerEntity.checkFallFlying`: airborne, usable chest Elytra, no flight,
  water or levitation. The FALL_FLYING pose is 0.6×0.6 with a 0.4 eye height.
- `LivingEntity.travel`: vanilla yaw/pitch, gravity, lift, drag, swept movement,
  collision damage and landing. The client-only `GameplayGlideTravelMixin`
  holds only its exact installed player before travel when authority is absent.
  A second injection before `LivingEntity.move` checks the already computed
  displacement against captured coverage. It does not reproduce flight physics.
- `LivingEntity.tickFallFlying`: equipment eligibility and durability remain
  vanilla, including while the bridge holds movement for inventory.
- `FireworkRocketItem.use` / `FireworkRocketEntity.tick`: immediate main-hand
  use creates the attached rocket and consumes it; the actual entity applies
  boost. The controller checks a fresh same-player/server/slot/component snapshot.
- `LivingEntity` NBT writes/reads `FallFlying`. The terrain checkpoint adds a
  distinct `gliding` tag. Attachment validates the saved vanilla flag and holds
  travel while client/server pose and position agree. Velocity resets during
  attachment; attached rockets may subsequently change it while travel is held.

Native pose transport adds optional `eyeHeight` and `gliding`, with legacy
standing/false defaults. Camera override is used for nonstanding eyes, even in
first person, and admitted only after native camera readback. Returning to
standing restores the normal camera. Death publishes its frozen alive anchor's
pose metadata. Glide admits at most 80 m/s; Creative retains 24 m/s. One final
landing interval may use the prior accepted glide speed profile.

Main Play/WorldBlocks includes the camera path. Older HUD-only Flight sessions
hold Elytra rather than expose a standing-eye mismatch. First-person aiming,
third-person camera placement and Minecraft rendering use the same actual eye.
Captured heightfield and owned block collision remain the coverage limit;
unsampled native roofs, walls and branches are not magically made solid. The
18-metre altitude ceiling and unknown-terrain holds remain in force.

Automation: `Test-GameplayElytra.ps1` covers actual equip/input/glide/steering,
rocket consumption/boost, inventory hold, landing/damage and walking; `-Persistence`
saves/reopens a glide. `Test-KcdElytra.ps1` separately exercises actual KCD2 camera,
position following, composition and cleanup using scripted guest input.
