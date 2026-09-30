"""Read-only: summarize results.json / partial.json rows for all-tests artifact roots."""
import json, sys, pathlib
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
for label in sys.argv[1:]:
    d = run / label
    print(f'== {label} ==')
    if not d.exists(): print('  MISSING'); continue
    for name in ('results.json', 'partial.json'):
        f = d / name
        if not f.exists(): continue
        try: data = json.loads(f.read_text())
        except Exception as e: print(f'  {name}: unreadable {e}'); continue
        rows = data.get('results') or data.get('rows') or data.get('checks') or []
        print(f'  {name}: keys={list(data)[:12]} rows={len(rows)}')
        for r in rows if isinstance(rows, list) else []:
            if not isinstance(r, dict): continue
            if r.get('status')=='NOT RUN' and r.get('checkpoint')=='diagnostic_subset': continue
            print('     keys:', sorted(r)); print('     detail:', json.dumps({k:r[k] for k in r if k not in ('id','status','checkpoint','counts')})[:1500])
            print('   ', r.get('id'), r.get('status'), r.get('checkpoint'), json.dumps(r.get('counts'))[:80], (r.get('reason') or r.get('summary') or r.get('failure') or '')[:300] if isinstance(r.get('reason') or r.get('summary') or r.get('failure') or '', str) else '')
        break
    wl = run / (label + '.wrapper.log')
    if wl.exists():
        t = wl.read_text(errors='replace').splitlines()
        print('  wrapper.log tail:'); [print('    ' + x[:300]) for x in t[-8:]]
