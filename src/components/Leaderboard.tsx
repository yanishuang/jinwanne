import { useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { ErrorNotice, Loading } from './Shared';
import { useResource } from '../lib/api';
import type { Outcome, Profile, Ranking } from '../lib/api';

export default function Leaderboard({ profile, revision }: { profile: Profile; revision: number }) {
  const [metric, setMetric] = useState<Outcome>('success');
  const [period, setPeriod] = useState('month');
  const [refresh, setRefresh] = useState(0);
  const { data, loading, error } = useResource<Ranking>(`/leaderboard?metric=${metric}&period=${period}`, revision + refresh);
  return <section className="leaderboard-page" aria-label="匿名排行榜">
    <p className="page-description">匿名上榜，只看天数。</p>
    <div className="line-tabs" aria-label="榜单类型">
      {(['success', 'declined'] as const).map(value => <button className={metric === value ? 'active' : ''} aria-pressed={metric === value} key={value} onClick={() => setMetric(value)}>{value === 'success' ? '成功榜' : '失败榜'}</button>)}
    </div>
    <div className="ranking-toolbar">
      <div className="segmented" aria-label="统计时间">
        {[['month', '本月'], ['year', '今年'], ['all', '全部']].map(([value, label]) => <button key={value} className={period === value ? 'active' : ''} aria-pressed={period === value} onClick={() => setPeriod(value)}>{label}</button>)}
      </div>
      <button className="icon-button" aria-label="刷新排行榜" onClick={() => setRefresh(value => value + 1)} disabled={loading}><RefreshCw size={18} className={loading ? 'spin' : ''} /></button>
    </div>
    {loading ? <Loading label="正在读取排行榜…" />
      : error ? <ErrorNotice message={error} onRetry={() => setRefresh(value => value + 1)} />
      : data && <>
        <table><thead><tr><th>排名</th><th>匿名用户</th><th>天数</th></tr></thead>
          <tbody>{data.rows.map(row => <tr className={row.isMe ? 'my-row' : ''} key={row.alias}>
            <td className="rank-number">{String(row.rank).padStart(2, '0')}</td>
            <td><span className="rank-alias">{row.alias}</span>{row.isMe && <small className="me-label">我</small>}</td>
            <td className="rank-days">{row.days}</td>
          </tr>)}</tbody>
        </table>
        {!data.rows.length && <div className="empty-ranking"><p>暂时还没有人上榜</p><span>有对应记录并主动参与后，就会出现在这里。</span></div>}
        <div className="participation-row">
          <span>{!profile.participating ? '我还没有参与排行' : data.mine ? `我的排名：第 ${data.mine.rank} 名 · ${data.mine.days} 天` : '已参与 · 暂无对应记录'}</span>
          <a href="#settings" className="outline-button">{profile.participating ? '管理' : '匿名参与'}</a>
        </div>
        <p className="rank-caption">自愿参与，可随时退出。</p>
        <details className="ranking-rules"><summary>统计规则</summary><p>北京时间，每天一个最终结果。失败指申请被拒绝，不评价任何人。相同天数并列，展示前 50 位及自己的排名。修改或删除后刷新即可更新。数据由用户自报。</p></details>
      </>}
  </section>;
}
