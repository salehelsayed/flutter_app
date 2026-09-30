"""Read-only: regex search in worktree proof files. usage: <regex> <relpath-under-proofs> [maxhits] [width] [skip]"""
import sys, pathlib, re
base = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs')
BAD = re.compile(r'run-env|private|secret|credential', re.I)
rx = re.compile(sys.argv[1]); mh = int(sys.argv[3]) if len(sys.argv) > 3 else 40; w = int(sys.argv[4]) if len(sys.argv) > 4 else 260
skip = int(sys.argv[5]) if len(sys.argv) > 5 else 0
n = 0; k = 0
for f in sorted(base.glob(sys.argv[2])):
    if not f.is_file() or BAD.search(str(f.relative_to(base))): continue
    for i, l in enumerate(f.read_text(errors='replace').splitlines(), 1):
        m = rx.search(l)
        if m:
            k += 1
            if k <= skip: continue
            print(f'{f.name}:{i}: {l[:w]}'); n += 1
            if n >= mh: sys.exit()
print('hits', n, 'total_seen', k)
