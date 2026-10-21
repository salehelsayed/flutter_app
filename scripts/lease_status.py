#!/usr/bin/env python3
"""Read-only status of mknoon device/build leases.

Finds each lease lock file the same way device_campaign_preflight.device_leases does
(/tmp/mknoon-device-leases-<uid>/<sha256(name)>.lock) and reports who holds it, using
only lsof and ps. It never opens the lock for writing and never calls flock, so it can
not take or disturb a lease.

    python3 scripts/lease_status.py                      # mknoon.shared-native-build
    python3 scripts/lease_status.py <lease-name> ...      # other leases too
    python3 scripts/lease_status.py --json
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

DEFAULT_LEASE = 'mknoon.shared-native-build'


def lease_dir():
    return os.environ.get('LEASE_STATUS_DIR') or '/tmp/mknoon-device-leases-%d' % os.getuid()


def lock_path(name, directory):
    return os.path.join(directory, hashlib.sha256(name.encode()).hexdigest() + '.lock')


def _run(argv):
    try:
        return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              universal_newlines=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return ''


def holder_pids(path, lsof='lsof'):
    pids = []
    for line in _run([lsof, '-Fp', '--', path]).splitlines():
        if line.startswith('p') and line[1:].isdigit() and int(line[1:]) not in pids:
            pids.append(int(line[1:]))
    return pids


def process_info(pid, lsof='lsof', ps='ps'):
    etime = _run([ps, '-o', 'etime=', '-p', str(pid)]).strip()
    command = _run([ps, '-o', 'command=', '-p', str(pid)]).strip()
    program, _, rest = command.partition(' ')
    command = (os.path.basename(program) + ' ' + rest).strip()
    cwd = ''
    for line in _run([lsof, '-a', '-p', str(pid), '-d', 'cwd', '-Fn']).splitlines():
        if line.startswith('n'):
            cwd = line[1:]
    return {'pid': pid, 'age': etime, 'command': command[:160], 'cwd': cwd}


def status(name, directory, lsof='lsof', ps='ps'):
    path = lock_path(name, directory)
    if not os.path.exists(path):
        return {'lease': name, 'state': 'FREE', 'lockFile': path, 'lockFileExists': False, 'holders': []}
    holders = [process_info(p, lsof, ps) for p in holder_pids(path, lsof)]
    return {'lease': name, 'state': 'HELD' if holders else 'FREE', 'lockFile': path,
            'lockFileExists': True, 'holders': holders}


def summary(result):
    if result['state'] == 'FREE':
        return '%s: FREE' % result['lease']
    parts = ['pid %d age %s cwd %s cmd %s' % (h['pid'], h['age'] or '?', h['cwd'] or '?', h['command'][:80])
             for h in result['holders']]
    return '%s: HELD by %s' % (result['lease'], '; '.join(parts))


def main(argv=None):
    parser = argparse.ArgumentParser(description='Read-only lease status (never takes a lease).')
    parser.add_argument('leases', nargs='*', default=[DEFAULT_LEASE])
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    lsof = os.environ.get('LEASE_STATUS_LSOF', 'lsof')
    ps = os.environ.get('LEASE_STATUS_PS', 'ps')
    results = [status(n, lease_dir(), lsof, ps) for n in args.leases]
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for r in results:
            print(summary(r))
    return 0


if __name__ == '__main__':
    sys.exit(main())
