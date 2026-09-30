"""Read-only: mtimes (UTC) and partial.json non-trivial rows. usage: <label>..."""
import json, sys, pathlib, datetime, re, os
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
def t(p): return datetime.datetime.utcfromtimestamp(p.stat().st_mtime).strftime('%m-%dT%H:%M:%S')
for label in sys.argv[1:]:
    d = run/label; wl = run/(label + '.wrapper.log')
    ms = []
    for root, dirs, fs in os.walk(d):
        if 'derived' in root: dirs[:] = []; continue
        for f in fs: ms.append((pathlib.Path(root)/f).stat().st_mtime)
    ct = min((x for x in ms), default=0); mt = max(ms, default=0)
    fmt = lambda x: datetime.datetime.utcfromtimestamp(x).strftime('%m-%dT%H:%M:%S') if x else '-'
    print(f'{label}: files {fmt(ct)}..{fmt(mt)} wrapper={t(wl) if wl.exists() else "-"}')
    p = d/'partial.json'
    if p.exists():
        data = json.loads(p.read_text())
        print('   partial keys', [k for k in data if k not in ('results', 'plan', 'obligations', 'not_selected')][:20], 'status', data.get('status'))
        for r in data.get('results') or []:
            if r.get('checkpoint') == 'diagnostic_subset' or (r.get('status') == 'NOT RUN' and not r.get('attempts')): continue
            print('   ROW', json.dumps({k: v for k, v in r.items() if k not in ('command', 'selected_paths', 'investigate')})[:1500])
