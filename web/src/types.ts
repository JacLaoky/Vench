export interface Position {
  ticker: string
  name: string
  qty: number
  can_sell_qty: number
  cost_price: number
  market_val: number
  pl_val: number
  pl_ratio: number
  today_pl_val: number
  side: string
  position_id: string | null
  stop_price: number | null
}

export interface Account {
  status: string
  total_assets?: number
  securities_assets?: number
}

export interface Transaction { action: string; date: string; price: string; qty: string }

/** One exit fill (partial or final) of a position, as returned by /api/all_trades and /api/journal. */
export interface Trade {
  trade_id: string
  position_id: string | null
  position_status: 'open' | 'closed' | null
  ticker: string
  trade_type: 'LONG' | 'SHORT'
  pnl: number
  net_pnl: number
  pct: string
  isProfit: boolean
  exit_date: string
  enter_time: string
  exit_time: string
  holding_time: string
  entry_price: number
  price: number
  qty: number
  note: string
  image_paths: string[]
  tags: string[]
  transactions: Transaction[]
  fee: number
  fee_details: [string, number][]
  stop_price: number | null
  /** Standardised R from the trading system's R ledger; set on the final exit of ledger trades. */
  r_multiple: number | null
}

export interface HoldingLeg {
  order_id: string
  action: string
  price: number
  qty: number
  realized_pnl: number
  net_realized_pnl: number
  fee: number
  date: string
  time: string
}

export interface HoldingDetail {
  status: string
  data: HoldingLeg[]
  total_pnl?: number
  total_net_pnl?: number
  entry_price?: number
  stop_price: number | null
  r_multiple: number | null
}

/** R statistics from the trading system's R ledger (one fixed 1R unit per trade). */
export interface RStats {
  source: string
  ledger: { ok: boolean | null; message: string; fetched_at: string | null; trades: number }
  count: number
  expectancy_r: number | null
  avg_win_r: number | null
  avg_loss_r: number | null
  total_r: number | null
  win_rate: number | null
  distribution: { label: string; count: number }[]
}

export interface TagCount { tag: string; count: number }

export interface JournalDay {
  date: string
  weekday: string
  pnl_value: number        // realized P&L of every exit this day (partials included), net of fees
  comm_value: number
  exits: number            // sells this day (partials included): they make up pnl_value
  closed: number           // positions that went flat this day: wins/losses/winPct count these
  wins: string
  losses: string
  winPct: string           // "—" when no position closed
  trades: string
  tickers: { name: string; win: boolean; trades: Trade[] }[]
}

export interface JournalMonth {
  month_key: string
  monthYear: string
  profit_value: number
  win_rate: number | null  // share of positions closed this month that won; null if none closed
  exits: number
  closed: number
  avgGain: string
  chart_data: { date: string; value: number }[]
}

export interface JournalResponse { daily: JournalDay[]; monthly: JournalMonth[] }

type AllWonLost = { all: string; won: string; lost: string }
export interface SymbolStat {
  symbol: string
  pnl_raw: number
  isProfit: boolean
  trades: AllWonLost
  amount: AllWonLost
}

/** One exit fill (partial sells included) with its realized P&L net of fees. */
export interface RealizedExit {
  time: string
  direction: string
  qty: number
  price: number
  avg_cost: number
  net: number
  pct: number
  kind: 'close' | 'partial'
  r: number | null
}

/** Realized P&L of one symbol over the period, with the exits behind it (newest first). */
export interface SymbolRealized {
  symbol: string
  pnl_raw: number
  isProfit: boolean
  exits: number
  won: number
  lost: number
  rows: RealizedExit[]
}

export interface DeepStats {
  gain_loss: { total: AllWonLost; avg_usd: AllWonLost; avg_pct: AllWonLost; trades: AllWonLost; win_rate: string }
  long_short: { long: AllWonLost; short: AllWonLost }
  timing: { holding: AllWonLost; entry_hour: AllWonLost }
  best_worst: { largest_usd: { won: string; lost: string }; largest_pct: { won: string; lost: string } }
  symbols_by_trades: SymbolStat[]
  symbols_by_amount: SymbolStat[]
}

export interface TagStat {
  tag: string
  count: number
  wins: number
  losses: number
  win_rate: number
  total_pnl: number
  avg_pnl: number
  avg_win: number
  avg_loss: number
  best_trade: number
  worst_trade: number
}

export interface SectorDetail {
  ticker: string
  price: number
  change_1d: number
  closes_50d: number[]
  ma10: number; ma10_pct: number
  ma20: number; ma20_pct: number
  ma50: number; ma50_pct: number
  ma200: number; ma200_pct: number
  rsi14: number | null
  ytd_pct: number
  week52_high: number
  week52_high_pct: number
}

export interface RecapStats {
  trades: number
  wins: number
  losses: number
  win_pct: number | null
  loss_pct: number | null
  avg_gain_pct: number | null
  avg_loss_pct: number | null
  largest_gain_pct: number | null
  largest_loss_pct: number | null
  avg_days_gain: number | null
  avg_days_loss: number | null
  net_pnl: number
  avg_r: number | null
  /** swing scope only */
  return_pct?: number
  cumulative_pct?: number
  capital_start?: number
  /** capital moved into (+) / out of (−) the swing pool */
  flows?: number
}

export interface RecapResponse {
  status: string
  scope: 'swing' | 'all'
  year: number
  years: number[]
  months: (RecapStats & { month: string })[]
  summary: RecapStats
  pool: { initial_base: number; pnl_offset: number; current: number; updated_at: string | null } | null
}
