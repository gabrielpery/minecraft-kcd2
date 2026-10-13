-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explicit bounded intent module. Load the verified aim_probe.lua first.
-- No hooks, timers, entity writes, input generation, or automatic activation.
-- The controller must bind a permit whose acknowledged install predates the
-- physical edge. This captures the camera at the later engine intent callback,
-- not at the original renderer input frame. The guest permit bounds total age.
MineCome = MineCome or {}
local capture = MineCome.CaptureAimSample
assert(type(capture) == "function", "Verified MineCome aim sampler required")
local MAX_ID, PERMIT_SECONDS, MAX_PERMITS = "9007199254740991", 0.5, 16
local state = MineCome._aimed_input
if type(state) ~= "table" then state = {}; MineCome._aimed_input = state end
-- Reload revokes active permits; it never resumes an old lease automatically.
state.active = nil
state.input_format = "aimed_ray_v1"
local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function id(v)
    return type(v) == "string" and #v >= 1 and #v <= #MAX_ID and string.match(v, "^[1-9][0-9]*$")
        and (#v < #MAX_ID or v <= MAX_ID)
end
local function greater(a, b) return #a > #b or (#a == #b and a > b) end
local function run_id(v) return type(v) == "string" and #v == 32 and string.match(v, "^[0-9a-f]+$") end
local function clock()
    if not System or type(System.GetCurrTime) ~= "function" then return nil end
    local ok, value = pcall(System.GetCurrTime)
    if ok and finite(value) and value >= 0 and value <= 1000000000000 then return value end
    return nil
end
local function number(v) return finite(v) and string.format("%.17g", v) or "null" end
local function vector(v)
    if type(v) ~= "table" or not finite(v.x) or not finite(v.y) or not finite(v.z) then return "null" end
    return string.format('{"x":%.17g,"y":%.17g,"z":%.17g}', v.x, v.y, v.z)
end
local function log(line)
    if not System or type(System.LogAlways) ~= "function" then return false end
    local ok, result = pcall(System.LogAlways, line)
    return ok and result ~= false
end
local function invalidate(reason) state.active = nil; return nil, reason end
local function active(run, arena)
    local a = state.active
    if not a or a.run ~= run or a.arena ~= arena then return nil, "session_mismatch" end
    local now = clock()
    if not now then return invalidate("clock_unavailable") end
    if now < a.last_at then return invalidate("clock_reversed") end
    if now >= a.expires then return invalidate("session_expired") end
    if player ~= a.player or not player or player.id ~= a.player_id then return invalidate("world_changed") end
    a.last_at = now
    return a, now
end
local function session_log(a, event, result, now, expires)
    return log(string.format('[MineComeAimSession] {"schema":1,"run":"%s","arena":"%s","event":"%s","result":"%s","engine_time":%s,"expires_engine_time":%s}',
        a.run, a.arena, event, result, number(now), number(expires)))
end
function MineCome.BeginAimedInput(run, arena, seconds)
    if not run_id(run) or not id(arena) then return false, "invalid_identity" end
    if not finite(seconds) or seconds ~= math.floor(seconds) or seconds < 45 or seconds > 180 then return false, "invalid_lease" end
    if state.active then return false, "already_active" end
    if state.last_run == run then return false, "replayed_run" end
    if not player or player.id == nil then return false, "no_world" end
    local now = clock()
    if not now or now + seconds > 1000000000000 then return false, "clock_unavailable" end
    local a = { run = run, arena = arena, player = player, player_id = player.id, started = now, last_at = now,
        expires = now + seconds, permits = {}, permit_count = 0, last_permit = "0", last_click = "0" }
    state.last_run, state.active = run, a
    if not session_log(a, "begin", "accepted", now, a.expires) then
        state.active = nil; return false, "log_failed"
    end
    return true, "accepted"
end
function MineCome.InstallAimedPermit(run, arena, permit)
    if not run_id(run) or not id(arena) or not id(permit) then return false, "invalid_identity" end
    local a, now = active(run, arena)
    if not a then return false, now end
    if not greater(permit, a.last_permit) then return false, "permit_replayed" end
    for key, value in pairs(a.permits) do
        if now - value > PERMIT_SECONDS then a.permits[key] = nil; a.permit_count = a.permit_count - 1 end
    end
    if a.permit_count >= MAX_PERMITS then return false, "permit_capacity" end
    -- Consume IDs before a log binding that may write then raise.
    a.last_permit, a.permits[permit], a.permit_count = permit, now, a.permit_count + 1
    if not log(string.format('[MineComeAimPermit] {"schema":1,"run":"%s","arena":"%s","permit":"%s","result":"installed","engine_time":%s,"expires_engine_time":%s}',
        run, arena, permit, number(now), number(now + PERMIT_SECONDS))) then
        a.permits[permit] = nil; a.permit_count = a.permit_count - 1; return false, "log_failed"
    end
    return true, "installed"
end
function MineCome.AimedIntent(run, arena, permit, click, action)
    if not run_id(run) or not id(arena) or not id(permit) or not id(click) then return false, "invalid_identity" end
    if action ~= 1 and action ~= 2 then return false, "invalid_action" end
    local a, now = active(run, arena)
    if not a then return false, now end
    if not greater(click, a.last_click) then return false, "click_replayed" end
    a.last_click = click
    local installed = a.permits[permit]
    if installed == nil then return false, "permit_unavailable" end
    a.permits[permit] = nil; a.permit_count = a.permit_count - 1
    if now - installed < 0 or now - installed > PERMIT_SECONDS then return false, "permit_expired" end
    local ok, record = pcall(capture)
    if not ok or type(record) ~= "table" then record = { reason = "capture_error" } end
    local current, completed = active(run, arena)
    local known = current == a and record.obstruction_known == true and record.reason == "none"
        and finite(record.engine_time) and finite(record.completed_engine_time)
        and record.engine_time >= now and record.completed_engine_time >= record.engine_time
        and record.completed_engine_time - record.engine_time <= 0.25
        and completed >= record.completed_engine_time and completed - installed <= PERMIT_SECONDS
    local reason = record.reason or "capture_error"
    if current ~= a then reason = completed
    elseif completed - installed > PERMIT_SECONDS then reason = "permit_expired_during_capture"
    elseif record.obstruction_known == true and not known then reason = "capture_time_invalid" end
    if not known then record.origin, record.forward = nil, nil end
    local occlusion = known and (record.result == "no_hit" and 1 or record.result == "hit" and 2 or 0) or 0
    if occlusion == 0 then known = false end
    local distance = occlusion == 2 and record.nearest_distance or 0
    local line = string.format('[MineComeAimInput] {"schema":1,"run":"%s","arena":"%s","request":"%s","permit":"%s","click":"%s","action":%d,"result":"%s","reason":"%s","permit_engine_time":%s,"engine_time":%s,"completed_engine_time":%s,"origin":%s,"direction":%s,"range":4.5,"occlusion":%d,"nearest_distance":%s}',
        run, arena, click, permit, click, action, known and "sampled" or "unavailable", reason, number(installed),
        number(record.engine_time), number(record.completed_engine_time), vector(record.origin), vector(record.forward), occlusion, number(distance))
    if not log(line) then return false, "log_failed" end
    return true, click
end
function MineCome.EndAimedInput(run, arena)
    if not run_id(run) or not id(arena) then return false, "invalid_identity" end
    local a = state.active
    if not a or a.run ~= run or a.arena ~= arena then return false, "session_mismatch" end
    state.active = nil
    if not session_log(a, "end", "ended", clock(), nil) then return false, "log_failed" end
    return true, "ended"
end
