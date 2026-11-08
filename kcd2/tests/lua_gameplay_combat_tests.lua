-- Standalone native API simulations: no actual-game claim.
local clock,logs,timers,next_timer,damage_calls,ray_hits,entities=0,{}, {},0,0,{},{}
local last_ray
local function require_true(v,m)if not v then error(m,2)end end
local function npc(raw,y)
 local e={id=raw,raw=raw,health=100,max_health=100,dead=false,pos={x=0,y=y,z=0}}
 e.soul={};e.actor={}
 function e:GetRawId()return self.raw end
 function e:GetWorldPos()return self.pos end
 function e:GetWorldBBox()return{x=self.pos.x-.3,y=self.pos.y-.3,z=0},{x=self.pos.x+.3,y=self.pos.y+.3,z=1.8}end
 function e.soul:GetId()return raw+1000 end
 function e.soul:GetState(name)require_true(name=='health','nonhealth read');return e.health end
 function e.soul:DealDamage(stamina,health,attacker,reaction)
  require_true(stamina==0 and attacker==player.id and reaction==false,'wrong attributed damage arguments')
  damage_calls=damage_calls+1;e.health=math.max(0,e.health-health)
 end
 function e.actor:GetMaxHealth()return e.max_health end
 function e.actor:IsDead()return e.dead end
 return e
end
player=npc(99,0);player.pos={x=0,y=0,z=0}
ent_all=7
System={GetCurrTime=function()return clock end,LogAlways=function(s)logs[#logs+1]=s end,GetEntitiesInSphere=function()return entities end}
Script={SetTimerForFunction=function(ms,name,data)next_timer=next_timer+1;timers[next_timer]={name=name,data=data};return next_timer end,KillTimer=function(id)timers[id]=nil end}
Physics={RayWorldIntersection=function(origin,direction,count,mask,skip1,skip2,out)
 last_ray=direction
 require_true(skip1==player.id and skip2~=player.id,'ray excluded wrong entities')
 for i,h in ipairs(ray_hits)do out[i]=h end;return #ray_hits
end}
MineCome={GameplayMovementCombatView=function()return{origin={x=0,y=0,z=1.6},direction={x=0,y=1,z=0},entity=player,id=player.id}end}
dofile(MINECOME_MODULE_PATH)
local run=string.rep('a',32)
local function start()clock=clock+3;require_true(MineCome.GameplayCombatBegin(run,10000,16,8),'begin failed')end
local function sample(seq)require_true(MineCome.GameplayCombatSample(run,seq),'sample failed')end
local function hit(seq,token,source,fraction)
 return MineCome.GameplayCombatHit(run,seq,token or 1,source or 1,fraction or .1,0,0,1.6,0,1.7,1.6)
end
local function finish()require_true(MineCome.GameplayCombatEnd(run),'cleanup failed');require_true(next(timers)==nil,'timer leaked')end
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
-- Maximum actor snapshots fit the engine's4095-byte log ceiling.
entities={};for i=1,8 do entities[i]=npc(i,2+i*.1)end;start();sample(1);require_true(#logs[#logs]<4000,'native log truncation risk');finish()
print('PASS native combat lifecycle, normalization, replay, identity, occlusion, stale input and cleanup (simulated engine)')
