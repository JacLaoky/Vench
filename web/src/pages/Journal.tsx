import { useMemo, useState } from 'react'
import { Search, ChevronLeft, StickyNote } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell, ReferenceLine, LineChart, Line } from 'recharts'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { fmtR, pnlColor, rColor, signedUsd } from '../lib/format'
import TradeDetail from '../components/TradeDetail'
import DayDetail from '../components/DayDetail'
import CalendarView from '../components/CalendarView'
import MonthDetail from '../components/MonthDetail'
import { EmptyState, ErrorState, Loading } from '../components/PageState'
import type { JournalDay, JournalMonth, JournalResponse, Trade } from '../types'

type View = 'days' | 'calendar' | 'months' | 'trades'

function flatten(journal: JournalResponse | null): Trade[] {
  return (journal?.daily ?? []).flatMap(day => day.tickers.flatMap(t => t.trades))
}

function patchJournal(journal: JournalResponse, tradeId: string, patch: Partial<Trade>): JournalResponse {
  const target = flatten(journal).find(t => t.trade_id === tradeId)
  const samePosition = (t: Trade) => Boolean(target?.position_id && t.position_id === target.position_id && 'stop_price' in patch)
  return {
    ...journal,
    daily: journal.daily.map(day => ({
      ...day,
      tickers: day.tickers.map(tk => ({
        ...tk,
        trades: tk.trades.map(t =>
          t.trade_id === tradeId ? { ...t, ...patch }
          : samePosition(t) ? { ...t, stop_price: patch.stop_price ?? t.stop_price }   // stops belong to the position
          : t),
      })),
    })),
  }
}

const shortDate = (date: string) =>
  new Date(`${date}T12:00:00`).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })

function DayCard({ day, note, onOpen }: { day: JournalDay; note: string; onOpen: () => void }) {
  return (
    <button onClick={onOpen} className="w-full text-left p-3 sm:p-4 rounded-xl border bg-white/5 border-white/10 hover:border-white/20 transition-colors">
      <div className="flex justify-between items-start gap-2">
        <div>
          <p className="text-sm font-medium text-white">{shortDate(day.date)}</p>
          <p className="text-xs text-slate-500 mt-0.5">
            {day.trades} fills{day.closed ? ` · ${day.wins}W ${day.losses}L · ${day.winPct}` : ''} · fees ${day.comm_value.toFixed(2)}
          </p>
        </div>
        <span className={`text-base font-semibold ${pnlColor(day.pnl_value)}`}>{signedUsd(day.pnl_value)}</span>
      </div>
      <div className="flex gap-1 flex-wrap mt-2">
        {day.tickers.map(t => (
          <span key={t.name} className={`text-[11px] px-2 py-0.5 rounded-full ${t.win ? 'bg-emerald-500/15 text-emerald-300' : 'bg-red-500/15 text-red-300'}`}>
            {t.name}
          </span>
        ))}
      </div>
      {note.trim() ? (
        <p className="text-xs text-slate-400 mt-2 line-clamp-2 whitespace-pre-wrap"><StickyNote size={11} className="inline mr-1 text-violet-300" />{note}</p>
      ) : (
        <p className="text-xs text-slate-600 mt-2">+ Add day note</p>
      )}
    </button>
  )
}

function MonthCard({ month, onOpen }: { month: JournalMonth; onOpen: () => void }) {
  return (
    <button onClick={onOpen} className="w-full text-left p-4 rounded-xl border bg-white/5 border-white/10 hover:border-white/20 transition-colors">
      <div className="flex justify-between items-start">
        <div>
          <p className="text-sm font-medium text-white">{month.monthYear}</p>
          <p className="text-xs text-slate-500 mt-0.5">
            {month.closed} closed{month.win_rate !== null ? ` · ${Math.round(month.win_rate * 100)}% win` : ''} · avg win {month.avgGain}
          </p>
        </div>
        <span className={`text-base font-semibold ${pnlColor(month.profit_value)}`}>{signedUsd(month.profit_value)}</span>
      </div>
      <div className="h-12 mt-2 -mx-1">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={month.chart_data}>
            <Line type="monotone" dataKey="value" dot={false} strokeWidth={2} stroke={month.profit_value >= 0 ? '#34d399' : '#f87171'} isAnimationActive={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </button>
  )
}

const Tip = ({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-[#1a1d27] border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      <p className="text-violet-400">{signedUsd(payload[0].value)}</p>
    </div>
  )
}

export default function Journal() {
  const journal = useApi(() => api.getJournal(), [])
  const notesApi = useApi(() => api.getDailyNotes(), [])
  const [view, setView] = usePersistentState<View>('journal.view', 'days')
  const [query, setQuery] = useState('')
  const [tagFilter, setTagFilter] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [openDate, setOpenDate] = useState<string | null>(null)
  const [openMonth, setOpenMonth] = useState<JournalMonth | null>(null)

  const days = useMemo(() => journal.data?.daily ?? [], [journal.data])
  const months = useMemo(() => journal.data?.monthly ?? [], [journal.data])
  const notes = useMemo(() => notesApi.data ?? {}, [notesApi.data])
  const trades = useMemo(() => flatten(journal.data), [journal.data])
  const dayByDate = useMemo(() => new Map(days.map(d => [d.date, d])), [days])
  const selected = trades.find(t => t.trade_id === selectedId) ?? null

  const allTags = useMemo(() => [...new Set(trades.flatMap(t => t.tags ?? []))].sort(), [trades])
  const q = query.toLowerCase()
  const filteredTrades = useMemo(() => trades.filter(t =>
    (!q || t.ticker.toLowerCase().includes(q)) && (!tagFilter || t.tags?.includes(tagFilter))
  ), [trades, q, tagFilter])
  const filteredDays = useMemo(() => days.filter(d => !q || d.tickers.some(t => t.name.toLowerCase().includes(q))), [days, q])
  const monthBars = useMemo(() => [...months].reverse().map(m => ({ label: m.month_key, value: m.profit_value })), [months])

  const updateTrade = (tradeId: string, patch: Partial<Trade>) =>
    journal.setData(prev => prev && patchJournal(prev, tradeId, patch))
  const saveNoteLocally = (date: string, note: string) =>
    notesApi.setData(prev => ({ ...(prev ?? {}), [date]: note }))

  if (journal.loading && !journal.data) return <Loading rows={5} />
  if (journal.error && !journal.data) return <ErrorState message={journal.error} onRetry={journal.reload} />

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap mb-4">
        <h1 className="text-xl font-semibold text-white">Trade Journal</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {(['days', 'calendar', 'months', 'trades'] as const).map(v => (
            <button key={v} onClick={() => setView(v)}
              className={`px-3 py-1 rounded-md text-sm transition-colors capitalize ${view === v ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {v}
            </button>
          ))}
        </div>
      </div>

      {(view === 'days' || view === 'trades') && !(view === 'trades' && selected) && (
        <div className="flex gap-3 mb-4 flex-wrap">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-500" />
            <input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search ticker…"
              className="pl-8 pr-3 py-1.5 bg-white/5 border border-white/10 rounded-lg text-sm text-white placeholder-slate-600 focus:outline-none focus:border-violet-500 w-36" />
          </div>
          {view === 'trades' && allTags.length > 0 && (
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
      )}

      {view === 'days' && (
        filteredDays.length === 0 ? <EmptyState title="No days match" /> : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
            {filteredDays.map(day => (
              <DayCard key={day.date} day={day} note={notes[day.date] ?? ''} onOpen={() => setOpenDate(day.date)} />
            ))}
          </div>
        )
      )}

      {view === 'calendar' && <CalendarView days={days} notes={notes} onSelect={setOpenDate} />}

      {view === 'months' && (
        <div>
          <div className="bg-white/5 rounded-xl border border-white/10 p-4 mb-4">
            <h2 className="text-sm font-medium text-white mb-4">Realized P&L by month</h2>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={monthBars}>
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} width={44} />
                <Tooltip content={<Tip />} cursor={{ fill: 'rgba(255,255,255,0.04)' }} />
                <ReferenceLine y={0} stroke="#374151" />
                <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                  {monthBars.map((e, i) => <Cell key={i} fill={e.value >= 0 ? '#34d399' : '#f87171'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {months.map(m => <MonthCard key={m.month_key} month={m} onOpen={() => setOpenMonth(m)} />)}
          </div>
        </div>
      )}

      {view === 'trades' && (
        <div className="flex gap-4 md:h-[calc(100vh-11rem)]">
          <div className={`w-full md:w-72 shrink-0 overflow-y-auto space-y-2 md:pr-1 ${selected ? 'hidden md:block' : ''}`}>
            {filteredTrades.length === 0 && <EmptyState title="No trades match" />}
            {filteredTrades.map(t => {
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
                <TradeDetail trade={selected} onUpdate={patch => updateTrade(selected.trade_id, patch)} />
              </>
            )}
          </div>
        </div>
      )}

      {openDate && (
        <DayDetail date={openDate} day={dayByDate.get(openDate)} note={notes[openDate] ?? ''}
          onNoteSaved={note => saveNoteLocally(openDate, note)}
          onTradeUpdate={updateTrade} onClose={() => setOpenDate(null)} />
      )}
      {openMonth && <MonthDetail month={openMonth} onClose={() => setOpenMonth(null)} />}
    </div>
  )
}
