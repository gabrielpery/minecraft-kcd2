local entities,names,timers={}, {}, {};local spawn_mode='entity';local calls=0;local logs={};local defer_remove=false
local run=string.rep('a',32);local last_entity
local function check(v,m)if not v then error(m,2)end end
player={id=99,GetWorldPos=function()return{x=0,y=0,z=0}end,GetAngles=function()return{x=0,y=0,z=0}end}
local original_find=function(id)return{Pos={x=id,y=88,z=99}}end
PathfindDebugUtils={FindDataTable=original_find,GetNPCSpeed=function()return 'walk'end,Data={untouched=true}}
System={GetEntity=function(id)check(type(id)=='number','invalid handle lookup');return entities[id]end,GetEntityByName=function(name)return names[name]end,RemoveEntity=function(id)calls=calls+1;if defer_remove then return end;local e=entities[id];if e then names[e.name]=nil;entities[id]=nil end end,LogAlways=function(s)logs[#logs+1]=s end}
Script={SetTimerForFunction=function(_,_,data)timers[1]=data;return 1 end,KillTimer=function(id)timers[id]=nil end}
XGenAIModule={SpawnEntity=function(params)
 check(params.ClassName=='NPC' and params.SharedSoulGuid=='88bee0ec-f164-4282-ae1e-6576a76b9bac','nonofficial test fixture')
 local e={id=1,name=params.Name,class='NPC',soul={},actor={},GetName=function(self)return self.name end};entities[1]=e;names[e.name]=e;last_entity=e
 if spawn_mode=='nil' then return nil elseif spawn_mode=='false' then return false elseif spawn_mode=='throw' then error('native return failed')elseif spawn_mode=='invalid_actor' then e.class='Other';return false elseif spawn_mode=='handle'then return e.id end;return e
end}
MineCome={};dofile(MINECOME_MODULE_PATH)
for _,mode in ipairs({'entity','handle'})do
 spawn_mode=mode;check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'valid spawn rejected')
 local destination=PathfindDebugUtils.FindDataTable(1);check(destination.Pos.x==0 and destination.Pos.y==2,'fixture did not hold own destination')
 check(PathfindDebugUtils.FindDataTable(55).Pos.x==55 and PathfindDebugUtils.Data.untouched,'unowned path or global Data changed')
 check(MineCome.GameplayCombatFixtureEnd(run),'cleanup failed');check(next(entities)==nil and next(timers)==nil,'owned entity/timer leaked')
 check(PathfindDebugUtils.FindDataTable==original_find,'original path function not restored')
end
for _,mode in ipairs({'nil','false','throw'})do spawn_mode=mode;local ok=MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0);check(not ok,'uncertain spawn accepted');check(next(entities)==nil and next(timers)==nil,'uncertain but identifiable spawn leaked');check(logs[#logs]:match('"removed":true'),'actual cleanup not recorded')end
spawn_mode='invalid_actor';local before=calls;check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'wrong named class adopted');check(calls==before,'unowned actor deleted');check(logs[#logs]:match('cleanup_unconfirmed') and logs[#logs]:match('"removed":false'),'unknown entity claimed removed');entities={};names={}
spawn_mode='entity';check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'spawn failed');local old=last_entity;local replacement={id=1,name=old.name,class='NPC',actor={},soul={}};entities[1]=replacement;names[old.name]=replacement;before=calls
check(not MineCome.GameplayCombatFixtureEnd(run),'replacement cleanup reported success');check(calls==before,'replacement actor removed')
entities={};names={};check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'expiry fixture failed');local data=timers[1];timers[1]=nil;MineCome_CombatFixtureExpire(data);check(next(entities)==nil,'expiry leaked actor')
-- Actual engine deletion completes on a later update. Stop queues one removal,
-- polls owned identity, then emits terminal only after both lookups disappear.
defer_remove=true;check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'deferred fixture failed');before=calls;local log_count=#logs
check(MineCome.GameplayCombatFixtureEnd(run),'deferred cleanup was treated as failure');check(calls==before+1 and #logs==log_count,'premature terminal or repeated remove')
check(MineCome.GameplayCombatFixtureEnd(run),'idempotent pending cleanup failed');check(calls==before+1,'pending removal retried')
local pending=timers[1];timers[1]=nil;MineCome_CombatFixtureCleanupTick(pending);check(#logs==log_count,'pending actor declared removed')
entities={};names={};pending=timers[1];timers[1]=nil;MineCome_CombatFixtureCleanupTick(pending)
check(logs[#logs]:match('"removed":true') and next(timers)==nil,'deferred disappearance unconfirmed')
-- Bounded polling cannot erase an actor which has replaced the original ID.
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'replacement pending fixture failed');check(MineCome.GameplayCombatFixtureEnd(run),'pending end failed');before=calls
old=last_entity;replacement={id=1,name=old.name,class='NPC',actor={},soul={}};entities[1]=replacement;names[old.name]=replacement
pending=timers[1];timers[1]=nil;MineCome_CombatFixtureCleanupTick(pending)
check(calls==before and logs[#logs]:match('cleanup_unconfirmed'),'replacement deleted or concealed during cleanup')
-- A later module reload/End may confirm eventual deletion after old evidence.
entities={};names={};check(MineCome.GameplayCombatFixtureEnd(run),'late disappearance not refreshed');check(logs[#logs]:match('"removed":true'),'late cleanup unconfirmed')
defer_remove=false;check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'path ownership fixture failed')
local other_find=function()return{Pos={x=77,y=77,z=77}}end;PathfindDebugUtils.FindDataTable=other_find
check(not MineCome.GameplayCombatFixtureEnd(run),'lost path ownership reported restored')
check(PathfindDebugUtils.FindDataTable==other_find and logs[#logs]:match('"path_restored":false'),'third-party path function overwritten')
PathfindDebugUtils.FindDataTable=original_find
print('PASS owned native NPC fixture cleanup: returned handle/object, post-create failure, unknown ownership, replacement, expiry (simulated engine)')
