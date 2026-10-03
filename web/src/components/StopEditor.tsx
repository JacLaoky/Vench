import { useState } from 'react'
import { api } from '../api'

interface Props {
  positionId: string
  ticker: string
  stop: number | null
  onSaved: (stop: number) => void
}

/** The position's current stop, kept as a journal reference. R does not come from it: R is read
 *  from the trading system's standardised 1R ledger. */
export default function StopEditor({ positionId, ticker, stop, onSaved }: Props) {
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

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <label className="text-xs text-slate-500">Current stop</label>
      <input type="number" inputMode="decimal" step="0.01" value={value} onChange={e => setValue(e.target.value)}
        className="w-24 bg-white/5 border border-white/10 rounded-lg px-2 py-1 text-sm text-white focus:outline-none focus:border-violet-500" />
      <button onClick={save} disabled={saving}
        className="px-3 py-1 bg-violet-600 hover:bg-violet-500 text-white text-xs rounded-lg disabled:opacity-50">
        {saving ? 'Saving…' : 'Save'}
      </button>
      {msg && <span className={`text-xs ${msg === 'Saved' ? 'text-emerald-400' : 'text-red-400'}`}>{msg}</span>}
    </div>
  )
}
