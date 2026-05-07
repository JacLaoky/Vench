import { useEffect, useState } from 'react'
import { api } from '../api'

interface Event {
  ticker: string
  time: string
}

interface DayEntry {
  date: string
  day_label: string
  events: Event[]
}

export default function Calendar() {
  const [days, setDays] = useState<DayEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    api.getEarningsCalendar()
      .then(d => setDays(d.data ?? []))
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  if (loading) return <div className="text-slate-500 text-sm">Loading…</div>
  if (error) return <div className="text-red-400 text-sm">Error: {error}</div>

  return (
    <div>
      <h1 className="text-xl font-semibold text-white mb-6">Earnings Calendar</h1>

      {days.length === 0 && <p className="text-slate-500 text-sm">No upcoming earnings data.</p>}

      <div className="space-y-3">
        {days.map(day => (
          <div key={day.date} className="bg-white/5 rounded-xl border border-white/10 overflow-hidden">
            <div className="px-4 py-2 border-b border-white/10">
              <h2 className="text-sm font-medium text-slate-300">{day.day_label}</h2>
            </div>
            <div className="flex flex-wrap gap-2 px-4 py-3">
              {day.events.map(ev => (
                <div key={ev.ticker} className="flex items-center gap-1.5 bg-white/5 border border-white/10 rounded-lg px-3 py-1.5">
                  <span className="font-medium text-white text-sm">{ev.ticker}</span>
                  <span className="text-xs text-slate-500">{ev.time}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
