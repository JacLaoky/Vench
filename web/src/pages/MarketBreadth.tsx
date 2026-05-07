import { useEffect, useState } from 'react'
import { api } from '../api'

interface Index { name: string; ticker: string; price: number; change_pct: number }
interface BreadthData {
  vix: number; vix_change: number
  indices: Index[]
  sectors_positive: number; sectors_total: number
  period: string
}

function vixLabel(vix: number) {
  if (vix < 15) return { label: 'Low', color: 'text-emerald-400' }
  if (vix < 20) return { label: 'Moderate', color: 'text-yellow-400' }
  if (vix < 30) return { label: 'Elevated Fear', color: 'text-orange-400' }
  return { label: 'Extreme Fear', color: 'text-red-400' }
}

const PERIODS = ['1D', '1W', '1M'] as const

export default function MarketBreadth() {
  const [data, setData] = useState<BreadthData | null>(null)
  const [period, setPeriod] = useState<'1D' | '1W' | '1M'>('1D')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    setLoading(true)
    api.getMarketBreadth(period)
      .then(d => setData(d))
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [period])

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>
  if (!data) return null

  const vix = vixLabel(data.vix)
  const breadthPct = Math.round((data.sectors_positive / data.sectors_total) * 100)

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-semibold text-white">Market Breadth</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {PERIODS.map(p => (
            <button key={p} onClick={() => setPeriod(p)}
              className={`px-2.5 py-1 rounded-md text-xs transition-colors ${period === p ? 'bg-white/15 text-white' : 'text-slate-400 hover:text-white'}`}>
              {p}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-6">
        {/* VIX card */}
        <div className="bg-white/5 rounded-xl border border-white/10 p-5">
          <p className="text-xs text-slate-500 mb-1">VIX (Fear Index)</p>
          <div className="flex items-end gap-3">
            <span className={`text-4xl font-bold ${vix.color}`}>{data.vix.toFixed(2)}</span>
            <span className={`text-sm mb-1 ${data.vix_change <= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
              {data.vix_change > 0 ? '+' : ''}{data.vix_change.toFixed(2)}
            </span>
          </div>
          <p className={`text-sm mt-1 font-medium ${vix.color}`}>{vix.label}</p>
        </div>

        {/* Sector breadth */}
        <div className="bg-white/5 rounded-xl border border-white/10 p-5 lg:col-span-2">
          <p className="text-xs text-slate-500 mb-1">Sectors Advancing</p>
          <div className="flex items-end gap-3 mb-3">
            <span className="text-3xl font-bold text-white">{data.sectors_positive}</span>
            <span className="text-slate-500 mb-1">/ {data.sectors_total}</span>
            <span className={`text-lg font-semibold mb-0.5 ${breadthPct >= 50 ? 'text-emerald-400' : 'text-red-400'}`}>{breadthPct}%</span>
          </div>
          <div className="w-full bg-white/10 rounded-full h-3 overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${breadthPct >= 50 ? 'bg-emerald-400' : 'bg-red-400'}`}
              style={{ width: `${breadthPct}%` }}
            />
          </div>
          <p className="text-xs text-slate-500 mt-2">
            {breadthPct >= 70 ? 'Broad advance — risk-on' : breadthPct >= 50 ? 'Mixed breadth' : 'Broad decline — risk-off'}
          </p>
        </div>
      </div>

      {/* Indices grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {data.indices.map(idx => (
          <div key={idx.ticker} className="bg-white/5 rounded-xl border border-white/10 p-4">
            <p className="text-xs text-slate-500">{idx.name}</p>
            <p className="text-lg font-semibold text-white mt-1">${idx.price.toFixed(2)}</p>
            <p className={`text-sm font-medium mt-0.5 ${idx.change_pct >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
              {idx.change_pct >= 0 ? '+' : ''}{idx.change_pct.toFixed(2)}%
            </p>
            <p className="text-xs text-slate-600 mt-1">{idx.ticker}</p>
          </div>
        ))}
      </div>
    </div>
  )
}
