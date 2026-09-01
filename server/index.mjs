import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { openDatabase } from './database.mjs';
import { createApp } from './app.mjs';

process.umask(0o077);
const root = fileURLToPath(new URL('../', import.meta.url));
const production = process.env.NODE_ENV === 'production';
const port = Number(process.env.PORT || 3000);
const host = process.env.HOST || '127.0.0.1';
const appOrigin = process.env.APP_ORIGIN;
const cookieSecure = process.env.COOKIE_SECURE === 'true';
if (production && !['127.0.0.1', 'localhost', '::1'].includes(host) && (!appOrigin?.startsWith('https://') || !cookieSecure)) {
  throw new Error('Public deployment requires HTTPS APP_ORIGIN and COOKIE_SECURE=true.');
}
const db = openDatabase(resolve(root, process.env.DATABASE_PATH || 'data/journal.sqlite'));
const app = createApp({ db, appOrigin, cookieSecure, development: !production, trustProxy: process.env.TRUST_PROXY === '1' ? 1 : false });
const server = createServer(app);
let vite;
if (production) {
  const site = resolve(root, 'site');
  const sendPage = name => (_req, res) => res.sendFile(resolve(site, name), { headers: { 'Cache-Control': 'no-cache' } });
  app.use(express.static(site, { index: false, dotfiles: 'deny', maxAge: '1h' }));
  app.get('/', sendPage('index.html'));
  app.get('/privacy', sendPage('privacy.html'));
  app.get('/support', sendPage('support.html'));
  app.get('/privacy.html', (_req, res) => res.redirect(308, '/privacy'));
  app.get('/support.html', (_req, res) => res.redirect(308, '/support'));
  app.use((_req, res) => res.status(404).sendFile(resolve(site, '404.html')));
} else {
  const { createServer: createViteServer } = await import('vite');
  vite = await createViteServer({
    root,
    server: {
      middlewareMode: true,
      hmr: { server },
      fs: {
        deny: [
          '**/.env', '**/.env.*', '**/data/**', '**/tmp/**',
          '**/*.sqlite', '**/*.sqlite-*', '**/*.db', '**/*.db-*',
          '**/*.{pem,key,p12,pfx,cer,crt,mobileprovision}',
        ],
      },
    },
    appType: 'spa',
  });
  app.use(vite.middlewares);
}
server.listen(port, host, () => console.log(`今晚呢已启动：http://localhost:${port}`));
async function shutdown() {
  await vite?.close();
  server.close(() => { db.close(); process.exit(0); });
  server.closeIdleConnections();
  setTimeout(() => process.exit(0), 5000).unref();
}
process.once('SIGTERM', shutdown);
process.once('SIGINT', shutdown);
