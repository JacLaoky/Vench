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
      <div className="absolute inset-0 bg-black/50 backdrop-blur-[2px]" onClick={onClose} />
      <div className={`relative w-full ${wide ? 'sm:max-w-2xl' : 'sm:max-w-md'} bg-surface sm:border-l border-line h-full flex flex-col shadow-2xl pt-[env(safe-area-inset-top)]`}>
        <div className="flex items-start justify-between gap-3 px-5 py-4 border-b border-line">
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
