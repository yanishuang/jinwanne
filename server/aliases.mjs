import { randomBytes } from 'node:crypto';

const DEFAULT_NAMES = ['松间来客', '月下散步', '山野来信', '慢慢相处', '听风的人', '晚风有信'];
const ALLOWED_ALIAS = /^[\p{L}\p{N}_· -]+$/u;

export function normalizeAlias(value) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ');
}

export function aliasKey(value) {
  return normalizeAlias(value).toLowerCase();
}

export function validateAlias(value) {
  if (typeof value !== 'string') return { error: '用户名格式无效。' };
  const alias = normalizeAlias(value);
  const length = [...alias].length;
  if (length < 2 || length > 16) return { error: '用户名需要 2–16 个字符。' };
  if (!ALLOWED_ALIAS.test(alias)) return { error: '用户名只能使用中文、字母、数字、空格以及 _ - ·。' };
  return { alias, key: aliasKey(alias) };
}

export function makeDefaultAlias() {
  const name = DEFAULT_NAMES[randomBytes(1)[0] % DEFAULT_NAMES.length];
  return `${name} · ${randomBytes(4).toString('hex').toUpperCase()}`;
}
