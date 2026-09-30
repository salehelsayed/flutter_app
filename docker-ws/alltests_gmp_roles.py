"""Read-only: list group multi-party scenario dirs newer than a cutoff and show role log files/sizes.
Usage: alltests_gmp_roles.py [list|tail <dir> <role> <n>|grep <dir> <role> <regex> <n>]"""
import sys, pathlib, time, re, datetime
t = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp')
cut = datetime.datetime(2026, 9, 26, 2, 39).timestamp()
bad = lambda n: 'run-env' in n or 'private' in n
mode = sys.argv[1] if len(sys.argv) > 1 else 'list'
if mode == 'list':
    ds = sorted([d for d in t.glob('group_multi_party_*') if d.is_dir() and d.stat().st_mtime > cut], key=lambda d: d.stat().st_mtime)
    for d in ds:
        fs = [f for f in d.iterdir() if f.is_file() and not bad(f.name)]
        print(time.strftime('%H:%M', time.localtime(d.stat().st_mtime)), d.name, ' '.join(f'{f.name}:{f.stat().st_size}' for f in sorted(fs) if f.suffix in ('.log', '.json'))[:400])
elif mode == 'tail':
    f = t / sys.argv[2] / sys.argv[3]
    if bad(f.name): sys.exit(2)
    for l in f.read_text(errors='replace').splitlines()[-int(sys.argv[4]):]: print(l[:300])
elif mode == 'grep':
    f = t / sys.argv[2] / sys.argv[3]
    if bad(f.name): sys.exit(2)
    rx = re.compile(sys.argv[4]); n = int(sys.argv[5]); k = 0
    for i, l in enumerate(f.read_text(errors='replace').splitlines(), 1):
        if rx.search(l):
            print(i, l[:300]); k += 1
            if k >= n: break
