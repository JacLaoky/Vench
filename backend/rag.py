"""
rag.py — Journal AI Assistant for Vench
RAG pipeline: SQLite notes → ChromaDB (multilingual embeddings) → DeepSeek generation
"""

import os
import sqlite3
import threading
from openai import OpenAI
import chromadb
from chromadb.utils import embedding_functions

DB_FILE    = 'local.db'
CHROMA_DIR = './chroma_db'

# Multilingual sentence-transformers model — handles Chinese + English notes
_ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="paraphrase-multilingual-MiniLM-L12-v2"
)

_chroma_client = chromadb.PersistentClient(path=CHROMA_DIR)
_collection    = _chroma_client.get_or_create_collection(
    name="vench_journal",
    embedding_function=_ef,
    metadata={"hnsw:space": "cosine"},
)

_index_lock  = threading.Lock()
_index_built = False


# ─────────────────────────── index building ────────────────────────────

def _load_documents() -> tuple[list[str], list[dict], list[str]]:
    """Pull notes + trades from SQLite and convert to text chunks."""
    conn = sqlite3.connect(DB_FILE)
    docs, metas, ids = [], [], []

    # 1. Daily notes
    rows = conn.execute(
        "SELECT date, note FROM daily_notes WHERE note != '' AND note IS NOT NULL"
    ).fetchall()
    for date, note in rows:
        if note.strip():
            docs.append(f"日期：{date}\n{note.strip()}")
            metas.append({"type": "daily_note", "date": date})
            ids.append(f"daily_{date}")

    # 2. Trade notes (joined with trade info for context)
    rows = conn.execute("""
        SELECT tn.trade_id, tn.note, t.code, t.trd_side, t.create_time
        FROM trade_notes tn
        LEFT JOIN trades t ON t.order_id = tn.trade_id
        WHERE tn.note != '' AND tn.note IS NOT NULL
    """).fetchall()
    for trade_id, note, code, side, create_time in rows:
        if note.strip():
            header = f"交易笔记 [{code} {side} {create_time}]" if code else "交易笔记"
            docs.append(f"{header}\n{note.strip()}")
            metas.append({
                "type":     "trade_note",
                "trade_id": str(trade_id),
                "ticker":   str(code or ""),
                "date":     str(create_time or ""),
            })
            ids.append(f"tradenote_{trade_id}")

    # 3. Global stats summary — one document covering all tickers (for aggregation questions)
    stat_rows = conn.execute("""
        SELECT
            code,
            COUNT(*) as total_pos,
            SUM(CASE WHEN pnl >= 0 THEN 1 ELSE 0 END) as wins,
            SUM(CASE WHEN pnl < 0  THEN 1 ELSE 0 END) as losses,
            ROUND(SUM(pnl), 2) as total_pnl,
            ROUND(MAX(pnl), 2) as best_trade,
            ROUND(MIN(pnl), 2) as worst_trade
        FROM (
            SELECT
                code,
                SUM(CASE WHEN trd_side IN ('SELL','SELL_SHORT') THEN price*qty ELSE 0 END)
                - SUM(CASE WHEN trd_side IN ('BUY','BUY_BACK')   THEN price*qty ELSE 0 END) AS pnl
            FROM trades
            WHERE position_id IS NOT NULL
            GROUP BY position_id
            HAVING SUM(CASE WHEN trd_side IN ('SELL','SELL_SHORT') THEN qty ELSE 0 END) > 0
               AND SUM(CASE WHEN trd_side IN ('BUY','BUY_BACK')   THEN qty ELSE 0 END) > 0
        )
        GROUP BY code
        ORDER BY total_pnl DESC
    """).fetchall()

    if stat_rows:
        lines = ["交易统计汇总（按标的）："]
        for code, total, wins, losses, total_pnl, best, worst in stat_rows:
            win_rate = round(wins / total * 100) if total else 0
            lines.append(
                f"  {code}: {total}笔已平仓, 盈利{wins}次/亏损{losses}次, "
                f"胜率{win_rate}%, 总盈亏${total_pnl:.2f}, "
                f"最佳${best:.2f}, 最差${worst:.2f}"
            )
        summary_text = "\n".join(lines)
        docs.append(summary_text)
        metas.append({"type": "stats_summary", "date": ""})
        ids.append("stats_summary_all")

    # 4. Position summaries with computed P&L
    pos_rows = conn.execute("""
        SELECT
            position_id, code,
            MIN(create_time) as open_time,
            MAX(create_time) as close_time,
            SUM(CASE WHEN trd_side IN ('SELL','SELL_SHORT') THEN price * qty ELSE 0 END) as sell_val,
            SUM(CASE WHEN trd_side IN ('BUY','BUY_BACK')   THEN price * qty ELSE 0 END) as buy_val,
            SUM(CASE WHEN trd_side IN ('SELL','SELL_SHORT') THEN qty ELSE 0 END) as sell_qty,
            SUM(CASE WHEN trd_side IN ('BUY','BUY_BACK')   THEN qty ELSE 0 END) as buy_qty
        FROM trades
        WHERE position_id IS NOT NULL
        GROUP BY position_id
        HAVING sell_qty > 0 AND buy_qty > 0
        ORDER BY MAX(create_time) DESC
        LIMIT 300
    """).fetchall()
    for pos_id, code, open_time, close_time, sell_val, buy_val, sell_qty, buy_qty in pos_rows:
        pnl = (sell_val or 0) - (buy_val or 0)
        result = '盈利' if pnl >= 0 else '亏损'
        text = (
            f"已平仓交易 [{code}] 开仓:{open_time} 平仓:{close_time} "
            f"盈亏:{result} ${abs(pnl):.2f} (position_id={pos_id})"
        )
        docs.append(text)
        metas.append({"type": "position", "ticker": str(code or ""), "date": str(close_time or "")})
        ids.append(f"pos_{pos_id}")

    # 4. Individual trade records (most recent 500)
    rows = conn.execute("""
        SELECT order_id, code, trd_side, price, qty, create_time, position_id
        FROM trades
        ORDER BY create_time DESC
        LIMIT 500
    """).fetchall()
    for order_id, code, side, price, qty, create_time, position_id in rows:
        text = (
            f"交易记录：{create_time} {side} {code} "
            f"{qty}股 @{price:.2f} (position: {position_id or '—'})"
        )
        docs.append(text)
        metas.append({
            "type":   "trade",
            "ticker": str(code or ""),
            "date":   str(create_time[:10] if create_time else ""),
        })
        ids.append(f"trade_{order_id}")

    conn.close()
    return docs, metas, ids


def build_index(force: bool = False) -> int:
    """Build (or rebuild) the ChromaDB vector index. Thread-safe."""
    global _index_built
    with _index_lock:
        if _index_built and not force:
            return _collection.count()

        docs, metas, ids = _load_documents()
        if not docs:
            _index_built = True
            return 0

        # Upsert in batches of 100
        batch = 100
        for i in range(0, len(docs), batch):
            _collection.upsert(
                documents=docs[i:i+batch],
                metadatas=metas[i:i+batch],
                ids=ids[i:i+batch],
            )

        _index_built = True
        return _collection.count()


# ─────────────────────────── query / answer ────────────────────────────

def ask(question: str, n_results: int = 6) -> dict:
    """
    Retrieve relevant chunks from ChromaDB and generate an answer with Claude.
    Returns {"answer": str, "sources": list[dict]}
    """
    # Lazy-build index on first query
    if not _index_built:
        build_index()

    if _collection.count() == 0:
        return {
            "answer": "还没有任何交易笔记或日记，先去 Journal 页面写点内容吧！",
            "sources": [],
        }

    # Retrieve
    results = _collection.query(query_texts=[question], n_results=n_results)
    chunks   = results["documents"][0]
    sources  = results["metadatas"][0]

    if not chunks:
        return {
            "answer": "没有找到相关的交易记录或笔记。",
            "sources": [],
        }

    context = "\n\n".join(f"[{i+1}] {c}" for i, c in enumerate(chunks))

    # Generate
    client   = OpenAI(api_key=os.getenv("DEEPSEEK_API_KEY"), base_url="https://api.deepseek.com")
    response = client.chat.completions.create(
        model="deepseek-v4-pro",
        messages=[
            {
                "role": "system",
                "content": (
                    "你是用户的个人交易助手，帮助他回顾和分析自己的交易日志。"
                    "只根据提供的内容回答，如果信息不足请直接说明，不要编造。"
                    "回答简洁，用中文。"
                ),
            },
            {
                "role": "user",
                "content": f"以下是从我的交易日志中检索到的相关内容：\n\n{context}\n\n我的问题：{question}",
            },
        ],
        stream=False,
        reasoning_effort="high",
        extra_body={"thinking": {"type": "enabled"}}
    )

    return {
        "answer":  response.choices[0].message.content,
        "sources": sources,
    }


# ─────────────────────────── background init ───────────────────────────

def init_async():
    """Start index building in background thread so Flask startup isn't blocked."""
    t = threading.Thread(target=build_index, daemon=True)
    t.start()
