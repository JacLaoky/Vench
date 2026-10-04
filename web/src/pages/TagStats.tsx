import { api } from '../api'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { pnlColor, signedUsd } from '../lib/format'
import { tagColor } from '../lib/tags'
import { EmptyState, ErrorState, Loading } from '../components/PageState'

const TIMEFRAMES = ['1W', '1M', '3M', '1Y', 'AT'] as const

const winBarColor = (rate: number) => (rate >= 60 ? 'bg-emerald-500' : rate >= 40 ? 'bg-amber-500' : 'bg-red-500')

export default function TagStats() {
  const [tf, setTf] = usePersistentState<string>('tags.timeframe', 'AT')
  const { data, error, loading, reload } = useApi(() => api.getTagStats(tf).then(r => r.data ?? []), [tf])

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap mb-2">
        <h1 className="text-xl font-semibold text-white">Tags{loading && data && <span className="text-xs text-slate-500 font-normal ml-2">updating…</span>}</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {TIMEFRAMES.map(t => (
            <button key={t} onClick={() => setTf(t)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors ${tf === t ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {t}
            </button>
          ))}
        </div>
      </div>
      <p className="text-xs text-slate-500 mb-5">Per closed position, net of fees. A position counts toward every tag on any of its fills.</p>

      {loading && !data ? <Loading rows={4} /> : error && !data ? <ErrorState message={error} onRetry={reload} /> : !data?.length ? (
        <EmptyState title="No tagged positions closed in this period" subtitle="Add tags to trades in the Journal or All Trades." />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {data.map(t => (
            <div key={t.tag} className="bg-white/5 rounded-xl border border-white/10 p-4">
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-medium px-2.5 py-0.5 rounded-full" style={tagColor(t.tag)}>{t.tag}</span>
                <span className={`text-base font-semibold ${pnlColor(t.total_pnl)}`}>{signedUsd(t.total_pnl)}</span>
              </div>
              <div className="flex items-center gap-2 mb-1">
                <div className="flex-1 h-1.5 rounded-full bg-white/10 overflow-hidden">
                  <div className={`h-full ${winBarColor(t.win_rate)}`} style={{ width: `${t.win_rate}%` }} />
                </div>
                <span className="text-xs text-slate-300 w-10 text-right">{Math.round(t.win_rate)}%</span>
              </div>
              <p className="text-[11px] text-slate-500 mb-3">{t.count} positions · {t.wins}W / {t.losses}L</p>
              <div className="grid grid-cols-2 gap-y-1 text-xs">
                <span className="text-slate-500">Avg per position</span><span className={`text-right ${pnlColor(t.avg_pnl)}`}>{signedUsd(t.avg_pnl)}</span>
                <span className="text-slate-500">Avg win</span><span className="text-right text-emerald-400">{signedUsd(t.avg_win)}</span>
                <span className="text-slate-500">Avg loss</span><span className="text-right text-red-400">{signedUsd(t.avg_loss)}</span>
                <span className="text-slate-500">Best / worst</span>
                <span className="text-right text-slate-300">{signedUsd(t.best_trade)} / {signedUsd(t.worst_trade)}</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
