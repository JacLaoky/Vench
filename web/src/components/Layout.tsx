import { useState } from 'react'
import { NavLink, useLocation } from 'react-router-dom'
import {
  LayoutDashboard, BookOpen, BarChart2, TrendingUp,
  Calendar, Activity, List, Calculator, RefreshCw, Waves, Menu, X, Tags, RotateCw, Table2,
} from 'lucide-react'
import { api } from '../api'
import { useBuildCheck } from '../lib/useBuildCheck'

const groups = [
  { title: 'Overview', items: [
    { to: '/',            label: 'Dashboard',   icon: LayoutDashboard },
  ] },
  { title: 'Review', items: [
    { to: '/journal',     label: 'Journal',     icon: BookOpen },
    { to: '/all-trades',  label: 'All Trades',  icon: List },
    { to: '/recap',       label: 'Recap',       icon: Table2 },
  ] },
  { title: 'Analytics', items: [
    { to: '/performance', label: 'Performance', icon: Activity },
    { to: '/stats',       label: 'Stats',       icon: BarChart2 },
    { to: '/tags',        label: 'Tags',        icon: Tags },
  ] },
  { title: 'Market', items: [
    { to: '/sectors',     label: 'Sectors',     icon: TrendingUp },
    { to: '/breadth',     label: 'Breadth',     icon: Waves },
    { to: '/calendar',    label: 'Earnings',    icon: Calendar },
  ] },
  { title: 'Tools', items: [
    { to: '/calculator',  label: 'Calculator',  icon: Calculator },
  ] },
]
const allItems = groups.flatMap(g => g.items)

function Brand() {
  return (
    <div className="flex items-center gap-2.5">
      <img src="/icons/icon-192.png" alt="" className="w-7 h-7 rounded-lg ring-1 ring-white/10" />
      <span className="text-[15px] font-semibold text-white tracking-tight">Vench</span>
    </div>
  )
}

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
        className="flex items-center justify-center gap-2 w-full px-3 py-2 rounded-lg text-sm text-slate-300 border border-line bg-white/[0.03] hover:bg-white/[0.06] hover:text-white transition-colors disabled:opacity-50">
        <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
        {syncing ? 'Syncing…' : 'Sync trades'}
      </button>
      {msg && <p className="text-xs text-slate-500 px-1 mt-1.5">{msg}</p>}
    </div>
  )
}

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <nav className="flex flex-col gap-4">
      {groups.map(group => (
        <div key={group.title}>
          <p className="label-caps px-3 mb-1.5">{group.title}</p>
          <div className="flex flex-col gap-0.5">
            {group.items.map(({ to, label, icon: Icon }) => (
              <NavLink key={to} to={to} end={to === '/'} onClick={onNavigate}
                className={({ isActive }) =>
                  `relative flex items-center gap-3 px-3 py-[7px] rounded-lg text-[13px] transition-colors ${
                    isActive
                      ? 'bg-violet-500/[0.12] text-white before:absolute before:left-0 before:top-1.5 before:bottom-1.5 before:w-[3px] before:rounded-full before:bg-violet-400'
                      : 'text-slate-400 hover:text-slate-100 hover:bg-white/[0.04]'
                  }`
                }>
                {({ isActive }) => (
                  <>
                    <Icon size={15} className={isActive ? 'text-violet-300' : ''} />
                    {label}
                  </>
                )}
              </NavLink>
            ))}
          </div>
        </div>
      ))}
    </nav>
  )
}

export default function Layout({ children }: { children: React.ReactNode }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const { pathname } = useLocation()
  useBuildCheck()
  const current = allItems.find(n => (n.to === '/' ? pathname === '/' : pathname.startsWith(n.to)))

  return (
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex w-56 shrink-0 border-r border-line bg-surface/60 backdrop-blur flex-col py-5 px-3 sticky top-0 h-screen">
        <div className="px-3 mb-7"><Brand /></div>
        <div className="flex-1 overflow-y-auto"><NavLinks /></div>
        <div className="mt-4 px-1"><SyncButton /></div>
      </aside>

      <div className="flex-1 min-w-0 flex flex-col">
        {/* Phone top bar */}
        <header className="md:hidden sticky top-0 z-40 bg-canvas/80 backdrop-blur-xl border-b border-line pt-[env(safe-area-inset-top)]">
          <div className="flex items-center justify-between px-4 h-12">
            <div className="flex items-center gap-2">
              <Brand />
              {current && <span className="text-xs text-slate-500">/ {current.label}</span>}
            </div>
            <div className="flex items-center gap-1">
              <button onClick={() => window.location.reload()} className="text-slate-400 p-1.5" aria-label="Refresh">
                <RotateCw size={17} />
              </button>
              <button onClick={() => setMenuOpen(o => !o)} className="text-slate-300 p-1" aria-label="Menu">
                {menuOpen ? <X size={20} /> : <Menu size={20} />}
              </button>
            </div>
          </div>
          {menuOpen && (
            <div className="px-3 pb-4 border-t border-line pt-3 max-h-[75vh] overflow-y-auto">
              <NavLinks onNavigate={() => setMenuOpen(false)} />
              <div className="mt-4"><SyncButton /></div>
            </div>
          )}
        </header>

        <main className="flex-1 overflow-auto px-4 py-5 sm:px-8 sm:py-7 pb-[calc(5rem+env(safe-area-inset-bottom))] md:pb-8">
          <div className="max-w-[1400px] mx-auto">{children}</div>
        </main>
      </div>
    </div>
  )
}
