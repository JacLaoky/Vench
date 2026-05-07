import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard, BookOpen, BarChart2, TrendingUp,
  Calendar, Activity, List, Calculator, RefreshCw, Waves
} from 'lucide-react'
import { api } from '../api'
import { useState } from 'react'

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

export default function Layout({ children }: { children: React.ReactNode }) {
  const [syncing, setSyncing] = useState(false)
  const [syncMsg, setSyncMsg] = useState('')

  async function handleSync() {
    setSyncing(true)
    setSyncMsg('')
    try {
      const res = await api.sync()
      setSyncMsg(res.message || 'Synced')
    } catch {
      setSyncMsg('Sync failed')
    } finally {
      setSyncing(false)
      setTimeout(() => setSyncMsg(''), 3000)
    }
  }

  return (
    <div className="flex min-h-screen bg-[#0f1117]">
      <aside className="w-52 shrink-0 border-r border-white/10 flex flex-col py-6 px-3">
        <div className="px-3 mb-6">
          <span className="text-lg font-semibold text-white tracking-tight">Vench</span>
          <span className="text-xs text-slate-500 ml-2">Trading</span>
        </div>

        <nav className="flex flex-col gap-0.5 flex-1">
          {nav.map(({ to, label, icon: Icon }) => (
            <NavLink key={to} to={to} end={to === '/'}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-colors ${
                  isActive
                    ? 'bg-violet-600/20 text-violet-400'
                    : 'text-slate-400 hover:text-white hover:bg-white/5'
                }`
              }>
              <Icon size={15} />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="mt-auto px-1">
          <button onClick={handleSync} disabled={syncing}
            className="flex items-center gap-2 w-full px-3 py-2 rounded-lg text-sm text-slate-400 hover:text-white hover:bg-white/5 transition-colors disabled:opacity-50">
            <RefreshCw size={14} className={syncing ? 'animate-spin' : ''} />
            {syncing ? 'Syncing…' : 'Sync'}
          </button>
          {syncMsg && <p className="text-xs text-slate-500 px-3 mt-1">{syncMsg}</p>}
        </div>
      </aside>

      <main className="flex-1 overflow-auto p-6">{children}</main>
    </div>
  )
}
