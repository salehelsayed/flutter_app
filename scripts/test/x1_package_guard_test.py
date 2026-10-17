"""The X1 supplemental reconnect wrapper must refuse any non-disposable package before touching a device."""

import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
GUARD = ROOT / "docker-ws" / "x1_package_guard.sh"
WRAPPER = ROOT / "docker-ws" / "x1_reconnect_supplemental.sh"
VARS = ("ANDROID_APP_PACKAGE", "SIMS_APP_ID", "ORG_GRADLE_PROJECT_androidApplicationId")


def guard(**overrides):
    env = {"PATH": "/usr/bin:/bin", **{name: "com.mknoon.sims.connectivity" for name in VARS}}
    for name, value in overrides.items():
        if value is None:
            env.pop(name, None)
        else:
            env[name] = value
    return subprocess.run(["bash", str(GUARD)], env=env, capture_output=True, text=True)


class PackageGuardTest(unittest.TestCase):
    def test_disposable_package_in_all_three_vars_passes(self):
        self.assertEqual(guard().returncode, 0)

    def test_production_package_is_refused(self):
        for name in VARS:
            with self.subTest(name):
                result = guard(**{name: "com.mknoon.app"})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("refused", result.stderr)

    def test_missing_or_empty_var_is_refused(self):
        for name in VARS:
            for value in (None, ""):
                with self.subTest(name=name, value=value):
                    self.assertNotEqual(guard(**{name: value}).returncode, 0)

    def test_non_matching_or_mixed_packages_are_refused(self):
        for value in ("com.mknoon.sims.", "com.mknoon.sims.Bad", "com.mknoon.sims.a.b", "com.mknoon.simsx.a", "com.mknoon.sims.x;rm"):
            with self.subTest(value):
                self.assertNotEqual(guard(ANDROID_APP_PACKAGE=value).returncode, 0)
        self.assertNotEqual(guard(SIMS_APP_ID="com.mknoon.sims.other").returncode, 0)

    def test_wrapper_dry_run_prints_package_and_target_classes_without_ids(self):
        result = subprocess.run(
            ["bash", str(WRAPPER), "PHYS123", "emulator-5554", "/tmp/x1-dry", "--dry-run"],
            capture_output=True, text=True, env={"PATH": "/usr/bin:/bin"}, cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("package=com.mknoon.sims.connectivity physical=android-physical emulator=android-emulator relay=compiled-production-defaults", result.stdout)
        for leaked in ("PHYS123", "emulator-5554", "mknoun", "p2p/"):
            self.assertNotIn(leaked, result.stdout)


class DeviceMediaWrapperTest(unittest.TestCase):
    def test_x2_dry_run_uses_the_directmedia_package_and_hides_ids(self):
        result = subprocess.run(
            ["bash", str(ROOT / "docker-ws" / "x2_device_media.sh"), "PHYS123", "emulator-5554", "/tmp/x2-dry", "--dry-run"],
            capture_output=True, text=True, env={"PATH": "/usr/bin:/bin:/sbin:/usr/sbin"}, cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("package=com.mknoon.sims.directmedia physical=android-physical emulator=android-emulator relay=local-fixture", result.stdout)
        for leaked in ("PHYS123", "emulator-5554"):
            self.assertNotIn(leaked, result.stdout)


class DeviceAudioWrapperTest(unittest.TestCase):
    def test_x3_dry_run_uses_the_productionaudio_package_and_hides_ids(self):
        result = subprocess.run(
            ["bash", str(ROOT / "docker-ws" / "x3_device_audio.sh"), "PHYS123", "emulator-5554", "/tmp/x3-dry", "--dry-run"],
            capture_output=True, text=True, env={"PATH": "/usr/bin:/bin:/sbin:/usr/sbin"}, cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("package=com.mknoon.sims.productionaudio physical=android-physical emulator=android-emulator relay=local-fixture turn=local-coturn", result.stdout)
        for leaked in ("PHYS123", "emulator-5554"):
            self.assertNotIn(leaked, result.stdout)


if __name__ == "__main__":
    unittest.main()
