#!/usr/bin/env python3
"""Behavior contracts for deterministic selection and truthful check results.

Temporary repositories and disposable unittest processes are the only executed
fixtures; no application build, device, external account or service is used.
"""

import argparse
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mknoon_checks as checks


class RepositoryFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mknoon-checks-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Isolated Test Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('.gitignore', '.codex-test-logs/\n__pycache__/\n')
        self.write('fixture_test.py', 'import unittest\nclass Fixture(unittest.TestCase):\n    def test_fixture(self):\n        self.assertEqual(2 + 2, 4)\n')
        for path in ('test/chat_test.dart', 'test/groups_test.dart', 'test/bridge_test.dart'):
            self.write(path, "test('retains exact received content', () {});\n")
        self.write('lib/shared.dart', 'original\n')
        self.write('lib/chat.dart', 'original\n')
        self.write('lib/delete.dart', 'original\n')
        self.write('lib/rename.dart', 'distinct original retained during rename\n')
        self.write('README.md', 'original\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'isolated baseline')
        self.base = checks.resolve_ref(self.root, 'HEAD')
        self.rules = {
            'schema_version': 1,
            'checks': {
                'fast': {'kind': 'python', 'paths': ['fixture_test.py'], 'boundary': 'workflow fixture', 'timeout_seconds': 10},
                'chat': {'kind': 'flutter', 'paths': ['test/chat_test.dart'], 'boundary': 'chat fixture', 'timeout_seconds': 10},
                'groups': {'kind': 'flutter', 'paths': ['test/groups_test.dart'], 'boundary': 'group fixture', 'timeout_seconds': 10},
                'bridge': {'kind': 'flutter', 'paths': ['test/bridge_test.dart'], 'boundary': 'bridge fixture', 'timeout_seconds': 10},
                'manual': {'kind': 'manual', 'boundary': 'signed artifact receipt', 'timeout_seconds': 10, 'assertions': ['reopen', 'receive']},
            },
            'fast': ['fast'], 'mandatory': ['fast', 'manual'],
            'conservative': ['chat', 'groups', 'bridge'],
            'areas': [
                {'id': 'workflow', 'patterns': ['fixture_test.py'], 'checks': ['fast'], 'why': 'isolated workflow fixture'},
                {'id': 'shared', 'patterns': ['lib/shared.dart'], 'checks': ['chat', 'groups', 'bridge'], 'why': 'shared event consumers'},
                {'id': 'chat', 'patterns': ['lib/chat.dart', 'test/*'], 'checks': ['chat'], 'why': 'conversation boundary'},
            ],
            'documentation_only': ['*.md'], 'evidence_exclusions': ['.codex-test-logs/**'],
        }

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def write(self, path, content):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return p

    def selection(self, paths=(), mode='change'):
        changes = [{'path': path, 'status': 'M'} for path in paths]
        return checks.select(copy.deepcopy(self.rules), changes, mode, checks.source_files(self.root), self.root)

    def args(self, **updates):
        values = dict(base=self.base, local=True, mode='change', build_label='isolated-fixture',
                      evidence=None, candidate_artifact=[], only=None, rerun_failed=False)
        values.update(updates)
        return argparse.Namespace(**values)


class SelectionTest(RepositoryFixture):
    def test_release_mandatory_survives_empty_and_documentation_only_diff(self):
        for paths in ([], ['README.md']):
            with self.subTest(paths=paths):
                result = self.selection(paths, 'release')
                ids = {row['id'] for row in result['selected']}
                self.assertTrue(set(self.rules['mandatory']).issubset(ids))
                self.assertFalse(result['unmapped_changes'])
        self.assertEqual(self.selection(['README.md'], 'release')['documentation_exclusions'], ['README.md'])

    def test_shared_dependency_and_multiple_changes_form_union_without_duplicates(self):
        result = self.selection(['lib/shared.dart', 'lib/chat.dart', 'lib/shared.dart'])
        ids = [row['id'] for row in result['selected']]
        self.assertEqual(set(ids), {'fast', 'chat', 'groups', 'bridge'})
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(result['affected_areas'], ['chat', 'shared'])
        chat = next(row for row in result['selected'] if row['id'] == 'chat')
        self.assertEqual(len(chat['reasons']), 2)

    def test_unknown_behavior_change_expands_selection_and_reports_gap(self):
        result = self.selection(['native/unknown_bridge.config'])
        self.assertEqual(result['unmapped_changes'], ['native/unknown_bridge.config'])
        self.assertTrue(set(self.rules['conservative']).issubset({row['id'] for row in result['selected']}))

    def test_missing_and_nonexistent_baselines_are_errors(self):
        for baseline in (None, '', 'does-not-exist'):
            with self.subTest(baseline=baseline):
                with self.assertRaises(checks.InvalidPlan):
                    checks.resolve_ref(self.root, baseline)
        with self.assertRaises(checks.InvalidPlan):
            checks.make_plan(self.args(base=None), self.root, self.rules)

    def test_local_diff_includes_committed_staged_unstaged_untracked_rename_delete(self):
        self.write('lib/committed.dart', 'committed after baseline\n')
        self.git('add', 'lib/committed.dart')
        self.git('commit', '-qm', 'candidate commit')
        self.write('lib/shared.dart', 'staged change\n')
        self.git('add', 'lib/shared.dart')
        self.write('lib/chat.dart', 'unstaged change\n')
        self.write('lib/new.dart', 'new untracked\n')
        self.git('mv', 'lib/rename.dart', 'lib/renamed.dart')
        (self.root / 'lib/delete.dart').unlink()
        rows = checks.changed_files(self.root, self.base, True)
        paths = {row['path'] for row in rows}
        self.assertEqual(paths, {'lib/committed.dart', 'lib/shared.dart', 'lib/chat.dart', 'lib/new.dart',
                                 'lib/rename.dart', 'lib/renamed.dart', 'lib/delete.dart'})
        self.assertIn({'path': 'lib/new.dart', 'status': '?'}, rows)
        self.assertTrue(any(row['path'] == 'lib/delete.dart' and row['status'] == 'D' for row in rows))
        self.assertTrue(any(row['path'] == 'lib/rename.dart' and row['status'].startswith('R') for row in rows))
        self.assertEqual({row['path'] for row in checks.changed_files(self.root, self.base, False)}, {'lib/committed.dart'})

    def test_added_and_renamed_tests_are_exactly_selected_and_deleted_reference_errors(self):
        self.write('test/new_test.dart', "test('new case', () {});\n")
        self.git('mv', 'test/chat_test.dart', 'test/renamed_test.dart')
        selected = self.selection(['test/new_test.dart', 'test/chat_test.dart', 'test/renamed_test.dart'])
        changed = [row for row in selected['selected'] if row['id'].startswith('changed.')]
        self.assertEqual({tuple(row['paths']) for row in changed}, {('test/new_test.dart',), ('test/renamed_test.dart',)})
        with self.assertRaisesRegex(checks.InvalidPlan, 'Stale/missing test selector'):
            checks.validate(self.root, self.rules)

    def test_stale_name_and_capability_are_visible_errors(self):
        rules = copy.deepcopy(self.rules)
        rules['checks']['chat']['names'] = ['a removed test name']
        with self.assertRaisesRegex(checks.InvalidPlan, 'Stale test name'):
            checks.validate(self.root, rules)
        rules = copy.deepcopy(self.rules)
        rules['checks']['device'] = {'kind': 'sims', 'capability': 'removed', 'boundary': 'device', 'timeout_seconds': 10}
        with self.assertRaisesRegex(checks.InvalidPlan, 'Stale SIMS capability'):
            checks.validate(self.root, rules)

    def test_empty_required_selection_metadata_is_invalid(self):
        for group in ('fast', 'mandatory', 'conservative'):
            with self.subTest(group=group):
                rules = copy.deepcopy(self.rules)
                rules[group] = []
                with self.assertRaisesRegex(checks.InvalidPlan, 'Empty required selection group'):
                    checks.validate(self.root, rules)

    def test_candidate_identity_changes_with_source_and_bundled_javascript(self):
        self.write('assets/core.js', 'version one')
        before = checks.source_identity(self.root, checks.source_files(self.root), self.rules)
        self.write('assets/core.js', 'version two')
        after = checks.source_identity(self.root, checks.source_files(self.root), self.rules)
        self.assertNotEqual(before['source_sha256'], after['source_sha256'])
        self.assertNotEqual(before['bundle_and_config_sha256']['assets/core.js'], after['bundle_and_config_sha256']['assets/core.js'])


class ParserTest(unittest.TestCase):
    @staticmethod
    def flutter(result='success', *, skipped=False, name='actual assertion', path='test/chat_test.dart', done=True):
        return '\n'.join(json.dumps(row) for row in [
            {'type': 'suite', 'suite': {'id': 0, 'path': '/candidate/' + path}},
            {'type': 'testStart', 'test': {'id': 1, 'suiteID': 0, 'name': name}},
            {'type': 'testDone', 'testID': 1, 'result': result, 'skipped': skipped},
            {'type': 'done', 'success': done},
        ])

    def parse(self, output, **kwargs):
        return checks.parse_execution('flutter', output, kwargs.pop('code', 0), selected_paths=['test/chat_test.dart'], **kwargs)

    def test_flutter_real_case_completion_is_required(self):
        result = self.parse(self.flutter())
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['counts']['passed'], 1)
        for output in ('', '{"type":"done","success":true}', self.flutter(name='loading test/chat_test.dart'), self.flutter(name='group (setUpAll)')):
            with self.subTest(output=output):
                self.assertEqual(self.parse(output)['status'], 'BLOCKED')

    def test_flutter_assertion_failure_startup_missing_file_skip_timeout_distinct(self):
        failure = self.parse(self.flutter('failure', done=False), code=1)
        self.assertEqual(failure['status'], 'FAIL')
        self.assertEqual(failure['checkpoint'], 'test_assertion')
        startup = self.parse(self.flutter('error', name='loading test/chat_test.dart', done=False), code=1)
        self.assertEqual(startup['status'], 'BLOCKED')
        self.assertIn('startup', startup['checkpoint'])
        missing = self.parse(self.flutter(path='test/other_test.dart'))
        self.assertEqual(missing['status'], 'BLOCKED')
        self.assertEqual(missing['missing_test_files'], ['test/chat_test.dart'])
        self.assertEqual(self.parse(self.flutter(skipped=True))['status'], 'BLOCKED')
        timeout = self.parse(self.flutter(), timed_out=True)
        self.assertEqual(timeout['status'], 'BLOCKED')
        self.assertEqual(timeout['checkpoint'], 'runner_timeout')

    def test_go_package_without_cases_and_node_skips_cannot_pass(self):
        go_zero = json.dumps({'Action': 'pass', 'Package': 'fixture'})
        self.assertEqual(checks.parse_execution('go', go_zero, 0)['status'], 'BLOCKED')
        go_pass = '\n'.join([json.dumps({'Action': 'pass', 'Package': 'fixture', 'Test': 'TestCase'}), go_zero])
        self.assertEqual(checks.parse_execution('go', go_pass, 0)['status'], 'PASS')
        node_skip = '1..2\n# pass 1\n# fail 0\n# skipped 1\n'
        self.assertEqual(checks.parse_execution('node', node_skip, 0)['status'], 'BLOCKED')
        self.assertEqual(checks.parse_execution('node', '1..0\n# pass 0\n# fail 0\n# skipped 0\n', 0)['status'], 'BLOCKED')

    def test_go_failures_keep_hashed_case_and_package_identity_only(self):
        package = 'example.invalid/PRIVATE_PACKAGE_CANARY/node'
        name = 'TestPrivateNameCanary'
        events = [
            {'Action': 'output', 'Package': package, 'Test': name,
             'Output': 'PRIVATE_MESSAGE_CANARY token=PRIVATE_TOKEN_CANARY'},
            {'Action': 'fail', 'Package': package, 'Test': name},
            {'Action': 'fail', 'Package': 'another/package', 'Test': name},
            {'Action': 'fail', 'Package': package},
        ]
        parsed = checks.parse_execution('go', '\n'.join(map(json.dumps, events)), 1)
        self.assertEqual(parsed['status'], 'FAIL')
        self.assertEqual(parsed['checkpoint'], 'test_assertion')
        self.assertEqual(parsed['counts'], {'passed': 0, 'failed': 2, 'skipped': 0})
        self.assertEqual(parsed['failed_cases'], [
            {'name_sha256': checks.digest(name),
             'top_level_name_sha256': checks.digest(name),
             'package_sha256': checks.digest(package)},
            {'name_sha256': checks.digest(name),
             'top_level_name_sha256': checks.digest(name),
             'package_sha256': checks.digest('another/package')},
        ])
        encoded = json.dumps(parsed)
        for private in (package, name, 'PRIVATE_MESSAGE_CANARY', 'PRIVATE_TOKEN_CANARY'):
            self.assertNotIn(private, encoded)

    def test_go_dynamic_subtest_keeps_discoverable_parent_hash_without_private_name(self):
        parent = 'TestExistingMediaOwnership'
        name = parent + '/account=PRIVATE_ACCOUNT_CANARY/message=PRIVATE_MESSAGE_CANARY'
        parsed = checks.parse_execution('go', json.dumps({
            'Action': 'fail', 'Package': 'fixture/node', 'Test': name}), 1)
        self.assertEqual(parsed['failed_cases'], [{
            'name_sha256': checks.digest(name),
            'top_level_name_sha256': checks.digest(parent),
            'package_sha256': checks.digest('fixture/node'),
        }])
        self.assertEqual(parsed['counts']['failed'], 1)
        self.assertNotIn(parent, json.dumps(parsed))
        self.assertNotIn('PRIVATE_', json.dumps(parsed))

    def test_go_malformed_events_do_not_crash_or_invent_case_completion(self):
        malformed = ['not JSON', json.dumps(None), json.dumps([]), json.dumps(7),
                     json.dumps('PRIVATE_RAW_CANARY')]
        malformed += [json.dumps({'Action': 'fail', 'Package': 'fixture', 'Test': value})
                      for value in (False, 7, [], {'name': 'PRIVATE_OBJECT_CANARY'})]
        valid = [json.dumps({'Action': 'pass', 'Package': 'fixture', 'Test': 'TestValid'}),
                 json.dumps({'Action': 'pass', 'Package': 'fixture'})]
        parsed = checks.parse_execution('go', '\n'.join(malformed + valid), 0)
        self.assertEqual(parsed['status'], 'PASS')
        self.assertEqual(parsed['counts'], {'passed': 1, 'failed': 0, 'skipped': 0})
        self.assertEqual(parsed['failed_cases'], [])
        self.assertNotIn('PRIVATE_', json.dumps(parsed))
        self.assertEqual(checks.parse_execution('go', '\n'.join(malformed), 1)['status'], 'BLOCKED')

    def test_go_package_failure_is_process_failure_not_an_invented_failed_case(self):
        output = '\n'.join(map(json.dumps, [
            {'Action': 'pass', 'Package': 'passing', 'Test': 'TestPassed'},
            {'Action': 'pass', 'Package': 'passing'},
            {'Action': 'fail', 'Package': 'failed/PRIVATE_PACKAGE_CANARY'},
        ]))
        parsed = checks.parse_execution('go', output, 1)
        self.assertEqual(parsed['status'], 'BLOCKED')
        self.assertEqual(parsed['checkpoint'], 'test_runner_startup_or_process_failure')
        self.assertEqual(parsed['counts'], {'passed': 1, 'failed': 0, 'skipped': 0})
        self.assertEqual(parsed['failed_cases'], [])
        self.assertNotIn('PRIVATE_', json.dumps(parsed))

    def test_go_named_failure_without_package_keeps_failure_with_unknown_identity(self):
        for package in (None, '', 7, {'private': 'PRIVATE_PACKAGE_CANARY'}):
            with self.subTest(package=package):
                parsed = checks.parse_execution('go', json.dumps({
                    'Action': 'fail', 'Test': 'TestFailure', 'Package': package}), 1)
                self.assertEqual(parsed['status'], 'FAIL')
                self.assertEqual(parsed['counts']['failed'], 1)
                self.assertEqual(parsed['failed_cases'], [{
                    'name_sha256': checks.digest('TestFailure'),
                    'top_level_name_sha256': checks.digest('TestFailure'),
                    'package_sha256': None,
                }])
                self.assertNotIn('PRIVATE_', json.dumps(parsed))

    def test_python_assertion_error_startup_and_zero_cases_cannot_pass(self):
        failure = 'Ran 3 tests in 0.001s\n\nFAILED (failures=1, errors=1)\n'
        parsed = checks.parse_execution('python', failure, 1)
        self.assertEqual(parsed['status'], 'FAIL')
        self.assertEqual(parsed['counts'], {'passed': 1, 'failed': 2, 'skipped': 0})
        self.assertEqual(checks.parse_execution('python', 'Ran 0 tests in 0.001s\n\nOK\n', 0)['status'], 'BLOCKED')
        self.assertEqual(checks.parse_execution('python', 'Python could not start', 2)['status'], 'BLOCKED')

    def test_aggregate_retains_first_attempt_failure_after_passing_rerun(self):
        self.assertEqual(checks.aggregate([{'status': 'FAIL'}, {'status': 'PASS'}]), 'FAIL')
        self.assertEqual(checks.aggregate([{'status': 'BLOCKED'}, {'status': 'PASS'}]), 'BLOCKED')
        self.assertEqual(checks.aggregate([{'status': 'NOT RUN'}]), 'NOT RUN')
        self.assertEqual(checks.aggregate([]), 'NOT RUN')

    def test_timeout_does_not_erase_an_observed_product_assertion_failure(self):
        parsed = self.parse(self.flutter('failure', done=False), code=1, timed_out=True)
        self.assertEqual(parsed['status'], 'FAIL')
        self.assertEqual(parsed['checkpoint'], 'test_assertion')

    def test_compiler_startup_failure_is_blocked_with_only_safe_source_diagnostics(self):
        output = ('lib/features/feed/application/example.dart:42:7: Error: PRIVATE_TOKEN_CANARY\n'
                  + json.dumps({'type': 'error', 'error': 'Failed to load PRIVATE_MESSAGE_CANARY', 'stackTrace': ''})
                  + '\n' + json.dumps({'type': 'done', 'success': False}))
        parsed = self.parse(output, code=1)
        self.assertEqual(parsed['status'], 'BLOCKED')
        diagnostics = parsed.get('compilation_diagnostics', [])
        self.assertTrue(diagnostics)
        self.assertIn({'source_path': 'lib/features/feed/application/example.dart', 'line': 42,
                       'column': 7, 'error_kind': 'compilation_error'}, diagnostics)
        encoded = json.dumps(parsed)
        self.assertNotIn('PRIVATE_TOKEN_CANARY', encoded)
        self.assertNotIn('PRIVATE_MESSAGE_CANARY', encoded)


class RepositoryMappingRegressionTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[2]
        self.rules = json.loads((self.root / checks.RULES).read_text())

    def select_path(self, path):
        return checks.select(copy.deepcopy(self.rules), [{'path': path, 'status': 'M'}], 'change', [], self.root)

    def test_feature_dart_edits_do_not_match_root_entrypoint_build_rule(self):
        # fnmatch '*' crosses '/' in Python; the former lib/*.dart rule
        # accidentally broadened every feature edit into a platform rebuild.
        for path, area in [
            ('lib/features/feed/presentation/screens/feed_screen.dart', 'feed'),
            ('lib/features/conversation/application/send_chat_message_use_case.dart', 'conversation'),
        ]:
            with self.subTest(path=path):
                selected = self.select_path(path)
                self.assertIn(area, selected['affected_areas'])
                self.assertNotIn('platform-build', selected['affected_areas'])

    def test_bridge_contract_keeps_dependent_feature_checks(self):
        selected = self.select_path('lib/core/bridge/p2p_bridge_client.dart')
        ids = {row['id'] for row in selected['selected']}
        self.assertTrue({'affected-conversation', 'affected-groups', 'affected-media', 'affected-push'}.issubset(ids))
        self.assertIn('transport', selected['affected_areas'])


class ExternalReportRegressionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mknoon-report-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'sims.json'

    @staticmethod
    def verdict(capability='fixture.executed', **updates):
        row = {'capabilityId': capability, 'status': 'PASS', 'assertionsAttempted': 1,
               'artifactPresent': True, 'exitCode': 0, 'printOnly': False, 'blocker': None}
        row.update(updates)
        return row

    def inspect(self, rows, capability='fixture.executed', code=0, timeout=False, **updates):
        report = {'verdicts': rows, 'validationErrors': [], 'builds': {}, 'plan': {'rows': [
            {'id': row['capabilityId'], 'allowedNaReason': 'target_unavailable_by_project_policy'} for row in rows]}}
        report.update(updates)
        self.path.write_text(json.dumps(report))
        return checks.inspect_sims(self.path, capability, code, timeout)

    def test_sims_only_complete_unique_executed_success_can_pass(self):
        self.assertEqual(self.inspect([self.verdict()])['status'], 'PASS')
        self.assertEqual(self.inspect([])['status'], 'BLOCKED')
        self.assertEqual(self.inspect([self.verdict(), self.verdict()])['status'], 'BLOCKED')
        for update in ({'printOnly': True}, {'exitCode': 1}, {'exitCode': None}, {'status': 'UNKNOWN'},
                       {'status': 'SKIP'}, {'assertionsAttempted': 0}, {'artifactPresent': False}):
            with self.subTest(update=update):
                self.assertEqual(self.inspect([self.verdict(**update)])['status'], 'BLOCKED')
        self.assertEqual(self.inspect([self.verdict()], validationErrors=['schema failure'])['status'], 'BLOCKED')

    def test_sims_timeout_preserves_observed_failure(self):
        self.assertEqual(self.inspect([self.verdict(status='FAIL', exitCode=1)], timeout=True)['status'], 'FAIL')
        self.assertEqual(self.inspect([self.verdict()], timeout=True)['status'], 'BLOCKED')

    def test_policy_na_only_satisfies_full_aggregate_with_a_real_pass(self):
        na = self.verdict('fixture.unavailable', status='N/A', assertionsAttempted=0,
                          artifactPresent=False, exitCode=None, printOnly=False,
                          blocker='targetUnavailable', targetCapabilityAvailable=False,
                          reason='target_unavailable_by_project_policy')
        self.assertEqual(self.inspect([self.verdict(), na], capability='*')['status'], 'PASS')
        self.assertEqual(self.inspect([na], capability='fixture.unavailable')['status'], 'BLOCKED')
        self.assertEqual(self.inspect([na], capability='*')['status'], 'BLOCKED')
        for update in ({'reason': 'credentials unavailable'}, {'blocker': 'credentials'},
                       {'targetCapabilityAvailable': True}, {'printOnly': True}):
            with self.subTest(update=update):
                self.assertEqual(self.inspect([self.verdict(), {**na, **update}], capability='*')['status'], 'BLOCKED')

    def legacy_fixture(self):
        logs = self.root / 'logs'
        logs.mkdir(exist_ok=True)
        rows = []
        for index in range(95):
            log = logs / f'{index + 1:03d}.log'
            log.write_text('All tests passed!\n')
            rows.append(f'PASS\tcase {index + 1}\t{log}\t1s')
        (self.root / 'summary.tsv').write_text('\n'.join(rows) + '\n')
        return logs / '010.log'

    def test_legacy_95_pass_routes_cannot_hide_skipped_or_zero_case_logs(self):
        target = self.legacy_fixture()
        self.assertEqual(checks.inspect_legacy(self.root, 0, False)['status'], 'PASS')
        for output in ('No tests ran.\n', 'Ran 0 tests in 0.01s\nOK\n',
                       '00:01 +4 ~1: All tests passed!\n', '--- SKIP: TestUnavailable (0.00s)\n',
                       'Ran 4 tests in 0.01s\nOK (skipped=1)\n', '# pass 4\n# skipped 1\n'):
            with self.subTest(output=output):
                target.write_text(output)
                self.assertEqual(checks.inspect_legacy(self.root, 0, False)['status'], 'BLOCKED')


class EvidenceAndExecutionTest(RepositoryFixture):
    def test_sdk_different_from_resolved_flutter_package_is_a_blocked_prerequisite(self):
        executable = self.write('sdk-on-path/bin/flutter', 'not executed')
        other_package = self.root / 'sdk-resolved/packages/flutter'
        other_package.mkdir(parents=True)
        config = self.write('.dart_tool/package_config.json', json.dumps({'packages': [
            {'name': 'flutter', 'rootUri': other_package.as_uri()}]}))
        with mock.patch.object(checks.shutil, 'which', return_value=str(executable)):
            self.assertTrue(checks.flutter_sdk_mismatch(self.root))
            reasons = checks.prerequisites({'kind': 'flutter'}, self.root, {}, {})
            self.assertTrue(any('Flutter SDK on PATH differs' in reason for reason in reasons))
            matched = executable.parent.parent / 'packages/flutter'
            config.write_text(json.dumps({'packages': [{'name': 'flutter', 'rootUri': matched.as_uri()}]}))
            self.assertFalse(checks.flutter_sdk_mismatch(self.root))
            self.assertFalse(checks.prerequisites({'kind': 'flutter'}, self.root, {}, {}))

    def test_missing_devices_and_unisolated_config_are_blocked_prerequisites(self):
        check = {'kind': 'sims', 'device_roles': ['android_physical', 'android_emulator']}
        self.assertTrue(checks.prerequisites(check, self.root, {}, {}))
        config = {'isolated_test_environment': True, 'devices': {'android_physical': 'p', 'android_emulator': 'e'}, 'fixture_reference': 'disposable'}
        matrix = {'flutter': [{'id': 'p', 'targetPlatform': 'android-arm64', 'emulator': False}], 'adb': ['p']}
        self.assertIn('target unavailable: android_emulator', checks.prerequisites(check, self.root, config, matrix))

    def manual_fixture(self):
        receipt = self.write('.codex-test-logs/manual/receipt.json', '{"observed":true}\n')
        identity = {'source_sha256': 'source', 'rules_sha256': 'rules'}
        artifacts = {'candidate.apk': 'artifact'}
        check = dict(self.rules['checks']['manual'], id='manual')
        evidence = {**identity, 'artifact_sha256': artifacts, 'checks': {'manual': {
            'status': 'PASS', 'reviewer': 'isolated-reviewer', 'observed_at': '2026-09-10T12:00:00Z',
            'assertions_observed': ['reopen', 'receive'],
            'receipts': [{'path': str(receipt.relative_to(self.root)), 'sha256': checks.file_hash(receipt)}],
        }}}
        return check, evidence, identity, artifacts, receipt

    def test_manual_evidence_requires_matching_source_rules_artifact_and_receipt(self):
        check, evidence, identity, artifacts, receipt = self.manual_fixture()
        self.assertEqual(checks.manual_result(check, evidence, identity, self.root, artifacts)['status'], 'PASS')
        self.assertEqual(checks.manual_result(check, {}, identity, self.root, artifacts)['status'], 'BLOCKED')
        for key in ('source_sha256', 'rules_sha256', 'artifact_sha256'):
            changed = copy.deepcopy(evidence)
            changed[key] = 'changed'
            self.assertEqual(checks.manual_result(check, changed, identity, self.root, artifacts)['status'], 'BLOCKED')
        incomplete = copy.deepcopy(evidence)
        incomplete['checks']['manual']['assertions_observed'] = ['receive']
        self.assertEqual(checks.manual_result(check, incomplete, identity, self.root, artifacts)['status'], 'BLOCKED')
        receipt.write_text('changed receipt')
        changed = checks.manual_result(check, evidence, identity, self.root, artifacts)
        self.assertEqual(changed['checkpoint'], 'evidence_receipt_missing_or_changed')
        receipt.unlink()
        self.assertEqual(checks.manual_result(check, evidence, identity, self.root, artifacts)['status'], 'BLOCKED')

    def execute_fixture(self, **kwargs):
        args = self.args(**kwargs)
        directory = self.root / '.codex-test-logs' / ('run-' + str(time.monotonic_ns()))
        directory.mkdir(parents=True)
        with mock.patch.object(checks, 'toolchain_identity', return_value={'fixture_python': sys.executable}):
            plan, files = checks.make_plan(args, self.root, self.rules)
        for row in plan['selected']:
            row['blocked_prerequisites'] = []
        real_launch = checks.launch
        def isolated_launch(command, *args):
            self.assertEqual(command[0], sys.executable, 'execution fixture must never launch application/native/device tools')
            return real_launch(command, *args)
        with contextlib.redirect_stdout(io.StringIO()), \
                mock.patch.object(checks, 'launch', side_effect=isolated_launch), \
                mock.patch.object(checks, 'toolchain_identity', return_value={'fixture_python': sys.executable}):
            code = checks.execute_plan(args, self.root, self.rules, plan, files, {}, {}, directory, time.monotonic())
        return code, json.loads((directory / 'results.json').read_text())

    def test_real_unittest_process_reports_automated_pass_but_missing_manual_blocks_release(self):
        code, report = self.execute_fixture(mode='release')
        self.assertNotEqual(code, 0)
        self.assertEqual(report['automated_status'], 'PASS')
        self.assertEqual(report['status'], 'BLOCKED')
        rows = {row['id']: row for row in report['results']}
        self.assertEqual(rows['fast']['attempts'][0]['counts']['passed'], 1)
        self.assertEqual(rows['manual']['checkpoint'], 'required_evidence_missing')

    def test_diagnostic_subset_retains_unexecuted_mandatory_check(self):
        code, report = self.execute_fixture(mode='release', only='fast')
        self.assertNotEqual(code, 0)
        manual = next(row for row in report['results'] if row['id'] == 'manual')
        self.assertEqual(manual['status'], 'NOT RUN')
        self.assertEqual(manual['checkpoint'], 'diagnostic_subset')

    def test_source_modified_during_passing_execution_invalidates_evidence(self):
        self.write('fixture_test.py', 'import unittest\nfrom pathlib import Path\nclass Fixture(unittest.TestCase):\n    def test_mutates_candidate(self):\n        Path("lib/shared.dart").write_text("changed during run")\n        self.assertTrue(True)\n')
        code, report = self.execute_fixture()
        self.assertNotEqual(code, 0)
        self.assertEqual(report['automated_status'], 'PASS')
        self.assertEqual(report['status'], 'BLOCKED')
        self.assertTrue(any('Source/configuration changed during execution' in gap for gap in report['gaps']))

    def test_real_first_attempt_failure_and_successful_diagnostic_rerun_stay_failed(self):
        self.write('fixture_test.py', 'import unittest\nfrom pathlib import Path\nclass Fixture(unittest.TestCase):\n    def test_first_failure(self):\n        marker = Path(".codex-test-logs/attempt-marker")\n        seen = marker.exists()\n        marker.write_text("attempted")\n        self.assertTrue(seen, "intentional isolated first-attempt failure")\n')
        code, report = self.execute_fixture(rerun_failed=True)
        self.assertEqual(code, 1)
        self.assertEqual(report['status'], 'FAIL')
        attempts = next(row['attempts'] for row in report['results'] if row['id'] == 'fast')
        self.assertEqual([row['status'] for row in attempts], ['FAIL', 'PASS'])

    def test_exit_zero_shell_error_cannot_hide_behind_completion_marker(self):
        broken = 'echo COMPLETE\n(set -u; echo "$MKNOON_INTENTIONALLY_UNSET")\nexit 0\n'
        path = self.root / 'historical_runner_fixture.sh'
        path.write_text(broken)
        out, code, timeout, _ = checks.launch(['bash', str(path)], self.root, 5)
        self.assertEqual(code, 0, 'fixture must reproduce the historical false-green exit status')
        self.assertEqual(checks.parse_execution('command', out, code, timeout, success_marker='COMPLETE')['status'], 'BLOCKED')
        path.write_text('echo COMPLETE\nexit 0\n')
        out, code, timeout, _ = checks.launch(['bash', str(path)], self.root, 5)
        self.assertEqual(checks.parse_execution('command', out, code, timeout, success_marker='COMPLETE')['status'], 'PASS')

    def test_empty_node_file_completion_is_not_a_registered_test(self):
        out = 'TAP version 13\n# Subtest: /tmp/empty_test.js\nok 1 - /tmp/empty_test.js\n1..1\n# tests 1\n# pass 1\n# fail 0\n'
        result = checks.parse_execution('node', out, 0)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(result['counts']['passed'], 0)

    @unittest.skipUnless(hasattr(os, 'killpg'), 'POSIX process groups required')
    def test_timeout_terminates_descendants_that_ignore_sigterm(self):
        ready = self.root / '.codex-test-logs/ready'
        ready.parent.mkdir()
        child = ('import os,signal,time\nfrom pathlib import Path\n'
                 'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                 f'Path({str(ready)!r}).write_text(str(os.getpid()))\n'
                 'time.sleep(30)\n')
        parent = ('import subprocess,sys,time\nfrom pathlib import Path\n'
                  f'p=subprocess.Popen([sys.executable,"-c",{child!r}])\n'
                  f'while not Path({str(ready)!r}).exists(): time.sleep(0.01)\n'
                  'time.sleep(30)\n')
        pid = None
        try:
            _, _, timed_out, seconds = checks.launch([sys.executable, '-c', parent], self.root, 0.5)
            self.assertTrue(timed_out)
            self.assertLess(seconds, 6)
            self.assertTrue(ready.exists(), 'child must have installed the SIGTERM handler before timeout')
            pid = int(ready.read_text())
            # A killed child can briefly remain a zombie until adopted/reaped.
            state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], text=True, capture_output=True).stdout.strip()
            self.assertFalse(state and not state.startswith('Z'), 'timeout left a live descendant ignoring SIGTERM')
        finally:
            if pid is None and ready.exists(): pid = int(ready.read_text())
            if pid is not None:
                try: os.kill(pid, signal.SIGKILL)
                except ProcessLookupError: pass


if __name__ == '__main__':
    unittest.main()
