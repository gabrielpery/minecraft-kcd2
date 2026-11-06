-- SPDX-License-Identifier: GPL-3.0-or-later
-- Bounded camera-only diagnostic; loading performs no engine calls.
-- Inspected kcd2-mod-docs 9cb067543245ec5cf4e27b3d21e32485a35db518:
-- Scripts/Scripts/CommandExecutor/cube.xml:14-38 calls
-- CryAction.SetViewCamera(position,{dx,dy,dz}) and ResetToNormalCamera().
-- script_bind_2025_01_14/CScriptBindAction__ResetToNormalCamera@IFunctionHandler__.html:60-62
-- describes restoring the last valid view. Camera/time/player getters and
-- Script timers use the established movement_probe.lua binding path.
-- C_ScriptBindActor__GetHeadDir@IFunctionHandler__.html:60-64 and
-- C_ScriptBindActor__GetHeadPos@IFunctionHandler__.html:60-62 document optional
-- observations only; they do NOT establish an independent mouse-look source.
-- Entry: MineCome.BeginPerspectiveProbe(run,"back"|"front",distance,duration_ms)
-- Default 0.25m / 300ms; maximum 2.5m / 1000ms. No player or input writes.
-- Use only through the exact tools executable guard in KcdToolsProbeHelpers.ps1.
MineCome = MineCome or {}
assert(type(MineCome)=="table", "MineCome namespace is not a table")
MineCome._perspective_probe = MineCome._perspective_probe or {}
local state = MineCome._perspective_probe
local LIMIT = 10000000
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function token(v) return type(v)=='string' and #v==32 and v:match('^[0-9a-f]+$')~=nil end
local function field(o,k) if type(o)~='table' and type(o)~='userdata' then return nil end local ok,v=pcall(function()return o[k]end);return ok and v or nil end
local function read(o,k,global) local f=field(o,k);if type(f)~='function' then return nil,false end local ok,v;if global then ok,v=pcall(f) else ok,v=pcall(f,o) end;return v,ok end
local function copy(v) if type(v)~='table' then return nil end local x,y,z=v.x,v.y,v.z;if not finite(x) or not finite(y) or not finite(z) or math.abs(x)>LIMIT or math.abs(y)>LIMIT or math.abs(z)>LIMIT then return nil end;return {x=x,y=y,z=z} end
local function distance(a,b) if not a or not b then return math.huge end return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function scale(v,n) return {x=v.x*n,y=v.y*n,z=v.z*n} end
local function clock() local v,ok=read(System,'GetCurrTime',true);return ok and finite(v) and v>=0 and v<1e12 and v or nil end
local function number(v) return finite(v) and string.format('%.17g',v) or 'null' end
local function vec(v) return v and ('{"x":'..number(v.x)..',"y":'..number(v.y)..',"z":'..number(v.z)..'}') or 'null' end
local function quote(v) return '"'..tostring(v):gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"' end
local function handle(v) return type(v)=='userdata' or (finite(v) and v>0 and v==math.floor(v)) end
local function snapshot()
 local e=player;local s={entity=e,id=field(e,'id')}
 s.position=copy(read(e,'GetWorldPos'));s.velocity=copy(read(e,'GetVelocity'))
 s.camera=copy(read(System,'GetViewCameraPos',true));s.forward=copy(read(System,'GetViewCameraDir',true));s.up=copy(read(System,'GetViewCameraUpDir',true));s.fov=read(System,'GetViewCameraFov',true)
 local actor=field(e,'actor');s.head_position=copy(read(actor,'GetHeadPos'));s.head_direction=copy(read(actor,'GetHeadDir'))
 s.link,s.link_ok=read(actor,'GetLinkedEntity');s.flags={}
 for _,item in ipairs({{actor,'IsDead'},{actor,'IsUnconscious'},{field(e,'player'),'IsSitting'},{field(e,'player'),'IsLaying'},{field(e,'human'),'IsMounted'}}) do local v,ok=read(item[1],item[2]);s.flags[#s.flags+1]={value=v,ok=ok} end
 s.stable=rawequal(e,player) and rawequal(s.id,field(e,'id'))
 return s
end
local function basis(s)
 return s.camera and s.forward and s.up and finite(s.fov) and s.fov>0 and s.fov<math.pi
  and math.abs(dot(s.forward,s.forward)-1)<=.01 and math.abs(dot(s.up,s.up)-1)<=.01 and math.abs(dot(s.forward,s.up))<=.01
end
local function safe(s,p)
 if not s.stable or not s.entity or not handle(s.id) or not s.position or not s.velocity then return 'player_unavailable' end
 if p and (not rawequal(s.entity,p.entity) or not rawequal(s.id,p.id)) then return 'player_changed' end
 for _,v in ipairs(s.flags) do if not v.ok or v.value~=false then return 'unsafe_player_state' end end
 if not s.link_ok or (s.link~=nil and s.link~=0) then return 'linked_player' end
 if not basis(s) then return 'camera_unavailable' end
 if not p and distance(s.camera,s.position)>3 then return 'normal_camera_unavailable' end
 if distance(s.velocity,{x=0,y=0,z=0})>.05 then return 'native_input_or_velocity' end
 if p and distance(s.position,p.origin)>.03 then return 'player_moved' end
end
local function emit(p,stage,result,s)
 local text='{"schema":1,"run":'..quote(p.run)..',"stage":'..quote(stage)..',"result":'..quote(result)
  ..',"terminal":'..tostring(p.terminal==true)..',"stop_reason":'..quote(p.stop_reason or '')..',"mode":'..quote(p.mode)..',"distance":'..number(p.distance)..',"duration_ms":'..number(p.duration)
  ..',"write_attempted":'..tostring(p.write_attempted==true)..',"reset_attempts":'..number(p.reset_attempts or 0)..',"reset_succeeded":'..tostring(p.reset_succeeded==true)
  ..',"camera_readback":'..tostring(p.camera_readback==true)..',"restored_readback":'..tostring(p.restored_readback==true)..',"feet_unchanged":'..tostring(s~=nil and rawequal(s.entity,p.entity) and rawequal(s.id,p.id) and distance(s.position,p.origin)<=.03)
  ..',"player_writes":0,"sampled_engine_seconds":'..number(clock())..',"origin":'..vec(p.origin)..',"camera_origin":'..vec(p.camera_origin)..',"target":'..vec(p.target)
  ..',"player":'..vec(s and s.position)..',"camera":'..vec(s and s.camera)..',"forward":'..vec(s and s.forward)..',"up":'..vec(s and s.up)..',"fov":'..number(s and s.fov)
  ..',"head_position":'..vec(s and s.head_position)..',"head_direction":'..vec(s and s.head_direction)..',"timers_cancelled":'..tostring(p.timers_cancelled==true)..'}'
 local ok,v=pcall(p.log,'[MineComePerspectiveProbe] '..text);return ok and v~=false
end
local function kill(p)
 local clean=true
 for slot,id in pairs(p.timers) do p.timers[slot]=nil;local ok,v=pcall(p.kill,id);if not ok or v==false then clean=false end end
 p.timers_cancelled=(p.timers_cancelled~=false) and clean
end
local function arm(p,slot,name,ms)
 local data={owner=p,slot=slot};p.data[slot]=data
 local ok,id=pcall(p.timer,ms,name,data,true)
 if not ok or not handle(id) then p.data[slot]=nil;return false end
 p.timers[slot]=id;return true
end
local function consume(data)
 if type(data)~='table' then return nil end local p=data.owner
 if type(p)~='table' or state.active~=p or p.terminal or p.data[data.slot]~=data or not handle(p.timers[data.slot]) then return nil end
 p.timers[data.slot]=nil;return p
end
local function terminal(p,result,s)
 if state.active~=p or p.terminal then return false end
 p.terminal=true;kill(p);state.active=nil;state.last=p
 return emit(p,'terminal',result,s or snapshot())
end
local function restored(p,s)
 return rawequal(s.entity,p.entity) and rawequal(s.id,p.id) and distance(s.position,p.origin)<=.03 and basis(s)
  and distance(s.camera,p.camera_origin)<=.05 and distance(s.forward,p.forward_origin)<=.02 and distance(s.up,p.up_origin)<=.02 and math.abs(s.fov-p.fov_origin)<=.01
end
local function reset(p,reason)
 if p.terminal or state.active~=p then return false end
 p.stop_reason=p.stop_reason or reason
 if not p.write_attempted then return terminal(p,reason,snapshot()) end
 if p.reset_succeeded then return true end
 -- Capture this exact release function before the write. Even a failed/throwing
 -- SetViewCamera can have partially changed the engine, so always release it.
 p.reset_attempts=(p.reset_attempts or 0)+1
 local ok,v=pcall(p.reset)
 if ok and v~=false then
  p.reset_succeeded=true;kill(p)
  if not arm(p,'verify','MineCome_PerspectiveProbeVerify',50) then
   local s=snapshot();p.restored_readback=restored(p,s)
   return terminal(p,p.restored_readback and 'restored_without_delayed_sample' or 'restore_readback_unverified',s)
  end
  return emit(p,'reset',reason,snapshot())
 end
 -- Three prearmed deadlines bound release retries even if later scheduling
 -- fails. Never report successful restoration just because release was called.
 if p.reset_attempts>=3 or (not p.timers.deadline and not p.timers.fallback and not p.timers.final) then return terminal(p,'reset_failed',snapshot()) end
 emit(p,'reset_failed',reason,snapshot());return false
end
function MineCome.BeginPerspectiveProbe(run,mode,offset,duration_ms)
 offset=offset or .25;duration_ms=duration_ms or 300
 if not token(run) then return false,'invalid_run' end
 if mode~='back' and mode~='front' then return false,'invalid_mode' end
 if not finite(offset) or offset<=0 or offset>2.5 or not finite(duration_ms) or duration_ms<100 or duration_ms>1000 or duration_ms~=math.floor(duration_ms) then return false,'invalid_bounds' end
 if state.active then return false,'busy' end
 local movement=MineCome._movement_probe;local gameplay=MineCome._gameplay_movement
 if (movement and (movement.active or movement.follower)) or (gameplay and gameplay.active) then return false,'movement_busy' end
 local p={run=run,mode=mode,distance=offset,duration=duration_ms,timers={},data={},created=clock(),
  log=field(System,'LogAlways'),set=field(CryAction,'SetViewCamera'),reset=field(CryAction,'ResetToNormalCamera'),timer=field(Script,'SetTimerForFunction'),kill=field(Script,'KillTimer')}
 if not p.created or type(p.log)~='function' or type(p.set)~='function' or type(p.reset)~='function' or type(p.timer)~='function' or type(p.kill)~='function' then return false,'api_unavailable' end
 local s=snapshot();local why=safe(s)
 if why then return false,why end
 p.entity,p.id,p.origin=s.entity,s.id,s.position;p.camera_origin,p.forward_origin,p.up_origin,p.fov_origin=s.camera,s.forward,s.up,s.fov
 local unit=scale(s.forward,1/math.sqrt(dot(s.forward,s.forward)));local sign=mode=='back' and -1 or 1
 p.target=copy({x=s.camera.x+unit.x*offset*sign,y=s.camera.y+unit.y*offset*sign,z=s.camera.z+unit.z*offset*sign});p.direction=scale(unit,mode=='front' and -1 or 1)
 if not p.target then return false,'target_out_of_bounds' end
 state.active=p
 if not arm(p,'deadline','MineCome_PerspectiveProbeDeadline',duration_ms) or not arm(p,'fallback','MineCome_PerspectiveProbeDeadline',duration_ms+50) or not arm(p,'final','MineCome_PerspectiveProbeDeadline',duration_ms+100)
  or not arm(p,'apply','MineCome_PerspectiveProbeApply',1) then terminal(p,'timer_failed_before_write',s);return false,'timer_failed_before_write' end
 if not emit(p,'queued','queued',s) then terminal(p,'log_failed_before_write',s);return false,'log_failed_before_write' end
 return true,'queued'
end
function MineCome_PerspectiveProbeApply(data)
 local p=consume(data);if not p then return false end
 local s,t=snapshot(),clock();local why=safe(s,p)
 if not t or t<p.created or (t-p.created)*1000>100 then why='enqueue_expired' end
 if why then return reset(p,why) end
 if field(CryAction,'SetViewCamera')~=p.set or field(CryAction,'ResetToNormalCamera')~=p.reset then return reset(p,'api_changed_before_write') end
 p.write_attempted=true
 -- The shipped use site passes direction as a numeric array, not x/y/z fields.
 local ok,v=pcall(p.set,copy(p.target),{p.direction.x,p.direction.y,p.direction.z})
 if not ok or v==false then return reset(p,'camera_write_failed') end
 if not arm(p,'sample','MineCome_PerspectiveProbeSample',math.min(50,p.duration-1)) then return reset(p,'sample_timer_failed') end
 return emit(p,'applied','awaiting_readback',snapshot()) or reset(p,'log_failed')
end
function MineCome_PerspectiveProbeSample(data)
 local p=consume(data);if not p then return false end
 local s=snapshot();local why=safe(s,p)
 p.camera_readback=not why and distance(s.camera,p.target)<=.05 and distance(s.forward,p.direction)<=.02
 if why or not p.camera_readback then return reset(p,why or 'camera_readback_failed') end
 return emit(p,'sample','camera_readback',s) or reset(p,'log_failed')
end
function MineCome_PerspectiveProbeDeadline(data) local p=consume(data);if not p then return false end;return reset(p,'deadline') end
function MineCome_PerspectiveProbeVerify(data)
 local p=consume(data);if not p then return false end
 local s=snapshot();p.restored_readback=restored(p,s)
 return terminal(p,p.restored_readback and 'restored' or 'restore_readback_failed',s)
end
function MineCome.EndPerspectiveProbe(run)
 if not token(run) then return false,'invalid_run' end
 local p=state.active;if not p or p.run~=run then return false,'wrong_or_inactive_run' end
 reset(p,'explicit_cancel');return true,'cancel_requested'
end
