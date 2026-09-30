#!/bin/bash
# Read-only: last activities + failure summary for the newest p269 xcresult in the worktree.
x=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-1790428419151456-41019/p269-ios.xcresult
xcrun xcresulttool get test-results summary --path "$x" 2>&1 | head -c 1500; echo
tid=$(xcrun xcresulttool get test-results tests --path "$x" 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin)
def w(n):
  for c in n:
    if c.get("nodeType")=="Test Case": print(c.get("nodeIdentifier")); return True
    if w(c.get("children",[])): return True
w(d.get("testNodes",[]))')
echo "tid=$tid"
xcrun xcresulttool get test-results activities --path "$x" --test-id "$tid" 2>&1 | python3 -c '
import json,sys
d=json.load(sys.stdin)
out=[]
def walk(a,depth=0):
  for x in a:
    out.append("  "*depth + str(x.get("startTime",""))[:14]+" "+x.get("title","")[:220]+(" [att:%s]"%",".join(t.get("name","") for t in x.get("attachments",[])) if x.get("attachments") else ""))
    walk(x.get("childActivities",[]),depth+1)
for r in d.get("testRuns",[]): walk(r.get("activities",[]))
print("\n".join([l for l in out if not l.strip().split(" ",1)[-1].startswith(("Checking","Capturing"))][-40:]))
'
