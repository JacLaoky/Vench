import { useState } from 'react'
import { AlertTriangle } from 'lucide-react'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { signedUsd, usd } from '../lib/format'

const input = 'mt-1 w-full field px-3 py-2 text-sm text-white'

function CapitalField({ capital, setCapital, accountTotal }: {
  capital: number
  setCapital: (n: number) => void
  accountTotal?: number
}) {
  return (
    <label className="block">
      <span className="text-xs text-slate-500">Capital ($)</span>
      <input type="number" inputMode="decimal" value={capital} onChange={e => setCapital(+e.target.value)} className={input} />
      {accountTotal !== undefined && Math.round(accountTotal) !== Math.round(capital) && (
        <button type="button" onClick={() => setCapital(Math.round(accountTotal))} className="text-[11px] text-violet-400 hover:text-violet-300 mt-1">
          Use account total {usd(accountTotal)}
        </button>
      )}
    </label>
  )
}

/** Shares figure that copies itself to the clipboard on tap (for pasting into the broker app). */
function CopyNumber({ value, className }: { value: number; className: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <button type="button" title="Copy" className={`${className} text-left`}
      onClick={() => navigator.clipboard?.writeText(String(value)).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1200) }).catch(() => {})}>
      {copied ? 'Copied' : value}
    </button>
  )
}

// ── Scale In ──────────────────────────────────────────────────────────────────
function ScaleIn({ accountTotal }: { accountTotal?: number }) {
  const [capital, setCapital] = usePersistentState('calc.capital', 10000)
  const [targetPct, setTargetPct] = usePersistentState('calc.scalein.targetPct', 10)
  const [ratios, setRatios] = usePersistentState('calc.scalein.ratios', [50, 30, 20])
  const [prices, setPrices] = useState([0, 0, 0])

  const totalSize = (capital * targetPct) / 100
  const ratioSum = ratios.reduce((s, r) => s + r, 0) || 1
  const tranches = ratios.map((r, i) => {
    const allocation = (totalSize * r) / ratioSum   // ratios are weights: 1:2:4 and 50:30:20 both work
    const shares = prices[i] > 0 ? Math.floor(allocation / prices[i]) : 0
    return { allocation, shares, cost: shares * prices[i] }
  })
  const totalShares = tranches.reduce((s, t) => s + t.shares, 0)
  const totalCost = tranches.reduce((s, t) => s + t.cost, 0)
  const avgCost = totalShares > 0 ? totalCost / totalShares : 0

  const setAt = (arr: number[], i: number, val: number) => arr.map((v, j) => (j === i ? val : v))

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <CapitalField capital={capital} setCapital={setCapital} accountTotal={accountTotal} />
        <label className="block">
          <span className="text-xs text-slate-500">Target size (% of capital)</span>
          <input type="number" inputMode="decimal" value={targetPct} onChange={e => setTargetPct(+e.target.value)} className={input} />
        </label>
      </div>

      <div className="text-xs text-slate-500">Total allocation: <span className="text-white font-medium">{usd(totalSize)}</span> · tranche weights {ratios.join(' : ')}</div>

      <div className="space-y-3">
        {[0, 1, 2].map(i => (
          <div key={i} className="grid grid-cols-3 gap-3 items-end">
            <label className="block">
              <span className="text-xs text-slate-500">Tranche {i + 1} weight</span>
              <input type="number" inputMode="decimal" value={ratios[i]} onChange={e => setRatios(setAt(ratios, i, +e.target.value))} className={input} />
            </label>
            <label className="block">
              <span className="text-xs text-slate-500">Entry price ($)</span>
              <input type="number" inputMode="decimal" step="0.01" value={prices[i] || ''} onChange={e => setPrices(setAt(prices, i, +e.target.value))} className={input} />
            </label>
            <div className="bg-white/[0.03] rounded-lg px-3 py-2 border border-line">
              <p className="text-xs text-slate-500">Shares</p>
              <CopyNumber value={tranches[i].shares} className="block text-white font-semibold" />
              <p className="text-xs text-slate-500">{usd(tranches[i].cost)}</p>
            </div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-3 gap-3 pt-4 border-t border-line">
        <div className="bg-violet-500/[0.07] border border-violet-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500">Total shares</p>
          <CopyNumber value={totalShares} className="block text-lg sm:text-xl font-semibold tracking-tight text-white" />
        </div>
        <div className="bg-violet-500/[0.07] border border-violet-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500">Avg cost</p>
          <p className="text-lg sm:text-xl font-semibold tracking-tight text-white">{usd(avgCost)}</p>
        </div>
        <div className="bg-violet-500/[0.07] border border-violet-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500">Total cost</p>
          <p className="text-lg sm:text-xl font-semibold tracking-tight text-white">{usd(totalCost)}</p>
          {capital > 0 && <p className="text-[11px] text-slate-500">{((totalCost / capital) * 100).toFixed(1)}% of capital</p>}
        </div>
      </div>
    </div>
  )
}

// ── Swing Trade ───────────────────────────────────────────────────────────────
const RISK_PRESETS = [0.25, 0.5, 1, 2]

function SwingTrade({ accountTotal }: { accountTotal?: number }) {
  const [capital, setCapital] = usePersistentState('calc.capital', 10000)
  const [riskPct, setRiskPct] = usePersistentState('calc.swing.riskPct', 1)
  const [side, setSide] = usePersistentState<'long' | 'short'>('calc.swing.side', 'long')
  const [entry, setEntry] = useState(0)
  const [stop, setStop] = useState(0)

  const maxRisk = (capital * riskPct) / 100
  const wrongSide = entry > 0 && stop > 0 && (side === 'long' ? stop >= entry : stop <= entry)
  const riskPerShare = wrongSide ? 0 : Math.abs(entry - stop)
  const shares = riskPerShare > 0 ? Math.floor(maxRisk / riskPerShare) : 0
  const positionSize = shares * entry

  const targets = [1, 1.5, 2, 3, 5].map(r => {
    const profit = r * riskPerShare * shares
    const price = side === 'long' ? entry + r * riskPerShare : entry - r * riskPerShare
    return { r, price, profit }
  })

  return (
    <div className="space-y-5">
      <div className="flex gap-2">
        {(['long', 'short'] as const).map(s => (
          <button key={s} onClick={() => setSide(s)}
            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors capitalize ${side === s
              ? s === 'long' ? 'bg-emerald-600 text-white' : 'bg-red-600 text-white'
              : 'bg-white/[0.04] border border-line text-slate-400 hover:text-white'}`}>
            {s}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <CapitalField capital={capital} setCapital={setCapital} accountTotal={accountTotal} />
        <label className="block">
          <span className="text-xs text-slate-500">Max risk (% of capital)</span>
          <input type="number" inputMode="decimal" step="0.05" value={riskPct} onChange={e => setRiskPct(+e.target.value)} className={input} />
          <div className="flex gap-1 mt-1">
            {RISK_PRESETS.map(p => (
              <button key={p} type="button" onClick={() => setRiskPct(p)}
                className={`text-[11px] px-2 py-0.5 rounded ${riskPct === p ? 'bg-violet-600 text-white' : 'bg-white/[0.04] border border-line text-slate-400 hover:text-white'}`}>
                {p}%
              </button>
            ))}
          </div>
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Entry price ($)</span>
          <input type="number" inputMode="decimal" step="0.01" value={entry || ''} onChange={e => setEntry(+e.target.value)} className={input} />
        </label>
        <label className="block">
          <span className="text-xs text-slate-500">Stop price ($)</span>
          <input type="number" inputMode="decimal" step="0.01" value={stop || ''} onChange={e => setStop(+e.target.value)} className={input} />
        </label>
      </div>

      {wrongSide && (
        <p className="flex items-center gap-2 text-xs text-amber-300 bg-amber-500/10 border border-amber-500/20 rounded-lg px-3 py-2">
          <AlertTriangle size={14} /> For a {side} the stop must be {side === 'long' ? 'below' : 'above'} the entry.
        </p>
      )}

      <div className="grid grid-cols-3 gap-3">
        <div className="bg-violet-500/[0.07] border border-violet-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500">Shares</p>
          <CopyNumber value={shares} className="block text-lg sm:text-2xl font-semibold tracking-tight text-white" />
          {riskPerShare > 0 && <p className="text-[11px] text-slate-500">${riskPerShare.toFixed(2)} risk/share</p>}
        </div>
        <div className="bg-violet-500/[0.07] border border-violet-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500 truncate">Position size</p>
          <p className="text-lg sm:text-2xl font-semibold tracking-tight text-white">{usd(positionSize)}</p>
          {capital > 0 && shares > 0 && <p className="text-[11px] text-slate-500">{((positionSize / capital) * 100).toFixed(1)}% of capital</p>}
        </div>
        <div className="bg-red-500/[0.07] border border-red-500/20 rounded-xl p-3 min-w-0">
          <p className="text-xs text-slate-500">Max risk</p>
          <p className="text-lg sm:text-2xl font-semibold tracking-tight text-red-400">-{usd(maxRisk)}</p>
        </div>
      </div>

      {shares > 0 && (
        <div>
          <h3 className="label-caps mb-3">Profit targets</h3>
          <div className="space-y-2">
            {targets.map(t => (
              <div key={t.r} className="flex justify-between items-center py-2 border-b border-line text-sm">
                <span className="text-slate-400 w-10">{t.r}R</span>
                <span className="text-white font-medium">{usd(t.price)}</span>
                <span className="text-emerald-400 font-medium">{signedUsd(t.profit)}</span>
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
const TABS = [{ id: 'scalein', label: 'Scale In' }, { id: 'swing', label: 'Swing Trade' }] as const

export default function Calculator() {
  const [tab, setTab] = usePersistentState<'scalein' | 'swing'>('calc.tab', 'scalein')
  const { data: account } = useApi(() => api.getAccount(), [])

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap mb-6">
        <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-white">Calculator</h1>
        <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5">
          {TABS.map(t => (
            <button key={t.id} onClick={() => setTab(t.id)}
              className={`px-3 py-1 rounded-md text-sm transition-colors ${tab === t.id ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <div className="max-w-2xl">
        <div className="card p-4 sm:p-6">
          {tab === 'scalein' ? <ScaleIn accountTotal={account?.total_assets} /> : <SwingTrade accountTotal={account?.total_assets} />}
        </div>
      </div>
    </div>
  )
}
