//===----------------------------------------------------------------------===//
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//===----------------------------------------------------------------------===//
// Run a generated recommender app against an in-page, manually advanced HTTP
// and WebSocket peer. The test owns no real account or service process.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, relative as relativePath, resolve, sep } from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = resolve(process.argv[2] || 'target/recommender-I09');
const mime = { '.css': 'text/css', '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm' };
const server = createServer(async (request, response) => {
  const fileName = decodeURIComponent(new URL(request.url, 'http://localhost').pathname).replace(/^\/+/, '') || 'app.html';
  if (fileName === 'favicon.ico') { response.writeHead(204).end(); return; }
  const path = resolve(root, fileName);
  const outsideRoot = relativePath(root, path);
  if (outsideRoot === '..' || outsideRoot.startsWith(`..${sep}`)) {
    response.writeHead(404).end(); return;
  }
  try {
    const body = await readFile(path);
    response.writeHead(200, { 'content-type': mime[extname(path)] || 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
const browser = await chromium.launch({ channel: process.env.PLAYWRIGHT_CHANNEL || 'msedge', headless: true });
const epoch = '0123456789abcdef0123456789abcdef';
const token = 'a'.repeat(32);
const profile = (revision) => ({ server_epoch: epoch, account_id: 7, revision: String(revision) });
const event = (type, revision, extra = {}) => ({ v: 1, type, ...profile(revision), ...extra });
const stateBody = JSON.stringify({ v: 1, type: 'state', profile: profile(5), username: 'fixture',
  ratings: [0, 1, 2, 3, 4].map(item_id => ({ item_id, rating: 3 })), model_generation: '1',
  operations: [], next_after_revision: '5', through_revision: '5' });

const page = await browser.newPage();
page.setDefaultTimeout(15000);
try {
  const pageErrors = [];
  page.on('pageerror', error => { pageErrors.push(error.message); console.error(error.stack); });
  page.on('console', message => { if (message.type() === 'error') pageErrors.push(message.text()); });
  await page.addInitScript(() => {
    const nativeFetch = window.fetch.bind(window);
    const peer = { requests: [], sockets: [], sent: [],
      respond(index, status, body) { this.requests[index].resolve(new Response(body, { status, headers: { 'content-type': 'application/json' } })); },
      fail(index, reason = 'fixture network failure') { this.requests[index].reject(new TypeError(reason)); },
      message(text) { this.sockets.at(-1)?.emit('message', text); } };
    window.__pendingPeer = peer;
    window.__holdTimers = false;
    const nativeSetTimeout = window.setTimeout.bind(window);
    window.setTimeout = (fn, ms, ...args) => window.__holdTimers ? 0 : nativeSetTimeout(fn, ms, ...args);
    window.fetch = (input, init = {}) => {
      const url = String(input);
      if (new URL(url, location.href).pathname.endsWith('/app.wasm')) return nativeFetch(input, init);
      return new Promise((resolve, reject) => {
        peer.requests.push({ url, method: init.method || 'GET', body: init.body || '', resolve, reject });
        init.signal?.addEventListener('abort', () => reject(new DOMException('cancelled', 'AbortError')), { once: true });
      });
    };
    class PeerSocket extends EventTarget {
      static CONNECTING = 0;
      static OPEN = 1;
      constructor(url) { super(); this.url = url; this.readyState = 0; this.bufferedAmount = 0; peer.sockets.push(this); queueMicrotask(() => { this.readyState = 1; this.dispatchEvent(new Event('open')); }); }
      send(text) { peer.sent.push(JSON.parse(text)); }
      close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
      emit(kind, text) { const message = new Event(kind); Object.defineProperty(message, 'data', { value: text }); this.dispatchEvent(message); }
    }
    window.WebSocket = PeerSocket;
  });
  await page.goto(`http://127.0.0.1:${address.port}/app.html?api=http%3A%2F%2F127.0.0.1%3A8080`);
  await page.locator('#username').fill('fixture');
  await page.locator('#password').fill('password');
  await page.locator('#login').click();
  await page.getByText('Signing in…').waitFor({ timeout: 5000 }).catch(async error => {
    throw new Error(`${error.message}; page errors=${JSON.stringify(pageErrors)}; body=${await page.locator('body').innerText()}`);
  });
  await page.waitForFunction(() => window.__pendingPeer.requests.some(request => request.url.includes('/v1/login')));
  const loginIndex = await page.evaluate(() => window.__pendingPeer.requests.findIndex(request => request.url.includes('/v1/login')));
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 200, body), { index: loginIndex,
    body: JSON.stringify({ v: 1, type: 'authenticated', token, server_epoch: epoch, account_id: 7, username: 'fixture' }) });

  await page.waitForFunction(() => window.__pendingPeer.requests.some(request => request.url.includes('/v1/state')));
  const stateIndex = await page.evaluate(() => window.__pendingPeer.requests.findIndex(request => request.url.includes('/v1/state')));
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 200, body), { index: stateIndex, body: stateBody });
  await page.waitForFunction(() => window.__pendingPeer.requests.some(request => request.url.endsWith('/movies')));
  const catalogueIndex = await page.evaluate(() => window.__pendingPeer.requests.findIndex(request => request.url.endsWith('/movies')));
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 200, body), { index: catalogueIndex,
    body: JSON.stringify({ movies: Array.from({ length: 1682 }, (_, item_id) => ({ item_id, title: `Movie ${item_id + 1}` })) }) });
  await page.getByText('Live', { exact: true }).waitFor();

  const initial = event('recommendations', 5, { model_generation: '1', job_id: '1', attempt: 1,
    cold_start: false, recommendations: [{ item_id: 40, score: 4.5 }] });
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(initial));
  await page.getByText('Movie 41', { exact: true }).waitFor();

  await page.locator('.movie-list li').filter({ has: page.getByText('Movie 6', { exact: true }) }).getByRole('button').click();
  await page.getByRole('button', { name: '4 stars', exact: true }).click();
  await page.locator('#save-rating').click();
  await page.locator('#ratings').getByText('· saving', { exact: false }).waitFor();
  await page.waitForFunction(() => window.__pendingPeer.sent.length === 1);
  const firstCommand = await page.evaluate(() => window.__pendingPeer.sent[0]);
  assert.equal(firstCommand.item_id, 5);
  assert.equal(firstCommand.rating, 4);
  const recommendations = page.locator('#recommendations').innerText();
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(event('accepted', 6,
    { operation_id: firstCommand.operation_id, item_id: 5, rating: 4 })));
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(event('saved', 6,
    { operation_id: firstCommand.operation_id })));
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(event('saved', 6,
    { operation_id: firstCommand.operation_id })));
  assert.equal(await page.locator('#recommendations').innerText(), await recommendations);
  assert.match(await page.locator('#save-status').innerText(), /saved/i);
  const refreshed = event('recommendations', 6, { model_generation: '1', job_id: '2', attempt: 1,
    cold_start: false, recommendations: [{ item_id: 41, score: 4.4 }] });
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(refreshed));
  await page.getByText('Movie 42', { exact: true }).waitFor();
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(refreshed));
  assert.equal(await page.locator('#recommendations li').count(), 1);

  await page.evaluate(() => { window.__holdTimers = true; window.__pendingPeer.sockets.at(-1).close(); });
  await page.getByText('Reconnecting', { exact: true }).waitFor();
  await page.locator('.movie-list li').filter({ has: page.getByText('Movie 7', { exact: true }) }).getByRole('button').click();
  await page.getByRole('button', { name: '5 stars', exact: true }).click();
  await page.locator('#save-rating').click();
  await page.waitForFunction(() => window.__pendingPeer.requests.some(request => request.url.includes('/v1/ratings')));
  const submitIndex = await page.evaluate(() => window.__pendingPeer.requests.findIndex(request => request.url.includes('/v1/ratings')));
  const fallback = JSON.parse(await page.evaluate(index => window.__pendingPeer.requests[index].body, submitIndex));
  assert.match(fallback.operation_id, new RegExp(`^${epoch}[0-9a-f]{32}$`));
  assert.equal(fallback.server_epoch, epoch);
  const saveEvent = event('accepted', 7, { operation_id: fallback.operation_id, item_id: 6, rating: 5 });
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 202, body), { index: submitIndex, body: JSON.stringify(saveEvent) });
  await page.getByText('accepted', { exact: false }).waitFor();
  await page.evaluate(() => { window.__holdTimers = false; window.dispatchEvent(new CustomEvent('recommender-reconnect')); });
  await page.waitForFunction(() => window.__pendingPeer.sockets.length >= 2);
  await page.getByText('Live', { exact: true }).waitFor();
  const newerRecommendations = event('recommendations', 7, { model_generation: '1', job_id: '3', attempt: 1,
    cold_start: false, recommendations: [{ item_id: 42, score: 4.3 }] });
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(newerRecommendations));
  await page.getByText('Movie 43', { exact: true }).waitFor({ timeout: 5000 }).catch(async error => {
    throw new Error(`${error.message}; status=${await page.locator('#save-status').innerText()}; ratings=${await page.locator('#ratings').innerText()}; errors=${JSON.stringify(pageErrors)}`);
  });
  await page.evaluate(text => window.__pendingPeer.message(text), JSON.stringify(event('saved', 7,
    { operation_id: fallback.operation_id })));
  await page.getByText('Rating saved.', { exact: true }).waitFor();
  assert.equal(await page.locator('#recommendations li').count(), 1);

  await page.evaluate(() => { window.__holdTimers = true; window.__pendingPeer.sockets.at(-1).close(); });
  await page.getByText('Reconnecting', { exact: true }).waitFor();
  const submitCountBeforeFailure = await page.evaluate(() => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/ratings')).length);
  await page.locator('.movie-list li').filter({ has: page.getByText('Movie 8', { exact: true }) }).getByRole('button').click();
  await page.getByRole('button', { name: '2 stars', exact: true }).click();
  await page.locator('#save-rating').click();
  await page.waitForFunction(count => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/ratings')).length > count, submitCountBeforeFailure);
  const failedSubmit = await page.evaluate(() => window.__pendingPeer.requests.map((request, index) => ({ request, index }))
    .filter(entry => entry.request.url.includes('/v1/ratings')).at(-1).index);
  await page.evaluate(index => window.__pendingPeer.fail(index), failedSubmit);
  await page.waitForFunction(() => window.__pendingPeer.requests.some(request => request.url.includes('/v1/operations/status')));
  await page.locator('#check-save-status').waitFor({ state: 'visible' });
  assert.equal(await page.evaluate(() => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/ratings')).length), 2);
  await page.evaluate(() => { window.__holdTimers = false; window.dispatchEvent(new CustomEvent('recommender-reconnect')); });
  await page.waitForFunction(() => window.__pendingPeer.sockets.length >= 3);
  const beforeUnloadPrevented = await page.evaluate(() => {
    const attempt = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(attempt);
    return attempt.defaultPrevented;
  });
  assert.equal(beforeUnloadPrevented, true);

  // A delayed earlier login must not authenticate after a newer login starts.
  await page.locator('#logout').click();
  await page.getByText('Unresolved saves remain.', { exact: false }).waitFor({ timeout: 5000 }).catch(async error => {
    throw new Error(`${error.message}; notice=${await page.locator('#notice').innerText()}; status=${await page.locator('#save-status').innerText()}; ratings=${await page.locator('#ratings').innerText()}; unresolved-action=${await page.locator('#check-save-status').isVisible()}`);
  });
  await page.locator('#logout-confirm').click();
  await page.locator('#login').waitFor({ state: 'visible' });
  await page.locator('#username').fill('old-session');
  await page.locator('#password').fill('password');
  await page.locator('#login').click();
  await page.waitForFunction(() => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/login')).length === 2);
  await page.locator('#username').fill('new-session');
  await page.locator('#login').click();
  await page.waitForFunction(() => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/login')).length === 3);
  const loginIndexes = await page.evaluate(() => window.__pendingPeer.requests.map((request, index) => ({ request, index }))
    .filter(entry => entry.request.url.includes('/v1/login')).map(entry => entry.index));
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 200, body), { index: loginIndexes[1],
    body: JSON.stringify({ v: 1, type: 'authenticated', token, server_epoch: epoch, account_id: 7, username: 'old-session' }) });
  assert.equal(await page.locator('#login').isVisible(), true);
  await page.evaluate(({ index, body }) => window.__pendingPeer.respond(index, 200, body), { index: loginIndexes[2],
    body: JSON.stringify({ v: 1, type: 'authenticated', token, server_epoch: epoch, account_id: 7, username: 'new-session' }) });
  await page.waitForFunction(() => window.__pendingPeer.requests.filter(request => request.url.includes('/v1/state')).length >= 2);
  assert.deepEqual(pageErrors, []);
  console.log('browser pending peer: optimistic paint, event ordering, duplicates, HTTP fallback, failure, cancellation and stale session pass');
} catch (error) {
  console.error(await page.locator('.movie-list li').evaluateAll(rows => rows.map(row => row.__brievItem)));
  console.error(await page.locator("body").innerText());
  console.error(await page.evaluate(async () => { const api = await import("./app.mjs"); return window.__pendingPeer.requests.map((r, i) => ({ url: r.url, status: api.http_async_status(i + 1), body: api.http_async_body(i + 1), error: api.http_async_error(i + 1) })); }));
  throw error;
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
