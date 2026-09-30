#!/usr/bin/env python3
"""Ordered title/text changes of the Mknoon notifications for one case of call_notifications.txt (Mac clock).

Usage: r28_notif_seq.py <call_notifications.txt> <case>
"""
import re
import sys

path, case = sys.argv[1], sys.argv[2]
on = False
last = None
out = []
for line in open(path, encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("--- "):
        on = line == "--- " + case
        continue
    if not on:
        continue
    m = re.match(r"\[(\d\d:\d\d:\d\d)\] (.*)", line)
    if not m:
        continue
    t, body = m.groups()
    recs = []
    for rec in body.split("#"):
        ti = re.search(r"android\.title=String \(([^)]*)\)", rec)
        tx = re.search(r"android\.text=String \(([^)]*)\)", rec)
        if ti or tx:
            recs.append(f"{ti.group(1) if ti else '?'} / {tx.group(1) if tx else '?'}")
    s = ", ".join(dict.fromkeys(recs))
    if s != last:
        out.append(f"{t} {s or '(none)'}")
        last = s
print("; ".join(out) or "no call notification seen")
