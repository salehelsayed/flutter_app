"""Host-only setup contracts. No device, Appium session or service is contacted."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import device_campaign_preflight as preflight

# Redacted, source-supported shape: ProcessList.dumpProcessesLSP calls the
# instrumentation census before dumpOtherProcessesInfoLSP, whose unconditional
# final record is mForceBackgroundCheck. This is host data, not device evidence.
IDLE = """ACTIVITY MANAGER RUNNING PROCESSES (dumpsys activity processes)
  All known processes:
  *PERS* UID 1000 ProcessRecord{fixture 1:system/1000}
  Process LRU list (sorted by oom_adj, 1 total, non-act at 0, non-svc at 0):
    PERS #0: sys ProcessRecord{fixture 1:system/1000}
  Total persistent processes: 1
  mProcessesReady=true mSystemReady=true mBooted=true mFactoryTest=0
  mBooting=false mCallFinishBooting=false mBootAnimationComplete=true
  ServiceManager statistics:
    getService(): count=1
  mForceBackgroundCheck=false
"""
BUSY = IDLE.replace('  Process LRU list',
                    '  Active instrumentation:\n    Instrumentation #0: private-canary\n  Process LRU list')



class CampaignPreflightTest(unittest.TestCase):
    def run_fixture(self, outputs, **updates):
        commands = []
        check = {'device_roles': ['android_physical', 'android_emulator'],
                 'host_preflight': 'notification-runner', **updates}
        def launch(command, root, timeout, env):
            commands.append(command)
            return outputs[len(commands) - 1]
        receipt = preflight.run(check, Path('/unused'),
                                {'devices': {'android_physical': 'fixture-phone',
                                             'android_emulator': 'fixture-emulator'}}, launch, {})
        return receipt, commands

    def test_busy_owner_stops_before_dependencies_without_disclosing_dump(self):
        receipt, commands = self.run_fixture([(BUSY, 0, False, .01)])
        self.assertEqual(receipt['checkpoint'], 'device_automation_busy')
        self.assertEqual(commands, [['adb', '-s', 'fixture-phone', 'shell', 'dumpsys', 'activity', 'processes']])
        self.assertIn('preserve foreign sessions', receipt['remediation'])
        self.assertNotIn('private-canary', json.dumps(receipt))

    def test_missing_or_failed_observation_never_means_idle(self):
        for output in [('', 0, False, .01), ('unknown format', 0, False, .01),
                       (IDLE + 'Permission Denial', 0, False, .01),
                       (IDLE, 1, False, .01), (IDLE, 0, True, .01)]:
            with self.subTest(output=output):
                receipt, commands = self.run_fixture([output])
                self.assertEqual(receipt['checkpoint'], 'device_automation_unobserved')
                self.assertEqual(len(commands), 1)

    def test_internal_dump_failure_with_zero_exit_never_reaches_host_probe(self):
        # Dumpsys::main returns zero even after its own 10-second timeout;
        # the wrapper's 15-second subprocess timeout does not detect it.
        for error in ("*** SERVICE 'activity' DUMP TIMEOUT (10000ms) EXPIRED ***",
                      "Error with service 'activity' while dumping: DEAD_OBJECT",
                      "Error while reading data for service activity: EPIPE",
                      "Exception occurred while dumping:"):
            for body in (IDLE, IDLE.split('  Process LRU list')[0]):
                with self.subTest(error=error, partial=body != IDLE):
                    receipt, commands = self.run_fixture([
                        (body + error + '\n', 0, False, .01),
                        (IDLE, 0, False, .01),
                        ('tc_a6_replay_before_ack_custody\n', 0, False, .01)])
                    self.assertEqual(receipt['checkpoint'], 'device_automation_unobserved')
                    self.assertEqual(len(commands), 1)

    def test_partial_or_unfamiliar_process_frames_never_mean_idle(self):
        header = IDLE.splitlines()[0] + '\n'
        for body in (header, header + '  Process LRU list:\n',
                     IDLE.rsplit('  mForceBackgroundCheck=', 1)[0],
                     IDLE.replace('mProcessesReady=true', 'unknownProcessState=true'),
                     IDLE + 'unrecognized trailing output\n',
                     IDLE + IDLE,
                     IDLE.replace('RUNNING PROCESSES', 'UNKNOWN PROCESSES')):
            with self.subTest(body=body):
                self.assertEqual(preflight.instrumentation_state(body), 'unavailable')

    def test_complete_source_supported_idle_frames_are_accepted(self):
        for force_background_check in ('true', 'false'):
            body = IDLE.replace('mForceBackgroundCheck=false',
                                'mForceBackgroundCheck=' + force_background_check)
            self.assertEqual(preflight.instrumentation_state(body), 'idle')
            self.assertEqual(preflight.instrumentation_state('\n' + body + '\n'), 'idle')

    def test_both_pinned_targets_precede_audited_no_device_listing(self):
        receipt, commands = self.run_fixture([(IDLE, 0, False, .01)] * 2 + [
            ('tc_a6_replay_before_ack_custody\n', 0, False, .02)])
        self.assertEqual(receipt['status'], 'PASS')
        self.assertEqual([c[2] for c in commands[:2]], ['fixture-phone', 'fixture-emulator'])
        self.assertEqual(commands[-1], ['dart', 'run',
            'integration_test/scripts/run_notification_tap_device_real.dart', '--list-scenarios'])

    def test_dependency_failure_is_bounded_and_redacted(self):
        for output in [('SocketException private-canary', 1, False, .02),
                       ('', 0, False, .02), ('', -9, True, .02)]:
            with self.subTest(output=output):
                receipt, commands = self.run_fixture([(IDLE, 0, False, .01)] * 2 + [output])
                self.assertEqual(receipt['checkpoint'], 'device_runner_dependencies_unready')
                self.assertEqual(len(commands), 3)
                self.assertNotIn('private-canary', json.dumps(receipt))

    def test_ios_only_check_never_invents_an_android_probe(self):
        receipt, commands = self.run_fixture([], device_roles=['ios_physical'], host_preflight=None)
        self.assertEqual(receipt['status'], 'PASS')
        self.assertEqual(commands, [])

    def test_campaign_exception_needs_a_reason_and_probe_must_be_known(self):
        check = {'kind': 'sims', 'device_roles': ['android_physical']}
        self.assertTrue(preflight.validate_metadata(check))
        check.update(ui_driver='existing_campaign', ui_driver_reason='Protocol fault injection')
        self.assertEqual(preflight.validate_metadata(check), [])
        for probe in ('unknown', []):
            self.assertTrue(preflight.validate_metadata({**check, 'host_preflight': probe}))

    def test_lease_is_cross_process_and_released_on_exception(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / 'leases'
            def child(target):
                program = ('import sys\n'
                           f'sys.path.insert(0, {str(Path(preflight.__file__).parent)!r})\n'
                           'from device_campaign_preflight import device_leases, DeviceLeaseBusy\n'
                           'try:\n'
                           f'    with device_leases([{target!r}], {str(directory)!r}): pass\n'
                           'except DeviceLeaseBusy: sys.exit(7)\n')
                return subprocess.run([sys.executable, '-c', program], capture_output=True, timeout=5).returncode
            with self.assertRaisesRegex(RuntimeError, 'fixture failure'):
                with preflight.device_leases(['fixture-target'], directory):
                    self.assertEqual(child('fixture-target'), 7)
                    self.assertEqual(child('other-target'), 0)
                    raise RuntimeError('fixture failure')
            self.assertEqual(child('fixture-target'), 0)

    def test_symlink_lease_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / 'alias'
            directory.symlink_to(temp, target_is_directory=True)
            with self.assertRaises(preflight.DeviceLeaseBusy):
                with preflight.device_leases(['fixture-target'], directory):
                    self.fail('unsafe lease admitted')
            self.assertEqual(list(Path(temp).iterdir()), [directory])


if __name__ == '__main__':
    unittest.main()
