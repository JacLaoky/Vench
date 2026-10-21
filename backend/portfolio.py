"""Account value over time: consolidated net asset value, money in and out, and time-weighted return.

Money moved into or out of an account (deposits, withdrawals — tuition paid from the account, say)
changes its value but is not performance. The time-weighted return (TWR) takes it out: each day's
return is

    r_t = (V_t − V_{t−1} − F_t) / (V_{t−1} + F_t)

with F_t the day's external flows, assumed to arrive at the start of the day (IBKR's own daily TWR
uses the same convention, which makes it a check on this one). Chaining the daily returns gives the
growth of $1 that stayed invested the whole time.

A transfer between the user's own accounts (a Moomoo withdrawal that arrives as an IBKR deposit) is
not external for the total: both legs are left out of the total's flows, and while the money is in
transit it is added back to the total so the curve does not dip. A shortfall between the two legs
(wire and FX costs) stays in the total as a loss.
"""

from dataclasses import dataclass

import pandas as pd

TRANSFER_WINDOW_DAYS = 10    # a transfer's deposit arrives within this many days of the withdrawal
TRANSFER_TOLERANCE = 0.03    # and differs from it by at most 3% (FX conversion, wire fees)


@dataclass
class Flow:
    id: int
    account: str
    date: pd.Timestamp
    amount: float
    kind: str
    label: str
    pair_id: int | None


def pair_transfers(flows: list[Flow]) -> dict[int, int]:
    """Match deposits into one account with withdrawals from another within TRANSFER_WINDOW_DAYS
    before it (or up to 2 days after) and about the same amount — one withdrawal, or two or three
    from the same account that add up (money is often sent in parts: $1,142.19 + $7,500 arrived as
    one $8,642 deposit). Flows already paired keep their pair; pair_id −1 means the user said this
    flow is not a transfer. Returns {flow id: partner id} for new pairs: every withdrawal points to
    its deposit, the deposit to the first withdrawal."""
    from itertools import combinations

    taken = {f.id for f in flows if f.pair_id is not None}
    out: dict[int, int] = {}
    withdrawals = [f for f in flows if f.kind == 'withdrawal' and f.amount < 0 and f.id not in taken]

    def close_enough(total: float, target: float) -> bool:
        return abs(total - target) <= TRANSFER_TOLERANCE * target

    for d in sorted((f for f in flows if f.kind == 'deposit' and f.amount > 0 and f.id not in taken), key=lambda f: f.date):
        pool = [w for w in withdrawals if w.id not in out and w.account != d.account
                and -2 <= (d.date - w.date).days <= TRANSFER_WINDOW_DAYS]
        singles = [w for w in pool if close_enough(abs(w.amount), d.amount)]
        group = [min(singles, key=lambda w: abs((d.date - w.date).days))] if singles else None
        for size in (2, 3):
            if group:
                break
            for account in {w.account for w in pool}:
                same = [w for w in pool if w.account == account]
                found = next((list(c) for c in combinations(same, size)
                              if close_enough(sum(abs(w.amount) for w in c), d.amount)), None)
                if found:
                    group = found
                    break
        if group:
            out[d.id] = group[0].id
            for w in group:
                out[w.id] = d.id
    return out


def _next_index(index: pd.DatetimeIndex, day: pd.Timestamp):
    """The first date in index on or after day (a weekend flow counts on the next trading day)."""
    pos = index.searchsorted(day)
    return index[pos] if pos < len(index) else None


def build_series(nav: pd.DataFrame, flows: list[Flow], accounts: list[str] | None = None) -> pd.DataFrame:
    """Daily frame for the chosen accounts (all when None): value per account, total value (with
    money in transit between them), external flow, daily return, TWR index, drawdown, cumulative
    net contributions and cumulative P&L. nav columns: account, date, nav, flow."""
    nav = nav[nav['nav'].notna()].copy()
    if accounts is not None:
        nav = nav[nav['account'].isin(accounts)]
    nav = nav[nav['nav'] > 0]   # days before an account was funded say nothing
    if nav.empty:
        return pd.DataFrame()
    nav['date'] = pd.to_datetime(nav['date'])
    chosen = sorted(nav['account'].unique())
    index = pd.DatetimeIndex(sorted(nav['date'].unique()))

    values = nav.pivot_table(index='date', columns='account', values='nav', aggfunc='last').reindex(index)
    first_day = {a: nav.loc[nav['account'] == a, 'date'].min() for a in chosen}
    for a in chosen:
        before = values.index < first_day[a]
        values[a] = values[a].ffill()
        values.loc[before, a] = 0.0
    values = values.fillna(0.0)

    # External flows per day: each account's own flows, minus both legs of transfers between the
    # chosen accounts; a weekend flow counts on the next day with a value
    ext = pd.Series(0.0, index=index)
    acct_flow = pd.DataFrame(0.0, index=index, columns=chosen)
    by_id = {f.id: f for f in flows}
    transit = pd.Series(0.0, index=index)
    for f in flows:
        if f.account not in chosen or f.kind not in ('deposit', 'withdrawal'):
            continue
        day = _next_index(index, f.date)
        if day is None:
            continue
        acct_flow.loc[day, f.account] += f.amount
        partner = by_id.get(f.pair_id) if f.pair_id and f.pair_id > 0 else None
        if partner is not None and partner.account in chosen:
            if f.kind == 'withdrawal':
                arrive = _next_index(index, partner.date)
                in_transit = (index >= day) & ((index < arrive) if arrive is not None else True)
                transit[in_transit] += abs(f.amount)
            continue
        ext[day] += f.amount

    total = values.sum(axis=1) + transit
    prev = total.shift(1).fillna(0.0)
    base = prev + ext
    ret = ((total - prev - ext) / base).where(base > 0, 0.0)
    ret.iloc[0] = 0.0
    twr = (1 + ret).cumprod()

    frame = values.copy()
    frame.columns = [f'value:{a}' for a in chosen]
    for a in chosen:
        frame[f'flow:{a}'] = acct_flow[a]
    frame['transit'] = transit
    frame['total'] = total
    frame['flow'] = ext
    frame['return'] = ret
    frame['twr'] = twr
    frame['drawdown'] = twr / twr.cummax() - 1
    # Net contributions: the first day's value counts as money put in, then every external flow
    frame['contributed'] = total.iloc[0] + ext.cumsum() - ext.iloc[0]
    frame['pnl'] = total - frame['contributed']
    return frame


def window(frame: pd.DataFrame, start: pd.Timestamp | None) -> pd.DataFrame:
    """The frame from start on, with TWR, drawdown, contributions and P&L restarted there."""
    if frame.empty or start is None or start <= frame.index[0]:
        return frame
    prior = frame[frame.index < start]
    part = frame[frame.index >= start].copy()
    if part.empty:
        return part
    opening = prior['total'].iloc[-1] if len(prior) else part['total'].iloc[0]
    part['twr'] = (1 + part['return']).cumprod()
    part['drawdown'] = part['twr'] / part['twr'].cummax() - 1
    part['contributed'] = opening + part['flow'].cumsum()
    part['pnl'] = part['total'] - part['contributed']
    part.attrs['opening'] = float(opening)
    return part


def period_return(frame: pd.DataFrame, since: pd.Timestamp) -> float | None:
    """TWR from the close before `since` to the latest day (since inception when `since` is earlier)."""
    part = frame[frame.index >= since]
    return None if part.empty else float((1 + part['return']).prod() - 1)


def monthly_returns(frame: pd.DataFrame) -> list[dict]:
    """Per calendar month: TWR, external flows, P&L (change in value less flows) and closing value."""
    out, prev_end = [], None
    for month, part in frame.groupby(frame.index.to_period('M')):
        start_value = prev_end if prev_end is not None else float(part['total'].iloc[0] - part['flow'].iloc[0])
        end_value = float(part['total'].iloc[-1])
        out.append({
            'month': str(month),
            'return_pct': round(float((1 + part['return']).prod() - 1) * 100, 2),
            'flow': round(float(part['flow'].sum()), 2),
            'pnl': round(end_value - start_value - float(part['flow'].sum()), 2),
            'end_value': round(end_value, 2),
        })
        prev_end = end_value
    return out


def breakdown(part: pd.DataFrame, flows: list[Flow], accounts: list[str]) -> dict:
    """Opening value + deposits − withdrawals (by label) + P&L = closing value, over a window."""
    if part.empty:
        return {}
    start, end = part.index[0], part.index[-1]
    opening = part.attrs.get('opening', float(part['total'].iloc[0] - part['flow'].iloc[0]))
    closing = float(part['total'].iloc[-1])
    deposits = float(part['flow'].clip(lower=0).sum())
    withdrawals = float(part['flow'].clip(upper=0).sum())
    labels: dict[str, float] = {}
    for f in flows:
        if (f.kind == 'withdrawal' and f.account in accounts and start <= f.date <= end
                and not (f.pair_id and f.pair_id > 0)):
            key = f.label or 'Unlabelled'
            labels[key] = labels.get(key, 0.0) + f.amount
    return {
        'opening': round(opening, 2),
        'deposits': round(deposits, 2),
        'withdrawals': round(withdrawals, 2),
        'withdrawals_by_label': {k: round(v, 2) for k, v in sorted(labels.items(), key=lambda kv: kv[1])},
        'pnl': round(closing - opening - deposits - withdrawals, 2),
        'closing': round(closing, 2),
    }
