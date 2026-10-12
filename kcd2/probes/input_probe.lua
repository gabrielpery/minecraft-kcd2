-- SPDX-License-Identifier: GPL-3.0-or-later
-- Original explicitly invoked temporary observer of the current Lua callback.
-- Installed official KCD2Mod 1.5.5 Data/Scripts.pak primary source:
-- Scripts/Entities/actor/player.lua:108-118 defines Player:OnAction(action,
-- activation,value), forwards to game rules and tests activation == "press".
-- Its comment says delivery currently covers ui_back/ui_start_pause. Seeing
-- this wrapper load does not prove physical movement/camera action delivery.
-- Entry SHA256: 93e909bbd2c96f49bd9b1c3222e74a24e61da5bbc9605b24e01a8d45e3104d70.
-- Warhorse binding dump pinned at kcd2-mod-docs commit
-- 9cb067543245ec5cf4e27b3d21e32485a35db518, script_bind_2025_01_14:
-- CScriptBindScript__SetTimerForFunction@IFunctionHandler__@int@char__.html:85-112
-- documents userData, update during pause, named callback and optional nil id.
-- No automatic start, action-map/listener changes, bindings, input simulation,
-- position/entity writes or persistent configuration. Only the exact captured
-- player's raw OnAction field is temporarily replaced and conditionally restored.

MineCome = MineCome or {}
MineCome._input_probe = MineCome._input_probe or { serial = 0 }
local state = MineCome._input_probe
state.probe_format = "player_action_probe_v1"
local MAX_EVENTS, LEASE_MS = 128, 15000
local actions = {
    moveforward = true, moveback = true, moveleft = true, moveright = true,
    jump = true, sprint = true, xi_movex = true, xi_movey = true,
    rotateyaw = true, rotatepitch = true, xi_rotateyaw = true, xi_rotatepitch = true,
    ui_start_pause = true, ui_back = true
}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function valid_token(token)
    return type(token) == "string" and #token >= 1 and #token <= 64
        and string.match(token, "^[0-9a-fA-F]+$") ~= nil
end

local function emit(line)
    if not System or type(System.LogAlways) ~= "function" then return false end
    local ok, result = pcall(System.LogAlways, line)
    return ok and result ~= false
end

local function receipt(token, event, result, events, restored, lease_ms)
    local lease_field = event == "begin" and (',"lease_ms":' .. tostring(lease_ms or 15000)) or ""
    return emit(string.format(
        '[MineComeActionProbeSession] {"schema":1,"run":"%s","event":"%s","result":"%s","events":%d,"callback_restored":%s%s}',
        token, event, result, events or 0, tostring(not not restored), lease_field))
end

local function finish(record, event, result)
    if record.done then return record.restored end
    record.done = true
    -- Never target a replacement player or overwrite another owner's handler.
    local restored = false
    if record.installed and rawget(record.player, "OnAction") == record.wrapper then
        rawset(record.player, "OnAction", record.old_raw)
        restored = true
    end
    record.restored = restored
    if state.active == record then state.active = nil end
    state.last = { token = record.token, events = record.events, restored = restored }
    receipt(record.token, event, result, record.events, restored)
    return restored
end

-- Timer data identifies only its own installation. Old timers cannot end a
-- later probe, and loading this module again preserves active wrapper ownership.
function MineCome_InputProbeLease(data, timerId)
    local record = state.active
    if type(data) ~= "table" or not record or record.done or data.run ~= record.token
        or data.serial ~= record.serial then return end
    finish(record, "expired", "ended")
end

function MineCome.BeginInputProbe(token, seconds)
    if not valid_token(token) then return false, "invalid_run" end
    if seconds == nil then seconds = 15 end
    if not finite(seconds) or seconds < 15 or seconds > 60 or seconds ~= math.floor(seconds) then
        return false, "invalid_lease"
    end
    local lease_ms = seconds * 1000
    if not System or type(System.LogAlways) ~= "function" then return false, "log_unavailable" end
    if state.active then
        local result = state.active.token == token and "already_active" or "rejected_active"
        receipt(token, "begin", result, state.active.events, false, state.active.lease_ms or LEASE_MS)
        return result == "already_active", result
    end
    if type(player) ~= "table" or player.id == nil or type(player.GetWorldPos) ~= "function" then
        receipt(token, "begin", "rejected_world", 0, false, lease_ms); return false, "rejected_world"
    end
    local captured, captured_id = player, player.id
    local ok, value = pcall(function() return captured:GetWorldPos() end)
    if not ok or type(value) ~= "table" or not finite(value.x) or not finite(value.y) or not finite(value.z)
        or math.abs(value.x) > 10000000 or math.abs(value.y) > 10000000 or math.abs(value.z) > 10000000
        or player ~= captured or captured.id ~= captured_id then
        receipt(token, "begin", "rejected_world", 0, false, lease_ms); return false, "rejected_world"
    end
    local old_raw = rawget(captured, "OnAction")
    local callback_ok, original = pcall(function() return captured.OnAction end)
    if not callback_ok or type(original) ~= "function" then
        receipt(token, "begin", "rejected_callback", 0, false, lease_ms); return false, "rejected_callback"
    end
    if not Script or type(Script.SetTimerForFunction) ~= "function" then
        receipt(token, "begin", "rejected_timer", 0, false, lease_ms); return false, "rejected_timer"
    end
    if not finite(state.serial) or state.serial < 0 or state.serial ~= math.floor(state.serial)
        or state.serial >= 16777215 then
        receipt(token, "begin", "rejected_generation", 0, false, lease_ms); return false, "rejected_generation"
    end
    state.serial = state.serial + 1
    local record = { token = token, serial = state.serial, player = captured, player_id = captured_id,
        old_raw = old_raw, original = original, events = 0, installed = false, done = false, lease_ms = lease_ms }
    record.wrapper = function(self, ...)
        -- Observation failures never prevent delivery to the original callback.
        -- Its exact self/args, multiple returns and error object propagate directly.
        local action, activation, action_value = ...
        if not record.done and state.active == record then
            if player ~= record.player or record.player.id ~= record.player_id then
                finish(record, "identity_changed", "ended")
            elseif rawget(record.player, "OnAction") ~= record.wrapper then
                finish(record, "handler_replaced", "superseded")
            elseif self == record.player and type(action) == "string" and actions[action] then
                record.events = record.events + 1
                local activation_name = "unknown"
                if activation == "press" or activation == "release" or activation == "hold" then
                    activation_name = activation
                end
                local logged = emit(string.format(
                    '[MineComeActionProbe] {"schema":1,"run":"%s","seq":%d,"action":"%s","activation_type":"%s","activation":"%s","value_type":"%s","value":%s}',
                    record.token, record.events, action, type(activation), activation_name, type(action_value),
                    finite(action_value) and string.format("%.17g", action_value) or "null"))
                if not logged then finish(record, "end", "log_failed")
                elseif record.events >= MAX_EVENTS then finish(record, "event_limit", "ended") end
            end
        end
        return original(self, ...)
    end
    state.active = record
    -- Arm cleanup before installing. Nil is a documented successful timer id.
    local timer_ok, timer = pcall(Script.SetTimerForFunction, lease_ms,
        "MineCome_InputProbeLease", { run = token, serial = record.serial }, true)
    if not timer_ok or timer == false then
        record.done = true
        if state.active == record then state.active = nil end
        receipt(token, "begin", "rejected_timer", 0, false, lease_ms); return false, "rejected_timer"
    end
    if state.active ~= record or record.done then
        receipt(token, "begin", "rejected_expired", 0, false, lease_ms); return false, "rejected_expired"
    end
    local current_ok, current = pcall(function() return captured.OnAction end)
    if player ~= captured or captured.id ~= captured_id or rawget(captured, "OnAction") ~= old_raw
        or not current_ok or current ~= original then
        finish(record, "identity_changed", "ended")
        receipt(token, "begin", "rejected_changed", 0, false, lease_ms); return false, "rejected_changed"
    end
    rawset(captured, "OnAction", record.wrapper)
    record.installed = true
    if not receipt(token, "begin", "started", 0, false, lease_ms) then
        finish(record, "end", "log_failed"); return false, "log_failed"
    end
    return true, "started"
end

function MineCome.EndInputProbe(token)
    if not valid_token(token) then return false, "invalid_run" end
    local record = state.active
    if record and record.token == token then
        local result = rawget(record.player, "OnAction") == record.wrapper and "ended" or "superseded"
        finish(record, "end", result); return true, result
    end
    if not record and state.last and state.last.token == token then
        receipt(token, "end", "ended", state.last.events, state.last.restored)
        return true, "ended"
    end
    receipt(token, "end", record and "rejected_token" or "no_session", 0, false)
    return false, record and "rejected_token" or "no_session"
end
