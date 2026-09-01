import { useState } from 'react';
import { ChevronRight, Download } from 'lucide-react';
import { api } from '../lib/api';
import type { Profile } from '../lib/api';
import { ErrorNotice } from './Shared';

export default function Settings({ profile, onProfile, notify }: {
  profile: Profile; onProfile: (profile: Profile) => void; notify: (message: string) => void;
}) {
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [confirmation, setConfirmation] = useState('');

  async function changeParticipation() {
    setBusy(true); setError('');
    try {
      const result = await api<{ profile: Profile }>('/profile', {
        method: 'PATCH', body: JSON.stringify({ participating: !profile.participating }),
      });
      onProfile(result.profile); setConsent(false);
      notify(result.profile.participating ? '已匿名参与排行。' : '已退出，私人记录仍保留。');
    } catch (error) { setError((error as Error).message); }
    finally { setBusy(false); }
  }

  async function exportData() {
    setBusy(true); setError('');
    try {
      const data = await api('/export');
      const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
      const link = document.createElement('a');
      link.href = url; link.download = '今晚呢-私人记录.json'; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 10_000);
      notify('已导出，请妥善保存。');
    } catch (error) { setError((error as Error).message); }
    finally { setBusy(false); }
  }

  async function deleteAccount() {
    setBusy(true); setError('');
    try {
      await api('/account', { method: 'DELETE', body: JSON.stringify({ confirmation }) });
      window.location.replace('/');
    } catch (error) { setError((error as Error).message); setBusy(false); }
  }

  return <section className="settings-page">
    {error && <ErrorNotice message={error} />}
    <a className="settings-link" href="#history"><span>我的记录</span><ChevronRight size={18} /></a>
    <div className="settings-section">
      <h2>匿名排行</h2>
      <p className="identity-label">{profile.alias}</p>
      <p>只公开匿名代号、成功和失败天数，不公开具体日期与备注。</p>
      {!profile.participating && <label className="consent-label"><input type="checkbox" checked={consent} disabled={busy} onChange={event => setConsent(event.target.checked)} /><span>我了解公开范围，自愿参与。</span></label>}
      <button className={profile.participating ? 'outline-button' : 'primary-button'} disabled={busy || (!profile.participating && !consent)} onClick={() => void changeParticipation()}>{busy ? '处理中…' : profile.participating ? '退出排行榜' : '开启匿名排行'}</button>
    </div>
    <details className="settings-details"><summary>隐私与数据</summary>
      <p>记录保存在服务器，通过当前浏览器的匿名身份访问。清除 Cookie、换设备或关闭无痕窗口后，无法找回原身份；本版不支持跨设备登录。</p>
      <p>其他用户看不到详细记录，但这不是端到端加密，服务器管理员可访问数据库。共用当前浏览器的人也能查看记录。</p>
      <p>本应用只记结果，不会向伴侣发送申请。失败表示申请被拒绝，亲密始终以双方自愿为前提。</p>
      <button className="outline-button" disabled={busy} onClick={() => void exportData()}><Download size={16} />导出记录</button>
    </details>
    <details className="settings-details"><summary>删除全部数据</summary>
      <p>删除当前匿名身份、全部记录和排名信息，无法撤销。</p>
      {!deleting ? <button className="quiet-button" onClick={() => setDeleting(true)}>删除身份与记录</button> : <div className="account-confirm"><label htmlFor="delete-account">请输入「删除」确认</label><input id="delete-account" value={confirmation} disabled={busy} onChange={event => setConfirmation(event.target.value)} autoComplete="off" /><div><button className="danger-button" disabled={busy || confirmation !== '删除'} onClick={() => void deleteAccount()}>永久删除</button><button className="quiet-button" disabled={busy} onClick={() => { setDeleting(false); setConfirmation(''); }}>取消</button></div></div>}
    </details>
  </section>;
}
