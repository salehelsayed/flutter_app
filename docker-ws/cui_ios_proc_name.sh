#!/bin/bash
# Read-only: name of one process on the Codex-UI iPhone 11.  host-run bash docker-ws/cui_ios_proc_name.sh <pid> <out-in-repo>
set -u
cd "$(dirname "$0")/.."
PID="${1:?pid}"; OUT="${2:?out}"
perl -e 'alarm 60; exec @ARGV' xcrun devicectl device info processes --device 00008030-001A6D2801BB802E --json-output "$OUT.json" >/dev/null 2>&1
echo "rc=$?"
python3 - "$OUT.json" "$PID" <<'PY'
import json,sys,os
d=json.load(open(sys.argv[1])); pid=int(sys.argv[2])
for p in d.get("result",{}).get("runningProcesses",[]):
    if p.get("processIdentifier")==pid: print("pid",pid,os.path.basename(p.get("executable","")))
print("total",len(d.get("result",{}).get("runningProcesses",[])))
PY
rm -f "$OUT.json"
