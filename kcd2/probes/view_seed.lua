-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explicit read-only view sample. Loading this module performs no engine calls.
-- Inspected kcd2-mod-docs9cb067543245ec5cf4e27b3d21e32485a35db518:
-- script_bind_2025_01_14/CScriptBindEntity__GetWorldPos@IFunctionHandler__.html:52,60
-- script_bind_2025_01_14/CScriptBindSystem__GetViewCameraDir@IFunctionHandler__.html:52,60
-- script_bind_2025_01_14/CScriptBind_System__GetViewCameraUpDir@IFunctionHandler__.html:52,60-62
-- Existing movement_probe.lua establishes actual tools1.5.5 getters and raw id
-- identity. No timers, position/view/input/physics writes, or native offsets.

if MineCome == nil then MineCome = {} end
assert(type(MineCome) == "table", "MineCome namespace is not a table")
local POSITION_LIMIT = 16777215
local MAX_MOVE_SQUARED = 0.1 * 0.1
local MIN_ROLL_COSINE = math.cos(math.pi / 180)

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end
local function field(owner, key)
    if type(owner) ~= "table" and type(owner) ~= "userdata" then return nil end
    local ok, value = pcall(function() return owner[key] end)
    return ok and value or nil
end
local function copy_vector(value, bound)
    if type(value) ~= "table" then return nil end
    local x, y, z = value.x, value.y, value.z
    if not finite(x) or not finite(y) or not finite(z)
        or math.abs(x) > bound or math.abs(y) > bound or math.abs(z) > bound then return nil end
    return { x = x, y = y, z = z }
end
local function norm(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function scaled(v, scale) return { x = v.x * scale, y = v.y * scale, z = v.z * scale } end
local function vector_json(v)
    if not v then return "null" end
    return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', v.x, v.y, v.z)
end

local function snapshot(system, log)
    local entity = player
    local id = field(entity, "id")
    if (type(entity) ~= "table" and type(entity) ~= "userdata") or type(id) ~= "userdata" then
        return "player_missing"
    end
    local get_position = field(entity, "GetWorldPos")
    local get_forward = field(system, "GetViewCameraDir")
    local get_up = field(system, "GetViewCameraUpDir")
    if type(get_position) ~= "function" or type(get_forward) ~= "function" or type(get_up) ~= "function" then
        return "api_missing"
    end
    local function unchanged()
        if not rawequal(player, entity) or not rawequal(field(entity, "id"), id) then return "player_changed" end
        if not rawequal(System, system) or not rawequal(field(system, "LogAlways"), log)
            or not rawequal(field(entity, "GetWorldPos"), get_position)
            or not rawequal(field(system, "GetViewCameraDir"), get_forward)
            or not rawequal(field(system, "GetViewCameraUpDir"), get_up) then return "api_error" end
    end
    local before = copy_vector(get_position(entity), POSITION_LIMIT)
    if not before then return "position_invalid" end
    local changed = unchanged()
    if changed then return changed end
    local forward = copy_vector(get_forward(), 1.01)
    if not forward then return "vector_invalid" end
    changed = unchanged()
    if changed then return changed end
    local up = copy_vector(get_up(), 1.01)
    if not up then return "vector_invalid" end
    changed = unchanged()
    if changed then return changed end
    local after = copy_vector(get_position(entity), POSITION_LIMIT)
    if not after then return "position_invalid" end
    changed = unchanged()
    if changed then return changed end
    local dx, dy, dz = after.x - before.x, after.y - before.y, after.z - before.z
    if dx * dx + dy * dy + dz * dz > MAX_MOVE_SQUARED then return "player_moved" end
    local fl, ul = norm(forward), norm(up)
    if fl < 0.99 or fl > 1.01 or ul < 0.99 or ul > 1.01 then return "vector_nonunit" end
    if math.abs(dot(forward, up)) > 0.01 then return "vector_not_orthogonal" end
    local f, u = scaled(forward, 1 / fl), scaled(up, 1 / ul)
    local horizontal = math.sqrt(f.x * f.x + f.y * f.y)
    if horizontal < 0.01 then return "vertical_view" end
    -- Normal player camera up is world+Z projected onto the plane normal to
    -- forward. Compare directions, preserving the original unmodified vectors.
    local projected = { x = -f.x * f.z, y = -f.y * f.z, z = 1 - f.z * f.z }
    projected = scaled(projected, 1 / norm(projected))
    if dot(u, projected) < MIN_ROLL_COSINE then return "rolled_view" end
    return "ok", before, forward, up
end

function MineCome.SampleInputView(run)
    local valid_run = type(run) == "string" and #run == 32 and run:match("^[0-9a-f]+$") ~= nil
    local system = System
    local log = field(system, "LogAlways")
    if type(log) ~= "function" then return false, "api_missing" end
    local reason, position, forward, up
    if not valid_run then reason = "invalid_run"
    else
        local ok
        ok, reason, position, forward, up = pcall(snapshot, system, log)
        if not ok then reason, position, forward, up = "api_error", nil, nil, nil end
    end
    local valid = reason == "ok"
    if not valid then position, forward, up = nil, nil, nil end
    local json = '{"schema":1,"run":"' .. (valid_run and run or "") .. '","valid":' .. tostring(valid)
        .. ',"reason":"' .. reason .. '","player":' .. vector_json(position)
        .. ',"forward":' .. vector_json(forward) .. ',"up":' .. vector_json(up) .. '}'
    local logged, result = pcall(log, "[MineComeInputView] " .. json)
    return valid and logged and result ~= false, reason
end
