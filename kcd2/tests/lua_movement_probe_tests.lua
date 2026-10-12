-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua5.2 runtime, simulated engine bindings. No live movement proof.
assert(type(MINECOME_MODULE_PATH) == "string")
local passed = 0
local function eq(a,b) assert(a==b,"got "..tostring(a)..", expected "..tostring(b)) end
local function test(name,fn) local ok,err=pcall(fn);if not ok then error(name..": "..tostring(err),0) end;passed=passed+1;print("PASS "..name) end
local function cp(v) return {x=v.x,y=v.y,z=v.z} end
local function fixture()
    local f={time=0,logs={},queue={},writes={},kills={},rays=0,schedules=0,nextId=1}
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
    System={GetCurrTime=function() return f.time end,LogAlways=function(line)
        if f.log_error then error("log failure") end;f.logs[#f.logs+1]=line end,
        GetViewCameraPos=function()
            if f.camera_bad then return nil end
            local p=f.fixed_camera or player.position;return {x=p.x,y=p.y,z=p.z+1.7}
        end,GetViewCameraDir=function() return {x=0,y=1,z=0} end,
        GetViewCameraUpDir=function() return {x=0,y=0,z=1} end,GetViewCameraFov=function() return 1.1 end,
        SetViewCamera=forbidden,ClearKeyState=forbidden,SpawnEntity=forbidden,RemoveEntity=forbidden}
    Script={SetTimerForFunction=function(ms,name,data,paused)
        eq(paused,true);assert(ms>=1 and ms<=(name=="MineCome_MovementFollowerExpiry" and 8000 or 750));f.schedules=f.schedules+1
        if f.fail_schedule==f.schedules then return nil end
        local id=f.nextId;f.nextId=id+1
        if f.userdata_timer and f.schedules==1 then id=io.stderr end
        f.queue[#f.queue+1]={id=id,at=f.time+ms/1000,name=name,data=data,alive=true};return id
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
print(string.format("Verified %d standalone movement-probe cases in %s; engine bindings simulated",passed,_VERSION))
