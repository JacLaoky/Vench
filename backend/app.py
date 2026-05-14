import os
# Fix Protobuf compatibility — must be set before any moomoo import
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

from dotenv import load_dotenv
load_dotenv()  # loads .env from current directory
import uuid
import json
import atexit
import time as _time
import threading
import collections
from datetime import datetime
import sqlite3
import pandas as pd
from flask import Flask, request, jsonify, send_from_directory, Response, stream_with_context
from flask_cors import CORS
from moomoo import *
from flask import Response, stream_with_context  # re-import after moomoo to avoid shadowing

app = Flask(__name__)
CORS(app)

# ======================== ⚙️ Configuration ========================
MOOMOO_ACC_ID = int(os.environ.get('MOOMOO_ACC_ID', '0'))
TRD_ENV   = TrdEnv.REAL
HOST_IP   = os.environ.get('MOOMOO_HOST', '127.0.0.1')
HOST_PORT = int(os.environ.get('MOOMOO_PORT', '11111'))
DB_FILE         = 'local.db'
UPLOAD_DIR      = 'trade_images'          # local directory for trade screenshots
DEEPSEEK_API_KEY = os.environ.get('DEEPSEEK_API_KEY', '')
SYNC_COOLDOWN_SECS = 30              # minimum seconds between /api/sync calls
SECTOR_CACHE_SECS  = 60              # /api/sectors cache TTL (11 sectors, fast)
THEME_CACHE_SECS   = 600             # /api/sectors?type=theme cache TTL (large pool, slow)
THEME_TOP_N        = 15              # number of top themes to return
THEME_WORKERS      = 8               # parallel fetch threads

_last_sync_time: float = 0.0        # epoch time of last completed sync
_sector_cache: dict | None = None   # sector data cache
_sector_cache_time: float = 0.0     # cache write time
_account_cache: dict | None = None  # account balance cache
_account_cache_time: float = 0.0    # account balance cache write time
ACCOUNT_CACHE_SECS = 60             # /api/account cache TTL
_detail_cache: dict = {}            # sector_detail cache, keyed by ticker
_detail_cache_time: dict = {}       # sector_detail cache write time
BREADTH_CACHE_SECS  = 120           # market breadth cache
EARNINGS_CACHE_SECS = 3600         # earnings calendar cache (1 hour)
_breadth_cache: dict | None = None
_breadth_cache_time: float  = 0.0
_earnings_cache: dict | None = None
_earnings_cache_time: float  = 0.0

# ── Moomoo kline rate limiter (max 55 calls / 30 s, 5-call safety margin) ──────
class _KlineRateLimiter:
    """Sliding-window rate limiter: at most max_calls within window_secs.
    Automatically sleeps when the limit is reached.
    """
    def __init__(self, max_calls: int = 55, window_secs: float = 30.0):
        self._max    = max_calls
        self._window = window_secs
        self._lock   = threading.Lock()
        self._calls: collections.deque = collections.deque()

    def acquire(self):
        with self._lock:
            now = _time.time()
            # Drop timestamps outside the window
            while self._calls and now - self._calls[0] > self._window:
                self._calls.popleft()
            # If full, wait until the oldest entry expires
            if len(self._calls) >= self._max:
                wait = self._window - (now - self._calls[0]) + 0.05
                if wait > 0:
                    _time.sleep(wait)
                now = _time.time()
                while self._calls and now - self._calls[0] > self._window:
                    self._calls.popleft()
            self._calls.append(_time.time())

_kline_limiter = _KlineRateLimiter(max_calls=55, window_secs=30)

# ======================== 📂 Load ETF list from etfs.json ========================
def _load_etfs() -> tuple[dict, dict]:
    """Read etfs.json and return (sector_map, theme_map).
    theme_map flattens all theme groups into a single dict.
    Returns empty dicts if the file is missing — server still starts.
    """
    etf_file = os.path.join(os.path.dirname(__file__), 'etfs.json')
    try:
        with open(etf_file, 'r', encoding='utf-8') as f:
            raw = json.load(f)
        sector_map = raw.get('sectors', {})
        # themes is a grouped structure; flatten into a single dict
        theme_raw  = raw.get('themes', {})
        theme_map  = {}
        for group in theme_raw.values():
            theme_map.update(group)
        return sector_map, theme_map
    except FileNotFoundError:
        print('[etfs] etfs.json not found, using empty maps')
        return {}, {}
    except Exception as e:
        print(f'[etfs] Failed to load etfs.json: {e}')
        return {}, {}

SECTOR_ETFS, THEME_ETFS = _load_etfs()

MARKET_INDICES = {
    'S&P 500':      'US.SPY',
    'Nasdaq 100':   'US.QQQ',
    'Russell 2000': 'US.IWM',
    'Dow Jones':    'US.DIA',
}

def _get_dynamic_tickers() -> list[str]:
    """Return deduplicated list of stock tickers from trade history + current holdings.
    Options tickers (contain spaces or special chars like C/P + strike) are excluded.
    """
    import re
    tickers = set()

    # From trade history in SQLite
    try:
        conn = sqlite3.connect(DB_FILE)
        rows = conn.execute("SELECT DISTINCT code FROM trades").fetchall()
        conn.close()
        for (code,) in rows:
            # Strip exchange prefix (e.g. 'US.AAPL' -> 'AAPL')
            raw = code.split('.')[-1] if '.' in code else code
            # Skip options: contain digits + C/P pattern or spaces
            if re.search(r'\d', raw) or ' ' in raw:
                continue
            tickers.add(raw.upper())
    except Exception as e:
        print(f'[earnings] db ticker fetch error: {e}')

    # From current Moomoo holdings
    try:
        ret, data = trd_ctx.position_list_query(trd_env=TRD_ENV, acc_id=MOOMOO_ACC_ID)
        if ret == RET_OK and not data.empty:
            for code in data['code']:
                raw = code.split('.')[-1] if '.' in code else code
                if not re.search(r'\d', raw) and ' ' not in raw:
                    tickers.add(raw.upper())
    except Exception as e:
        print(f'[earnings] holdings ticker fetch error: {e}')

    return sorted(tickers)

# ======================== Database Initialization ========================
def _add_column_if_missing(conn, table: str, column: str, col_def: str):
    """Safe ALTER TABLE: only runs if the column doesn't already exist."""
    existing = {row[1] for row in conn.execute(f'PRAGMA table_info({table})')}
    if column not in existing:
        conn.execute(f'ALTER TABLE {table} ADD COLUMN {column} {col_def}')


def init_db():
    """Create tables on first run; idempotent on subsequent runs (includes migrations)."""
    os.makedirs(UPLOAD_DIR, exist_ok=True)   # ensure screenshot directory exists

    conn = sqlite3.connect(DB_FILE)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS trades (
            order_id    TEXT PRIMARY KEY,
            code        TEXT NOT NULL,
            trd_side    TEXT NOT NULL,
            price       REAL NOT NULL,
            qty         REAL NOT NULL,
            create_time TEXT NOT NULL
        )
    ''')

    # trade_notes: keyed by closing order_id, stores note text and screenshot paths
    conn.execute('''
        CREATE TABLE IF NOT EXISTS trade_notes (
            trade_id    TEXT PRIMARY KEY,
            note        TEXT    NOT NULL DEFAULT \'\',
            image_paths TEXT    NOT NULL DEFAULT \'[]\',
            updated_at  TEXT    NOT NULL
        )
    ''')

    # daily_notes: keyed by date string, stores daily review notes
    conn.execute('''
        CREATE TABLE IF NOT EXISTS daily_notes (
            date        TEXT PRIMARY KEY,
            note        TEXT NOT NULL DEFAULT \'\',
            updated_at  TEXT NOT NULL
        )
    ''')

    # Schema migrations: safely add new columns (no-op if already present)
    # Example: _add_column_if_missing(conn, 'trades', 'new_col', 'TEXT DEFAULT ""')
    _add_column_if_missing(conn, 'trades', 'tags', "TEXT NOT NULL DEFAULT '[]'")
    _add_column_if_missing(conn, 'trades', 'position_id', "TEXT")

    conn.execute('''
        CREATE TABLE IF NOT EXISTS position_stops (
            position_id  TEXT PRIMARY KEY,
            ticker       TEXT NOT NULL,
            stop_price   REAL NOT NULL,
            updated_at   TEXT NOT NULL
        )
    ''')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS position_pnl (
            position_id  TEXT PRIMARY KEY,
            code         TEXT NOT NULL,
            realized_pnl REAL NOT NULL,
            is_win       INTEGER NOT NULL,
            open_time    TEXT,
            close_time   TEXT
        )
    ''')

    # ticker_pnl: per-ticker net P&L view (use this for ranking/win-rate questions)
    conn.execute('''
        CREATE VIEW IF NOT EXISTS ticker_pnl AS
        SELECT
            code,
            COUNT(*)                              AS total_positions,
            SUM(is_win)                           AS wins,
            COUNT(*) - SUM(is_win)                AS losses,
            ROUND(SUM(realized_pnl), 2)           AS net_pnl,
            ROUND(MAX(realized_pnl), 2)           AS best_position,
            ROUND(MIN(realized_pnl), 2)           AS worst_position,
            ROUND(SUM(is_win)*100.0/COUNT(*), 1)  AS win_rate_pct
        FROM position_pnl
        GROUP BY code
    ''')

    conn.commit()
    conn.close()
    print("Database initialized (including notes tables)")

init_db()


def assign_position_ids(conn=None):
    """
    Process all trades chronologically per ticker.
    When qty crosses zero (new position opens), assign a new position_id.
    Format: '{TICKER}_{seq}' e.g. 'NVDA_3'
    Updates the position_id column in the trades table.
    """
    should_close = conn is None
    if conn is None:
        conn = sqlite3.connect(DB_FILE)

    rows = conn.execute(
        'SELECT order_id, code, trd_side, qty, create_time FROM trades ORDER BY create_time ASC'
    ).fetchall()

    position_qty = {}   # ticker -> running qty
    position_seq = {}   # ticker -> sequence counter
    position_cur = {}   # ticker -> current position_id

    updates = []
    for order_id, code, side, qty, create_time in rows:
        ticker = code
        qty    = float(qty)

        prev_qty = position_qty.get(ticker, 0.0)

        # Compute new running qty
        # BUY / BUY_BACK both add shares; SELL / SELL_SHORT both subtract
        if side in ('BUY', 'BUY_BACK'):
            new_qty = prev_qty + qty
        else:  # SELL, SELL_SHORT
            new_qty = prev_qty - qty

        # Snap to zero if floating point near-zero
        if abs(new_qty) < 0.001:
            new_qty = 0.0

        # New position starts when previous qty was 0 and now non-zero
        if abs(prev_qty) < 0.001 and abs(new_qty) >= 0.001:
            seq = position_seq.get(ticker, 0) + 1
            position_seq[ticker]  = seq
            position_cur[ticker]  = f'{ticker}_{seq}'

        position_qty[ticker] = new_qty
        updates.append((position_cur.get(ticker), order_id))

    conn.executemany('UPDATE trades SET position_id=? WHERE order_id=?', updates)
    conn.commit()

    if should_close:
        conn.close()

    print(f'[positions] assigned position_ids to {len(updates)} trades')


assign_position_ids()

# ======================== Moomoo Connection ========================
trd_ctx   = OpenSecTradeContext(filter_trdmarket=TrdMarket.US,
                                host=HOST_IP, port=HOST_PORT,
                                security_firm=SecurityFirm.FUTUSG)
quote_ctx = OpenQuoteContext(host=HOST_IP, port=HOST_PORT)

# Gracefully close both connections on process exit
atexit.register(lambda: (trd_ctx.close(), quote_ctx.close()))


# ======================== 🛠️ Utilities ========================

def get_multiplier(code: str) -> float:
    """Auto-detect options multiplier: ticker with digits → options (×100), else stock (×1)."""
    clean = code.split('.')[-1]
    return 100.0 if any(c.isdigit() for c in clean) else 1.0


def fmt_holding(delta) -> str:
    """Format a timedelta into a human-readable holding duration."""
    secs = delta.total_seconds()
    if secs < 60:      return "a few seconds"
    if secs < 3600:    return f"{int(secs / 60)} minutes"
    if delta.days == 0: return f"{int(secs / 3600)} hours"
    return f"{delta.days} days"


def find_round_trip(df: pd.DataFrame, ticker: str,
                    exit_time, trade_type: str) -> tuple:
    """
    Walk backwards through df to find the full round-trip for this closing trade.

    Returns:
        transactions : list[dict]  — all legs in chronological order
        enter_time   : Timestamp   — time of the first entry leg
    """
    history = (
        df[(df['code'] == ticker) & (df['create_time'] <= exit_time)]
        .sort_values('create_time', ascending=False)
    )

    transactions = []
    enter_time   = exit_time
    qty_balance  = 0.0

    for _, h in history.iterrows():
        h_side  = h['trd_side']
        h_qty   = float(h['qty'])
        h_price = float(h['price'])
        h_time  = h['create_time']

        transactions.append({
            "date":   h_time.strftime('%m/%d %I:%M %p'),
            "action": h_side,
            "qty":    str(int(h_qty)),
            "price":  f"${h_price:.4f}",
        })

        # Accumulate qty by direction until it reaches zero (entry found)
        # BUY_BACK closes a short (acts like BUY); SELL_SHORT opens a short (acts like SELL)
        if trade_type == 'LONG':
            qty_balance += h_qty if h_side in ('SELL', 'SELL_SHORT') else -h_qty
        else:
            qty_balance += h_qty if h_side in ('BUY', 'BUY_BACK') else -h_qty

        enter_time = h_time
        if abs(qty_balance) < 0.001:
            break

    transactions.reverse()   # restore chronological order
    return transactions, enter_time


def build_trade_card(row, df: pd.DataFrame) -> dict:
    """
    Build a trade card dict from a closing row and the full trades DataFrame.
    Calls find_round_trip internally; shared by all routes.
    """
    exit_time  = row['create_time']
    ticker_raw = row['code']
    clean_name = ticker_raw.replace('US.', '')
    side       = row['trd_side']
    pnl        = row['realized_pnl']
    trade_type = "LONG" if side == 'SELL' else "SHORT"

    # Scope find_round_trip to this position only (if position_id available)
    row_pos_id = row.get('position_id') if hasattr(row, 'get') else getattr(row, 'position_id', None)
    if row_pos_id and 'position_id' in df.columns:
        trip_df = df[df['position_id'] == row_pos_id]
    else:
        trip_df = df  # fallback: old behaviour (all ticker history)

    transactions, enter_time = find_round_trip(trip_df, ticker_raw, exit_time, trade_type)

    holding_str = fmt_holding(exit_time - enter_time)

    multiplier  = get_multiplier(ticker_raw)
    trade_value = float(row['price']) * float(row['qty']) * multiplier
    pct         = (pnl / trade_value * 100) if trade_value > 0 else 0

    # Compute weighted-average entry price from the BUY/SELL_SHORT legs
    # Used by the frontend for correct R = pnl / (|entry - stop| × qty)
    if trade_type == 'LONG':
        entry_actions = ('BUY', 'BUY_BACK')
    else:
        entry_actions = ('SELL', 'SELL_SHORT')
    entry_legs = [t for t in transactions if t['action'] in entry_actions]
    if entry_legs:
        total_entry_qty = sum(float(t['qty']) for t in entry_legs)
        entry_price = (
            sum(float(t['price'].replace('$', '')) * float(t['qty']) for t in entry_legs)
            / total_entry_qty
        ) if total_entry_qty > 0 else 0.0
    else:
        entry_price = 0.0

    # Load existing note and images for this trade (empty defaults if none)
    trade_id = str(row['order_id'])
    conn = sqlite3.connect(DB_FILE)
    note_row = conn.execute(
        'SELECT note, image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()
    tags_row = conn.execute(
        'SELECT tags, position_id FROM trades WHERE order_id = ?', (trade_id,)
    ).fetchone()
    saved_note     = note_row[0] if note_row else ''
    saved_images   = json.loads(note_row[1]) if note_row else []
    saved_tags     = json.loads(tags_row[0]) if tags_row and tags_row[0] else []
    position_id    = tags_row[1] if tags_row and tags_row[1] else None

    # Look up stop price for this position
    stop_price = None
    if position_id:
        stop_row = conn.execute(
            'SELECT stop_price FROM position_stops WHERE position_id=?', (position_id,)
        ).fetchone()
        stop_price = stop_row[0] if stop_row else None
    conn.close()

    return {
        "trade_id":     trade_id,
        "day":          exit_time.strftime('%d'),
        "month":        exit_time.strftime('%b'),
        "ticker":       clean_name,
        "trade_type":   trade_type,
        "pnl":          round(pnl, 2),
        "pct":          f"{int(pct)}%",
        "isProfit":     pnl >= 0,
        "transactions": transactions,
        "enter_time":   enter_time.strftime('%a %d %b %I:%M %p'),
        "exit_time":    exit_time.strftime('%a %d %b %I:%M %p'),
        "holding_time": holding_str,
        "trade_count":  str(len(transactions)),
        "note":         saved_note,
        "image_paths":  saved_images,
        "tags":         saved_tags,
        "position_id":  position_id,
        "stop_price":   stop_price,
        "price":        float(row['price']),
        "qty":          float(row['qty']),
        "entry_price":  round(entry_price, 4),
    }


# ======================== Data Access Layer (with cache) ========================

# Module-level PnL cache: avoids recomputing on every API request
_pnl_cache: pd.DataFrame | None = None


def invalidate_cache():
    """Call after syncing data to clear the PnL cache."""
    global _pnl_cache
    _pnl_cache = None


def load_df_with_pnl() -> pd.DataFrame:
    """
    Read SQLite → cast types → compute PnL, cached in a module variable.
    Returns the cached copy if still valid to avoid repeated I/O.
    """
    global _pnl_cache
    if _pnl_cache is not None:
        return _pnl_cache.copy()

    conn = sqlite3.connect(DB_FILE)
    df   = pd.read_sql_query("SELECT * FROM trades", conn)
    conn.close()

    if df.empty:
        return df   # empty table: return early without caching

    df['price']       = pd.to_numeric(df['price'])
    df['qty']         = pd.to_numeric(df['qty'])
    df['create_time'] = pd.to_datetime(df['create_time'], format='mixed')

    _pnl_cache = calculate_trades_pnl(df)
    print("♻️  PnL cache updated")
    return _pnl_cache.copy()


def slice_by_period(df: pd.DataFrame, period: str) -> pd.DataFrame:
    """Slice a PnL DataFrame by the given period parameter."""
    now = pd.Timestamp.now()

    offsets = {
        '1W':  pd.DateOffset(weeks=1),
        '1M':  pd.DateOffset(months=1),
        '3M':  pd.DateOffset(months=3),
        '1Y':  pd.DateOffset(years=1),
    }

    if period in offsets:
        return df[df['create_time'] >= now - offsets[period]].copy()
    if period == 'YTD':
        ytd_start = pd.Timestamp(year=now.year, month=1, day=1)
        return df[df['create_time'] >= ytd_start].copy()
    return df.copy()   # 'AT' = All Time



def _write_position_pnl():
    """Write FIFO-accurate pnl per position into position_pnl table for RAG SQL queries."""
    try:
        df = load_df_with_pnl()
        closed = df[df['realized_pnl'] != 0][
            ['position_id', 'code', 'realized_pnl', 'is_win', 'create_time']
        ].copy()
        if closed.empty:
            return

        # Aggregate by position_id (partial closes → one row per position)
        agg = closed.groupby('position_id').agg(
            code=('code', 'first'),
            realized_pnl=('realized_pnl', 'sum'),
            open_time=('create_time', 'min'),
            close_time=('create_time', 'max'),
        ).reset_index()
        agg['is_win'] = (agg['realized_pnl'] > 0).astype(int)

        conn = sqlite3.connect(DB_FILE)
        conn.execute("DELETE FROM position_pnl")
        conn.executemany(
            "INSERT INTO position_pnl (position_id, code, realized_pnl, is_win, open_time, close_time) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            [
                (
                    row['position_id'],
                    row['code'],
                    round(float(row['realized_pnl']), 2),
                    int(row['is_win']),
                    str(row['open_time']),
                    str(row['close_time']),
                )
                for _, row in agg.iterrows()
            ]
        )
        conn.commit()
        conn.close()
        print(f"[position_pnl] written {len(agg)} positions")
    except Exception as e:
        print(f"[position_pnl] write failed: {e}")


# ======================== 🧮 Core Financial Algorithms ========================

def calculate_trades_pnl(df: pd.DataFrame) -> pd.DataFrame:
    """
    Advanced moving-average cost basis (supports long/short and options multiplier).
    Annotates each row with realized_pnl and is_win, then returns the DataFrame.
    """
    df = df.sort_values('create_time').copy()

    positions  = {}
    pnl_list   = []
    is_win_list = []

    for _, row in df.iterrows():
        ticker = row['code']
        side   = row['trd_side']
        price  = float(row['price'])
        qty    = float(row['qty'])
        mult   = get_multiplier(ticker)

        pos = positions.setdefault(ticker, {'qty': 0.0, 'avg_cost': 0.0})
        realized_pnl = 0.0
        cur_qty  = pos['qty']
        cur_cost = pos['avg_cost']

        if side == 'BUY':
            if cur_qty >= 0:                          # long entry / add to long
                new_qty        = cur_qty + qty
                pos['avg_cost'] = (cur_qty * cur_cost + qty * price) / new_qty
                pos['qty']      = new_qty
            else:                                     # short exit (buy to cover)
                cover      = min(qty, abs(cur_qty))
                realized_pnl = (cur_cost - price) * cover * mult
                remaining  = qty - cover
                if remaining > 0:
                    pos['qty']      = remaining
                    pos['avg_cost'] = price
                else:
                    pos['qty'] = cur_qty + qty
                    if pos['qty'] == 0:
                        pos['avg_cost'] = 0.0

        elif side == 'SELL':
            if cur_qty <= 0:                          # short entry / add to short
                new_abs        = abs(cur_qty) + qty
                pos['avg_cost'] = (abs(cur_qty) * cur_cost + qty * price) / new_abs
                pos['qty']      = cur_qty - qty
            else:                                     # long exit (sell to close)
                sell_qty     = min(qty, cur_qty)
                realized_pnl = (price - cur_cost) * sell_qty * mult
                remaining    = qty - sell_qty
                if remaining > 0:
                    pos['qty']      = -remaining
                    pos['avg_cost'] = price
                else:
                    pos['qty'] = cur_qty - qty
                    if pos['qty'] == 0:
                        pos['avg_cost'] = 0.0

        pnl_list.append(realized_pnl)
        is_win_list.append(realized_pnl > 0 if realized_pnl != 0 else False)

    df['realized_pnl'] = pnl_list
    df['is_win']       = is_win_list
    return df


# ======================== Moomoo Data Fetch ========================

def sync_positions() -> list:
    ret, data = trd_ctx.position_list_query(trd_env=TRD_ENV, acc_id=MOOMOO_ACC_ID)
    if ret == RET_OK:
        print("Positions fetched successfully")
        return data[['code', 'qty', 'cost_price', 'val', 'pl_ratio']].to_dict(orient='records')
    print(f"Failed to fetch positions: {data}")
    return []


def sync_trades_to_db() -> bool:
    """Fetch historical filled orders from Moomoo and bulk-insert into SQLite, then clear PnL cache."""
    print("🔄 Syncing historical orders...")

    start_date = "2025-11-01"
    end_date   = datetime.now().strftime("%Y-%m-%d")

    ret, data = trd_ctx.history_order_list_query(
        status_filter_list=[OrderStatus.FILLED_ALL, OrderStatus.FILLED_PART],
        trd_env=TRD_ENV,
        acc_id=MOOMOO_ACC_ID,
        start=start_date,
        end=end_date,
    )

    if ret != RET_OK:
        print(f"❌ Failed to fetch historical orders: {data}")
        return False
    if data.empty:
        print("⚠️ No historical orders found")
        return True

    # Bulk insert with executemany + OR IGNORE (much faster than row-by-row)
    records = [
        (str(r['order_id']), r['code'], r['trd_side'],
         float(r['dealt_avg_price']), float(r['dealt_qty']), r['create_time'])
        for _, r in data.iterrows()
    ]

    conn   = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.executemany(
        'INSERT OR IGNORE INTO trades (order_id, code, trd_side, price, qty, create_time) VALUES (?,?,?,?,?,?)',
        records
    )
    saved_count = cursor.rowcount
    conn.commit()
    conn.close()

    invalidate_cache()
    print(f"Sync complete! {saved_count} new trade records inserted.")
    return True


# ======================== API Routes ========================

@app.route('/')
def home():
    try:
        with open('index.html', 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return "Missing index.html", 404


@app.route('/api/portfolio', methods=['GET'])
def get_portfolio():
    try:
        ret, data = trd_ctx.position_list_query(trd_env=TRD_ENV, acc_id=MOOMOO_ACC_ID)
        if ret != RET_OK:
            return jsonify({"status": "error", "message": str(data)}), 500
        if data.empty:
            return jsonify({"status": "success", "data": []}), 200

        wanted = ['code', 'stock_name', 'qty', 'can_sell_qty',
                  'cost_price', 'market_val', 'pl_val', 'pl_ratio',
                  'today_pl_val', 'position_side']
        cols = [c for c in wanted if c in data.columns]
        rows = []
        for _, r in data[cols].iterrows():
            ticker = str(r.get('code', '')).replace('US.', '')
            rows.append({
                'ticker':        ticker,
                'name':          str(r.get('stock_name', ticker)),
                'qty':           float(r.get('qty', 0)),
                'can_sell_qty':  float(r.get('can_sell_qty', 0)),
                'cost_price':    round(float(r.get('cost_price', 0)), 4),
                'market_val':    round(float(r.get('market_val', 0)), 2),
                'pl_val':        round(float(r.get('pl_val', 0)), 2),
                'pl_ratio':      round(float(r.get('pl_ratio', 0)), 4),
                'today_pl_val':  round(float(r.get('today_pl_val', 0)), 2),
                'side':          str(r.get('position_side', 'LONG')),
            })
        # Sort by market value descending
        rows.sort(key=lambda x: x['market_val'], reverse=True)

        # Enrich with position_id + stop_price from local DB
        if rows:
            conn_db = sqlite3.connect(DB_FILE)
            ticker_list = [r['ticker'] for r in rows]
            placeholders = ','.join('?' * len(ticker_list))

            # Pull all trades for these tickers to find open position_ids
            df_trades = pd.read_sql(
                f"""SELECT trd_side, qty, position_id,
                           UPPER(REPLACE(code, 'US.', '')) AS ticker_clean
                    FROM trades
                    WHERE UPPER(REPLACE(code, 'US.', '')) IN ({placeholders})
                    ORDER BY create_time ASC""",
                conn_db, params=ticker_list
            )

            # Pull all stop prices at once
            stops_raw = conn_db.execute(
                f"""SELECT position_id, stop_price FROM position_stops
                    WHERE UPPER(REPLACE(ticker, 'US.', '')) IN ({placeholders})""",
                ticker_list
            ).fetchall()
            conn_db.close()
            stop_map = {r[0]: r[1] for r in stops_raw}

            # Find open position_id per ticker
            open_pid_map = {}  # ticker → position_id
            if not df_trades.empty:
                for (tkr, pid), grp in df_trades.groupby(['ticker_clean', 'position_id']):
                    buy_qty  = grp[grp['trd_side'].isin(['BUY',  'BUY_BACK'])]['qty'].sum()
                    sell_qty = grp[grp['trd_side'].isin(['SELL', 'SELL_SHORT'])]['qty'].sum()
                    if buy_qty - sell_qty > 0.001:
                        open_pid_map[tkr] = pid  # last open pid wins

            for row in rows:
                tkr = row['ticker'].upper()
                pid = open_pid_map.get(tkr)
                row['position_id'] = pid
                row['stop_price']  = stop_map.get(pid) if pid else None

        return jsonify({"status": "success", "data": rows}), 200
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/api/sync', methods=['GET'])
def trigger_sync():
    global _last_sync_time
    import time
    elapsed = time.time() - _last_sync_time
    if elapsed < SYNC_COOLDOWN_SECS:
        remaining = int(SYNC_COOLDOWN_SECS - elapsed)
        return jsonify({
            "status": "cooldown",
            "message": f"Sync on cooldown. Try again in {remaining}s."
        }), 429
    if sync_trades_to_db():
        _last_sync_time = time.time()
        assign_position_ids()
        _write_position_pnl()
        if DEEPSEEK_API_KEY:
            try:
                import rag
                threading.Thread(target=rag.build_index, kwargs={'force': True}, daemon=True).start()
            except Exception:
                pass
        return jsonify({"status": "success", "message": "Sync completed"}), 200
    return jsonify({"status": "error", "message": "Sync failed, check console"}), 500


@app.route('/api/trades', methods=['GET'])
def get_local_trades():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    rows = conn.execute('SELECT * FROM trades ORDER BY create_time DESC LIMIT 500').fetchall()
    conn.close()
    return jsonify({"status": "success", "data": [dict(r) for r in rows]}), 200


@app.route('/api/trades/<trade_id>/tags', methods=['PATCH'])
def update_trade_tags(trade_id):
    body = request.get_json(force=True)
    tags = body.get('tags', [])  # list of strings
    tags_json = json.dumps(tags)
    conn = sqlite3.connect(DB_FILE)
    cur = conn.execute('UPDATE trades SET tags=? WHERE order_id=?', (tags_json, trade_id))
    conn.commit()
    conn.close()
    if cur.rowcount == 0:
        return jsonify({'status': 'error', 'message': 'trade not found'}), 404
    return jsonify({'status': 'success', 'tags': tags}), 200


@app.route('/api/positions/<position_id>/stop', methods=['PATCH'])
def set_position_stop(position_id):
    body       = request.get_json(force=True)
    stop_price = float(body.get('stop_price', 0))
    ticker     = body.get('ticker', '')

    conn = sqlite3.connect(DB_FILE)
    conn.execute('''
        INSERT INTO position_stops (position_id, ticker, stop_price, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(position_id) DO UPDATE SET
            stop_price = excluded.stop_price,
            updated_at = excluded.updated_at
    ''', (position_id, ticker, stop_price, datetime.now().isoformat()))
    conn.commit()
    conn.close()
    return jsonify({'status': 'success', 'position_id': position_id, 'stop_price': stop_price}), 200


@app.route('/api/positions/<position_id>/stop', methods=['GET'])
def get_position_stop(position_id):
    conn = sqlite3.connect(DB_FILE)
    row  = conn.execute(
        'SELECT stop_price FROM position_stops WHERE position_id=?', (position_id,)
    ).fetchone()
    conn.close()
    if row:
        return jsonify({'status': 'success', 'stop_price': row[0]}), 200
    return jsonify({'status': 'not_found', 'stop_price': None}), 200


@app.route('/api/tags', methods=['GET'])
def get_all_tags():
    conn = sqlite3.connect(DB_FILE)
    rows = conn.execute("SELECT tags FROM trades WHERE tags != '[]' AND tags IS NOT NULL").fetchall()
    conn.close()
    from collections import Counter
    counter = Counter()
    for (tags_str,) in rows:
        try:
            for t in json.loads(tags_str):
                counter[t] += 1
        except Exception:
            pass
    sorted_tags = [{'tag': t, 'count': c} for t, c in counter.most_common()]
    return jsonify({'status': 'success', 'tags': sorted_tags}), 200


@app.route('/api/tag_stats', methods=['GET'])
def get_tag_stats():
    """Tag performance analytics. Supports timeframe: 1W, 1M, 3M, 1Y, AT (default)."""
    timeframe = request.args.get('timeframe', 'AT').upper()

    # Load PnL-annotated dataframe (uses module-level cache)
    df_all = load_df_with_pnl()
    if df_all.empty:
        return jsonify({'status': 'success', 'timeframe': timeframe, 'data': []}), 200

    # Only closed trades (realized_pnl != 0) have meaningful PnL
    df = df_all[df_all['realized_pnl'] != 0].copy()

    # Apply timeframe filter based on create_time
    from datetime import timedelta
    if timeframe != 'AT':
        offsets = {
            '1W':  timedelta(days=7),
            '1M':  timedelta(days=30),
            '3M':  timedelta(days=90),
            '1Y':  timedelta(days=365),
        }
        delta = offsets.get(timeframe)
        if delta:
            cutoff = pd.Timestamp.now() - delta
            df = df[df['create_time'] >= cutoff].copy()

    if df.empty:
        return jsonify({'status': 'success', 'timeframe': timeframe, 'data': []}), 200

    # Fetch tags for trades in scope
    order_ids = df['order_id'].tolist()
    if not order_ids:
        return jsonify({'status': 'success', 'timeframe': timeframe, 'data': []}), 200

    conn = sqlite3.connect(DB_FILE)
    placeholders = ','.join('?' * len(order_ids))
    tag_rows = conn.execute(
        f"SELECT order_id, tags FROM trades "
        f"WHERE order_id IN ({placeholders}) "
        f"AND tags IS NOT NULL AND tags != '' AND tags != '[]'",
        order_ids
    ).fetchall()
    conn.close()

    # Build a map: order_id -> tags list
    tags_map = {}
    for (oid, tags_str) in tag_rows:
        try:
            tags_map[str(oid)] = json.loads(tags_str)
        except Exception:
            pass

    # Accumulate per-tag stats
    tag_stats = {}  # tag -> {pnls: [], wins: int, losses: int}

    for _, row in df.iterrows():
        oid = str(row['order_id'])
        tags = tags_map.get(oid, [])
        if not tags:
            continue
        pnl = float(row['realized_pnl'])
        for tag in tags:
            if tag not in tag_stats:
                tag_stats[tag] = {'pnls': [], 'wins': 0, 'losses': 0}
            tag_stats[tag]['pnls'].append(pnl)
            if pnl > 0:
                tag_stats[tag]['wins'] += 1
            elif pnl < 0:
                tag_stats[tag]['losses'] += 1

    if not tag_stats:
        return jsonify({'status': 'success', 'timeframe': timeframe, 'data': []}), 200

    # Build result list
    result = []
    for tag, s in tag_stats.items():
        pnls   = s['pnls']
        count  = len(pnls)
        wins   = s['wins']
        losses = s['losses']
        total_pnl = sum(pnls)
        win_pnls  = [p for p in pnls if p > 0]
        loss_pnls = [p for p in pnls if p < 0]

        result.append({
            'tag':         tag,
            'count':       count,
            'wins':        wins,
            'losses':      losses,
            'win_rate':    round(wins / count * 100, 1) if count else 0.0,
            'total_pnl':   round(total_pnl, 2),
            'avg_pnl':     round(total_pnl / count, 2) if count else 0.0,
            'avg_win':     round(sum(win_pnls) / len(win_pnls), 2) if win_pnls else 0.0,
            'avg_loss':    round(sum(loss_pnls) / len(loss_pnls), 2) if loss_pnls else 0.0,
            'best_trade':  round(max(pnls), 2),
            'worst_trade': round(min(pnls), 2),
        })

    # Sort by total_pnl descending (most profitable first)
    result.sort(key=lambda x: x['total_pnl'], reverse=True)

    return jsonify({'status': 'success', 'timeframe': timeframe, 'data': result}), 200


@app.route('/api/all_trades', methods=['GET'])
def get_all_trades():
    df = load_df_with_pnl()
    if df.empty:
        return jsonify({"status": "success", "data": []}), 200

    closed = df[df['realized_pnl'] != 0].sort_values('create_time', ascending=False)
    result = [build_trade_card(row, df) for _, row in closed.iterrows()]
    return jsonify({"status": "success", "data": result}), 200


@app.route('/api/journal', methods=['GET'])
def get_journal_data():
    df = load_df_with_pnl()
    if df.empty:
        return jsonify({"status": "empty", "daily": [], "monthly": []}), 200

    df['date']           = df['create_time'].dt.strftime('%Y-%m-%d')
    df['month_sort_key'] = df['create_time'].dt.strftime('%Y-%m')

    # --- Group by day ---
    daily_data = []
    for date_str, grp in df.groupby('date'):
        dt_obj     = datetime.strptime(date_str, '%Y-%m-%d')
        daily_pnl  = grp['realized_pnl'].sum()
        sells      = grp[grp['trd_side'] == 'SELL']
        sell_count = len(sells)
        wins       = (sells['is_win'] == True).sum()
        win_pct    = f"{int(wins / sell_count * 100)}%" if sell_count else "0%"

        # Per ticker: bundle all closing trades for that day into a trade card list
        ticker_pills = []
        for ticker, g in grp.groupby('code'):
            clean   = ticker.replace('US.', '')
            grp_pnl = g['realized_pnl'].sum()
            # Only rows with realized_pnl != 0 (actual closes)
            closes  = g[g['realized_pnl'] != 0].sort_values('create_time', ascending=False)
            cards   = [build_trade_card(row, df) for _, row in closes.iterrows()]
            ticker_pills.append({
                "name":   clean,
                "win":    bool(grp_pnl >= 0),
                "trades": cards,
            })

        daily_data.append({
            "date":     date_str,
            "day":      dt_obj.strftime('%d'),
            "weekday":  dt_obj.strftime('%a'),
            "pnl":      f"${abs(daily_pnl):.2f}",
            "isProfit": bool(daily_pnl >= 0),
            "winPct":   win_pct,
            "trades":   str(len(grp)),
            "wins":     str(wins),
            "losses":   str(sell_count - wins),
            "comm":     "$0.00",
            "tickers":  ticker_pills,
        })

    daily_data.sort(key=lambda x: x['date'], reverse=True)

    # --- Group by month ---
    monthly_data = []
    for month_key, grp in df.groupby('month_sort_key'):
        grp_sorted  = grp.sort_values('create_time')
        monthly_pnl = grp_sorted['realized_pnl'].sum()
        sells       = grp_sorted[grp_sorted['trd_side'] == 'SELL']
        sell_count  = len(sells)
        wins        = (sells['is_win'] == True).sum()
        win_pct     = f"{int(wins / sell_count * 100)}%" if sell_count else "0%"

        year, month = map(int, month_key.split('-'))
        month_start = datetime(year, month, 1).strftime('%b %d')
        chart_data  = [{"date": month_start, "value": 0.0}]
        cum_pnl     = 0.0

        for _, r in grp_sorted.iterrows():
            if r['realized_pnl'] != 0:
                cum_pnl += r['realized_pnl']
                chart_data.append({
                    "date":  r['create_time'].strftime('%b %d'),
                    "value": round(cum_pnl, 2),
                })

        if len(chart_data) == 1:
            chart_data.append({"date": month_start, "value": 0.0})

        monthly_data.append({
            "sort_key":  month_key,
            "monthYear": grp_sorted['create_time'].iloc[0].strftime('%B, %Y'),
            "profit":    f"{'-' if monthly_pnl < 0 else ''}${abs(monthly_pnl):.2f}",
            "wins":      win_pct,
            "avgGain":   "N/A",
            "chart_data": chart_data,
            "isProfit":  bool(monthly_pnl >= 0),
        })

    monthly_data.sort(key=lambda x: x['sort_key'], reverse=True)
    for item in monthly_data:
        del item['sort_key']

    return jsonify({"status": "success", "daily": daily_data, "monthly": monthly_data}), 200


@app.route('/api/stats', methods=['GET'])
def get_trading_stats():
    """Core trading metrics with dynamic time slicing (1W/1M/3M/YTD/1Y/AT)."""
    period = request.args.get('period', '1M')

    df_all = load_df_with_pnl()
    if df_all.empty:
        return jsonify({"status": "empty", "message": "No trade data yet"}), 200

    df = slice_by_period(df_all, period)

    total_pnl   = df['realized_pnl'].sum()
    sell_orders = df[df['trd_side'] == 'SELL']
    sell_count  = len(sell_orders)
    wins        = (sell_orders['is_win'] == True).sum()
    losses      = sell_count - wins

    win_loss_split = ([wins / sell_count, losses / sell_count]
                      if sell_count else [0.0, 1.0])

    # Per-position win rate (groups by position_id if available)
    if 'position_id' in df.columns and df['position_id'].notna().any():
        pos_pnl   = df[df['realized_pnl'] != 0].groupby('position_id')['realized_pnl'].sum()
        pos_wins  = (pos_pnl > 0).sum()
        pos_total = len(pos_pnl)
        _win_rate_num = round(pos_wins / pos_total * 100, 1) if pos_total > 0 else 0.0
        win_rate_str  = f"{int(_win_rate_num)}%"
    else:
        win_rate_str = f"{int(wins / sell_count * 100)}%" if sell_count else "0%"

    won_pnl_sum      = sell_orders[sell_orders['is_win'] == True]['realized_pnl'].sum()
    lost_pnl_sum     = sell_orders[sell_orders['is_win'] == False]['realized_pnl'].sum()
    avg_gain_usd     = won_pnl_sum / wins if wins else 0.0
    avg_loss_usd_abs = abs(lost_pnl_sum / losses) if losses else 0.0
    total_avg        = avg_gain_usd + avg_loss_usd_abs
    avg_gain_split_usd = ([avg_gain_usd / total_avg, avg_loss_usd_abs / total_avg]
                           if total_avg else [0.0, 1.0])

    # Avg Gain % = total PnL / total entry capital
    df['_mult']        = df['code'].apply(get_multiplier)
    df['_enter_value'] = df['price'] * df['qty'] * df['_mult']
    total_enter_value  = df[df['trd_side'] == 'SELL']['_enter_value'].sum()
    avg_gain_pct       = (total_pnl / total_enter_value) if total_enter_value else 0.0

    # Profit Factor = gross profit / |gross loss|
    pf_raw   = round(float(won_pnl_sum) / float(abs(lost_pnl_sum)), 2) if losses and lost_pnl_sum != 0 else None
    pf_str   = f"{pf_raw:.2f}" if pf_raw is not None else "∞"
    pf_split = ([pf_raw / (pf_raw + 1), 1.0 / (pf_raw + 1)]
                if pf_raw and pf_raw > 0 else [0.0, 1.0])

    # Last-7-days bar chart (today as anchor, 7 days back)
    today         = pd.Timestamp.now().normalize()
    df['_date']   = df['create_time'].dt.strftime('%Y-%m-%d')
    daily_pnl_map = df.groupby('_date')['realized_pnl'].sum().to_dict()

    last_7_chart = []
    for i in range(6, -1, -1):
        day     = today - pd.Timedelta(days=i)
        day_str = day.strftime('%Y-%m-%d')
        pnl_val = daily_pnl_map.get(day_str, 0.0)
        last_7_chart.append({
            "weekday":  day.strftime('%a'),
            "pnl":      round(pnl_val, 2),
            "isProfit": pnl_val >= 0,
        })

    # Latest 3 closed trades
    closed = df[df['realized_pnl'] != 0].sort_values('create_time', ascending=False)
    latest_trades = [build_trade_card(row, df_all) for _, row in closed.head(3).iterrows()]

    # Cumulative profit chart
    df_sorted = df.sort_values('create_time').copy()
    df_sorted['_date_only'] = df_sorted['create_time'].dt.date
    daily_sum  = df_sorted.groupby('_date_only')['realized_pnl'].sum().reset_index()
    daily_sum['_date_str'] = pd.to_datetime(daily_sum['_date_only']).dt.strftime('%b %d, %Y')
    daily_sum['_cum']      = daily_sum['realized_pnl'].cumsum()

    if not daily_sum.empty:
        first_date_str = pd.to_datetime(
            daily_sum['_date_only'].iloc[0] - pd.Timedelta(days=1)
        ).strftime('%b %d, %Y')
        profit_chart = [{"date": first_date_str, "value": 0.0}] + [
            {"date": r['_date_str'], "value": round(r['_cum'], 2)}
            for _, r in daily_sum.iterrows()
        ]
    else:
        today_str    = pd.Timestamp.today().strftime('%b %d, %Y')
        profit_chart = [{"date": today_str, "value": 0.0}, {"date": today_str, "value": 0.0}]

    return jsonify({
        "status": "success",
        "summary": {
            "total_pnl":           round(total_pnl, 2),
            "win_rate":            win_rate_str,
            "win_split":           win_loss_split,
            "avg_gain_usd":        round(avg_gain_usd, 2),
            "avg_gain_split_usd":  avg_gain_split_usd,
            "avg_gain_pct":        f"{avg_gain_pct * 100:.2f}%",
            "avg_gain_split_pct":  win_loss_split,
            "profit_factor":       pf_str,
            "profit_factor_split": pf_split,
            "sell_count":          sell_count,
            "trade_count":         len(df),
            "profit_chart":        profit_chart,
        },
        "last_7_chart":  last_7_chart,
        "latest_trades": latest_trades,
    }), 200


@app.route('/api/monthly_details', methods=['GET'])
def get_monthly_details():
    """Monthly deep review: stats table + full trade log."""
    month_str = request.args.get('month')   # e.g. "March, 2026"

    df_all = load_df_with_pnl()
    if df_all.empty:
        return jsonify({"status": "empty"}), 200

    df_all['month_label'] = df_all['create_time'].dt.strftime('%B, %Y')
    month_closed = df_all[
        (df_all['month_label'] == month_str) & (df_all['realized_pnl'] != 0)
    ].copy()

    if month_closed.empty:
        return jsonify({"status": "empty"}), 200

    # --- Deep stats analysis ---
    trades_data = []
    for _, row in month_closed.iterrows():
        exit_time  = row['create_time']
        ticker     = row['code']
        side       = row['trd_side']
        pnl        = row['realized_pnl']
        trade_type = "LONG" if side == 'SELL' else "SHORT"
        clean_tick = ticker.split('.')[-1]

        mult        = get_multiplier(ticker)
        trade_value = float(row['price']) * float(row['qty']) * mult
        pct         = (pnl / trade_value) if trade_value > 0 else 0

        # Only enter_time needed here; build_trade_card fills in full transactions
        _, enter_time = find_round_trip(df_all, ticker, exit_time, trade_type)

        trades_data.append({
            "pnl":         pnl,
            "pct":         pct,
            "is_win":      pnl > 0,
            "type":        trade_type,
            "holding_sec": (exit_time - enter_time).total_seconds(),
            "entry_hour":  enter_time.hour + enter_time.minute / 60.0,
            "symbol":      clean_tick,
        })

    df_t    = pd.DataFrame(trades_data)
    won_df  = df_t[df_t['is_win']]
    lost_df = df_t[~df_t['is_win']]

    def fmt_usd(v):  return f"{'-' if v < 0 else ''}${abs(v):.2f}" if not pd.isna(v) else "$0.00"
    def fmt_pct(v):  return f"{v * 100:.2f}%" if not pd.isna(v) else "0.00%"
    def fmt_time(s):
        if pd.isna(s): return "0s"
        if s < 60:     return "a few seconds"
        if s < 3600:   return f"{int(s / 60)}m"
        if s < 86400:  return f"{int(s / 3600)}h"
        return f"{int(s / 86400)}d"
    def fmt_hour(h):
        if pd.isna(h): return "0:00"
        return f"{int(h):02d}:{int((h - int(h)) * 60):02d}"

    # Symbol breakdown
    symbol_stats = []
    for sym, grp in df_t.groupby('symbol'):
        w = grp[grp['is_win']]
        l = grp[~grp['is_win']]
        _spnl = float(grp['pnl'].sum())
        symbol_stats.append({
            "symbol": sym,
            "trades": {"all": str(len(grp)), "won": str(len(w)), "lost": str(len(l))},
            "amount": {
                "all":  fmt_usd(_spnl),
                "won":  fmt_usd(float(w['pnl'].sum())) if not w.empty else "$0.00",
                "lost": fmt_usd(float(l['pnl'].sum())) if not l.empty else "$0.00",
            },
            "pnl_raw":      round(_spnl, 2),
            "isProfit":     bool(_spnl >= 0),
            "_raw_trades":  len(grp),
            "_raw_pnl_abs": abs(_spnl),
        })

    stats = {
        "gain_loss": {
            "total":    {"all": fmt_usd(df_t['pnl'].sum()),  "won": fmt_usd(won_df['pnl'].sum()),  "lost": fmt_usd(lost_df['pnl'].sum())},
            "avg_usd":  {"all": fmt_usd(df_t['pnl'].mean()), "won": fmt_usd(won_df['pnl'].mean()), "lost": fmt_usd(lost_df['pnl'].mean())},
            "avg_pct":  {"all": fmt_pct(df_t['pct'].mean()), "won": fmt_pct(won_df['pct'].mean()), "lost": fmt_pct(lost_df['pct'].mean())},
            "trades":   {"all": str(len(df_t)), "won": str(len(won_df)), "lost": str(len(lost_df))},
            "win_rate": fmt_pct(len(won_df) / len(df_t) if len(df_t) else 0),
        },
        "long_short": {
            "long":  {"all": str((df_t['type'] == 'LONG').sum()),  "won": str((won_df['type'] == 'LONG').sum()),  "lost": str((lost_df['type'] == 'LONG').sum())},
            "short": {"all": str((df_t['type'] == 'SHORT').sum()), "won": str((won_df['type'] == 'SHORT').sum()), "lost": str((lost_df['type'] == 'SHORT').sum())},
        },
        "timing": {
            "holding":    {"all": fmt_time(df_t['holding_sec'].mean()), "won": fmt_time(won_df['holding_sec'].mean()), "lost": fmt_time(lost_df['holding_sec'].mean())},
            "entry_hour": {"all": fmt_hour(df_t['entry_hour'].mean()),  "won": fmt_hour(won_df['entry_hour'].mean()),  "lost": fmt_hour(lost_df['entry_hour'].mean())},
        },
        "best_worst": {
            "largest_usd": {"won": fmt_usd(won_df['pnl'].max() if not won_df.empty else 0), "lost": fmt_usd(lost_df['pnl'].min() if not lost_df.empty else 0)},
            "largest_pct": {"won": fmt_pct(won_df['pct'].max() if not won_df.empty else 0), "lost": fmt_pct(lost_df['pct'].min() if not lost_df.empty else 0)},
        },
        "symbols_by_trades":  sorted(symbol_stats, key=lambda x: x['_raw_trades'],   reverse=True),
        "symbols_by_amount":  sorted(symbol_stats, key=lambda x: x['pnl_raw'],        reverse=True),
    }

    # Full trade log
    month_trades_list = [
        build_trade_card(row, df_all)
        for _, row in month_closed.sort_values('create_time', ascending=False).iterrows()
    ]

    return jsonify({
        "status": "success",
        "data":   stats,
        "trades": month_trades_list,
    }), 200


# ======================== Performance Analysis ========================

@app.route('/api/performance', methods=['GET'])
def get_performance():
    """Deep performance analysis: core metrics, monthly bars, DOW distribution, gain/loss/timing/symbol stats."""
    period = request.args.get('period', '1M')

    df_all = load_df_with_pnl()
    if df_all.empty:
        return jsonify({"status": "empty"}), 200

    df = slice_by_period(df_all, period)

    # ── Closing trade counts ──────────────────────────────────────
    sell_orders = df[df['trd_side'] == 'SELL'].copy()
    sell_count  = len(sell_orders)
    wins        = (sell_orders['is_win'] == True).sum()
    losses      = sell_count - wins
    win_rate    = wins / sell_count if sell_count else 0.0

    won_df  = sell_orders[sell_orders['is_win'] == True]
    lost_df = sell_orders[sell_orders['is_win'] == False]

    avg_win       = float(won_df['realized_pnl'].mean())  if wins   else 0.0
    avg_loss      = abs(float(lost_df['realized_pnl'].mean())) if losses else 0.0
    gross_profit  = float(won_df['realized_pnl'].sum())
    gross_loss    = abs(float(lost_df['realized_pnl'].sum()))
    profit_factor = round(gross_profit / gross_loss, 2) if gross_loss > 0 else 999.0
    win_loss_ratio = round(avg_win / avg_loss, 2) if avg_loss > 0 else 0.0
    expectancy    = round((avg_win * win_rate) - (avg_loss * (1 - win_rate)), 2) if sell_count else 0.0
    total_pnl     = float(df['realized_pnl'].sum())

    # ── Max Drawdown ─────────────────────────────────────────────
    df_sorted = df.sort_values('create_time').copy()
    df_sorted['_cum'] = df_sorted['realized_pnl'].cumsum()
    peak = df_sorted['_cum'].cummax()
    max_drawdown = float((df_sorted['_cum'] - peak).min()) if not df_sorted.empty else 0.0

    # ── Streak ───────────────────────────────────────────────────
    cur_win_streak = cur_loss_streak = 0
    max_win_streak = max_loss_streak = 0
    for _, row in sell_orders.sort_values('create_time').iterrows():
        if bool(row['is_win']):
            cur_win_streak  += 1; cur_loss_streak = 0
        else:
            cur_loss_streak += 1; cur_win_streak  = 0
        max_win_streak  = max(max_win_streak,  cur_win_streak)
        max_loss_streak = max(max_loss_streak, cur_loss_streak)
    current_streak_type  = 'W' if cur_win_streak > 0 else 'L'
    current_streak_count = cur_win_streak if cur_win_streak > 0 else cur_loss_streak

    # ── Monthly bar chart ────────────────────────────────────────
    df['_month_key'] = df['create_time'].dt.strftime('%Y-%m')
    df['_month_lbl'] = df['create_time'].dt.strftime('%b %Y')
    monthly_grp = df.groupby(['_month_key', '_month_lbl'])['realized_pnl'].sum().reset_index()
    monthly_grp = monthly_grp.sort_values('_month_key')
    monthly_bars = [
        {"label": str(r['_month_lbl']), "value": round(float(r['realized_pnl']), 2),
         "isProfit": bool(r['realized_pnl'] >= 0)}
        for _, r in monthly_grp.iterrows()
    ]

    # ── Day-of-week distribution ──────────────────────────────────
    sell_orders['_dow'] = sell_orders['create_time'].dt.dayofweek
    dow_labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']
    dow_stats = []
    for i, lbl in enumerate(dow_labels):
        grp = sell_orders[sell_orders['_dow'] == i]
        day_wins  = (grp['is_win'] == True).sum()
        day_total = len(grp)
        day_pnl   = float(grp['realized_pnl'].sum())
        dow_stats.append({
            "label":    lbl,
            "trades":   int(day_total),
            "win_rate": round(float(day_wins) / day_total, 4) if day_total else 0.0,
            "pnl":      round(day_pnl, 2),
            "isProfit": bool(day_pnl >= 0),
        })

    # ── Deep stats (mirrors monthly_details logic, adapts to any period) ────
    # Rebuild trade-level data for each closing trade
    closed = sell_orders.copy()

    def fmt_usd(v):
        if pd.isna(v): return "$0.00"
        return f"{'-' if v < 0 else ''}${abs(v):.2f}"
    def fmt_pct(v):
        return f"{v * 100:.2f}%" if not pd.isna(v) else "0.00%"
    def fmt_time(s):
        if pd.isna(s): return "0s"
        if s < 60:     return "a few seconds"
        if s < 3600:   return f"{int(s / 60)}m"
        if s < 86400:  return f"{int(s / 3600)}h"
        return f"{int(s / 86400)}d"
    def fmt_hour(h):
        if pd.isna(h): return "0:00"
        return f"{int(h):02d}:{int((h - int(h)) * 60):02d}"

    trades_data = []
    for _, row in closed.iterrows():
        exit_time  = row['create_time']
        ticker     = row['code']
        pnl        = row['realized_pnl']
        trade_type = "LONG"   # sell = close long
        clean_tick = ticker.split('.')[-1]
        mult        = get_multiplier(ticker)
        trade_value = float(row['price']) * float(row['qty']) * mult
        pct         = (pnl / trade_value) if trade_value > 0 else 0
        _, enter_time = find_round_trip(df_all, ticker, exit_time, trade_type)
        trades_data.append({
            "pnl":         float(pnl),
            "pct":         float(pct),
            "is_win":      bool(row['is_win']),
            "type":        trade_type,
            "holding_sec": float((exit_time - enter_time).total_seconds()),
            "entry_hour":  float(enter_time.hour + enter_time.minute / 60.0),
            "symbol":      clean_tick,
        })

    # Also include short exits (BUY to cover)
    buy_covers = df[(df['trd_side'] == 'BUY') & (df['realized_pnl'] != 0)].copy()
    for _, row in buy_covers.iterrows():
        exit_time  = row['create_time']
        ticker     = row['code']
        pnl        = row['realized_pnl']
        clean_tick = ticker.split('.')[-1]
        mult        = get_multiplier(ticker)
        trade_value = float(row['price']) * float(row['qty']) * mult
        pct         = (pnl / trade_value) if trade_value > 0 else 0
        _, enter_time = find_round_trip(df_all, ticker, exit_time, "SHORT")
        trades_data.append({
            "pnl":         float(pnl),
            "pct":         float(pct),
            "is_win":      bool(pnl > 0),
            "type":        "SHORT",
            "holding_sec": float((exit_time - enter_time).total_seconds()),
            "entry_hour":  float(enter_time.hour + enter_time.minute / 60.0),
            "symbol":      clean_tick,
        })

    df_t    = pd.DataFrame(trades_data) if trades_data else pd.DataFrame(
        columns=['pnl','pct','is_win','type','holding_sec','entry_hour','symbol'])
    won_t   = df_t[df_t['is_win'] == True]
    lost_t  = df_t[df_t['is_win'] == False]

    # Symbol breakdown
    symbol_stats = []
    for sym, grp in df_t.groupby('symbol'):
        w = grp[grp['is_win'] == True]
        l = grp[grp['is_win'] == False]
        _sym_pnl = float(grp['pnl'].sum())
        symbol_stats.append({
            "symbol": str(sym),
            "trades": {"all": str(len(grp)), "won": str(len(w)), "lost": str(len(l))},
            "amount": {
                "all":  fmt_usd(_sym_pnl),
                "won":  fmt_usd(float(w['pnl'].sum())) if not w.empty else "$0.00",
                "lost": fmt_usd(float(l['pnl'].sum())) if not l.empty else "$0.00",
            },
            "pnl_raw":      round(_sym_pnl, 2),
            "isProfit":     bool(_sym_pnl >= 0),
            "_raw_trades":  int(len(grp)),
            "_raw_pnl_abs": abs(_sym_pnl),
        })

    deep_stats = {
        "gain_loss": {
            "total":   {"all": fmt_usd(df_t['pnl'].sum()),  "won": fmt_usd(won_t['pnl'].sum()),  "lost": fmt_usd(lost_t['pnl'].sum())},
            "avg_usd": {"all": fmt_usd(df_t['pnl'].mean()), "won": fmt_usd(won_t['pnl'].mean()), "lost": fmt_usd(lost_t['pnl'].mean())},
            "avg_pct": {"all": fmt_pct(df_t['pct'].mean()), "won": fmt_pct(won_t['pct'].mean()), "lost": fmt_pct(lost_t['pct'].mean())},
            "trades":  {"all": str(len(df_t)), "won": str(len(won_t)), "lost": str(len(lost_t))},
            "win_rate": fmt_pct(len(won_t) / len(df_t) if len(df_t) else 0),
        },
        "long_short": {
            "long":  {"all": str((df_t['type'] == 'LONG').sum()),  "won": str((won_t['type'] == 'LONG').sum()),  "lost": str((lost_t['type'] == 'LONG').sum())},
            "short": {"all": str((df_t['type'] == 'SHORT').sum()), "won": str((won_t['type'] == 'SHORT').sum()), "lost": str((lost_t['type'] == 'SHORT').sum())},
        },
        "timing": {
            "holding":    {"all": fmt_time(df_t['holding_sec'].mean()), "won": fmt_time(won_t['holding_sec'].mean()), "lost": fmt_time(lost_t['holding_sec'].mean())},
            "entry_hour": {"all": fmt_hour(df_t['entry_hour'].mean()),  "won": fmt_hour(won_t['entry_hour'].mean()),  "lost": fmt_hour(lost_t['entry_hour'].mean())},
        },
        "best_worst": {
            "largest_usd": {
                "won":  fmt_usd(won_t['pnl'].max() if not won_t.empty else 0),
                "lost": fmt_usd(lost_t['pnl'].min() if not lost_t.empty else 0),
            },
            "largest_pct": {
                "won":  fmt_pct(won_t['pct'].max() if not won_t.empty else 0),
                "lost": fmt_pct(lost_t['pct'].min() if not lost_t.empty else 0),
            },
        },
        "symbols_by_trades": sorted(symbol_stats, key=lambda x: x['_raw_trades'],   reverse=True),
        "symbols_by_amount": sorted(symbol_stats, key=lambda x: x['pnl_raw'],        reverse=True),
    }

    # ── Sharpe Ratio ──────────────────────────────────────────────────────────
    # Per-trade % returns; annualization factor = sqrt(252)
    trade_returns = df_t['pct'].dropna() if not df_t.empty else pd.Series(dtype=float)
    if len(trade_returns) >= 2:
        mean_r = float(trade_returns.mean())
        std_r  = float(trade_returns.std())
        sharpe_ratio = round((mean_r / std_r) * (252 ** 0.5), 2) if std_r > 0 else 0.0
    else:
        sharpe_ratio = 0.0

    # ── Sortino Ratio ─────────────────────────────────────────────────────────
    # Uses downside deviation only (std of negative returns)
    if len(trade_returns) >= 2:
        neg_returns  = trade_returns[trade_returns < 0]
        downside_std = float(neg_returns.std()) if len(neg_returns) >= 2 else 0.0
        sortino_ratio = round((mean_r / downside_std) * (252 ** 0.5), 2) if downside_std > 0 else 0.0
    else:
        sortino_ratio = 0.0

    # ── Kelly Criterion ───────────────────────────────────────────────────────
    # Kelly % = W - (1 - W) / R, where W = win rate, R = avg win / avg loss
    if win_loss_ratio > 0 and 0 < win_rate < 1:
        kelly_pct = round((win_rate - (1 - win_rate) / win_loss_ratio) * 100, 1)
        kelly_pct = max(kelly_pct, 0.0)   # negative Kelly = do not trade
    else:
        kelly_pct = 0.0

    # ── Drawdown curve (equity curve + drawdown depth per trade) ─────────────
    # Sort by close time; accumulate PnL; track running peak and current drawdown
    if not df_t.empty:
        # Rebuild cumulative PnL sequence from df (time-sliced raw data)
        df_closed = df[df['realized_pnl'] != 0].sort_values('create_time')
        equity_pts = []
        cum = 0.0
        peak = 0.0
        for _, r in df_closed.iterrows():
            cum  += float(r['realized_pnl'])
            peak  = max(peak, cum)
            dd    = cum - peak          # negative or zero
            equity_pts.append({
                "date":     r['create_time'].strftime('%b %d'),
                "equity":   round(cum, 2),
                "drawdown": round(dd, 2),
            })
        # Cap at 200 points to avoid oversized payloads
        if len(equity_pts) > 200:
            step = len(equity_pts) // 200
            equity_pts = equity_pts[::step]
    else:
        equity_pts = []

    return jsonify({
        "status": "success",
        "summary": {
            "total_pnl":           round(total_pnl, 2),
            "trade_count":         sell_count,
            "win_rate":            f"{int(win_rate * 100)}%",
            "profit_factor":       profit_factor,
            "expectancy":          expectancy,
            "avg_win":             round(avg_win, 2),
            "avg_loss":            round(avg_loss, 2),
            "win_loss_ratio":      win_loss_ratio,
            "max_drawdown":        round(max_drawdown, 2),
            "max_win_streak":      int(max_win_streak),
            "max_loss_streak":     int(max_loss_streak),
            "current_streak":      int(current_streak_count),
            "current_streak_type": current_streak_type,
            # Risk metrics
            "sharpe_ratio":        sharpe_ratio,
            "sortino_ratio":       sortino_ratio,
            "kelly_pct":           kelly_pct,
        },
        "monthly_bars":   monthly_bars,
        "dow_stats":      dow_stats,
        "deep_stats":     deep_stats,
        "drawdown_curve": equity_pts,
    }), 200


# ======================== Notes & Screenshots API ========================

@app.route('/api/notes/<trade_id>', methods=['GET'])
def get_note(trade_id: str):
    """Get note and screenshot list for a trade."""
    conn = sqlite3.connect(DB_FILE)
    row  = conn.execute(
        'SELECT note, image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()
    conn.close()

    if row:
        return jsonify({
            "status":      "success",
            "note":        row[0],
            "image_paths": json.loads(row[1]),
        }), 200
    return jsonify({"status": "success", "note": "", "image_paths": []}), 200


@app.route('/api/notes/<trade_id>', methods=['POST'])
def save_note(trade_id: str):
    """Save or update the note text for a trade."""
    body = request.get_json(silent=True) or {}
    note = str(body.get('note', ''))

    conn = sqlite3.connect(DB_FILE)
    # Preserve existing screenshots if any; otherwise default to empty list
    existing = conn.execute(
        'SELECT image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()
    image_paths = existing[0] if existing else '[]'

    conn.execute(
        '''INSERT INTO trade_notes (trade_id, note, image_paths, updated_at)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(trade_id) DO UPDATE SET note = excluded.note,
                                               updated_at = excluded.updated_at''',
        (trade_id, note, image_paths, datetime.now().isoformat())
    )
    conn.commit()
    conn.close()
    return jsonify({"status": "success", "message": "Note saved"}), 200


@app.route('/api/upload_image/<trade_id>', methods=['POST'])
def upload_image(trade_id: str):
    """Upload a screenshot, save it locally, and append the filename to trade_notes.image_paths."""
    if 'image' not in request.files:
        return jsonify({"status": "error", "message": "No image field found"}), 400

    file      = request.files['image']
    ext       = os.path.splitext(file.filename)[1].lower() or '.jpg'
    filename  = f"{trade_id}_{uuid.uuid4().hex[:8]}{ext}"
    save_path = os.path.join(UPLOAD_DIR, filename)
    file.save(save_path)

    # Append filename to the DB record
    conn = sqlite3.connect(DB_FILE)
    existing = conn.execute(
        'SELECT image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()

    if existing:
        paths = json.loads(existing[0])
        paths.append(filename)
        conn.execute(
            '''UPDATE trade_notes SET image_paths = ?, updated_at = ?
               WHERE trade_id = ?''',
            (json.dumps(paths), datetime.now().isoformat(), trade_id)
        )
    else:
        conn.execute(
            '''INSERT INTO trade_notes (trade_id, note, image_paths, updated_at)
               VALUES (?, \'\', ?, ?)''',
            (trade_id, json.dumps([filename]), datetime.now().isoformat())
        )
    conn.commit()
    conn.close()

    return jsonify({
        "status":   "success",
        "filename": filename,
        "url":      f"/api/images/{filename}",
    }), 200


@app.route('/api/delete_image/<trade_id>/<filename>', methods=['DELETE'])
def delete_image(trade_id: str, filename: str):
    """Delete a screenshot (physical file + database record)."""
    file_path = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(file_path):
        os.remove(file_path)

    conn = sqlite3.connect(DB_FILE)
    existing = conn.execute(
        'SELECT image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()
    if existing:
        paths = [p for p in json.loads(existing[0]) if p != filename]
        conn.execute(
            'UPDATE trade_notes SET image_paths = ?, updated_at = ? WHERE trade_id = ?',
            (json.dumps(paths), datetime.now().isoformat(), trade_id)
        )
        conn.commit()
    conn.close()
    return jsonify({"status": "success"}), 200


@app.route('/api/images/<filename>', methods=['GET'])
def serve_image(filename: str):
    """Serve screenshots from the trade_images/ directory."""
    return send_from_directory(UPLOAD_DIR, filename)


@app.route('/api/daily_notes', methods=['GET'])
def get_all_daily_notes():
    """Return all daily notes as { "2026-03-10": "note text", ... }."""
    conn = sqlite3.connect(DB_FILE)
    rows = conn.execute('SELECT date, note FROM daily_notes').fetchall()
    conn.close()
    return jsonify({r[0]: r[1] for r in rows}), 200


@app.route('/api/daily_notes/<date>', methods=['GET'])
def get_daily_note(date: str):
    """Get the note for a single day."""
    conn  = sqlite3.connect(DB_FILE)
    row   = conn.execute('SELECT note FROM daily_notes WHERE date = ?', (date,)).fetchone()
    conn.close()
    return jsonify({"status": "success", "note": row[0] if row else ""}), 200


@app.route('/api/daily_notes/<date>', methods=['POST'])
def save_daily_note(date: str):
    """Save (upsert) the note for a single day."""
    body = request.get_json(silent=True) or {}
    note = str(body.get('note', ''))
    conn = sqlite3.connect(DB_FILE)
    conn.execute(
        '''INSERT INTO daily_notes (date, note, updated_at)
           VALUES (?, ?, ?)
           ON CONFLICT(date) DO UPDATE SET note = excluded.note, updated_at = excluded.updated_at''',
        (date, note, datetime.now().isoformat())
    )
    conn.commit()
    conn.close()
    return jsonify({"status": "success"}), 200


# ======================== Journal AI (RAG) ========================

# ── Session store ────────────────────────────────────────────────────────────
_sessions: dict = {}          # session_id → {"history": [...], "ts": float}
_SESSION_TTL    = 3600        # 1 hour idle timeout


def _get_history(session_id: str) -> list:
    now = _time.time()
    # Purge expired sessions
    for k in [k for k, v in _sessions.items() if now - v["ts"] > _SESSION_TTL]:
        del _sessions[k]
    if session_id not in _sessions:
        _sessions[session_id] = {"history": [], "ts": now}
    _sessions[session_id]["ts"] = now
    return _sessions[session_id]["history"]


def _save_history(session_id: str, history: list):
    if session_id in _sessions:
        _sessions[session_id]["history"] = history[-20:]  # keep last 10 turns


@app.route('/api/journal/ask', methods=['POST'])
def journal_ask():
    """Answer a question with session history (non-streaming)."""
    try:
        import rag
        body       = request.get_json(silent=True) or {}
        question   = str(body.get('question', '')).strip()
        session_id = str(body.get('session_id', 'default'))
        if not question:
            return jsonify({"error": "question is required"}), 400
        history = _get_history(session_id)
        result  = rag.ask(question, history)
        _save_history(session_id, result.get("history", []))
        return jsonify(result), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/journal/ask/stream', methods=['POST'])
def journal_ask_stream():
    """Streaming SSE endpoint with session history."""
    try:
        import rag
        body       = request.get_json(silent=True) or {}
        question   = str(body.get('question', '')).strip()
        session_id = str(body.get('session_id', 'default'))
        if not question:
            return jsonify({"error": "question is required"}), 400

        history = _get_history(session_id)

        def generate():
            try:
                updated_history = history
                for chunk in rag.ask_stream(question, history):
                    if chunk.startswith("data: [META]"):
                        meta = json.loads(chunk[len("data: [META]"):].strip())
                        updated_history = meta.get("history", history)
                    yield chunk
                _save_history(session_id, updated_history)
            except Exception as e:
                import traceback; traceback.print_exc()
                yield f"data: {json.dumps('⚠️ 服务器错误：' + str(e), ensure_ascii=False)}\n\n"
                yield "data: [DONE]\n\n"

        resp = Response(stream_with_context(generate()), content_type="text/event-stream")
        resp.headers["X-Accel-Buffering"] = "no"
        resp.headers["Cache-Control"] = "no-cache"
        return resp
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/journal/session/clear', methods=['POST'])
def journal_clear_session():
    """Clear a session's conversation history."""
    body       = request.get_json(silent=True) or {}
    session_id = str(body.get('session_id', 'default'))
    if session_id in _sessions:
        _sessions[session_id]["history"] = []
    return jsonify({"status": "ok"}), 200


@app.route('/api/journal/reindex', methods=['POST'])
def journal_reindex():
    """Force-rebuild the RAG vector index (call after adding new notes)."""
    try:
        import rag
        count = rag.build_index(force=True)
        return jsonify({"status": "ok", "indexed": count}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ======================== Sector Performance ========================

@app.route('/api/sectors', methods=['GET'])
def get_sectors():
    """Return sector/theme ETF price change data.
    Params: period=1D|1W|1M, type=sector|theme
    For themes: fetches the full ETF pool and returns only the top THEME_TOP_N.
    """
    import time as _time
    import traceback
    from datetime import timedelta
    from concurrent.futures import ThreadPoolExecutor, as_completed
    import threading

    global _sector_cache, _sector_cache_time
    period    = request.args.get('period', '1D')
    data_type = request.args.get('type', 'sector')
    cache_ttl = THEME_CACHE_SECS if data_type == 'theme' else SECTOR_CACHE_SECS

    # Hot-reload etfs.json on every request so changes take effect without restart
    sector_map, theme_map = _load_etfs()
    etf_map = theme_map if data_type == 'theme' else sector_map

    # ── Cache check ───────────────────────────────────────────────
    cache_key = f'{data_type}_{period}'
    if (_sector_cache is not None
            and _sector_cache.get('key') == cache_key
            and _time.time() - _sector_cache_time < cache_ttl):
        return jsonify(_sector_cache['payload']), 200

    try:
        days_map   = {'1D': 5, '1W': 10, '1M': 35}
        days       = days_map.get(period, 5)
        end_date   = datetime.now().strftime('%Y-%m-%d')
        start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        # ── Per-ETF fetch function ─────────────────────────────────
        # quote_ctx is not thread-safe; serialize API calls with a lock
        _lock = threading.Lock()

        def fetch_one(name_code):
            name, code = name_code
            ticker = code.split('.')[-1]
            try:
                _kline_limiter.acquire()
                with _lock:
                    ret, kdf, _ = quote_ctx.request_history_kline(
                        code, start=start_date, end=end_date,
                        ktype=KLType.K_DAY
                    )
                if ret != RET_OK or kdf is None or len(kdf) == 0:
                    print(f'[sectors] {code} kline error: {kdf}')
                    return {'name': name, 'ticker': ticker,
                            'price': 0.0, 'change_pct': 0.0}

                close_col  = 'close' if 'close' in kdf.columns else 'close_price'
                closes     = kdf[close_col].astype(float)
                last_close = closes.iloc[-1]
                price      = round(last_close, 2)

                if period == '1D':
                    if len(closes) >= 2:
                        prev = closes.iloc[-2]
                        change_pct = round((last_close - prev) / prev * 100, 2) \
                            if prev > 0 else 0.0
                    else:
                        cr_col = 'change_rate' if 'change_rate' in kdf.columns else None
                        change_pct = round(float(kdf.iloc[-1][cr_col]), 2) \
                            if cr_col else 0.0
                else:
                    first = closes.iloc[0]
                    change_pct = round((last_close - first) / first * 100, 2) \
                        if first > 0 else 0.0

                return {'name': name, 'ticker': ticker,
                        'price': price, 'change_pct': change_pct}

            except Exception as e:
                print(f'[sectors] {code} exception: {e}')
                traceback.print_exc()
                return {'name': name, 'ticker': ticker,
                        'price': 0.0, 'change_pct': 0.0}

        # ── Parallel fetch (multi-threaded for theme pool) ─────────
        workers = THEME_WORKERS if data_type == 'theme' else 1
        result  = []
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(fetch_one, item): item
                       for item in etf_map.items()}
            for fut in as_completed(futures):
                result.append(fut.result())

        # ── After sorting, keep only top N for themes ──────────────
        result.sort(key=lambda x: x['change_pct'], reverse=True)
        if data_type == 'theme':
            result = result[:THEME_TOP_N]

        payload = {'status': 'success', 'period': period,
                   'type': data_type, 'data': result}
        _sector_cache      = {'key': cache_key, 'payload': payload}
        _sector_cache_time = _time.time()
        return jsonify(payload), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ======================== Sector Detail ========================

@app.route('/api/sector_detail', methods=['GET'])
def get_sector_detail():
    """Return detailed technical indicators for a single sector ETF (MA, YTD, 52-week high, etc.).
    GET /api/sector_detail?ticker=XLK
    Cache TTL = 300 s.
    """
    import time as _time
    import traceback

    global _detail_cache, _detail_cache_time

    ticker = request.args.get('ticker', '').strip().upper()
    if not ticker:
        return jsonify({'status': 'error', 'message': 'ticker is required'}), 400

    # ── Cache check ───────────────────────────────────────────────
    if (ticker in _detail_cache
            and _time.time() - _detail_cache_time.get(ticker, 0) < 300):
        return jsonify(_detail_cache[ticker]), 200

    try:
        from datetime import datetime, timedelta

        end_date   = datetime.today().strftime('%Y-%m-%d')
        start_date = (datetime.today() - timedelta(days=400)).strftime('%Y-%m-%d')
        code       = f'US.{ticker}'

        _kline_limiter.acquire()
        ret, df, _ = quote_ctx.request_history_kline(
            code,
            start=start_date,
            end=end_date,
            ktype=KLType.K_DAY,
        )

        if ret != RET_OK:
            return jsonify({'status': 'error', 'message': str(df)}), 500

        if df is None or len(df) < 2:
            return jsonify({'status': 'error', 'message': 'Insufficient data'}), 500

        # ── Normalize column names ────────────────────────────────
        if 'close' in df.columns:
            closes = df['close'].astype(float)
        elif 'close_price' in df.columns:
            closes = df['close_price'].astype(float)
        else:
            return jsonify({'status': 'error', 'message': 'No close column found'}), 500

        closes = closes.reset_index(drop=True)
        price      = float(closes.iloc[-1])
        prev_close = float(closes.iloc[-2])

        # ── 1-day change ──────────────────────────────────────────
        change_1d = (price - prev_close) / prev_close * 100

        # ── YTD ──────────────────────────────────────────────────────
        # Find first bar of current year using time_key column
        current_year = datetime.today().year
        if 'time_key' in df.columns:
            year_mask = df['time_key'].astype(str).str.startswith(str(current_year))
            ytd_rows  = df[year_mask]
        else:
            ytd_rows = df  # fallback: use full window

        if len(ytd_rows) >= 1:
            if 'close' in df.columns:
                ytd_start = float(ytd_rows['close'].astype(float).iloc[0])
            else:
                ytd_start = float(ytd_rows['close_price'].astype(float).iloc[0])
            ytd_pct = (price - ytd_start) / ytd_start * 100
        else:
            ytd_pct = 0.0

        # ── 52-week high (last 252 trading bars) ──────────────────
        window_252 = closes.iloc[-252:] if len(closes) >= 252 else closes
        week52_high     = float(window_252.max())
        week52_high_pct = (price - week52_high) / week52_high * 100

        # ── Moving averages ───────────────────────────────────────
        def _ma(n: int) -> float:
            window = closes.iloc[-n:] if len(closes) >= n else closes
            return float(window.mean())

        def _ma_pct(ma_val: float) -> float:
            return (price - ma_val) / ma_val * 100

        ma10  = _ma(10)
        ma20  = _ma(20)
        ma50  = _ma(50)
        ma200 = _ma(200)

        # ── RSI 14 ────────────────────────────────────────────────
        def _rsi(period: int = 14) -> float:
            if len(closes) < period + 1:
                return 50.0  # neutral value when data is insufficient
            deltas  = closes.diff().dropna()
            gains   = deltas.clip(lower=0)
            losses  = (-deltas).clip(lower=0)
            # Wilder smoothed moving average (consistent with mainstream charting)
            avg_gain = gains.ewm(com=period - 1, min_periods=period).mean().iloc[-1]
            avg_loss = losses.ewm(com=period - 1, min_periods=period).mean().iloc[-1]
            if avg_loss == 0:
                return 100.0
            rs = avg_gain / avg_loss
            return round(100 - (100 / (1 + rs)), 2)

        rsi14 = _rsi(14)

        # ── Last 50 trading days closing prices (for frontend sparkline) ────
        closes_50d = [round(v, 2) for v in closes.iloc[-50:].tolist()]

        payload = {
            'status':        'success',
            'ticker':        ticker,
            'price':         round(price, 2),
            'change_1d':     round(change_1d, 2),
            'ytd_pct':       round(ytd_pct, 2),
            'week52_high':   round(week52_high, 2),
            'week52_high_pct': round(week52_high_pct, 2),
            'ma10':          round(ma10, 2),
            'ma10_pct':      round(_ma_pct(ma10), 2),
            'ma20':          round(ma20, 2),
            'ma20_pct':      round(_ma_pct(ma20), 2),
            'ma50':          round(ma50, 2),
            'ma50_pct':      round(_ma_pct(ma50), 2),
            'ma200':         round(ma200, 2),
            'ma200_pct':     round(_ma_pct(ma200), 2),
            'rsi14':         rsi14,
            'closes_50d':    closes_50d,
        }

        _detail_cache[ticker]      = payload
        _detail_cache_time[ticker] = _time.time()
        return jsonify(payload), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ======================== Market Breadth ========================

@app.route('/api/market_breadth', methods=['GET'])
def get_market_breadth():
    """Market breadth: major indices, VIX proxy, sector positive count.
    GET /api/market_breadth?period=1D|1W|1M
    Cache TTL = 120s per period.
    """
    import time as _time
    import traceback
    import threading
    from datetime import timedelta
    from concurrent.futures import ThreadPoolExecutor, as_completed

    global _breadth_cache, _breadth_cache_time

    period = request.args.get('period', '1D')
    if period not in ('1D', '1W', '1M'):
        period = '1D'
    cache_key = f'breadth_{period}'

    if (_breadth_cache is not None
            and _breadth_cache.get('key') == cache_key
            and _time.time() - _breadth_cache_time < BREADTH_CACHE_SECS):
        return jsonify(_breadth_cache['payload']), 200

    try:
        days_map   = {'1D': 5, '1W': 10, '1M': 35}
        days       = days_map.get(period, 5)
        end_date   = datetime.now().strftime('%Y-%m-%d')
        start_date = (datetime.now() - timedelta(days=days)).strftime('%Y-%m-%d')

        # Sector ETFs for breadth — always use 1D window (5 days)
        breadth_start = (datetime.now() - timedelta(days=5)).strftime('%Y-%m-%d')

        _lock = threading.Lock()

        def fetch_kline(code, s_date, e_date):
            """Fetch kline and return DataFrame or None."""
            _kline_limiter.acquire()
            with _lock:
                ret, kdf, _ = quote_ctx.request_history_kline(
                    code, start=s_date, end=e_date, ktype=KLType.K_DAY
                )
            if ret != RET_OK or kdf is None or len(kdf) == 0:
                return None
            return kdf

        def compute_change(kdf, p):
            close_col = 'close' if 'close' in kdf.columns else 'close_price'
            closes    = kdf[close_col].astype(float)
            last_close = closes.iloc[-1]
            price      = round(last_close, 2)
            if p == '1D':
                if len(closes) >= 2:
                    prev = closes.iloc[-2]
                    change_pct = round((last_close - prev) / prev * 100, 2) if prev > 0 else 0.0
                else:
                    cr_col = 'change_rate' if 'change_rate' in kdf.columns else None
                    change_pct = round(float(kdf.iloc[-1][cr_col]), 2) if cr_col else 0.0
            else:
                first = closes.iloc[0]
                change_pct = round((last_close - first) / first * 100, 2) if first > 0 else 0.0
            return price, change_pct

        # ── Fetch indices ────────────────────────────────────────
        indices = []
        for name, code in MARKET_INDICES.items():
            ticker = code.split('.')[-1]
            kdf = fetch_kline(code, start_date, end_date)
            if kdf is not None:
                price, change_pct = compute_change(kdf, period)
            else:
                price, change_pct = 0.0, 0.0
                print(f'[breadth] {code} kline failed')
            indices.append({'name': name, 'ticker': ticker,
                            'price': price, 'change_pct': change_pct})

        # ── Fetch real VIX via yfinance (^VIX spot index) ────────
        try:
            import yfinance as yf
            yf_period = {'1D': '10d', '1W': '1mo', '1M': '3mo'}.get(period, '10d')
            closes_vix = yf.Ticker('^VIX').history(period=yf_period)['Close'].dropna()
            if len(closes_vix) >= 2:
                vix_price  = round(float(closes_vix.iloc[-1]), 2)
                if period == '1D':
                    prev_vix   = float(closes_vix.iloc[-2])
                    vix_change = round((vix_price - prev_vix) / prev_vix * 100, 2) \
                                 if prev_vix > 0 else 0.0
                else:
                    first_vix  = float(closes_vix.iloc[0])
                    vix_change = round((vix_price - first_vix) / first_vix * 100, 2) \
                                 if first_vix > 0 else 0.0
            else:
                vix_price, vix_change = 0.0, 0.0
        except Exception as vix_err:
            print(f'[breadth] VIX fetch failed: {vix_err}')
            vix_price, vix_change = 0.0, 0.0

        # ── Fetch sector ETFs for breadth (always 1D) ────────────
        sector_map, _ = _load_etfs()
        sectors_positive = 0
        sectors_total    = len(sector_map)

        def fetch_sector_one(name_code):
            name, code = name_code
            kdf = fetch_kline(code, breadth_start, end_date)
            if kdf is None:
                return 0.0
            _, change_pct = compute_change(kdf, '1D')
            return change_pct

        with ThreadPoolExecutor(max_workers=4) as pool:
            futs = {pool.submit(fetch_sector_one, item): item
                    for item in sector_map.items()}
            for fut in as_completed(futs):
                cp = fut.result()
                if cp > 0:
                    sectors_positive += 1

        payload = {
            'status':           'success',
            'period':           period,
            'indices':          indices,
            'vix':              round(vix_price, 2),
            'vix_change':       round(vix_change, 2),
            'sectors_positive': sectors_positive,
            'sectors_total':    sectors_total,
        }
        _breadth_cache      = {'key': cache_key, 'payload': payload}
        _breadth_cache_time = _time.time()
        return jsonify(payload), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ======================== Earnings Calendar ========================

@app.route('/api/earnings_calendar', methods=['GET'])
def get_earnings_calendar():
    """Upcoming earnings for dynamically fetched tickers (next 7 days).
    Tickers sourced from trade history + current holdings. Cache TTL = 3600s.
    """
    import time as _time
    import traceback
    from concurrent.futures import ThreadPoolExecutor, as_completed
    from datetime import date, timedelta

    global _earnings_cache, _earnings_cache_time

    if (_earnings_cache is not None
            and _time.time() - _earnings_cache_time < EARNINGS_CACHE_SECS):
        return jsonify(_earnings_cache), 200

    try:
        import yfinance as yf

        today    = date.today()
        cutoff   = today + timedelta(days=7)

        def fetch_ticker_earnings(ticker):
            results = []
            try:
                t = yf.Ticker(ticker)
                cal = t.calendar  # dict or None

                # Primary: use .calendar dict
                if cal and isinstance(cal, dict):
                    raw_dates = cal.get('Earnings Date', [])
                    if not isinstance(raw_dates, list):
                        raw_dates = [raw_dates]
                    for rd in raw_dates:
                        try:
                            if hasattr(rd, 'date'):
                                d = rd.date()
                            else:
                                d = date.fromisoformat(str(rd)[:10])
                            if today <= d <= cutoff:
                                # Try to get time of day
                                time_label = 'TAS'
                                et = cal.get('Earnings Time') or cal.get('earnings_time')
                                if et:
                                    et_str = str(et).upper()
                                    if 'BMO' in et_str or 'BEFORE' in et_str:
                                        time_label = 'BMO'
                                    elif 'AMC' in et_str or 'AFTER' in et_str:
                                        time_label = 'AMC'
                                results.append({'ticker': ticker,
                                                'date':   d.isoformat(),
                                                'time':   time_label})
                        except Exception:
                            pass

                # Fallback: .earnings_dates DataFrame
                if not results:
                    try:
                        ed = t.earnings_dates
                        if ed is not None and not ed.empty:
                            for idx in ed.index:
                                try:
                                    if hasattr(idx, 'date'):
                                        d = idx.date()
                                    else:
                                        import pandas as _pd
                                        d = _pd.Timestamp(idx).date()
                                    if today <= d <= cutoff:
                                        results.append({'ticker': ticker,
                                                        'date':   d.isoformat(),
                                                        'time':   'TAS'})
                                except Exception:
                                    pass
                    except Exception:
                        pass
            except Exception as exc:
                print(f'[earnings] {ticker} error: {exc}')
            return results

        watchlist = _get_dynamic_tickers()
        all_events = []
        with ThreadPoolExecutor(max_workers=10) as pool:
            futs = {pool.submit(fetch_ticker_earnings, t): t
                    for t in watchlist}
            for fut in as_completed(futs):
                all_events.extend(fut.result())

        # De-duplicate (same ticker+date)
        seen = set()
        unique_events = []
        for ev in all_events:
            key = (ev['ticker'], ev['date'])
            if key not in seen:
                seen.add(key)
                unique_events.append(ev)

        # Sort by date
        unique_events.sort(key=lambda x: x['date'])

        # Group by date
        from collections import OrderedDict
        grouped = OrderedDict()
        for ev in unique_events:
            d_str = ev['date']
            if d_str not in grouped:
                grouped[d_str] = []
            grouped[d_str].append({'ticker': ev['ticker'], 'time': ev['time']})

        # Build response list with human-readable day label
        data = []
        for d_str, events in grouped.items():
            d_obj    = date.fromisoformat(d_str)
            day_label = d_obj.strftime('%a, %b %-d')
            data.append({'date': d_str, 'day_label': day_label, 'events': events})

        payload = {
            'status':       'success',
            'generated_at': today.isoformat(),
            'data':         data,
        }
        _earnings_cache      = payload
        _earnings_cache_time = _time.time()
        return jsonify(payload), 200

    except Exception as e:
        traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ======================== 📂 Open Position Trades ========================

@app.route('/api/holdings/<ticker>/trades', methods=['GET'])
def get_holding_trades(ticker):
    """
    Returns all trades in a position for a given ticker.
    - ?position_id=TSLA_3  → specific (closed or open) position by ID
    - no param             → auto-detect currently open position_id(s)
    Computes realized_pnl per trade and position-level R multiple.
    """
    ticker_clean = ticker.replace('US.', '').upper()
    position_id  = request.args.get('position_id')   # optional

    try:
        conn = sqlite3.connect(DB_FILE)

        # Pull ALL trades for this ticker so compute_realized_pnl has full history
        df_all = pd.read_sql(
            """SELECT order_id, code, trd_side, price, qty, create_time, position_id
               FROM trades
               WHERE UPPER(REPLACE(code, 'US.', '')) = ?
               ORDER BY create_time ASC""",
            conn, params=(ticker_clean,)
        )

        # Fetch stop prices for all positions of this ticker
        stop_rows = conn.execute(
            """SELECT position_id, stop_price
               FROM position_stops
               WHERE UPPER(REPLACE(ticker, 'US.', '')) = ?""",
            (ticker_clean,)
        ).fetchall()
        stop_map = {r[0]: r[1] for r in stop_rows}

        conn.close()

        if df_all.empty:
            return jsonify({'status': 'success', 'data': [], 'r_multiple': None}), 200

        # Compute realized_pnl for every row using full history (correct avg cost)
        df_pnl = calculate_trades_pnl(df_all.copy())

        if position_id:
            # Specific position requested (from AllTradesScreen)
            target_df = df_pnl[df_pnl['position_id'] == position_id].copy()
        else:
            # Auto-detect open positions (net qty > 0)
            open_pids = set()
            for pid, grp in df_pnl.groupby('position_id'):
                buy_qty  = grp[grp['trd_side'].isin(['BUY',  'BUY_BACK'])]['qty'].sum()
                sell_qty = grp[grp['trd_side'].isin(['SELL', 'SELL_SHORT'])]['qty'].sum()
                if buy_qty - sell_qty > 0.001:
                    open_pids.add(pid)
            if not open_pids:
                return jsonify({'status': 'success', 'data': [], 'r_multiple': None}), 200
            target_df = df_pnl[df_pnl['position_id'].isin(open_pids)].copy()

        if target_df.empty:
            return jsonify({'status': 'success', 'data': [], 'r_multiple': None}), 200

        # Compute position-level stats
        pid_used    = target_df['position_id'].iloc[0]
        stop_price  = stop_map.get(pid_used)
        total_pnl   = float(target_df['realized_pnl'].sum())

        # Weighted-average entry price from BUY/SELL_SHORT legs
        entry_legs = target_df[target_df['trd_side'].isin(['BUY', 'SELL_SHORT'])]
        entry_qty  = float(entry_legs['qty'].sum())
        entry_price = (
            float((entry_legs['price'] * entry_legs['qty']).sum()) / entry_qty
        ) if entry_qty > 0 else 0.0

        # R = total_pnl / (|entry - stop| × total_exit_qty)
        r_multiple = None
        if stop_price and entry_price > 0:
            exit_legs = target_df[target_df['trd_side'].isin(['SELL', 'BUY_BACK'])]
            exit_qty  = float(exit_legs['qty'].sum())
            risk      = abs(entry_price - stop_price) * exit_qty
            if risk > 0.001:
                r_multiple = round(total_pnl / risk, 2)

        result = []
        for _, row in target_df.iterrows():
            dt  = pd.to_datetime(row['create_time'])
            pid = row.get('position_id')
            result.append({
                'order_id':     str(row['order_id']),
                'position_id':  pid,
                'action':       row['trd_side'],
                'price':        round(float(row['price']), 4),
                'qty':          float(row['qty']),
                'realized_pnl': round(float(row['realized_pnl']), 2),
                'date':         dt.strftime('%Y-%m-%d'),
                'time':         dt.strftime('%H:%M'),
                'day':          dt.strftime('%d'),
                'month':        dt.strftime('%b').upper(),
                'stop_price':   stop_map.get(pid),
            })

        return jsonify({
            'status':       'success',
            'data':         result,
            'total_pnl':    round(total_pnl, 2),
            'entry_price':  round(entry_price, 4),
            'stop_price':   stop_price,
            'r_multiple':   r_multiple,
        }), 200

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


# ======================== Account Balance ========================

@app.route('/api/account', methods=['GET'])
def get_account():
    """Returns USD account balance: total_assets, securities_assets.
    Cached for ACCOUNT_CACHE_SECS seconds.
    """
    global _account_cache, _account_cache_time

    if (_account_cache is not None
            and _time.time() - _account_cache_time < ACCOUNT_CACHE_SECS):
        return jsonify(_account_cache), 200

    try:
        ret, data = trd_ctx.accinfo_query(
            trd_env=TRD_ENV,
            acc_id=MOOMOO_ACC_ID,
            currency=Currency.USD,
        )
        if ret != RET_OK:
            return jsonify({'status': 'error', 'message': str(data)}), 500

        row = data.iloc[0]
        total_assets     = float(row.get('total_assets',     0))
        securities_assets = float(row.get('securities_assets', 0))

        payload = {
            'status':           'success',
            'total_assets':     round(total_assets, 2),
            'securities_assets': round(securities_assets, 2),
        }
        _account_cache      = payload
        _account_cache_time = _time.time()
        return jsonify(payload), 200

    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({'status': 'error', 'message': str(e)}), 500


if __name__ == '__main__':
    print("Backend Server Running")
    _write_position_pnl()
    # Kick off RAG index build in background (non-blocking)
    if DEEPSEEK_API_KEY:
        try:
            import rag
            rag.init_async()
            print("RAG index building in background...")
        except Exception as e:
            print(f"RAG init skipped: {e}")
    app.run(host='0.0.0.0', port=5001)