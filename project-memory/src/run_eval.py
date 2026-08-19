#!/usr/bin/env python3
"""A/B evaluation runner for the project-memory recall arm (plans 381 + 382).

`--gate`   runs the 18 GATED questions from eval/expected_facts.json (12
           `v1_scope` from plan 381 + 6 `v2_scope` from plan 382's memory pass)
           and exits 0 only if every `required` substring appears in the RECALL
           OUTPUT (not in the query -- see TC-381-10) within the token cap.
`--report` runs all 30 questions with per-question token counts, and is the
           B-arm artifact to set against project-memory/BASELINE-RESULTS.md
           (A arm: ~45k tokens and ~3.1 min per question).
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_graph  # noqa: E402
import recall as recall_mod  # noqa: E402

DEFAULT_DB = Path(__file__).resolve().parents[1] / "graph.db"
DEFAULT_EXPECTATIONS = Path(__file__).resolve().parents[1] / "eval" / "expected_facts.json"
TOKEN_CAP = 1000
BUDGET = 700


def load_expectations(path=DEFAULT_EXPECTATIONS):
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    return document["questions"]


def memory_source_present():
    return Path(build_graph.DEFAULT_MEMORY_DIR).is_dir()


def gated(row):
    """Rows `--gate` enforces: plan-381 v1 scope OR plan-382 v2 scope.

    v2 rows are answered by the session-memory pass, whose source lives OUTSIDE
    the repository -- other machines, CI containers and Codex do not have it.
    Where the source is absent those rows are untestable, not failing: the same
    portability carve-out TC-382-05 gives the builder, and it is announced, not
    silent. The check reads the SOURCE, never the graph, so a memory directory
    that is present but produced no facts stays gated and reds honestly.
    """
    if row.get("v2_scope") and not memory_source_present():
        return False
    return bool(row.get("v1_scope") or row.get("v2_scope"))


def score(db_path, rows, budget=BUDGET, cap=TOKEN_CAP):
    """Score each row against recall's OUTPUT. Never against the query."""
    results = []
    for row in rows:
        output = recall_mod.recall(Path(db_path), row["query"], budget=budget)
        haystack = output.lower()
        missing = [item for item in row["required"] if item.lower() not in haystack]
        tokens = recall_mod.token_count(output)
        results.append({
            "id": row["id"],
            "category": row["category"],
            "query": row["query"],
            "required": row["required"],
            "missing": missing,
            "tokens": tokens,
            "v1_scope": row["v1_scope"],
            "v2_scope": bool(row.get("v2_scope")),
            "pass": not missing and tokens <= cap,
            "output": output,
        })
    return results


def _print_table(results):
    print("| Q | scope | tokens | hit | missing |")
    print("|---|---|--:|---|---|")
    for row in results:
        print("| {} | {} | {} | {} | {} |".format(
            row["id"],
            "v1" if row["v1_scope"] else ("v2" if row.get("v2_scope") else "phase-3"),
            row["tokens"],
            "HIT" if row["pass"] else "MISS",
            ", ".join(row["missing"]) or "-",
        ))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--gate", action="store_true")
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    parser.add_argument("--expectations", default=str(DEFAULT_EXPECTATIONS))
    parser.add_argument("--show", action="store_true", help="print recall output per row")
    args = parser.parse_args(argv)

    if not args.gate and not args.report:
        parser.error("choose --gate or --report")
    if not Path(args.db).exists():
        print("FAIL: {} missing -- run build_graph.py first".format(args.db),
              file=sys.stderr)
        return 2

    expectations = load_expectations(args.expectations)
    if args.gate and not memory_source_present():
        dropped = [row["id"] for row in expectations if row.get("v2_scope")]
        print("NOTE: {} not present -- {} v2-scope row(s) ungated here: {}".format(
            build_graph.DEFAULT_MEMORY_DIR, len(dropped), ", ".join(dropped)))
    rows = [row for row in expectations if gated(row)] if args.gate else expectations
    results = score(args.db, rows)

    _print_table(results)
    if args.show:
        for row in results:
            print("\n--- {} :: {}".format(row["id"], row["query"]))
            print(row["output"])

    scoped = [row for row in results if gated(row)]
    hits = [row for row in scoped if row["pass"]]
    tokens = [row["tokens"] for row in results]
    print("\ngated: {}/{} hit; tokens min/median/max: {}/{}/{}".format(
        len(hits), len(scoped),
        min(tokens), sorted(tokens)[len(tokens) // 2], max(tokens),
    ))

    if args.gate:
        misses = [row for row in results if not row["pass"]]
        if misses:
            print("FAIL: {} gated question(s) missed: {}".format(
                len(misses), ", ".join(row["id"] for row in misses)), file=sys.stderr)
            return 1
        print("OK: {}/{} gated questions answered within the token cap".format(
            len(hits), len(scoped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
