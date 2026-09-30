"""Read-only. usage: ls <root> <glob> [max] | grep <root> <regex> <glob> [maxhits] [width] | sed <root> <relpath> <start> <end> [width]"""
import sys, pathlib, re
roots = {'run': '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run', 'wt': '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree', 'main': '/Volumes/CrucialX9/flutter_app'}
BAD = re.compile(r'run-env|private|secret|credential', re.I)
m = sys.argv[1]; r = pathlib.Path(roots[sys.argv[2]])
if m == 'ls':
    mx = int(sys.argv[4]) if len(sys.argv) > 4 else 60; n = 0
    for p in sorted(r.glob(sys.argv[3])):
        if BAD.search(p.name): continue
        st = p.stat(); print(p.relative_to(r), st.st_size); n += 1
        if n >= mx: break
    print('n', n)
elif m == 'grep':
    rx = re.compile(sys.argv[3]); mh = int(sys.argv[5]) if len(sys.argv) > 5 else 30; w = int(sys.argv[6]) if len(sys.argv) > 6 else 300; n = 0
    for f in sorted(r.glob(sys.argv[4])):
        if not f.is_file() or BAD.search(str(f.relative_to(r))) or f.stat().st_size > 80_000_000: continue
        try: text = f.read_text(errors='replace')
        except Exception: continue
        for i, l in enumerate(text.splitlines(), 1):
            mm = rx.search(l)
            if mm:
                s = max(0, mm.start() - w // 3); print(f'{f.relative_to(r)}:{i}: {l[s:s + w]}'); n += 1
                if n >= mh: sys.exit()
    print('hits', n)
elif m == 'sed':
    f = r / sys.argv[3]
    if BAD.search(str(f)): sys.exit('refused')
    a, b = int(sys.argv[4]), int(sys.argv[5]); w = int(sys.argv[6]) if len(sys.argv) > 6 else 400
    for i, l in enumerate(f.read_text(errors='replace').splitlines(), 1):
        if a <= i <= b: print(f'{i}: {l[:w]}')
        if i > b: break
