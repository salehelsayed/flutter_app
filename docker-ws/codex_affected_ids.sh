#!/bin/bash
# Print the selected check IDs from Codex's affected-checks.json files under a given evidence dir (read-only).
#   host-run bash docker-ws/codex_affected_ids.sh <dir>
find "${1:?dir}" -maxdepth 3 -name 'affected-checks.json' -print 2>/dev/null | while read -r f; do
  echo "== $f"; python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));ids=d.get("selected_ids") or [x.get("id") for x in d.get("checks",d.get("selected",[])) if isinstance(x,dict)];print(" ".join(sorted(set(i for i in ids if i))))' "$f"
done
