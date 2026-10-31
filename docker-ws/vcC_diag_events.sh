#!/bin/bash
# VC-023 read-only (Hetzner test relay, via hetzner_ssh.py): for the newest call-diagnostic trace file(s) changed in the last
# MIN minutes, print one line per media snapshot event: event time, platform/role, transport, pairRelayInvolvement,
# mediaFlowVerified. Also prints terminal end reasons. No ids, peer ids or addresses.
MIN=${MIN:-5}
D=/var/lib/mknoon/call-diagnostics
find "$D" -maxdepth 1 -type f -name '*-*-*-*-*.json' -mmin -"$MIN" -printf '%T@ %p\n' | sort -n | while read -r _ f; do
python3 - "$f" <<'PY'
import json, sys, datetime, warnings
warnings.simplefilter("ignore")
d = json.load(open(sys.argv[1]))
evs = d.get("events", d if isinstance(d, list) else [])
print("== file", datetime.datetime.utcfromtimestamp(__import__("os").path.getmtime(sys.argv[1])).strftime("%H:%M:%SZ"), "events", len(evs))
keys = set()
for w in evs:
    e = w.get("event", w) if isinstance(w, dict) else {}
    v = e.get("values", {}) or {}
    st, ac = e.get("stage"), e.get("action")
    if st == "media" and ac == "snapshot" or "transport" in v or e.get("outcome") in ("ended",) or ac in ("end", "terminal"):
        t = e.get("occurredAtMs") or e.get("tsMs") or e.get("atMs") or 0
        ts = datetime.datetime.utcfromtimestamp(t / 1000).strftime("%H:%M:%S") if t else "?"
        print(ts, e.get("platform") or e.get("source"), e.get("role"), st, ac, e.get("outcome"), "transport=%s" % v.get("transport"),
              "pair=%s" % v.get("pairRelayInvolvement"), "verified=%s" % v.get("mediaFlowVerified"), "reason=%s" % (e.get("reason") or v.get("endReason")))
    keys.update(e.keys())
print("event keys:", sorted(keys))
PY
done
