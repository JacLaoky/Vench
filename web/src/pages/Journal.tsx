import { useMemo, useState } from 'react'
import { Search, ChevronLeft } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, ReferenceLine } from 'recharts'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd } from '../lib/format'
import TradeDetail from '../components/TradeDetail'
import type { Trade } from '../types'

interface MonthEntry { label: string; value: number; isProfit: boolean; trades: number }

const Tip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-[#1a1d27] border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      <p className="text-violet-400">${payload[0]?.value?.toFixed(2)}</p>
    </div>
  )
}

interface JournalResponse { daily?: { tickers?: { trades?: Trade[] }[] }[] }

function flatten(journal: JournalResponse): Trade[] {
  const flat: Trade[] = []
  for (const day of journal?.daily ?? []) {
    for (const ticker of day.tickers ?? []) {
      for (const trade of ticker.trades ?? []) flat.push(trade)
    }
  }
  return flat
}

export default function Journal() {
  const { data: trades, setData: setTrades, error, loading } = useApi(
    () => api.getJournal().then(flatten), [],
  )
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [view, setView] = useState<'daily' | 'monthly'>('daily')
  const [query, setQuery] = useState('')
  const [tagFilter, setTagFilter] = useState('')

  const list = useMemo(() => trades ?? [], [trades])
  const selected = list.find(t => t.trade_id === selectedId) ?? null

  const monthly = useMemo<MonthEntry[]>(() => {
    const map: Record<string, { pnl: number; trades: number }> = {}
    for (const t of list) {
      const mo = t.exit_date.slice(0, 7)
      map[mo] ??= { pnl: 0, trades: 0 }
      map[mo].pnl += t.net_pnl ?? t.pnl
      map[mo].trades += 1
    }
    return Object.entries(map).sort(([a], [b]) => a.localeCompare(b))
      .map(([label, { pnl, trades }]) => ({ label, value: pnl, isProfit: pnl >= 0, trades }))
  }, [list])

  const allTags = useMemo(() => [...new Set(list.flatMap(t => t.tags ?? []))].sort(), [list])

  const filtered = useMemo(() => list.filter(t =>
    (!query || t.ticker.toLowerCase().includes(query.toLowerCase())) && (!tagFilter || t.tags?.includes(tagFilter))
  ), [list, query, tagFilter])

  function update(tradeId: string, patch: Partial<Trade>) {
    setTrades(prev => prev && prev.map(t => {
      if (t.trade_id === tradeId) return { ...t, ...patch }
      // stops belong to the position: every exit card of that position shows the new values
      const sel = prev.find(x => x.trade_id === tradeId)
      if (sel?.position_id && t.position_id === sel.position_id && 'stop_price' in patch) {
        return { ...t, stop_price: patch.stop_price ?? t.stop_price }
      }
      return t
    }))
  }

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold text-white">Trade Journal</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {(['daily', 'monthly'] as const).map(v => (
            <button key={v} onClick={() => setView(v)}
              className={`px-3 py-1 rounded-md text-sm transition-colors capitalize ${view === v ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {v}
            </button>
          ))}
        </div>
      </div>

      {view === 'monthly' ? (
        <div>
          <div className="bg-white/5 rounded-xl border border-white/10 p-4 mb-4">
            <h2 className="text-sm font-medium text-white mb-4">Monthly P&L</h2>
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={monthly}>
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="#374151" />
                <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                  {monthly.map((e, i) => <Cell key={i} fill={e.isProfit ? '#34d399' : '#f87171'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="bg-white/5 rounded-xl border border-white/10 overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs text-slate-500 border-b border-white/10">
                  <th className="text-left px-4 py-2">Month</th>
                  <th className="text-right px-4 py-2">Exits</th>
                  <th className="text-right px-4 py-2">P&L</th>
                </tr>
              </thead>
              <tbody>
                {[...monthly].reverse().map(m => (
                  <tr key={m.label} className="border-b border-white/5">
                    <td className="px-4 py-2.5 text-slate-300">{m.label}</td>
                    <td className="text-right px-4 py-2.5 text-slate-400">{m.trades}</td>
                    <td className={`text-right px-4 py-2.5 font-medium ${pnlColor(m.value)}`}>{signedUsd(m.value)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div>
          <div className={`flex gap-3 mb-4 flex-wrap ${selected ? 'hidden md:flex' : ''}`}>
            <div className="relative">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
              <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search ticker…"
                className="pl-8 pr-3 py-1.5 bg-white/5 border border-white/10 rounded-lg text-sm text-white placeholder-slate-600 focus:outline-none focus:border-violet-500 w-36" />
            </div>
            {allTags.length > 0 && (
              <div className="flex gap-1 flex-wrap">
                <button onClick={() => setTagFilter('')}
                  className={`px-2.5 py-1 rounded-full text-xs transition-colors ${!tagFilter ? 'bg-violet-600 text-white' : 'bg-white/5 text-slate-400 hover:text-white'}`}>
                  All
                </button>
                {allTags.map(tag => (
                  <button key={tag} onClick={() => setTagFilter(tag === tagFilter ? '' : tag)}
                    className={`px-2.5 py-1 rounded-full text-xs transition-colors ${tagFilter === tag ? 'bg-violet-600 text-white' : 'bg-white/5 text-slate-400 hover:text-white'}`}>
                    {tag}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="flex gap-4 md:h-[calc(100vh-11rem)]">
            {/* Trade list (on phones it gives way to the detail view) */}
            <div className={`w-full md:w-72 shrink-0 overflow-y-auto space-y-2 md:pr-1 ${selected ? 'hidden md:block' : ''}`}>
              {filtered.length === 0 && <p className="text-slate-500 text-sm">No trades match</p>}
              {filtered.map(t => {
                const net = t.net_pnl ?? t.pnl
                return (
                  <div key={t.trade_id} onClick={() => setSelectedId(t.trade_id)}
                    className={`p-3 rounded-xl border cursor-pointer transition-colors ${
                      selectedId === t.trade_id ? 'bg-violet-600/20 border-violet-500/50' : 'bg-white/5 border-white/10 hover:border-white/20'
                    }`}>
                    <div className="flex justify-between items-start">
                      <span className="font-medium text-white text-sm">{t.ticker}</span>
                      <span className={`text-sm font-medium ${pnlColor(net)}`}>{signedUsd(net)}</span>
                    </div>
                    <div className="flex justify-between mt-1">
                      <span className="text-xs text-slate-500">{t.trade_type} · {t.holding_time}</span>
                      {t.r_multiple !== null
                        ? <span className={`text-xs ${rColor(t.r_multiple)}`}>{fmtR(t.r_multiple)}</span>
                        : <span className={`text-xs ${pnlColor(net)}`}>{t.pct}</span>}
                    </div>
                    <div className="flex justify-between mt-1">
                      <span className="text-xs text-slate-600">{t.exit_time}</span>
                      {t.tags?.length > 0 && (
                        <div className="flex gap-1">
                          {t.tags.slice(0, 2).map(tag => (
                            <span key={tag} className="text-xs px-1.5 bg-violet-600/20 text-violet-400 rounded-full">{tag}</span>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>

            <div className={`flex-1 min-w-0 bg-white/5 rounded-xl border border-white/10 p-4 sm:p-5 md:overflow-y-auto ${selected ? '' : 'hidden md:block'}`}>
              {!selected ? (
                <p className="text-slate-500 text-sm">Select a trade to view details</p>
              ) : (
                <>
                  <button onClick={() => setSelectedId(null)} className="md:hidden flex items-center gap-1 text-sm text-slate-400 mb-4">
                    <ChevronLeft size={16} /> Trades
                  </button>
                  <TradeDetail trade={selected} onUpdate={patch => update(selected.trade_id, patch)} />
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
