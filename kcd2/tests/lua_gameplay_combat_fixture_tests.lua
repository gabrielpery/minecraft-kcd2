local entities,names,timers={}, {}, {};local spawn_mode='entity';local calls=0;local logs={};local defer_remove=false
local run=string.rep('a',32);local last_entity,last_params;local profiles,weapons,spawns=0,0,0;local profile_mode='normal'
local expected_preset='10101010-c8cb-81dd-40f1-2f0554804f83';local weapon_count,ammo_count=1,80;local draws,switches=0,0;local stats,skills={},{}
local function check(v,m)if not v then error(m,2)end end
player={id=99,GetWorldPos=function()return{x=0,y=0,z=0}end,GetAngles=function()return{x=0,y=0,z=0}end}
local original_find=function(id)return{Pos={x=id,y=88,z=99}}end
PathfindDebugUtils={FindDataTable=original_find,GetNPCSpeed=function()return 'walk'end,Data={untouched=true}}
System={GetEntity=function(id)check(type(id)=='number','invalid handle lookup');return entities[id]end,GetEntityByName=function(name)return names[name]end,RemoveEntity=function(id)calls=calls+1;if defer_remove then return end;local e=entities[id];if e then names[e.name]=nil;entities[id]=nil end end,LogAlways=function(s)logs[#logs+1]=s end}
Script={SetTimerForFunction=function(_,_,data)timers[1]=data;return 1 end,KillTimer=function(id)timers[id]=nil end}
XGenAIModule={SpawnEntity=function(params)
 spawns=spawns+1;last_params=params
 check(params.ClassName=='NPC' and (params.SharedSoulGuid=='88bee0ec-f164-4282-ae1e-6576a76b9bac' or params.SharedSoulGuid=='d2a3c045-2d43-491c-80a4-96137fcb99de'),'nonofficial test fixture')
 local e={id=1,name=params.Name,class='NPC',soul={SetStatLevelDebug=function(_,key,value)stats[key]=value end,SetSkillLevelDebug=function(_,key,value)skills[key]=value end},actor={},GetName=function(self)return self.name end};entities[1]=e;names[e.name]=e;last_entity=e
 e.actor.EquipWeaponPreset=function(_,preset)check(entities[1]==e and names[e.name]==e and e~=player,'unowned weapon mutation');check(preset==expected_preset,'wrong hostile preset');weapons=weapons+1 end
 local melee={['65a211bd-2c7e-40a8-984f-66c8730444e4']=1,['55f81ddb-7c17-41c5-a17c-c9948766c1c8']=1,['9aa773b1-ede0-4ff5-bbd8-2595b36c8a1a']=1,['a8eb10aa-84eb-416f-8ed2-46d909a26552']=1}
 local function is_ammo(class)return class=='ad6f0f01-aec4-44d1-982c-1210eb01b74a' or class=='166b4c7b-5e17-48db-bf0d-02f24eacdcbf'end
 e.inventory={GetCountOfClass=function(_,class)if melee[class]~=nil then return melee[class]end;if is_ammo(class)then return ammo_count end;check(class=='9e31a288-7de0-4c0d-81cd-5cf00548d2d5' or class=='b4a0b9c9-bf92-4cce-ad43-f20f57c892b9' or class=='b77f912a-042b-47ca-8f42-5fddbcad3763','unexpected weapon readback');return weapon_count end,DeleteItemOfClass=function(_,class,count)check(melee[class]==1 and count==1 and entities[1]==e and names[e.name]==e,'foreign/unexpected item deletion');if spawn_mode~='remove_failed' then melee[class]=0 end end}
 e.inventory.FindItem=function(_,class)check(is_ammo(class),'unexpected ammo lookup');return 'ownedAmmo'end
 e.actor.EquipInventoryItem=function(_,item)check(item=='ownedAmmo' and entities[1]==e and names[e.name]==e,'unowned ammo equip')end
 e.human={DrawWeapon=function()check(entities[1]==e and names[e.name]==e,'unowned weapon draw');draws=draws+1 end,ToggleWeaponSet=function(_,index)check(index==1 and entities[1]==e and names[e.name]==e,'wrong ranged set/owner');switches=switches+1 end}
 if spawn_mode=='no_weapon' then e.actor.EquipWeaponPreset=nil end
 if spawn_mode=='no_inventory' then e.inventory=nil elseif spawn_mode=='no_draw'then e.human.DrawWeapon=nil elseif spawn_mode=='no_switch'then e.human.ToggleWeaponSet=nil elseif spawn_mode=='no_remove'then e.inventory.DeleteItemOfClass=nil end
 if spawn_mode=='nil' then return nil elseif spawn_mode=='false' then return false elseif spawn_mode=='throw' then error('native return failed')elseif spawn_mode=='invalid_actor' then e.class='Other';return false elseif spawn_mode=='handle'then return e.id end;return e
end}
CombatDebug={SetSkillProfile=function(e,level)
 check(entities[e.id]==e and names[e.name]==e and e~=player,'unowned profile mutation');check(level==1,'hostile fixture not novice');profiles=profiles+1
 if profile_mode=='throw' then error('profile setup failed')elseif profile_mode=='replace'then entities[e.id]={id=e.id,name=e.name,class='NPC',soul={},actor={}};names[e.name]=entities[e.id]end
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
-- Hostile mode is explicit and uses the official basic-AI enemy, retaining
-- perception and native AI while avoiding every path-follower override.
local path_before=PathfindDebugUtils;PathfindDebugUtils=nil
before=profiles;local before_weapons=weapons
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile'),'hostile fixture rejected without unrelated path API')
check(last_params.SharedSoulGuid=='d2a3c045-2d43-491c-80a4-96137fcb99de' and last_params.PercepDestinationrObjectAI==nil and last_params.PerceptibleObjectAI==nil,'hostile perception disabled or wrong soul')
check(last_params.Rot.x==0 and last_params.Rot.y==0 and math.abs(last_params.Rot.z-math.pi)<.00001,'hostile enemy not facing player')
check(profiles==before+1 and weapons==before_weapons+1 and logs[#logs]:match('"mode":"hostile"'),'hostile setup/receipt incomplete')
check(PathfindDebugUtils==nil,'hostile fixture installed path wrapper');check(MineCome.GameplayCombatFixtureEnd(run),'hostile cleanup failed')
check(next(entities)==nil and next(timers)==nil and logs[#logs]:match('"path_restored":true'),'hostile resources leaked')
PathfindDebugUtils=path_before
local combat_before=CombatDebug;CombatDebug=nil;before=spawns
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile'),'missing combat API admitted')
check(spawns==before and next(timers)==nil,'missing API mutated state');CombatDebug=combat_before
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'unknown') and spawns==before,'invalid fixture mode mutated state')
spawn_mode='no_weapon';before=profiles;before_weapons=weapons
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile'),'missing owned weapon API admitted')
check(profiles==before and weapons==before_weapons and next(entities)==nil and next(timers)==nil,'post-spawn API failure mutated profile or leaked fixture')
spawn_mode='entity';profile_mode='throw';before_weapons=weapons
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile'),'partial profile exception admitted')
check(weapons==before_weapons and next(entities)==nil and next(timers)==nil,'profile failure continued setup or leaked fixture')
profile_mode='replace';before_weapons=weapons;before=calls
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile'),'replacement during profile admitted')
check(weapons==before_weapons and calls==before and logs[#logs]:match('cleanup_unconfirmed'),'replacement mutated or deleted')
entities={};names={};profile_mode='normal';check(MineCome.GameplayCombatFixtureEnd(run),'late hostile removal unconfirmed')
-- Armed fixtures retain real native AI. The bow has verified inventory ammo,
-- meets its official stat requirements and requests the ranged weapon set.
expected_preset='9b042396-e438-4a79-ab9d-138c12cda0a6';before=draws;local switches_before=switches
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0,'hostile_sword'),'sword rejected')
check(draws==before+1 and switches==switches_before and logs[#logs]:match('"weapon_count":1') and logs[#logs]:find(expected_preset,1,true),'sword preset/draw/readback missing')
check(MineCome.GameplayCombatFixtureEnd(run),'sword cleanup failed')
expected_preset='540bab62-09ea-41a9-bc44-e30a8cf98d56';before=draws
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_bow'),'bow rejected')
check(draws==before+1 and switches==switches_before+1 and stats.strength==22 and stats.agility==22 and stats.courage==30 and skills.marksmanship==22,'bow ranged selection/stats/draw missing')
check(logs[#logs]:match('"ammo_count":80') and logs[#logs]:match('"ranged_set_requested":true') and logs[#logs]:find(expected_preset,1,true),'bow inventory receipt incomplete')
check(PathfindDebugUtils.FindDataTable==original_find and MineCome.GameplayCombatFixtureEnd(run),'bow AI or cleanup changed')
before=spawns
for _,point in ipairs({2,5.49,8.01})do check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,point,0,'hostile_bow'),'bow unsafe range accepted')end
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_sword') and not MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile'),'armed range leaked to melee')
check(spawns==before,'invalid range spawned fixture')
for _,missing in ipairs({'no_inventory','no_draw','no_switch','no_remove'})do
 spawn_mode=missing;before=profiles;before_weapons=weapons
 check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_bow'),'missing bow API accepted')
 check(profiles==before and weapons==before_weapons and next(entities)==nil and next(timers)==nil,'missing API setup or cleanup failed')
end
spawn_mode='entity'
spawn_mode='remove_failed';before=draws;switches_before=switches
check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_bow'),'failed melee removal accepted')
check(draws==before and switches==switches_before and next(entities)==nil and next(timers)==nil,'failed melee removal drew or leaked fixture');spawn_mode='entity'
for _,missing in ipairs({'weapon','ammo'})do
 weapon_count=missing=='weapon' and 0 or 1;ammo_count=missing=='ammo' and 0 or 80;before=draws;switches_before=switches
 check(not MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_bow'),'empty bow inventory accepted')
 check(draws==before and switches==switches_before and next(entities)==nil and next(timers)==nil,'incomplete bow drew weapon or leaked')
end
weapon_count=1;ammo_count=80;expected_preset='10101010-c8cb-81dd-40f1-2f0554804f83'
expected_preset='1a5e4d64-f240-4596-b0c6-49e11c047468';ammo_count=65;before=draws;switches_before=switches
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,6,0,'hostile_crossbow'),'crossbow rejected')
check(draws==before+1 and switches==switches_before+1 and logs[#logs]:match('"ammo_count":65') and logs[#logs]:match('"melee_items_removed":true') and logs[#logs]:match('"ammo_equip_requested":true'),'crossbow native equipment proof missing')
check(MineCome.GameplayCombatFixtureEnd(run),'crossbow cleanup failed');expected_preset='10101010-c8cb-81dd-40f1-2f0554804f83';ammo_count=80
-- Default remains passive; hostile configuration must not leak across runs.
before=profiles;before_weapons=weapons
check(MineCome.GameplayCombatFixtureBegin(run,1000,0,2,0),'passive regression after hostile mode')
check(last_params.SharedSoulGuid=='88bee0ec-f164-4282-ae1e-6576a76b9bac' and last_params.PercepDestinationrObjectAI==false and last_params.PerceptibleObjectAI==false and profiles==before and weapons==before_weapons,'hostile configuration leaked to passive mode')
check(MineCome.GameplayCombatFixtureEnd(run),'final passive cleanup failed')
print('PASS owned native NPC passive/unarmed/sword/bow/crossbow fixtures: official presets, ranged ammo/selection/stats, bounded geometry, missing APIs, uncertain spawn, replacement, expiry and deferred cleanup (simulated engine)')
