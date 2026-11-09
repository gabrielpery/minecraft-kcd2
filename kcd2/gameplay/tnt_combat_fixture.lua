-- SPDX-License-Identifier: GPL-3.0-or-later
-- Two isolated passive NPCs for blast acceptance. Spawn/path APIs match the
-- inspected official PathfindDebugUtils used by combat_fixture.lua; ground rays
-- match ground_probe.lua's pinned Physics.RayWorldIntersection binding.
-- No native damage, existing actor mutation, player protection or camera writes.
MineCome=MineCome or {}
MineCome._tnt_combat_fixture=MineCome._tnt_combat_fixture or {}
local state=MineCome._tnt_combat_fixture
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<10000000 end
local function vector(v)return type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z)end
local function number(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function read(o,k,...)
 if type(o)~='table' or type(o[k])~='function'then return nil end
 local ok,v=pcall(o[k],o,...);if ok then return v end
end
local function owned(e)return e.entity and System.GetEntity(e.id)==e.entity and System.GetEntityByName(e.name)==e.entity and e.entity.id==e.id and e.entity.soul==e.soul end
local function gone(e)return not e.unknown and (not e.entity or System.GetEntity(e.id)==nil) and System.GetEntityByName(e.name)==nil end
local function allgone(p)for _,e in ipairs(p.actors)do if not gone(e)then return false end end;return true end
local function observe(e)
 if not owned(e)then return false end
 local hp=read(e.soul,'GetState','health');local maximum=read(e.entity.actor,'GetMaxHealth')
 if not finite(hp) or not finite(maximum) or maximum<=0 then return false end
 e.last_health=hp;e.maximum=maximum;e.health_samples=(e.health_samples or 0)+1;return true
end
local function emit(p,event,result)
 local rows={}
 for _,e in ipairs(p.actors)do
  observe(e)
  rows[#rows+1]='{"label":"'..e.label..'","raw_id":'..number(e.raw)..',"x":'..number(e.position.x)..',"y":'..number(e.position.y)..',"z":'..number(e.position.z)..',"health":'..number(e.last_health)..',"max_health":'..number(e.maximum)..',"health_samples":'..tostring(e.health_samples or 0)..',"health_observed":'..tostring((e.health_samples or 0)>0)..',"present":'..tostring(owned(e)==true)..',"removed":'..tostring(gone(e))..'}'
 end
 System.LogAlways('[MineComeTntCombatFixture] {"schema":1,"run":"'..p.run..'","event":"'..event..'","result":"'..result..'","active":'..tostring(state.active==p)..',"removed":'..tostring(allgone(p))..',"path_restored":'..tostring(p.path_restored==true)..',"actors":['..table.concat(rows,',')..']}')
end
local function finish(p)
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil end end
 if p.sample_timer then local ok,v=pcall(Script.KillTimer,p.sample_timer);if ok and v~=false then p.sample_timer=nil end end
 if p.wrapper and PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.wrapper then p.path_table.FindDataTable=p.original end
 p.path_restored=not p.wrapper or PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.original
 p.stopped=true;p.stopping=false;if state.active==p then state.active=nil end;state.last=p
 local good=allgone(p) and p.path_restored and p.timer==nil and p.sample_timer==nil
 emit(p,'terminal',good and p.reason or 'cleanup_unconfirmed');return good
end
local function cleanup(p)
 if allgone(p)then return finish(p)end
 if p.polls<=0 then return finish(p)end;p.polls=p.polls-1
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,50,'MineCome_TntCombatFixtureCleanup',data,true)
 if not ok or id==nil or id==false then return finish(p)end;p.timer=id;p.timer_data=data;return true
end
function MineCome_TntCombatFixtureCleanup(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or p.timer_data~=data or not p.stopping then return end
 p.timer=nil;p.timer_data=nil;cleanup(p)
end
local function stop(p,reason)
 if p.stopped then emit(p,'terminal',allgone(p) and p.path_restored and reason or 'cleanup_unconfirmed');return allgone(p) and p.path_restored end
 if p.stopping then return true end
 emit(p,'health','before_cleanup');p.reason=reason;p.stopping=true;p.polls=40
 if p.sample_timer then local ok,v=pcall(Script.KillTimer,p.sample_timer);if not ok or v==false then return finish(p)end;p.sample_timer=nil;p.sample_data=nil end
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if not ok or v==false then return finish(p)end;p.timer=nil end
 for _,e in ipairs(p.actors)do if not gone(e) and owned(e) and not e.remove_requested then e.remove_requested=true;pcall(System.RemoveEntity,e.id)end end
 return cleanup(p)
end
-- The official dummy despawns after its 3s wait/move and ten 1s waits
-- (Scripts.pak AI/haste/test_pathfollower_dummy.xml). Retain independent real
-- health observations before that happens; never label cached health as present.
local function schedule_sample(p)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,100,'MineCome_TntCombatFixtureSample',data,true)
 if not ok or id==nil or id==false then return false end;p.sample_timer=id;p.sample_data=data;return true
end
function MineCome_TntCombatFixtureSample(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or p.sample_data~=data or p.stopping or p.stopped then return end
 p.sample_timer=nil;p.sample_data=nil
 for _,e in ipairs(p.actors)do observe(e)end
 if not allgone(p) and not schedule_sample(p)then stop(p,'sample_timer_missing')end
end
function MineCome_TntCombatFixtureExpire(data)
 local p=type(data)=='table' and data.owner;if p and state.active==p and p.timer_data==data then p.timer=nil;stop(p,'expired')end
end
local function ground(x,y,z)
 local hits={};local ok,n=pcall(Physics.RayWorldIntersection,{x=x,y=y,z=z+4},{x=0,y=0,z=-12},4,ent_terrain,player.id,nil,hits)
 if not ok or not finite(n) or n~=math.floor(n) or n<1 or n>=4 then return nil end
 local best
 for i=1,n do local h=hits[i]
  if type(h)~='table' or not finite(h.dist) or h.dist<0 or h.dist>12 or not vector(h.pos) or not vector(h.normal) or h.normal.z<.5 or math.abs(h.pos.x-x)>.02 or math.abs(h.pos.y-y)>.02 or math.abs(h.pos.z-(z+4-h.dist))>.02 then return nil end
  if not best or h.dist<best.dist then best=h end
 end
 if hits[n+1]~=nil then return nil end
 return{x=x,y=y,z=best.pos.z+.05}
end
function MineCome.GameplayTntCombatFixtureBegin(run,duration)
 if type(run)~='string' or #run~=32 or not run:match('^[0-9a-f]+$') or not finite(duration) or duration~=math.floor(duration) or duration<1000 or duration>120000 then return false,'invalid_begin'end
 if state.active then return false,'fixture_owned'end
 if state.last and (not allgone(state.last) or not state.last.path_restored)then return false,'cleanup_unconfirmed'end
 if not player or not player.id or type(player.actor)~='table' or type(System)~='table' or type(System.GetEntity)~='function' or type(System.GetEntityByName)~='function' or type(System.RemoveEntity)~='function' or type(Physics)~='table' or type(Physics.RayWorldIntersection)~='function' or not finite(ent_terrain) or ent_terrain<=0 or type(XGenAIModule)~='table' or type(XGenAIModule.SpawnEntity)~='function' or type(PathfindDebugUtils)~='table' or type(PathfindDebugUtils.FindDataTable)~='function' or type(PathfindDebugUtils.GetNPCSpeed)~='function' or type(Script)~='table' or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function'then return false,'api_missing'end
 local feet=read(player,'GetWorldPos');local forward=read(player.actor,'GetHeadDir');local rotation=read(player,'GetAngles')
 if not vector(feet) or not vector(forward) or not vector(rotation)then return false,'view_invalid'end
 local length=math.sqrt(forward.x^2+forward.y^2);if length<.1 then return false,'view_vertical'end
 local p={run=run,actors={},path_table=PathfindDebugUtils,original=PathfindDebugUtils.FindDataTable,path_restored=true}
 for _,spec in ipairs({{'near',6},{'control',-9}})do
  local pos=ground(feet.x+forward.x/length*spec[2],feet.y+forward.y/length*spec[2],feet.z)
  if not pos then return false,'ground_unconfirmed'end
  local e={label=spec[1],name='MineComeTntCombat_'..run..'_'..spec[1],position=pos,rotation=rotation}
  if System.GetEntityByName(e.name)then return false,'name_occupied'end;p.actors[#p.actors+1]=e
 end
 state.active=p;local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,duration,'MineCome_TntCombatFixtureExpire',data,true)
 if not ok or id==nil or id==false then state.active=nil;return false,'timer_missing'end;p.timer=id;p.timer_data=data
 for _,e in ipairs(p.actors)do
  local params={ClassName='NPC',Name=e.name,SharedSoulGuid='88bee0ec-f164-4282-ae1e-6576a76b9bac',Properties={},Pos=e.position,Rot=e.rotation,PercepDestinationrObjectAI=false,PerceptibleObjectAI=false}
  local spawned,value=pcall(XGenAIModule.SpawnEntity,params);local entity=spawned and type(value)=='table' and value or nil
  if spawned and (type(value)=='userdata' or finite(value) and value>0 and value==math.floor(value))then entity=System.GetEntity(value)end
  local named=System.GetEntityByName(e.name)
  if type(named)=='table' and named~=player and named.id and named.class=='NPC' and type(named.actor)=='table' and type(named.soul)=='table' and read(named,'GetName')==e.name and System.GetEntity(named.id)==named then e.entity=named;e.id=named.id;e.soul=named.soul;e.raw=read(named,'GetRawId')end
  e.unknown=named~=nil and e.entity==nil
  if not spawned or not e.entity or entity~=e.entity then stop(p,'spawn_unconfirmed');return false,'spawn_unconfirmed'end
 end
 if PathfindDebugUtils~=p.path_table or p.path_table.FindDataTable~=p.original then stop(p,'path_changed');return false,'path_changed'end
 p.wrapper=function(id)for _,e in ipairs(p.actors)do if id==e.id and owned(e)then return{Pos={x=e.position.x,y=e.position.y,z=e.position.z},Rot={x=e.rotation.x,y=e.rotation.y,z=e.rotation.z}}end end;return p.original(id)end
 p.path_table.FindDataTable=p.wrapper;p.path_restored=false
 if not schedule_sample(p)then stop(p,'sample_timer_missing');return false,'sample_timer_missing'end
 emit(p,'begin','spawned');return true
end
function MineCome.GameplayTntCombatFixtureHealth(run)
 local p=state.active;if not p or p.run~=run then return false,'fixture_missing'end
 for _,e in ipairs(p.actors)do if not owned(e)then return false,'actor_changed'end end
 emit(p,'health','sampled');return true
end
function MineCome.GameplayTntCombatFixtureEnd(run)
 local p=state.active or state.last;if not p or p.run~=run then return false,'fixture_missing'end;return stop(p,'explicit_stop')
end
