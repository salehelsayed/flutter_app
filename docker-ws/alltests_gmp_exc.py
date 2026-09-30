"""Read-only: per scenario dir since 02:39, per role log, print first exception message + first 2 harness frames, and count of SELF_REMOVED_COMMIT_FAILED."""
import pathlib, re, datetime
t = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp')
cut = datetime.datetime(2026, 9, 26, 2, 39).timestamp()
ds = sorted([d for d in t.glob('group_multi_party_*') if d.is_dir() and d.stat().st_mtime > cut], key=lambda d: d.stat().st_mtime)
for d in ds:
    out = []
    for f in sorted(d.glob('*.log')):
        if 'run-env' in f.name or 'private' in f.name: continue
        lines = f.read_text(errors='replace').splitlines()
        cf = sum('SELF_REMOVED_COMMIT_FAILED' in l for l in lines)
        idx = next((i for i, l in enumerate(lines) if 'EXCEPTION CAUGHT BY FLUTTER TEST' in l), None)
        if idx is None:
            if cf: out.append(f'  {f.name}: no-exc commitFailed={cf}')
            continue
        msg = ' | '.join(l.replace('flutter: ', '')[:150] for l in lines[idx+1:idx+3])
        frames = [re.sub(r'\(file://.*/integration_test/', '(', l.replace('flutter: ', ''))[:120] for l in lines[idx+3:idx+40] if re.match(r'(flutter: )?#[1-3] ', l)][:3]
        out.append(f'  {f.name}: commitFailed={cf} :: {msg} :: ' + ' / '.join(frames))
    if out:
        print(d.name[18:]); print('\n'.join(out))
