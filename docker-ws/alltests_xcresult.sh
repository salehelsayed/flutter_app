#!/bin/bash
# Read-only: failure summaries from xcresult bundles found under a run-root label.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
for label in "$@"; do
  find "$run/$label" -name '*.xcresult' -maxdepth 6 2>/dev/null | while read -r x; do
    echo "== ${x#$run/} =="
    xcrun xcresulttool get test-results summary --path "$x" 2>&1 | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception as e: print("unparsable",e); sys.exit()
print("result",d.get("result"),"pass",d.get("passedTests"),"fail",d.get("failedTests"),"skip",d.get("skippedTests"))
for f in d.get("testFailures",[]): print(" FAIL",f.get("testIdentifierString") or f.get("testName"),"|",(f.get("failureText") or "")[:400])
' 
  done
done
