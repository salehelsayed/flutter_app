import hashlib
import io
import json
import os
import stat
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import lease_status  # noqa: E402

LEASE = 'mknoon.shared-native-build'


def write_exe(path, body):
    with open(path, 'w') as f:
        f.write('#!/bin/sh\n' + body)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class LeaseStatusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, 'leases')
        os.mkdir(self.dir, 0o700)
        self.lock = os.path.join(self.dir, hashlib.sha256(LEASE.encode()).hexdigest() + '.lock')
        self.lsof = os.path.join(self.tmp.name, 'lsof')
        self.ps = os.path.join(self.tmp.name, 'ps')
        write_exe(self.ps, 'case "$2" in etime=) echo "  01:02:03";; command=) echo "python3 scripts/mknoon_checks.py run --only device-notifications-ios";; esac\n')

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self, *args):
        env = {'LEASE_STATUS_DIR': self.dir, 'LEASE_STATUS_LSOF': self.lsof, 'LEASE_STATUS_PS': self.ps}
        old = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        out = io.StringIO()
        try:
            with redirect_stdout(out):
                self.assertEqual(lease_status.main(list(args)), 0)
        finally:
            for k, v in old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        return out.getvalue()

    def test_missing_lock_file_is_free(self):
        write_exe(self.lsof, 'exit 1\n')
        self.assertEqual(self.run_main().splitlines(),
                         ['mknoon.shared-native-build: FREE', 'mknoon.host-tests: 0/2 slots used'])

    def test_lock_file_without_holder_is_free(self):
        open(self.lock, 'w').close()
        write_exe(self.lsof, 'exit 1\n')
        result = json.loads(self.run_main('--json'))[0]
        self.assertEqual(result['state'], 'FREE')
        self.assertTrue(result['lockFileExists'])
        self.assertEqual(result['holders'], [])

    def test_held_lock_reports_pid_age_cwd_and_command(self):
        open(self.lock, 'w').close()
        write_exe(self.lsof, 'case "$1" in -Fp) [ "$3" = "%s" ] && echo p4242;; -a) echo p4242; echo fcwd; echo n/Volumes/x/build/wt-cui-b376;; esac\n' % self.lock)
        line = self.run_main().splitlines()[0]
        self.assertEqual(line, 'mknoon.shared-native-build: HELD by pid 4242 age 01:02:03 cwd /Volumes/x/build/wt-cui-b376 '
                               'cmd python3 scripts/mknoon_checks.py run --only device-notifications-ios')
        result = json.loads(self.run_main('--json'))[0]
        self.assertEqual(result['holders'], [{'pid': 4242, 'age': '01:02:03',
                                              'command': 'python3 scripts/mknoon_checks.py run --only device-notifications-ios',
                                              'cwd': '/Volumes/x/build/wt-cui-b376'}])

    def test_never_takes_the_lease(self):
        open(self.lock, 'w').close()
        write_exe(self.lsof, 'exit 1\n')
        before = os.stat(self.lock)
        self.run_main()
        after = os.stat(self.lock)
        self.assertEqual((before.st_ino, before.st_size, before.st_mtime), (after.st_ino, after.st_size, after.st_mtime))
        self.assertEqual(sorted(os.listdir(self.dir)), [os.path.basename(self.lock)])

    def slot_lock(self, n):
        return os.path.join(self.dir, hashlib.sha256(('mknoon.host-tests.slot-%d' % n).encode()).hexdigest() + '.lock')

    def test_host_slots_and_native_priority(self):
        open(self.slot_lock(2), 'w').close()
        write_exe(self.lsof, 'case "$1" in -Fp) [ "$3" = "%s" ] && echo p5151;; -a) echo p5151; echo fcwd; echo n/Volumes/x/build/wt-astra;; esac\n'
                  % self.slot_lock(2))
        with open(os.path.join(self.dir, 'native-wanted.%d' % os.getppid()), 'w') as f:
            json.dump({'pid': os.getppid(), 'state': 'waiting', 'time': time.time()}, f)
        lines = self.run_main().splitlines()
        self.assertEqual(lines[0], 'mknoon.shared-native-build: FREE')
        self.assertEqual(lines[1], 'mknoon.host-tests: 1/2 slots used (slot-2 pid 5151 age 01:02:03 cwd /Volumes/x/build/wt-astra)'
                                   ' [native priority: new slots paused, pid %d waiting]' % os.getppid())
        host = json.loads(self.run_main('--json'))[1]
        self.assertEqual((host['lease'], host['used'], [s['state'] for s in host['slots']]),
                         ('mknoon.host-tests', 1, ['FREE', 'HELD']))
        self.assertEqual([w['state'] for w in host['nativeWanted']], ['waiting'])

    def test_other_lease_names(self):
        write_exe(self.lsof, 'exit 1\n')
        self.assertEqual(self.run_main(LEASE, 'emulator-5560').splitlines(),
                         ['mknoon.shared-native-build: FREE', 'emulator-5560: FREE'])


if __name__ == '__main__':
    unittest.main()
