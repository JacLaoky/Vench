import { api } from '../api'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { fmtR, pnlColor, rColor, signedUsd, usd } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/PageState'
import type { RecapStats } from '../types'

type Scope = 'swing' | 'all'

const pct = (n: number | null | undefined, signed = false) =>
  n === null || n === undefined ? '—' : `${signed && n > 0 ? '+' : ''}${n.toFixed(2)}%`
const days = (n: number | null) => (n === null ? '—' : n.toFixed(2))
const monthLabel = (key: string) =>
  new Date(`${key}-01T12:00:00`).toLocaleDateString('en-US', { month: 'short', year: '2-digit' }).replace(' ', '-')

interface Column {
  label: string
  swingOnly?: boolean
  render: (s: RecapStats) => React.ReactNode
}

const COLUMNS: Column[] = [
  { label: 'Return', swingOnly: true, render: s => <span className={pnlColor(s.return_pct ?? 0)}>{pct(s.return_pct, true)}</span> },
  { label: 'Cumulative', swingOnly: true, render: s => s.cumulative_pct === undefined ? '' : <span className={pnlColor(s.cumulative_pct)}>{pct(s.cumulative_pct, true)}</span> },
  { label: 'Flows', swingOnly: true, render: s => s.flows ? <span className="text-sky-300">{signedUsd(s.flows)}</span> : '—' },
  { label: 'Net P&L', render: s => <span className={pnlColor(s.net_pnl)}>{signedUsd(s.net_pnl)}</span> },
  { label: 'Avg R', swingOnly: true, render: s => <span className={rColor(s.avg_r)}>{fmtR(s.avg_r)}</span> },
  { label: 'Avg Gain %', render: s => <span className="text-emerald-400">{pct(s.avg_gain_pct)}</span> },
  { label: 'Avg Loss %', render: s => <span className="text-red-400">{pct(s.avg_loss_pct)}</span> },
  { label: 'Win %', render: s => pct(s.win_pct) },
  { label: 'Loss %', render: s => pct(s.loss_pct) },
  { label: 'Wins', render: s => s.wins },
  { label: 'Losses', render: s => s.losses },
  { label: '# Trades', render: s => s.trades },
  { label: 'LG Gain', render: s => <span className="text-emerald-400">{pct(s.largest_gain_pct)}</span> },
  { label: 'LG Loss', render: s => <span className="text-red-400">{pct(s.largest_loss_pct)}</span> },
  { label: 'Avg Days Gain', render: s => days(s.avg_days_gain) },
  { label: 'Avg Days Loss', render: s => days(s.avg_days_loss) },
]

export default function Recap() {
  const [scope, setScope] = usePersistentState<Scope>('recap.scope', 'swing')
  const [year, setYear] = usePersistentState<number | null>('recap.year', null)
  const { data, error, loading, reload } = useApi(() => api.getRecap(scope, year ?? undefined), [scope, year])

  const columns = COLUMNS.filter(c => !c.swingOnly || scope === 'swing')
  const cell = 'px-3 py-2 text-right whitespace-nowrap'
  const head = 'px-3 py-2 text-right whitespace-nowrap font-medium'

  return (
    <div>
      <div className="flex items-center justify-between gap-3 flex-wrap mb-4">
        <h1 className="text-xl font-semibold text-white">
          {data?.year ?? ''} Recap{loading && data && <span className="text-xs text-slate-500 font-normal ml-2">updating…</span>}
        </h1>
        <div className="flex gap-2 flex-wrap">
          {data && data.years.length > 1 && (
            <select value={data.year} onChange={e => setYear(Number(e.target.value))}
              className="bg-white/5 border border-white/10 rounded-lg text-sm text-slate-200 px-2 py-1 focus:outline-none focus:border-violet-500">
              {data.years.map(y => <option key={y} value={y}>{y}</option>)}
            </select>
          )}
          <div className="flex gap-1 bg-white/5 rounded-lg p-1">
            {([['swing', 'Swing'], ['all', 'All trades']] as const).map(([id, label]) => (
              <button key={id} onClick={() => { setScope(id); setYear(null) }}
                className={`px-3 py-1 rounded-md text-sm transition-colors ${scope === id ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
                {label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {loading && !data ? <Loading rows={4} /> : error && !data ? <ErrorState message={error} onRetry={reload} /> : !data || data.months.length === 0 ? (
        <EmptyState title="No closed positions for this year" />
      ) : (
        <>
          <div className="bg-white/5 rounded-xl border border-white/10 overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-sky-900/60 text-sky-100 text-xs">
                  <th className="px-3 py-2 text-left font-medium sticky left-0 bg-[#132a40] z-10">Month</th>
                  {columns.map(c => <th key={c.label} className={head}>{c.label}</th>)}
                </tr>
              </thead>
              <tbody>
                <tr className="border-b-2 border-sky-800/60 bg-white/[0.04] font-semibold">
                  <td className="px-3 py-2 text-left text-white whitespace-nowrap sticky left-0 bg-[#1b1e29] z-10">{data.year}</td>
                  {columns.map(c => (
                    <td key={c.label} className={`${cell} text-slate-100`}>
                      {c.label === 'Cumulative' ? '' : c.render(data.summary)}
                    </td>
                  ))}
                </tr>
                {data.months.map(m => (
                  <tr key={m.month} className="border-b border-white/5 last:border-0 hover:bg-white/[0.03]">
                    <td className="px-3 py-2 text-left text-slate-200 whitespace-nowrap sticky left-0 bg-[#16181f] z-10">{monthLabel(m.month)}</td>
                    {columns.map(c => <td key={c.label} className={`${cell} text-slate-300`}>{c.render(m)}</td>)}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="text-[11px] text-slate-500 mt-3 space-y-1">
            {scope === 'swing' ? (
              <>
                <p>Swing = right-side trades from the trading system's R ledger (it starts in September 2026). Each position counts once, net of fees.</p>
                {data.pool ? (
                  <p>
                    Return = the month's realized P&L ÷ the right-side capital pool (Modified Dietz: money added or withdrawn mid-month
                    counts for the part of the month it was in the pool). Pool = {usd(data.pool.initial_base)} at set-up, plus Flows, plus
                    realized P&L (now {usd(data.pool.current)}). Cumulative chains the monthly returns from the start of the year, so
                    Flows (recorded with /pool_add in Telegram) never count as return.
                  </p>
                ) : (
                  <p className="text-amber-300">The capital pool hasn't been received from the trading system yet, so returns are not shown.</p>
                )}
              </>
            ) : (
              <p>All closed positions in this account, net of fees, one row per month of closing. No return % here: there is no single capital base for every strategy.</p>
            )}
            <p>Gain/loss % = net P&L ÷ cost at entry. Days are calendar days from first fill to the closing fill.</p>
          </div>
        </>
      )}
    </div>
  )
}
