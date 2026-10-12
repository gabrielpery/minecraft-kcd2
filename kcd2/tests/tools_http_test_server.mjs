// SPDX-License-Identifier: GPL-3.0-or-later
// Local test double only. It never launches a game or evaluates console text.
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

if (!process.argv[2]) throw new Error('Supply the installed PowerShell 7 executable');
let observerRequests = 0;
let validBinding = true;
const commands = [];
const observer = http.createServer((request, response) => {
  ++observerRequests;
  response.end('UNEXPECTED proxy/redirect request');
});
await new Promise(resolve => observer.listen(0, '127.0.0.2', resolve));
const observerPort = observer.address().port;
const server = http.createServer((request, response) => {
  const url = new URL(request.url, 'http://127.0.0.1');
  switch (url.pathname) {
    case '/api/test/body': response.end('diagnostic-body'); break;
    case '/api/test/redirect':
      response.writeHead(302, { Location: `http://127.0.0.2:${observerPort}/redirected` });
      response.end('redirect'); break;
    case '/api/test/status-error': response.writeHead(500); response.end('error'); break;
    case '/api/test/oversized-fixed':
      response.writeHead(200, { 'Content-Length': 128 }); response.end('x'.repeat(128)); break;
    case '/api/test/oversized-stream':
      response.write('x'.repeat(10)); response.write('x'.repeat(10)); response.end('x'.repeat(20)); break;
    case '/api/test/slow-body': {
      response.write('x');
      const timer = setInterval(() => response.write('x'), 100);
      response.on('close', () => clearInterval(timer));
      break;
    }
    case '/api/test/missing-binding': validBinding = false; response.end('ok'); break;
    case '/api/test/valid-binding': validBinding = true; response.end('ok'); break;
    case '/api/test/stats': response.end(JSON.stringify({ observer_requests: observerRequests, commands })); break;
    case '/api/System/Console':
      response.end(`<Console><Method name="${validBinding ? 'ExecuteString' : 'NotExecuteString'}"/></Console>`); break;
    case '/api/System/Console/ExecuteString':
      commands.push(url.searchParams.get('command')); response.end('<ok/>'); break;
    default: response.writeHead(404); response.end('missing');
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  const test = spawn(process.argv[2], [
    '-NoProfile', '-File', fileURLToPath(new URL('./tools_http_helpers.ps1', import.meta.url)),
    '-Port', String(server.address().port), '-ObserverPort', String(observerPort)
  ], { stdio: 'inherit', windowsHide: true });
  const code = await new Promise((resolve, reject) => {
    test.on('error', reject);
    test.on('exit', resolve);
  });
  process.exitCode = code ?? 1;
} finally {
  server.closeAllConnections(); observer.closeAllConnections();
  server.close(); observer.close();
}
