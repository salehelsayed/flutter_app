from __future__ import annotations

from pathlib import Path
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "integration_test/scripts/ios_notification_payload_xcui_driver.dart"
FIXTURE_DRIVER = ROOT / "integration_test/scripts/ios_notification_identity_fixture.py"
sys.path.insert(0, str(FIXTURE_DRIVER.parent))
spec = importlib.util.spec_from_file_location("ios_identity_fixture", FIXTURE_DRIVER)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
RECEIVER = "00008030-0000000000000000"
PEER = "12D3KooW" + "a" * 44


def digest(value):
    return hashlib.sha256(value).hexdigest()


def private_json(path, value):
    path.write_text(json.dumps(value))
    path.chmod(0o600)


class PreparedFixture:
    def __init__(self, root):
        self.root = root
        self.snapshot = root / "snapshot"
        self.snapshot.mkdir(mode=0o700)
        self.manifest_path = self.snapshot / "manifest.json"
        self.database = b"opaque pristine SQLCipher database"
        self.wal = b"opaque committed identity WAL"
        for name, data in {"identity.db": self.database, "identity.db-wal": self.wal}.items():
            path = self.snapshot / name
            path.write_bytes(data)
            path.chmod(0o600)
        self.manifest = {
            "schema": fixture.SCHEMA,
            "bundleId": "com.mknoon.app",
            "receiverDeviceIdSha256": digest(RECEIVER.encode()),
            "peerDeviceIdSha256": digest(PEER.encode()),
            "mlKemPublicKeySha256": "a" * 64,
            "pristineBeforeProviderDispatch": True,
            "files": {"identity.db": digest(self.database), "identity.db-wal": digest(self.wal)},
        }
        self.staging_path = root / "staging.json"
        self.staging = {
            "receiverDeviceId": RECEIVER,
            "peerDeviceId": PEER,
            "bundleId": "com.mknoon.app",
            "dedicatedDisposableReceiver": True,
            "destructiveTestStateResetAuthorized": True,
            "identityDatabaseSnapshotManifest": "snapshot/manifest.json",
        }
        self.save()

    def save(self):
        private_json(self.manifest_path, self.manifest)
        self.staging["identityDatabaseSnapshotSha256"] = digest(self.manifest_path.read_bytes())
        private_json(self.staging_path, self.staging)

    def restore(self, control):
        temporary = self.root / "transfer"
        temporary.mkdir(mode=0o700, exist_ok=True)
        return fixture.restore_fixture(self.staging_path, receiver=RECEIVER,
                                       peer=PEER, temporary=temporary, control=control)


class DeviceTransfers:
    def __init__(self):
        self.events = []
        self.files = {}
        self.corrupt_readback = False
        self.fail_write = False

    def copy_to(self, source, label, destination):
        self.events.append(("write", destination))
        if self.fail_write:
            return False
        self.files[destination] = source.read_bytes()
        return True

    def copy_from(self, destination, label, source):
        self.events.append(("read", source))
        destination.write_bytes(b"corrupted" if self.corrupt_readback else self.files[source])
        return True


class IosNotificationIdentityFixtureTest(unittest.TestCase):
    def test_fresh_install_restores_identity_before_any_receiver_launch(self):
        source = DRIVER.read_text()
        preflight = source.split("Future<void> _preflight() async {", 1)[1]
        preflight = preflight.split("Future<void> _captureReceiverHandoff", 1)[0]
        self.assertIn("action: 'validate'", preflight)
        install = source.split("Future<void> _installExactApplication() async {", 1)[1]
        install = install.split("Future<void> _startSyslog() async {", 1)[0]
        self.assertIn("action: 'restore'", install)
        self.assertNotIn('SimsPayloadReceiver', install)
        self.assertNotIn("_stageReceiverAutoSetup", install)
        self.assertLess(install.index("'before-install'"), install.index("'install'"))
        self.assertNotIn("'launch'", install)
        # Every original phase installs/restores before its UI preparation.
        self.assertEqual(source.count("await _installExactApplication();"), 3)

    def test_each_fresh_container_receives_same_database_and_sidecars_before_launch(self):
        with tempfile.TemporaryDirectory() as raw:
            prepared = PreparedFixture(Path(raw))
            for _ in range(3):
                control = DeviceTransfers()
                result = prepared.restore(control)
                self.assertEqual(control.files, {
                    "Documents/identity.db": prepared.database,
                    "Documents/identity.db-wal": prepared.wal,
                })
                self.assertEqual(control.events, [
                    ("write", "Documents/identity.db"),
                    ("write", "Documents/identity.db-wal"),
                    ("read", "Documents/identity.db"),
                    ("read", "Documents/identity.db-wal"),
                ])
                self.assertEqual(result["mlKemPublicKeySha256"], "a" * 64)
                # The next original phase cannot inherit any prior phase bytes.
                control.files["Documents/identity.db"] = b"phase-end history"

    def test_read_only_validation_never_constructs_device_control(self):
        with tempfile.TemporaryDirectory() as raw:
            prepared = PreparedFixture(Path(raw))
            original = fixture._DeviceControl
            fixture._DeviceControl = lambda **kwargs: self.fail("device command in preflight")
            try:
                result = fixture.validate_fixture(prepared.staging_path, receiver=RECEIVER, peer=PEER)
                self.assertEqual(result["manifestSha256"], prepared.staging["identityDatabaseSnapshotSha256"])
            finally:
                fixture._DeviceControl = original

    def test_mismatched_authority_and_untrusted_paths_fail_before_device_write(self):
        mutations = [
            lambda p: p.staging.update(receiverDeviceId="other-phone"),
            lambda p: p.staging.update(peerDeviceId="other-peer"),
            lambda p: p.staging.update(bundleId="other.app"),
            lambda p: p.staging.update(dedicatedDisposableReceiver=False),
            lambda p: p.staging.update(destructiveTestStateResetAuthorized=False),
            lambda p: p.staging.pop("identityDatabaseSnapshotManifest"),
            lambda p: p.staging.update(identityDatabaseSnapshotManifest="../snapshot/manifest.json"),
            lambda p: p.staging.update(identityDatabaseSnapshotManifest="/tmp/manifest.json"),
            lambda p: p.staging.update(identityDatabaseSnapshotManifest="snapshot//manifest.json"),
            lambda p: p.manifest.update(receiverDeviceIdSha256="b" * 64),
            lambda p: p.manifest.update(peerDeviceIdSha256="b" * 64),
            lambda p: p.manifest.update(bundleId="other.app"),
            lambda p: p.manifest.update(pristineBeforeProviderDispatch=False),
            lambda p: p.manifest.update(pristineBeforeProviderDispatch=1),
            lambda p: p.manifest.update(mlKemPublicKeySha256="invalid-key"),
            lambda p: p.manifest["files"].update({"../identity.db": "b" * 64}),
            lambda p: p.manifest["files"].pop("identity.db"),
            lambda p: p.manifest["files"].update({"identity.db": "b" * 64}),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate), tempfile.TemporaryDirectory() as raw:
                prepared = PreparedFixture(Path(raw))
                mutate(prepared)
                prepared.save()
                control = DeviceTransfers()
                with self.assertRaises(fixture.FixtureFailure):
                    prepared.restore(control)
                self.assertEqual(control.events, [])

    def test_changed_key_or_database_without_staging_reauthorization_fails_before_write(self):
        for kind in ("key", "database", "manifest-digest"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as raw:
                prepared = PreparedFixture(Path(raw))
                if kind == "key":
                    prepared.manifest["mlKemPublicKeySha256"] = "b" * 64
                    private_json(prepared.manifest_path, prepared.manifest)
                elif kind == "database":
                    (prepared.snapshot / "identity.db").write_bytes(b"different database")
                else:
                    prepared.staging["identityDatabaseSnapshotSha256"] = "b" * 64
                    private_json(prepared.staging_path, prepared.staging)
                control = DeviceTransfers()
                with self.assertRaises(fixture.FixtureFailure):
                    prepared.restore(control)
                self.assertEqual(control.events, [])

    def test_all_allowed_present_sidecars_are_transferred_and_verified(self):
        with tempfile.TemporaryDirectory() as raw:
            prepared = PreparedFixture(Path(raw))
            for name in ("identity.db-shm", "identity.db-journal"):
                path = prepared.snapshot / name
                path.write_bytes(b"opaque sidecar")
                path.chmod(0o600)
                prepared.manifest["files"][name] = digest(path.read_bytes())
            prepared.save()
            control = DeviceTransfers()
            prepared.restore(control)
            self.assertEqual(set(control.files), {f"Documents/{name}" for name in prepared.manifest["files"]})
            self.assertEqual(len(control.events), 8)

    def test_unprotected_symlink_hardlink_and_untracked_files_fail_before_write(self):
        for kind in ("file-mode", "directory-mode", "manifest-mode", "staging-mode",
                     "symlink", "symlink-parent", "hardlink", "extra-sidecar"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as raw:
                prepared = PreparedFixture(Path(raw))
                database = prepared.snapshot / "identity.db"
                if kind == "file-mode":
                    database.chmod(0o644)
                elif kind == "directory-mode":
                    prepared.snapshot.chmod(0o755)
                elif kind == "manifest-mode":
                    prepared.manifest_path.chmod(0o644)
                elif kind == "staging-mode":
                    prepared.staging_path.chmod(0o644)
                elif kind == "symlink":
                    original = prepared.root / "original.db"
                    database.rename(original)
                    database.symlink_to(original)
                elif kind == "symlink-parent":
                    original = prepared.root / "original"
                    prepared.snapshot.rename(original)
                    prepared.snapshot.symlink_to(original, target_is_directory=True)
                elif kind == "hardlink":
                    os.link(database, prepared.root / "linked.db")
                else:
                    (prepared.snapshot / "identity.db-journal").write_bytes(b"unattested")
                control = DeviceTransfers()
                with self.assertRaises(fixture.FixtureFailure):
                    prepared.restore(control)
                self.assertEqual(control.events, [])

    def test_copy_failure_and_corrupt_roundtrip_never_report_success(self):
        for kind in ("write", "roundtrip"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as raw:
                prepared = PreparedFixture(Path(raw))
                control = DeviceTransfers()
                control.fail_write = kind == "write"
                control.corrupt_readback = kind == "roundtrip"
                with self.assertRaises(fixture.FixtureFailure):
                    prepared.restore(control)

    def test_cli_failure_is_redacted_and_never_contacts_device(self):
        with tempfile.TemporaryDirectory() as raw:
            prepared = PreparedFixture(Path(raw))
            prepared.manifest["privateKey"] = "private-value-must-not-escape"
            prepared.save()
            result = subprocess.run([
                sys.executable, str(FIXTURE_DRIVER), "--action", "restore",
                "--staging-manifest", str(prepared.staging_path),
                "--receiver", RECEIVER, "--peer", PEER,
            ], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 78)
            self.assertNotIn("private-value-must-not-escape", result.stdout + result.stderr)
            self.assertIn('"code":"fixture_shape"', result.stdout)


if __name__ == "__main__":
    unittest.main()
