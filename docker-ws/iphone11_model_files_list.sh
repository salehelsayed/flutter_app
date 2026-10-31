#!/bin/bash
# Read-only: list files larger than 100 MB in the Mknoon app container on the iPhone 11 (path + exact bytes),
# print the JSON shape of one entry, and which AFC tools exist on the Mac.   host-run bash docker-ws/iphone11_model_files_list.sh
U=00008030-001A6D2801BB802E; J=/tmp/mk11_files_$$.json
timeout 180 xcrun devicectl device info files --device $U --domain-type appDataContainer --domain-identifier com.mknoon.app \
  --json-output "$J" >/dev/null 2>&1; echo "list exit=$?"
python3 - "$J" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
files = d.get("result", {}).get("files", [])
print("entries", len(files))
if files: print("keys", sorted(files[0].keys()))
if files: print("metadata keys", sorted((files[0].get("metadata") or {}).keys()))
def size(f):
    m = f.get("metadata") or {}
    for k in ("fileSize", "size", "byteCount", "length"):
        v = m.get(k, f.get(k))
        if isinstance(v, dict): v = v.get("value") or v.get("bytes")
        if isinstance(v, (int, float)): return int(v)
    return 0
big = sorted(((size(f), f.get("relativePath") or f.get("name") or str(f.get("url"))) for f in files), reverse=True)
for s, p in big[:8]: print(s, p)
for f in files:
    n = (f.get("relativePath") or "").lower()
    if "litert" in n or "gemma" in n or "model" in n: print("match", size(f), f.get("relativePath"))
PY
rm -f "$J"
echo "== tools"; for t in afcclient ifuse pymobiledevice3 idevicefs; do echo "$t: $(command -v $t || ls /opt/homebrew/bin/$t 2>/dev/null || echo none)"; done
