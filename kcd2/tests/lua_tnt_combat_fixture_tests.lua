local entities,names,timers,logs={},{},{},{}
local next_id,removed=0,0;local mode='ok';local deferred=false
local run=string.rep('a',32)
local function check(v,m)if not v then error(m,2)end end
player={id=99,GetWorldPos=function()return{x=0,y=0,z=0}end,GetAngles=function()return{x=0,y=0,z=0}end,actor={GetHeadDir=function()return{x=0,y=1,z=0}end}}
local original=function(id)return{unowned=id}end
PathfindDebugUtils={FindDataTable=original,GetNPCSpeed=function()return'walk'end}
System={GetEntity=function(id)return entities[id]end,GetEntityByName=function(name)return names[name]end,
 RemoveEntity=function(id)removed=removed+1;if not deferred then local e=entities[id];if e then entities[id]=nil;names[e.name]=nil end end end,
 LogAlways=function(line)logs[#logs+1]=line end}
Script={SetTimerForFunction=function(ms,name,data)local id=#logs+next_id+100;while timers[id]do id=id+1 end;timers[id]={name=name,data=data};return id end,KillTimer=function(id)timers[id]=nil end}
ent_terrain=256
Physics={RayWorldIntersection=function(o,d,n,mask,skip,skip2,h)
 check(mask==ent_terrain and skip==player.id and skip2==nil and n==4,'unexpected terrain query')
 if mode=='no_ground'then return 0 end
 h[1]={dist=4,pos={x=o.x,y=o.y,z=o.z-4},normal={x=0,y=0,z=1}};return 1
end}
XGenAIModule={SpawnEntity=function(p)
 check(p.ClassName=='NPC' and p.SharedSoulGuid=='88bee0ec-f164-4282-ae1e-6576a76b9bac','nonofficial dummy')
 next_id=next_id+1;local e={id=next_id,name=p.Name,class='NPC',hp=100,actor={},soul={}}
 e.GetName=function(self)return self.name end;e.GetRawId=function(self)return self.id end
 e.soul.GetState=function(_,kind)check(kind=='health','unexpected soul access');return e.hp end;e.actor.GetMaxHealth=function()return 100 end
 entities[e.id]=e;names[e.name]=e
 if mode=='uncertain'then return nil end
 return e
end}
MineCome={};dofile(MINECOME_MODULE_PATH)
check(not MineCome.GameplayTntCombatFixtureBegin('bad',1000),'invalid run admitted')
mode='no_ground';check(not MineCome.GameplayTntCombatFixtureBegin(run,1000),'missing terrain admitted');check(next(entities)==nil,'terrain failure spawned actors');mode='ok'
check(MineCome.GameplayTntCombatFixtureBegin(run,1000),'valid pair refused')
check(not MineCome.GameplayTntCombatFixtureBegin(run,1000),'duplicate begin admitted')
local p=MineCome._tnt_combat_fixture.active
check(#p.actors==2 and p.actors[1].position.y==6 and p.actors[2].position.y==-9,'test radii differ')
check(PathfindDebugUtils.FindDataTable(p.actors[1].id).Pos.y==6 and PathfindDebugUtils.FindDataTable(888).unowned==888,'path override escaped exact actors')
p.actors[1].entity.hp=25
check(MineCome.GameplayTntCombatFixtureHealth(run),'health readback failed')
check(logs[#logs]:match('"health":25') and logs[#logs]:match('"health":100'),'health/control observations missing')
check(MineCome.GameplayTntCombatFixtureEnd(run),'pair cleanup failed')
check(next(entities)==nil and next(timers)==nil and PathfindDebugUtils.FindDataTable==original,'pair leaked actor/timer/path')
local before=removed;check(MineCome.GameplayTntCombatFixtureEnd(run),'duplicate cleanup refused');check(removed==before,'duplicate cleanup removed twice')
mode='uncertain';check(not MineCome.GameplayTntCombatFixtureBegin(run,1000),'uncertain native return admitted');check(next(entities)==nil and next(timers)==nil,'uncertain spawn leaked');mode='ok'
check(MineCome.GameplayTntCombatFixtureBegin(run,1000),'deferred pair refused');deferred=true;p=MineCome._tnt_combat_fixture.active
check(MineCome.GameplayTntCombatFixtureEnd(run),'deferred removal not started');check(PathfindDebugUtils.FindDataTable~=original,'cleanup restored before native disappearance')
for _,e in ipairs(p.actors)do entities[e.id]=nil;names[e.name]=nil end
local timer=timers[p.timer];timers[p.timer]=nil;_G[timer.name](timer.data)
check(PathfindDebugUtils.FindDataTable==original and logs[#logs]:match('"removed":true'),'deferred native removal not confirmed');deferred=false
check(MineCome.GameplayTntCombatFixtureBegin(run,1000),'expiry pair refused');p=MineCome._tnt_combat_fixture.active;timer=timers[p.timer];timers[p.timer]=nil;_G[timer.name](timer.data)
check(next(entities)==nil and next(timers)==nil and logs[#logs]:match('"result":"expired"'),'expiry did not clean exact pair')
check(MineCome.GameplayTntCombatFixtureBegin(run,1000),'sample pair refused');p=MineCome._tnt_combat_fixture.active
p.actors[1].entity.hp=37
timer=timers[p.sample_timer];timers[p.sample_timer]=nil;_G[timer.name](timer.data)
check(p.actors[1].last_health==37 and p.actors[1].health_samples>1,'sampler failed to retain native damage')
for _,e in ipairs(p.actors)do entities[e.id]=nil;names[e.name]=nil end
timer=timers[p.sample_timer];timers[p.sample_timer]=nil;_G[timer.name](timer.data)
check(not p.sample_timer,'sampling continued after official dummy despawn')
check(MineCome.GameplayTntCombatFixtureEnd(run),'despawned cleanup failed')
check(logs[#logs]:match('"health":37') and logs[#logs]:match('"present":false') and logs[#logs]:match('"health_observed":true'),'cached native health mislabeled or lost')
check(next(timers)==nil and PathfindDebugUtils.FindDataTable==original,'sampler cleanup leaked')
print('TNT combat fixture lifecycle passed: pair isolation, readback, uncertain spawn, delayed deletion, expiry and replay')
