import { useEffect, useState, useCallback } from 'react'
import { X } from 'lucide-react'
import { api } from '../api'
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip,
  ResponsiveContainer, Cell, ReferenceLine
} from 'recharts'

interface Summary {
  trade_count: number; win_rate: string; avg_win: number; avg_loss: number
  win_loss_ratio: number; profit_factor: number; expectancy: number
  max_drawdown: number; sharpe_ratio: number; sortino_ratio: number
  kelly_pct: number; current_streak: number; current_streak_type: string
  max_win_streak: number; max_loss_streak: number; total_pnl: number
}
interface PerfData {
  summary: Summary
  monthly_bars: { label: string; value: number; isProfit: boolean }[]
  dow_stats: { label: string; pnl: number; trades: number; win_rate: number; isProfit: boolean }[]
  drawdown_curve: { date: string; drawdown: number; equity: number }[]
  deep_stats: {
    gain_loss: { avg_usd: { won: string; lost: string; all: string }; win_rate: string; trades: { won: string; lost: string } }
    best_worst: { largest_usd: { won: string; lost: string }; largest_pct: { won: string; lost: string } }
    symbols_by_amount: { symbol: string; pnl_raw: number; isProfit: boolean; trades: { all: string } }[]
  }
}

const TIMEFRAMES = ['1W', '1M', '3M', '1Y', 'YTD', 'AT'] as const

function MetricCard({ label, value, sub, color }: { label: string; value: string; sub?: string; color?: string }) {
  return (
    <div className="bg-white/5 rounded-xl p-4 border border-white/10">
      <p className="text-xs text-slate-500 mb-1">{label}</p>
      <p className={`text-lg font-semibold ${color ?? 'text-white'}`}>{value}</p>
      {sub && <p className="text-xs text-slate-500 mt-0.5">{sub}</p>}
    </div>
  )
}

const Tip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-[#1a1d27] border border-white/10 rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.name} style={{ color: p.color ?? '#a78bfa' }}>
          {p.name}: {typeof p.value === 'number' ? `$${p.value.toFixed(2)}` : p.value}
        </p>
      ))}
    </div>
  )
}

interface SymbolTrade {
  trade_id: string; ticker: string; trade_type: string
  pnl: number; pct: string; isProfit: boolean
  enter_time: string; exit_time: string; holding_time: string
  entry_price: number; price: number; qty: number; tags: string[]
}

interface SymbolSummary {
  symbol: string; pnl_raw: number; isProfit: boolean; trades: { all: string }
}

function SymbolPanel({
  symbol, allTrades, onClose
}: {
  symbol: SymbolSummary
  allTrades: SymbolTrade[]
  onClose: () => void
}) {
  const trades = allTrades.filter(t => t.ticker === symbol.symbol)
  const wins = trades.filter(t => t.isProfit).length
  const winRate = trades.length ? Math.round((wins / trades.length) * 100) : 0
  const maxPnl = Math.max(...trades.map(t => Math.abs(t.pnl)), 1)

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      {/* backdrop */}
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />

      {/* panel */}
      <div className="relative w-full max-w-md bg-[#13151f] border-l border-white/10 h-full flex flex-col shadow-2xl animate-in slide-in-from-right duration-200">
        {/* header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/10">
          <div>
            <h2 className="text-lg font-semibold text-white">{symbol.symbol}</h2>
            <p className="text-xs text-slate-500">{symbol.trades.all} trades</p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white transition-colors">
            <X size={18} />
          </button>
        </div>

        {/* summary strip */}
        <div className="grid grid-cols-3 gap-px bg-white/10 border-b border-white/10">
          {[
            { label: 'Total P&L', value: `${symbol.isProfit ? '+' : ''}$${symbol.pnl_raw.toFixed(2)}`, color: symbol.isProfit ? 'text-emerald-400' : 'text-red-400' },
            { label: 'Win Rate', value: `${winRate}%`, color: winRate >= 50 ? 'text-emerald-400' : 'text-red-400' },
            { label: 'W / L', value: `${wins} / ${trades.length - wins}`, color: 'text-white' },
          ].map(item => (
            <div key={item.label} className="bg-[#13151f] px-4 py-3 text-center">
              <p className="text-xs text-slate-500 mb-0.5">{item.label}</p>
              <p className={`text-sm font-semibold ${item.color}`}>{item.value}</p>
            </div>
          ))}
        </div>

        {/* trade list */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
          {trades.length === 0 && <p className="text-slate-500 text-sm">No trades found</p>}
          {trades.map(t => (
            <div key={t.trade_id} className="bg-white/5 rounded-xl border border-white/10 p-4">
              <div className="flex justify-between items-start mb-2">
                <span className={`text-xs px-1.5 py-0.5 rounded ${t.trade_type === 'LONG' ? 'bg-emerald-600/20 text-emerald-400' : 'bg-red-600/20 text-red-400'}`}>
                  {t.trade_type}
                </span>
                <span className={`font-semibold ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                  {t.isProfit ? '+' : ''}${t.pnl.toFixed(2)}
                  <span className="text-xs ml-1 opacity-70">({t.pct})</span>
                </span>
              </div>

              {/* mini bar */}
              <div className="w-full bg-white/5 rounded-full h-1.5 mb-3 overflow-hidden">
                <div
                  className={`h-full rounded-full ${t.isProfit ? 'bg-emerald-400' : 'bg-red-400'}`}
                  style={{ width: `${Math.min(100, (Math.abs(t.pnl) / maxPnl) * 100)}%` }}
                />
              </div>

              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-slate-500">
                <span>Entry <span className="text-slate-300">${t.entry_price.toFixed(2)}</span></span>
                <span>Exit <span className="text-slate-300">${t.price.toFixed(2)}</span></span>
                <span>Qty <span className="text-slate-300">{t.qty}</span></span>
                <span>Held <span className="text-slate-300">{t.holding_time}</span></span>
              </div>
              <p className="text-xs text-slate-600 mt-2">{t.enter_time} → {t.exit_time}</p>

              {t.tags?.length > 0 && (
                <div className="flex gap-1 mt-2 flex-wrap">
                  {t.tags.map(tag => (
                    <span key={tag} className="text-xs px-1.5 py-0.5 bg-violet-600/20 text-violet-400 rounded-full">{tag}</span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function SymbolRanking({
  symbols, onSelect
}: {
  symbols: SymbolSummary[]
  onSelect: (s: SymbolSummary) => void
}) {
  const [mode, setMode] = useState<'winners' | 'losers'>('winners')

  const list = [...symbols]
    .filter(s => mode === 'winners' ? s.isProfit : !s.isProfit)
    .sort((a, b) => mode === 'winners' ? b.pnl_raw - a.pnl_raw : a.pnl_raw - b.pnl_raw)
    .slice(0, 10)

  const maxAbs = Math.max(...list.map(s => Math.abs(s.pnl_raw)), 1)

  return (
    <div className="bg-white/5 rounded-xl border border-white/10 p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-medium text-white">Top Symbols</h2>
        <div className="flex gap-1 bg-white/5 rounded-lg p-0.5">
          <button onClick={() => setMode('winners')}
            className={`px-2.5 py-1 rounded-md text-xs transition-colors ${mode === 'winners' ? 'bg-emerald-600 text-white' : 'text-slate-400 hover:text-white'}`}>
            Winners
          </button>
          <button onClick={() => setMode('losers')}
            className={`px-2.5 py-1 rounded-md text-xs transition-colors ${mode === 'losers' ? 'bg-red-600 text-white' : 'text-slate-400 hover:text-white'}`}>
            Losers
          </button>
        </div>
      </div>

      {list.length === 0 ? (
        <p className="text-slate-500 text-sm py-2">No {mode} in this period</p>
      ) : (
        <div className="space-y-2">
          {list.map((s, i) => (
            <button key={s.symbol} onClick={() => onSelect(s)}
              className="flex items-center gap-3 w-full group hover:bg-white/5 rounded-lg px-2 py-1 -mx-2 transition-colors">
              <span className="text-xs text-slate-600 w-4 shrink-0 text-left">{i + 1}</span>
              <span className="text-sm text-slate-300 w-24 shrink-0 text-left truncate group-hover:text-white transition-colors" title={s.symbol}>
                {s.symbol}
              </span>
              <div className="flex-1 bg-white/5 rounded-full h-2 overflow-hidden">
                <div
                  className={`h-full rounded-full ${s.isProfit ? 'bg-emerald-400' : 'bg-red-400'}`}
                  style={{ width: `${(Math.abs(s.pnl_raw) / maxAbs) * 100}%` }}
                />
              </div>
              <span className={`text-sm font-medium w-20 text-right ${s.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                {s.isProfit ? '+' : ''}${s.pnl_raw.toFixed(2)}
              </span>
              <span className="text-xs text-slate-500 w-10 text-right">{s.trades.all}x</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

export default function Performance() {
  const [data, setData] = useState<PerfData | null>(null)
  const [tf, setTf] = useState('AT')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [selectedSymbol, setSelectedSymbol] = useState<SymbolSummary | null>(null)
  const [allTrades, setAllTrades] = useState<SymbolTrade[]>([])

  useEffect(() => {
    setLoading(true)
    Promise.all([api.getPerformance(tf), api.getAllTrades()])
      .then(([perf, trades]) => {
        setData(perf)
        setAllTrades(trades.data ?? [])
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [tf])

  const openSymbol = useCallback((s: SymbolSummary) => setSelectedSymbol(s), [])

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>
  if (!data) return null

  const s = data.summary
  const winPct = parseFloat(s.win_rate)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-semibold text-white">Performance</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {TIMEFRAMES.map(t => (
            <button key={t} onClick={() => setTf(t)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors ${tf === t ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {t}
            </button>
          ))}
        </div>
      </div>

      {/* KPI grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <MetricCard label="Total P&L" value={`${s.total_pnl >= 0 ? '+' : ''}$${s.total_pnl.toFixed(2)}`} color={s.total_pnl >= 0 ? 'text-emerald-400' : 'text-red-400'} />
        <MetricCard label="Win Rate" value={s.win_rate} color={winPct >= 50 ? 'text-emerald-400' : 'text-red-400'} sub={`${data.deep_stats.gain_loss.trades.won}W / ${data.deep_stats.gain_loss.trades.lost}L`} />
        <MetricCard label="Profit Factor" value={String(s.profit_factor)} color={s.profit_factor >= 1 ? 'text-emerald-400' : 'text-red-400'} />
        <MetricCard label="Expectancy" value={`$${s.expectancy.toFixed(2)}`} color={s.expectancy >= 0 ? 'text-emerald-400' : 'text-red-400'} />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <MetricCard label="Avg Win" value={`$${s.avg_win.toFixed(2)}`} color="text-emerald-400" sub={data.deep_stats.best_worst.largest_usd.won} />
        <MetricCard label="Avg Loss" value={`-$${s.avg_loss.toFixed(2)}`} color="text-red-400" sub={data.deep_stats.best_worst.largest_usd.lost} />
        <MetricCard label="Max Drawdown" value={`$${Math.abs(s.max_drawdown).toFixed(2)}`} color="text-red-400" />
        <MetricCard label="Kelly %" value={`${s.kelly_pct.toFixed(1)}%`} />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <MetricCard label="Sharpe Ratio" value={s.sharpe_ratio.toFixed(2)} color={s.sharpe_ratio >= 1 ? 'text-emerald-400' : 'text-slate-300'} />
        <MetricCard label="Sortino Ratio" value={s.sortino_ratio.toFixed(2)} color={s.sortino_ratio >= 1 ? 'text-emerald-400' : 'text-slate-300'} />
        <MetricCard label="Win/Loss Ratio" value={s.win_loss_ratio.toFixed(2)} />
        <MetricCard
          label="Current Streak"
          value={`${s.current_streak}${s.current_streak_type}`}
          color={s.current_streak_type === 'W' ? 'text-emerald-400' : 'text-red-400'}
          sub={`Best W: ${s.max_win_streak}  Best L: ${s.max_loss_streak}`}
        />
      </div>

      {/* Charts row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* Drawdown curve */}
        {data.drawdown_curve?.length > 0 && (
          <div className="bg-white/5 rounded-xl border border-white/10 p-4">
            <h2 className="text-sm font-medium text-white mb-4">Drawdown Curve</h2>
            <ResponsiveContainer width="100%" height={180}>
              <AreaChart data={data.drawdown_curve}>
                <defs>
                  <linearGradient id="ddGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#f87171" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#f87171" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="#374151" />
                <Area type="monotone" dataKey="drawdown" stroke="#f87171" fill="url(#ddGrad)" strokeWidth={2} name="Drawdown" dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Monthly bars */}
        {data.monthly_bars?.length > 0 && (
          <div className="bg-white/5 rounded-xl border border-white/10 p-4">
            <h2 className="text-sm font-medium text-white mb-4">Monthly P&L</h2>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={data.monthly_bars}>
                <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="#374151" />
                <Bar dataKey="value" radius={[4, 4, 0, 0]} name="P&L">
                  {data.monthly_bars.map((e, i) => <Cell key={i} fill={e.isProfit ? '#34d399' : '#f87171'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* DOW stats */}
        {data.dow_stats?.length > 0 && (
          <div className="bg-white/5 rounded-xl border border-white/10 p-4">
            <h2 className="text-sm font-medium text-white mb-4">Day of Week</h2>
            <ResponsiveContainer width="100%" height={160}>
              <BarChart data={data.dow_stats}>
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#64748b' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="#374151" />
                <Bar dataKey="pnl" radius={[4, 4, 0, 0]} name="P&L">
                  {data.dow_stats.map((e, i) => <Cell key={i} fill={e.isProfit ? '#34d399' : '#f87171'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* P&L by Symbol */}
        {data.deep_stats.symbols_by_amount?.length > 0 && (
          <SymbolRanking symbols={data.deep_stats.symbols_by_amount} onSelect={openSymbol} />
        )}
      </div>

      {selectedSymbol && (
        <SymbolPanel
          symbol={selectedSymbol}
          allTrades={allTrades}
          onClose={() => setSelectedSymbol(null)}
        />
      )}
    </div>
  )
}
