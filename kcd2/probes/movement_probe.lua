-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original opt-in capability / restored position probe; no automatic work.
-- Evidence: kcd2-mod-docs9cb067543245ec5cf4e27b3d21e32485a35db518,
-- script_bind_2025_01_14 Entity.GetWorldPos/GetVelocity and actor/player/human
-- getters. Installed tools Data/Scripts.pak SpawnPoint.lua:104 uses SetWorldPos;
-- SinglePlayer.lua:266 uses the same player setter. Timer optional userData and
-- bUpdateDuringPause: CScriptBindScript__SetTimerForFunction...html:80-110;
-- KillTimer...html:70-84. Ray call: PressurizedObject.lua:308-310, private hit table.
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
local function horizontal(v) return vector(v) and math.sqrt(v.x*v.x+v.y*v.y) or math.huge end
local function follower_receipt(p,event,result,s,seq,target,readback,follow_error)
    if p.records >= 128 then return false end
    local clock = now()
    local lease = p.latest and clock and math.max(0,(LEASE_SECONDS-(clock-p.latest.received))*1000) or 0
    local physical = ""
    if p.physical_movement then
        target = target or (p.restoring and p.origin or p.last_owned)
        physical = ',"physical_movement":true,"camera_mode":"native_look","camera_basis_valid":'
            .. tostring(physical_camera(s) == true) .. ',"sampled_engine_seconds":' .. number(clock)
            .. ',"player_readback_error":' .. number(distance(s and s.position.value,target))
    end
    local text = '{"schema":1,"run":' .. quote(p.run) .. ',"event":' .. quote(event) .. ',"result":' .. quote(result)
        .. ',"terminal":' .. tostring(p.terminal == true) .. ',"seq":' .. number(seq or p.last_applied_seq or 0)
        .. ',"target":' .. vecjson(target or p.last_owned) .. ',"player":' .. vecjson(s and s.position.value)
        .. ',"camera":' .. camera_json(s and s.camera) .. ',"readback":' .. tostring(readback == true)
        .. ',"follow_error":' .. number(follow_error) .. ',"lease_ms":' .. number(lease)
        .. ',"hard_deadline_ms":8000,"elapsed_ms":' .. number(clock and (clock-p.created)*1000)
        .. ',"writes":' .. number(p.writes) .. ',"end_result":' .. quote(p.end_result or "none")
        .. ',"timers_cancelled":' .. tostring(p.timers_cancelled ~= false) .. physical .. '}'
    local ok = emit("[MineComeMovementFollower]",text)
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
local function begin_follower(run,physical)
    if not token(run) then return false,"invalid_run" end
    if state.active or state.follower then return false,"busy" end
    local s,clock = snapshot(),now()
    local unsafe = guards(s,0.05,true,true)
    if not clock then unsafe = "clock_unavailable" end
    if type(field(s.entity,"SetWorldPos")) ~= "function" then unsafe = "position_writer_unavailable" end
    if not Script or type(Script.SetTimerForFunction) ~= "function" or type(Script.KillTimer) ~= "function" then unsafe = "timer_unavailable" end
    local p = {run=run,entity=s.entity,id=s.id,created=clock,deadline=clock and clock+8,origin=copy(s.position.value),
        camera_origin=copy(s.camera.position.value),last_owned=copy(s.position.value),last_snapshot=s,timers={},data={},
        records=0,writes=0,last_queued_seq=0,last_applied_seq=0,last_heartbeat=clock,last_clock=clock,
        physical_movement=physical}
    if unsafe then p.terminal=true;follower_receipt(p,"rejected",unsafe,s,0,nil,false);return false,unsafe end
    state.follower = p
    -- This timer is armed once; Apply never reschedules or extends it.
    if not arm(p,"hard","MineCome_MovementFollowerExpiry",FOLLOWER_MS,FOLLOWER_MS)
        or not arm(p,"tick","MineCome_MovementFollowerTick",TICK_MS) then
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
function MineCome.ApplyMovementFollower(run,seq,x,y,z)
    if not token(run) then return false,"invalid_run" end
    local p = state.follower
    if not p or p.run ~= run or p.terminal or p.restoring or p.end_requested then return false,"wrong_or_inactive_run" end
    local target = {x=x,y=y,z=z}
    local invalid
    if not finite(seq) or seq < 1 or seq > 200 or seq ~= math.floor(seq) then invalid = "sequence_invalid"
    elseif seq <= p.last_queued_seq then invalid = "sequence_replayed"
    elseif not vector(target) or distance(target,p.origin) > 2 or z-p.origin.z < -0.2 or z-p.origin.z > 1.5 then invalid = "target_out_of_bounds" end
    local clock = now()
    if not clock or clock < p.last_clock then invalid = "clock_unavailable_or_regressed"
    elseif clock >= p.deadline then invalid = "hard_deadline"
    elseif not p.latest and clock-p.created > 0.8 then invalid = "first_pose_expired" end
    if invalid then
        local reported_seq = finite(seq) and seq >= 1 and seq <= 200 and seq == math.floor(seq) and seq or 0
        if p.records >= 126 then p.end_requested="receipt_budget" else follower_receipt(p,"rejected",invalid,p.last_snapshot,reported_seq,copy(target),false) end
        return false,invalid
    end
    p.last_queued_seq = seq
    p.latest = {seq=seq,target=copy(target),received=clock}
    return true,"queued"
end
function MineCome_MovementFollowerTick(data)
    local p = follower_consume(data);if not p then return false end
    local clock,s = now(),snapshot();p.last_snapshot = s
    if not clock or clock < p.last_clock then return follower_stop(p,"clock_unavailable_or_regressed") end
    p.last_clock = clock
    if p.end_requested then return follower_stop(p,p.end_requested) end
    if clock >= p.deadline then return follower_stop(p,"hard_deadline") end
    if p.records >= 126 then return follower_stop(p,"receipt_budget") end
    if not p.latest then
        if clock-p.created > 0.8 then return follower_stop(p,"first_pose_expired") end
    elseif clock-p.latest.received > LEASE_SECONDS then return follower_stop(p,"frame_lease_expired") end
    local unsafe = guards(s,6,true)
    if s.entity ~= p.entity or s.id ~= p.id then unsafe = "player_changed" end
    if distance(s.position.value,p.last_owned) > 0.35 then unsafe = "unexpected_player_navigation" end
    if horizontal(s.velocity.value) > 0.2 then unsafe = "unexpected_horizontal_input" end
    if unsafe then return follower_stop(p,unsafe) end
    -- Sample the previous write only after a normal game frame. Applied ACKs
    -- carry that exact seq/target, not the next queued target's camera values.
    if p.pending_receipt then
        local pending = p.pending_receipt;p.pending_receipt = nil
        local readback = distance(s.position.value,pending.target) <= 0.05
        local error = follower_camera_error(p,s,pending.target)
        if not follower_receipt(p,"applied",readback and "applied_readback" or "delayed_readback_changed",s,pending.seq,pending.target,readback,error) then return follower_stop(p,"log_failed") end
    elseif p.latest and clock-p.last_heartbeat >= 1 then
        p.last_heartbeat = clock
        if not follower_receipt(p,"heartbeat","holding_latest",s,nil,p.last_owned,distance(s.position.value,p.last_owned)<=0.05,
            follower_camera_error(p,s,p.last_owned)) then return follower_stop(p,"log_failed") end
    end
    if p.latest then
        if not p.ground_verified then
            if distance(s.position.value,p.origin) > 0.02 or not ground(p.origin,p.id) then return follower_stop(p,"initial_ground_not_verified") end
            s = snapshot()
            if guards(s,0.05,true,true) or s.entity ~= p.entity or s.id ~= p.id or distance(s.position.value,p.origin)>0.02 then return follower_stop(p,"player_changed_during_ground_check") end
            p.ground_verified = true
        end
        if p.writes >= 199 then return follower_stop(p,"write_budget") end
        local frame = p.latest
        p.write_attempted=true;p.writes=p.writes+1
        local ok,value = pcall(p.entity.SetWorldPos,p.entity,copy(frame.target))
        local readback = snapshot();p.last_snapshot = readback
        if ok and value ~= false and readback.stable and readback.entity == p.entity and readback.id == p.id and distance(readback.position.value,frame.target)<=0.05 then
            p.last_owned = copy(frame.target)
            if frame.seq ~= p.last_applied_seq then p.pending_receipt={seq=frame.seq,target=copy(frame.target)};p.last_applied_seq=frame.seq end
        else
            -- A native call can fail after changing the transform. A same-entity
            -- readback at the exact requested point makes guarded cleanup safe.
            if readback.stable and readback.entity == p.entity and readback.id == p.id and distance(readback.position.value,frame.target)<=0.05 then p.last_owned=copy(frame.target) end
            return follower_stop(p,"position_write_or_readback_failed")
        end
    end
    if not arm(p,"tick","MineCome_MovementFollowerTick",TICK_MS) then return follower_stop(p,"tick_timer_failed") end
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
