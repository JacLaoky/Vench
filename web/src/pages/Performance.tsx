import { useState, useCallback } from 'react'
import { usePersistentState } from '../lib/usePersistentState'
import { ErrorState, Loading } from '../components/PageState'
import Drawer from '../components/Drawer'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd, usd } from '../lib/format'
import type { DeepStats, RStats, SymbolStat } from '../types'
import {
  ComposedChart, Area, Line, BarChart, Bar, XAxis, YAxis, Tooltip,
  ResponsiveContainer, Cell, ReferenceLine
} from 'recharts'

interface Summary {
  trade_count: number; win_rate: string; avg_win: number; avg_loss: number
  win_loss_ratio: number; profit_factor: number; expectancy: number
  max_drawdown: number; sharpe_ratio: number; sortino_ratio: number
  kelly_pct: number; current_streak: number; current_streak_type: string
  max_win_streak: number; max_loss_streak: number; total_pnl: number; partial_pnl: number
}
interface PerfData {
  summary: Summary
  r_stats: RStats
  monthly_bars: { label: string; value: number; isProfit: boolean }[]
  dow_stats: { label: string; pnl: number; trades: number; win_rate: number; isProfit: boolean }[]
  drawdown_curve: { date: string; drawdown: number; equity: number }[]
  deep_stats: DeepStats
}

const TIMEFRAMES = ['1W', '1M', '3M', '1Y', 'YTD', 'AT'] as const

function MetricCard({ label, value, sub, color }: { label: string; value: string; sub?: string; color?: string }) {
  return (
    <div className="card p-4">
      <p className="label-caps mb-2">{label}</p>
      <p className={`text-xl font-semibold tracking-tight ${color ?? 'text-white'}`}>{value}</p>
      {sub && <p className="text-xs text-slate-500 mt-1">{sub}</p>}
    </div>
  )
}

const Tip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-surface-3 border border-line-strong rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.name} style={{ color: p.color ?? '#a79bfb' }}>
          {p.name}: {typeof p.value === 'number' ? signedUsd(p.value) : p.value}
        </p>
      ))}
    </div>
  )
}

type SymbolSummary = SymbolStat

/** Closed positions of one symbol in the selected period: the same set the ranking counted. */
function SymbolPanel({ symbol, period, onClose }: { symbol: SymbolSummary; period: string; onClose: () => void }) {
  const positions = symbol.positions ?? []
  const won = Number(symbol.trades.won)
  const all = Number(symbol.trades.all)
  const winRate = all ? Math.round((won / all) * 100) : 0
  const maxPnl = Math.max(...positions.map(p => Math.abs(p.net_pnl)), 1)

  return (
    <Drawer title={symbol.symbol} onClose={onClose}
      subtitle={`${all} closed position${all === 1 ? '' : 's'} · ${period === 'AT' ? 'all time' : period} · net of fees`}>
      <div className="grid grid-cols-3 gap-2 text-center mb-5">
        {[
          { label: 'Total P&L', value: signedUsd(symbol.pnl_raw), color: pnlColor(symbol.pnl_raw) },
          { label: 'Win rate', value: `${winRate}%`, color: winRate >= 50 ? 'text-emerald-400' : 'text-red-400' },
          { label: 'W / L', value: `${symbol.trades.won} / ${symbol.trades.lost}`, color: 'text-white' },
        ].map(item => (
          <div key={item.label} className="bg-white/[0.03] border border-line rounded-lg py-2">
            <p className="text-[11px] text-slate-500">{item.label}</p>
            <p className={`text-sm font-semibold ${item.color}`}>{item.value}</p>
          </div>
        ))}
      </div>

      <div className="space-y-3">
        {positions.map(p => (
          <div key={p.position_id} className="card p-4">
            <div className="flex justify-between items-start mb-2">
              <span className={`text-xs px-1.5 py-0.5 rounded ${p.direction === 'LONG' ? 'bg-emerald-500/15 text-emerald-300' : 'bg-red-500/15 text-red-300'}`}>
                {p.direction}
              </span>
              <span className={`font-semibold ${pnlColor(p.net_pnl)}`}>
                {signedUsd(p.net_pnl)}
                <span className="text-xs ml-1 opacity-90">({p.pct >= 0 ? '+' : ''}{p.pct.toFixed(1)}%)</span>
                {p.r !== null && <span className={`text-xs ml-1.5 ${rColor(p.r)}`}>{fmtR(p.r)}</span>}
              </span>
            </div>
            <div className="w-full bg-white/5 rounded-full h-1.5 mb-3 overflow-hidden">
              <div className={`h-full rounded-full ${p.net_pnl >= 0 ? 'bg-emerald-400' : 'bg-red-400'}`}
                style={{ width: `${Math.min(100, (Math.abs(p.net_pnl) / maxPnl) * 100)}%` }} />
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-slate-500">
              <span>Avg entry <span className="text-slate-300">{usd(p.avg_entry)}</span></span>
              <span>Avg exit <span className="text-slate-300">{usd(p.avg_exit)}</span></span>
              <span>Qty <span className="text-slate-300">{p.qty}</span></span>
              <span>Held <span className="text-slate-300">{p.held}</span></span>
            </div>
            <p className="text-xs text-slate-600 mt-2">{p.open_time} → {p.close_time}</p>
          </div>
        ))}
      </div>
    </Drawer>
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
    <div className="card p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-medium text-white">Top Symbols</h2>
        <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5">
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

function RSection({ r }: { r: RStats }) {
  const ledgerNote = r?.ledger?.ok === false
    ? <p className="text-xs text-amber-300 mt-1">R ledger unavailable ({r.ledger.message}); showing the last synced copy.</p>
    : null
  if (!r || r.count === 0) {
    return (
      <div className="card p-4 mb-6">
        <h2 className="text-sm font-medium text-white mb-1">R Multiples</h2>
        <p className="text-xs text-slate-500">No R-ledger trades closed in this period.</p>
        {ledgerNote}
      </div>
    )
  }
  return (
    <div className="card p-4 mb-6">
      <div className="flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-1 mb-4">
        <h2 className="text-sm font-medium text-white whitespace-nowrap">R Multiples</h2>
        <span className="text-xs text-slate-500">
          {r.count} trades · standardised 1R ledger{r.win_rate !== null ? ` · ${Math.round(r.win_rate * 100)}% win` : ''}
        </span>
      </div>
      {ledgerNote}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
        <MetricCard label="Expectancy" value={fmtR(r.expectancy_r)} color={rColor(r.expectancy_r)} sub="avg R per trade" />
        <MetricCard label="Avg Win" value={fmtR(r.avg_win_r)} color="text-emerald-400" />
        <MetricCard label="Avg Loss" value={fmtR(r.avg_loss_r)} color="text-red-400" />
        <MetricCard label="Total" value={fmtR(r.total_r)} color={rColor(r.total_r)} />
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <BarChart data={r.distribution}>
          <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} />
          <YAxis allowDecimals={false} tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} width={24} />
          <Tooltip cursor={{ fill: 'rgba(255,255,255,0.04)' }}
            contentStyle={{ background: '#1b2030', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 8, fontSize: 12 }}
            labelStyle={{ color: '#e3e6ee', marginBottom: 2 }} itemStyle={{ color: '#c3c8d4', padding: 0 }} />
          <Bar dataKey="count" name="Positions" radius={[4, 4, 0, 0]}>
            {r.distribution.map((d, i) => <Cell key={i} fill={d.label.startsWith('-') || d.label.startsWith('≤') ? '#f47a7a' : '#3fd49a'} />)}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

function BreakdownTables({ deep }: { deep: DeepStats }) {
  const rows: [string, { all: string; won: string; lost: string }][] = [
    ['Long positions', deep.long_short.long],
    ['Short positions', deep.long_short.short],
    ['Avg hold', deep.timing.holding],
    ['Avg entry time (ET)', deep.timing.entry_hour],
    ['Avg return %', deep.gain_loss.avg_pct],
    ['Avg P&L', deep.gain_loss.avg_usd],
  ]
  return (
    <div className="card p-4 mb-4">
      <h2 className="text-sm font-medium text-white mb-3">Breakdown <span className="text-xs text-slate-500 font-normal ml-1">per closed position</span></h2>
      <table className="w-full text-sm">
        <thead><tr className="label-caps"><th /><th className="text-right font-normal">All</th><th className="text-right font-normal">Won</th><th className="text-right font-normal">Lost</th></tr></thead>
        <tbody>
          {rows.map(([label, v]) => (
            <tr key={label} className="border-b border-line last:border-0">
              <td className="py-1.5 text-slate-400">{label}</td>
              <td className="py-1.5 text-right text-white">{v.all}</td>
              <td className="py-1.5 text-right text-emerald-400">{v.won}</td>
              <td className="py-1.5 text-right text-red-400">{v.lost}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export default function Performance() {
  const [tf, setTf] = usePersistentState<string>('performance.timeframe', 'AT')
  const [selectedSymbol, setSelectedSymbol] = useState<SymbolSummary | null>(null)
  const { data, error, loading, reload } = useApi(() => api.getPerformance(tf) as Promise<PerfData>, [tf])

  const openSymbol = useCallback((s: SymbolSummary) => setSelectedSymbol(s), [])

  if (loading && !data) return <Loading rows={5} />
  if (error && !data) return <ErrorState message={error} onRetry={reload} />
  if (!data) return null

  const s = data.summary
  const winPct = parseFloat(s.win_rate)

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap mb-6">
        <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-white">Performance{loading && <span className="text-xs text-slate-500 font-normal ml-2">updating…</span>}</h1>
        <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5">
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
        <MetricCard label="Total P&L" value={signedUsd(s.total_pnl)} color={s.total_pnl >= 0 ? 'text-emerald-400' : 'text-red-400'}
          sub={`closed positions${s.partial_pnl ? ` · partials ${signedUsd(s.partial_pnl)}` : ''}`} />
        <MetricCard label="Win Rate" value={s.win_rate} color={winPct >= 50 ? 'text-emerald-400' : 'text-red-400'} sub={`${data.deep_stats.gain_loss.trades.won}W / ${data.deep_stats.gain_loss.trades.lost}L`} />
        <MetricCard label="Profit Factor" value={s.profit_factor >= 999 ? '∞' : s.profit_factor.toFixed(2)} color={s.profit_factor >= 1 ? 'text-emerald-400' : 'text-red-400'} />
        <MetricCard label="Expectancy" value={signedUsd(s.expectancy)} color={s.expectancy >= 0 ? 'text-emerald-400' : 'text-red-400'} />
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-6">
        <MetricCard label="Avg Win" value={usd(s.avg_win)} color="text-emerald-400" sub={data.deep_stats.best_worst.largest_usd.won} />
        <MetricCard label="Avg Loss" value={`-${usd(s.avg_loss)}`} color="text-red-400" sub={data.deep_stats.best_worst.largest_usd.lost} />
        <MetricCard label="Max Drawdown" value={`-${usd(s.max_drawdown)}`} color="text-red-400" />
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

      <RSection r={data.r_stats} />

      {/* Charts row */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* Drawdown curve */}
        {data.drawdown_curve?.length > 0 && (
          <div className="card p-4">
            <div className="flex items-baseline justify-between gap-3 flex-wrap mb-4">
              <h2 className="text-sm font-medium text-white">
                Equity &amp; Drawdown
                <span className="text-xs text-slate-500 font-normal ml-2">cumulative realized P&amp;L per day</span>
              </h2>
              <div className="flex items-center gap-3 text-xs text-slate-400">
                <span className="flex items-center gap-1.5"><span className="w-2 h-2 rounded-full bg-violet-400" />Equity</span>
                <span className="flex items-center gap-1.5"><span className="w-2 h-2 rounded-full bg-red-400" />Drawdown</span>
              </div>
            </div>
            <ResponsiveContainer width="100%" height={180}>
              <ComposedChart data={data.drawdown_curve}>
                <defs>
                  <linearGradient id="ddGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#f47a7a" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#f47a7a" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
                <Area type="monotone" dataKey="drawdown" stroke="#f47a7a" fill="url(#ddGrad)" strokeWidth={1.5} name="Drawdown" dot={false} />
                <Line type="monotone" dataKey="equity" stroke="#a79bfb" strokeWidth={2} name="Equity" dot={false} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Monthly bars */}
        {data.monthly_bars?.length > 0 && (
          <div className="card p-4">
            <h2 className="text-sm font-medium text-white mb-4">Monthly P&L</h2>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={data.monthly_bars}>
                <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
                <Bar dataKey="value" radius={[4, 4, 0, 0]} name="P&L">
                  {data.monthly_bars.map((e, i) => <Cell key={i} fill={e.isProfit ? '#3fd49a' : '#f47a7a'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* DOW stats */}
        {data.dow_stats?.length > 0 && (
          <div className="card p-4">
            <h2 className="text-sm font-medium text-white mb-4">Day of Week</h2>
            <ResponsiveContainer width="100%" height={160}>
              <BarChart data={data.dow_stats}>
                <XAxis dataKey="label" tick={{ fontSize: 11, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <Tooltip content={<Tip />} />
                <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
                <Bar dataKey="pnl" radius={[4, 4, 0, 0]} name="P&L">
                  {data.dow_stats.map((e, i) => <Cell key={i} fill={e.isProfit ? '#3fd49a' : '#f47a7a'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
            <div className="grid grid-cols-5 text-center text-[11px] mt-2 border-t border-line pt-2">
              {data.dow_stats.map(d => (
                <div key={d.label}>
                  <p className="text-slate-300">{d.trades} closed</p>
                  <p className={d.trades ? (d.win_rate >= 0.5 ? 'text-emerald-400' : 'text-red-400') : 'text-slate-600'}>
                    {d.trades ? `${Math.round(d.win_rate * 100)}% win` : '—'}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* P&L by Symbol */}
        {data.deep_stats.symbols_by_amount?.length > 0 && (
          <SymbolRanking symbols={data.deep_stats.symbols_by_amount} onSelect={openSymbol} />
        )}
      </div>

      <BreakdownTables deep={data.deep_stats} />

      {selectedSymbol && (
        <SymbolPanel
          symbol={selectedSymbol}
          period={tf}
          onClose={() => setSelectedSymbol(null)}
        />
      )}
    </div>
  )
}
