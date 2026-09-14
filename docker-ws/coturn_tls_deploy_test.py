#!/usr/bin/env python3
"""Offline renewal failure controls; fixture CA is not public-root evidence."""

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'coturn_tls_deploy', Path(__file__).with_name('coturn_tls_deploy.py'))
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)


class CertificatePromotionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory()
        cls.fixtures = Path(cls.temporary.name)
        root = cls.fixtures / 'root'
        deploy.openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                       '-keyout', str(root) + '.key', '-out', str(root) + '.pem',
                       '-days', '45', '-subj', '/CN=Offline fixture root',
                       '-addext', 'basicConstraints=critical,CA:TRUE',
                       '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
        cls.trust = Path(str(root) + '.pem')
        intermediate = cls.fixtures / 'intermediate'
        deploy.openssl('req', '-new', '-newkey', 'rsa:2048', '-nodes',
                       '-keyout', str(intermediate) + '.key',
                       '-out', str(intermediate) + '.csr', '-subj', '/CN=Fixture issuer')
        extensions = cls.fixtures / 'issuer.ext'
        extensions.write_text('basicConstraints=critical,CA:TRUE,pathlen:0\n'
                              'keyUsage=critical,keyCertSign,cRLSign\n')
        deploy.openssl('x509', '-req', '-in', str(intermediate) + '.csr',
                       '-CA', cls.trust, '-CAkey', str(root) + '.key',
                       '-set_serial', '1', '-out', str(intermediate) + '.pem',
                       '-days', '40', '-extfile', extensions)
        for index, (name, hostname, days) in enumerate([
                ('old', 'turn.invalid', 30), ('new', 'turn.invalid', 31),
                ('wrong-host', 'other.invalid', 30), ('near-expiry', 'turn.invalid', 1)]):
            directory = cls.fixtures / name
            directory.mkdir()
            deploy.openssl('req', '-new', '-newkey', 'rsa:2048', '-nodes',
                           '-keyout', directory / 'privkey.pem',
                           '-out', directory / 'request.csr', '-subj', f'/CN={hostname}')
            extensions.write_text(f'subjectAltName=DNS:{hostname}\n'
                                  'basicConstraints=critical,CA:FALSE\n'
                                  'keyUsage=critical,digitalSignature,keyEncipherment\n'
                                  'extendedKeyUsage=serverAuth\n')
            deploy.openssl('x509', '-req', '-in', directory / 'request.csr',
                           '-CA', str(intermediate) + '.pem',
                           '-CAkey', str(intermediate) + '.key',
                           '-set_serial', str(index + 2), '-out', directory / 'leaf.pem',
                           '-days', str(days), '-extfile', extensions)
            (directory / 'fullchain.pem').write_bytes(
                (directory / 'leaf.pem').read_bytes() +
                Path(str(intermediate) + '.pem').read_bytes())

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.working = tempfile.TemporaryDirectory()
        self.addCleanup(self.working.cleanup)
        self.destination = Path(self.working.name) / 'tls'
        self.destination.mkdir(mode=0o750)
        for name in ('fullchain.pem', 'privkey.pem'):
            shutil.copyfile(self.fixtures / 'old' / name, self.destination / name)
        self.reloads = []
        self.old_fingerprint = self.promote(self.fixtures / 'old', prepare=True)

    def promote(self, source, *, prepare=False, callback=None):
        return deploy.promote(source, self.destination, self.trust, 'turn.invalid',
                              os.getgid(), callback or self.reloads.append, prepare=prepare)

    def pair(self):
        return tuple((self.destination / n).read_bytes()
                     for n in ('fullchain.pem', 'privkey.pem'))

    def test_prepare_preserves_bytes_permissions_and_does_not_reload(self):
        self.assertEqual(self.reloads, [])
        for name in ('fullchain.pem', 'privkey.pem'):
            path = self.destination / name
            self.assertEqual(path.read_bytes(), (self.fixtures / 'old' / name).read_bytes())
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
            self.assertEqual(os.readlink(path), f'current/{name}')

    def test_valid_renewal_switches_both_files_before_reload_and_keeps_rollback(self):
        previous = (self.destination / 'current').resolve()
        seen = []

        def reload(fingerprint):
            seen.append(deploy.validate_pair(self.destination, self.trust, 'turn.invalid'))
            self.assertEqual(seen[-1], fingerprint)
            self.assertEqual(self.pair(), tuple((self.fixtures / 'new' / n).read_bytes()
                                               for n in ('fullchain.pem', 'privkey.pem')))

        fingerprint = self.promote(self.fixtures / 'new', callback=reload)
        self.assertNotEqual(fingerprint, self.old_fingerprint)
        self.assertEqual(seen, [fingerprint])
        self.assertTrue(previous.is_dir())

    def test_invalid_replacements_never_overwrite_or_signal(self):
        original = self.pair()
        previous = os.readlink(self.destination / 'current')
        for kind in ('wrong-host', 'near-expiry', 'key-mismatch', 'missing-issuer',
                     'reversed-chain', 'malformed', 'untrusted-root'):
            with self.subTest(kind=kind):
                source = Path(self.working.name) / kind
                shutil.copytree(self.fixtures / (kind if kind in ('wrong-host', 'near-expiry') else 'new'), source)
                if kind == 'key-mismatch':
                    shutil.copyfile(self.fixtures / 'old/privkey.pem', source / 'privkey.pem')
                if kind == 'missing-issuer':
                    shutil.copyfile(source / 'leaf.pem', source / 'fullchain.pem')
                if kind == 'reversed-chain':
                    (source / 'fullchain.pem').write_bytes(
                        (self.fixtures / 'intermediate.pem').read_bytes() + (source / 'leaf.pem').read_bytes())
                if kind == 'malformed':
                    (source / 'fullchain.pem').write_bytes(b'not a certificate')
                if kind == 'untrusted-root':
                    deploy.openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                                   '-keyout', source / 'privkey.pem', '-out', source / 'fullchain.pem',
                                   '-days', '30', '-subj', '/CN=turn.invalid',
                                   '-addext', 'subjectAltName=DNS:turn.invalid')
                with self.assertRaises(deploy.InvalidCertificate):
                    self.promote(source)
                self.assertEqual(self.pair(), original)
                self.assertEqual(os.readlink(self.destination / 'current'), previous)
                self.assertEqual(self.reloads, [])

    def test_reload_failure_restores_old_pair_and_is_still_failure(self):
        previous = os.readlink(self.destination / 'current')
        seen = []

        def reload(fingerprint):
            self.assertEqual(deploy.validate_pair(self.destination, self.trust, 'turn.invalid'), fingerprint)
            seen.append(fingerprint)
            if len(seen) == 1:
                raise RuntimeError('simulated listener failed to load new pair')

        with self.assertRaisesRegex(RuntimeError, 'simulated listener'):
            self.promote(self.fixtures / 'new', callback=reload)
        self.assertEqual(os.readlink(self.destination / 'current'), previous)
        self.assertEqual(seen[-1], self.old_fingerprint)
        self.assertEqual(len(seen), 2)

    def test_unrelated_lineage_hook_does_nothing(self):
        result = subprocess.run(['sh', str(Path(__file__).with_name('50-mknoon-coturn'))],
                                env={**os.environ, 'RENEWED_LINEAGE': '/unrelated/lineage'},
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
