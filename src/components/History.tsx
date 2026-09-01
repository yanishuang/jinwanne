import { useState } from 'react';
import { api, dayLabel, useResource } from '../lib/api';
import type { DiaryData, Entry, Outcome } from '../lib/api';
import { ErrorNotice, Loading } from './Shared';

export default function History({ today, revision, onChange, notify }: {
  today: string; revision: number; onChange: () => void; notify: (message: string) => void;
}) {
  const [month, setMonth] = useState(today.slice(0, 7));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState<string | null>(null);
  const resource = useResource<DiaryData>(`/records?month=${month}`, revision);

  async function change(entry: Entry, outcome?: Outcome) {
    if (busy) return;
    setBusy(true); setError('');
    try {
      await api(`/records/${entry.date}`, {
        method: outcome ? 'PUT' : 'DELETE',
        body: JSON.stringify(outcome ? { outcome, note: entry.note } : {}),
      });
      setDeleting(null); onChange(); notify(outcome ? '结果已修改。' : '记录已删除。');
    } catch (error) { setError((error as Error).message); }
    finally { setBusy(false); }
  }

  return <section className="history-page">
    <label className="month-picker">查看月份<input aria-label="查看月份" type="month" min="2000-01" max={today.slice(0, 7)} value={month} disabled={busy} onChange={event => { if (event.target.value) setMonth(event.target.value); }} /></label>
    {error && <ErrorNotice message={error} />}
    {resource.loading ? <Loading /> : resource.error ? <ErrorNotice message={resource.error} onRetry={onChange} /> : resource.data && <>
      <div className="history-stats"><div><span>成功天数</span><strong>{resource.data.stats.success}<small>天</small></strong></div><div><span>失败天数</span><strong>{resource.data.stats.declined}<small>天</small></strong></div></div>
      {resource.data.records.length ? <div className="history-list">{resource.data.records.map(entry => <details key={entry.date} className="history-item">
        <summary><span>{dayLabel(entry.date)}</span><strong>{entry.outcome === 'success' ? '成功' : '失败'}</strong></summary>
        {entry.note && <p className="history-note">{entry.note}</p>}
        <div className="history-actions"><button disabled={busy} onClick={() => void change(entry, 'success')}>改为成功</button><button disabled={busy} onClick={() => void change(entry, 'declined')}>改为失败</button><button disabled={busy} onClick={() => setDeleting(entry.date)}>删除</button></div>
        {deleting === entry.date && <div className="delete-confirm" role="alert"><p>确认删除这一天？统计也会随之更新。</p><button className="danger-button" disabled={busy} onClick={() => void change(entry)}>确认删除</button><button className="quiet-button" disabled={busy} onClick={() => setDeleting(null)}>取消</button></div>}
      </details>)}</div> : <p className="history-empty">这个月还没有记录。</p>}
    </>}
  </section>;
}
