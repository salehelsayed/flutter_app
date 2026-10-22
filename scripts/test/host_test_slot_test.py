"""Host-only contracts for the two-slot host-test lease. No device or service is contacted."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import device_campaign_preflight as preflight
import mknoon_checks

PASS = lambda: True  # noqa: E731


def hold_native_in_child(directory):
    program = ('import sys, time\n'
               f'sys.path.insert(0, {str(Path(preflight.__file__).parent)!r})\n'
               'from device_campaign_preflight import device_leases\n'
               f'with device_leases(["mknoon.shared-native-build"], {str(directory)!r}):\n'
               '    print("held", flush=True)\n'
               '    sys.stdin.readline()\n')
    child = subprocess.Popen([sys.executable, '-c', program], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    assert child.stdout.readline().strip() == 'held'
    return child


def dead_pid():
    child = subprocess.Popen([sys.executable, '-c', 'pass'])
    child.wait()
    return child.pid


class HostTestSlotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / 'leases'

    def tearDown(self):
        self.tmp.cleanup()

    def slot(self, **kwargs):
        kwargs.setdefault('guard', PASS)
        kwargs.setdefault('wait_seconds', 0)
        return preflight.host_test_slot(self.dir, **kwargs)

    def test_two_slots_then_busy(self):
        with self.slot(), self.slot():
            with self.assertRaisesRegex(preflight.HostSlotBusy, 'both host-test slots busy'):
                with self.slot():
                    self.fail('third holder admitted')
        with self.slot():
            pass

    def test_host_slot_does_not_take_the_native_lease(self):
        with self.slot():
            with preflight.device_leases(['mknoon.shared-native-build'], self.dir):
                pass

    def test_native_holder_pauses_new_slots_but_not_running_ones(self):
        with self.slot():
            child = hold_native_in_child(self.dir)
            try:
                self.assertEqual([w['state'] for w in preflight.native_wanted(self.dir)], ['holding'])
                with self.assertRaisesRegex(preflight.HostSlotBusy, 'native build priority'):
                    with self.slot():
                        self.fail('slot granted during a native build')
            finally:
                child.communicate('\n', timeout=5)
        self.assertEqual(preflight.native_wanted(self.dir), [])
        with self.slot():
            pass

    def test_busy_native_attempt_leaves_a_waiting_marker_and_release_removes_it(self):
        child = hold_native_in_child(self.dir)
        try:
            with self.assertRaises(preflight.DeviceLeaseBusy):
                with preflight.device_leases(['mknoon.shared-native-build'], self.dir):
                    self.fail('native lease shared')
            marker = json.loads((self.dir / f'native-wanted.{os.getpid()}').read_text())
            self.assertEqual(marker['state'], 'waiting')
        finally:
            child.communicate('\n', timeout=5)
        with preflight.device_leases(['mknoon.shared-native-build'], self.dir):
            self.assertTrue((self.dir / f'native-wanted.{os.getpid()}').exists())
        self.assertFalse((self.dir / f'native-wanted.{os.getpid()}').exists())

    def test_stale_markers_are_ignored(self):
        preflight.lease_directory(self.dir)
        gone = dead_pid()
        (self.dir / f'native-wanted.{gone}').write_text(json.dumps({'pid': gone, 'state': 'holding', 'time': time.time()}))
        parent = os.getppid()
        (self.dir / f'native-wanted.{parent}').write_text(
            json.dumps({'pid': parent, 'state': 'waiting', 'time': time.time() - preflight.NATIVE_WANTED_TTL - 1}))
        self.assertEqual(preflight.native_wanted(self.dir), [])
        with self.slot():
            pass

    def test_fresh_waiting_marker_from_a_live_process_pauses_slots(self):
        preflight.lease_directory(self.dir)
        parent = os.getppid()
        (self.dir / f'native-wanted.{parent}').write_text(json.dumps({'pid': parent, 'state': 'waiting', 'time': time.time()}))
        with self.assertRaisesRegex(preflight.HostSlotBusy, 'native build priority'):
            with self.slot():
                self.fail('slot granted while a native build waits')

    def test_memory_guard_blocks_a_new_slot(self):
        with self.assertRaisesRegex(preflight.HostSlotBusy, 'memory or swap guard'):
            with self.slot(guard=lambda: False):
                self.fail('slot granted under memory pressure')

    def test_waits_for_a_slot_then_proceeds(self):
        answers = iter([False, True])
        slept = []
        with self.slot(guard=lambda: next(answers), wait_seconds=60, sleep=slept.append):
            pass
        self.assertEqual(slept, [15])

    def test_host_only_classification(self):
        flutter = {'kind': 'flutter', 'command': ['flutter', 'test', '--no-pub', '--machine', 'test/a_test.dart']}
        self.assertTrue(mknoon_checks.host_only_check(flutter))
        self.assertTrue(mknoon_checks.host_only_check({'kind': 'command', 'command': ['flutter', 'analyze']}))
        self.assertTrue(mknoon_checks.host_only_check({'kind': 'command', 'command': ['dart', 'test', 'test/x_test.dart']}))
        self.assertFalse(mknoon_checks.host_only_check({**flutter, 'command': ['flutter', 'test', 'integration_test/a_test.dart']}))
        self.assertFalse(mknoon_checks.host_only_check({**flutter, 'command': ['flutter', 'test', '-d', 'x', 'test/a_test.dart']}))
        self.assertFalse(mknoon_checks.host_only_check({'kind': 'command', 'command': ['flutter', 'build', 'apk']}))
        self.assertFalse(mknoon_checks.host_only_check({'kind': 'sims', 'command': ['flutter', 'test']}))
        self.assertFalse(mknoon_checks.host_only_check({**flutter, 'resources': ['device:android']}))


if __name__ == '__main__':
    unittest.main()
