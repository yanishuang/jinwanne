import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { DatabaseSync } from 'node:sqlite';
import { openDatabase } from './database.mjs';
import { createApp } from './app.mjs';
import { todayInShanghai, validDay, periodStart } from './dates.mjs';

const fixedNow = () => new Date('2026-08-31T15:50:00Z');
async function setup(t, options = {}) {
  const db = openDatabase(options.path);
  const app = createApp({ db, now: fixedNow, limit: false, ...options });
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const stop = async () => { await new Promise(resolve => server.close(resolve)); db.close(); };
  if (!options.manualClose) t.after(stop);
  const request = async (path, { cookie, method = 'GET', body, rawBody, headers = {} } = {}) => {
    const response = await fetch(base + '/api' + path, { method, headers: { 'Content-Type': 'application/json', 'X-Journal-Request': '1', ...(cookie ? { Cookie: cookie } : {}), ...headers }, ...(rawBody !== undefined ? { body: rawBody } : body === undefined ? {} : { body: JSON.stringify(body) }) });
    return { status: response.status, data: await response.json(), headers: response.headers };
  };
  const newUser = async () => {
    const response = await request('/session', { method: 'POST', body: {} });
    assert.equal(response.status, 200);
    return { cookie: response.headers.get('set-cookie').split(';')[0], profile: response.data.profile };
  };
  const put = (cookie, date, outcome, note = '') => request('/records/' + date, { cookie, method: 'PUT', body: { outcome, note } });
  return { db, request, newUser, put, stop };
}

test('anonymous sessions use private cookies, hashed credentials, and opt out by default', async t => {
  const { request, db } = await setup(t);
  const response = await request('/session', { method: 'POST', body: {} });
  assert.equal(response.data.profile.participating, false);
  assert.equal(response.data.today, '2026-08-31');
  assert.equal(response.data.timezone, 'Asia/Shanghai');
  assert.match(response.headers.get('set-cookie'), /HttpOnly/);
  assert.match(response.headers.get('set-cookie'), /SameSite=Strict/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  const cookie = response.headers.get('set-cookie').split(';')[0];
  const token = cookie.split('=')[1];
  assert.notEqual(db.prepare('SELECT token_hash FROM users').get().token_hash, token);
  const again = await request('/session', { method: 'POST', cookie, body: {} });
  assert.deepEqual(again.data.profile, response.data.profile);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
});

test('same-day saves are idempotent, edits move counts, and concurrent writes count once', async t => {
  const { request, newUser, put } = await setup(t);
  const { cookie } = await newUser();
  await put(cookie, '2026-08-20', 'declined', '仅自己可见');
  await Promise.all(Array.from({ length: 8 }, () => put(cookie, '2026-08-20', 'declined')));
  let result = await request('/records?month=2026-08', { cookie });
  assert.deepEqual(result.data.stats, { success: 0, declined: 1, total: 1 });
  await put(cookie, '2026-08-20', 'success', '修改后的备注');
  result = await request('/records?month=2026-08', { cookie });
  assert.deepEqual(result.data.stats, { success: 1, declined: 0, total: 1 });
  assert.equal(result.data.records[0].note, '修改后的备注');
  await request('/records/2026-08-20', { method: 'DELETE', cookie, body: {} });
  result = await request('/records?month=2026-08', { cookie });
  assert.deepEqual(result.data.stats, { success: 0, declined: 0, total: 0 });
});

test('identity isolation applies to reads, edits, deletes, exports, and public ranking payloads', async t => {
  const { request, newUser, put } = await setup(t);
  const alice = await newUser(); const bob = await newUser();
  await put(alice.cookie, '2026-08-20', 'success', 'Alice private note');
  assert.equal((await request('/records?month=2026-08', { cookie: bob.cookie })).data.records.length, 0);
  await put(bob.cookie, '2026-08-20', 'declined', 'Bob private note');
  await request('/records/2026-08-20', { method: 'DELETE', cookie: bob.cookie, body: {} });
  assert.equal((await request('/export', { cookie: alice.cookie })).data.records[0].note, 'Alice private note');
  assert.equal((await request('/export', { cookie: bob.cookie })).data.records.length, 0);
  await request('/profile', { method: 'PATCH', cookie: alice.cookie, body: { participating: true } });
  const ranks = await request('/leaderboard', { cookie: bob.cookie });
  assert.deepEqual(Object.keys(ranks.data.rows[0]).sort(), ['alias', 'days', 'isMe', 'rank']);
  assert.equal(ranks.data.rows[0].isMe, false);
  assert.equal(ranks.data.mine, null);
  assert.ok(!JSON.stringify(ranks.data).includes('private note'));
});

test('invalid and future dates, malformed inputs and unknown filters are rejected', async t => {
  const { request, newUser, put } = await setup(t);
  const { cookie } = await newUser();
  for (const date of ['2026-09-01', '2026-02-30', '2025-02-29', '2026-8-01', '1999-12-31']) assert.equal((await put(cookie, date, 'success')).status, 400, date);
  assert.equal((await put(cookie, '2024-02-29', 'success')).status, 200);
  assert.equal((await put(cookie, '2026-08-31', 'pending')).status, 400);
  assert.equal((await put(cookie, '2026-08-31', 'success', 'x'.repeat(301))).status, 400);
  assert.equal((await put(cookie, '2026-08-31', 'success', {})).status, 400);
  assert.equal((await request('/records?month=2026-13', { cookie })).status, 400);
  assert.equal((await request('/leaderboard?metric=note', { cookie })).status, 400);
  assert.equal((await request('/leaderboard?period=week', { cookie })).status, 400);
  assert.equal((await request('/profile', { method: 'PATCH', cookie, body: { participating: 'true' } })).status, 400);
});

test('rankings aggregate real server rows, respect periods, ties and immediate withdrawal', async t => {
  const { request, newUser, put } = await setup(t);
  const alice = await newUser(); const bob = await newUser(); const charlie = await newUser();
  for (const user of [alice, bob, charlie]) await request('/profile', { method: 'PATCH', cookie: user.cookie, body: { participating: true } });
  for (const user of [alice, bob]) for (const date of ['2026-08-01', '2026-08-02']) await put(user.cookie, date, 'success');
  await put(charlie.cookie, '2026-08-03', 'success');
  await put(alice.cookie, '2026-07-31', 'success');
  await put(alice.cookie, '2025-12-31', 'success');
  await put(bob.cookie, '2026-08-03', 'declined');
  const month = await request('/leaderboard?metric=success&period=month', { cookie: alice.cookie });
  assert.deepEqual(month.data.rows.map(row => [row.rank, row.days]), [[1, 2], [1, 2], [3, 1]]);
  assert.equal(month.data.mine.days, 2);
  assert.equal((await request('/leaderboard?period=year', { cookie: alice.cookie })).data.mine.days, 3);
  assert.equal((await request('/leaderboard?period=all', { cookie: alice.cookie })).data.mine.days, 4);
  const declined = await request('/leaderboard?metric=declined', { cookie: bob.cookie });
  assert.equal(declined.data.total, 1); assert.equal(declined.data.mine.days, 1);
  await request('/profile', { method: 'PATCH', cookie: alice.cookie, body: { participating: false } });
  const after = await request('/leaderboard', { cookie: alice.cookie });
  assert.equal(after.data.total, 2); assert.equal(after.data.mine, null);
  assert.ok(after.data.rows.every(row => row.alias !== alice.profile.alias));
  assert.equal((await request('/export', { cookie: alice.cookie })).data.records.length, 4);
});

test('zero entries never enter rankings and participants are private before opting in', async t => {
  const { request, newUser, put } = await setup(t);
  const { cookie } = await newUser();
  await put(cookie, '2026-08-01', 'success');
  assert.equal((await request('/leaderboard', { cookie })).data.rows.length, 0);
  await request('/profile', { method: 'PATCH', cookie, body: { participating: true } });
  assert.equal((await request('/leaderboard?metric=declined', { cookie })).data.rows.length, 0);
});

test('public leaderboard is read-only and does not create an identity', async t => {
  const { request, newUser, put, db } = await setup(t);
  const user = await newUser();
  await put(user.cookie, '2026-08-01', 'success');
  await request('/profile', { method: 'PATCH', cookie: user.cookie, body: { participating: true } });
  const before = db.prepare('SELECT COUNT(*) AS n FROM users').get().n;
  const ranking = await request('/leaderboard?metric=success&period=month');
  assert.equal(ranking.status, 200);
  assert.equal(ranking.data.rows.length, 1);
  assert.equal(ranking.data.rows[0].isMe, false);
  assert.equal(ranking.data.mine, null);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, before);
});

test('custom usernames are normalized, unique and shown on rankings', async t => {
  const { request, newUser, put, db } = await setup(t);
  const alice = await newUser();
  const bob = await newUser();

  const renamed = await request('/profile', { method: 'PATCH', cookie: alice.cookie, body: { alias: '  Tonight_7  ' } });
  assert.equal(renamed.status, 200);
  assert.equal(renamed.data.profile.alias, 'Tonight_7');
  assert.equal(db.prepare('SELECT alias_key FROM users WHERE alias = ?').get('Tonight_7').alias_key, 'tonight_7');

  const duplicate = await request('/profile', { method: 'PATCH', cookie: bob.cookie, body: { alias: 'ＴＯＮＩＧＨＴ＿７' } });
  assert.equal(duplicate.status, 409);
  assert.match(duplicate.data.error, /已经有人使用/);
  for (const alias of ['A', '名字🙂', '<script>', '这是一个超过十六个字符长度限制的用户名']) {
    assert.equal((await request('/profile', { method: 'PATCH', cookie: bob.cookie, body: { alias } })).status, 400, alias);
  }

  const generated = await request('/profile', { method: 'PATCH', cookie: bob.cookie, body: { alias: '' } });
  assert.equal(generated.status, 200);
  assert.ok(generated.data.profile.alias.length >= 2);
  assert.notEqual(generated.data.profile.alias.toLowerCase(), 'tonight_7');

  await put(alice.cookie, '2026-08-02', 'success');
  await request('/profile', { method: 'PATCH', cookie: alice.cookie, body: { participating: true } });
  const ranking = await request('/leaderboard?metric=success&period=month');
  assert.equal(ranking.data.rows[0].alias, 'Tonight_7');
});

test('authentication and CSRF boundaries fail closed', async t => {
  const { request, newUser } = await setup(t, { appOrigin: 'https://journal.example' });
  const { cookie } = await newUser();
  for (const path of ['/records', '/export']) assert.equal((await request(path)).status, 401);
  assert.equal((await request('/leaderboard')).status, 200);
  assert.equal((await request('/session', { method: 'POST', body: {}, headers: { 'X-Journal-Request': '' } })).status, 403);
  assert.equal((await request('/profile', { cookie, method: 'PATCH', body: { participating: true }, headers: { Origin: 'https://evil.example' } })).status, 403);
  assert.equal((await request('/profile', { cookie, method: 'PATCH', body: { participating: true }, headers: { Origin: 'https://journal.example', 'Sec-Fetch-Site': 'cross-site' } })).status, 403);
  assert.equal((await request('/profile', { cookie, method: 'PATCH', body: { participating: true }, headers: { Origin: 'https://journal.example' } })).status, 200);
  assert.equal((await request('/session', { method: 'POST', body: {}, headers: { 'Content-Type': 'text/plain' } })).status, 415);
});

test('permanent deletion cascades records, removes rank, revokes token and preserves others', async t => {
  const { request, newUser, put, db } = await setup(t);
  const alice = await newUser(); const bob = await newUser();
  await put(alice.cookie, '2026-08-01', 'success'); await put(bob.cookie, '2026-08-02', 'declined');
  await request('/profile', { cookie: alice.cookie, method: 'PATCH', body: { participating: true } });
  assert.equal((await request('/account', { cookie: alice.cookie, method: 'DELETE', body: {} })).status, 400);
  const deleted = await request('/account', { cookie: alice.cookie, method: 'DELETE', body: { confirmation: '删除' } });
  assert.equal(deleted.status, 200); assert.match(deleted.headers.get('set-cookie'), /Expires=Thu, 01 Jan 1970/);
  assert.equal((await request('/export', { cookie: alice.cookie })).status, 401);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM records').get().n, 1);
  assert.equal((await request('/leaderboard', { cookie: bob.cookie })).data.total, 0);
  assert.equal((await request('/export', { cookie: bob.cookie })).data.records.length, 1);
});

test('records and anonymous identity survive server restart', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'journal-persistence-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'journal.sqlite');
  const first = await setup(t, { path, manualClose: true });
  const { cookie } = await first.newUser();
  await first.put(cookie, '2026-08-31', 'declined', 'persisted');
  await first.stop();
  const second = await setup(t, { path });
  const records = await second.request('/records', { cookie });
  assert.equal(records.status, 200); assert.equal(records.data.records[0].note, 'persisted');
});

test('legacy databases gain normalized unique username keys without losing users', t => {
  const dir = mkdtempSync(join(tmpdir(), 'journal-alias-migration-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'journal.sqlite');
  const legacy = new DatabaseSync(path);
  legacy.exec(`CREATE TABLE users (
    id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, alias TEXT NOT NULL UNIQUE,
    participating INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, session_expires_at INTEGER NOT NULL
  )`);
  legacy.prepare('INSERT INTO users VALUES (?, ?, ?, ?, ?, ?)').run('u1', 'hash', '晚风有信 · ABCD1234', 0, '2026-01-01', 1);
  legacy.close();
  const migrated = openDatabase(path);
  assert.equal(migrated.prepare('SELECT alias_key FROM users WHERE id = ?').get('u1').alias_key, '晚风有信 · abcd1234');
  assert.throws(() => migrated.prepare('INSERT INTO users (id, token_hash, alias, alias_key, created_at, session_expires_at) VALUES (?, ?, ?, ?, ?, ?)').run('u2', 'hash2', 'other', '晚风有信 · abcd1234', '2026-01-02', 1));
  migrated.close();
});

test('server date boundaries follow Shanghai instead of host or browser timezone', () => {
  assert.equal(todayInShanghai(new Date('2026-08-31T15:59:59Z')), '2026-08-31');
  assert.equal(todayInShanghai(new Date('2026-08-31T16:00:00Z')), '2026-09-01');
  assert.equal(todayInShanghai(new Date('2026-12-31T16:00:00Z')), '2027-01-01');
  assert.equal(periodStart('month', '2027-01-01'), '2027-01-01');
  assert.equal(periodStart('year', '2027-01-01'), '2027-01-01');
  assert.ok(validDay('2024-02-29', '2026-08-31'));
  assert.equal(validDay('2026-02-29', '2026-08-31'), false);
});

test('English sessions use valid English aliases without renaming existing identities', async t => {
  const { request, newUser, put, db } = await setup(t);
  const headers = { 'X-Journal-Language': 'en' };
  const chinese = await newUser();
  assert.match(chinese.profile.alias, /\p{Script=Han}/u);
  const same = await request('/session', { method: 'POST', cookie: chinese.cookie, body: {}, headers });
  assert.equal(same.data.profile.alias, chinese.profile.alias);
  const english = await request('/session', { method: 'POST', body: {}, headers });
  assert.equal(english.status, 200);
  assert.match(english.data.profile.alias, /^[A-Za-z]+ · [A-F0-9]{8}$/);
  assert.ok([...english.data.profile.alias].length <= 16);
  assert.equal(english.data.profile.participating, false);
  assert.equal(english.headers.get('content-language'), 'en');
  assert.match(english.headers.get('vary'), /X-Journal-Language/);
  const cookie = english.headers.get('set-cookie').split(';')[0];
  await put(cookie, '2026-08-31', 'success');
  assert.equal((await request('/leaderboard', { headers })).data.rows.length, 0);
  const rename = await request('/profile', { method: 'PATCH', cookie: chinese.cookie, body: { alias: '' }, headers });
  assert.match(rename.data.profile.alias, /^[A-Za-z]+ · [A-F0-9]{8}$/);
  const duplicate = await request('/profile', { method: 'PATCH', cookie, body: { alias: rename.data.profile.alias.toLowerCase() }, headers });
  assert.equal(duplicate.status, 409);
  assert.match(duplicate.data.error, /username is taken/);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 2);
  // Language changes display only: the existing deletion protocol stays compatible.
  const deleted = await request('/account', { method: 'DELETE', cookie, body: { confirmation: '删除' }, headers });
  assert.equal(deleted.status, 200);
});

test('English errors cover validation, security, parser, and not-found boundaries', async t => {
  const { request, newUser } = await setup(t);
  const { cookie } = await newUser();
  const headers = { 'X-Journal-Language': 'en' };
  const cases = [
    ['/records', {}, 401, /session has expired/],
    ['/session', { method: 'POST', body: {}, headers: { 'X-Journal-Request': '' } }, 403, /request source/],
    ['/session', { method: 'POST', body: {}, headers: { 'Content-Type': 'text/plain' } }, 415, /JSON/],
    ['/session', { method: 'POST', rawBody: '{bad' }, 400, /request format/],
    ['/session', { method: 'POST', body: { data: 'a'.repeat(9000) } }, 413, /too large/],
    ['/records?month=nope', { cookie }, 400, /month/],
    ['/records/2999-01-01', { cookie, method: 'PUT', body: { outcome: 'success' } }, 400, /Future dates/],
    ['/records/2026-08-31', { cookie, method: 'PUT', body: { outcome: 'unknown' } }, 400, /outcome/],
    ['/records/invalid', { cookie, method: 'DELETE', body: {} }, 400, /date/],
    ['/profile', { cookie, method: 'PATCH', body: { unknown: true } }, 400, /profile/],
    ['/profile', { cookie, method: 'PATCH', body: { participating: 'yes' } }, 400, /whether to join/],
    ['/profile', { cookie, method: 'PATCH', body: { alias: 1 } }, 400, /username/],
    ['/profile', { cookie, method: 'PATCH', body: { alias: 'a' } }, 400, /2–16/],
    ['/profile', { cookie, method: 'PATCH', body: { alias: '<script>' } }, 400, /letters, numbers/],
    ['/leaderboard?metric=bad', {}, 400, /filters/],
    ['/account', { cookie, method: 'DELETE', body: {} }, 400, /confirm permanent deletion/],
    ['/missing', {}, 404, /Endpoint not found/],
  ];
  for (const [path, options, status, expected] of cases) {
    const result = await request(path, { ...options, headers: { ...headers, ...options.headers } });
    assert.equal(result.status, status, path);
    assert.match(result.data.error, expected, path);
    assert.doesNotMatch(result.data.error, /\p{Script=Han}/u, path);
  }
  // Older clients and unknown language values retain the Chinese response.
  for (const lang of [undefined, 'zh-Hans', 'fr', 'english']) {
    const result = await request('/missing', { headers: lang ? { 'X-Journal-Language': lang } : {} });
    assert.equal(result.data.error, '接口不存在。');
    assert.equal(result.headers.get('content-language'), 'zh-Hans');
  }
});

test('rate limiting keeps its limits and returns the requested language', async t => {
  const { request } = await setup(t, { limit: true });
  const headers = { 'X-Journal-Language': 'en' };
  for (let i = 0; i < 30; i += 1) assert.equal((await request('/session', { method: 'POST', body: {}, headers })).status, 200);
  const sessions = await request('/session', { method: 'POST', body: {}, headers });
  assert.equal(sessions.status, 429);
  assert.match(sessions.data.error, /Too many new sessions/);
  // 31 requests used above; the general per-minute limit remains 240.
  for (let i = 31; i < 240; i += 1) assert.equal((await request('/health', { headers })).status, 200);
  const general = await request('/health', { headers });
  assert.equal(general.status, 429);
  assert.match(general.data.error, /Too many requests/);
  assert.equal((await request('/health')).data.error, '操作太频繁，请稍后再试。');
});
