"""Offline contracts for joining existing native logs, not device evidence."""
import copy
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import sims_native_xctest_receipts as native
import mknoon_checks as checks
import testing_inventory as inventory


class NativeReceiptChainTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scope = self.root / 'build/sims/proofs' / native.CAPABILITY
        self.capture = self.scope / 'capture-current'
        self.artifact_path = self.scope / 'proof.json'
        self.names = [
            'testPreparePayloadFastPathNotificationTap',
            'testBackgroundRegisteredPayloadFastPathNotificationTap',
            'testPayloadFastPathNotificationTap',
            'testObservePayloadNotificationRecovery',
            'testVerifyPayloadNotificationRecoveryRetirement',
            'testRestorePayloadFastPathNetwork',
        ]
        self.phase_counts = ((2, 1, 1, 0, 0, 0),
                             (2, 1, 0, 1, 1, 0),
                             (2, 1, 0, 2, 0, 1))
        counts = {'NotificationTapUITests/' + name: sum(row[i] for row in self.phase_counts)
                  for i, name in enumerate(self.names)}
        self.specs = {native.CAPABILITY: dict(format=native.FORMAT, counts=counts)}
        self.artifact = dict(schema='mknoon.sims.proof.v1', capabilityId=native.CAPABILITY)
        for (phase, _, run_key), counts in zip(native.PHASES, self.phase_counts):
            directory = self.capture / phase
            directory.mkdir(parents=True)
            output = 'private-fixture-text-must-never-leave-the-log\n'
            for name, count in zip(self.names, counts):
                output += (f"Test Case '-[RunnerUITests.NotificationTapUITests {name}]' passed (0.1 seconds).\n" * count)
            (directory / 'ui-automation.redacted.log').write_text(output)
            self.artifact[run_key] = 'run-' + phase
            self.refresh_phase(phase)
        self.refresh_parent()
        self.attempt = dict(report_verification_observed=True)

    @staticmethod
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def refresh_phase(self, phase):
        _, digest_key, run_key = next(p for p in native.PHASES if p[0] == phase)
        directory = self.capture / phase
        receipt = dict(runId=self.artifact[run_key], evidenceSha256={
            'uiAutomationLog': self.digest(directory / 'ui-automation.redacted.log')})
        path = directory / 'automation_receipt.json'
        path.write_text(json.dumps(receipt))
        self.artifact[digest_key] = self.digest(path)

    def refresh_parent(self):
        self.artifact_path.write_text(json.dumps(self.artifact))
        self.report = dict(verdicts=[dict(capabilityId=native.CAPABILITY, status='PASS',
            artifactEvidence=dict(path=str(self.artifact_path), sha256=self.digest(self.artifact_path)))])

    def collect(self):
        return native.collect(self.root, self.report, self.attempt, self.specs)

    def assert_blocked(self):
        rows = self.collect()
        self.assertEqual({r['status'] for r in rows}, {'BLOCKED'})
        self.assertEqual(sum(r['counts']['passed'] for r in rows), 0)

    def test_verified_chain_reuses_all_six_exact_methods_without_private_output(self):
        rows = self.collect()
        self.assertEqual(len(rows), 6)
        self.assertEqual({r['status'] for r in rows}, {'PASS'})
        self.assertEqual({r['id'].removeprefix('xctest:'): r['counts']['passed'] for r in rows},
                         self.specs[native.CAPABILITY]['counts'])
        self.assertNotIn('private-fixture-text', json.dumps(rows))
        self.assertNotIn(str(self.root), json.dumps(rows))

    def test_each_link_rejects_changed_bytes(self):
        for path in (self.artifact_path,
                     self.capture / 'fast-path/automation_receipt.json',
                     self.capture / 'retry/ui-automation.redacted.log'):
            with self.subTest(path=path.name):
                before = path.read_bytes()
                path.write_bytes(before + b' ')
                self.assert_blocked()
                path.write_bytes(before)

    def test_missing_or_duplicate_phase_cannot_pass(self):
        original = self.capture / 'fast-path/automation_receipt.json'
        saved = original.read_bytes()
        original.unlink()
        self.assert_blocked()
        original.write_bytes(saved)
        duplicate = self.scope / 'capture-other/fast-path'
        shutil.copytree(original.parent, duplicate)
        self.assert_blocked()

    def test_valid_hashes_cannot_hide_skips_zero_wrong_or_duplicate_tests(self):
        log = self.capture / 'retry/ui-automation.redacted.log'
        original = log.read_text()
        bad = [
            '',
            original + 'Executed 0 tests\n',
            original + "Test Case '-[NotificationTapUITests testUnexpected]' passed (0.1 seconds).\n",
            original + "Test Case '-[NotificationTapUITests testRestorePayloadFastPathNetwork]' skipped\n",
            original + "Test Case '-[NotificationTapUITests testRestorePayloadFastPathNetwork]' failed\n",
            original + original,
        ]
        for output in bad:
            with self.subTest(output_length=len(output)):
                log.write_text(output)
                self.refresh_phase('retry')
                self.refresh_parent()
                self.assert_blocked()

    def test_parent_pass_requires_verified_report(self):
        self.attempt.clear()
        shutil.rmtree(self.scope)
        self.assert_blocked()

    def test_sims_ingestion_exposes_scoped_method_receipts_and_missing_proof(self):
        report = self.root / 'sims.json'
        report.write_text(json.dumps(self.report))
        good = checks.sims_receipt_details(report, self.attempt,
            [native.CAPABILITY], native_specs=self.specs, root=self.root)
        self.assertTrue(good['native_xctest_receipts_complete'])
        self.assertEqual(len(good['route_results']), 6)
        self.assertEqual({r['capability'] for r in good['route_results']}, {native.CAPABILITY})
        (self.capture / 'retry/ui-automation.redacted.log').unlink()
        missing = checks.sims_receipt_details(report, self.attempt,
            [native.CAPABILITY], native_specs=self.specs, root=self.root)
        self.assertFalse(missing['native_xctest_receipts_complete'])
        self.assertEqual({r['status'] for r in missing['route_results']}, {'BLOCKED'})
        # A parent's otherwise valid PASS cannot supply the missing method.
        self.assertEqual(missing['capability_results'][0]['status'], 'PASS')

    def test_full_executor_blocks_parent_pass_with_missing_native_log(self):
        identity = dict(head='fixture', source_sha256='a' * 64, rules_sha256='b' * 64)
        args = SimpleNamespace(evidence=None, candidate_artifact=[], only=None,
            rerun_failed=False, mode='full', jobs=1)
        check = dict(id='major', kind='sims', command=['fixture-sims'],
            capability='*', selected_paths=[native.CAPABILITY], timeout_seconds=10,
            resources=['isolated:fixture'], native_xctest_receipts=self.specs)
        plan = dict(mode='full', baseline='fixture', candidate_build='', identity=identity,
            selected=[check], not_selected=[], unmapped_changes=[], obligations=[])

        def launch(command, cwd, timeout, env=None):
            if command == ['fixture-sims']:
                Path(env['SIMS_REPORT_PATH']).write_text(json.dumps(self.report))
            else:
                self.assertEqual(command[:3], ['dart', 'tool/sims/sims.dart', 'verify-report'])
            return '', 0, False, .001

        for missing in (False, True):
            with self.subTest(missing_log=missing):
                if missing:
                    (self.capture / 'retry/ui-automation.redacted.log').unlink()
                out = self.root / '.codex-test-logs' / str(missing)
                out.mkdir(parents=True)
                # Only the child process and its already-tested SIMS verifier
                # are synthetic. Exercise the real executor/status join.
                with mock.patch.object(checks, 'launch', side_effect=launch), \
                     mock.patch.object(checks, 'inspect_sims', return_value=dict(
                         status='PASS', checkpoint='fixture_parent_pass', counts=dict(
                             passed=1, failed=0, skipped=0))), \
                     mock.patch.object(checks.device_preflight, 'device_leases',
                                       side_effect=lambda *_: contextlib.nullcontext()), \
                     mock.patch.object(checks, 'source_files', return_value=[]), \
                     mock.patch.object(checks, 'source_identity', return_value=identity), \
                     contextlib.redirect_stdout(io.StringIO()):
                    code = checks.execute_plan(args, self.root, {}, copy.deepcopy(plan),
                                               [], {}, {}, out, time.monotonic())
                report = json.loads((out / 'results.json').read_text())
                self.assertEqual(code, 2 if missing else 0)
                self.assertEqual(report['automated_status'], 'BLOCKED' if missing else 'PASS')
                if missing:
                    self.assertEqual(report['results'][0]['checkpoint'],
                                     'native_xctest_evidence_incomplete')

    def test_bound_artifact_cannot_escape_owned_proof_directory(self):
        outside = self.root / 'outside.json'
        shutil.copyfile(self.artifact_path, outside)
        self.report['verdicts'][0]['artifactEvidence']['path'] = str(outside)
        self.assert_blocked()

    def test_methods_from_different_captures_cannot_be_stitched(self):
        destination = self.scope / 'capture-other'
        destination.mkdir()
        (self.capture / 'retry').rename(destination / 'retry')
        self.assert_blocked()

    def test_unexecuted_and_unavailable_native_methods_remain_distinct(self):
        self.report['verdicts'] = []
        self.assertEqual({r['status'] for r in self.collect()}, {'NOT RUN'})
        self.report['verdicts'] = [dict(capabilityId=native.CAPABILITY,
            status='N/A', reason='target_unavailable_by_project_policy')]
        self.assertEqual({r['status'] for r in self.collect()}, {'N/A'})
        self.attempt.clear()
        self.assert_blocked()

    def test_invalid_declaration_is_rejected(self):
        for value in (0, -1, True, '1'):
            with self.subTest(value=value):
                spec = copy.deepcopy(self.specs)
                spec[native.CAPABILITY]['counts'][next(iter(spec[native.CAPABILITY]['counts']))] = value
                self.assertTrue(native.validate_specs(spec))


class ScopedObligationTest(unittest.TestCase):
    def test_combined_binding_requires_capability_and_its_unique_method(self):
        capability = native.CAPABILITY
        route = 'xctest:NotificationTapUITests/testPayloadFastPathNotificationTap'
        obligations = [dict(id='native', owners=['major'], status='SELECTED',
            receipt_bindings=[dict(owner='major', capability=capability, route=route)])]
        attempt = dict(capability_results=[dict(id=capability, status='PASS')])
        result = dict(major=dict(status='PASS', attempts=[attempt]))
        self.assertEqual(checks.obligation_results(obligations, result)[0]['status'], 'NOT RUN')
        attempt['route_results'] = [dict(id=route, capability='wrong', status='PASS')]
        self.assertEqual(checks.obligation_results(obligations, result)[0]['status'], 'NOT RUN')
        attempt['route_results'][0]['capability'] = capability
        self.assertEqual(checks.obligation_results(obligations, result)[0]['status'], 'PASS')
        attempt['route_results'].append(dict(attempt['route_results'][0]))
        self.assertEqual(checks.obligation_results(obligations, result)[0]['status'], 'NOT RUN')


class NativeSpecValidationTest(unittest.TestCase):
    def test_sims_method_binding_needs_its_declared_native_selector(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'case.swift').write_text('func testPayloadFastPathNotificationTap() {}')
            selector = 'NotificationTapUITests/testPayloadFastPathNotificationTap'
            check = dict(id='major', kind='sims', native_xctest_receipts={
                native.CAPABILITY: dict(format=native.FORMAT, counts={selector: 1})})
            binding = dict(owner='major', capability=native.CAPABILITY,
                           route='xctest:' + selector, patterns=['case.swift'], reason='fixture')
            rules = dict(full_commands=[check], full_inventory=dict(mappings=[binding]))
            with mock.patch.object(inventory, 'validate_sims_partitions', return_value=[]):
                self.assertEqual(inventory.validate_policy(root, rules, ['case.swift']), [])
                binding['route'] = 'xctest:NotificationTapUITests/testUndeclared'
                self.assertTrue(any('declared SIMS method' in error for error in
                                    inventory.validate_policy(root, rules, ['case.swift'])))


if __name__ == '__main__':
    unittest.main()
