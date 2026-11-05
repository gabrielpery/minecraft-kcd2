-- Standalone binding simulation; this does not establish live KCD rendering.
local A,B=string.rep('a',32),string.rep('b',32)
local passed=0
local function eq(a,b)assert(a==b,'got '..tostring(a)..', expected '..tostring(b))end
local function test(name,fn)local ok,err=pcall(fn);if not ok then error(name..': '..tostring(err),0)end;passed=passed+1;print('PASS '..name)end
local function fixture()
 local f={time=10,timers={},logs={},entities={},names={},serial=0,spawns=0,removes=0,callback=false}
 local retained={value='untouched'};MineCome={_block_sink=retained};player={id=17};ENTITY_FLAG_NO_SAVE=32
 System={GetCurrTime=function()return f.time end,LogAlways=function(s)f.logs[#f.logs+1]=s end,
  GetEntity=function(id)return f.entities[id]end,GetEntityByName=function(name)return f.names[name]end,
  SpawnEntity=function(args)
   eq(f.callback,true);eq(args.class,'BasicEntity');eq(args.properties.Physics.bPhysicalize,false);eq(args.properties.object_Model,'objects/minecome/stone.cgf')
   f.spawns=f.spawns+1;local e={id=100+f.spawns,name=args.name,position=args.position,angles=false}
   function e:GetName()return self.name end
   function e:LoadObject(slot,path)eq(slot,0);eq(path,'objects/minecome/stone.cgf');if f.fail_load then error('load failed')end end
   function e:SetWorldAngles(v)eq(v.x,0);eq(v.y,0);eq(v.z,0);self.angles=true end
   function e:GetLocalBBox()return{x=0,y=-1,z=0},{x=1,y=0,z=1}end
   function e:GetWorldBBox()assert(self.angles);local p=self.position;return{x=p.x,y=p.y-1,z=p.z},{x=p.x+(f.bad_geometry and 2 or 1),y=p.y,z=p.z+1}end
   function e:DrawSlot(slot,draw)eq(slot,0);eq(draw,1);self.drawn=true end
   function e:SetFlags(flag,mask)eq(flag,32);eq(mask,0)end
   f.entities[e.id]=e;f.names[e.name]=e;return e
  end,
  RemoveEntity=function(id)
   eq(f.callback,true);f.removes=f.removes+1
   if f.delayed and not f.delay_used then f.delay_used=true;return end
   local e=f.entities[id];if e then f.names[e.name]=nil;f.entities[id]=nil end
  end}
 Script={SetTimerForFunction=function(ms,name,data,paused)
   assert(type(ms)=='number' and ms>=10);eq(paused,true);f.serial=f.serial+1;f.timers[f.serial]={id=f.serial,name=name,data=data,ms=ms,alive=true};return f.serial
  end,KillTimer=function(id)assert(f.timers[id] and f.timers[id].alive);f.timers[id].alive=false end}
 dofile(MINECOME_MODULE_PATH);eq(MineCome._block_sink,retained);eq(f.serial,0);eq(f.spawns,0)
 function f:begin(run)return MineCome.GameplayBlocksBegin(run or A,86400000,120,2040,56,-4,3,-4,3)end
 function f:fire(advance)
  local e;for i=1,self.serial do if self.timers[i].alive then e=self.timers[i];break end end;assert(e,'No pending timer')
  e.alive=false;self.time=self.time+(advance or e.ms/1000);self.callback=true
  local ok,result=pcall(_G[e.name],e.data);self.callback=false;assert(ok,result)
 end
 function f:drain(n)for _=1,n do self:fire()end end
 function f:count()local n=0;for _ in pairs(self.entities)do n=n+1 end;return n end
 function f:reason(v)assert(self.logs[#self.logs]:find('"result":"'..v..'"',1,true),self.logs[#self.logs])end
 return f
end
test('begin and malformed snapshots make no entity writes',function()
 local f=fixture();eq(f:begin('bad'),false);eq(f:begin(),true);eq(f:begin(B),false);eq(f.spawns,0)
 eq(MineCome.GameplayBlocksApply(A,0,{4,64,0}),false);eq(MineCome.GameplayBlocksApply(A,0,{0,55,0}),false)
 eq(MineCome.GameplayBlocksApply(A,0,{0,64,0,0,64,0}),false);eq(MineCome.GameplayBlocksApply(A,0,{[1]=0,[3]=0}),false)
 eq(f.spawns,0)
end)
test('correct corner geometry and differential reconciliation',function()
 local f=fixture();assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{1,64,2}));f:fire();f:reason('mirrored');eq(f:count(),1)
 local e=f.entities[101];eq(e.position.x,121);eq(e.position.y,2038);eq(e.position.z,56);eq(e.drawn,true)
 assert(MineCome.GameplayBlocksApply(A,1,{1,64,2,1,65,2}));f:fire();eq(f:count(),2);eq(f.spawns,2)
 assert(MineCome.GameplayBlocksApply(A,2,{1,65,2}));f:fire();eq(f:count(),1);eq(f.removes,1)
 assert(MineCome.GameplayBlocksEnd(A));f:fire();eq(f:count(),0);eq(f.removes,2);f:reason('explicit_stop');eq(MineCome._gameplay_blocks.active,nil)
end)
test('work is bounded and snapshots survive a new session',function()
 local f=fixture();assert(f:begin());local flat={};for x=-4,3 do for z=-4,3 do flat[#flat+1]=x;flat[#flat+1]=64;flat[#flat+1]=z end end
 assert(MineCome.GameplayBlocksApply(A,0,flat));f:fire();eq(f:count(),8);f:drain(7);eq(f:count(),64);f:reason('mirrored')
 assert(MineCome.GameplayBlocksEnd(A));f:drain(8);eq(f:count(),0);assert(f:begin(B));assert(MineCome.GameplayBlocksApply(B,0,{0,64,0}));f:fire();eq(f:count(),1)
end)
test('lease expiry cleans only owned entities',function()
 local f=fixture();f.entities[99]={id=99,name='foreign'};f.names.foreign=f.entities[99]
 assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{0,64,0}));f:fire();f:fire(2.1);eq(f:count(),1);eq(f.entities[99].name,'foreign');f:reason('lease_or_world_changed')
end)
test('world replacement retires the current visuals',function()
 local f=fixture();assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{0,64,0}));f:fire();player={id=18};f:fire();eq(f:count(),0);f:reason('lease_or_world_changed')
end)
test('failed geometry and deferred removal are cleaned',function()
 local f=fixture();f.bad_geometry=true;assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{0,64,0}));f:fire();f:fire();eq(f:count(),0);f:reason('spawn_or_geometry_failed')
 f=fixture();f.delayed=true;assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{0,64,0}));f:fire();assert(MineCome.GameplayBlocksEnd(A));f:fire();eq(f:count(),1);f:fire();eq(f:count(),0);f:reason('explicit_stop')
end)
test('renamed id is preserved and incomplete cleanup is explicit',function()
 local f=fixture();assert(f:begin());assert(MineCome.GameplayBlocksApply(A,0,{0,64,0}));f:fire()
 local e=f.entities[101];f.names[e.name]=nil;e.name='not_ours';f.names[e.name]=e
 assert(MineCome.GameplayBlocksEnd(A));f:fire(2.1);eq(f.removes,0);eq(f:count(),1);f:reason('cleanup_failed');eq(f:begin(B),false)
end)
test('expanded captured bounds preserve corner geometry and outer limits',function()
 local f=fixture()
 eq(MineCome.GameplayBlocksBegin(A,10000,120,2040,56,-69,67,-68,67),false)
 assert(MineCome.GameplayBlocksBegin(A,10000,120,2040,56,-68,67,-68,67))
 eq(MineCome.GameplayBlocksApply(A,0,{68,64,0}),false)
 assert(MineCome.GameplayBlocksApply(A,0,{7,64,-9}));f:fire();eq(f:count(),1)
 local e=f.entities[101];eq(e.position.x,127);eq(e.position.y,2049);eq(e.position.z,56)
 assert(MineCome.GameplayBlocksEnd(A));f:fire();eq(f:count(),0);f:reason('explicit_stop')
end)
print('PASS '..passed..' gameplay block lifecycle tests (simulated bindings)')
