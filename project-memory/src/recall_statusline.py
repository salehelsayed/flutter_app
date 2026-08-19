#!/usr/bin/env python3
"""Statusline fragment for project-memory recall usage.

Prints `recall N (M hit)` for TODAY's (UTC) CLI recalls, read from
recall_stats.jsonl (written by recall.py's main()). Prints `recall 0` when
the ledger exists but holds no calls today — deployed-but-unused is exactly
the adoption signal worth seeing — and prints NOTHING when there is no
ledger yet (tool not deployed / stats disabled). Day-scoped, not
session-scoped: the ledger carries no session id (recall is a plain CLI,
not a hook). Best-effort: any error prints nothing, never breaks the
statusline.
"""

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

DEFAULT_LEDGER = Path(__file__).resolve().parents[1] / "recall_stats.jsonl"


def fragment(ledger, today):
    if not ledger.exists():
        return ""
    calls = 0
    hits = 0
    try:
        with ledger.open(encoding="utf-8") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if str(record.get("ts", ""))[:10] != today:
                    continue
                calls += 1
                if record.get("hit"):
                    hits += 1
    except OSError:
        return ""
    if calls == 0:
        return "recall 0"
    return "recall {} ({} hit)".format(calls, hits)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ledger", default=str(DEFAULT_LEDGER))
    parser.add_argument("--today", default=None,
                        help="YYYY-MM-DD override (tests); default = UTC today")
    args = parser.parse_args(argv)
    today = args.today or dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    text = fragment(Path(args.ledger), today)
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
