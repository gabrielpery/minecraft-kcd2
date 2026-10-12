# KCD2 input forwarding research

Read-only source inspection on 2026-10-12. Both games were closed; no callbacks,
action maps, key bindings, engine hooks or runtime modules were changed.

The stock files establish semantic movement/camera actions and a Lua `OnAction`
callback. They do **not** establish that ordinary movement or mouse axes reach
that callback. The current supported Lua route therefore remains a candidate
for an observation test, rather than a completed KCD-keyboard input bridge.

## Sources and actual input names

Pinned references remain `kcd2-mod-docs` commit
`9cb067543245ec5cf4e27b3d21e32485a35db518` and `libKCD2` commit
`10d20f28faba462c4bf98a01abb48225cc51bb91`. Installed archive entries below were
read in memory without modifying the official tools installation.

`C:/Program Files (x86)/Steam/steamapps/common/KCD2Mod/Data/IPL_GameData.pak`
contains:

| Entry and lines | Input definition |
|---|---|
| `Libs/Config/defaultProfile.xml:33-42` | `movement_x`: moveleft, moveright, xi_movex; `movement_y`: moveforward, moveback, xi_movey. Keyboard actions specify press/release; analog actions use the controller sticks. |
| `defaultProfile.xml:49-54` | movement includes both axes, sprint, jump and toggle_run. |
| `defaultProfile.xml:57-66` | rotateyaw uses maxis_x; rotatepitch uses maxis_y. Controller equivalents are xi_rotateyaw and xi_rotatepitch. |
| `defaultProfile.xml:425-434` | The `player` action map includes movement, camera and interaction. This is a richer map than the legacy Lua script's references to a map called `default`. |
| `Libs/Config/keybindSuperactions.xml:14-70` | Default left/right/up/down superactions connect movement to A/D/W/S and arrow keys. Their keyboard bindings are writable. |

SHA-256: defaultProfile.xml
`69ad9fd618cd31961fef8eb061f3f2723997df5e0fb257ec74d0d5f555592565`;
keybindSuperactions.xml
`6d59be44430169cf2d464a659b34a90a669c2d4272dfcf58f353fff5e8479a45`.
`Libs/Config/Profiles/default/actionmaps.xml` is only an empty ActionMaps root;
it is not evidence for the user's current effective bindings.

Prefer action names over hard-coded physical keys. The stock defaults do not
describe remapped user controls, active menu/cutscene maps or controller input.
No documented Lua held-key getter or held-movement CVar was found. The archived
`CScriptBindGame__KeybindsRebindInput@IFunctionHandler__@char_@char_@int@char_.html:52`
is a binding **writer**, not an input-state reader.

## What Lua can currently observe

In installed `Data/Scripts.pak`, `Scripts/Entities/actor/player.lua:108` defines
`Player:OnAction(action, activation, value)`. Its comment says that at that point
it receives ui_back and ui_start_pause. Lines110-113 forward to the game rules
and preserve its early-return behavior. Lines116-118 also handle a custom
horse-call action with activation `press`. Thus some semantic actions reach Lua,
but the comment is not proof that movement or analog values do.

The entry hash is
`93e909bbd2c96f49bd9b1c3222e74a24e61da5bbc9605b24e01a8d45e3104d70`.
No installed Lua call site demonstrating moveforward/rotateyaw observation was
found. Absence of a use site is not proof that delivery is impossible.

A later explicit observation probe can temporarily wrap this exact Lua callback,
log only the named movement/camera actions, and delegate with the original self,
arguments and return values. It must preserve the original game behavior and
restore only the exact wrapper it owns, with a short game-owned lease. First
prove press/release, mouse axes, focus loss and menu behavior. This source review
did not install such an observer. A wrapper cannot observe events that the
engine consumes before calling Lua.

## Listener APIs and their limitations

Generated binding paths below are under
`external/kcd2-mod-docs/script_bind_2025_01_14`.

- `CScriptBind_ActionMapManager__SetActionListener@IFunctionHandler_@char_@ScriptHandle.html:52`
  defines map name plus entity ID. Stock player.lua uses it at lines196,425,439
  and elsewhere for cheat-map switching. It assigns the map's entity listener;
  it is not a documented additive observer. The copied Crytek interface confirms
  a single entity listener at `libKCD2/include/CryEngine/CryAction/IActionMapManager.h:278-279`.
  No corresponding Lua GetActionListener/AddExtraActionListener binding was found.
- `...SetDefaultActionEntity@IFunctionHandler_@EntityId@bool.html:70-93` can
  replace the default and optionally update all map assignments.
  `...GetDefaultActionEntity@IFunctionHandler_.html:60-62` reads that default,
  not every map's original listener. It is insufficient for reversible replacement
  of the active gameplay listeners.
- `...EnableActionMapManager@IFunctionHandler_@bool@bool.html:70-93` disables
  the entire manager and optionally resets action state. It does not capture
  input for a second simulation. Do not apply it as a forwarding shortcut.
- `CScriptBind_UIAction__RegisterActionListener@IFunctionHandler_@SmartScriptTable@char_@char_@char_.html:70-107`
  concerns UI Action lifecycle events such as OnStart/OnEnd. It does not subscribe
  to gameplay key actions. [Crytek's UIAction reference](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756813/pages/23306614)
  confirms that distinction.
- `CScriptBindSystem__ClearKeyState@IFunctionHandler__.html:60-62` clears state;
  `C_ScriptBind_GameRules__FreezeInput@IFunctionHandler__@bool.html:70-84` freezes
  input. Neither is a read API, and no matching prior-freeze-state getter was
  established. They cannot promise exact restoration of another system's state.

Loading a custom XML map is documented, but key priority, exclusivity, dispatch
and reversible removal require a separate test. It must not silently replace
the real player map or duplicate keys while claiming passive observation.

## Native future route, presently blocked

`libKCD2/include/Offsets/vtables/IActionMapManager.h:14-25,40-41` describes the
actual retail1.5.6 AddExtraActionListener registration: a null map name observes
dispatched actions from enabled maps. `Offsets/vtables/IActionListener.h:23-25`
declares OnAction(actionId, activationMode, value). This is a more direct semantic
capture route than polling keys.

It is not deployable with the current prerequisites: the verified retail address
map remains missing, and the active official tools executable is1.5.5 rather
than the interface's target1.5.6. The partial interface also does not declare a
verified removal method, so callback lifetime/unregistration needs research.
Copied generic Crytek headers cannot substitute for the game's shuffled ABI.

`Offsets/vtables/IInput.h:51` also names a native InputState method, taking an
opaque key-name identifier and state. It is not a Lua keyboard API. Do not call
it through assumed structs/offsets or claim System.GetKeyState exists.

## Authority and camera path for the next lab

Camera observation is already independent of input capture: the game-side
diagnostic reads final camera position/forward/up/FOV; the native parser builds
the verified right/up/back quaternion. Apply camera values only on the Minecraft
game thread. Camera following does not prove movement or collision authority.

There are two distinct movement experiments:

1. **KCD pose mirror:** KCD2 retains movement/collision authority and Minecraft
   receives position snapshots. Setting MC player position every sample bypasses
   Minecraft's ordinary movement collision resolution. This can measure terrain
   alignment, but it is not Minecraft-authoritative movement.
2. **Minecraft collision authority:** a proved stream of KCD semantic movement
   intent drives Minecraft's normal input/movement on its game thread. The
   resulting server-confirmed MC position can later drive a separately gated
   KCD follower. This needs the input observation prerequisite above, a lease,
   single owner, focus/menu neutralization and session/reset tags. KCD position
   writes remain a separate opt-in probe, described in KCD-MOVEMENT.md.

For the sampled-heightfield lab, first validate ordinary Minecraft-controlled
movement against the sampled terrain without continuous KCD/MC position writes.
Use the existing KCD camera read separately if desired. Forwarding zero after
release, timeout, focus loss, disconnect or session reset is essential; queued
input must not survive reconnect. A socket thread must copy bounded values and
leave all player/input/world work to the game threads.

## Leased observer outcome — 2026-10-12

The original `kcd2/probes/input_probe.lua` now provides the temporary callback
observer described above. It delegates exact original arguments and return values,
restores only its owned wrapper and uses a game-owned fixed lease. Twenty standalone
Lua5.2 cases pass with simulated bindings. The live60s session expired and restored
the callback correctly, but captured zero named actions and55 stationary player/view
samples. The user's completion reply arrived afterward; a later sample showed motion.
The result is inconclusive for physical movement/mouse delivery, rather than proof
that Lua cannot observe it. No action map was reassigned or key event injected.

Player/camera following has separate live proof in the coupled Minecraft lab.
Its scripted Minecraft inputs do not establish KCD-focused input forwarding.
See [the progress record](../PROGRESS.md#live-coupled-movement--2026-10-12).

## Timed human input proof — 2026-10-12

The later restarted60s observer overlapped the user's actual W/Space/mouse check.
The user replied "done";77 samples measured13.5983m maximum player displacement
and a1.7893 change in the forward unit vector. The callback logged three
`jump` actions with string activation `press` and numeric value1. No jump release,
watched moveforward/other walking action, or watched rotateyaw/rotatepitch action
was recorded. The fixed lease and explicit end both confirmed callback restoration.

This proves some real gameplay input reaches `Player:OnAction` in the active
official1.5.5 build. It does not prove sufficient movement/mouse intent or complete
press/release delivery for vanilla Minecraft controls. Do not infer absence of
physical input from an empty callback log or substitute observed KCD position for
Minecraft-authoritative movement intent. The next route needs independently
supported walking/mouse capture, focus/menu neutralization and explicit bindings.
Source and live evidence are linked in
[progress](../PROGRESS.md#source-repository-and-input-recheck--2026-10-12).
