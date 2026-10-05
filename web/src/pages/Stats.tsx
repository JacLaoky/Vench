import { api } from '../api'
import { signedUsd, usd } from '../lib/format'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { ErrorState, Loading } from '../components/PageState'
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip,
  ResponsiveContainer, Cell, ReferenceLine
} from 'recharts'

interface Summary {
  trade_count: number
  sell_count: number
  win_rate: string
  avg_gain_usd: number
  avg_gain_pct: string
  profit_factor: string
  total_pnl: number
  partial_pnl: number
  profit_chart: Array<{ date: string; value: number }>
}

interface StatsData {
  summary: Summary
  last_7_chart: Array<{ weekday: string; pnl: number; isProfit: boolean }>
  latest_trades: Array<{
    ticker: string; pnl: number; pct: string; isProfit: boolean
    enter_time: string; exit_time: string; holding_time: string; trade_type: string
  }>
}

function StatBox({ label, value, color, sub }: { label: string; value: string; color?: string; sub?: string }) {
  return (
    <div className="card p-4">
      <p className="label-caps mb-2">{label}</p>
      <p className={`text-xl font-semibold ${color ?? 'text-white'}`}>{value}</p>
      {sub && <p className="text-xs text-slate-500 mt-1">{sub}</p>}
    </div>
  )
}

const CustomTooltip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-surface-3 border border-line-strong rounded-lg px-3 py-2 text-xs">
      <p className="text-slate-400 mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.name} style={{ color: p.color ?? '#a79bfb' }}>
          {typeof p.value === 'number' ? signedUsd(p.value) : p.value}
        </p>
      ))}
    </div>
  )
}

const TIMEFRAMES = ['1W', '1M', '3M', '1Y', 'YTD', 'AT'] as const

export default function Stats() {
  const [tf, setTf] = usePersistentState<string>('stats.timeframe', 'AT')
  const { data, error, loading, reload } = useApi(() => api.getStats(tf) as Promise<StatsData>, [tf])

  if (loading && !data) return <Loading rows={4} />
  if (error && !data) return <ErrorState message={error} onRetry={reload} />
  if (!data) return null

  const s = data.summary
  const winPct = parseFloat(s.win_rate)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-white">Stats</h1>
        <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5">
          {TIMEFRAMES.map(t => (
            <button key={t} onClick={() => setTf(t)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors ${tf === t ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {t}
            </button>
          ))}
        </div>
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-6">
        <StatBox label="Total Trades" value={String(s.sell_count)} />
        <StatBox label="Win Rate" value={s.win_rate} color={winPct >= 50 ? 'text-emerald-400' : 'text-red-400'} />
        <StatBox label="Avg Gain" value={usd(s.avg_gain_usd)} color="text-emerald-400" />
        <StatBox label="Profit Factor" value={s.profit_factor} color={parseFloat(s.profit_factor) >= 1 ? 'text-emerald-400' : 'text-red-400'} />
        <StatBox label="Total P&L" value={signedUsd(s.total_pnl)} color={s.total_pnl >= 0 ? 'text-emerald-400' : 'text-red-400'}
          sub={`closed positions${s.partial_pnl ? ` · partials ${signedUsd(s.partial_pnl)}` : ''}`} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4">
        {/* Cumulative P&L curve */}
        {s.profit_chart?.length > 0 && (
          <div className="card p-4">
            <h2 className="text-sm font-medium text-white mb-4">Cumulative P&L</h2>
            <ResponsiveContainer width="100%" height={180}>
              <AreaChart data={s.profit_chart}>
                <defs>
                  <linearGradient id="pnlGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#a79bfb" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#a79bfb" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
                <YAxis tick={{ fontSize: 10, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
                <Area type="monotone" dataKey="value" stroke="#a79bfb" fill="url(#pnlGrad)" strokeWidth={2} name="P&L" dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Last 7 days bar */}
        {data.last_7_chart?.length > 0 && (
          <div className="card p-4">
            <h2 className="text-sm font-medium text-white mb-4">Last 7 Days</h2>
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={data.last_7_chart}>
                <XAxis dataKey="weekday" tick={{ fontSize: 11, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#9097a8' }} axisLine={false} tickLine={false} />
                <Tooltip content={<CustomTooltip />} />
                <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
                <Bar dataKey="pnl" radius={[4, 4, 0, 0]} name="P&L">
                  {data.last_7_chart.map((entry, i) => (
                    <Cell key={i} fill={entry.isProfit ? '#3fd49a' : '#f47a7a'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Latest trades */}
      {data.latest_trades?.length > 0 && (
        <div className="card overflow-hidden">
          <div className="px-4 py-3 border-b border-line">
            <h2 className="text-sm font-medium text-white">Recent Trades</h2>
          </div>
          <table className="w-full text-sm">
            <thead>
              <tr className="label-caps border-b border-line bg-white/[0.02]">
                <th className="text-left px-4 py-2">Ticker</th>
                <th className="text-left px-4 py-2">Type</th>
                <th className="text-right px-4 py-2">P&L</th>
                <th className="text-right px-4 py-2">%</th>
                <th className="text-right px-4 py-2">Held</th>
                <th className="text-right px-4 py-2">Exit</th>
              </tr>
            </thead>
            <tbody>
              {data.latest_trades.map((t, i) => (
                <tr key={i} className="border-b border-line hover:bg-white/[0.03] transition-colors">
                  <td className="px-4 py-2 font-medium text-white">{t.ticker}</td>
                  <td className="px-4 py-2 text-slate-400 text-xs">{t.trade_type}</td>
                  <td className={`text-right px-4 py-2 font-medium ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>
                    {t.isProfit ? '+' : ''}${t.pnl.toFixed(2)}
                  </td>
                  <td className={`text-right px-4 py-2 text-xs ${t.isProfit ? 'text-emerald-400' : 'text-red-400'}`}>{t.pct}</td>
                  <td className="text-right px-4 py-2 text-slate-500 text-xs">{t.holding_time}</td>
                  <td className="text-right px-4 py-2 text-slate-500 text-xs">{t.exit_time}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
