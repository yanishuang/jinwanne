import { useEffect, useState } from 'react';

export type Outcome = 'success' | 'declined';
export type Profile = { alias: string; participating: boolean };
export type Session = { profile: Profile; today: string; timezone: string };
export type Entry = { date: string; outcome: Outcome; note: string; updatedAt: string };
export type DiaryData = { records: Entry[]; stats: { success: number; declined: number; total: number } };
export type RankRow = { alias: string; rank: number; days: number; isMe: boolean };
export type Ranking = { rows: RankRow[]; mine: RankRow | null; total: number; start: string; end: string; updatedAt: string };

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch('/api' + path, {
    ...options, credentials: 'same-origin', cache: 'no-store',
    headers: { 'Content-Type': 'application/json', 'X-Journal-Request': '1', ...options.headers },
  });
  const body = await response.json().catch(() => ({ error: '服务器连接异常，请稍后重试。' }));
  if (!response.ok) throw new Error(body.error || '操作失败，请稍后再试。');
  return body as T;
}
export function useResource<T>(path: string, revision = 0) {
  const [state, setState] = useState<{ data: T | null; error: string; loading: boolean }>({ data: null, error: '', loading: true });
  useEffect(() => {
    const controller = new AbortController();
    setState({ data: null, loading: true, error: '' });
    api<T>(path, { signal: controller.signal }).then(data => setState({ data, loading: false, error: '' })).catch(error => {
      if (!controller.signal.aborted) setState({ data: null, loading: false, error: error.message });
    });
    return () => controller.abort();
  }, [path, revision]);
  return state;
}
export const monthNames = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
export function dayLabel(date: string) {
  const parsed = new Date(date + 'T12:00:00+08:00');
  if (Number.isNaN(parsed.getTime())) return '请选择有效日期';
  const parts = new Intl.DateTimeFormat('zh-CN', { timeZone: 'Asia/Shanghai', month: 'numeric', day: 'numeric', weekday: 'long' }).formatToParts(parsed);
  const part = (type: string) => parts.find(item => item.type === type)?.value;
  return `${part('month')} 月 ${part('day')} 日 · ${part('weekday')}`;
}
export function shiftMonth(month: string, direction: number) {
  const [year, number] = month.split('-').map(Number);
  const date = new Date(Date.UTC(year, number - 1 + direction, 1));
  return date.toISOString().slice(0, 7);
}
