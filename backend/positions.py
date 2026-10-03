"""Position engine: one definition of a "position" shared by every route.

A position (cycle) for a ticker starts when its running quantity leaves zero and ends when it
returns to zero — long or short, with any number of scale-ins and partial exits in between.
Its id is the order_id of its first fill, so ids never shift when older fills arrive late.

`resets` is a set of order_ids after which the broker reports the position flat even though the
order history leaves a small residue (e.g. a fractional share moved outside of orders). The
running quantity is forced to zero after such an order, closing the position.
"""

import pandas as pd

EPS = 1e-3
LONG_SIDES = ('BUY', 'BUY_BACK')      # add shares
SHORT_SIDES = ('SELL', 'SELL_SHORT')  # remove shares


def multiplier(code: str) -> float:
    """Options (ticker containing digits) trade in contracts of 100; stocks are 1."""
    clean = code.split('.')[-1]
    return 100.0 if any(c.isdigit() for c in clean) else 1.0


def signed_qty(side: str, qty: float) -> float:
    return qty if side in LONG_SIDES else -qty


def assign_cycles(df: pd.DataFrame, resets=frozenset()) -> pd.Series:
    """position_id for every fill. df needs order_id, code, trd_side, qty, create_time."""
    ids = pd.Series(index=df.index, dtype=object)
    running: dict[str, float] = {}
    current: dict[str, str] = {}
    for idx, row in df.sort_values(['create_time', 'order_id']).iterrows():
        code = row['code']
        prev = running.get(code, 0.0)
        new = prev + signed_qty(row['trd_side'], float(row['qty']))
        if abs(new) < EPS or str(row['order_id']) in resets:
            new = 0.0
        if abs(prev) < EPS:
            current[code] = str(row['order_id'])
        running[code] = new
        ids[idx] = current[code]
    return ids


def realized_pnl(df: pd.DataFrame, resets=frozenset()) -> pd.DataFrame:
    """Per-fill realized P&L on a moving-average cost basis (gross, before fees).
    Handles longs and shorts, including BUY_BACK / SELL_SHORT, and options multipliers.
    """
    df = df.sort_values(['create_time', 'order_id']).copy()
    book: dict[str, dict] = {}
    pnl = []
    for _, row in df.iterrows():
        code, price, qty = row['code'], float(row['price']), float(row['qty'])
        mult = multiplier(code)
        pos = book.setdefault(code, {'qty': 0.0, 'avg': 0.0})
        delta = signed_qty(row['trd_side'], qty)
        realized = 0.0
        if pos['qty'] == 0 or (pos['qty'] > 0) == (delta > 0):
            new_abs = abs(pos['qty']) + qty
            pos['avg'] = (abs(pos['qty']) * pos['avg'] + qty * price) / new_abs
            pos['qty'] += delta
        else:
            closing = min(qty, abs(pos['qty']))
            direction = 1 if pos['qty'] > 0 else -1
            realized = (price - pos['avg']) * closing * mult * direction
            remaining = qty - closing
            pos['qty'] += delta
            if abs(pos['qty']) < EPS:
                pos['qty'], pos['avg'] = 0.0, 0.0
            elif remaining > EPS:
                pos['avg'] = price  # flipped through zero: the excess opens a new position at this price
        if str(row['order_id']) in resets:
            pos['qty'], pos['avg'] = 0.0, 0.0
        pnl.append(realized)
    df['realized_pnl'] = pnl
    return df


def summarize(df: pd.DataFrame, resets=frozenset()) -> pd.DataFrame:
    """One row per position. df must already carry position_id, realized_pnl and fee."""
    rows = []
    for pid, grp in df.sort_values(['create_time', 'order_id']).groupby('position_id', sort=False):
        code = grp['code'].iloc[0]
        mult = multiplier(code)
        is_long = grp['trd_side'].iloc[0] in LONG_SIDES
        entry_sides = LONG_SIDES if is_long else SHORT_SIDES
        entries = grp[grp['trd_side'].isin(entry_sides)]
        exits = grp[~grp['trd_side'].isin(entry_sides)]
        net_qty = float(sum(signed_qty(s, q) for s, q in zip(grp['trd_side'], grp['qty'])))
        closed = abs(net_qty) < EPS or str(grp['order_id'].iloc[-1]) in resets
        entry_qty = float(entries['qty'].sum())
        exit_qty = float(exits['qty'].sum())
        gross = float(grp['realized_pnl'].sum())
        fees = float(grp['fee'].sum())
        rows.append({
            'position_id': pid,
            'code': code,
            'direction': 'LONG' if is_long else 'SHORT',
            'status': 'closed' if closed else 'open',
            'entry_qty': entry_qty,
            'avg_entry': float((entries['price'] * entries['qty']).sum()) / entry_qty if entry_qty else 0.0,
            'exit_qty': exit_qty,
            'avg_exit': float((exits['price'] * exits['qty']).sum()) / exit_qty if exit_qty else 0.0,
            'entry_cost': float((entries['price'] * entries['qty']).sum()) * mult,
            'multiplier': mult,
            'gross_pnl': gross,
            'fees': fees,
            'net_pnl': gross - fees,
            'open_time': grp['create_time'].min(),
            'close_time': grp['create_time'].max() if closed else pd.NaT,
            'order_ids': list(grp['order_id'].astype(str)),
            'legs': len(grp),
        })
    return pd.DataFrame(rows)


def r_multiple(net_pnl: float, avg_entry: float, initial_stop, entry_qty: float, mult: float):
    """Net P&L in units of the risk taken at entry: |entry − initial stop| × shares × multiplier."""
    if initial_stop is None or pd.isna(initial_stop) or not avg_entry:
        return None
    risk = abs(avg_entry - float(initial_stop)) * entry_qty * mult
    return round(net_pnl / risk, 2) if risk > 0.001 else None
