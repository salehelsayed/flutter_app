"""Read-only: per-root overview. usage: alltests_root.py <label>..."""
import json, sys, pathlib, re, os
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
BAD = re.compile(r'run-env|private|secret|token|credential', re.I)
def s(v, m=350): return (v if isinstance(v, str) else json.dumps(v))[:m]
for label in sys.argv[1:]:
    d = run/label; print(f'########## {label}')
    if not d.exists(): print('MISSING'); continue
    files = []
    for root, dirs, fs in os.walk(d):
        rel = pathlib.Path(root).relative_to(d)
        if 'derived' in rel.parts or 'DerivedData' in rel.parts: dirs[:] = []; continue
        if len(rel.parts) >= 3: dirs[:] = []
        for f in fs:
            if not BAD.search(f): files.append((str(rel/f), (pathlib.Path(root)/f).stat().st_size))
    print('files(%d):' % len(files), '; '.join(f'{p}={n}' for p, n in sorted(files)[:40])[:1800])
    sm = d/'summary.txt'
    if sm.exists():
        for l in sm.read_text(errors='replace').splitlines():
            if not l.startswith('NOT RUN') and not l.startswith('Gap:'): print('  S|', l[:300])
    for fn in ('results.json', 'partial.json'):
        f = d/fn
        if not f.exists(): continue
        try: data = json.loads(f.read_text())
        except Exception as e: print(fn, 'unreadable', e); continue
        print(f'  [{fn}] status={data.get("status")} automated={data.get("automated_status")}')
        for r in data.get('results') or []:
            if r.get('checkpoint') == 'diagnostic_subset': continue
            print(f'  ROW {r.get("id")} {r.get("status")} {r.get("checkpoint")} exec={r.get("execution_seconds")}')
            for k in ('reason', 'failure', 'blocker', 'detail', 'summary', 'message', 'error'):
                if r.get(k): print(f'    {k}: {s(r[k], 600)}')
            for p in r.get('preflight') or []:
                if p.get('status') != 'PASS' or True:
                    obs = [o for o in p.get('observations', []) if o.get('exit_status') not in (0,) or o.get('state') not in ('idle','ready', None)]
                    print(f'    preflight {p.get("status")} {p.get("checkpoint")} {s({k:v for k,v in p.items() if k!="observations"}, 500)} badobs={s(obs, 700)}')
            for a in r.get('attempts') or []:
                print('    attempt', s({k: v for k, v in a.items() if k not in ('capability_results', 'step_results', 'builds', 'schedule', 'route_results')}, 700))
                for c in a.get('capability_results') or []: print('     cap', s(c, 300))
                for c in a.get('step_results') or []:
                    print('     step', s(c, 400))
                for c in a.get('route_results') or []: print('     route', s(c, 300))
        break
    wl = run/(label + '.wrapper.log')
    if wl.exists():
        print('  wrapper.log tail:')
        for x in wl.read_text(errors='replace').splitlines()[-6:]: print('   W|', x[:300])
