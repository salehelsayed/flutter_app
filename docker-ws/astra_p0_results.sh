#!/bin/bash
# Read-only: summarize every result.json under Astra's P0 evidence (pass/fail/skip counts and failing test names).
#   host-run bash docker-ws/astra_p0_results.sh
D=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030/.codex-test-logs
cd "$D" || exit 2
python3 -I - <<'PY'
import json,glob,os
fs=sorted(glob.glob('p0-*/**/result*.json',recursive=True)+glob.glob('p0-*/**/*summary*.json',recursive=True), key=os.path.getmtime)
for f in fs:
    try: j=json.load(open(f))
    except Exception as e: continue
    if not isinstance(j,dict): continue
    keys={k:j[k] for k in j if k in ('passed','failed','skipped','total','exit','exit_code','status','files','file','test_file') and not isinstance(j[k],(list,dict))}
    fails=[]
    for k in ('failures','failed_tests','failing','fail'):
        if isinstance(j.get(k),list): fails=j[k]
    print(f, keys, [str(x)[:200] for x in fails][:6])
PY
