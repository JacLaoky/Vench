"""IBKR Flex Web Service: fetch an Activity Flex statement and turn it into rows for the journal.

The query (built in Client Portal → Performance & Reports → Flex Queries) must be XML with
"Breakout by Day" on and these sections: Account Information, Trades (Execution), Open Positions
(Summary), Net Asset Value (NAV) in Base, Change in NAV, Statement of Funds, Cash Transactions,
Transfers, Corporate Actions. With the daily breakout IBKR returns one statement per account per
day, so every row carries its own accountId and date.

Times in the statement are US/Eastern wall-clock (the same as Moomoo's), dates are yyyyMMdd and a
date-time is "yyyyMMdd;HHmmss". Amounts in the "InBase" sections and ChangeInNAV are already in the
base currency (USD); cash transactions are in their own currency with fxRateToBase.
"""

import io
import time
import xml.etree.ElementTree as ET
from collections import defaultdict

import requests

BASE_URL = "https://ndcdyn.interactivebrokers.com/AccountManagement/FlexWebService"
_HEADERS = {"User-Agent": "Vench/1.0"}   # the Flex service rejects requests without a User-Agent
_IN_PROGRESS = "1019"                    # "Statement generation in progress. Please try again shortly."
# "Statement could not be generated at this time" / "Too many requests": IBKR is busy, try later
_RETRY_LATER = {"1001", "1018"}


class FlexError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(f"Flex error {code}: {message}")
        self.code = code


def fetch_statement(token: str, query_id: str, from_date: str | None = None, to_date: str | None = None,
                    wait_secs: float = 300, poll_secs: float = 5) -> bytes:
    """Request a statement and poll until it is ready. The token is sent to IBKR only.

    from_date/to_date (yyyyMMdd) override the query's period. Use them for routine fetches: with
    the daily breakout a full year for two accounts is cut short by IBKR (the second account's
    days stopped at 2026-09-01 without any error)."""
    params = {"t": token, "q": query_id, "v": 3}
    if from_date and to_date:
        params.update(fd=from_date, td=to_date)
    for attempt in range(5):
        resp = requests.get(f"{BASE_URL}/SendRequest", params=params, headers=_HEADERS, timeout=30)
        resp.raise_for_status()
        root = ET.fromstring(resp.content)
        code = root.findtext("ErrorCode") or "?"
        if root.findtext("Status") == "Success" or code not in _RETRY_LATER or attempt == 4:
            break
        time.sleep(30)
    if root.findtext("Status") != "Success":
        raise FlexError(code, root.findtext("ErrorMessage") or "request refused")
    reference = root.findtext("ReferenceCode")

    deadline = time.time() + wait_secs
    while True:
        time.sleep(poll_secs)
        resp = requests.get(f"{BASE_URL}/GetStatement", params={"t": token, "q": reference, "v": 3},
                            headers=_HEADERS, timeout=120)
        resp.raise_for_status()
        if resp.content.lstrip().startswith(b"<FlexQueryResponse"):
            return resp.content
        status = ET.fromstring(resp.content)
        code = status.findtext("ErrorCode") or "?"
        if code not in {_IN_PROGRESS, *_RETRY_LATER} or time.time() > deadline:
            raise FlexError(code, status.findtext("ErrorMessage") or "statement not available")


def _f(value, default: float = 0.0) -> float:
    try:
        return float(value) if value not in (None, "") else default
    except ValueError:
        return default


def _day(value: str) -> str:
    """'20261019' or '20261019;103000' → '2026-10-19'."""
    d = (value or "")[:8]
    return f"{d[:4]}-{d[4:6]}-{d[6:8]}" if len(d) == 8 else ""


def _when(value: str) -> str:
    """'20261019;103000' → '2026-10-19 10:30:00' (US/Eastern wall-clock, like Moomoo's times)."""
    day = _day(value)
    t = value.split(";", 1)[1] if ";" in (value or "") else "000000"
    return f"{day} {t[:2]}:{t[2:4]}:{t[4:6]}" if day else ""


def _code(symbol: str) -> str:
    return "US." + symbol.strip().replace(" ", ".")


def _side(buy_sell: str, open_close: str) -> str:
    """Moomoo's side names, which the position engine and trade cards use: a short is opened with
    SELL_SHORT and covered with BUY_BACK."""
    oc = (open_close or "").split(";")[0]
    if buy_sell.startswith("SELL"):
        return "SELL_SHORT" if oc == "O" else "SELL"
    return "BUY_BACK" if oc == "C" else "BUY"


_FLOW_KINDS = {
    "Deposits/Withdrawals": None,                 # deposit or withdrawal by sign
    "Dividends": "dividend",
    "Payment In Lieu Of Dividends": "dividend",
    "Withholding Tax": "tax",
    "871(m) Withholding": "tax",
    "Broker Interest Received": "interest",
    "Broker Interest Paid": "interest",
    "Bond Interest Received": "interest",
    "Other Fees": "fee",
    "Commission Adjustments": "fee",
}


def parse_statement(xml: bytes) -> dict:
    """Rows for the journal from a Flex statement:

    trades     one row per order (executions of the same IB order merged: summed quantity,
               volume-weighted price, summed commission, time of the last execution); stocks only
    nav        one row per account and day: nav, cash, stock, flow (deposits/withdrawals and asset
               transfers, the money that is not performance) and IBKR's own daily TWR in %
    cash_flows cash transactions (deposits, withdrawals, dividends, tax, interest, fees), each
               with IBKR's transactionID and the amount in USD
    positions  open positions of each account on its latest statement day (position_days)
    accounts   account ids seen in the statement
    """
    execs = defaultdict(list)
    nav: dict[tuple, dict] = {}
    internal: dict[tuple, float] = {}
    flows: dict[str, dict] = {}
    positions: list[dict] = []
    statement_day: dict[str, str] = {}
    accounts: set[str] = set()

    for _, el in ET.iterparse(io.BytesIO(xml), events=("end",)):
        tag, a = el.tag, el.attrib
        account = a.get("accountId", "")
        if account:
            accounts.add(account)

        if tag == "Trade" and a.get("assetCategory") == "STK" and a.get("levelOfDetail", "EXECUTION") == "EXECUTION":
            execs[(account, a.get("ibOrderID"))].append(dict(a))

        elif tag == "EquitySummaryByReportDateInBase":
            statement_day[account] = max(statement_day.get(account, ""), _day(a.get("reportDate")))
            row = nav.setdefault((account, _day(a.get("reportDate"))), {})
            row.update(nav=_f(a.get("total")), cash=_f(a.get("cash")), stock=_f(a.get("stock")))

        elif tag == "ChangeInNAV" and a.get("fromDate") and a.get("fromDate") == a.get("toDate"):
            row = nav.setdefault((account, _day(a.get("fromDate"))), {})
            if _f(a.get("internalCashTransfers")):
                internal[(account, _day(a.get("fromDate")))] = _f(a.get("internalCashTransfers"))
            row.update(
                flow=_f(a.get("depositsWithdrawals")) + _f(a.get("internalCashTransfers")) + _f(a.get("assetTransfers")),
                broker_twr=_f(a.get("twr")),
                start_value=_f(a.get("startingValue")),
                end_value=_f(a.get("endingValue")),
            )

        elif tag == "CashTransaction" and a.get("transactionID"):
            amount = _f(a.get("amount")) * _f(a.get("fxRateToBase"), 1.0)
            kind = _FLOW_KINDS.get(a.get("type", ""), "other")
            if kind is None:
                kind = "deposit" if amount >= 0 else "withdrawal"
            flows[a["transactionID"]] = {
                "account": account,
                "date": _day(a.get("reportDate") or a.get("dateTime")),
                "amount_usd": round(amount, 2),
                "amount": _f(a.get("amount")),
                "currency": a.get("currency", "USD"),
                "kind": kind,
                "description": a.get("description", ""),
                "external_id": "IB-" + a["transactionID"],
            }

        elif tag == "OpenPosition" and a.get("assetCategory", "STK") == "STK":
            qty = _f(a.get("position"))
            positions.append({
                "account": account,
                "report_date": _day(a.get("reportDate")),
                "code": _code(a.get("symbol", "")),
                "qty": qty,
                "cost_price": _f(a.get("costBasisPrice")),
                "cost_money": _f(a.get("costBasisMoney")),
                "mark_price": _f(a.get("markPrice")),
                "value": _f(a.get("positionValue")),
                "unrealized": _f(a.get("fifoPnlUnrealized")),
                "side": "SHORT" if qty < 0 else "LONG",
            })
        if tag in ("FlexStatement",):
            el.clear()

    trades = []
    for (account, order_id), legs in execs.items():
        qty = sum(abs(_f(l.get("quantity"))) for l in legs)
        if not qty or not order_id:
            continue
        legs.sort(key=lambda l: l.get("dateTime", ""))
        first = legs[0]
        commission = -sum(_f(l.get("ibCommission")) for l in legs)
        trades.append({
            "order_id": f"IB-{order_id}",
            "account": account,
            "code": _code(first.get("symbol", "")),
            "trd_side": _side(first.get("buySell", ""), first.get("openCloseIndicator", "")),
            "price": sum(abs(_f(l.get("quantity"))) * _f(l.get("tradePrice")) for l in legs) / qty,
            "qty": qty,
            "create_time": _when(legs[-1].get("dateTime", "")),
            "fee": round(commission, 4),
            "fee_details": [["IBKR Commission", round(commission, 4)]],
        })

    # A cancelled withdrawal shows up as the withdrawal, a "CANCELLATION" credit and the re-sent
    # withdrawal: drop each cancellation with one withdrawal of the same day and amount
    cash_flows = list(flows.values())
    dropped = []
    for c in [x for x in cash_flows if "CANCELLATION" in x["description"].upper() and x["amount_usd"] > 0]:
        twin = next((x for x in cash_flows if x["kind"] == "withdrawal" and x["account"] == c["account"]
                     and x["date"] == c["date"] and abs(x["amount_usd"] + c["amount_usd"]) < 0.01), None)
        if twin is not None:
            cash_flows.remove(c)
            cash_flows.remove(twin)
            dropped += [c["external_id"], twin["external_id"]]
    # Cash moved between IBKR accounts has no cash transaction line: ChangeInNAV's internal cash
    # transfers become a withdrawal and a deposit, which the transfer matching then pairs
    for (account, day), amount in internal.items():
        cash_flows.append({
            "account": account, "date": day, "amount_usd": round(amount, 2), "amount": round(amount, 2),
            "currency": "USD", "kind": "deposit" if amount > 0 else "withdrawal",
            "description": "Internal transfer between IBKR accounts", "external_id": f"IB-ICT-{account}-{day}",
        })

    nav_rows = [
        {"account": acc, "date": day, **{k: row.get(k) for k in
         ("nav", "cash", "stock", "flow", "broker_twr", "start_value", "end_value")}}
        for (acc, day), row in sorted(nav.items()) if day and "nav" in row
    ]
    return {
        "trades": trades,
        "nav": nav_rows,
        "cash_flows": cash_flows,
        "dropped_ids": dropped,
        # holdings on each account's latest statement day (none listed = the account holds nothing)
        "positions": [p for p in positions if p["report_date"] == statement_day.get(p["account"])],
        "position_days": statement_day,
        "accounts": sorted(accounts),
    }
