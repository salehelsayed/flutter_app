#!/bin/bash
# Read-only: tail of the app's native call diagnostics (debug build, run-as).
. "$(dirname "$0")/beta_env.sh"
$ADB shell "run-as $PKG sh -c 'ls files/call_diagnostics/ 2>&1; cat files/call_diagnostics/state.json 2>/dev/null'" > /tmp/beta_call_diag.json
wc -c /tmp/beta_call_diag.json
/usr/bin/python3 - <<'PY'
import json,re
raw=open('/tmp/beta_call_diag.json').read()
i=raw.find('{'); 
try:
    d=json.loads(raw[i:])
except Exception as e:
    print("parse:",e); print(raw[:1500]); raise SystemExit
def walk(o):
    if isinstance(o,dict):
        for v in o.values(): yield from walk(v)
    elif isinstance(o,list):
        for v in o: yield from walk(v)
    else: yield o
lines=[s for s in walk(d) if isinstance(s,str) and re.search(r'20:2[6-8]|presentation|present |reject|refus|skew|expir',s)]
for s in lines[-25:]: print(s[:220])
PY
