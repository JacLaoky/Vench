import { X } from 'lucide-react'

/** Right-hand panel on desktop, full screen on phones; respects the iPhone notch / home bar. */
export default function Drawer({ title, subtitle, onClose, children, wide = false }: {
  title: React.ReactNode
  subtitle?: React.ReactNode
  onClose: () => void
  children: React.ReactNode
  wide?: boolean
}) {
  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className={`relative w-full ${wide ? 'sm:max-w-2xl' : 'sm:max-w-md'} bg-[#13151f] sm:border-l border-white/10 h-full flex flex-col shadow-2xl pt-[env(safe-area-inset-top)]`}>
        <div className="flex items-start justify-between gap-3 px-5 py-4 border-b border-white/10">
          <div className="min-w-0">
            <h2 className="text-lg font-semibold text-white truncate">{title}</h2>
            {subtitle && <div className="text-xs text-slate-500 mt-0.5">{subtitle}</div>}
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white shrink-0" aria-label="Close"><X size={18} /></button>
        </div>
        <div className="flex-1 overflow-y-auto px-5 py-4 pb-[calc(1.5rem+env(safe-area-inset-bottom))]">{children}</div>
      </div>
    </div>
  )
}
