import { randomBytes } from 'node:crypto';

const DEFAULT_NAMES = ['松间来客', '月下散步', '山野来信', '慢慢相处', '听风的人', '晚风有信'];
const ENGLISH_DEFAULT_NAMES = ['Comet', 'Moon', 'Orbit', 'Dusk', 'Rover', 'Echo'];
const ALLOWED_ALIAS = /^[\p{L}\p{N}_· -]+$/u;

export function normalizeAlias(value) {
  return value.normalize('NFKC').trim().replace(/\s+/gu, ' ');
}

export function aliasKey(value) {
  return normalizeAlias(value).toLowerCase();
}

export function validateAlias(value, language = 'zh-Hans') {
  const message = (chinese, english) => language === 'en' ? english : chinese;
  if (typeof value !== 'string') return { error: message('用户名格式无效。', 'Invalid username.') };
  const alias = normalizeAlias(value);
  const length = [...alias].length;
  if (length < 2 || length > 16) return { error: message('用户名需要 2–16 个字符。', 'Use 2–16 characters for your username.') };
  if (!ALLOWED_ALIAS.test(alias)) return { error: message('用户名只能使用中文、字母、数字、空格以及 _ - ·。', 'Use letters, numbers, spaces, or _ - · in your username.') };
  return { alias, key: aliasKey(alias) };
}

export function makeDefaultAlias(language = 'zh-Hans') {
  const names = language === 'en' ? ENGLISH_DEFAULT_NAMES : DEFAULT_NAMES;
  const name = names[randomBytes(1)[0] % names.length];
  return `${name} · ${randomBytes(4).toString('hex').toUpperCase()}`;
}
