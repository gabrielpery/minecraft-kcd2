// SPDX-License-Identifier: GPL-3.0-or-later
// Explicit synthetic HTTP engine and Minecraft wire peers; no game is launched.
import {spawn} from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const [exe,workspace]=process.argv.slice(2);
assert.ok(exe&&workspace,'usage: tools_aimed_integration.mjs HOST_EXE WORKSPACE');
const run='0123456789abcdef0123456789abcdef';
const root=fs.mkdtempSync(path.join(workspace,'runtime','tools-aimed-fixture-'));
fs.mkdirSync(path.join(root,'config'));fs.mkdirSync(path.join(root,'runtime','logs'),{recursive:true});
const token='b'.repeat(64);fs.writeFileSync(path.join(root,'config','bridge.token'),token);
const gameLog=path.join(root,'fixture-kcd.log');fs.writeFileSync(gameLog,'Synthetic aimed fixture. No live KCD proof.\n');
const stopFile=path.join(root,'stop.request');
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const log=(marker,value)=>fs.appendFileSync(gameLog,`\r\n${marker} ${JSON.stringify(value)}`);
const commands=[],owned=new Map(),installations=new Map();
let beginCount=0,bootstrapAckSent=false,refusePermitAck=false,session=0;
const started=performance.now();
const clock=()=>Math.fround(100+(performance.now()-started)/1000);
const sessionLog=(event,id,result)=>log('[MineComeBlockSession]',{schema:1,event,session:id,result,owned_count:owned.size,pending_count:0});
const server=http.createServer((request,response)=>{
  const url=new URL(request.url,'http://127.0.0.1');
  if(url.pathname==='/api/System/Console'){response.end('ExecuteString');return;}
  assert.equal(url.pathname,'/api/System/Console/ExecuteString');
  const command=url.searchParams.get('command');commands.push(command);
  if(command==='#MineCome.SamplePose()')log('[MineComePose]',{schema:1,player:{x:100,y:200,z:50.08},camera:{x:100,y:200,z:51.7},forward:{x:1,y:0,z:0},up:{x:0,y:0,z:1},fov_raw:1,calibrated:false});
  const sink=command.match(/^#MineCome\.(BeginBlockSession|HeartbeatBlockSession|EndBlockSession|ApplyStoneEvent)\(([^)]+)\)$/);
  if(sink){
    const values=sink[2].split(',').map(v=>v.startsWith("'")?Number(v.slice(1,-1)):Number(v));
    const [id,sequence,operation,x,y,z,kx,ky,kz]=values;
    if(sink[1]==='BeginBlockSession'){session=id;sessionLog('begin',id,'accepted');}
    if(sink[1]==='HeartbeatBlockSession')sessionLog('heartbeat',id,'alive');
    if(sink[1]==='EndBlockSession'){owned.clear();sessionLog('end',id,'ended');}
    if(sink[1]==='ApplyStoneEvent'){
      assert.deepEqual([x,y,z],[12,64,20]);
      assert.ok(Math.abs(kx-101.5)<1e-8&&Math.abs(ky-200.5)<1e-8&&Math.abs(kz-50.08)<1e-8,'replica must use offered camera alignment, never legacy forward island');
      const receipt={schema:1,event:operation===1?'place':'remove',session:id,sequence,operation,mc:{x,y,z},position:{x:kx,y:ky,z:kz},result:operation===1?'spawned':'removed',bounds_min:operation===1?{x:0,y:-1,z:0}:null,bounds_max:operation===1?{x:1,y:0,z:1}:null,physics:false,live_draw_verified:false};
      if(operation===1)owned.set('seed',id);else owned.delete('seed');
      setTimeout(()=>{if(operation===1)bootstrapAckSent=true;log('[MineComeBlock]',receipt);},250);
    }
  }
  const begin=command.match(/^#MineCome.BeginAimedInput\('([0-9a-f]{32})','([1-9][0-9]*)',60\)$/);
  if(begin){
    assert.ok(bootstrapAckSent,'input session began before replica engine acknowledgement');
    assert.equal(begin[1],run);assert.equal(begin[2],'1');beginCount++;
    const now=clock();log('[MineComeAimSession]',{schema:1,run,arena:'1',event:'begin',result:'accepted',engine_time:now,expires_engine_time:Math.fround(now+60)});
  }
  const permit=command.match(/^#MineCome.InstallAimedPermit\('([0-9a-f]{32})','([1-9][0-9]*)','([1-9][0-9]*)'\)$/);
  if(permit){
    assert.equal(beginCount,1);assert.equal(permit[1],run);assert.equal(permit[2],'1');
    const now=clock();installations.set(permit[3],now);
    if(!refusePermitAck)log('[MineComeAimPermit]',{schema:1,run,arena:'1',permit:permit[3],result:'installed',engine_time:now,expires_engine_time:Math.fround(now+.5)});
  }
  // Deliberately arrive after the independent stone cleanup receipt.
  if(command===`#MineCome.EndAimedInput('${run}','1')`)setTimeout(()=>log('[MineComeAimSession]',{schema:1,run,arena:'1',event:'end',result:'ended',engine_time:clock(),expires_engine_time:null}),350);
  response.end('HTTP dispatch acknowledgement only');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
const args=['--home',root,'--game-log',gameLog,'--stop-file',stopFile,'--fov-unit','radians','--seconds','14','--port',String(port),'--tools-port',String(server.address().port),'--standalone-fixture'];
async function refused(extra,reason){
  const child=spawn(exe,[...args,...extra],{windowsHide:true});let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
  assert.equal(code,1,output);assert.ok(output.includes(reason),output);
}
await refused(['--aimed-stone'],'invalid aimed begin');
await refused(['--aimed-run',run],'requires explicit aimed');
await refused(['--aimed-stone','--aimed-run',run,'--interactive-stone'],'cannot mix');
await refused(['--aimed-stone','--aimed-run',run,'--camera-only'],'cannot mix');
const child=spawn(exe,[...args,'--aimed-stone','--aimed-run',run],{windowsHide:true});
let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
const finished=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',resolve);});
const waitFor=async(test,label,timeout=4000)=>{const end=performance.now()+timeout;while(!test()){if(performance.now()>end)throw new Error(`Timed out: ${label}\n${output}`);await delay(10);}};
function frame(type,seq,payload=Buffer.alloc(0)){
  const header=Buffer.alloc(32);header.write('MCME');header.writeUInt16LE(1,4);header.writeUInt16LE(2,6);header.writeUInt16LE(type,8);header.writeUInt32LE(payload.length,12);header.writeBigUInt64LE(BigInt(seq),16);header.writeBigUInt64LE(1n,24);return Buffer.concat([header,payload]);
}
const arena=Buffer.alloc(100);arena.writeBigUInt64LE(1n);
[10.5,65.62,20.5,100,200,51.7,1].forEach((v,i)=>arena.writeDoubleLE(v,8+8*i));
[12,64,20,10,62,18,14,66,22].forEach((v,i)=>arena.writeInt32LE(v,64+4*i));
let socket,poseTimer,permitTimer,seq=1,permitId=0,arenaAck=false,hostPose=false;
const requests=[];
const send=(type,payload)=>socket.write(frame(type,seq++,payload));
const event=operation=>{const id=Buffer.from('minecraft:stone'),body=Buffer.alloc(18);body.writeUInt32LE(operation);body.writeInt32LE(12,4);body.writeInt32LE(64,8);body.writeInt32LE(20,12);body.writeUInt16LE(id.length,16);send(5,Buffer.concat([body,id]));};
const result=(id,action)=>{const body=Buffer.alloc(24);body.writeBigUInt64LE(1n);body.writeBigUInt64LE(BigInt(id),8);body.writeUInt32LE(action,16);body.writeUInt32LE(1,20);send(13,body);};
function readyPermits(){return [...output.matchAll(/^AIM_PERMIT_READY run=([0-9a-f]{32}) arena=([1-9][0-9]*) permit=([1-9][0-9]*) installed_utc_ms=([1-9][0-9]*)$/gm)].map(m=>({run:m[1],arena:m[2],permit:m[3],utc:Number(m[4])}));}
async function newestPermit(excluded='0'){
  await waitFor(()=>readyPermits().some(p=>BigInt(p.permit)>BigInt(excluded)&&Date.now()-p.utc<100),'fresh acknowledged permit');
  return readyPermits().filter(p=>BigInt(p.permit)>BigInt(excluded)&&Date.now()-p.utc<150).at(-1);
}
function capture(permit,click,action=2,overrides={}){
  const installed=installations.get(permit.permit);assert.notEqual(installed,undefined);
  const value={schema:1,run,arena:'1',request:String(click),permit:permit.permit,click:String(click),action,result:'sampled',reason:'none',permit_engine_time:installed,engine_time:Math.fround(installed+.1),completed_engine_time:Math.fround(installed+.11),origin:{x:100,y:200,z:51.7},direction:{x:1,y:0,z:0},range:4.5,occlusion:1,nearest_distance:0,...overrides};
  log('[MineComeAimInput]',value);return value;
}
try{
  await waitFor(()=>output.includes('Official tools console binding verified'),'adapter startup');
  socket=net.createConnection({host:'127.0.0.1',port});socket.on('error',()=>{});
  let buffered=Buffer.alloc(0);
  socket.on('data',chunk=>{
    buffered=Buffer.concat([buffered,chunk]);
    while(buffered.length>=32){
      const size=buffered.readUInt32LE(12);if(buffered.length<32+size)break;
      const type=buffered.readUInt16LE(8),payload=buffered.subarray(32,32+size);assert.equal(buffered.readUInt16LE(6),2);
      if(type===1)assert.equal(payload.readUInt32LE(4),2);
      if(type===3){assert.equal(payload.readUInt32LE(124),11);hostPose=true;}
      if(type===11){assert.deepEqual(payload,arena);arenaAck=true;}
      if(type===12){assert.equal(size,96);requests.push({arena:payload.readBigUInt64LE(0),id:payload.readBigUInt64LE(8),permit:payload.readBigUInt64LE(16),action:payload.readUInt32LE(24),occlusion:payload.readUInt32LE(28),origin:[0,1,2].map(i=>payload.readDoubleLE(32+8*i))});}
      buffered=buffered.subarray(32+size);
    }
  });
  await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject);});
  const name=Buffer.from('synthetic aimed peer'),hello=Buffer.alloc(12);hello.writeUInt32LE(2);hello.writeUInt32LE(2,4);hello.writeUInt16LE(name.length,8);hello.writeUInt16LE(64,10);send(1,Buffer.concat([hello,name,Buffer.from(token)]));
  const pose=()=>{const body=Buffer.alloc(128);[10.5,64,20.5,10.5,65.62,20.5,0,0,0,1,1,0,0,0,1].forEach((v,i)=>body.writeDoubleLE(v,i*8));body.writeUInt32LE(2,120);body.writeUInt32LE(11,124);send(4,body);};
  pose();poseTimer=setInterval(pose,50);
  await waitFor(()=>hostPose,'fresh host pose');send(10,arena);await waitFor(()=>arenaAck,'byte-identical arena ACK');
  assert.equal(beginCount,0,'no input permits before confirmed bootstrap event');event(1);
  permitTimer=setInterval(()=>{const body=Buffer.alloc(16);body.writeBigUInt64LE(1n);body.writeBigUInt64LE(BigInt(++permitId),8);send(14,body);},100);
  const first=await newestPermit();assert.equal(first.run,run);assert.equal(first.arena,'1');
  assert.ok(output.indexOf('STONE_ENGINE_ACK')<output.indexOf('AIM_INPUT_BEGIN_ACK'));
  log('[MineComeAimSession]',{schema:1,run,arena:'1',event:'end',result:'ended',engine_time:clock(),expires_engine_time:null});
  await delay(70);assert.ok(!output.includes('AIM_INPUT_END_ACK'),'unsolicited end must not become cleanup evidence');
  capture(first,99,2,{result:'unavailable',reason:'ray_unavailable',occlusion:0});
  await waitFor(()=>output.includes('reason=unavailable_or_malformed_sample'),'unavailable sample refused');
  assert.ok(output.includes('"reason":"ray_unavailable"'),'bounded original refusal evidence preserved');
  const firstUsable=await newestPermit(first.permit);
  capture(firstUsable,1);await waitFor(()=>requests.length===1,'physical captured intent dispatch');
  assert.deepEqual(requests[0],{arena:1n,id:1n,permit:BigInt(firstUsable.permit),action:2,occlusion:1,origin:[100,200,51.7]});
  capture(firstUsable,1);await waitFor(()=>output.includes('reason=replayed_intent'),'duplicate click rejected');assert.equal(requests.length,1);
  result(1,2);await waitFor(()=>output.includes('AIM_INPUT_RESULT'),'independent Minecraft result');assert.equal(owned.size,1,'result is not an engine removal');
  event(2);await waitFor(()=>output.includes('result=removed'),'actual block event engine acknowledgement');
  const stale=await newestPermit(first.permit);await delay(550);capture(stale,2);
  await waitFor(()=>output.includes('reason=unknown_or_consumed_permit')||output.includes('reason=stale_or_unready_capture'),'expired original permit rejected');assert.equal(requests.length,1);
  const fresh=await newestPermit(stale.permit);capture(fresh,3,1,{run:'f'.repeat(32)});
  await waitFor(()=>output.includes('reason=wrong_run_or_arena'),'wrong run rejected');
  capture(fresh,3,1);await waitFor(()=>requests.length===2,'fresh permit after stale capture');assert.equal(requests[1].id,3n);assert.equal(requests[1].action,1);assert.equal(requests[1].permit,BigInt(fresh.permit));
  result(3,1);event(1);await waitFor(()=>owned.size===1&&output.includes('AIM_INPUT_RESULT run='+run+' arena=1 request=3'),'second actual block transition');
  refusePermitAck=true;const readyBefore=readyPermits().at(-1).permit;
  await delay(650);assert.equal(readyPermits().at(-1).permit,readyBefore,'HTTP dispatch without Lua ACK must not announce readiness');
  const unacknowledged={permit:String(permitId-1)};
  if(installations.has(unacknowledged.permit)){capture(unacknowledged,4);await delay(150);assert.equal(requests.length,2,'unacknowledged permit cannot dispatch');}
  fs.writeFileSync(stopFile,'Owned synthetic fixture stop');const code=await finished;assert.equal(code,0,output);
  assert.equal(owned.size,0);assert.ok(output.includes('cleanup_ack=true'));assert.ok(commands.includes(`#MineCome.EndAimedInput('${run}','1')`));
  assert.ok(output.includes('AIM_INPUT_END_ACK run='+run+' arena=1'),'late input gate ACK must be read after stone cleanup');
  assert.ok(output.indexOf('STONE_CLEANUP_ACK')<output.indexOf('AIM_INPUT_END_ACK'));
  assert.ok(output.includes('Aimed input cleanup acknowledgement: true'));
  fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify({schema:1,result:'passed',synthetic_engine:true,synthetic_minecraft_peer:true,kcd_connected:false,requests:requests.length,engine_cleanup:true},null,2));
  console.log('TOOLS_AIMED_INTEGRATION_PASS synthetic_engine=true synthetic_minecraft_peer=true requests=2 cleanup=true');
}finally{
  clearInterval(poseTimer);clearInterval(permitTimer);if(socket)socket.destroy();
  if(child.exitCode===null){fs.writeFileSync(stopFile,'Owned fixture cleanup');await Promise.race([finished,delay(3000)]);}
  await new Promise(resolve=>server.close(resolve));
}
