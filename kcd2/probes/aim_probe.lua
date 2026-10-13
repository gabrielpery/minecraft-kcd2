-- SPDX-License-Identifier: GPL-3.0-or-later
-- Separate read-only diagnostic; loading this file does not run the probe.
-- Inspected Warhorse bindings at external/kcd2-mod-docs commit
-- 9cb067543245ec5cf4e27b3d21e32485a35db518, script_bind_2025_01_14:
-- CScriptBindSystem__GetViewCameraPos@IFunctionHandler__.html:60
-- CScriptBindSystem__GetViewCameraDir@IFunctionHandler__.html:60
-- CScriptBindSystem__GetCurrTime@IFunctionHandler__.html:60
-- CScriptBindPhysics__RayWorldIntersection@IFunctionHandler_.html:107
-- Primary scripts: Scripts/Entities/Render/Lightning.lua:352-353 reads the
-- camera; Scripts/Entities/Physics/PressurizedObject.lua:308 supplies a scaled
-- ray, max hits, ent_all, skipped entity id, nil, and an output table.
-- Documented ray-hit fields pos/dist are validated, never inferred from an
-- entity position: https://www.cryengine.com/docs/static/engines/cryengine-3/categories/1638401/pages/1933330
-- One synchronous callback samples the real camera and one bounded physics
-- ray. Engine time is not UTC. This does not establish MC/KCD alignment or
-- authorize any action. No shared hit table, timers, or game-state writes.

MineCome = MineCome or {}
local RANGE, MAX_HITS = 4.5, 16
local MAX_POSITION, MAX_SAMPLE_SECONDS, POSITION_TOLERANCE = 10000000, 0.25, 0.01

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function vector(value)
    return type(value) == "table" and finite(value.x) and finite(value.y) and finite(value.z)
        and math.abs(value.x) <= MAX_POSITION and math.abs(value.y) <= MAX_POSITION
        and math.abs(value.z) <= MAX_POSITION
end

local function copy(value)
    return { x = value.x, y = value.y, z = value.z }
end

local function time(value)
    return finite(value) and value >= 0 and value <= 1000000000000
end

local function number_json(value)
    return finite(value) and string.format("%.17g", value) or "null"
end

local function vector_json(value)
    if not vector(value) then return "null" end
    return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', value.x, value.y, value.z)
end

local function sample(record)
    local owner = player
    if not owner then return "no_world" end
    local skip = owner.id
    if skip == nil then return "skip_id_unavailable" end
    if type(System.GetCurrTime) ~= "function" then return "time_unavailable" end
    if type(System.GetViewCameraPos) ~= "function" or type(System.GetViewCameraDir) ~= "function" then
        return "camera_unavailable"
    end
    if not Physics or type(Physics.RayWorldIntersection) ~= "function" then return "ray_unavailable" end
    if not finite(ent_all) or ent_all <= 0 or ent_all > 2147483647 or ent_all ~= math.floor(ent_all) then
        return "mask_unavailable"
    end
    record.mask = ent_all
    local ok, value = pcall(System.GetCurrTime)
    if not ok then return "time_error" end
    if not time(value) then return "time_invalid" end
    record.engine_time = value
    ok, value = pcall(System.GetViewCameraPos)
    if not ok then return "camera_position_error" end
    if not vector(value) then return "camera_position_invalid" end
    record.origin = copy(value)
    ok, value = pcall(System.GetViewCameraDir)
    if not ok then return "camera_forward_error" end
    if not vector(value) then return "camera_forward_invalid" end
    local length = math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    if not finite(length) or length < 0.000000001 then return "camera_forward_invalid" end
    record.forward = { x = value.x / length, y = value.y / length, z = value.z / length }
    record.direction = { x = record.forward.x * RANGE, y = record.forward.y * RANGE,
        z = record.forward.z * RANGE }
    -- Give the binding independent argument copies: neither its output nor an
    -- engine-owned vector can change the captured camera fields in this record.
    local hits = {}
    record.skip_player = true
    local ray_ok, count = pcall(Physics.RayWorldIntersection, copy(record.origin), copy(record.direction),
        MAX_HITS, record.mask, skip, nil, hits)
    local end_ok, completed = pcall(System.GetCurrTime)
    if end_ok and time(completed) then record.completed_engine_time = completed end
    if not end_ok then return "completed_time_error" end
    if not time(completed) then return "completed_time_invalid" end
    if completed < record.engine_time then return "clock_reversed" end
    if completed - record.engine_time > MAX_SAMPLE_SECONDS then return "sample_expired" end
    if player ~= owner or owner.id ~= skip then return "world_changed" end
    if not ray_ok then return "ray_error" end
    if not finite(count) or count < 0 or count > MAX_HITS or count ~= math.floor(count) then
        return "hit_count_invalid"
    end
    record.hit_count = count
    local nearest
    for index = 1, MAX_HITS do
        local hit = hits[index]
        if index > count then
            if hit ~= nil then return "hit_count_mismatch" end
        else
            if type(hit) ~= "table" or not vector(hit.pos) or not finite(hit.dist)
                or hit.dist < 0 or hit.dist > RANGE then return "hit_fields_invalid" end
            local dx = hit.pos.x - record.origin.x - record.forward.x * hit.dist
            local dy = hit.pos.y - record.origin.y - record.forward.y * hit.dist
            local dz = hit.pos.z - record.origin.z - record.forward.z * hit.dist
            -- Check both location and reported distance, including lateral
            -- errors. A plausible first hit cannot hide a malformed later hit.
            if dx * dx + dy * dy + dz * dz > POSITION_TOLERANCE * POSITION_TOLERANCE then
                return "hit_outside_segment"
            end
            if not nearest or hit.dist < nearest.dist then nearest = { pos = copy(hit.pos), dist = hit.dist } end
        end
    end
    if hits[MAX_HITS + 1] ~= nil then return "hit_count_mismatch" end
    -- The binding may have truncated a saturated buffer. Do not assume its
    -- ordering or declare the nearest obstruction known in that case.
    if count == MAX_HITS then return "hit_buffer_saturated" end
    if nearest then record.nearest_position, record.nearest_distance = nearest.pos, nearest.dist end
    record.result = count == 0 and "no_hit" or "hit"
    return "none"
end

function MineCome.ProbeAim(runToken)
    if type(runToken) ~= "string" or #runToken < 1 or #runToken > 64
        or not string.match(runToken, "^[0-9a-fA-F]+$") then return false, "invalid_run" end
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end
    local record = { result = "unavailable", skip_player = false }
    local ok, reason = pcall(sample, record)
    if not ok then reason = "probe_error" end
    local known = ok and reason == "none"
    if not known then
        record.result, record.nearest_position, record.nearest_distance = "unavailable", nil, nil
    end
    local line = string.format(
        '[MineComeAimProbe] {"schema":1,"run":"%s","result":"%s","reason":"%s","engine_time":%s,"completed_engine_time":%s,"origin":%s,"forward":%s,"direction":%s,"range":4.5,"max_hits":16,"mask_name":"ent_all","mask":%s,"skip_player":%s,"hit_count":%s,"obstruction_known":%s,"clear":%s,"nearest_position":%s,"nearest_distance":%s,"diagnostic_only":true,"aiming_verified":false}',
        runToken, record.result, reason, number_json(record.engine_time), number_json(record.completed_engine_time),
        vector_json(record.origin), vector_json(record.forward), vector_json(record.direction), number_json(record.mask),
        tostring(record.skip_player), number_json(record.hit_count), tostring(known), tostring(known and record.result == "no_hit"),
        vector_json(record.nearest_position), number_json(record.nearest_distance))
    local logged, accepted = pcall(System.LogAlways, line)
    if not logged or accepted == false then return false, "log_failed" end
    return true, record.result
end
