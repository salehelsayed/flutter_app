"""Read-only: first N matches (with following context lines) in a worktree file. usage: <relpath> <regex> [n] [after] [width]"""
import sys, pathlib, re
wt = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree')
f = wt/sys.argv[1]; rx = re.compile(sys.argv[2]); n = int(sys.argv[3]) if len(sys.argv) > 3 else 3
after = int(sys.argv[4]) if len(sys.argv) > 4 else 10; w = int(sys.argv[5]) if len(sys.argv) > 5 else 300
left = 0; hits = 0
with open(f, errors='replace') as fh:
    for i, l in enumerate(fh, 1):
        if left > 0: print(f'   {i}: {l.rstrip()[:w]}'); left -= 1; continue
        if hits < n and rx.search(l):
            print(f'>> {i}: {l.rstrip()[:w]}'); hits += 1; left = after
        elif hits >= n and left == 0: break
