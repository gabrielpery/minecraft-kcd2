-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua5.2 runtime; simulated getter values, not live view/engine proof.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local RUN = "0123456789abcdef0123456789abcdef"
local function eq(a, b) assert(a == b, "got " .. tostring(a) .. ", expected " .. tostring(b)) end
local function test(name, fn)
    local ok, error_message = pcall(fn)
    if not ok then error(name .. ": " .. tostring(error_message), 0) end
    passed = passed + 1; print("PASS " .. name)
end
local function fixture()
    local f = { logs = {}, calls = { position = 0, forward = 0, up = 0 },
        position = { x = 120, y = 2040, z = 56 }, forward = { x = 0, y = 1, z = 0 }, up = { x = 0, y = 0, z = 1 } }
    local retained = { untouched = true }
    MineCome = { _block_sink = retained, _movement_probe = retained, _interactive_input = retained }
    player = { id = io.stdout }
    f.entity = player
    local function forbidden() error("write/timer/physics API invoked") end
    player.SetWorldPos = forbidden
    player.actor = { PlayerSetViewAngles = forbidden, SimulateOnAction = forbidden }
    function player:GetWorldPos()
        eq(self, f.entity); f.calls.position = f.calls.position + 1
        if f.on_position then return f.on_position(f.calls.position) end
        return f.position
    end
    System = {
        LogAlways = function(line) f.logs[#f.logs + 1] = line end,
        GetViewCameraDir = function()
            f.calls.forward = f.calls.forward + 1
            if f.on_forward then return f.on_forward() end
            return f.forward
        end,
        GetViewCameraUpDir = function()
            f.calls.up = f.calls.up + 1
            if f.on_up then return f.on_up() end
            return f.up
        end,
        ClearKeyState = forbidden, SetViewCamera = forbidden, SpawnEntity = forbidden, RemoveEntity = forbidden
    }
    Script = { SetTimerForFunction = forbidden, KillTimer = forbidden }
    Physics = { RayWorldIntersection = forbidden }
    dofile(MINECOME_MODULE_PATH)
    eq(#f.logs, 0); eq(f.calls.position, 0); eq(f.calls.forward, 0); eq(f.calls.up, 0)
    eq(MineCome._block_sink, retained); eq(MineCome._movement_probe, retained); eq(MineCome._interactive_input, retained)
    function f:sample(reason)
        local ok, actual = MineCome.SampleInputView(RUN)
        eq(actual, reason); eq(ok, reason == "ok"); eq(#self.logs, 1)
        local line = self.logs[1]
        assert(line:find('[MineComeInputView] {"schema":1,"run":"' .. RUN .. '",', 1, true))
        assert(line:find('"reason":"' .. reason .. '"', 1, true))
        if reason == "ok" then assert(line:find('"valid":true', 1, true))
        else assert(line:find('"valid":false', 1, true)); assert(line:find('"player":null,"forward":null,"up":null', 1, true)) end
        assert(not line:lower():find(':nan', 1, true)); assert(not line:lower():find(':inf', 1, true))
        assert(not line:find('userdata:', 1, true)); return line
    end
    return f
end

test("module is inert and preserves existing MineCome state", function()
    local f = fixture(); f:sample("ok"); eq(f.calls.position, 2); eq(f.calls.forward, 1); eq(f.calls.up, 1)
end)
test("four upright cardinal headings remain exact", function()
    for _, v in ipairs({ {x=0,y=1,z=0}, {x=1,y=0,z=0}, {x=0,y=-1,z=0}, {x=-1,y=0,z=0} }) do
        local f = fixture(); f.forward = v
        local line = f:sample("ok")
        assert(line:find(string.format('"forward":{"x":%d,"y":%d,"z":0}', v.x, v.y), 1, true))
    end
end)
test("ordinary positive and negative pitch has projected world-up", function()
    for _, angle in ipairs({ -0.8, 0.8 }) do
        local f = fixture(); f.forward = {x=0,y=math.cos(angle),z=math.sin(angle)}
        f.up = {x=0,y=-math.sin(angle),z=math.cos(angle)}; f:sample("ok")
    end
end)
test("half-degree roll accepted and two-degree roll rejected", function()
    for _, degrees in ipairs({ 0.5, 2 }) do
        local f = fixture(); local radians = degrees * math.pi / 180
        f.up = {x=math.sin(radians),y=0,z=math.cos(radians)}
        f:sample(degrees == 0.5 and "ok" or "rolled_view")
    end
end)
test("upside-down camera rejected", function() local f=fixture();f.up={x=0,y=0,z=-1};f:sample("rolled_view") end)
test("vertical and near-vertical views rejected", function()
    for _, horizontal in ipairs({0,0.005}) do
        local f=fixture();local vertical=math.sqrt(1-horizontal*horizontal)
        f.forward={x=horizontal,y=0,z=vertical};f.up={x=-vertical,y=0,z=horizontal};f:sample("vertical_view")
    end
end)
test("missing world or ambiguous entity id refused", function()
    local f=fixture();player=nil;f:sample("player_missing")
    for _, id in ipairs({0,1,"1",false,{}}) do f=fixture();player.id=id;f:sample("player_missing") end
    f=fixture();player.id=nil;f:sample("player_missing")
end)
test("missing getter refused before calls", function()
    for _, missing in ipairs({"GetWorldPos","GetViewCameraDir","GetViewCameraUpDir"}) do
        local f=fixture();if missing=="GetWorldPos" then player[missing]=nil else System[missing]=nil end
        f:sample("api_missing");eq(f.calls.position,0);eq(f.calls.forward,0);eq(f.calls.up,0)
    end
end)
test("getter errors cannot emit valid receipt", function()
    for _, broken in ipairs({"position","forward","up"}) do
        local f=fixture();f["on_"..broken]=function() error("getter unavailable") end;f:sample("api_error")
    end
end)
test("false/nil/non-table getter result refused", function()
    for _, value in ipairs({false,1,"vector",{x=0,y=1}}) do
        local f=fixture();f.on_forward=function() return value end;f:sample("vector_invalid")
    end
    local f=fixture();f.on_up=function() return nil end;f:sample("vector_invalid")
    f=fixture();f.on_position=function() return false end;f:sample("position_invalid")
end)
test("nonfinite and out-of-bound positions refused", function()
    for _, value in ipairs({0/0,math.huge,-math.huge,16777216}) do
        local f=fixture();f.position.x=value;f:sample("position_invalid")
    end
end)
test("nonfinite and out-of-bound camera vectors refused", function()
    for _, value in ipairs({0/0,math.huge,-math.huge,2}) do
        local f=fixture();f.forward.x=value;f:sample("vector_invalid")
    end
end)
test("non-unit vectors refused", function()
    for _, v in ipairs({{x=0,y=0,z=0},{x=0.8,y=0.8,z=0},{x=0,y=0.98,z=0}}) do
        local f=fixture();f.forward=v;f:sample("vector_nonunit")
    end
end)
test("nonorthogonal otherwise-unit vectors refused", function()
    local f=fixture();f.up={x=0,y=0.02,z=math.sqrt(1-0.02^2)};f:sample("vector_not_orthogonal")
end)
test("replacement player is rejected before further getters", function()
    local f=fixture();f.on_forward=function() player={id=io.stdout};return f.forward end
    f:sample("player_changed");eq(f.calls.position,1);eq(f.calls.up,0)
end)
test("same entity with replaced raw handle is rejected", function()
    local f=fixture();f.on_forward=function() player.id=io.stderr;return f.forward end
    f:sample("player_changed");eq(f.calls.position,1);eq(f.calls.up,0)
end)
test("metatable equality cannot conceal replacement table", function()
    local f=fixture();local mt={__eq=function() return true end};setmetatable(player,mt)
    f.on_forward=function() player=setmetatable({id=io.stdout},mt);return f.forward end;f:sample("player_changed")
end)
test("getter and System reference changes refused", function()
    local f=fixture();f.on_forward=function() player.GetWorldPos=function() return f.position end;return f.forward end;f:sample("api_error")
    f=fixture();f.on_up=function() System={LogAlways=System.LogAlways};return f.up end;f:sample("api_error")
end)
test("displacement over tenth-meter rejected and small movement allowed", function()
    for _, displacement in ipairs({0.099,0.101}) do
        local f=fixture();f.on_position=function(call)
            return {x=120+(call==2 and displacement or 0),y=2040,z=56}
        end;f:sample(displacement<0.1 and "ok" or "player_moved")
    end
end)
test("returned mutable vectors are copied before next getter", function()
    local f=fixture();f.on_up=function() f.forward.x=0.9;return f.up end
    local line=f:sample("ok");assert(line:find('"forward":{"x":0,"y":1,"z":0}',1,true))
end)
test("invalid tokens cannot invoke getters or inject receipt text", function()
    for _, run in ipairs({"", "A"..RUN:sub(2), string.rep("a",31), string.rep("a",33), 'a"\n', 7, {}}) do
        local f=fixture();local ok,reason=MineCome.SampleInputView(run);eq(ok,false);eq(reason,"invalid_run")
        eq(f.calls.position,0);eq(f.calls.forward,0);eq(f.calls.up,0)
        eq(#f.logs,1);assert(f.logs[1]:find('"run":"","valid":false,"reason":"invalid_run"',1,true));assert(not f.logs[1]:find('\n',1,true))
    end
end)
test("missing/failed logger never returns a successful sample", function()
    local f=fixture();System.LogAlways=nil;eq(MineCome.SampleInputView(RUN),false);eq(#f.logs,0);eq(f.calls.position,0)
    f=fixture();System.LogAlways=function() error("logger failed") end;eq(MineCome.SampleInputView(RUN),false);eq(#f.logs,0)
    f=fixture();System.LogAlways=function() return false end;eq(MineCome.SampleInputView(RUN),false);eq(#f.logs,0)
end)
test("reloading original module preserves state and replaces only sample function", function()
    fixture();local sink,probe,input=MineCome._block_sink,MineCome._movement_probe,MineCome._interactive_input
    local original=MineCome.SampleInputView;dofile(MINECOME_MODULE_PATH);assert(MineCome.SampleInputView~=original)
    eq(MineCome._block_sink,sink);eq(MineCome._movement_probe,probe);eq(MineCome._interactive_input,input)
end)
print("LUA_VIEW_SEED_TEST_PASS cases="..passed)
