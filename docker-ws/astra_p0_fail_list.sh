#!/bin/bash
# Read-only: print the failing/skipped/stalled test entries from Astra's P0 batch reports.
#   host-run bash docker-ws/astra_p0_fail_list.sh
D=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030/.codex-test-logs/p0-inventory-20261030
cd "$D" || exit 2
python3 -I - <<'PY'
import json,glob
for f in sorted(glob.glob('*-batch-report.json'))+['callback-unresolved-stall.json']:
    try: j=json.load(open(f))
    except Exception as e: print(f,'ERR',e); continue
    print('==',f, 'keys=',list(j)[:12] if isinstance(j,dict) else type(j).__name__)
    def walk(o,p=''):
        if isinstance(o,dict):
            st=str(o.get('status',o.get('result',o.get('verdict','')))).upper()
            if any(k in st for k in ('FAIL','SKIP','STALL','TIMEOUT','ERROR')):
                print('  ',p, {k:(str(v)[:220]) for k,v in o.items() if k in ('file','test','name','status','result','verdict','exit','reason','error','message','log','duration','stalled_at','last_line')})
            for k,v in o.items(): walk(v,p+'/'+str(k))
        elif isinstance(o,list):
            for i,v in enumerate(o): walk(v,p+f'[{i}]')
    walk(j)
    if f.startswith('callback'): print(json.dumps(j,indent=1)[:2500])
PY
