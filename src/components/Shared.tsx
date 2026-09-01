import { AlertCircle, LoaderCircle } from 'lucide-react';

export function ErrorNotice({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return <div className="error-notice" role="alert"><AlertCircle size={17} /><span>{message}</span>{onRetry && <button className="text-button" onClick={onRetry}>重新加载</button>}</div>;
}

export function Loading({ label = '正在读取记录…' }: { label?: string }) {
  return <div className="loading" role="status"><LoaderCircle size={17} className="spin" /><span>{label}</span></div>;
}
