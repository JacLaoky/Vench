import { useState } from 'react'
import { TrendingUp, TrendingDown, ChevronRight } from 'lucide-react'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { pnlColor, signedUsd, usd } from '../lib/format'
import PositionDrawer from '../components/PositionDrawer'
import { ErrorState, Loading } from '../components/PageState'
import type { Position } from '../types'

function StatCard({ label, value, positive }: { label: string; value: string; positive?: boolean }) {
  return (
    <div className="bg-white/5 rounded-xl p-4 border border-white/10">
      <p className="text-xs text-slate-500 mb-1">{label}</p>
      <p className={`text-lg sm:text-xl font-semibold ${positive === undefined ? 'text-white' : positive ? 'text-emerald-400' : 'text-red-400'}`}>
        {value}
      </p>
    </div>
  )
}

const pct = (n: number) => `${n >= 0 ? '+' : ''}${n.toFixed(2)}%`

export default function Dashboard() {
  const { data, setData, error, loading, reload } = useApi(
    () => Promise.all([api.getPortfolio(), api.getAccount()]), [],
  )
  const [selected, setSelected] = useState<Position | null>(null)

  if (loading && !data) return <Loading rows={5} />
  if (error || !data) return <ErrorState message={error || 'No data'} onRetry={reload} />

  const [portfolio, account] = data
  const positions = portfolio.data ?? []
  const totalPnl = positions.reduce((s, p) => s + p.pl_val, 0)
  const todayPnl = positions.reduce((s, p) => s + p.today_pl_val, 0)
  const totalMktVal = positions.reduce((s, p) => s + p.market_val, 0)

  function stopSaved(ticker: string, stop: number) {
    setData(prev => prev && [
      { ...prev[0], data: prev[0].data.map(p => p.ticker === ticker ? { ...p, stop_price: stop } : p) },
      prev[1],
    ])
    setSelected(p => p && { ...p, stop_price: stop })
  }

  return (
    <div>
      <h1 className="text-xl font-semibold text-white mb-6">Dashboard</h1>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-8">
        <StatCard label="Total Assets" value={account.total_assets !== undefined ? usd(account.total_assets) : '—'} />
        <StatCard label="Market Value" value={usd(totalMktVal)} />
        <StatCard label="Unrealized P&L" value={signedUsd(totalPnl)} positive={totalPnl >= 0} />
        <StatCard label="Today's P&L" value={signedUsd(todayPnl)} positive={todayPnl >= 0} />
      </div>

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
                  <th className="text-right px-4 py-2 hidden sm:table-cell">Cost</th>
                  <th className="text-right px-4 py-2 hidden sm:table-cell">Mkt Val</th>
                  <th className="text-right px-4 py-2">P&L</th>
                  <th className="text-right px-4 py-2 hidden md:table-cell">Today</th>
                  <th className="text-right px-4 py-2">Stop</th>
                  <th className="w-6" />
                </tr>
              </thead>
              <tbody>
                {positions.map(p => (
                  <tr key={p.ticker} onClick={() => setSelected(p)}
                    className="border-b border-white/5 hover:bg-white/5 transition-colors cursor-pointer">
                    <td className="px-4 py-3">
                      <div className="font-medium text-white">{p.ticker}</div>
                      <div className="text-xs text-slate-500 truncate max-w-[120px]">{p.name}</div>
                    </td>
                    <td className="text-right px-4 py-3 text-slate-300">{p.qty}</td>
                    <td className="text-right px-4 py-3 text-slate-300 hidden sm:table-cell">${p.cost_price.toFixed(2)}</td>
                    <td className="text-right px-4 py-3 text-slate-300 hidden sm:table-cell">{usd(p.market_val)}</td>
                    <td className={`text-right px-4 py-3 font-medium ${pnlColor(p.pl_val)}`}>
                      <div className="flex items-center justify-end gap-1">
                        {p.pl_val >= 0 ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
                        {signedUsd(p.pl_val)}
                      </div>
                      <div className="text-xs opacity-70">{pct(p.pl_ratio)}</div>
                    </td>
                    <td className={`text-right px-4 py-3 text-xs hidden md:table-cell ${pnlColor(p.today_pl_val)}`}>
                      {signedUsd(p.today_pl_val)}
                    </td>
                    <td className="text-right px-4 py-3 text-xs">
                      {p.stop_price
                        ? <span className="text-slate-300">${p.stop_price.toFixed(2)}</span>
                        : <span className="text-slate-600">set</span>}
                    </td>
                    <td className="pr-3 text-slate-600"><ChevronRight size={14} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {selected && (
        <PositionDrawer position={selected} onClose={() => setSelected(null)}
          onStopSaved={stop => stopSaved(selected.ticker, stop)} />
      )}
    </div>
  )
}
