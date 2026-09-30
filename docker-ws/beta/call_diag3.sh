#!/bin/bash
/usr/bin/python3 - <<'PY'
import json,datetime
raw=open('/tmp/beta_call_diag.json').read(); d=json.loads(raw[raw.find('{'):])
for e in d["events"]:
    t=datetime.datetime.utcfromtimestamp(e["occurredAtMs"]/1000)
    if not (datetime.datetime(2026,9,25,20,27,15) <= t <= datetime.datetime(2026,9,25,20,27,45)): continue
    if e.get("stage") in ("authority","preflight"): continue
    extra={k:v for k,v in e.items() if k not in ("schemaVersion","eventId","runId","sequence","occurredAtMs","elapsedMs","stage","action","source","role")}
    print(t.strftime("%H:%M:%S.%f")[:12], e.get("source"), e.get("stage"), e.get("action"), json.dumps(extra)[:170])
PY
