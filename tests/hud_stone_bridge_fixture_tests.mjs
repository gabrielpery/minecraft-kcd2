// The peer below is intentionally synthetic: these checks validate the test harness only.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import {randomBytes} from 'node:crypto';
import {encodeFrame, FrameReader, parseHello, syntheticPose, validatePose, parseBlockEvent, parseResult,
  validateStep, StepTracker, runFixture, readPendingStep} from './hud_stone_bridge_fixture.mjs';

let checks = 0;
const check = (value, message) => { assert.ok(value, message); checks++; };
const equal = (actual, expected, message) => { assert.deepEqual(actual, expected, message); checks++; };
const rejects = (callback, pattern, message) => { assert.throws(callback, pattern, message); checks++; };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const run = 'a'.repeat(32), token = 'b'.repeat(64);
const step = (n, action, expected) => ({schema: 1, run, step: n, action, expected_result: expected});
function hello(credential = token) {
  const name = Buffer.from('synthetic test guest'), body = Buffer.alloc(12 + name.length + credential.length);
  body.writeUInt32LE(2); body.writeUInt32LE(1, 4); body.writeUInt16LE(name.length, 8); body.writeUInt16LE(credential.length, 10);
  name.copy(body, 12); body.write(credential, 12 + name.length); return body;
}
function event(operation = 1, x = 2, y = 60, z = 3, id = 'minecraft:stone') {
  const body = Buffer.alloc(18 + id.length);
  body.writeUInt32LE(operation); body.writeInt32LE(x, 4); body.writeInt32LE(y, 8); body.writeInt32LE(z, 12); body.writeUInt16LE(id.length, 16); body.write(id, 18); return body;
}
function result(id = 1n, action = 1, code = 1) {
  const body = Buffer.alloc(16); body.writeBigUInt64LE(id); body.writeUInt32LE(action, 8); body.writeUInt32LE(code, 12); return body;
}

const wire = Buffer.concat([encodeFrame(1, 1n, hello()), encodeFrame(2, 2n), encodeFrame(9, 3n, result())]);
for (const size of [1, 2, 3, 7, 31, 32, 33, 65, 256, wire.length]) {
  const reader = new FrameReader(), frames = [];
  for (let offset = 0; offset < wire.length; offset += size) reader.push(wire.subarray(offset, offset + size), frame => frames.push(frame));
  equal(frames.map(frame => [frame.type, frame.sequence]), [[1, 1n], [2, 2n], [9, 3n]], `fragment size ${size}`);
  equal(reader.pendingBytes, 0, 'fragments fully consumed');
}
for (const [offset, value] of [[0, 0], [4, 2], [6, 0], [8, 0], [8, 10], [10, 1]]) {
  const bad = encodeFrame(1, 1n, hello()); bad[offset] = value;
  rejects(() => new FrameReader().push(bad, () => {}), /Invalid protocol/, 'malformed header rejected');
}
const oversized = encodeFrame(1, 1n); oversized.writeUInt32LE(65537, 12);
rejects(() => new FrameReader().push(oversized, () => {}), /Invalid protocol/, 'oversized declared payload rejected before allocation');
for (const sequence of [0n, 1n]) {
  const reader = new FrameReader(); reader.push(encodeFrame(2, 1n), () => {});
  const bad = encodeFrame(2, 2n); bad.writeBigUInt64LE(sequence, 16);
  rejects(() => reader.push(bad, () => {}), /sequence/, 'zero/replayed sequence rejected');
}
rejects(() => new FrameReader().push(Buffer.alloc(1024 * 1024 + 1), () => {}), /oversized/, 'oversized socket chunk rejected');
equal(parseHello(hello(), token).role, 2, 'valid exact MC identity');
rejects(() => parseHello(hello('c'.repeat(64)), token), /authentication/, 'wrong credential rejected');
for (const offset of [0, 4, 8, 10]) {
  const bad = hello(); bad.writeUInt16LE(0, offset);
  rejects(() => parseHello(bad, token), /hello/, 'invalid hello role/caps/length rejected');
}
const invalidUtf = hello(); invalidUtf[12] = 0xff;
rejects(() => parseHello(invalidUtf, token), /encoded data/, 'invalid UTF-8 hello rejected');
validatePose(syntheticPose(), 1); checks++;
rejects(() => validatePose(syntheticPose()), /metadata/, 'MC cannot send host-space pose');
for (const offset of [0, 48, 80, 112]) {
  const bad = syntheticPose(); bad.writeDoubleLE(NaN, offset);
  rejects(() => validatePose(bad, 1), /metadata/, 'non-finite pose rejected');
}
const invalidFlags = syntheticPose(); invalidFlags.writeUInt32LE(16, 124);
rejects(() => validatePose(invalidFlags, 1), /metadata/, 'unknown pose flags rejected');
equal(parseBlockEvent(event()), {operation: 1, x: 2, y: 60, z: 3, block_id: 'minecraft:stone'}, 'stone cell parsed');
rejects(() => parseBlockEvent(event(3)), /event/, 'invalid block operation');
rejects(() => parseBlockEvent(event(1, 2, 60, 3, 'minecraft:dirt')), /identifier/, 'unrelated block rejected');
rejects(() => parseBlockEvent(event().subarray(0, 19)), /event/, 'truncated block string');
equal(parseResult(result()), {request_id: 1, action: 1, result: 1}, 'result parsed');
for (const bad of [result(0n), result(9007199254740992n), result(1n, 3), result(1n, 1, 0), result(1n, 1, 8), Buffer.alloc(15)])
  rejects(() => parseResult(bad), /result/, 'invalid result rejected');
equal(validateStep(step(1, 1, 1), run, 1), step(1, 1, 1), 'fresh identity accepted');
for (const bad of [{...step(1, 1, 1), run: 'c'.repeat(32)}, {...step(1, 1, 1), extra: true}, step(2, 2, 1), step(1, 2, 1), step(1, 1, 2), null])
  rejects(() => validateStep(bad, run, 1), /run-bound/, 'wrong run/scenario rejected');
const accepted = new StepTracker(step(1, 1, 1), 1000, null);
check(!accepted.ready(1000), 'no result/event is not ready');
accepted.acceptEvent(parseBlockEvent(event())); check(!accepted.ready(1010), 'event alone is not ready');
accepted.acceptResult(parseResult(result()), 1020); check(accepted.ready(1020), 'accepted result plus actual event is ready');
rejects(() => accepted.acceptResult(parseResult(result()), 1030), /duplicate/, 'duplicate result rejected');
rejects(() => accepted.acceptEvent(parseBlockEvent(event())), /duplicate/, 'duplicate event rejected');
const rejected = new StepTracker(step(3, 1, 2), 1000, [2, 60, 3]);
rejected.acceptResult(parseResult(result(3n, 1, 2)), 1100);
check(!rejected.ready(1299), 'unavailable requires full quiet window');
check(rejected.ready(1300), 'unavailable accepted only after 200ms without events');
rejects(() => rejected.acceptEvent(parseBlockEvent(event())), /Unexpected/, 'unavailable never accepts block event');
const broken = new StepTracker(step(2, 2, 1), 1000, [2, 60, 3]);
rejects(() => broken.acceptEvent(parseBlockEvent(event(2, 4))), /fixed target/, 'fixed cell mismatch rejected');
rejects(() => broken.acceptResult(parseResult(result(1n, 2, 1)), 1001), /Unexpected/, 'wrong request ID rejected');
rejects(() => broken.ready(4001), /deadline/, 'accepted request deadline bounded');

// Exercise file publication, authentication, fragmented sockets, six steps and orderly shutdown.
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'minecome-stone-peer-tests-'));
let client, fixtureTask;
const originalOpen = fs.openSync;
let busyReads = 0;
try {
  // Inject the exact transient Windows failure on the real fixture's pending step
  // path. No other file reads are affected and the ordinary deadline is retained.
  fs.openSync = function(file, ...args) {
    if (file === path.join(temp, 'stone-step-2.json') && args[0] === (fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0)) && busyReads < 3) {
      busyReads++; throw Object.assign(new Error('Injected writer sharing collision'), {code: 'EBUSY'});
    }
    return originalOpen.call(fs, file, ...args);
  };
  const expires = Date.now() + 15000;
  const fixture = runFixture(temp, run, String(expires)); fixtureTask = fixture;
  let fixtureFailure; fixture.catch(error => { fixtureFailure = error; });
  async function waitFor(name) {
    const deadline = Date.now() + 5000;
    while (!fs.existsSync(path.join(temp, name))) {
      if (fixtureFailure) throw fixtureFailure;
      if (Date.now() > deadline) throw new Error(`test receipt timeout: ${name}`);
      await delay(10);
    }
    return JSON.parse(fs.readFileSync(path.join(temp, name), 'utf8'));
  }
  const ready = await waitFor('stone-peer-ready.json');
  equal(ready.peer_kind, 'standalone_protocol_fixture', 'ready names synthetic peer');
  equal(ready.run, run, 'ready is run-bound');
  const generated = fs.readFileSync(path.join(temp, 'stone-bridge.token'), 'ascii').trim();
  check(/^[0-9a-f]{64}$/.test(generated) && generated !== token, 'fresh random credential written');
  fs.writeFileSync(path.join(temp, 'client.log'), '[test-only synthetic marker] HUD_STONE_READY\n', {flag: 'wx'});
  client = net.createConnection({host: '127.0.0.1', port: ready.port});
  let tx = 1n, hostPoses = 0, requests = 0, hostError;
  const hostReader = new FrameReader();
  client.on('error', error => { hostError = error; });
  client.on('data', data => {
    try {
      hostReader.push(data, frame => {
        if (frame.type === 1) {
          equal(frame.body.readUInt32LE(0), 1, 'host role');
          equal(frame.body.readUInt32LE(4), 1, 'host capability');
          equal(frame.body.readUInt16LE(10), 0, 'host sends no credential');
          const pose = syntheticPose(); pose.writeUInt32LE(2, 120); client.write(encodeFrame(4, tx++, pose));
        } else if (frame.type === 3) { validatePose(frame.body, 1); hostPoses++; }
        else if (frame.type === 8) {
          const id = frame.body.readBigUInt64LE(), action = frame.body.readUInt32LE(8);
          equal(Number(id), ++requests, 'request ID sequence');
          const code = [3, 4].includes(Number(id)) ? 2 : 1;
          const frames = [];
          if (code === 1) frames.push(encodeFrame(5, tx++, event(action)));
          frames.push(encodeFrame(9, tx++, result(id, action, code)));
          client.write(Buffer.concat(frames));
        } else throw new Error('Unexpected host message in synthetic fixture test');
      });
    } catch (error) { hostError = error; client.destroy(); }
  });
  await new Promise((resolve, reject) => { client.once('connect', resolve); client.once('error', reject); });
  const authenticated = encodeFrame(1, tx++, hello(generated));
  for (let i = 0; i < authenticated.length; i += 3) client.write(authenticated.subarray(i, i + 3));
  for (let n = 1; n <= 6; n++) {
    const action = [2, 6].includes(n) ? 2 : 1, code = [3, 4].includes(n) ? 2 : 1;
    fs.writeFileSync(path.join(temp, `stone-step-${n}.json`), JSON.stringify(step(n, action, code)), {flag: 'wx'});
    const receipt = await waitFor(`stone-result-${n}.json`);
    equal(Object.keys(receipt).sort(), ['action', 'block_event_operation', 'peer_kind', 'request_id', 'result', 'run', 'schema', 'step'], 'native step receipt has exact eight fields');
    equal([receipt.run, receipt.request_id, receipt.result, receipt.block_event_operation], [run, n, code, code === 1 ? action : 0], 'run-bound result receipt');
    if (hostError) throw hostError;
  }
  client.end(encodeFrame(7, tx++));
  const summary = await fixture;
  equal(busyReads, 3, 'pending step sharing collisions retried before the same six-step run completes');
  equal(summary.steps, 6, 'all steps finished'); equal(summary.block_events, 4, 'exactly four actual block event packets');
  check(summary.received_poses > 0 && hostPoses > 0, 'bidirectional validated poses');
  const receipt = await waitFor('stone-peer-result.json');
  equal(receipt.result, 'passed', 'final receipt pass');
  check(receipt.auth_verified && receipt.orderly_goodbye && receipt.guest_socket_closed, 'authentication and orderly close proof');
  check(receipt.synthetic_host_pose && !receipt.kcd_compositing_verified && !receipt.physical_input_verified, 'receipt does not overclaim game/input evidence');
  equal(receipt.fixed_cell, [2, 60, 3], 'same target throughout');
} finally {
  fs.openSync = originalOpen;
  client?.destroy();
  if (!fs.existsSync(path.join(temp, 'stone-peer-result.json'))) fs.writeFileSync(path.join(temp, 'stone-peer-stop.request'), 'test cleanup');
  await fixtureTask?.catch(() => {});
  const resolved = path.resolve(temp), parent = path.resolve(os.tmpdir());
  if (path.dirname(resolved) !== parent || !path.basename(resolved).startsWith('minecome-stone-peer-tests-')) throw new Error('Unsafe temporary cleanup path');
  fs.rmSync(resolved, {recursive: true, force: true});
}

async function failureCase(name, act, expected, lifetime = 5000) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'minecome-stone-peer-tests-'));
  let connection;
  const task = runFixture(directory, run, String(Date.now() + lifetime)).then(() => null, error => error);
  try {
    const readyFile = path.join(directory, 'stone-peer-ready.json');
    for (let i = 0; i < 200 && !fs.existsSync(readyFile); i++) await delay(10);
    const ready = JSON.parse(fs.readFileSync(readyFile, 'utf8'));
    const credential = fs.readFileSync(path.join(directory, 'stone-bridge.token'), 'ascii').trim();
    if (act) {
      connection = net.createConnection({host: '127.0.0.1', port: ready.port});
      connection.on('error', () => {});
      await new Promise((resolve, reject) => { connection.once('connect', resolve); connection.once('error', reject); });
      await act({directory, connection, credential});
    }
    const failure = await task;
    check(failure instanceof Error && expected.test(failure.message), `${name}: expected failure`);
    const receipt = JSON.parse(fs.readFileSync(path.join(directory, 'stone-peer-result.json'), 'utf8'));
    equal(receipt.result, 'failed', `${name}: final failed receipt`);
    check(!JSON.stringify(receipt).includes(credential), `${name}: credential is absent from receipt`);
    check(!fs.existsSync(path.join(directory, 'stone-result-1.json')), `${name}: no success step publication`);
  } finally {
    connection?.destroy();
    if (!fs.existsSync(path.join(directory, 'stone-peer-result.json'))) fs.writeFileSync(path.join(directory, 'stone-peer-stop.request'), 'test cleanup');
    await task;
    const resolved = path.resolve(directory);
    if (path.dirname(resolved) !== path.resolve(os.tmpdir()) || !path.basename(resolved).startsWith('minecome-stone-peer-tests-')) throw new Error('Unsafe temporary cleanup path');
    fs.rmSync(resolved, {recursive: true, force: true});
  }
}
// A busy pending step is retryable; malformed content, non-sharing errors and
// consumed-step mutation remain fatal rather than being treated as not ready.
for (const code of ['EACCES', 'EPERM', 'EIO']) {
  fs.openSync = () => { throw Object.assign(new Error(`Injected ${code}`), {code}); };
  const file = new URL('../minecraft/gradle.properties', import.meta.url);
  try { rejects(() => readPendingStep(file), new RegExp(code), 'non-sharing read error remains fatal'); }
  finally { fs.openSync = originalOpen; }
}
await failureCase('bad authentication', ({connection}) => connection.write(encodeFrame(1, 1n, hello(token))), /authentication/);
await failureCase('changed run identity', ({directory, connection, credential}) => {
  fs.writeFileSync(path.join(directory, 'client.log'), 'HUD_STONE_READY');
  fs.writeFileSync(path.join(directory, 'stone-step-1.json'), JSON.stringify({...step(1, 1, 1), run: 'c'.repeat(32)}));
  connection.write(encodeFrame(1, 1n, hello(credential)));
}, /run-bound/);
await failureCase('malformed step JSON', ({directory, connection, credential}) => {
  fs.writeFileSync(path.join(directory, 'client.log'), 'HUD_STONE_READY');
  fs.writeFileSync(path.join(directory, 'stone-step-1.json'), '{');
  connection.write(encodeFrame(1, 1n, hello(credential)));
}, /Malformed/);
await failureCase('oversized step', ({directory, connection, credential}) => {
  fs.writeFileSync(path.join(directory, 'client.log'), 'HUD_STONE_READY');
  fs.writeFileSync(path.join(directory, 'stone-step-1.json'), ' '.repeat(4097));
  connection.write(encodeFrame(1, 1n, hello(credential)));
}, /bounded/);
try {
  fs.openSync = function(file, ...args) {
    if (typeof file === 'string' && file.endsWith('stone-step-1.json') && args[0] === (fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0)))
      throw Object.assign(new Error('Injected persistent sharing collision'), {code: 'EBUSY'});
    return originalOpen.call(fs, file, ...args);
  };
  await failureCase('busy step hard expiry', ({directory, connection, credential}) => {
    fs.writeFileSync(path.join(directory, 'client.log'), 'HUD_STONE_READY');
    fs.writeFileSync(path.join(directory, 'stone-step-1.json'), JSON.stringify(step(1, 1, 1)));
    connection.write(encodeFrame(1, 1n, hello(credential)));
  }, /hard expiry/, 300);
} finally { fs.openSync = originalOpen; }
await failureCase('stop request', ({directory}) => fs.writeFileSync(path.join(directory, 'stone-peer-stop.request'), ''), /stop requested/);
await failureCase('hard expiry', null, /hard expiry/, 200);
console.log(`PASS: ${checks} stone protocol fixture checks (synthetic harness only; no KCD or physical input claim).`);
