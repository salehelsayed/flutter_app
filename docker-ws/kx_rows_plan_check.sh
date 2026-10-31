#!/bin/bash
# Plan-only check of kx_only_checks.py: prints the device-audio command it would run. Host-side.
#   host-run bash docker-ws/kx_rows_plan_check.sh <tree under build/> <kx-csv> <evidence-dir> <device-config>
M=/Volumes/CrucialX9/flutter_app; W=$M/build/$1; export KX_KEEP="$2"; EV="$M/$3"; CFG="$M/$4"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$W" || exit 2; OUT="$EV/kxplan-$(date -u +%H%M%S)"
python3 "$M/docker-ws/kx_only_checks.py" plan --mode change --base a7508ab52c56fcc32a6c870d0222fc8f4f12fcde --local \
  --only device-audio --device-config "$CFG" --output "$OUT" > "$OUT.txt" 2>&1; echo "rc=$?"
python3 -c 'import json,sys;p=json.load(open(sys.argv[1]));[print(c["id"]," ".join(c.get("command",[]))[-700:]) for c in p.get("selected",p.get("checks",[])) if c.get("id")=="device-audio"]' "$OUT/plan.json" 2>&1 | tail -3
tail -3 "$OUT.txt"
