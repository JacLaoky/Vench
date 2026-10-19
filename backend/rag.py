"""
rag.py — Journal AI Assistant for Vench
Architecture: DeepSeek Function Calling
  - run_sql:      query SQLite directly for any numeric/stats question
  - search_notes: hybrid search (BM25 + vectors, fused with RRF) over diary/trade notes
"""

import os
import re
import gc
import json
import math
import time
import ctypes
import hashlib
import sqlite3
import threading
from collections import Counter, defaultdict
from openai import OpenAI

DB_FILE    = 'local.db'
CHROMA_DIR = './chroma_db'
EMBED_MODEL = "BAAI/bge-small-zh-v1.5"   # Chinese embedding model, 512-dim, reads up to 512 tokens
COLLECTION  = "vench_notes_bge"          # vectors from different models can't share a collection

# The model runs on ONNX Runtime via fastembed and is loaded only on the first notes search.
# It replaced paraphrase-multilingual-MiniLM-L12-v2: on the eval set in rag_eval/ vector-only
# Recall@5 went from 0.55 to 0.71, and peak memory in a test process from ~930 MB to ~280 MB
# (that model also cut its input off at 128 tokens, about 150 Chinese characters).
# After this long without a notes search the model is dropped again (the index stays on disk).
IDLE_UNLOAD_SECS = int(os.environ.get('RAG_IDLE_UNLOAD_SECS', '600'))

# Notes are split into chunks of at most this many characters (plus the note's date/ticker
# header), so a long diary entry that covers several topics is matched topic by topic.
CHUNK_CHARS = 100
CANDIDATES  = 20   # results taken from each retriever before fusion
RRF_K       = 60   # reciprocal rank fusion constant (the value from the original RRF paper)

_collection  = None
_last_used   = 0.0
_index_lock  = threading.RLock()
_index_dirty = True   # notes changed since the last refresh (or never indexed in this process)
_bm25        = None   # keyword index over the same chunks; tiny, so it stays loaded


_embed_model = None   # one shared ONNX model; chromadb may rebuild the function from its config


def _shared_model():
    global _embed_model
    if _embed_model is None:
        from fastembed import TextEmbedding
        _embed_model = TextEmbedding(EMBED_MODEL)
    return _embed_model


def _fastembed_function():
    """Dense embeddings from fastembed (ONNX) in the shape chromadb expects."""
    from chromadb.api.types import EmbeddingFunction
    import numpy as np

    class FastEmbedFunction(EmbeddingFunction):
        def __init__(self, model_name: str = EMBED_MODEL):
            self.model_name = model_name

        def __call__(self, input):
            return [np.asarray(v, dtype=np.float32) for v in _shared_model().embed(list(input))]

        @staticmethod
        def name() -> str:
            return "vench_fastembed"

        def get_config(self) -> dict:
            return {"model_name": self.model_name}

        @staticmethod
        def build_from_config(config: dict):
            return FastEmbedFunction(config["model_name"])

    return FastEmbedFunction()


def _get_collection():
    global _collection, _last_used
    with _index_lock:
        _last_used = time.time()
        if _collection is None:
            import chromadb
            client = chromadb.PersistentClient(path=CHROMA_DIR)
            for old in client.list_collections():   # indexes built with earlier models
                if old.name != COLLECTION:
                    client.delete_collection(old.name)
            _collection = client.get_or_create_collection(
                name=COLLECTION, embedding_function=_fastembed_function(),
                metadata={"hnsw:space": "cosine"},
            )
            threading.Thread(target=_unload_when_idle, daemon=True).start()
        return _collection


def _unload_when_idle():
    """Drop the embedding model once notes search has been idle for IDLE_UNLOAD_SECS."""
    global _collection, _embed_model
    while True:
        time.sleep(min(60, IDLE_UNLOAD_SECS))
        with _index_lock:
            if time.time() - _last_used < IDLE_UNLOAD_SECS:
                continue
            _collection = None
            _embed_model = None
        gc.collect()
        try:
            ctypes.CDLL("libc.so.6").malloc_trim(0)   # hand freed heap back to the OS (glibc)
        except OSError:
            pass
        print("[rag] embedding model unloaded after idle period")
        return


def mark_dirty():
    """Call when notes (or the trades they describe) change; the next search re-syncs the index."""
    global _index_dirty
    _index_dirty = True


# ─────────────────────────── index building (notes only) ───────────────────

def _load_notes() -> list[tuple[str, str, str, dict]]:
    """Diary notes and trade notes as (note_id, header, body, metadata)."""
    conn = sqlite3.connect(DB_FILE)
    notes = []

    # Daily notes
    rows = conn.execute(
        "SELECT date, note FROM daily_notes WHERE note != '' AND note IS NOT NULL"
    ).fetchall()
    for date, note in rows:
        if note.strip():
            notes.append((f"daily_{date}", f"日期：{date}", note.strip(),
                          {"type": "daily_note", "date": date}))

    # Trade notes
    rows = conn.execute("""
        SELECT tn.trade_id, tn.note, t.code, t.trd_side, t.create_time
        FROM trade_notes tn
        LEFT JOIN trades t ON t.order_id = tn.trade_id
        WHERE tn.note != '' AND tn.note IS NOT NULL
    """).fetchall()
    for trade_id, note, code, side, create_time in rows:
        if note.strip():
            header = f"交易笔记 [{code} {side} {create_time}]" if code else "交易笔记"
            notes.append((f"tradenote_{trade_id}", header, note.strip(), {
                "type":     "trade_note",
                "trade_id": str(trade_id),
                "ticker":   str(code or ""),
                "date":     str(create_time or ""),
            }))

    conn.close()
    return notes


def _split(body: str, size: int = CHUNK_CHARS) -> list[str]:
    """Split a note into pieces of at most `size` characters: at line breaks first, then after
    sentence ends, and only as a last resort in the middle of a sentence."""
    pieces = []
    for line in body.splitlines():
        line = line.strip()
        if len(line) <= size:
            pieces += [line] if line else []
            continue
        for sent in re.split(r"(?<=[。！？!?；;])", line):
            pieces += [sent[i:i + size] for i in range(0, len(sent), size) if sent[i:i + size].strip()]

    chunks, cur = [], ""
    for piece in pieces:   # pack neighbouring pieces back together while they fit
        if cur and len(cur) + 1 + len(piece) > size:
            chunks.append(cur)
            cur = piece
        else:
            cur = f"{cur}\n{piece}" if cur else piece
    return chunks + [cur] if cur else chunks


def _chunk_notes(notes, size: int = CHUNK_CHARS) -> tuple[list[str], list[dict], list[str]]:
    """Turn notes into index entries. Every chunk repeats its note's header, so a chunk from the
    middle of a diary entry still carries its date and ticker."""
    docs, metas, ids = [], [], []
    for note_id, header, body, meta in notes:
        day = int(re.sub(r"\D", "", meta.get("date", ""))[:8] or 0)   # 20260703, for date filters
        for k, chunk in enumerate(_split(body, size)):
            docs.append(f"{header}\n{chunk}")
            metas.append({**meta, "parent": note_id, "day": day})
            ids.append(f"{note_id}#{k}")
    return docs, metas, ids


def build_index(force: bool = False) -> int:
    """Bring the notes index in line with SQLite. Only new or edited chunks are embedded (a content
    hash is kept in each entry's metadata); deleted ones are removed. force=True re-embeds all.
    The BM25 index is rebuilt from the same chunks every time (it is cheap).
    """
    global _index_dirty, _bm25
    with _index_lock:
        col = _get_collection()
        if not _index_dirty and not force and _bm25 is not None:
            return col.count()

        docs, metas, ids = _chunk_notes(_load_notes())
        for meta, doc in zip(metas, docs):
            meta["hash"] = hashlib.sha1(doc.encode("utf-8")).hexdigest()

        existing = col.get(include=["metadatas"])
        have = {i: (m or {}).get("hash") for i, m in zip(existing["ids"], existing["metadatas"])}
        todo = [k for k, i in enumerate(ids) if force or have.get(i) != metas[k]["hash"]]
        for start in range(0, len(todo), 100):
            batch = todo[start:start + 100]
            col.upsert(
                documents=[docs[k] for k in batch],
                metadatas=[metas[k] for k in batch],
                ids=[ids[k] for k in batch],
            )
        stale = sorted(set(have) - set(ids))
        if stale:
            col.delete(ids=stale)

        _bm25 = BM25(ids, docs, metas)
        _index_dirty = False
        print(f"[rag] index synced: {len(todo)} embedded, {len(stale)} removed, {col.count()} chunks")
        return col.count()


# ─────────────────────────── hybrid search ─────────────────────────────────

def _tokenize(text: str) -> list[str]:
    """Latin words and numbers as whole tokens (NVDA, vcp, atr), Chinese as overlapping character
    bigrams (止损 → 止损; 移动止损 → 移动 动止 止损). Bigrams need no dictionary, unlike jieba."""
    tokens = []
    for run in re.findall(r"[a-z0-9]+|[\u4e00-\u9fff]+", text.lower()):
        if run.isascii() or len(run) == 1:
            tokens.append(run)
        else:
            tokens += [run[i:i + 2] for i in range(len(run) - 1)]
    return tokens


class BM25:
    """Okapi BM25 over the note chunks, kept in memory (a few hundred short chunks)."""

    def __init__(self, ids: list[str], docs: list[str], metas: list[dict], k1=1.5, b=0.75):
        self.ids, self.docs, self.metas = ids, docs, metas
        self.by_id = {i: n for n, i in enumerate(ids)}
        self.k1, self.b = k1, b
        self.tfs  = [Counter(_tokenize(d)) for d in docs]
        self.lens = [sum(tf.values()) for tf in self.tfs]
        self.avgdl = sum(self.lens) / len(self.lens) if self.lens else 1.0
        df = Counter(t for tf in self.tfs for t in tf)
        n = len(docs)
        self.idf = {t: math.log(1 + (n - f + 0.5) / (f + 0.5)) for t, f in df.items()}

    def rank(self, query: str, k: int, keep=lambda n: True) -> list[str]:
        terms = set(_tokenize(query))
        scored = []
        for n, tf in enumerate(self.tfs):
            if not keep(n):
                continue
            norm = self.k1 * (1 - self.b + self.b * self.lens[n] / self.avgdl)
            s = sum(self.idf[t] * tf[t] * (self.k1 + 1) / (tf[t] + norm) for t in terms if t in tf)
            if s > 0:
                scored.append((s, n))
        scored.sort(reverse=True)
        return [self.ids[n] for _, n in scored[:k]]


def _rrf(rankings: list[list[str]], k: int = RRF_K) -> list[str]:
    """Reciprocal rank fusion: score(d) = sum over rankings of 1 / (k + rank of d). It only uses
    ranks, so BM25 scores and cosine distances never have to be put on the same scale."""
    score = defaultdict(float)
    for ranking in rankings:
        for rank, doc_id in enumerate(ranking, start=1):
            score[doc_id] += 1 / (k + rank)
    return sorted(score, key=score.get, reverse=True)


def _day(value: str | None, pad: str) -> int | None:
    """'2026-07-03' → 20260703. A partial date is padded, so '2026-07' works as a bound too:
    pad '0' for a lower bound (20260700), '9' for an upper one (20260799)."""
    digits = re.sub(r"\D", "", value or "")[:8]
    return int(digits.ljust(8, pad)) if digits else None


def search(col, index: BM25, query: str, n: int = 6, date_from: str | None = None,
           date_to: str | None = None, ticker: str | None = None,
           mode: str = "hybrid") -> list[tuple[str, str]]:
    """Top n notes for the query as (note_id, best matching chunk), at most one chunk per note.
    mode 'vector' or 'bm25' runs a single retriever (used by the evaluation)."""
    lo, hi = _day(date_from, "0"), _day(date_to, "9")
    ticker = (ticker or "").strip().upper()

    rankings = []
    if mode in ("hybrid", "vector"):
        conds = ([{"day": {"$gte": lo}}] if lo else []) + ([{"day": {"$lte": hi}}] if hi else [])
        where = {"$and": conds} if len(conds) > 1 else (conds[0] if conds else None)
        res = col.query(query_texts=[query], n_results=min(CANDIDATES, col.count()), where=where,
                        where_document={"$contains": ticker} if ticker else None)
        rankings.append(res["ids"][0])
    if mode in ("hybrid", "bm25"):
        def keep(i):
            day = index.metas[i]["day"]
            return ((lo is None or day >= lo) and (hi is None or day <= hi)
                    and (not ticker or ticker in index.docs[i].upper()))
        rankings.append(index.rank(query, CANDIDATES, keep))

    hits, seen = [], set()
    for chunk_id in _rrf(rankings):
        i = index.by_id.get(chunk_id)
        if i is None or index.metas[i]["parent"] in seen:
            continue
        seen.add(index.metas[i]["parent"])
        hits.append((index.metas[i]["parent"], index.docs[i]))
        if len(hits) == n:
            break
    return hits


# ─────────────────────────── tools ─────────────────────────────────────────

# SQL allowlist — only SELECT permitted
def _run_sql(query: str) -> str:
    q = query.strip()
    if not q.upper().startswith("SELECT"):
        return "Error: only SELECT statements are allowed."
    try:
        # Read-only connection: the model can only ever read, whatever SQL it writes
        conn = sqlite3.connect(f"file:{DB_FILE}?mode=ro", uri=True)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(q).fetchmany(200)
        conn.close()
        if not rows:
            return "查询结果为空。"
        return json.dumps([dict(r) for r in rows], ensure_ascii=False, default=str)
    except Exception as e:
        return f"SQL Error: {e}"


def _search_notes(query: str, n: int = 6, date_from: str | None = None,
                  date_to: str | None = None, ticker: str | None = None) -> str:
    col = _get_collection()
    if _index_dirty or _bm25 is None:
        build_index()
    if col.count() == 0:
        return "暂无笔记内容。"
    hits = search(col, _bm25, query, n, date_from, date_to, ticker)
    if not hits:
        return "未找到相关笔记。"
    return "\n\n---\n\n".join(chunk for _, chunk in hits)


# Tool definitions for DeepSeek
_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_sql",
            "description": (
                "对交易数据库执行 SELECT 查询，回答所有数字统计类问题。\n"
                "可用表：\n"
                "• ticker_pnl(code, total_positions, wins, losses, net_pnl, best_position, worst_position, win_rate_pct)"
                "  ← 按标的汇总的净盈亏视图(只含已平仓仓位)，回答'哪个标的盈利/亏损最多、胜率最高'等问题必须用这张表\n"
                "• position_pnl(position_id, code, direction, status, realized_pnl, is_win, entry_qty, avg_entry, "
                "r_multiple, initial_1r_usd, open_time, close_time)"
                "  ← 单笔仓位：direction=LONG/SHORT，status=open/closed(统计胜负只用 closed)，realized_pnl 是扣完手续费的净盈亏；"
                "r_multiple 只来自实盘系统的标准化 1R 账本(右侧 swing 交易)，其他仓位为空\n"
                "• r_ledger(position_id, ticker, direction, open_date, close_date, net_pnl, initial_1r_usd, realized_r, r_source)"
                "  ← 标准化 R 账本：每笔右侧交易开仓时锁定的统一 1R 金额和实际 R 倍数，回答 R/期望值问题用这张表\n"
                "• trades(order_id, code, trd_side, price, qty, create_time, position_id, tags)"
                "  ← 原始交易记录，用于时间筛选、次数统计、tags查询\n"
                "• daily_notes(date, note), trade_notes(trade_id, note)\n"
                "注意：net_pnl 是净盈亏（盈利+亏损之和），不要只筛选亏损仓位来计算"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "只读 SELECT SQL 语句"
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_notes",
            "description": (
                "在日记和交易笔记中搜索（关键词 + 语义混合检索），适用于心态、复盘、"
                "情绪、特定事件等文字类问题。问题里有时间范围或具体标的时，"
                "用 date_from / date_to / ticker 过滤，不要只写进 query。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索关键词或问题描述"
                    },
                    "date_from": {
                        "type": "string",
                        "description": "可选，起始日期 YYYY-MM-DD（含）"
                    },
                    "date_to": {
                        "type": "string",
                        "description": "可选，结束日期 YYYY-MM-DD（含）"
                    },
                    "ticker": {
                        "type": "string",
                        "description": "可选，只看提到该标的的笔记，如 NVDA"
                    }
                },
                "required": ["query"]
            }
        }
    }
]


# ─────────────────────────── agentic loop ──────────────────────────────────

_SYSTEM_PROMPT = (
    "你是用户的个人交易助手，帮助他回顾和分析自己的交易记录和日志。\n"
    "你有两个工具：\n"
    "1. run_sql — 查询交易数据库，用于数字统计类问题\n"
    "2. search_notes — 搜索日记和笔记，用于心态复盘类问题\n"
    "优先用工具获取真实数据再回答，不要凭空推测。回答简洁，用中文。"
)


def _build_messages(question: str, history: list[dict]) -> list[dict]:
    """Construct message list: system + history + new user question."""
    messages = [{"role": "system", "content": _SYSTEM_PROMPT}]
    # Inject conversation history (max last 10 turns to stay within context)
    messages.extend(history[-20:])
    messages.append({"role": "user", "content": question})
    return messages


def _execute_tool(fn: str, args: dict) -> tuple[str, dict]:
    """Execute a tool call and return (result, source_record)."""
    if fn == "run_sql":
        return _run_sql(args["query"]), {"type": "sql", "query": args["query"]}
    elif fn == "search_notes":
        filters = {k: args[k] for k in ("date_from", "date_to", "ticker") if args.get(k)}
        return _search_notes(args["query"], **filters), {"type": "notes", "query": args["query"], **filters}
    return f"Unknown tool: {fn}", {}


def _run_tool_loop(client, messages: list, sources: list, max_rounds: int = 5):
    """Run agentic tool-calling loop until no more tool calls. Returns final messages."""
    for _ in range(max_rounds):
        response = client.chat.completions.create(
            model="deepseek-chat",
            messages=messages,
            tools=_TOOLS,
            tool_choice="auto",
        )
        msg = response.choices[0].message

        if not msg.tool_calls:
            return msg.content or "（无回答）", False  # done

        messages.append(msg)
        for tc in msg.tool_calls:
            result, source = _execute_tool(
                tc.function.name, json.loads(tc.function.arguments)
            )
            if source:
                sources.append(source)
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result,
            })

    return "（超出最大工具调用次数，请重试）", False


def ask(question: str, history: list[dict] | None = None) -> dict:
    """
    Agentic loop with conversation history support.
    history: list of prior {"role": ..., "content": ...} messages.
    Returns {"answer": str, "sources": list, "history": updated list}
    """
    history = history or []
    client  = OpenAI(api_key=os.getenv("DEEPSEEK_API_KEY"), base_url="https://api.deepseek.com")
    messages = _build_messages(question, history)
    sources  = []

    answer, _ = _run_tool_loop(client, messages, sources)

    # Build updated history to return to caller
    new_history = history + [
        {"role": "user",      "content": question},
        {"role": "assistant", "content": answer},
    ]

    return {"answer": answer, "sources": sources, "history": new_history}


def ask_stream(question: str, history: list[dict] | None = None):
    """
    Streaming version: tool calls run synchronously, final answer streams via SSE.
    Yields SSE-formatted strings. Last yield contains sources + updated history as JSON.
    """
    history  = history or []
    client   = OpenAI(api_key=os.getenv("DEEPSEEK_API_KEY"), base_url="https://api.deepseek.com")
    messages = _build_messages(question, history)
    sources  = []

    # Phase 1: tool-calling loop (non-streaming)
    # Track whether any tools were actually called, so we know if Phase 2 is needed.
    tools_called = False
    direct_answer = None  # set when model answers with no tool calls on first try

    for _ in range(5):
        response = client.chat.completions.create(
            model="deepseek-chat",
            messages=messages,
            tools=_TOOLS,
            tool_choice="auto",
        )
        msg = response.choices[0].message

        if not msg.tool_calls:
            if not tools_called:
                # Model answered directly without calling any tools.
                # Capture the content so we can stream it without a second API call.
                direct_answer = msg.content or ""
            else:
                # After tool results, model gave a final answer — append and go to Phase 2.
                messages.append(msg)
            break

        tools_called = True
        messages.append(msg)
        for tc in msg.tool_calls:
            result, source = _execute_tool(
                tc.function.name, json.loads(tc.function.arguments)
            )
            if source:
                sources.append(source)
            messages.append({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result,
            })
    else:
        yield "data: （超出最大工具调用次数）\n\n"
        yield "data: [DONE]\n\n"
        return

    full_answer = ""

    if direct_answer is not None:
        # Stream the direct answer character-by-character (no extra API call needed)
        for char in direct_answer:
            full_answer += char
            yield f"data: {json.dumps(char, ensure_ascii=False)}\n\n"
    else:
        # Phase 2: stream the final answer after tool calls (no tools passed = no leakage)
        # Add a temporary instruction so the model answers directly without outputting tool markup
        phase2_messages = messages + [{
            "role": "user",
            "content": "请根据以上查询结果，直接给出简洁的中文回答，不要调用任何工具。"
        }]
        stream = client.chat.completions.create(
            model="deepseek-chat",
            messages=phase2_messages,
            stream=True,
        )
        for chunk in stream:
            delta = chunk.choices[0].delta.content
            if delta:
                full_answer += delta
                yield f"data: {json.dumps(delta, ensure_ascii=False)}\n\n"

    # Send metadata at end
    new_history = history + [
        {"role": "user",      "content": question},
        {"role": "assistant", "content": full_answer},
    ]
    meta = json.dumps({"sources": sources, "history": new_history}, ensure_ascii=False)
    yield f"data: [META]{meta}\n\n"
    yield "data: [DONE]\n\n"
