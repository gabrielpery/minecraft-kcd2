-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua5.2 runtime, simulated bindings only. Never calls a game or mutator.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local RUN = "0123456789abcdef0123456789abcdef"
local function eq(a,b) assert(a==b,"got "..tostring(a)..", expected "..tostring(b)) end
local function has(line,text) assert(line:find(text,1,true),"receipt missing "..text) end
local function test(name,fn)
    local ok,message=pcall(fn);if not ok then error(name..": "..tostring(message),0) end
    passed=passed+1;print("PASS "..name)
end
local function fixture()
    local f={logs={},reads=0,forbidden=0,values={},methods={}}
    local retained={untouched=true}
    MineCome={_block_sink=retained,_movement_probe=retained,_interactive_input=retained}
    local seed=function() return "retained" end
    MineCome.SampleInputView=seed
    player={id=io.stdout,actor={},player={},human={}}
    f.entity=player
    local function forbidden()
        f.forbidden=f.forbidden+1;error("unowned control mutation or parameterized state read invoked")
    end
    ActionMapManager={EnableActionFilter=forbidden,IsFilterEnabled=forbidden,EnableActionMapManager=forbidden}
    GameRules={FreezeInput=forbidden,IsFrozen=forbidden}
    g_gameRules={game={FreezeInput=forbidden,IsFrozen=forbidden}}
    player.EnablePhysics=forbidden
    Script={SetTimerForFunction=forbidden,KillTimer=forbidden}
    Physics={RayWorldIntersection=forbidden}
    System={LogAlways=function(line)
        if f.log_error then error("logger unavailable") end
        if f.log_false then return false end
        f.logs[#f.logs+1]=line
    end,ClearKeyState=forbidden,SetViewCamera=forbidden,SpawnEntity=forbidden,RemoveEntity=forbidden}
    Game={};Calendar={};CryAction={}
    local function getter(owner,method,name,global)
        f.methods[name]={owner=owner,method=method}
        owner[method]=function(self)
            if global then eq(self,nil) else eq(self,owner) end
            f.reads=f.reads+1
            if f.on_read then f.on_read(name) end
            if f.errors and f.errors[name] then error("getter failed") end
            if f.results and f.results[name] then return f.results[name]() end
            if f.values[name]~=nil then return f.values[name] end
            return name=="game_started"
        end
    end
    getter(player.actor,"IsDead","dead");getter(player.actor,"IsUnconscious","unconscious")
    getter(player.player,"IsSitting","sitting");getter(player.player,"IsLaying","laying")
    getter(player.human,"IsMounted","mounted");getter(player.human,"IsInDialog","in_dialog")
    getter(Game,"IsLoadingEngineSaveGame","loading_engine_save",true)
    getter(Calendar,"IsWorldTimePaused","world_time_paused",true)
    getter(CryAction,"IsGameStarted","game_started",true)
    dofile(MINECOME_MODULE_PATH)
    eq(f.reads,0);eq(f.forbidden,0);eq(#f.logs,0)
    eq(MineCome._block_sink,retained);eq(MineCome._movement_probe,retained);eq(MineCome._interactive_input,retained)
    eq(MineCome.SampleInputView,seed)
    function f:sample()
        local ok,reason=MineCome.ProbeControlCapabilities(RUN);eq(ok,true);eq(reason,"sampled")
        eq(#self.logs,1);eq(self.forbidden,0)
        local line=self.logs[1];assert(#line<=4096);has(line,'[MineComeControlCapabilities] {"schema":1,"run":"'..RUN..'"')
        has(line,'"ownership_verified":false,"restoration_verified":false,"is_frozen_is_input_state":false')
        assert(not line:find('userdata:',1,true));assert(not line:find('\n',1,true));return line
    end
    return f
end
local function unknown(line,name,method_type,value_type)
    has(line,'"'..name..'":{"method_type":"'..method_type..'","ok":false,"value_type":"'..value_type..'","value":null}')
end

test("module is inert and only the named capability function is added",function() fixture() end)
test("actual boolean getters are typed and mutators are never called",function()
    local f=fixture();local line=f:sample();eq(f.reads,9)
    has(line,'"identity_stable":true,"entity_id_type":"userdata","references_stable":true')
    has(line,'"action_map_manager":{"owner_type":"table","EnableActionFilter":"function","IsFilterEnabled":"function","EnableActionMapManager":"function"}')
    has(line,'"global_game_rules":{"owner_type":"table","FreezeInput":"function","IsFrozen":"function"}')
    has(line,'"game_rules_game":{"owner_type":"table","FreezeInput":"function","IsFrozen":"function"}')
    has(line,'"player":{"owner_type":"table","EnablePhysics":"function"}')
    has(line,'"dead":{"method_type":"function","ok":true,"value_type":"boolean","value":false}')
    has(line,'"game_started":{"method_type":"function","ok":true,"value_type":"boolean","value":true}')
end)
test("global GameRules absence does not conceal actual bound owner",function()
    local f=fixture();GameRules=nil;local line=f:sample()
    has(line,'"global_game_rules":{"owner_type":"nil","FreezeInput":"nil","IsFrozen":"nil"}')
    has(line,'"game_rules_game":{"owner_type":"table","FreezeInput":"function","IsFrozen":"function"}')
end)
test("userdata game binding supports method type reads without invoking it",function()
    local f=fixture();local old=debug.getmetatable(io.stderr);local methods=g_gameRules.game
    debug.setmetatable(io.stderr,{__index=methods});g_gameRules.game=io.stderr
    local ok,message=pcall(function()
        local line=f:sample();has(line,'"game_rules_game":{"owner_type":"userdata","FreezeInput":"function","IsFrozen":"function"}')
    end)
    debug.setmetatable(io.stderr,old);assert(ok,message)
end)
test("unsupported function types are reported literally including false",function()
    local f=fixture();ActionMapManager.EnableActionFilter=false;ActionMapManager.IsFilterEnabled="unsupported"
    ActionMapManager.EnableActionMapManager={};player.EnablePhysics=17;local line=f:sample()
    has(line,'"EnableActionFilter":"boolean","IsFilterEnabled":"string","EnableActionMapManager":"table"')
    has(line,'"EnablePhysics":"number"')
end)
test("missing functions and owners are unknown rather than false",function()
    local f=fixture();player.actor.IsDead=nil;player.human=nil;Game.IsLoadingEngineSaveGame=nil;Calendar=nil
    local line=f:sample();unknown(line,"dead","nil","nil");unknown(line,"mounted","nil","nil")
    unknown(line,"in_dialog","nil","nil");unknown(line,"loading_engine_save","nil","nil")
    unknown(line,"world_time_paused","nil","nil")
end)
test("numbers strings nil and userdata never become boolean guard values",function()
    local outcomes={function() return 0 end,function() return 1 end,function() return "false" end,
        function() return nil end,function() return io.stdout end,function() return {} end}
    local types={"number","number","string","nil","userdata","table"}
    for i,outcome in ipairs(outcomes) do
        local f=fixture();f.results={dead=outcome};local line=f:sample();unknown(line,"dead","function",types[i])
    end
end)
test("true partial guards remain true but never establish ownership",function()
    local f=fixture();f.values.dead=true;f.values.in_dialog=true;f.values.world_time_paused=true
    local line=f:sample();has(line,'"dead":{"method_type":"function","ok":true,"value_type":"boolean","value":true}')
    has(line,'"in_dialog":{"method_type":"function","ok":true,"value_type":"boolean","value":true}')
    has(line,'"world_time_paused":{"method_type":"function","ok":true,"value_type":"boolean","value":true}')
end)
test("getter errors emit unknown with actual error type",function()
    local f=fixture();f.errors={dead=true,loading_engine_save=true};local line=f:sample()
    unknown(line,"dead","function","error");unknown(line,"loading_engine_save","function","error")
end)
test("throwing method lookup is bounded and reported without error text",function()
    local f=fixture();ActionMapManager=setmetatable({},{__index=function() error("private secret") end})
    local line=f:sample();has(line,'"EnableActionFilter":"error","IsFilterEnabled":"error","EnableActionMapManager":"error"')
    assert(not line:find("private secret",1,true))
end)
test("missing world never dereferences player getters",function()
    local f=fixture();player=nil;local line=f:sample();eq(f.reads,3)
    has(line,'"identity_stable":false,"entity_id_type":"nil"');unknown(line,"dead","nil","nil")
    unknown(line,"game_started","function","boolean")
end)
test("nonuserdata id is reported without guessed identity",function()
    for _,id in ipairs({0,1,"1",false,{}}) do
        local f=fixture();player.id=id;local line=f:sample();eq(f.reads,3)
        has(line,'"identity_stable":false,"entity_id_type":"'..type(id)..'"')
    end
end)
test("replacement actor stops further body getters and clears prior results",function()
    local f=fixture();f.on_read=function(name) if name=="dead" then player={id=io.stdout} end end
    local line=f:sample();eq(f.reads,1);has(line,'"identity_stable":false')
    has(line,'"references_stable":false');unknown(line,"dead","function","boolean")
end)
test("raw handle replacement prevents stable identity",function()
    local f=fixture();f.on_read=function(name) if name=="dead" then player.id=io.stderr end end
    local line=f:sample();has(line,'"identity_stable":false');unknown(line,"dead","function","boolean")
    has(line,'"references_stable":false');eq(f.reads,1)
end)
test("metatable equality cannot conceal player replacement",function()
    local f=fixture();local mt={__eq=function() return true end};setmetatable(player,mt)
    f.on_read=function(name) if name=="dead" then player=setmetatable({id=io.stdout},mt) end end
    has(f:sample(),'"identity_stable":false')
end)
test("nested owner replacement invalidates all captured guard values",function()
    local f=fixture();f.on_read=function(name) if name=="dead" then player.human={} end end
    local line=f:sample();eq(f.reads,1);has(line,'"references_stable":false');unknown(line,"dead","function","boolean")
end)
test("function replacement is detected even while player id remains stable",function()
    local f=fixture();f.on_read=function(name) if name=="dead" then Calendar.IsWorldTimePaused=function() return false end end end
    local line=f:sample();eq(f.reads,1);has(line,'"identity_stable":true');has(line,'"references_stable":false')
end)
test("global binding replacement invalidates reference provenance",function()
    local f=fixture();f.on_read=function(name) if name=="dead" then g_gameRules={game={}} end end
    local line=f:sample();eq(f.reads,1);has(line,'"references_stable":false')
end)
test("invalid run cannot log arbitrary text or call a getter",function()
    for _,run in ipairs({"",string.rep("a",31),string.rep("a",33),"A"..RUN:sub(2),'a"\n',7,{}}) do
        local f=fixture();local ok,reason=MineCome.ProbeControlCapabilities(run);eq(ok,false);eq(reason,"invalid_run")
        eq(f.reads,0);eq(f.forbidden,0);eq(#f.logs,0)
    end
end)
test("missing failed and false-returning logger cannot report success",function()
    local f=fixture();System.LogAlways=nil;eq(MineCome.ProbeControlCapabilities(RUN),false);eq(f.reads,0);eq(#f.logs,0)
    f=fixture();f.log_error=true;local ok,reason=MineCome.ProbeControlCapabilities(RUN);eq(ok,false);eq(reason,"log_failed");eq(#f.logs,0)
    f=fixture();f.log_false=true;ok,reason=MineCome.ProbeControlCapabilities(RUN);eq(ok,false);eq(reason,"log_failed");eq(#f.logs,0)
end)
test("reload changes only owned function and leaves prior state intact",function()
    fixture();local old=MineCome.ProbeControlCapabilities;local sink,probe,input,seed=MineCome._block_sink,MineCome._movement_probe,MineCome._interactive_input,MineCome.SampleInputView
    dofile(MINECOME_MODULE_PATH);assert(old~=MineCome.ProbeControlCapabilities)
    eq(MineCome._block_sink,sink);eq(MineCome._movement_probe,probe);eq(MineCome._interactive_input,input);eq(MineCome.SampleInputView,seed)
end)
print("LUA_CONTROL_CAPABILITIES_TEST_PASS cases="..passed)
