-- SPDX-License-Identifier: GPL-3.0-or-later
-- Local native combat telemetry, exact actor names and native proxy upkeep.
-- CombatDebug.StartLog/StopLog supplies LogType2 and SetCVar+ResetLogging.
-- Official Soul.SetState + FeatureTests/player.xml:611 supplies native upkeep;
-- buff.xml:150 supplies the nonpersistent death guard. No event is synthesized
-- from health polling, and native entity GUIDs are NOT soul telemetry GUIDs.
MineCome=MineCome or {}
MineCome._gameplay_incoming=MineCome._gameplay_incoming or {}
local state=MineCome._gameplay_incoming
local BUFF='44e1ccc9-9252-48a9-922d-2ae4523c69a3'
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function integer(v,a,b)return finite(v) and v==math.floor(v) and v>=a and v<=b end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function number(v)return finite(v) and string.format('%.12g',v) or 'null'end
local function quote(v)return '"'..v:gsub('[%z\1-\31\\"]',function(c)if c=='\\'then return '\\\\'elseif c=='"'then return '\\"'end;return string.format('\\u%04x',string.byte(c))end)..'"'end
local function read(o,k,...)
 if type(o)~='table' or type(o[k])~='function'then return nil end
 local ok,a,b=pcall(o[k],o,...);if ok then return a,b end
end
local function clock(p)
 local ok,t=pcall(p.now);return ok and finite(t) and t>=0 and t or nil
end
local function api(p)
 return System==p.system and System.GetCVar==p.get and System.SetCVar==p.set and System.ExecuteCommand==p.command and System.GetEntity==p.entity and System.GetEntityByName==p.named and System.GetCurrTime==p.now
end
local function entity_name(e)
 local name=read(e,'GetName');if type(name)=='string' and #name>0 and #name<=160 then return name end
end
local function player_owned(p)
 if not api(p) or player~=p.player or player.id~=p.player_id or player.soul~=p.soul or player.actor~=p.actor or player.this~=p.player_this or player.this.id~=p.player_wuid or p.soul.SetState~=p.health_set or p.soul.GetState~=p.health_get or p.soul.GetId~=p.soul_getid or p.actor.GetMaxHealth~=p.health_max then return false end
 local ok,e=pcall(p.entity,p.player_id);local named_ok,named=pcall(p.named,p.player_name)
 return ok and e==p.player and named_ok and named==p.player and entity_name(player)==p.player_name and read(p.soul,'GetId')==p.soul_id and read(p.actor,'IsDead')==false and read(p.actor,'GetMaxHealth')==p.maximum
end
local function settings_owned(p)
 if not api(p)then return false end
 for _,e in ipairs(p.entries)do local ok,v=pcall(p.get,e.name);if not ok or v~=e.value then return false end end
 return true
end
local function buff_owned(p)
 return p.buff_instance~=nil and p.soul.AddBuff==p.add_buff and p.soul.RemoveBuff==p.remove_buff and p.soul.HasBuffDebug==p.has_buff and read(p.soul,'HasBuffDebug',BUFF)==true
end
local function emit(p,event,extra)
 local line='[MineComeGameplayIncoming] {"schema":1,"run":'..quote(p.run)..',"event":'..quote(event)..(extra or '')..'}'
 if #line>3900 then return false end
 local ok,v=pcall(System.LogAlways,line);return ok and v~=false
end
local function health_write(p,value)
 if not player_owned(p) or not buff_owned(p)then return false end
 p.health_writes=p.health_writes+1
 local ok,result=pcall(p.health_set,p.soul,'health',value)
 local after=read(p.soul,'GetState','health')
 local confirmed=ok and result~=false and finite(after) and math.abs(after-value)<.001
 if confirmed and value==p.maximum then p.reaction_pending_hp=nil end
 return confirmed
end
local function observed_native_injury(p,hp,t)
 -- Repeated reads of one pending loss must not prolong a reaction allowance.
 if not p.reaction_pending_hp or hp<p.reaction_pending_hp-.001 then p.reaction_at=t end
 p.reaction_pending_hp=hp
end
local function restore_settings(p)
 if not api(p)then return false end
 local restored=true
 for i=#p.entries,1,-1 do local e=p.entries[i]
  if e.attempted then
   local ok,v=pcall(p.get,e.name)
   if not ok then restored=false
   elseif v==e.before then
   elseif v==e.value or e.previous~=nil and v==e.previous then
    local good,result=pcall(p.set,e.name,e.before);local read_ok,after=pcall(p.get,e.name)
    if not good or result==false or not read_ok or after~=e.before then restored=false end
   else restored=false end
  end
 end
 -- Reset closes the OLD logger using its old path, then applies restored CVars.
 if restored and p.reset_attempted then local ok,result=pcall(p.command,'wh_rpg_ResetLogging');restored=ok and result~=false end
 return restored
end
local function stop(p,why)
 if p.stopped then return p.restored end
 p.stopped=true
 if p.timer then local ok,v=pcall(Script.KillTimer,p.timer);if ok and v~=false then p.timer=nil end end;p.timer_data=nil
 -- During this lease native health is only a proxy. Restore the captured
 -- baseline while the exact native player, APIs and our death guard remain ours.
 local owned=player_owned(p)
 local health_restored=not p.buff_attempted
 if p.buff_instance and owned and buff_owned(p)then
  local hp=read(p.soul,'GetState','health')
  health_restored=finite(hp) and hp>0 and hp<=p.maximum and (math.abs(hp-p.original_health)<.001 or health_write(p,p.original_health))
 end
 local buff_restored=not p.buff_attempted
 if p.buff_instance and owned and p.soul.RemoveBuff==p.remove_buff and p.soul.HasBuffDebug==p.has_buff then
  if read(p.soul,'HasBuffDebug',BUFF)==false then buff_restored=true
  else
   p.buff_remove_attempted=true;local ok,result=pcall(p.remove_buff,p.soul,p.buff_instance)
   buff_restored=ok and result~=false and read(p.soul,'HasBuffDebug',BUFF)==false
  end
 end
 local settings_restored=restore_settings(p)
 p.restored=p.timer==nil and health_restored and buff_restored and settings_restored
 state.active=nil;state.last=p
 emit(p,'terminal',',"reason":'..quote(why)..',"sequence":'..(p.epoch+1)..',"closed_path":'..quote(p.path)..',"native_clock_ms":'..number((clock(p)or 0)*1000)..',"restored":'..tostring(p.restored)..',"cvars_restored":'..tostring(settings_restored)..',"buff_restored":'..tostring(buff_restored)..',"health_restored":'..tostring(health_restored)..',"health_writes":'..p.health_writes)
 return p.restored
end
local function valid(p)
 local c=MineCome._gameplay_combat and MineCome._gameplay_combat.active
 local t=clock(p)
 if c~=p.combat or c.stopped or not t or t<p.last_clock or t>=c.deadline or t-c.received>2 then return nil,'lease_expired'end
 if not player_owned(p)then return nil,'player_changed'end
 if not settings_owned(p)then return nil,'logging_changed'end
 if not buff_owned(p)then return nil,'protection_changed'end
 p.last_clock=t;return t
end
local function schedule(p)
 local data={owner=p};local ok,id=pcall(Script.SetTimerForFunction,100,'MineCome_GameplayIncomingTick',data,true)
 if not ok or not id then return false end;p.timer=id;p.timer_data=data;return true
end
function MineCome_GameplayIncomingTick(data)
 local p=type(data)=='table' and data.owner
 if not p or state.active~=p or p.timer_data~=data then return end;p.timer=nil;p.timer_data=nil
 local t,why=valid(p)
 if t then
  local hp=read(p.soul,'GetState','health')
  if finite(hp) and hp>0 and hp<p.maximum then observed_native_injury(p,hp,t)end
  if not finite(hp) or hp<=0 or hp>p.maximum then why='health_unavailable'
  elseif hp<p.maximum and not health_write(p,p.maximum)then why='health_upkeep_failed'
  elseif not schedule(p)then why='timer_unavailable'else return end
 end
 stop(p,why);if type(MineCome.GameplayCombatEnd)=='function'then pcall(MineCome.GameplayCombatEnd,p.run)end
end
function MineCome.GameplayCombatIncomingValidate(run)
 local p=state.active;if not p then return not(state.last and state.last.run==run and not state.last.restored)end
 if p.run~=run then return false end
 return valid(p)~=nil
end
-- A real native hit can briefly set physical velocity even though the guest
-- still owns walking. This read-only exception never produces a Minecraft hit,
-- changes velocity, relaxes position drift or accepts another movement owner.
function MineCome.GameplayCombatIncomingAllowsReaction(run,movement,entity,id,velocity)
 local p=state.active;local m=MineCome._gameplay_movement and MineCome._gameplay_movement.active
 local diagnostic={reason='incoming_missing'}
 if not p or p.run~=run then return false,diagnostic end
 diagnostic.reason='movement_owner'
 if m~=movement or not m or m.run~=run or m.entity~=entity or m.id~=id or m.terminal or m.stopping or entity~=p.player or id~=p.player_id then return false,diagnostic end
 diagnostic.reason='invalid_velocity'
 if type(velocity)~='table' or not finite(velocity.x) or not finite(velocity.y) or not finite(velocity.z) then return false,diagnostic end
 local t,why=valid(p);if not t then diagnostic.reason=why;return false,diagnostic end
 local hp=read(p.soul,'GetState','health');diagnostic.native_health=hp;diagnostic.native_maximum=p.maximum
 if not finite(hp) or hp<=0 or hp>p.maximum then diagnostic.reason='health_unavailable';return false,diagnostic end
 if hp<p.maximum then observed_native_injury(p,hp,t)end
 diagnostic.injury_age_ms=p.reaction_at and (t-p.reaction_at)*1000 or nil
 diagnostic.guest_hurt_ack=p.applied_ack or 0
 diagnostic.guest_hurt_age_ms=p.applied_at and (t-p.applied_at)*1000 or nil
 if velocity.x*velocity.x+velocity.y*velocity.y>9 then diagnostic.reason='horizontal_limit';return false,diagnostic end
 if math.abs(velocity.z)>6 then diagnostic.reason='vertical_limit';return false,diagnostic end
 if p.applied_at and t>=p.applied_at and t-p.applied_at<=.75 then diagnostic.reason='allowed_guest_hurt';return true,diagnostic end
 if not p.reaction_at then diagnostic.reason='no_observed_injury';return false,diagnostic end
 if t<p.reaction_at or t-p.reaction_at>.5 then diagnostic.reason='injury_window_expired';return false,diagnostic end
 diagnostic.reason='allowed';return true,diagnostic
end
-- The exact host supplies only Minecraft's acknowledgement of an owned native
-- hurt. This admits its delayed physical knockback; it does not apply damage.
-- Cumulative ACKs may coalesce, but replay never refreshes the original window.
function MineCome.GameplayCombatIncomingApplied(run,ack)
 local p=state.active;local m=MineCome._gameplay_movement and MineCome._gameplay_movement.active
 if not p or p.run~=run or not integer(ack,1,10000000) or not m or m.run~=run or m.entity~=p.player or m.id~=p.player_id or m.terminal or m.stopping then return false,'applied_not_owned'end
 local t,why=valid(p);if not t then return false,why end
 local previous=p.applied_ack or 0
 if ack<previous then return false,'applied_replayed'end
 if ack==previous then return emit(p,'applied',p.last_applied)end
 p.applied_ack=ack;p.applied_at=t
 p.last_applied=',"ack":'..ack..',"native_clock_ms":'..number(t*1000)
 if not emit(p,'applied',p.last_applied)then stop(p,'log_failed');return false,'log_failed'end
 return true
end
function MineCome.GameplayCombatIncomingBegin(run,path)
 local c=MineCome._gameplay_combat and MineCome._gameplay_combat.active
 if not token(run) or not c or c.run~=run or c.stopped or type(path)~='string' or #path>230 or not path:match('^[A-Za-z]:/[%w%._%-% /]+/000000/$') or not path:find(run,1,true)then return false,'invalid_begin'end
 if state.active or state.last and not state.last.restored then return false,'owned_or_unrestored'end
 if type(System)~='table' or type(System.GetCVar)~='function' or type(System.SetCVar)~='function' or type(System.ExecuteCommand)~='function' or type(System.GetEntity)~='function' or type(System.GetEntityByName)~='function' or type(System.GetCurrTime)~='function' or type(System.LogAlways)~='function' or type(Script)~='table' or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'api_missing'end
 if player~=c.player or type(player.soul)~='table' or type(player.actor)~='table' or type(player.this)~='table' then return false,'player_missing'end
 local s=player.soul;local a=player.actor
 for _,key in ipairs({'GetId','GetState','SetState','AddBuff','RemoveBuff','HasBuffDebug'})do if type(s[key])~='function'then return false,'soul_api_missing'end end
 local p={run=run,combat=c,player=player,player_id=player.id,player_this=player.this,player_wuid=player.this.id,soul=s,actor=a,soul_id=read(s,'GetId'),player_name=entity_name(player),system=System,get=System.GetCVar,set=System.SetCVar,command=System.ExecuteCommand,entity=System.GetEntity,named=System.GetEntityByName,now=System.GetCurrTime,health_set=s.SetState,health_get=s.GetState,health_max=a.GetMaxHealth,soul_getid=s.GetId,add_buff=s.AddBuff,remove_buff=s.RemoveBuff,has_buff=s.HasBuffDebug,maximum=read(a,'GetMaxHealth'),original_health=read(s,'GetState','health'),entries={},path=path,prefix=path:sub(1,-8),epoch=0,identities={},health_writes=0}
 if not p.player_name or not p.soul_id or not finite(p.maximum) or p.maximum<=0 or p.maximum>1000000 or not finite(p.original_health) or p.original_health<=0 or p.original_health>p.maximum or not player_owned(p) or read(s,'HasBuffDebug',BUFF)~=false then return false,'player_baseline_missing'end
 local now=clock(p);if not now or now<c.last_clock or now>=c.deadline or now-c.received>2 then return false,'lease_expired'end;p.started=now;p.last_clock=now
 local values={{'wh_rpg_LogFilepath',path},{'wh_rpg_LogCompression',0},{'wh_rpg_LogLevel',1},{'wh_rpg_LogType',2},{'wh_rpg_LogReasons',0},{'wh_rpg_LogInterval',100000},{'wh_rpg_LogSize',100000000},{'wh_rpg_TelemetryLimitedToPlayline',0},{'wh_rpg_LogTarget',2}}
 for _,v in ipairs(values)do local ok,before=pcall(p.get,v[1]);if not ok or type(before)~=type(v[2]) or type(before)=='number' and not finite(before)then return false,'logging_baseline_missing'end;p.entries[#p.entries+1]={name=v[1],value=v[2],before=before}end
 state.active=p;if not schedule(p)then state.active=nil;return false,'timer_unavailable'end
 p.buff_attempted=true;local buff_ok,instance=pcall(p.add_buff,p.soul,BUFF)
 if buff_ok and (type(instance)=='userdata' or type(instance)=='string' and #instance>0 or finite(instance) and instance>0)then p.buff_instance=instance end
 if not buff_ok or not buff_owned(p)then stop(p,'protection_setup_failed');return false,'protection_setup_failed'end
 for _,e in ipairs(p.entries)do e.attempted=true;local ok,result=pcall(p.set,e.name,e.value);local got,current=pcall(p.get,e.name)
  if not ok or result==false or not got or current~=e.value then stop(p,'logging_setup_failed');return false,'logging_setup_failed'end
 end
 p.reset_attempted=true;local reset_ok,result=pcall(p.command,'wh_rpg_ResetLogging')
 if not reset_ok or result==false then stop(p,'logging_reset_failed');return false,'logging_reset_failed'end
 if p.original_health<p.maximum and not health_write(p,p.maximum)then stop(p,'health_setup_failed');return false,'health_setup_failed'end
 if not emit(p,'begin',',"player_name":'..quote(p.player_name)..',"native_clock_ms":'..number(now*1000)..',"native_maximum":'..number(p.maximum)..',"path":'..quote(path))then stop(p,'log_failed');return false,'log_failed'end
 return true
end
function MineCome.GameplayCombatIncomingSample(run,seq,nearby_actors)
 local p=state.active;if not p then return true end
 if p.run~=run then return false end
 local t,why=valid(p);if not t then stop(p,why);return false end
 local sample=p.combat.samples[seq];if not sample then return false end
 local names,rows={},{}
 -- Count every enumerated nearby actor, including ones omitted by the packet's
 -- eight-actor limit. A truncated actor list cannot prove unique names.
 if type(nearby_actors)~='table'then return false end
 for _,a in ipairs(nearby_actors)do local name=entity_name(a.entity);if name then names[name]=(names[name]or 0)+1 end end
 if names[p.player_name]then stop(p,'ambiguous_player_name');return false end
 local tokens={};for id in pairs(sample.actors)do tokens[#tokens+1]=id end;table.sort(tokens)
 for _,id in ipairs(tokens)do local a=sample.actors[id];local name=entity_name(a.entity)
  local ok,e=pcall(p.entity,a.id);local good,named
  if name then good,named=pcall(p.named,name)end
  if name and name~=p.player_name and names[name]==1 and ok and e==a.entity and good and named==a.entity and a.entity.soul==a.soul and read(a.soul,'GetId')==a.soul_id then
   local first=math.max(p.started,p.combat.actors[id].first_seen or sample.time)*1000
   local old=p.identities[id]
   if old and (old.name~=name or old.first_seen_ms~=first)then stop(p,'actor_identity_changed');return false end
   p.identities[id]=old or{name=name,first_seen_ms=first}
   rows[#rows+1]='{"token":'..id..',"name":'..quote(name)..',"first_seen_ms":'..number(first)..'}'
  end
 end
 if not emit(p,'identity',',"seq":'..seq..',"player_name":'..quote(p.player_name)..',"native_clock_ms":'..number(t*1000)..',"actors":['..table.concat(rows,',')..']')then stop(p,'log_failed');return false end
 return true
end
function MineCome.GameplayCombatIncomingRotate(run,epoch)
 local p=state.active;if not p or p.run~=run then return false,'session_missing'end
 local t,why=valid(p);if not t then stop(p,why);return false,why end
 if integer(epoch,1,999999) and epoch==p.epoch and p.last_close then return emit(p,'closed_segment',p.last_close)end
 if not integer(epoch,1,999999) or epoch~=p.epoch+1 then return false,'invalid_epoch'end
 local previous=p.path;local next_path=p.prefix..string.format('%06d',epoch)..'/'
 local entry=p.entries[1];entry.previous=entry.value;entry.value=next_path
 local ok,result=pcall(p.set,entry.name,next_path);local got,value=pcall(p.get,entry.name)
 if not ok or result==false or not got or value~=next_path then stop(p,'rotation_path_failed');return false,'rotation_path_failed'end
 local reset_ok,reset_result=pcall(p.command,'wh_rpg_ResetLogging')
 if not reset_ok or reset_result==false then stop(p,'rotation_reset_failed');return false,'rotation_reset_failed'end
 entry.previous=nil;p.path=next_path;p.epoch=epoch
 p.last_close=',"sequence":'..epoch..',"closed_path":'..quote(previous)..',"next_path":'..quote(next_path)..',"native_clock_ms":'..number((clock(p)or t)*1000)
 if not emit(p,'closed_segment',p.last_close)then stop(p,'log_failed');return false,'log_failed'end
 return true
end
function MineCome.GameplayCombatIncomingEnd(run)
 local p=state.active
 if not p then return not(state.last and state.last.run==run and not state.last.restored)end
 if p.run~=run then return false end
 return stop(p,'explicit_stop')
end
