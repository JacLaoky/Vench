import { SCOPES, useScope } from '../lib/scope'

export default function ScopeSwitch({ className = '' }: { className?: string }) {
  const { scope, setScope } = useScope()
  return (
    <div className={`flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5 ${className}`}>
      {SCOPES.map(s => (
        <button key={s.id} onClick={() => setScope(s.id)}
          className={`flex-1 px-2.5 py-1 rounded-md text-xs transition-colors ${scope === s.id ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
          {s.label}
        </button>
      ))}
    </div>
  )
}
