import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from flutter_native_asset_lock import FlutterNativeAssetLock
import mknoon_checks as checks


def command(path='test/one_test.dart'):
    return ['flutter', 'test', '--no-pub', '--machine', '--concurrency=1', '--timeout=2m', path]


def check(path):
    return dict(kind='flutter', command=command(path), selected_paths=[path])


class NativeAssetLockTest(unittest.TestCase):
    def test_four_distinct_standard_lanes_can_overlap_but_other_owners_cannot(self):
        lanes = [check(f'test/lane{i}_test.dart') for i in range(4)]
        for i, left in enumerate(lanes):
            for right in lanes[i + 1:]:
                self.assertTrue(checks.resources_compatible(left, right))
        self.assertFalse(checks.resources_compatible(lanes[0], lanes[0]))
        native = dict(kind='command', command=['flutter', 'build', 'apk'], resources=['build:apk'])
        self.assertFalse(checks.resources_compatible(lanes[0], native))
        for mutation in [dict(environment={'FLAG': 'different'}), dict(resources=['unknown']),
                         dict(command=command('test/other_test.dart') + ['--dart-define=X=Y'])]:
            self.assertFalse(checks.resources_compatible(lanes[0], {**lanes[1], **mutation}))

    def test_lock_releases_only_after_complete_valid_stdout_event(self):
        with tempfile.TemporaryDirectory() as root:
            with FlutterNativeAssetLock(root, command(), time.monotonic() + 1) as first:
                self.assertTrue(first.ready)
                first.feed_stdout(b'{"type":"testStart"}\n')
                first.feed_stdout(b'{"type":"print","message":"testStart"}\n')
                with FlutterNativeAssetLock(root, command(), time.monotonic() + .01) as blocked:
                    self.assertFalse(blocked.ready)
                event = json.dumps(dict(type='testStart', test=dict(id=1, suiteID=0, name='loading'))).encode() + b'\n'
                first.feed_stdout(event[:20])
                self.assertIsNotNone(first.handle)
                first.feed_stdout(event[20:])
                self.assertIsNone(first.handle)
                with FlutterNativeAssetLock(root, command(), time.monotonic() + 1) as next_lane:
                    self.assertTrue(next_lane.ready)

    def test_failed_startup_and_overlong_lines_do_not_strand_or_release_lock_early(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(RuntimeError, 'startup'):
                with FlutterNativeAssetLock(root, command(), time.monotonic() + 1) as first:
                    first.feed_stdout(b'x' * 70000)
                    first.feed_stdout(b'{"type":"testStart","test":{"id":1,"suiteID":0,"name":"fake"}}\n')
                    self.assertIsNotNone(first.handle)
                    raise RuntimeError('startup')
            with FlutterNativeAssetLock(root, command(), time.monotonic() + 1) as next_lane:
                self.assertTrue(next_lane.ready)

    def test_canonical_tree_alias_shares_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'tree'
            root.mkdir()
            alias = Path(temporary) / 'alias'
            alias.symlink_to(root, target_is_directory=True)
            with FlutterNativeAssetLock(root, command(), time.monotonic() + 1):
                with FlutterNativeAssetLock(alias, command(), time.monotonic() + .01) as blocked:
                    self.assertFalse(blocked.ready)


if __name__ == '__main__':
    unittest.main()
