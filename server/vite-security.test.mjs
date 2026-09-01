import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { rm } from 'node:fs/promises';
import { createServer } from 'node:net';

async function unusedPort() {
  const probe = createServer();
  await new Promise((resolve, reject) => probe.listen(0, '127.0.0.1', resolve).once('error', reject));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  return port;
}

test('development server never publishes SQLite runtime files', async t => {
  const port = await unusedPort();
  const databasePath = `data/vite-security-${process.pid}.sqlite`;
  const child = spawn(process.execPath, ['server/index.mjs'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      HOST: '127.0.0.1',
      PORT: String(port),
      DATABASE_PATH: databasePath,
      NODE_ENV: 'development',
    },
    stdio: 'ignore',
  });

  t.after(async () => {
    if (child.exitCode === null) {
      child.kill('SIGTERM');
      await once(child, 'exit');
    }
    for (const suffix of ['', '-wal', '-shm']) await rm(databasePath + suffix, { force: true });
  });

  let ready = false;
  for (let attempt = 0; attempt < 100 && !ready; attempt += 1) {
    await new Promise(resolve => setTimeout(resolve, 50));
    try {
      ready = (await fetch(`http://127.0.0.1:${port}/api/health`)).ok;
    } catch {}
  }
  assert.equal(ready, true, 'development server did not start');

  const response = await fetch(`http://127.0.0.1:${port}/${databasePath}`);
  const body = new Uint8Array(await response.arrayBuffer());
  assert.equal(response.status, 403);
  assert.notEqual(new TextDecoder().decode(body.slice(0, 15)), 'SQLite format 3');
});
