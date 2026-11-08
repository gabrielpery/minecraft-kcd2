# Death and respawn integration

Implemented 8 November 2026 for the owned Overworld gameplay session. Minecraft
owns death, dropped inventory, survival state and the real Respawn button. KCD2
follows an explicitly acknowledged relocation; ordinary pose speed and freshness
checks are unchanged.

## Lifecycle

- Fresh server death observations freeze the last valid owned pose and release
  movement, mining and food actions. DeathScreen uses the normal HUD pointer path;
  world keys, E, Escape and chat cannot bypass it.
- Fabric AFTER_RESPAWN queues the exact dead-to-live replacement. On the next
  server tick, the coordinator verifies the same server, world, UUID and network
  handler, including the handler's newly assigned player and UUID-manager entry.
  Teleporting inside the callback would move the old player.
- The default destination is the captured origin. An explicit Overworld spawn is
  admitted only with captured support and clear body/head space. Unsupported or
  blocked destinations stop the session; unrelated flat-world spawn is not used.
- Native death acknowledgment precedes one relocation for that epoch. Receipts
  bind run, world, process, patch, epoch, origin and target. Missing, changed,
  stale or replayed transitions cannot authorize an ordinary teleport.
- Client/server controllers explicitly rebind, retaining terrain, placed blocks
  and furnace identities while clearing old actions and observations. Late mouse
  release edges survive the UI rebind. The temporary terrain screen closes only
  after the new identities, native acknowledgment, received chunk and client pose
  agree; its usual renderer-ready condition cannot finish with terrain rendering
  suppressed by the HUD compositor.

## Persistence and coverage

Captured collision remains installed through the integrated server's final save.
The session closes the player connection, performs vanilla disconnect, then
releases collision at SERVER_STOPPED. Previously, drops could fall through the
removed terrain during shutdown and reopen far below it. No entity position,
velocity, inventory or death state is rewritten to repair this.

`Start-GameplaySession.ps1 -InitialTerrainRadius 1` enables exploration and
prefetches the eight neighboring tiles through real capture and durable admission.
Together with the original tile this provides a 24m-by-24m starting area when all
captures succeed. Refused terrain remains unknown. The respawn fixture requires
this ring because ordinary death drops can scatter beyond the original 8m area.
Items outside captured coverage still lack host collision; the ring is not an
unlimited-world guarantee.

## Automated verification

`Test-GameplayRespawn.ps1` passes two actual Minecraft launches in
`runtime/evidence/gameplay-respawn-20261108-195728-3e5a1e52c4f743f0974f5adcd5fb77e0/verification.json`.
It places a crafting table, walks away, uses vanilla Survival death with
keepInventory disabled, clicks the actual enabled Respawn button, verifies both
player replacements and continued walking, then saves and reopens. The same
three-diamond item entity, position and table survive reload. Nine terrain tiles
are admitted and retained. Standalone acknowledgments are explicitly local;
this result does not claim a native relocation.

`Test-KcdRespawn.ps1` runs the connected counterpart or validates an existing
receipt with `-VerifyEvidenceDirectory`. It requires genuine host terrain/camera,
matching native lifecycle acknowledgment, death-screen image bytes, compositor
progress during the death screen, post-respawn walking and normal cleanup.
Physical mouse acceptance is separate from scripted guest input.

Connected KCD2 PASS:
`runtime/evidence/gameplay-kcd-20261108-200330-a3cf004de7e04f23b48173bab56547f2/native-respawn-verification.json`.
Nine genuine terrain tiles, both lifecycle acknowledgements, actual button use,
health/food restoration, retained construction/drop and subsequent walking pass.
Native composition and reprojection each advanced 162 frames during the death
screen dwell; the client saved and closed normally and the native body restored.
This uses scripted guest input and logged composition, not a new physical-input
or post-composite screenshot claim.

The connected test exposed native float32 coordinate conversion and an early
acknowledgement while the follower was still interpolating. Lifecycle receipts
now require the exact original or float32-rounded target, a completed segment,
same-thread position readback and `applied_seq == pose_seq == seq`. Fresh frozen
poses renew their lease without restarting interpolation; ordinary movement
limits are unchanged. A consumed single-arm gameplay HUD process is rejected
before another Minecraft launch, with a clear KCD restart instruction.

Focused checks cover 171 strict acknowledgment cases, 42 Lua binding cases,
13 PowerShell lifecycle groups and 12 terrain-host groups. Existing movement and
block regressions remain applicable.

## Limits and next work

Cross-dimension respawn, beds/anchors outside admitted coverage, automatic instant
respawn, and unrelated command teleports are not verified by this milestone.
Opening a previously dead save is implemented but needs a dedicated restart
check. Native NPC damage exchange, Elytra and selective KCD health/stamina HUD
suppression remain required product work.

## Inspected source

Pinned Minecraft 1.21.1/Yarn evidence is under ignored
`runtime/evidence/respawn-source-20261108/`: PlayerManager, ServerPlayerEntity,
ServerPlayNetworkHandler, ClientPlayNetworkHandler, DeathScreen, WorldLoadingState
and MinecraftClient. Installed Fabric AFTER_RESPAWN and SERVER_STOPPED hooks were
inspected; SERVER_STOPPED runs after vanilla final save/world closure. No new
native engine offsets or unverified engine methods are used.
