-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original diagnostic script. APIs are documented by the official Lua bindings.
-- No base-game script overrides, automatic entity writes or save commands.
MineCome = MineCome or {}
MineCome.diagnostic_enabled = false
MineCome.diagnostic_interval_ms = 200

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function vector_json(value)
    if not value or not finite(value.x) or not finite(value.y) or not finite(value.z) then
        return nil
    end
    return string.format('{"x":%.9g,"y":%.9g,"z":%.9g}', value.x, value.y, value.z)
end

function MineCome.ReadCamera()
    if not System or not System.GetViewCameraPos or not System.GetViewCameraDir
        or not System.GetViewCameraUpDir or not System.GetViewCameraFov then
        return nil
    end
    return {
        position = System.GetViewCameraPos(),
        forward = System.GetViewCameraDir(),
        up = System.GetViewCameraUpDir(),
        fov_raw = System.GetViewCameraFov()
    }
end

function MineCome.SamplePose()
    local camera = MineCome.ReadCamera()
    if not camera then
        System.LogAlways("[MineCome] Camera state unavailable")
        return false
    end
    local p, f, u = vector_json(camera.position), vector_json(camera.forward), vector_json(camera.up)
    if not p or not f or not u or not finite(camera.fov_raw) then
        System.LogAlways("[MineCome] Camera state invalid; raw sample skipped")
        return false
    end
    -- The installed official tools use player:GetWorldDir(); GetWorldPos is an
    -- official entity binding. The global player may be absent before world load.
    local player_json = "null"
    if player and player.GetWorldPos then
        local ok, position = pcall(function() return player:GetWorldPos() end)
        if ok then player_json = vector_json(position) or "null" end
    end
    System.LogAlways(string.format(
        '[MineComePose] {"schema":1,"player":%s,"camera":%s,"forward":%s,"up":%s,"fov_raw":%.9g,"calibrated":false}',
        player_json, p, f, u, camera.fov_raw))
    return true
end

MineCome.LogCamera = MineCome.SamplePose

function MineCome.Ping(message)
    local text = tostring(message or "MINECOME_PING")
    text = string.sub(string.gsub(text, "[\r\n]", " "), 1, 120)
    System.LogAlways("[MineComePing] " .. text)
end

-- Timer callback name is global, as required by SetTimerForFunction's binding.
function MineCome_DiagnosticTick()
    if not MineCome.diagnostic_enabled then return end
    local ok, result = pcall(MineCome.SamplePose)
    if not ok then
        System.LogAlways("[MineCome] Camera sampling error; diagnostics stopped")
        MineCome.diagnostic_enabled = false
        return
    end
    Script.SetTimerForFunction(MineCome.diagnostic_interval_ms, "MineCome_DiagnosticTick")
end

function MineCome.StartDiagnostics(interval_ms)
    if not Script or not Script.SetTimerForFunction then
        System.LogAlways("[MineCome] Documented script timer is unavailable")
        return false
    end
    if MineCome.diagnostic_enabled then return true end
    local interval = tonumber(interval_ms) or 200
    MineCome.diagnostic_interval_ms = math.max(200, math.min(5000, math.floor(interval)))
    MineCome.diagnostic_enabled = true
    Script.SetTimerForFunction(MineCome.diagnostic_interval_ms, "MineCome_DiagnosticTick")
    System.LogAlways("[MineCome] Read-only pose diagnostics started (at most 5 Hz)")
    return true
end

function MineCome.StopDiagnostics()
    MineCome.diagnostic_enabled = false
    System.LogAlways("[MineCome] Pose diagnostics stopped")
end

-- Explicit visual diagnostic using original Minecraft-exported assets compiled
-- by the installed official Resource Compiler. No physics proxy is available.
local stone_name = "MineCome_RuntimeStone"
local stone_model = "objects/minecome/stone.cgf"
local STONE_BOUNDS_TOLERANCE = 0.01

local function stone_point_matches(actual, expected)
    if type(actual) ~= "table" then return false end
    for _, axis in ipairs({ "x", "y", "z" }) do
        if not finite(actual[axis]) or math.abs(actual[axis] - expected[axis]) > STONE_BOUNDS_TOLERANCE then
            return false
        end
    end
    return true
end

local function checked_stone_bounds(entity, position)
    local minimum, maximum = entity:GetLocalBBox()
    local world_minimum, world_maximum = entity:GetWorldBBox()
    -- The compiled MC cell (x,y,z)->(x,-z,y) has this corner pivot,
    -- not a centered pivot. Size-only checks miss the engine's -90-degree
    -- default entity rotation, which displaced the visible cube by one metre.
    if not stone_point_matches(minimum, { x = 0, y = -1, z = 0 })
        or not stone_point_matches(maximum, { x = 1, y = 0, z = 1 })
        or not stone_point_matches(world_minimum, { x = position.x, y = position.y - 1, z = position.z })
        or not stone_point_matches(world_maximum, { x = position.x + 1, y = position.y, z = position.z + 1 }) then
        error("stone world geometry differs from the mapped Minecraft cell")
    end
    return minimum, maximum
end

local function load_aligned_stone(entity, position)
    entity:LoadObject(0, stone_model)
    -- Official Warhorse script_bind_2025_01_14:
    -- CScriptBindEntity__SetWorldAngles@IFunctionHandler__@Ang3.html and
    -- CScriptBindEntity__GetWorldBBox@IFunctionHandler__.html.
    -- Installed AnimObject.lua:614 also uses SetWorldAngles to restore a pose.
    -- Explicit world angles avoid System.SpawnEntity's observed -90-degree
    -- default. Read back the rendered bounds before drawing/acknowledging.
    entity:SetWorldAngles({ x = 0, y = 0, z = 0 })
    local minimum, maximum = checked_stone_bounds(entity, position)
    entity:DrawSlot(0, 1)
    return minimum, maximum
end

function MineCome.RemoveStone()
    if not MineCome.stone_entity_id then return true end
    local entity = System.GetEntityByName(stone_name)
    if not entity or entity.id ~= MineCome.stone_entity_id then
        MineCome.stone_entity_id = nil
        return true
    end
    local ok = pcall(function() System.RemoveEntity(entity.id) end)
    if not ok then
        System.LogAlways("[MineComeVisual] Temporary entity removal failed")
        return false
    end
    MineCome.stone_entity_id = nil
    System.LogAlways("[MineComeVisual] Temporary Minecraft entity removal requested")
    return true
end

function MineCome.ShowStone()
    if not player or not player.GetWorldPos then
        System.LogAlways("[MineComeVisual] No player/world; spawn withheld")
        return false
    end
    local player_ok, player_position = pcall(function() return player:GetWorldPos() end)
    local camera = MineCome.ReadCamera()
    if not player_ok or not vector_json(player_position) or not camera
        or not vector_json(camera.position) or not vector_json(camera.forward) then
        System.LogAlways("[MineComeVisual] Invalid live world/camera; spawn withheld")
        return false
    end
    local direction = camera.forward
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
    if not finite(length) or length < 0.000001 then return false end
    if not MineCome.RemoveStone() then return false end
    if System.GetEntityByName(stone_name) then
        System.LogAlways("[MineComeVisual] Reserved entity name already exists; preserving it")
        return false
    end
    local position = {
        x = camera.position.x + direction.x * 3 / length,
        y = camera.position.y + direction.y * 3 / length,
        z = camera.position.z + direction.z * 3 / length
    }
    local ok, entity = pcall(function()
        return System.SpawnEntity({
            class = "BasicEntity", name = stone_name, position = position,
            properties = {
                object_Model = stone_model,
                Physics = { bPhysicalize = false, bRigidBody = false, bPushableByPlayers = false }
            }
        })
    end)
    if not ok or not entity or not entity.id then
        System.LogAlways("[MineComeVisual] BasicEntity spawn failed")
        return false
    end
    MineCome.stone_entity_id = entity.id
    local loaded, minimum, maximum = pcall(function()
        -- The optional engine constant is checked rather than assuming SDK bits.
        if type(ENTITY_FLAG_NO_SAVE) == "number" and entity.SetFlags then
            entity:SetFlags(ENTITY_FLAG_NO_SAVE, 0)
        else
            System.LogAlways("[MineComeVisual] No exported no-save flag; remove the temporary entity before saving")
        end
        return load_aligned_stone(entity, position)
    end)
    if not loaded then
        System.LogAlways("[MineComeVisual] Geometry/bounds unavailable; removing temporary entity")
        MineCome.RemoveStone()
        return false
    end
    System.LogAlways(string.format(
        '[MineComeVisual] {"event":"spawn_requested","model":"%s","position":%s,"bounds_min":%s,"bounds_max":%s,"physics":false,"live_draw_verified":false}',
        stone_model, vector_json(position), vector_json(minimum), vector_json(maximum)))
    return true
end

-- Bounded stone-only sink. The host forwards these calls through the official
-- ExecuteString console, on the engine thread. No network callback runs here.
-- Official bindings: System.{GetCurrTime,GetEntity,GetEntityByName,SpawnEntity,
-- RemoveEntity}, entity:{LoadObject,DrawSlot,SetWorldAngles,GetLocalBBox,GetWorldBBox,SetFlags}, and
-- Script.SetTimerForFunction are in Warhorse's script_bind_2025_01_14 docs.
-- BasicEntity's installed SetFromProperties only physicalizes when
-- Properties.Physics.bPhysicalize is true. This sink always supplies false.
local BLOCK_CAPACITY = 128
local CLEANUP_BUDGET = 16
local BLOCK_TIMER_MS = 250
local BLOCK_LEASE_SECONDS = 6
local BLOCK_LEASE_TICKS = 24
-- The live KCD Lua/console boundary rounds numeric values to float32. IDs stay
-- canonical decimal strings throughout; JSON receives the validated digits.
local MAX_ID_TOKEN = "9007199254740991"
local MAX_MC_INTEGER = 16777215
local HOST_RADIUS_SQUARED = 32 * 32

-- Preserve provenance and the high-water mark if the original module reloads.
MineCome._block_sink = MineCome._block_sink or {
    last_session = "0", serial = "0", tick = 0, owned = {}, ending = {},
    cleanup_cursor = 1, timer_pending = false
}
local sink = MineCome._block_sink

local function integer_between(value, minimum, maximum)
    return finite(value) and value >= minimum and value <= maximum and value == math.floor(value)
end

local function valid_id_token(value)
    return type(value) == "string" and #value > 0 and #value <= #MAX_ID_TOKEN
        and string.match(value, "^[1-9][0-9]*$") ~= nil
        and (#value < #MAX_ID_TOKEN or value <= MAX_ID_TOKEN)
end

local function token_greater(value, previous)
    return #value > #previous or (#value == #previous and value > previous)
end

local function increment_token(value)
    if value == MAX_ID_TOKEN then return nil end
    local suffix = ""
    for index = #value, 1, -1 do
        local digit = string.sub(value, index, index)
        if digit ~= "9" then
            return string.sub(value, 1, index - 1) .. string.char(string.byte(digit) + 1) .. suffix
        end
        suffix = "0" .. suffix
    end
    return "1" .. suffix
end

-- Reloads retain exact known ownership. A legacy numeric id has already lost
-- precision in the old live VM; preserve its observed digits, never guess the
-- original transport id. Existing entity names/ids and timer state stay intact.
if sink.token_format ~= "decimal_text_v1" then
    local function legacy_token(value)
        if type(value) == "string" then return value end
        if finite(value) and value >= 0 and value == math.floor(value) then return string.format("%.0f", value) end
        return "0"
    end
    sink.last_session = legacy_token(sink.last_session)
    sink.serial = legacy_token(sink.serial)
    if sink.active then
        sink.active.session = legacy_token(sink.active.session)
        sink.active.sequence = legacy_token(sink.active.sequence)
    end
    for _, record in ipairs(sink.owned) do
        record.session = legacy_token(record.session)
        if record.remove_ack then
            record.remove_ack.session = legacy_token(record.remove_ack.session)
            record.remove_ack.sequence = legacy_token(record.remove_ack.sequence)
        end
    end
    local migrated_ending = {}
    for session, pending in pairs(sink.ending) do migrated_ending[legacy_token(session)] = pending end
    sink.ending = migrated_ending
    sink.token_format = "decimal_text_v1"
end

local function exact_integer_json(value)
    if valid_id_token(value) then return value end
    return "null"
end

local function valid_position(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
        and math.abs(value.x) <= 10000000 and math.abs(value.y) <= 10000000
        and math.abs(value.z) <= 10000000
end

local function owned_counts(session)
    local total, pending = 0, 0
    for _, record in ipairs(sink.owned) do
        if not session or record.session == session then
            total = total + 1
            if record.pending then pending = pending + 1 end
        end
    end
    return total, pending
end

local function sink_log(line)
    if System and System.LogAlways then pcall(System.LogAlways, line) end
end

local function session_receipt(event, session, result)
    local total, pending = owned_counts(session)
    sink_log(string.format(
        '[MineComeBlockSession] {"schema":1,"event":"%s","session":%s,"result":"%s","owned_count":%d,"pending_count":%d}',
        event, exact_integer_json(session), result, total, pending))
end

local function block_receipt(session, sequence, operation, mc, position, result, minimum, maximum)
    local event = operation == 1 and "place" or operation == 2 and "remove" or "invalid"
    local mc_json = "null"
    if type(mc) == "table" and integer_between(mc.x, -MAX_MC_INTEGER, MAX_MC_INTEGER)
        and integer_between(mc.y, -MAX_MC_INTEGER, MAX_MC_INTEGER) and integer_between(mc.z, -MAX_MC_INTEGER, MAX_MC_INTEGER) then
        mc_json = string.format('{"x":%.0f,"y":%.0f,"z":%.0f}', mc.x, mc.y, mc.z)
    end
    local function precise_vector(value)
        if not valid_position(value) then return "null" end
        return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', value.x, value.y, value.z)
    end
    sink_log(string.format(
        '[MineComeBlock] {"schema":1,"event":"%s","session":%s,"sequence":%s,"operation":%s,"mc":%s,"position":%s,"result":"%s","bounds_min":%s,"bounds_max":%s,"physics":false,"live_draw_verified":false}',
        event, exact_integer_json(session), exact_integer_json(sequence),
        (operation == 1 or operation == 2) and tostring(operation) or "null",
        mc_json, precise_vector(position), result, precise_vector(minimum), precise_vector(maximum)))
    return result == "spawned" or result == "already_present" or result == "removed" or result == "absent", result
end

local function engine_ready()
    return System and type(System.GetEntity) == "function" and type(System.GetEntityByName) == "function"
        and type(System.SpawnEntity) == "function" and type(System.RemoveEntity) == "function"
        and Script and type(Script.SetTimerForFunction) == "function"
end

local function world_player()
    if not player or type(player.GetWorldPos) ~= "function" then return nil end
    local ok, position = pcall(function() return player:GetWorldPos() end)
    if not ok or not valid_position(position) then return nil end
    return position, player.id or player
end

local function clock_time()
    if not System or type(System.GetCurrTime) ~= "function" then return nil end
    local ok, now = pcall(System.GetCurrTime)
    if ok and finite(now) then return now end
    return nil
end

local function refresh_lease(active)
    active.refreshed_at = clock_time()
    active.refreshed_tick = sink.tick
end

local function schedule_block_tick()
    if sink.timer_pending then return true end
    if not Script or type(Script.SetTimerForFunction) ~= "function" then return false end
    sink.timer_pending = true
    -- The documented fourth parameter makes cleanup run during pause. Supply
    -- the documented table userData so its optional parameter is unambiguous.
    local ok, timer = pcall(Script.SetTimerForFunction, BLOCK_TIMER_MS, "MineCome_BlockLeaseTick", {}, true)
    if not ok or timer == false then sink.timer_pending = false; return false end
    return true -- A nil timer id is permitted by the documented binding.
end

local function mark_pending(record)
    record.pending = true
    local active = sink.active
    if active and active.session == record.session and active.blocks[record.key] == record then
        active.blocks[record.key] = nil
    end
end

local function finish_active()
    local active = sink.active
    if not active then return end
    for _, record in ipairs(sink.owned) do
        if record.session == active.session then mark_pending(record) end
    end
    if owned_counts(active.session) > 0 then sink.ending[active.session] = true end
    sink.active = nil
end

local function remove_owned(record)
    -- Both lookups must agree before issuing a deletion. A colliding name or a
    -- reused/renamed id is never sufficient evidence of our original entity.
    local name_ok, by_name = pcall(System.GetEntityByName, record.name)
    local id_ok, by_id = pcall(System.GetEntity, record.id)
    if not name_ok or not id_ok then return false end
    if not by_id then return not by_name or by_name.id ~= record.id end
    if not by_name or not by_id or by_name.id ~= record.id or by_id.id ~= record.id then return false end
    if type(by_id.GetName) == "function" then
        local ok, name = pcall(function() return by_id:GetName() end)
        if not ok or name ~= record.name then return false end
    end
    local ok, removed = pcall(System.RemoveEntity, record.id)
    if not ok or removed == false then return false end
    name_ok, by_name = pcall(System.GetEntityByName, record.name)
    id_ok, by_id = pcall(System.GetEntity, record.id)
    return name_ok and id_ok and not by_id and (not by_name or by_name.id ~= record.id)
end

local function owned_at(session, key)
    for _, record in ipairs(sink.owned) do
        if record.session == session and record.key == key then return record end
    end
    return nil
end

local function acknowledge_removed(record)
    local ack = record.remove_ack
    if not ack then return end
    record.remove_ack = nil
    -- Engine removal may complete on a later frame. Retire ownership first,
    -- then acknowledge the original ordered event, even if its session ended.
    block_receipt(ack.session, ack.sequence, 2, ack.mc, ack.position, "removed")
end

local function cleanup_one(record)
    if not record.pending or not remove_owned(record) then return false end
    for index, candidate in ipairs(sink.owned) do
        if candidate == record then
            table.remove(sink.owned, index)
            if index < sink.cleanup_cursor then sink.cleanup_cursor = sink.cleanup_cursor - 1 end
            acknowledge_removed(record)
            return true
        end
    end
    return false
end

local function cleanup_step()
    if not System or type(System.GetEntityByName) ~= "function" or type(System.GetEntity) ~= "function"
        or type(System.RemoveEntity) ~= "function" then return end
    local examined, budget = 0, math.min(CLEANUP_BUDGET, #sink.owned)
    while #sink.owned > 0 and examined < budget do
        if sink.cleanup_cursor > #sink.owned then sink.cleanup_cursor = 1 end
        local record = sink.owned[sink.cleanup_cursor]
        examined = examined + 1
        if record.pending and remove_owned(record) then
            table.remove(sink.owned, sink.cleanup_cursor)
            acknowledge_removed(record)
        else
            sink.cleanup_cursor = sink.cleanup_cursor + 1
        end
    end
    for session in pairs(sink.ending) do
        if owned_counts(session) == 0 then
            sink.ending[session] = nil
            session_receipt("cleanup", session, "ended")
        end
    end
end

local function active_world_valid(active)
    local position, identity = world_player()
    return position and identity == active.player_identity, position
end

local function check_active()
    local active = sink.active
    if not active then return nil end
    local valid, position = active_world_valid(active)
    local now = clock_time()
    local elapsed = now and active.refreshed_at and now - active.refreshed_at
    if not valid or (elapsed and (elapsed < 0 or elapsed >= BLOCK_LEASE_SECONDS))
        or sink.tick - active.refreshed_tick >= BLOCK_LEASE_TICKS then
        local session = active.session
        finish_active()
        session_receipt("expired", session, owned_counts(session) == 0 and "ended" or "cleanup_pending")
        return nil
    end
    return active, position
end

local function distance_squared(a, b)
    return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2
end

function MineCome_BlockLeaseTick()
    if not sink.timer_pending then return end
    sink.timer_pending = false
    sink.tick = sink.tick + 1
    local active, position = check_active()
    if active then
        for _, record in ipairs(sink.owned) do
            if not record.pending and record.session == active.session
                and distance_squared(record.position, position) > HOST_RADIUS_SQUARED then
                mark_pending(record)
            end
        end
    end
    cleanup_step()
    if sink.active or #sink.owned > 0 then
        if not schedule_block_tick() then
            local session = sink.active and sink.active.session
            finish_active()
            cleanup_step()
            session_receipt("timer_failed", session, #sink.owned == 0 and "ended" or "cleanup_pending")
        end
    end
end

function MineCome.BeginBlockSession(session)
    if not valid_id_token(session) then
        session_receipt("begin", nil, "rejected_session"); return false, "rejected_session"
    end
    local current = check_active()
    if current and current.session == session then
        if not schedule_block_tick() then
            finish_active(); cleanup_step()
            session_receipt("begin", session, "rejected_timer"); return false, "rejected_timer"
        end
        refresh_lease(current)
        session_receipt("begin", session, "accepted"); return true, "accepted"
    end
    if not token_greater(session, sink.last_session) then
        session_receipt("begin", session, "rejected_replay"); return false, "rejected_replay"
    end
    local position, identity = world_player()
    if not engine_ready() or not position then
        session_receipt("begin", session, "rejected_world"); return false, "rejected_world"
    end
    if not schedule_block_tick() then
        session_receipt("begin", session, "rejected_timer"); return false, "rejected_timer"
    end
    finish_active()
    cleanup_step()
    sink.last_session = session
    sink.active = { session = session, sequence = "0", blocks = {}, player_identity = identity }
    refresh_lease(sink.active)
    if type(ENTITY_FLAG_NO_SAVE) ~= "number" and not sink.warned_no_save then
        sink.warned_no_save = true
        sink_log("[MineCome] No exported no-save flag; remove runtime blocks before saving")
    end
    session_receipt("begin", session, "accepted")
    return true, "accepted"
end

function MineCome.HeartbeatBlockSession(session)
    local active = check_active()
    if not valid_id_token(session) or not active or active.session ~= session then
        session_receipt("heartbeat", session, "rejected_session"); return false, "rejected_session"
    end
    refresh_lease(active)
    if not schedule_block_tick() then
        finish_active(); cleanup_step()
        session_receipt("heartbeat", session, "rejected_timer"); return false, "rejected_timer"
    end
    session_receipt("heartbeat", session, "alive")
    return true, "alive"
end

function MineCome.EndBlockSession(session)
    if not valid_id_token(session) then
        session_receipt("end", nil, "rejected_session"); return false, "rejected_session"
    end
    if sink.active and sink.active.session == session then finish_active() end
    if token_greater(session, sink.last_session) then
        session_receipt("end", session, "rejected_session"); return false, "rejected_session"
    end
    -- An old End may retry only records carrying that old session's provenance.
    for _, record in ipairs(sink.owned) do
        if record.session == session then mark_pending(record); sink.ending[session] = true end
    end
    cleanup_step()
    local result = owned_counts(session) == 0 and "ended" or "cleanup_pending"
    if #sink.owned > 0 or sink.active then schedule_block_tick() end
    session_receipt("end", session, result)
    return result == "ended", result
end

function MineCome.ApplyStoneEvent(session, sequence, operation, mc_x, mc_y, mc_z, kcd_x, kcd_y, kcd_z)
    local mc = { x = mc_x, y = mc_y, z = mc_z }
    local position = { x = kcd_x, y = kcd_y, z = kcd_z }
    local active, player_position = check_active()
    if not valid_id_token(session) or not active or active.session ~= session then
        return block_receipt(session, sequence, operation, mc, position, "rejected_session")
    end
    if not valid_id_token(sequence) then
        return block_receipt(session, sequence, operation, mc, position, "rejected_sequence")
    end
    if operation ~= 1 and operation ~= 2 then
        return block_receipt(session, sequence, operation, mc, position, "rejected_operation")
    end
    if not integer_between(mc_x, -MAX_MC_INTEGER, MAX_MC_INTEGER)
        or not integer_between(mc_y, -MAX_MC_INTEGER, MAX_MC_INTEGER)
        or not integer_between(mc_z, -MAX_MC_INTEGER, MAX_MC_INTEGER) or not valid_position(position) then
        return block_receipt(session, sequence, operation, nil, nil, "rejected_coordinates")
    end
    if not token_greater(sequence, active.sequence) then
        return block_receipt(session, sequence, operation, mc, position, "rejected_stale")
    end
    -- Consume each valid ordered event once, even if an engine write fails.
    active.sequence = sequence
    refresh_lease(active)
    local key = string.format("%.0f,%.0f,%.0f", mc_x, mc_y, mc_z)
    local existing = active.blocks[key] or owned_at(session, key)
    if operation == 2 then
        if not existing then return block_receipt(session, sequence, operation, mc, position, "absent") end
        mark_pending(existing)
        cleanup_one(existing)
        local unresolved = owned_at(session, key)
        if not unresolved then return block_receipt(session, sequence, operation, mc, position, "removed") end
        -- One pending ACK per owned record keeps metadata bounded by 128.
        -- A newer concurrent remove cannot overwrite the original event.
        if unresolved.remove_ack then
            return block_receipt(session, sequence, operation, mc, position, "rejected_pending")
        end
        unresolved.remove_ack = { session = session, sequence = sequence, mc = mc, position = position }
        return block_receipt(session, sequence, operation, mc, position, "cleanup_pending")
    end
    if distance_squared(position, player_position) > HOST_RADIUS_SQUARED then
        return block_receipt(session, sequence, operation, mc, position, "rejected_radius")
    end
    if existing and existing.pending then
        cleanup_one(existing)
        if owned_at(session, key) then
            return block_receipt(session, sequence, operation, mc, position, "cleanup_pending")
        end
        existing = nil
    end
    if existing then
        local name_ok, by_name = pcall(System.GetEntityByName, existing.name)
        local id_ok, by_id = pcall(System.GetEntity, existing.id)
        if not name_ok or not id_ok then
            return block_receipt(session, sequence, operation, mc, position, "rejected_ownership")
        end
        if not by_id and (not by_name or by_name.id ~= existing.id) then
            -- A newer place may recreate a cell removed outside this sink.
            mark_pending(existing); cleanup_one(existing); existing = nil
        elseif not by_name or not by_id or by_name.id ~= existing.id or by_id.id ~= existing.id then
            mark_pending(existing)
            return block_receipt(session, sequence, operation, mc, position, "rejected_ownership")
        end
    end
    if existing then
        if distance_squared(existing.position, position) > 0.000000000001 then
            return block_receipt(session, sequence, operation, mc, position, "rejected_origin_change")
        end
        -- Re-check actual geometry; a reload must not bless a pre-fix rotated
        -- entity, or one whose world/slot transform changed after creation.
        local valid, minimum, maximum = pcall(function()
            return checked_stone_bounds(System.GetEntity(existing.id), position)
        end)
        if not valid then
            mark_pending(existing); cleanup_one(existing)
            return block_receipt(session, sequence, operation, mc, position, "geometry_failed")
        end
        existing.minimum, existing.maximum = minimum, maximum
        return block_receipt(session, sequence, operation, mc, position, "already_present", minimum, maximum)
    end
    if #sink.owned >= BLOCK_CAPACITY then
        return block_receipt(session, sequence, operation, mc, position, "rejected_capacity")
    end
    local serial = increment_token(sink.serial)
    if not serial then return block_receipt(session, sequence, operation, mc, position, "rejected_serial") end
    sink.serial = serial
    local name = "MineCome_Block_" .. session .. "_" .. serial
    local lookup_ok, collision = pcall(System.GetEntityByName, name)
    if not lookup_ok or collision then return block_receipt(session, sequence, operation, mc, position, "rejected_name") end
    local ok, entity = pcall(System.SpawnEntity, {
        class = "BasicEntity", name = name, position = position,
        properties = { object_Model = stone_model,
            Physics = { bPhysicalize = false, bRigidBody = false, bPushableByPlayers = false } }
    })
    if not ok or not entity or not entity.id then
        -- Spawn callbacks can raise after creation. Recover only the unique,
        -- previously absent name supplied to this call, retaining its provenance.
        local recovered_ok, recovered = pcall(System.GetEntityByName, name)
        if recovered_ok and recovered and recovered.id then
            local failed = { session = session, id = recovered.id, name = name, key = key,
                position = position, pending = true }
            sink.owned[#sink.owned + 1] = failed
            cleanup_one(failed)
        end
        return block_receipt(session, sequence, operation, mc, position, "spawn_failed")
    end
    local record = { session = session, id = entity.id, name = name, key = key, position = position, pending = false }
    sink.owned[#sink.owned + 1] = record
    active.blocks[key] = record
    local loaded, minimum, maximum = pcall(function()
        if type(ENTITY_FLAG_NO_SAVE) == "number" and type(entity.SetFlags) == "function" then
            entity:SetFlags(ENTITY_FLAG_NO_SAVE, 0)
        end
        return load_aligned_stone(entity, position)
    end)
    if not loaded then
        mark_pending(record); cleanup_one(record)
        return block_receipt(session, sequence, operation, mc, position, "geometry_failed")
    end
    record.minimum, record.maximum = minimum, maximum
    return block_receipt(session, sequence, operation, mc, position, "spawned", minimum, maximum)
end

function MineCome.BlockSinkStatus()
    local total, pending = owned_counts()
    return { active_session = sink.active and sink.active.session, last_session = sink.last_session,
        last_sequence = sink.active and sink.active.sequence, owned_count = total,
        pending_count = pending, timer_pending = sink.timer_pending }
end

-- Original console commands only emit gameplay intent. The relay asks real
-- Minecraft to act, and Minecraft's ordered BLOCK_EVENTs drive the stone sink.
-- Documented System.AddCCommand(name, scriptCommand, help) stores a Lua command
-- string; named global indirection keeps existing registrations valid on reload.
-- No key bindings, entity calls, block sessions or save settings are changed.
MineCome._interactive_input = MineCome._interactive_input or {
    last_request = "0", registered_commands = {}, commands_registered = false
}
local input = MineCome._interactive_input
input.input_format = "stone_action_v1"
local INPUT_INTERVAL_SECONDS = 0.25

function MineCome.InteractiveIntent(action)
    if action ~= 1 and action ~= 2 then return false, "invalid_action" end
    if not world_player() then return false, "no_world" end
    local now = clock_time()
    if not now then return false, "clock_unavailable" end
    if input.last_input_at ~= nil then
        if not finite(input.last_input_at) or now < input.last_input_at
            or now - input.last_input_at < INPUT_INTERVAL_SECONDS then
            return false, "rate_limited"
        end
    end
    if input.last_request ~= "0" and not valid_id_token(input.last_request) then
        return false, "request_invalid"
    end
    local request = increment_token(input.last_request)
    if not request then return false, "request_exhausted" end
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end
    -- Consume before logging: a binding that writes then raises cannot cause a
    -- later call to reuse a request that may already have reached the relay.
    input.last_request = request
    input.last_input_at = now
    local ok, result = pcall(System.LogAlways, string.format(
        '[MineComeInput] {"schema":1,"request":%s,"action":%d}', request, action))
    if not ok or result == false then return false, "log_failed" end
    return true, request
end

local function register_input_commands()
    local available = System and type(System.AddCCommand) == "function" or false
    local commands = {
        { "minecome_place", "MineCome.InteractiveIntent(1)", "Request real Minecraft stone placement through MineCome's relay" },
        { "minecome_break", "MineCome.InteractiveIntent(2)", "Request real Minecraft block breaking through MineCome's relay" }
    }
    local registered = input.registered_commands
    for _, command in ipairs(commands) do
        if available and registered[command[1]] ~= true then
            local ok, result = pcall(System.AddCCommand, command[1], command[2], command[3])
            if ok and result ~= false then registered[command[1]] = true end
        end
    end
    input.commands_registered = registered.minecome_place == true and registered.minecome_break == true
    local result = input.commands_registered and "registered" or available and "failed" or "unavailable"
    sink_log(string.format(
        '[MineComeInputRegistration] {"schema":1,"input_format":"stone_action_v1","function_available":%s,"commands_registered":%s,"result":"%s","live_input_verified":false}',
        tostring(available), tostring(input.commands_registered), result))
end

register_input_commands()

if System and System.LogAlways then
    System.LogAlways("[MineCome] Lua diagnostic initialized; run #MineCome.SamplePose() after loading the world")
end
