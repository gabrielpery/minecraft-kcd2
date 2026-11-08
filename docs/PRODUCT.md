# MineCome product target

User-confirmed scope, 5 November 2026. This defines the intended product, not
features available in the current development prototype. The original goal is
real Minecraft Java gameplay inside the actual Kingdom Come: Deliverance II
world, following the integration principles of SkyCraft and EldenCraft.

## Required experience

KCD2 is the primary window. A real Minecraft process supplies its game systems
in the background. The player is Minecraft's Steve, with Minecraft hands, held
items, equipment and a visible character in third person. KCD2 supplies its
environment, NPCs, AI, dialogue and quests wherever the integration permits.

| Area | Product requirement |
|---|---|
| Player and movement | Minecraft walking, sprinting, jumping, crouching, swimming, falling and camera perspectives on KCD2 collision; continuous exploration with terrain acquired as needed. |
| Flight | Creative flight, including normal double-tap jump, ascent/descent and sprint flight; vanilla Elytra equipping, gliding, steering, firework boosting, landing and collision/damage behavior. Host camera and collision must follow throughout. |
| Commands | Open Minecraft chat/command entry from the KCD2 window. Execute actual vanilla commands on the dedicated Minecraft server, including `/gamemode survival`, `/gamemode creative` and `/give`, with the appropriate world permissions. Preserve feedback, suggestions and completion. Mode changes must update controls, UI, abilities, mining and survival rules without restarting either game. |
| Visuals and UI | Steve/skin, hands, held items, armour, first/third person, Minecraft hotbar, health, hunger, armour, experience, inventory and interaction screens inside KCD2. Use Minecraft-generated content and lighting/depth integration appropriate to each layer. |
| Building and mining | General Minecraft block/item states, placement on targeted faces, survival breaking time, tools, drops, durability and persistent player construction. The finished scope is not restricted to stone or a fixed arena. |
| Survival | Real Minecraft health, hunger, saturation, food, regeneration, armour, effects, fall/environmental damage, death and respawn. Minecraft's server owns the player's survival state; a decorative HUD does not satisfy this requirement. |
| Combat | Minecraft melee/ranged weapons and combat rules against KCD2 NPCs, with reciprocal NPC attacks damaging the Minecraft player. Preserve native NPC identity/AI and translate damage coherently between the games. |
| Systems | Crafting, containers, furnaces, enchanting, redstone, moving blocks, fluids, TNT/explosions, Minecraft mobs and their relevant interactions with the host world. |
| Host world | Preserve KCD2 towns, buildings, weather, dialogue, quests and native interactions where compatible. Persistent mining/deformation of native terrain and environmental objects remains part of the full target. |
| Persistence and delivery | A reusable world/session, saved inventory/player state and construction, clean reload/reconnect, a supported KCD2 build, repeatable installation and one normal start/stop flow. No short demo cutoff or automatic return to the starting position in ordinary play. |

Commands use Minecraft's parser and server permission checks, not arbitrary KCD2
console execution. Command-driven teleportation, death, world changes and mode
changes need the same movement/session reconciliation as ordinary gameplay.
Combat must remain free-moving and free-aiming, as in Minecraft. KCD2 target lock,
forced camera alignment and combat movement restrictions must not take ownership
of the player during MineCome gameplay. NPCs retain their native movement and
attacks; session cleanup restores any host control settings it changes.
Native enemies should visibly react to valid Minecraft hits through KCD2's own
hit-reaction/animation system. Health loss alone does not establish that visual
requirement. Minecraft bows and crossbows are part of ranged combat: preserve
actual charge/ammunition, projectile flight, collisions, damage and enchantments,
and render the real Minecraft projectiles in the host world.
Flights must use Minecraft's actual ability and Elytra mechanics; increasing a
ground-test position limit alone is not a flight implementation.

## Reference parity

Comparable Minecraft functionality demonstrated by SkyCraft and EldenCraft is
the full ambition. Do not silently reduce that to a HUD, stone demo or Creative
walking. Game-specific features such as Skyrim skills or Elden Ring's Torrent
need a deliberate KCD2 counterpart; they are not literal assets to copy. Record
unsupported interactions and constraints explicitly. New upstream features do
not silently change the release checklist.

## Delivery order

1. **Persistent playable foundation:** reusable Minecraft save, sustained input,
   camera/HUD, ongoing collision acquisition, general block ownership and clean
   recovery. Resolve the supported KCD2 runtime/access path alongside this work.
2. **Minecraft player and sandbox:** Steve/hands/items/armour, arbitrary block
   rendering, chat/commands, Creative flight and persistent construction in that
   same session. Introduce a general rendering path rather than another asset
   pipeline for each block or item.
3. **Survival and combat:** a complete food/health/mining/crafting loop, NPC
   attacks in both directions, death/respawn, and Elytra/rocket flight in the same
   persistent session. These are required features, not optional polish.
4. **Extended systems and release:** remaining block entities/redstone/fluids,
   mobs, native terrain destruction, progression/quest compatibility and packaging.

Milestones are implementation order, not reduced final scope. A finished product
must satisfy the agreed required experience and list any remaining limitations.
Do not promise a release date based only on passing isolated tests.

## Development policy

Prioritize playable progress per unit of time and usage. Reuse existing automation;
fix concrete integration blockers instead of creating more short-lived labs.
Keep essential compatibility, ownership, thread and recovery checks. Defer
non-blocking polish. Batch manual acceptance at a larger playable milestone;
no repeated F8 countdowns or already-proven small input sequences.

Current implementation and evidence belong in [PROGRESS.md](PROGRESS.md), and the
next concrete task belongs in [NEXT_SESSION.md](NEXT_SESSION.md).
