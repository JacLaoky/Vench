import { useState } from 'react'
import {
  Area, AreaChart, CartesianGrid, ComposedChart, Line, LineChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { ArrowLeftRight } from 'lucide-react'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { usePersistentState } from '../lib/usePersistentState'
import { pnlColor, signedUsd, usd } from '../lib/format'
import { EmptyState, ErrorState, Loading } from '../components/PageState'
import type { AssetFlow, AssetsResponse } from '../types'

const RANGES = ['1M', '3M', 'YTD', '1Y', 'ALL'] as const
const ACCOUNT_COLORS = ['#a79bfb', '#5ec4f0', '#3fd49a', '#f5b85b', '#f47a7a']
const LABELS = ['Tuition', 'Rent', 'Living costs', 'Transfer out', 'Other']

const tooltipStyle = {
  contentStyle: { background: '#1b2030', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 8, fontSize: 12 },
  labelStyle: { color: '#aab0bf' },
}
const axis = { tick: { fontSize: 10, fill: '#9097a8' }, axisLine: false, tickLine: false } as const
const pct = (n: number | null | undefined, digits = 2) =>
  n === null || n === undefined ? '—' : `${n > 0 ? '+' : ''}${n.toFixed(digits)}%`
const shortDate = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
const kUsd = (n: number) => (Math.abs(n) >= 1000 ? `$${(n / 1000).toFixed(1)}k` : `$${n.toFixed(0)}`)

function Kpi({ label, value, sub, color }: { label: string; value: string; sub?: string; color?: string }) {
  return (
    <div className="card p-4">
      <p className="label-caps mb-2">{label}</p>
      <p className={`text-xl sm:text-2xl font-semibold tracking-tight ${color ?? 'text-white'}`}>{value}</p>
      {sub && <p className="text-xs text-slate-500 mt-1">{sub}</p>}
    </div>
  )
}

function Section({ title, note, children }: { title: string; note?: string; children: React.ReactNode }) {
  return (
    <div className="card p-4 min-w-0">
      <h2 className="text-sm font-medium text-white">{title}</h2>
      {note && <p className="text-[11px] text-slate-500 mt-0.5">{note}</p>}
      <div className="mt-3">{children}</div>
    </div>
  )
}

/** Opening value → money in → money out (by what it was for) → P&L → closing value. */
function Breakdown({ b }: { b: AssetsResponse['breakdown'] }) {
  const rows: [string, number, string][] = [
    ['Opening value', b.opening, 'text-slate-200'],
    ['Deposits', b.deposits, 'text-sky-300'],
    ...Object.entries(b.withdrawals_by_label).map(([k, v]) => [`Withdrawn · ${k}`, v, 'text-amber-300'] as [string, number, string]),
    ['Investment P&L', b.pnl, b.pnl >= 0 ? 'text-emerald-400' : 'text-red-400'],
  ]
  const transfersOut = b.withdrawals - Object.values(b.withdrawals_by_label).reduce((s, v) => s + v, 0)
  if (Math.abs(transfersOut) > 0.005) rows.splice(2, 0, ['Moved to other accounts', transfersOut, 'text-slate-400'])
  const scale = Math.max(...rows.map(r => Math.abs(r[1])), Math.abs(b.closing), 1)
  return (
    <div className="space-y-1.5 text-sm">
      {rows.map(([label, value, color]) => (
        <div key={label} className="grid grid-cols-[1fr_auto] sm:grid-cols-[180px_1fr_auto] items-center gap-3">
          <span className="text-slate-400">{label}</span>
          <div className="hidden sm:block h-1.5 rounded-full bg-white/[0.04] overflow-hidden">
            <div className={`h-full rounded-full ${value >= 0 ? 'bg-violet-400/60' : 'bg-amber-400/60'}`}
              style={{ width: `${(Math.abs(value) / scale) * 100}%` }} />
          </div>
          <span className={`tabular-nums ${color}`}>{label === 'Opening value' ? usd(value) : signedUsd(value)}</span>
        </div>
      ))}
      <div className="grid grid-cols-[1fr_auto] sm:grid-cols-[180px_1fr_auto] items-center gap-3 pt-1.5 border-t border-line">
        <span className="text-white font-medium">Closing value</span>
        <span className="hidden sm:block" />
        <span className="tabular-nums text-white font-medium">{usd(b.closing)}</span>
      </div>
    </div>
  )
}

function MonthlyGrid({ monthly }: { monthly: AssetsResponse['monthly'] }) {
  const years = [...new Set(monthly.map(m => m.month.slice(0, 4)))].sort().reverse()
  const byKey = Object.fromEntries(monthly.map(m => [m.month, m]))
  const cellColor = (r: number) => {
    const a = Math.min(Math.abs(r) / 8, 1) * 0.45 + 0.08
    return r >= 0 ? `rgba(63, 212, 154, ${a})` : `rgba(244, 122, 122, ${a})`
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[440px] table-fixed text-[10px] sm:text-[11px]">
        <thead>
          <tr className="text-slate-500">
            <th className="text-left font-medium py-1 pr-1 w-9">Year</th>
            {['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'].map((m, i) =>
              <th key={i} className="font-medium py-1 text-center">{m}</th>)}
          </tr>
        </thead>
        <tbody>
          {years.map(y => (
            <tr key={y}>
              <td className="py-1 pr-2 text-slate-300">{y}</td>
              {Array.from({ length: 12 }, (_, i) => {
                const m = byKey[`${y}-${String(i + 1).padStart(2, '0')}`]
                return (
                  <td key={i} className="p-0.5">
                    {m ? (
                      <div className="rounded py-1.5 text-center tabular-nums text-white"
                        style={{ background: cellColor(m.return_pct) }}
                        title={`P&L ${signedUsd(m.pnl)} · flows ${signedUsd(m.flow)} · end ${usd(m.end_value)}`}>
                        {`${m.return_pct > 0 ? '+' : ''}${m.return_pct.toFixed(1)}`}
                      </div>
                    ) : <div className="py-1.5" />}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/** Import a Flex statement downloaded from Client Portal (Performance & Reports → Flex Queries → Run,
 *  XML) — for when IBKR's Web Service is unavailable. */
function StatementUpload({ onDone }: { onDone: () => void }) {
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  async function upload(file: File | undefined) {
    if (!file) return
    setBusy(true)
    setMsg('Importing…')
    try {
      const res = await api.uploadIbkrStatement(file)
      setMsg(`Imported: ${res.message}`)
      onDone()
    } catch (e) {
      setMsg((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  return (
    <p>
      <label className={`underline cursor-pointer hover:text-slate-300 ${busy ? 'opacity-50 pointer-events-none' : ''}`}>
        Import an IBKR statement (Flex XML from Client Portal)
        <input type="file" accept=".xml,text/xml" className="hidden" onChange={e => upload(e.target.files?.[0])} />
      </label>
      {msg && <span className="ml-2">{msg}</span>}
    </p>
  )
}

function FlowRow({ f, onSaved }: { f: AssetFlow; onSaved: () => void }) {
  const [saving, setSaving] = useState(false)
  const transfer = f.pair_id !== null && f.pair_id > 0
  async function save(patch: { label?: string; pair_id?: number | null }) {
    setSaving(true)
    try {
      await api.updateCashFlow(f.id, patch)
      onSaved()
    } finally {
      setSaving(false)
    }
  }
  return (
    <tr className="border-b border-line last:border-0">
      <td className="py-2 pr-3 whitespace-nowrap">
        <div className="text-slate-300 text-xs sm:text-sm">{f.date}</div>
        <div className="text-[11px] text-slate-500">{f.account_label}</div>
      </td>
      <td className={`py-2 pr-3 text-right tabular-nums whitespace-nowrap ${f.amount >= 0 ? 'text-sky-300' : 'text-amber-300'}`}>
        {signedUsd(f.amount)}
      </td>
      <td className="py-2 text-right whitespace-nowrap">
        {transfer ? (
          <span className="inline-flex items-center gap-1.5 text-xs text-slate-400">
            <ArrowLeftRight size={12} /> transfer
            <button disabled={saving} onClick={() => save({ pair_id: -1 })} title="Not a transfer between my accounts"
              className="text-slate-600 hover:text-slate-300 px-1" aria-label="Not a transfer">×</button>
          </span>
        ) : f.kind === 'withdrawal' ? (
          <select disabled={saving} value={f.label} onChange={e => save({ label: e.target.value })}
            className="field text-xs text-slate-200 px-2 py-1 max-w-[140px]">
            <option value="">What for?</option>
            {LABELS.map(l => <option key={l} value={l}>{l}</option>)}
            {f.label && !LABELS.includes(f.label) && <option value={f.label}>{f.label}</option>}
          </select>
        ) : <span className="text-xs text-slate-500">deposit</span>}
      </td>
    </tr>
  )
}

export default function Assets() {
  const [range, setRange] = usePersistentState<(typeof RANGES)[number]>('assets.range', 'ALL')
  const [account, setAccount] = usePersistentState<string>('assets.account', '')
  const { data, error, loading, reload } = useApi(() => api.getAssets(range, account || undefined), [range, account])

  if (loading && !data) return <Loading rows={5} />
  if (error && !data) return <ErrorState message={error} onRetry={reload} />
  if (!data || data.status === 'empty') {
    return <EmptyState title="No account values yet" subtitle="They appear after the first sync with IBKR statements or an after-close Moomoo snapshot." />
  }

  const k = data.kpis
  const accounts = data.accounts
  const colorOf = (acc: string) => ACCOUNT_COLORS[Math.max(0, data.all_accounts.findIndex(a => a.account === acc)) % ACCOUNT_COLORS.length]
  const labelOf = (acc: string) => data.all_accounts.find(a => a.account === acc)?.label ?? acc
  const chart = data.series.map(p => ({ ...p, ...Object.fromEntries(Object.entries(p.values).map(([a, v]) => [`v:${a}`, v])) }))
  const rebuilt = accounts.flatMap(a => a.sources.filter(s => s.source === 'reconstructed').map(s => ({ ...s, label: a.label })))
  const flex = data.sources['ibkr_flex']
  const hasTransit = data.series.some(p => p.transit > 0)

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-xl sm:text-2xl font-semibold tracking-tight text-white">
          Assets{loading && <span className="text-xs text-slate-500 font-normal ml-2">updating…</span>}
        </h1>
        <div className="flex gap-2 flex-wrap">
          <select value={account} onChange={e => setAccount(e.target.value)} className="field text-sm text-slate-200 px-2 py-1">
            <option value="">All accounts</option>
            {data.all_accounts.map(a => <option key={a.account} value={a.account}>{a.label}</option>)}
          </select>
          <div className="flex gap-0.5 bg-white/[0.03] border border-line rounded-lg p-0.5">
            {RANGES.map(r => (
              <button key={r} onClick={() => setRange(r)}
                className={`px-2.5 py-1 rounded-md text-xs transition-colors ${range === r ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-white'}`}>
                {r}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Kpi label="Total value" value={usd(k.value)} sub={`close of ${k.as_of}`} />
        <Kpi label="Investment P&L" value={signedUsd(k.pnl)} color={pnlColor(k.pnl)}
          sub={`${range === 'ALL' ? 'since ' + k.inception : range} · deposits & withdrawals excluded`} />
        <Kpi label="Time-weighted return" value={pct(k.twr_pct)} color={pnlColor(k.twr_pct)}
          sub={k.spy_pct !== null ? `SPY ${pct(k.spy_pct)} over the same days` : 'growth of money that stayed invested'} />
        <Kpi label="Max drawdown" value={pct(k.max_drawdown_pct)} color="text-red-400"
          sub={`now ${pct(k.drawdown_pct)} from the peak`} />
      </div>
      <div className="flex gap-4 text-xs text-slate-400 flex-wrap px-1">
        <span>Month to date <span className={pnlColor(k.mtd_pct ?? 0)}>{pct(k.mtd_pct)}</span></span>
        <span>Year to date <span className={pnlColor(k.ytd_pct ?? 0)}>{pct(k.ytd_pct)}</span></span>
        <span>Since {k.inception} <span className={pnlColor(k.inception_pct)}>{pct(k.inception_pct)}</span></span>
        {Object.entries(data.income).map(([kind, v]) => (
          <span key={kind} className="capitalize">{kind} <span className={pnlColor(v)}>{signedUsd(v)}</span></span>
        ))}
      </div>

      <Section title="Account value" note="Stacked by account. The dashed line is the money you put in, net of withdrawals; the gap to it is investment P&L.">
        <div className="flex gap-3 flex-wrap text-xs text-slate-400 mb-2">
          {accounts.map(a => (
            <span key={a.account} className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full" style={{ background: colorOf(a.account) }} />
              {a.label} {a.value !== null && usd(a.value)}
            </span>
          ))}
          <span className="flex items-center gap-1.5"><span className="w-3 border-t border-dashed border-slate-300" />Net contributed</span>
        </div>
        <ResponsiveContainer width="100%" height={260}>
          <ComposedChart data={chart}>
            <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
            <XAxis dataKey="date" tickFormatter={shortDate} minTickGap={40} {...axis} />
            <YAxis tickFormatter={kUsd} width={52} {...axis} />
            <Tooltip {...tooltipStyle} labelFormatter={l => String(l)}
              formatter={(v, name) => [usd(Number(v)), String(name)]} />
            {accounts.map(a => (
              <Area key={a.account} type="monotone" dataKey={`v:${a.account}`} name={labelOf(a.account)} stackId="v"
                stroke={colorOf(a.account)} fill={colorOf(a.account)} fillOpacity={0.25} strokeWidth={1.5} dot={false} />
            ))}
            {hasTransit && (
              <Area type="stepAfter" dataKey="transit" name="In transit between accounts" stackId="v"
                stroke="#9097a8" fill="#9097a8" fillOpacity={0.2} strokeWidth={1} dot={false} />
            )}
            <Line type="monotone" dataKey="contributed" name="Net contributed" stroke="#c3c8d4" strokeDasharray="4 4"
              strokeWidth={1.25} dot={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </Section>

      <div className="grid lg:grid-cols-2 gap-4">
        <Section title="Return vs SPY" note="Time-weighted: deposits and withdrawals don't count as gains or losses.">
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={data.series}>
              <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
              <XAxis dataKey="date" tickFormatter={shortDate} minTickGap={40} {...axis} />
              <YAxis tickFormatter={v => `${v}%`} width={44} {...axis} />
              <Tooltip {...tooltipStyle} formatter={(v, name) => [pct(Number(v)), String(name)]} />
              <ReferenceLine y={0} stroke="rgba(255,255,255,0.1)" />
              <Line type="monotone" dataKey="twr_pct" name="Portfolio" stroke="#a79bfb" strokeWidth={2} dot={false} />
              <Line type="monotone" dataKey="spy_pct" name="SPY" stroke="#9097a8" strokeWidth={1.25} dot={false} connectNulls />
            </LineChart>
          </ResponsiveContainer>
        </Section>
        <Section title="Drawdown" note="Fall from the highest time-weighted value so far.">
          <ResponsiveContainer width="100%" height={200}>
            <AreaChart data={data.series}>
              <defs>
                <linearGradient id="assetDd" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#f47a7a" stopOpacity={0.35} />
                  <stop offset="95%" stopColor="#f47a7a" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
              <XAxis dataKey="date" tickFormatter={shortDate} minTickGap={40} {...axis} />
              <YAxis tickFormatter={v => `${v}%`} width={44} {...axis} />
              <Tooltip {...tooltipStyle} formatter={v => [pct(Number(v)), 'Drawdown']} />
              <Area type="monotone" dataKey="drawdown_pct" stroke="#f47a7a" fill="url(#assetDd)" strokeWidth={1.5} dot={false} />
            </AreaChart>
          </ResponsiveContainer>
        </Section>
      </div>

      <div className="grid lg:grid-cols-2 gap-4">
        <Section title="Where the value went" note={`${range === 'ALL' ? 'Since ' + k.inception : range}: money in and out vs. investment result.`}>
          <Breakdown b={data.breakdown} />
        </Section>
        <Section title="Monthly returns" note="Time-weighted return in % per calendar month. Hover a month for its P&L and flows.">
          <MonthlyGrid monthly={data.monthly} />
        </Section>
      </div>

      <Section title="Deposits & withdrawals"
        note="Transfers between your own accounts are matched automatically and don't count as money in or out of the total. Label withdrawals to see what they paid for.">
        {data.flows.length === 0 ? <p className="text-sm text-slate-500">None in this range.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <tbody>
                {data.flows.map(f => <FlowRow key={f.id} f={f} onSaved={reload} />)}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      <div className="text-[11px] text-slate-500 space-y-1 px-1">
        <p>Values are end-of-day. IBKR: daily statements (Flex){flex && <> — last fetch {flex.at?.replace('T', ' ')}: {flex.ok ? flex.message : <span className="text-amber-300">{flex.message}</span>}</>}.
          Moomoo: the account's total after each close.</p>
        {rebuilt.map(r => (
          <p key={r.label}>{r.label} from {r.first} to {r.last} is rebuilt from its fills, cash flows and closing prices, not read from the broker.</p>
        ))}
        <p>Return each day = (value − previous value − money in/out) ÷ (previous value + money in/out).</p>
        <StatementUpload onDone={reload} />
      </div>
    </div>
  )
}
