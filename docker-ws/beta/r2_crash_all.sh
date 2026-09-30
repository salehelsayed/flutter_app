#!/bin/bash
# Read-only: every Runner crash report since 2026-09-24 (signature line each), copies them into
# artifacts/beta-20260927/crash/, and prints the full faulting thread of the ones named in $@.
OUT=/Volumes/CrucialX9/flutter_app/artifacts/beta-20260927/crash; mkdir -p "$OUT"
for F in $(ls -t ~/Library/Logs/DiagnosticReports/Runner-2026-09-2[4-7]-*.ips 2>/dev/null); do
  cp "$F" "$OUT/" 2>/dev/null
  /usr/bin/python3 - "$F" "$@" <<'PY'
import json, sys, os
raw = open(sys.argv[1]).read(); head, body = raw.split('\n', 1)
h = json.loads(head); b = json.loads(body); imgs = b.get("usedImages", [])
def nm(f):
    i = f.get("imageIndex")
    return (imgs[i].get("name") or imgs[i].get("path","?").split("/")[-1]) if i is not None and i < len(imgs) else "?"
ft = b.get("faultingThread", 0); th = b["threads"][ft]
base = os.path.basename(sys.argv[1])
fr = [nm(f) + ":" + f.get("symbol", "?")[:60] for f in th.get("frames", [])[:3]]
print(base, h.get("app_version"), b.get("exception", {}).get("type"), b.get("exception", {}).get("signal"), "|", " <- ".join(fr))
if base in sys.argv[2:]:
    print("   thread", ft, th.get("name"), th.get("queue"))
    for f in th.get("frames", [])[:30]:
        print("     ", nm(f).ljust(26), f.get("symbol", "?")[:110], "+", f.get("symbolLocation", ""))
    asi = b.get("asi"); 
    if asi: print("   asi:", json.dumps(asi)[:600])
    print("   procLaunch:", b.get("procLaunch"), "captureTime:", b.get("captureTime"), "uptime:", b.get("uptime"))
PY
done
