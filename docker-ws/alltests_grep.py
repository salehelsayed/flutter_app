"""Read-only: regex search in run-root files. usage: <regex> <relglob> [maxhits] [width]"""
import sys, pathlib, re
run = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run')
BAD = re.compile(r'run-env|private|secret|token|credential', re.I)
rx = re.compile(sys.argv[1]); mh = int(sys.argv[3]) if len(sys.argv) > 3 else 20; w = int(sys.argv[4]) if len(sys.argv) > 4 else 300
n = 0
for f in sorted(run.glob(sys.argv[2])):
    if not f.is_file() or BAD.search(str(f.relative_to(run))) or f.stat().st_size > 60_000_000: continue
    try: text = f.read_text(errors='replace')
    except Exception: continue
    for i, l in enumerate(text.splitlines(), 1):
        m = rx.search(l)
        if m:
            s = max(0, m.start() - w // 3)
            print(f'{f.relative_to(run)}:{i}: {l[s:s + w]}'); n += 1
            if n >= mh: sys.exit()
print('hits', n)
