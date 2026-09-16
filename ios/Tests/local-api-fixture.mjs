import { writeFileSync } from 'node:fs';
import { openDatabase } from '../../server/database.mjs';
import { createApp } from '../../server/app.mjs';

const db = openDatabase(':memory:');
const app = createApp({ db, limit: false });
const server = app.listen(0, '127.0.0.1', () => {
  writeFileSync(process.argv[2], `http://127.0.0.1:${server.address().port}/api`, { mode: 0o600 });
});
process.on('SIGTERM', () => server.close(() => { db.close(); process.exit(0); }));
