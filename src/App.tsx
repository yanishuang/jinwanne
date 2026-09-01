import { useEffect, useState } from 'react';
import { ArrowLeft, BarChart3, ClipboardList, Settings2, X } from 'lucide-react';
import QuickRecord from './components/QuickRecord';
import Leaderboard from './components/Leaderboard';
import Settings from './components/Settings';
import History from './components/History';
import { ErrorNotice, Loading } from './components/Shared';
import { api } from './lib/api';
import type { Session } from './lib/api';

type Page = 'home' | 'leaderboard' | 'settings' | 'history';
function currentPage(): Page {
  const hash = window.location.hash.slice(1);
  return hash === 'leaderboard' || hash === 'settings' || hash === 'history' ? hash : 'home';
}

export default function App() {
  const [page, setPage] = useState(currentPage);
  const [session, setSession] = useState<Session | null>(null);
  const [bootError, setBootError] = useState('');
  const [revision, setRevision] = useState(0);
  const [toast, setToast] = useState('');
  const refresh = () => setRevision(value => value + 1);

  const init = () => {
    setBootError('');
    api<Session>('/session', { method: 'POST', body: '{}' })
      .then(setSession)
      .catch(error => setBootError(error.message));
  };
  useEffect(init, []);
  useEffect(() => {
    const onHash = () => { setPage(currentPage()); window.scrollTo({ top: 0 }); };
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);
  useEffect(() => {
    if (!session) return;
    const updateDay = () => {
      const localDay = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
      }).format(new Date());
      if (localDay === session.today || document.visibilityState !== 'visible') return;
      api<Session>('/session', { method: 'POST', body: '{}' })
        .then(data => { setSession(data); refresh(); })
        .catch(() => { /* Retry on focus or the next minute without hiding records. */ });
    };
    const timer = setInterval(updateDay, 60_000);
    window.addEventListener('focus', updateDay);
    return () => { clearInterval(timer); window.removeEventListener('focus', updateDay); };
  }, [session]);
  useEffect(() => {
    if (!toast) return;
    const timer = setTimeout(() => setToast(''), 4000);
    return () => clearTimeout(timer);
  }, [toast]);

  const secondary = page === 'settings' || page === 'history';
  const title = page === 'home' ? '今晚呢' : page === 'leaderboard' ? '排行榜' : page === 'history' ? '我的记录' : '设置';

  return <div className={`app-shell page-${page}`}>
    <header className="app-header">
      {secondary
        ? <a href={page === 'history' ? '#settings' : '#home'} className="icon-button" aria-label="返回"><ArrowLeft size={22} /></a>
        : <span className="header-spacer" />}
      <a href="#home" className="app-title">{title}</a>
      {secondary ? <span className="header-spacer" /> : <a href="#settings" className="icon-button" aria-label="设置"><Settings2 size={22} /></a>}
    </header>
    <main className="main-content">
      {!session
        ? bootError ? <ErrorNotice message={bootError} onRetry={init} /> : <Loading label="正在打开…" />
        : page === 'home' ? <QuickRecord key={session.today} today={session.today} revision={revision} onSaved={refresh} />
        : page === 'leaderboard' ? <Leaderboard profile={session.profile} revision={revision} />
        : page === 'history' ? <History today={session.today} revision={revision} onChange={refresh} notify={setToast} />
        : <Settings profile={session.profile} onProfile={profile => { setSession({ ...session, profile }); refresh(); }} notify={setToast} />}
    </main>
    <nav className="bottom-nav" aria-label="主导航">
      <a href="#home" className={page === 'home' ? 'active' : ''} aria-current={page === 'home' ? 'page' : undefined}><ClipboardList size={22} /><span>记录</span></a>
      <a href="#leaderboard" className={page === 'leaderboard' ? 'active' : ''} aria-current={page === 'leaderboard' ? 'page' : undefined}><BarChart3 size={23} /><span>排行榜</span></a>
    </nav>
    {toast && <div className="toast" role="status"><span>{toast}</span><button aria-label="关闭提示" onClick={() => setToast('')}><X size={16} /></button></div>}
  </div>;
}
