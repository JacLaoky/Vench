import { X } from 'lucide-react'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd, usd } from '../lib/format'
import type { Position } from '../types'
import StopEditor from './StopEditor'

export default function PositionDrawer({ position, onClose, onStopSaved }: {
  position: Position
  onClose: () => void
  onStopSaved: (stop: number) => void
}) {
  const { data, error, loading, reload } = useApi(
    () => api.getHolding(position.ticker, position.position_id ?? undefined), [position.ticker],
  )

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-[2px]" onClick={onClose} />
      <div className="relative w-full sm:max-w-md bg-surface sm:border-l border-line h-full flex flex-col shadow-2xl pt-[env(safe-area-inset-top)]">
        <div className="flex items-center justify-between px-5 py-4 border-b border-line">
          <div>
            <h2 className="text-lg font-semibold text-white">{position.ticker}</h2>
            <p className="text-xs text-slate-500">
              {position.side} · {position.qty} shares · avg cost ${position.cost_price.toFixed(2)}
              {position.qty > 0 && <> · now ${(position.market_val / position.qty).toFixed(2)}</>}
            </p>
            <p className={`text-xs ${pnlColor(position.today_pl_val)}`}>Today {signedUsd(position.today_pl_val)}</p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white" aria-label="Close"><X size={18} /></button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5 pb-[calc(1.5rem+env(safe-area-inset-bottom))]">
          <div className="grid grid-cols-3 gap-2 text-center">
            <div className="bg-white/[0.03] border border-line rounded-lg py-2">
              <p className="text-[11px] text-slate-500">Unrealized</p>
              <p className={`text-sm font-semibold ${pnlColor(position.pl_val)}`}>{signedUsd(position.pl_val)}</p>
            </div>
            <div className="bg-white/[0.03] border border-line rounded-lg py-2">
              <p className="text-[11px] text-slate-500">Realized (net)</p>
              <p className={`text-sm font-semibold ${pnlColor(data?.total_net_pnl ?? 0)}`}>
                {data ? signedUsd(data.total_net_pnl ?? 0) : '…'}
              </p>
            </div>
            <div className="bg-white/[0.03] border border-line rounded-lg py-2">
              <p className="text-[11px] text-slate-500">R (ledger)</p>
              <p className={`text-sm font-semibold ${rColor(data?.r_multiple)}`}>{data ? fmtR(data.r_multiple) : '…'}</p>
            </div>
          </div>

          {position.position_id ? (
            <section>
              <h3 className="label-caps mb-2">Stop</h3>
              <StopEditor positionId={position.position_id} ticker={position.ticker}
                stop={position.stop_price} onSaved={stop => { onStopSaved(stop); reload() }} />
            </section>
          ) : (
            <p className="text-xs text-slate-500">This holding has no matching fills yet — sync first to edit its stop.</p>
          )}

          <section>
            <h3 className="label-caps mb-2">Fills</h3>
            {loading && <p className="text-sm text-slate-500">Loading…</p>}
            {error && <p className="text-sm text-red-400">Error: {error}</p>}
            {data?.data.map(leg => (
              <div key={leg.order_id} className="flex justify-between items-center text-sm py-1.5 border-b border-line">
                <span className={leg.action.includes('BUY') ? 'text-emerald-400' : 'text-red-400'}>{leg.action}</span>
                <span className="text-slate-300">{leg.qty} @ {usd(leg.price)}</span>
                <span className={`text-xs w-20 text-right ${leg.net_realized_pnl ? pnlColor(leg.net_realized_pnl) : 'text-slate-600'}`}>
                  {leg.net_realized_pnl ? signedUsd(leg.net_realized_pnl) : '—'}
                </span>
                <span className="text-xs text-slate-500 w-20 text-right">{leg.date}</span>
              </div>
            ))}
          </section>
        </div>
      </div>
    </div>
  )
}
