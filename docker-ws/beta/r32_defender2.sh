#!/bin/bash
# Read-only: latest Defender scans and which processes trigger the most real-time scans.
M=/usr/local/bin/mdatp
$M scan list 2>&1 | tail -16
echo "--- real-time protection statistics (top processes by scanned files):"
T=$(mktemp); $M diagnostic real-time-protection-statistics --output json > "$T" 2>&1
/usr/bin/python3 - "$T" <<'PY'
import json,sys
raw=open(sys.argv[1]).read()
try: d=json.loads(raw)
except Exception: print(raw[:600]); sys.exit()
c=d.get("counters",d)
rows=[(x.get("totalFilesScanned",0),x.get("maxFileScanTime",0),x.get("path") or x.get("name")) for x in c] if isinstance(c,list) else []
for n,t,p in sorted(rows,reverse=True)[:12]: print(n, t, p)
PY
