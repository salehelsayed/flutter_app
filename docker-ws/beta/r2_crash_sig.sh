#!/bin/bash
# Read-only: exception + top 3 frames of the faulting thread for every Runner/SpringBoard
# report from today, then relaunch the iPhone app.
. "$(dirname "$0")/beta_env.sh"
for F in $(ls -t ~/Library/Logs/DiagnosticReports/Runner-2026-09-2[67]-*.ips ~/Library/Logs/DiagnosticReports/SpringBoard-2026-09-27-*.ips 2>/dev/null | head -8); do
/usr/bin/python3 - "$F" <<'PY'
import json, sys, os
raw = open(sys.argv[1]).read(); head, body = raw.split('\n', 1)
h = json.loads(head); b = json.loads(body); imgs = b.get("usedImages", [])
th = b["threads"][b.get("faultingThread", 0)]
fr = [ (imgs[f["imageIndex"]]["name"] if f.get("imageIndex") is not None and f["imageIndex"] < len(imgs) else "?") + ":" + f.get("symbol","?")[:70] for f in th.get("frames", [])[:3]]
print(os.path.basename(sys.argv[1]), h.get("app_version"), b.get("exception",{}).get("type"), b.get("exception",{}).get("signal"), "|", " <- ".join(fr))
PY
done
xcrun simctl launch "$UDID" "$BUNDLE" && echo relaunched
