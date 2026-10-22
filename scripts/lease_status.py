#!/usr/bin/env python3
"""Read-only status of mknoon device/build leases.

Finds each lease lock file the same way device_campaign_preflight.device_leases does
(/tmp/mknoon-device-leases-<uid>/<sha256(name)>.lock) and reports who holds it, using
only lsof and ps. It never opens the lock for writing and never calls flock, so it can
not take or disturb a lease.

    python3 scripts/lease_status.py                      # native lease line, then host-test slots line
    python3 scripts/lease_status.py <lease-name> ...      # only the named leases
    python3 scripts/lease_status.py --json

Host-test slots (mknoon.host-tests.slot-1/2) are reported as N/2 used, plus any live
native-wanted marker, which pauses new host slots.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

DEFAULT_LEASE = 'mknoon.shared-native-build'
HOST_TESTS_LEASE = 'mknoon.host-tests'
HOST_TEST_SLOTS = 2
NATIVE_WANTED_TTL = 120


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


def native_wanted(directory, now=None):
    """Read-only copy of device_campaign_preflight.native_wanted (no lease dir creation)."""
    now = time.time() if now is None else now
    wanted = []
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        return wanted
    for name in names:
        if not name.startswith('native-wanted.') or name.endswith('.tmp'):
            continue
        try:
            with open(os.path.join(directory, name)) as f:
                entry = json.load(f)
            pid, state, stamp = int(entry['pid']), entry['state'], float(entry['time'])
            os.kill(pid, 0)
        except ProcessLookupError:
            continue
        except PermissionError:
            pass
        except (OSError, ValueError, KeyError, TypeError):
            continue
        if state == 'holding' or (state == 'waiting' and now - stamp < NATIVE_WANTED_TTL):
            wanted.append({'pid': pid, 'state': state, 'age_seconds': int(now - stamp)})
    return wanted


def host_status(directory, lsof='lsof', ps='ps'):
    slots = []
    for n in range(1, HOST_TEST_SLOTS + 1):
        slot = status('%s.slot-%d' % (HOST_TESTS_LEASE, n), directory, lsof, ps)
        slot['slot'] = n
        slots.append(slot)
    used = sum(1 for s in slots if s['state'] == 'HELD')
    return {'lease': HOST_TESTS_LEASE, 'state': '%d/%d' % (used, HOST_TEST_SLOTS), 'used': used,
            'slots': slots, 'nativeWanted': native_wanted(directory)}


def host_summary(result):
    line = '%s: %s slots used' % (result['lease'], result['state'])
    held = ['slot-%d pid %d age %s cwd %s' % (s['slot'], h['pid'], h['age'] or '?', h['cwd'] or '?')
            for s in result['slots'] for h in s['holders']]
    if held:
        line += ' (' + '; '.join(held) + ')'
    if result['nativeWanted']:
        line += ' [native priority: new slots paused, %s]' % ', '.join(
            'pid %d %s' % (w['pid'], w['state']) for w in result['nativeWanted'])
    return line


def summary(result):
    if result['state'] == 'FREE':
        return '%s: FREE' % result['lease']
    parts = ['pid %d age %s cwd %s cmd %s' % (h['pid'], h['age'] or '?', h['cwd'] or '?', h['command'][:80])
             for h in result['holders']]
    return '%s: HELD by %s' % (result['lease'], '; '.join(parts))


def main(argv=None):
    parser = argparse.ArgumentParser(description='Read-only lease status (never takes a lease).')
    parser.add_argument('leases', nargs='*')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    lsof = os.environ.get('LEASE_STATUS_LSOF', 'lsof')
    ps = os.environ.get('LEASE_STATUS_PS', 'ps')
    results = [status(n, lease_dir(), lsof, ps) for n in (args.leases or [DEFAULT_LEASE])]
    if not args.leases:
        results.append(host_status(lease_dir(), lsof, ps))
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for r in results:
            print(host_summary(r) if r['lease'] == HOST_TESTS_LEASE else summary(r))
    return 0


if __name__ == '__main__':
    sys.exit(main())
