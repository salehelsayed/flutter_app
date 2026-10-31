#!/bin/bash
# Read-only: summarize Astra's per-catalog-id test refs (ids, boundary/group, runner, platforms).
#   host-run bash docker-ws/astra_p0_refs_summary.sh
F=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030/.codex-test-logs/p0-inventory-20261030/per-catalog-id-test-refs.json
python3 -I - "$F" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
print(type(j).__name__, list(j)[:8] if isinstance(j,dict) else len(j))
items=j if isinstance(j,list) else (j.get('ids') or j.get('items') or j.get('catalog_ids') or j)
if isinstance(items,dict): items=[dict(id=k,**v) if isinstance(v,dict) else {'id':k,'v':v} for k,v in items.items()]
print('n=',len(items)); print('keys=',sorted({k for i in items for k in i})[:30])
for i in items[:3]: print(json.dumps(i)[:700])
PY
