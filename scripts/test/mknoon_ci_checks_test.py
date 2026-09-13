#!/usr/bin/env python3
"""CI acceptance using real Git graphs and isolated unittest subprocess evidence."""

import contextlib
import copy
import io
import json
import os
from pathlib import Path
import re
import sys
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import mknoon_checks as checks
import mknoon_checks_test as fixtures


class CiFixture(fixtures.RepositoryFixture):
    def setUp(self):
        super().setUp()
        # All execution stays in disposable Python fixtures, even when the
        # synthetic branch graph selects several consumer IDs.
        for check in self.rules['checks'].values():
            if check['kind'] != 'manual':
                check.update(kind='python', paths=['fixture_test.py'])
        self.rules['areas'][0]['patterns'].append('tool/testing/selection.json')
        self.write('tool/testing/selection.json', json.dumps(self.rules))
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture selection rules')
        self.base = checks.resolve_ref(self.root, 'HEAD')
        self.git('checkout', '-qb', 'contribution')
        self.write('lib/chat.dart', 'PR feature\n')
        self.git('commit', '-qam', 'feature')
        self.head = checks.resolve_ref(self.root, 'HEAD')
        self.git('checkout', '-qb', 'target', self.base)
        self.write('README.md', 'target advanced independently\n')
        self.git('commit', '-qam', 'target advances')
        self.target = checks.resolve_ref(self.root, 'HEAD')
        self.git('merge', '--no-ff', '-qm', 'synthetic PR merge', 'contribution')
        self.candidate = checks.resolve_ref(self.root, 'HEAD')
        self.event = {'repository': {'full_name': 'fixture/repository'}, 'number': 7,
                      'pull_request': {
                          'head': {'sha': self.head, 'repo': {'full_name': 'fixture/repository'}},
                          'base': {'sha': self.target, 'ref': 'target'}}}
        self.event_path = self.write('.codex-test-logs/event.json', json.dumps(self.event))
        self.env = {'GITHUB_SHA': self.candidate, 'GITHUB_REPOSITORY': 'fixture/repository',
                    'GITHUB_RUN_ID': '123', 'GITHUB_RUN_ATTEMPT': '1',
                    'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_EVENT_PATH': str(self.event_path),
                    'GITHUB_WORKFLOW_REF': 'fixture/repository/.github/workflows/mknoon-checks.yml@refs/pull/7/merge',
                    'GITHUB_REF': 'refs/pull/7/merge',
                    'GITHUB_OUTPUT': str(self.root / '.codex-test-logs/outputs')}

    def context(self):
        return checks.ci_context(self.root, self.env)

    def cli(self, action, *extra, env=None):
        directory = self.root / '.codex-test-logs' / (action + '-' + str(time.monotonic_ns()))
        with mock.patch.object(checks, 'ROOT', self.root), \
                mock.patch.dict(os.environ, {**self.env, **(env or {})}), \
                mock.patch.object(checks, 'toolchain_identity', return_value={'python': 'fixture'}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = checks.main([action, '--output', str(directory), *map(str, extra)])
        return code, directory

    def expected(self):
        code, path = self.cli('ci-plan')
        self.assertEqual(code, 0, (path / 'error.json').read_text() if (path / 'error.json').exists() else '')
        plan = json.loads((path / 'plan.json').read_text())
        return path, plan

    def execute(self, expected_path, expected, *extra):
        return self.cli('ci-run', '--expected-plan', expected_path / 'plan.json', *extra,
                        env={'MKNOON_PLAN_SHA256': expected['plan_sha256']})

    def completed(self):
        path, expected = self.expected()
        code, run = self.execute(path, expected)
        self.assertEqual(code, 0, (run / 'summary.txt').read_text() if (run / 'summary.txt').exists() else '')
        return expected, json.loads((run / 'plan.json').read_text()), json.loads((run / 'results.json').read_text())

    def verify(self, expected, plan, report, **updates):
        values = dict(context=self.context(), fingerprint=expected['plan_sha256'],
                      metadata_result='success', execution_result='success')
        values.update(updates)
        return checks.verify_ci_results(expected, plan, report, **values)


class CiBaselineTest(CiFixture):
    def test_pr_uses_head_target_merge_base_while_testing_the_merge_candidate(self):
        context = self.context()
        self.assertEqual(context['baseline'], self.base)
        self.assertEqual(context['sha'], self.candidate)
        # Reproduce why using the synthetic merge's HEAD gives the wrong base.
        old = checks.git(self.root, 'merge-base', 'HEAD', self.target).decode().strip()
        self.assertEqual(old, self.target)
        self.assertNotEqual(context['baseline'], old)
        _, expected = self.expected()
        self.assertEqual(expected['baseline'], self.base)
        self.assertIn('lib/chat.dart', {c['path'] for c in expected['changes']})
        self.assertEqual(expected['ci']['pr_base_ref'], 'target')

    def test_stale_head_base_or_checked_out_candidate_is_rejected(self):
        for field in ('head', 'base'):
            with self.subTest(field=field):
                event = copy.deepcopy(self.event)
                event['pull_request'][field]['sha'] = self.base
                self.event_path.write_text(json.dumps(event))
                with self.assertRaises(checks.InvalidPlan):
                    self.context()
        self.event_path.write_text(json.dumps(self.event))
        with self.assertRaises(checks.InvalidPlan):
            checks.ci_context(self.root, {**self.env, 'GITHUB_SHA': self.head})

    def test_fork_can_plan_on_hosted_runner_but_cannot_execute_on_shared_runner(self):
        self.event['pull_request']['head']['repo']['full_name'] = 'contributor/fork'
        self.event_path.write_text(json.dumps(self.event))
        path, expected = self.expected()
        with mock.patch.object(checks, 'execute_plan') as execute:
            code, run = self.execute(path, expected)
        self.assertEqual(code, 2)
        execute.assert_not_called()
        self.assertIn('Fork code', (run / 'error.json').read_text())

    def test_schedule_and_dispatch_preserve_separate_modes_and_explicit_baselines(self):
        schedule = {**self.env, 'GITHUB_EVENT_NAME': 'schedule'}
        context = checks.ci_context(self.root, schedule)
        self.assertEqual((context['mode'], context['baseline']), ('full', self.candidate))
        dispatch = {**self.env, 'GITHUB_EVENT_NAME': 'workflow_dispatch'}
        for mode in ('change', 'release', 'full'):
            self.event['inputs'] = {'mode': mode, 'baseline': self.base}
            self.event_path.write_text(json.dumps(self.event))
            self.assertEqual(checks.ci_context(self.root, dispatch)['mode'], mode)
        for baseline in ('', 'target', 'HEAD^'):
            self.event['inputs']['baseline'] = baseline
            self.event_path.write_text(json.dumps(self.event))
            with self.assertRaises(checks.InvalidPlan):
                checks.ci_context(self.root, dispatch)
        with self.assertRaises(checks.InvalidPlan):
            checks.ci_context(self.root, {**self.env, 'GITHUB_EVENT_NAME': 'pull_request_target'})


class CiAcceptanceTest(CiFixture):
    def test_complete_real_execution_passes_both_validator_and_ci_cli(self):
        expected_path, expected = self.expected()
        code, run = self.execute(expected_path, expected)
        self.assertEqual(code, 0)
        plan = json.loads((run / 'plan.json').read_text())
        report = json.loads((run / 'results.json').read_text())
        self.assertEqual(self.verify(expected, plan, report)['status'], 'PASS')
        code, verdict = self.cli('ci-verify', '--expected-plan', expected_path / 'plan.json',
                                 '--report-directory', run, env={
                                     'MKNOON_PLAN_SHA256': expected['plan_sha256'],
                                     'MKNOON_METADATA_RESULT': 'success', 'MKNOON_EXECUTION_RESULT': 'success'})
        self.assertEqual(code, 0)
        self.assertEqual(json.loads((verdict / 'verdict.json').read_text())['completed_checks'], 2)

    def test_metadata_success_cannot_cover_disabled_skipped_cancelled_queued_or_missing_job(self):
        expected, plan, report = self.completed()
        for conclusion in ('skipped', 'cancelled', 'failure', '', 'queued', 'in_progress', 'disabled'):
            with self.subTest(conclusion=conclusion), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, report, execution_result=conclusion)
        for conclusion in ('failure', 'cancelled', 'skipped', ''):
            with self.subTest(metadata=conclusion), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, report, metadata_result=conclusion)

    def test_metadata_only_empty_partial_duplicate_and_extra_results_are_rejected(self):
        expected, plan, report = self.completed()
        for rows in ([], report['results'][:1], [report['results'][0]] * 2,
                     report['results'] + [{**report['results'][0], 'id': 'unexpected'}]):
            changed = {**report, 'results': rows}
            with self.subTest(rows=len(rows)), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, changed)
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, plan, {'status': 'NOT RUN', 'identity': plan['identity'], 'results': report['results']})

    def test_superficial_pass_cannot_hide_bad_first_attempt_or_incomplete_execution(self):
        expected, plan, report = self.completed()
        mutations = [
            {'status': 'FAIL'}, {'status': 'BLOCKED'}, {'status': 'NOT RUN'},
            {'exit_status': 1}, {'timed_out': True}, {'completion_observed': False},
            {'counts': {'passed': 0, 'failed': 0, 'skipped': 0}},
            {'counts': {'passed': 1, 'failed': 1, 'skipped': 0}},
            {'counts': {'passed': 1, 'failed': 0, 'skipped': 1}},
            {'missing_test_files': ['fixture_test.py']}, {'raw_output_sha256': None}]
        for mutation in mutations:
            changed = copy.deepcopy(report)
            changed['results'][0]['attempts'][0].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, changed)
        changed = copy.deepcopy(report)
        changed['results'][0]['attempts'] = []
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, plan, changed)

    def test_stale_candidate_baseline_rules_run_attempt_plan_and_commands_are_rejected(self):
        expected, plan, report = self.completed()
        for key in ('mode', 'baseline', 'identity', 'plan_sha256', 'ci', 'toolchains'):
            with self.subTest(key=key), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, {**report, key: None})
        for key in ('sha', 'run_id', 'run_attempt', 'pr_head', 'pr_base', 'mode'):
            with self.subTest(context=key), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, report, context={**self.context(), key: 'stale'})
        changed = copy.deepcopy(plan)
        changed['selected'].pop()
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, changed, report)
        for key in ('command', 'selected_paths', 'kind'):
            changed = copy.deepcopy(report)
            changed['results'][0][key] = 'wrong'
            with self.subTest(row=key), self.assertRaises(checks.InvalidPlan):
                self.verify(expected, plan, changed)
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, plan, {**report, 'gaps': ['Unmapped change']})

    def test_missing_results_file_cannot_pass_even_when_jobs_claim_success(self):
        path, expected = self.expected()
        _, run = self.execute(path, expected)
        (run / 'results.json').unlink()
        code, _ = self.cli('ci-verify', '--expected-plan', path / 'plan.json', '--report-directory', run,
                            env={'MKNOON_PLAN_SHA256': expected['plan_sha256'],
                                 'MKNOON_METADATA_RESULT': 'success', 'MKNOON_EXECUTION_RESULT': 'success'})
        self.assertNotEqual(code, 0)

    def test_real_failure_and_passing_diagnostic_rerun_preserve_failure(self):
        self.write('fixture_test.py', 'import unittest\nfrom pathlib import Path\nclass Fixture(unittest.TestCase):\n'
                   '    def test_first_attempt(self):\n        marker=Path(".codex-test-logs/first")\n'
                   '        seen=marker.exists()\n        marker.touch()\n        self.assertTrue(seen)\n')
        self.git('commit', '-qam', 'failing diagnostic fixture')
        self.env.update(GITHUB_SHA=checks.resolve_ref(self.root, 'HEAD'), GITHUB_EVENT_NAME='workflow_dispatch')
        self.event['inputs'] = {'mode': 'change', 'baseline': self.base}
        self.event_path.write_text(json.dumps(self.event))
        path, expected = self.expected()
        code, run = self.execute(path, expected, '--rerun-failed')
        self.assertEqual(code, 1)
        report = json.loads((run / 'results.json').read_text())
        self.assertEqual([a['status'] for a in report['results'][0]['attempts']], ['FAIL', 'PASS'])
        # Even falsified outer aggregate success cannot hide the first failure.
        report.update(status='PASS', automated_status='PASS')
        report['results'][0]['status'] = 'PASS'
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, json.loads((run / 'plan.json').read_text()), report)

    def test_release_requires_original_device_and_signed_artifact_evidence(self):
        self.rules['checks']['device'] = {'kind': 'sims', 'capability': 'fixture.device',
            'boundary': 'isolated fixture device', 'timeout_seconds': 1}
        self.rules['mandatory'].append('device')
        self.write('tool/sims/critical_features.json', json.dumps({'capabilities': [{'id': 'fixture.device'}]}))
        self.rules['areas'][0]['patterns'].append('tool/sims/critical_features.json')
        self.write('tool/testing/selection.json', json.dumps(self.rules))
        self.git('add', '.')
        self.git('commit', '-qm', 'release fixture contract')
        self.env.update(GITHUB_SHA=checks.resolve_ref(self.root, 'HEAD'), GITHUB_EVENT_NAME='workflow_dispatch')
        self.event['inputs'] = {'mode': 'release', 'baseline': self.base}
        self.event_path.write_text(json.dumps(self.event))
        path, expected = self.expected()
        # No device config exists; this must never launch SIMS or touch a device.
        with mock.patch.object(checks, 'sims_environment', side_effect=AssertionError('device execution forbidden')):
            code, run = self.execute(path, expected)
        self.assertEqual(code, 2)
        plan = json.loads((run / 'plan.json').read_text())
        report = json.loads((run / 'results.json').read_text())
        rows = {r['id']: r for r in report['results']}
        self.assertEqual(rows['device']['status'], 'BLOCKED')
        self.assertEqual(rows['manual']['status'], 'BLOCKED')
        self.assertIn('Signed candidate artifacts not supplied', report['gaps'])
        with self.assertRaises(checks.InvalidPlan):
            self.verify(expected, plan, report)

    def test_plan_identity_is_portable_but_selection_and_rules_are_bound(self):
        expected, plan, report = self.completed()
        portable = copy.deepcopy(expected)
        portable['selected'][0]['command'][0] = '/other/host/python3'
        portable['selected'][0]['blocked_prerequisites'] = ['host tool unavailable']
        portable['toolchains'] = {'python': 'another installed version'}
        self.assertEqual(checks.plan_fingerprint(portable), expected['plan_sha256'])
        portable['identity']['rules_sha256'] = 'different'
        self.assertNotEqual(checks.plan_fingerprint(portable), expected['plan_sha256'])

    def test_full_uses_existing_full_commands_with_its_own_acceptance_mode(self):
        self.rules['full_commands'] = [{**self.rules['checks']['fast'], 'id': 'full-fixture',
            'command': [sys.executable, '-m', 'unittest', 'fixture_test.py']}]
        self.write('tool/testing/selection.json', json.dumps(self.rules))
        self.git('commit', '-qam', 'full command fixture')
        self.env.update(GITHUB_SHA=checks.resolve_ref(self.root, 'HEAD'), GITHUB_EVENT_NAME='schedule')
        expected, plan, report = self.completed()
        self.assertEqual(report['mode'], 'full')
        self.assertEqual([r['id'] for r in report['results']], ['full-fixture'])
        self.assertEqual(self.verify(expected, plan, report)['status'], 'PASS')


class ConsumerSelectionTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[2]
        self.rules = json.loads((self.root / checks.RULES).read_text())

    def selected(self, path, mode='change'):
        return checks.select(copy.deepcopy(self.rules), [{'path': path, 'status': 'M'}], mode, [], self.root)

    def test_shared_bridge_storage_and_lifecycle_select_communication_consumers(self):
        consumers = {'affected-conversation', 'affected-groups', 'affected-media', 'affected-push', 'affected-calls'}
        for path in ('lib/core/bridge/p2p_bridge_client.dart', 'go-mknoon/bridge/bridge.go',
                     'lib/core/database/app_database.dart', 'lib/core/secure_storage/secure_key_store.dart',
                     'lib/core/lifecycle/app_lifecycle_coordinator.dart'):
            with self.subTest(path=path):
                self.assertTrue(consumers.issubset({c['id'] for c in self.selected(path)['selected']}))

    def test_shared_notification_changes_select_direct_and_group_projection_consumers(self):
        ids = {c['id'] for c in self.selected('lib/core/notifications/app_visibility_authority.dart')['selected']}
        self.assertTrue({'affected-conversation', 'affected-groups', 'affected-push'}.issubset(ids))

    def test_build_configuration_keeps_device_checks_and_all_release_requirements(self):
        for path in ('android/app/build.gradle.kts', 'ios/Podfile', 'pubspec.lock',
                     'tool/build/voice_call_release_defines.json', 'scripts/run_test_gates.sh',
                     'scripts/run_host_test_gates.sh'):
            with self.subTest(path=path):
                selected = self.selected(path)
                ids = {c['id'] for c in selected['selected']}
                self.assertTrue({'affected-conversation', 'affected-groups', 'affected-push',
                                 'affected-calls', 'device-reconnect', 'device-media'}.issubset(ids))
                self.assertFalse(any(c['kind'] == 'manual' for c in selected['selected']))
                release_ids = {c['id'] for c in self.selected(path, 'release')['selected']}
                self.assertTrue(set(self.rules['mandatory']).issubset(release_ids))

    def test_isolated_ci_tests_have_exact_mapping_without_narrowing_unknown_infrastructure(self):
        for path in ('scripts/test/mknoon_checks_test.py', 'scripts/test/mknoon_ci_checks_test.py',
                     'scripts/test/testing_inventory_test.py'):
            selected = self.selected(path)
            self.assertEqual({c['id'] for c in selected['selected']}, set(self.rules['fast']) | {'workflow', 'provider-schema'})
            self.assertFalse(selected['unmapped_changes'])
        for path in ('scripts/test/new_shared_fixture_test.py', 'scripts/run_new_gate.sh'):
            with self.subTest(path=path):
                self.assertIn('affected-conversation', {c['id'] for c in self.selected(path)['selected']})
        unknown = self.selected('new_native_boundary/unknown.config')
        self.assertEqual(unknown['unmapped_changes'], ['new_native_boundary/unknown.config'])
        self.assertTrue({c for c in self.rules['conservative'] if self.rules['checks'][c]['kind'] != 'manual'}
                        .issubset({c['id'] for c in unknown['selected']}))


class WorkflowSafetyTest(unittest.TestCase):
    def setUp(self):
        self.workflow = (Path(__file__).resolve().parents[2] / '.github/workflows/mknoon-checks.yml').read_text()
        self.jobs = dict(re.findall(r'^  (\w+):\n(.*?)(?=^  \w+:\n|\Z)',
                                   self.workflow.split('\njobs:\n', 1)[1], re.M | re.S))

    def test_required_verdict_waits_for_execution_and_always_checks_failures(self):
        required = self.jobs['required']
        self.assertRegex(required, r'needs: \[metadata, selected\]')
        self.assertIn('    if: always()\n', required)
        self.assertIn("github.event_name == 'pull_request' && 'Mknoon regression checks'", required)
        self.assertIn('MKNOON_EXECUTION_RESULT: ${{ needs.selected.result }}', required)
        self.assertIn('MKNOON_PLAN_SHA256: ${{ needs.metadata.outputs.plan_sha256 }}', required)
        self.assertRegex(required, r'if: always\(\)\n        env:[\s\S]+?run: python3 scripts/mknoon_checks.py ci-verify')
        self.assertNotIn('continue-on-error', self.workflow)
        self.assertNotIn('paths-ignore:', self.workflow)

    def test_shared_host_is_gated_serialized_and_exports_only_allowlisted_attempt_files(self):
        selected = self.jobs['selected']
        self.assertIn("vars.MKNOON_TEST_RUNNER_ENABLED == 'true'", selected)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', selected)
        self.assertIn('group: mknoon-shared-test-devices', selected)
        self.assertIn('cancel-in-progress: false', selected)
        self.assertIn('queue: max', selected)
        self.assertNotIn('pull_request_target:', self.workflow)
        self.assertNotIn('secrets.', self.workflow)
        self.assertEqual(self.workflow.count('persist-credentials: false'), 3)
        self.assertIn('checks-${{ github.run_id }}-${{ github.run_attempt }}', selected)
        exported = re.findall(r'^            (\.codex-test-logs/\S+)$', selected, re.M)
        self.assertEqual({Path(p).name for p in exported},
                         {'plan.json', 'results.json', 'partial.json', 'summary.txt', 'error.json'})
        self.assertIn('include-hidden-files: true', selected)


if __name__ == '__main__':
    unittest.main()
