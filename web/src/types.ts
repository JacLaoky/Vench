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
