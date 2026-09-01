import { useEffect, useRef, useState } from 'react';
import { Check, Minus } from 'lucide-react';
import { api, dayLabel, useResource } from '../lib/api';
import type { DiaryData, Entry, Outcome } from '../lib/api';
import { ErrorNotice, Loading } from './Shared';

export default function QuickRecord({ today, revision, onSaved }: {
  today: string; revision: number; onSaved: () => void;
}) {
  const { data, loading, error } = useResource<DiaryData>(`/records?month=${today.slice(0, 7)}`, revision);
  const [choosing, setChoosing] = useState(false);
  const [saved, setSaved] = useState<Entry | null>(null);
  const [saving, setSaving] = useState<Outcome | null>(null);
  const [saveError, setSaveError] = useState('');
  const writing = useRef(false);
  const choiceHeading = useRef<HTMLHeadingElement>(null);
  const savedHeading = useRef<HTMLHeadingElement>(null);
  const entry = saved ?? data?.records.find(record => record.date === today);

  useEffect(() => {
    if (choosing) choiceHeading.current?.focus();
    else if (saved) savedHeading.current?.focus();
  }, [choosing, saved]);

  async function save(outcome: Outcome) {
    if (writing.current) return;
    writing.current = true;
    setSaving(outcome); setSaveError('');
    try {
      // Preserve a note from the earlier app when changing just the result.
      const note = entry?.note ?? '';
      await api(`/records/${today}`, { method: 'PUT', body: JSON.stringify({ outcome, note }) });
      setSaved({ date: today, outcome, note, updatedAt: new Date().toISOString() });
      setChoosing(false); onSaved();
    } catch (error) {
      setSaveError((error as Error).message || '保存失败，请再试一次。');
    } finally {
      writing.current = false; setSaving(null);
    }
  }

  return <section className="quick-record" aria-label="今晚记录">
    <div className="quick-content">
      <p className="today-label">{dayLabel(today)}</p>
      {loading && !saved ? <Loading label="正在读取…" />
        : error && !saved ? <ErrorNotice message={error} onRetry={onSaved} />
        : choosing ? <div className="quick-step" key="choose">
          <h1 ref={choiceHeading} tabIndex={-1}>结果怎么样？</h1>
          <div className="result-buttons">
            <button className="primary-button" disabled={saving !== null} onClick={() => void save('success')}>{saving === 'success' ? '保存中…' : '成功'}</button>
            <button className="outline-button" disabled={saving !== null} onClick={() => void save('declined')}>{saving === 'declined' ? '保存中…' : '失败'}</button>
          </div>
          {saveError && <ErrorNotice message={saveError} />}
          <button className="quiet-button" disabled={saving !== null} onClick={() => { setChoosing(false); setSaveError(''); }}>返回</button>
        </div>
        : entry ? <div className="quick-step saved-step" key="saved" role="status">
          <div className="saved-symbol">{entry.outcome === 'success' ? <Check size={29} strokeWidth={2} /> : <Minus size={29} strokeWidth={2} />}</div>
          <h1 ref={savedHeading} tabIndex={-1}>今晚{entry.outcome === 'success' ? '成功' : '失败'}</h1>
          <p className="saved-caption">已记下，今天不重复计数。</p>
          <button className="quiet-button" onClick={() => setChoosing(true)}>修改结果</button>
        </div>
        : <div className="quick-step" key="start">
          <h1 className="sr-only">记录今晚的结果</h1>
          <button className="primary-button start-button" onClick={() => setChoosing(true)}>今晚发起了</button>
        </div>}
    </div>
    <p className="home-footnote">私人记录 · 双方自愿</p>
  </section>;
}
