#!/bin/bash
# Run one command while holding the shared native-build lease (same lock file as mknoon_checks); fail fast if busy.
#   host-run bash docker-ws/with_native_build_lease.sh -- <command...>
[ "$1" = "--" ] && shift
exec python3 - "$@" <<'PY'
import fcntl, hashlib, os, subprocess, sys
d = '/tmp/mknoon-device-leases-%d' % os.getuid()
p = os.path.join(d, hashlib.sha256(b'mknoon.shared-native-build').hexdigest() + '.lock')
fd = os.open(p, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print('LEASE_BUSY'); sys.exit(75)
print('LEASE_HELD', flush=True)
rc = subprocess.call(sys.argv[1:])
os.close(fd)
print('LEASE_RELEASED rc=%d' % rc, flush=True)
sys.exit(rc)
PY
