-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sustained visual mirror of an authoritative Minecraft stone snapshot.
-- Inspected APIs are those used in lua/data/scripts/mods/minecome.lua:
-- Warhorse script_bind_2025_01_14 System Spawn/Get/RemoveEntity; entity
-- LoadObject/DrawSlot/SetWorldAngles/GetLocalBBox/GetWorldBBox/SetFlags;
-- Script.SetTimerForFunction/KillTimer. No native physics or save commands.
MineCome = MineCome or {}
MineCome._gameplay_blocks = MineCome._gameplay_blocks or {}
local state = MineCome._gameplay_blocks
local MODEL, CAPACITY, LEASE, BUDGET = 'objects/minecome/stone.cgf',64,2,8
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function integer(v,a,b)return finite(v) and v==math.floor(v) and v>=a and v<=b end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function clock()local ok,v=pcall(System.GetCurrTime);if ok and finite(v)then return v end end
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local function point(a,b)return type(a)=='table' and finite(a.x) and finite(a.y) and finite(a.z) and math.abs(a.x-b.x)<.001 and math.abs(a.y-b.y)<.001 and math.abs(a.z-b.z)<.001 end
local function emit(p,event,result)
 System.LogAlways('[MineComeGameplayBlocks] '..string.format('{"schema":1,"run":"%s","event":"%s","result":"%s","revision":%d,"count":%d,"spawned":%d,"removed":%d,"active":%s,"timers_cancelled":%s,"native_physics":false}',p.run,event,result,p.revision,count(p.owned),p.spawned,p.removed,tostring(state.active==p and not p.stopping),tostring(p.timer==nil)))
end
local function schedule(p,delay)
 if p.timer~=nil then return true end
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,delay,'MineCome_GameplayBlocksTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.timer_data=data;return true
end
local function stop(p,reason)
 if not p.stopping then p.stopping=true;p.reason=reason;p.cleanup_started=clock();p.desired={};p.pending=nil end
 return schedule(p,10)
end
local function entity_owned(r)
 local ok,a=pcall(System.GetEntity,r.id);local named,b=pcall(System.GetEntityByName,r.name)
 if not ok or not named then return false,false end
 if not a then return true,b==nil or b.id~=r.id end
 if not b or a.id~=r.id or b.id~=r.id then return false,false end
 if a.GetName then local good,name=pcall(a.GetName,a);if not good or name~=r.name then return false,false end end
 return true,false,a
end
local function remove(r)
 local owned,absent=entity_owned(r);if not owned then return false end;if absent then return true end
 local ok,v=pcall(System.RemoveEntity,r.id);if not ok or v==false then return false end
 owned,absent=entity_owned(r);return owned and absent
end
local function position(p,c)return{x=p.x+c.x,y=p.y-c.z,z=p.z+c.y-64}end
local function geometry(e,pos)
 local a,b=e:GetLocalBBox();local wa,wb=e:GetWorldBBox()
 -- Compiled Minecraft stone is corner-pivoted, not centered. Explicit zero
 -- angles prevent the engine's observed default -90-degree rotation.
 if not point(a,{x=0,y=-1,z=0}) or not point(b,{x=1,y=0,z=1}) or
  not point(wa,{x=pos.x,y=pos.y-1,z=pos.z}) or not point(wb,{x=pos.x+1,y=pos.y,z=pos.z+1})then error('geometry_mismatch')end
end
local function spawn(p,key,c)
 p.serial=p.serial+1;local name='MineCome_Gameplay_'..p.run..'_'..p.serial
 local ok,existing=pcall(System.GetEntityByName,name);if not ok or existing then return false end
 local pos=position(p,c);local good,e=pcall(System.SpawnEntity,{class='BasicEntity',name=name,position=pos,properties={object_Model=MODEL,Physics={bPhysicalize=false,bRigidBody=false,bPushableByPlayers=false}}})
 if not good or not e or not e.id then return false end
 local r={id=e.id,name=name,position=pos};p.owned[key]=r;p.spawned=p.spawned+1
 local loaded=pcall(function()
  if type(ENTITY_FLAG_NO_SAVE)=='number' and e.SetFlags then e:SetFlags(ENTITY_FLAG_NO_SAVE,0)end
  e:LoadObject(0,MODEL);e:SetWorldAngles({x=0,y=0,z=0});geometry(e,pos);e:DrawSlot(0,1)
 end)
 return loaded
end
function MineCome.GameplayBlocksBegin(run,duration_ms,x,y,z,minx,maxx,minz,maxz)
 if not token(run) or not integer(duration_ms,1000,86400000) or not finite(x) or not finite(y) or not finite(z) or math.abs(x)>10000000 or math.abs(y)>10000000 or math.abs(z)>10000000 or
  not integer(minx,-1024,1024) or not integer(maxx,-1024,1024) or not integer(minz,-1024,1024) or not integer(maxz,-1024,1024) or maxx<minx or maxz<minz or maxx-minx>8 or maxz-minz>8 then return false,'invalid_identity_or_bounds' end
 if state.active then return false,'session_owned' end
 if not System or type(System.SpawnEntity)~='function' or type(System.RemoveEntity)~='function' or type(System.GetEntity)~='function' or type(System.GetEntityByName)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'api_unavailable' end
 if not player or not player.id then return false,'player_unavailable' end
 local t=clock();if not t then return false,'clock_unavailable' end
 local p={run=run,x=x,y=y,z=z,minx=minx,maxx=maxx,minz=minz,maxz=maxz,created=t,deadline=t+duration_ms/1000,received=t,last_clock=t,revision=-1,owned={},desired={},serial=0,spawned=0,removed=0,player=player,player_id=player.id}
 state.active=p;if not schedule(p,100)then state.active=nil;return false,'timer_unavailable'end
 emit(p,'begin','ready');return true
end
function MineCome.GameplayBlocksHeartbeat(run)
 local p=state.active;if not p or p.run~=run or p.stopping then return false,'session_missing'end
 local t=clock();if not t or t<p.last_clock or t>=p.deadline or t-p.received>LEASE then stop(p,'lease_expired');return false,'lease_expired'end
 p.received=t;p.last_clock=t;return true
end
function MineCome.GameplayBlocksApply(run,revision,flat)
 local p=state.active;if not p or p.run~=run or p.stopping then return false,'session_missing'end
 if not integer(revision,0,10000000) or revision<=p.revision or p.pending or type(flat)~='table' or #flat>CAPACITY*3 or #flat%3~=0 then return false,'revision_or_capacity'end
 local desired={};local n=0
 for k in pairs(flat)do if not integer(k,1,#flat)then return false,'sparse_coordinates'end;n=n+1 end
 if n~=#flat then return false,'sparse_coordinates'end
 for i=1,#flat,3 do
  local x,y,z=flat[i],flat[i+1],flat[i+2]
  if not integer(x,p.minx,p.maxx) or not integer(z,p.minz,p.maxz) or not integer(y,56,80)then return false,'outside_capture'end
  local key=x..':'..y..':'..z;if desired[key]then return false,'duplicate_cell'end;desired[key]={x=x,y=y,z=z}
 end
 local ok,why=MineCome.GameplayBlocksHeartbeat(run);if not ok then return false,why end
 p.desired=desired;p.pending=revision;return true
end
function MineCome.GameplayBlocksEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then emit(state.last,'terminal',state.last.reason);return true end;return false,'session_missing'end
 if p.run~=run then return false,'session_owned'end
 return stop(p,'explicit_stop')
end
function MineCome_GameplayBlocksTick(data)
 if type(data)~='table'then return end;local p=data.owner
 if not p or state.active~=p or p.timer_data~=data then return end;p.timer=nil;p.timer_data=nil
 local t=clock()
 if not p.stopping and (not t or t<p.last_clock or t>=p.deadline or t-p.received>LEASE or player~=p.player or player.id~=p.player_id)then stop(p,'lease_or_world_changed')end
 if t then p.last_clock=t end
 local budget=BUDGET;local unresolved=false
 for key,r in pairs(p.owned)do
  if not p.desired[key] and budget>0 then
   budget=budget-1;if remove(r)then p.owned[key]=nil;p.removed=p.removed+1 else unresolved=true end
  end
 end
 if not p.stopping then
  for key,c in pairs(p.desired)do
   if not p.owned[key] and budget>0 then budget=budget-1;if not spawn(p,key,c)then stop(p,'spawn_or_geometry_failed');break end
   elseif p.owned[key]then local owned,absent,e=entity_owned(p.owned[key]);if not owned or absent or not pcall(geometry,e,p.owned[key].position)then stop(p,'ownership_or_geometry_changed');break end end
  end
 end
 if p.stopping then
  if count(p.owned)==0 then
   if p.timer then pcall(Script.KillTimer,p.timer);p.timer=nil;p.timer_data=nil end
   state.active=nil;state.last=p;emit(p,'terminal',p.reason);return
  end
  if t and p.cleanup_started and t-p.cleanup_started>2 then
   p.reason='cleanup_failed';if p.timer then pcall(Script.KillTimer,p.timer);p.timer=nil;p.timer_data=nil end
   emit(p,'terminal',p.reason);return -- retain ownership; never adopt/delete unknown entities
  end
 elseif p.pending~=nil and not unresolved and count(p.owned)==count(p.desired)then
  p.revision=p.pending;p.pending=nil;emit(p,'applied','mirrored')
 end
 if not schedule(p,(p.pending~=nil or p.stopping) and 10 or 100)then stop(p,'timer_unavailable')end
end
