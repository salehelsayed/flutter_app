#!/usr/bin/env python3
"""Patch-3 keyboard-race check over the FAILED rows of one sims run (Kayan m-f21e764e).

Usage: check_patch3_signature.py <sims-captures/sims-XXXX dir> <signature file>
For each failed row log, scan its proofs attempts for production_direct_send/logs/maestro.log
(batch5 is out of scope) matching the signature, then confirm in the sibling screen-hierarchy
step-*-tapOnElement-chat_composer.json: orbit.view.inner_circle present, chat_composer absent.
"""
import json
import re
import sys
from pathlib import Path

run, signature = Path(sys.argv[1]), Path(sys.argv[2])
pattern = re.compile(signature.read_text().strip())


def resource_ids(node, out):
    if isinstance(node, dict):
        rid = node.get("attributes", {}).get("resource-id") or node.get("resource-id")
        if rid:
            out.add(rid)
        for value in node.values():
            resource_ids(value, out)
    elif isinstance(node, list):
        for value in node:
            resource_ids(value, out)
    return out


failed = []
for log in sorted((run / "logs").glob("*.log")):
    text = log.read_text(errors="replace")
    if not re.search(r"^exitCode=", text, re.M):
        continue
    if '"status":"PASS"' in text or re.search(r"^exitCode=0$", text, re.M):
        continue
    failed.append(log.stem)
print(f"failed rows: {len(failed)}")
for row in failed:
    matches = []
    for maestro_log in sorted((run / "proofs" / row).glob("**/production_direct_send/logs/maestro.log")):
        if not pattern.search(maestro_log.read_text(errors="replace")):
            continue
        confirmed = False
        for hierarchy in sorted(maestro_log.parent.parent.glob("screen-hierarchy/step-*-tapOnElement-chat_composer.json")):
            ids = resource_ids(json.loads(hierarchy.read_text()), set())
            if "orbit.view.inner_circle" in ids and "chat_composer" not in ids:
                confirmed = True
        matches.append((maestro_log.relative_to(run), confirmed))
    if not matches:
        print(f"{row}: no signature match")
    for path, confirmed in matches:
        print(f"{row}: MATCH confirmed={confirmed} {path}")
