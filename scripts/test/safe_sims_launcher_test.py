"""Host-only launcher counterexamples: no real device, provider, relay or SSH."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
import uuid

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("safe_sims_launcher", ROOT / "docker-ws/run_sims_safe.py")
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class SafeLauncherTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="safe-launcher-contract-")
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name).resolve()
        (self.repo / "docker-ws").mkdir()
        (self.repo / "tool/sims").mkdir(parents=True)
        self.manifest = json.loads((ROOT / "tool/sims/critical_features.json").read_text())
        self.save_manifest()
        (self.repo / ".gitignore").write_text("/build/\n/docker-ws/local_devices.env\n")
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True, capture_output=True)
        (self.repo / "build").mkdir()
        relay = self.repo / "build/test-relay.txt"
        relay.write_text("/ip4/127.0.0.1/tcp/4001/ws\n")
        sdk = self.repo / "sdk"
        (sdk / "bin").mkdir(parents=True)
        dart = sdk / "bin/dart"
        dart.write_text("#!" + sys.executable + "\n" + """
import json,os,pathlib,subprocess,sys
data = {
 'argv': sys.argv[1:],
 'pins': json.loads(os.environ['SIMS_PROTECTED_DEVICE_ASSIGNMENTS_JSON']),
 'environment_names': sorted(os.environ),
 'workers': {k:os.environ.get(k) for k in ['SIMS_MAX_PARALLEL','SIMS_HOST_CONCURRENCY','MKNOON_HOST_FLUTTER_WORKERS']},
 'ssh_exit': subprocess.call(['ssh','-V'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL),
}
pathlib.Path(os.environ['SIMS_REPORT_PATH']).write_text(json.dumps(data))
print('private-child-marker')
""")
        dart.chmod(0o700)
        self.env = {
            **{k: os.environ[k] for k in ("HOME", "PATH", "USER", "TMPDIR") if k in os.environ},
            "MKNOON_FLUTTER_SDK": str(sdk),
            "SIMS_ANDROID_EMULATOR_DEVICE_ID": "emulator-" + str(uuid.uuid4().int % 100000),
            "KAYAN_TEST_RELAY_FILE": str(relay),
        }
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(launcher, "REPO", self.repo).start()
        mock.patch.dict(os.environ, self.env, clear=True).start()
        mock.patch.object(launcher, "host_gate", return_value={"passed": True}).start()
        self.prepared = mock.patch.object(
            launcher, "prepared_devices", side_effect=lambda *args: contextlib.nullcontext()
        ).start()

    def save_manifest(self):
        (self.repo / "tool/sims/critical_features.json").write_text(json.dumps(self.manifest))

    def invoke(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            code = launcher.main(args)
        return code, output.getvalue()

    def native(self):
        return json.loads((self.repo / "build/kayan-safe/native-report.json").read_text())

    def test_rebinding_changes_only_explicit_audited_device_metadata(self):
        rebound = launcher.disposable_manifest(self.manifest)
        original = {r["id"]: r for r in self.manifest["capabilities"]}
        changed = []
        for row in rebound["capabilities"]:
            before = original[row["id"]]
            if row != before:
                changed.append(row["id"])
                self.assertIn("android.emulator.rebindable", before["targetCapabilities"])
                self.assertNotIn("android.physical", row["targetCapabilities"])
                self.assertTrue(any(r["name"].split(":")[-1] == "android-emulator-fourth"
                                    for r in row["resources"]))
                for field in set(before) - {"resources", "targetCapabilities", "artifactValidator", "assertions"}:
                    self.assertEqual(row[field], before[field], (row["id"], field))
        self.assertEqual(len(changed), 64)
        self.assertEqual(rebound["buildProfiles"], self.manifest["buildProfiles"])
        self.assertEqual(launcher.disposable_manifest(rebound), rebound)

    def test_generated_manifest_and_rebinding_flag_replace_ambient_inputs(self):
        os.environ["SIMS_MANIFEST"] = "forbidden-ambient-manifest"
        self.invoke("major")
        generated = self.repo / "build/kayan-safe/manifest.json"
        rows = {r["id"]: r for r in json.loads(generated.read_text())["capabilities"]}
        self.assertNotIn("android.physical", rows["production.routing_smoke"]["targetCapabilities"])
        self.assertNotIn("android.physical", rows["android.production_1to1_audio_call"]["targetCapabilities"])
        self.assertEqual(rows["android.production_1to1_audio_call"]["artifactValidator"], "validateAndroidProductionAudioCallEmulatorArtifact")
        self.assertEqual(generated.stat().st_mode & 0o777, 0o600)
        self.assertIn("SIMS_DISPOSABLE_ANDROID_JOURNEYS", self.native()["environment_names"])

    def test_list_needs_no_targets_relay_credentials_or_dart(self):
        (self.repo / "docker-ws/local_devices.env").write_text("SIMS_IOS_SIMULATOR_ID='unterminated\n")
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(
            launcher, "run_child", side_effect=AssertionError("child launched")
        ):
            code, output = self.invoke("major", "--list")
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(output)["rows"])
        self.assertFalse((self.repo / "build/kayan-safe").exists())

    def test_credential_cases_and_companion_provider_builds_are_blocked(self):
        _, output = self.invoke("major", "--list")
        rows = {r["id"]: r for r in json.loads(output)["rows"]}
        for key in ("notifications.android_recovery_completion",
                    "production.notification_open", "production.notification_sound",
                    "build.android.production_fcm"):
            self.assertEqual(rows[key]["blocker"], "credentials", key)

    def test_phone_proofs_do_not_turn_into_emulator_proofs(self):
        for mode in ("notification-recovery",):
            with self.subTest(mode=mode), mock.patch.object(
                launcher, "run_child", side_effect=AssertionError("phone campaign launched")
            ):
                code, output = self.invoke(mode)
            self.assertEqual(code, 78)
            self.assertIn("BLOCKED", output)

    def test_fixture_modes_delegate_existing_controllers_with_two_emulator_pins(self):
        os.environ.update({"SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID": "emulator-4004",
                           "PLAN399_FIXTURE_HOST_IP": "127.0.0.1",
                           "PLAN347_FIXTURE_HOST_IP": "127.0.0.1"})
        for mode, adapter in (("device-audio", "run_production_audio_call_sims.dart"),
                              ("device-media", "run_direct_media_blob_custody_sims.dart")):
            with self.subTest(mode=mode):
                code, output = self.invoke(mode)
                self.assertEqual(code, 0)
                args = self.native()["argv"]
                self.assertIn("integration_test/scripts/" + adapter, args)
                self.assertNotIn("--exclude", args)
                self.assertNotIn("--prepare-builds", args)
                self.assertNotIn("127.0.0.1", output)
        _, output = self.invoke("major", "--list")
        rows = {r["id"]: r for r in json.loads(output)["rows"]}
        self.assertEqual(rows["android.production_1to1_audio_call"]["blocker"], "local_fixture_mode_required")
        self.assertEqual(rows["android.direct_media_blob_custody"]["blocker"], "local_fixture_mode_required")

    def test_fixture_mode_refuses_missing_pair_or_explicit_interface(self):
        for values in ({}, {"SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID": "emulator-4004"}):
            with mock.patch.dict(os.environ, values), mock.patch.object(
                launcher, "run_child", side_effect=AssertionError("fixture unexpectedly launched")
            ):
                with self.assertRaises(ValueError):
                    self.invoke("device-audio")

    def test_explicit_target_beats_local_file(self):
        (self.repo / "docker-ws/local_devices.env").write_text(
            "SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-" + str(uuid.uuid4().int % 100000) + "\n"
        )
        self.invoke("major")
        self.assertEqual(self.native()["pins"], {
            "android-emulator": self.env["SIMS_ANDROID_EMULATOR_DEVICE_ID"]
        })

    def test_explicit_empty_does_not_fall_back_to_file(self):
        (self.repo / "docker-ws/local_devices.env").write_text(
            "SIMS_ANDROID_EMULATOR_DEVICE_ID=emulator-" + str(uuid.uuid4().int % 100000) + "\n"
        )
        os.environ["SIMS_ANDROID_EMULATOR_DEVICE_ID"] = ""
        with self.assertRaises(ValueError), mock.patch.object(
            launcher, "run_child", side_effect=AssertionError("fallback target launched")
        ):
            self.invoke("major")

    def test_invalid_target_is_refused_before_child(self):
        os.environ["SIMS_ANDROID_EMULATOR_DEVICE_ID"] = "all"
        with self.assertRaises(ValueError), mock.patch.object(
            launcher, "run_child", side_effect=AssertionError("invalid target launched")
        ):
            self.invoke("major")

    def test_unignored_relay_file_is_refused(self):
        path = self.repo / "relay.txt"
        path.write_text("/ip4/127.0.0.1/tcp/4001/ws")
        os.environ["KAYAN_TEST_RELAY_FILE"] = str(path)
        with self.assertRaises(ValueError):
            self.invoke("major")
        self.assertFalse((self.repo / "build/kayan-safe/native-report.json").exists())

    def test_no_credentials_phone_defaults_or_child_output_leak(self):
        forbidden = ("FIREBASE_SERVICE_ACCOUNT", "SSH_AUTH_SOCK",
                     "SIMS_IOS_APNS_AUTH_KEY_PATH", "SIMS_ANDROID_PHYSICAL_DEVICE_ID",
                     "SIMS_ARTIFACT_ANDROID_E2E_MAIN")
        os.environ.update({key: "private-input-marker" for key in forbidden})
        code, output = self.invoke("major")
        data = self.native()
        self.assertEqual(code, 78)  # Filtered major cannot claim full acceptance.
        self.assertFalse(set(forbidden) & set(data["environment_names"]))
        self.assertEqual(data["ssh_exit"], 78)
        self.assertEqual(set(data["workers"].values()), {"1"})
        self.prepared.assert_called_once()
        self.assertNotIn("private-child-marker", output)
        self.assertNotIn("private-input-marker", output)
        self.assertNotIn(self.env["SIMS_ANDROID_EMULATOR_DEVICE_ID"], output)
        self.assertNotIn("127.0.0.1", output)

    def test_physical_rows_and_unused_provider_builds_are_excluded(self):
        self.invoke("major")
        args = self.native()["argv"]
        excluded = {args[i + 1] for i, a in enumerate(args) if a == "--exclude"}
        self.assertIn("android.production_1to1_audio_call", excluded)
        self.assertNotIn("production.routing_smoke", excluded)
        self.assertIn("build.android.production_fcm", excluded)
        self.assertNotIn("production.group_catalog.private_partition_readd_heal", excluded)

    def test_native_output_symlink_cannot_overwrite_source(self):
        directory = self.repo / "build/kayan-safe"
        directory.mkdir()
        source = self.repo / "sentinel.txt"
        source.write_text("preserve")
        (directory / "native-report.json").symlink_to(source)
        with self.assertRaises(ValueError):
            self.invoke("major")
        self.assertEqual(source.read_text(), "preserve")

    def test_ignored_output_outside_own_directory_is_refused(self):
        with self.assertRaises(ValueError):
            self.invoke("major", "--output", "build/tool-cache")
        self.assertFalse((self.repo / "build/tool-cache").exists())

    def test_tracked_file_in_ignored_directory_cannot_be_overwritten(self):
        directory = self.repo / "build/kayan-safe"
        directory.mkdir()
        path = directory / "native-report.json"
        path.write_text("preserve")
        subprocess.run(["git", "-C", str(self.repo), "add", "-f", str(path)],
                       check=True, capture_output=True)
        with self.assertRaises(ValueError):
            self.invoke("major")
        self.assertEqual(path.read_text(), "preserve")

    def test_host_pressure_blocks_before_campaign(self):
        with mock.patch.object(launcher, "host_gate", return_value={"passed": False}):
            code, output = self.invoke("major")
        self.assertEqual(code, 78)
        self.assertIn("host disk", output)
        self.assertFalse((self.repo / "build/kayan-safe/native-report.json").exists())

    def test_simulator_alias_is_explicit_and_empty_primary_does_not_fall_back(self):
        target = str(uuid.uuid4())
        self.assertEqual(launcher.pins({"SIMS_IOS_SIMULATOR_ID": target}),
                         {"ios-simulator-a": target})
        with self.assertRaises(ValueError):
            launcher.pins({"SIMS_IOS_SIMULATOR_ID": target,
                           "SIMS_IOS_SIMULATOR_A_DEVICE_ID": ""})

    def test_signal_exit_is_not_reported_as_success(self):
        with mock.patch.object(launcher, "run_child", return_value=(-15, 0)):
            code, output = self.invoke("major")
        self.assertEqual(code, 143)
        self.assertIn("FAIL", output)

    def test_log_cap_rotation_and_first_failure_are_bounded(self):
        directory = self.repo / "build/kayan-safe"
        directory.mkdir()
        with mock.patch.object(launcher, "LOG_LIMIT", 32):
            code, dropped = launcher.run_child(
                [sys.executable, "-c", "print('x'*4096);raise SystemExit(17)"],
                dict(os.environ), directory,
            )
            self.assertEqual(code, 17)
            self.assertGreater(dropped, 4000)
            first = (directory / "first-failure.log").read_bytes()
            for _ in range(2):
                launcher.run_child([sys.executable, "-c", "print('y'*4096)"],
                                   dict(os.environ), directory)
        self.assertEqual((directory / "first-failure.log").read_bytes(), first)
        for name in ("launcher.log", "launcher.previous.log", "first-failure.log"):
            self.assertLessEqual((directory / name).stat().st_size, 32)

    def test_bad_cli_argument_does_not_echo_its_value(self):
        with self.assertRaises(ValueError), contextlib.redirect_stderr(io.StringIO()) as error:
            self.invoke("private-argument-marker")
        self.assertNotIn("private-argument-marker", error.getvalue())


class HostGateTest(unittest.TestCase):
    def test_swapout_growth_blocks_even_with_free_memory_and_low_load(self):
        observations = [
            "System-wide memory free percentage: 60%", "Swapouts: 4.", "{ 3.0 2.0 1.0 }",
            "System-wide memory free percentage: 60%", "Swapouts: 5.", "{ 3.0 2.0 1.0 }",
        ]
        with mock.patch.object(launcher.subprocess, "check_output", side_effect=observations), \
             mock.patch.object(launcher.time, "sleep"), \
             mock.patch.object(launcher.shutil, "disk_usage", return_value=SimpleNamespace(free=40 * 1024**3)):
            self.assertFalse(launcher.host_gate()["passed"])

    def test_unavailable_pressure_observation_fails_closed(self):
        with mock.patch.object(launcher.subprocess, "check_output", return_value=""):
            with self.assertRaises(ValueError):
                launcher.host_gate()


class PreparedDevicesTest(unittest.TestCase):
    def exercise(self, status="PASS", busy=False):
        events = []
        class Busy(RuntimeError):
            pass
        @contextlib.contextmanager
        def lease(targets):
            events.append("lease")
            if busy:
                raise Busy("private-target-marker")
            try:
                yield
            finally:
                events.append("release")
        def observe(check, root, config, launch, env):
            events.append("preflight")
            self.assertEqual(check["device_roles"], ["ios_simulator"])
            self.assertEqual(set(config["devices"]), {"ios_simulator"})
            return {"status": status, "observations": []}
        modules = {
            "device_campaign_preflight": SimpleNamespace(
                device_leases=lease, run=observe, DeviceLeaseBusy=Busy),
            "mknoon_checks": SimpleNamespace(launch=object()),
        }
        with mock.patch.dict(sys.modules, modules), \
             mock.patch.object(sys, "path", list(sys.path)), \
             mock.patch.object(launcher, "write_json"):
            try:
                with launcher.prepared_devices(
                    {"ios-simulator-a": str(uuid.uuid4())}, {}, Path("/unused")
                ):
                    events.append("body")
            except ValueError as error:
                self.assertNotIn("private-target-marker", str(error))
                events.append("blocked")
        return events

    def test_setup_is_inside_the_existing_lease(self):
        self.assertEqual(self.exercise(), ["lease", "preflight", "body", "release"])

    def test_blocked_setup_releases_lease_without_running_campaign(self):
        self.assertEqual(self.exercise(status="BLOCKED"),
                         ["lease", "preflight", "release", "blocked"])

    def test_foreign_lease_blocks_without_exposing_target(self):
        self.assertEqual(self.exercise(busy=True), ["lease", "blocked"])


if __name__ == "__main__":
    unittest.main()
