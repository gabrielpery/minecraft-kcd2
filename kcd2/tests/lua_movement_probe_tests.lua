-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua5.2 runtime, simulated engine bindings. No live movement proof.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local maximum_buffered_receipt_bytes = 0
local function eq(a,b) assert(a==b,"got "..tostring(a)..", expected "..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<0.00000001,"got "..tostring(a)..", expected near "..tostring(b)) end
local function target_receipt(line,seq,x,y,z)
    local actual_seq=tonumber(line:match('"seq":([^,]+)'))
    local a,b,c=line:match('"target":{"x":([^,]+),"y":([^,]+),"z":([^}]+)}')
    eq(actual_seq,seq);assert(a and b and c,"target vector missing");near(tonumber(a),x);near(tonumber(b),y);near(tonumber(c),z)
end
local function receipt_number(line,name) return assert(tonumber(line:match('"'..name..'":([^,}]+)')),name.." missing") end
local function receipt_vector(line,name)
    local x,y,z=line:match('"'..name..'":{"x":([^,]+),"y":([^,]+),"z":([^}]+)}')
    return {x=assert(tonumber(x)),y=assert(tonumber(y)),z=assert(tonumber(z))}
end
local function receipt_samples(line)
    local array=assert(line:match('"segment_observed_samples":%[(.*)%]'),"samples missing")
    local samples={}
    for object in array:gmatch('{"fraction":.-"readback_error":[^}]+}') do
        local camera=assert(object:match('"camera":(%b{})'),"sample camera missing")
        local sample={fraction=receipt_number(object,"fraction"),requested=receipt_vector(object,"requested"),
            actual=receipt_vector(object,"actual"),written=receipt_number(object,"written_engine_seconds"),
            observed=receipt_number(object,"observed_engine_seconds"),error=receipt_number(object,"readback_error"),
            performed=object:find('"write_performed":true',1,true)~=nil,
            camera={position=receipt_vector(camera,"position"),forward=receipt_vector(camera,"forward"),
                up=receipt_vector(camera,"up"),fov=receipt_number(camera,"fov")},
            camera_basis_valid=object:find('"camera_basis_valid":true',1,true)~=nil,
            written_frame_id=tonumber(object:match('"written_frame_id":([^,}]+)')),
            observed_frame_id=tonumber(object:match('"observed_frame_id":([^,}]+)'))}
        if object:find('"bracket_from_seq":',1,true) then
            sample.source={from_seq=receipt_number(object,"bracket_from_seq"),from_ms=receipt_number(object,"bracket_from_ms"),
                from_target=receipt_vector(object,"bracket_from_target"),to_seq=receipt_number(object,"bracket_to_seq"),
                to_ms=receipt_number(object,"bracket_to_ms"),to_target=receipt_vector(object,"bracket_to_target"),
                received=receipt_number(object,"bracket_to_received_engine_seconds"),playback=receipt_number(object,"playback_source_ms"),
                hold=object:find('"source_hold":true',1,true)~=nil}
        end
        samples[#samples+1]=sample
    end
    return samples
end
local function test(name,fn) local ok,err=pcall(fn);if not ok then error(name..": "..tostring(err),0) end;passed=passed+1;print("PASS "..name) end
local function cp(v) return {x=v.x,y=v.y,z=v.z} end
local function fixture()
    local f={time=0,logs={},queue={},writes={},kills={},rays=0,schedules=0,nextId=1,physical_frame_seconds=1/60,frame_reads=0}
    local retained={marker="untouched"}
    MineCome={_block_sink=retained,_interactive_input=retained}
    player={id=io.stdout,position={x=120,y=2040,z=56},velocity={x=0,y=0,z=0},actor={},player={},human={}}
    f.entity=player
    function player:GetWorldPos() if f.position_error then error("lost") end;return self.position end
    function player:GetVelocity() return self.velocity end
    function player:SetWorldPos(v)
        local owned=MineCome._movement_probe.active or MineCome._movement_probe.follower
        f.writes[#f.writes+1]={position=cp(v),at=f.time,restore_armed=owned.timers.restore~=nil or owned.timers.hard~=nil}
        if not f.no_write then self.position=cp(v) end
        if f.throw_first_write and #f.writes==1 then error("after mutation") end
        if f.on_write then f.on_write(#f.writes,self) end
    end
    player.actor.IsDead=function() return f.dead or false end
    player.actor.IsUnconscious=function() return f.unconscious or false end
    player.actor.GetLinkedEntity=function() return f.linked end
    player.player.IsSitting=function() return f.sitting or false end
    player.player.IsLaying=function() return f.laying or false end
    player.human.IsMounted=function() return f.mounted or false end
    local function forbidden() error("unowned write invoked") end
    player.actor.PlayerSetViewAngles=forbidden;player.actor.SimulateOnAction=forbidden
    System={GetCurrTime=function() return f.time end,
        GetFrameID=function() f.frame_reads=f.frame_reads+1;return f.frame_id or math.floor(f.time*60+.5) end,
        LogAlways=function(line)
        if f.log_error then error("log failure") end
        if line:find("[MineComeMovementFollower]",1,true) then assert(#line+2<3800,"native follower log budget exceeded") end
        if line:find('"position_mode":"source_time_buffered"',1,true) then
            maximum_buffered_receipt_bytes=math.max(maximum_buffered_receipt_bytes,#line)
        end
        f.logs[#f.logs+1]=line end,
        GetViewCameraPos=function()
            if f.camera_bad then return nil end
            local p=f.fixed_camera or player.position;local offset=f.camera_offset or {x=0,y=0,z=0}
            return {x=p.x+offset.x,y=p.y+offset.y,z=p.z+1.7+offset.z}
        end,GetViewCameraDir=function() return f.forward or {x=0,y=1,z=0} end,
        GetViewCameraUpDir=function() return f.up or {x=0,y=0,z=1} end,GetViewCameraFov=function() return 1.1 end,
        SetViewCamera=forbidden,ClearKeyState=forbidden,SpawnEntity=forbidden,RemoveEntity=forbidden}
    Script={SetTimerForFunction=function(ms,name,data,paused)
        eq(paused,true);assert(ms>=1 and ms<=(name=="MineCome_MovementFollowerExpiry" and 18000 or 750));f.schedules=f.schedules+1
        if name=="MineCome_MovementFollowerExpiry" then assert(ms==8000 or ms==18000,"unknown native deadline profile") end
        if f.fail_schedule==f.schedules then return nil end
        local id=f.nextId;f.nextId=id+1
        if f.userdata_timer and f.schedules==1 then id=io.stderr end
        local delay=name=="MineCome_MovementFollowerTick" and ms==1 and f.physical_frame_seconds or ms/1000
        f.queue[#f.queue+1]={id=id,at=f.time+delay,name=name,data=data,alive=true};return id
    end,KillTimer=function(id)
        f.kills[#f.kills+1]=id
        if f.kill_error then error("kill failed") end
        local found=false
        for _,event in ipairs(f.queue) do if event.id==id and event.alive then event.alive=false;found=true end end
        assert(found,"cancellation of consumed/unowned handle")
    end}
    ent_terrain=256
    Physics={RayWorldIntersection=function(origin,dir,max,mask,skip,skip2,out)
        eq(max,1);eq(mask,256);eq(skip,player.id);eq(skip2,nil);eq(dir.z,-2);f.rays=f.rays+1
        if f.ground_error then error("ray unavailable") end
        local height=56+(f.target_slope and origin.x>120.05 and 0.051 or 0)
        out[1]={pos={x=origin.x,y=origin.y,z=height},normal={x=0,y=0,z=1},dist=origin.z-height}
        if f.ray_change then f.ray_change(f.rays) end
        return f.no_hit and 0 or 1
    end}
    dofile(MINECOME_MODULE_PATH)
    eq(#f.logs,0);eq(#f.queue,0);eq(#f.writes,0);eq(MineCome._block_sink,retained)
    function f:verify(run)
        run=run or "a1";eq(MineCome.ProbeMovementCapabilities(run),true)
        eq(MineCome.VerifyMovementNoLinkContract(run,self.linked==0 and "number_zero" or "nil"),true)
    end
    function f:advance(delta)
        local target=self.time+delta
        while true do
            local best
            for _,event in ipairs(self.queue) do if event.alive and event.at<=target and (not best or event.at<best.at) then best=event end end
            if not best then break end
            best.alive=false;self.time=best.at;assert(type(_G[best.name])=="function");_G[best.name](best.data,best.id)
        end
        self.time=target
    end
    function f:last(stage)
        for i=#self.logs,1,-1 do if not stage or self.logs[i]:find('"stage":"'..stage..'"',1,true) then return self.logs[i] end end
    end
    function f:tick(at)
        local next_tick
        for _,event in ipairs(self.queue) do if event.alive and event.name=="MineCome_MovementFollowerTick" then next_tick=event end end
        assert(next_tick,"no owned physical tick");next_tick.alive=false;self.time=at or next_tick.at
        _G[next_tick.name](next_tick.data,next_tick.id)
    end
    function f:reachEndpoint()
        for i=1,128 do
            local p=assert(MineCome._movement_probe.follower)
            if p.pending_receipt then return end
            self:tick()
        end
        error("endpoint did not arrive")
    end
    function f:contains(text) for _,line in ipairs(self.logs) do if line:find(text,1,true) then return true end end;return false end
    function f:activeTimers() local count=0;for _,e in ipairs(self.queue) do if e.alive then count=count+1 end end;return count end
    return f
end
test("capabilities are typed read-only snapshots with explicit nil link and raw userdata",function()
    local f=fixture();eq(MineCome.ProbeMovementCapabilities("ABC1"),true)
    eq(#f.writes,0);eq(#f.queue,0);eq(f.rays,0)
    assert(f:last():find('[MineComeMovementCapabilities]',1,true))
    assert(f:last():find('"linked_kind":"nil"',1,true));assert(f:last():find('"entity_id_type":"userdata"',1,true))
    assert(f:last():find('"dead":{"method_type":"function","ok":true,"value_type":"boolean","finite":false,"value":false}',1,true))
    assert(not f:last():find('userdata:',1,true));eq(MineCome._movement_probe.verified_no_link_kind,nil)
end)
test("tokens reject injection before API reads or logging",function()
    local f=fixture()
    for _,run in ipairs({"",'a"',"a\n","-1","g",string.rep("a",65),12,{}}) do
        eq(MineCome.ProbeMovementCapabilities(run),false);eq(MineCome.BeginMovementProbe(run),false);eq(MineCome.EndMovementProbe(run),false)
    end
    eq(#f.logs,0);eq(#f.queue,0);eq(#f.writes,0)
end)
test("capability missing world methods errors and nonfinite values never become valid snapshots",function()
    local f=fixture();player=nil;eq(MineCome.ProbeMovementCapabilities("a"),true);assert(f:last():find('"result":"no_world"',1,true))
    f=fixture();player.actor.GetLinkedEntity=nil;player.GetVelocity=nil;player.position.x=0/0
    eq(MineCome.ProbeMovementCapabilities("a"),true)
    assert(f:last():find('"velocity":{"method_type":"nil","ok":false',1,true));assert(f:last():find('"linked_kind":"unavailable"',1,true))
    assert(not f:last():lower():find(':nan',1,true));eq(MineCome.VerifyMovementNoLinkContract("a","nil"),false)
    f=fixture();f.position_error=true;eq(MineCome.ProbeMovementCapabilities("a"),true);assert(f:last():find('"value_type":"error"',1,true))
end)
test("no-link contract requires explicit matching receipt and same raw entity",function()
    local f=fixture();local ok,reason=MineCome.BeginMovementProbe("a");eq(ok,false);eq(reason,"no_link_contract_unverified")
    eq(MineCome.VerifyMovementNoLinkContract("a","nil"),false);eq(MineCome.ProbeMovementCapabilities("a"),true)
    eq(MineCome.VerifyMovementNoLinkContract("b","nil"),false);eq(MineCome.VerifyMovementNoLinkContract("a","number_zero"),false)
    player.id=io.stderr;eq(MineCome.VerifyMovementNoLinkContract("a","nil"),false);eq(#f.writes,0)
end)
test("numeric zero absence is distinct and opaque/nonzero link values are refused",function()
    local f=fixture();f.linked=0;f:verify();assert(f:contains('"linked_kind":"number_zero"'))
    eq(MineCome.BeginMovementProbe("b"),true);f:advance(1);eq(#f.writes,2)
    for _,link in ipairs({io.stderr,1,false,"0",{}}) do
        f=fixture();f.linked=link;eq(MineCome.ProbeMovementCapabilities("a"),true)
        eq(MineCome.VerifyMovementNoLinkContract("a","nil"),false);eq(MineCome.VerifyMovementNoLinkContract("a","number_zero"),false)
        eq(MineCome.BeginMovementProbe("b"),false);eq(#f.writes,0)
    end
end)
test("unsafe unknown player booleans velocity camera and timers refuse before scheduling",function()
    for _,key in ipairs({"dead","unconscious","sitting","laying","mounted"}) do
        local f=fixture();f:verify();f[key]=true;eq(MineCome.BeginMovementProbe("b"),false);eq(#f.queue,0)
    end
    local f=fixture();f:verify();player.actor.IsDead=function() return 0 end;eq(MineCome.BeginMovementProbe("b"),false)
    f=fixture();f:verify();player.velocity.x=.05;eq(MineCome.BeginMovementProbe("b"),false)
    f=fixture();f:verify();player.velocity.x=0/0;eq(MineCome.BeginMovementProbe("b"),false)
    f=fixture();f:verify();f.camera_bad=true;eq(MineCome.BeginMovementProbe("b"),false)
    f=fixture();f:verify();Script.KillTimer=nil;eq(MineCome.BeginMovementProbe("b"),false)
    f=fixture();f:verify();System.GetCurrTime=nil;eq(MineCome.BeginMovementProbe("b"),false)
end)
test("console only enqueues and cleanup is armed before the one step",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);eq(#f.writes,0);eq(f:activeTimers(),1)
    f:advance(.001);eq(#f.writes,1);eq(f.writes[1].restore_armed,true)
    eq(f.writes[1].position.x,120.1);eq(f.writes[1].position.y,2040);eq(f.writes[1].position.z,56);eq(f:activeTimers(),3)
    local ok,reason=MineCome.BeginMovementProbe("c");eq(ok,false);eq(reason,"busy")
    f:advance(.100);assert(f:last("sample100"));f:advance(.150);assert(f:last("sample250"))
    f:advance(.350);eq(#f.writes,2);eq(player.position.x,120);eq(f:activeTimers(),0);eq(MineCome._movement_probe.active,nil)
    assert(f:last("restored"):find('"terminal":true',1,true));assert(f:last("restored"):find('"result":"restored"',1,true))
    assert(f.writes[2].at<=.8);eq(f.rays,2)
end)
test("ground height no-hit slope mask failure and player changes refuse initial write",function()
    for _,mode in ipairs({"no_hit","target_slope","ground_error"}) do
        local f=fixture();f:verify();f[mode]=true;eq(MineCome.BeginMovementProbe("b"),true);f:advance(1);eq(#f.writes,0);eq(f:activeTimers(),0)
        assert(f:last("rejected"):find('"result":"ground_not_verified"',1,true))
    end
    local f=fixture();f:verify();ent_terrain=nil;eq(MineCome.BeginMovementProbe("b"),true);f:advance(1);eq(#f.writes,0)
    f=fixture();f:verify();f.ray_change=function(i) if i==2 then player.id=io.stderr end end
    eq(MineCome.BeginMovementProbe("b"),true);f:advance(1);eq(#f.writes,0)
end)
test("pre-apply navigation identity and delayed enqueue expiration refuse mutation",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);player.position.x=120.021;f:advance(1);eq(#f.writes,0)
    f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);player.id=io.stderr;f:advance(1);eq(#f.writes,0)
    f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);local e=f.queue[1];e.alive=false;f.time=.11;_G[e.name](e.data,e.id);eq(#f.writes,0)
end)
test("timer failures leave no initial write or unbounded work",function()
    for schedule=1,4 do
        local f=fixture();f:verify();f.fail_schedule=schedule;MineCome.BeginMovementProbe("b");f:advance(1)
        eq(#f.writes,0);eq(f:activeTimers(),0);eq(MineCome._movement_probe.active,nil)
    end
end)
test("exact-token cancel is deferred and closes only owned state",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);eq(MineCome.EndMovementProbe("c"),false)
    eq(MineCome.EndMovementProbe("b"),true);eq(#f.writes,0);f:advance(1);eq(#f.writes,0);assert(f:last("cancelled"))
    f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001)
    eq(MineCome.EndMovementProbe("c"),false);eq(MineCome.EndMovementProbe("b"),true);eq(#f.writes,1)
    local count=f.schedules;eq(MineCome.EndMovementProbe("b"),true);eq(f.schedules,count)
    f:advance(.102);eq(#f.writes,2);eq(player.position.x,120);eq(f:activeTimers(),0);assert(f:last("restored"))
end)
test("restore rejects navigation velocity and replaced entities without overwriting",function()
    for _,change in ipairs({function() player.position.x=120.301 end,function() player.position.x=120.15 end,function() player.velocity.x=.201 end,
        function() player.id=io.stderr end,function() player.actor.GetLinkedEntity=function() return io.stderr end end}) do
        local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001);change();f:advance(1)
        eq(#f.writes,1);eq(f:activeTimers(),0);assert(f:last("restore_failed"));eq(MineCome._movement_probe.active,nil)
    end
end)
test("mutation followed by API exception still performs guarded cleanup",function()
    local f=fixture();f:verify();f.throw_first_write=true;eq(MineCome.BeginMovementProbe("b"),true);f:advance(1)
    eq(#f.writes,2);eq(player.position.x,120);assert(f:last("restored"));assert(f:last("apply_failed"))
end)
test("camera failure cannot strand safe position and camera outcome remains explicitly unverified",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001);f.camera_bad=true;f:advance(1)
    eq(#f.writes,2);eq(player.position.x,120);assert(f:last("restore_failed"):find('"restore_result":"restored"',1,true))
    f=fixture();f:verify();f.fixed_camera=cp(player.position);eq(MineCome.BeginMovementProbe("b"),true);f:advance(.251)
    assert(f:last("sample250"):find('"camera_follow":false',1,true));f:advance(1);eq(#f.writes,2)
end)
test("userdata timer handles are cancelled raw and stray callbacks cannot consume owned timers",function()
    local first=fixture();first:verify();first.userdata_timer=true;first.log_error=true
    eq(MineCome.BeginMovementProbe("b"),false);eq(first.kills[1],io.stderr);eq(#first.writes,0);eq(first:activeTimers(),0)
    local f=fixture();f:verify();f.userdata_timer=true;eq(MineCome.BeginMovementProbe("b"),true)
    local p=MineCome._movement_probe.active;eq(MineCome_MovementProbeApply({probe=p,slot="apply"}),false);eq(#f.writes,0)
    f.log_error=true;-- cleanup through a real callback still cannot touch another module's timer
    f:advance(1);eq(#f.writes,2);eq(MineCome._movement_probe.active,nil)
end)
test("reload preserves active ownership and callbacks from an old run cannot mutate a new run",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001)
    local old=MineCome._movement_probe.active.data.sample100;local retained=MineCome._block_sink
    dofile(MINECOME_MODULE_PATH);eq(MineCome._block_sink,retained);f:advance(1);eq(#f.writes,2)
    f:verify("c");eq(MineCome.BeginMovementProbe("d"),true);eq(MineCome_MovementProbeSample(old),false);eq(#f.writes,2)
    f:advance(1);eq(#f.writes,4);eq(f:activeTimers(),0)
end)
test("late restore and timer cancellation failures are never labelled clean success",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001)
    local p=MineCome._movement_probe.active;local restoreEvent
    for _,e in ipairs(f.queue) do if e.data==p.data.restore then restoreEvent=e end end
    restoreEvent.alive=false;f.time=.9;MineCome_MovementProbeRestore(restoreEvent.data,restoreEvent.id);f:advance(.1)
    eq(#f.writes,2);assert(f:last("restore_failed"):find('"result":"restored_late"',1,true))
    f=fixture();f:verify();eq(MineCome.BeginMovementProbe("b"),true);f:advance(.001);f.kill_error=true
    eq(MineCome.EndMovementProbe("b"),true);f:advance(1);eq(#f.writes,2)
    assert(f:last():find('timer_cancel_failed',1,true));assert(f:last():find('"timers_cancelled":false',1,true))
end)
test("follower begins without writes and first pose must arrive within800ms",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true);eq(#f.writes,0)
    eq(f.queue[1].name,"MineCome_MovementFollowerExpiry");eq(f.queue[1].at,8);eq(f:activeTimers(),2)
    f:advance(.85);eq(#f.writes,0);eq(MineCome._movement_probe.follower,nil);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"first_pose_expired"'))
end)
test("follower only queues copied poses and delayed ACK is for the previous normal frame",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.BeginMovementProbe("c"),false);eq(MineCome.BeginMovementFollower("c"),false)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);eq(#f.writes,0)
    f:advance(.04);eq(#f.writes,1);eq(player.position.x,120.1)
    assert(not f:contains('"event":"applied"'))
    eq(MineCome.ApplyMovementFollower("b",2,120.2,2040,56),true)
    f:advance(.04);assert(f:contains('"event":"applied","result":"applied_readback"'))
    assert(f:contains('"seq":1,"target":{"x":120.09999999999999'))
    eq(player.position.x,120.2)
    f:advance(.04);assert(f:contains('"seq":2,"target":{"x":120.2'))
    eq(MineCome.EndMovementFollower("b"),true);eq(player.position.x,120.2)
    f:advance(.08);eq(player.position.x,120);eq(MineCome._movement_probe.follower,nil);eq(f:activeTimers(),0)
    assert(f:contains('"event":"restored","result":"restored","terminal":true'))
end)
test("follower replay badseq targetbound and wrongsession cannot refresh lease",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    for _,seq in ipairs({0,-1,201,.5,"1",0/0,math.huge}) do eq(MineCome.ApplyMovementFollower("b",seq,120,2040,56),false) end
    eq(MineCome.ApplyMovementFollower("c",1,120,2040,56),false)
    for _,point in ipairs({{122.01,2040,56},{120,2040,57.51},{120,2040,55.79},{120+0/0,2040,56}}) do
        eq(MineCome.ApplyMovementFollower("b",1,point[1],point[2],point[3]),false)
    end
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.2)
    eq(MineCome.ApplyMovementFollower("b",1,120.2,2040,56),false)
    f:advance(.3);eq(MineCome._movement_probe.follower,nil);eq(player.position.x,120)
    assert(f:contains('"end_result":"frame_lease_expired"'))
end)
test("hard8second deadline is armed once and fresh poses never extend it",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    local original=MineCome._movement_probe.follower.timers.hard
    for seq=1,80 do
        if not MineCome._movement_probe.follower or MineCome._movement_probe.follower.restoring then break end
        eq(MineCome.ApplyMovementFollower("b",seq,120.1,2040,56),true)
        eq(MineCome._movement_probe.follower.timers.hard,original);f:advance(.1)
    end
    f:advance(.1);eq(MineCome._movement_probe.follower,nil);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(#f.writes<=200);local lines=0;for _,line in ipairs(f.logs) do if line:find('[MineComeMovementFollower]',1,true) then lines=lines+1 end end;assert(lines<=128)
    local expires=0;for _,e in ipairs(f.queue) do if e.name=="MineCome_MovementFollowerExpiry" then expires=expires+1 end end;eq(expires,1)
    assert(f:contains('"end_result":"hard_deadline"') or f:contains('"end_result":"write_budget"'))
end)
test("follower end before first write cancels timers and wrongtoken never cancels ownership",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.EndMovementFollower("c"),false);eq(MineCome.EndMovementFollower("b"),true);eq(#f.writes,0)
    f:advance(.05);eq(#f.writes,0);eq(f:activeTimers(),0);assert(f:contains('"end_result":"explicit_end"'))
end)
test("follower rejects replacement userdata unexpected body and horizontal input without restoration",function()
    for _,change in ipairs({function() player.id=io.stderr end,function() player.position.x=120.451 end,
        function() player.velocity.x=.201 end,function() player.actor.IsDead=function() return true end end}) do
        local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true);eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true)
        f:advance(.04);local count=#f.writes;change();f:advance(.08)
        eq(#f.writes,count);eq(MineCome._movement_probe.follower,nil);eq(f:activeTimers(),0)
        assert(f:contains('"event":"restore_failed"'))
    end
end)
test("follower firstwrite requires same-identity ground evidence and cancels failed tick scheduling",function()
    local f=fixture();f:verify();f.no_hit=true;eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.08);eq(#f.writes,0);eq(f:activeTimers(),0)
    f=fixture();f:verify();f.ray_change=function() player.id=io.stderr end;eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.08);eq(#f.writes,0)
    f=fixture();f:verify();f.fail_schedule=3;eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.12);eq(player.position.x,120)
    eq(MineCome._movement_probe.follower,nil);eq(f:activeTimers(),0)
end)
test("follower stale callbacks cannot drive next session and reload preserves current ownership",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    local old=MineCome._movement_probe.follower.data.tick;eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true)
    f:advance(.04);dofile(MINECOME_MODULE_PATH);eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    eq(MineCome.BeginMovementFollower("c"),true);local count=#f.writes;eq(MineCome_MovementFollowerTick(old),false);eq(#f.writes,count)
    eq(MineCome.ApplyMovementFollower("b",2,120.2,2040,56),false);eq(MineCome.EndMovementFollower("c"),true);f:advance(.08)
    eq(f:activeTimers(),0)
end)
test("physical view is read-only and requires verified actor and advancing engine time",function()
    local f=fixture()
    eq(MineCome.SamplePhysicalHudView("a1"),false);eq(#f.writes,0);eq(f:activeTimers(),0)
    f:verify();eq(MineCome.SamplePhysicalHudView("b"),true)
    local line=f:last();assert(line:find('[MineComeHudPhysicalView]',1,true))
    assert(line:find('"seq":1,"result":"sampled","physical_movement":true',1,true))
    assert(line:find('"sampled_engine_seconds":0',1,true));assert(line:find('"camera_basis_valid":true',1,true))
    local count=#f.logs
    eq(MineCome.SamplePhysicalHudView("b"),false);eq(#f.logs,count)
    f:advance(.1);f.forward={x=1,y=0,z=0};eq(MineCome.SamplePhysicalHudView("b"),true)
    assert(f:last():find('"seq":2',1,true));assert(f:last():find('"forward":{"x":1,"y":0,"z":0}',1,true))
    eq(#f.writes,0);eq(f:activeTimers(),0);eq(f.rays,0)
end)
test("physical view rejects foreign follower token identity motion and invalid camera",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.SamplePhysicalHudView("b"),false)
    f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.SamplePhysicalHudView("c"),false);eq(MineCome.SamplePhysicalHudView("b"),true)
    for _,change in ipairs({function() player.id=io.stderr end,function() player.velocity.x=.05 end,
        function(f) f.camera_bad=true end,function(f) f.forward={x=0,y=2,z=0} end,
        function(f) f.up={x=0,y=1,z=0} end,function(f) f.camera_offset={x=4,y=0,z=0} end}) do
        f=fixture();f:verify();change(f);eq(MineCome.SamplePhysicalHudView("b"),false)
        eq(#f.writes,0);eq(f:activeTimers(),0)
    end
    f=fixture();f:verify();eq(MineCome.SamplePhysicalHudView('a"'),false)
    eq(MineCome.BeginPhysicalMovementFollower('a"'),false);eq(#f.writes,0);eq(f:activeTimers(),0)
end)
test("physical view sequence deadline and failure remain bounded across reload",function()
    local f=fixture();f:verify();f.log_error=true
    eq(MineCome.SamplePhysicalHudView("b"),false);eq(MineCome._movement_probe.physical_view,nil)
    f.log_error=false;eq(MineCome.SamplePhysicalHudView("b"),true)
    dofile(MINECOME_MODULE_PATH);f:advance(.1);eq(MineCome.SamplePhysicalHudView("b"),true)
    eq(MineCome._movement_probe.physical_view.sequence,2)
    local count=#f.logs;f.time=.05;eq(MineCome.SamplePhysicalHudView("b"),false);eq(#f.logs,count)
    f.time=120;eq(MineCome.SamplePhysicalHudView("b"),false);eq(#f.logs,count)
    eq(MineCome.SamplePhysicalHudView("c"),true)
    MineCome._movement_probe.physical_view.sequence=1024;f:advance(.1)
    eq(MineCome.SamplePhysicalHudView("c"),false);eq(#f.writes,0);eq(f:activeTimers(),0)
end)
test("physical follower accepts native look while preserving player readback and restoration",function()
    local f=fixture();f:verify();eq(MineCome.SamplePhysicalHudView("b"),true)
    eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome._movement_probe.follower.physical_movement,true)
    local hard=MineCome._movement_probe.follower.timers.hard
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.04)
    f.camera_offset={x=.6,y=0,z=0};f.forward={x=1,y=0,z=0}
    f:advance(.12);assert(f:contains('"event":"applied","result":"applied_readback"'))
    assert(f:last():find('"follow_error":null',1,true));assert(f:last():find('"camera_basis_valid":true',1,true))
    assert(f:last():find('"player_readback_error":0',1,true));assert(f:last():find('"forward":{"x":1,"y":0,"z":0}',1,true))
    eq(MineCome.SamplePhysicalHudView("b"),true);eq(MineCome._movement_probe.follower.timers.hard,hard)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:last():find('"event":"restored","result":"restored","terminal":true',1,true))
    assert(f:last():find('"target":{"x":120,"y":2040,"z":56}',1,true))
    assert(f:last():find('"player_readback_error":0',1,true))
    for _,line in ipairs(f.logs) do
        if line:find('[MineComeMovementFollower]',1,true) then
            assert(line:find('"physical_movement":true,"camera_mode":"native_look"',1,true))
            assert(line:find('"sampled_engine_seconds":',1,true))
        end
    end
    eq(MineCome.SamplePhysicalHudView("b"),true);eq(f:activeTimers(),0)
end)
test("physical follower keeps exact target and velocity guards and stale pose lease",function()
    for _,change in ipairs({function() player.id=io.stderr end,function() player.position.x=120.451 end,
        function() player.velocity.x=.201 end,function() player.actor.IsDead=function() return true end end}) do
        local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
        eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.04)
        local count=#f.writes;change();f:advance(.08)
        eq(#f.writes,count);eq(f:activeTimers(),0);assert(f:contains('"event":"restore_failed"'))
    end
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    for _,point in ipairs({{122.01,2040,56},{120,2040,57.51},{120,2040,54.49},{121.5,2040,54.5}}) do
        eq(MineCome.ApplyMovementFollower("b",1,point[1],point[2],point[3]),false)
    end
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.2)
    eq(MineCome.SamplePhysicalHudView("b"),true);f:advance(.3)
    eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"frame_lease_expired"'))
end)
test("physical interpolation follows elapsed engine time with delayed observed samples",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040.3,56.3),true);eq(#f.writes,0)
    for i=1,4 do
        f:tick();near(player.position.x,120+6*f.time);near(player.position.y,2040+3*f.time);near(player.position.z,56+3*f.time)
        assert(not f:contains('"event":"applied"'))
    end
    f:reachEndpoint();assert(not f:contains('"event":"applied"'));local endpoint_time=f.time
    f:tick();target_receipt(f:last(),1,120.6,2040.3,56.3)
    assert(f:last():find('"position_mode":"timed_interpolation","interpolation_ms":100',1,true))
    near(receipt_number(f:last(),"target_receipt_age_ms"),f.time*1000)
    local samples=receipt_samples(f:last());assert(#samples>=1 and #samples<=8)
    eq(receipt_number(f:last(),"segment_update_count"),#f.writes)
    local observations=receipt_number(f:last(),"segment_observation_count")
    assert(observations>=#f.writes and observations>=#samples)
    eq(f:last():find('"segment_observed_samples_truncated":true',1,true)~=nil,observations>#samples)
    near(receipt_number(f:last(),"segment_max_readback_error"),0)
    near(receipt_number(f:last(),"segment_max_observation_gap_ms"),1000/60)
    for _,sample in ipairs(samples) do
        assert(sample.fraction>=0 and sample.fraction<=1);assert(sample.observed>sample.written)
        near(sample.requested.x,120+.6*sample.fraction);near(sample.actual.x,sample.requested.x)
        near(sample.fraction,math.min(1,sample.written/.1))
    end
    eq(samples[#samples].fraction,1);near(samples[#samples].written,endpoint_time)
    near(samples[#samples].observed,receipt_number(f:last(),"sampled_engine_seconds"))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("same engine time callbacks cannot add interpolation steps or acknowledge endpoints",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick()
    local writes=#f.writes;local t=f.time
    for i=1,4 do f:tick(t) end
    eq(#f.writes,writes);assert(not f:contains('"event":"applied"'))
    f:reachEndpoint();writes=#f.writes;t=f.time
    for i=1,4 do f:tick(t) end
    eq(#f.writes,writes);assert(not f:contains('"event":"applied"'))
    f:tick();assert(f:contains('"event":"applied","result":"applied_readback"'))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("physical camera telemetry retains later actual getter values and native frame identifiers",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    f.frame_id=1000;eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick()
    local camera={x=120.03,y=2040.02,z=57.74}
    System.GetViewCameraPos=function() return camera end
    f.forward={x=1,y=0,z=0};f.frame_id=1002;f:tick()
    camera.x=120.2;f.forward.x=0;f.forward.y=1
    while not MineCome._movement_probe.follower.pending_receipt do f.frame_id=f.frame_id+2;f:tick() end
    f.frame_id=f.frame_id+2;f:tick()
    local samples=receipt_samples(f:last());local first=samples[1]
    near(first.requested.x,120.1);near(first.actual.x,120.1)
    near(first.camera.position.x,120.03);near(first.camera.position.y,2040.02);near(first.camera.position.z,57.74)
    near(first.camera.forward.x,1);near(first.camera.forward.y,0);near(first.camera.up.z,1);near(first.camera.fov,1.1)
    eq(first.camera_basis_valid,true);eq(first.written_frame_id,1000);eq(first.observed_frame_id,1002)
    assert(first.observed>first.written);assert(math.abs(first.camera.position.x-first.requested.x)>.05)
    near(samples[#samples].camera.position.x,120.2);near(samples[#samples].camera.forward.y,1)
    eq(samples[#samples].observed_frame_id,f.frame_id)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("optional unavailable or invalid native frame identifiers do not change physical movement",function()
    for _,method in ipairs({false,function() error("frame unavailable") end,function() return nil end,
        function() return -1 end,function() return .5 end,function() return 0/0 end,function() return math.huge end,
        function() return 9007199254740992 end,function() return "9" end,function() return {} end}) do
        local f=fixture();System.GetFrameID=method;f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
        eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:reachEndpoint();f:tick()
        assert(f:last():find('"event":"applied","result":"applied_readback"',1,true))
        local samples=receipt_samples(f:last());assert(#samples>=1)
        for _,sample in ipairs(samples) do
            eq(sample.written_frame_id,nil);eq(sample.observed_frame_id,nil);eq(sample.camera_basis_valid,true)
            near(sample.actual.x,sample.requested.x)
        end
        assert(f:last():find('"written_frame_id":null,"observed_frame_id":null',1,true))
        eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
    end
end)

test("stationary observations retain real camera motion without adding actor writes",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    f.frame_id=0;eq(MineCome.ApplyMovementFollower("b",1,120,2040,56),true);f:tick();eq(#f.writes,0)
    f.camera_offset={x=.2,y=0,z=.1};f.forward={x=1,y=0,z=0};f.frame_id=1;f:tick()
    local samples=receipt_samples(f:last());eq(#samples,1);eq(#f.writes,0)
    near(samples[1].actual.x,120);near(samples[1].camera.position.x,120.2);near(samples[1].camera.position.z,57.8)
    eq(samples[1].performed,false);eq(samples[1].written_frame_id,0);eq(samples[1].observed_frame_id,1)
    near(samples[1].camera.forward.x,1);eq(samples[1].camera_basis_valid,true)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("write and observed frame identifier availability are recorded independently",function()
    for _,write_available in ipairs({true,false}) do
        local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
        System.GetFrameID=write_available and function() return 42 end or nil
        eq(MineCome.ApplyMovementFollower("b",1,120,2040,56),true);f:tick()
        System.GetFrameID=not write_available and function() return 44 end or nil;f:tick()
        local sample=receipt_samples(f:last())[1]
        eq(sample.written_frame_id,write_available and 42 or nil)
        eq(sample.observed_frame_id,not write_available and 44 or nil)
        eq(#f.writes,0);assert(sample.observed>sample.written)
        eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
    end
end)

test("interpolation starts no earlier than target acceptance or the previous tick",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    f:tick();f.time=.025;eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true)
    f:tick();near(player.position.x,120+6*(f.time-.025))
    f:reachEndpoint();f:tick();near(receipt_number(f:last(),"segment_start_engine_seconds"),.025)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
end)

test("physical observations retain intermediate and endpoint drift",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick()
    local requested=player.position.x;player.position.x=player.position.x+.02;f:tick()
    f:reachEndpoint();player.position.x=120.66;f:tick()
    assert(f:last():find('"event":"applied","result":"delayed_readback_changed"',1,true))
    assert(f:last():find('"readback":false',1,true));target_receipt(f:last(),1,120.6,2040,56)
    local samples=receipt_samples(f:last());near(samples[1].requested.x,requested);near(samples[1].actual.x,requested+.02)
    near(samples[1].error,.02);near(receipt_number(f:last(),"segment_max_readback_error"),.06)
    near(receipt_number(f:last(),"player_readback_error"),.06)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("physical follower finishes its immutable segment while later targets coalesce",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick();near(player.position.x,120.1)
    eq(MineCome.ApplyMovementFollower("b",2,120.9,2040,56),true)
    eq(MineCome.ApplyMovementFollower("b",3,121.2,2040,56),true)
    f:reachEndpoint();near(player.position.x,120.6);assert(not f:contains('"event":"applied"'))
    f:tick();target_receipt(f:last(),1,120.6,2040,56);assert(player.position.x>120.6 and player.position.x<121.2)
    f:reachEndpoint();f:tick();target_receipt(f:last(),3,121.2,2040,56)
    local applied=0
    for _,line in ipairs(f.logs) do
        if line:find('"event":"applied"',1,true) then applied=applied+1;assert(not line:find('"seq":2,',1,true)) end
    end
    eq(applied,2);eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("fresh arrivals cannot extend an older physical segment lease",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick();near(player.position.x,120.1)
    f.time=.45;eq(MineCome.ApplyMovementFollower("b",2,120.8,2040,56),true)
    f:tick(.45);near(player.position.x,120.1);assert(not f:contains('"event":"applied"'))
    f:reachEndpoint();f:tick();target_receipt(f:last(),2,120.8,2040,56)
    near(receipt_number(f:last(),"segment_start_engine_seconds"),.45)
    for _,line in ipairs(f.logs) do
        if line:find('"event":"applied"',1,true) then assert(not line:find('"seq":1,',1,true)) end
    end
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("physical acceptance clock regression rejects before interpolation",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    f.time=.025;eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true)
    f.time=.01;eq(MineCome.ApplyMovementFollower("b",2,120.8,2040,56),false)
    f:tick(.015);eq(#f.writes,0);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"clock_unavailable_or_regressed"'))
end)

test("physical partial segment cancellation and expiry restore without claiming an endpoint",function()
    for _,expiry in ipairs({false,true}) do
        local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
        eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:tick();near(player.position.x,120.1)
        if expiry then f:tick(.45) else eq(MineCome.EndMovementFollower("b"),true) end
        f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
        assert(not f:contains('"event":"applied"'))
        assert(f:last():find('"event":"restored","result":"restored","terminal":true',1,true))
        if expiry then assert(f:last():find('"end_result":"frame_lease_expired"',1,true)) end
    end
end)

test("failed physical intermediate or endpoint writes retain guarded restoration",function()
    for failed=1,6 do
        local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
        f.on_write=function(count) if count==failed then error("setter failed after mutation") end end
        eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:advance(.25)
        eq(player.position.x,120);eq(f:activeTimers(),0);assert(not f:contains('"event":"applied"'))
        assert(f:last():find('"end_result":"position_write_or_readback_failed"',1,true))
    end
end)

test("stationary targets skip setters but still require a later observed endpoint",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120,2040,56),true);f:tick()
    eq(#f.writes,0);assert(not f:contains('"event":"applied"'))
    f:tick();target_receipt(f:last(),1,120,2040,56);eq(receipt_number(f:last(),"segment_update_count"),0)
    eq(receipt_number(f:last(),"segment_observation_count"),1)
    assert(f:last():find('"endpoint_write_performed":false',1,true))
    local samples=receipt_samples(f:last());eq(#samples,1);eq(samples[1].fraction,1);eq(samples[1].performed,false)
    assert(samples[1].observed>samples[1].written);f:advance(.1);eq(#f.writes,0)
    player.position.x=120.01;f:tick();eq(#f.writes,1);eq(player.position.x,120)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("stationary endpoint observation does not stall a newer moving target",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120,2040,56),true);f:tick()
    eq(MineCome.ApplyMovementFollower("b",2,120.6,2040,56),true);f:tick()
    target_receipt(f:last(),1,120,2040,56);assert(player.position.x>120 and player.position.x<120.6)
    f:reachEndpoint();f:tick();target_receipt(f:last(),2,120.6,2040,56)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("bounded observed sample array always retains the endpoint",function()
    local f=fixture();f.physical_frame_seconds=.005;f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.6,2040,56),true);f:reachEndpoint();f:tick()
    local samples=receipt_samples(f:last());assert(#samples>=1 and #samples<=8);eq(samples[#samples].fraction,1)
    assert(receipt_number(f:last(),"segment_observation_count")>8)
    assert(f:last():find('"segment_observed_samples_truncated":true',1,true))
    near(samples[#samples].observed,receipt_number(f:last(),"sampled_engine_seconds"))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("only physical follower permits bounded downhill targets",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120,2040,54.5),true);f:tick();near(player.position.z,55.75)
    f:reachEndpoint();f:tick();near(player.position.z,54.5);target_receipt(f:last(),1,120,2040,54.5)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.z,56);eq(f:activeTimers(),0)
    f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120,2040,55.79),false);eq(#f.writes,0)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("physical write budget reserves restoration even with excessively frequent ticks",function()
    local f=fixture();f.physical_frame_seconds=.001;f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    for seq=1,20 do
        if not MineCome._movement_probe.follower or MineCome._movement_probe.follower.restoring then break end
        eq(MineCome.ApplyMovementFollower("b",seq,120+(seq%2)*.6,2040,56),true);f:advance(.1)
    end
    f:advance(.1);eq(#f.writes,512);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"write_budget"'))
end)

test("physical 60Hz writes fit the unchanged hard deadline and view samples never extend it",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    local hard=MineCome._movement_probe.follower.timers.hard
    for seq=1,80 do
        if not MineCome._movement_probe.follower or MineCome._movement_probe.follower.restoring then break end
        eq(MineCome.ApplyMovementFollower("b",seq,120.4+(seq%2)*.4,2040,56),true)
        eq(MineCome.SamplePhysicalHudView("b"),true)
        eq(MineCome._movement_probe.follower.timers.hard,hard);f:advance(.1)
    end
    f:advance(.1);eq(player.position.x,120);eq(f:activeTimers(),0);assert(#f.writes>200 and #f.writes<=512)
    assert(f:contains('"end_result":"hard_deadline"'));assert(not f:contains('"end_result":"write_budget"'))
end)

test("physical camera loss still restores safe player but does not claim camera success",function()
    local f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.04)
    f.camera_bad=true;f:advance(.12)
    eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:last():find('"event":"restore_failed","result":"normal_camera_unavailable_after_restore"',1,true))
    assert(f:last():find('"camera_basis_valid":false',1,true));assert(f:last():find('"readback":true',1,true))
end)
test("legacy follower retains fixed camera offset metric and original receipt schema",function()
    local f=fixture();f:verify();eq(MineCome.BeginMovementFollower("b"),true)
    eq(MineCome.ApplyMovementFollower("b",1,120.1,2040,56),true);f:advance(.04)
    f.camera_offset={x=.6,y=0,z=0};f:advance(.04)
    assert(not f:last():find('"follow_error":null',1,true))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    assert(not f:contains('"physical_movement"'));assert(not f:contains('"camera_basis_valid"'))
    eq(f.frame_reads,0)
    eq(player.position.x,120);eq(f:activeTimers(),0)
end)

local function buffered_fixture(extended,walking_area)
    local f=fixture();f:verify()
    eq((extended and MineCome.BeginExtendedBufferedPhysicalMovementFollower or MineCome.BeginBufferedPhysicalMovementFollower)("b",walking_area),true)
    function f:point(seq,source_ms,dx)
        return MineCome.ApplyBufferedMovementFollower("b",seq,120+(dx or 0),2040,56,source_ms)
    end
    return f
end
local function buffered_samples(line)
    assert(line:find('"position_mode":"source_time_buffered","interpolation_ms":null',1,true))
    eq(receipt_number(line,"playback_delay_ms"),200)
    local epoch=receipt_number(line,"playback_epoch_engine_seconds")
    local samples=receipt_samples(line)
    for _,sample in ipairs(samples) do
        local source=assert(sample.source,"missing source bracket")
        near(source.playback,(sample.written-epoch)*1000)
        assert(sample.observed>sample.written);assert(sample.written-source.received<=.4+1e-12)
        local fraction=source.hold and 0 or math.max(0,math.min(1,(source.playback-source.from_ms)/(source.to_ms-source.from_ms)))
        near(sample.fraction,fraction)
        for _,axis in ipairs({"x","y","z"}) do
            near(sample.requested[axis],source.from_target[axis]+(source.to_target[axis]-source.from_target[axis])*fraction)
        end
        if source.hold then eq(source.from_seq,source.to_seq) end
    end
    return samples
end

test("buffered playback holds startup and acknowledges actual interpolation rather than source endpoints",function()
    local f=buffered_fixture();eq(f:point(1,0,0),true);f:advance(.1);eq(f:point(2,100,.2),true)
    f:advance(.1);eq(f:point(3,200,.4),true);eq(#f.writes,0)
    local epoch=MineCome._movement_probe.follower.buffer_epoch;near(epoch,.2)
    f:tick(.225);near(player.position.x,120.05);assert(not f:contains('"event":"applied"'))
    f:tick(.245);target_receipt(f:last(),1,120.05,2040,56)
    near(receipt_vector(f:last(),"source_target").x,120);eq(receipt_number(f:last(),"source_seq"),1)
    eq(receipt_number(f:last(),"source_points_crossed"),1);buffered_samples(f:last())
    f:tick(.315);near(player.position.x,120.23);f:tick(.332)
    target_receipt(f:last(),2,120.23,2040,56);near(receipt_vector(f:last(),"source_target").x,120.2)
    eq(receipt_number(f:last(),"source_ms"),100);local samples=buffered_samples(f:last())
    eq(samples[#samples].source.from_seq,2);eq(samples[#samples].source.to_seq,3)
    near(samples[#samples].fraction,.15);near(MineCome._movement_probe.follower.buffer_epoch,epoch)
    assert(f:last():find('"endpoint_write_performed":null',1,true))
    for _,write in ipairs(f.writes) do assert(math.abs(write.position.x-120.2)>1e-8) end
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("uneven source waypoints preserve continuous speed across normal frames without endpoint pauses",function()
    local f=buffered_fixture();eq(f:point(1,0),true)
    for index,source in ipairs({97,203,307,401}) do
        f:advance(.1);eq(f:point(index+1,source,source*.002),true)
    end
    f:advance(.05);assert(#f.writes>=13)
    for index,write in ipairs(f.writes) do
        near(write.position.x,120+2*(write.at-.2))
        if index>1 then
            local previous=f.writes[index-1];near(write.position.x-previous.position.x,2*(write.at-previous.at))
            assert(write.position.x>previous.position.x)
        end
    end
    for _,line in ipairs(f.logs) do if line:find('"event":"applied"',1,true) then buffered_samples(line) end end
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("skipped playback frames report multiple crossed source points with one later actual observation",function()
    local f=buffered_fixture()
    for index,source in ipairs({0,50,100,200}) do eq(f:point(index,source,source*.002),true) end
    f:tick(.35);eq(#f.writes,1);near(player.position.x,120.3);assert(not f:contains('"event":"applied"'))
    f:tick(.36);target_receipt(f:last(),3,120.3,2040,56)
    eq(receipt_number(f:last(),"source_points_crossed"),3);near(receipt_vector(f:last(),"source_target").x,120.2)
    local samples=buffered_samples(f:last());eq(#samples,1);eq(samples[1].source.from_seq,3);eq(samples[1].source.to_seq,4)
    near(samples[1].fraction,.5);eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("buffered input validates origin source clock ordering and bounded queue before actor writes",function()
    for _,invalid in ipairs({function(f) return f:point(1,1,0) end,function(f) return f:point(1,0,.001) end,
        function(f) return f:point(1,0/0,0) end,function(f) return f:point(1,math.huge,0) end,
        function(f) return f:point(1,-1,0) end,function(f) return f:point(1,6000.01,0) end,
        function(f) return f:point(0,0,0) end,function(f) return f:point(201,0,0) end,
        function(f) eq(f:point(1,0,0),true);return f:point(1,100,.1) end,
        function(f) eq(f:point(1,0,0),true);return f:point(2,0,.1) end,
        function(f) eq(f:point(1,0,0),true);return f:point(2,100,2.01) end,
        function(f) for seq=1,8 do eq(f:point(seq,(seq-1)*100,0),true) end;return f:point(9,800,0) end}) do
        local f=buffered_fixture();eq(invalid(f),false);eq(#f.writes,0);f:advance(.05)
        eq(#f.writes,0);eq(f:activeTimers(),0);eq(MineCome._movement_probe.follower,nil)
    end
end)

test("buffered mode mixing fails closed while wrong session tokens leave ownership intact",function()
    local f=buffered_fixture();eq(MineCome.ApplyBufferedMovementFollower("c",1,120,2040,56,0),false)
    eq(MineCome._movement_probe.follower.end_requested,nil);eq(MineCome.ApplyMovementFollower("b",1,120,2040,56),false)
    f:advance(.05);eq(#f.writes,0);eq(f:activeTimers(),0)
    f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.ApplyBufferedMovementFollower("b",1,120,2040,56,0),false);f:advance(.05)
    eq(#f.writes,0);eq(f:activeTimers(),0)
end)

test("buffered eight point capacity includes the retained historical anchor",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:tick(.2)
    eq(#MineCome._movement_probe.follower.buffer_queue,0)
    eq(MineCome._movement_probe.follower.buffer_anchor.seq,1)
    for seq=2,8 do eq(f:point(seq,(seq-1)*50),true) end
    eq(#MineCome._movement_probe.follower.buffer_queue,7)
    eq(f:point(9,400),false);f:advance(.05);eq(#f.writes,0);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"source_queue_overflow"'))
end)

test("buffered expiry cannot skip an old destination merely because a later point is fresh",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,300,.6),true);f:tick(.25)
    near(player.position.x,120.1);f:tick(.27);f.time=.35;eq(f:point(3,500,1),true)
    local writes=#f.writes;f:tick(.41);eq(#f.writes,writes+1);eq(player.position.x,120)
    f:advance(.08);eq(f:activeTimers(),0);assert(f:contains('"end_result":"source_destination_expired"'))
end)

test("buffered historical left geometry may outlive its lease while the active destination stays fresh",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,200,.4),true)
    f:advance(.2);eq(f:point(3,500,1),true);f:advance(.25)
    assert(MineCome._movement_probe.follower and not MineCome._movement_probe.follower.restoring)
    assert(f.time-MineCome._movement_probe.follower.buffer_anchor.received>.4)
    assert(player.position.x>120.65);eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("buffered late points and moving continuations after tail hold stop without catch-up writes",function()
    for _,source in ipairs({140,300}) do
        local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.2),true)
        f:tick(.35);f:tick(.36);near(player.position.x,120.2);local writes=#f.writes
        eq(f:point(3,source,.6),false);eq(#f.writes,writes);f:advance(.08)
        eq(player.position.x,120);eq(#f.writes,writes+1);eq(f:activeTimers(),0)
        assert(f:contains(source==140 and '"end_result":"source_time_late"' or '"end_result":"source_continuation_late"'))
    end
end)

test("buffered tail holds never extrapolate and identical stationary continuation adds no actor writes",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:tick(.25)
    f.camera_offset={x=.2,y=0,z=.1};f:tick(.27);eq(#f.writes,0)
    local sample=buffered_samples(f:last())[1];eq(sample.source.hold,true);near(sample.source.playback,50)
    near(sample.fraction,0);near(sample.camera.position.x,120.2)
    eq(f:point(2,200),true);f:advance(.15);eq(#f.writes,0)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(#f.writes,0);eq(f:activeTimers(),0)
end)

test("buffered sample truncation retains the final ACK observation even between waypoints",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.19);eq(f:point(2,300,.6),true)
    f:advance(.21);eq(f:point(3,500,1),true);f:advance(.09);f:tick(.515);f:tick(.531)
    local samples=buffered_samples(f:last());assert(#samples>=1 and #samples<=8);assert(receipt_number(f:last(),"segment_observation_count")>8)
    assert(f:last():find('"segment_observed_samples_truncated":true',1,true))
    near(samples[#samples].fraction,.075);near(samples[#samples].observed,.531);near(samples[#samples].requested.x,120.63)
    target_receipt(f:last(),2,120.63,2040,56)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("buffered same-clock callbacks cannot acknowledge or consume another source waypoint",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.2),true);f:tick(.225)
    local writes=#f.writes;local count=#MineCome._movement_probe.follower.buffer_queue
    for index=1,3 do f:tick(.225) end
    eq(#f.writes,writes);eq(#MineCome._movement_probe.follower.buffer_queue,count)
    assert(not f:contains('"event":"applied"'));f:tick(.24);assert(f:contains('"event":"applied"'))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("buffered write budget still reserves one restoration with faster-than-frame callbacks",function()
    local f=buffered_fixture();f.physical_frame_seconds=.0001
    eq(f:point(1,0),true);eq(f:point(2,100,.4),true);eq(f:point(3,200,.8),true);f:advance(.4)
    eq(#f.writes,512);eq(player.position.x,120);eq(f:activeTimers(),0);assert(f:contains('"end_result":"write_budget"'))
end)

test("buffered delayed receipts cannot revive an expired crossed source point",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.2),true);f:tick(.39)
    near(player.position.x,120.2);f.time=.395;eq(f:point(3,300,.2),true);f:tick(.405)
    f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"source_receipt_expired"'));assert(not f:contains('"event":"applied"'))
end)

test("buffered source inputs and view samples never change the epoch or original hard deadline",function()
    local f=buffered_fixture();local p=MineCome._movement_probe.follower;local hard=p.timers.hard
    eq(f:point(1,0),true);local epoch=p.buffer_epoch;local deadline=p.deadline
    f:advance(.1);eq(f:point(2,100,.2),true);eq(MineCome.SamplePhysicalHudView("b"),true)
    eq(p.buffer_epoch,epoch);eq(p.deadline,deadline);eq(p.timers.hard,hard);near(deadline-p.created,8)
    f:advance(.15);eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    eq(player.position.x,120);eq(f:activeTimers(),0)
end)

test("buffered full precision camera and source metadata stay within eight retained observations",function()
    local f=buffered_fixture();f.camera_offset={x=.12345678912345,y=.23456789123456,z=.34567891234567}
    f.forward={x=math.cos(.3),y=math.sin(.3),z=0}
    f.up={x=-math.sin(.3)*math.sin(.2),y=math.cos(.3)*math.sin(.2),z=math.cos(.2)}
    eq(f:point(1,0),true);f:advance(.19)
    eq(MineCome.ApplyBufferedMovementFollower("b",2,120.6123456789123,2040.234567891234,56.123456789123,300.123456789123),true)
    f:advance(.21)
    eq(MineCome.ApplyBufferedMovementFollower("b",3,121.0123456789123,2040.434567891234,56.223456789123,500.234567891234),true)
    f:advance(.09);f:tick(.515123456789);f:tick(.531234567891)
    local samples=buffered_samples(f:last());assert(#samples>=1 and #samples<8)
    assert(f:last():find('"segment_observed_samples_truncated":true',1,true))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(f:activeTimers(),0)
end)

test("buffered serialization fits the native log budget with maximum run token and verbose numeric fields",function()
    local f=fixture();f:verify();local run=string.rep("a",64);eq(MineCome.BeginBufferedPhysicalMovementFollower(run),true)
    f.frame_id=9007199254740991;f.camera_offset={x=.12345678912345,y=.23456789123456,z=.34567891234567}
    f.forward={x=math.cos(.3),y=math.sin(.3),z=0}
    f.up={x=-math.sin(.3)*math.sin(.2),y=math.cos(.3)*math.sin(.2),z=math.cos(.2)}
    eq(MineCome.ApplyBufferedMovementFollower(run,1,120,2040,56,0),true);f:advance(.19)
    eq(MineCome.ApplyBufferedMovementFollower(run,2,120.6123456789123,2040.234567891234,56.123456789123,300.123456789123),true)
    f:advance(.21)
    eq(MineCome.ApplyBufferedMovementFollower(run,3,121.0123456789123,2040.434567891234,56.223456789123,500.234567891234),true)
    f:advance(.09);f:tick(.515123456789);f:tick(.531234567891)
    local line=f:last();local samples=buffered_samples(line);assert(#line+2<=3798)
    assert(#samples>=1 and #samples<=2);assert(receipt_number(line,"segment_observation_count")>8)
    assert(line:find('"segment_observed_samples_truncated":true',1,true))
    near(samples[#samples].observed,receipt_number(line,"sampled_engine_seconds"))
    near(samples[#samples].requested.x,receipt_vector(line,"target").x)
    eq(MineCome.EndMovementFollower(run),true);f:advance(.08);eq(f:activeTimers(),0)
end)

local function buffered_ack(f,seq)
    for index,line in ipairs(f.logs) do
        if line:find('[MineComeMovementFollower]',1,true) and line:find('"event":"applied"',1,true)
            and receipt_number(line,"seq")==seq then return line,index end
    end
end
test("buffered finish drains final observation and camera before restoring without another host request",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true)
    local p=MineCome._movement_probe.follower;local hard=p.timers.hard;local received=p.latest.received;local epoch=p.buffer_epoch
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);eq(#f.writes,0)
    f:advance(.05);local records=p.records;eq(MineCome.FinishBufferedMovementFollower("b",2),true)
    eq(p.records,records);eq(p.latest.received,received);eq(p.buffer_epoch,epoch);eq(p.timers.hard,hard);eq(p.deadline,8)
    local restored_after_ack=false
    f.on_write=function()
        if player.position.x==120 and #f.writes>1 then
            local ack=assert(buffered_ack(f,2),"origin restored before final source ACK")
            local samples=buffered_samples(ack);local last=samples[#samples]
            near(last.actual.x,120.25);near(last.camera.position.x,120.25);near(last.observed,receipt_number(ack,"sampled_engine_seconds"))
            assert(ack:find('"readback":true',1,true));restored_after_ack=true
        end
    end
    f:advance(.3);eq(restored_after_ack,true);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:last():find('"event":"restored","result":"restored","terminal":true',1,true))
    assert(f:last():find('"end_result":"explicit_end"',1,true));eq(MineCome._movement_probe.follower,nil)
end)

test("buffered finish cannot confuse a final write with its later successful ACK",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true);f:tick(.31)
    local p=MineCome._movement_probe.follower;eq(p.last_applied_seq,2);eq(p.last_buffered_ack_seq,nil)
    local writes=#f.writes;eq(MineCome.FinishBufferedMovementFollower("b",2),true);eq(#f.writes,writes)
    f:tick(.31);eq(#f.writes,writes);eq(buffered_ack(f,2),nil);near(player.position.x,120.25)
    f:tick(.33);assert(buffered_ack(f,2));eq(#f.writes,writes+1);eq(player.position.x,120)
    f:advance(.08);eq(f:activeTimers(),0);assert(f:last():find('"end_result":"explicit_end"',1,true))
end)

test("buffered finish after an existing final ACK restores only on the next normal tick",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true)
    f:tick(.31);f:tick(.33);assert(buffered_ack(f,2));local writes=#f.writes;local records=#f.logs
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);eq(#f.writes,writes);eq(#f.logs,records)
    near(player.position.x,120.25);f:tick(.35);eq(player.position.x,120);eq(#f.writes,writes+1)
    f:advance(.08);eq(f:activeTimers(),0);assert(f:last():find('"end_result":"explicit_end"',1,true))
end)

test("buffered finish rejects invalid mode sequence or absent source without granting a new lease",function()
    for _,invalid in ipairs({false,0,-1,201,.5,0/0,math.huge,"2",3}) do
        local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.25),true)
        eq(MineCome.FinishBufferedMovementFollower("b",invalid),false);f:advance(.05)
        eq(#f.writes,0);eq(f:activeTimers(),0);assert(not f:contains('"end_result":"explicit_end"'))
    end
    local f=buffered_fixture();eq(MineCome.FinishBufferedMovementFollower("b",1),false);f:advance(.05);eq(f:activeTimers(),0)
    f=fixture();f:verify();eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    eq(MineCome.FinishBufferedMovementFollower("b",1),false);f:advance(.05);eq(#f.writes,0);eq(f:activeTimers(),0)
    f=buffered_fixture();eq(f:point(1,0),true)
    eq(MineCome.FinishBufferedMovementFollower("c",1),false);eq(MineCome.FinishBufferedMovementFollower("!",1),false)
    eq(MineCome._movement_probe.follower.end_requested,nil);eq(MineCome._movement_probe.follower.finish_seq,nil)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.05);eq(f:activeTimers(),0)
end)

test("a buffered finish seal rejects later source appends and conflicting seals",function()
    for _,append in ipairs({true,false}) do
        local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true);f:advance(.15)
        local p=MineCome._movement_probe.follower;local received=p.latest.received;local writes=#f.writes
        eq(MineCome.FinishBufferedMovementFollower("b",2),true)
        if append then eq(f:point(3,200,.5),false) else eq(MineCome.FinishBufferedMovementFollower("b",3),false) end
        eq(p.latest.seq,2);eq(p.latest.received,received);eq(#f.writes,writes)
        f:advance(.08);eq(player.position.x,120);eq(#f.writes,writes+1);eq(f:activeTimers(),0)
        assert(f:contains(append and '"end_result":"source_after_finish"' or '"end_result":"final_source_mismatch"'))
        assert(not f:contains('"end_result":"explicit_end"'))
    end
end)

test("a failed final buffered readback restores safely without successful finish",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true)
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);f:tick(.31);player.position.x=120.31;f:tick(.33)
    local ack=assert(buffered_ack(f,2));assert(ack:find('"readback":false',1,true))
    assert(ack:find('"result":"delayed_readback_changed"',1,true));eq(player.position.x,120)
    f:advance(.08);eq(f:activeTimers(),0);assert(f:contains('"end_result":"final_readback_changed"'))
    assert(not f:contains('"end_result":"explicit_end"'))
end)

test("final buffered ACK logging failure cannot become a successful native finish",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true)
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);f:tick(.31)
    local p=MineCome._movement_probe.follower;f.log_error=true;f:tick(.33)
    eq(player.position.x,120);eq(p.last_buffered_ack_seq,nil);eq(p.end_result,"log_failed")
    f.log_error=false;f:advance(.08);eq(f:activeTimers(),0);assert(f:contains('"end_result":"log_failed"'))
    eq(buffered_ack(f,2),nil)
end)

test("buffered native finish does not extend expiration or retroactively finish a stopped run",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.25),true)
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);f:tick(.39);f:tick(.41);f:advance(.08)
    eq(player.position.x,120);eq(f:activeTimers(),0);eq(buffered_ack(f,2),nil)
    assert(f:contains('"end_result":"frame_lease_expired"'));eq(MineCome.FinishBufferedMovementFollower("b",2),false)
    f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.25),true);f:tick(.25);f.time=.41
    eq(MineCome.FinishBufferedMovementFollower("b",2),false);f:tick(.41);f:advance(.08)
    eq(player.position.x,120);eq(f:activeTimers(),0);assert(f:contains('"end_result":"frame_lease_expired"'))
    f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.25),true)
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);f:tick(8);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"hard_deadline"'))
end)

test("immediate end still cancels a sealed buffered path without claiming the final ACK",function()
    local f=buffered_fixture();eq(f:point(1,0),true);f:advance(.1);eq(f:point(2,100,.25),true)
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);f:tick(.25)
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
    eq(buffered_ack(f,2),nil);assert(f:contains('"end_result":"explicit_end"'))
end)

test("an already acknowledged late finish still cannot extend the next tick beyond its source lease",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.25),true)
    f:tick(.31);f:tick(.33);assert(buffered_ack(f,2));f.time=.399
    eq(MineCome.FinishBufferedMovementFollower("b",2),true);local writes=#f.writes
    f:tick(.41);eq(#f.writes,writes+1);eq(player.position.x,120);f:advance(.08)
    eq(f:activeTimers(),0);assert(f:contains('"end_result":"frame_lease_expired"'))
    assert(not f:contains('"end_result":"explicit_end"'))
end)

test("buffered finish keeps the ordinary setter budget and restoration reserve",function()
    local f=buffered_fixture();f.physical_frame_seconds=.0001
    eq(f:point(1,0),true);eq(f:point(2,100,.4),true);eq(f:point(3,200,.8),true)
    eq(MineCome.FinishBufferedMovementFollower("b",3),true);f:advance(.4)
    eq(#f.writes,512);eq(player.position.x,120);eq(f:activeTimers(),0);assert(f:contains('"end_result":"write_budget"'))
    assert(not f:contains('"end_result":"explicit_end"'))
end)

test("extended profile drains sixteen seconds with all source readbacks and exact restoration",function()
    local f=buffered_fixture(true);local p=MineCome._movement_probe.follower
    local hard=p.timers.hard;near(p.deadline-p.created,18)
    eq(f:point(1,0),true);local epoch=p.buffer_epoch
    for index=1,160 do
        f:advance(.1)
        eq(f:point(index+1,index*100,.35*math.sin(index/5)),true)
        eq(p.timers.hard,hard);near(p.deadline,18);near(p.buffer_epoch,epoch)
        assert(#p.buffer_queue+(p.buffer_anchor and 1 or 0)<=8)
        if index==80 then
            dofile(MINECOME_MODULE_PATH)
            eq(MineCome._movement_probe.follower,p);eq(p.timers.hard,hard)
        end
        if index%20==0 then eq(MineCome.SamplePhysicalHudView("b"),true) end
    end
    eq(MineCome.FinishBufferedMovementFollower("b",161),true)
    f:advance(.35)
    eq(player.position.x,120);eq(player.position.y,2040);eq(player.position.z,56)
    eq(f:activeTimers(),0);eq(MineCome._movement_probe.follower,nil)
    assert(#f.writes>511 and #f.writes<=2048)
    eq(p.last_buffered_ack_seq,161);eq(p.end_result,"explicit_end")
    local count=0
    for _,line in ipairs(f.logs) do
        if line:find('[MineComeMovementFollower]',1,true) then
            assert(line:find('"movement_session":"extended"',1,true))
            eq(receipt_number(line,"hard_deadline_ms"),18000)
            if line:find('"event":"applied"',1,true) then
                count=count+1;eq(receipt_number(line,"source_seq"),count)
                eq(receipt_number(line,"source_ms"),(count-1)*100)
                assert(line:find('"readback":true',1,true));buffered_samples(line)
            end
        end
    end
    eq(count,161);assert(p.records<256)
    assert(f:last():find('"event":"restored","result":"restored"',1,true))
end)

test("extended entry point is explicit and never changes the baseline budgets or schema",function()
    local f=buffered_fixture();local p=MineCome._movement_probe.follower
    eq(MineCome.BeginExtendedBufferedPhysicalMovementFollower("b"),false)
    eq(f:point(1,0),true)
    local ok,why=f:point(2,6000.01);eq(ok,false);eq(why,"source_time_invalid")
    near(p.deadline-p.created,8);f:advance(.05)
    assert(not f:contains('"movement_session"'));eq(receipt_number(f:last(),"hard_deadline_ms"),8000)
    f=fixture();f:verify()
    eq(MineCome.BeginBufferedPhysicalMovementFollower("b",18000,16000,2047),false)
    eq(f:activeTimers(),0);eq(MineCome.BeginBufferedPhysicalMovementFollower("b"),true)
    near(MineCome._movement_probe.follower.deadline,8)
    eq(MineCome.ApplyBufferedMovementFollower("b",1,120,2040,56,0),true)
    eq(MineCome.ApplyBufferedMovementFollower("b",2,120,2040,56,16000),false)
    f:advance(.05);assert(not f:contains('"movement_session"'))
end)

test("extended source and sequence bounds are exact and retain spatial bounds",function()
    local f=buffered_fixture(true);eq(f:point(1,0),true)
    eq(f:point(200,16000),true)
    local ok,why=f:point(201,16000);eq(ok,false);eq(why,"sequence_invalid");f:advance(.05)
    for _,source in ipairs({16000.0001,-1,math.huge,0/0}) do
        f=buffered_fixture(true);eq(f:point(1,0),true)
        ok,why=f:point(2,source);eq(ok,false);eq(why,"source_time_invalid");f:advance(.05)
    end
    for _,row in ipairs({{122,56,true},{122.0001,56,false},{120,57.5,true},{120,57.5001,false},
            {120,54.5,true},{120,54.4999,false}}) do
        f=buffered_fixture(true);eq(f:point(1,0),true)
        ok,why=MineCome.ApplyBufferedMovementFollower("b",2,row[1],2040,row[2],100)
        eq(ok,row[3]);if not row[3] then eq(why,"target_out_of_bounds") end
        eq(MineCome.EndMovementFollower("b"),true);f:advance(.05);eq(f:activeTimers(),0)
    end
end)

test("extended source freshness remains four hundred milliseconds and restoration is guarded",function()
    local f=buffered_fixture(true);eq(f:point(1,0),true);eq(f:point(2,100,.2),true)
    f:tick(.31);f:tick(.33);near(player.position.x,120.2)
    f:tick(.4001);f:advance(.05)
    eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"frame_lease_expired"'))
    assert(not f:contains('"end_result":"explicit_end"'))
end)

test("extended hard deadline restores at eighteen seconds without relying on host cleanup",function()
    local f=buffered_fixture(true);eq(f:point(1,0),true);eq(f:point(2,100,.2),true)
    f:tick(.31);f:tick(.33);local p=MineCome._movement_probe.follower
    local hard
    for _,event in ipairs(f.queue) do if event.alive and event.name=="MineCome_MovementFollowerExpiry" then hard=event end end
    assert(hard);near(hard.at,18);hard.alive=false;f.time=hard.at
    _G[hard.name](hard.data,hard.id);f:advance(.05)
    eq(player.position.x,120);eq(f:activeTimers(),0);eq(p.end_result,"hard_deadline")
    eq(receipt_number(f:last(),"hard_deadline_ms"),18000)
end)

test("extended fast callbacks reserve one of exactly 2048 writes for restoration",function()
    local f=buffered_fixture(true)
    eq(f:point(1,0),true);eq(f:point(2,100,.4),true);eq(f:point(3,200,.8),true)
    f:advance(.19);f.physical_frame_seconds=.00005;f:tick(.2);f:advance(.2)
    eq(#f.writes,2048);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"end_result":"write_budget"'))
end)

test("extended receipts reserve two records for restoration and termination",function()
    local f=buffered_fixture(true);eq(f:point(1,0),true);eq(f:point(2,100,.2),true)
    f:tick(.31);f:tick(.33);local p=MineCome._movement_probe.follower
    -- Reach the receipt cap deterministically without inventing source points:
    -- previous cases exercise actual ACK emission over a sustained full session.
    p.records=254;f:tick(.35);f:advance(.05)
    eq(p.records,256);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"event":"restoring"'));assert(f:contains('"event":"restored"'))
    eq(p.end_result,"receipt_budget")
end)

test("pre-profile active follower reload retains baseline ownership and budgets",function()
    local f=buffered_fixture();eq(f:point(1,0),true);eq(f:point(2,100,.2),true)
    f:tick(.25);local p=MineCome._movement_probe.follower;local hard=p.timers.hard
    -- The previous module's active state did not contain a profile registry.
    MineCome._movement_probe.follower_profiles=nil
    dofile(MINECOME_MODULE_PATH)
    eq(MineCome._movement_probe.follower,p);eq(p.timers.hard,hard);near(p.deadline,8)
    local ok,why=f:point(3,6000.01);eq(ok,false);eq(why,"source_time_invalid")
    f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(not f:contains('"movement_session"'));eq(receipt_number(f:last(),"hard_deadline_ms"),8000)
end)
test("wide follower requires explicit physical profile and preserves narrow admission",function()
    local f=fixture();f:verify()
    eq(MineCome.BeginMovementFollower("b","wide"),false)
    for _,area in ipairs({"", "normal", "WIDE",true,4,{}}) do eq(MineCome.BeginPhysicalMovementFollower("b",area),false) end
    eq(f:activeTimers(),0);eq(#f.writes,0)
    eq(MineCome.BeginPhysicalMovementFollower("b"),true)
    MineCome._movement_probe.follower.walking_area="wide" -- Caller-visible mutable state grants no authority.
    local ok,why=MineCome.ApplyMovementFollower("b",1,122.01,2040,56);eq(ok,false);eq(why,"target_out_of_bounds")
    assert(not f:contains('"walking_area"'))
    eq(MineCome.EndMovementFollower("b"),true);f:advance(.08)
    eq(MineCome.BeginPhysicalMovementFollower("c","wide"),true)
    eq(MineCome.ApplyMovementFollower("c",1,123,2040,56),true)
    ok,why=MineCome.ApplyMovementFollower("c",2,124.01,2040,56);eq(ok,false);eq(why,"target_out_of_bounds")
    ok,why=MineCome.ApplyMovementFollower("c",3,120,2040,57.51);eq(ok,false);eq(why,"target_out_of_bounds")
    assert(f:contains('"walking_area":"wide"'));eq(receipt_number(f:last(),"hard_deadline_ms"),8000)
    eq(MineCome.EndMovementFollower("c"),true);f:advance(.08);eq(f:activeTimers(),0)
end)
test("wide buffered motion crosses old footprint and restores without changing its lease",function()
    local f=buffered_fixture(true,"wide");local p=MineCome._movement_probe.follower;local hard=p.timers.hard
    eq(f:point(1,0,0),true)
    for i=1,16 do
        eq(f:point(i+1,i*100,i*.2),true);f:advance(.1)
        eq(p.timers.hard,hard);near(p.deadline,18)
    end
    assert(player.position.x>122,"crossed old 2m origin radius")
    eq(MineCome.FinishBufferedMovementFollower("b",17),true);f:advance(.35)
    eq(player.position.x,120);eq(f:activeTimers(),0)
    assert(f:contains('"event":"restored"'));assert(f:contains('"walking_area":"wide"'))
end)
test("wide profile survives module reload and retains bounds and source duration",function()
    local f=buffered_fixture(true,"wide");eq(f:point(1,0),true)
    local p=MineCome._movement_probe.follower;local hard=p.timers.hard
    dofile(MINECOME_MODULE_PATH);eq(p.timers.hard,hard);near(p.deadline,18)
    eq(f:point(2,100,3),true)
    local ok,why=f:point(3,200,4.01);eq(ok,false);eq(why,"target_out_of_bounds")
    f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
    f=buffered_fixture(true,"wide");eq(f:point(1,0),true)
    ok,why=f:point(2,16000.01,0);eq(ok,false);eq(why,"source_time_invalid")
    f:advance(.08);eq(player.position.x,120);eq(f:activeTimers(),0)
end)
print(string.format("Verified %d standalone movement-probe cases in %s; engine bindings simulated",passed,_VERSION))
print(string.format("Maximum tested buffered receipt: %d bytes plus CRLF; serialized subset of eight retained observations",maximum_buffered_receipt_bytes))
