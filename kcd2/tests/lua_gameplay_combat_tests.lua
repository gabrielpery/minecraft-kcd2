-- Standalone native API simulations: no actual-game claim.
local clock,logs,timers,next_timer,damage_calls,ray_hits,entities=0,{}, {},0,0,{},{}
local last_ray,on_ray
local lock_names={'wh_cs_playermaxopponentdistancetolock','wh_cs_playermaxopponentdistancetounlock','wh_cs_playerunlocktimeout'}
local defaults={4,7,3};local cvars,writes={},{};local cvar_behavior
for i,name in ipairs(lock_names)do cvars[name]=defaults[i]end
local function require_true(v,m)if not v then error(m,2)end end
local function npc(raw,y)
 local e={id=raw,raw=raw,this={id='wuid-'..raw},health=100,max_health=100,dead=false,pos={x=0,y=y,z=0}}
 e.soul={};e.actor={}
 function e:GetRawId()return self.raw end
 function e:GetWorldPos()return self.pos end
 function e:GetWorldBBox()return{x=self.pos.x-.3,y=self.pos.y-.3,z=0},{x=self.pos.x+.3,y=self.pos.y+.3,z=1.8}end
 function e.soul:GetId()return raw+1000 end
 function e.soul:GetState(name)require_true(name=='health','nonhealth read');return e.health end
 function e.soul:DealDamage(stamina,health,attacker,reaction)
  require_true(stamina==0 and attacker==player.this.id and attacker~=player.id and reaction==false,'damage must attribute WUID, not entity handle')
  damage_calls=damage_calls+1;e.health=math.max(0,e.health-health)
 end
 function e.actor:GetMaxHealth()return e.max_health end
 function e.actor:IsDead()return e.dead end
 return e
end
player=npc(99,0);player.pos={x=0,y=0,z=0}
ent_all=7
System={GetCurrTime=function()return clock end,LogAlways=function(s)logs[#logs+1]=s end,GetEntitiesInSphere=function()return entities end}
System.GetCVar=function(name)return cvars[name]end
System.SetCVar=function(name,value)
 require_true(cvars[name]~=nil,'unknown/non-player CVar written');writes[#writes+1]={name=name,value=value}
 if cvar_behavior then return cvar_behavior(name,value)end;cvars[name]=value
end
Script={SetTimerForFunction=function(ms,name,data)next_timer=next_timer+1;timers[next_timer]={name=name,data=data};return next_timer end,KillTimer=function(id)timers[id]=nil end}
Physics={RayWorldIntersection=function(origin,direction,count,mask,skip1,skip2,out)
 last_ray=direction
 require_true(skip1==player.id and skip2~=player.id,'ray excluded wrong entities')
 if on_ray then on_ray()end
 for i,h in ipairs(ray_hits)do out[i]=h end;return #ray_hits
end}
MineCome={GameplayMovementCombatView=function()return{origin={x=0,y=0,z=1.6},direction={x=0,y=1,z=0},entity=player,id=player.id}end}
dofile(MINECOME_MODULE_PATH)
local run=string.rep('a',32)
local function start()clock=clock+3;require_true(MineCome.GameplayCombatBegin(run,10000,16,8),'begin failed');for _,name in ipairs(lock_names)do require_true(cvars[name]==0,'lock policy not admitted')end end
local function sample(seq)require_true(MineCome.GameplayCombatSample(run,seq),'sample failed')end
local function hit(seq,token,source,fraction)
 return MineCome.GameplayCombatHit(run,seq,token or 1,source or 1,fraction or .1,0,0,1.6,0,1.7,1.6)
end
local function restored()for i,name in ipairs(lock_names)do require_true(cvars[name]==defaults[i],'lock baseline not restored')end end
local function finish()require_true(MineCome.GameplayCombatEnd(run),'cleanup failed');require_true(next(timers)==nil,'timer leaked');restored();require_true(logs[#logs]:match('"lock_policy_restored":true'),'lock cleanup not recorded')end
local player_this=player.this;player.this=nil
require_true(not MineCome.GameplayCombatBegin(run,10000,16,8),'missing attacker WUID admitted');player.this=player_this
local a=npc(1,2);entities={a};start();sample(1)
require_true(logs[#logs]:match('"token":1') and logs[#logs]:match('"max_health":100'),'missing real actor snapshot')
require_true(hit(1),'accepted melee failed');require_true(a.health==90 and damage_calls==1,'damage did not scale native maxHP')
require_true(hit(1),'duplicate acknowledgement failed');require_true(a.health==90 and damage_calls==1,'duplicate attack applied')
clock=clock+.1;sample(2);a.health=500;a.max_health=500;require_true(hit(2,1,2,.1),'scaled hit failed');require_true(a.health==450,'maxHP normalization wrong')
finish()
-- A square Minecraft proxy is wider than a rectangular native box. Its front
-- surface is only an aim hint; scenery must be traced to actual native contact.
a=npc(1,2);entities={a}
function a:GetWorldBBox()return{x=-.6,y=1.7,z=0},{x=.6,y=2.3,z=1.8}end
start();sample(1)
require_true(MineCome.GameplayCombatHit(run,1,1,1,.1,0,0,1.6,0,1.4,1.6),'rectangular native target rejected')
require_true(a.health==90 and math.abs(last_ray.y-1.7)<.00001,'native contact or scenery ray used proxy face');finish()
-- Same reused native ID / persistent soul ID must not retarget another object.
a=npc(1,2);entities={a};start();sample(1);entities={npc(1,2)}
local before_reuse=damage_calls;local ok,why=hit(1);require_true(ok and why=='target_changed','recycled actor ID accepted');require_true(damage_calls==before_reuse,'recycled actor was damaged')
clock=clock+.1;sample(2);require_true(logs[#logs]:match('"token":2'),'generation reused');finish()
-- An occluder closer than the intended NPC prevents an otherwise valid hit.
entities={npc(1,2)};start();sample(1);ray_hits={{dist=1,pos={x=0,y=1,z=1.6}}}
ok,why=hit(1);require_true(ok and why=='occluded','wall ignored');ray_hits={};finish()
-- Origin, aim, expiry and malformed payloads fail before a native setter.
entities={npc(1,2)};start();sample(1)
ok,why=MineCome.GameplayCombatHit(run,1,1,1,.1,1,0,1.6,0,1.7,1.6);require_true(ok and why=='view_changed','wrong eye accepted')
ok,why=MineCome.GameplayCombatHit(run,2,1,1,0/0,0,0,1.6,0,1.7,1.6);require_true(ok and why=='invalid_hit','NaN accepted')
clock=clock+.301;ok,why=hit(3);require_true(ok and why=='stale_target','stale snapshot accepted');finish()
-- Setters which throw after changing state must never be retried.
a=npc(1,2);entities={a};start();sample(1)
function a.soul:DealDamage(_,damage)damage_calls=damage_calls+1;a.health=a.health-damage;error('unknown setter outcome')end
ok,why=hit(1);require_true(ok and why=='damage_unconfirmed','unknown outcome promoted to success')
local once=damage_calls;hit(1);require_true(damage_calls==once,'unknown outcome retried');finish()
-- Damage is capped at currentHP; nothing heals/overflows with a strong attack.
a=npc(1,2);entities={a};start();sample(1);require_true(hit(1,1,1,50),'strong melee rejected');require_true(a.health==0,'strong melee did not kill');finish()
-- Loss of the original player cancels the lease without writing health.
entities={npc(1,2)};start();local original=player;player=npc(100,0)
local before=damage_calls;ok,why=MineCome.GameplayCombatSample(run,1);require_true(not ok and why=='player_changed','player identity change ignored');require_true(next(timers)==nil and before==damage_calls,'identity cleanup failed');player=original
-- WUID changes must not silently reattribute an otherwise unchanged handle.
entities={npc(1,2)};start();sample(1);local saved_wuid=player.this.id;before=damage_calls
player.this.id='replacement-wuid';ok,why=hit(1)
require_true(not ok and why=='player_changed' and damage_calls==before and next(timers)==nil,'changed attacker WUID admitted');player.this.id=saved_wuid
entities={npc(1,2)};start();sample(1);before=damage_calls
on_ray=function()player.this.id='replacement-wuid'end;ok,why=hit(1);on_ray=nil
require_true(ok and why=='target_changed' and damage_calls==before,'WUID changed during ray was used');player.this.id=saved_wuid;finish()
-- Maximum actor snapshots fit the engine's4095-byte log ceiling.
entities={};for i=1,8 do entities[i]=npc(i,2+i*.1)end;start();sample(1);require_true(#logs[#logs]<4000,'native log truncation risk');finish()
-- Baselines and all three APIs are required before any write or timer.
local set_cvar=System.SetCVar;local get_cvar=System.GetCVar
for _,missing in ipairs({'GetCVar','SetCVar'})do local saved=System[missing];System[missing]=nil;local n=#writes
 require_true(not MineCome.GameplayCombatBegin(run,10000,16,8) and #writes==n and next(timers)==nil,'missing CVar API mutated state');System[missing]=saved
end
for _,bad in ipairs({'4',false,0/0,math.huge})do cvars[lock_names[3]]=bad;local n=#writes
 require_true(not MineCome.GameplayCombatBegin(run,10000,16,8) and #writes==n and next(timers)==nil,'invalid CVar baseline mutated state')
end
cvars[lock_names[3]]=nil;local n=#writes
require_true(not MineCome.GameplayCombatBegin(run,10000,16,8) and #writes==n,'absent CVar baseline mutated state');cvars[lock_names[3]]=3
-- A setter may throw after changing state. Restore exact owned values once,
-- without continuing later settings or starting a usable combat session.
cvar_behavior=function(name,value)cvars[name]=value;if name==lock_names[2] and value==0 then error('setter changed then threw')end end
local ok,why=MineCome.GameplayCombatBegin(run,10000,16,8)
require_true(not ok and why=='lock_policy_setup_failed' and next(timers)==nil,'partial setter failure admitted')
restored();require_true(logs[#logs]:match('"lock_policy_restored":true'),'partial setup restoration missing');cvar_behavior=nil
-- Ignored setter/readback mismatch restores other owned settings.
cvar_behavior=function(name,value)if name~=lock_names[2]then cvars[name]=value end end
require_true(not MineCome.GameplayCombatBegin(run,10000,16,8),'ignored setter admitted');restored();cvar_behavior=nil
-- The lease restores policy even without an explicit end.
start();clock=clock+2.1;local timer_id,data=next(timers);timers[timer_id]=nil;MineCome_GameplayCombatTick(data.data)
require_true(next(timers)==nil and logs[#logs]:match('lease_expired') and logs[#logs]:match('"lock_policy_restored":true'),'lease failed policy cleanup');restored()
-- Timer admission failure occurs before any policy write.
local set_timer=Script.SetTimerForFunction;Script.SetTimerForFunction=function()return nil end;n=#writes
require_true(not MineCome.GameplayCombatBegin(run,10000,16,8) and #writes==n,'failed timer mutated CVar policy');Script.SetTimerForFunction=set_timer
-- Preserve exact non-default baselines, including a pre-existing zero.
defaults={0,2.25,9};for i,name in ipairs(lock_names)do cvars[name]=defaults[i]end;start();finish()
defaults={4,7,3};for i,name in ipairs(lock_names)do cvars[name]=defaults[i]end
-- Foreign changes must be preserved; restore only settings still owned by us.
start();cvars[lock_names[2]]=11
ok,why=MineCome.GameplayCombatSample(run,1)
require_true(not ok and why=='lock_policy_changed' and cvars[lock_names[2]]==11 and cvars[lock_names[1]]==4 and cvars[lock_names[3]]==3,'foreign CVar overwritten or owned settings leaked')
require_true(logs[#logs]:match('"lock_policy_restored":false') and not MineCome.GameplayCombatEnd(run),'incomplete policy cleanup claimed success')
require_true(not MineCome.GameplayCombatBegin(run,10000,16,8),'new session admitted with unconfirmed prior restoration')
-- New process simulation resets ownership after deliberately foreign-state tests.
local function reset_policy_state()
 MineCome._gameplay_combat.active=nil;MineCome._gameplay_combat.last=nil
 System.GetCVar=get_cvar;System.SetCVar=set_cvar;cvar_behavior=nil
 for i,name in ipairs(lock_names)do cvars[name]=defaults[i]end
end
reset_policy_state()
-- Revalidate after the engine ray, before a damage setter.
entities={npc(1,2)};start();sample(1);before=damage_calls
on_ray=function()cvars[lock_names[1]]=8 end;ok,why=hit(1);on_ray=nil
require_true(not ok and why=='lock_policy_changed' and damage_calls==before and cvars[lock_names[1]]==8,'changed lock policy allowed native damage or was overwritten')
reset_policy_state()
-- Replaced CVar APIs have no ownership; never use foreign setters for cleanup.
start();local foreign_calls=0;System.SetCVar=function()foreign_calls=foreign_calls+1 end
require_true(not MineCome.GameplayCombatEnd(run) and foreign_calls==0 and logs[#logs]:match('"lock_policy_restored":false'),'foreign setter used or unconfirmed cleanup hidden')
reset_policy_state()
-- Real-arrow contract: contiguous segments independent of the current eye after
-- launch, nearest native obstruction, exact actor generations and one setter.
local arrow=string.rep('b',32)
local function trace(seq,id,segment,from,to)
 return MineCome.GameplayProjectileTrace(run,seq,id or arrow,segment or 1,0,from or 0,1.6,0,to or 3,1.6)
end
local function impact(seq,id,segment,actor_token,fraction)
 return MineCome.GameplayProjectileImpact(run,seq,id or arrow,segment or 1,actor_token or 1,fraction or .25)
end
local function projectile_receipt(event,result)
 local text=logs[#logs];require_true(text:match('"event":"'..event..'"') and text:match('"result":"'..result..'"'),'projectile receipt differs: '..text)
 require_true(#text<4000,'projectile log exceeded native limit');return text
end
a=npc(1,2);entities={a};start();before=damage_calls
local projectile_rays=0;on_ray=function()projectile_rays=projectile_rays+1 end
require_true(trace(1),'arrow actor trace failed');projectile_receipt('projectile_trace','actor')
require_true(trace(1) and projectile_rays==1,'duplicate trace was executed again')
require_true(not trace(1,nil,1,0,2.5) and projectile_rays==1,'changed duplicate trace admitted');on_ray=nil
require_true(a.health==100 and damage_calls==before,'trace changed NPC health')
require_true(logs[#logs]:match('"actor_token":1') and math.abs(MineCome._gameplay_combat.active.projectiles[arrow].collision.point.y-1.4)<.000001,'vanilla arrow margin on real actor contact missing')
require_true(impact(2),'arrow impact failed');projectile_receipt('projectile_impact','damaged')
require_true(a.health==75 and damage_calls==before+1,'vanilla damage fraction not applied')
require_true(impact(2) and a.health==75 and damage_calls==before+1,'duplicate impact reapplied')
require_true(not impact(2,nil,nil,nil,.5),'changed duplicate impact admitted')
require_true(impact(3),'finished-arrow rejection absent');projectile_receipt('projectile_impact','rejected');require_true(a.health==75,'same arrow damaged twice')
finish()
-- Launch anchored once; aiming elsewhere later cannot redirect the real arrow.
a=npc(1,5);entities={a};start();require_true(trace(1,nil,1,0,3),'initial clear arrow trace failed');projectile_receipt('projectile_trace','clear')
local view_get=MineCome.GameplayMovementCombatView
MineCome.GameplayMovementCombatView=function()error('continuation must not query current eye')end
require_true(trace(2,nil,2,3,6),'continuation used current view');projectile_receipt('projectile_trace','actor')
require_true(impact(3,nil,2),'distant arrow impact failed');require_true(a.health==75,'distant trajectory damage absent')
MineCome.GameplayMovementCombatView=view_get;finish()
-- Actual rectangle contact wins over the square proxy and nearer scenery wins
-- over that real contact; native output order is not assumed sorted.
a=npc(1,2);function a:GetWorldBBox()return{x=-.6,y=1.7,z=0},{x=.6,y=2.3,z=1.8}end
entities={a};start();ray_hits={{dist=2.5,pos={x=0,y=2.5,z=1.6},normal={x=0,y=-1,z=0}},{dist=1,pos={x=0,y=1,z=1.6},normal={x=0,y=-1,z=0}}}
require_true(trace(1),'scenery trace failed');projectile_receipt('projectile_trace','scenery')
require_true(logs[#logs]:match('"contact":{"x":0,"y":1,"z":1.6}') and a.health==100,'nearest scenery was not selected')
ray_hits={};require_true(impact(2),'scenery-impact refusal absent');projectile_receipt('projectile_impact','rejected');require_true(a.health==100,'scenery arrow damaged actor');finish()
-- Match vanilla ProjectileUtil's0.3f entity margin, including impact recheck.
-- A ray just outside the expanded top must miss; nearby scenery is never inflated.
for _,height in ipairs({2.099,2.101})do
 a=npc(1,2);entities={a};start()
 require_true(MineCome.GameplayProjectileTrace(run,1,arrow,1,0,0,height,0,3,height),'grazing arrow trace failed')
 if height<2.1 then
  projectile_receipt('projectile_trace','actor');require_true(impact(2),'grazing impact failed')
  projectile_receipt('projectile_impact','damaged');require_true(a.health==75,'vanilla margin omitted from impact recheck')
 else projectile_receipt('projectile_trace','clear');require_true(a.health==100,'outside vanilla margin hit actor')end
 finish()
end
a=npc(1,2);entities={a};start();ray_hits={{dist=1,pos={x=0,y=1,z=2.099},normal={x=0,y=-1,z=0}}}
MineCome.GameplayProjectileTrace(run,1,arrow,1,0,0,2.099,0,3,2.099)
require_true(projectile_receipt('projectile_trace','scenery'):match('"contact":{"x":0,"y":1,"z":2.099}'),'scenery moved by actor margin')
require_true(a.health==100,'grazing arrow crossed scenery');ray_hits={};finish()
-- A new obstruction appearing before acknowledgement blocks native damage.
a=npc(1,2);entities={a};start();trace(1);ray_hits={{dist=1,pos={x=0,y=1,z=1.6},normal={x=0,y=-1,z=0}}};impact(2)
require_true(projectile_receipt('projectile_impact','rejected'):match('"reason":"occluded"') and a.health==100,'impact skipped fresh scenery check');ray_hits={};finish()
-- Malformed ray output, stale collision, reused actor and changed shooter refuse.
for _,fault in ipairs({'normal','point','overflow'})do
 a=npc(1,2);entities={a};start();ray_hits={{dist=1,pos={x=0,y=1,z=1.6},normal={x=0,y=-1,z=0}}}
 if fault=='normal'then ray_hits[1].normal.y=2 elseif fault=='point'then ray_hits[1].pos.x=1 else for i=2,16 do ray_hits[i]=ray_hits[1]end end
 trace(1);require_true(projectile_receipt('projectile_trace','rejected'):match('scenery_unknown'),'invalid native trace admitted');ray_hits={};finish()
end
a=npc(1,2);entities={a};start();trace(1);clock=clock+.301;impact(2)
require_true(projectile_receipt('projectile_impact','rejected'):match('stale_impact') and a.health==100,'stale impact admitted');finish()
a=npc(1,2);entities={a};start();trace(1);a.soul.GetId=function()return 999999 end;impact(2)
require_true(projectile_receipt('projectile_impact','rejected'):match('target_changed') and a.health==100,'replaced actor generation damaged');finish()
a=npc(1,2);entities={a};start();trace(1);before=damage_calls;saved_wuid=player.this.id
on_ray=function()player.this.id='replacement-wuid'end;ok,why=impact(2);on_ray=nil
require_true(not ok and why=='player_changed' and damage_calls==before,'impact changed shooter attribution');player.this.id=saved_wuid;restored()
-- Unknown setter outcomes are consumed exactly once, even under a new request.
a=npc(1,2);entities={a};start();trace(1)
function a.soul:DealDamage(_,amount)damage_calls=damage_calls+1;a.health=a.health-amount;error('setter changed then failed')end
before=damage_calls;impact(2);require_true(projectile_receipt('projectile_impact','rejected'):match('damage_unconfirmed'),'unknown projectile setter success claimed')
impact(2);impact(3);require_true(a.health==75 and damage_calls==before+1,'unknown arrow impact retried');finish()
-- Bad initial eye, discontinuity, too long segment and expired trajectory stop.
entities={};start();trace(1,nil,1,1,3);require_true(projectile_receipt('projectile_trace','rejected'):match('launch_changed'),'remote arrow spawn admitted');finish()
entities={};start();trace(1,nil,1,0,3);trace(2,nil,2,3.1,6);require_true(projectile_receipt('projectile_trace','rejected'):match('trajectory_changed'),'discontinuous arrow admitted');finish()
entities={};start();trace(1,nil,1,0,5);require_true(projectile_receipt('projectile_trace','rejected'):match('invalid_segment'),'oversized arrow segment admitted');finish()
entities={};start();for segment=1,21 do trace(segment,nil,segment,(segment-1)*3,segment*3);projectile_receipt('projectile_trace','clear')end
trace(22,nil,22,63,66);require_true(projectile_receipt('projectile_trace','rejected'):match('trajectory_changed'),'cumulative arrow path exceeded64m');finish()
entities={};clock=clock+3;require_true(MineCome.GameplayCombatBegin(run,20000,16,8),'long session begin');trace(1,nil,1,0,1)
for step=1,11 do clock=clock+1;sample(step)end
trace(2,nil,2,1,2);require_true(projectile_receipt('projectile_trace','rejected'):match('trajectory_changed'),'expired arrow trajectory admitted');finish()
entities={};start();require_true(not MineCome.GameplayProjectileTrace(run,1,'not-uuid',1,0,0,1.6,0,3,1.6),'malformed arrow identity admitted')
require_true(MineCome.GameplayProjectileTrace(run,1,arrow,1,0/0,0,1.6,0,3,1.6),'malformed vector lacked bounded refusal');projectile_receipt('projectile_trace','rejected');finish()
-- At most16 active flights; terminal arrows cannot reuse their UUID to launch.
entities={};start();for i=1,16 do require_true(trace(i,string.format('%032x',i),1,0,1),'bounded arrow admission failed')end
trace(17,string.format('%032x',17),1,0,1);require_true(projectile_receipt('projectile_trace','rejected'):match('projectile_capacity'),'active projectile bound ignored');finish()
require_true(next(MineCome._gameplay_combat.last.projectiles)==nil and MineCome._gameplay_combat.last.projectile_last==nil,'projectile refs retained after cleanup')
print('PASS native combat lifecycle, normalization, replay, identity, occlusion, owned lock cleanup and projectile trace/impact (simulated engine)')
