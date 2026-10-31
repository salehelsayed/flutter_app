#!/bin/bash
# VC-023 read-only (Hetzner via hetzner_ssh.py): for trace files changed in the last MIN minutes, print the distinct
# (role, stage, action, outcome, reason) rows whose outcome or reason is not ok/none, plus terminal rows. No ids or addresses.
MIN=${MIN:-5}
find /var/lib/mknoon/call-diagnostics -maxdepth 1 -type f -name '*-*-*-*-*.json' -mmin -"$MIN" -printf '%T@ %p\n' | sort -n | while read -r _ f; do
python3 - "$f" <<'PY'
import json, sys, collections
evs = json.load(open(sys.argv[1])).get("events", [])
rows = collections.Counter()
for w in evs:
    e = w.get("event", w)
    o, r = e.get("outcome"), e.get("reason")
    if o not in ("ok", None) or r not in ("none", None) or "terminal" in str(e.get("stage")) or "end" in str(e.get("action")):
        rows[(e.get("role"), e.get("stage"), e.get("action"), o, r)] += 1
print("== file events", len(evs))
for k, n in sorted(rows.items(), key=str):
    print(n, *k)
PY
done
