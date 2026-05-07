import { useEffect, useState } from 'react'
import { api } from '../api'

interface SectorItem {
  ticker: string; name: string; change_pct: number; price: number
}

function heatColor(pct: number): string {
  if (pct >= 3)  return 'bg-emerald-500/40 border-emerald-500/50 text-emerald-300'
  if (pct >= 1)  return 'bg-emerald-600/20 border-emerald-600/30 text-emerald-400'
  if (pct >= 0)  return 'bg-emerald-900/20 border-emerald-900/30 text-emerald-600'
  if (pct >= -1) return 'bg-red-900/20 border-red-900/30 text-red-500'
  if (pct >= -3) return 'bg-red-600/20 border-red-600/30 text-red-400'
  return 'bg-red-500/40 border-red-500/50 text-red-300'
}

const PERIODS = ['1D', '1W', '1M'] as const

export default function Sectors() {
  const [items, setItems] = useState<SectorItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [tab, setTab] = useState<'sectors' | 'themes'>('sectors')
  const [period, setPeriod] = useState<'1D' | '1W' | '1M'>('1D')

  useEffect(() => {
    setLoading(true)
    setItems([])
    const params: Record<string, string> = { period }
    if (tab === 'themes') params.type = 'theme'
    api.getSectors(tab === 'themes' ? 'theme' : undefined, period)
      .then(d => setItems(d.data ?? []))
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [tab, period])

  const sorted = [...items].sort((a, b) => b.change_pct - a.change_pct)
  const best = sorted[0]
  const worst = sorted[sorted.length - 1]
  const avg = sorted.length ? sorted.reduce((s, i) => s + i.change_pct, 0) / sorted.length : 0

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-semibold text-white">Market</h1>
        <div className="flex gap-2">
          <div className="flex gap-1 bg-white/5 rounded-lg p-1">
            {PERIODS.map(p => (
              <button key={p} onClick={() => setPeriod(p)}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors ${period === p ? 'bg-white/15 text-white' : 'text-slate-400 hover:text-white'}`}>
                {p}
              </button>
            ))}
          </div>
          <div className="flex gap-1 bg-white/5 rounded-lg p-1">
            {(['sectors', 'themes'] as const).map(t => (
              <button key={t} onClick={() => setTab(t)}
                className={`px-3 py-1 rounded-md text-sm transition-colors capitalize ${tab === t ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
                {t}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Summary chips */}
      {sorted.length > 0 && (
        <div className="flex gap-3 mb-5 text-xs">
          <div className="flex items-center gap-1.5 bg-emerald-600/10 border border-emerald-600/20 rounded-lg px-3 py-1.5">
            <span className="text-slate-500">Best</span>
            <span className="text-emerald-400 font-medium">{best?.name}</span>
            <span className="text-emerald-400">+{best?.change_pct.toFixed(2)}%</span>
          </div>
          <div className="flex items-center gap-1.5 bg-red-600/10 border border-red-600/20 rounded-lg px-3 py-1.5">
            <span className="text-slate-500">Worst</span>
            <span className="text-red-400 font-medium">{worst?.name}</span>
            <span className="text-red-400">{worst?.change_pct.toFixed(2)}%</span>
          </div>
          <div className="flex items-center gap-1.5 bg-white/5 border border-white/10 rounded-lg px-3 py-1.5">
            <span className="text-slate-500">Avg</span>
            <span className={avg >= 0 ? 'text-emerald-400' : 'text-red-400'}>{avg >= 0 ? '+' : ''}{avg.toFixed(2)}%</span>
          </div>
        </div>
      )}

      {loading && <div className="text-slate-500 text-sm">Loading…</div>}
      {error && <div className="text-red-400 text-sm">Error: {error}</div>}

      {!loading && !error && (
        <div className="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {sorted.map(item => (
            <div key={item.ticker} className={`rounded-xl border p-4 transition-opacity ${heatColor(item.change_pct)}`}>
              <div className="flex justify-between items-start mb-2">
                <span className="font-medium text-sm">{item.name}</span>
                <span className="font-mono text-xs opacity-60">{item.ticker}</span>
              </div>
              <p className="text-2xl font-bold">
                {item.change_pct > 0 ? '+' : ''}{item.change_pct.toFixed(2)}%
              </p>
              <p className="text-xs opacity-60 mt-1">${item.price.toFixed(2)}</p>
            </div>
          ))}
          {sorted.length === 0 && (
            <p className="col-span-4 text-slate-500 text-sm py-6">No data available</p>
          )}
        </div>
      )}
    </div>
  )
}
