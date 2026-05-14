import { useEffect, useState, useMemo } from 'react'
import { api } from '../api'
import { Search } from 'lucide-react'
import JournalAI from '../components/JournalAI'
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, ReferenceLine
} from 'recharts'

interface Transaction { action: string; date: string; price: string; qty: string }
interface Trade {
  trade_id: string; position_id: string; ticker: string; trade_type: string
  pnl: number; pct: string; enter_time: string; exit_time: string
  holding_time: string; entry_price: number; price: number; qty: number
  note: string; tags: string[]; transactions: Transaction[]
  isProfit: boolean; month: string
}
interface MonthEntry {
  label: string; value: number; isProfit: boolean; trades: number
}

const Tip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-[#1a1d27] border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      <p className="text-violet-400">${payload[0]?.value?.toFixed(2)}</p>
    </div>
  )
}

export default function Journal() {
  const [trades, setTrades] = useState<Trade[]>([])
  const [monthly, setMonthly] = useState<MonthEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [selected, setSelected] = useState<Trade | null>(null)
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)
  const [view, setView] = useState<'daily' | 'monthly'>('daily')
  const [query, setQuery] = useState('')
  const [tagFilter, setTagFilter] = useState('')

  useEffect(() => {
    api.getJournal()
      .then(data => {
        const flat: Trade[] = []
        for (const day of data.daily ?? []) {
          for (const ticker of day.tickers ?? []) {
            for (const trade of ticker.trades ?? []) flat.push(trade)
          }
        }
        setTrades(flat)

        // Build monthly summary from monthly array
        const monthMap: Record<string, { pnl: number; trades: number }> = {}
        for (const day of data.daily ?? []) {
          const mo = day.date?.slice(0, 7) ?? ''
          if (!monthMap[mo]) monthMap[mo] = { pnl: 0, trades: 0 }
          for (const ticker of day.tickers ?? []) {
            for (const trade of ticker.trades ?? []) {
              monthMap[mo].pnl += trade.pnl
              monthMap[mo].trades += 1
            }
          }
        }
        setMonthly(
          Object.entries(monthMap)
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([label, { pnl, trades }]) => ({ label, value: pnl, isProfit: pnl >= 0, trades }))
        )
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  const allTags = useMemo(() => {
    const set = new Set<string>()
    trades.forEach(t => t.tags?.forEach(tag => set.add(tag)))
    return [...set].sort()
  }, [trades])

  const filtered = useMemo(() => {
    return trades.filter(t => {
      if (query && !t.ticker.toLowerCase().includes(query.toLowerCase())) return false
      if (tagFilter && !t.tags?.includes(tagFilter)) return false
      return true
    })
  }, [trades, query, tagFilter])

  function openTrade(t: Trade) { setSelected(t); setNote(t.note ?? '') }

  async function saveNote() {
    if (!selected) return
    setSaving(true)
    try {
      await api.saveNote(selected.trade_id, note)
      setTrades(prev => prev.map(t => t.trade_id === selected.trade_id ? { ...t, note } : t))
      setSelected(prev => prev ? { ...prev, note } : null)
    } finally { setSaving(false) }
  }

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>

  return (
    <>
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
        /* ── Monthly view ── */
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
                  <th className="text-right px-4 py-2">Trades</th>
                  <th className="text-right px-4 py-2">P&L</th>
                </tr>
              </thead>
              <tbody>
                {[...monthly].reverse().map(m => (
                  <tr key={m.label} className="border-b border-white/5">
                    <td className="px-4 py-2.5 text-slate-300">{m.label}</td>
                    <td className="text-right px-4 py-2.5 text-slate-400">{m.trades}</td>
                    <td className={`text-right px-4 py-2.5 font-medium ${m.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                      {m.isProfit ? '+' : '-'}${Math.abs(m.value).toFixed(2)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        /* ── Daily view ── */
        <div>
          {/* Filters */}
          <div className="flex gap-3 mb-4 flex-wrap">
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

          <div className="flex gap-4 h-[calc(100vh-11rem)]">
            {/* Trade list */}
            <div className="w-72 shrink-0 overflow-y-auto space-y-2 pr-1">
              {filtered.length === 0 && <p className="text-slate-500 text-sm">No trades match</p>}
              {filtered.map(t => (
                <div key={t.trade_id} onClick={() => openTrade(t)}
                  className={`p-3 rounded-xl border cursor-pointer transition-colors ${
                    selected?.trade_id === t.trade_id
                      ? 'bg-violet-600/20 border-violet-500/50'
                      : 'bg-white/5 border-white/10 hover:border-white/20'
                  }`}>
                  <div className="flex justify-between items-start">
                    <span className="font-medium text-white text-sm">{t.ticker}</span>
                    <span className={`text-sm font-medium ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                      {t.isProfit ? '+' : '-'}${Math.abs(t.pnl).toFixed(2)}
                    </span>
                  </div>
                  <div className="flex justify-between mt-1">
                    <span className="text-xs text-slate-500">{t.trade_type} · {t.holding_time}</span>
                    <span className={`text-xs ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>{t.pct}</span>
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
              ))}
            </div>

            {/* Detail panel */}
            <div className="flex-1 bg-white/5 rounded-xl border border-white/10 p-5 overflow-y-auto">
              {!selected ? (
                <p className="text-slate-500 text-sm">Select a trade to view details</p>
              ) : (
                <div>
                  <div className="flex items-center gap-3 mb-1">
                    <h2 className="text-lg font-semibold text-white">{selected.ticker}</h2>
                    <span className="text-xs px-2 py-0.5 rounded-full bg-white/10 text-slate-400">{selected.trade_type}</span>
                    <span className={`text-lg font-semibold ${selected.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                      {selected.isProfit ? '+' : '-'}${Math.abs(selected.pnl).toFixed(2)} ({selected.pct})
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 mb-4">{selected.enter_time} → {selected.exit_time} · {selected.holding_time}</p>

                  <div className="mb-5">
                    <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">Transactions</h3>
                    {selected.transactions?.map((tx, i) => (
                      <div key={i} className="flex justify-between text-sm py-1.5 border-b border-white/5">
                        <span className={tx.action.includes('BUY') ? 'text-emerald-400' : 'text-red-400'}>{tx.action}</span>
                        <span className="text-slate-300">{tx.qty} @ {tx.price}</span>
                        <span className="text-slate-500 text-xs">{tx.date}</span>
                      </div>
                    ))}
                  </div>

                  {selected.tags?.length > 0 && (
                    <div className="mb-5 flex gap-2 flex-wrap">
                      {selected.tags.map(tag => (
                        <span key={tag} className="text-xs px-2 py-0.5 bg-violet-600/20 text-violet-400 rounded-full">{tag}</span>
                      ))}
                    </div>
                  )}

                  <div>
                    <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">Note</h3>
                    <textarea value={note} onChange={e => setNote(e.target.value)} rows={5}
                      placeholder="Add your trade notes here…"
                      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 resize-none focus:outline-none focus:border-violet-500" />
                    <button onClick={saveNote} disabled={saving}
                      className="mt-2 px-4 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-sm rounded-lg disabled:opacity-50 transition-colors">
                      {saving ? 'Saving…' : 'Save'}
                    </button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
    <JournalAI />
  </>
  )
}
