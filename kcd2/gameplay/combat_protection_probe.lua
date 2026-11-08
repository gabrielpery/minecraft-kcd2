-- SPDX-License-Identifier: GPL-3.0-or-later
-- Explicit owned-NPC experiment; never protects, damages or heals the player.
-- Source: official buff.xml:150 / buff_exclusivity.xml:5; Soul AddBuff,
-- RemoveBuff, HasBuffDebug and DealDamage binding pages. SinglePlayer.lua:291-298
-- dispatches target.Client.OnHit(target,hit). Optional normal_hit follows
-- SinglePlayer.lua:184-206 CreateHit -> game:ServerHit and
-- Entities/Others/Hazard.lua:169 (entity shooter/weapon IDs). Soul damage uses
-- player.this.id WUID as in the official hostageSituation scripts. No interception claim.
MineCome=MineCome or {}
MineCome._combat_protection_probe=MineCome._combat_protection_probe or {}
local state=MineCome._combat_protection_probe
local BUFF='44e1ccc9-9252-48a9-922d-2ae4523c69a3'
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function wuid(e)
 local id=type(e)=='table' and type(e.this)=='table' and e.this.id
 if (type(id)=='string' and id~='') or (type(id)=='number' and finite(id) and id>0) or type(id)=='userdata' then
  if __null==nil or id~=__null then return id end
 end
end
local function n(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function b(v)return type(v)=='boolean' and tostring(v) or 'null'end
local function clean(v)return tostring(v):gsub('[^a-zA-Z0-9_ :./-]','_'):sub(1,240)end
local function require_true(v,why)if not v then error(why,0)end end
local function owned(p)
 local f=MineCome._gameplay_combat_fixture and MineCome._gameplay_combat_fixture.active
 return f==p.fixture and f and f.entity==p.entity and p.entity~=player and p.entity.id==p.id and p.entity.soul==p.soul and
  System.GetEntity(p.id)==p.entity and System.GetEntityByName(p.fixture.name)==p.entity
end
local function emit(p)
 local hits={}
 for _,h in ipairs(p.hits)do hits[#hits+1]='{"damage":'..n(h.damage)..',"damage_type":"'..h.damage_type..'","hit_type":"'..h.hit_type..'","target_matches":'..b(h.target_matches)..',"shooter_matches":'..b(h.shooter_matches)..'}'end
 System.LogAlways('[MineComeCombatProtection] {"schema":1,"run":"'..p.run..'","damage_mode":"'..p.damage_mode..'","attacker_identifier_kind":"'..p.attacker_identifier_kind..'","completed":'..tostring(p.completed==true)..',"reason":"'..clean(p.reason)..'","active":'..tostring(state.active==p)..',"timers_cancelled":'..tostring(p.timer==nil)..',"player_mutated":false,"before":'..n(p.before)..',"maximum":'..n(p.maximum)..',"nonlethal_after":'..n(p.nonlethal_after)..',"nonlethal_dead":'..b(p.nonlethal_dead)..',"lethal_after":'..n(p.lethal_after)..',"lethal_dead":'..b(p.lethal_dead)..',"nonlethal_damage_observed":'..tostring(p.nonlethal_damage_observed==true)..',"lethal_damage_observed":'..tostring(p.lethal_damage_observed==true)..',"protection_observed":'..tostring(p.protection_observed==true)..',"buff_baseline_type":"'..clean(p.buff_baseline_type or 'unread')..'","buff_after_type":"'..clean(p.buff_after_type or 'unread')..'","buff_instance_type":"'..clean(p.buff_instance_type or 'unread')..'","buff_removed":'..tostring(p.buff_removed==true)..',"callback_restored":'..tostring(p.callback_restored==true)..',"callback_count":'..p.callback_count..',"callbacks_truncated":'..tostring(p.callback_count>#p.hits)..',"hits":['..table.concat(hits,',')..']}')
end
local function finish(p,reason,completed)
 if p.finished then return end;p.finished=true;p.reason=reason;p.completed=completed==true
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil end end;p.timer_data=nil
 if p.client_copy then
  if owned(p) and rawget(p.entity,'Client')==p.client_copy then p.entity.Client=p.original_client_raw end
  p.callback_restored=owned(p) and rawget(p.entity,'Client')==p.original_client_raw and p.entity.Client==p.original_client
 else p.callback_restored=true end
 if p.buff_attempted then
  if owned(p) and p.buff_instance~=nil then
   local ok=pcall(p.soul.RemoveBuff,p.soul,p.buff_instance)
   local read_ok,present=pcall(p.soul.HasBuffDebug,p.soul,BUFF)
   p.buff_removed=ok and read_ok and present==false
  else p.buff_removed=false end
 else p.buff_removed=true end
 if state.active==p then state.active=nil end;state.last=p
 if not p.buff_removed or not p.callback_restored or p.timer~=nil then p.completed=false;p.reason=reason..'_cleanup_unconfirmed'end
 pcall(MineCome.GameplayCombatFixtureEnd,p.run)
 emit(p)
end
local function schedule(p,delay)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,delay,'MineCome_CombatProtectionTick',data,true)
 if not ok or id==nil or id==false then return false end;p.timer=id;p.timer_data=data;return true
end
local function valid(p)
 require_true(owned(p),'npc_ownership_changed')
 require_true(player==p.player and player.id==p.player_id and (p.damage_mode~='soul' or wuid(player)==p.player_wuid),'player_identity_changed')
 local t=System.GetCurrTime();require_true(finite(t) and t>=p.started and t-p.started<5,'probe_deadline')
end
local function health(p)
 local value=p.soul:GetState('health');local dead=p.entity.actor:IsDead()
 require_true(finite(value) and value>=0 and value<=p.maximum and type(dead)=='boolean','health_state_unavailable')
 return value,dead
end
local function damage(p,amount)
 valid(p)
 if p.damage_mode=='normal_hit' then
  require_true(g_gameRules==p.rules and p.rules.CreateHit==p.create_hit and p.rules.game==p.rules_game,'game_rules_identity_changed')
  p.rules:CreateHit(p.id,p.player_id,p.player_id,amount,nil,nil,nil,'normal')
 else p.soul:DealDamage(0,amount,p.player_wuid,false)end
end
function MineCome_CombatProtectionTick(data)
 local p=type(data)=='table' and data.owner
 if not p or p~=state.active or p.timer_data~=data or p.finished then return end;p.timer=nil;p.timer_data=nil
 local ok,why=pcall(function()
  valid(p)
  if p.stage==1 then
   local present=p.soul:HasBuffDebug(BUFF);p.buff_after_type=type(present);require_true(present==true,'buff_presence_unconfirmed')
   damage(p,p.maximum*.1);p.stage=2
   require_true(schedule(p,300),'timer_unavailable')
  elseif p.stage==2 then
   p.nonlethal_after,p.nonlethal_dead=health(p);p.nonlethal_damage_observed=p.nonlethal_after<p.before;require_true(not p.nonlethal_dead,'nonlethal_killed_npc')
   damage(p,p.maximum*2);p.stage=3
   require_true(schedule(p,300),'timer_unavailable')
  elseif p.stage==3 then
   p.lethal_after,p.lethal_dead=health(p);p.lethal_damage_observed=p.lethal_after<p.nonlethal_after
   p.protection_observed=p.nonlethal_damage_observed and p.lethal_damage_observed and not p.lethal_dead and p.lethal_after>0
   finish(p,'experiment_complete',true)
  else error('invalid_stage',0)end
 end)
 if not ok then finish(p,clean(why),false)end
end
function MineCome.GameplayCombatProtectionProbe(run,damage_mode)
 if type(run)~='string' or #run~=32 or not run:match('^[0-9a-f]+$')then return false,'invalid_run'end
 if damage_mode==nil then damage_mode='soul'end
 if damage_mode~='soul' and damage_mode~='normal_hit' then return false,'invalid_damage_mode'end
 if state.active then return false,'probe_owned'end
 local p={run=run,damage_mode=damage_mode,attacker_identifier_kind=damage_mode=='soul' and 'wuid' or 'entity_handle',hits={},callback_count=0,player=player,player_id=player and player.id,stage=0}
 state.active=p
 local ok,why=pcall(function()
  require_true(player and player.actor and type(System.GetCurrTime)=='function','player_or_clock_missing')
  p.started=System.GetCurrTime();require_true(finite(p.started),'clock_unavailable')
  if damage_mode=='soul' then p.player_wuid=wuid(player);require_true(p.player_wuid~=nil,'player_wuid_unavailable')end
  if damage_mode=='normal_hit' then
   require_true(type(g_gameRules)=='table' and type(g_gameRules.CreateHit)=='function' and type(g_gameRules.game)=='table' and type(g_gameRules.game.ServerHit)=='function','normal_hit_api_missing')
   p.rules=g_gameRules;p.create_hit=g_gameRules.CreateHit;p.rules_game=g_gameRules.game
  end
  local pos=player:GetWorldPos();local d=player.actor:GetHeadDir();local horizontal=math.sqrt(d.x*d.x+d.y*d.y)
  require_true(horizontal>.1,'native_view_vertical')
  local spawned,reason=MineCome.GameplayCombatFixtureBegin(run,10000,pos.x+d.x/horizontal*2,pos.y+d.y/horizontal*2,pos.z)
  require_true(spawned,'fixture_'..tostring(reason))
  p.fixture=MineCome._gameplay_combat_fixture.active;p.entity=p.fixture and p.fixture.entity;p.id=p.entity and p.entity.id;p.soul=p.entity and p.entity.soul
  valid(p)
  require_true(type(p.soul.HasBuffDebug)=='function' and type(p.soul.AddBuff)=='function' and type(p.soul.RemoveBuff)=='function' and type(p.soul.DealDamage)=='function','buff_api_missing')
  p.maximum=p.entity.actor:GetMaxHealth();require_true(finite(p.maximum) and p.maximum>0 and p.maximum<=1000000,'maximum_unavailable')
  local dead;p.before,dead=health(p);require_true(not dead and p.before>p.maximum*.2,'fixture_health_invalid')
  local baseline=p.soul:HasBuffDebug(BUFF);p.buff_baseline_type=type(baseline);require_true(baseline==false,'buff_absent_baseline_unconfirmed');valid(p)
  p.original_client_raw=rawget(p.entity,'Client');p.original_client=p.entity.Client
  require_true(p.original_client==nil or type(p.original_client)=='table','client_callback_table_invalid')
  local original=p.original_client and p.original_client.OnHit;require_true(original==nil or type(original)=='function','client_callback_invalid')
  p.client_copy={};for key,value in pairs(p.original_client or {})do p.client_copy[key]=value end
  p.client_copy.OnHit=function(target,hit,...)
   if target==p.entity and owned(p) and not p.finished then
    p.callback_count=p.callback_count+1
    if #p.hits<8 then local h=type(hit)=='table' and hit or {}
     p.hits[#p.hits+1]={damage=finite(h.damage) and h.damage or nil,damage_type=type(h.damage),hit_type=clean(h.type or type(hit)),target_matches=h.target==p.entity or h.targetId==p.id,shooter_matches=h.shooter==p.player or h.shooterId==p.player_id}
    end
   end
   if original then return original(target,hit,...)end
  end
  p.entity.Client=p.client_copy
  p.buff_attempted=true;local instance=p.soul:AddBuff(BUFF);p.buff_instance_type=type(instance)
  require_true(type(instance)=='userdata' or (type(instance)=='string' and #instance>0) or (finite(instance) and instance>0),'buff_instance_unavailable')
  p.buff_instance=instance;p.stage=1;require_true(schedule(p,200),'timer_unavailable')
 end)
 if not ok then finish(p,clean(why),false);return false,p.reason end
 return true,'scheduled'
end
function MineCome.GameplayCombatProtectionEnd(run)
 local p=state.active
 if p and p.run==run then finish(p,'explicit_stop',false);return true end
 return state.last~=nil and state.last.run==run
end
