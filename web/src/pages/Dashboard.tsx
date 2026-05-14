import { useEffect, useState } from 'react'
import { api } from '../api'
import { TrendingUp, TrendingDown } from 'lucide-react'

interface Position {
  ticker: string
  name: string
  qty: number
  cost_price: number
  market_val: number
  pl_val: number
  pl_ratio: number
  today_pl_val: number
  side: string
  stop_price: number | null
}

interface Account {
  cash?: number
  total_assets?: number
  market_val?: number
  total_pnl?: number
}

function StatCard({ label, value, sub, positive }: { label: string; value: string; sub?: string; positive?: boolean }) {
  return (
    <div className="bg-white/5 rounded-xl p-4 border border-white/10">
      <p className="text-xs text-slate-500 mb-1">{label}</p>
      <p className={`text-xl font-semibold ${positive === undefined ? 'text-white' : positive ? 'text-emerald-400' : 'text-red-400'}`}>
        {value}
      </p>
      {sub && <p className="text-xs text-slate-500 mt-1">{sub}</p>}
    </div>
  )
}

function fmt(n: number, prefix = '$') {
  return `${prefix}${Math.abs(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

function pct(n: number) {
  return `${n >= 0 ? '+' : ''}${n.toFixed(2)}%`
}

export default function Dashboard() {
  const [positions, setPositions] = useState<Position[]>([])
  const [account, setAccount] = useState<Account | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    Promise.all([api.getPortfolio(), api.getAccount()])
      .then(([port, acc]) => {
        setPositions(port.data ?? [])
        setAccount(acc.data ?? null)
      })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>

  const totalPnl = positions.reduce((s, p) => s + p.pl_val, 0)
  const todayPnl = positions.reduce((s, p) => s + p.today_pl_val, 0)
  const totalMktVal = positions.reduce((s, p) => s + p.market_val, 0)

  return (
    <div>
      <h1 className="text-xl font-semibold text-white mb-6">Dashboard</h1>

      {/* Summary cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-8">
        <StatCard
          label="Total Assets"
          value={account?.total_assets ? fmt(account.total_assets) : fmt(totalMktVal + (account?.cash ?? 0))}
        />
        <StatCard label="Market Value" value={fmt(totalMktVal)} />
        <StatCard
          label="Unrealized P&L"
          value={`${totalPnl >= 0 ? '+' : '-'}${fmt(totalPnl)}`}
          positive={totalPnl >= 0}
        />
        <StatCard
          label="Today's P&L"
          value={`${todayPnl >= 0 ? '+' : '-'}${fmt(todayPnl)}`}
          positive={todayPnl >= 0}
        />
      </div>

      {/* Positions table */}
      <div className="bg-white/5 rounded-xl border border-white/10 overflow-hidden">
        <div className="px-4 py-3 border-b border-white/10">
          <h2 className="text-sm font-medium text-white">Open Positions ({positions.length})</h2>
        </div>
        {positions.length === 0 ? (
          <p className="text-slate-500 text-sm p-6">No open positions</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-xs text-slate-500 border-b border-white/10">
                  <th className="text-left px-4 py-2">Ticker</th>
                  <th className="text-right px-4 py-2">Qty</th>
                  <th className="text-right px-4 py-2">Cost</th>
                  <th className="text-right px-4 py-2">Mkt Val</th>
                  <th className="text-right px-4 py-2">P&L</th>
                  <th className="text-right px-4 py-2">Today</th>
                  <th className="text-right px-4 py-2">Stop</th>
                </tr>
              </thead>
              <tbody>
                {positions.map(p => (
                  <tr key={p.ticker} className="border-b border-white/5 hover:bg-white/5 transition-colors">
                    <td className="px-4 py-3">
                      <div className="font-medium text-white">{p.ticker}</div>
                      <div className="text-xs text-slate-500 truncate max-w-[120px]">{p.name}</div>
                    </td>
                    <td className="text-right px-4 py-3 text-slate-300">{p.qty}</td>
                    <td className="text-right px-4 py-3 text-slate-300">${p.cost_price.toFixed(2)}</td>
                    <td className="text-right px-4 py-3 text-slate-300">{fmt(p.market_val)}</td>
                    <td className={`text-right px-4 py-3 font-medium ${p.pl_val >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                      <div className="flex items-center justify-end gap-1">
                        {p.pl_val >= 0 ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
                        {p.pl_val >= 0 ? '+' : '-'}{fmt(p.pl_val)}
                      </div>
                      <div className="text-xs opacity-70">{pct(p.pl_ratio)}</div>
                    </td>
                    <td className={`text-right px-4 py-3 text-xs ${p.today_pl_val >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                      {p.today_pl_val >= 0 ? '+' : '-'}{fmt(p.today_pl_val)}
                    </td>
                    <td className="text-right px-4 py-3 text-slate-500 text-xs">
                      {p.stop_price ? `$${p.stop_price.toFixed(2)}` : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
