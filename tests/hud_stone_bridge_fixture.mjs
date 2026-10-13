// A synthetic, loopback-only protocol host for the actual Minecraft HUD/stone lab.
// This proves vanilla guest behaviour; it cannot prove KCD rendering or physical input.
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import {randomBytes, timingSafeEqual, createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const MAX_PAYLOAD = 65536;
const MAX_JSON = 4096;
const MAX_LOG_TAIL = 65536;
const PEER_KIND = 'standalone_protocol_fixture';
const TYPES = {HELLO: 1, HEARTBEAT: 2, KCD_POSE: 3, MC_POSE: 4, BLOCK_EVENT: 5, ERROR: 6, GOODBYE: 7, REQUEST: 8, RESULT: 9};
const EXPECTED = [[1, 1], [2, 1], [1, 2], [1, 2], [1, 1], [2, 1]];
const utf8 = new TextDecoder('utf-8', {fatal: true});
const fail = message => { throw new Error(message); };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function encodeFrame(type, sequence, body = Buffer.alloc(0)) {
  if (!Number.isInteger(type) || type < 1 || type > 9 || typeof sequence !== 'bigint' || sequence < 1n ||
      sequence > 0xffffffffffffffffn || !Buffer.isBuffer(body) || body.length > MAX_PAYLOAD) fail('Invalid outgoing frame');
  const header = Buffer.alloc(32);
  header.write('MCME'); header.writeUInt16LE(1, 4); header.writeUInt16LE(1, 6);
  header.writeUInt16LE(type, 8); header.writeUInt32LE(body.length, 12);
  header.writeBigUInt64LE(sequence, 16); header.writeBigUInt64LE(BigInt(Date.now()) * 1000n, 24);
  return Buffer.concat([header, body]);
}

export class FrameReader {
  #buffer = Buffer.alloc(0);
  #lastSequence = 0n;
  push(chunk, consume) {
    if (!Buffer.isBuffer(chunk) || chunk.length > 1024 * 1024) fail('Invalid or oversized transport chunk');
    // Consume a bounded frame at a time, even when TCP coalesces many valid frames.
    let offset = 0;
    while (offset < chunk.length) {
      const headerNeeded = Math.max(0, 32 - this.#buffer.length);
      const wanted = headerNeeded || (32 + this.#buffer.readUInt32LE(12) - this.#buffer.length);
      const take = Math.min(wanted, chunk.length - offset);
      this.#buffer = Buffer.concat([this.#buffer, chunk.subarray(offset, offset + take)]);
      offset += take;
      if (this.#buffer.length < 32) continue;
      const h = this.#buffer;
      if (h.toString('ascii', 0, 4) !== 'MCME' || h.readUInt16LE(4) !== 1 || h.readUInt16LE(6) !== 1 ||
          h.readUInt16LE(8) < 1 || h.readUInt16LE(8) > 9 || h.readUInt16LE(10) !== 0 || h.readUInt32LE(12) > MAX_PAYLOAD)
        fail('Invalid protocol 1.1 header');
      const length = 32 + h.readUInt32LE(12);
      if (h.length < length) continue;
      const sequence = h.readBigUInt64LE(16);
      if (sequence <= this.#lastSequence) fail('Replayed or out-of-order frame sequence');
      this.#lastSequence = sequence;
      const packet = {type: h.readUInt16LE(8), sequence, body: h.subarray(32)};
      this.#buffer = Buffer.alloc(0);
      consume(packet);
    }
  }
  get pendingBytes() { return this.#buffer.length; }
}

export function parseHello(body, credential) {
  if (body.length < 12) fail('Truncated guest hello');
  const nameLength = body.readUInt16LE(8), tokenLength = body.readUInt16LE(10);
  if (body.readUInt32LE(0) !== 2 || body.readUInt32LE(4) !== 1 || nameLength < 1 || nameLength > 128 ||
      tokenLength !== 64 || body.length !== 12 + nameLength + tokenLength) fail('Invalid guest hello identity/capabilities');
  const name = utf8.decode(body.subarray(12, 12 + nameLength));
  const supplied = body.subarray(12 + nameLength);
  if (!/^[0-9a-f]{64}$/.test(credential) || !timingSafeEqual(supplied, Buffer.from(credential, 'ascii'))) fail('Guest authentication failed');
  return {name, role: 2, capabilities: 1};
}

function hostHello() {
  const name = Buffer.from('MineCome standalone stone protocol fixture');
  const body = Buffer.alloc(12 + name.length);
  body.writeUInt32LE(1); body.writeUInt32LE(1, 4); body.writeUInt16LE(name.length, 8); name.copy(body, 12);
  return body;
}

export function syntheticPose() {
  const body = Buffer.alloc(128);
  [1, 2, 3, 1, 2, 4.8, 0, 0, 0, 1, 1.2, 0, 0, 0, 1].forEach((value, index) => body.writeDoubleLE(value, index * 8));
  body.writeUInt32LE(1, 120); body.writeUInt32LE(11, 124); // KCD space; player/camera/in-world, deliberately uncalibrated.
  return body;
}

export function validatePose(body, expectedSpace = 2) {
  if (body.length !== 128) fail('Invalid pose size');
  const values = Array.from({length: 15}, (_, i) => body.readDoubleLE(i * 8));
  if (values.some(value => !Number.isFinite(value)) || Math.abs(values.slice(6, 10).reduce((sum, v) => sum + v * v, 0) - 1) > 0.001 ||
      values[10] <= 0 || values[10] >= Math.PI || values[14] <= 0 || body.readUInt32LE(120) !== expectedSpace ||
      (body.readUInt32LE(124) & ~15) !== 0) fail('Invalid pose metadata');
}

export function parseBlockEvent(body) {
  if (body.length < 18) fail('Truncated block event');
  const operation = body.readUInt32LE(0), length = body.readUInt16LE(16);
  if (![1, 2].includes(operation) || length < 1 || length > 1024 || body.length !== 18 + length) fail('Invalid block event');
  const blockId = utf8.decode(body.subarray(18));
  if (blockId !== 'minecraft:stone') fail('Unexpected block registry identifier');
  return {operation, x: body.readInt32LE(4), y: body.readInt32LE(8), z: body.readInt32LE(12), block_id: blockId};
}

export function parseResult(body) {
  if (body.length !== 16) fail('Invalid stone result size');
  const id = body.readBigUInt64LE(0), action = body.readUInt32LE(8), result = body.readUInt32LE(12);
  if (id < 1n || id > 9007199254740991n || ![1, 2].includes(action) || result < 1 || result > 7) fail('Invalid stone result fields');
  return {request_id: Number(id), action, result};
}

export function validateStep(document, run, step) {
  if (!document || Array.isArray(document) || typeof document !== 'object' ||
      Object.keys(document).sort().join(',') !== 'action,expected_result,run,schema,step' ||
      document.schema !== 1 || document.run !== run || !Number.isInteger(step) || step < 1 || step > 6 ||
      document.step !== step || document.action !== EXPECTED[step - 1][0] || document.expected_result !== EXPECTED[step - 1][1])
    fail('Invalid run-bound stone step');
  return document;
}

export class StepTracker {
  constructor(step, startedAt, fixedCell) {
    this.step = step; this.startedAt = startedAt; this.fixedCell = fixedCell; this.result = null; this.event = null;
  }
  acceptResult(result, now) {
    if (this.result || result.request_id !== this.step.step || result.action !== this.step.action || result.result !== this.step.expected_result)
      fail('Unexpected or duplicate stone result');
    this.result = result; this.resultAt = now;
  }
  acceptEvent(event) {
    if (this.event || this.step.expected_result !== 1 || event.operation !== this.step.action) fail('Unexpected or duplicate stone block event');
    const cell = [event.x, event.y, event.z];
    if (this.fixedCell && cell.some((value, i) => value !== this.fixedCell[i])) fail('Stone block events changed fixed target cell');
    this.fixedCell = cell; this.event = event;
  }
  ready(now) {
    if (now - this.startedAt > 3000) fail('Stone request result/event deadline expired');
    return this.result !== null && (this.step.expected_result === 1 ? this.event !== null : now - this.resultAt >= 200);
  }
}

function checkedFile(file, maximum, optional = false) {
  let before;
  try { before = fs.lstatSync(file); } catch (error) { if (optional && error.code === 'ENOENT') return null; throw error; }
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1 || before.size > maximum) fail('Evidence file must be bounded, regular and unlinked');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
  try {
    const opened = fs.fstatSync(fd);
    if (opened.ino !== before.ino || opened.dev !== before.dev || opened.nlink !== 1 || opened.size !== before.size) fail('Evidence file identity changed');
    const data = Buffer.alloc(opened.size);
    if (fs.readSync(fd, data, 0, data.length, 0) !== data.length) fail('Evidence file read was incomplete');
    const after = fs.fstatSync(fd);
    if (after.size !== opened.size || after.mtimeMs !== opened.mtimeMs || after.ctimeMs !== opened.ctimeMs) fail('Evidence file changed during read');
    return {data, digest: hash(data)};
  } finally { fs.closeSync(fd); }
}

function logReady(directory) {
  const file = path.join(directory, 'client.log');
  let info;
  try { info = fs.lstatSync(file); } catch (error) { if (error.code === 'ENOENT') return false; throw error; }
  if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 64 * 1024 * 1024) fail('Invalid client evidence log');
  const fd = fs.openSync(file, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
  try {
    const opened = fs.fstatSync(fd);
    if (opened.ino !== info.ino || opened.dev !== info.dev || opened.nlink !== 1) fail('Client log identity changed');
    const bytes = Buffer.alloc(Math.min(MAX_LOG_TAIL, opened.size));
    const count = fs.readSync(fd, bytes, 0, bytes.length, Math.max(0, opened.size - bytes.length));
    // PowerShell may write either UTF-8 or UTF-16LE depending on the caller's shell.
    return bytes.subarray(0, count).toString('utf8').includes('HUD_STONE_READY') || bytes.subarray(0, count).toString('utf16le').includes('HUD_STONE_READY');
  } finally { fs.closeSync(fd); }
}

function publish(file, value) {
  const temporary = `${file}.${randomBytes(8).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + '\n', {flag: 'wx', mode: 0o600});
    // Same-directory rename exposes only a complete JSON document in this fresh run.
    if (fs.existsSync(file)) fail('Refusing to replace an existing fixture receipt');
    fs.renameSync(temporary, file);
  } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
}

export async function runFixture(directoryArgument, run, expiresArgument) {
  const started = Date.now(), expires = Number(expiresArgument);
  if (!directoryArgument || !/^[0-9a-f]{32}$/.test(run || '') || !Number.isSafeInteger(expires) || expires <= started || expires - started > 180000)
    fail('Usage: hud_stone_bridge_fixture.mjs EVIDENCE_DIRECTORY RUN32HEX EXPIRES_UTC_MS (maximum 180 seconds)');
  const directory = path.resolve(directoryArgument);
  if (!fs.lstatSync(directory).isDirectory() || fs.lstatSync(directory).isSymbolicLink() || fs.realpathSync(directory).toLowerCase() !== directory.toLowerCase())
    fail('Evidence directory must be an existing real directory');
  const file = name => path.join(directory, name);
  for (const name of ['stone-bridge.token', 'stone-peer-ready.json', 'stone-peer-result.json', 'stone-peer-stop.request',
    ...Array.from({length: 6}, (_, i) => `stone-step-${i + 1}.json`), ...Array.from({length: 6}, (_, i) => `stone-result-${i + 1}.json`)])
    if (fs.existsSync(file(name))) fail('Stone fixture requires fresh run evidence');
  const credential = randomBytes(32).toString('hex');
  fs.writeFileSync(file('stone-bridge.token'), credential + '\n', {flag: 'wx', mode: 0o600});
  let socket = null, failure = null, authenticated = false, authVerified = false, closed = false, goodbye = false, ready = false;
  let sequence = 1n, active = null, fixedCell = null, completed = 0, blockEvents = 0, receivedPoses = 0, receivedFrames = 0, receivedBytes = 0;
  let connectionAt = 0, lastRx = 0, lastPose = 0, sessions = 0;
  const immutableSteps = new Map(), stepReceipts = [];
  const setFailure = error => { if (!failure) failure = error instanceof Error ? error : new Error('Stone fixture failed'); };
  const send = (type, body) => {
    if (!socket || socket.destroyed || !socket.writable) fail('Guest socket is unavailable');
    if (socket.writableLength > 128 * 1024) fail('Guest socket write backlog exceeded');
    socket.write(encodeFrame(type, sequence++, body), error => { if (error) setFailure(new Error('Guest socket write failed')); });
  };
  const receive = packet => {
    if (++receivedFrames > 10000) fail('Guest frame count exceeded fixture bound');
    lastRx = Date.now();
    if (!authenticated) {
      if (packet.type !== TYPES.HELLO) fail('Guest did not send hello first');
      parseHello(packet.body, credential); authenticated = true; authVerified = true;
      send(TYPES.HELLO, hostHello()); send(TYPES.KCD_POSE, syntheticPose()); lastPose = Date.now(); return;
    }
    if (goodbye) fail('Guest sent a frame after goodbye');
    switch (packet.type) {
      case TYPES.MC_POSE: validatePose(packet.body); receivedPoses++; break;
      case TYPES.HEARTBEAT: if (packet.body.length !== 0) fail('Heartbeat payload must be empty'); break;
      case TYPES.BLOCK_EVENT:
        if (!active) fail('Unsolicited stone block event');
        active.acceptEvent(parseBlockEvent(packet.body)); blockEvents++; break;
      case TYPES.RESULT:
        if (!active) fail('Unsolicited stone input result');
        active.acceptResult(parseResult(packet.body), Date.now()); break;
      case TYPES.GOODBYE:
        if (packet.body.length !== 0 || completed !== 6 || active) fail('Premature or invalid guest goodbye');
        goodbye = true; socket.end(); break;
      default: fail('Unexpected guest protocol message');
    }
  };
  const server = net.createServer(incoming => {
    try {
      if ((socket && !socket.destroyed) || completed !== 0 || active || ++sessions > 8) { incoming.destroy(); fail('Unexpected guest connection'); }
      if (incoming.remoteAddress !== '127.0.0.1') { incoming.destroy(); fail('Non-loopback guest rejected'); }
      const connectionReader = new FrameReader();
      socket = incoming; authenticated = false; closed = false; sequence = 1n; connectionAt = Date.now(); lastRx = connectionAt;
      incoming.setNoDelay(true);
      incoming.on('data', chunk => {
        try {
          receivedBytes += chunk.length;
          if (receivedBytes > 8 * 1024 * 1024) fail('Guest byte count exceeded fixture bound');
          if (incoming !== socket) fail('Obsolete guest connection sent data');
          connectionReader.push(chunk, receive);
        } catch (error) { setFailure(error); incoming.destroy(); }
      });
      incoming.on('error', () => { if (incoming === socket) setFailure(new Error('Guest socket error')); });
      incoming.on('close', () => {
        try {
          if (incoming !== socket) return;
          closed = true;
          if (connectionReader.pendingBytes !== 0) fail('Guest closed a truncated protocol frame');
          if (completed !== 6 && (completed !== 0 || active)) fail('Guest disconnected before six steps completed');
          authenticated = false;
        } catch (error) { setFailure(error); }
      });
    } catch (error) { incoming.destroy(); setFailure(error); }
  });
  server.on('error', () => setFailure(new Error('Loopback fixture server error')));
  const signal = () => setFailure(new Error('Stone fixture interrupted'));
  process.once('SIGINT', signal); process.once('SIGTERM', signal);
  let outcome;
  try {
    await new Promise((resolve, reject) => {
      const onError = () => reject(new Error('Could not listen on loopback'));
      server.once('error', onError);
      server.listen({host: '127.0.0.1', port: 0, exclusive: true}, () => { server.off('error', onError); resolve(); });
    });
    publish(file('stone-peer-ready.json'), {schema: 1, run, pid: process.pid, port: server.address().port, expires_utc_ms: expires, peer_kind: PEER_KIND});
    while (true) {
      if (failure) throw failure;
      const now = Date.now();
      if (now >= expires) fail('Stone fixture hard expiry reached');
      if (checkedFile(file('stone-peer-stop.request'), MAX_JSON, true)) fail('Stone fixture stop requested');
      for (const [name, digest] of immutableSteps) if (checkedFile(file(name), MAX_JSON).digest !== digest) fail('Consumed step file was modified');
      if (socket && !socket.destroyed && !authenticated && now - connectionAt > 6000) fail('Guest hello deadline expired');
      if (authenticated && !goodbye && now - lastRx > 6000) fail('Guest protocol liveness deadline expired');
      if (authenticated && !goodbye && now - lastPose >= 100) { send(TYPES.KCD_POSE, syntheticPose()); lastPose = now; }
      if (!ready && authenticated) ready = logReady(directory);
      if (active && active.ready(now)) {
        fixedCell = active.fixedCell;
        const receipt = {schema: 1, run, step: active.step.step, request_id: active.step.step, action: active.step.action,
          result: active.result.result, block_event_operation: active.event?.operation || 0, peer_kind: PEER_KIND};
        publish(file(`stone-result-${active.step.step}.json`), receipt);
        stepReceipts.push({...receipt, ...(active.event ? {block_event: active.event} : {})}); completed++; active = null;
      }
      if (ready && authenticated && !active && completed < 6) {
        const name = `stone-step-${completed + 1}.json`, next = checkedFile(file(name), MAX_JSON, true);
        if (next) {
          let document;
          try { document = JSON.parse(utf8.decode(next.data)); } catch { fail('Malformed stone step JSON'); }
          const step = validateStep(document, run, completed + 1);
          immutableSteps.set(name, next.digest); active = new StepTracker(step, now, fixedCell);
          const body = Buffer.alloc(12); body.writeBigUInt64LE(BigInt(step.step)); body.writeUInt32LE(step.action, 8);
          send(TYPES.REQUEST, body);
        }
      }
      if (completed === 6 && closed) {
        if (blockEvents !== 4 || receivedPoses === 0 || !authVerified) fail('Incomplete guest protocol evidence');
        outcome = 'passed'; break;
      }
      await delay(20);
    }
  } catch (error) { setFailure(error); outcome = 'failed'; }
  finally {
    socket?.destroy();
    if (server.listening) await new Promise(resolve => server.close(resolve));
    process.removeListener('SIGINT', signal); process.removeListener('SIGTERM', signal);
    publish(file('stone-peer-result.json'), {schema: 1, run, result: failure ? 'failed' : (outcome || 'failed'), steps: completed, block_events: blockEvents,
      received_poses: receivedPoses, auth_verified: authVerified, peer_kind: PEER_KIND, synthetic_host_pose: true,
      kcd_compositing_verified: false, physical_input_verified: false, orderly_goodbye: goodbye, guest_socket_closed: closed,
      fixed_cell: fixedCell, step_results: stepReceipts, expires_utc_ms: expires, finished_utc_ms: Date.now(),
      ...(failure ? {failure: failure.message} : {})});
  }
  if (failure) throw failure;
  return {steps: completed, block_events: blockEvents, received_poses: receivedPoses};
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await runFixture(...process.argv.slice(2));
    console.log(`STONE_PEER_PASS steps=${result.steps} block_events=${result.block_events} received_poses=${result.received_poses} synthetic_host_pose=true`);
  } catch (error) {
    // Never include payloads, the credential, or arbitrary received hello/log strings in output.
    console.error(`STONE_PEER_FAIL ${error.message}`); process.exitCode = 1;
  }
}
