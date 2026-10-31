#!/bin/bash
# Read-only: list the phone-step (non host_source) boundaries from Astra's per-catalog-id refs, grouped by boundary.
#   host-run bash docker-ws/astra_p0_phone_boundaries.sh
F=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030/.codex-test-logs/p0-inventory-20261030/per-catalog-id-test-refs.json
python3 -I - "$F" <<'PY'
import json,sys,collections
j=json.load(open(sys.argv[1]))['ids']
b=collections.OrderedDict(); ids_phone=set()
for cid,refs in j.items():
    for r in refs:
        if r.get('source_classification')=='host_source': continue
        k=r['boundary_key']; e=b.setdefault(k,{'ids':set(),'path':r['path'],'cls':r['source_classification'],'disp':r.get('runtime_disposition')})
        e['ids'].update(r.get('ids',[cid])); ids_phone.add(cid)
print('phone ids',len(ids_phone),'boundaries',len(b))
for k,e in b.items(): print(f"{k} | {e['path'].split('/')[-1]} | {e['cls']} | {','.join(sorted(e['ids']))}")
PY
