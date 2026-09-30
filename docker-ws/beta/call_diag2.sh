#!/bin/bash
/usr/bin/python3 - <<'PY'
import json
raw=open('/tmp/beta_call_diag.json').read(); d=json.loads(raw[raw.find('{'):])
print("top keys:", list(d.keys())[:20])
# find the longest list of dict events
best=None
def find(o,path=""):
    global best
    if isinstance(o,list) and o and isinstance(o[0],dict):
        if best is None or len(o)>len(best[1]): best=(path,o)
    if isinstance(o,dict):
        for k,v in o.items(): find(v,path+"/"+k)
    elif isinstance(o,list):
        for i,v in enumerate(o[:3]): find(v,path+f"[{i}]")
find(d)
print("events at", best[0], len(best[1]))
for e in best[1][-14:]:
    print(json.dumps(e)[:260])
PY
