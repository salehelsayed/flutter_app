#!/bin/bash
# Read-only: newest Runner crash report(s) on this Mac, with the crashed thread's top frames.
D=~/Library/Logs/DiagnosticReports
echo "now $(date '+%H:%M:%S')"
ls -lt "$D" 2>/dev/null | head -8
F=$(ls -t "$D"/Runner-*.ips 2>/dev/null | head -1)
echo "=== newest: $F"
[ -n "$F" ] || exit 0
OUT=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260927/crash; mkdir -p "$OUT"; cp "$F" "$OUT/" 2>/dev/null
/usr/bin/python3 - "$F" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
head, body = raw.split('\n', 1)
h = json.loads(head); b = json.loads(body)
print("app:", h.get("app_name"), h.get("app_version"), h.get("build_version"), "captured:", h.get("timestamp"))
ex = b.get("exception", {}); print("exception:", ex, "termination:", b.get("termination", {}).get("indicator"))
print("faultingThread:", b.get("faultingThread"))
imgs = b.get("usedImages", [])
th = b["threads"][b.get("faultingThread", 0)]
print("thread name:", th.get("name"), "queue:", th.get("queue"))
for fr in th.get("frames", [])[:25]:
    img = imgs[fr["imageIndex"]]["name"] if fr.get("imageIndex") is not None and fr["imageIndex"] < len(imgs) else "?"
    print(f'  {img:28s} {fr.get("symbol","?")} +{fr.get("symbolLocation","")}')
PY
