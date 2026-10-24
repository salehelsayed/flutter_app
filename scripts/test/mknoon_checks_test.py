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
from concurrent.futures import ThreadPoolExecutor
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
        # These repositories run synthetic tasks only. Keep the real locking
        # behavior, but do not contend with live device campaigns on this host.
        real_leases = checks.device_preflight.device_leases
        def fixture_leases(targets, directory=None):
            return real_leases(targets, directory=(directory if directory is not None
                               else self.root / '.codex-test-logs/fixture-leases'))
        lease_patch = mock.patch.object(checks.device_preflight, 'device_leases', fixture_leases)
        lease_patch.start()
        self.addCleanup(lease_patch.stop)
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
                'fast': {'kind': 'python', 'paths': ['fixture_test.py'], 'boundary': 'workflow fixture', 'timeout_seconds': 10, 'resources': ['isolated:workflow-fixture']},
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
    def test_android_sims_policy_and_adapter_validation_fail_closed(self):
        self.write('tool/sims/critical_features.json', json.dumps({'capabilities': [{'id': 'fixture.android'}]}))
        adapter = 'integration_test/scripts/fixture_android.dart'
        self.write(adapter, '// fixture adapter, not executed\n')
        check = {'kind': 'sims', 'capability': 'fixture.android', 'boundary': 'Android fixture',
                 'timeout_seconds': 10, 'device_roles': ['android_physical', 'android_emulator'],
                 'adapter': adapter, 'requires_disposable_android_package': True,
                 'ui_driver': 'existing_campaign', 'ui_driver_reason': 'Isolated scheduler fixture'}
        self.rules['checks']['android'] = check
        checks.validate(self.root, self.rules)
        for update in ({'adapter': '../other.dart'}, {'adapter': 'integration_test/scripts/missing.dart'},
                       {'disposable_android_package': 'com.mknoon.app'},
                       {'requires_disposable_android_package': False}):
            with self.subTest(update=update):
                rules = copy.deepcopy(self.rules)
                rules['checks']['android'].update(update)
                with self.assertRaises(checks.InvalidPlan):
                    checks.validate(self.root, rules)
        del check['requires_disposable_android_package']
        with self.assertRaises(checks.InvalidPlan):
            checks.validate(self.root, self.rules)

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

    def test_workspace_access_metadata_does_not_hide_native_plist_changes(self):
        repository_rules = json.loads((Path(__file__).resolve().parents[2] /
                                       'tool/testing/selection.json').read_text())
        self.rules['evidence_exclusions'] = repository_rules['evidence_exclusions']
        self.write('info.plist', '<key>LastAccessedDate</key><date>earlier</date>')
        self.write('ios/Runner/Info.plist', '<key>CFBundleVersion</key><string>1</string>')
        before = checks.source_identity(self.root, checks.source_files(self.root), self.rules)
        self.write('info.plist', '<key>LastAccessedDate</key><date>later</date>')
        accessed = checks.source_identity(self.root, checks.source_files(self.root), self.rules)
        self.assertEqual(before['source_sha256'], accessed['source_sha256'])
        self.write('ios/Runner/Info.plist', '<key>CFBundleVersion</key><string>2</string>')
        changed = checks.source_identity(self.root, checks.source_files(self.root), self.rules)
        self.assertNotEqual(accessed['source_sha256'], changed['source_sha256'])


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

    def test_flutter_skip_keeps_discoverable_identity_without_raw_reason_or_name(self):
        private_name = 'conditional case private-recipient-canary'
        output = self.flutter(skipped=True, name=private_name) + '\n' + json.dumps({
            'type': 'print', 'message': 'private-skip-reason-canary',
        })
        parsed = self.parse(output)
        self.assertEqual(parsed['status'], 'BLOCKED')
        self.assertEqual(parsed['failed_cases'], [])
        self.assertEqual(len(parsed['skipped_cases']), 1)
        case = parsed['skipped_cases'][0]
        self.assertEqual(case['name_sha256'], checks.digest(private_name))
        self.assertTrue(case['suite_path'].endswith('/test/chat_test.dart'))
        self.assertNotIn('private-recipient-canary', json.dumps(parsed))
        self.assertNotIn('private-skip-reason-canary', json.dumps(parsed))

    def test_go_skip_keeps_parent_and_package_hash_without_turning_into_pass(self):
        parent = 'TestLoopbackFeasibility'
        name, package = parent + '/private-peer-canary', 'private-import-canary'
        output = '\n'.join(json.dumps(row) for row in [
            {'Action': 'output', 'Output': 'private-skip-reason-canary'},
            {'Action': 'skip', 'Test': name, 'Package': package},
            {'Action': 'pass', 'Test': 'TestOther', 'Package': package},
            {'Action': 'pass', 'Package': package},
        ])
        parsed = checks.parse_execution('go', output, 0)
        self.assertEqual(parsed['status'], 'BLOCKED')
        self.assertEqual(parsed['counts'], {'passed': 1, 'failed': 0, 'skipped': 1})
        self.assertEqual(parsed['skipped_cases'], [{
            'name_sha256': checks.digest(name),
            'top_level_name_sha256': checks.digest(parent),
            'package_sha256': checks.digest(package),
        }])
        self.assertEqual(parsed['failed_cases'], [])
        self.assertNotIn('private-', json.dumps(parsed))

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

    def test_capability_dispatch_executes_assertions_instead_of_only_building(self):
        capability = 'fixture.executed'
        command, selected = checks.command_for({'kind': 'sims', 'capability': capability}, self.root, [])
        # Model the real CLI distinction: --prepare-builds retains build rows
        # only. The existing report verifier must never accept those as proof.
        rows = [self.verdict('build.fixture')] if '--prepare-builds' in command else [self.verdict(capability)]
        self.assertEqual(selected, [capability])
        self.assertEqual(self.inspect(rows)['status'], 'PASS')
        self.assertEqual(self.inspect([self.verdict('build.fixture')])['checkpoint'], 'zero_capability_execution')

    def test_fixture_adapter_is_the_execution_owner_when_mapped(self):
        check = {'kind': 'sims', 'capability': 'android.production_1to1_audio_call',
                 'adapter': 'integration_test/scripts/run_production_audio_call_sims.dart'}
        command, selected = checks.command_for(check, self.root, [])
        self.assertEqual(command, ['dart', 'run', check['adapter'], '--mode', 'major', '--scenario', check['capability']])
        self.assertEqual(selected, [check['capability']])

    def test_sims_timeout_preserves_observed_failure(self):
        self.assertEqual(self.inspect([self.verdict(status='FAIL', exitCode=1)], timeout=True)['status'], 'FAIL')
        self.assertEqual(self.inspect([self.verdict()], timeout=True)['status'], 'BLOCKED')

    def test_fixture_cohort_cannot_pass_on_its_anchor_without_the_additional_case(self):
        manifest = self.root / 'tool/sims/critical_features.json'
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({'capabilities': [
            dict(id='build.fixture', modes=['major']),
            dict(id='fixture.executed', modes=['major'], dependencies=['build.fixture']),
            dict(id='kx0020', modes=['major'], dependencies=['build.fixture']),
        ]}))
        check = dict(kind='sims', capability='fixture.executed', additional_capabilities=['kx0020'],
                     adapter='integration_test/scripts/run_production_audio_call_sims.dart')
        command, selected = checks.command_for(check, self.root, [])
        self.assertIn('--include-regressions', command)
        self.assertEqual(set(selected), {'fixture.executed', 'kx0020', 'build.fixture'})
        self.inspect([self.verdict(), self.verdict('build.fixture')])
        result = checks.inspect_sims(self.path, '*', 0, False, selected)
        self.assertEqual(result['checkpoint'], 'incomplete_sims_selection')
        self.inspect([self.verdict(), self.verdict('build.fixture'), self.verdict('kx0020', status='FAIL')])
        self.assertEqual(checks.inspect_sims(self.path, '*', 1, False, selected)['status'], 'FAIL')

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

    def test_legacy_skip_parser_distinguishes_progress_counts_from_estimates(self):
        for output in ('[07:40:50.820] [ORCH] Scenario E1: Sending ~100KB message...\n',
                       'transfer completed in ~12 ms\nAll tests passed!\n',
                       '100 tests passed\n', '00:01 +4 ~0: All tests passed!\n'):
            with self.subTest(output=output):
                self.assertIsNone(checks.legacy_log_incomplete_checkpoint(output))
        for output in ('00:01 +4 ~1: All tests passed!\n',
                       '[ALICE] flutter: 01:02:03 +4 -1 ~2: scenario\n',
                       '00:01 ~1: scenario\n',
                       '00:01 \x1b[32m+4\x1b[0m \x1b[33m~1\x1b[0m: All tests passed!\n'):
            with self.subTest(output=output):
                self.assertEqual(checks.legacy_log_incomplete_checkpoint(output),
                                 'legacy_skipped_tests')


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
            sims_reasons = checks.prerequisites({'kind': 'sims', 'requirements': ['flutter']}, self.root, {}, {})
            self.assertTrue(any('Flutter SDK on PATH differs' in reason for reason in sims_reasons))
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

    def test_actual_android_campaign_requires_a_disposable_package_before_launch(self):
        check = {'kind': 'sims', 'capability': 'android.direct_media_blob_custody',
                 'device_roles': ['android_physical', 'android_emulator'],
                 'requires_disposable_android_package': True}
        config = {'isolated_test_environment': True,
                  'devices': {'android_physical': 'p', 'android_emulator': 'e'},
                  'fixture_reference': 'real disposable fixture'}
        matrix = {'flutter': [{'id': 'p', 'targetPlatform': 'android-arm64', 'emulator': False},
                              {'id': 'e', 'targetPlatform': 'android-arm64', 'emulator': True}], 'adb': ['p', 'e']}
        for package in (None, 'com.mknoon.app', 'com.mknoon.sims.', 'com.mknoon.sims.bad-id', False):
            with self.subTest(package=package):
                config['sims_android_packages'] = {check['capability']: package}
                reasons = checks.prerequisites(check, self.root, config, matrix)
                self.assertTrue(any('disposable Android package' in reason for reason in reasons))
        config['sims_android_packages'] = {check['capability']: 'com.mknoon.sims.directmedia'}
        self.assertEqual(checks.prerequisites(check, self.root, config, matrix), [])
        env = checks.sims_environment(config, self.root / 'report.json', check)
        for name in ('ANDROID_APP_PACKAGE', 'SIMS_APP_ID', 'ORG_GRADLE_PROJECT_androidApplicationId'):
            self.assertEqual(env[name], 'com.mknoon.sims.directmedia')
        self.assertEqual(env['RELIABILITY_MULTI_DEVICE_IDS'], 'p,e')

    def test_fixed_campaign_package_cannot_be_redirected_by_config(self):
        check = {'kind': 'sims', 'capability': 'android.production_1to1_audio_call',
                 'disposable_android_package': 'com.mknoon.sims.productionaudio'}
        config = {'devices': {'android_physical': 'p', 'android_emulator': 'e'}}
        env = checks.sims_environment(config, self.root / 'report.json', check)
        self.assertEqual(env['ANDROID_APP_PACKAGE'], check['disposable_android_package'])
        config['sims_android_packages'] = {check['capability']: 'com.mknoon.sims.other'}
        with self.assertRaises(checks.InvalidPlan):
            checks.sims_environment(config, self.root / 'report.json', check)

    def test_fcm_campaign_requires_matching_config_without_exposing_values(self):
        check = {'kind': 'sims', 'capability': 'notifications.android_payload_campaign',
                 'disposable_android_package': 'com.mknoon.sims.notifications',
                 'requires_firebase_android_client': True, 'device_roles': []}
        config = {'isolated_test_environment': True, 'fixture_reference': 'real downloaded fixture'}
        path = 'android/app/google-services.json'
        for contents in (None, '{', json.dumps({'client': [{'client_info': {
                'android_client_info': {'package_name': 'com.mknoon.app'}}}]})):
            with self.subTest(contents=contents):
                if contents is not None:
                    self.write(path, contents)
                reasons = checks.prerequisites(check, self.root, config, {})
                self.assertIn('Matching Firebase Android client configuration required for disposable package', reasons)
        self.write(path, json.dumps({'project_info': {'project_id': 'isolated-fixture'}, 'client': [{'client_info': {
            'mobilesdk_app_id': 'fixture-app', 'android_client_info': {'package_name': 'com.mknoon.sims.notifications'}}}]}))
        self.assertEqual(checks.prerequisites(check, self.root, config, {}), [])

    def test_fcm_campaign_checks_explicit_production_package_binding(self):
        check = {'kind': 'sims', 'requires_firebase_android_client': True,
                 'environment': {'ANDROID_APP_PACKAGE': 'com.mknoon.app'}, 'device_roles': []}
        config = {'isolated_test_environment': True, 'fixture_reference': 'authorized guarded app'}
        path = 'android/app/google-services.json'
        self.write(path, json.dumps({'project_info': {'project_id': 'isolated-fixture'},
            'client': [{'client_info': {'mobilesdk_app_id': 'fixture-app',
            'android_client_info': {'package_name': 'com.mknoon.app'}}}]}))
        self.assertEqual(checks.prerequisites(check, self.root, config, {}), [])
        check['environment']['ANDROID_APP_PACKAGE'] = 'com.mknoon.unregistered'
        self.assertTrue(checks.prerequisites(check, self.root, config, {}))

    def test_package_binding_does_not_invent_android_roles_for_ios(self):
        env = checks.sims_environment({'devices': {'ios_physical': 'i'}}, self.root / 'report.json',
                                     {'kind': 'sims', 'capability': 'notifications.ios_payload_fast_path'})
        self.assertEqual(env['SIMS_IOS_DEVICE_ID'], 'i')
        self.assertNotIn('RELIABILITY_MULTI_DEVICE_IDS', env)
        self.assertNotIn('ANDROID_APP_PACKAGE', env)

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

    def test_capacity_failure_cannot_pass_with_a_prior_success_marker(self):
        self.write('fixture_test.py', "import unittest\nclass Fixture(unittest.TestCase):\n"
                   "    def test_fixture(self):\n        print('Ran 1 test\\nOK', flush=True)\n"
                   "        print('x' * 4096, flush=True)\n")
        budget = checks.CaptureBudget(stream_limit=1024, run_limit=8192)
        with mock.patch.object(checks, 'CaptureBudget', return_value=budget):
            code, report = self.execute_fixture(only='fast')
        row = next(row for row in report['results'] if row['id'] == 'fast')
        self.assertEqual(code, 1)
        self.assertEqual(row['status'], 'FAIL')
        self.assertEqual(row['attempts'][0]['checkpoint'], 'evidence_capacity')
        self.assertEqual(row['attempts'][0]['evidence_capacity_failure']['stream'], 'stdout')
        self.assertLessEqual(report['capture_budget']['charged_bytes'], 8192)

    def test_screenshot_capacity_invalidates_pass_and_is_not_retried(self):
        self.write('fixture_test.py', 'import os,unittest\nfrom pathlib import Path\n'
            'class Fixture(unittest.TestCase):\n    def test_fixture(self):\n'
            '        p=Path(os.environ["MKNOON_CAPTURE_ROOT"]); p.mkdir(parents=True)\n'
            '        (p/"one.png").write_bytes(b"x"*11)\n')
        real_check = checks.check_screenshots
        with mock.patch.object(checks, 'check_screenshots', side_effect=lambda path: real_check(path, file_limit=10)):
            code, report = self.execute_fixture(only='fast', rerun_failed=True)
        row = next(row for row in report['results'] if row['id'] == 'fast')
        self.assertEqual(code, 1)
        self.assertEqual(row['status'], 'FAIL')
        self.assertEqual(len(row['attempts']), 1)
        self.assertEqual(row['attempts'][0]['evidence_capacity_failure']['stream'], 'screenshots')

    def test_retention_failure_invalidates_a_completed_passing_report(self):
        _, report = self.execute_fixture(only='fast')
        directory = self.root / '.codex-test-logs/retention-fixture'
        directory.mkdir()
        owner = mock.Mock()
        owner.finish.side_effect = checks.RetentionCapacityError('evidence_capacity: protected evidence')
        def inner(argv, managed):
            managed.update(owner=owner, path=directory)
            (directory / 'results.json').write_text(json.dumps(report))
            return 0
        with mock.patch.object(checks, '_main', side_effect=inner), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = checks.main([])
        failed = json.loads((directory / 'results.json').read_text())
        self.assertEqual(code, 93)
        self.assertEqual(failed['status'], 'FAIL')
        self.assertEqual(failed['run_failure'], 'evidence_capacity')
        self.assertEqual(failed['automated_status'], 'PASS')
        self.assertIn('overall: FAIL', (directory / 'summary.txt').read_text())

    def test_native_capacity_exit_cannot_be_hidden_by_missing_or_passing_report(self):
        path = self.root / 'sims.json'
        for exists in (False, True):
            if exists:
                path.write_text(json.dumps({'verdicts': [ExternalReportRegressionTest.verdict('fixture.device')]}))
            result = checks.inspect_sims(path, 'fixture.device', 93, False)
            self.assertEqual(result['status'], 'FAIL')
            self.assertEqual(result['checkpoint'], 'evidence_capacity')

    def test_cancelled_run_audits_toolchains_without_cancelling_version_probes(self):
        self.write('lib/shared.dart', 'changed for isolated cancellation fixture\n')
        args = self.args(only='chat')
        directory = self.root / '.codex-test-logs/cancelled-audit'
        directory.mkdir(parents=True)
        def probe(root):
            out, code, timeout, _ = checks.launch(
                [sys.executable, '-c', 'import time; time.sleep(.05); print("fixture-toolchain")'],
                root, 5)
            return {'fixture': out.strip(), 'available': code == 0 and not timeout}
        with mock.patch.object(checks, 'toolchain_identity', side_effect=probe):
            plan, files = checks.make_plan(args, self.root, self.rules)
        cancelled = False
        def cancel_after_omitted_check(*values, **kwargs):
            nonlocal cancelled
            if not cancelled and values[:1] == ('NOT RUN',):
                cancelled = True
                handler = signal.getsignal(signal.SIGTERM)
                self.assertTrue(callable(handler))
                handler(signal.SIGTERM, None)
        real_launch = checks.launch
        def isolated_launch(command, *values):
            self.assertEqual(command[0], sys.executable)
            return real_launch(command, *values)
        try:
            with contextlib.redirect_stdout(io.StringIO()), \
                    mock.patch.object(checks, 'print', side_effect=cancel_after_omitted_check, create=True), \
                    mock.patch.object(checks, 'launch', side_effect=isolated_launch), \
                    mock.patch.object(checks, 'toolchain_identity', side_effect=probe):
                code = checks.execute_plan(args, self.root, self.rules, plan, files, {}, {}, directory, time.monotonic())
            report = json.loads((directory / 'results.json').read_text())
            self.assertTrue(cancelled)
            self.assertNotEqual(code, 0)
            self.assertIn('Run cancelled; unfinished obligations retained', report['gaps'])
            self.assertNotIn('Toolchain or resolved package configuration changed during execution', report['gaps'])
        finally:
            checks._LAUNCH_CONTEXT.__dict__.clear()

    def test_real_unittest_process_reports_automated_pass_but_missing_manual_blocks_release(self):
        # Only a Python child in a temporary repository runs here. It must not
        # contend with an actual Flutter/native build in another check.
        with mock.patch.object(checks.device_preflight, 'device_leases',
                               side_effect=AssertionError('Python fixture requested a native/device lease')):
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

    def test_device_only_subset_executes_without_promoting_omitted_host_checks(self):
        code, report, launched = self.execute_device_subset()
        rows = {r['id']: r for r in report['results']}
        self.assertEqual(rows['device']['status'], 'PASS')
        self.assertEqual(rows['fast']['status'], 'NOT RUN')
        self.assertEqual(report['status'], 'NOT RUN')
        self.assertNotEqual(code, 0)
        self.assertEqual(len(launched), 2, 'only fake device execution and report verification run')

    def test_completed_host_skips_remain_blocked_but_allow_independent_device(self):
        code, report, launched = self.execute_device_subset(host_status='SKIPS')
        rows = {row['id']: row for row in report['results']}
        self.assertEqual(rows['fast']['status'], 'BLOCKED')
        self.assertEqual(rows['fast']['attempts'][0]['counts'], dict(passed=1, failed=0, skipped=1))
        self.assertEqual(rows['device']['status'], 'PASS')
        self.assertEqual(report['status'], 'BLOCKED')
        self.assertNotEqual(code, 0)
        self.assertEqual(len([cmd for cmd in launched if cmd[0] == 'dart']), 2)

    def test_skipped_host_explicit_dependency_still_blocks_device(self):
        _, report, launched = self.execute_device_subset(host_status='SKIPS', host_dependency=True)
        rows = {row['id']: row for row in report['results']}
        self.assertEqual(rows['device']['checkpoint'], 'dependency_failed')
        self.assertFalse(any(cmd[0] == 'dart' for cmd in launched))

    def test_selected_host_failure_or_unavailable_prerequisite_still_blocks_device(self):
        for status in ('FAIL', 'BLOCKED'):
            with self.subTest(status=status):
                _, report, launched = self.execute_device_subset(host_status=status)
                rows = {r['id']: r for r in report['results']}
                self.assertEqual(rows['fast']['status'], status)
                self.assertEqual(rows['device']['status'], 'NOT RUN')
                self.assertEqual(rows['device']['checkpoint'], 'host_prerequisite_failed')
                self.assertFalse(any(command[0] == 'dart' for command in launched))

    def execute_device_subset(self, host_status=None, preflight_status=None, device_failure=False, retry=False, second_device=False, verification_failure=False, host_dependency=False):
        self.write('tool/sims/critical_features.json', json.dumps({'capabilities': [{'id': 'fixture.device'}]}))
        self.rules['checks']['device'] = {'kind': 'sims', 'capability': 'fixture.device',
                                          'boundary': 'fake device scheduler boundary', 'timeout_seconds': 10,
                                          'device_roles': ['android_physical'],
                                          'disposable_android_package': 'com.mknoon.sims.fixture',
                                          'ui_driver': 'existing_campaign', 'ui_driver_reason': 'Isolated scheduler fixture'}
        if host_dependency:
            self.rules['checks']['device']['dependencies'] = ['fast']
        device_checks = ['device']
        if second_device:
            self.rules['checks']['device-next'] = copy.deepcopy(self.rules['checks']['device'])
            device_checks.append('device-next')
        self.rules['areas'].append({'id': 'device-fixture', 'patterns': ['lib/shared.dart', 'tool/sims/critical_features.json'],
                                    'checks': device_checks, 'why': 'isolated scheduling sentinel'})
        self.write('lib/shared.dart', 'candidate requiring the fake device boundary\n')
        args = self.args(only=','.join((['fast'] if host_status else []) + device_checks), rerun_failed=retry)
        if host_status == 'SKIPS':
            self.write('fixture_test.py', 'import unittest\nclass Fixture(unittest.TestCase):\n    def test_pass(self): pass\n    @unittest.skip("external fixture absent")\n    def test_external(self): pass\n')
        if host_status == 'FAIL':
            self.write('fixture_test.py', 'import unittest\nclass Fixture(unittest.TestCase):\n    def test_fixture(self):\n        self.fail("intentional host gate failure")\n')
        directory = self.root / '.codex-test-logs' / ('device-subset-' + str(time.monotonic_ns()))
        directory.mkdir(parents=True)
        with mock.patch.object(checks, 'toolchain_identity', return_value={'fixture_python': sys.executable}):
            plan, files = checks.make_plan(args, self.root, self.rules)
        for row in plan['selected']:
            row['blocked_prerequisites'] = ['fixture prerequisite unavailable'] if row['id'] == 'fast' and host_status == 'BLOCKED' else []
        launched = []
        real_launch = checks.launch
        def launch(command, cwd, timeout, env=None):
            launched.append(command)
            if command[0] == sys.executable:
                return real_launch(command, cwd, timeout, env)
            self.assertEqual(command[0], 'dart')
            # Stub the external boundary: this test must never start Flutter,
            # Dart, adb, an app or an external service.
            if 'verify-report' not in command:
                verdict = ExternalReportRegressionTest.verdict('fixture.device')
                if device_failure:
                    verdict.update(status='FAIL', exitCode=1)
                Path(env['SIMS_REPORT_PATH']).write_text(json.dumps({'verdicts': [verdict], 'validationErrors': []}))
            elif verification_failure:
                return '', 1, False, .001
            return '', 0, False, .001
        with contextlib.redirect_stdout(io.StringIO()), \
                mock.patch.object(checks, 'launch', side_effect=launch), \
                mock.patch.object(checks.device_preflight, 'device_leases', return_value=contextlib.nullcontext()), \
                mock.patch.object(checks.device_preflight, 'run', return_value=preflight_status or {'status': 'PASS', 'checkpoint': 'fixture_ready'}), \
                mock.patch.object(checks, 'toolchain_identity', return_value={'fixture_python': sys.executable}):
            code = checks.execute_plan(args, self.root, self.rules, plan, files, {}, {}, directory, time.monotonic())
        return code, json.loads((directory / 'results.json').read_text()), launched

    def test_device_preflight_block_never_launches_or_blindly_retries(self):
        _, report, launched = self.execute_device_subset(
            preflight_status={'status': 'BLOCKED', 'checkpoint': 'device_automation_busy'}, retry=True)
        row = next(r for r in report['results'] if r['id'] == 'device')
        self.assertEqual(row['status'], 'BLOCKED')
        self.assertEqual(row['checkpoint'], 'device_automation_busy')
        self.assertEqual(len(row['attempts']), 1)
        self.assertEqual(launched, [])

    def test_device_failure_requires_cleanup_review_before_next_campaign(self):
        _, report, launched = self.execute_device_subset(device_failure=True, retry=True, second_device=True)
        rows = {r['id']: r for r in report['results']}
        self.assertEqual(rows['device']['status'], 'FAIL')
        self.assertEqual(len(rows['device']['attempts']), 1)
        self.assertTrue(rows['device']['attempts'][0]['cleanup_review_required'])
        self.assertEqual(rows['device-next']['status'], 'NOT RUN')
        self.assertEqual(rows['device-next']['checkpoint'], 'device_cleanup_review_required')
        self.assertEqual(len(launched), 2, 'failed reports still need independent integrity verification')
        self.assertTrue(rows['device']['attempts'][0]['report_verification_observed'])

    def test_report_verification_failure_never_hides_an_observed_test_failure(self):
        for failed in (False, True):
            with self.subTest(test_failed=failed):
                _, report, launched = self.execute_device_subset(
                    device_failure=failed, verification_failure=True)
                row = next(r for r in report['results'] if r['id'] == 'device')
                self.assertEqual(row['status'], 'FAIL' if failed else 'BLOCKED')
                self.assertTrue(row['attempts'][0]['report_verification_failed'])
                self.assertFalse(row['attempts'][0].get('report_verification_observed'))
                self.assertEqual(len(launched), 2)

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


class FlutterFileReuseTest(RepositoryFixture):
    paths = ['test/chat_test.dart', 'test/groups_test.dart', 'test/bridge_test.dart']

    def execute_lanes(self, mutate=None, first_outcome=None, retry=False):
        rules = copy.deepcopy(self.rules)
        rules['fast'] = ['lane-a', 'lane-b', 'lane-c']
        for cid, paths in zip(rules['fast'], ([self.paths[0], self.paths[1]],
                [self.paths[1], self.paths[2]], [self.paths[0], self.paths[2]])):
            rules['checks'][cid] = dict(kind='flutter', paths=paths, boundary='host-only replay fixture',
                timeout_seconds=10, resources=['isolated:flutter-fixture'])
        args = self.args(rerun_failed=retry)
        directory = self.root / '.codex-test-logs' / ('reuse-' + str(time.monotonic_ns()))
        directory.mkdir(parents=True)
        with mock.patch.object(checks, 'toolchain_identity', return_value={'fixture': 'no SDK execution'}):
            plan, files = checks.make_plan(args, self.root, rules)
        for check in plan['selected']:
            check['blocked_prerequisites'] = []
        if mutate:
            mutate({c['id']: c for c in plan['selected']})
        commands = []

        def replay(command, cwd, timeout, env=None):
            self.assertEqual(command[:2], ['flutter', 'test'])
            commands.append(list(command))
            paths = [p for p in command if p in self.paths]
            self.assertTrue(paths)
            events = []
            failure = first_outcome == 'FAIL' and len(commands) == 1
            skipped = first_outcome == 'SKIP' and len(commands) == 1
            for sid, path in enumerate(paths):
                events.extend([
                    dict(type='suite', suite=dict(id=sid, path=str(self.root / path))),
                    dict(type='testStart', time=sid * 10, test=dict(id=sid, suiteID=sid, name='fixture assertion')),
                    dict(type='testDone', time=sid * 10 + 1, testID=sid,
                         result='failure' if failure and sid == 0 else 'success', skipped=skipped and sid == 0),
                ])
            events.append(dict(type='done', time=30, success=not failure))
            if first_outcome == 'CAPACITY' and len(commands) == 1:
                checks._LAUNCH_CONTEXT.capture_failure = {'stream': 'stdout', 'reason': 'fixture_capacity'}
            return '\n'.join(json.dumps(event) for event in events) + '\n', int(failure), False, .01

        # Replayed output never starts Flutter; live host admission belongs to
        # the real launch boundary, not this file-receipt fixture.
        with contextlib.redirect_stdout(io.StringIO()), \
                mock.patch.object(checks, 'launch', side_effect=replay), \
                mock.patch.object(checks.device_preflight, 'host_test_slot', side_effect=contextlib.nullcontext), \
                mock.patch.object(checks, 'toolchain_identity', return_value={'fixture': 'no SDK execution'}):
            code = checks.execute_plan(args, self.root, rules, plan, files, {}, {}, directory, time.monotonic())
        self.last_plan = plan
        return code, json.loads((directory / 'results.json').read_text()), commands, {c['id']: c for c in plan['selected']}

    def test_partial_and_complete_reuse_preserve_lanes_counts_and_direct_raw_owners(self):
        code, report, commands, selected = self.execute_lanes()
        self.assertEqual(code, 0)
        self.assertEqual([[p for p in c if p in self.paths] for c in commands],
                         [self.paths[:2], [self.paths[2]]])
        self.assertEqual(report['flutter_file_reuse'], {'eligible_file_executions': 3, 'reused_file_receipts': 3})
        rows = {row['id']: row for row in report['results']}
        for row in rows.values():
            self.assertEqual(row['command'], selected[row['id']]['command'])
            self.assertEqual(row['selected_paths'], selected[row['id']]['selected_paths'])
            self.assertEqual(row['attempts'][0]['counts'], dict(passed=2, failed=0, skipped=0))
        later = rows['lane-c']['attempts'][0]
        self.assertIsNone(later['raw_output_sha256'], 'reuse must not invent a new raw-output hash')
        self.assertEqual(later['executed_command'], [])
        self.assertTrue(checks.verify_flutter_reuse(rows['lane-c'], later, selected, rows))
        self.assertFalse(checks.verify_flutter_reuse(rows['lane-b'], rows['lane-b']['attempts'][0], selected, rows))
        context = {'mode': 'change'}
        expected = copy.deepcopy(self.last_plan)
        expected['ci'] = context
        expected['plan_sha256'] = checks.plan_fingerprint(expected)
        ci_report = copy.deepcopy(report)
        ci_report.update(ci=context, plan_sha256=expected['plan_sha256'])
        verdict = checks.verify_ci_results(expected, expected, ci_report, context,
            expected['plan_sha256'], 'success', 'success')
        self.assertEqual(verdict['status'], 'PASS')

    def test_environment_flags_and_filtered_commands_do_not_share_receipts(self):
        def environment(selected): selected['lane-b']['environment'] = {'FIXTURE_MODE': 'different'}
        def flags(selected): selected['lane-b']['command'][4] = '--concurrency=2'
        def filtered(selected): selected['lane-b']['command'] += ['--name', 'fixture assertion']
        for mutation in (environment, flags, filtered):
            with self.subTest(mutation=mutation.__name__):
                code, report, commands, _ = self.execute_lanes(mutate=mutation)
                self.assertEqual(code, 0)
                self.assertEqual([p for p in commands[1] if p in self.paths], sorted(self.paths[1:]))
                self.assertEqual(report['flutter_file_reuse']['eligible_file_executions'], 3 if mutation is filtered else 5)
                self.assertEqual([p for p in commands[-1] if p in self.paths], [self.paths[2]])

    def test_failed_skipped_and_capacity_limited_attempts_never_seed_reuse(self):
        for outcome in ('FAIL', 'SKIP', 'CAPACITY'):
            with self.subTest(outcome=outcome):
                _, report, commands, _ = self.execute_lanes(first_outcome=outcome)
                self.assertNotEqual(report['results'][0]['status'], 'PASS')
                self.assertEqual(sum(self.paths[1] in command for command in commands), 2)

    def test_explicit_retry_runs_and_preserves_the_first_failure(self):
        _, report, commands, _ = self.execute_lanes(first_outcome='FAIL', retry=True)
        first = report['results'][0]
        self.assertEqual([a['status'] for a in first['attempts']], ['FAIL', 'PASS'])
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual([p for p in commands[1] if p in self.paths], self.paths[:2])
        self.assertEqual(sum(self.paths[1] in command for command in commands), 3)

    def test_mocked_flutter_replay_does_not_consult_live_host_guard(self):
        with mock.patch.dict(os.environ, {'MKNOON_HOST_SLOT_WAIT_SECONDS': '0'}), \
                mock.patch.object(checks.device_preflight, 'default_host_guard', return_value=False) as guard:
            code, report, commands, _ = self.execute_lanes()
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(len(commands), 2)
        guard.assert_not_called()

    def test_cache_is_invocation_local(self):
        for _ in range(2):
            code, _, commands, _ = self.execute_lanes()
            self.assertEqual(code, 0)
            self.assertEqual(len(commands), 2)

    def test_ci_rejects_forged_source_context_counts_hash_or_membership(self):
        _, report, _, selected = self.execute_lanes()
        for key, value in [('source_check_id', 'absent'), ('source_log_sha256', 'a' * 64),
                           ('context_sha256', 'b' * 64), ('file_sha256', 'c' * 64),
                           ('counts', dict(passed=99, failed=0, skipped=0))]:
            with self.subTest(key=key):
                altered = copy.deepcopy(report)
                rows = {row['id']: row for row in altered['results']}
                attempt = rows['lane-c']['attempts'][0]
                attempt['reused_files'][0][key] = value
                with self.assertRaises(checks.InvalidPlan):
                    checks.verify_flutter_reuse(rows['lane-c'], attempt, selected, rows)
        rows = {row['id']: row for row in report['results']}
        rows['lane-c']['attempts'][0]['executed_paths'] = [self.paths[0]]
        with self.assertRaises(checks.InvalidPlan):
            checks.verify_flutter_reuse(rows['lane-c'], rows['lane-c']['attempts'][0], selected, rows)

    def test_changed_source_or_raw_log_cannot_reuse_an_old_receipt(self):
        ledger = checks.FlutterFileReceipts({'source': 'fixture'}, {})
        path = self.paths[0]
        log = self.root / 'first.raw.log'
        log.write_text('original raw fixture')
        counts = dict(passed=1, failed=0, skipped=0)
        attempt = dict(status='PASS', counts=counts,
                       file_results=[dict(path=path, status='PASS', counts=counts)])
        ledger.remember('context', self.root, [path], {path: checks.file_hash(self.root / path)},
                        attempt, 'owner', log, self.root)
        self.assertIsNotNone(ledger.find('context', self.root, path))
        log.write_text('changed raw fixture')
        self.assertIsNone(ledger.find('context', self.root, path))
        log.write_text('original raw fixture')
        self.write(path, 'changed source')
        self.assertIsNone(ledger.find('context', self.root, path))


class CaptureBudgetTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.saved_context = {}
        for name in ('capture_budget', 'capture_failure', 'cancel_event', 'raw_capture_path'):
            self.saved_context[name] = getattr(checks._LAUNCH_CONTEXT, name, None)
            setattr(checks._LAUNCH_CONTEXT, name, None)

    def tearDown(self):
        for name, value in self.saved_context.items():
            if value is None:
                if hasattr(checks._LAUNCH_CONTEXT, name): delattr(checks._LAUNCH_CONTEXT, name)
            else: setattr(checks._LAUNCH_CONTEXT, name, value)

    def run_script(self, script, budget):
        checks._LAUNCH_CONTEXT.capture_budget = budget
        checks._LAUNCH_CONTEXT.capture_failure = None
        return checks.launch([sys.executable, '-c', script], self.root, 8)

    def test_default_stream_budget_retains_verbose_suite_completion(self):
        payload_bytes = 9 * 1024 * 1024
        marker = b'\nVERBOSE_SUITE_COMPLETED\n'
        budget = checks.CaptureBudget()
        out, code, timed_out, _ = self.run_script(
            f"import os;os.write(1,b'x'*{payload_bytes});os.write(1,{marker!r})",
            budget)
        self.assertEqual((code, timed_out), (0, False))
        self.assertTrue(out.endswith(marker.decode()))
        self.assertEqual(out.count('x'), payload_bytes)
        self.assertEqual(budget.used, payload_bytes + len(marker))

    def test_stdout_and_stderr_have_independent_bounds(self):
        budget = checks.CaptureBudget(stream_limit=64, run_limit=128)
        out, code, timed_out, _ = self.run_script("import os;os.write(1,b'a'*48);os.write(2,b'b'*48)", budget)
        self.assertEqual((code, timed_out), (0, False))
        self.assertEqual((out.count('a'), out.count('b'), budget.used), (48, 48, 96))

    def test_default_budget_keeps_a_large_lane_stdout(self):
        out, code, timed_out, _ = self.run_script(
            "import os\nfor _ in range(16): os.write(1, b'x' * (1024 * 1024))", checks.CaptureBudget())
        self.assertEqual((code, timed_out), (0, False))
        self.assertEqual(out.count('x'), 16 * 1024 * 1024)
        self.assertNotIn('MKNOON_EVIDENCE_CAPACITY_EXCEEDED', out)

    def test_stream_overflow_keeps_prefix_and_explicit_failure(self):
        budget = checks.CaptureBudget(stream_limit=1024, run_limit=8192)
        out, code, timed_out, _ = self.run_script(
            "import os,time;os.write(1,b'PASS before overflow\\n'+b'x'*4096);time.sleep(30)", budget)
        self.assertEqual((code, timed_out), (93, False))
        self.assertTrue(out.startswith('PASS before overflow\n'))
        self.assertIn('MKNOON_EVIDENCE_CAPACITY_EXCEEDED', out)
        failure = checks._LAUNCH_CONTEXT.capture_failure
        self.assertEqual(failure['stream'], 'stdout')
        self.assertLessEqual(failure['retained_stream_bytes'], 1024)
        self.assertLessEqual(budget.used, 8192)

    def test_one_run_budget_is_shared_by_sequential_commands(self):
        budget = checks.CaptureBudget(stream_limit=64, run_limit=80)
        self.assertEqual(self.run_script("import os;os.write(1,b'a'*48)", budget)[1], 0)
        out, code, timed_out, _ = self.run_script("import os;os.write(1,b'b'*48)", budget)
        self.assertEqual((code, timed_out, budget.used), (93, False, 80))
        self.assertTrue(out.startswith('b' * 32))
        self.assertEqual(checks._LAUNCH_CONTEXT.capture_failure['reason'], 'run')

    def test_replacement_decoding_cannot_expand_the_saved_byte_allowance(self):
        budget = checks.CaptureBudget(stream_limit=64, run_limit=512)
        out, code, _, _ = self.run_script("import os;os.write(1,bytes([255])*40)", budget)
        self.assertEqual(code, 93)
        self.assertTrue(out.startswith('\ufffd' * 21))
        self.assertEqual(checks._LAUNCH_CONTEXT.capture_failure['retained_stream_bytes'], 63)

    def test_private_raw_log_is_visible_before_the_child_finishes(self):
        path = self.root / 'command.raw.log'
        release = self.root / 'release'
        budget = checks.CaptureBudget(stream_limit=1024, run_limit=8192)
        script = ("import pathlib,sys,time;print('phase-one',flush=True);"
                  "p=pathlib.Path(sys.argv[1]);\nwhile not p.exists():time.sleep(.01)\n"
                  "print('phase-two',flush=True)")
        def launch():
            checks._LAUNCH_CONTEXT.capture_budget = budget
            return checks.launch_to_log([sys.executable, '-c', script, str(release)], self.root, 8, None, path)
        with ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(launch)
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and (not path.exists() or b'phase-one' not in path.read_bytes()):
                    time.sleep(.01)
                self.assertIn(b'phase-one', path.read_bytes())
                self.assertFalse(future.done())
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            finally:
                release.write_text('continue')
            out, code, _, _ = future.result(timeout=10)
        self.assertEqual(code, 0)
        self.assertEqual(out, path.read_text())
        self.assertIn('phase-two', out)


if __name__ == '__main__':
    unittest.main()
