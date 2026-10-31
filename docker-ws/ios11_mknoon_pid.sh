#!/bin/bash
# Read-only: is com.mknoon.app (not other Mknoon bundles) running on the iPhone 11. Prints bundle id + yes/no only.
U=00008030-001A6D2801BB802E; J=$(mktemp); P=$(mktemp)
timeout 90 /usr/bin/xcrun devicectl device info apps --device "$U" --json-output "$J" >/dev/null 2>&1
timeout 90 /usr/bin/xcrun devicectl device info processes --device "$U" --json-output "$P" >/dev/null 2>&1
python3 - "$J" "$P" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]; procs = json.load(open(sys.argv[2]))["result"]["runningProcesses"]
for a in apps:
    b = a.get("bundleIdentifier", "")
    if not b.startswith("com.mknoon") or "xctrunner" in b: continue
    url = a.get("url", "").rstrip("/")
    run = any(p.get("executable", "").startswith(url) for p in procs)
    print(b, "version", a.get("version"), "build", a.get("bundleVersion"), "running", "yes" if run else "no")
PY
