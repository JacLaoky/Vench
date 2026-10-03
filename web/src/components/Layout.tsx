import { useState } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import {
  LayoutDashboard, BookOpen, BarChart2, TrendingUp,
  Calendar, Activity, List, Calculator, RefreshCw, Waves, Menu, X,
} from 'lucide-react'
import { api } from '../api'

const nav = [
  { to: '/',            label: 'Dashboard',    icon: LayoutDashboard },
  { to: '/journal',     label: 'Journal',      icon: BookOpen },
  { to: '/all-trades',  label: 'All Trades',   icon: List },
  { to: '/stats',       label: 'Stats',        icon: BarChart2 },
  { to: '/performance', label: 'Performance',  icon: Activity },
  { to: '/sectors',     label: 'Sectors',      icon: TrendingUp },
  { to: '/breadth',     label: 'Breadth',      icon: Waves },
  { to: '/calendar',    label: 'Calendar',     icon: Calendar },
  { to: '/calculator',  label: 'Calculator',   icon: Calculator },
]

function SyncButton() {
  const [syncing, setSyncing] = useState(false)
  const [msg, setMsg] = useState('')

  async function handleSync() {
    setSyncing(true)
    setMsg('')
    try {
      const res = await api.sync()
      setMsg(res.message || 'Synced')
    } catch (e) {
      setMsg((e as Error).message || 'Sync failed')
    } finally {
      setSyncing(false)
      setTimeout(() => setMsg(''), 4000)
    }
  }

  return (
    <div>
      <button onClick={handleSync} disabled={syncing}
        className="flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm text-slate-400 hover:text-white hover:bg-white/5 transition-colors disabled:opacity-50">
        <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
        {syncing ? 'Syncing…' : 'Sync'}
      </button>
      {msg && <p className="text-xs text-slate-500 px-3 mt-1">{msg}</p>}
    </div>
  )
}

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="flex flex-col gap-0.5">
      {nav.map(({ to, label, icon: Icon }) => (
        <NavLink key={to} to={to} end={to === '/'} onClick={onNavigate}
          className={({ isActive }) =>
            `flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
              isActive ? 'bg-violet-600/20 text-violet-400' : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`
          }>
          <Icon size={15} />
          {label}
        </NavLink>
      ))}
    </nav>
  )
}

export default function Layout({ children }: { children: React.ReactNode }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const { pathname } = useLocation()
  const current = nav.find(n => (n.to === '/' ? pathname === '/' : pathname.startsWith(n.to)))

  return (
    <div className="flex min-h-screen bg-[#0f1117]">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex w-52 shrink-0 border-r border-white/10 flex-col py-6 px-3 sticky top-0 h-screen">
        <div className="px-3 mb-6">
          <span className="text-lg font-semibold text-white tracking-tight">Vench</span>
          <span className="text-xs text-slate-500 ml-2">Trading</span>
        </div>
        <div className="flex-1"><NavLinks /></div>
        <div className="mt-auto px-1"><SyncButton /></div>
      </aside>

      <div className="flex-1 min-w-0 flex flex-col">
        {/* Phone top bar */}
        <header className="md:hidden sticky top-0 z-40 bg-[#0f1117]/95 backdrop-blur border-b border-white/10 pt-[env(safe-area-inset-top)]">
          <div className="flex items-center justify-between px-4 h-12">
            <span className="text-base font-semibold text-white">Vench <span className="text-xs text-slate-500 font-normal ml-1">{current?.label}</span></span>
            <button onClick={() => setMenuOpen(o => !o)} className="text-slate-300 p-1" aria-label="Menu">
              {menuOpen ? <X size={20} /> : <Menu size={20} />}
            </button>
          </div>
          {menuOpen && (
            <div className="px-3 pb-3 border-t border-white/10 pt-2">
              <NavLinks onNavigate={() => setMenuOpen(false)} />
              <div className="mt-2 border-t border-white/10 pt-2"><SyncButton /></div>
            </div>
          )}
        </header>

        <main className="flex-1 overflow-auto p-4 sm:p-6 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-6">{children}</main>
      </div>
    </div>
  )
}
