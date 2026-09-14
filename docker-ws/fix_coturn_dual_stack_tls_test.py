"""Preservation and rollback for the separate external-IPv4-only repair mode."""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('turn_listener_repair', Path(__file__).with_name('fix_coturn_dual_stack_tls.py'))
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)

ORIGINAL = ('realm=synthetic.invalid\r\n'
            'static-auth-secret=synthetic-preserved-secret\r\n'
            'external-ip=192.0.2.9/10.0.0.2 # keep mapping comment\r\n'
            'relay-ip=2001:db8::2\r\n'
            'allowed-peer-ip=10.0.0.2\r\n'
            'cert=/preserve/fullchain.pem\r\n'
            'pkey=/preserve/privkey.pem\r\n'
            'min-port=49152\r\nmax-port=50175\r\n')


class ExternalIpv4RepairTest(unittest.TestCase):
    def args(self, *, apply=False, expected=None):
        return SimpleNamespace(private_ipv4='10.0.0.2', public_ipv4='198.51.100.10',
                               apply=apply, expect_config_sha256=expected)

    def test_only_the_selected_public_ipv4_bytes_change(self):
        changed = repair.render_external_ipv4(ORIGINAL, '10.0.0.2', '198.51.100.10')
        self.assertEqual(changed, ORIGINAL.replace('192.0.2.9', '198.51.100.10'))
        for bad in (ORIGINAL.replace('/10.0.0.2', '/10.0.0.3'),
                    ORIGINAL + 'external-ip=192.0.2.8/10.0.0.2\n'):
            with self.assertRaises(ValueError):
                repair.render_external_ipv4(bad, '10.0.0.2', '198.51.100.10')
        with self.assertRaises(ValueError):
            repair.render_external_ipv4(ORIGINAL, '10.0.0.2', '2001:db8::10')

    @patch.object(repair, 'active_allocation_count', return_value=0)
    @patch.object(repair.subprocess, 'check_output', return_value=b'99\n')
    @patch.object(repair.subprocess, 'run')
    def test_preview_does_not_touch_config_certificates_hooks_or_services(self, run, pid, allocations):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'turnserver.conf'; config.write_bytes(ORIGINAL.encode())
            output = io.StringIO()
            with contextlib.redirect_stdout(output): repair.repair_external_ipv4(self.args(), config=config)
            self.assertEqual(config.read_bytes(), ORIGINAL.encode())
            self.assertNotIn('synthetic-preserved-secret', output.getvalue())
            run.assert_not_called()
            self.assertEqual(pid.call_args.args[0], ['systemctl', 'show', 'coturn', '-p', 'MainPID', '--value'])
            self.assertEqual(list(Path(directory).iterdir()), [config])

    @patch.object(repair.subprocess, 'run')
    def test_apply_requires_the_exact_preview_hash(self, run):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'turnserver.conf'; config.write_bytes(ORIGINAL.encode())
            with self.assertRaisesRegex(RuntimeError, 'expected hash'):
                repair.repair_external_ipv4(self.args(apply=True, expected='outdated'), config=config)
            self.assertEqual(config.read_bytes(), ORIGINAL.encode())
            run.assert_not_called()

    @patch.object(repair, 'active_allocation_count', return_value=1)
    @patch.object(repair.subprocess, 'check_output', return_value=b'99\n')
    @patch.object(repair.subprocess, 'run')
    def test_active_calls_prevent_application_and_restart(self, run, pid, allocations):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'turnserver.conf'; config.write_bytes(ORIGINAL.encode())
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, 'Active TURN'):
                repair.repair_external_ipv4(self.args(apply=True, expected=hashlib.sha256(ORIGINAL.encode()).hexdigest()), config=config)
            self.assertEqual(config.read_bytes(), ORIGINAL.encode())
            run.assert_not_called()

    @patch.object(repair, 'active_allocation_count', return_value=0)
    @patch.object(repair.subprocess, 'check_output', return_value=b'99\n')
    @patch.object(repair.subprocess, 'run')
    def test_failed_restart_restores_exact_config_and_keeps_certificate_paths(self, run, pid, allocations):
        run.side_effect = [subprocess.CalledProcessError(1, ['systemctl', 'restart', 'coturn']), SimpleNamespace(returncode=0)]
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'turnserver.conf'; config.write_bytes(ORIGINAL.encode())
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError):
                repair.repair_external_ipv4(self.args(apply=True, expected=hashlib.sha256(ORIGINAL.encode()).hexdigest()),
                    config=config, backup_root=Path(directory) / 'backups')
            self.assertEqual(config.read_bytes(), ORIGINAL.encode())
            self.assertEqual([call.args[0] for call in run.call_args_list], [['systemctl', 'restart', 'coturn']] * 2)


if __name__ == '__main__':
    unittest.main()
