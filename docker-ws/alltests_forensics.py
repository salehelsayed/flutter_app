"""Read-only forensics: alltests_forensics.py <mode> args
modes: tree <label> [depth] | json <label> [maxchars] | tail <relpath> [n] [grep] | report [n]"""
import json, sys, pathlib, re, os
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
BAD = re.compile(r'run-env|private|secret|token|credential', re.I)
mode = sys.argv[1]
if mode == 'tree':
    d = run / sys.argv[2]; depth = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    n = 0
    for root, dirs, files in os.walk(d):
        rel = pathlib.Path(root).relative_to(d)
        if len(rel.parts) >= depth: dirs[:] = []
        for f in sorted(files):
            p = pathlib.Path(root) / f
            if BAD.search(f): continue
            n += 1
            if n > int(os.environ.get('MAXF', '80')): break
            print(f'{str(rel/f)[:160]}  {p.stat().st_size}')
    print('files listed', n)
elif mode == 'json':
    f = run / sys.argv[2]; mx = int(sys.argv[3]) if len(sys.argv) > 3 else 6000
    print(f.read_text(errors='replace')[:mx])
elif mode == 'tail':
    f = run / sys.argv[2]; n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
    if BAD.search(f.name): sys.exit('refused')
    lines = f.read_text(errors='replace').splitlines()
    if len(sys.argv) > 4:
        rx = re.compile(sys.argv[4], re.I); lines = [l for l in lines if rx.search(l)]
    for l in lines[-n:]: print(l[:int(sys.argv[5]) if len(sys.argv) > 5 else 400])
elif mode == 'report':
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    for l in (run/'failure-report.md').read_text(errors='replace').splitlines()[-n:]: print(l[:500])
elif mode == 'ls':
    for p in sorted(run.iterdir()):
        if BAD.search(p.name): continue
        print(p.name, p.stat().st_size if p.is_file() else '/')
