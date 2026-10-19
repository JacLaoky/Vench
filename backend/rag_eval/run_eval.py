"""
Retrieval evaluation for search_notes on a synthetic trading journal (rag_eval/notes.jsonl,
64 notes written for this test, not real journal data) and 39 hand-labelled queries.

    cd backend && python rag_eval/run_eval.py

Compares the old setup (multilingual MiniLM, vector search over whole notes, no filters) with
the current model, chunking, BM25 alone and the hybrid. Recall@5: share of a query's relevant notes found in the top 5. MRR: 1 / rank of the
first relevant note (top 10), averaged over queries.
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import chromadb
import numpy as np
from chromadb.api.types import EmbeddingFunction
import rag

HERE = os.path.dirname(os.path.abspath(__file__))
OLD_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"


class OldModel(EmbeddingFunction):
    """The embedding model search_notes used before bge-small-zh, for the baseline row."""

    def __init__(self):
        from fastembed import TextEmbedding
        self.model = TextEmbedding(OLD_MODEL)

    def __call__(self, input):
        return [np.asarray(v, dtype=np.float32) for v in self.model.embed(list(input))]

    @staticmethod
    def name() -> str:
        return "eval_old_model"


def load_jsonl(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def to_notes(rows):
    """Same (note_id, header, body, metadata) shape as rag._load_notes() builds from SQLite."""
    notes, num_of = [], {}
    for r in rows:
        if r["kind"] == "daily":
            note_id = f"daily_{r['date']}"
            notes.append((note_id, f"日期：{r['date']}", r["note"], {"type": "daily_note", "date": r["date"]}))
        else:
            note_id = f"tradenote_{r['num']}"
            notes.append((note_id, f"交易笔记 [{r['code']} {r['side']} {r['date']}]", r["note"],
                          {"type": "trade_note", "ticker": r["code"], "date": r["date"]}))
        num_of[note_id] = r["num"]
    return notes, num_of


def build(notes, size, name, embedding_function=None):
    docs, metas, ids = rag._chunk_notes(notes, size)
    col = chromadb.EphemeralClient().get_or_create_collection(
        name=name, embedding_function=embedding_function or rag._fastembed_function(),
        metadata={"hnsw:space": "cosine"})
    col.add(documents=docs, metadatas=metas, ids=ids)
    return col, rag.BM25(ids, docs, metas)


def evaluate(col, index, queries, num_of, mode, use_filters):
    recall, mrr, secs = [], [], 0.0
    for q in queries:
        filters = {k: q[k] for k in ("date_from", "date_to", "ticker") if k in q and use_filters}
        t = time.perf_counter()
        hits = rag.search(col, index, q["q"], 10, mode=mode, **filters)
        secs += time.perf_counter() - t
        got = [num_of[note_id] for note_id, _ in hits]
        rel = set(q["relevant"])
        recall.append(len(rel & set(got[:5])) / len(rel))
        mrr.append(next((1 / r for r, x in enumerate(got, 1) if x in rel), 0.0))
    n = len(queries)
    return sum(recall) / n, sum(mrr) / n, secs / n * 1000


def main():
    notes, num_of = to_notes(load_jsonl("notes.jsonl"))
    queries = load_jsonl("queries.jsonl")
    plain = [q for q in queries if not ({"date_from", "date_to", "ticker"} & q.keys())]
    filtered = [q for q in queries if q not in plain]

    old = build(notes, 10_000, "old", OldModel())     # one entry per note, like the old index
    whole = build(notes, 10_000, "whole")
    chunked = build(notes, rag.CHUNK_CHARS, "chunked")
    print(f"{len(notes)} notes → {whole[0].count()} entries unchunked, {chunked[0].count()} chunks")

    setups = [
        ("旧：MiniLM 整条向量",   old,     "vector", False),
        ("bge 整条向量",          whole,   "vector", True),
        ("bge 分块 + 向量",       chunked, "vector", True),
        ("分块 + BM25",           chunked, "bm25",   True),
        ("bge 分块 + 混合 (RRF)", chunked, "hybrid", True),
    ]
    print(f"\n{'':22}{'普通查询 (%d)' % len(plain):>20}{'带过滤查询 (%d)' % len(filtered):>22}{'':>10}")
    print(f"{'':22}{'Recall@5':>11}{'MRR':>9}{'Recall@5':>13}{'MRR':>9}{'ms/查询':>10}")
    for label, (col, index), mode, use_filters in setups:
        r1, m1, ms = evaluate(col, index, plain, num_of, mode, use_filters)
        r2, m2, _ = evaluate(col, index, filtered, num_of, mode, use_filters)
        print(f"{label:<22}{r1:>11.3f}{m1:>9.3f}{r2:>13.3f}{m2:>9.3f}{ms:>10.1f}")


if __name__ == "__main__":
    main()
