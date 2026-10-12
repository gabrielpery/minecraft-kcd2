# KCD2 movement and camera API research

Read-only inspection on 2026-10-11. No movement, camera, input, physics or timer
commands were sent to the game for this research. These findings identify a
supported script route; they do not prove movement authority in the live world.

## Provenance

- `external/kcd2-mod-docs`, commit
  `9cb067543245ec5cf4e27b3d21e32485a35db518`; generated Warhorse binding archive
  `script_bind_2025_01_14` and archived official modding articles.
- `external/libKCD2`, commit
  `10d20f28faba462c4bf98a01abb48225cc51bb91`. Its reverse-engineered declarations
  target retail 1.5.6, whereas the current tested official-tools executable has
  fixed file version 1.0.0.0 and translated FileVersion/ProductVersion 1.5.5.0.
  These declarations corroborate names; they do not authorize native ABI calls
  in the tools build. The retail KCSE address-map prerequisite remains missing.
- Installed official tools archive, read in memory without extracting or changing
  files: `C:/Program Files (x86)/Steam/steamapps/common/KCD2Mod/Data/Scripts.pak`.
  Entry names and line numbers below refer to the unmodified archived Lua/XML.

## Supported position and view setters

The installed spawn path uses the exact player APIs we need:

| Source in installed `Scripts.pak` | Evidence |
|---|---|
| `Scripts/Entities/Others/SpawnPoint.lua:99-109` | Checks `g_localActor`, assigns it to `player`, calls `player:SetWorldPos(...)`, then `player.actor:PlayerSetViewAngles(...)`. |
| `Scripts/GameRules/SinglePlayer.lua:263-271` | The player spawn path calls the same position and view-angle setters. |

Entry SHA-256 values: SpawnPoint.lua
`3ebfcdf2b7254886b8a072fe54c6bdd003b7caf5017913f8e47872e504d22a2d`;
SinglePlayer.lua
`7f21cf79c1a8526f307db8329f502def5851c3aa33e34745a05079634a2fb3bc`.

The binding archive defines:

- `CScriptBindEntity__SetWorldPos@IFunctionHandler__@Vec3.html:52,60`:
  `Entity.SetWorldPos(vPos)`. Lua entity method syntax is `player:SetWorldPos({x=...,y=...,z=...})`.
- `CScriptBindEntity__GetWorldPos@IFunctionHandler__.html:60`:
  `Vec3 Entity.GetWorldPos()`; our existing diagnostic already samples it live.
- `C_ScriptBindActor__PlayerSetViewAngles@IFunctionHandler__@Ang3.html:52`:
  actor method with an `Ang3` argument. The installed scripts establish the
  `player.actor:PlayerSetViewAngles(angles)` access path. libKCD2 corroborates its
  registration in `include/entitymodule/C_ScriptBindActor.h:52`.

`SetWorldPos` changes an entity transform directly. It is a teleport/position
probe, not a demonstrated collision-respecting movement-controller request.
The archived [Crytek entity binding reference](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756813/pages/23306601)
also documents the world-position getter/setter; the installed KCD2 call sites
are the stronger evidence for this game.

## Read-only guards and snapshots

All binding filenames below are under `script_bind_2025_01_14`.

| Read | Exact evidence | Limit |
|---|---|---|
| `player:GetVelocity()` | `CScriptBindEntity__GetVelocity@IFunctionHandler__.html:60-62`, returns a three-component vector. | Check finite values and near-zero velocity. Live return shape still needs sampling; position writes do not promise to clear velocity. |
| `player.actor:IsDead()` and `:IsUnconscious()` | Installed `Scripts/Entities/AI/Shared/BasicAIActions.lua:44` checks both against `false`. The binding archive contains both methods. | Require actual booleans; missing/failed/ambiguous checks must refuse a write. |
| `player.player:IsSitting()` and `:IsLaying()` | Installed `BasicAIActions.lua:80`; binding pages `C_ScriptBindPlayer__IsSitting@IFunctionHandler__.html:60-62` and `...IsLaying...:60-62`. | Sitting/lying actions cannot be treated as ordinary stationary movement. |
| `player.human:IsMounted()` | `C_ScriptBindHuman__IsMounted@IFunctionHandler__.html:60-62`. Shipped player.lua uses the `human` table, e.g. line352. | Mounted return behavior has not been sampled live. |
| `player.actor:GetLinkedEntity()` | `C_ScriptBindActor__GetLinkedEntity@IFunctionHandler__.html:60-62`; installed SpeedLimiter.lua:88 only has a commented example. | Validate whether no link is represented by nil, zero, or another value; do not guess. |
| Camera position/direction/up/FOV | Existing live diagnostic; generated System binding pages. | These are final camera values, not proof of an actor controller's persistent look state. |
| `System.GetViewCameraAngles()` | `CScriptBindSystem__GetViewCameraAngles@IFunctionHandler__.html:60-62`. | Documented getter; not yet sampled by MineCome. |
| `player.actor:GetAngles()` | `C_ScriptBindActor__GetAngles@IFunctionHandler__.html:60-62`, described as actor rotation. | The docs do not establish that this is an exact inverse of `PlayerSetViewAngles`. Do not promise full view-state restoration from it. |

Keep captured entity handles and vector copies inside game Lua. Do not convert
entity handles through Lua floating-point numbers. A restore must verify the same
player entity/table and handle still exist; a replacement world/player must never
receive the captured coordinates.

## Camera follower and camera override distinction

The first probe should change position only and leave the normal player camera
active. The installed spawn code uses the actor's view setter rather than a
freestanding camera replacement. Measure subsequent player and camera samples:
their displacement should agree within a stated tolerance while camera offset
and basis remain sensible. Camera following after our position write is an
inference to verify, not an established MineCome result.

The archive also documents `Action.SetViewCamera()`
(`CScriptBindAction__SetViewCamera@IFunctionHandler__.html:60-62`),
`Action.SetViewCameraByAngles()`
(`CScriptBind_Action__SetViewCameraByAngles@IFunctionHandler_.html:60-62`), and
`Action.ResetToNormalCamera()`
(`CScriptBindAction__ResetToNormalCamera@IFunctionHandler__.html:60-62`). The reset
is described as restoring the last stored valid view. However, the first two
pages omit the actual positional argument schema, and no use sites were found
in the installed Lua scripts. They are insufficient evidence for a free camera
follower implementation. Resetting a camera override also does not undo actor
look state. Do not introduce these calls for the initial movement probe.

libKCD2 `include/entitymodule/C_ActorPhysicsState.h:12-31` describes an engine
per-frame look integrator, view limits, mouse-look deltas and mounted-camera glue;
`include/entitymodule/C_Player.h:123` describes combat/focus-camera control.
These explain why a view setter may be clamped or overwritten during interaction
or combat. They are version-specific analysis, not a reason to access offsets.

## Game-owned execution and restoration deadline

`CScriptBindScript__SetTimerForFunction@IFunctionHandler__@int@char__.html:70-110`
documents milliseconds, a global function name, optional userData, optional
`bUpdateDuringPause`, and a returned timer ID. Lines85-87 explicitly document
pause-time triggering. `CScriptBindScript__KillTimer@IFunctionHandler__@ScriptHandle.html:70-84`
documents cancellation by the returned ID. Existing MineCome block leases use
this timer API and have live normal-cleanup evidence; a movement restore timer
and pause behavior have not been tested.

The script system is updated per frame in libKCD2's copied
`include/CryEngine/CryCommon/IScriptSystem.h:216-218`; its VM and owned timer
manager are described in `include/crysystem/CScriptSystem.h:51-52,72`.
The inspected sources do not expose the HTTP server's exact thread handoff.
Use the already verified official console binding to enqueue an original Lua
intent, then perform any movement and timed restore in the game-owned script
callback. Never dereference game objects from Bridge's socket thread. No
native script-system or camera ABI calls are needed for this route.

A future one-shot design is implementable without changing base scripts:

1. Explicitly arm only in the separately backed-up fresh tools world, with a
   real MC connection and fresh poses. Validate the capabilities and read-only
   guards above, no existing probe, stationary player, and locally checked ground.
2. Copy player position, velocity and camera samples. Choose one bounded
   horizontal displacement, initially at most0.1m, preserving Z. This limit is a
   proposed test bound, not a collision guarantee.
3. Arm a short restore timer with pause updates **before** writing. If scheduling
   fails, perform no movement. Log the probe ID and captured entity provenance.
4. Write once with `SetWorldPos`; record immediate and delayed readback, plus
   camera samples. Do not continuously fight the game's movement/physics loop.
5. Restore once on the local deadline, normal cancellation or relay disconnect,
   only while the original entity/world identity and probe ownership still match.
   Record confirmed readback or explicit restore failure. Do not restore into a
   new world or over an unrelated player action. Do not extend the deadline when
   receiving network traffic.

An engine close, Lua reset, missing player or world unload can prevent a timer
from restoring position. Return-to-origin cannot undo quest triggers, AI reactions,
animation changes, collision corrections, falls or autosaves. The probe must
remain opt-in and confined to the disposable test world; it is not a general
rollback facility. There is no verified guard for all cutscenes, ladders,
interaction holds, combat locks and quest transitions yet.

## Collision-respecting input route: promising, not yet established

`C_ScriptBindActor__SimulateOnAction@IFunctionHandler__@char__@int@float.html:52,70-82`
documents action name, activation mode and value; libKCD2
`include/entitymodule/C_ScriptBindActor.h:35` lists its registration.
Installed `Scripts/FeatureTests/PlayerMovement.xml:30-35` uses the action names
`moveforward` and `moveback` through the feature-test input override.
The copied Crytek header `include/CryEngine/CryAction/IActionMapManager.h:33-39`
defines press=1, release=2, hold=4. This suggests a short input pulse followed by
an unconditional timed release, allowing KCD2's own collision/movement controller
to remain authoritative.

No installed Lua call site for SimulateOnAction was found, and the feature-test
override is a different API. Its effects, activation semantics in this build,
and interaction with simultaneous physical input need an explicit bounded live
probe before continuous external control. Release of our synthetic action is
not exact restoration of the user's prior input. The supported SetWorldPos
one-shot has stronger KCD2-specific call-site evidence for the first position
authority check; neither route currently proves unrestricted movement sync.

## Live bounded follower continuation — 2026-10-12

The separately loaded original `kcd2/probes/movement_probe.lua` now implements
the supported game-thread position path with exact actor/no-link checks,
400ms arrival lease, fixed8s deadline, delayed camera readbacks and guarded
restoration. The one-shot0.1m position/camera probe passed in the actual tools
world. A later real Minecraft server-driven walk/jump/landing run also passed
21 delayed KCD acknowledgements and returned the player to its starting position.
See [the progress record](../PROGRESS.md#live-coupled-movement--2026-10-12).

Native KCD physics remains active and user input is not suppressed. This confirms
the short follower over a sampled local heightfield, with the listed guards;
it does not establish general player state coverage or sustained exclusive authority.
