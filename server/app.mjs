import express from 'express';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { todayInShanghai, validDay, validMonth, periodStart, TIMEZONE } from './dates.mjs';
import { aliasKey, makeDefaultAlias, validateAlias } from './aliases.mjs';

const COOKIE = 'journal_session';
const MAX_AGE = 365 * 24 * 60 * 60 * 1000;
const hash = token => createHash('sha256').update(token).digest('hex');
const profile = user => ({ alias: user.alias, participating: Boolean(user.participating) });
const bodyIsObject = body => body !== null && typeof body === 'object' && !Array.isArray(body);
const language = req => /^en(?:-|$)/i.test(req.get('x-journal-language') || '') ? 'en' : 'zh-Hans';
const message = (req, chinese, english) => language(req) === 'en' ? english : chinese;

function unusedDefaultAlias(db, locale) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const alias = makeDefaultAlias(locale);
    if (!db.prepare('SELECT 1 FROM users WHERE alias_key = ?').get(aliasKey(alias))) return alias;
  }
  throw new Error('Unable to allocate alias');
}

export function createApp({ db, now = () => new Date(), appOrigin, cookieSecure = false, development = false, limit = true, trustProxy = false }) {
  const app = express();
  if (trustProxy) app.set('trust proxy', trustProxy);
  app.disable('x-powered-by');
  app.use(helmet({
    contentSecurityPolicy: development ? false : { directives: { 'upgrade-insecure-requests': cookieSecure ? [] : null } },
    strictTransportSecurity: cookieSecure ? undefined : false,
    referrerPolicy: { policy: 'no-referrer' },
  }));
  app.use('/api', (req, res, next) => {
    res.set('Cache-Control', 'no-store');
    res.set('Content-Language', language(req));
    res.vary('X-Journal-Language');
    if (req.method === 'GET' || req.method === 'HEAD') return next();
    const origin = req.get('origin');
    const allowed = appOrigin || `${req.protocol}://${req.get('host')}`;
    if (req.get('x-journal-request') !== '1' || (origin && origin !== allowed) || req.get('sec-fetch-site') === 'cross-site') {
      return res.status(403).json({ error: message(req, '请求来源无效，请从应用页面操作。', 'Invalid request source. Please use the app.') });
    }
    if (!req.is('application/json')) return res.status(415).json({ error: message(req, '请使用 JSON 格式。', 'Please use JSON format.') });
    next();
  });
  app.use(express.json({ limit: '8kb' }));
  if (limit) app.use('/api', rateLimit({ windowMs: 60_000, limit: 240, standardHeaders: 'draft-8', legacyHeaders: false, handler: (req, res) => res.status(429).json({ error: message(req, '操作太频繁，请稍后再试。', 'Too many requests. Please try again shortly.') }) }));
  const cookieOptions = { httpOnly: true, sameSite: 'strict', secure: cookieSecure, path: '/' };
  const readUser = req => {
    const token = req.headers.cookie?.split(';').map(part => part.trim()).find(part => part.startsWith(COOKIE + '='))?.slice(COOKIE.length + 1);
    if (!token || !/^[a-f0-9]{64}$/.test(token)) return null;
    return db.prepare('SELECT * FROM users WHERE token_hash = ? AND session_expires_at > ?').get(hash(token), now().getTime());
  };
  const auth = (req, res, next) => {
    const user = readUser(req);
    if (!user) return res.status(401).json({ error: message(req, '匿名身份已失效，请刷新页面重新进入。', 'Your anonymous session has expired. Please reopen the app.') });
    req.user = user;
    next();
  };
  app.get('/api/health', (_req, res) => res.json({ ok: true }));
  const sessionLimit = limit ? rateLimit({ windowMs: 60 * 60_000, limit: 30, skip: req => Boolean(readUser(req)), handler: (req, res) => res.status(429).json({ error: message(req, '创建身份过于频繁，请稍后再试。', 'Too many new sessions. Please try again later.') }), standardHeaders: 'draft-8', legacyHeaders: false }) : (_req, _res, next) => next();
  app.post('/api/session', sessionLimit, (req, res) => {
    let user = readUser(req);
    if (!user) {
      const token = randomBytes(32).toString('hex');
      const id = randomUUID();
      const alias = unusedDefaultAlias(db, language(req));
      db.prepare('INSERT INTO users (id, token_hash, alias, alias_key, created_at, session_expires_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, hash(token), alias, aliasKey(alias), now().toISOString(), now().getTime() + MAX_AGE);
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
      res.cookie(COOKIE, token, { ...cookieOptions, maxAge: MAX_AGE });
    } else {
      db.prepare('UPDATE users SET session_expires_at = ? WHERE id = ?').run(now().getTime() + MAX_AGE, user.id);
      const token = req.headers.cookie.split(';').map(p => p.trim()).find(p => p.startsWith(COOKIE + '=')).slice(COOKIE.length + 1);
      res.cookie(COOKIE, token, { ...cookieOptions, maxAge: MAX_AGE });
    }
    const today = todayInShanghai(now());
    res.json({ profile: profile(user), today, timezone: TIMEZONE });
  });
  app.get('/api/records', auth, (req, res) => {
    const month = req.query.month ?? todayInShanghai(now()).slice(0, 7);
    if (!validMonth(month)) return res.status(400).json({ error: message(req, '月份格式无效。', 'Invalid month.') });
    const records = db.prepare('SELECT date, outcome, note, updated_at AS updatedAt FROM records WHERE user_id = ? AND date >= ? AND date <= ? ORDER BY date DESC').all(req.user.id, month + '-01', month + '-31');
    const success = records.filter(r => r.outcome === 'success').length;
    res.json({ records, stats: { success, declined: records.length - success, total: records.length } });
  });
  app.put('/api/records/:date', auth, (req, res) => {
    if (!validDay(req.params.date, todayInShanghai(now()))) return res.status(400).json({ error: message(req, '请选择 2000 年以来的有效日期，不能记录未来。', 'Choose a valid date from 2000 onward. Future dates are not allowed.') });
    if (!bodyIsObject(req.body) || !['success', 'declined'].includes(req.body.outcome) || (req.body.note !== undefined && (typeof req.body.note !== 'string' || req.body.note.length > 300))) return res.status(400).json({ error: message(req, '请选择当天结果，备注最多 300 字。', 'Choose an outcome. Notes must be 300 characters or fewer.') });
    const { outcome, note = '' } = req.body;
    db.prepare(`INSERT INTO records (user_id, date, outcome, note, updated_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id, date) DO UPDATE SET outcome = excluded.outcome, note = excluded.note, updated_at = excluded.updated_at`).run(req.user.id, req.params.date, outcome, note.trim(), now().toISOString());
    res.json({ ok: true });
  });
  app.delete('/api/records/:date', auth, (req, res) => {
    if (!validDay(req.params.date, todayInShanghai(now()))) return res.status(400).json({ error: message(req, '日期无效。', 'Invalid date.') });
    db.prepare('DELETE FROM records WHERE user_id = ? AND date = ?').run(req.user.id, req.params.date);
    res.json({ ok: true });
  });
  app.patch('/api/profile', auth, (req, res) => {
    if (!bodyIsObject(req.body)) return res.status(400).json({ error: message(req, '个人资料格式无效。', 'Invalid profile information.') });
    const keys = Object.keys(req.body);
    if (!keys.length || keys.some(key => !['alias', 'participating'].includes(key))) return res.status(400).json({ error: message(req, '个人资料格式无效。', 'Invalid profile information.') });
    if ('participating' in req.body && typeof req.body.participating !== 'boolean') return res.status(400).json({ error: message(req, '请选择是否参与匿名排行。', 'Choose whether to join the anonymous leaderboard.') });

    let nextAlias = req.user.alias;
    if ('alias' in req.body) {
      if (typeof req.body.alias !== 'string') return res.status(400).json({ error: message(req, '用户名格式无效。', 'Invalid username.') });
      if (!req.body.alias.trim()) {
        nextAlias = unusedDefaultAlias(db, language(req));
      } else {
        const validated = validateAlias(req.body.alias, language(req));
        if (validated.error) return res.status(400).json({ error: validated.error });
        nextAlias = validated.alias;
      }
      const existing = db.prepare('SELECT id FROM users WHERE alias_key = ?').get(aliasKey(nextAlias));
      if (existing && existing.id !== req.user.id) return res.status(409).json({ error: message(req, '这个用户名已经有人使用了，请换一个。', 'This username is taken. Please choose another.') });
    }

    const participating = 'participating' in req.body ? req.body.participating : Boolean(req.user.participating);
    db.prepare('UPDATE users SET alias = ?, alias_key = ?, participating = ? WHERE id = ?').run(nextAlias, aliasKey(nextAlias), Number(participating), req.user.id);
    const updated = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
    res.json({ profile: profile(updated) });
  });
  app.get('/api/leaderboard', (req, res) => {
    const metric = req.query.metric ?? 'success';
    const period = req.query.period ?? 'month';
    if (!['success', 'declined'].includes(metric) || !['month', 'year', 'all'].includes(period)) return res.status(400).json({ error: message(req, '排行榜筛选条件无效。', 'Invalid leaderboard filters.') });
    const user = readUser(req);
    const today = todayInShanghai(now());
    const start = periodStart(period, today);
    const rankedSql = `WITH totals AS (
      SELECT u.id, u.alias, COUNT(*) AS days FROM users u JOIN records r ON u.id = r.user_id
      WHERE u.participating = 1 AND r.outcome = ? AND r.date >= ? AND r.date <= ? GROUP BY u.id
    ), ranked AS (SELECT id, alias, days, RANK() OVER (ORDER BY days DESC) AS rank FROM totals)`;
    const rows = db.prepare(rankedSql + ' SELECT * FROM ranked ORDER BY rank, alias LIMIT 50').all(metric, start, today);
    const mine = user ? db.prepare(rankedSql + ' SELECT * FROM ranked WHERE id = ?').get(metric, start, today, user.id) : null;
    const total = db.prepare(rankedSql + ' SELECT COUNT(*) AS count FROM ranked').get(metric, start, today).count;
    const clean = row => ({ alias: row.alias, days: row.days, rank: row.rank, isMe: Boolean(user && row.id === user.id) });
    res.json({ metric, period, start, end: today, total, rows: rows.map(clean), mine: mine ? clean(mine) : null, updatedAt: now().toISOString() });
  });
  app.get('/api/export', auth, (req, res) => {
    const records = db.prepare('SELECT date, outcome, note, updated_at AS updatedAt FROM records WHERE user_id = ? ORDER BY date DESC').all(req.user.id);
    res.attachment('jinwan-ne-private-records.json').json({ version: 1, timezone: TIMEZONE, exportedAt: now().toISOString(), records });
  });
  app.delete('/api/account', auth, (req, res) => {
    if (req.body?.confirmation !== '删除') return res.status(400).json({ error: message(req, '请输入「删除」确认。', 'Please confirm permanent deletion in the app.') });
    db.prepare('DELETE FROM users WHERE id = ?').run(req.user.id);
    res.clearCookie(COOKIE, cookieOptions);
    res.json({ ok: true });
  });
  app.use('/api', (req, res) => res.status(404).json({ error: message(req, '接口不存在。', 'Endpoint not found.') }));
  app.use((err, req, res, _next) => {
    if (err.type === 'entity.too.large') return res.status(413).json({ error: message(req, '提交内容太长。', 'The submitted content is too large.') });
    if (err instanceof SyntaxError && err.status === 400) return res.status(400).json({ error: message(req, '提交内容格式无效。', 'Invalid request format.') });
    // Never log request bodies, cookies, SQL values or private notes.
    console.error('Request failed:', err.name);
    res.status(500).json({ error: message(req, '服务器暂时无法处理，请稍后重试。', 'The server is temporarily unavailable. Please try again later.') });
  });
  return app;
}
