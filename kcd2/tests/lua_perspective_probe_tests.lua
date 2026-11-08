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
 local f={ms=0,timers={},next=0,sets=0,resets=0,logs={},calls=0,draws={},bodyVisible=true,position={x=120,y=2040,z=56},camera={x=120,y=2040,z=57.6},forward={x=0,y=1,z=0},up={x=0,y=0,z=1},velocity={x=0,y=0,z=0}}
 local retained={untouched=true};MineCome={_block_sink=retained};player={id=io.stdout};f.entity=player
 local function forbidden() error('player/input/physics write invoked') end
 function player:GetWorldPos() eq(self,f.entity);f.calls=f.calls+1;return f.position end
 function player:GetVelocity() return f.velocity end
 player.SetWorldPos=forbidden
 function player:IsHidden() return false end
 function player:IsSlotValid(slot) eq(slot,0);return true end
 function player:IsSlotCharacter(slot) eq(slot,0);return true end
 function player:DrawSlot(slot,enabled)
  eq(self,f.entity);eq(slot,0);assert(enabled==0 or enabled==1);f.draws[#f.draws+1]=enabled;f.bodyVisible=enabled==1
  if f.drawFailures and f.drawFailures[#f.draws] then error('draw call failed after partial write') end
 end
 player.actor={GetLinkedEntity=function()return nil end,IsDead=function()return false end,IsUnconscious=function()return false end,
  GetAngles=function()return f.actorAngles or {x=0,y=0,z=0} end,GetViewAngleOffset=function()return {x=0,y=0,z=0} end,
  GetHeadDir=function()return f.headDirection or f.normalForward or {x=0,y=1,z=0} end,GetHeadPos=function()return f.headPosition or f.normalCamera or {x=120,y=2040,z=57.6} end,PlayerSetViewAngles=forbidden}
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
  if not f.ignoreReset then f.camera=copy(f.normalCamera or f.savedCamera);f.forward=copy(f.normalForward or f.savedForward);f.up=copy(f.normalUp or f.savedUp) end
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
test('look observation preserves bounds and does not cycle the camera',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,1200,'observe'),true)
 f:advance(600);eq(f.sets,1);eq(f.resets,0);assert(MineCome._perspective_probe.active.look_samples>=5)
 f:advance(800);eq(f.sets,1);eq(f.resets,1);f:terminal('restored')
end)
test('look bounds never widen original one-second diagnostic entry',function()
 local f=fixture();eq(f:begin('back',.25,1200),false)
 for _,duration in ipairs({99,15001,200.5,0/0,math.huge}) do eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,duration,'observe'),false) end
 for _,strategy in ipairs({'','follow','RESAMPLE',3}) do eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,1000,strategy),false) end
 eq(f.sets,0);eq(next(f.timers),nil)
end)
test('look observations include independent actor angles without using them',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true)
 f:advance(60);f.actorAngles={x=.4,y=0,z=.2};f:advance(100)
 local line=f.logs[#f.logs];assert(line:find('"actor_angles":{"x":0.40000000000000002',1,true));near(f.forward.z,0)
 f:advance(800);f:terminal('restored')
end)
test('same-callback resample follows simulated independent normal yaw and pitch',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'resample'),true)
 f:advance(60);f.normalForward={x=.6,y=0,z=.8};f.normalUp={x=-.8,y=0,z=.6}
 f:advance(100);local p=MineCome._perspective_probe.active;eq(p.normal_sample_immediate,true);eq(p.resample_resets,1);eq(p.resample_writes,1)
 near(f.forward.x,.6);near(f.forward.z,.8);near(f.camera.x,119.85);near(f.camera.z,57.4);near(f.position.x,120)
 f:advance(800);local line=f:terminal('restored');assert(line:find('"normal_view_position_restored":true,"original_view_basis_restored":false',1,true))
end)
test('same-callback reset without immediate normal readback retains prior target',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'resample'),true)
 f:advance(60);f.ignoreReset=true;f:advance(100);local p=MineCome._perspective_probe.active
 eq(p.normal_sample_immediate,false);eq(p.resample_writes,1);near(f.camera.y,2039.75)
 f:advance(800);f:terminal('restore_readback_failed')
end)
test('resample release failure falls through bounded final cleanup',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'resample'),true)
 f:advance(60);f.resetFailures=1;f:advance(200);eq(f.resets,2);eq(f.sets,1);f:terminal('restored')
end)
test('resample write failure resets again after possible partial change',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'resample'),true)
 f:advance(60);f.throwSet=true;f:advance(200);eq(f.resets,2);eq(f.sets,2);f:terminal('restored')
end)
test('look timer failure cancels bounded ownership',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true)
 f.failTimer='MineCome_PerspectiveProbeLook';f:advance(300);eq(f.resets,1);f:terminal('restored')
end)
test('look cancellation does not schedule a new sample after cleanup',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'front',.25,15000,'resample'),true)
 f:advance(200);eq(MineCome.EndPerspectiveProbe(RUN),true);f:advance(20000);f:terminal('restored');eq(f.sets,2);eq(f.resets,2)
end)
test('look restoration follows current native head after natural eye animation',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true)
 f:advance(60);f.normalCamera={x=120,y=2040.071,z=57.6};f.normalForward={x=.6,y=0,z=.8};f.normalUp={x=-.8,y=0,z=.6}
 f:advance(800);local line=f:terminal('restored');assert(line:find('"normal_view_position_restored":true,"original_view_basis_restored":false',1,true))
 near(f.position.y,2040);eq(f.sets,1);eq(f.resets,1)
end)
test('look restoration requires current head getters even when original view matches',function()
 for _,key in ipairs({'GetHeadPos','GetHeadDir'}) do
  local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true)
  f:advance(60);player.actor[key]=nil;f:advance(800);local line=f:terminal('restore_readback_failed')
  assert(line:find('"normal_view_position_restored":false,"original_view_basis_restored":true',1,true))
 end
end)
test('look restoration rejects mismatched eye direction and remote head',function()
 local mutations={
  function(f) f.headPosition={x=120.051,y=2040,z=57.6} end,
  function(f) f.headDirection={x=.03,y=math.sqrt(1-.03*.03),z=0} end,
  function(f) f.normalCamera={x=120,y=2040,z=59.01} end,
  function(f) f.headPosition={x=0/0,y=2040,z=57.6} end,
 }
 for _,mutate in ipairs(mutations) do
  local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true)
  f:advance(60);mutate(f);f:advance(800);f:terminal('restore_readback_failed');eq(f.resets,1)
 end
end)
test('static restoration still rejects eye motion even when it matches current head',function()
 local f=fixture();eq(f:begin(),true);f:advance(60);f.normalCamera={x=120,y=2040.071,z=57.6}
 f:advance(500);f:terminal('restore_readback_failed')
end)
test('body experiment is optional and does not write ordinary camera probes',function()
 local f=fixture();eq(f:begin(),true);f:advance(500);f:terminal('restored');eq(#f.draws,0)
 f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe'),true);f:advance(800);f:terminal('restored');eq(#f.draws,0)
 for _,bad in ipairs({1,'true',{},0}) do f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',bad),false);eq(f.sets,0);eq(#f.draws,0) end
end)
test('body experiment establishes visible baseline hides and restores slot zero',function()
 local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),true);f:advance(60)
 eq(#f.draws,2);eq(f.draws[1],1);eq(f.draws[2],0);eq(f.bodyVisible,false);near(f.position.y,2040)
 f:advance(800);local line=f:terminal('restored');eq(#f.draws,3);eq(f.draws[3],1);eq(f.bodyVisible,true)
 assert(line:find('"body_baseline_succeeded":true,"body_hide_succeeded":true,"body_restore_succeeded":true',1,true));assert(line:find('"body_visibility_readback_verified":false',1,true))
end)
test('body experiment refuses missing invalid or hidden player body before writes',function()
 local changes={function()player.DrawSlot=nil end,function()player.IsSlotValid=function()return false end end,
  function()player.IsSlotCharacter=function()return false end end,function()player.IsHidden=function()return true end end,
  function()player.IsSlotValid=function()return nil end end}
 for _,change in ipairs(changes) do local f=fixture();change();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),false);eq(#f.draws,0);eq(f.sets,0) end
end)
test('body partial hide failure still restores visible baseline and camera',function()
 local f=fixture();f.drawFailures={[2]=true};eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),true)
 f:advance(100);f:terminal('restored');eq(f.bodyVisible,true);eq(#f.draws,3);eq(f.resets,1);eq(MineCome._perspective_probe.last.body_hide_succeeded,false)
end)
test('body restore retries independently without duplicating camera reset',function()
 local f=fixture();f.drawFailures={[3]=true,[4]=true};eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),true)
 f:advance(1000);f:terminal('restored');eq(#f.draws,5);eq(f.resets,1);eq(f.bodyVisible,true)
end)
test('body restore permanent failure remains explicit and bounded',function()
 local f=fixture();f.drawFailures={[3]=true,[4]=true,[5]=true};eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),true)
 f:advance(1000);f:terminal('body_restore_failed');eq(#f.draws,5);eq(f.resets,1)
end)
test('body cleanup never draws on a replacement player or replaced binding',function()
 for _,replacement in ipairs({'entity','method'}) do local f=fixture();eq(MineCome.BeginPerspectiveLookProbe(RUN,'back',.25,700,'observe',true),true);f:advance(60)
  if replacement=='entity' then player={id=io.stderr} else player.DrawSlot=function()error('replacement must not be called')end end
  f:advance(1000);f:terminal('body_restore_failed');eq(#f.draws,2);eq(f.resets,1)
 end
end)
print('LUA_PERSPECTIVE_PROBE_TEST_PASS cases='..passed)
