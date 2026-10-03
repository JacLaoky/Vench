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
from datetime import datetime, timedelta
import sqlite3
import pandas as pd
from flask import Flask, request, jsonify, send_from_directory, Response, stream_with_context
from flask_cors import CORS
from moomoo import *
from flask import Response, stream_with_context  # re-import after moomoo to avoid shadowing
from datetime import datetime, timedelta  # re-import: `from moomoo import *` shadows datetime
import positions as P

app = Flask(__name__)
# Only our own web front-ends may call the API from a browser (comma-separated origins)
CORS(app, origins=[o.strip() for o in os.environ.get('CORS_ORIGINS', 'http://localhost:5173').split(',') if o.strip()])
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024
ALLOWED_IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.webp'}

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
DETAIL_CACHE_MAX = 200              # oldest ticker evicted beyond this (key comes from the URL)
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
    _add_column_if_missing(conn, 'trades', 'fee', "REAL NOT NULL DEFAULT 0.0")
    _add_column_if_missing(conn, 'trades', 'fee_details', "TEXT NOT NULL DEFAULT '[]'")

    conn.execute('''
        CREATE TABLE IF NOT EXISTS position_stops (
            position_id  TEXT PRIMARY KEY,
            ticker       TEXT NOT NULL,
            stop_price   REAL NOT NULL,
            updated_at   TEXT NOT NULL
        )
    ''')

    # initial_stop is locked at the first stop ever set (defines 1R); stop_price is the current stop
    _add_column_if_missing(conn, 'position_stops', 'initial_stop', 'REAL')
    conn.execute('UPDATE position_stops SET initial_stop = stop_price WHERE initial_stop IS NULL')

    # Broker-reconciled closes: after this order the broker shows the ticker flat even though the
    # order history leaves a small residue (fractional shares moved outside of orders)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS position_resets (
            order_id    TEXT PRIMARY KEY,
            code        TEXT NOT NULL,
            residue     REAL NOT NULL,
            created_at  TEXT NOT NULL
        )
    ''')

    # position_pnl is fully derived (rebuilt on every sync) — recreate it when the schema is old
    pnl_cols = {row[1] for row in conn.execute('PRAGMA table_info(position_pnl)')}
    if pnl_cols and 'status' not in pnl_cols:
        conn.execute('DROP VIEW IF EXISTS ticker_pnl')
        conn.execute('DROP TABLE position_pnl')
    conn.execute('''
        CREATE TABLE IF NOT EXISTS position_pnl (
            position_id  TEXT PRIMARY KEY,
            code         TEXT NOT NULL,
            direction    TEXT NOT NULL,
            status       TEXT NOT NULL,
            realized_pnl REAL NOT NULL,
            is_win       INTEGER,
            entry_qty    REAL NOT NULL,
            avg_entry    REAL NOT NULL,
            initial_stop REAL,
            r_multiple   REAL,
            open_time    TEXT,
            close_time   TEXT
        )
    ''')

    # ticker_pnl: per-ticker net P&L over closed positions (use this for ranking/win-rate questions)
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
        WHERE status = 'closed'
        GROUP BY code
    ''')

    # Legacy tables from an earlier design: never written by this code — drop them while empty
    for legacy in ('positions', 'journal_entries'):
        exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (legacy,)
        ).fetchone()
        if exists and conn.execute(f'SELECT COUNT(*) FROM {legacy}').fetchone()[0] == 0:
            conn.execute(f'DROP TABLE {legacy}')

    conn.commit()
    conn.close()
    print("Database initialized (including notes tables)")

init_db()


def load_resets(conn) -> set:
    return {r[0] for r in conn.execute('SELECT order_id FROM position_resets')}


def assign_position_ids():
    """Assign every fill to its position (id = first order_id of the position, see positions.py).
    Stops saved against an older id follow their position to the new id.
    """
    conn = sqlite3.connect(DB_FILE)
    df = pd.read_sql_query(
        'SELECT order_id, code, trd_side, qty, create_time, position_id AS old_id FROM trades', conn
    )
    if df.empty:
        conn.close()
        return
    df['qty'] = pd.to_numeric(df['qty'])
    df['create_time'] = pd.to_datetime(df['create_time'], format='mixed')
    df['position_id'] = P.assign_cycles(df, load_resets(conn))

    moved = (
        df[df['old_id'].notna() & (df['old_id'] != df['position_id'])]
        .groupby('old_id')['position_id'].first().to_dict()
    )
    for old_id, new_id in moved.items():
        conn.execute(
            'UPDATE OR IGNORE position_stops SET position_id=? WHERE position_id=?', (new_id, old_id)
        )
    conn.executemany(
        'UPDATE trades SET position_id=? WHERE order_id=?',
        list(zip(df['position_id'], df['order_id'])),
    )
    conn.commit()
    conn.close()
    invalidate_cache()
    print(f'[positions] {df["position_id"].nunique()} positions over {len(df)} fills; '
          f'{len(moved)} position ids migrated')


# ======================== Moomoo Connection ========================
trd_ctx   = OpenSecTradeContext(filter_trdmarket=TrdMarket.US,
                                host=HOST_IP, port=HOST_PORT,
                                security_firm=SecurityFirm.FUTUSG)
quote_ctx = OpenQuoteContext(host=HOST_IP, port=HOST_PORT)

# Gracefully close both connections on process exit
atexit.register(lambda: (trd_ctx.close(), quote_ctx.close()))


# ======================== 🛠️ Utilities ========================

get_multiplier = P.multiplier


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

    ctx = _card_context()
    trade_id = str(row['order_id'])
    saved_tags, position_id, own_fee, own_fee_details = ctx['meta'].get(trade_id, ([], None, 0.0, []))

    # Scope find_round_trip to this position's fills only
    trip_df = ctx['fills'].get(position_id, df)

    transactions, enter_time = find_round_trip(trip_df, ticker_raw, exit_time, trade_type)

    holding_str = fmt_holding(exit_time - enter_time)

    multiplier  = get_multiplier(ticker_raw)
    trade_value = float(row['price']) * float(row['qty']) * multiplier
    # pct and isProfit computed after fee attribution below (need fee_amount first)

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

    saved_note, saved_images = ctx['notes'].get(trade_id, ('', []))

    # Fees: each partial exit carries its own fee; the final exit of the position also carries
    # every entry-leg fee (scale-in buys), since entry costs can't be fairly split across exits.
    is_final_close = position_id is None or ctx['last_close'].get(position_id) == trade_id
    fee_amount  = own_fee
    fee_details = list(own_fee_details)
    if is_final_close and position_id:
        entry_fee, entry_details = ctx['entry_fees'].get(position_id, (0.0, []))
        fee_amount += entry_fee
        fee_details.extend(entry_details)

    # Position-level facts (stops, status, R) come from the position engine
    stop_price = initial_stop = position_r = position_status = None
    p = ctx['positions'].get(position_id)
    if p is not None:
        stop_price      = None if pd.isna(p['stop_price']) else float(p['stop_price'])
        initial_stop    = None if pd.isna(p['initial_stop']) else float(p['initial_stop'])
        position_status = p['status']
        position_r      = p['r_multiple']

    net_pnl_val = round(pnl - fee_amount, 2)
    pct         = (net_pnl_val / trade_value * 100) if trade_value > 0 else 0

    return {
        "trade_id":     trade_id,
        "day":          exit_time.strftime('%d'),
        "month":        exit_time.strftime('%b'),
        "ticker":       clean_name,
        "trade_type":   trade_type,
        "pnl":          round(pnl, 2),
        "pct":          f"{int(pct)}%",
        "isProfit":     net_pnl_val >= 0,
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
        "initial_stop": initial_stop,
        "position_status": position_status,
        "r_multiple":   position_r if is_final_close and position_status == 'closed' else None,
        "price":        float(row['price']),
        "qty":          float(row['qty']),
        "entry_price":  round(entry_price, 4),
        "fee":          round(fee_amount, 4),
        "fee_details":  fee_details,
        "net_pnl":      net_pnl_val,
    }


# ======================== Data Access Layer (with cache) ========================

# Module-level caches: avoid recomputing on every API request
_pnl_cache: pd.DataFrame | None = None
_positions_cache: pd.DataFrame | None = None


_card_ctx: dict | None = None


def invalidate_cache():
    """Call after syncing data or editing stops/notes/tags to clear the derived caches."""
    global _pnl_cache, _positions_cache, _card_ctx
    _pnl_cache = None
    _positions_cache = None
    _card_ctx = None


def _card_context() -> dict:
    """Everything build_trade_card looks up, loaded once per cache generation instead of
    ~5 queries per card (the journal renders hundreds of cards)."""
    global _card_ctx
    if _card_ctx is not None:
        return _card_ctx
    conn = sqlite3.connect(DB_FILE)
    notes = {
        tid: (note, json.loads(paths) if paths else [])
        for tid, note, paths in conn.execute('SELECT trade_id, note, image_paths FROM trade_notes')
    }
    meta, last_close, entry_fees = {}, {}, {}
    for oid, pid, side, tags, fee, details in conn.execute(
        'SELECT order_id, position_id, trd_side, tags, fee, fee_details FROM trades '
        'ORDER BY create_time, order_id'
    ):
        fee = float(fee or 0)
        details = json.loads(details) if details else []
        meta[oid] = (json.loads(tags) if tags else [], pid, fee, details)
        if side in ('SELL', 'BUY_BACK'):
            last_close[pid] = oid          # ordered by time: the last one wins
        elif side in ('BUY', 'SELL_SHORT'):
            acc = entry_fees.setdefault(pid, [0.0, []])
            acc[0] += fee
            acc[1].extend(details)
    conn.close()

    pos = load_positions()
    df = load_df_with_pnl()
    _card_ctx = {
        'notes': notes,
        'meta': meta,
        'last_close': last_close,
        'entry_fees': {pid: (v[0], v[1]) for pid, v in entry_fees.items()},
        'positions': {r['position_id']: r for r in pos.to_dict('records')} if not pos.empty else {},
        'fills': {pid: g for pid, g in df.groupby('position_id')} if not df.empty else {},
    }
    return _card_ctx


def _notes_changed():
    """Notes/tags/images edited: refresh card lookups and let the Journal AI re-index notes."""
    invalidate_cache()
    if DEEPSEEK_API_KEY:
        import rag
        rag.mark_dirty()


def now_et() -> pd.Timestamp:
    """Current US/Eastern wall-clock time, naive — trade times from Moomoo are naive Eastern."""
    return pd.Timestamp.now(tz='America/New_York').tz_localize(None)


def load_positions() -> pd.DataFrame:
    """One row per position (open and closed) with net P&L, initial/current stop and R multiple."""
    global _positions_cache
    if _positions_cache is not None:
        return _positions_cache.copy()

    df = load_df_with_pnl()
    if df.empty:
        return pd.DataFrame()
    conn = sqlite3.connect(DB_FILE)
    resets = load_resets(conn)
    stops = pd.read_sql_query(
        'SELECT position_id, stop_price, initial_stop FROM position_stops', conn
    )
    conn.close()

    summary = P.summarize(df, resets).merge(stops, on='position_id', how='left')
    summary['r_multiple'] = [
        P.r_multiple(r.net_pnl, r.avg_entry, r.initial_stop, r.entry_qty, r.multiplier)
        for r in summary.itertuples()
    ]
    summary['is_win'] = summary['net_pnl'] > 0
    _positions_cache = summary
    return summary.copy()


def closed_positions(period: str = 'AT') -> pd.DataFrame:
    """Closed positions whose close time falls in the period — the unit for win rate/expectancy."""
    pos = load_positions()
    if pos.empty:
        return pos
    closed = pos[pos['status'] == 'closed'].copy()
    closed['create_time'] = closed['close_time']   # slice_by_period filters on create_time
    return slice_by_period(closed, period).sort_values('close_time')


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

    df['fee'] = pd.to_numeric(df['fee'], errors='coerce').fillna(0)
    _pnl_cache = calculate_trades_pnl(df)
    # Net P&L per fill: realized_pnl minus this order's own fee (entry fees land on entry fills)
    _pnl_cache['net_realized_pnl'] = _pnl_cache['realized_pnl'] - _pnl_cache['fee']
    _pnl_cache['is_win'] = (_pnl_cache['net_realized_pnl'] > 0) & (_pnl_cache['realized_pnl'] != 0)
    print("♻️  PnL cache updated")
    return _pnl_cache.copy()


def slice_by_period(df: pd.DataFrame, period: str) -> pd.DataFrame:
    """Slice a PnL DataFrame by the given period parameter."""
    now = now_et()

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
    """Persist every position (open and closed) to position_pnl for the Journal AI's SQL tool.
    realized_pnl is net of all fees; is_win is only set once a position is closed.
    """
    try:
        pos = load_positions()
        if pos.empty:
            return
        conn = sqlite3.connect(DB_FILE)
        conn.execute("DELETE FROM position_pnl")
        conn.executemany(
            "INSERT INTO position_pnl (position_id, code, direction, status, realized_pnl, is_win, "
            "entry_qty, avg_entry, initial_stop, r_multiple, open_time, close_time) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    r.position_id, r.code, r.direction, r.status,
                    round(float(r.net_pnl), 2),
                    int(r.net_pnl > 0) if r.status == 'closed' else None,
                    float(r.entry_qty), round(float(r.avg_entry), 4),
                    None if pd.isna(r.initial_stop) else float(r.initial_stop),
                    r.r_multiple,
                    str(r.open_time),
                    None if pd.isna(r.close_time) else str(r.close_time),
                )
                for r in pos.itertuples()
            ]
        )
        conn.commit()
        conn.close()
        print(f"[position_pnl] written {len(pos)} positions ({(pos['status'] == 'closed').sum()} closed)")
    except Exception as e:
        print(f"[position_pnl] write failed: {e}")


# ======================== 🧮 Core Financial Algorithms ========================

def calculate_trades_pnl(df: pd.DataFrame) -> pd.DataFrame:
    """Per-fill gross realized P&L (moving-average cost, longs and shorts) — see positions.py."""
    conn = sqlite3.connect(DB_FILE)
    resets = load_resets(conn)
    conn.close()
    df = P.realized_pnl(df, resets)
    df['is_win'] = df['realized_pnl'] > 0
    return df


# ======================== Moomoo Data Fetch ========================

def sync_trades_to_db() -> bool:
    """Pull filled orders from Moomoo into SQLite (upsert), refresh fees, reconcile residues."""
    print("🔄 Syncing historical orders...")

    # history_order_list_query rejects ranges longer than 360 days; older fills are already stored
    start_date = (datetime.now() - timedelta(days=359)).strftime("%Y-%m-%d")
    end_date   = datetime.now().strftime("%Y-%m-%d")

    # CANCELLED_PART = partly filled, then cancelled: its fills are real and must not be dropped
    ret, data = trd_ctx.history_order_list_query(
        status_filter_list=[OrderStatus.FILLED_ALL, OrderStatus.FILLED_PART, OrderStatus.CANCELLED_PART],
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

    data = data[data['dealt_qty'].astype(float) > 0]
    # updated_time ≈ fill time; create_time is when the order was placed (a GTC stop can fill weeks later)
    records = [
        (str(r['order_id']), r['code'], r['trd_side'],
         float(r['dealt_avg_price']), float(r['dealt_qty']), r['updated_time'] or r['create_time'])
        for _, r in data.iterrows()
    ]

    conn = sqlite3.connect(DB_FILE)
    before = {
        oid: (qty, price, t) for oid, qty, price, t in
        conn.execute('SELECT order_id, qty, price, create_time FROM trades')
    }
    conn.executemany(
        """INSERT INTO trades (order_id, code, trd_side, price, qty, create_time) VALUES (?,?,?,?,?,?)
           ON CONFLICT(order_id) DO UPDATE SET
               price = excluded.price, qty = excluded.qty, create_time = excluded.create_time""",
        records
    )
    inserted = [r[0] for r in records if r[0] not in before]
    changed = [
        r[0] for r in records
        if r[0] in before and (abs(before[r[0]][0] - r[4]) > 1e-9 or abs(before[r[0]][1] - r[3]) > 1e-9)
    ]
    retimed = sum(1 for r in records if r[0] in before and before[r[0]][2] != r[5])
    conn.commit()

    # Fees: new orders, orders whose fill changed, and any still missing a fee
    order_ids = [r[0] for r in records]
    missing = [
        row[0] for row in conn.execute(
            f"SELECT order_id FROM trades WHERE fee=0 AND order_id IN ({','.join('?'*len(order_ids))})",
            order_ids
        ).fetchall()
    ]
    need_fee = sorted(set(missing) | set(changed))
    if need_fee:
        print(f"💰 Querying fees for {len(need_fee)} orders…")
        ret_fee, fee_data = trd_ctx.order_fee_query(
            order_id_list=need_fee,
            trd_env=TRD_ENV,
            acc_id=MOOMOO_ACC_ID,
        )
        if ret_fee == RET_OK and not fee_data.empty:
            fee_updates = []
            for _, fr in fee_data.iterrows():
                raw_amount  = fr['fee_amount']
                fee_amount  = float(raw_amount) if raw_amount != 'N/A' else 0.0
                fee_details = json.dumps(fr['fee_details']) if fr['fee_details'] else '[]'
                fee_updates.append((fee_amount, fee_details, str(fr['order_id'])))
            conn.executemany('UPDATE trades SET fee=?, fee_details=? WHERE order_id=?', fee_updates)
            conn.commit()
            print(f"✅ Fees stored for {len(fee_updates)} orders.")
        else:
            print(f"⚠️ Fee query failed or returned empty: {fee_data}")

    _reconcile_residues(conn)
    conn.close()
    invalidate_cache()
    print(f"Sync complete! {len(inserted)} new, {len(changed)} updated, {retimed} re-timed to fill time.")
    return True


def _reconcile_residues(conn) -> None:
    """If the broker shows a ticker flat but the order history leaves less than one share
    (fractional shares moved outside of orders), close the position after its last fill.
    Larger gaps are left open on purpose — they mean fills are missing and should be visible.
    """
    ret, held = trd_ctx.position_list_query(trd_env=TRD_ENV, acc_id=MOOMOO_ACC_ID)
    if ret != RET_OK:
        print(f"⚠️ Residue check skipped, position query failed: {held}")
        return
    held_qty = {r['code']: float(r['qty']) for _, r in held.iterrows()} if not held.empty else {}

    rows = conn.execute(
        'SELECT order_id, code, trd_side, qty FROM trades ORDER BY create_time, order_id'
    ).fetchall()
    resets = load_resets(conn)
    running, last_order = {}, {}
    for oid, code, side, qty in rows:
        running[code] = 0.0 if oid in resets else running.get(code, 0.0) + P.signed_qty(side, float(qty))
        last_order[code] = oid

    for code, qty in running.items():
        if P.EPS <= abs(qty) < 1 and abs(held_qty.get(code, 0.0)) < P.EPS:
            conn.execute(
                'INSERT OR IGNORE INTO position_resets (order_id, code, residue, created_at) VALUES (?,?,?,?)',
                (last_order[code], code, qty, datetime.now().isoformat())
            )
            print(f"🔧 {code}: broker is flat but orders leave {qty:+.4f} — position closed after {last_order[code]}")
    conn.commit()



# ======================== 📊 Per-position statistics ========================

def _fmt_usd(v):
    return "$0.00" if pd.isna(v) else f"{'-' if v < 0 else ''}${abs(v):.2f}"


def _fmt_pct(v):
    return "0.00%" if pd.isna(v) else f"{v * 100:.2f}%"


def _fmt_time(s):
    if pd.isna(s): return "0s"
    if s < 60:     return "a few seconds"
    if s < 3600:   return f"{int(s / 60)}m"
    if s < 86400:  return f"{int(s / 3600)}h"
    return f"{int(s / 86400)}d"


def _fmt_hour(h):
    if pd.isna(h): return "0:00"
    return f"{int(h):02d}:{int((h - int(h)) * 60):02d}"


def deep_stats(cp: pd.DataFrame) -> dict:
    """Gain/loss, long/short, timing, best/worst and per-symbol breakdown over closed positions."""
    df_t = pd.DataFrame({
        'pnl':         cp['net_pnl'].astype(float),
        'pct':         (cp['net_pnl'] / cp['entry_cost'].where(cp['entry_cost'] > 0)).fillna(0.0),
        'is_win':      cp['is_win'].astype(bool),
        'type':        cp['direction'],
        'holding_sec': (cp['close_time'] - cp['open_time']).dt.total_seconds(),
        'entry_hour':  cp['open_time'].dt.hour + cp['open_time'].dt.minute / 60.0,
        'symbol':      cp['code'].str.split('.').str[-1],
    }) if not cp.empty else pd.DataFrame(
        columns=['pnl', 'pct', 'is_win', 'type', 'holding_sec', 'entry_hour', 'symbol'])
    won_t  = df_t[df_t['is_win'] == True]
    lost_t = df_t[df_t['is_win'] == False]

    symbol_stats = []
    for sym, grp in df_t.groupby('symbol'):
        w = grp[grp['is_win'] == True]
        l = grp[grp['is_win'] == False]
        sym_pnl = float(grp['pnl'].sum())
        symbol_stats.append({
            "symbol": str(sym),
            "trades": {"all": str(len(grp)), "won": str(len(w)), "lost": str(len(l))},
            "amount": {
                "all":  _fmt_usd(sym_pnl),
                "won":  _fmt_usd(float(w['pnl'].sum())) if not w.empty else "$0.00",
                "lost": _fmt_usd(float(l['pnl'].sum())) if not l.empty else "$0.00",
            },
            "pnl_raw":      round(sym_pnl, 2),
            "isProfit":     bool(sym_pnl >= 0),
            "_raw_trades":  int(len(grp)),
            "_raw_pnl_abs": abs(sym_pnl),
        })

    return {
        "gain_loss": {
            "total":    {"all": _fmt_usd(df_t['pnl'].sum()),  "won": _fmt_usd(won_t['pnl'].sum()),  "lost": _fmt_usd(lost_t['pnl'].sum())},
            "avg_usd":  {"all": _fmt_usd(df_t['pnl'].mean()), "won": _fmt_usd(won_t['pnl'].mean()), "lost": _fmt_usd(lost_t['pnl'].mean())},
            "avg_pct":  {"all": _fmt_pct(df_t['pct'].mean()), "won": _fmt_pct(won_t['pct'].mean()), "lost": _fmt_pct(lost_t['pct'].mean())},
            "trades":   {"all": str(len(df_t)), "won": str(len(won_t)), "lost": str(len(lost_t))},
            "win_rate": _fmt_pct(len(won_t) / len(df_t) if len(df_t) else 0),
        },
        "long_short": {
            "long":  {"all": str((df_t['type'] == 'LONG').sum()),  "won": str((won_t['type'] == 'LONG').sum()),  "lost": str((lost_t['type'] == 'LONG').sum())},
            "short": {"all": str((df_t['type'] == 'SHORT').sum()), "won": str((won_t['type'] == 'SHORT').sum()), "lost": str((lost_t['type'] == 'SHORT').sum())},
        },
        "timing": {
            "holding":    {"all": _fmt_time(df_t['holding_sec'].mean()), "won": _fmt_time(won_t['holding_sec'].mean()), "lost": _fmt_time(lost_t['holding_sec'].mean())},
            "entry_hour": {"all": _fmt_hour(df_t['entry_hour'].mean()),  "won": _fmt_hour(won_t['entry_hour'].mean()),  "lost": _fmt_hour(lost_t['entry_hour'].mean())},
        },
        "best_worst": {
            "largest_usd": {"won": _fmt_usd(won_t['pnl'].max() if not won_t.empty else 0), "lost": _fmt_usd(lost_t['pnl'].min() if not lost_t.empty else 0)},
            "largest_pct": {"won": _fmt_pct(won_t['pct'].max() if not won_t.empty else 0), "lost": _fmt_pct(lost_t['pct'].min() if not lost_t.empty else 0)},
        },
        "symbols_by_trades": sorted(symbol_stats, key=lambda x: x['_raw_trades'], reverse=True),
        "symbols_by_amount": sorted(symbol_stats, key=lambda x: x['pnl_raw'],     reverse=True),
    }


R_BUCKETS = [(-float('inf'), -2, '≤ -2R'), (-2, -1, '-2R ~ -1R'), (-1, 0, '-1R ~ 0'),
             (0, 1, '0 ~ 1R'), (1, 2, '1R ~ 2R'), (2, 3, '2R ~ 3R'), (3, float('inf'), '≥ 3R')]


def r_stats(cp: pd.DataFrame) -> dict:
    """Expectancy and distribution in R, over closed positions that have an initial stop."""
    rs = cp['r_multiple'].dropna().astype(float) if not cp.empty else pd.Series(dtype=float)
    if rs.empty:
        return {"count": 0, "coverage": f"0/{len(cp)}", "expectancy_r": None,
                "avg_win_r": None, "avg_loss_r": None, "total_r": None, "distribution": []}
    wins, losses = rs[rs > 0], rs[rs <= 0]
    return {
        "count":        int(len(rs)),
        "coverage":     f"{len(rs)}/{len(cp)}",
        "expectancy_r": round(float(rs.mean()), 2),
        "avg_win_r":    round(float(wins.mean()), 2) if len(wins) else None,
        "avg_loss_r":   round(float(losses.mean()), 2) if len(losses) else None,
        "total_r":      round(float(rs.sum()), 2),
        "distribution": [
            {"label": label, "count": int(((rs > lo) & (rs <= hi)).sum()) if lo != -float('inf') else int((rs <= hi).sum())}
            for lo, hi, label in R_BUCKETS
        ],
    }


def daily_pnl_series(df: pd.DataFrame) -> pd.Series:
    """Net realized P&L per business day across the period, including flat days (zeros)."""
    if df.empty:
        return pd.Series(dtype=float)
    daily = df.groupby(df['create_time'].dt.normalize())['net_realized_pnl'].sum()
    days = pd.bdate_range(daily.index.min(), daily.index.max())
    return daily.reindex(days.union(daily.index), fill_value=0.0)


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

        # Enrich with the open position's id and stops from the position engine
        if rows:
            pos = load_positions()
            open_pos = {}
            if not pos.empty:
                for r in pos[pos['status'] == 'open'].sort_values('open_time').itertuples():
                    open_pos[r.code.replace('US.', '').upper()] = r
            for row in rows:
                op = open_pos.get(row['ticker'].upper())
                row['position_id']  = op.position_id if op else None
                row['stop_price']   = None if not op or pd.isna(op.stop_price) else float(op.stop_price)
                row['initial_stop'] = None if not op or pd.isna(op.initial_stop) else float(op.initial_stop)

        return jsonify({"status": "success", "data": rows}), 200
    except Exception as e:
        import traceback; traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/api/sync', methods=['POST'])
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
            import rag
            rag.mark_dirty()   # trade-note headers may have changed; re-embedded on the next search
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
    invalidate_cache()
    if cur.rowcount == 0:
        return jsonify({'status': 'error', 'message': 'trade not found'}), 404
    return jsonify({'status': 'success', 'tags': tags}), 200


@app.route('/api/positions/<position_id>/stop', methods=['PATCH'])
def set_position_stop(position_id):
    """Set the current stop. The first stop ever set becomes the initial stop (defines 1R) and is
    not changed by later moves; pass `initial_stop` explicitly only to correct it.
    """
    body       = request.get_json(force=True)
    stop_price = float(body.get('stop_price', 0))
    ticker     = body.get('ticker', '')
    initial    = body.get('initial_stop')

    conn = sqlite3.connect(DB_FILE)
    conn.execute('''
        INSERT INTO position_stops (position_id, ticker, stop_price, initial_stop, updated_at)
        VALUES (?, ?, ?, COALESCE(?, ?), ?)
        ON CONFLICT(position_id) DO UPDATE SET
            stop_price   = excluded.stop_price,
            initial_stop = COALESCE(?, position_stops.initial_stop, excluded.stop_price),
            updated_at   = excluded.updated_at
    ''', (position_id, ticker, stop_price, initial, stop_price, datetime.now().isoformat(), initial))
    row = conn.execute(
        'SELECT stop_price, initial_stop FROM position_stops WHERE position_id=?', (position_id,)
    ).fetchone()
    conn.commit()
    conn.close()
    invalidate_cache()
    _write_position_pnl()
    return jsonify({'status': 'success', 'position_id': position_id,
                    'stop_price': row[0], 'initial_stop': row[1]}), 200


@app.route('/api/positions/<position_id>/stop', methods=['GET'])
def get_position_stop(position_id):
    conn = sqlite3.connect(DB_FILE)
    row  = conn.execute(
        'SELECT stop_price, initial_stop FROM position_stops WHERE position_id=?', (position_id,)
    ).fetchone()
    conn.close()
    if row:
        return jsonify({'status': 'success', 'stop_price': row[0], 'initial_stop': row[1]}), 200
    return jsonify({'status': 'not_found', 'stop_price': None, 'initial_stop': None}), 200


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

    # One sample per closed position (net of fees), tagged with every tag on any of its fills
    closed = closed_positions(timeframe)
    if closed.empty:
        return jsonify({'status': 'success', 'timeframe': timeframe, 'data': []}), 200

    conn = sqlite3.connect(DB_FILE)
    tag_rows = conn.execute(
        "SELECT position_id, tags FROM trades WHERE tags IS NOT NULL AND tags NOT IN ('', '[]')"
    ).fetchall()
    conn.close()
    tags_by_position: dict[str, set] = {}
    for pid, tags_str in tag_rows:
        try:
            tags_by_position.setdefault(pid, set()).update(json.loads(tags_str))
        except Exception:
            pass

    tag_stats = {}  # tag -> {pnls: [], wins: int, losses: int}
    for pos in closed.itertuples():
        tags = tags_by_position.get(pos.position_id)
        if not tags:
            continue
        pnl = float(pos.net_pnl)
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

    # Wins/losses count positions that closed on that day/month (not individual sell orders)
    cp = closed_positions('AT')
    closed_by_day   = cp.groupby(cp['close_time'].dt.strftime('%Y-%m-%d'))['is_win'] if not cp.empty else None
    closed_by_month = cp.groupby(cp['close_time'].dt.strftime('%Y-%m'))['is_win'] if not cp.empty else None

    def _win_loss(groups, key):
        if groups is None or key not in groups.groups:
            return 0, 0
        g = groups.get_group(key)
        return int(g.sum()), int(len(g) - g.sum())

    # --- Group by day ---
    daily_data = []
    for date_str, grp in df.groupby('date'):
        dt_obj     = datetime.strptime(date_str, '%Y-%m-%d')
        daily_pnl  = grp['net_realized_pnl'].sum()
        wins, losses = _win_loss(closed_by_day, date_str)
        win_pct    = f"{int(wins / (wins + losses) * 100)}%" if wins + losses else "0%"

        # Per ticker: bundle all closing trades for that day into a trade card list
        ticker_pills = []
        for ticker, g in grp.groupby('code'):
            clean   = ticker.replace('US.', '')
            grp_pnl = g['net_realized_pnl'].sum()
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
            "losses":   str(losses),
            "comm":     f"${grp['fee'].sum():.2f}",
            "tickers":  ticker_pills,
        })

    daily_data.sort(key=lambda x: x['date'], reverse=True)

    # --- Group by month ---
    monthly_data = []
    for month_key, grp in df.groupby('month_sort_key'):
        grp_sorted  = grp.sort_values('create_time')
        monthly_pnl = grp_sorted['net_realized_pnl'].sum()
        wins, losses = _win_loss(closed_by_month, month_key)
        win_pct     = f"{int(wins / (wins + losses) * 100)}%" if wins + losses else "0%"
        month_cp    = cp[cp['close_time'].dt.strftime('%Y-%m') == month_key] if not cp.empty else cp
        month_wins  = month_cp[month_cp['is_win']]['net_pnl'] if not cp.empty else []

        year, month = map(int, month_key.split('-'))
        month_start = datetime(year, month, 1).strftime('%b %d')
        chart_data  = [{"date": month_start, "value": 0.0}]
        cum_pnl     = 0.0

        for _, r in grp_sorted.iterrows():
            if r['realized_pnl'] != 0:
                cum_pnl += r['net_realized_pnl']
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
            "avgGain":   f"${month_wins.mean():.2f}" if len(month_wins) else "N/A",
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
    total_pnl = df['net_realized_pnl'].sum()

    # Trade statistics are per closed position (net of every fill's fees)
    cp     = closed_positions(period)
    n_pos  = len(cp)
    won    = cp[cp['is_win']] if n_pos else cp
    lost   = cp[~cp['is_win']] if n_pos else cp
    wins, losses = len(won), len(lost)

    win_loss_split = [wins / n_pos, losses / n_pos] if n_pos else [0.0, 1.0]
    win_rate_str   = f"{int(wins / n_pos * 100)}%" if n_pos else "0%"

    won_pnl_sum      = float(won['net_pnl'].sum()) if wins else 0.0
    lost_pnl_sum     = float(lost['net_pnl'].sum()) if losses else 0.0
    avg_gain_usd     = won_pnl_sum / wins if wins else 0.0
    avg_loss_usd_abs = abs(lost_pnl_sum / losses) if losses else 0.0
    total_avg        = avg_gain_usd + avg_loss_usd_abs
    avg_gain_split_usd = ([avg_gain_usd / total_avg, avg_loss_usd_abs / total_avg]
                           if total_avg else [0.0, 1.0])

    # Avg Gain % = net P&L of closed positions / the capital they put in at entry
    entry_capital = float(cp['entry_cost'].sum()) if n_pos else 0.0
    avg_gain_pct  = (float(cp['net_pnl'].sum()) / entry_capital) if entry_capital else 0.0

    # Profit Factor = gross profit / |gross loss|
    pf_raw   = round(won_pnl_sum / abs(lost_pnl_sum), 2) if losses and lost_pnl_sum != 0 else None
    pf_str   = f"{pf_raw:.2f}" if pf_raw is not None else "∞"
    pf_split = ([pf_raw / (pf_raw + 1), 1.0 / (pf_raw + 1)]
                if pf_raw and pf_raw > 0 else [0.0, 1.0])
    sell_count = n_pos

    # Last-7-days bar chart (today as anchor, 7 days back)
    today         = now_et().normalize()
    df['_date']   = df['create_time'].dt.strftime('%Y-%m-%d')
    daily_pnl_map = df.groupby('_date')['net_realized_pnl'].sum().to_dict()

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
    daily_sum  = df_sorted.groupby('_date_only')['net_realized_pnl'].sum().reset_index()
    daily_sum['_date_str'] = pd.to_datetime(daily_sum['_date_only']).dt.strftime('%b %d, %Y')
    daily_sum['_cum']      = daily_sum['net_realized_pnl'].cumsum()

    if not daily_sum.empty:
        first_date_str = pd.to_datetime(
            daily_sum['_date_only'].iloc[0] - pd.Timedelta(days=1)
        ).strftime('%b %d, %Y')
        profit_chart = [{"date": first_date_str, "value": 0.0}] + [
            {"date": r['_date_str'], "value": round(r['_cum'], 2)}
            for _, r in daily_sum.iterrows()
        ]
    else:
        today_str    = now_et().strftime('%b %d, %Y')
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

    # Deep stats over positions that closed in this month
    cp = closed_positions('AT')
    month_cp = cp[cp['close_time'].dt.strftime('%B, %Y') == month_str] if not cp.empty else cp
    stats = deep_stats(month_cp)
    stats["r"] = r_stats(month_cp)

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
    """Deep performance analysis over closed positions: core metrics, R statistics, monthly bars,
    day-of-week distribution, deep stats, and a daily equity / drawdown curve.
    """
    period = request.args.get('period', '1M')

    df_all = load_df_with_pnl()
    if df_all.empty:
        return jsonify({"status": "empty"}), 200

    df = slice_by_period(df_all, period)
    cp = closed_positions(period)

    # ── Per-position outcomes ─────────────────────────────────────
    n_pos    = len(cp)
    won_df   = cp[cp['is_win']] if n_pos else cp
    lost_df  = cp[~cp['is_win']] if n_pos else cp
    wins, losses = len(won_df), len(lost_df)
    win_rate = wins / n_pos if n_pos else 0.0

    avg_win        = float(won_df['net_pnl'].mean()) if wins else 0.0
    avg_loss       = abs(float(lost_df['net_pnl'].mean())) if losses else 0.0
    gross_profit   = float(won_df['net_pnl'].sum()) if wins else 0.0
    gross_loss     = abs(float(lost_df['net_pnl'].sum())) if losses else 0.0
    profit_factor  = round(gross_profit / gross_loss, 2) if gross_loss > 0 else 999.0
    win_loss_ratio = round(avg_win / avg_loss, 2) if avg_loss > 0 else 0.0
    expectancy     = round(float(cp['net_pnl'].mean()), 2) if n_pos else 0.0
    total_pnl      = float(df['net_realized_pnl'].sum())

    # ── Streaks (positions in close order) ────────────────────────
    cur_win_streak = cur_loss_streak = max_win_streak = max_loss_streak = 0
    for is_win in (cp['is_win'] if n_pos else []):
        if is_win:
            cur_win_streak += 1; cur_loss_streak = 0
        else:
            cur_loss_streak += 1; cur_win_streak = 0
        max_win_streak  = max(max_win_streak, cur_win_streak)
        max_loss_streak = max(max_loss_streak, cur_loss_streak)
    current_streak_type  = 'W' if cur_win_streak > 0 else 'L'
    current_streak_count = cur_win_streak if cur_win_streak > 0 else cur_loss_streak

    # ── Monthly bar chart (realized P&L by month) ────────────────
    df['_month_key'] = df['create_time'].dt.strftime('%Y-%m')
    df['_month_lbl'] = df['create_time'].dt.strftime('%b %Y')
    monthly_grp = df.groupby(['_month_key', '_month_lbl'])['net_realized_pnl'].sum().reset_index()
    monthly_bars = [
        {"label": str(r['_month_lbl']), "value": round(float(r['net_realized_pnl']), 2),
         "isProfit": bool(r['net_realized_pnl'] >= 0)}
        for _, r in monthly_grp.sort_values('_month_key').iterrows()
    ]

    # ── Day-of-week distribution (by close day) ───────────────────
    dow_stats = []
    for i, lbl in enumerate(['Mon', 'Tue', 'Wed', 'Thu', 'Fri']):
        grp = cp[cp['close_time'].dt.dayofweek == i] if n_pos else cp
        day_pnl = float(grp['net_pnl'].sum()) if len(grp) else 0.0
        dow_stats.append({
            "label":    lbl,
            "trades":   int(len(grp)),
            "win_rate": round(float(grp['is_win'].sum()) / len(grp), 4) if len(grp) else 0.0,
            "pnl":      round(day_pnl, 2),
            "isProfit": bool(day_pnl >= 0),
        })

    # ── Risk ratios on the daily P&L series (scale-free, so no account size needed) ──
    daily = daily_pnl_series(df)
    if len(daily) >= 2 and daily.std() > 0:
        sharpe_ratio = round(float(daily.mean() / daily.std()) * (252 ** 0.5), 2)
        downside_dev = float(((daily.clip(upper=0)) ** 2).mean() ** 0.5)
        sortino_ratio = round(float(daily.mean()) / downside_dev * (252 ** 0.5), 2) if downside_dev > 0 else 0.0
    else:
        sharpe_ratio = sortino_ratio = 0.0

    # Kelly % = W − (1 − W) / (avg win / avg loss); negative means "don't trade this"
    if win_loss_ratio > 0 and 0 < win_rate < 1:
        kelly_pct = max(round((win_rate - (1 - win_rate) / win_loss_ratio) * 100, 1), 0.0)
    else:
        kelly_pct = 0.0

    # ── Equity / drawdown curve: cumulative realized P&L per day, peak starts at 0 ──
    equity_pts, max_drawdown = [], 0.0
    cum = peak = 0.0
    for day, pnl in daily.items():
        cum += float(pnl)
        peak = max(peak, cum)
        max_drawdown = min(max_drawdown, cum - peak)
        equity_pts.append({"date": day.strftime('%b %d'), "equity": round(cum, 2), "drawdown": round(cum - peak, 2)})
    if len(equity_pts) > 200:
        equity_pts = equity_pts[::len(equity_pts) // 200]

    return jsonify({
        "status": "success",
        "summary": {
            "total_pnl":           round(total_pnl, 2),
            "trade_count":         n_pos,
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
            "sharpe_ratio":        sharpe_ratio,
            "sortino_ratio":       sortino_ratio,
            "kelly_pct":           kelly_pct,
        },
        "r_stats":        r_stats(cp),
        "monthly_bars":   monthly_bars,
        "dow_stats":      dow_stats,
        "deep_stats":     deep_stats(cp),
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
    _notes_changed()
    return jsonify({"status": "success", "message": "Note saved"}), 200


@app.route('/api/upload_image/<trade_id>', methods=['POST'])
def upload_image(trade_id: str):
    """Upload a screenshot, save it locally, and append the filename to trade_notes.image_paths."""
    if 'image' not in request.files:
        return jsonify({"status": "error", "message": "No image field found"}), 400

    file      = request.files['image']
    ext       = os.path.splitext(file.filename)[1].lower() or '.jpg'
    if ext not in ALLOWED_IMAGE_EXTS:
        return jsonify({"status": "error", "message": f"Unsupported image type: {ext}"}), 400
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

    invalidate_cache()
    return jsonify({
        "status":   "success",
        "filename": filename,
        "url":      f"/api/images/{filename}",
    }), 200


@app.route('/api/delete_image/<trade_id>/<filename>', methods=['DELETE'])
def delete_image(trade_id: str, filename: str):
    """Delete a screenshot (physical file + database record). Only images attached to this trade."""
    conn = sqlite3.connect(DB_FILE)
    existing = conn.execute(
        'SELECT image_paths FROM trade_notes WHERE trade_id = ?', (trade_id,)
    ).fetchone()
    paths = json.loads(existing[0]) if existing else []
    if filename not in paths:
        conn.close()
        return jsonify({"status": "error", "message": "Image not found for this trade"}), 404

    conn.execute(
        'UPDATE trade_notes SET image_paths = ?, updated_at = ? WHERE trade_id = ?',
        (json.dumps([p for p in paths if p != filename]), datetime.now().isoformat(), trade_id)
    )
    conn.commit()
    conn.close()
    file_path = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(file_path):
        os.remove(file_path)
    invalidate_cache()
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
    _notes_changed()
    return jsonify({"status": "success"}), 200


# ======================== Journal AI (RAG) ========================

# ── Session store ────────────────────────────────────────────────────────────
_sessions: dict = {}          # session_id → {"history": [...], "ts": float}
_SESSION_TTL    = 3600        # 1 hour idle timeout
_SESSION_MAX    = 50          # oldest idle session is evicted beyond this


def _get_history(session_id: str) -> list:
    now = _time.time()
    # Purge expired sessions
    for k in [k for k, v in _sessions.items() if now - v["ts"] > _SESSION_TTL]:
        del _sessions[k]
    while len(_sessions) >= _SESSION_MAX and session_id not in _sessions:
        del _sessions[min(_sessions, key=lambda k: _sessions[k]["ts"])]
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

        if len(_detail_cache) >= DETAIL_CACHE_MAX and ticker not in _detail_cache:
            oldest = min(_detail_cache_time, key=_detail_cache_time.get)
            _detail_cache.pop(oldest, None)
            _detail_cache_time.pop(oldest, None)
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
            # Auto-detect the currently open position(s) of this ticker
            pos = load_positions()
            open_pids = set(
                pos[(pos['status'] == 'open') &
                    (pos['code'].str.replace('US.', '').str.upper() == ticker_clean)]['position_id']
            ) if not pos.empty else set()
            if not open_pids:
                return jsonify({'status': 'success', 'data': [], 'r_multiple': None}), 200
            target_df = df_pnl[df_pnl['position_id'].isin(open_pids)].copy()

        if target_df.empty:
            return jsonify({'status': 'success', 'data': [], 'r_multiple': None}), 200

        # Compute position-level stats
        pid_used    = target_df['position_id'].iloc[0]
        stop_price  = stop_map.get(pid_used)
        total_pnl   = float(target_df['realized_pnl'].sum())

        # ── Fetch fees for every order in this position ──────────────────────
        order_ids   = target_df['order_id'].astype(str).tolist()
        conn2       = sqlite3.connect(DB_FILE)
        placeholders = ','.join('?' * len(order_ids))
        fee_rows    = conn2.execute(
            f'SELECT order_id, fee, fee_details FROM trades WHERE order_id IN ({placeholders})',
            order_ids
        ).fetchall()
        conn2.close()
        fee_map     = {r[0]: (float(r[1]) if r[1] else 0.0) for r in fee_rows}

        # Identify the final closing order (last SELL/BUY_BACK by time)
        close_mask  = target_df['trd_side'].isin(['SELL', 'BUY_BACK'])
        entry_mask  = target_df['trd_side'].isin(['BUY', 'SELL_SHORT'])
        final_close_id = None
        if close_mask.any():
            final_close_id = str(
                target_df[close_mask].sort_values('create_time').iloc[-1]['order_id']
            )
        total_entry_fee = sum(
            fee_map.get(str(oid), 0.0)
            for oid in target_df[entry_mask]['order_id'].astype(str)
        )
        total_all_fees = sum(fee_map.get(str(oid), 0.0) for oid in order_ids)
        total_net_pnl  = round(total_pnl - total_all_fees, 2)

        # Weighted-average entry price from BUY/SELL_SHORT legs
        entry_legs = target_df[target_df['trd_side'].isin(['BUY', 'SELL_SHORT'])]
        entry_qty  = float(entry_legs['qty'].sum())
        entry_price = (
            float((entry_legs['price'] * entry_legs['qty']).sum()) / entry_qty
        ) if entry_qty > 0 else 0.0

        # R = net P&L / (|avg entry − initial stop| × shares entered), from the position engine
        summary = load_positions()
        match = summary[summary['position_id'] == pid_used] if not summary.empty else summary
        r_multiple   = match.iloc[0]['r_multiple'] if not match.empty else None
        initial_stop = None
        if not match.empty and not pd.isna(match.iloc[0]['initial_stop']):
            initial_stop = float(match.iloc[0]['initial_stop'])

        result = []
        for _, row in target_df.iterrows():
            dt      = pd.to_datetime(row['create_time'])
            pid     = row.get('position_id')
            oid_str = str(row['order_id'])
            gross   = round(float(row['realized_pnl']), 2)
            is_close = row['trd_side'] in ('SELL', 'BUY_BACK')

            # Net P&L per row: exit fee always deducted; final exit also carries all entry fees
            exit_fee = fee_map.get(oid_str, 0.0) if is_close else 0.0
            extra    = total_entry_fee if (is_close and oid_str == final_close_id) else 0.0
            net      = round(gross - exit_fee - extra, 2)

            result.append({
                'order_id':         oid_str,
                'position_id':      pid,
                'action':           row['trd_side'],
                'price':            round(float(row['price']), 4),
                'qty':              float(row['qty']),
                'realized_pnl':     gross,
                'net_realized_pnl': net,
                'fee':              round(exit_fee + extra, 4),
                'date':             dt.strftime('%Y-%m-%d'),
                'time':             dt.strftime('%H:%M'),
                'day':              dt.strftime('%d'),
                'month':            dt.strftime('%b').upper(),
                'stop_price':       stop_map.get(pid),
            })

        return jsonify({
            'status':         'success',
            'data':           result,
            'total_pnl':      round(total_pnl, 2),
            'total_net_pnl':  total_net_pnl,
            'entry_price':    round(entry_price, 4),
            'stop_price':     stop_price,
            'initial_stop':   initial_stop,
            'r_multiple':     r_multiple,
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
    assign_position_ids()
    _write_position_pnl()
    # Default to loopback: remote access goes through `tailscale serve`, never a public port.
    # waitress (pure-Python WSGI server) streams the Journal AI's SSE responses unbuffered.
    from waitress import serve
    serve(app, host=os.environ.get('VENCH_HOST', '127.0.0.1'),
          port=int(os.environ.get('VENCH_PORT', '5001')), threads=8)