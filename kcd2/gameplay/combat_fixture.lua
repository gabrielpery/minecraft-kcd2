-- SPDX-License-Identifier: GPL-3.0-or-later
-- Optional isolated test actor. Exact official Scripts/Debug/PathfindDebugUtils
-- 30-58 supplies the NPC shared soul and XGenAIModule.SpawnEntity schema.
-- Owns only the unique newly-created actor, never existing NPCs/player state.
MineCome=MineCome or {}
MineCome._gameplay_combat_fixture=MineCome._gameplay_combat_fixture or {}
local state=MineCome._gameplay_combat_fixture
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function vector(v)return type(v)=='table' and finite(v.x) and finite(v.y) and finite(v.z)end
local function distance(a,b)return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
local function emit(p,event,result)
 System.LogAlways('[MineComeCombatFixture] {"schema":1,"run":"'..p.run..'","event":"'..event..'","result":"'..result..'","active":'..tostring(state.active==p)..',"removed":'..tostring(p.removed==true)..',"path_restored":'..tostring(p.path_restored~=false)..'}')
end
local function owned(p)
 return p.entity and System.GetEntity(p.id)==p.entity and System.GetEntityByName(p.name)==p.entity and p.entity.id==p.id and p.entity.soul==p.soul
end
local function gone(p)
 return (not p.entity or System.GetEntity(p.id)==nil) and System.GetEntityByName(p.name)==nil and not p.spawn_unknown
end
local function finish(p,removed)
 p.removed=removed;p.stopped=true;p.stopping=false
 if p.timer then Script.KillTimer(p.timer);p.timer=nil end;p.timer_data=nil
 if p.path_wrapper then
  if PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.path_wrapper then p.path_table.FindDataTable=p.path_original end
  p.path_restored=PathfindDebugUtils==p.path_table and p.path_table.FindDataTable==p.path_original
 else p.path_restored=true end
 if state.active==p then state.active=nil end;state.last=p
 local complete=removed and p.path_restored
 emit(p,'terminal',complete and p.reason or 'cleanup_unconfirmed');return complete
end
local function cleanup_poll(p)
 if gone(p)then return finish(p,true)end
 if not owned(p) or p.cleanup_polls<=0 then return finish(p,false)end
 p.cleanup_polls=p.cleanup_polls-1
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,50,'MineCome_CombatFixtureCleanupTick',data,true)
 if not ok or id==nil or id==false then return finish(p,false)end;p.timer=id;p.timer_data=data;return true
end
function MineCome_CombatFixtureCleanupTick(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or not p.stopping or p.timer_data~=data then return end
 p.timer=nil;p.timer_data=nil;cleanup_poll(p)
end
local function stop(p,reason)
 if p.stopped then
  -- A prior source version may already have reported an immediate readback
  -- failure. Refresh only disappearance; never issue RemoveEntity twice.
  if not p.removed and gone(p)then p.reason=reason;return finish(p,true)end
  return p.removed
 end
 if p.stopping then return true end
 p.stopping=true;p.reason=reason;p.cleanup_polls=40
 if p.timer then Script.KillTimer(p.timer);p.timer=nil end;p.timer_data=nil
 if gone(p)then return finish(p,true)end
 if not owned(p)then return finish(p,false)end
 -- Native deletion is deferred until an engine update. Issue it exactly once,
 -- retain the original references, and publish terminal only after readback.
 p.remove_requested=true;pcall(System.RemoveEntity,p.id)
 return cleanup_poll(p)
end
function MineCome_CombatFixtureExpire(data)
 local p=type(data)=='table' and data.owner;if p and state.active==p and p.timer_data==data then p.timer=nil;stop(p,'expired')end
end
function MineCome.GameplayCombatFixtureBegin(run,duration_ms,x,y,z)
 if type(run)~='string' or #run~=32 or not run:match('^[0-9a-f]+$') or not finite(duration_ms) or duration_ms~=math.floor(duration_ms) or duration_ms<1000 or duration_ms>120000 or not vector({x=x,y=y,z=z}) then return false,'invalid_fixture'end
 if state.active then return false,'fixture_owned'end
 if not player or not player.GetWorldPos or not XGenAIModule or type(XGenAIModule.SpawnEntity)~='function' or not System or type(System.GetEntity)~='function' or type(System.GetEntityByName)~='function' or type(System.RemoveEntity)~='function' or not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'fixture_api_missing'end
 if type(PathfindDebugUtils)~='table' or type(PathfindDebugUtils.FindDataTable)~='function' or type(PathfindDebugUtils.GetNPCSpeed)~='function' then return false,'fixture_path_api_missing'end
 local position={x=x,y=y,z=z};local feet=player:GetWorldPos()
 if not vector(feet) or distance(position,feet)>5 then return false,'fixture_too_far'end
 local p={run=run,name='MineComeCombat_'..run..'_fixture',path_table=PathfindDebugUtils,path_original=PathfindDebugUtils.FindDataTable,position=position,rotation=player:GetAngles()}
 if System.GetEntityByName(p.name)then return false,'fixture_name_occupied'end
 state.active=p;local data={owner=p};local ok,timer=pcall(Script.SetTimerForFunction,duration_ms,'MineCome_CombatFixtureExpire',data,true)
 if not ok or timer==nil or timer==false then state.active=nil;return false,'fixture_timer_missing'end;p.timer=timer;p.timer_data=data
 local spawned,result=pcall(XGenAIModule.SpawnEntity,{ClassName='NPC',Name=p.name,SharedSoulGuid='88bee0ec-f164-4282-ae1e-6576a76b9bac',Properties={},PercepDestinationrObjectAI=false,PerceptibleObjectAI=false,Pos=position,Rot=player:GetAngles()})
 local entity=spawned and type(result)=='table' and result or nil
 if spawned and (type(result)=='userdata' or (finite(result) and result>0 and result==math.floor(result)))then entity=System.GetEntity(result)end
 local named=System.GetEntityByName(p.name)
 -- SpawnEntity may create the actor and then fail/return an unexpected shape.
 -- Claim only a newly-created, exact-name NPC whose ID lookup agrees, so it can
 -- be cleaned up; do not report success for an unverified native return value.
 if type(named)=='table' and named.id~=nil and named~=player and named.class=='NPC' and type(named.actor)=='table' and type(named.soul)=='table' and type(named.GetName)=='function' and named:GetName()==p.name and System.GetEntity(named.id)==named then
  p.entity=named;p.id=named.id;p.soul=named.soul
 end
 if not spawned or not p.entity or entity~=p.entity then
  p.spawn_unknown=named~=nil and p.entity==nil;stop(p,'spawn_unconfirmed');return false,'spawn_unconfirmed'
 end
 p.entity=entity;p.id=entity.id;p.soul=entity.soul
 if type(p.soul)~='table' or type(entity.actor)~='table' then stop(p,'actor_unavailable');return false,'actor_unavailable'end
 if PathfindDebugUtils~=p.path_table or p.path_table.FindDataTable~=p.path_original then stop(p,'fixture_path_changed');return false,'fixture_path_changed'end
 -- Official test_pathfollower_dummy.xml asks this Lua function for its Move
 -- destination after3s. Pin only our fixture's destination to its own spawn;
 -- other test actors retain their original behavior and global Data untouched.
 p.path_wrapper=function(entity_id)
  if entity_id==p.id and owned(p)then return{Pos={x=p.position.x,y=p.position.y,z=p.position.z},Rot={x=p.rotation.x,y=p.rotation.y,z=p.rotation.z}}end
  return p.path_original(entity_id)
 end
 p.path_table.FindDataTable=p.path_wrapper;p.path_restored=false
 emit(p,'begin','spawned');return true
end
function MineCome.GameplayCombatFixtureEnd(run)
 local p=state.active
 if not p then if state.last and state.last.run==run then
  p=state.last;if not p.removed and gone(p)then p.reason='explicit_stop';return finish(p,true)end
  emit(p,'terminal',p.removed and p.path_restored~=false and 'explicit_stop' or 'cleanup_unconfirmed');return p.removed and p.path_restored~=false
 end;return false,'fixture_missing'end
 if p.run~=run then return false,'fixture_owned'end;return stop(p,'explicit_stop')
end
