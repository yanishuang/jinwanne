import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { DatabaseSync } from 'node:sqlite';

// Exercise the actual production routes against an isolated temporary database.
test('English public pages and leaderboard are reachable without creating an account', async t => {
  const probe = createServer();
  await new Promise((resolve, reject) => probe.listen(0, '127.0.0.1', resolve).once('error', reject));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const directory = await mkdtemp(join(tmpdir(), 'journal-site-language-'));
  const databasePath = join(directory, 'journal.sqlite');
  const child = spawn(process.execPath, ['server/index.mjs'], {
    cwd: process.cwd(),
    env: { ...process.env, HOST: '127.0.0.1', PORT: String(port), DATABASE_PATH: databasePath, NODE_ENV: 'production' },
    stdio: 'ignore',
  });
  t.after(async () => {
    if (child.exitCode === null) { child.kill('SIGTERM'); await once(child, 'exit'); }
    await rm(directory, { recursive: true, force: true });
  });
  const base = `http://127.0.0.1:${port}`;
  let ready = false;
  for (let attempt = 0; attempt < 100 && !ready; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 50));
    try { ready = (await fetch(base + '/api/health')).ok; } catch {}
  }
  assert.equal(ready, true, 'production server did not start');
  for (const path of ['/en', '/en/', '/en/privacy', '/en/support']) {
    const response = await fetch(base + path);
    assert.equal(response.status, 200, path);
    assert.match(await response.text(), /<html lang="en">/, path);
    assert.equal(response.headers.has('set-cookie'), false, path);
    assert.equal(response.headers.get('cache-control'), 'no-cache', path);
  }
  const english404 = await fetch(base + '/en/missing-page');
  assert.equal(english404.status, 404);
  assert.match(await english404.text(), /<html lang="en">/);
  const script = await fetch(base + '/en/leaderboard.js');
  assert.equal(script.status, 200);
  const source = await script.text();
  assert.match(source, /alias\.textContent = row\.alias/);
  assert.doesNotMatch(source, /innerHTML/);
  const board = await fetch(base + '/api/leaderboard', { headers: { 'X-Journal-Language': 'en' } });
  assert.equal(board.status, 200);
  assert.deepEqual((await board.json()).rows, []);
  const chinese = await fetch(base + '/privacy');
  assert.match(await chinese.text(), /<html lang="zh-CN">/);
  const readOnly = new DatabaseSync(databasePath, { readOnly: true });
  assert.equal(readOnly.prepare('SELECT COUNT(*) AS n FROM users').get().n, 0);
  readOnly.close();
});
