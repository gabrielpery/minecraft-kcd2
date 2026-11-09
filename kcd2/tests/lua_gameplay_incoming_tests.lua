-- Standalone engine simulation, not a claim about native combat delivery.
local t,logs,timers,next_timer=10,{}, {},0
local run=string.rep('a',32);local path='C:/MineCome/'..run..'/000000/'
local initial={wh_cs_playermaxopponentdistancetolock=4,wh_cs_playermaxopponentdistancetounlock=7,wh_cs_playerunlocktimeout=3,wh_rpg_LogFilepath='%USER%/Logs/',wh_rpg_LogCompression=6,wh_rpg_LogLevel=0,wh_rpg_LogType=0,wh_rpg_LogReasons=1,wh_rpg_LogInterval=10,wh_rpg_LogSize=4096,wh_rpg_TelemetryLimitedToPlayline=1,wh_rpg_LogTarget=0}
local cvars,entities,all,commands,writes={}, {}, {}, {},{}
local cvar_behavior,health_behavior,buff_behavior=nil,nil,nil
local DEATH_BUFF='44e1ccc9-9252-48a9-922d-2ae4523c69a3'
local INJURY_BUFF='a2088337-e015-4c28-8ab2-043f6925c087'
local function check(v,m)if not v then error(m,2)end end
local function npc(id,name)
 local e={id=id,this={id='wuid-'..id},hp=100,maximum=100,name=name,soul={},actor={},buff=false,injury_buff=false,prior_injury=true,health_writes=0,removes=0,adds=0,pos={x=0,y=id,z=0}}
 function e:GetName()return self.name end
 function e:GetRawId()return self.id end
 function e:GetWorldPos()return self.pos end
 function e:GetWorldBBox()return{x=-.3,y=self.pos.y-.3,z=0},{x=.3,y=self.pos.y+.3,z=1.8}end
 function e.soul:GetId()return id+1000 end
 function e.soul:GetState(key)check(key=='health','wrong health read');return e.hp end
 function e.soul:SetState(key,v)check(key=='health','wrong health write');e.health_writes=e.health_writes+1;if health_behavior then return health_behavior(e,v)end;e.hp=v end
 function e.soul:DealDamage()error('incoming must never deal native damage')end
 function e.soul:AddBuff(guid)
  check(guid==DEATH_BUFF or guid==INJURY_BUFF,'wrong buff');e.adds=e.adds+1
  if buff_behavior then return buff_behavior(e,guid)end
  if guid==DEATH_BUFF then e.buff=true;return 123 end
  e.injury_buff=true;return 124
 end
 function e.soul:HasBuffDebug(guid)
  check(guid==DEATH_BUFF or guid==INJURY_BUFF,'unexpected buff read')
  if guid==DEATH_BUFF then return e.buff end;return e.injury_buff
 end
 function e.soul:RemoveBuff(instance)
  check(instance==123 or instance==124,'foreign buff instance removed');e.removes=e.removes+1
  if instance==123 then e.buff=false else e.injury_buff=false end
 end
 function e.soul:RemoveAllBuffsByGuid()error('incoming must never remove unrelated injuries')end
 function e.soul:GetDerivedStat()error('hin is not a native derived-stat getter')end
 function e.actor:GetMaxHealth()return e.maximum end
 function e.actor:IsDead()return e.hp<=0 end
 all[id]=e;return e
end
player=npc(99,'Dude');player.pos.y=0
local a=npc(1,'unique_actor');entities={a}
System={GetCurrTime=function()return t end,LogAlways=function(line)logs[#logs+1]=line end,GetEntity=function(id)return all[id]end,GetEntityByName=function(name)for _,e in pairs(all)do if e.name==name then return e end end end,GetEntitiesInSphere=function()return entities end,GetCVar=function(name)return cvars[name]end,SetCVar=function(name,value)check(cvars[name]~=nil,'unknown cvar');writes[#writes+1]={name,value};if cvar_behavior then return cvar_behavior(name,value)end;cvars[name]=value end,ExecuteCommand=function(cmd)check(cmd=='wh_rpg_ResetLogging','unexpected command');commands[#commands+1]={cmd,path=cvars.wh_rpg_LogFilepath}end}
Script={SetTimerForFunction=function(ms,name,data)next_timer=next_timer+1;timers[next_timer]={name=name,data=data,ms=ms};return next_timer end,KillTimer=function(id)timers[id]=nil end}
Physics={RayWorldIntersection=function()return 0 end};ent_all=7
MineCome={}
dofile(MINECOME_MODULE_PATH:gsub('combat_incoming.lua$','combat_session.lua'))
dofile(MINECOME_MODULE_PATH)
local function reset()
 for k,v in pairs(initial)do cvars[k]=v end
 MineCome._gameplay_combat.active=nil;MineCome._gameplay_combat.last=nil;MineCome._gameplay_incoming.active=nil;MineCome._gameplay_incoming.last=nil
 timers={};cvar_behavior=nil;health_behavior=nil;buff_behavior=nil;t=t+5;player.hp=100;player.buff=false;player.injury_buff=false;player.prior_injury=true;all[99]=player;all[1]=a;a.name='unique_actor';entities={a};all[2]=nil
end
local function begin()
 check(MineCome.GameplayCombatBegin(run,10000,16,8),'combat begin failed')
 check(MineCome.GameplayCombatIncomingBegin(run,path),'incoming begin failed')
 check(player.buff and player.injury_buff and cvars.wh_rpg_LogType==2 and cvars.wh_rpg_LogTarget==2,'incoming not admitted')
 check(logs[#logs]:match('"bleeding_protection_original":false') and logs[#logs]:match('"bleeding_protection_active":true'),'injury guard begin readback missing')
end
local function restored()
 for k,v in pairs(initial)do check(cvars[k]==v,'cvar not restored '..k)end
 check(next(timers)==nil and not player.buff and not player.injury_buff,'timer or buff leaked')
 check(player.prior_injury,'prior injury was removed')
end
local function finish()check(MineCome.GameplayCombatEnd(run),'combat cleanup failed');restored()end
reset();player.hp=75;begin();check(player.hp==100,'native proxy not refilled')
check(MineCome.GameplayCombatSample(run,1),'sample failed')
check(logs[#logs-1]:match('"event":"identity"') and logs[#logs-1]:match('"token":1,"name":"unique_actor"') and logs[#logs]:match('"event":"sample"'),'identity not paired before sample')
local old_seen=MineCome._gameplay_incoming.active.identities[1].first_seen_ms
t=t+.1;check(MineCome.GameplayCombatSample(run,2),'second sample failed');check(MineCome._gameplay_incoming.active.identities[1].first_seen_ms==old_seen,'first seen moved')
local p=MineCome._gameplay_incoming.active;player.hp=94;local timer=p.timer;timers[timer]=nil;MineCome_GameplayIncomingTick(p.timer_data);check(player.hp==100,'real native loss not replenished')
local before=#commands;check(MineCome.GameplayCombatIncomingRotate(run,1),'rotation failed')
check(cvars.wh_rpg_LogFilepath=='C:/MineCome/'..run..'/000001/' and #commands==before+1,'rotation wrong path or reset count')
local close=logs[#logs];check(MineCome.GameplayCombatIncomingRotate(run,1) and #commands==before+1 and logs[#logs]==close,'duplicate rotation was not idempotent')
check(not MineCome.GameplayCombatIncomingRotate(run,3),'skipped epoch accepted')
finish();check(player.hp==75,'native baseline was not restored')
-- No incoming session preserves the existing outgoing behavior.
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'outgoing begin');check(MineCome.GameplayCombatSample(run,1),'outgoing sample');finish()
-- Duplicate names and names not resolving to the exact sampled generation
-- never acquire an incoming identity.
reset();local other=npc(2,'unique_actor');entities={a,other};begin();MineCome.GameplayCombatSample(run,1)
check(logs[#logs-1]:match('"actors":%[%]'),'ambiguous names admitted');finish()
reset();other=npc(2,'unique_actor');entities={a,other}
check(MineCome.GameplayCombatBegin(run,10000,16,1),'limited combat begin');check(MineCome.GameplayCombatIncomingBegin(run,path),'limited incoming begin');MineCome.GameplayCombatSample(run,1)
check(logs[#logs-1]:match('"actors":%[%]'),'unsampled duplicate name admitted');finish()
reset();a.name='Dude';local original_named=System.GetEntityByName
System.GetEntityByName=function(name)if name=='Dude'then return player end;return original_named(name)end
begin();check(not MineCome.GameplayCombatSample(run,1),'NPC sharing player name admitted');restored();check(not MineCome._gameplay_combat.active,'ambiguous victim did not stop session');System.GetEntityByName=original_named;a.name='unique_actor'
reset();begin();MineCome.GameplayCombatSample(run,1);local stale=a;all[1]=npc(1,'unique_actor');entities={all[1]};t=t+.1
check(MineCome.GameplayCombatSample(run,2),'replacement sample');check(logs[#logs-1]:match('"token":2') and not logs[#logs-1]:match('"token":1'),'generation token reused');finish();a=stale;all[1]=a
-- Require an absent buff and every original logging value before any write.
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'preflight combat');player.buff=true;local wc=#writes;local ac=player.adds
check(not MineCome.GameplayCombatIncomingBegin(run,path) and #writes==wc and player.adds==ac,'foreign buff mutated');player.buff=false;finish()
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'injury preflight combat');player.injury_buff=true;wc=#writes;ac=player.adds
check(not MineCome.GameplayCombatIncomingBegin(run,path) and #writes==wc and player.adds==ac and player.injury_buff,'foreign injury guard mutated');player.injury_buff=false;finish()
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'missing cvar combat');cvars.wh_rpg_LogCompression=nil;wc=#writes;ac=player.adds
check(not MineCome.GameplayCombatIncomingBegin(run,path) and #writes==wc and player.adds==ac,'missing baseline mutated');cvars.wh_rpg_LogCompression=6;finish()
-- A setter can throw after mutation; the attempted setting still restores.
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'partial combat')
cvar_behavior=function(name,v)cvars[name]=v;if name=='wh_rpg_LogType' and v==2 then error('changed then threw')end end
check(not MineCome.GameplayCombatIncomingBegin(run,path),'partial setup accepted');cvar_behavior=nil;finish()
-- Injury protection failure restores only our exact guard instances, without
-- querying the unsupported intermediate-stat getter or altering prior injuries.
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'injury setup combat')
buff_behavior=function(e,guid)if guid==DEATH_BUFF then e.buff=true;return 123 end;return false end
check(not MineCome.GameplayCombatIncomingBegin(run,path),'missing injury guard accepted');buff_behavior=nil
check(MineCome._gameplay_incoming.last.restored and logs[#logs]:match('"bleeding_protection_restored":true'),'failed injury setup cleanup unconfirmed');finish()
-- A mutating AddBuff that throws loses the returned instance: fail closed,
-- preserve that unknown instance, and never claim complete cleanup.
reset();check(MineCome.GameplayCombatBegin(run,10000,16,8),'ambiguous injury combat')
buff_behavior=function(e,guid)if guid==DEATH_BUFF then e.buff=true;return 123 end;e.injury_buff=true;error('injury added then threw')end
check(not MineCome.GameplayCombatIncomingBegin(run,path),'ambiguous injury setup accepted');buff_behavior=nil
check(player.injury_buff and not player.buff and player.prior_injury and not MineCome._gameplay_incoming.last.restored and logs[#logs]:match('"buff_restored":false'),'unknown injury instance removed or cleanup claimed complete')
-- Externally removed protection immediately ends the incoming lease. Its
-- absence is already the captured baseline, so cleanup must not remove others.
reset();begin();player.injury_buff=false
check(not MineCome.GameplayCombatSample(run,1),'lost injury guard admitted');restored()
-- Preserve foreign CVar state and block subsequent incoming admission.
reset();begin();cvars.wh_rpg_LogType=17
check(not MineCome.GameplayCombatSample(run,1),'foreign logging admitted')
check(cvars.wh_rpg_LogType==17 and not player.buff and not MineCome._gameplay_incoming.last.restored,'foreign state overwritten or cleanup claimed complete')
-- Expiry removes the guard and restores native health without a host.
reset();player.hp=88;begin();p=MineCome._gameplay_incoming.active;t=t+2.1;timer=p.timer;timers[timer]=nil;MineCome_GameplayIncomingTick(p.timer_data)
restored();check(player.hp==88 and not MineCome._gameplay_combat.active,'expiry failed')
-- Health setters that mutate then throw stop the lease, not retry upkeep.
reset();begin();p=MineCome._gameplay_incoming.active;player.hp=94
health_behavior=function(e,v)e.hp=v;error('changed then threw')end
local hw=player.health_writes;timer=p.timer;timers[timer]=nil;MineCome_GameplayIncomingTick(p.timer_data)
check(player.health_writes==hw+1 and not MineCome._gameplay_combat.active,'ambiguous upkeep retried');health_behavior=nil;restored()
-- Loss of exact player identity never changes the replacement player.
reset();begin();local original=player;player=npc(101,'Replacement');local replacement_writes=player.health_writes
check(not MineCome.GameplayCombatSample(run,1),'replacement player admitted')
check(player.health_writes==replacement_writes and original.buff and original.injury_buff and not player.injury_buff,'replacement changed or original buff blindly removed');player=original;all[101]=nil
print('Incoming native logging, identity, idempotent rotation, proxy health and cleanup simulations passed')
reset();begin();p=MineCome._gameplay_incoming.active
local movement={run=run,entity=player,id=player.id};MineCome._gameplay_movement={active=movement}
local v={x=1,y=0,z=0}
local function reaction()return MineCome.GameplayCombatIncomingAllowsReaction(run,movement,player,player.id,v)end
check(not reaction(),'normal native walking bypassed velocity guard')
player.hp=96;check(reaction(),'pending real native loss not admitted');local injured=t
t=t+.1;check(reaction() and p.reaction_at==injured,'repeated health read extended injury window')
timer=p.timer;timers[timer]=nil;MineCome_GameplayIncomingTick(p.timer_data)
check(player.hp==100 and reaction(),'confirmed native upkeep lost reaction allowance')
v.x=3.01;check(not reaction(),'unbounded reaction velocity');v.x=1;v.z=6.01;check(not reaction(),'vertical reaction limit relaxed');v.z=0
local correct=movement.run;movement.run=string.rep('b',32);check(not reaction(),'foreign movement run admitted');movement.run=correct
movement.stopping=true;check(not reaction(),'stopping movement admitted');movement.stopping=nil
t=injured+.501;check(not reaction(),'reaction allowance did not expire')
player.hp=95;check(reaction(),'new actual injury did not reopen window')
finish();MineCome._gameplay_movement=nil
print('Bounded native injury reaction ownership, velocity limits and nonrenewing expiry passed')
reset();begin();p=MineCome._gameplay_incoming.active
movement={run=run,entity=player,id=player.id};MineCome._gameplay_movement={active=movement};v={x=1,y=0,z=0}
check(not reaction(),'no actual injury/ACK admitted')
check(not MineCome.GameplayCombatIncomingApplied(run,0),'zero ACK opened reaction window')
check(not MineCome.GameplayCombatIncomingApplied(string.rep('b',32),1),'foreign run ACK admitted')
check(MineCome.GameplayCombatIncomingApplied(run,1) and reaction(),'new Minecraft ACK did not open reaction window')
local applied_at=p.applied_at;local ack_receipt=logs[#logs]
t=t+.751
check(not reaction(),'Minecraft reaction window did not expire')
check(MineCome.GameplayCombatIncomingApplied(run,1) and p.applied_at==applied_at and logs[#logs]==ack_receipt and not reaction(),'duplicate Minecraft ACK renewed reaction window')
check(MineCome.GameplayCombatIncomingApplied(run,3) and reaction(),'coalesced cumulative Minecraft ACK refused')
check(not MineCome.GameplayCombatIncomingApplied(run,2),'old Minecraft ACK admitted')
movement.stopping=true;check(not MineCome.GameplayCombatIncomingApplied(run,4),'stopping movement ACK admitted');movement.stopping=nil
v.x=3.001;check(not reaction(),'Minecraft ACK bypassed physical horizontal cap');v.x=1;v.z=6.001;check(not reaction(),'Minecraft ACK bypassed physical vertical cap');v.z=0
finish();MineCome._gameplay_movement=nil
print('Minecraft hurt ACK window ownership, coalescing, expiry and idempotent replay passed')
