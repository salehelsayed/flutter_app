#!/usr/bin/env python3
"""Classify each finished row log of a sims run by its typed result, not the wrapper exit code.

Usage: classify_sims_rows.py <logs dir> [--exclude <row>...]
Verdict order: SIMS_RESULT_JSON status, then a BLOCKED marker in the text, then exitCode.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

logs = Path(sys.argv[1])
exclude = set(sys.argv[3:]) if len(sys.argv) > 2 and sys.argv[2] == "--exclude" else set()
counts = Counter()
rows = []
for log in sorted(logs.glob("*.log")):
    if log.stem in exclude:
        continue
    text = log.read_text(errors="replace")
    exit_match = re.search(r"^exitCode=(-?\d+)$", text, re.M)
    if not exit_match:
        verdict, detail = "IN_PROGRESS", ""
    else:
        results = re.findall(r"SIMS_RESULT_JSON=(\{.*\})", text)
        status, detail = None, ""
        if results:
            try:
                result = json.loads(results[-1])
                status = result.get("status")
                detail = result.get("blocker") or result.get("detail") or ""
            except ValueError:
                pass
        blocked = re.search(r"(Device execution requires explicit leased runtime targets|"
                            r"resolved to the same target|Build omitted because no selected consumer)"
                            r"[^\n]{0,120}", text)
        if blocked and status in (None, "PASS"):
            verdict, detail = "BLOCKED", blocked.group(0)
        elif status:
            verdict = status
        elif blocked:
            verdict, detail = "BLOCKED", blocked.group(0)
        else:
            verdict = "PASS" if exit_match.group(1) == "0" else "FAIL"
    counts[verdict] += 1
    rows.append((verdict, log.stem, detail[:160]))
print(" ".join(f"{k}={v}" for k, v in sorted(counts.items())))
for verdict, row, detail in rows:
    if verdict not in ("PASS", "IN_PROGRESS"):
        print(f"{verdict}\t{row}\t{detail}")
