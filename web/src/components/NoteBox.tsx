import { useState } from 'react'

/** Text note with explicit Save; remount it (key) when it should show a different note. */
export default function NoteBox({ label, initial, save, rows = 4 }: {
  label?: string
  initial: string
  save: (note: string) => Promise<unknown>
  rows?: number
}) {
  const [note, setNote] = useState(initial)
  const [state, setState] = useState<'idle' | 'saving' | 'saved' | string>('idle')

  async function onSave() {
    setState('saving')
    try {
      await save(note)
      setState('saved')
    } catch (e) {
      setState(`Save failed: ${(e as Error).message}`)
    }
  }

  return (
    <section>
      {label && <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">{label}</h3>}
      <textarea value={note} onChange={e => { setNote(e.target.value); setState('idle') }} rows={rows}
        placeholder="Write your notes here…"
        className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-slate-200 placeholder-slate-600 resize-y focus:outline-none focus:border-violet-500" />
      <div className="flex items-center gap-3 mt-2">
        <button onClick={onSave} disabled={state === 'saving' || (note === initial && state !== 'idle')}
          className="px-4 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-sm rounded-lg disabled:opacity-50">
          {state === 'saving' ? 'Saving…' : 'Save'}
        </button>
        {state === 'saved' && <span className="text-xs text-emerald-400">Saved</span>}
        {state.startsWith('Save failed') && <span className="text-xs text-red-400">{state}</span>}
      </div>
    </section>
  )
}
