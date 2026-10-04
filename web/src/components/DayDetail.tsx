import { useMemo, useState } from 'react'
import { ChevronLeft } from 'lucide-react'
import { api } from '../api'
import { fmtR, pnlColor, rColor, signedUsd, usd } from '../lib/format'
import type { JournalDay, Trade } from '../types'
import Drawer from './Drawer'
import NoteBox from './NoteBox'
import TradeDetail from './TradeDetail'

const fullDate = (date: string) =>
  new Date(`${date}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', year: 'numeric' })

/** One day: stats, the day's note, and its exits grouped by ticker → position. `day` is absent
 *  for days without fills (e.g. a calendar day), which still get a note. */
export default function DayDetail({ date, day, note, onNoteSaved, onTradeUpdate, onClose }: {
  date: string
  day?: JournalDay
  note: string
  onNoteSaved: (note: string) => void
  onTradeUpdate: (tradeId: string, patch: Partial<Trade>) => void
  onClose: () => void
}) {
  const [openTradeId, setOpenTradeId] = useState<string | null>(null)
  const tickers = useMemo(() => (day?.tickers ?? []).filter(t => t.trades.length > 0), [day])
  const openTrade = tickers.flatMap(t => t.trades).find(t => t.trade_id === openTradeId) ?? null

  return (
    <Drawer title={fullDate(date)} onClose={onClose} wide
      subtitle={day ? `${day.trades} fills · ${day.closed} positions closed · commission ${usd(day.comm_value)}` : 'No fills this day'}>
      {openTrade ? (
        <>
          <button onClick={() => setOpenTradeId(null)} className="flex items-center gap-1 text-sm text-slate-400 hover:text-white mb-4">
            <ChevronLeft size={16} /> {fullDate(date)}
          </button>
          <TradeDetail trade={openTrade} onUpdate={patch => onTradeUpdate(openTrade.trade_id, patch)} />
        </>
      ) : (
        <div className="space-y-6">
          {day && (
            <div className="grid grid-cols-3 gap-2 text-center">
              <div className="bg-white/[0.03] border border-line rounded-lg py-2">
                <p className="text-[11px] text-slate-500">Closed P&amp;L (net)</p>
                <p className={`text-sm font-semibold ${pnlColor(day.pnl_value)}`}>{signedUsd(day.pnl_value)}</p>
              </div>
              <div className="bg-white/[0.03] border border-line rounded-lg py-2">
                <p className="text-[11px] text-slate-500">Won / Lost</p>
                <p className="text-sm font-semibold text-white">{day.wins} / {day.losses}</p>
              </div>
              <div className="bg-white/[0.03] border border-line rounded-lg py-2">
                <p className="text-[11px] text-slate-500">Win rate</p>
                <p className="text-sm font-semibold text-white">{day.closed ? day.winPct : '—'}</p>
              </div>
              {day.partial_value !== 0 && (
                <p className="col-span-3 text-[11px] text-slate-500 text-left">
                  Partial exits from positions still open: <span className={pnlColor(day.partial_value)}>{signedUsd(day.partial_value)}</span> (counted on the day the position closes)
                </p>
              )}
            </div>
          )}

          <NoteBox key={date} label="Day note" initial={note}
            save={async text => { await api.saveDailyNote(date, text); onNoteSaved(text) }} />

          {tickers.length > 0 && (
            <section>
              <h3 className="label-caps mb-2">Exits</h3>
              <div className="space-y-3">
                {tickers.map(t => {
                  const net = t.trades.reduce((s, x) => s + (x.net_pnl ?? x.pnl), 0)
                  return (
                    <div key={t.name} className="card overflow-hidden">
                      <div className="flex justify-between items-center px-3 py-2 border-b border-line">
                        <span className="font-medium text-white">{t.name}</span>
                        <span className={`text-sm font-medium ${pnlColor(net)}`}>{signedUsd(net)}</span>
                      </div>
                      {t.trades.map(trade => {
                        const tnet = trade.net_pnl ?? trade.pnl
                        return (
                          <button key={trade.trade_id} onClick={() => setOpenTradeId(trade.trade_id)}
                            className="w-full flex justify-between items-center px-3 py-2 text-left hover:bg-white/[0.03] border-b border-line last:border-0">
                            <span className="text-xs text-slate-400">
                              {trade.trade_type} · {trade.qty} @ ${trade.price.toFixed(2)}
                              {trade.position_status === 'open' && <span className="text-amber-300"> · partial</span>}
                            </span>
                            <span className="flex items-center gap-3">
                              {trade.r_multiple !== null && <span className={`text-xs ${rColor(trade.r_multiple)}`}>{fmtR(trade.r_multiple)}</span>}
                              <span className={`text-sm ${pnlColor(tnet)}`}>{signedUsd(tnet)}</span>
                            </span>
                          </button>
                        )
                      })}
                    </div>
                  )
                })}
              </div>
            </section>
          )}
        </div>
      )}
    </Drawer>
  )
}
