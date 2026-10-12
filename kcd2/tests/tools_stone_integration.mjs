// SPDX-License-Identifier: GPL-3.0-or-later
// Original HTTP/engine and Minecraft protocol fixtures, never a live-game claim.
import {spawn} from 'node:child_process';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
const [exe,workspace]=process.argv.slice(2);
const interactive=process.argv.includes('--interactive');
assert.ok(exe&&workspace,'usage: node tools_stone_integration.mjs HOST_EXE WORKSPACE [--interactive]');
const root=fs.mkdtempSync(path.join(workspace,'runtime','tools-stone-fixture-'));
fs.mkdirSync(path.join(root,'config'));fs.mkdirSync(path.join(root,'runtime','logs'),{recursive:true});
const token='a'.repeat(64);fs.writeFileSync(path.join(root,'config','bridge.token'),token);
const gameLog=path.join(root,'fixture-kcd.log');fs.writeFileSync(gameLog,'Standalone simulated engine; not KCD2.\n');
async function refused(args,reason) {
  const probe=spawn(exe,args,{windowsHide:true});let output='';probe.stdout.on('data',b=>output+=b);probe.stderr.on('data',b=>output+=b);
  const code=await new Promise((resolve,reject)=>{probe.once('error',reject);probe.once('close',resolve);});
  assert.equal(code,1,output);assert.ok(output.includes(reason),output);
}
const common=['--home',root,'--game-log',gameLog,'--fov-unit','radians','--mirror-stone'];
await refused(common,'official development executable');
await refused([...common,'--standalone-fixture'],'separate non-game log and non-default HTTP port');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
// The inspected live engine writes a separator before each record and leaves
// its latest record unterminated. Keep a carried tail on every interactive
// read: reconnect/outage taint must belong to that line, not all later lines.
// The existing legacy fixture retains its original newline-terminated writes.
const log=(marker,value)=>fs.appendFileSync(gameLog,interactive?
  `\r\n${marker} ${JSON.stringify(value)}`:`${marker} ${JSON.stringify(value)}\n`);
const commands=[],owned=new Map(),registered=new Set();let suppressBegin=false,rejectBegin=false,cleanupHold=false,delayedAck=false,deferredRemove=true,completedDeferredRemovals=0,malformedReceipts=0;
let sampleUnavailableUntil=0,unavailableSamples=0;
const sessionLog=(event,session,result)=>log('[MineComeBlockSession]',{schema:1,event,session,result,owned_count:owned.size,pending_count:result==='cleanup_pending'?owned.size:0});
const server=http.createServer((request,response)=>{
  const url=new URL(request.url,'http://127.0.0.1');
  if(url.pathname==='/api/System/Console') {response.end('ExecuteString');return;}
  assert.equal(url.pathname,'/api/System/Console/ExecuteString');
  const command=url.searchParams.get('command');commands.push(command);
  if(command==='#MineCome.SamplePose()'&&Date.now()<sampleUnavailableUntil) {
    ++unavailableSamples;
    setTimeout(()=>{response.statusCode=503;response.end('simulated temporary game HTTP outage');},300);return;
  }
  if(command==='#MineCome.SamplePose()') log('[MineComePose]',{schema:1,player:{x:100,y:200,z:50},camera:{x:100,y:200,z:51.7},forward:{x:0,y:1,z:0},up:{x:0,y:0,z:1},fov_raw:1,calibrated:false});
  const match=command.match(/^#MineCome\.(BeginBlockSession|HeartbeatBlockSession|EndBlockSession|ApplyStoneEvent)\(([^)]+)\)$/);
  if(match) {
    const args=match[2].split(',');
    assert.match(args[0],/^'[1-9][0-9]{0,15}'$/,'session must cross Lua boundary as canonical text');
    if(match[1]==='ApplyStoneEvent') assert.match(args[1],/^'[1-9][0-9]{0,15}'$/,'sequence must cross Lua boundary as canonical text');
    const [session,sequence,operation,x,y,z,kx,ky,kz]=args.map(value=>value.startsWith("'")?Number(value.slice(1,-1)):Math.fround(Number(value)));
    assert.ok(Number.isSafeInteger(session)&&session>0);
    if(match[1]==='BeginBlockSession') {
      if(rejectBegin) sessionLog('begin',session,'rejected_timer');
      else if(!suppressBegin) {registered.add(session);sessionLog('begin',session,'accepted');}
    }
    else if(match[1]==='HeartbeatBlockSession') sessionLog('heartbeat',session,'alive');
    else if(match[1]==='EndBlockSession') {
      if(!registered.has(session)) sessionLog('end',session,'rejected_session');
      else if(cleanupHold&&owned.size) sessionLog('end',session,'cleanup_pending');
      else {owned.clear();sessionLog('end',session,'ended');}
    }
    else {
      const key=`${x},${y},${z}`;
      if(operation===1) {assert.deepEqual([kx,ky,kz],[100.5,203.5,51]);owned.set(key,session);}
      else if(!deferredRemove) owned.delete(key);
      const receipt={schema:1,event:operation===1?'place':'remove',session,sequence,operation,mc:{x,y,z},position:{x:kx,y:ky,z:kz},result:operation===1?'spawned':'removed',bounds_min:operation===1?{x:0,y:-1,z:0}:null,bounds_max:operation===1?{x:1,y:0,z:1}:null,physics:false,live_draw_verified:false};
      if(deferredRemove&&operation===2) {
        deferredRemove=false;
        log('[MineComeBlock]',{...receipt,result:'cleanup_pending'});
        setTimeout(()=>{owned.delete(key);++completedDeferredRemovals;log('[MineComeBlock]',receipt);},600);
      } else if(delayedAck&&operation===1) {
        delayedAck=false;
        ++malformedReceipts;fs.appendFileSync(gameLog,`[MineComeBlock] ${JSON.stringify(receipt).slice(0,-1)}\n`);
        setTimeout(()=>log('[MineComeBlock]',receipt),500);
      } else log('[MineComeBlock]',receipt);
    }
  }
  response.end('dispatch only');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
const stopFile=path.join(root,'stop.request');
const child=spawn(exe,['--home',root,'--game-log',gameLog,'--stop-file',stopFile,'--fov-unit','radians','--seconds','18','--port',String(port),'--tools-port',String(server.address().port),interactive?'--interactive-stone':'--mirror-stone','--standalone-fixture'],{windowsHide:true});
let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
const finished=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',code=>resolve(code));});
const waitFor=async(predicate,label,timeout=4000)=>{const until=Date.now()+timeout;while(!predicate()){if(Date.now()>until)throw new Error(`Timed out: ${label}\n${output}`);await delay(25);}};
function frame(type,sequence,body=Buffer.alloc(0),minor=0) {
  const h=Buffer.alloc(32);h.write('MCME');h.writeUInt16LE(1,4);h.writeUInt16LE(minor,6);h.writeUInt16LE(type,8);h.writeUInt32LE(body.length,12);h.writeBigUInt64LE(BigInt(sequence),16);h.writeBigUInt64LE(1n,24);return Buffer.concat([h,body]);
}
async function peer(role=2,minor=0) {
  const socket=net.createConnection({host:'127.0.0.1',port});socket.on('error',()=>{});
  let received=Buffer.alloc(0);const inputs=[],frames=[];
  socket.on('data',chunk=>{
    received=Buffer.concat([received,chunk]);
    while(received.length>=32) {
      assert.equal(received.subarray(0,4).toString(),'MCME');
      const size=received.readUInt32LE(12);assert.ok(size<=65536);
      if(received.length<32+size)break;
      const type=received.readUInt16LE(8),messageMinor=received.readUInt16LE(6),body=received.subarray(32,32+size);
      frames.push({type,minor:messageMinor});
      assert.equal(messageMinor,minor,'host must preserve negotiated minor');
      if(type===1)assert.equal(body.readUInt32LE(4),minor===1?1:0,'host must confirm negotiated capability');
      if(type===8) {
        assert.equal(minor,1);assert.equal(size,12);
        inputs.push({id:body.readBigUInt64LE(0),action:body.readUInt32LE(8)});
      }
      received=received.subarray(32+size);
    }
  });
  await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject);});
  let sequence=1;const send=(type,body)=>socket.write(frame(type,sequence++,body,minor));
  const name=Buffer.from('standalone simulated peer'),credential=Buffer.from(token),hello=Buffer.alloc(12);
  hello.writeUInt32LE(role);hello.writeUInt32LE(minor===1?1:0,4);hello.writeUInt16LE(name.length,8);hello.writeUInt16LE(credential.length,10);send(1,Buffer.concat([hello,name,credential]));
  let flags=11;
  const pose=()=>{
    const body=Buffer.alloc(128),values=[10.5,64,20.5,10.5,65.7,20.5,0,0,0,1,1,0,0,0,1];
    values.forEach((v,i)=>body.writeDoubleLE(v,i*8));body.writeUInt32LE(2,120);body.writeUInt32LE(flags,124);send(4,body);
  };
  pose();const timer=setInterval(pose,100);
  return {inputs,frames,invalid(){flags=0;pose();},valid(){flags=11;pose();},result(id,action,result=1){const body=Buffer.alloc(16);body.writeBigUInt64LE(BigInt(id));body.writeUInt32LE(action,8);body.writeUInt32LE(result,12);send(9,body);},event(operation){const id=Buffer.from('minecraft:stone'),body=Buffer.alloc(18);body.writeUInt32LE(operation);body.writeInt32LE(11,4);body.writeInt32LE(65,8);body.writeInt32LE(21,12);body.writeUInt16LE(id.length,16);send(5,Buffer.concat([body,id]));},close(){clearInterval(timer);socket.destroy();}};
}
const count=name=>commands.filter(c=>c.startsWith(`#MineCome.${name}(`)).length;
let active;
try {
  await waitFor(()=>output.includes('Official tools console binding verified'),'host startup');
  if(interactive) {
    const intent=(id,action)=>log('[MineComeInput]',{schema:1,request:id,action});
    active=await peer();await delay(500);intent(1,1);
    await waitFor(()=>output.includes('STONE_INPUT_REJECTED reason=no_ready_world_or_input_peer request=1'),'legacy peer input capability guard');
    assert.equal(active.inputs.length,0,'minor0 peer must never receive input extension');active.close();
    active=await peer(2,1);await delay(500);intent(2,1);
    await waitFor(()=>active.inputs.length===1,'minor1 log intent becomes wire request');
    assert.deepEqual(active.inputs[0],{id:2n,action:1});
    active.result(2,2);await delay(150);
    assert.ok(!output.includes('STONE_INPUT_RESULT request=2'),'wrong-action result cannot acknowledge an inflight request');
    active.result(2,1);active.event(1);
    await waitFor(()=>output.includes('STONE_INPUT_RESULT request=2 action=1 result=1'),'matching wire result');
    await waitFor(()=>output.includes('result=spawned'),'resulting simulated Minecraft block event spawns display');
    intent(3,2);await waitFor(()=>active.inputs.length===2,'break intent becomes wire request');
    assert.deepEqual(active.inputs[1],{id:3n,action:2});active.result(3,2);active.event(2);
    await waitFor(()=>output.includes('STONE_INPUT_RESULT request=3 action=2 result=1'),'matching break result');
    await waitFor(()=>output.includes('result=removed'),'deferred resulting remove event acknowledged');
    intent(2,1);await waitFor(()=>output.includes('STONE_INPUT_REJECTED reason=replayed_intent request=2'),'replayed log intent rejected');
    assert.equal(active.inputs.length,2);
    sampleUnavailableUntil=Date.now()+1800;
    await waitFor(()=>unavailableSamples>0,'simulated temporary HTTP failure begins');
    intent(4,1);await delay(2400);
    assert.ok(output.includes('Official HTTP temporarily unavailable'),'fixture exercised the real native outage branch');
    assert.ok(!active.inputs.some(input=>input.id===4n),'intent accumulated during HTTP outage must not be replayed after recovery');
    intent(5,1);await waitFor(()=>active.inputs.some(input=>input.id===5n),'fresh post-recovery input accepted');
    active.result(5,1);
    await waitFor(()=>output.includes('STONE_INPUT_RESULT request=5 action=1 result=1'),'post-recovery matching result');
    active.invalid();await delay(300);intent(6,1);await delay(400);
    assert.ok(!active.inputs.some(input=>input.id===6n),'invalid Minecraft world must reject remote action');
    active.valid();await delay(400);intent(7,1);
    await waitFor(()=>active.inputs.some(input=>input.id===7n),'fresh valid-world intent after reset');
    active.result(7,1);active.event(1);
    await waitFor(()=>owned.size===1&&count('ApplyStoneEvent')>=3,'active simulated entity before graceful stop');
    fs.writeFileSync(stopFile,'Owning interactive fixture requests graceful shutdown while display entity is active.');
    const code=await finished;assert.equal(code,0,output);assert.equal(owned.size,0);assert.match(output,/cleanup_ack=true/);
    fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify({kind:'standalone-original-http-and-engine-fixtures',interactive:true,live_game_verified:false,passed:true,checks:['engine-style prefix CRLF with persistent unterminated tail','fresh input after stale reconnect partial line','minor0 input rejection','minor1 capability negotiation','log intent to exact input wire request','wrong-action result ignored','matching input result','resulting simulated block display events','log input replay rejection','HTTP outage input backlog rejection','invalid-world input guard','graceful stop with active entity cleanup'],output},null,2));
    console.log('PASS: interactive original native forwarding + simulated HTTP/engine/MC peer; no live-game proof.');
    console.log(`Evidence: ${root}`);
  } else {
  active=await peer(3);await delay(400);active.event(1);await delay(500);assert.equal(count('BeginBlockSession'),0,'harness cannot write engine');active.close();
  active=await peer();await delay(500);delayedAck=true;active.event(1);active.event(2);
  await waitFor(()=>count('ApplyStoneEvent')===1,'first real-role event dispatch');
  await delay(200);assert.equal(count('ApplyStoneEvent'),1,'truncated receipt does not release queued removal');
  await waitFor(()=>output.includes('STONE_REMOVAL_PENDING'),'deferred engine deletion receipt');
  assert.equal(count('EndBlockSession'),0,'pending removal keeps the session alive');
  assert.equal(owned.size,1,'entity remains owned until engine deletion completes');
  assert.ok(!output.includes('result=removed'),'pending deletion cannot count as removed');
  active.event(1);await delay(200);assert.equal(count('ApplyStoneEvent'),2,'pending deletion blocks the next placement');
  await waitFor(()=>output.includes('result=removed'),'complete remove engine acknowledgement');assert.equal(completedDeferredRemovals,1);assert.equal(malformedReceipts,1);
  await waitFor(()=>count('ApplyStoneEvent')===3,'second stone placement after deletion');
  active.invalid();await waitFor(()=>count('EndBlockSession')>=1,'world validity cleanup');await waitFor(()=>output.includes('STONE_CLEANUP_ACK'),'cleanup engine acknowledgement');assert.equal(owned.size,0);active.close();
  delayedAck=false;active=await peer();await delay(500);active.event(1);await waitFor(()=>count('BeginBlockSession')>=2&&count('ApplyStoneEvent')>=4,'fresh reconnect session');
  const sessions=commands.filter(c=>c.startsWith('#MineCome.BeginBlockSession')).map(c=>Number(c.match(/\('([0-9]+)'\)/)[1]));assert.ok(sessions[1]>sessions[0],'restart-safe monotonic session ID');
  cleanupHold=true;active.close();await waitFor(()=>count('EndBlockSession')>=2,'disconnect cleanup dispatch');
  active=await peer();await delay(500);active.event(1);await delay(500);
  assert.equal(count('BeginBlockSession'),2,'pending cleanup prevents reset acknowledgement and new session');
  cleanupHold=false;owned.clear();sessionLog('cleanup',sessions[1],'ended');
  await waitFor(()=>count('BeginBlockSession')>=3&&count('ApplyStoneEvent')>=5,'pending cleanup recovery');
  active.close();await waitFor(()=>owned.size===0,'cleanup before rejected begin');
  rejectBegin=true;active=await peer();await delay(500);active.event(1);
  await waitFor(()=>output.includes('Lua rejected session begin'),'explicit begin rejection');
  const rejectedSession=commands.filter(c=>c.startsWith('#MineCome.BeginBlockSession')).at(-1).match(/\('([0-9]+)'\)/)[1];
  await waitFor(()=>commands.includes(`#MineCome.EndBlockSession('${rejectedSession}')`),'end unregistered session');
  await delay(300);rejectBegin=false;active.event(1);
  await waitFor(()=>count('BeginBlockSession')>=5&&count('ApplyStoneEvent')>=6,'end rejected_session proves absent and permits recovery');
  active.close();await waitFor(()=>owned.size===0,'cleanup before missing acknowledgement');
  suppressBegin=true;active=await peer();await delay(500);const applied=count('ApplyStoneEvent');active.event(1);
  await waitFor(()=>output.includes('no engine acknowledgement for session begin'),'HTTP 200 cannot establish sink readiness',3500);
  assert.equal(count('ApplyStoneEvent'),applied);active.close();
  fs.writeFileSync(stopFile,'Owning fixture requests graceful shutdown after verified cleanup.');
  const code=await finished;assert.equal(code,0,output);assert.equal(owned.size,0);assert.match(output,/cleanup_ack=true/);
  fs.writeFileSync(path.join(root,'verification.json'),JSON.stringify({kind:'standalone-original-http-and-engine-fixtures',live_game_verified:false,passed:true,checks:['harness rejection','proper mapped origin','real-role add/remove ordering','complete receipt requirement','engine acknowledgement serialization','deferred deletion blocks placement until final receipt','invalid-world cleanup','reconnect session','disconnect cleanup','begin acknowledgement timeout'],output},null,2));
  console.log('PASS: original native tools host + simulated HTTP/engine/MC peers; no live-game proof.');
  console.log(`Evidence: ${root}`);
  }
} catch(error) {child.kill();throw error;}
finally {active?.close();server.close();}
