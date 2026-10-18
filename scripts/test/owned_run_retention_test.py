import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from owned_run_retention import OwnedRuns, RetentionCapacityError, MARKER, check_screenshots


class OwnedRetentionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        subprocess.run(['git', 'init', '-q', str(self.repository)], check=True)
        self.owner = OwnedRuns(self.repository)

    def run_fixture(self, state='active', bytes_count=32):
        # Hold runs active while the fixture set is assembled; production
        # finish prunes immediately and would hide an invalid selection.
        with mock.patch.object(self.owner, '_prune', return_value={}):
            path = self.owner.start('checks')
        (path / 'raw.log').write_bytes(b'x' * bytes_count)
        if state != 'active':
            data = json.loads((path / MARKER).read_text())
            data['state'] = state
            self.owner._save(path, data)
        return path

    def test_active_last_two_passes_and_first_untriaged_failure(self):
        active = self.run_fixture()
        first_failure = self.run_fixture('FAIL')
        old_good = self.run_fixture('PASS')
        good1 = self.run_fixture('PASS')
        good2 = self.run_fixture('PASS')
        later_failure = self.run_fixture('FAIL')
        self.owner.finish(active, 'PASS')
        self.assertTrue(first_failure.exists())
        self.assertTrue(good2.exists())
        self.assertTrue(active.exists())
        self.assertFalse(good1.exists())
        self.assertFalse(old_good.exists())
        self.assertFalse(later_failure.exists())

    def test_referenced_run_and_transitive_report_reference_survive(self):
        referenced = self.run_fixture()
        dependent = self.run_fixture()
        (dependent / 'report.json').write_text(json.dumps({'proof': str(referenced / 'raw.log')}))
        document = self.repository / 'evidence.md'
        # Put a run name across a read boundary as well.
        document.write_text('x' * (64 * 1024 - 8) + str(dependent / 'report.json'))
        subprocess.run(['git', 'add', 'evidence.md'], cwd=self.repository, check=True)
        for path in (referenced, dependent):
            data = json.loads((path / MARKER).read_text())
            data['state'] = 'PASS'
            self.owner._save(path, data)
        self.run_fixture('PASS')
        self.run_fixture('PASS')
        self.owner._prune()
        self.assertTrue(referenced.exists())
        self.assertTrue(dependent.exists())

    def test_unmarked_directories_foreign_data_and_symlink_targets_survive(self):
        target = self.run_fixture('PASS')
        foreign = self.owner.root / 'foreign'
        foreign.mkdir()
        (foreign / 'keep').write_text('foreign')
        (foreign / 'evidence-link').symlink_to(target / 'raw.log')
        outside = self.repository / 'outside'
        outside.mkdir()
        (outside / 'keep').write_text('outside')
        (self.owner.root / 'foreign-link').symlink_to(outside, target_is_directory=True)
        self.run_fixture('PASS')
        self.run_fixture('PASS')
        self.owner._prune()
        self.assertTrue(target.exists())
        self.assertEqual((foreign / 'keep').read_text(), 'foreign')
        self.assertEqual((outside / 'keep').read_text(), 'outside')

    def test_hard_linked_evidence_is_protected(self):
        target = self.run_fixture('PASS')
        os.link(target / 'raw.log', self.repository / 'external-evidence.log')
        self.run_fixture('PASS')
        self.run_fixture('PASS')
        self.owner._prune()
        self.assertTrue(target.exists())

    def test_protected_over_quota_fails_without_deleting_evidence(self):
        active = self.run_fixture(bytes_count=128)
        tiny = OwnedRuns(self.repository, limit_bytes=64)
        with self.assertRaisesRegex(RetentionCapacityError, 'evidence_capacity'):
            tiny.finish(active, 'PASS')
        self.assertEqual((active / 'raw.log').stat().st_size, 128)
        self.assertEqual(json.loads((active / MARKER).read_text())['state'], 'FAIL')

    def test_never_adopts_existing_output_or_symlinked_root(self):
        with tempfile.TemporaryDirectory() as other:
            repository = Path(other)
            root = repository / '.codex-test-logs' / 'owned-runs'
            root.mkdir(parents=True)
            (root / 'old.log').write_text('old evidence')
            with self.assertRaisesRegex(ValueError, 'no ownership marker'):
                OwnedRuns(repository)
            self.assertEqual((root / 'old.log').read_text(), 'old evidence')
        with tempfile.TemporaryDirectory() as other:
            repository = Path(other)
            (repository / '.codex-test-logs').symlink_to(self.owner.root)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                OwnedRuns(repository)

    def test_finish_rejects_foreign_and_forged_ownership(self):
        foreign = self.repository / 'foreign'
        foreign.mkdir()
        with self.assertRaises(ValueError):
            self.owner.finish(foreign, 'PASS')
        run = self.run_fixture()
        marker = json.loads((run / MARKER).read_text())
        marker['run'] = 'another-directory'
        self.owner._save(run, marker)
        with self.assertRaises(ValueError):
            self.owner.finish(run, 'PASS')
        self.assertTrue(run.exists())

    def test_screenshots_count_file_and_aggregate_limits_preserve_evidence(self):
        run = self.run_fixture()
        image = run / 'one.png'
        image.write_bytes(b'x' * 8)
        with self.assertRaises(RetentionCapacityError):
            check_screenshots(run, file_limit=7)
        self.assertEqual(image.read_bytes(), b'x' * 8)
        (run / 'two.png').write_bytes(b'y' * 8)
        with self.assertRaises(RetentionCapacityError):
            check_screenshots(run, max_count=1)
        with self.assertRaises(RetentionCapacityError):
            check_screenshots(run, max_bytes=15)
        (run / 'foreign.png').symlink_to(self.repository / 'unavailable.png')
        self.assertEqual(check_screenshots(run), {'count': 2, 'bytes': 16})


if __name__ == '__main__':
    unittest.main()
