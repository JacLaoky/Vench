"""
rag.py — Journal AI Assistant for Vench
Architecture: DeepSeek Function Calling
  - run_sql:      query SQLite directly for any numeric/stats question
  - search_notes: semantic search in ChromaDB for diary/note questions
"""

import os
import json
import sqlite3
import threading
from openai import OpenAI
import chromadb
from chromadb.utils import embedding_functions

DB_FILE    = 'local.db'
CHROMA_DIR = './chroma_db'

# ChromaDB — only used for notes (daily_notes + trade_notes)
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


# ─────────────────────────── index building (notes only) ───────────────────

def _load_documents() -> tuple[list[str], list[dict], list[str]]:
    """Load only diary notes and trade notes into ChromaDB."""
    conn = sqlite3.connect(DB_FILE)
    docs, metas, ids = [], [], []

    # Daily notes
    rows = conn.execute(
        "SELECT date, note FROM daily_notes WHERE note != '' AND note IS NOT NULL"
    ).fetchall()
    for date, note in rows:
        if note.strip():
            docs.append(f"日期：{date}\n{note.strip()}")
            metas.append({"type": "daily_note", "date": date})
            ids.append(f"daily_{date}")

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
            docs.append(f"{header}\n{note.strip()}")
            metas.append({
                "type":     "trade_note",
                "trade_id": str(trade_id),
                "ticker":   str(code or ""),
                "date":     str(create_time or ""),
            })
            ids.append(f"tradenote_{trade_id}")

    conn.close()
    return docs, metas, ids


def build_index(force: bool = False) -> int:
    """Build (or rebuild) the ChromaDB notes index. Thread-safe."""
    global _index_built
    with _index_lock:
        if _index_built and not force:
            return _collection.count()

        docs, metas, ids = _load_documents()
        if docs:
            for i in range(0, len(docs), 100):
                _collection.upsert(
                    documents=docs[i:i+100],
                    metadatas=metas[i:i+100],
                    ids=ids[i:i+100],
                )
        _index_built = True
        print(f"[rag] index built: {_collection.count()} notes")
        return _collection.count()


# ─────────────────────────── tools ─────────────────────────────────────────

# SQL allowlist — only SELECT permitted
def _run_sql(query: str) -> str:
    q = query.strip()
    if not q.upper().startswith("SELECT"):
        return "Error: only SELECT statements are allowed."
    try:
        conn = sqlite3.connect(DB_FILE)
        conn.row_factory = sqlite3.Row
        rows = conn.execute(q).fetchmany(200)
        conn.close()
        if not rows:
            return "查询结果为空。"
        return json.dumps([dict(r) for r in rows], ensure_ascii=False, default=str)
    except Exception as e:
        return f"SQL Error: {e}"


def _search_notes(query: str, n: int = 6) -> str:
    if not _index_built:
        build_index()
    if _collection.count() == 0:
        return "暂无笔记内容。"
    results = _collection.query(query_texts=[query], n_results=n)
    docs = results["documents"][0]
    if not docs:
        return "未找到相关笔记。"
    return "\n\n---\n\n".join(docs)


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
                "  ← 按标的汇总的净盈亏视图，回答'哪个标的盈利/亏损最多、胜率最高'等问题必须用这张表\n"
                "• position_pnl(position_id, code, realized_pnl, is_win, open_time, close_time)"
                "  ← 单笔仓位盈亏，回答具体某笔仓位时用\n"
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
                "在日记和交易笔记中做语义搜索，适用于心态、复盘、"
                "情绪、特定事件等文字类问题。"
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索关键词或问题描述"
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
        return _search_notes(args["query"]), {"type": "notes", "query": args["query"]}
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
    if not _index_built:
        build_index()

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
    if not _index_built:
        build_index()

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


# ─────────────────────────── background init ───────────────────────────────

def init_async():
    """Start index building in background thread so Flask startup isn't blocked."""
    t = threading.Thread(target=build_index, daemon=True)
    t.start()
