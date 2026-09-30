#!/bin/bash
# Read-only: activity timeline + attachment export for one test in an xcresult under the run root.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run; x="$run/$1"; tid="$2"; out=/Volumes/CrucialX9/flutter_app/docker-ws/.run_handover_copy/xcatt
xcrun xcresulttool get test-results activities --path "$x" --test-id "$tid" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
def walk(a,depth=0):
  for x in a:
    print("  "*depth + str(x.get("startTime",""))[:14], x.get("title","")[:200], "[att:%d]"%len(x.get("attachments",[])) if x.get("attachments") else "")
    walk(x.get("childActivities",[]),depth+1)
for r in d.get("testRuns",[]): walk(r.get("activities",[]))
'
rm -rf "$out"; mkdir -p "$out"; xcrun xcresulttool export attachments --path "$x" --output-path "$out" >/dev/null 2>&1; ls "$out" | head
