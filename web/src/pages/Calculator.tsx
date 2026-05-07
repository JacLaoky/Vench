import { useState } from 'react'

// ── Scale In ──────────────────────────────────────────────────────────────────
function ScaleIn() {
  const [capital, setCapital] = useState(10000)
  const [targetPct, setTargetPct] = useState(10)
  const [ratios, setRatios] = useState([50, 30, 20])
  const [prices, setPrices] = useState([0, 0, 0])

  const totalSize = (capital * targetPct) / 100
  const tranches = ratios.map((r, i) => {
    const allocation = (totalSize * r) / 100
    const shares = prices[i] > 0 ? Math.floor(allocation / prices[i]) : 0
    return { allocation, shares, cost: shares * prices[i] }
  })
  const totalShares = tranches.reduce((s, t) => s + t.shares, 0)
  const totalCost = tranches.reduce((s, t) => s + t.cost, 0)
  const avgCost = totalShares > 0 ? totalCost / totalShares : 0

  function setRatio(i: number, val: number) {
    const newR = [...ratios]
    newR[i] = val
    setRatios(newR)
  }
  function setPrice(i: number, val: number) {
    const newP = [...prices]
    newP[i] = val
    setPrices(newP)
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-4">
        <label className="block">
          <span className="text-xs text-slate-500">Capital ($)</span>
          <input type="number" value={capital} onChange={e => setCapital(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Target Size (%)</span>
          <input type="number" value={targetPct} onChange={e => setTargetPct(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
      </div>

      <div className="text-xs text-slate-500">Total allocation: <span className="text-white font-medium">${totalSize.toFixed(2)}</span></div>

      <div className="space-y-3">
        {[0, 1, 2].map(i => (
          <div key={i} className="grid grid-cols-3 gap-3 items-end">
            <label className="block">
              <span className="text-xs text-slate-500">Tranche {i + 1} ratio (%)</span>
              <input type="number" value={ratios[i]} onChange={e => setRatio(i, +e.target.value)}
                className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
            </label>
            <label className="block">
              <span className="text-xs text-slate-500">Entry price ($)</span>
              <input type="number" step="0.01" value={prices[i] || ''} onChange={e => setPrice(i, +e.target.value)}
                className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
            </label>
            <div className="bg-white/5 rounded-lg px-3 py-2 border border-white/10">
              <p className="text-xs text-slate-500">Shares</p>
              <p className="text-white font-semibold">{tranches[i].shares}</p>
              <p className="text-xs text-slate-500">${tranches[i].cost.toFixed(2)}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-3 gap-3 pt-4 border-t border-white/10">
        <div className="bg-violet-600/10 border border-violet-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Total Shares</p>
          <p className="text-xl font-bold text-white">{totalShares}</p>
        </div>
        <div className="bg-violet-600/10 border border-violet-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Avg Cost</p>
          <p className="text-xl font-bold text-white">${avgCost.toFixed(2)}</p>
        </div>
        <div className="bg-violet-600/10 border border-violet-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Total Cost</p>
          <p className="text-xl font-bold text-white">${totalCost.toFixed(2)}</p>
        </div>
      </div>
    </div>
  )
}

// ── Swing Trade ───────────────────────────────────────────────────────────────
function SwingTrade() {
  const [capital, setCapital] = useState(10000)
  const [riskPct, setRiskPct] = useState(1)
  const [entry, setEntry] = useState(0)
  const [stop, setStop] = useState(0)
  const [side, setSide] = useState<'long' | 'short'>('long')

  const maxRisk = (capital * riskPct) / 100
  const riskPerShare = Math.abs(entry - stop)
  const shares = riskPerShare > 0 ? Math.floor(maxRisk / riskPerShare) : 0
  const positionSize = shares * entry

  const targets = [1, 1.5, 2, 3, 5].map(r => {
    const profit = r * riskPerShare * shares
    const price = side === 'long' ? entry + r * riskPerShare : entry - r * riskPerShare
    return { r, price, profit }
  })

  return (
    <div className="space-y-5">
      <div className="flex gap-2 mb-2">
        {(['long', 'short'] as const).map(s => (
          <button key={s} onClick={() => setSide(s)}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors capitalize ${side === s
              ? s === 'long' ? 'bg-emerald-600 text-white' : 'bg-red-600 text-white'
              : 'bg-white/5 text-slate-400 hover:text-white'}`}>
            {s}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-2 gap-4">
        <label className="block">
          <span className="text-xs text-slate-500">Capital ($)</span>
          <input type="number" value={capital} onChange={e => setCapital(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Max Risk (%)</span>
          <input type="number" step="0.1" value={riskPct} onChange={e => setRiskPct(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Entry Price ($)</span>
          <input type="number" step="0.01" value={entry || ''} onChange={e => setEntry(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Stop Price ($)</span>
          <input type="number" step="0.01" value={stop || ''} onChange={e => setStop(+e.target.value)}
            className="mt-1 w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-violet-500" />
        </label>
      </div>

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-violet-600/10 border border-violet-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Shares</p>
          <p className="text-2xl font-bold text-white">{shares}</p>
        </div>
        <div className="bg-violet-600/10 border border-violet-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Position Size</p>
          <p className="text-2xl font-bold text-white">${positionSize.toFixed(0)}</p>
        </div>
        <div className="bg-red-600/10 border border-red-500/30 rounded-xl p-3">
          <p className="text-xs text-slate-500">Max Risk</p>
          <p className="text-2xl font-bold text-red-400">-${maxRisk.toFixed(2)}</p>
        </div>
      </div>

      {shares > 0 && (
        <div>
          <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-3">Profit Targets</h3>
          <div className="space-y-2">
            {targets.map(t => (
              <div key={t.r} className="flex justify-between items-center py-2 border-b border-white/5 text-sm">
                <span className="text-slate-400 w-10">{t.r}R</span>
                <span className="text-white font-medium">${t.price.toFixed(2)}</span>
                <span className="text-emerald-400 font-medium">+${t.profit.toFixed(2)}</span>
                <span className="text-slate-500 text-xs">+{((t.profit / positionSize) * 100).toFixed(1)}%</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

// ── Main ──────────────────────────────────────────────────────────────────────
export default function Calculator() {
  const [tab, setTab] = useState<'scalein' | 'swing'>('scalein')

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-semibold text-white">Calculator</h1>
        <div className="flex gap-1 bg-white/5 rounded-lg p-1">
          {[{ id: 'scalein', label: 'Scale In' }, { id: 'swing', label: 'Swing Trade' }].map(t => (
            <button key={t.id} onClick={() => setTab(t.id as any)}
              className={`px-3 py-1 rounded-md text-sm transition-colors ${tab === t.id ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-2xl">
        <div className="bg-white/5 rounded-xl border border-white/10 p-6">
          {tab === 'scalein' ? <ScaleIn /> : <SwingTrade />}
        </div>
      </div>
    </div>
  )
}
