#!/bin/bash
# Read-only v6 (adversarial refuter): resolve GNU LongLink names and compare the
# FULL member sequences (name, size, mtime, uid, gid) of:
#   A = CZjnKQ backup private-data.tar (first campaign capture, diag4 baseline)
#   B = /tmp/device_verify.tar (diag4 on-device re-cut, 07:46Z)
#   C = newest backup (4CATff) if different
# Decide: same name SET reordered vs different SET vs metadata-only drift.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag6_315_result.txt"
T='/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T'

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
  ls -ld "$T"/mknoon-group-reaction-notification-state-* 2>/dev/null
  A="$T/mknoon-group-reaction-notification-state-CZjnKQ/21071FDF600CSC/private-data.tar"
  B="/tmp/device_verify.tar"
  C=$(ls -td "$T"/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)/21071FDF600CSC/private-data.tar
  for f in "$A" "$B" "$C"; do ls -la "$f" 2>/dev/null || echo "missing: $f"; done
  python3 - "$A" "$B" "$C" <<'EOF'
import sys, hashlib

def members(path):
    try:
        data = open(path,'rb').read()
    except FileNotFoundError:
        return None
    out = []
    off = 0; n = len(data); pending_long = None
    while off + 512 <= n:
        h = data[off:off+512]
        if h == b'\x00'*512:
            off += 512; continue
        name = h[0:100].split(b'\x00')[0].decode(errors='replace')
        typ = chr(h[156])
        size = int((h[124:136].split(b'\x00')[0].strip() or b'0'), 8)
        mtime = int((h[136:148].split(b'\x00')[0].strip() or b'0'), 8)
        uid = (h[108:116].split(b'\x00')[0].strip() or b'0').decode()
        gid = (h[116:124].split(b'\x00')[0].strip() or b'0').decode()
        mode = (h[100:108].split(b'\x00')[0].strip() or b'0').decode()
        payload = data[off+512: off+512+size]
        if typ == 'L':
            pending_long = payload.rstrip(b'\x00').decode(errors='replace')
        else:
            full = pending_long if pending_long else name
            pending_long = None
            csum = hashlib.sha256(payload).hexdigest()[:12] if typ == '0' else '-'
            out.append((full, typ, size, mtime, uid, gid, mode, csum))
        off += 512 + (size+511)//512*512
    return out

labels = ['A=CZjnKQ-backup','B=device-recut-0746Z','C=newest-backup']
tars = {}
for lab, p in zip(labels, sys.argv[1:4]):
    m = members(p)
    tars[lab] = m
    print(f'{lab}: {"MISSING" if m is None else str(len(m))+" real members"} path={p}')

def compare(la, lb):
    a, b = tars[la], tars[lb]
    if a is None or b is None:
        print(f'--- {la} vs {lb}: skipped (missing) ---'); return
    print(f'--- {la} vs {lb} ---')
    na = [m[0] for m in a]; nb = [m[0] for m in b]
    print('  name SEQUENCE identical:', na == nb)
    print('  name MULTISET identical:', sorted(na) == sorted(nb))
    only_a = sorted(set(na)-set(nb)); only_b = sorted(set(nb)-set(na))
    print('  names only in', la, ':', len(only_a), only_a[:4])
    print('  names only in', lb, ':', len(only_b), only_b[:4])
    da = {m[0]: m for m in a}; db = {m[0]: m for m in b}
    shared = [nm for nm in na if nm in db]
    size_diff = [(nm, da[nm][2], db[nm][2]) for nm in shared if da[nm][2] != db[nm][2]]
    mtime_diff = [(nm, da[nm][3], db[nm][3]) for nm in shared if da[nm][3] != db[nm][3]]
    ug_diff = [(nm, da[nm][4:7], db[nm][4:7]) for nm in shared if da[nm][4:7] != db[nm][4:7]]
    content_diff = [(nm, da[nm][7], db[nm][7]) for nm in shared if da[nm][7] != db[nm][7]]
    print('  shared-name SIZE diffs:', len(size_diff), size_diff[:6])
    print('  shared-name MTIME diffs:', len(mtime_diff), mtime_diff[:6])
    print('  shared-name uid/gid/mode diffs:', len(ug_diff), ug_diff[:4])
    print('  shared-name CONTENT diffs:', len(content_diff), content_diff[:6])
    if na != nb and sorted(na) == sorted(nb):
        for i,(x,y) in enumerate(zip(na,nb)):
            if x != y:
                print(f'  first ORDER divergence at member {i}: {la}={x[-60:]} | {lb}={y[-60:]}')
                break

compare('A=CZjnKQ-backup','B=device-recut-0746Z')
compare('A=CZjnKQ-backup','C=newest-backup')
compare('B=device-recut-0746Z','C=newest-backup')
EOF
} > "$OUT" 2>&1

echo "wrote $OUT"
