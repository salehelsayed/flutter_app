"""Read-only: list paths matching a glob under run root or worktree. usage: <root: run|wt|main> <glob> [max]"""
import sys, pathlib, re
roots = {'run': '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run', 'wt': '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree', 'main': '/Volumes/CrucialX9/flutter_app'}
r = pathlib.Path(roots[sys.argv[1]]); mx = int(sys.argv[3]) if len(sys.argv) > 3 else 40
BAD = re.compile(r'run-env|private|secret|token|credential', re.I)
n = 0
for p in r.glob(sys.argv[2]):
    if BAD.search(p.name): continue
    st = p.stat(); print(p.relative_to(r), st.st_size, int(st.st_mtime)); n += 1
    if n >= mx: break
print('n', n)
