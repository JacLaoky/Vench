import { useEffect, useState, useMemo } from 'react'
import { api } from '../api'
import { Search } from 'lucide-react'

interface Trade {
  trade_id: string; ticker: string; trade_type: string
  pnl: number; pct: string; isProfit: boolean
  enter_time: string; exit_time: string; holding_time: string
  entry_price: number; price: number; qty: number
  note: string; tags: string[]
}

type SortKey = 'exit_time' | 'pnl' | 'ticker'
type Filter = 'all' | 'win' | 'loss' | 'long' | 'short'

export default function AllTrades() {
  const [trades, setTrades] = useState<Trade[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [query, setQuery] = useState('')
  const [filter, setFilter] = useState<Filter>('all')
  const [sort, setSort] = useState<SortKey>('exit_time')
  const [sortAsc, setSortAsc] = useState(false)

  useEffect(() => {
    api.getAllTrades()
      .then(d => setTrades(d.data ?? []))
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  const filtered = useMemo(() => {
    let list = trades
    if (query) list = list.filter(t => t.ticker.toLowerCase().includes(query.toLowerCase()))
    if (filter === 'win') list = list.filter(t => t.isProfit)
    if (filter === 'loss') list = list.filter(t => !t.isProfit)
    if (filter === 'long') list = list.filter(t => t.trade_type === 'LONG')
    if (filter === 'short') list = list.filter(t => t.trade_type === 'SHORT')
    return [...list].sort((a, b) => {
      let cmp = 0
      if (sort === 'pnl') cmp = a.pnl - b.pnl
      else if (sort === 'ticker') cmp = a.ticker.localeCompare(b.ticker)
      else cmp = a.exit_time.localeCompare(b.exit_time)
      return sortAsc ? cmp : -cmp
    })
  }, [trades, query, filter, sort, sortAsc])

  function toggleSort(key: SortKey) {
    if (sort === key) setSortAsc(p => !p)
    else { setSort(key); setSortAsc(false) }
  }

  const SortBtn = ({ k, label }: { k: SortKey; label: string }) => (
    <button onClick={() => toggleSort(k)}
      className={`px-2 py-0.5 rounded text-xs transition-colors ${sort === k ? 'text-violet-400' : 'text-slate-500 hover:text-slate-300'}`}>
      {label}{sort === k ? (sortAsc ? ' ↑' : ' ↓') : ''}
    </button>
  )

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold text-white">All Trades <span className="text-slate-500 text-sm font-normal ml-1">({filtered.length})</span></h1>
      </div>

      {/* Controls */}
      <div className="flex flex-wrap gap-3 mb-4">
        <div className="relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
          <input
            value={query} onChange={e => setQuery(e.target.value)}
            placeholder="Search ticker…"
            className="pl-8 pr-3 py-1.5 bg-white/5 border border-white/10 rounded-lg text-sm text-white placeholder-slate-600 focus:outline-none focus:border-violet-500 w-40"
          />
        </div>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {(['all', 'win', 'loss', 'long', 'short'] as Filter[]).map(f => (
            <button key={f} onClick={() => setFilter(f)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors capitalize ${filter === f ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {f}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-1 text-xs text-slate-500">
          Sort: <SortBtn k="exit_time" label="Date" /> <SortBtn k="pnl" label="P&L" /> <SortBtn k="ticker" label="Ticker" />
        </div>
      </div>

      {/* Table */}
      <div className="bg-white/5 rounded-xl border border-white/10 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-xs text-slate-500 border-b border-white/10">
                <th className="text-left px-4 py-2">Ticker</th>
                <th className="text-left px-4 py-2">Type</th>
                <th className="text-right px-4 py-2">Entry</th>
                <th className="text-right px-4 py-2">Exit</th>
                <th className="text-right px-4 py-2">Qty</th>
                <th className="text-right px-4 py-2">P&L</th>
                <th className="text-right px-4 py-2">%</th>
                <th className="text-right px-4 py-2">Held</th>
                <th className="text-left px-4 py-2">Tags</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map(t => (
                <tr key={t.trade_id} className="border-b border-white/5 hover:bg-white/5 transition-colors">
                  <td className="px-4 py-2.5 font-medium text-white max-w-[120px]">
                    <span className="block truncate" title={t.ticker}>{t.ticker}</span>
                  </td>
                  <td className="px-4 py-2.5">
                    <span className={`text-xs px-1.5 py-0.5 rounded ${t.trade_type === 'LONG' ? 'bg-emerald-600/20 text-emerald-400' : 'bg-red-600/20 text-red-400'}`}>
                      {t.trade_type}
                    </span>
                  </td>
                  <td className="text-right px-4 py-2.5 text-slate-300">${t.entry_price.toFixed(2)}</td>
                  <td className="text-right px-4 py-2.5 text-slate-300">${t.price.toFixed(2)}</td>
                  <td className="text-right px-4 py-2.5 text-slate-400">{t.qty}</td>
                  <td className={`text-right px-4 py-2.5 font-medium ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                    {t.isProfit ? '+' : ''}${t.pnl.toFixed(2)}
                  </td>
                  <td className={`text-right px-4 py-2.5 text-xs ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>{t.pct}</td>
                  <td className="text-right px-4 py-2.5 text-slate-500 text-xs">{t.holding_time}</td>
                  <td className="px-4 py-2.5">
                    <div className="flex gap-1 flex-wrap">
                      {t.tags?.map(tag => (
                        <span key={tag} className="text-xs px-1.5 py-0.5 bg-violet-600/20 text-violet-400 rounded-full">{tag}</span>
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
    </div>
  )
}
