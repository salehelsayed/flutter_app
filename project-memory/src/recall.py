#!/usr/bin/env python3
"""Deterministic, budget-bounded recall over the project-memory graph.

Contract (plan 381):
  * seeds come from exact + case-insensitive ALIAS matches on the question --
    no embeddings, no network, no model call;
  * traversal is <= 2 hops over `relations` via a recursive CTE;
  * output is one FACT per line, carrying the relationship AND its provenance
    on the same line, so a fact can never be read detached from its source;
  * output is deterministic (same question -> byte-identical answer) and
    truncated at a token budget (default 700, hard cap 1000);
  * NOTHING is ever emitted that is not a row in graph.db. Zero seeds prints
    exactly `No facts found for: <terms>` -- never a guess.

Usage:  recall.py "<question>" [--budget 700] [--db project-memory/graph.db]
"""

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_graph  # noqa: E402

DEFAULT_DB = Path(__file__).resolve().parents[1] / "graph.db"
DEFAULT_BUDGET = 700
HARD_CAP = 1000
MAX_HOPS = 2
CHARS_PER_TOKEN = 4
FIRST_PASS_EDGES = 4

STOPWORDS = frozenset("""
a an the is are was were be been being of for to in on at by with as and or
what which who whom whose why how did does do done it its that this these those
from still not no any all still there here about into over under
""".split())

WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9_./-]*")


def token_count(text):
    return int(math.ceil(len(text) / float(CHARS_PER_TOKEN)))


def tokenize(question):
    tokens = []
    for word in WORD.findall(question):
        token = word.strip("./-_").lower()
        if token and token not in STOPWORDS and token not in tokens:
            tokens.append(token)
    return tokens


def probes(tokens):
    """Alias probes: tokens, their hyphen parts, and adjacent pairs."""
    found = set(tokens)
    for token in tokens:
        if "-" in token:
            found.update(part for part in token.split("-") if len(part) >= 4)
        if "/" in token:
            found.update(part for part in token.split("/") if len(part) >= 4)
    for left, right in zip(tokens, tokens[1:]):
        found.add("{} {}".format(left, right))
        found.add("{}-{}".format(left, right))
    return sorted(found)


def seed(db_path, tokens):
    keys = probes(tokens)
    if not keys:
        return []
    placeholders = ",".join("?" * len(keys))
    rows = build_graph.query(
        db_path,
        "SELECT entity_id, count(DISTINCT alias) FROM aliases"
        " WHERE alias IN ({}) GROUP BY entity_id".format(placeholders),
        tuple(keys),
    )
    return [row[0] for row in sorted(rows, key=lambda row: (-row[1], row[0]))]


def _entities(db_path, ids):
    if not ids:
        return {}
    placeholders = ",".join("?" * len(ids))
    rows = build_graph.query(
        db_path,
        "SELECT id, name, etype, status, source_doc, source_line, source_commit"
        " FROM entities WHERE id IN ({})".format(placeholders),
        tuple(ids),
    )
    return {row[0]: row[1:] for row in rows}


def reachable(db_path, seeds):
    placeholders = ",".join("?" * len(seeds))
    rows = build_graph.query(
        db_path,
        "WITH RECURSIVE reach(id, hop) AS ("
        "  SELECT id, 0 FROM entities WHERE id IN ({})"
        "  UNION"
        "  SELECT CASE WHEN r.src_id = reach.id THEN r.dst_id ELSE r.src_id END,"
        "         reach.hop + 1"
        "    FROM relations r JOIN reach"
        "      ON (r.src_id = reach.id OR r.dst_id = reach.id)"
        "   WHERE reach.hop < {}"
        ") SELECT id, min(hop) FROM reach GROUP BY id".format(placeholders, MAX_HOPS),
        tuple(seeds),
    )
    return {row[0]: row[1] for row in rows}


def relevance(text, tokens):
    """How many question terms the fact itself contains. Ordering only -- a fact
    is never rewritten, invented, or scored into existence."""
    lowered = text.lower()
    return sum(1 for token in tokens if token in lowered)


def _entity_fact(row):
    name, etype, status, doc, line, commit = row
    return "{} [{}/{}] ({}:{} @{})".format(name, etype, status, doc, line, commit)


def _edge_fact(src, dst, rtype, doc, line, commit):
    return "{} [{}/{}] --{}--> {} [{}/{}] ({}:{} @{})".format(
        src[0], src[1], src[2], rtype, dst[0], dst[1], dst[2], doc, line, commit
    )


def recall(db_path, question, budget=DEFAULT_BUDGET):
    tokens = tokenize(question)
    seeds = seed(db_path, tokens)
    if not seeds:
        return "No facts found for: {}".format(" ".join(tokens))

    nodes = reachable(db_path, seeds)
    rows = _entities(db_path, sorted(nodes))
    edges = build_graph.query(
        db_path,
        "SELECT src_id, dst_id, rtype, source_doc, source_line FROM relations",
    )
    incident = {}
    for src_id, dst_id, rtype, doc, line in edges:
        if src_id not in nodes or dst_id not in nodes:
            continue
        incident.setdefault(src_id, []).append((src_id, dst_id, rtype, doc, line))
        incident.setdefault(dst_id, []).append((src_id, dst_id, rtype, doc, line))

    facts = []
    emitted = set()

    def push(text):
        if text not in emitted:
            emitted.add(text)
            facts.append(text)

    def edge_key(edge):
        src_id, dst_id, rtype, _doc, line = edge
        text = "{} {}".format(rows.get(src_id, ("",))[0], rows.get(dst_id, ("",))[0])
        return (-relevance(text, tokens), rtype, rows.get(dst_id, ("",))[0], line)

    # Pass 1 keeps breadth across seeds (every seed gets its own line plus its
    # most on-question edges) before any one seed's tail can eat the budget.
    tails = []
    for entity_id in seeds:
        if entity_id not in rows:
            continue
        push(_entity_fact(rows[entity_id]))
        ranked = sorted(
            (edge for edge in incident.get(entity_id, [])
             if edge[0] in rows and edge[1] in rows),
            key=edge_key,
        )
        for edge in ranked[:FIRST_PASS_EDGES]:
            push(_edge_fact(rows[edge[0]], rows[edge[1]], edge[2], edge[3], edge[4],
                            rows[edge[0]][5]))
        tails.extend(ranked[FIRST_PASS_EDGES:])

    for edge in tails:
        push(_edge_fact(rows[edge[0]], rows[edge[1]], edge[2], edge[3], edge[4],
                        rows[edge[0]][5]))

    for edge in sorted(
        (edge for edge in edges if edge[0] in rows and edge[1] in rows),
        key=edge_key,
    ):
        push(_edge_fact(rows[edge[0]], rows[edge[1]], edge[2], edge[3], edge[4],
                        rows[edge[0]][5]))

    limit = min(budget, HARD_CAP)
    kept = []
    used = 0
    for index, fact in enumerate(facts):
        cost = token_count(fact) + 1
        if used + cost > limit:
            remaining = len(facts) - index
            notice = "... truncated at budget: {} more facts".format(remaining)
            if used + token_count(notice) + 1 <= limit:
                kept.append(notice)
            break
        kept.append(fact)
        used += cost
    return "\n".join(kept)


STATS_PATH = Path(__file__).resolve().parents[1] / "recall_stats.jsonl"


def _log_usage(question, budget, output, duration_ms):
    """Usage ledger for the adoption measurement (same pattern as
    tdd_context.py's query log: question is stored as a hash, never as text).
    CLI-only by design -- run_eval.py and the test suite call recall() directly
    and never land here. Best-effort: stats must never break recall.
    Disable with PROJECT_MEMORY_STATS=0."""
    if os.environ.get("PROJECT_MEMORY_STATS") == "0":
        return
    try:
        record = {
            "ts": dt.datetime.now(dt.timezone.utc).isoformat(),
            "question_sha256": hashlib.sha256(question.encode()).hexdigest()[:16],
            "budget": budget,
            "result_chars": len(output),
            "tokens": token_count(output),
            "hit": not output.startswith("No facts found"),
            "duration_ms": round(duration_ms, 2),
        }
        with STATS_PATH.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record) + "\n")
    except OSError:
        pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("question")
    parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    parser.add_argument("--db", default=str(DEFAULT_DB))
    args = parser.parse_args(argv)
    if not Path(args.db).exists():
        print("FAIL: {} missing -- run build_graph.py first".format(args.db),
              file=sys.stderr)
        return 2
    started = time.time()
    output = recall(Path(args.db), args.question, budget=args.budget)
    _log_usage(args.question, args.budget, output, (time.time() - started) * 1000)
    print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
