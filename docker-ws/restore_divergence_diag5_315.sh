#!/bin/bash
# Read-only v5 (adversarial refuter): decode the tar block structure around the
# first divergent offset properly — check for GNU LongLink/pax headers, list the
# real member sequence with offsets in the skia region, and dump the true
# headers adjacent to offset 114725376 for BOTH the backup tar and the diag4
# device re-cut (if still present at /tmp/device_verify.tar).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag5_315_result.txt"
BK=$(ls -td /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') backup=$BK ==="
  TAR="$BK/21071FDF600CSC/private-data.tar"
  [ -f "$TAR" ] || { echo "FATAL: backup tar missing (backup dir gone?)"; ls -la "$BK" 2>/dev/null; exit 0; }
  ls -la /tmp/device_verify.tar 2>/dev/null || echo "note: /tmp/device_verify.tar absent"
  python3 - "$TAR" <<'EOF'
import sys, re
bak = open(sys.argv[1],'rb').read()
try:
    dev = open('/tmp/device_verify.tar','rb').read()
except FileNotFoundError:
    dev = None

def walk(data, label):
    print(f'--- member walk ({label}) around divergence ---')
    off = 0
    n = len(data)
    hits = []
    while off + 512 <= n:
        h = data[off:off+512]
        if h == b'\x00'*512:
            off += 512
            continue
        name = h[0:100].split(b'\x00')[0].decode(errors='replace')
        typeflag = chr(h[156])
        size_field = h[124:136].split(b'\x00')[0].strip()
        try:
            size = int(size_field, 8) if size_field else 0
        except ValueError:
            print(f'  UNPARSEABLE size at offset {off} name={name!r} raw={size_field!r}')
            break
        prefix = h[345:500].split(b'\x00')[0].decode(errors='replace')
        full = (prefix + '/' + name) if prefix else name
        data_start = off + 512
        data_len = (size + 511)//512*512
        if 114725376 - 4096 <= off <= 114725376 + 8192:
            mtime = h[136:148].split(b'\x00')[0].strip().decode()
            uid = h[108:116].split(b'\x00')[0].strip().decode()
            gid = h[116:124].split(b'\x00')[0].strip().decode()
            print(f'  hdr@{off} type={typeflag!r} size={size} mtime={mtime} uid={uid} gid={gid} name={full[:130]}')
            if typeflag in ('L','x','g'):
                payload = data[data_start:data_start+size]
                print(f'    payload[:200]={payload[:200]!r}')
        hits.append((off, full, typeflag, size))
        off = data_start + data_len
    return hits

bh = walk(bak, 'backup')
if dev is not None:
    dh = walk(dev, 'device-recut')
    print('--- member-order comparison (names only, full walk) ---')
    bn = [(f,t,s) for _,f,t,s in bh]
    dn = [(f,t,s) for _,f,t,s in dh]
    print('backup members:', len(bn), 'device members:', len(dn))
    same_order = bn == dn
    print('identical (name,type,size) sequence:', same_order)
    if not same_order:
        for i,(x,y) in enumerate(zip(bn,dn)):
            if x != y:
                print(f'  first sequence divergence at member {i}:')
                print(f'    backup : {x}')
                print(f'    device : {y}')
                break
        setb = set(f for f,_,_ in bn); setd = set(f for f,_,_ in dn)
        print('  names only in backup:', sorted(setb-setd)[:5])
        print('  names only in device:', sorted(setd-setb)[:5])
        # size-by-name comparison
        sb = {f:s for f,_,s in bn}; sd = {f:s for f,_,s in dn}
        diff_sz = [(f, sb[f], sd[f]) for f in sb if f in sd and sb[f]!=sd[f]]
        print('  same-name different-size members:', diff_sz[:10])
else:
    print('device recut absent; backup walk only')

print('--- skia dir member list in backup (name, size, mtime) ---')
off=0; n=len(bak)
while off + 512 <= n:
    h = bak[off:off+512]
    if h == b'\x00'*512:
        off += 512; continue
    name = h[0:100].split(b'\x00')[0].decode(errors='replace')
    size_field = h[124:136].split(b'\x00')[0].strip()
    size = int(size_field, 8) if size_field else 0
    if '/skia/' in name or name.endswith('/skia'):
        mtime = int(h[136:148].split(b'\x00')[0].strip() or b'0', 8)
        print(f'  {name} size={size} mtime={mtime} hdr@{off}')
    off += 512 + (size+511)//512*512
EOF
} > "$OUT" 2>&1

echo "wrote $OUT"
