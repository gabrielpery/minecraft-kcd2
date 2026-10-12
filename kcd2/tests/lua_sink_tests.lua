-- SPDX-License-Identifier: GPL-3.0-or-later
-- The original module executes in a real Lua VM; only the engine is simulated.
assert(type(MINECOME_MODULE_PATH) == "string", "runner must supply module path")
local passed = 0
local SESSION = "1800000000000000"
local NEXT_SESSION = "1800000000000001"
local PREVIOUS_SESSION = "1799999999999999"
local MAX_INTEGER = "9007199254740991"

local function equal(actual, expected, message)
    assert(actual == expected, (message or "unexpected value") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function fixture(options)
    options = options or {}
    local f = { now = 0, next_id = 1, entities = {}, names = {}, timers = {}, logs = {},
        spawns = {}, removals = {}, flags = {}, timer_calls = 0, commands = {}, registrations = {},
        command_mode = options.command_mode }
    MineCome = nil
    ENTITY_FLAG_NO_SAVE = nil
    player = { id = 999, position = { x = 0, y = 0, z = 0 } }
    function player:GetWorldPos() return self.position end
    System = {
        LogAlways = function(line) f.logs[#f.logs + 1] = line end,
        GetCurrTime = function() if f.bad_clock then error("clock unavailable") end; return f.now end,
        GetEntityByName = function(name)
            if f.bad_name_lookup then error("name lookup unavailable") end
            return f.names[name]
        end,
        GetEntity = function(id)
            if f.bad_id_lookup then error("id lookup unavailable") end
            return f.entities[id]
        end,
        SpawnEntity = function(params)
            if f.spawn_fails then error("spawn failed") end
            f.spawns[#f.spawns + 1] = params
            local entity = { id = f.next_id, name = params.name }
            f.next_id = f.next_id + 1
            function entity:GetName() return self.name end
            function entity:SetFlags(flag, mode) f.flags[#f.flags + 1] = { flag, mode } end
            function entity:LoadObject(slot, model)
                if f.geometry_fails then error("model unavailable") end
                equal(slot, 0); equal(model, "objects/minecome/stone.cgf")
            end
            function entity:DrawSlot(slot, draw) equal(slot, 0); equal(draw, 1) end
            function entity:GetLocalBBox()
                if f.malformed_bbox then return 3, nil end
                if f.wrong_scale then return { x = 0, y = 0, z = 0 }, { x = 2, y = 2, z = 2 } end
                return { x = 0, y = -1, z = 0 }, { x = 1, y = 0, z = 1 }
            end
            f.entities[entity.id] = entity
            f.names[entity.name] = entity
            if f.spawn_partial then error("spawn callback failed after creation") end
            return entity
        end,
        RemoveEntity = function(id)
            f.removals[#f.removals + 1] = id
            if f.remove_mode == "throw" then error("remove failed") end
            if f.remove_mode == "false" then return false end
            if f.remove_mode == "deferred" then return end
            local entity = f.entities[id]
            if entity and f.names[entity.name] == entity then f.names[entity.name] = nil end
            f.entities[id] = nil
        end
    }
    if not options.no_command_binding then
        System.AddCCommand = function(name, callback, help)
            f.registrations[#f.registrations + 1] = { name = name, callback = callback, help = help }
            if f.command_mode == "throw" then error("command binding unavailable") end
            if f.command_mode == "false" or f.command_mode == name then return false end
            assert(f.commands[name] == nil, "duplicate console registration")
            f.commands[name] = { callback = callback, help = help }
            -- The documented engine binding may return no value on success.
        end
    end
    Script = { SetTimerForFunction = function(delay, callback, data, during_pause)
        f.timer_calls = f.timer_calls + 1
        if f.timer_fails then error("timer failed") end
        equal(delay, 250); equal(callback, "MineCome_BlockLeaseTick")
        equal(type(data), "table"); equal(during_pause, true)
        f.timers[#f.timers + 1] = { name = callback, data = data }
        return f.timer_calls
    end }
    dofile(MINECOME_MODULE_PATH)
    function f:tick(elapsed)
        local timer = table.remove(self.timers, 1)
        assert(timer, "no scheduled callback")
        self.now = self.now + (elapsed == nil and 0.25 or elapsed)
        _G[timer.name](timer.data, 1)
        assert(#self.timers <= 1, "multiple lease timer chains")
    end
    function f:place(sequence, x, px, session)
        if type(sequence) == "number" then sequence = string.format("%.0f", sequence) end
        return MineCome.ApplyStoneEvent(session or SESSION, sequence, 1, x or 0, 64, 0, px or 0, 0, 0)
    end
    function f:remove(sequence, x, session)
        if type(sequence) == "number" then sequence = string.format("%.0f", sequence) end
        return MineCome.ApplyStoneEvent(session or SESSION, sequence, 2, x or 0, 64, 0, 0, 0, 0)
    end
    function f:status() return MineCome.BlockSinkStatus() end
    function f:begin(session) return MineCome.BeginBlockSession(session or SESSION) end
    function f:entity() for _, entity in pairs(self.entities) do return entity end end
    function f:erase_entity(entity)
        if self.names[entity.name] == entity then self.names[entity.name] = nil end
        self.entities[entity.id] = nil
    end
    function f:remove_receipts(sequence, result, session)
        if type(sequence) == "number" then sequence = string.format("%.0f", sequence) end
        local receipts = {}
        for index, line in ipairs(self.logs) do
            if line:find('[MineComeBlock] {"schema":1,"event":"remove"', 1, true)
                and line:find('"sequence":' .. sequence .. ',', 1, true)
                and line:find('"session":' .. (session or SESSION) .. ',', 1, true)
                and line:find('"result":"' .. result .. '"', 1, true) then
                receipts[#receipts + 1] = { index = index, line = line }
            end
        end
        return receipts
    end
    function f:input_receipts()
        local receipts = {}
        for _, line in ipairs(self.logs) do
            if line:find('[MineComeInput] ', 1, true) == 1 then receipts[#receipts + 1] = line end
        end
        return receipts
    end
    function f:console(name)
        local command = assert(self.commands[name], "console command was not registered")
        local compiled = assert((loadstring or load)(command.callback))
        compiled()
    end
    return f
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

test("stone creation uses actual unit asset with physics disabled and receipt bbox", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1, 10, 3))
    local params = f.spawns[1]
    equal(params.class, "BasicEntity"); equal(params.properties.object_Model, "objects/minecome/stone.cgf")
    equal(params.properties.Physics.bPhysicalize, false)
    equal(params.properties.Physics.bRigidBody, false)
    equal(params.properties.Physics.bPushableByPlayers, false)
    equal(#f.flags, 0); equal(f:status().owned_count, 1)
    local log = f.logs[#f.logs]
    assert(log:find('"session":1800000000000000', 1, true))
    assert(log:find('"event":"place"', 1, true))
    assert(log:find('"result":"spawned"', 1, true))
    assert(log:find('"bounds_min":{"x":0,"y":-1,"z":0}', 1, true))
    assert(log:find('"live_draw_verified":false', 1, true))
end)

test("only an exported no-save flag is used", function()
    local f = fixture(); ENTITY_FLAG_NO_SAVE = 123456; assert(f:begin()); assert(f:place(1))
    equal(#f.flags, 1); equal(f.flags[1][1], 123456); equal(f.flags[1][2], 0)
    ENTITY_FLAG_NO_SAVE = "32768"; assert(f:place(2, 1)); equal(#f.flags, 1)
end)

test("duplicate and out-of-order events cannot undo newer state", function()
    local f = fixture(); assert(f:begin()); assert(f:place(3))
    local ok, result = f:remove(2); equal(ok, false); equal(result, "rejected_stale")
    equal(f:status().owned_count, 1); equal(#f.removals, 0)
    equal(f:place(3), false); equal(#f.spawns, 1)
    assert(f:place(4)); equal(#f.spawns, 1)
    assert(f:remove(5)); equal(f:status().owned_count, 0)
    equal(f:place(4), false); equal(f:status().owned_count, 0)
end)

test("string session and sequence preserve every digit at the maximum bound", function()
    local f = fixture(); assert(f:begin(MAX_INTEGER))
    assert(f:place(MAX_INTEGER, -16777215, 0, MAX_INTEGER))
    local line = f.logs[#f.logs]
    assert(line:find('"session":9007199254740991', 1, true))
    assert(line:find('"sequence":9007199254740991', 1, true))
    assert(line:find('"x":-16777215', 1, true))
    equal(f:begin("9007199254740992"), false)
end)

test("duplicate live Begin is idempotent and ended sessions cannot replay", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    assert(f:begin()); equal(f:status().owned_count, 1); equal(#f.timers, 1)
    assert(MineCome.EndBlockSession(SESSION)); equal(f:begin(), false)
    assert(f:begin(NEXT_SESSION)); equal(f:place(2, 0, 0, SESSION), false)
end)

test("malformed arguments cannot spawn or consume valid sequence", function()
    local f = fixture(); assert(f:begin())
    for _, value in ipairs({ 0, -1, 1, 1.5, math.huge, -math.huge, "01", {} }) do
        equal(f:begin(value), false)
        equal(MineCome.ApplyStoneEvent(SESSION, value, 1, 0, 64, 0, 0, 0, 0), false)
    end
    equal(f:begin(0 / 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 3, 0, 64, 0, 0, 0, 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 1, 16777216, 64, 0, 0, 0, 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 1, 0, 64.5, 0, 0, 0, 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 1, 0, 64, 0, math.huge, 0, 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 1, 0, 64, 0, 0 / 0, 0, 0), false)
    equal(MineCome.ApplyStoneEvent(SESSION, "1", 1, 0, 64, 0, "0);bad()", 0, 0), false)
    equal(f:status().last_sequence, "0"); equal(#f.spawns, 0); assert(f:place(1))
end)

test("host radius includes boundary and rejects distant geometry", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1, 0, 32))
    local ok, result = f:place(2, 1, 32.0001)
    equal(ok, false); equal(result, "rejected_radius"); equal(#f.spawns, 1)
    equal(f:place(2, 1, 0), false) -- A valid ordered rejected write still consumed its event.
end)

test("an existing MC cell cannot be silently moved within a session", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1, 0, 2))
    local ok, result = f:place(2, 0, 3)
    equal(ok, false); equal(result, "rejected_origin_change"); equal(#f.spawns, 1)
end)

test("capacity 128 includes pending records from previous sessions", function()
    local f = fixture(); assert(f:begin())
    for i = 1, 128 do assert(f:place(i, i)) end
    local ok, result = f:place(129, 129)
    equal(ok, false); equal(result, "rejected_capacity")
    f.remove_mode = "throw"; equal(MineCome.EndBlockSession(SESSION), false)
    equal(f:status().pending_count, 128)
    assert(f:begin(NEXT_SESSION))
    ok, result = f:place(1, 1, 0, NEXT_SESSION)
    equal(ok, false); equal(result, "rejected_capacity"); equal(f:status().owned_count, 128)
end)

test("bounded cleanup retries fairly with only one timer chain", function()
    local f = fixture(); assert(f:begin())
    for i = 1, 128 do assert(f:place(i, i)) end
    f.remove_mode = "false"; equal(MineCome.EndBlockSession(SESSION), false)
    equal(#f.removals, 16); equal(#f.timers, 1)
    f:tick(); equal(#f.removals, 32); equal(f.removals[17], 17)
    f.remove_mode = nil
    for _ = 1, 8 do f:tick() end
    equal(f:status().owned_count, 0); equal(#f.timers, 0)
    assert(f.logs[#f.logs]:find('"event":"cleanup"', 1, true))
    assert(f.logs[#f.logs]:find('"result":"ended"', 1, true))
end)

test("deferred removal retains ownership until absence is confirmed", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    f.remove_mode = "deferred"
    local ok, result = f:remove(2)
    equal(ok, false); equal(result, "cleanup_pending"); equal(f:status().owned_count, 1)
    f.remove_mode = nil; f:tick(); equal(f:status().owned_count, 0)
    assert(f:remove(3)); equal(#f.removals, 2)
end)

test("pending same-cell removal defers replacement and never reports absent", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1)); f.remove_mode = "deferred"
    local ok, result = f:remove(2)
    equal(ok, false); equal(result, "cleanup_pending")
    ok, result = f:place(3)
    equal(ok, false); equal(result, "cleanup_pending"); equal(#f.spawns, 1)
    ok, result = f:remove(4)
    equal(ok, false); equal(result, "rejected_pending"); equal(f:status().owned_count, 1)
    f.remove_mode = nil; assert(f:place(5)); equal(#f.spawns, 2); equal(f:status().owned_count, 1)
end)

test("remove targets its exact cell immediately at full capacity", function()
    local f = fixture(); assert(f:begin())
    for i = 1, 128 do assert(f:place(i, i)) end
    assert(f:remove(129, 128)); equal(#f.removals, 1); equal(f.removals[1], 128)
    equal(f:status().owned_count, 127)
end)

test("lookup failure never authorizes removal or forgets ownership", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    f.bad_id_lookup = true; equal(MineCome.EndBlockSession(SESSION), false)
    equal(#f.removals, 0); equal(f:status().owned_count, 1)
    f.bad_id_lookup = nil; f:tick(); equal(f:status().owned_count, 0)
end)

test("foreign name collision and reused id are preserved", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    local own = f:entity(); local foreign = { id = 456, name = own.name }
    f.names[own.name] = foreign
    equal(MineCome.EndBlockSession(SESSION), false); equal(#f.removals, 0)
    f:tick(); equal(#f.removals, 0)
    f.entities[own.id] = nil; f:tick(); equal(f:status().owned_count, 0)
    equal(f.names[own.name], foreign); equal(#f.removals, 0)

    f = fixture(); assert(f:begin()); assert(f:place(1)); own = f:entity()
    f.names[own.name] = nil
    f.entities[own.id] = { id = own.id, name = "Foreign_ReusedId" }
    equal(MineCome.EndBlockSession(SESSION), false); equal(#f.removals, 0)
    f.entities[own.id] = nil; f:tick(); equal(f:status().owned_count, 0)
end)

test("reserved unique spawn name is never overwritten", function()
    local f = fixture(); assert(f:begin())
    local name = "MineCome_Block_1800000000000000_1"
    f.names[name] = { id = 77, name = name }
    local ok, result = f:place(1)
    equal(ok, false); equal(result, "rejected_name"); equal(#f.spawns, 0); equal(#f.removals, 0)
end)

test("geometry failure remains tracked when removal also fails", function()
    local f = fixture(); assert(f:begin()); f.geometry_fails = true; f.remove_mode = "throw"
    local ok, result = f:place(1)
    equal(ok, false); equal(result, "geometry_failed"); equal(f:status().pending_count, 1)
    f.remove_mode = nil; f:tick(); equal(f:status().owned_count, 0)
    f.geometry_fails = nil; assert(f:place(2)); equal(#f.spawns, 2)
end)

test("malformed and wrong-scale bbox withhold success receipts", function()
    for _, mode in ipairs({ "malformed_bbox", "wrong_scale" }) do
        local f = fixture(); assert(f:begin()); f[mode] = true
        local ok, result = f:place(1)
        equal(ok, false); equal(result, "geometry_failed"); equal(f:status().owned_count, 0)
    end
end)

test("engine creation failure never acknowledges a spawn", function()
    local f = fixture(); assert(f:begin()); f.spawn_fails = true
    local ok, result = f:place(1)
    equal(ok, false); equal(result, "spawn_failed"); equal(f:status().owned_count, 0)
end)

test("partial failed spawn retains provenance for cleanup retries", function()
    local f = fixture(); assert(f:begin()); f.spawn_partial = true; f.remove_mode = "throw"
    local ok, result = f:place(1)
    equal(ok, false); equal(result, "spawn_failed"); equal(f:status().pending_count, 1)
    f.remove_mode = nil; f:tick(); equal(f:status().owned_count, 0)
end)

test("already-present acknowledgement requires a currently owned entity", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    local own = f:entity(); f.entities[own.id] = nil; f.names[own.name] = nil
    assert(f:place(2)); equal(#f.spawns, 2); equal(f:status().owned_count, 1)
    own = f:entity(); f.names[own.name] = { id = 123, name = own.name }
    local ok, result = f:place(3)
    equal(ok, false); equal(result, "rejected_ownership"); equal(#f.spawns, 2)
end)

test("six-second lease expires and cleans up without heartbeat", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    for _ = 1, 23 do f:tick() end
    equal(f:status().active_session, SESSION); equal(f:status().owned_count, 1)
    f:tick(); equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
    equal(f:begin(), false)
end)

test("real elapsed time catches delayed timer callback", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    f:tick(7); equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
end)

test("heartbeat extends lease but another session cannot extend it", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    for _ = 1, 20 do f:tick() end
    assert(MineCome.HeartbeatBlockSession(SESSION)); equal(MineCome.HeartbeatBlockSession(NEXT_SESSION), false)
    for _ = 1, 20 do f:tick() end
    equal(f:status().active_session, SESSION)
    for _ = 1, 4 do f:tick() end
    equal(f:status().active_session, nil)
end)

test("fallback timer lease expires when engine clock is unavailable or paused", function()
    for _, mode in ipairs({ "paused", "unavailable" }) do
        local f = fixture(); if mode == "unavailable" then f.bad_clock = true end
        assert(f:begin()); assert(f:place(1))
        for _ = 1, 24 do f:tick(0) end
        equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
    end
end)

test("world loss and player replacement immediately end ownership session", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1)); player = nil; f:tick()
    equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
    f = fixture(); assert(f:begin()); assert(f:place(1)); player.id = 1000
    equal(MineCome.HeartbeatBlockSession(SESSION), false)
    f:tick(); equal(f:status().owned_count, 0)
end)

test("walking away schedules out-of-radius cells for removal", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1)); player.position.x = 33
    f:tick(); equal(f:status().active_session, SESSION); equal(f:status().owned_count, 0)
end)

test("old-session End cannot delete newer-session entity", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    assert(f:begin(NEXT_SESSION)); assert(f:place(1, 0, 0, NEXT_SESSION))
    local entity = f:entity(); assert(MineCome.EndBlockSession(SESSION))
    equal(f:entity(), entity); equal(f:status().active_session, NEXT_SESSION)
end)

test("module reload preserves owned entities, session high-water and timer", function()
    local f = fixture(); assert(f:begin()); assert(f:place(1))
    dofile(MINECOME_MODULE_PATH)
    equal(f:status().owned_count, 1); equal(f:status().last_session, SESSION)
    assert(f:begin()); equal(#f.timers, 1); assert(MineCome.EndBlockSession(SESSION))
    equal(f:begin(PREVIOUS_SESSION), false)
end)

test("timer failure prevents Begin and fail-closes active writes", function()
    local f = fixture(); f.timer_fails = true
    equal(f:begin(), false); equal(f:status().active_session, nil); equal(#f.spawns, 0)
    f.timer_fails = nil; assert(f:begin()); assert(f:place(1)); f.timer_fails = true
    f:tick(); equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
end)

test("engine clock regression fail-closes the session", function()
    local f = fixture(); f.now = 10; assert(f:begin()); assert(f:place(1))
    f.now = 9; f:tick(0); equal(f:status().active_session, nil); equal(f:status().owned_count, 0)
end)

test("canonical string ids preserve adjacent live timestamp digits", function()
    local f = fixture()
    local first, second = "1791733572711306", "1791733572711307"
    assert(f:begin(first)); assert(f:place("9007199254740990", 1, 0, first))
    equal(type(f:status().active_session), "string")
    equal(type(f:status().last_sequence), "string")
    assert(f.logs[#f.logs]:find('"session":1791733572711306', 1, true))
    assert(f.logs[#f.logs]:find('"sequence":9007199254740990', 1, true))
    assert(f:begin(second)); equal(f:begin(first), false)
    equal(f:status().active_session, second)
    assert(f:place(MAX_INTEGER, 1, 0, second))
    equal(f:place("9007199254740990", 1, 0, second), false)
end)

test("decimal ordering handles carry boundaries and unequal digit lengths", function()
    local f = fixture(); assert(f:begin("9")); assert(f:place("9", 0, 0, "9"))
    assert(f:place("10", 1, 0, "9")); equal(f:remove("2", 1, "9"), false)
    assert(f:remove("99", 1, "9")); assert(f:place("100", 1, 0, "9"))
    assert(f:begin("10")); equal(f:begin("9"), false); equal(f:begin("2"), false)
    assert(f:begin("99")); assert(f:begin("100")); equal(f:begin("99"), false)
    equal(f:status().active_session, "100")
end)

test("noncanonical and injected id strings never reach logs or writes", function()
    local f = fixture(); assert(f:begin())
    local invalid = { "", "0", "00", "01", "+1", "-1", "1.0", "1e3", " 1", "1 ", "1\n", "1\000",
        "1);bad()", "9007199254740992", "10000000000000000", string.rep("9", 1000), true, false, {}, 1 }
    for _, value in ipairs(invalid) do
        equal(MineCome.BeginBlockSession(value), false)
        equal(MineCome.HeartbeatBlockSession(value), false)
        equal(MineCome.EndBlockSession(value), false)
        equal(MineCome.ApplyStoneEvent(SESSION, value, 1, 0, 64, 0, 0, 0, 0), false)
        equal(MineCome.ApplyStoneEvent(value, "1", 1, 0, 64, 0, 0, 0, 0), false)
    end
    equal(f:status().last_sequence, "0"); equal(#f.spawns, 0)
    for _, line in ipairs(f.logs) do assert(not line:find("bad()", 1, true)) end
    assert(f:place("1")); equal(f:status().last_session, SESSION)
end)

test("Minecraft coordinates stay within the live float32 exact integer range", function()
    local f = fixture(); assert(f:begin())
    assert(MineCome.ApplyStoneEvent(SESSION, "1", 1, 16777215, -16777215, 16777215, 0, 0, 0))
    for _, value in ipairs({ 16777216, -16777216, 16777217, -16777217 }) do
        equal(MineCome.ApplyStoneEvent(SESSION, "2", 1, value, 0, 0, 0, 0, 0), false)
        equal(MineCome.ApplyStoneEvent(SESSION, "2", 1, 0, value, 0, 0, 0, 0), false)
        equal(MineCome.ApplyStoneEvent(SESSION, "2", 1, 0, 0, value, 0, 0, 0), false)
    end
    equal(f:status().last_sequence, "1"); equal(#f.spawns, 1)
end)

test("legacy rounded numeric high-water migrates without guessing lost digits", function()
    local f = fixture(); local state = MineCome._block_sink
    state.last_session = 1791733520138240; state.serial = 0; state.token_format = nil
    dofile(MINECOME_MODULE_PATH)
    equal(state.last_session, "1791733520138240"); equal(state.serial, "0")
    equal(state.token_format, "decimal_text_v1")
    equal(f:begin("1791733520138240"), false)
    assert(f:begin("1791733572711306"))
    equal(f:status().active_session, "1791733572711306")
end)

test("legacy active numeric ids migrate while preserving exact entity provenance", function()
    local f = fixture(); assert(f:begin()); assert(f:place("116", 3))
    local state, entity = MineCome._block_sink, f:entity()
    local name, id = entity.name, entity.id
    state.last_session = 1800000000000000; state.serial = 1; state.token_format = nil
    state.active.session = 1800000000000000; state.active.sequence = 116
    state.owned[1].session = 1800000000000000
    dofile(MINECOME_MODULE_PATH)
    equal(state.active.session, SESSION); equal(state.active.sequence, "116")
    equal(state.owned[1].session, SESSION); equal(state.owned[1].name, name); equal(state.owned[1].id, id)
    equal(#f.timers, 1); assert(f:begin()); assert(f:remove("117", 3))
    equal(f:status().owned_count, 0); equal(f.removals[1], id)
end)

test("legacy pending numeric groups survive migration and still require cleanup", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1")); f.remove_mode = "throw"
    equal(MineCome.EndBlockSession(SESSION), false)
    local state, entity = MineCome._block_sink, f:entity()
    local name, id = entity.name, entity.id
    state.last_session = 1800000000000000; state.serial = 1; state.token_format = nil
    state.owned[1].session = 1800000000000000
    state.ending = { [1800000000000000] = true }
    dofile(MINECOME_MODULE_PATH)
    equal(state.owned[1].session, SESSION); equal(state.ending[SESSION], true)
    equal(state.owned[1].name, name); equal(state.owned[1].id, id)
    equal(MineCome.EndBlockSession(SESSION), false); equal(f:status().pending_count, 1)
    f.remove_mode = nil; f:tick(); equal(f:status().owned_count, 0)
    assert(f.logs[#f.logs]:find('"session":1800000000000000', 1, true))
    assert(f.logs[#f.logs]:find('"result":"ended"', 1, true))
end)

test("string serial carry keeps private entity names unique without numeric coercion", function()
    local f = fixture(); assert(f:begin()); MineCome._block_sink.serial = "999"
    assert(f:place("1")); equal(f:entity().name, "MineCome_Block_1800000000000000_1000")
    MineCome._block_sink.serial = MAX_INTEGER
    local ok, result = f:place("2", 1)
    equal(ok, false); equal(result, "rejected_serial"); equal(#f.spawns, 1)
end)

test("deferred engine deletion eventually acknowledges the original remove metadata once", function()
    local f = fixture(); assert(f:begin()); assert(f:place("120", -5))
    local entity = f:entity(); f.remove_mode = "deferred"
    local ok, result = MineCome.ApplyStoneEvent(SESSION, "441", 2, -5, 64, 0, 123.25, 2044.5, 56.125)
    equal(ok, false); equal(result, "cleanup_pending")
    equal(#f:remove_receipts("441", "removed"), 0)
    f:tick(); f:tick(); equal(f:status().owned_count, 1)
    equal(#f:remove_receipts("441", "removed"), 0)
    f:erase_entity(entity); f:tick()
    equal(f:status().owned_count, 0)
    local receipts = f:remove_receipts("441", "removed")
    equal(#receipts, 1)
    assert(receipts[1].line:find('"mc":{"x":-5,"y":64,"z":0}', 1, true))
    assert(receipts[1].line:find('"position":{"x":123.25,"y":2044.5,"z":56.125}', 1, true))
    f:tick(); equal(#f:remove_receipts("441", "removed"), 1)
end)

test("End preserves pending remove ACK and cleanup receipt follows confirmed removal", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1"))
    local entity = f:entity(); f.remove_mode = "deferred"
    equal(f:remove("2"), false); equal(MineCome.EndBlockSession(SESSION), false)
    equal(#f:remove_receipts("2", "removed"), 0); equal(f:status().pending_count, 1)
    f:erase_entity(entity); f:tick()
    local receipts = f:remove_receipts("2", "removed")
    equal(#receipts, 1); equal(f:status().owned_count, 0)
    assert(f.logs[#f.logs]:find('"event":"cleanup"', 1, true))
    assert(receipts[1].index < #f.logs)
    assert(MineCome.EndBlockSession(SESSION)); assert(MineCome.EndBlockSession(SESSION))
    equal(#f:remove_receipts("2", "removed"), 1)
end)

test("lease expiry retains pending event until real entity absence", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1"))
    local entity = f:entity(); f.remove_mode = "deferred"; equal(f:remove("2"), false)
    f:tick(7); equal(f:status().active_session, nil); equal(f:status().pending_count, 1)
    equal(#f:remove_receipts("2", "removed"), 0)
    f:erase_entity(entity); f:tick(); equal(#f:remove_receipts("2", "removed"), 1)
    equal(f:status().owned_count, 0)
    assert(f.logs[#f.logs]:find('"event":"cleanup"', 1, true))
end)

test("reconnect ACK keeps old provenance and cannot retire new-session entity", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1"))
    local old_entity = f:entity(); f.remove_mode = "deferred"; equal(f:remove("2"), false)
    assert(f:begin(NEXT_SESSION)); assert(f:place("1", 0, 0, NEXT_SESSION))
    f:erase_entity(old_entity); f:tick()
    equal(#f:remove_receipts("2", "removed", SESSION), 1)
    equal(#f:remove_receipts("2", "removed", NEXT_SESSION), 0)
    equal(f:status().active_session, NEXT_SESSION); equal(f:status().owned_count, 1)
end)

test("newer concurrent remove cannot overwrite the original pending event", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1"))
    local entity = f:entity(); f.remove_mode = "deferred"
    equal(f:remove("2"), false)
    local ok, result = f:remove("3"); equal(ok, false); equal(result, "rejected_pending")
    ok, result = f:remove("2"); equal(ok, false); equal(result, "rejected_stale")
    f:erase_entity(entity); f:tick()
    equal(#f:remove_receipts("2", "removed"), 1); equal(#f:remove_receipts("3", "removed"), 0)
end)

test("module reload retains pending event metadata and the single cleanup timer", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1"))
    local entity = f:entity(); f.remove_mode = "deferred"; equal(f:remove("2"), false)
    dofile(MINECOME_MODULE_PATH); equal(#f.timers, 1)
    equal(MineCome._block_sink.owned[1].remove_ack.sequence, "2")
    f:erase_entity(entity); f:tick(); equal(#f:remove_receipts("2", "removed"), 1)
end)

test("synchronous removal produces one completion receipt without a deferred duplicate", function()
    local f = fixture(); assert(f:begin()); assert(f:place("1")); assert(f:remove("2"))
    equal(#f:remove_receipts("2", "removed"), 1)
    f:tick(); assert(MineCome.EndBlockSession(SESSION))
    equal(#f:remove_receipts("2", "removed"), 1)
end)

test("documented commands register fixed global callbacks without binding keys", function()
    local f = fixture()
    equal(#f.registrations, 2)
    equal(f.registrations[1].name, "minecome_place")
    equal(f.registrations[1].callback, "MineCome.InteractiveIntent(1)")
    equal(f.registrations[2].name, "minecome_break")
    equal(f.registrations[2].callback, "MineCome.InteractiveIntent(2)")
    for _, command in ipairs(f.registrations) do
        assert(command.help:find("real Minecraft", 1, true))
    end
    equal(MineCome._interactive_input.input_format, "stone_action_v1")
    equal(MineCome._interactive_input.commands_registered, true)
    equal(MineCome._interactive_input.last_request, "0")
    equal(#f.spawns, 0); equal(#f.removals, 0); equal(#f.timers, 0)
    assert(f.logs[1]:find('"commands_registered":true', 1, true))
    assert(f.logs[1]:find('"live_input_verified":false', 1, true))
end)

test("console callbacks emit only canonical ordered intents with a shared rate limit", function()
    local f = fixture()
    f:console("minecome_place")
    equal(f:input_receipts()[1], '[MineComeInput] {"schema":1,"request":1,"action":1}')
    f.now = 0.249; f:console("minecome_break"); equal(#f:input_receipts(), 1)
    f.now = 0.25; f:console("minecome_break")
    equal(f:input_receipts()[2], '[MineComeInput] {"schema":1,"request":2,"action":2}')
    f.now = 0.5; f:console("minecome_place")
    equal(f:input_receipts()[3], '[MineComeInput] {"schema":1,"request":3,"action":1}')
    equal(MineCome._interactive_input.last_request, "3")
    equal(#f.spawns, 0); equal(#f.removals, 0); equal(#f.timers, 0)
end)

test("invalid interactive actions and absent world do not consume requests", function()
    local f = fixture()
    for _, action in ipairs({ 0, 3, -1, 1.5, "1", "2", {}, false, true, math.huge }) do
        local ok, reason = MineCome.InteractiveIntent(action)
        equal(ok, false); equal(reason, "invalid_action")
    end
    equal(MineCome.InteractiveIntent(nil), false)
    local live_player = player; player = nil
    local ok, reason = MineCome.InteractiveIntent(1)
    equal(ok, false); equal(reason, "no_world")
    player = { GetWorldPos = function() error("world unloaded") end }
    equal(MineCome.InteractiveIntent(2), false)
    player = { GetWorldPos = function() return { x = math.huge, y = 0, z = 0 } end }
    equal(MineCome.InteractiveIntent(1), false)
    equal(MineCome._interactive_input.last_request, "0"); equal(#f:input_receipts(), 0)
    player = live_player; assert(MineCome.InteractiveIntent(1))
    equal(MineCome._interactive_input.last_request, "1")
end)

test("interactive engine clock availability and regression fail closed", function()
    local f = fixture(); f.bad_clock = true
    local ok, reason = MineCome.InteractiveIntent(1)
    equal(ok, false); equal(reason, "clock_unavailable")
    f.bad_clock = nil; f.now = math.huge; equal(MineCome.InteractiveIntent(1), false)
    f.now = 10; assert(MineCome.InteractiveIntent(1))
    f.now = 9; ok, reason = MineCome.InteractiveIntent(2)
    equal(ok, false); equal(reason, "rate_limited")
    f.now = 10.249; equal(MineCome.InteractiveIntent(2), false)
    f.now = 10.25; assert(MineCome.InteractiveIntent(2))
    equal(#f:input_receipts(), 2); equal(MineCome._interactive_input.last_request, "2")
end)

test("interactive decimal request carry and maximum avoid numeric rounding", function()
    local f = fixture(); local state = MineCome._interactive_input
    state.last_request = "999"; assert(MineCome.InteractiveIntent(1))
    equal(state.last_request, "1000")
    equal(f:input_receipts()[1], '[MineComeInput] {"schema":1,"request":1000,"action":1}')
    state.last_request = "9007199254740990"; f.now = 0.25
    assert(MineCome.InteractiveIntent(2)); equal(state.last_request, MAX_INTEGER)
    equal(f:input_receipts()[2], '[MineComeInput] {"schema":1,"request":9007199254740991,"action":2}')
    f.now = 0.5; local ok, reason = MineCome.InteractiveIntent(1)
    equal(ok, false); equal(reason, "request_exhausted")
    equal(state.last_request, MAX_INTEGER); equal(#f:input_receipts(), 2)
end)

test("corrupt interactive request tokens cannot enter JSON or reset the high-water mark", function()
    local f = fixture(); local state = MineCome._interactive_input
    for _, value in ipairs({ "", "00", "01", "+1", "-1", "1.0", "1e3", "1\n", "1);bad()",
        "9007199254740992", 1, false, true, {} }) do
        state.last_request = value
        local ok, reason = MineCome.InteractiveIntent(1)
        equal(ok, false); equal(reason, "request_invalid"); equal(state.last_request, value)
    end
    equal(#f:input_receipts(), 0)
    state.last_request = "0"; assert(MineCome.InteractiveIntent(1))
    equal(state.last_request, "1")
end)

test("interactive module reload retains counter and rate gate with global callback indirection", function()
    local f = fixture(); f:console("minecome_place")
    local state, previous_function = MineCome._interactive_input, MineCome.InteractiveIntent
    dofile(MINECOME_MODULE_PATH)
    equal(MineCome._interactive_input, state); equal(state.last_request, "1")
    assert(MineCome.InteractiveIntent ~= previous_function)
    equal(#f.registrations, 2); equal(state.commands_registered, true)
    f:console("minecome_break"); equal(#f:input_receipts(), 1)
    local current_function, called = MineCome.InteractiveIntent, 0
    MineCome.InteractiveIntent = function(action)
        called = called + 1; return current_function(action)
    end
    f.now = 0.25; f:console("minecome_break")
    equal(called, 1); equal(state.last_request, "2"); equal(#f:input_receipts(), 2)
end)

test("interactive intents leave active display session entities and lease unchanged", function()
    local f = fixture(); assert(f:begin()); assert(f:place("100"))
    local state, entity = MineCome._block_sink, f:entity()
    local active, refreshed_at, refreshed_tick = state.active, state.active.refreshed_at, state.active.refreshed_tick
    local serial, timer_calls = state.serial, f.timer_calls
    assert(MineCome.InteractiveIntent(1)); f.now = 0.25; assert(MineCome.InteractiveIntent(2))
    equal(state.active, active); equal(state.active.sequence, "100")
    equal(state.active.refreshed_at, refreshed_at); equal(state.active.refreshed_tick, refreshed_tick)
    equal(state.serial, serial); equal(f:entity(), entity); equal(f:status().owned_count, 1)
    equal(#f.spawns, 1); equal(#f.removals, 0); equal(#f.flags, 0)
    equal(f.timer_calls, timer_calls); equal(#f.timers, 1)
end)

test("unavailable command binding reports capability absence and can retry on reload", function()
    local f = fixture({ no_command_binding = true })
    equal(MineCome._interactive_input.commands_registered, false); equal(#f.registrations, 0)
    assert(f.logs[1]:find('"function_available":false', 1, true))
    assert(f.logs[1]:find('"result":"unavailable"', 1, true))
    System.AddCCommand = function(name, callback, help)
        f.registrations[#f.registrations + 1] = { name = name, callback = callback, help = help }
        f.commands[name] = { callback = callback, help = help }
    end
    dofile(MINECOME_MODULE_PATH)
    equal(MineCome._interactive_input.commands_registered, true); equal(#f.registrations, 2)
end)

test("failed registration never claims both commands and retries only missing names", function()
    local f = fixture({ command_mode = "minecome_break" })
    equal(MineCome._interactive_input.commands_registered, false)
    equal(MineCome._interactive_input.registered_commands.minecome_place, true)
    equal(MineCome._interactive_input.registered_commands.minecome_break, nil)
    assert(f.logs[1]:find('"result":"failed"', 1, true))
    f.command_mode = nil; dofile(MINECOME_MODULE_PATH)
    equal(MineCome._interactive_input.commands_registered, true); equal(#f.registrations, 3)
    equal(f.registrations[3].name, "minecome_break")
    dofile(MINECOME_MODULE_PATH); equal(#f.registrations, 3)
    for _, mode in ipairs({ "throw", "false" }) do
        f = fixture({ command_mode = mode })
        equal(MineCome._interactive_input.commands_registered, false)
        f.command_mode = nil; dofile(MINECOME_MODULE_PATH)
        equal(MineCome._interactive_input.commands_registered, true); equal(#f.registrations, 4)
    end
end)

test("failed interactive logging consumes a possibly emitted ID without retrying it", function()
    local f = fixture(); local original_log = System.LogAlways
    System.LogAlways = function(line) original_log(line); error("partial log failure") end
    local ok, reason = MineCome.InteractiveIntent(1)
    equal(ok, false); equal(reason, "log_failed")
    equal(MineCome._interactive_input.last_request, "1")
    System.LogAlways = original_log; f.now = 0.25; assert(MineCome.InteractiveIntent(2))
    equal(f:input_receipts()[2], '[MineComeInput] {"schema":1,"request":2,"action":2}')
    System.LogAlways = nil; f.now = 0.5
    ok, reason = MineCome.InteractiveIntent(1)
    equal(ok, false); equal(reason, "log_unavailable")
    equal(MineCome._interactive_input.last_request, "2")
end)

print(string.format("Verified %d standalone sink/input lifecycle cases in %s", passed, _VERSION))
