#!/bin/bash
# Run integration_test/scripts/turn_path_probe.py on the Mac (it has IPv6; the container
# does not). Credentials come from the production relay via the app's own request code
# (artifacts/beta-20260925/turnprobe/turncredclient-darwin, disposable identity).
# Usage: turn_probe_mac.sh <server> <port> <control-family> <allocation-family> <udp|tcp|tls> [hostname]
set -u
SRC=/Volumes/CrucialX9/flutter_app
D="$SRC/artifacts/beta-20260925/turnprobe"
OUT="$D/out_$(date +%H%M%S)_c$3_a$4_$5"
EXTRA=(); [ -n "${6:-}" ] && EXTRA=(--hostname "$6")
cd "$D" || exit 2
xattr -d com.apple.quarantine turncredclient-darwin 2>/dev/null
timeout 240 /usr/bin/python3 "$SRC/integration_test/scripts/turn_path_probe.py" --server "$1" --port "$2" \
  --control-family "$3" --allocation-family "$4" --transport "$5" ${EXTRA[@]+"${EXTRA[@]}"} \
  --credential-command ./turncredclient-darwin --trials 1 --output "$OUT" 2>&1 | tail -2 \
  | /usr/bin/python3 -c 'import sys, json
for l in sys.stdin:
    try:
        d = json.loads(l)
        print({k: d.get(k) for k in ("transport", "connectionFamily", "actualAllocationFamilies", "hostnameVerified", "status", "failedStage")},
              [(e["sent"], e["received"]) for e in d.get("endpoints", [])])
    except Exception:
        print(l.strip()[:300])'
