import { AlertTriangle, Inbox, RotateCw } from 'lucide-react'

/** Skeleton placeholder shown while a page's first load is in flight. */
export function Loading({ rows = 4 }: { rows?: number }) {
  return (
    <div className="space-y-3 animate-pulse" aria-label="Loading">
      <div className="h-6 w-40 rounded-md bg-white/[0.06]" />
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="h-20 rounded-[0.875rem] bg-white/[0.03] border border-line" />
      ))}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center text-center py-12 px-4">
      <AlertTriangle size={28} className="text-amber-400 mb-3" />
      <p className="text-sm text-white mb-1">Couldn't load this page</p>
      <p className="text-xs text-slate-500 mb-4 max-w-sm break-words">{message}</p>
      {onRetry && (
        <button onClick={onRetry}
          className="flex items-center gap-2 px-4 py-1.5 bg-violet-600 hover:bg-violet-500 text-white shadow-sm shadow-violet-950/50 text-sm rounded-lg">
          <RotateCw size={14} /> Retry
        </button>
      )}
    </div>
  )
}

export function EmptyState({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <div className="flex flex-col items-center text-center py-10 px-4 text-slate-500">
      <Inbox size={24} className="mb-2" />
      <p className="text-sm text-slate-300">{title}</p>
      {subtitle && <p className="text-xs mt-1">{subtitle}</p>}
    </div>
  )
}
