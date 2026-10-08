import { useState } from 'react'
import { api } from '../api'

interface Props {
  positionId: string
  ticker: string
  stop: number | null
  /** The trading system recorded this stop at entry; it is synced from there, not edited here. */
  locked?: boolean
  onSaved: (stop: number) => void
}

/** The position's entry stop — a record of the risk taken at entry. Trades the trading system
 *  opened carry the stop it recorded (read-only); manual trades can enter theirs. R itself is read
 *  from the trading system's standardised 1R ledger. */
export default function StopEditor({ positionId, ticker, stop, locked = false, onSaved }: Props) {
  const [value, setValue] = useState(stop?.toString() ?? '')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')

  async function save() {
    const next = parseFloat(value)
    if (!(next > 0)) {
      setMsg('Enter a positive price')
      return
    }
    setSaving(true)
    setMsg('')
    try {
      const res = await api.setStop(positionId, ticker, next)
      onSaved(res.stop_price)
      setMsg('Saved')
    } catch (e) {
      setMsg(`Save failed: ${(e as Error).message}`)
    } finally {
      setSaving(false)
    }
  }

  if (locked) {
    return (
      <div className="flex items-baseline gap-2 flex-wrap">
        <span className="text-xs text-slate-500">Entry stop</span>
        <span className="text-sm text-white">{stop !== null ? `$${stop.toFixed(2)}` : '—'}</span>
        <span className="text-[11px] text-slate-500">from the trading system</span>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <label className="text-xs text-slate-500">Entry stop</label>
      <input type="number" inputMode="decimal" step="0.01" value={value} onChange={e => setValue(e.target.value)}
        className="w-24 field px-2 py-1 text-sm text-white" />
      <button onClick={save} disabled={saving}
        className="px-3 py-1 bg-violet-600 hover:bg-violet-500 text-white shadow-sm shadow-violet-950/50 text-xs rounded-lg disabled:opacity-50">
        {saving ? 'Saving…' : 'Save'}
      </button>
      {msg && <span className={`text-xs ${msg === 'Saved' ? 'text-emerald-400' : 'text-red-400'}`}>{msg}</span>}
    </div>
  )
}
