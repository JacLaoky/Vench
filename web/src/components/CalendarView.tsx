import { useMemo } from 'react'
import { pnlColor, signedUsd } from '../lib/format'
import type { JournalDay } from '../types'

// Five shades per sign; the two brightest carry dark ink so the numbers stay readable (WCAG AA).
const PROFIT = ['#064e3b', '#065f46', '#047857', '#2fbf8a', '#5fe0ae']
const LOSS   = ['#7f1d1d', '#991b1b', '#b91c1c', '#e05252', '#f58b8b']
const PROFIT_INK = ['#ffffff', '#ffffff', '#ffffff', '#04261a', '#04261a']
const LOSS_INK   = ['#ffffff', '#ffffff', '#ffffff', '#2f0909', '#2f0909']
type Shade = { bg: string; ink: string }
const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

const iso = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

/** Shade index 0–4 by the day's percentile among days of the same sign. */
function useShader(days: JournalDay[]) {
  return useMemo(() => {
    const wins = days.map(d => d.pnl_value).filter(v => v > 0).sort((a, b) => a - b)
    const losses = days.map(d => -d.pnl_value).filter(v => v > 0).sort((a, b) => a - b)
    const level = (sorted: number[], v: number) => {
      const rank = sorted.findIndex(x => x >= v)
      return Math.min(4, Math.floor(((rank < 0 ? sorted.length - 1 : rank) / Math.max(1, sorted.length)) * 5))
    }
    return (pnl: number): Shade | undefined => {
      if (pnl > 0) { const l = level(wins, pnl); return { bg: PROFIT[l], ink: PROFIT_INK[l] } }
      if (pnl < 0) { const l = level(losses, -pnl); return { bg: LOSS[l], ink: LOSS_INK[l] } }
      return undefined
    }
  }, [days])
}

function YearHeatmap({ byDate, shade, onSelect }: {
  byDate: Map<string, JournalDay>
  shade: (pnl: number) => Shade | undefined
  onSelect: (date: string) => void
}) {
  const end = new Date()
  const start = new Date(end)
  start.setDate(start.getDate() - 364 - ((start.getDay() + 6) % 7))   // align to a Monday
  const weeks: Date[][] = []
  for (const d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    if ((d.getDay() + 6) % 7 === 0) weeks.push([])
    weeks[weeks.length - 1].push(new Date(d))
  }
  return (
    <div className="hidden md:block card p-4 mb-4 overflow-x-auto">
      <p className="text-xs text-slate-500 mb-2">Past year</p>
      <div className="flex gap-[3px]">
        {weeks.map((week, i) => (
          <div key={i} className="flex flex-col gap-[3px]">
            {week.map(d => {
              const key = iso(d)
              const day = byDate.get(key)
              return (
                <button key={key} onClick={() => onSelect(key)} title={day ? `${key}  ${signedUsd(day.pnl_value)}` : key}
                  className="w-3 h-3 rounded-[2px] bg-white/5 hover:ring-1 hover:ring-white/40"
                  style={day ? { background: shade(day.pnl_value)?.bg ?? 'rgba(255,255,255,0.15)' } : undefined} />
              )
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

export default function CalendarView({ days, notes, onSelect }: {
  days: JournalDay[]
  notes: Record<string, string>
  onSelect: (date: string) => void
}) {
  const byDate = useMemo(() => new Map(days.map(d => [d.date, d])), [days])
  const shade = useShader(days)

  const months = useMemo(() => {
    const keys = new Set(days.map(d => d.date.slice(0, 7)))
    keys.add(iso(new Date()).slice(0, 7))
    return [...keys].sort().reverse()
  }, [days])

  return (
    <div>
      <YearHeatmap byDate={byDate} shade={shade} onSelect={onSelect} />
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {months.map(key => {
          const [y, m] = key.split('-').map(Number)
          const first = new Date(y, m - 1, 1)
          const daysInMonth = new Date(y, m, 0).getDate()
          const lead = (first.getDay() + 6) % 7
          const monthDays = days.filter(d => d.date.startsWith(key))
          const pnl = monthDays.reduce((s, d) => s + d.pnl_value, 0)
          const closed = monthDays.reduce((s, d) => s + d.closed, 0)
          const wins = monthDays.reduce((s, d) => s + Number(d.wins), 0)
          const partial = monthDays.reduce((s, d) => s + (d.partial_value ?? 0), 0)
          return (
            <div key={key} className="card p-3 sm:p-4">
              <div className="flex items-baseline justify-between mb-3 gap-2 flex-wrap">
                <h3 className="text-sm font-medium text-white">{first.toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</h3>
                <span className="text-xs text-slate-500">
                  {closed} closed{closed ? ` · ${Math.round((wins / closed) * 100)}% win` : ''} ·{' '}
                  <span className={pnlColor(pnl)}>{signedUsd(pnl)}</span>
                  {Math.abs(partial) >= 0.005 && <span className="text-slate-600"> · partials {signedUsd(partial)}</span>}
                </span>
              </div>
              <div className="grid grid-cols-7 gap-1 text-center">
                {WEEKDAYS.map(w => <div key={w} className="text-[10px] text-slate-600 pb-1">{w}</div>)}
                {Array.from({ length: lead }, (_, i) => <div key={`lead${i}`} />)}
                {Array.from({ length: daysInMonth }, (_, i) => {
                  const date = `${key}-${String(i + 1).padStart(2, '0')}`
                  const day = byDate.get(date)
                  const sh = day ? shade(day.pnl_value) : undefined
                  return (
                    <button key={date} onClick={() => onSelect(date)}
                      className={`relative aspect-square sm:aspect-auto sm:h-14 rounded-md text-left p-1 transition hover:ring-1 hover:ring-white/30 ${day ? '' : 'bg-white/[0.03]'}`}
                      style={sh ? { background: sh.bg, color: sh.ink } : day ? { background: 'rgba(255,255,255,0.08)', color: '#e3e6ee' } : undefined}>
                      <span className={`block text-[10px] ${day ? '' : 'text-slate-600'}`}>{i + 1}</span>
                      {day && day.pnl_value !== 0 && (
                        <span className="hidden sm:block text-[10px] font-semibold truncate">
                          {day.pnl_value > 0 ? '+' : '-'}{Math.abs(day.pnl_value) >= 1000 ? `${(Math.abs(day.pnl_value) / 1000).toFixed(1)}k` : Math.round(Math.abs(day.pnl_value))}
                        </span>
                      )}
                      {notes[date]?.trim() && <span className="absolute top-1 right-1 w-1.5 h-1.5 rounded-full bg-violet-300" />}
                    </button>
                  )
                })}
              </div>
            </div>
          )
        })}
      </div>
      <p className="text-[11px] text-slate-600 mt-3">Day P&amp;L and win rate count positions closed that day, net of all their fees; a partial sell is counted when its position closes. Shading ranks each day against your other winning or losing days. A dot marks a day note.</p>
    </div>
  )
}
