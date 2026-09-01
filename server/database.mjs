import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname } from 'node:path';
import { aliasKey } from './aliases.mjs';

export function openDatabase(path = ':memory:') {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const db = new DatabaseSync(path);
  if (path !== ':memory:') chmodSync(path, 0o600);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    PRAGMA busy_timeout = 5000;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      token_hash TEXT NOT NULL UNIQUE,
      alias TEXT NOT NULL UNIQUE,
      alias_key TEXT NOT NULL UNIQUE,
      participating INTEGER NOT NULL DEFAULT 0 CHECK(participating IN (0, 1)),
      created_at TEXT NOT NULL,
      session_expires_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS records (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      date TEXT NOT NULL,
      outcome TEXT NOT NULL CHECK(outcome IN ('success', 'declined')),
      note TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_id, date)
    );
    CREATE INDEX IF NOT EXISTS records_date_outcome ON records(date, outcome, user_id);
  `);
  const userColumns = db.prepare('PRAGMA table_info(users)').all();
  if (!userColumns.some(column => column.name === 'alias_key')) {
    db.exec('ALTER TABLE users ADD COLUMN alias_key TEXT');
  }
  const existingAliases = db.prepare('SELECT id, alias FROM users ORDER BY created_at, id').all();
  const usedKeys = new Set();
  const updateAlias = db.prepare('UPDATE users SET alias = ?, alias_key = ? WHERE id = ?');
  for (const user of existingAliases) {
    let alias = user.alias;
    let key = aliasKey(alias);
    if (usedKeys.has(key)) {
      alias = `${[...alias].slice(0, 9).join('')} · ${user.id.slice(0, 4).toUpperCase()}`;
      key = aliasKey(alias);
    }
    usedKeys.add(key);
    updateAlias.run(alias, key, user.id);
  }
  db.exec('CREATE UNIQUE INDEX IF NOT EXISTS users_alias_key_unique ON users(alias_key)');
  return db;
}
