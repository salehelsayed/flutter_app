"""Executable fixture contracts for full-suite adapters (no live devices)."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_LOCAL_DART = ROOT / '.codex-test-logs/runtime-tools/dart'
DART = _LOCAL_DART if _LOCAL_DART.exists() else Path(shutil.which('dart') or '/unavailable/dart')


class GroupFullAdapterTest(unittest.TestCase):
    def run_adapter(self, mode, partial=False):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            shim = base / 'dart'
            shim.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['ARGV_LOG']).write_text(json.dumps(sys.argv[1:]))
ids=json.loads(os.environ['SCENARIOS'])
if os.environ.get('PARTIAL')=='1':ids=ids[:-1]
path=os.environ.get('GMP_SWEEP_REPORT')
if path:Path(path).write_text(json.dumps({'scenarios':[{'scenario':s,'passed':True} for s in ids]}))
''')
            shim.chmod(0o755)
            app = base / 'Runner.app'; app.mkdir(); (app/'Info.plist').touch()
            source=(ROOT/'integration_test/scripts/group_multi_party_device_criteria.dart').read_text()
            ids=re.findall("^  '([^']+)':",source.split('const _scenarioRequirements =',1)[1].split('};',1)[0],re.M)
            ids.remove('all')
            if mode=='smoke':
                ids=re.findall("'([^']+)'",source.split('const smokeGroupMultiPartyDeviceScenarioIds = <String>[',1)[1].split('];',1)[0])
            env={**os.environ, 'PATH':str(base)+os.pathsep+os.environ['PATH'],
                 'MKNOON_RELAY_ADDRESSES':'127.0.0.1:4001','SIMS_ARTIFACT_IOS_SIMULATOR_E2E':str(app),
                 'SIMS_PROOF_DIRECTORY':str(base/'proof'), 'ARGV_LOG':str(base/'argv'),
                 'SCENARIOS':json.dumps(ids),'PARTIAL':str(int(partial))}
            targets=[f'{i}'*8+'-'+f'{i}'*4+'-'+f'{i}'*4+'-'+f'{i}'*4+'-'+f'{i}'*12 for i in range(1,5)]
            for key,value in zip('ABCD',targets):env[f'SIMS_IOS_SIMULATOR_{key}_DEVICE_ID']=value
            env['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS']=','.join(targets)
            result=subprocess.run([str(DART),'integration_test/scripts/run_group_multi_party_sims.dart','--scenario',mode],cwd=ROOT,env=env,text=True,capture_output=True)
            self.assertIn('SIMS_RESULT_JSON=',result.stdout,result.stderr)
            payload=json.loads(result.stdout.split('SIMS_RESULT_JSON=')[-1])
            proof=json.loads(Path(payload['artifactEvidence']['path']).read_text()) if 'artifactEvidence' in payload else None
            return result.returncode,payload,json.loads((base/'argv').read_text()),proof

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_full_pass_requires_all_109_terminal_scenarios(self):
        code,payload,argv,proof=self.run_adapter('all')
        self.assertEqual(code,0,payload)
        self.assertEqual(argv[argv.index('--scenario')+1],'all')
        self.assertEqual(payload['assertionsAttempted'],109)
        self.assertIn('scenarioResults',json.dumps(proof))

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_successful_child_with_missing_scenario_is_blocked(self):
        code,payload,_,_=self.run_adapter('all',partial=True)
        self.assertNotEqual(code,0)
        self.assertEqual(payload['status'],'BLOCKED')
        self.assertEqual(payload['blocker'],'missingArtifact')

class RuntimeAdapterTest(unittest.TestCase):
    def module(self):
        import sys
        sys.path.insert(0,str(ROOT/'scripts'))
        import full_suite_adapters
        return full_suite_adapters

    def test_campaign_reuses_only_exact_native_case_receipts(self):
        m = self.module()
        step = {'format':'marker', 'marker':'campaign validated',
                'native_xctest_counts':{'Example/testSetup':1, 'Example/testTap':2}}
        setup = "Test Case '-[RunnerUITests.Example testSetup]' passed (0.1 seconds).\n"
        tap = "Test Case '-[RunnerUITests.Example testTap]' passed (0.1 seconds).\n"
        output = setup + tap + tap + 'campaign validated'
        proof = m.inspect(step, output, 0, False, ROOT)
        self.assertEqual(proof['status'], 'PASS')
        self.assertEqual(proof['route_results'], [
            {'id':'xctest:Example/testSetup','status':'PASS','counts':{'passed':1,'failed':0,'skipped':0}},
            {'id':'xctest:Example/testTap','status':'PASS','counts':{'passed':2,'failed':0,'skipped':0}}])
        for bad in ['campaign validated', setup + tap + 'campaign validated',
                    output + tap, output + "Test Case '-[Example testOther]' passed\n",
                    output + "Test Case '-[Example testTap]' failed\n",
                    output + "Test Case '-[Example testTap]' skipped\n"]:
            with self.subTest(output=bad):
                result = m.inspect(step, bad, 0, False, ROOT)
                self.assertEqual(result['status'], 'BLOCKED')
                self.assertNotIn('route_results', result)
        self.assertNotIn('route_results', m.inspect(step, output, 1, False, ROOT))

    def test_campaign_native_receipt_metadata_rejects_invalid_counts(self):
        m = self.module()
        for counts in [{}, {'Example/testTap':0}, {'Example/testTap':True},
                       {'Example/testTap':'2'}, {'not a selector':1}]:
            check = {'steps':[{'command':['dart','campaign.dart'], 'format':'marker',
                              'marker':'done', 'native_xctest_counts':counts}]}
            self.assertTrue(m.validate(check, ROOT))

    def test_config_and_pinned_target_are_bound_without_shell_interpolation(self):
        m=self.module()
        check={'id':'reaction','device_roles':['android_physical','android_emulator'],
               'required_config':['service_account'], 'config_files':['service_account'],
               'steps':[{'command':['dart','run','runner.dart','--scenario','singleton','--recipient','{device:android_physical}',
                                    '--sender','{device:android_emulator}','--service-account','{config:service_account}','--artifact-dir','{output}'],
                         'format':'marker','marker':'validated singleton'}]}
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'credentials with spaces.json';path.write_text('{}')
            config={'isolated_test_environment':True,'fixture_reference':'fixture',
                    'devices':{'android_physical':'phone','android_emulator':'emulator-1'},
                    'full_suite':{'service_account':str(path)}}
            matrix={'flutter':[{'id':'phone','targetPlatform':'android-arm64','emulator':False},
                              {'id':'emulator-1','targetPlatform':'android-x64','emulator':True}], 'adb':['phone','emulator-1']}
            self.assertEqual(m.prerequisites(check,config,matrix),[])
            steps,env=m.bind(check,config,ROOT,Path(tmp)/'out')
            self.assertIn(str(path),steps[0]['command'])
            self.assertEqual(steps[0]['command'][steps[0]['command'].index('--scenario')+1],'singleton')
            self.assertEqual(steps[0]['command'][-1],str(Path(tmp)/'out'))
            config['full_suite']={}
            self.assertIn('full_suite.service_account required',m.prerequisites(check,config,matrix))

    def test_unavailable_optional_hardware_is_na_but_discovery_error_is_blocked(self):
        m=self.module();check={'device_roles':['ios_physical']}
        self.assertEqual(m.availability(check,{}, {'flutter':[],'errors':[]}), 'N/A')
        self.assertEqual(m.availability(check,{}, {'errors':['flutter discovery failed']}),'BLOCKED')

    def test_zero_exit_does_not_replace_test_completion(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            step={'format':'xctest','selectors':['Example/testOne']}
            self.assertEqual(m.inspect(step,'** TEST SUCCEEDED **',0,False,Path(tmp))['status'],'BLOCKED')
            out="Test Case '-[RunnerTests.Example testOne]' passed (0.01 seconds).\nExecuted 1 test, with 0 failures"
            self.assertEqual(m.inspect(step,out,0,False,Path(tmp))['status'],'PASS')
            self.assertEqual(m.inspect(step,out.replace('passed','skipped'),0,False,Path(tmp))['status'],'BLOCKED')

    def test_junit_requires_exact_class_and_fresh_nonzero_results(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);p=root/'TEST-Plugin.xml'
            step={'format':'junit','report_glob':'TEST-*.xml','classes':['Plugin']}
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'BLOCKED')
            p.write_text('<testsuite tests="1"><testcase classname="Plugin" name="assertion"/></testsuite>')
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'PASS')
            p.write_text('<testsuite tests="1"><testcase classname="Other" name="assertion"/></testsuite>')
            self.assertEqual(m.inspect(step,'BUILD SUCCESSFUL',0,False,root)['status'],'BLOCKED')

    def test_junit_failure_survives_gradle_nonzero_exit(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'TEST-Proof.xml').write_text(
                '<testsuite tests="1" failures="1"><testcase classname="Proof" name="assertion">'
                '<failure>expected 117, actual 119</failure></testcase></testsuite>')
            proof=m.inspect({'format':'junit','report_glob':'TEST-*.xml','classes':['Proof']},
                            'There were failing tests. BUILD FAILED',1,False,root)
            self.assertEqual(proof['status'],'FAIL')
            self.assertEqual(proof['checkpoint'],'native_assertion_failed')
            self.assertEqual(proof['counts'],{'passed':0,'failed':1,'skipped':0})
            self.assertEqual(proof['exit_status'],1)

    def test_junit_passing_xml_cannot_override_gradle_failure(self):
        m=self.module()
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'TEST-Proof.xml').write_text(
                '<testsuite tests="1"><testcase classname="Proof" name="assertion"/></testsuite>')
            proof=m.inspect({'format':'junit','report_glob':'TEST-*.xml','classes':['Proof']},
                            'BUILD FAILED',1,False,root)
            self.assertEqual(proof['status'],'BLOCKED')
            self.assertEqual(proof['checkpoint'],'adapter_process_failed')
            self.assertEqual(proof['exit_status'],1)

import sys
sys.path.insert(0,str(ROOT/'scripts/test'))
from mknoon_full_checks_test import FullExecutionFixture


class AdapterCLITest(FullExecutionFixture):
    def test_startup_os_error_retains_errno_without_private_exception_text(self):
        import errno
        from unittest import mock
        from mknoon_checks_test import checks
        task = {'id':'adapter','kind':'full_adapter','command':[sys.executable,'-c','pass'],
                'steps':[{'command':[sys.executable,'-c','pass'],'format':'marker','marker':'done'}],
                'boundary':'startup failure fixture','timeout_seconds':10,'resources':['isolated:adapter']}
        for number in [errno.ENOSPC, errno.ENOENT]:
            with self.subTest(errno=number), mock.patch.object(
                    checks, 'launch', side_effect=OSError(number, 'private-credential-path')):
                code, report = self.run_full([task])
            self.assertNotEqual(code, 0)
            attempt = report['results'][0]['attempts'][0]
            self.assertEqual(attempt['checkpoint'], 'test_runner_startup')
            self.assertEqual(attempt['os_error_errno'], number)
            self.assertNotIn('private-credential-path', json.dumps(report))

    def test_existing_full_cli_executes_adapter_steps_and_retains_completion(self):
        self.write('contract.py',"from pathlib import Path\nPath('.codex-test-logs/proof').write_text('executed')\nprint('EXACT ASSERTIONS COMPLETE')\n")
        task={'id':'adapter','kind':'full_adapter','command':['python3','contract.py'],
              'steps':[{'command':[sys.executable,'contract.py'],'format':'marker','marker':'EXACT ASSERTIONS COMPLETE'}],
              'boundary':'real fixture subprocess','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertEqual(code,0,report)
        self.assertTrue((self.root/'.codex-test-logs/proof').exists())
        self.assertTrue(report['results'][0]['attempts'][0]['step_results'][0]['completion_observed'])

    def test_missing_step_completion_stops_dependent_adapter_step(self):
        self.write('empty.py','pass\n')
        self.write('later.py',"from pathlib import Path\nPath('.codex-test-logs/later').touch()\nprint('done')\n")
        task={'id':'adapter','kind':'full_adapter','command':[sys.executable,'empty.py'],
              'steps':[{'command':[sys.executable,'empty.py'],'format':'marker','marker':'done'},
                       {'command':[sys.executable,'later.py'],'format':'marker','marker':'done'}],
              'boundary':'fixture','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertNotEqual(code,0)
        self.assertFalse((self.root/'.codex-test-logs/later').exists())
        self.assertEqual(report['results'][0]['status'],'BLOCKED')

class MetadataCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rules=json.loads((ROOT/'tool/testing/selection.json').read_text())

    def test_full_group_mode_and_exact_catalogue_are_selected(self):
        major=next(c for c in self.rules['full_commands'] if c['id']=='full-sims-major')
        self.assertEqual(major.get('environment',{}).get('SIMS_GROUP_MULTI_PARTY_SCENARIO'),'all')
        catalog=next(c for c in self.rules['full_inventory']['catalogs'] if 'group_multi_party_device_criteria' in c['path'])
        self.assertEqual(catalog['start'],'const _scenarioRequirements =')
        self.assertIn('all',catalog['exclude_selectors'])

    def test_exact_reaction_singletons_and_performance_variants(self):
        checks=self.rules['full_commands']
        commands=[step['command'] for c in checks for step in c.get('steps',[])]
        for selector in ['head_provenance','android_background_crypto_preflight','android_first_wake_profile_aot',
                         'android_durable_reaction_background_connected','android_message_unread_lifecycle',
                         'android_physical_recipient','ios_physical_recipient',
                         'ios_announcement_reaction_recipient','ios_chat_group_message_and_reaction_recipient']:
            matches=[c for c in commands if '--scenario' in c and c[c.index('--scenario')+1]==selector]
            self.assertEqual(len(matches),1,selector)
            self.assertIn('--recipient',matches[0]);self.assertIn('--artifact-dir',matches[0])
        first=next(c for c in commands if 'android_first_wake_profile_aot' in c)
        self.assertIn('--require-alert',first)
        for selector in ['FEED_INIT','SHELL_SWITCH','FEED_ORBIT_OFFSCREEN','CONVERSATION','CONVERSATION_SUB','ORBIT']:
            match=[c for c in commands if '--dart-define=PERF_TARGET='+selector in c]
            self.assertEqual(len(match),1,selector)
            self.assertIn('{device:macos}',match[0])
        self.assertFalse(any('--dart-define=PERF_TARGET=FEED' in c for c in commands))

    def test_native_proof_wrappers_and_contract_mains_have_executable_owners(self):
        text=json.dumps([c.get('steps') for c in self.rules['full_commands']])
        for path in ['run_app_visibility_native_371.sh','run_ios_nse_native_373.sh','run_android_headless_recovery_native_374.sh',
                     'run_app_visibility_android_e2e.sh','ios_receiver_bootstrap_contract_test.dart',
                     'ios_sender_projection_fixture_contract_test.dart',':background_push_crypto:testDebugUnitTest']:
            self.assertIn(path,text)

class BenchmarkAdapterTest(unittest.TestCase):
    def test_benchmark_suite_propagates_failed_or_empty_child_before_completion(self):
        for body in ['exit 7', 'exit 0']:
            with tempfile.TemporaryDirectory() as tmp:
                shim=Path(tmp)/'flutter';shim.write_text('#!/bin/sh\n'+body+'\n');shim.chmod(0o755)
                result=subprocess.run([str(DART),'integration_test/scripts/run_benchmark_suite.dart','-d','fixture-simulator','--scenarios','B','--fixture-dir',tmp],cwd=ROOT,env={**os.environ,'PATH':tmp+os.pathsep+os.environ['PATH']},text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0,result.stdout)
                self.assertNotIn('FULL_BENCHMARK_COMPLETED',result.stdout)

class XCTestBindingTest(unittest.TestCase):
    def test_fresh_xctestrun_receives_exact_fixture_environment_and_selector(self):
        import plistlib
        import full_suite_adapters as m
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);products=root/'build/Build/Products';products.mkdir(parents=True)
            original=products/'Runner.xctestrun';original.write_bytes(plistlib.dumps({'RunnerUITests':{'EnvironmentVariables':{'BASE':'kept'}},'RunnerTests':{}}))
            fixture=root/'fixture.json';fixture.write_text(json.dumps({'NotificationTapUITests/testNotificationTap':{'environment':{'MKNOON_APNS_TAP_EXPECTED_TITLE':'fixture title'},'target_id':'phone'}}))
            step={'xctest_fixture':str(fixture),'selectors':['NotificationTapUITests/testNotificationTap'],
                  'xctestrun_directory':str(products),'xctestrun_output':str(root/'active.xctestrun'),'target_id':'phone'}
            m.prepare_step(step)
            result=plistlib.loads((root/'active.xctestrun').read_bytes())
            self.assertEqual(result['RunnerUITests']['EnvironmentVariables'],{'BASE':'kept','MKNOON_APNS_TAP_EXPECTED_TITLE':'fixture title'})
            self.assertEqual(plistlib.loads(original.read_bytes())['RunnerUITests']['EnvironmentVariables'],{'BASE':'kept'})
            step['target_id']='other'
            with self.assertRaisesRegex(ValueError,'target'):m.prepare_step(step)

class CanonicalHostTest(unittest.TestCase):
    def test_gate_host_alias_keeps_default_execution_and_full_skips_exact_host_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp);shim=base/'flutter';log=base/'calls';shim.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n');shim.chmod(0o755)
            env={**os.environ,'PATH':tmp+os.pathsep+os.environ['PATH'],'CALL_LOG':str(log)}
            normal=subprocess.run(['bash','scripts/run_test_gates.sh','baseline'],cwd=ROOT,env=env,text=True,capture_output=True)
            self.assertEqual(normal.returncode,0,normal.stderr);self.assertIn('test/core/',log.read_text())
            log.unlink()
            alias=subprocess.run(['bash','scripts/run_test_gates.sh','baseline'],cwd=ROOT,env={**env,'MKNOON_FULL_HOST_OWNER':'host.dart.all'},text=True,capture_output=True)
            self.assertEqual(alias.returncode,0,alias.stderr)
            calls=log.read_text()
            self.assertNotIn('test test/',calls,'full gate repeats canonical host tests')
            self.assertIn('integration_test/posts_phase1_fake_test.dart',calls)
            self.assertIn('integration_test/loading_states_smoke_test.dart',calls)
            self.assertIn('HOST_RESULT_ALIAS host.dart.all test/',alias.stdout)

class AdapterBoundaryTest(FullExecutionFixture):
    def test_missing_optional_target_is_na_and_never_launches(self):
        import contextlib,io,time
        from unittest import mock
        from mknoon_checks_test import checks
        task={'id':'ios','kind':'full_adapter','command':[sys.executable,'-c','raise SystemExit(9)'],
              'steps':[{'command':[sys.executable,'-c','raise SystemExit(9)'],'format':'marker','marker':'proof'}],
              'device_roles':['ios_physical'],'boundary':'optional native target','timeout_seconds':10,'resources':['unknown']}
        self.rules['full_commands']=[task]
        self.write('tool/testing/selection.json',json.dumps(self.rules))
        config=self.write('.codex-test-logs/devices.json',json.dumps({'isolated_test_environment':True,'fixture_reference':'fixture','devices':{}}))
        output=self.root/'.codex-test-logs/na'
        with mock.patch.object(checks,'ROOT',self.root),mock.patch.object(checks,'toolchain_identity',return_value={}),mock.patch.object(checks,'devices',return_value={'flutter':[],'adb':[],'ios_simulators':[],'errors':[]}),contextlib.redirect_stdout(io.StringIO()):
            code=checks.main(['full','--base',self.base,'--local','--device-config',str(config),'--output',str(output)])
        report=json.loads((output/'results.json').read_text())
        self.assertEqual(report['results'][0]['status'],'N/A')
        self.assertEqual(report['results'][0]['attempts'],[])
        self.assertEqual(report['results'][0]['checkpoint'],'target_unavailable_by_project_policy')

    def test_complete_sims_owner_alias_uses_exact_capability_result(self):
        from mknoon_checks_test import checks
        obligations=[{'id':'alias','path':'test/a.dart','selector':'gate:A','status':'SELECTED','owners':['major'],'owner_capability':'host.dart.all'}]
        results={'major':{'status':'BLOCKED','attempts':[{'capability_results':[{'id':'host.dart.all','status':'PASS'},{'id':'other','status':'BLOCKED'}]}]}}
        self.assertEqual(checks.obligation_results(obligations,results)[0]['status'],'PASS')
        results['major']['attempts'][0]['capability_results']=[]
        self.assertEqual(checks.obligation_results(obligations,results)[0]['status'],'NOT RUN')

class TargetPolicyTest(unittest.TestCase):
    def test_flutter_darwin_target_is_supported_for_macos_performance(self):
        import full_suite_adapters as m
        matrix={'flutter':[{'id':'macos','targetPlatform':'darwin','emulator':False}],'errors':[]}
        check={'device_roles':['macos']}
        self.assertEqual(m.availability(check,{},matrix),'AVAILABLE')
        config={'isolated_test_environment':True,'fixture_reference':'fixture','devices':{'macos':'macos'}}
        self.assertEqual(m.prerequisites(check,config,matrix),[])

class AdapterLogRetentionTest(FullExecutionFixture):
    def test_preparation_output_survives_later_fixture_failure(self):
        task={'id':'adapter','kind':'full_adapter','command':[sys.executable,'-c',"print('BUILD RECEIPT')"],
              'steps':[{'command':[sys.executable,'-c',"print('BUILD RECEIPT')"],'format':'marker','marker':'BUILD RECEIPT'},
                       {'command':[sys.executable,'-c',"print('not reached')"],'format':'xctest','selectors':['Fixture/testOne'],'xctest_fixture':'/missing-fixture.json'}],
              'boundary':'retained preparation evidence','timeout_seconds':10,'resources':['isolated:adapter']}
        code,report=self.run_full([task])
        self.assertNotEqual(code,0)
        logs=list((self.root/'.codex-test-logs').rglob('adapter-1.raw.log'))
        self.assertEqual(len(logs),1)
        self.assertIn('BUILD RECEIPT',logs[0].read_text())
        self.assertNotIn('not reached',logs[0].read_text())

class ClassificationSafetyTest(unittest.TestCase):
    def test_standalone_assertion_failure_is_fail_and_compilation_error_is_blocked(self):
        import full_suite_adapters as m
        with tempfile.TemporaryDirectory() as tmp:
            step={'format':'assert_main'}
            result=m.inspect(step,'Unhandled exception:\nBad state: assertion failed\n',255,False,Path(tmp))
            self.assertEqual(result['status'],'FAIL')
            self.assertEqual(m.inspect(step,'Error: import could not be resolved',255,False,Path(tmp))['status'],'BLOCKED')

    def test_changed_support_source_invalidates_its_exclusion(self):
        import testing_inventory
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'empty_test.dart').write_text('void main() {}')
            rules={'full_inventory':{'exclusions':[{'pattern':'empty_test.dart','reason':'empty template','source_sha256':'0'*64}]}}
            errors=testing_inventory.validate_policy(root,rules,['empty_test.dart'])
            self.assertTrue(any('source' in e.lower() for e in errors),errors)

class ChangedStandaloneContractTest(unittest.TestCase):
    def test_changed_native_flutter_proof_reuses_existing_exact_owner(self):
        import copy
        from mknoon_checks_test import checks
        rules=json.loads((ROOT/'tool/testing/selection.json').read_text())
        path='integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart'
        owner=next(c for c in rules['full_commands'] if c['id']=='full.native.pb266-release')
        result=checks.select(copy.deepcopy(rules),[{'path':path,'status':'M'}],'change',[path],ROOT)
        self.assertEqual(result['unmapped_changes'],[])
        selected=[c for c in result['selected'] if c['id']==owner['id']]
        self.assertEqual(len(selected),1)
        self.assertEqual(selected[0]['command'],owner['command'])
        self.assertEqual(selected[0]['steps'],owner['steps'])
        self.assertEqual(selected[0]['device_roles'],['android_physical'])

    def test_changed_assertion_mains_reuse_exact_adapters_and_unknown_tests_fail_closed(self):
        import copy
        from mknoon_checks_test import checks
        rules=json.loads((ROOT/'tool/testing/selection.json').read_text())
        paths=['scripts/test/ios_receiver_bootstrap_contract_test.dart','scripts/test/ios_sender_projection_fixture_contract_test.dart']
        result=checks.select(copy.deepcopy(rules),[{'path':p,'status':'M'} for p in paths],'change',paths,ROOT)
        self.assertEqual(result['unmapped_changes'],[])
        for path in paths:
            matches=[c for c in result['selected'] if c.get('kind')=='full_adapter' and c['command']==['dart','--enable-asserts',path]]
            self.assertEqual(len(matches),1,path)
        unknown='scripts/test/new_unowned_test.dart'
        result=checks.select(copy.deepcopy(rules),[{'path':unknown,'status':'A'}],'change',[unknown],ROOT)
        self.assertEqual(result['unmapped_changes'],[unknown])

    @unittest.skipUnless(DART.exists(), 'real Dart SDK launcher required')
    def test_both_current_standalone_contracts_execute_with_assertions(self):
        for path in ['scripts/test/ios_receiver_bootstrap_contract_test.dart','scripts/test/ios_sender_projection_fixture_contract_test.dart']:
            with self.subTest(path=path):
                result=subprocess.run([str(DART),'--enable-asserts',path],cwd=ROOT,text=True,capture_output=True)
                self.assertEqual(result.returncode,0,result.stderr)


class SelectorFlowContracts(unittest.TestCase):
    def test_warm_dart_route_failure_cannot_pass_native_foreground_check(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);log=root/'log';log.write_text('REMOTE_NOTIFICATION_ROUTE_ERROR: missing fixture contact\n')
            script=root/'probe.sh'
            script.write_text(source+'\nassert_log_contains() { return 0; }\nassert_scenario_markers warm "$CONTRACT_LOG" direct text direct_message\n')
            result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_LOG':str(log)},capture_output=True,text=True,timeout=10)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('REMOTE_NOTIFICATION_ROUTE_ERROR',result.stderr)

    def test_both_build_paths_enable_existing_debug_fixture_seam(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        for skip in (0, 1):
            with self.subTest(skip=skip), tempfile.TemporaryDirectory() as name:
                root=Path(name);script=root/'probe.sh'
                script.write_text(source+r'''
RESULT_ROOT="$CONTRACT_ROOT/output"
APP_PATH="$CONTRACT_ROOT"
MATRIX_FIXTURE="$CONTRACT_MATRIX"
skip_build="$CONTRACT_SKIP"
scenario_filter=cold:direct_video
flutter() { printf '%s\n' "$*" >> "$CONTRACT_ROOT/flutter-args"; }
split_devices() { printf 'simulator\tContract phone\n'; }
prepare_xcode_ui_tests() { :; }
install_app_on_device() { :; }
run_scenario() { :; }
main
''')
                result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_ROOT':name,'CONTRACT_SKIP':str(skip),'CONTRACT_MATRIX':str(ROOT/'test/features/push/fixtures/ios_notification_message_matrix.json')},capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode,0,result.stderr)
                args=(root/'flutter-args').read_text()
                self.assertIn('--dart-define=E2E_TEST_MODE=true',args)
                self.assertIn('--dart-define=PRODUCTION_FCM=true',args)
                self.assertEqual('--config-only' in args, bool(skip))

    def test_warm_host_push_requires_fresh_authorized_alert_settings(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        for authorization,alert,emit,expected in [(2,2,True,True),(0,0,True,False),(1,1,True,False),(2,1,True,False),(2,2,False,False)]:
            with self.subTest(authorization=authorization,alert=alert,emit=emit), tempfile.TemporaryDirectory() as name:
                root=Path(name);log=root/'log'
                # Old authorization is insufficient if the current launch emits none.
                log.write_text('[PUSH_DIAG] native_notification_settings authorization=UNAuthorizationStatus(rawValue: 2) alert=UNNotificationSetting(rawValue: 2)\n')
                script=root/'probe.sh'
                script.write_text(source+r'''
xcrun() {
  if [[ "$4" == com.apple.springboard ]]; then touch "$CONTRACT_ROOT/backgrounded";
  elif [[ "$CONTRACT_EMIT" == 1 ]]; then
    printf '[PUSH_DIAG] native_notification_settings authorization=UNAuthorizationStatus(rawValue: %s) alert=UNNotificationSetting(rawValue: %s)\n' "$CONTRACT_AUTH" "$CONTRACT_ALERT"
  fi
}
wait_for_any_pattern_after_line() { return 0; }
sleep() { :; }
launch_warm_app_for_host_push simulator "$CONTRACT_ROOT/log" "$$"
''')
                result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_ROOT':name,'CONTRACT_EMIT':str(int(emit)),'CONTRACT_AUTH':str(authorization),'CONTRACT_ALERT':str(alert)},capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode==0,expected,result.stderr)
                self.assertEqual((root/'backgrounded').exists(),expected)

    def test_install_requires_permission_setup_and_ends_its_launch(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        for authorized,native_code in [(True,0),(False,0),(True,7)]:
            with self.subTest(authorized=authorized,native_code=native_code), tempfile.TemporaryDirectory() as name:
                root=Path(name);script=root/'probe.sh'
                script.write_text(source+r'''
RESULT_ROOT="$CONTRACT_ROOT"
xcrun() { printf '%s\n' "$*" >> "$CONTRACT_ROOT/order"; }
write_auto_setup_config() { printf 'auto_setup\n' >> "$CONTRACT_ROOT/order"; }
start_log_stream() { /bin/sleep 5 & started_pid=$!; }
run_xcode_ui_test() {
  printf 'selector=%s\n' "$2" >> "$CONTRACT_ROOT/order"
  (exit "$CONTRACT_NATIVE_CODE") & started_pid=$!
}
wait_for_ready_signal() { return 0; }
launch_warm_app_for_host_push() {
  printf 'authorization_readback\n' >> "$CONTRACT_ROOT/order"
  [[ "$CONTRACT_AUTHORIZED" == 1 ]]
}
install_app_on_device simulator Contract
''')
                result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_ROOT':name,'CONTRACT_AUTHORIZED':str(int(authorized)),'CONTRACT_NATIVE_CODE':str(native_code)},capture_output=True,text=True,timeout=10)
                self.assertEqual(result.returncode==0,authorized and native_code==0,result.stderr)
                order=(root/'order').read_text().splitlines()
                self.assertIn('selector=-only-testing:RunnerUITests/NotificationTapUITests/testPrepareWarmNotificationTap',order)
                self.assertEqual('authorization_readback' in order,native_code==0)
                self.assertEqual(order[-1],'simctl terminate simulator com.mknoon.app')

    def test_default_device_failure_is_not_automatically_retried(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);script=root/'probe.sh'
            script.write_text(source+r'''
run_scenario_once() { printf 'attempt\n' >> "$CONTRACT_ROOT/attempts"; return 17; }
sleep() { :; }
run_scenario simulator Contract direct_text warm Fixture
''')
            env={k:v for k,v in os.environ.items() if k!='IOS_NOTIFICATION_TAP_SMOKE_RETRIES'}
            result=subprocess.run(['bash',str(script)],env={**env,'CONTRACT_ROOT':name},capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,17,result.stderr)
            self.assertEqual((root/'attempts').read_text().splitlines(),['attempt'])

    def test_direct_fixture_uses_existing_contact_seeding_and_preserves_foreign_commands(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        for foreign in (False, True):
            with self.subTest(foreign=foreign), tempfile.TemporaryDirectory() as name:
                root=Path(name);documents=root/'Documents';documents.mkdir()
                config=documents/'intro_e2e_config.json'
                if foreign: config.write_text('{"stepId":"foreign-owner"}')
                script=root/'probe.sh'
                script.write_text(source+r'''
RESULT_ROOT="$CONTRACT_ROOT"
MATRIX_FIXTURE="$CONTRACT_MATRIX"
xcrun() {
  if [[ "$2" == get_app_container ]]; then printf '%s\n' "$CONTRACT_ROOT";
  else printf '%s\n' "$*" >> "$CONTRACT_ROOT/actions"; fi
}
prepare_direct_notification_fixture simulator direct_video direct
cp "$CONTRACT_ROOT/Documents/intro_e2e_config.json" "$CONTRACT_ROOT/observed.json"
cleanup_notification_fixture_commands
''')
                result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_ROOT':name,'CONTRACT_MATRIX':str(ROOT/'test/features/push/fixtures/ios_notification_message_matrix.json')},capture_output=True,text=True,timeout=10)
                if foreign:
                    self.assertNotEqual(result.returncode,0)
                    self.assertEqual(json.loads(config.read_text()),{'stepId':'foreign-owner'})
                else:
                    self.assertEqual(result.returncode,0,result.stderr)
                    command=json.loads((root/'observed.json').read_text())
                    contact=json.loads(command['add_contacts'][0]['qrPayload'])
                    self.assertEqual(contact['ns'],'peer-alice')
                    self.assertEqual(contact['un'],'Alice')
                    self.assertFalse(config.exists())

    def test_readiness_requires_an_emitted_event(self):
        source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
        cases=[
            ('predicate', '', 'Filtering the log data using "eventMessage CONTAINS \'MKNOON_APNS_TAP_READY\'"', False),
            ('build_export', '', 'export MKNOON_APNS_TAP_READY_FILE=/tmp/case.ready', False),
            ('empty_ready_file', '', '', False),
            ('partial_event', 'MKNOON_APNS_TAP_READY mode=warm', '', False),
            ('log_event', None, 'timestamp Runner: MKNOON_APNS_TAP_READY mode=cold title_configured=true', True),
            ('file_event', 'MKNOON_APNS_TAP_READY mode=warm title_configured=true\n', '', True),
        ]
        for label,ready,log,expected in cases:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as name:
                root=Path(name)
                if ready is not None: (root/'ready').write_text(ready)
                (root/'log').write_text(log)
                script=root/'probe.sh'
                script.write_text(source+'\nwait_for_ready_signal "$CONTRACT_ROOT/ready" "$CONTRACT_ROOT/log" "$$" 1\n')
                result=subprocess.run(['bash',str(script)],env={**os.environ,'CONTRACT_ROOT':name},capture_output=True,text=True,timeout=5)
                self.assertEqual(result.returncode==0,expected,result.stderr)

    def run_flow(self, method, mode, *, ready=True, push=True, native_code=0):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name)
            # Evaluate the actual campaign functions, replacing only external
            # device/build operations with a bounded synthetic process.
            source=(ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text().removesuffix('main "$@"\n')
            harness=source+r'''
RESULT_ROOT="$CONTRACT_ROOT"
native_selector="$CONTRACT_METHOD"
sleep() { /bin/sleep 0.01; }
matrix_case_fields() { printf 'Fixture title\tFixture body\tdirect\ttext\tdirect\n'; }
prepare_direct_notification_fixture() { printf 'fixture\n' >> "$CONTRACT_ROOT/order"; }
start_log_stream() { /bin/sleep 5 & started_pid=$!; }
run_xcode_ui_test() {
  printf 'selector=%s\n' "$2" >> "$CONTRACT_ROOT/order"
  (
    if [[ "$CONTRACT_READY" == 1 ]]; then
      printf 'MKNOON_APNS_TAP_READY mode=%s title_configured=true\n' "$CONTRACT_MODE" > "$5"
    fi
    for ((i=0;i<200;i++)); do
      [[ -f "$CONTRACT_ROOT/pushed" ]] && break
      /bin/sleep 0.01
    done
    [[ -f "$CONTRACT_ROOT/pushed" ]] || exit 78
    if [[ "$CONTRACT_NATIVE_CODE" == 0 ]]; then
      printf "Test Case '-[RunnerUITests.NotificationTapUITests %s]' passed (0.100 seconds).\n" "$CONTRACT_METHOD" >> "$3"
    else
      printf "Test Case '-[RunnerUITests.NotificationTapUITests %s]' failed (0.100 seconds).\n" "$CONTRACT_METHOD" >> "$3"
    fi
    exit "$CONTRACT_NATIVE_CODE"
  ) & started_pid=$!
}
if [[ "$CONTRACT_READY" != 1 ]]; then wait_for_ready_signal() { return 1; }; fi
push_fixture() {
  printf 'push\n' >> "$CONTRACT_ROOT/order"
  [[ "$CONTRACT_PUSH" == 1 ]] || return 1
  : > "$CONTRACT_ROOT/pushed"
}
xcrun() { printf 'native=%s\n' "$*" >> "$CONTRACT_ROOT/order"; }
assert_scenario_markers() { printf 'route_assertions\n' >> "$CONTRACT_ROOT/order"; }
run_scenario_once simulator 'Contract phone' direct_text "$CONTRACT_MODE" case
'''
            script=root/'harness.sh';script.write_text(harness)
            env={**os.environ,'CONTRACT_ROOT':str(root),'CONTRACT_METHOD':method,'CONTRACT_MODE':mode,
                 'CONTRACT_READY':str(int(ready)),'CONTRACT_PUSH':str(int(push)),'CONTRACT_NATIVE_CODE':str(native_code)}
            result=subprocess.run(['bash',str(script)],env=env,text=True,capture_output=True,timeout=10)
            order=(root/'order').read_text().splitlines() if (root/'order').exists() else []
            return result,order

    def test_integrated_warm_injects_after_exact_selector_and_keeps_route_assertions(self):
        result,order=self.run_flow('testNotificationTap','warm')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(order,['fixture','selector=-only-testing:RunnerUITests/NotificationTapUITests/testNotificationTap','push','route_assertions'])
        self.assertIn("testNotificationTap]' passed",result.stdout)

    def test_integrated_cold_terminates_before_native_ready_and_injection(self):
        result,order=self.run_flow('testColdNotificationTap','cold')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(order,['fixture','native=simctl terminate simulator com.mknoon.app','selector=-only-testing:RunnerUITests/NotificationTapUITests/testColdNotificationTap','push','route_assertions'])

    def test_existing_notification_preserves_push_before_tap(self):
        result,order=self.run_flow('testTapExistingNotification','cold')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertLess(order.index('push'),next(i for i,x in enumerate(order) if x.startswith('selector=')))
        self.assertEqual(order[-1],'route_assertions')

    def test_missing_readiness_never_injects_or_claims_pass(self):
        result,order=self.run_flow('testNotificationTap','warm',ready=False)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('push',order)
        self.assertNotIn('route_assertions',order)
        self.assertNotIn('PASS case',result.stdout)

    def test_injection_failure_never_reaches_route_assertions(self):
        result,order=self.run_flow('testNotificationTap','warm',push=False)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn('route_assertions',order)
        self.assertNotIn('PASS case',result.stdout)

    def test_native_failure_remains_failure(self):
        result,order=self.run_flow('testColdNotificationTap','cold',native_code=65)
        self.assertEqual(result.returncode,65)
        self.assertIn("testColdNotificationTap]' failed",result.stdout)
        self.assertNotIn('route_assertions',order)
        self.assertNotIn('PASS case',result.stdout)

class SelectorArgumentContracts(unittest.TestCase):
    def selection(self, args):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);script=root/'scripts/run_ios_notification_tap_ui_smoke.sh';script.parent.mkdir()
            script.write_text((ROOT/'scripts/run_ios_notification_tap_ui_smoke.sh').read_text())
            fixture=root/'test/features/push/fixtures/ios_notification_message_matrix.json';fixture.parent.mkdir(parents=True)
            fixture.write_bytes((ROOT/'test/features/push/fixtures/ios_notification_message_matrix.json').read_bytes())
            return subprocess.run(['bash',str(script),'--selection-only',*args],text=True,capture_output=True,timeout=10)

    def test_three_exact_native_modes_validate_without_device_actions(self):
        for method,scenario in [('testNotificationTap','warm:direct_text'),('testColdNotificationTap','cold:direct_video'),('testTapExistingNotification','cold:direct_video')]:
            with self.subTest(method=method):
                result=self.selection(['--native-selector',method,'--scenario',scenario,'--retries','0'])
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),scenario)

    def test_native_modes_reject_missing_scenario_wrong_pair_and_unknown_selector(self):
        for args in [
            ['--native-selector','testNotificationTap','--retries','0'],
            ['--native-selector','testNotificationTap','--scenario','cold:direct_video','--retries','0'],
            ['--native-selector','testColdNotificationTap','--scenario','warm:direct_text','--retries','0'],
            ['--native-selector','testArbitraryMethod','--scenario','warm:direct_text','--retries','0'],
        ]:
            with self.subTest(args=args):self.assertEqual(self.selection(args).returncode,2)

    def test_native_modes_require_no_automatic_retry(self):
        result=self.selection(['--native-selector','testNotificationTap','--scenario','warm:direct_text','--retries','1'])
        self.assertEqual(result.returncode,2)
        self.assertIn('--retries 0',result.stderr)

    def test_existing_matrix_selection_still_has_twelve_cases(self):
        result=self.selection([])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(result.stdout.splitlines()),12)
