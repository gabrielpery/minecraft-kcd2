-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original opt-in capability / restored position probe; no automatic work.
-- Evidence: kcd2-mod-docs9cb067543245ec5cf4e27b3d21e32485a35db518,
-- script_bind_2025_01_14 Entity.GetWorldPos/GetVelocity and actor/player/human
-- getters. Installed tools Data/Scripts.pak SpawnPoint.lua:104 uses SetWorldPos;
-- SinglePlayer.lua:266 uses the same player setter. Timer optional userData and
-- bUpdateDuringPause: CScriptBindScript__SetTimerForFunction...html:80-110;
-- KillTimer...html:70-84. Ray call: PressurizedObject.lua:308-310, private hit table.
-- Optional frame telemetry: CScriptBindSystem__GetFrameID@IFunctionHandler__.html:60-62.
-- See docs/research/KCD-MOVEMENT.md. No camera/freeze/input/native-offset writes.

MineCome = MineCome or {}
MineCome._movement_probe = MineCome._movement_probe or { schema = 1 }
local state = MineCome._movement_probe
local LIMIT = 10000000
local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end
local function vector(v)
    return type(v) == "table" and finite(v.x) and finite(v.y) and finite(v.z)
        and math.abs(v.x) <= LIMIT and math.abs(v.y) <= LIMIT and math.abs(v.z) <= LIMIT
end
local function copy(v) return vector(v) and { x = v.x, y = v.y, z = v.z } or nil end
local function token(v) return type(v) == "string" and #v >= 1 and #v <= 64 and v:match("^[0-9a-fA-F]+$") ~= nil end
local function quote(v) return '"' .. tostring(v):gsub('[%z\1-\31\\"]', function(c) return string.format("\\u%04x", string.byte(c)) end) .. '"' end
local function number(n) return finite(n) and string.format("%.17g", n) or "null" end
local function vecjson(v) return vector(v) and ('{"x":' .. number(v.x) .. ',"y":' .. number(v.y) .. ',"z":' .. number(v.z) .. '}') or "null" end
local function emit(prefix, text)
    if not System or type(System.LogAlways) ~= "function" then return false end
    local ok, result = pcall(System.LogAlways, prefix .. " " .. text)
    return ok and result ~= false
end
local function field(owner, key)
    if type(owner) ~= "table" and type(owner) ~= "userdata" then return nil end
    local ok, value = pcall(function() return owner[key] end)
    if ok then return value end
    return nil
end
local function read(owner, method, global)
    local fn = field(owner, method)
    local result = { method_type = type(fn), ok = false, value_type = "nil" }
    if type(fn) ~= "function" then return result end
    local ok, value
    if global then ok, value = pcall(fn) else ok, value = pcall(fn, owner) end
    result.ok, result.value_type = ok, ok and type(value) or "error"
    if ok then result.value = vector(value) and copy(value) or value end
    return result
end
local function descriptor(r)
    local value = "null"
    if r.value_type == "boolean" then value = tostring(r.value)
    elseif r.value_type == "number" then value = number(r.value)
    elseif vector(r.value) then value = vecjson(r.value) end
    return '{"method_type":' .. quote(r.method_type) .. ',"ok":' .. tostring(r.ok)
        .. ',"value_type":' .. quote(r.value_type) .. ',"finite":' .. tostring(finite(r.value) or vector(r.value)) .. ',"value":' .. value .. '}'
end
local function linked_kind(r)
    if not r.ok then return "unavailable" end
    if r.value_type == "nil" then return "nil" end
    if r.value_type == "number" and finite(r.value) and r.value == 0 then return "number_zero" end
    return r.value_type -- nonzero numbers / userdata are reported, never guessed absent.
end
local function identity(entity, id) return entity ~= nil and player == entity and field(entity, "id") == id and id ~= nil end
local function snapshot()
    local entity = type(player) == "table" and player or nil
    local s = { entity = entity, id = field(entity, "id") }
    s.position, s.velocity = read(entity, "GetWorldPos"), read(entity, "GetVelocity")
    s.dead, s.unconscious = read(field(entity, "actor"), "IsDead"), read(field(entity, "actor"), "IsUnconscious")
    s.linked = read(field(entity, "actor"), "GetLinkedEntity")
    s.sitting, s.laying = read(field(entity, "player"), "IsSitting"), read(field(entity, "player"), "IsLaying")
    s.mounted = read(field(entity, "human"), "IsMounted")
    s.camera = { position = read(System, "GetViewCameraPos", true), forward = read(System, "GetViewCameraDir", true),
        up = read(System, "GetViewCameraUpDir", true), fov = read(System, "GetViewCameraFov", true) }
    s.stable = identity(entity, s.id)
    return s
end
function MineCome.ProbeMovementCapabilities(run)
    if not token(run) then return false, "invalid_run" end
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end
    local s = snapshot()
    local text = '{"schema":1,"run":' .. quote(run) .. ',"result":' .. quote(s.entity and "sampled" or "no_world")
        .. ',"identity_stable":' .. tostring(s.stable) .. ',"entity_id_type":' .. quote(type(s.id))
        .. ',"position":' .. descriptor(s.position) .. ',"velocity":' .. descriptor(s.velocity)
        .. ',"dead":' .. descriptor(s.dead) .. ',"unconscious":' .. descriptor(s.unconscious)
        .. ',"linked_entity":' .. descriptor(s.linked) .. ',"linked_kind":' .. quote(linked_kind(s.linked))
        .. ',"sitting":' .. descriptor(s.sitting) .. ',"laying":' .. descriptor(s.laying) .. ',"mounted":' .. descriptor(s.mounted)
        .. ',"camera":{"position":' .. descriptor(s.camera.position) .. ',"forward":' .. descriptor(s.camera.forward)
        .. ',"up":' .. descriptor(s.camera.up) .. ',"fov":' .. descriptor(s.camera.fov) .. '}'
        .. ',"timer_set_type":' .. quote(type(Script and Script.SetTimerForFunction))
        .. ',"timer_kill_type":' .. quote(type(Script and Script.KillTimer)) .. '}'
    if not emit("[MineComeMovementCapabilities]", text) then return false, "log_failed" end
    state.capability = { run = run, entity = s.entity, id = s.id, linked_kind = linked_kind(s.linked), stable = s.stable }
    return true, s.entity and "sampled" or "no_world"
end
-- Explicit trusted acknowledgement of a matching read-only capability receipt.
-- It cannot establish a contract for userdata/nonzero/unknown linked values.
function MineCome.VerifyMovementNoLinkContract(run, kind)
    if not token(run) then return false, "invalid_run" end
    local cap = state.capability
    if state.active or state.follower then return false, "busy" end
    if not cap or cap.run ~= run or not cap.stable or not identity(cap.entity, cap.id)
        or (kind ~= "nil" and kind ~= "number_zero") or cap.linked_kind ~= kind then return false, "unverified_no_link" end
    local current = read(field(cap.entity, "actor"), "GetLinkedEntity")
    if linked_kind(current) ~= kind then return false, "linked_changed" end
    if not emit("[MineComeMovementContract]", '{"schema":1,"run":' .. quote(run) .. ',"linked_kind":' .. quote(kind) .. ',"result":"verified"}') then return false, "log_failed" end
    state.verified_no_link_kind = kind
    state.verified_entity, state.verified_id = cap.entity, cap.id
    return true, "verified"
end

local function now()
    local r = read(System, "GetCurrTime", true)
    return r.ok and finite(r.value) and r.value >= 0 and r.value < 1000000000000 and r.value or nil
end
local function native_frame_id()
    local r = read(System, "GetFrameID", true)
    -- Optional diagnostic only; unavailable IDs do not change follower guards.
    return r.ok and finite(r.value) and r.value >= 0 and r.value <= 9007199254740991
        and r.value == math.floor(r.value) and r.value or nil
end
local function distance(a, b)
    if not vector(a) or not vector(b) then return math.huge end
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2)
end
local function speed(v) return vector(v) and math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z) or math.huge end
local function normal_camera(c)
    if not c or not c.position.ok or not vector(c.position.value) or not c.forward.ok or not vector(c.forward.value)
        or not c.up.ok or not vector(c.up.value) or not c.fov.ok or not finite(c.fov.value)
        or c.fov.value <= 0 or c.fov.value >= math.pi then return false end
    local f, u = c.forward.value, c.up.value
    local fl, ul = f.x*f.x+f.y*f.y+f.z*f.z, u.x*u.x+u.y*u.y+u.z*u.z
    return math.abs(fl-1) <= 0.05 and math.abs(ul-1) <= 0.05 and math.abs(f.x*u.x+f.y*u.y+f.z*u.z) <= 0.05
end
local function guards(s, velocity_limit, require_camera, strict_speed)
    if not s.stable or (type(s.id) ~= "userdata" and not (finite(s.id) and s.id > 0 and s.id == math.floor(s.id))) then return "identity_unavailable" end
    if not s.position.ok or not vector(s.position.value) then return "position_unavailable" end
    local v = speed(s.velocity.value)
    if not s.velocity.ok or v > velocity_limit or (strict_speed and v == velocity_limit) then return "velocity_unavailable_or_moving" end
    for _, r in ipairs({s.dead,s.unconscious,s.sitting,s.laying,s.mounted}) do
        if not r.ok or r.value_type ~= "boolean" then return "state_boolean_unknown" end
        if r.value ~= false then return "unsafe_player_state" end
    end
    if state.verified_entity ~= s.entity or state.verified_id ~= s.id or not state.verified_no_link_kind then return "no_link_contract_unverified" end
    if linked_kind(s.linked) ~= state.verified_no_link_kind then return "linked_entity_unknown_or_present" end
    if require_camera ~= false and (not normal_camera(s.camera) or distance(s.camera.position.value,s.position.value) > 3) then return "normal_camera_unavailable" end
    return nil
end
local function camera_json(c)
    return '{"position":' .. vecjson(c and c.position.value) .. ',"forward":' .. vecjson(c and c.forward.value)
        .. ',"up":' .. vecjson(c and c.up.value) .. ',"fov":' .. number(c and c.fov.value) .. '}'
end
local function physical_camera(s)
    return s and normal_camera(s.camera) and distance(s.camera.position.value,s.position.value) <= 3
end
-- Read-only view samples use the same inspected System getters as snapshot().
-- The host timestamps its request, correlates this advancing sequence in fresh
-- log bytes and binds the result to its exact process; engine time is not UTC.
-- This sampler neither starts a follower nor extends its input/deadline leases.
function MineCome.SamplePhysicalHudView(run)
    if not token(run) then return false,"invalid_run" end
    if state.active then return false,"busy" end
    local follower = state.follower
    if follower and (follower.run ~= run or follower.physical_movement ~= true or follower.terminal) then
        return false,"wrong_or_nonphysical_follower"
    end
    local s,clock = snapshot(),now()
    local unsafe = guards(s,follower and 6 or 0.05,true,not follower)
    if not clock then unsafe = "clock_unavailable" end
    if follower and (s.entity ~= follower.entity or s.id ~= follower.id) then unsafe = "player_changed" end
    if unsafe then return false,unsafe end
    local view = state.physical_view
    if not view or view.run ~= run then
        view = {run=run,entity=s.entity,id=s.id,created=clock,sequence=0}
    elseif view.entity ~= s.entity or view.id ~= s.id then return false,"player_changed" end
    if clock < view.created or (view.sampled and clock <= view.sampled) then return false,"clock_not_advancing" end
    if clock-view.created >= 120 or view.sequence >= 1024 then return false,"view_budget_expired" end
    local sequence = view.sequence+1
    local text = '{"schema":1,"run":' .. quote(run) .. ',"seq":' .. number(sequence)
        .. ',"result":"sampled","physical_movement":true,"sampled_engine_seconds":' .. number(clock)
        .. ',"player":' .. vecjson(s.position.value) .. ',"camera":' .. camera_json(s.camera)
        .. ',"camera_basis_valid":true}'
    if not emit("[MineComeHudPhysicalView]",text) then return false,"log_failed" end
    view.sequence,view.sampled = sequence,clock;state.physical_view = view
    return true,"sampled"
end
local function receipt(p, stage, result, s, terminal)
    local clock = now()
    return emit("[MineComeMovementProbe]", '{"schema":1,"run":' .. quote(p.run) .. ',"stage":' .. quote(stage)
        .. ',"result":' .. quote(result) .. ',"terminal":' .. tostring(terminal == true)
        .. ',"applied":' .. tostring(p.applied == true) .. ',"write_attempted":' .. tostring(p.write_attempted == true)
        .. ',"readback":' .. tostring(p.readback == true) .. ',"restore_attempted":' .. tostring(p.restore_attempted == true)
        .. ',"restore_result":' .. quote(p.restore_result or "not_attempted")
        .. ',"elapsed_ms":' .. number(clock and p.created and (clock-p.created)*1000)
        .. ',"origin":' .. vecjson(p.origin) .. ',"target":' .. vecjson(p.target)
        .. ',"player":' .. vecjson(s and s.position.value) .. ',"velocity":' .. vecjson(s and s.velocity.value)
        .. ',"camera":' .. camera_json(s and s.camera) .. ',"camera_follow":' .. tostring(p.camera_follow == true)
        .. ',"timers_cancelled":' .. tostring(p.timers_cancelled ~= false) .. '}')
end
local function handle(value)
    return type(value) == "userdata" or (finite(value) and value > 0 and value == math.floor(value))
end
local function kill_owned(p)
    local clean = true
    for slot, id in pairs(p.timers) do
        p.timers[slot] = nil
        if not handle(id) or not Script or type(Script.KillTimer) ~= "function" then clean = false
        else local ok, result = pcall(Script.KillTimer,id); if not ok or result == false then clean = false end end
    end
    p.timers_cancelled = p.timers_cancelled ~= false and clean
end
local function finish(p, stage, result, s)
    if state.active ~= p or p.terminal then return false end
    p.terminal = true
    kill_owned(p)
    state.active = nil
    if not p.timers_cancelled then result = result .. "_timer_cancel_failed" end
    return receipt(p,stage,result,s,true)
end
local function arm(p,slot,name,delay,maximum)
    if not Script or type(Script.SetTimerForFunction) ~= "function" or type(Script.KillTimer) ~= "function" then return false end
    if p.timers[slot] ~= nil or delay < 1 or delay > (maximum or 750) then return false end
    local data = { probe = p, slot = slot }; p.data[slot] = data
    local ok, id = pcall(Script.SetTimerForFunction,delay,name,data,true)
    if not ok or not handle(id) then p.data[slot] = nil; return false end
    p.timers[slot] = id
    return true
end
local function consume(data)
    if type(data) ~= "table" or type(data.probe) ~= "table" then return nil end
    local p = data.probe
    if state.active ~= p or p.terminal or p.data[data.slot] ~= data or not handle(p.timers[data.slot]) then return nil end
    -- The returned ScriptHandle is retained unchanged for KillTimer. The exact
    -- userData table identifies this run; callback handles may be new wrappers.
    p.timers[data.slot] = nil
    return p
end
local function ground(position, id)
    if not Physics or type(Physics.RayWorldIntersection) ~= "function" or not finite(ent_terrain)
        or ent_terrain <= 0 or ent_terrain > 2147483647 or ent_terrain ~= math.floor(ent_terrain) then return nil end
    local hits = {}
    local ok, count = pcall(Physics.RayWorldIntersection,{x=position.x,y=position.y,z=position.z+1},
        {x=0,y=0,z=-2},1,ent_terrain,id,nil,hits)
    local h = hits[1]
    if not ok or count ~= 1 or type(h) ~= "table" or not vector(h.pos) or not vector(h.normal)
        or not finite(h.dist) or h.dist < 0 or h.dist > 2 or h.normal.z < 0.9 then return nil end
    local n = h.normal.x*h.normal.x+h.normal.y*h.normal.y+h.normal.z*h.normal.z
    if math.abs(n-1) > 0.05 or math.abs(h.pos.x-position.x) > 0.02 or math.abs(h.pos.y-position.y) > 0.02
        or math.abs(position.z+1-h.pos.z-h.dist) > 0.05 or math.abs(h.pos.z-position.z) > 0.15 then return nil end
    return h.pos.z
end
local restore
restore = function(p, reason)
    local s = snapshot()
    if not p.write_attempted then return finish(p,"cancelled",reason,s) end
    local unsafe = guards(s,0.2,false)
    if s.entity ~= p.entity or s.id ~= p.id then unsafe = "player_changed" end
    if distance(s.position.value,p.origin) > 0.3 then unsafe = "unexpected_player_navigation" end
    -- A stopped user can still have navigated within0.3m. Require the owned
    -- destination (or an already-restored origin), rather than undoing that move.
    if distance(s.position.value,p.target) > 0.03 and distance(s.position.value,p.origin) > 0.03 then unsafe = "unexpected_player_navigation" end
    if unsafe then p.restore_result = "skipped_" .. unsafe; return finish(p,"restore_failed",p.restore_result,s) end
    p.restore_attempted = true
    local clock = now();p.late = not clock or clock-p.created > 0.8
    local ok, value = pcall(p.entity.SetWorldPos,p.entity,copy(p.origin))
    s = snapshot()
    p.readback = ok and value ~= false and s.stable and s.entity == p.entity and s.id == p.id and distance(s.position.value,p.origin) <= 0.03
    p.restore_result = p.readback and "restored" or "readback_failed"
    if not p.readback then return finish(p,"restore_failed","restore_readback_failed",s) end
    p.restoring = true
    kill_owned(p)
    if not arm(p,"post_restore","MineCome_MovementProbeRestored",100) then return finish(p,"restore_failed","post_restore_timer_failed",s) end
    return receipt(p,"restoring",reason,s,false)
end
function MineCome.BeginMovementProbe(run)
    if not token(run) then return false,"invalid_run" end
    if state.active or state.follower then return false,"busy" end
    local s, clock = snapshot(), now()
    local unsafe = guards(s,0.05,true,true)
    if not clock then unsafe = "clock_unavailable" end
    if type(field(s.entity,"SetWorldPos")) ~= "function" then unsafe = "position_writer_unavailable" end
    if not Script or type(Script.SetTimerForFunction) ~= "function" or type(Script.KillTimer) ~= "function" then unsafe = "timer_unavailable" end
    local p = {run=run,entity=s.entity,id=s.id,created=clock,origin=copy(s.position.value),camera_origin=copy(s.camera.position.value),timers={},data={}}
    if unsafe then receipt(p,"rejected",unsafe,s,true);return false,unsafe end
    p.target = {x=p.origin.x+0.1,y=p.origin.y,z=p.origin.z}
    if not vector(p.target) then receipt(p,"rejected","target_out_of_bounds",s,true);return false,"target_out_of_bounds" end
    state.active = p
    if not arm(p,"apply","MineCome_MovementProbeApply",1) then finish(p,"rejected","enqueue_timer_failed",s);return false,"enqueue_timer_failed" end
    if not receipt(p,"queued","queued",s,false) then finish(p,"rejected","log_failed",s);return false,"log_failed" end
    return true,"queued"
end
function MineCome_MovementProbeApply(data)
    local p = consume(data);if not p then return false end
    if p.cancel_requested then return finish(p,"cancelled","cancelled_before_write",snapshot()) end
    local s, clock = snapshot(), now()
    local unsafe = guards(s,0.05,true,true)
    if s.entity ~= p.entity or s.id ~= p.id then unsafe = "player_changed" end
    if distance(s.position.value,p.origin) > 0.02 then unsafe = "player_moved_before_write" end
    if not clock or clock-p.created > 0.1 or clock < p.created then unsafe = "enqueue_expired" end
    if unsafe then return finish(p,"rejected",unsafe,s) end
    local old_height, new_height = ground(p.origin,p.id), ground(p.target,p.id)
    s = snapshot();clock = now()
    if not old_height or not new_height or math.abs(old_height-new_height) > 0.05 then return finish(p,"rejected","ground_not_verified",s) end
    if guards(s,0.05,true,true) or s.entity ~= p.entity or s.id ~= p.id or distance(s.position.value,p.origin) > 0.02
        or not clock or clock-p.created > 0.1 then return finish(p,"rejected","player_changed_during_ground_check",s) end
    if not arm(p,"restore","MineCome_MovementProbeRestore",500)
        or not arm(p,"sample100","MineCome_MovementProbeSample",100)
        or not arm(p,"sample250","MineCome_MovementProbeSample",250) then return finish(p,"rejected","restore_or_sample_timer_failed",s) end
    -- All cleanup timers are armed before this sole initial position write.
    p.write_attempted = true
    local ok, value = pcall(p.entity.SetWorldPos,p.entity,copy(p.target))
    s = snapshot()
    p.readback = ok and value ~= false and s.stable and s.entity == p.entity and s.id == p.id and distance(s.position.value,p.target) <= 0.03
    p.applied = p.readback
    if not p.readback then receipt(p,"apply_failed","position_write_or_readback_failed",s,false);return restore(p,"apply_failed_cleanup") end
    if not receipt(p,"applied","applied_readback",s,false) then return restore(p,"log_failed_cleanup") end
    return true
end
function MineCome_MovementProbeSample(data)
    local p = consume(data);if not p then return false end
    if p.cancel_requested then return restore(p,"explicit_cancel") end
    local s = snapshot()
    if guards(s,0.2) or s.entity ~= p.entity or s.id ~= p.id or distance(s.position.value,p.origin) > 0.3 then return restore(p,"sample_guard_failed") end
    local expected = {x=p.camera_origin.x+0.1,y=p.camera_origin.y,z=p.camera_origin.z}
    p.camera_follow = distance(s.camera.position.value,expected) <= 0.05
    p.readback = distance(s.position.value,p.target) <= 0.03
    return receipt(p,data.slot,p.readback and "sampled" or "position_readback_changed",s,false)
end
function MineCome_MovementProbeRestore(data)
    local p = consume(data);if not p then return false end
    return restore(p,p.cancel_requested and "explicit_cancel" or "deadline_restore")
end
function MineCome_MovementProbeCancel(data)
    local p = consume(data);if not p then return false end
    return restore(p,"explicit_cancel")
end
function MineCome_MovementProbeRestored(data)
    local p = consume(data);if not p then return false end
    local s = snapshot()
    p.readback = s.stable and s.entity == p.entity and s.id == p.id and distance(s.position.value,p.origin) <= 0.03
    local camera_restored = normal_camera(s.camera) and distance(s.camera.position.value,p.camera_origin) <= 0.05
    local result = (p.readback and camera_restored) and (p.late and "restored_late" or "restored") or "restore_delayed_readback_failed"
    return finish(p,result == "restored" and "restored" or "restore_failed",result,s)
end
function MineCome.EndMovementProbe(run)
    if not token(run) then return false,"invalid_run" end
    local p = state.active
    if not p or p.run ~= run then return false,"wrong_or_inactive_run" end
    if p.cancel_requested or p.restoring then return true,"cancel_queued" end
    p.cancel_requested = true
    if not p.write_attempted then return true,"cancel_queued" end
    if not arm(p,"cancel","MineCome_MovementProbeCancel",1) then return false,"cancel_timer_failed_deadline_retained" end
    return true,"cancel_queued"
end

-- Bounded debug follower. Minecraft snapshots supply positions; KCD's ordinary
-- camera follows the actor. This does not replace KCD's physics, suppress real
-- input, implement general collision adoption, or roll back quest/AI effects.
local FOLLOWER_MS, TICK_MS, LEASE_SECONDS = 8000, 40, 0.4
local PHYSICAL_TICK_MS, INTERPOLATION_SECONDS, POSITION_EPSILON = 1, 0.1, 0.0001
local BUFFER_DELAY_SECONDS, BUFFER_CAPACITY, SOURCE_LIMIT_MS = 0.2, 8, 6000
local FOLLOWER_LOG_MAX_BYTES = 3798 -- Includes the tag, separating space and CRLF.
-- Select a closed profile once at Begin. Source callbacks cannot raise budgets,
-- change profiles, or renew the deadline. Preserve the registry across a module
-- reload so existing owned timers retain their original profile.
local SCRIPTED_LIMITS = { hard_ms=FOLLOWER_MS,source_ms=SOURCE_LIMIT_MS,writes=199,receipts=128 }
local PHYSICAL_LIMITS = { hard_ms=FOLLOWER_MS,source_ms=SOURCE_LIMIT_MS,writes=511,receipts=128 }
local EXTENDED_LIMITS = { hard_ms=18000,source_ms=16000,writes=2047,receipts=256,session="extended" }
state.follower_profiles = state.follower_profiles or setmetatable({}, { __mode="k" })
local follower_profiles = state.follower_profiles
-- A still-owned follower from the pre-profile module has only baseline limits.
-- Attach that baseline without changing any existing deadline or timer handle.
if state.follower and not follower_profiles[state.follower] then
    follower_profiles[state.follower] = state.follower.physical_movement and PHYSICAL_LIMITS or SCRIPTED_LIMITS
end
local function follower_limits(p) return follower_profiles[p] end
local function follower_tick_ms(p) return p.physical_movement and PHYSICAL_TICK_MS or TICK_MS end
local function horizontal(v) return vector(v) and math.sqrt(v.x*v.x+v.y*v.y) or math.huge end
local function source_sample_json(source)
    if not source then return "" end
    return ',"bracket_from_seq":' .. number(source.from.seq) .. ',"bracket_from_ms":' .. number(source.from.source_ms)
        .. ',"bracket_from_target":' .. vecjson(source.from.target)
        .. ',"bracket_to_seq":' .. number(source.to.seq) .. ',"bracket_to_ms":' .. number(source.to.source_ms)
        .. ',"bracket_to_target":' .. vecjson(source.to.target)
        .. ',"bracket_to_received_engine_seconds":' .. number(source.to.received)
        .. ',"playback_source_ms":' .. number(source.playback_ms) .. ',"source_hold":' .. tostring(source.hold)
end
local function segment_samples(segment,count)
    if not segment then return "null" end
    local values={}
    for index=1,count do
        -- Keep the final delayed observation when the serialized subset must
        -- shrink. The in-memory observations and all aggregates stay intact.
        local sample=segment.samples[index==count and #segment.samples or index]
        values[#values+1]='{"fraction":' .. number(sample.fraction) .. ',"requested":' .. vecjson(sample.requested)
            .. ',"actual":' .. vecjson(sample.actual) .. ',"written_engine_seconds":' .. number(sample.written_at)
            .. ',"observed_engine_seconds":' .. number(sample.observed_at) .. ',"write_performed":' .. tostring(sample.written)
            .. ',"camera":' .. camera_json(sample.camera) .. ',"camera_basis_valid":' .. tostring(sample.camera_basis_valid)
            .. ',"written_frame_id":' .. number(sample.written_frame_id) .. ',"observed_frame_id":' .. number(sample.observed_frame_id)
            .. source_sample_json(sample.source)
            .. ',"readback_error":' .. number(sample.error) .. '}'
    end
    return '[' .. table.concat(values,',') .. ']'
end
local function follower_receipt(p,event,result,s,seq,target,readback,follow_error,received,segment,source)
    local limits = follower_limits(p)
    if p.records >= limits.receipts then return false end
    local clock = now()
    local lease = p.latest and clock and math.max(0,(LEASE_SECONDS-(clock-p.latest.received))*1000) or 0
    local physical,source_fields = "",""
    if p.physical_movement then
        target = target or (p.restoring and p.origin or p.last_owned)
        physical = ',"physical_movement":true,"camera_mode":"native_look","camera_basis_valid":'
            .. tostring(physical_camera(s) == true) .. ',"sampled_engine_seconds":' .. number(clock)
            .. ',"player_readback_error":' .. number(distance(s and s.position.value,target))
            .. ',"position_mode":' .. quote(p.buffered_movement and "source_time_buffered" or "timed_interpolation")
            .. ',"interpolation_ms":' .. (p.buffered_movement and "null" or "100") .. ',"target_receipt_age_ms":'
            .. number(received and clock and (clock-received)*1000)
            .. ',"segment_start_engine_seconds":' .. number(segment and segment.started)
            .. ',"segment_update_count":' .. number(segment and segment.updates)
            .. ',"segment_observation_count":' .. number(segment and segment.observations)
            .. ',"segment_max_observation_gap_ms":' .. number(segment and segment.max_gap_ms)
            .. ',"segment_max_readback_error":' .. number(segment and segment.max_error)
            .. ',"endpoint_write_performed":' .. (not p.buffered_movement and segment and tostring(segment.endpoint_written) or "null")
        if p.buffered_movement then
            source_fields = ',"playback_delay_ms":200,"playback_epoch_engine_seconds":' .. number(p.buffer_epoch)
                .. ',"source_seq":' .. number(source and source.crossed.seq) .. ',"source_ms":' .. number(source and source.crossed.source_ms)
                .. ',"source_target":' .. vecjson(source and source.crossed.target)
                .. ',"source_points_crossed":' .. number(source and source.crossed_count)
                .. ',"playback_source_ms":' .. number(source and source.playback_ms)
                .. ',"acknowledged_write_performed":' .. (segment and tostring(segment.endpoint_written) or "null")
        end
    end
    local common = '{"schema":1,"run":' .. quote(p.run) .. ',"event":' .. quote(event) .. ',"result":' .. quote(result)
        .. ',"terminal":' .. tostring(p.terminal == true) .. ',"seq":' .. number(seq or p.last_applied_seq or 0)
        .. ',"target":' .. vecjson(target or p.last_owned) .. ',"player":' .. vecjson(s and s.position.value)
        .. ',"camera":' .. camera_json(s and s.camera) .. ',"readback":' .. tostring(readback == true)
        .. ',"follow_error":' .. number(follow_error) .. ',"lease_ms":' .. number(lease)
        .. ',"hard_deadline_ms":' .. number(limits.hard_ms) .. ',"elapsed_ms":' .. number(clock and (clock-p.created)*1000)
        .. ',"writes":' .. number(p.writes) .. ',"end_result":' .. quote(p.end_result or "none")
        .. ',"timers_cancelled":' .. tostring(p.timers_cancelled ~= false)
        .. (limits.session and ',"movement_session":' .. quote(limits.session) or "")
    local function serialize(count)
        local observations=""
        if p.physical_movement then
            observations=',"segment_observed_samples_truncated":' .. (segment and tostring(segment.observations>count) or "null")
                .. ',"segment_observed_samples":' .. segment_samples(segment,count)
        end
        return common .. physical .. observations .. source_fields .. '}'
    end
    local prefix="[MineComeMovementFollower]"
    local count=segment and #segment.samples or 0
    local text=serialize(count)
    -- KCD's logger truncates long lines. Bound the whole record before emission
    -- rather than letting a valid receipt become partial JSON in the game log.
    while #prefix+1+#text+2>FOLLOWER_LOG_MAX_BYTES and count>1 do
        count=count-1;text=serialize(count)
    end
    if #prefix+1+#text+2>FOLLOWER_LOG_MAX_BYTES then return false end
    local ok = emit(prefix,text)
    if ok then p.records = p.records+1 end
    return ok
end
local function follower_consume(data)
    if type(data) ~= "table" or type(data.probe) ~= "table" then return nil end
    local p = data.probe
    if state.follower ~= p or p.terminal or p.data[data.slot] ~= data or not handle(p.timers[data.slot]) then return nil end
    p.timers[data.slot] = nil
    return p
end
local function follower_finish(p,event,result,s,readback,follow_error)
    if state.follower ~= p or p.terminal then return false end
    p.terminal = true;kill_owned(p);state.follower = nil
    if not p.timers_cancelled then result = result .. "_timer_cancel_failed" end
    return follower_receipt(p,event,result,s,nil,nil,readback,follow_error)
end
local function follower_camera_error(p,s,target)
    -- Physical native look may legitimately rotate the camera-to-actor offset.
    -- Report the current normal basis instead of reusing the scripted fixed-
    -- offset metric. No camera state or orientation is written by this module.
    if p.physical_movement then return nil end
    if not normal_camera(s.camera) then return nil end
    return distance(s.camera.position.value,{x=p.camera_origin.x+target.x-p.origin.x,
        y=p.camera_origin.y+target.y-p.origin.y,z=p.camera_origin.z+target.z-p.origin.z})
end
local function follower_stop(p,reason)
    if state.follower ~= p or p.terminal or p.restoring then return false end
    p.end_result = reason
    local s = snapshot();p.last_snapshot = s
    if not p.write_attempted then return follower_finish(p,"rejected",reason,s,false) end
    local unsafe = guards(s,0.2,false)
    if s.entity ~= p.entity or s.id ~= p.id then unsafe = "player_changed" end
    if distance(s.position.value,p.last_owned) > 0.35 then unsafe = "unexpected_player_navigation" end
    if horizontal(s.velocity.value) > 0.2 then unsafe = "unexpected_horizontal_input" end
    if unsafe then return follower_finish(p,"restore_failed","skipped_" .. unsafe,s,false) end
    p.writes = p.writes+1
    local ok,value = pcall(p.entity.SetWorldPos,p.entity,copy(p.origin))
    s = snapshot();p.last_snapshot = s
    local confirmed = ok and value ~= false and s.stable and s.entity == p.entity and s.id == p.id and distance(s.position.value,p.origin) <= 0.05
    if not confirmed then return follower_finish(p,"restore_failed","restore_readback_failed",s,false) end
    p.restoring = true;kill_owned(p)
    if not arm(p,"restored","MineCome_MovementFollowerRestored",TICK_MS) then return follower_finish(p,"restore_failed","post_restore_timer_failed",s,true) end
    return follower_receipt(p,"restoring","restored_position_pending_camera",s,nil,p.origin,true)
end
local function begin_follower(run,physical,buffered,extended)
    if not token(run) then return false,"invalid_run" end
    if state.active or state.follower then return false,"busy" end
    local s,clock = snapshot(),now()
    local unsafe = guards(s,0.05,true,true)
    if not clock then unsafe = "clock_unavailable" end
    if type(field(s.entity,"SetWorldPos")) ~= "function" then unsafe = "position_writer_unavailable" end
    if not Script or type(Script.SetTimerForFunction) ~= "function" or type(Script.KillTimer) ~= "function" then unsafe = "timer_unavailable" end
    local limits = extended and EXTENDED_LIMITS or physical and PHYSICAL_LIMITS or SCRIPTED_LIMITS
    local p = {run=run,entity=s.entity,id=s.id,created=clock,deadline=clock and clock+limits.hard_ms/1000,origin=copy(s.position.value),
        camera_origin=copy(s.camera.position.value),last_owned=copy(s.position.value),last_snapshot=s,timers={},data={},
        records=0,writes=0,last_queued_seq=0,last_applied_seq=0,last_heartbeat=clock,last_clock=clock,
        physical_movement=physical,last_physical_tick=clock,buffered_movement=buffered,buffer_queue=buffered and {} or nil}
    follower_profiles[p] = limits
    if unsafe then p.terminal=true;follower_receipt(p,"rejected",unsafe,s,0,nil,false);return false,unsafe end
    state.follower = p
    -- This timer is armed once; Apply never reschedules or extends it.
    if not arm(p,"hard","MineCome_MovementFollowerExpiry",limits.hard_ms,limits.hard_ms)
        or not arm(p,"tick","MineCome_MovementFollowerTick",follower_tick_ms(p)) then
        follower_finish(p,"rejected","initial_timer_failed",s,false);return false,"initial_timer_failed"
    end
    if not follower_receipt(p,"begin","awaiting_first_pose",s,0,nil,false) then
        follower_finish(p,"rejected","log_failed",s,false);return false,"log_failed"
    end
    return true,"begun"
end
function MineCome.BeginMovementFollower(run)
    return begin_follower(run,false)
end
function MineCome.BeginPhysicalMovementFollower(run)
    return begin_follower(run,true)
end
function MineCome.BeginBufferedPhysicalMovementFollower(run)
    return begin_follower(run,true,true)
end
function MineCome.BeginExtendedBufferedPhysicalMovementFollower(run)
    return begin_follower(run,true,true,true)
end
local function reject_buffered_input(p,reason,seq,target)
    p.end_requested=reason
    if p.records<follower_limits(p).receipts-2 then
        local reported=finite(seq) and seq>=1 and seq<=200 and seq==math.floor(seq) and seq or 0
        follower_receipt(p,"rejected",reason,p.last_snapshot,reported,copy(target),false)
    end
    return false,reason
end
function MineCome.ApplyMovementFollower(run,seq,x,y,z)
    if not token(run) then return false,"invalid_run" end
    local p = state.follower
    if not p or p.run ~= run or p.terminal or p.restoring or p.end_requested then return false,"wrong_or_inactive_run" end
    if p.buffered_movement then return reject_buffered_input(p,"buffered_mode_mismatch",seq,{x=x,y=y,z=z}) end
    local target = {x=x,y=y,z=z}
    local invalid
    if not finite(seq) or seq < 1 or seq > 200 or seq ~= math.floor(seq) then invalid = "sequence_invalid"
    elseif seq <= p.last_queued_seq then invalid = "sequence_replayed"
    elseif not vector(target) or distance(target,p.origin) > 2 or z-p.origin.z < (p.physical_movement and -1.5 or -0.2)
        or z-p.origin.z > 1.5 then invalid = "target_out_of_bounds" end
    local clock = now()
    if not clock or clock < p.last_clock or (p.physical_movement and p.latest and clock < p.latest.received) then invalid = "clock_unavailable_or_regressed"
    elseif clock >= p.deadline then invalid = "hard_deadline"
    elseif not p.latest and clock-p.created > 0.8 then invalid = "first_pose_expired" end
    if invalid then
        local reported_seq = finite(seq) and seq >= 1 and seq <= 200 and seq == math.floor(seq) and seq or 0
        if p.records >= follower_limits(p).receipts-2 then p.end_requested="receipt_budget" else follower_receipt(p,"rejected",invalid,p.last_snapshot,reported_seq,copy(target),false) end
        return false,invalid
    end
    p.last_queued_seq = seq
    p.latest = {seq=seq,target=copy(target),received=clock}
    return true,"queued"
end
function MineCome.ApplyBufferedMovementFollower(run,seq,x,y,z,source_ms)
    if not token(run) then return false,"invalid_run" end
    local p=state.follower
    if not p or p.run~=run or p.terminal or p.restoring or p.end_requested then return false,"wrong_or_inactive_run" end
    local target={x=x,y=y,z=z}
    if not p.buffered_movement then return reject_buffered_input(p,"buffered_mode_mismatch",seq,target) end
    if p.finish_seq then return reject_buffered_input(p,"source_after_finish",seq,target) end
    local clock=now()
    local invalid
    if not finite(seq) or seq<1 or seq>200 or seq~=math.floor(seq) then invalid="sequence_invalid"
    elseif seq<=p.last_queued_seq then invalid="sequence_replayed"
    elseif not vector(target) or distance(target,p.origin)>2 or z-p.origin.z < -1.5 or z-p.origin.z>1.5 then invalid="target_out_of_bounds"
    elseif not finite(source_ms) or source_ms<0 or source_ms>follower_limits(p).source_ms then invalid="source_time_invalid"
    elseif not clock or clock<p.last_clock or (p.latest and clock<p.latest.received) then invalid="clock_unavailable_or_regressed"
    elseif clock>=p.deadline then invalid="hard_deadline"
    elseif not p.latest and clock-p.created>0.8 then invalid="first_pose_expired"
    elseif not p.latest and (source_ms~=0 or distance(target,p.origin)>POSITION_EPSILON) then invalid="source_anchor_invalid"
    elseif p.latest and source_ms<=p.latest.source_ms then invalid="source_time_replayed"
    elseif p.buffer_epoch and source_ms<(clock-p.buffer_epoch)*1000 then invalid="source_time_late"
    elseif #p.buffer_queue+(p.buffer_anchor and 1 or 0)>=BUFFER_CAPACITY then invalid="source_queue_overflow"
    elseif p.buffer_tail_held and #p.buffer_queue==0 and p.buffer_anchor
        and distance(target,p.buffer_anchor.target)>POSITION_EPSILON then invalid="source_continuation_late" end
    if invalid then return reject_buffered_input(p,invalid,seq,target) end
    local point={seq=seq,target=copy(target),received=clock,source_ms=source_ms}
    p.buffer_queue[#p.buffer_queue+1]=point
    if not p.buffer_epoch then p.buffer_epoch=clock+BUFFER_DELAY_SECONDS end
    p.last_queued_seq=seq;p.latest=point
    return true,"queued"
end
function MineCome.FinishBufferedMovementFollower(run,final_seq)
    if not token(run) then return false,"invalid_run" end
    local p=state.follower
    if not p or p.run~=run or p.terminal or p.restoring or p.end_requested then return false,"wrong_or_inactive_run" end
    local clock=now()
    local invalid
    if not p.buffered_movement then invalid="buffered_mode_mismatch"
    elseif not finite(final_seq) or final_seq<1 or final_seq>200 or final_seq~=math.floor(final_seq) then invalid="final_sequence_invalid"
    elseif not p.latest then invalid="final_source_missing"
    elseif final_seq~=p.latest.seq then invalid="final_source_mismatch"
    elseif not clock or clock<p.last_clock or clock<p.latest.received then invalid="clock_unavailable_or_regressed"
    elseif clock>=p.deadline then invalid="hard_deadline"
    elseif clock-p.latest.received>LEASE_SECONDS then invalid="frame_lease_expired" end
    if invalid then return reject_buffered_input(p,invalid,final_seq,p.last_owned) end
    -- Sealing only records intent. No setters, timer changes or renewed leases
    -- occur in this console callback, including on an identical repeated seal.
    p.finish_seq=final_seq
    return true,"finish_queued"
end
local function physical_observe(p,s,clock)
    local step=p.physical_step
    if not step then return end
    -- Scheduling another callback is not proof of another game frame.
    if clock<=step.at then return end
    p.physical_step=nil
    local segment=step.segment
    local error=distance(s.position.value,step.target)
    segment.observations=segment.observations+1
    segment.max_error=math.max(segment.max_error,error)
    segment.max_gap_ms=math.max(segment.max_gap_ms,(clock-(segment.last_observed or step.at))*1000)
    segment.last_observed=clock
    if #segment.samples<8 or step.fraction==1 or step.preserve_observation then
        local index=math.min(#segment.samples+1,8)
        -- snapshot() already copies getter vectors. Retain the later camera
        -- observation, not the requested actor position or immediate readback.
        segment.samples[index]={fraction=step.fraction,requested=copy(step.target),actual=copy(s.position.value),
            written_at=step.at,observed_at=clock,written=step.written,error=error,camera=s.camera,
            camera_basis_valid=physical_camera(s)==true,written_frame_id=step.frame_id,observed_frame_id=native_frame_id(),source=step.source}
    end
end
local function physical_write(p,clock,previous_tick)
    -- Engine-time interpolation, never velocity extrapolation. The immutable
    -- target retains its own acceptance lease while later targets coalesce.
    local segment = p.physical_segment
    if segment and clock-segment.received > LEASE_SECONDS then segment=nil;p.physical_segment=nil end
    if not segment and p.latest.seq ~= p.last_applied_seq then
        local target,start = p.latest.target,p.last_owned
        segment={seq=p.latest.seq,target=copy(target),received=p.latest.received,start=copy(start),
            started=math.max(p.latest.received,previous_tick),stationary=distance(start,target)<=POSITION_EPSILON,
            samples={},updates=0,observations=0,max_gap_ms=0,max_error=0,endpoint_written=false}
        p.physical_segment=segment
    end
    if not segment then return p.latest,p.latest.target,false,nil end
    local fraction=segment.stationary and 1 or math.max(0,math.min(1,(clock-segment.started)/INTERPOLATION_SECONDS))
    local target=copy(segment.target)
    if fraction<1 then
        target={x=segment.start.x+(target.x-segment.start.x)*fraction,
            y=segment.start.y+(target.y-segment.start.y)*fraction,z=segment.start.z+(target.z-segment.start.z)*fraction}
    end
    return segment,target,fraction==1,fraction
end
local function buffered_write(p,clock)
    if not p.buffer_epoch or clock<p.buffer_epoch then return nil end
    local playback=(clock-p.buffer_epoch)*1000
    local crossed,crossed_count=nil,0
    while p.buffer_queue[1] and p.buffer_queue[1].source_ms<=playback do
        local point=p.buffer_queue[1]
        -- A fresh later sample cannot revive an expired part of the path.
        if clock-point.received>LEASE_SECONDS then return nil,nil,nil,nil,nil,"source_destination_expired" end
        table.remove(p.buffer_queue,1);p.buffer_anchor=point;crossed=point;crossed_count=crossed_count+1
    end
    local left=p.buffer_anchor
    if not left then return nil,nil,nil,nil,nil,"source_anchor_unavailable" end
    local right=p.buffer_queue[1] or left
    if clock-right.received>LEASE_SECONDS then return nil,nil,nil,nil,nil,"source_destination_expired" end
    local hold=left==right
    local fraction=hold and 0 or math.max(0,math.min(1,(playback-left.source_ms)/(right.source_ms-left.source_ms)))
    local target={x=left.target.x+(right.target.x-left.target.x)*fraction,
        y=left.target.y+(right.target.y-left.target.y)*fraction,z=left.target.z+(right.target.z-left.target.z)*fraction}
    local source={from=left,to=right,playback_ms=playback,hold=hold,crossed=crossed,crossed_count=crossed_count}
    p.buffer_tail_held=hold and playback>left.source_ms
    local segment=p.buffer_segment
    if not segment then
        segment={started=clock,samples={},updates=0,observations=0,max_gap_ms=0,max_error=0,endpoint_written=false}
        p.buffer_segment=segment
    end
    return segment,target,crossed~=nil,fraction,source
end
function MineCome_MovementFollowerTick(data)
    local p = follower_consume(data);if not p then return false end
    local clock,s = now(),snapshot();p.last_snapshot = s
    if not clock or clock < p.last_clock then return follower_stop(p,"clock_unavailable_or_regressed") end
    p.last_clock = clock
    if p.end_requested then return follower_stop(p,p.end_requested) end
    if clock >= p.deadline then return follower_stop(p,"hard_deadline") end
    if p.records >= follower_limits(p).receipts-2 then return follower_stop(p,"receipt_budget") end
    if not p.latest then
        if clock-p.created > 0.8 then return follower_stop(p,"first_pose_expired") end
    elseif clock-p.latest.received > LEASE_SECONDS then return follower_stop(p,"frame_lease_expired")
    elseif p.physical_movement and clock<p.latest.received then return follower_stop(p,"clock_unavailable_or_regressed") end
    local unsafe = guards(s,6,true)
    if s.entity ~= p.entity or s.id ~= p.id then unsafe = "player_changed" end
    if distance(s.position.value,p.last_owned) > 0.35 then unsafe = "unexpected_player_navigation" end
    if horizontal(s.velocity.value) > 0.2 then unsafe = "unexpected_horizontal_input" end
    if unsafe then return follower_stop(p,unsafe) end
    local previous_tick=p.last_physical_tick
    if p.physical_movement then
        if clock<=previous_tick then
            if not arm(p,"tick","MineCome_MovementFollowerTick",PHYSICAL_TICK_MS) then return follower_stop(p,"tick_timer_failed") end
            return true
        end
        p.last_physical_tick=clock
        physical_observe(p,s,clock)
    end
    -- Sample the previous write only after a normal game frame. Applied ACKs
    -- carry that exact seq/target, not the next queued target's camera values.
    if p.pending_receipt then
        local pending = p.pending_receipt;p.pending_receipt = nil
        if p.buffered_movement and clock-pending.received>LEASE_SECONDS then return follower_stop(p,"source_receipt_expired") end
        local readback = distance(s.position.value,pending.target) <= 0.05
        local error = follower_camera_error(p,s,pending.target)
        if not follower_receipt(p,"applied",readback and "applied_readback" or "delayed_readback_changed",s,pending.seq,pending.target,readback,error,pending.received,pending.segment,pending.source) then return follower_stop(p,"log_failed") end
        if p.buffered_movement then p.last_buffered_ack_seq=pending.seq;p.last_buffered_ack_readback=readback end
    elseif p.latest and clock-p.last_heartbeat >= 1 then
        p.last_heartbeat = clock
        if not follower_receipt(p,"heartbeat","holding_latest",s,nil,p.last_owned,distance(s.position.value,p.last_owned)<=0.05,
            follower_camera_error(p,s,p.last_owned)) then return follower_stop(p,"log_failed") end
    end
    if p.buffered_movement and p.finish_seq and p.last_buffered_ack_seq==p.finish_seq then
        -- The final source write alone is insufficient: its actual observation
        -- and camera receipt must be emitted before the guarded origin restore.
        return follower_stop(p,p.last_buffered_ack_readback and "explicit_end" or "final_readback_changed")
    end
    if p.latest then
        if not p.ground_verified then
            if distance(s.position.value,p.origin) > 0.02 or not ground(p.origin,p.id) then return follower_stop(p,"initial_ground_not_verified") end
            s = snapshot()
            if guards(s,0.05,true,true) or s.entity ~= p.entity or s.id ~= p.id or distance(s.position.value,p.origin)>0.02 then return follower_stop(p,"player_changed_during_ground_check") end
            p.ground_verified = true
        end
        local frame,target,endpoint,fraction,source,source_error = p.latest,p.latest.target,true,nil,nil,nil
        if p.buffered_movement then
            frame,target,endpoint,fraction,source,source_error=buffered_write(p,clock)
            if source_error then return follower_stop(p,source_error) end
        elseif p.physical_movement then frame,target,endpoint,fraction=physical_write(p,clock,previous_tick) end
        if not frame then
            if not arm(p,"tick","MineCome_MovementFollowerTick",follower_tick_ms(p)) then return follower_stop(p,"tick_timer_failed") end
            return true
        end
        local written=not p.physical_movement or distance(s.position.value,target)>POSITION_EPSILON
        local ok,value,readback=true,nil,s
        if written then
            -- Reserve one additional write for guarded restoration. Legacy
            -- scripted cadence/budget remain 40ms and 199 ordinary writes.
            if p.writes >= follower_limits(p).writes then return follower_stop(p,"write_budget") end
            p.write_attempted=true;p.writes=p.writes+1
            ok,value=pcall(p.entity.SetWorldPos,p.entity,copy(target))
            readback=snapshot();p.last_snapshot=readback
        end
        if ok and value ~= false and readback.stable and readback.entity == p.entity and readback.id == p.id and distance(readback.position.value,target)<=0.05 then
            p.last_owned = copy(target)
            if p.physical_movement and fraction then
                if written then frame.updates=frame.updates+1 end
                p.physical_step={segment=frame,target=copy(target),fraction=fraction,at=clock,written=written,frame_id=native_frame_id(),
                    source=source,preserve_observation=p.buffered_movement and endpoint}
            end
            if endpoint then
                if p.buffered_movement then
                    frame.endpoint_written=written
                    p.pending_receipt={seq=source.crossed.seq,target=copy(target),received=source.crossed.received,segment=frame,source=source}
                    p.last_applied_seq=source.crossed.seq;p.buffer_segment=nil
                elseif frame.seq ~= p.last_applied_seq then
                    if p.physical_movement then frame.endpoint_written=written end
                    p.pending_receipt={seq=frame.seq,target=copy(frame.target),received=frame.received,
                        segment=p.physical_movement and frame or nil};p.last_applied_seq=frame.seq
                end
                if p.physical_movement then p.physical_segment=nil end
            end
        else
            -- A native call can fail after changing the transform. A same-entity
            -- readback at the exact requested point makes guarded cleanup safe.
            if readback.stable and readback.entity == p.entity and readback.id == p.id and distance(readback.position.value,target)<=0.05 then p.last_owned=copy(target) end
            return follower_stop(p,"position_write_or_readback_failed")
        end
    end
    if not arm(p,"tick","MineCome_MovementFollowerTick",follower_tick_ms(p)) then return follower_stop(p,"tick_timer_failed") end
    return true
end
function MineCome_MovementFollowerExpiry(data)
    local p = follower_consume(data);if not p then return false end
    return follower_stop(p,"hard_deadline")
end
function MineCome_MovementFollowerRestored(data)
    local p = follower_consume(data);if not p then return false end
    local s = snapshot();p.last_snapshot = s
    local confirmed = s.stable and s.entity == p.entity and s.id == p.id and distance(s.position.value,p.origin)<=0.05
    local error = follower_camera_error(p,s,p.origin)
    if p.physical_movement and not physical_camera(s) then
        return follower_finish(p,"restore_failed","normal_camera_unavailable_after_restore",s,confirmed,error)
    end
    return follower_finish(p,confirmed and "restored" or "restore_failed",confirmed and "restored" or "delayed_restore_readback_failed",s,confirmed,error)
end
function MineCome.EndMovementFollower(run)
    if not token(run) then return false,"invalid_run" end
    local p = state.follower
    if not p or p.run ~= run or p.terminal then return false,"wrong_or_inactive_run" end
    if not p.restoring then p.end_requested = "explicit_end" end
    return true,"end_queued"
end
