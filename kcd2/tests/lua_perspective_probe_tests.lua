-- SPDX-License-Identifier: GPL-3.0-or-later
-- Actual Lua runtime, fake engine. These tests establish guarded ownership and
-- cleanup only; they do not establish KCD camera behavior or native mouse look.
assert(type(MINECOME_MODULE_PATH)=='string')
local RUN='0123456789abcdef0123456789abcdef'
local passed=0
local function eq(a,b) assert(a==b,'got '..tostring(a)..', expected '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<1e-8) end
local function copy(v) return {x=v.x,y=v.y,z=v.z} end
local function test(name,fn) local ok,e=pcall(fn);if not ok then error(name..': '..tostring(e),0) end;passed=passed+1;print('PASS '..name) end
local function fixture()
 local f={ms=0,timers={},next=0,sets=0,resets=0,logs={},calls=0,position={x=120,y=2040,z=56},camera={x=120,y=2040,z=57.6},forward={x=0,y=1,z=0},up={x=0,y=0,z=1},velocity={x=0,y=0,z=0}}
 local retained={untouched=true};MineCome={_block_sink=retained};player={id=io.stdout};f.entity=player
 local function forbidden() error('player/input/physics write invoked') end
 function player:GetWorldPos() eq(self,f.entity);f.calls=f.calls+1;return f.position end
 function player:GetVelocity() return f.velocity end
 player.SetWorldPos=forbidden
 player.actor={GetLinkedEntity=function()return nil end,IsDead=function()return false end,IsUnconscious=function()return false end,
  GetHeadDir=function()return {x=0,y=1,z=0} end,GetHeadPos=function()return {x=120,y=2040,z=57.6} end,PlayerSetViewAngles=forbidden}
 player.player={IsSitting=function()return false end,IsLaying=function()return false end};player.human={IsMounted=function()return false end}
 Physics={RayWorldIntersection=forbidden}
 System={GetCurrTime=function()return f.ms/1000 end,GetViewCameraPos=function()return f.camera end,GetViewCameraDir=function()return f.forward end,GetViewCameraUpDir=function()return f.up end,GetViewCameraFov=function()return 1.2 end,
  LogAlways=function(line) if f.failLog then return false end;f.logs[#f.logs+1]=line end}
 CryAction={SetViewCamera=function(pos,dir)
  f.sets=f.sets+1;eq(type(pos.x),'number');eq(pos[1],nil);eq(type(dir[1]),'number');eq(dir.x,nil)
  f.savedCamera=copy(f.camera);f.savedForward=copy(f.forward);f.savedUp=copy(f.up)
  if not f.ignoreSet then f.camera=copy(pos);f.forward={x=dir[1],y=dir[2],z=dir[3]} end
  if f.throwSet then error('set after partial change') end
  if f.falseSet then return false end
 end,ResetToNormalCamera=function()
  f.resets=f.resets+1
  if f.failReset or (f.resetFailures and f.resets<=f.resetFailures) then error('reset unavailable') end
  if not f.ignoreReset then f.camera=copy(f.savedCamera);f.forward=copy(f.savedForward);f.up=copy(f.savedUp) end
 end}
 Script={SetTimerForFunction=function(ms,name,data,update)
  eq(update,true);f.next=f.next+1
  if f.failTimer==name or f.failTimerNumber==f.next then return nil end
  f.timers[f.next]={at=f.ms+ms,name=name,data=data};return f.next
 end,KillTimer=function(id) f.timers[id]=nil;return not f.failKill end}
 dofile(MINECOME_MODULE_PATH);eq(f.calls,0);eq(f.sets,0);eq(f.resets,0);eq(#f.logs,0);eq(MineCome._block_sink,retained)
 function f:begin(mode,offset,duration) return MineCome.BeginPerspectiveProbe(RUN,mode or 'back',offset,duration) end
 function f:advance(ms)
  local untilMs=self.ms+ms;local safety=0
  while true do
   local chosen,t
   for id,v in pairs(self.timers) do if v.at<=untilMs and (not t or v.at<t.at or (v.at==t.at and id<chosen)) then chosen,t=id,v end end
   if not chosen then break end
   safety=safety+1;assert(safety<30,'unbounded timer loop');self.ms=t.at;self.timers[chosen]=nil;_G[t.name](t.data)
  end
  self.ms=untilMs
 end
 function f:terminal(result)
  assert(MineCome._perspective_probe.active==nil);eq(next(self.timers),nil)
  local line=self.logs[#self.logs];assert(line and line:find('"terminal":true',1,true))
  assert(line:find('"result":"'..result..'"',1,true),line);assert(line:find('"player_writes":0',1,true))
  assert(not line:find('userdata:',1,true));assert(not line:lower():find(':nan',1,true));return line
 end
 return f
end
test('inert load; rear offset preserves feet and restores automatically',function()
 local f=fixture();eq(f:begin(),true);eq(f.sets,0);f:advance(60);eq(f.sets,1);near(f.camera.y,2039.75);near(f.position.y,2040)
 assert(MineCome._perspective_probe.active.camera_readback);f:advance(500);eq(f.resets,1);f:terminal('restored');near(f.camera.y,2040)
end)
test('front offset reverses viewing direction only and restores basis',function()
 local f=fixture();eq(f:begin('front',2.5,1000),true);f:advance(60);near(f.camera.y,2042.5);near(f.forward.y,-1);near(f.position.y,2040)
 f:advance(1100);eq(f.resets,1);f:terminal('restored');near(f.forward.y,1)
end)
test('invalid run mode distance and duration cannot mutate engine',function()
 local f=fixture();for _,run in ipairs({'',string.rep('a',31),'A'..RUN:sub(2),'a"\n',7}) do eq(MineCome.BeginPerspectiveProbe(run,'back'),false) end
 for _,mode in ipairs({'','left','BACK',1}) do eq(f:begin(mode),false) end
 for _,offset in ipairs({0,-1,2.5001,math.huge,0/0,'1'}) do eq(f:begin('back',offset),false) end
 for _,duration in ipairs({99,1001,100.5,math.huge,0/0,'100'}) do eq(f:begin('back',1,duration),false) end
 eq(f.sets,0);eq(f.calls,0);eq(next(f.timers),nil)
end)
test('missing mandatory binding or reset refuses before write',function()
 for _,key in ipairs({'SetViewCamera','ResetToNormalCamera'}) do local f=fixture();CryAction[key]=nil;eq(f:begin(),false);eq(f.sets,0) end
 local f=fixture();System.GetCurrTime=nil;eq(f:begin(),false);eq(f.sets,0)
 f=fixture();Script.KillTimer=nil;eq(f:begin(),false);eq(f.sets,0)
end)
test('head getters are optional observations not authority',function()
 local f=fixture();player.actor.GetHeadDir=nil;player.actor.GetHeadPos=function() error('optional getter') end
 eq(f:begin(),true);f:advance(500);local line=f:terminal('restored');assert(line:find('"head_position":null,"head_direction":null',1,true))
end)
test('active movement and diagnostic owner reject camera probe',function()
 for _,owner in ipairs({'gameplay','diagnostic','follower'}) do local f=fixture()
  if owner=='gameplay' then MineCome._gameplay_movement={active={}} else MineCome._movement_probe={[owner=='follower' and 'follower' or 'active']={}} end
  eq(f:begin(),false);eq(f.sets,0)
 end
 local f=fixture();eq(f:begin(),true);eq(f:begin(),false);f:advance(500);eq(f.sets,1)
end)
test('unsafe player identity state velocity or camera rejected',function()
 local setters={function()player.id='fake'end,function()player.actor.IsDead=function()return true end end,function()player.actor.GetLinkedEntity=function()return io.stderr end end,
  function(f)f.velocity.x=.1 end,function(f)f.forward.y=.5 end,function(f)f.camera.y=2044 end,function(f)f.position.x=0/0 end}
 for _,setter in ipairs(setters) do local f=fixture();setter(f);eq(f:begin(),false);eq(f.sets,0);eq(next(f.timers),nil) end
end)
test('all cleanup deadlines must be armed before write',function()
 for n=1,4 do local f=fixture();f.failTimerNumber=n;eq(f:begin(),false);eq(f.sets,0);eq(f.resets,0);f:terminal('timer_failed_before_write') end
end)
test('cancel before apply cancels every timer without camera write',function()
 local f=fixture();eq(f:begin(),true);eq(MineCome.EndPerspectiveProbe(RUN),true);f:advance(1000);eq(f.sets,0);eq(f.resets,0);f:terminal('explicit_cancel')
end)
test('wrong token cancellation leaves actual deadline active',function()
 local f=fixture();eq(f:begin(),true);eq(MineCome.EndPerspectiveProbe(string.rep('a',32)),false);f:advance(500);f:terminal('restored')
end)
test('cancel after apply resets automatically',function()
 local f=fixture();eq(f:begin(),true);f:advance(2);eq(MineCome.EndPerspectiveProbe(RUN),true);f:advance(60);eq(f.resets,1);f:terminal('restored')
end)
test('throwing or false camera write still invokes captured reset',function()
 for _,kind in ipairs({'throwSet','falseSet'}) do local f=fixture();f[kind]=true;eq(f:begin(),true);f:advance(100);eq(f.resets,1);f:terminal('restored') end
end)
test('ignored camera write fails readback and releases override',function()
 local f=fixture();f.ignoreSet=true;eq(f:begin(),true);f:advance(150);eq(f.resets,1);f:terminal('restored');eq(MineCome._perspective_probe.last.camera_readback,false)
end)
test('player movement during probe releases without moving feet',function()
 local f=fixture();eq(f:begin(),true);f:advance(2);f.position.x=120.1;f:advance(150);eq(f.resets,1);near(f.position.x,120.1);f:terminal('restore_readback_failed')
end)
test('player replacement releases owned camera but never changes player',function()
 local f=fixture();eq(f:begin(),true);f:advance(2);player={id=io.stderr};f:advance(150);eq(f.resets,1);eq(player.id,io.stderr);f:terminal('restore_readback_failed')
end)
test('late apply or changed API refuses before write',function()
 local f=fixture();eq(f:begin(),true);local t=f.timers[4];f.timers[4]=nil;f.ms=150;_G[t.name](t.data);eq(f.sets,0);f:terminal('enqueue_expired')
 f=fixture();eq(f:begin(),true);CryAction.SetViewCamera=function()error('replacement called')end;f:advance(2);eq(f.sets,0);f:terminal('api_changed_before_write')
end)
test('sample timer failure restores immediately',function()
 local f=fixture();f.failTimer='MineCome_PerspectiveProbeSample';eq(f:begin(),true);f:advance(100);eq(f.resets,1);f:terminal('restored')
end)
test('restore verification timer failure records only immediate readback',function()
 local f=fixture();f.failTimer='MineCome_PerspectiveProbeVerify';eq(f:begin(),true);f:advance(500);eq(f.resets,1);f:terminal('restored_without_delayed_sample')
end)
test('bounded reset retries recover transient failure',function()
 local f=fixture();f.resetFailures=2;eq(f:begin(),true);f:advance(600);eq(f.resets,3);f:terminal('restored')
end)
test('permanent reset failure is explicit terminal failure after three attempts',function()
 local f=fixture();f.failReset=true;eq(f:begin(),true);f:advance(600);eq(f.resets,3);local line=f:terminal('reset_failed');assert(line:find('"reset_succeeded":false',1,true))
end)
test('reset success without camera restoration cannot claim restored',function()
 local f=fixture();f.ignoreReset=true;eq(f:begin(),true);f:advance(600);eq(f.resets,1);f:terminal('restore_readback_failed')
end)
test('logger failure after applying cannot skip release',function()
 local f=fixture();eq(f:begin(),true);f.failLog=true;f:advance(500);eq(f.resets,1);eq(next(f.timers),nil);eq(MineCome._perspective_probe.active,nil)
end)
test('reload and stale callbacks cannot duplicate camera writes or resets',function()
 local f=fixture();eq(f:begin(),true);local old=f.timers[4];dofile(MINECOME_MODULE_PATH);f:advance(500);f:terminal('restored')
 _G[old.name](old.data);eq(f.sets,1);eq(f.resets,1)
 eq(f:begin(),true);_G[old.name](old.data);f:advance(500);eq(f.sets,2);eq(f.resets,2);f:terminal('restored')
end)
print('LUA_PERSPECTIVE_PROBE_TEST_PASS cases='..passed)
