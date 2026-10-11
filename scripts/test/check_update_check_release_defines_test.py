"""Contracts for the SE-41 release guard. Offline; does not build anything."""

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import check_update_check_release_defines as guard

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "check_update_check_release_defines.py"
ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_DEFINES = ROOT / "tool/build/voice_call_release_defines.json"


def run(args, env=None):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=env or {},
    )


class ReleaseGuardTest(unittest.TestCase):
    def test_real_release_defines_pass(self):
        result = run(["--release", f"--dart-define-from-file={RELEASE_DEFINES}"])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_dart_define_off_fails(self):
        for args in (
            ["--dart-define=MKNOON_UPDATE_CHECK=off"],
            ["--dart-define", "MKNOON_UPDATE_CHECK=OFF"],
        ):
            result = run(["--release", *args])
            self.assertEqual(result.returncode, 1, args)
            self.assertIn("RELEASE GUARD FAILED: MKNOON_UPDATE_CHECK=", result.stderr)

    def test_dart_define_on_passes(self):
        result = run(["--dart-define=MKNOON_UPDATE_CHECK=on"])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_define_file_off_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            json_file = pathlib.Path(tmp) / "defines.json"
            json_file.write_text(json.dumps({"MKNOON_UPDATE_CHECK": "off"}))
            env_file = pathlib.Path(tmp) / "defines.env"
            env_file.write_text("MKNOON_UPDATE_CHECK=off\n")
            for path in (json_file, env_file):
                self.assertEqual(run([f"--dart-define-from-file={path}"]).returncode, 1)
                self.assertEqual(run(["--dart-define-from-file", str(path)]).returncode, 1)

    def test_missing_define_file_fails_closed(self):
        result = run(["--dart-define-from-file=/nonexistent/defines.json"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("cannot read a define file", result.stderr)

    def test_environment_off_fails(self):
        result = run([], env={"MKNOON_UPDATE_CHECK": "off"})
        self.assertEqual(result.returncode, 1)

    def test_release_scripts_call_the_guard(self):
        for script in (
            "scripts/build_ios_appstore_ipa.sh",
            "docker-ws/build_store_release.sh",
            "docker-ws/build_play_aab.sh",
        ):
            text = (ROOT / script).read_text(encoding="utf-8")
            self.assertIn("check_update_check_release_defines.py", text, script)

    def test_values_lists_every_source(self):
        values = guard.update_check_values(
            ["--dart-define=MKNOON_UPDATE_CHECK=on", "--dart-define=OTHER=off"],
            {},
        )
        self.assertEqual(values, [("--dart-define", "on")])


if __name__ == "__main__":
    unittest.main()
