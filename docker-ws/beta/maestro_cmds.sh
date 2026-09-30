#!/bin/bash
# Read-only: Maestro command timeline (start time, duration, status, command) for one flow dir.
# Usage: maestro_cmds.sh <label_dev>   e.g. s10_netdrop_android
. "$(dirname "$0")/beta_env.sh"
/usr/bin/python3 - "$(current_run)/maestro/$1" <<'PY'
import json, os, sys, datetime
for root, _, files in os.walk(sys.argv[1]):
    for fn in files:
        if fn != "commands.json": continue
        print("===", os.path.relpath(os.path.join(root, fn), sys.argv[1]))
        def walk(cmds, depth=0):
            for c in cmds:
                m = c.get("metadata", {})
                t = m.get("timestamp")
                ts = datetime.datetime.fromtimestamp(t/1000).strftime("%H:%M:%S.%f")[:12] if t else "-"
                cmd = c.get("command", {})
                name = next(iter(cmd.keys()), "?")
                body = json.dumps(cmd.get(name, ""))[:100]
                print(ts, f'{(m.get("duration") or 0)/1000:6.1f}s', m.get("status", "?"), "  "*depth + name, body)
        walk(json.load(open(os.path.join(root, fn))))
PY
