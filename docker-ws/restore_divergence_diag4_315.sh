#!/bin/bash
# Decisive: rebuild the verify tar on-device with the guard's exact invocation,
# pull it, locate the FIRST divergent byte vs the backup tar, decode the
# surrounding tar header field.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docker-ws/restore_divergence_diag4_315_result.txt"
BK=$(ls -td /var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/mknoon-group-reaction-notification-state-* 2>/dev/null | head -1)

{
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') backup=$BK ==="
  echo "--- manifest entries + expected sha ---"
  python3 -c "
import json
m = json.load(open('$BK/recovery-manifest.json'))
import sys
print(json.dumps(m, indent=1)[:900])
"
  ENTRIES=$(tar -tf "$BK/21071FDF600CSC/private-data.tar" | awk -F/ '{print $1}' | sort -u | tr '\n' ' ')
  echo "top entries: $ENTRIES"
  echo "--- rebuild verify tar on device (guard's invocation) ---"
  adb -s 21071FDF600CSC shell "run-as com.mknoon.app tar -cf .diag_verify.tar -- $ENTRIES" 2>&1 | head -3
  adb -s 21071FDF600CSC exec-out run-as com.mknoon.app cat .diag_verify.tar > /tmp/device_verify.tar
  adb -s 21071FDF600CSC shell "run-as com.mknoon.app rm -f .diag_verify.tar"
  ls -la /tmp/device_verify.tar "$BK/21071FDF600CSC/private-data.tar"
  echo "--- shas ---"
  shasum -a 256 /tmp/device_verify.tar "$BK/21071FDF600CSC/private-data.tar" | awk '{print $1}'
  echo "--- first divergent offset + header context ---"
  python3 - <<'EOF'
a = open('/tmp/device_verify.tar','rb').read()
b = open("$BK".replace('$BK','') or '','rb') if False else None
EOF
  python3 - "$BK/21071FDF600CSC/private-data.tar" <<'EOF'
import sys
dev = open('/tmp/device_verify.tar','rb').read()
bak = open(sys.argv[1],'rb').read()
print('sizes:', len(dev), len(bak))
n = min(len(dev), len(bak))
diff = next((i for i in range(n) if dev[i] != bak[i]), None)
if diff is None:
    print('identical up to min length; size delta only')
else:
    print('first divergent offset:', diff)
    block = (diff // 512) * 512
    def hdr(data, off):
        h = data[off:off+512]
        name = h[0:100].rstrip(b'\x00').decode(errors='replace')
        mode = h[100:108].rstrip(b'\x00 ').decode(errors='replace')
        uid = h[108:116].rstrip(b'\x00 ').decode(errors='replace')
        gid = h[116:124].rstrip(b'\x00 ').decode(errors='replace')
        size = h[124:136].rstrip(b'\x00 ').decode(errors='replace')
        mtime = h[136:148].rstrip(b'\x00 ').decode(errors='replace')
        uname = h[265:297].rstrip(b'\x00').decode(errors='replace')
        gname = h[297:329].rstrip(b'\x00').decode(errors='replace')
        return dict(name=name, mode=mode, uid=uid, gid=gid, size=size, mtime=mtime, uname=uname, gname=gname)
    # scan back to the nearest plausible header (name printable)
    for probe in range(block, max(-1, block-512*40), -512):
        h = hdr(bak, probe)
        if h['name']:
            print('nearest header at', probe)
            print(' backup :', h)
            print(' device :', hdr(dev, probe))
            break
    print('in-block field offset:', diff - block)
EOF
} > "$OUT" 2>&1

echo "wrote $OUT"
