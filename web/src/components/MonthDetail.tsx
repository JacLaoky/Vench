import { api } from '../api'
import { useApi } from '../lib/useApi'
import { fmtR, pnlColor, rColor, signedUsd } from '../lib/format'
import type { JournalMonth } from '../types'
import Drawer from './Drawer'
import { EmptyState, ErrorState, Loading } from './PageState'

function Row({ label, all, won, lost }: { label: string; all: string; won: string; lost: string }) {
  return (
    <tr className="border-b border-line last:border-0">
      <td className="py-1.5 text-slate-400">{label}</td>
      <td className="py-1.5 text-right text-white">{all}</td>
      <td className="py-1.5 text-right text-emerald-400">{won}</td>
      <td className="py-1.5 text-right text-red-400">{lost}</td>
    </tr>
  )
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="card p-4">
      <h3 className="label-caps mb-3">{title}</h3>
      {children}
    </section>
  )
}

export default function MonthDetail({ month, onClose }: { month: JournalMonth; onClose: () => void }) {
  const { data, error, loading, reload } = useApi(() => api.getMonthDetail(month.monthYear), [month.monthYear])
  const s = data?.data

  return (
    <Drawer title={month.monthYear} wide onClose={onClose}
      subtitle={<span>Realized <span className={pnlColor(month.profit_value)}>{signedUsd(month.profit_value)}</span> · {month.closed} positions closed</span>}>
      {loading && !data ? <Loading rows={4} /> : error ? <ErrorState message={error} onRetry={reload} /> : !s ? (
        <EmptyState title="No positions closed this month" />
      ) : (
        <div className="space-y-4">
          <Card title="Gain / loss (per closed position, net of fees)">
            <table className="w-full text-sm">
              <thead><tr className="label-caps"><th /><th className="text-right font-normal">All</th><th className="text-right font-normal">Won</th><th className="text-right font-normal">Lost</th></tr></thead>
              <tbody>
                <Row label="Total" {...s.gain_loss.total} />
                <Row label="Average $" {...s.gain_loss.avg_usd} />
                <Row label="Average %" {...s.gain_loss.avg_pct} />
                <Row label="Positions" {...s.gain_loss.trades} />
              </tbody>
            </table>
            <p className="text-xs text-slate-500 mt-2">Win rate {s.gain_loss.win_rate}</p>
          </Card>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Card title="R (standardised ledger)">
              {s.r.count === 0 ? <p className="text-xs text-slate-500">No R-ledger trades closed this month.</p> : (
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <span className="text-slate-400">Trades</span><span className="text-right text-white">{s.r.count}</span>
                  <span className="text-slate-400">Expectancy</span><span className={`text-right ${rColor(s.r.expectancy_r)}`}>{fmtR(s.r.expectancy_r)}</span>
                  <span className="text-slate-400">Total</span><span className={`text-right ${rColor(s.r.total_r)}`}>{fmtR(s.r.total_r)}</span>
                </div>
              )}
            </Card>
            <Card title="Long / short">
              <table className="w-full text-sm"><tbody>
                <Row label="Long" {...s.long_short.long} />
                <Row label="Short" {...s.long_short.short} />
              </tbody></table>
            </Card>
            <Card title="Timing">
              <table className="w-full text-sm"><tbody>
                <Row label="Avg hold" {...s.timing.holding} />
                <Row label="Avg entry (ET)" {...s.timing.entry_hour} />
              </tbody></table>
            </Card>
            <Card title="Best / worst">
              <div className="grid grid-cols-2 gap-2 text-sm">
                <span className="text-slate-400">Largest win</span>
                <span className="text-right text-emerald-400">{s.best_worst.largest_usd.won} ({s.best_worst.largest_pct.won})</span>
                <span className="text-slate-400">Largest loss</span>
                <span className="text-right text-red-400">{s.best_worst.largest_usd.lost} ({s.best_worst.largest_pct.lost})</span>
              </div>
            </Card>
          </div>

          <Card title="By symbol">
            <table className="w-full text-sm">
              <thead><tr className="label-caps"><th className="text-left font-normal">Symbol</th><th className="text-right font-normal">Positions</th><th className="text-right font-normal">W / L</th><th className="text-right font-normal">P&L</th></tr></thead>
              <tbody>
                {s.symbols_by_amount.map(sym => (
                  <tr key={sym.symbol} className="border-b border-line last:border-0">
                    <td className="py-1.5 text-white">{sym.symbol}</td>
                    <td className="py-1.5 text-right text-slate-400">{sym.trades.all}</td>
                    <td className="py-1.5 text-right text-slate-400">{sym.trades.won} / {sym.trades.lost}</td>
                    <td className={`py-1.5 text-right ${pnlColor(sym.pnl_raw)}`}>{signedUsd(sym.pnl_raw)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </div>
      )}
    </Drawer>
  )
}
