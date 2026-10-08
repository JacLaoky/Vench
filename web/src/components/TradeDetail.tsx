import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd } from '../lib/format'
import type { Trade } from '../types'
import StopEditor from './StopEditor'
import TagEditor from './TagEditor'
import Screenshots from './Screenshots'
import NoteBox from './NoteBox'

export default function TradeDetail({ trade, onUpdate }: { trade: Trade; onUpdate: (patch: Partial<Trade>) => void }) {
  const { data: dayNoteData, setData: setDayNote, error: dayNoteError, loading: dayNoteLoading } = useApi(
    () => api.getDailyNote(trade.exit_date).then(r => r.note ?? ''), [trade.exit_date],
  )
  const dayNote = dayNoteLoading ? null : dayNoteData

  const net = trade.net_pnl ?? trade.pnl

  return (
    <div className="space-y-6">
      <div>
        <div className="flex items-center gap-3 flex-wrap mb-1">
          <h2 className="text-lg font-semibold text-white">{trade.ticker}</h2>
          <span className="text-xs px-2 py-0.5 rounded-full bg-white/10 text-slate-400">{trade.trade_type}</span>
          {trade.position_status === 'open' && (
            <span className="text-xs px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-300">partial exit · still open</span>
          )}
          <span className={`text-lg font-semibold ${pnlColor(net)}`}>{signedUsd(net)} ({trade.pct})</span>
          {trade.r_multiple !== null && (
            <span className={`text-sm font-semibold ${rColor(trade.r_multiple)}`} title="Standardised R from the trading system's R ledger">
              {fmtR(trade.r_multiple)}
            </span>
          )}
        </div>
        <p className="text-xs text-slate-500">{trade.enter_time} → {trade.exit_time} · {trade.holding_time}</p>
      </div>

      <section>
        <h3 className="label-caps mb-2">Transactions</h3>
        {trade.transactions?.map((tx, i) => (
          <div key={i} className="flex justify-between text-sm py-1.5 border-b border-line">
            <span className={tx.action.includes('BUY') ? 'text-emerald-400' : 'text-red-400'}>{tx.action}</span>
            <span className="text-slate-300">{tx.qty} @ {tx.price}</span>
            <span className="text-slate-500 text-xs">{tx.date}</span>
          </div>
        ))}
        {(trade.fee ?? 0) > 0 && (
          <div className="mt-2 pt-2 border-t border-line space-y-1">
            <div className="flex justify-between text-sm">
              <span className="text-slate-500">Commission</span>
              <span className="text-red-400">-${trade.fee.toFixed(2)}</span>
            </div>
            {trade.fee_details?.map(([title, val], i) => (
              <div key={i} className="flex justify-between text-xs text-slate-600">
                <span className="pl-2">{title}</span>
                <span>-${Number(val).toFixed(2)}</span>
              </div>
            ))}
            <div className="flex justify-between text-sm font-medium pt-1 border-t border-line">
              <span className="text-slate-400">Net P&L</span>
              <span className={pnlColor(net)}>{signedUsd(net)}</span>
            </div>
          </div>
        )}
      </section>

      {trade.position_id && (
        <section>
          <h3 className="label-caps mb-2">Entry stop</h3>
          <StopEditor key={trade.position_id} positionId={trade.position_id} ticker={trade.ticker}
            stop={trade.stop_price} locked={trade.stop_locked} onSaved={stop => onUpdate({ stop_price: stop })} />
        </section>
      )}

      <section>
        <h3 className="label-caps mb-2">Tags</h3>
        <TagEditor tradeId={trade.trade_id} tags={trade.tags ?? []} onChange={tags => onUpdate({ tags })} />
      </section>

      <section>
        <h3 className="label-caps mb-2">Screenshots</h3>
        <Screenshots tradeId={trade.trade_id} images={trade.image_paths ?? []}
          onChange={image_paths => onUpdate({ image_paths })} />
      </section>

      <NoteBox key={trade.trade_id} label="Trade note" initial={trade.note ?? ''}
        save={async note => { await api.saveNote(trade.trade_id, note); onUpdate({ note }) }} />

      {dayNoteError ? (
        <p className="text-xs text-red-400">Couldn't load the note for {trade.exit_date}: {dayNoteError}</p>
      ) : dayNote === null ? (
        <p className="text-xs text-slate-600">Loading day note…</p>
      ) : (
        <NoteBox key={trade.exit_date} label={`Day note · ${trade.exit_date}`} initial={dayNote}
          save={async note => { await api.saveDailyNote(trade.exit_date, note); setDayNote(note) }} />
      )}
    </div>
  )
}
