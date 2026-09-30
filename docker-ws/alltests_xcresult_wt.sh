#!/bin/bash
# Read-only: failure summaries of the newest xcresult bundles under a worktree proofs capability dir.
d="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/$1"
find "$d" -name '*.xcresult' -maxdepth 4 -newermt "${2:-2026-09-26 14:00}" 2>/dev/null | while read -r x; do
  echo "== ${x#$d/}"
  xcrun xcresulttool get test-results summary --path "$x" 2>&1 | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception as e: print("unparsable",e); sys.exit()
print("result",d.get("result"),"pass",d.get("passedTests"),"fail",d.get("failedTests"))
for f in d.get("testFailures",[]): print(" FAIL",f.get("testIdentifierString"),"|",(f.get("failureText") or "")[:400])
'
done
