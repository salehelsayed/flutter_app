"""Correction-cycle regressions: synthetic host evidence, never live devices."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mknoon_checks_test import RepositoryFixture, checks
import testing_inventory as inventory

PROJECT = Path(__file__).resolve().parents[2]


class ReviewFixture(RepositoryFixture):
    def policy(self, commands=(), automatic=()):
        self.rules['full_commands'] = list(commands)
        self.rules['full_inventory'] = dict(automatic=list(automatic), listings=[],
                                           mappings=[], exclusions=[], catalogs=[])

    def execute(self, plan, files, config=None):
        out = self.root / '.codex-test-logs' / str(time.monotonic_ns())
        out.mkdir(parents=True)
        lease = checks.device_preflight.device_leases
        with mock.patch.object(checks.device_preflight, 'device_leases',
                side_effect=lambda ids: lease(ids, self.root / '.codex-test-logs/leases')), \
                contextlib.redirect_stdout(io.StringIO()):
            code = checks.execute_plan(self.args(mode='full', jobs=1), self.root,
                self.rules, plan, files, config or {}, {}, out, time.monotonic())
        return code, json.loads((out / 'results.json').read_text()), out


class PrivateReceiptTest(ReviewFixture):
    def verdict(self, **changes):
        return dict(dict(capabilityId='fixture', status='PASS', assertionsAttempted=1,
                         artifactPresent=True, exitCode=0, printOnly=False, blocker=None), **changes)

    def test_every_report_free_text_and_wrongly_typed_fact_is_private(self):
        # Fresh arbitrary strings, including valid identifier syntax: no token redactor suffices.
        marker = 'private_' + uuid.uuid4().hex
        payload = dict(verdicts=[self.verdict(reason=marker, detail=marker)], validationErrors=[],
            builds=dict(requestedProfiles=marker, actualBuilds=2, totalElapsedMs=7,
                        profileElapsedMs={marker: 4}, artifactDigests={marker: marker},
                        declaredExceptions=[marker], builtProfileIds=[marker], extra=marker),
            schedule=dict(selectedIds=[marker], attemptedIds=[marker], terminalIds=[marker],
                          causalFailureId=marker, maxObservedConcurrency=1,
                          verdicts=[self.verdict(detail=marker)], extra=marker,
                          traces=[dict(capabilityId=marker, startedAt=marker, endedAt=marker,
                                       dependencyWaitMs=marker, resources=[dict(name=marker, access=marker)])]))
        path = self.write('receipt.json', json.dumps(payload))
        for verified in (False, True):
            with self.subTest(verified=verified):
                observed = checks.inspect_sims(path, 'fixture', 0, False)
                details = checks.sims_receipt_details(path, dict(report_verification_observed=verified))
                self.assertNotIn(marker, json.dumps([observed, details]))
                self.assertEqual(observed['status'], 'PASS')
                self.assertEqual(details['builds']['actualBuilds'], 2)
                self.assertEqual(details['schedule']['maxObservedConcurrency'], 1)
        for field in ('capabilityId', 'status', 'assertionsAttempted'):
            with self.subTest(field=field):
                payload['verdicts'] = [self.verdict(**{field: marker})]
                path.write_text(json.dumps(payload))
                self.assertNotIn(marker, json.dumps(checks.sims_receipt_details(path, {})))

    def test_real_failing_report_keeps_private_raw_and_first_failure(self):
        marker = 'private diagnostic ' + uuid.uuid4().hex
        payload = dict(verdicts=[self.verdict(status='FAIL', detail=marker, reason=marker)],
            validationErrors=[], builds={}, schedule=dict(verdicts=[dict(detail=marker)]))
        self.write('emit.py', 'import os,json\nfrom pathlib import Path\n'
            'Path(os.environ["SIMS_REPORT_PATH"]).write_text(json.dumps(' + repr(payload) + '))\n'
            'print(' + repr(marker) + ')\nraise SystemExit(1)\n')
        row = dict(id='receipt', kind='sims', capability='fixture', device_roles=[],
            command=[sys.executable, 'emit.py'], selected_paths=['fixture'], timeout_seconds=10)
        files = checks.source_files(self.root)
        plan = dict(mode='full', baseline=self.base, candidate_build='host-fixture', identity=checks.source_identity(self.root, files, self.rules),
            selected=[row], not_selected=[], unmapped_changes=[])
        code, result, out = self.execute(plan, files)
        self.assertEqual((code, result['status']), (1, 'FAIL'))
        for name in ('results.json', 'partial.json'):
            self.assertNotIn(marker, (out / name).read_text())
        raw = list(out.glob('*.raw.log'))
        self.assertTrue(raw)
        self.assertIn(marker, raw[0].read_text())
        self.assertEqual(raw[0].stat().st_mode & 0o077, 0)


class CommandScopeTest(ReviewFixture):
    def test_real_python_filter_cannot_hide_omitted_failure(self):
        self.write('sample_test.py', 'import unittest\nclass Cases(unittest.TestCase):\n'
            ' def test_selected(self): self.assertTrue(True)\n'
            ' def test_omitted(self): self.fail("omitted assertion must run")\n')
        command = dict(id='subset', kind='python', paths=['sample_test.py'],
            command=[sys.executable, '-m', 'unittest', '-v', 'sample_test.py', '-k', 'test_selected'],
            timeout_seconds=10, resources=['isolated:subset'])
        self.policy([command], [dict(family='python_unittest', patterns=['*_test.py'])])
        plan, files = checks.make_full_plan(self.args(), self.root, self.rules, capture_toolchains=False)
        code, report, _ = self.execute(plan, files)
        file_row = next(r for r in report['obligations'] if r['path']=='sample_test.py' and not r['selector'])
        self.assertEqual(file_row['status'], 'FAIL')
        self.assertNotEqual(code, 0)
        self.assertNotEqual(file_row['owners'], ['subset'])

    def test_authoritative_argv_filters_and_ambiguity_do_not_own_file(self):
        cases = [
            ('python', 'fixture_test.py', [sys.executable, '-m', 'unittest', 'fixture_test.py'], ['-k', 'selected']),
            ('python', 'fixture_test.py', [sys.executable, '-m', 'unittest', 'fixture_test.py'], ['-kselected']),
            ('flutter', 'test/chat_test.dart', ['flutter', 'test', 'test/chat_test.dart'], ['--name=selected']),
            ('flutter', 'test/chat_test.dart', ['flutter', 'test', 'test/chat_test.dart'], ['--plain-name', 'selected']),
            ('flutter', 'test/chat_test.dart', ['dart', 'test', 'test/chat_test.dart'], ['--name', 'selected']),
            ('flutter', 'test/chat_test.dart', ['dart', 'test', 'test/chat_test.dart'], ['--plain-name=selected']),
            ('flutter', 'test/chat_test.dart', ['flutter', 'test', 'test/chat_test.dart'], ['--tags=selected']),
            ('node', 'sample_test.js', ['node', '--test', 'sample_test.js'], ['--test-name-pattern=selected']),
            ('go', 'sample_test.go', ['go', 'test', './...'], ['-run', 'Selected']),
            ('go', 'sample_test.go', ['go', 'test', './...'], ['-run=Selected']),
            ('go', 'sample_test.go', ['go', 'test', './...'], ['-test.run=Selected']),
            ('python', 'fixture_test.py', [sys.executable, 'opaque.py'], []),
        ]
        self.write('sample_test.js', '// discovery only')
        self.write('sample_test.go', 'package sample')
        for kind, path, prefix, filters in cases:
            with self.subTest(argv=prefix + filters):
                row = dict(id='subset', kind=kind, selected_paths=[path], command=prefix+filters)
                self.policy([row])
                ledger = inventory.reconcile(self.root, self.rules, [row], checks.source_files(self.root))
                file_row = next(r for r in ledger['obligations'] if r['path']==path and not r['selector'])
                self.assertNotIn('subset', file_row['owners'])

    def test_listing_equals_filter_keeps_unfiltered_owner(self):
        row = dict(id='host', kind='command', command=[])
        self.policy([row], [dict(family='flutter_host', patterns=['test/*'])])
        self.rules['full_inventory']['listings'] = [dict(id='host', owner='host',
            command=['bash','scripts/run_host_test_gates.sh','host-all','--list'])]
        with mock.patch.object(inventory, 'list_runner', return_value=dict(status='PASS',
                planned_commands=['flutter test test/chat_test.dart --name=selected'])):
            selected = [row]
            ledger = inventory.reconcile(self.root, self.rules, selected, checks.source_files(self.root))
        whole = next(r for r in ledger['obligations'] if r['path']=='test/chat_test.dart' and not r['selector'])
        self.assertNotIn('host', whole['owners'])
        self.assertTrue(whole['owners'])

    def test_unfiltered_python_suite_retains_ownership(self):
        row = dict(id='suite', kind='python', selected_paths=['fixture_test.py'],
                   command=[sys.executable, '-m', 'unittest', '-v', 'fixture_test.py'])
        self.policy([row])
        ledger = inventory.reconcile(self.root, self.rules, [row], checks.source_files(self.root))
        whole = next(r for r in ledger['obligations'] if r['path']=='fixture_test.py' and not r['selector'])
        self.assertEqual(whole['owners'], ['suite'])

    def test_go_mapping_respects_run_filters_and_retains_unfiltered_suite(self):
        self.write('sample_test.go', 'package sample')
        for flags in ([], ['-run','Selected'], ['-run=Selected'], ['--run=Selected'], ['-test.run','Selected']):
            with self.subTest(flags=flags):
                row = dict(id='go-suite', kind='go', command=['go','test','./...',*flags], selected_paths=[])
                self.policy([row])
                self.rules['full_inventory']['mappings'] = [dict(owner='go-suite', patterns=['sample_test.go'], reason='Go package tests')]
                ledger = inventory.reconcile(self.root, self.rules, [row], checks.source_files(self.root))
                whole = next(r for r in ledger['obligations'] if r['path']=='sample_test.go')
                self.assertEqual(whole['owners'], [] if flags else ['go-suite'])

    def test_explicit_dart_filter_owns_only_a_selector_obligation(self):
        row = dict(id='subset', kind='flutter', command=['flutter','test','test/chat_test.dart','--plain-name=selected'],
                   selected_paths=['test/chat_test.dart'])
        self.policy([row])
        ledger = inventory.reconcile(self.root, self.rules, [row], checks.source_files(self.root))
        rows = [r for r in ledger['obligations'] if r['path']=='test/chat_test.dart']
        self.assertEqual(next(r for r in rows if not r['selector'])['status'], 'UNMAPPED')
        self.assertTrue(any(r['selector'] and r['owners']==['subset'] for r in rows))


class ChildReceiptTest(ReviewFixture):
    def test_actual_swift_mapping_joins_unavailable_child(self):
        path = 'ios/RunnerTests/ReviewTests.swift'
        self.write(path, '// source registration only; no native execution')
        self.write('ios/Runner.xcodeproj/project.pbxproj', 'ReviewTests.swift in Sources')
        actual = json.loads((PROJECT / checks.RULES).read_text())
        mapping = next(m for m in actual['full_inventory']['mappings'] if m.get('source_registration'))
        row = dict(id='full-sims-major', kind='sims', capability='*', sims_mode='major', command=[])
        self.policy([row])
        self.rules['full_inventory']['mappings'] = [mapping]
        ledger = inventory.reconcile(self.root, self.rules, [row], checks.source_files(self.root))
        results = {'full-sims-major': dict(status='PASS', attempts=[dict(status='PASS', capability_results=[
            dict(id='native.ios.runner_tests', status='N/A', reason='target_unavailable_by_project_policy')])])}
        joined = checks.obligation_results(ledger['obligations'], results)
        self.assertEqual(next(r for r in joined if r['path']==path)['status'], 'N/A')

    def test_every_binding_joins_all_attempts_without_parent_substitution(self):
        for key, receipts in [('capability', 'capability_results'), ('route', 'route_results')]:
            for expected, attempts in [
                ('N/A', ['N/A']), ('FAIL', ['FAIL','PASS']), ('NOT RUN', [None]),
                ('BLOCKED', ['BLOCKED']), ('NOT RUN', ['PASS',None]), ('PASS', ['PASS'])]:
                with self.subTest(key=key, expected=expected, attempts=attempts):
                    obligation = dict(id='file', path='file', selector='', owners=['parent'],
                        receipt_bindings=[dict(owner='parent', **{key:'leaf'})])
                    result = dict(status='PASS', attempts=[dict(status='PASS', **{receipts:
                        [] if status is None else [dict(id='leaf', status=status)]}) for status in attempts])
                    joined = checks.obligation_results([obligation], {'parent':result})
                    self.assertEqual(joined[0]['status'], expected)


class ProtectedDeviceTest(ReviewFixture):
    def test_all_pins_are_leased_and_android_preflighted_before_child(self):
        from device_campaign_preflight_test import IDLE
        ids = dict(android_physical='usb', android_emulator='emu1', android_emulator_second='emu2',
                   ios_physical='phone', ios_simulator='simA', ios_simulator_b='simB',
                   ios_simulator_c='simC', ios_simulator_d='simD')
        config = dict(devices=ids)
        row = dict(id='protected', kind='sims', capability='fixture', sims_mode='major',
                   selected_paths=['fixture'], command=[sys.executable, 'proof.py'], timeout_seconds=10)
        self.write('proof.py', '''import fcntl,hashlib,json,os
from pathlib import Path
pins=json.loads(os.environ['SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON'])
for target in pins.values():
 path=Path('.codex-test-logs/leases')/(hashlib.sha256(target.encode()).hexdigest()+'.lock')
 with path.open('r+') as lock:
  try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError: pass
  else: raise AssertionError('child reached an unleased target')
Path('.codex-test-logs/received-pins.json').write_text(json.dumps(pins))
# An intentionally failing synthetic receipt; no product/native PASS is claimed.
Path(os.environ['SIMS_REPORT_PATH']).write_text(json.dumps({'verdicts':[{'capabilityId':'fixture','status':'FAIL'}]}))
raise SystemExit(1)
''')
        files = checks.source_files(self.root)
        plan = dict(mode='full', baseline=self.base, candidate_build='lease-fixture', selected=[row],
            identity=checks.source_identity(self.root, files, self.rules), not_selected=[], unmapped_changes=[])
        observed = []
        original = checks.launch
        def launch(command, cwd, timeout, env):
            if command[0] == 'adb':
                observed.append(command[2])
                return IDLE, 0, False, 0
            self.assertEqual(set(observed), {'usb','emu1','emu2'})
            return original(command, cwd, timeout, env)
        with mock.patch.object(checks, 'launch', side_effect=launch):
            self.execute(plan, files, config)
        received = self.root / '.codex-test-logs/received-pins.json'
        self.assertTrue(received.is_file(), 'child could not confirm every device lease')
        self.assertEqual(set(json.loads(received.read_text()).values()), set(ids.values()))

    def test_omitted_legacy_peer_cannot_inherit_an_ambient_device(self):
        env = dict(SIMS_ANDROID_EMULATOR_DEVICE_ID='foreign-peer')
        env.update(checks.sims_environment(dict(devices={'android_physical':'usb'}), self.root/'report.json'))
        self.assertEqual(env['SIMS_ANDROID_EMULATOR_DEVICE_ID'], '')
        self.assertNotIn('foreign-peer', json.dumps(env))

    def test_wrapper_exports_every_protected_role_including_additional_peers(self):
        ids = dict(android_physical='usb', android_emulator='emu1', android_emulator_second='emu2',
                   ios_physical='phone', ios_simulator='simA', ios_simulator_b='simB',
                   ios_simulator_c='simC', ios_simulator_d='simD')
        env = checks.sims_environment(dict(devices=ids), self.root/'report.json')
        protected = env.get('SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON')
        self.assertIsNotNone(protected, 'SIMS must know exactly which IDs have wrapper protection')
        self.assertEqual(set(json.loads(protected).values()), set(ids.values()))
        roles = checks.device_preflight.device_roles(dict(kind='legacy', device_roles=['android_physical','ios_simulator']), dict(devices=ids))
        self.assertEqual(set(roles), set(ids), 'nested SIMS can consume roles beyond the outer legacy pair')

    def test_actual_binding_never_prepares_or_assigns_unprotected_targets(self):
        # This pure Dart host probe imports production binding/resolution code.
        # Dependency package config is supplied by the host-check setup; no discovery is invoked.
        packages = os.environ.get('MKNOON_REVIEW_DART_PACKAGES')
        if not packages and (PROJECT / '.dart_tool/package_config.json').is_file():
            packages = str(PROJECT / '.dart_tool/package_config.json')
        if not packages:
            self.skipTest('Set MKNOON_REVIEW_DART_PACKAGES to the host crypto package config')
        dart = self.write('binding_probe.dart', DART_PROBE.replace('@PROJECT@', PROJECT.as_uri()))
        run = subprocess.run([os.environ.get('MKNOON_REVIEW_DART', 'dart'), '--packages='+packages, str(dart), str(PROJECT)],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        observations = json.loads(run.stdout)
        self.assertEqual(observations['empty']['assignments'], {})
        self.assertEqual(observations['empty']['status'], 'BLOCKED')
        self.assertEqual(observations['partial']['assignments'], {})
        self.assertEqual(observations['partial']['status'], 'BLOCKED')
        self.assertEqual(observations['launchable']['preparation'], 0)
        self.assertEqual(observations['launchable']['status'], 'BLOCKED')
        self.assertEqual(observations['absent']['status'], 'N/A')
        self.assertEqual(observations['complete']['assignments'], {'device:android-physical':'usb', 'device:android-emulator':'emu'})
        self.assertIsNone(observations['complete']['status'])
        self.assertEqual(observations['opaque']['status'], 'BLOCKED')
        self.assertEqual(observations['ios']['assignments'], {'device:ios-simulator-a':'simZ'})


DART_PROBE = r'''
import 'dart:convert';
import 'dart:io';
import '@PROJECT@/tool/sims/device_binding.dart';
import '@PROJECT@/tool/sims/live_device_resolver.dart';
import '@PROJECT@/tool/sims/manifest.dart';
import '@PROJECT@/tool/sims/planner.dart';

void main(List<String> args) {
  final manifest = SimsManifest.fromJsonString(File('${args[0]}/tool/sims/critical_features.json').readAsStringSync());
  final base = manifest.capabilities.firstWhere((c) => c.id == 'native.ios.runner_tests');
  CapabilitySpec row(List<String> roles) => base.copyWith(id:'fixture', dependencies:[], targetCapabilities:[],
    resources: roles.map((r) => ResourceLock(name:'device:$r', access: ResourceAccess.exclusive)).toList());
  SimsLiveDeviceTarget target(String id, SimsLiveDeviceKind kind, {bool launchable=false, bool ios=false}) => SimsLiveDeviceTarget(
    name:id, platform:ios ? SimsLiveDevicePlatform.ios : SimsLiveDevicePlatform.android, kind:kind,
    availability:launchable ? SimsLiveDeviceAvailability.launchable : SimsLiveDeviceAvailability.connected,
    runtimeId:launchable ? null : id, launchId:launchable ? id : null, sources:SimsDeviceDiscoverySource.values);
  final devices = [target('usb', SimsLiveDeviceKind.physical), target('emu', SimsLiveDeviceKind.emulator)];
  Map<String,Object?> bind(CapabilitySpec c, List<SimsLiveDeviceTarget> targets, Map<String,String> pins) {
    final b = SimsDevicePlanBinding.bind(SimsPlan(mode:SimsMode.major, simultaneous:false,
      releaseEligibleCandidate:false, manifestDigest:'fixture', family:null, onlyId:null, rows:[c]),
      SimsLiveDeviceInventory(targets:targets, sourceResults:[for(final s in SimsDeviceDiscoverySource.values)
        SimsDiscoverySourceResult(source:s, status:SimsDiscoveryStatus.success, detail:'host fixture')]),
      processEnvironment:{'SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON':jsonEncode(pins)});
    return {'assignments':b.assignments, 'preparation':b.preparationTargets.length,
      'status':b.preflightVerdicts[c.id]?.toJson()['status']};
  }
  final pair = row(['android-physical','android-emulator']);
  stdout.writeln(jsonEncode({
    'empty':bind(pair, devices, {}),
    'partial':bind(pair, devices, {'android-physical':'usb'}),
    'complete':bind(pair, devices, {'android-physical':'usb','android-emulator':'emu'}),
    'absent':bind(row(['ios-simulator-a']), [], {}),
    'launchable':bind(row(['android-emulator']), [target('avd', SimsLiveDeviceKind.emulator, launchable:true)], {}),
    'opaque':bind(manifest.capabilities.firstWhere((c) => c.id=='reliability.full.cleaned_legacy'), [], {}),
    'ios':bind(row(['ios-simulator-a']), [target('simA', SimsLiveDeviceKind.simulator, ios:true),
      target('simZ', SimsLiveDeviceKind.simulator, ios:true)], {'ios-simulator-a':'simZ'}),
  }));
}
'''


if __name__ == '__main__':
    unittest.main()
