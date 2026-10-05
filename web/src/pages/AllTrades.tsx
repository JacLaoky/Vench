import { useMemo, useState } from 'react'
import { Search, X } from 'lucide-react'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd } from '../lib/format'
import TradeDetail from '../components/TradeDetail'
import { ErrorState, Loading } from '../components/PageState'
import { tagColor } from '../lib/tags'
import type { Trade } from '../types'

type SortKey = 'exit_time' | 'pnl' | 'r' | 'ticker'
type Filter = 'all' | 'win' | 'loss' | 'long' | 'short' | 'with R'

const net = (t: Trade) => t.net_pnl ?? t.pnl

function SortBtn({ active, asc, label, onClick }: { active: boolean; asc: boolean; label: string; onClick: () => void }) {
  return (
    <button onClick={onClick}
      className={`px-2 py-0.5 rounded text-xs transition-colors ${active ? 'text-violet-400' : 'text-slate-500 hover:text-slate-300'}`}>
      {label}{active ? (asc ? ' ↑' : ' ↓') : ''}
    </button>
  )
}

export default function AllTrades() {
  const { data, setData, error, loading, reload } = useApi(() => api.getAllTrades().then(d => d.data ?? []), [])
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<Filter>('all')
  const [tag, setTag] = useState('')
  const [sort, setSort] = useState<SortKey>('exit_time')
  const [sortAsc, setSortAsc] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const trades = useMemo(() => data ?? [], [data])
  const selected = trades.find(t => t.trade_id === selectedId) ?? null
  const allTags = useMemo(() => [...new Set(trades.flatMap(t => t.tags ?? []))].sort(), [trades])

  const filtered = useMemo(() => {
    let list = trades
    if (query) list = list.filter(t => t.ticker.toLowerCase().includes(query.toLowerCase()))
    if (tag) list = list.filter(t => t.tags?.includes(tag))
    if (filter === 'win') list = list.filter(t => net(t) >= 0)
    if (filter === 'loss') list = list.filter(t => net(t) < 0)
    if (filter === 'long') list = list.filter(t => t.trade_type === 'LONG')
    if (filter === 'short') list = list.filter(t => t.trade_type === 'SHORT')
    if (filter === 'with R') list = list.filter(t => t.r_multiple !== null)
    return [...list].sort((a, b) => {
      const cmp =
        sort === 'pnl' ? net(a) - net(b)
        : sort === 'r' ? (a.r_multiple ?? -Infinity) - (b.r_multiple ?? -Infinity)
        : sort === 'ticker' ? a.ticker.localeCompare(b.ticker)
        : a.exit_date.localeCompare(b.exit_date)
      return sortAsc ? cmp : -cmp
    })
  }, [trades, query, tag, filter, sort, sortAsc])

  function toggleSort(key: SortKey) {
    if (sort === key) setSortAsc(p => !p)
    else { setSort(key); setSortAsc(false) }
  }

  if (loading && !data) return <Loading rows={6} />
  if (error && !data) return <ErrorState message={error} onRetry={reload} />

  return (
    <div>
      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-white mb-4">
        All Trades <span className="text-slate-500 text-sm font-normal ml-1">({filtered.length} exits)</span>
      </h1>

      <div className="flex flex-wrap gap-3 mb-4">
        <div className="relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
          <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search ticker…"
            className="pl-8 pr-3 py-1.5 field text-sm text-white w-40" />
        </div>
        <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5 flex-wrap">
          {(['all', 'win', 'loss', 'long', 'short', 'with R'] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors capitalize ${filter === f ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {f}
            </button>
          ))}
        </div>
        {allTags.length > 0 && (
          <select value={tag} onChange={e => setTag(e.target.value)}
            className="field text-xs text-slate-300 px-2 py-1.5">
            <option value="">All tags</option>
            {allTags.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
        )}
        <div className="flex items-center gap-1 text-xs text-slate-500">
          Sort: {([['exit_time', 'Date'], ['pnl', 'P&L'], ['r', 'R'], ['ticker', 'Ticker']] as [SortKey, string][]).map(([k, label]) => (
            <SortBtn key={k} active={sort === k} asc={sortAsc} label={label} onClick={() => toggleSort(k)} />
          ))}
        </div>
      </div>

      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="label-caps border-b border-line bg-white/[0.02]">
                <th className="text-left px-4 py-2">Ticker</th>
                <th className="text-left px-4 py-2 hidden sm:table-cell">Type</th>
                <th className="text-right px-4 py-2 hidden md:table-cell">Entry</th>
                <th className="text-right px-4 py-2 hidden md:table-cell">Exit</th>
                <th className="text-right px-4 py-2 hidden md:table-cell">Qty</th>
                <th className="text-right px-4 py-2">P&L</th>
                <th className="text-right px-4 py-2">R</th>
                <th className="text-right px-4 py-2 hidden sm:table-cell">Held</th>
                <th className="text-left px-4 py-2 hidden lg:table-cell">Tags</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(t => (
                <tr key={t.trade_id} onClick={() => setSelectedId(t.trade_id)}
                  className="border-b border-line hover:bg-white/[0.03] transition-colors cursor-pointer">
                  <td className="px-4 py-2.5 max-w-[140px]">
                    <span className="block truncate font-medium text-white" title={t.ticker}>{t.ticker}</span>
                    <span className="block text-[11px] text-slate-600">{t.exit_date}{t.position_status === 'open' ? ' · partial' : ''}</span>
                  </td>
                  <td className="px-4 py-2.5 hidden sm:table-cell">
                    <span className={`text-xs px-1.5 py-0.5 rounded ${t.trade_type === 'LONG' ? 'bg-emerald-600/20 text-emerald-400' : 'bg-red-600/20 text-red-400'}`}>
                      {t.trade_type}
                    </span>
                  </td>
                  <td className="text-right px-4 py-2.5 text-slate-300 hidden md:table-cell">${t.entry_price.toFixed(2)}</td>
                  <td className="text-right px-4 py-2.5 text-slate-300 hidden md:table-cell">${t.price.toFixed(2)}</td>
                  <td className="text-right px-4 py-2.5 text-slate-400 hidden md:table-cell">{t.qty}</td>
                  <td className={`text-right px-4 py-2.5 font-medium ${pnlColor(net(t))}`}>
                    {signedUsd(net(t))}
                    <span className="block text-[11px] opacity-90">{t.pct}</span>
                  </td>
                  <td className={`text-right px-4 py-2.5 font-medium ${rColor(t.r_multiple)}`}>{fmtR(t.r_multiple)}</td>
                  <td className="text-right px-4 py-2.5 text-slate-500 text-xs hidden sm:table-cell">{t.holding_time}</td>
                  <td className="px-4 py-2.5 hidden lg:table-cell">
                    <div className="flex gap-1 flex-wrap">
                      {t.tags?.map(tg => (
                        <span key={tg} className="text-xs px-1.5 py-0.5 rounded-full" style={tagColor(tg)}>{tg}</span>
                      ))}
                    </div>
                  </td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr><td colSpan={9} className="text-center py-8 text-slate-500 text-sm">No trades match</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {selected && (
        <div className="fixed inset-0 z-50 flex justify-end">
          <div className="absolute inset-0 bg-black/50 backdrop-blur-[2px]" onClick={() => setSelectedId(null)} />
          <div className="relative w-full sm:max-w-xl bg-surface sm:border-l border-line h-full overflow-y-auto p-5 pt-[calc(1.25rem+env(safe-area-inset-top))] pb-[calc(1.5rem+env(safe-area-inset-bottom))]">
            <button onClick={() => setSelectedId(null)} className="absolute top-[calc(1rem+env(safe-area-inset-top))] right-4 text-slate-400 hover:text-white" aria-label="Close">
              <X size={18} />
            </button>
            <TradeDetail trade={selected}
              onUpdate={patch => setData(prev => prev && prev.map(t => t.trade_id === selected.trade_id ? { ...t, ...patch } : t))} />
          </div>
        </div>
      )}
    </div>
  )
}
