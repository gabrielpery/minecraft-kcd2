// Native C++ / actual Java codec interoperability and adversarial socket tests.
// The native host and Node probes are explicitly synthetic, not game verification.
import {spawn} from 'node:child_process';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const port=38770;
const tokenFile=path.join(root,'config','bridge.token');
const token=fs.readFileSync(tokenFile,'ascii').trim();
assert.match(token,/^[0-9a-f]{64}$/);
const logfile=path.join(root,'runtime','logs','integration-native.log');
fs.mkdirSync(path.dirname(logfile),{recursive:true});
const delay=ms=>new Promise(r=>setTimeout(r,ms));
const run=(command,args)=>{
  const child=spawn(command,args,{cwd:root,windowsHide:true}); let output='';
  child.stdout.on('data',d=>output+=d);child.stderr.on('data',d=>output+=d);
  const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',code=>resolve({code,output}));});
  return {child,done,get output(){return output;}};
};
function frame(type,seq,body=Buffer.alloc(0)) {
  const h=Buffer.alloc(32);h.write('MCME');h.writeUInt16LE(1,4);h.writeUInt16LE(type,8);h.writeUInt32LE(body.length,12);h.writeBigUInt64LE(BigInt(seq),16);h.writeBigUInt64LE(1n,24);return Buffer.concat([h,body]);
}
function hello(credential=token) {
  const name=Buffer.from('node synthetic probe');const t=Buffer.from(credential);const b=Buffer.alloc(12);
  b.writeUInt32LE(3);b.writeUInt16LE(name.length,8);b.writeUInt16LE(t.length,10);return Buffer.concat([b,name,t]);
}
async function open() {
  const s=net.createConnection({host:'127.0.0.1',port});s.on('error',()=>{});
  await new Promise((resolve,reject)=>{s.once('connect',resolve);s.once('error',reject);});
  let bytes=Buffer.alloc(0),queue=[],waiters=[];
  s.on('data',chunk=>{
    bytes=Buffer.concat([bytes,chunk]);
    while(bytes.length>=32) {const size=bytes.readUInt32LE(12);if(bytes.length<32+size) break;
      const packet={type:bytes.readUInt16LE(8),body:bytes.subarray(32,32+size)};
      bytes=bytes.subarray(32+size);const waiter=waiters.shift();if(waiter)waiter(packet);else queue.push(packet);
    }
  });
  return {socket:s,next:()=>queue.length?Promise.resolve(queue.shift()):new Promise((resolve,reject)=>{
    const timer=setTimeout(()=>{waiters=waiters.filter(w=>w!==callback);reject(new Error('frame timeout'));},3000);
    const callback=p=>{clearTimeout(timer);resolve(p);};waiters.push(callback);
  })};
}
async function closed(s,timeout=3000) {
  if(s.destroyed) return;
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{s.destroy();reject(new Error('peer not rejected in time'));},timeout);s.once('close',()=>{clearTimeout(timer);resolve();});});
}
const host=run(path.join(root,'build','native','Release','minecome_host.exe'),[tokenFile,logfile,'20',String(port)]);
try {
  for(let i=0;i<100&&!host.output.includes('listening');i++) await delay(50);
  assert.ok(host.output.includes('listening'),'host startup');
  let p=await open();p.socket.write(frame(4,1,Buffer.alloc(128)));await closed(p.socket);
  p=await open();p.socket.write(frame(1,1,hello('0'.repeat(64))));await closed(p.socket);
  p=await open();const corrupt=frame(1,1,hello());corrupt[0]=0;p.socket.write(corrupt);await closed(p.socket);
  p=await open();const oversize=frame(1,1);oversize.writeUInt32LE(65537,12);p.socket.write(oversize);await closed(p.socket);
  p=await open();const bytes=frame(1,1,hello());
  for(let i=0;i<bytes.length;i+=3) {p.socket.write(bytes.subarray(i,i+3));await delay(2);}
  assert.equal((await p.next()).type,1,'fragmented HELLO roundtrip');
  p.socket.write(frame(2,1));await closed(p.socket); // sequence replay
  p=await open();p.socket.write(frame(1,1,hello()));assert.equal((await p.next()).type,1);
  await closed(p.socket,8000); // server heartbeat cannot substitute for client liveness
  p=await open();p.socket.write(frame(1,1,hello()));assert.equal((await p.next()).type,1);
  const invalidPose=Buffer.alloc(128);invalidPose.writeDoubleLE(Number.NaN,0);
  p.socket.write(frame(4,2,invalidPose));await closed(p.socket);
  const java=process.env.JAVA_HOME?path.join(process.env.JAVA_HOME,'bin','java.exe'):'java';
  const cli=run(java,[`-Dminecome.port=${port}`,'-cp',path.join(root,'protocol','java','build','classes'),'dev.minecome.protocol.CodecCli',tokenFile,'3']);
  const guest=await cli.done;assert.equal(guest.code,0,guest.output);assert.match(guest.output,/Synthetic harness received host poses: [1-9]/);
  const result=await host.done;assert.equal(result.code,0,result.output);assert.match(result.output,/received_poses=[1-9]/);assert.match(result.output,/received_block_events=1/);
  console.log('PASS: auth/version/framing/fragmentation/sequence/NaN/heartbeat/reconnect plus C++<->Java pose/block interoperability. Synthetic harness only.');
  console.log(guest.output.trim());console.log(result.output.trim());
} catch(error) {
  host.child.kill();console.error(host.output);throw error;
}
