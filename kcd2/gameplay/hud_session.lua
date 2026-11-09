-- SPDX-License-Identifier: GPL-3.0-or-later
-- Selective native stats visibility, owned by one existing movement session.
-- Installed KCD2Mod Data/IPL_GameData.pak, Libs/UI/UIElements/HUD.xml:2,693
-- defines element "hud" and MovieClip "Stats" (bc.mc_StatsContainer.mc_StatsEle).
-- Player/horse/opponent bars are children (735-754); compass, subtitles,
-- dialogue and interaction prompts are separate clips and are never written.
-- Inspected kcd2-mod-docs 9cb0675 CScriptBindUIAction__{IsVisible,SetVisible}
-- documents UIAction.<method>(elementName, instanceID, mcName[, boolean]).
-- Instance 0 is the normal game HUD; never use -1 (all instances).
-- Live true/false/true and peer-expiry restoration, other clips unchanged:
-- hud-selective-validation-20261109-152332-5a41cd11702a48a6875528f7300f3fdf.
-- Every UI read/write runs on an owned pause-updating engine timer. The
-- existing movement pose heartbeat renews this lease, not a new host poll.
-- Another writer setting the same value cannot be distinguished by readback.
MineCome = MineCome or {}
assert(type(MineCome)=='table','MineCome namespace unavailable')
local root,state=MineCome,MineCome._gameplay_hud
local function exports(s)
 return root.GameplayHudBegin==s.begin and root.GameplayHudEnd==s.finish and root.ReportGameplayHud==s.report
end
if state==nil then
 assert(MineCome_GameplayHudTimer==nil and root.GameplayHudBegin==nil and root.GameplayHudEnd==nil and root.ReportGameplayHud==nil,'HUD exports already owned')
 state={owner='minecome_gameplay_hud_v1'};root._gameplay_hud=state
else
 assert(type(state)=='table' and state.owner=='minecome_gameplay_hud_v1' and state.callback==MineCome_GameplayHudTimer and exports(state),'HUD state already owned')
end
local LEASE=2
local function finite(v)return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function token(v)return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function handle(v)return type(v)=='userdata' or finite(v) and v>0 and v==math.floor(v) end
local function owned()return MineCome==root and root._gameplay_hud==state and state.callback==MineCome_GameplayHudTimer and exports(state) end
local function clock(p)
 if p and (System~=p.system or System.GetCurrTime~=p.clock) then return nil end
 if not System or type(System.GetCurrTime)~='function' then return nil end
 local ok,v=pcall(System.GetCurrTime);return ok and finite(v) and v>=0 and v<1e12 and v or nil
end
local function bindings(p)return UIAction==p.ui and UIAction and UIAction.IsVisible==p.reader and UIAction.SetVisible==p.writer end
local function read(p)
 if not bindings(p) then return nil end
 local ok,v=pcall(p.reader,'hud',0,'Stats');if ok and type(v)=='boolean' then return v end
end
local function quote(v)return '"'..tostring(v):gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"' end
local function value(v)if type(v)=='boolean' then return tostring(v) elseif finite(v) then return string.format('%.17g',v) elseif type(v)=='string' then return quote(v) end return 'null' end
local function emit(p,event)
 local o={schema=1,run=p.run,event=event,result=p.reason or 'queued',backend='ui_movieclip',element='hud',instance=0,clip='Stats',
  original_visible=p.original,current_visible=p.current,hidden=p.applied==true and p.current==false,restored=p.restored==true,
  active=state.active==p and not p.terminal,write_attempted=p.write_attempted==true,owned_write=p.owned_write==true,
  restore_attempted=p.restore_attempted==true,timers_cancelled=p.timers_cancelled~=false,lease_seconds=LEASE,
  native_clock_ms=(clock(p) or 0)*1000,movement_sequence=p.movement.sequence or 0}
 local parts={};for _,k in ipairs({'schema','run','event','result','backend','element','instance','clip','original_visible','current_visible','hidden','restored','active','write_attempted','owned_write','restore_attempted','timers_cancelled','lease_seconds','native_clock_ms','movement_sequence'}) do parts[#parts+1]=quote(k)..':'..value(o[k]) end
 if System~=p.system or System.LogAlways~=p.log then return false,o end
 local ok,v=pcall(p.log,'[MineComeGameplayHud] {'..table.concat(parts,',')..'}');return ok and v~=false,o
end
local function cancel(p)
 for slot,id in pairs(p.timers)do
  p.timers[slot]=nil;local ok,v=false,false
  if Script==p.script and Script.KillTimer==p.kill then ok,v=pcall(p.kill,id)end
  if not ok or v==false then p.timers_cancelled=false end
 end
end
local function finish(p,reason)
 if state.active~=p or p.terminal then return false end
 p.reason=reason;p.current=read(p)
 if p.original~=nil then
  if p.current==p.original then p.restored=true
  elseif p.write_attempted and p.current==false and bindings(p) then
   p.restore_attempted=true;pcall(p.writer,'hud',0,'Stats',p.original)
   p.current=read(p);p.restored=p.current==p.original
  end
 else p.restored=not p.write_attempted end
 p.terminal=true;cancel(p);state.active=nil;state.last=p
 local logged=emit(p,'terminal');return p.restored==true and logged
end
local function arm(p,slot,delay)
 if Script~=p.script or Script.SetTimerForFunction~=p.schedule or p.timers[slot]~=nil then return false end
 local data={owner=p,slot=slot};p.data[slot]=data
 local ok,id=pcall(p.schedule,delay,'MineCome_GameplayHudTimer',data,true)
 if not ok or not handle(id)then p.data[slot]=nil;return false end
 p.timers[slot]=id;return true
end
local function reason(p)
 local t=clock(p);if not t or t<p.last_clock then return 'clock_invalid' end;p.last_clock=t
 if t>=p.deadline then return 'session_expired' end
 local m=p.movement
 if root._gameplay_movement~=p.movement_state or p.movement_state.active~=m or m.terminal or m.stopping or m.run~=p.run then return 'movement_stopped' end
 if player~=p.entity or player.id~=p.id or m.entity~=p.entity or m.id~=p.id then return 'player_changed' end
 local heartbeat=m.latest and m.latest.received or p.created
 if not finite(heartbeat) or heartbeat>t or t-heartbeat>LEASE then return 'peer_lease_expired' end
 if not bindings(p) then return 'binding_changed' end
end
function MineCome.GameplayHudBegin(run,duration_ms)
 if not owned()then return false,'ownership_lost' end
 if not token(run) or not finite(duration_ms) or duration_ms~=math.floor(duration_ms) or duration_ms<1000 or duration_ms>86400000 then return false,'invalid_run_or_duration' end
 if state.active then return false,'busy' end
 if state.last and state.last.run==run then return false,'run_consumed' end
 if state.last and not state.last.restored then return false,'prior_cleanup_incomplete' end
 if root._hud_visibility and root._hud_visibility.active then return false,'diagnostic_busy' end
 local ms=root._gameplay_movement;local m=type(ms)=='table' and ms.active
 if type(m)~='table' or m.run~=run or m.terminal or m.stopping or m.entity~=player or m.id==nil or type(player)~='table' or player.id~=m.id then return false,'movement_owner_unavailable' end
 local t=clock();if not t or not finite(m.deadline) or m.deadline<=t then return false,'movement_deadline_unavailable' end
 if not UIAction or type(UIAction.IsVisible)~='function' or type(UIAction.SetVisible)~='function' or type(System.LogAlways)~='function' then return false,'ui_api_unavailable' end
 if not Script or type(Script.SetTimerForFunction)~='function' or type(Script.KillTimer)~='function' then return false,'timer_api_unavailable' end
 local p={run=run,created=t,last_clock=t,deadline=math.min(t+duration_ms/1000,m.deadline),movement=m,movement_state=ms,entity=player,id=m.id,
  ui=UIAction,reader=UIAction.IsVisible,writer=UIAction.SetVisible,system=System,clock=System.GetCurrTime,log=System.LogAlways,
  script=Script,schedule=Script.SetTimerForFunction,kill=Script.KillTimer,timers={},data={}}
 state.active=p
 -- Schedule expiry before the first callback that can touch Flash state.
 if not arm(p,'expiry',math.max(1,math.floor((p.deadline-t)*1000))) or not arm(p,'tick',1) then
  -- No UI call has happened yet; failure cleanup needs no engine UI access.
  p.restored=true;p.terminal=true;p.reason='timer_arm_failed';cancel(p);state.active=nil;state.last=p;emit(p,'terminal');return false,p.reason
 end
 if not emit(p,'queued')then p.end_requested=true;return false,'log_failed' end
 return true,'queued'
end
function MineCome_GameplayHudTimer(data)
 if type(data)~='table' or not owned() then return false end
 local p=data.owner;local slot=data.slot
 if type(p)~='table' or state.active~=p or p.terminal or p.data[slot]~=data or not handle(p.timers[slot])then return false end
 p.timers[slot]=nil
 if slot=='expiry'then return finish(p,'session_expired')end
 if p.end_requested then return finish(p,'requested_end')end
 local why=reason(p);if why then return finish(p,why)end
 p.current=read(p)
 if not p.applied then
  if p.current==nil then return finish(p,'visibility_unavailable')end
  p.original=p.current
  if p.original then
   p.write_attempted=true;local ok,v=pcall(p.writer,'hud',0,'Stats',false);p.current=read(p);p.owned_write=p.current==false
   if not ok or v==false or p.current~=false then return finish(p,'hide_failed')end
  end
  p.applied=true;p.reason='hidden'
  if not emit(p,'begin')then return finish(p,'log_failed')end
 elseif p.current~=false then return finish(p,'visibility_changed')end
 why=reason(p);if why then return finish(p,why)end
 if not arm(p,'tick',100)then return finish(p,'heartbeat_timer_failed')end
 return true
end
state.callback=MineCome_GameplayHudTimer
function MineCome.GameplayHudEnd(run)
 if not owned() or not token(run)then return false,'invalid_owner_or_run' end
 local p=state.active or state.last;if not p or p.run~=run then return false,'inactive' end
 if p.terminal then local ok=emit(p,'terminal');return p.restored==true and ok,p.reason end
 p.end_requested=true
 if not p.timers.stop and not arm(p,'stop',1)then return false,'end_timer_failed' end
 return true,'queued'
end
function MineCome.ReportGameplayHud(run)
 if not owned() or not token(run)then return false,'invalid_owner_or_run' end
 local p=state.active or state.last;if not p or p.run~=run then return false,'inactive' end
 return emit(p,'status') -- Cached visibility: never touch Flash from a console callback.
end
state.begin,state.finish,state.report=root.GameplayHudBegin,root.GameplayHudEnd,root.ReportGameplayHud
