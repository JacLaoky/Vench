import { LineChart, Line, ResponsiveContainer, YAxis } from 'recharts'
import { api } from '../api'
import { useApi } from '../lib/useApi'
import Drawer from './Drawer'
import { ErrorState, Loading } from './PageState'

const pct = (n: number) => `${n >= 0 ? '+' : ''}${n.toFixed(2)}%`
const tone = (n: number) => (n >= 0 ? 'text-emerald-400' : 'text-red-400')

function RsiGauge({ rsi }: { rsi: number }) {
  const label = rsi >= 70 ? 'Overbought' : rsi <= 30 ? 'Oversold' : 'Neutral'
  const color = rsi >= 70 ? 'text-red-400' : rsi <= 30 ? 'text-emerald-400' : 'text-slate-300'
  return (
    <div>
      <div className="flex justify-between text-sm mb-2">
        <span className="text-slate-400">RSI 14</span>
        <span className={color}>{rsi.toFixed(1)} · {label}</span>
      </div>
      <div className="relative h-2 rounded-full bg-gradient-to-r from-emerald-500/40 via-slate-500/30 to-red-500/40">
        <div className="absolute top-0 bottom-0 w-px bg-white/30" style={{ left: '30%' }} />
        <div className="absolute top-0 bottom-0 w-px bg-white/30" style={{ left: '70%' }} />
        <div className="absolute -top-1 w-1.5 h-4 rounded bg-white" style={{ left: `calc(${Math.min(100, Math.max(0, rsi))}% - 3px)` }} />
      </div>
      <div className="flex justify-between text-[10px] text-slate-600 mt-1"><span>0</span><span>30</span><span>70</span><span>100</span></div>
    </div>
  )
}

export default function SectorDrawer({ ticker, name, onClose }: { ticker: string; name: string; onClose: () => void }) {
  const { data: d, error, loading, reload } = useApi(() => api.getSectorDetail(ticker), [ticker])

  return (
    <Drawer title={name} subtitle={ticker} onClose={onClose}>
      {loading && !d ? <Loading rows={3} /> : error || !d ? <ErrorState message={error || 'No data'} onRetry={reload} /> : (
        <div className="space-y-5">
          <div className="flex items-end justify-between">
            <div>
              <p className="text-2xl font-semibold text-white">${d.price.toFixed(2)}</p>
              <p className={`text-sm ${tone(d.change_1d)}`}>{pct(d.change_1d)} today</p>
            </div>
            <div className="text-right text-xs space-y-0.5">
              <p><span className="text-slate-500">YTD </span><span className={tone(d.ytd_pct)}>{pct(d.ytd_pct)}</span></p>
              <p><span className="text-slate-500">vs 52w high </span><span className={tone(-d.week52_high_pct)}>{d.week52_high_pct === 0 ? 'at high' : `-${Math.abs(d.week52_high_pct).toFixed(2)}%`}</span></p>
            </div>
          </div>

          {d.closes_50d?.length > 1 && (
            <div className="h-28 bg-white/5 rounded-xl border border-white/10 p-2">
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={d.closes_50d.map((c, i) => ({ i, c }))}>
                  <YAxis domain={['dataMin', 'dataMax']} hide />
                  <Line type="monotone" dataKey="c" dot={false} strokeWidth={2} isAnimationActive={false}
                    stroke={d.closes_50d[d.closes_50d.length - 1] >= d.closes_50d[0] ? '#34d399' : '#f87171'} />
                </LineChart>
              </ResponsiveContainer>
              <p className="text-[10px] text-slate-600 -mt-1 px-1">Last 50 sessions</p>
            </div>
          )}

          <div className="grid grid-cols-2 gap-2">
            {([['MA 10', d.ma10, d.ma10_pct], ['MA 20', d.ma20, d.ma20_pct], ['MA 50', d.ma50, d.ma50_pct], ['MA 200', d.ma200, d.ma200_pct]] as const).map(([label, ma, dist]) => (
              <div key={label} className="bg-white/5 rounded-lg border border-white/10 px-3 py-2">
                <p className="text-[11px] text-slate-500">{label}</p>
                <p className="text-sm text-white">${ma.toFixed(2)}</p>
                <p className={`text-[11px] ${tone(dist)}`}>price {pct(dist)}</p>
              </div>
            ))}
          </div>

          {d.rsi14 !== null && <RsiGauge rsi={d.rsi14} />}
        </div>
      )}
    </Drawer>
  )
}
