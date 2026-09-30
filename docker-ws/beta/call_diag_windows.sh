#!/bin/bash
# Read-only: pull the Pixel app's native call diagnostics (debug build, run-as)
# into the beta folder and print the events inside the given UTC windows.
# Usage: call_diag_windows.sh "HH:MM:SS-HH:MM:SS" ["HH:MM:SS-HH:MM:SS" ...]
. "$(dirname "$0")/beta_env.sh"
OUT="$BETA/diag"; mkdir -p "$OUT"
F="$OUT/call_diag_$(date '+%Y%m%d-%H%M%S').json"
$ADB shell "run-as $PKG cat files/call_diagnostics/state.json" > "$F" 2>&1
echo "saved $F ($(wc -c < "$F") bytes)"
/usr/bin/python3 - "$F" "$@" <<'PY'
import json, sys, datetime
path, windows = sys.argv[1], sys.argv[2:]
raw = open(path).read()
d = json.loads(raw[raw.find('{'):])
events = d.get("events") or []
print("events:", len(events))
def utc(ms): return datetime.datetime.utcfromtimestamp(ms / 1000)
for w in windows:
    a, b = w.split("-")
    print(f"===== {a} - {b} UTC")
    for e in events:
        t = utc(e["occurredAtMs"]).strftime("%H:%M:%S.%f")[:12]
        if not (a <= t[:8] <= b): continue
        extra = {k: v for k, v in e.items() if k not in (
            "schemaVersion", "eventId", "runId", "sequence", "occurredAtMs",
            "elapsedMs", "stage", "action", "source", "role")}
        print(t, e.get("source"), e.get("stage"), e.get("action"), json.dumps(extra)[:230])
PY
