#!/usr/bin/env python3
"""Run one command while holding the shared native-build lease (queue until free).
   host-run docker-ws/with_native_lease.py <log-file-in-repo> -- <cmd> [args...]"""
import os, subprocess, sys, time
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'scripts'))
import device_campaign_preflight as pre  # noqa: E402
log = os.path.join(REPO, sys.argv[1]); cmd = sys.argv[sys.argv.index('--') + 1:]
deadline = time.time() + 3 * 3600
while True:
    try:
        with pre.device_leases(['mknoon.shared-native-build']):
            t0 = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            with open(log, 'a') as f:
                f.write(f'lease acquired {t0}\n'); f.flush()
                rc = subprocess.call(cmd, stdout=f, stderr=subprocess.STDOUT)
                f.write(f'exit={rc} lease released {time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}\n')
            sys.exit(rc)
    except pre.DeviceLeaseBusy:
        if time.time() > deadline:
            print('lease wait timeout'); sys.exit(75)
        time.sleep(20)
