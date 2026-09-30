"""Read-only: tail/grep a file under the all-tests worktree. usage: <relpath> [n] [regex] [width]"""
import sys, pathlib, re
wt = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree')
BAD = re.compile(r'run-env|private|secret|token|credential', re.I)
f = wt/sys.argv[1]
if BAD.search(f.name): sys.exit('refused')
n = int(sys.argv[2]) if len(sys.argv) > 2 else 40; w = int(sys.argv[4]) if len(sys.argv) > 4 else 400
rx = re.compile(sys.argv[3], re.I) if len(sys.argv) > 3 and sys.argv[3] != '.' else None
out = []
with open(f, errors='replace') as fh:
    for l in fh:
        if rx is None or rx.search(l):
            out.append(l.rstrip('\n'))
            if len(out) > n: out.pop(0)
for l in out: print(l[:w])
