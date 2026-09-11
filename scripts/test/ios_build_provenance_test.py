from __future__ import annotations

import importlib.util
import json
import os
import plistlib
import subprocess
import tarfile
import tempfile
import textwrap
import unittest
import zipfile
from pathlib import Path
from unittest import mock


SPEC = importlib.util.spec_from_file_location(
    "ios_build_provenance", Path(__file__).resolve().parents[1] / "ios_build_provenance.py")
provenance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(provenance)


class IosBuildProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        (self.root / "lib").mkdir()
        (self.root / "lib/main.dart").write_text("void main() {}\n")
        (self.root / "pubspec.lock").write_text("packages: {}\n")
        (self.root / ".gitignore").write_text("build/\n")
        for args in (("init", "-q"), ("config", "user.email", "fixture@example.invalid"),
                     ("config", "user.name", "Fixture"), ("add", "."),
                     ("commit", "-qm", "fixture")):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)
        original = provenance.command

        def command(root, *args):
            if args[:2] == ("flutter", "--version"):
                return json.dumps({"frameworkVersion": "fixture", "flutterRoot": "/private/sdk"})
            if args[0] == "xcodebuild":
                return "Xcode fixture\nBuild version fixture"
            return original(root, *args)

        patcher = mock.patch.object(provenance, "command", side_effect=command)
        patcher.start()
        self.addCleanup(patcher.stop)
        uuid_patcher = mock.patch.object(provenance, "image_uuids", side_effect=lambda root, path: [
            {"uuid": path.read_text(), "architecture": "arm64"}])
        uuid_patcher.start()
        self.addCleanup(uuid_patcher.stop)

    def products(self, capture):
        archive = self.root / "build/ios/archive/Runner.xcarchive"
        app = archive / "Products/Applications/Runner.app"
        app.mkdir(parents=True)
        info = {"CFBundleIdentifier": "com.example.fixture", "CFBundleVersion": "117",
                "CFBundleShortVersionString": "1.0.1"}
        (archive / "Info.plist").write_bytes(plistlib.dumps({"fixture": True}))
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        binaries = {"Runner": "RUNNER-UUID", "Frameworks/App.framework/App": "APP-UUID",
                    "Frameworks/Flutter.framework/Flutter": "FLUTTER-UUID"}
        for name, identifier in binaries.items():
            target = app / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(identifier)
            stem = Path(name).name
            dsym = "Runner.app" if stem == "Runner" else stem + ".framework"
            dwarf = archive / "dSYMs" / (dsym + ".dSYM/Contents/Resources/DWARF") / stem
            dwarf.parent.mkdir(parents=True)
            dwarf.write_text(identifier)
        asset = app / "Frameworks/App.framework/flutter_assets/core.js"
        asset.parent.mkdir(parents=True)
        asset.write_text("/* synthetic bundled asset */")
        ipa = self.root / "build/ios/ipa/fixture.ipa"
        ipa.parent.mkdir(parents=True)
        with zipfile.ZipFile(ipa, "w") as zipped:
            for path in app.rglob("*"):
                if path.is_file():
                    zipped.write(path, "Payload/Runner.app/" + path.relative_to(app).as_posix())
        return archive, ipa

    def test_retains_exact_products_symbols_and_asset_hashes_without_overwriting(self):
        capture = provenance.begin(self.root, ["--dart-define=TOKEN=private-value"])
        archive, ipa = self.products(capture)
        destination = provenance.retain(self.root, capture, archive, ipa)
        record = json.loads((destination / "provenance.json").read_text())
        self.assertEqual(destination.parent.name, "1.0.1+117")
        self.assertEqual(record["status"], "retained")
        self.assertTrue(record["sourceUnchanged"])
        self.assertEqual(provenance.sha256(destination / "mknoon.ipa"), provenance.sha256(ipa))
        self.assertEqual(provenance.tree_hashes(destination / "Runner.xcarchive"),
                         provenance.tree_hashes(archive))
        self.assertIn("Payload/Runner.app/Frameworks/App.framework/flutter_assets/core.js",
                      record["ipaFilesSha256"])
        self.assertEqual(len(record["images"]), 6)
        encoded = json.dumps(record)
        self.assertNotIn("private-value", encoded)
        self.assertNotIn("/private/sdk", encoded)
        self.assertNotIn(str(self.root), encoded)
        with self.assertRaisesRegex(ValueError, "already completed"):
            provenance.retain(self.root, destination, archive, ipa)

    def test_changed_source_retains_evidence_and_does_not_claim_unchanged_inputs(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        (self.root / "lib/main.dart").write_text("void main() { print('changed'); }\n")
        destination = provenance.retain(self.root, capture, archive, ipa)
        record = json.loads((destination / "provenance.json").read_text())
        self.assertEqual(record["status"], "retained_source_changed")
        self.assertFalse(record["sourceUnchanged"])
        self.assertTrue(record["after"]["relevantWorkingTreeDirty"])
        self.assertNotEqual(record["before"]["files"]["lib/main.dart"],
                            record["after"]["files"]["lib/main.dart"])
        self.assertIn("after", record["sourceSnapshots"])
        self.assertIn(b"print('changed')", (destination / "source-after.patch").read_bytes())

    def test_local_source_bytes_reconstruct_staged_unstaged_binary_deleted_and_new_files(self):
        (self.root / "assets").mkdir()
        (self.root / "assets/icon.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00original")
        (self.root / "lib/deleted.dart").write_text("const deleted = true;\n")
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "extra fixture"], cwd=self.root, check=True)
        revision = provenance.command(self.root, "git", "rev-parse", "HEAD")
        (self.root / "lib/main.dart").write_text("void main() { print('staged'); }\n")
        subprocess.run(["git", "add", "lib/main.dart"], cwd=self.root, check=True)
        (self.root / "lib/main.dart").write_text("void main() { print('unstaged'); }\n")
        (self.root / "lib/deleted.dart").unlink()
        (self.root / "assets/icon.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00changed")
        (self.root / "lib/new.dart").write_text("const newlyAdded = true;\n")
        (self.root / "lib/new.dart").chmod(0o755)

        capture = provenance.begin(self.root, [])
        record = json.loads((capture / "provenance.json").read_text())
        snapshot = record["sourceSnapshots"]["before"]
        self.assertEqual(snapshot["revision"], revision)
        self.assertEqual(snapshot["excluded"], {})
        self.assertIn(b"GIT binary patch", (capture / snapshot["patch"]["path"]).read_bytes())
        self.assertEqual(capture.stat().st_mode & 0o777, 0o700)
        self.assertEqual((capture / snapshot["patch"]["path"]).stat().st_mode & 0o777, 0o600)
        with tempfile.TemporaryDirectory() as temporary:
            restored = Path(temporary) / "restored"
            subprocess.run(["git", "clone", "-q", str(self.root), str(restored)], check=True)
            subprocess.run(["git", "apply", "--binary", str(capture / snapshot["patch"]["path"])],
                           cwd=restored, check=True)
            with tarfile.open(capture / snapshot["untrackedArchive"]["path"]) as tar:
                tar.extractall(restored, filter="data")
            for relative, digest in snapshot["retainedFileHashes"].items():
                self.assertEqual(provenance.sha256(restored / relative), digest)
                self.assertEqual((restored / relative).read_bytes(), (self.root / relative).read_bytes())
            self.assertFalse((restored / "lib/deleted.dart").exists())
            self.assertEqual((restored / "lib/new.dart").stat().st_mode & 0o777, 0o755)

    def test_source_snapshot_excludes_credentials_in_old_or_new_bytes_config_ignored_and_symlinks(self):
        private = b"-----BEGIN PRIVATE KEY-----\nsynthetic-private-material\n-----END PRIVATE KEY-----"
        (self.root / "lib/removed_key.dart").write_bytes(private)
        subprocess.run(["git", "add", "lib/removed_key.dart"], cwd=self.root, check=True)
        subprocess.run(["git", "commit", "-qm", "synthetic credential fixture"], cwd=self.root, check=True)
        (self.root / "lib/removed_key.dart").unlink()
        (self.root / "lib/main.dart").write_bytes(private)
        (self.root / "lib/helper.dart").write_text("const safe = true;\n")
        (self.root / "lib/credentials.dart").write_text("const privateSetting = 'fixture';\n")
        (self.root / "lib/ignored.dart").write_bytes(private)
        with (self.root / ".gitignore").open("a") as stream:
            stream.write("lib/ignored.dart\n")
        (self.root / "lib/config.dart").write_text("const arbitraryConfig = 'do-not-copy';\n")
        with tempfile.TemporaryDirectory() as external:
            outside = Path(external) / "outside.dart"
            outside.write_bytes(private)
            (self.root / "lib/link.dart").symlink_to(outside)
            capture = provenance.begin(self.root, ["--dart-define-from-file=lib/config.dart"])
            record = json.loads((capture / "provenance.json").read_text())
            snapshot = record["sourceSnapshots"]["before"]
            self.assertEqual(snapshot["untrackedFiles"], ["lib/helper.dart"])
            self.assertEqual(snapshot["trackedChanges"], [])
            self.assertIn("credential-shaped content", snapshot["excluded"]["lib/main.dart"])
            self.assertIn("credential-shaped content", snapshot["excluded"]["lib/removed_key.dart"])
            self.assertIn("symlink", snapshot["excluded"]["lib/link.dart"])
            self.assertIn("lib/config.dart", snapshot["excluded"])
            self.assertNotIn("lib/ignored.dart", snapshot["untrackedFiles"])
            self.assertNotIn(str(outside), json.dumps(record))
            self.assertNotIn("synthetic-private-material", json.dumps(record))
            self.assertEqual((capture / snapshot["patch"]["path"]).read_bytes(), b"")
            with tarfile.open(capture / snapshot["untrackedArchive"]["path"]) as tar:
                self.assertEqual(tar.getnames(), ["lib/helper.dart"])
                self.assertNotIn(private, tar.extractfile("lib/helper.dart").read())

    def test_changed_source_during_capture_is_rejected_without_claiming_a_snapshot(self):
        (self.root / "lib/main.dart").write_text("const first = 1;\n")
        original = provenance.source_identity
        calls = 0

        def mutate_after_identity(root, extra_files):
            nonlocal calls
            calls += 1
            if calls == 2:
                (root / "lib/main.dart").write_text("const second = 2;\n")
            return original(root, extra_files)

        with mock.patch.object(provenance, "source_identity", side_effect=mutate_after_identity):
            with self.assertRaisesRegex(ValueError, "Source changed while capturing"):
                provenance.begin(self.root, [])
        captures = list((self.root / "build/releases").iterdir())
        self.assertEqual(len(captures), 1)
        self.assertFalse((captures[0] / "provenance.json").exists())
        self.assertFalse((captures[0] / "source-before.patch").exists())
        self.assertFalse((captures[0] / "source-before-untracked.tar.gz").exists())

    def test_capture_started_without_byte_retention_still_retains_products_and_marks_gap(self):
        (self.root / "lib/main.dart").write_text("const source = 'legacy capture';\n")
        capture = provenance.begin(self.root, [])
        metadata = json.loads((capture / "provenance.json").read_text())
        del metadata["sourceSnapshots"]
        (capture / "source-before.patch").unlink()
        (capture / "source-before-untracked.tar.gz").unlink()
        (capture / "provenance.json").write_text(json.dumps(metadata))
        archive, ipa = self.products(capture)
        destination = provenance.retain(self.root, capture, archive, ipa)
        record = json.loads((destination / "provenance.json").read_text())
        self.assertEqual(record["status"], "retained")
        self.assertIn("sourceBeforeBytesUnavailable", record)
        self.assertNotIn("before", record["sourceSnapshots"])
        self.assertIn(b"legacy capture", (destination / "source-after.patch").read_bytes())

    def test_ignored_define_files_are_hashed_without_recording_values(self):
        (self.root / "build").mkdir()
        secret = self.root / "build/defines.json"
        secret.write_text('{"TOKEN":"do-not-persist"}')
        capture = provenance.begin(self.root, ["--dart-define-from-file", str(secret)])
        record = json.loads((capture / "provenance.json").read_text())
        self.assertEqual(record["before"]["files"]["build/defines.json"], provenance.sha256(secret))
        self.assertNotIn("do-not-persist", json.dumps(record))
        self.assertNotIn(str(self.root), json.dumps(record))

    def test_rejects_stale_archive_without_retaining_wrong_build(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        os.utime(archive / "Info.plist", ns=(1, 1))
        with self.assertRaisesRegex(ValueError, "predates"):
            provenance.retain(self.root, capture, archive, ipa)
        self.assertFalse((capture / "Runner.xcarchive").exists())

    def test_rejects_same_version_with_different_ipa_binary_uuid(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        (archive / "Products/Applications/Runner.app/Runner").write_text("OTHER-BUILD")
        with self.assertRaisesRegex(ValueError, "UUID mismatch"):
            provenance.retain(self.root, capture, archive, ipa)
        self.assertEqual(json.loads((capture / "provenance.json").read_text())["status"], "build_pending")

    def test_rejects_stale_ipa_even_when_uuid_matches_new_archive(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        os.utime(ipa, ns=(1, 1))
        with self.assertRaisesRegex(ValueError, "IPA predates"):
            provenance.retain(self.root, capture, archive, ipa)
        self.assertFalse((capture / "Runner.xcarchive").exists())

    def test_rejects_mismatched_dsym_instead_of_certifying_symbols(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        (archive / "dSYMs/Runner.app.dSYM/Contents/Resources/DWARF/Runner").write_text("OTHER-SYMBOLS")
        with self.assertRaisesRegex(ValueError, "mismatched dSYM"):
            provenance.retain(self.root, capture, archive, ipa)

    def test_independent_attempts_reserve_unique_directories(self):
        first = provenance.begin(self.root, [])
        second = provenance.begin(self.root, [])
        self.assertNotEqual(first, second)
        self.assertTrue((first / "provenance.json").exists())
        self.assertTrue((second / "provenance.json").exists())

    def test_external_define_content_is_identified_without_retaining_its_path(self):
        with tempfile.TemporaryDirectory() as external:
            secret = Path(external) / "private.json"
            secret.write_text('{"TOKEN":"external-secret"}')
            arguments = ["--dart-define-from-file=" + str(secret)]
            capture = provenance.begin(self.root, arguments)
            archive, ipa = self.products(capture)
            secret.write_text('{"TOKEN":"changed-secret"}')
            destination = provenance.retain(self.root, capture, archive, ipa, arguments)
            record = json.loads((destination / "provenance.json").read_text())
            self.assertFalse(record["sourceUnchanged"])
            self.assertEqual(record["extraInputFiles"], ["external-input-0"])
            self.assertNotIn(external, json.dumps(record))
            self.assertNotIn("external-secret", json.dumps(record))
            self.assertNotIn("changed-secret", json.dumps(record))

    def test_corrupt_copy_is_rejected(self):
        capture = provenance.begin(self.root, [])
        archive, ipa = self.products(capture)
        original = provenance.shutil.copy2

        def corrupt(source, destination, **kwargs):
            result = original(source, destination, **kwargs)
            Path(destination).write_bytes(b"incomplete-copy")
            return result

        with mock.patch.object(provenance.shutil, "copy2", side_effect=corrupt):
            with self.assertRaisesRegex(ValueError, "changed while being retained"):
                provenance.retain(self.root, capture, archive, ipa)

    def test_shell_entrypoint_preserves_arguments_and_retains_only_after_success(self):
        scripts = self.root / "scripts"
        scripts.mkdir()
        entrypoint = scripts / "build_ios_appstore_ipa.sh"
        entrypoint.write_bytes((Path(__file__).resolve().parents[1] / entrypoint.name).read_bytes())
        (self.root / "ios").mkdir()
        (self.root / "ios/ExportOptions-AppStore.plist").write_bytes(plistlib.dumps({"method": "app-store-connect"}))
        helper = scripts / "ios_build_provenance.py"
        helper.write_text(textwrap.dedent('''\
            import json, pathlib, sys
            root = pathlib.Path(__file__).resolve().parents[1]
            with (root / 'events.jsonl').open('a') as stream:
                stream.write(json.dumps([sys.argv[1], sys.argv[2:]]) + '\\n')
            print('build/releases/fixture')
            '''))
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        flutter = fake_bin / "flutter"
        flutter.write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import json, os, pathlib, sys
            with pathlib.Path('events.jsonl').open('a') as stream:
                stream.write(json.dumps(['flutter', sys.argv[1:]]) + '\\n')
            sys.exit(int(os.environ.get('FIXTURE_BUILD_EXIT', '0')))
            '''))
        flutter.chmod(0o755)
        environment = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
        arguments = ["--build-number", "118", "--dart-define=FIXTURE=value with spaces"]
        for exit_code, stages in ((0, ["begin", "flutter", "retain"]), (17, ["begin", "flutter"])):
            (self.root / "events.jsonl").write_text("")
            result = subprocess.run(["bash", str(entrypoint), *arguments], cwd=self.root,
                                    env={**environment, "FIXTURE_BUILD_EXIT": str(exit_code)},
                                    text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, exit_code, result.stderr)
            events = [json.loads(line) for line in (self.root / "events.jsonl").read_text().splitlines()]
            self.assertEqual([event[0] for event in events], stages)
            actual = events[1][1]
            self.assertEqual(actual[:3], ["build", "ipa", "--release"])
            self.assertIn("--export-options-plist=" + str(self.root / "ios/ExportOptions-AppStore.plist"), actual)
            self.assertIn("--dart-define-from-file=" + str(self.root / "tool/build/voice_call_release_defines.json"), actual)
            self.assertEqual(actual[-len(arguments):], arguments)


if __name__ == "__main__":
    unittest.main()
