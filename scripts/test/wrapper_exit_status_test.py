"""Repo run wrappers must return their child's real exit status (and X3 must fail on leftover owned cleanup)."""

import os
import pathlib
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
WS = ROOT / "docker-ws"


class FakeTools:
    def __init__(self):
        self.dir = pathlib.Path(tempfile.mkdtemp())
        self.report = pathlib.Path(tempfile.mkdtemp()) / "report"

    def tool(self, name, body):
        path = self.dir / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run(self, script, *args):
        env = {"PATH": f"{self.dir}:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": str(self.dir)}
        return subprocess.run(["bash", str(WS / script), *args], capture_output=True, text=True, env=env, cwd=str(ROOT))


def mac_tools(fake, dart_exit=0, leftover_containers=""):
    fake.tool("dart", f"exit {dart_exit}")
    fake.tool("ipconfig", "echo 192.168.1.10")
    fake.tool("go", "exit 0")
    fake.tool("docker", f'''case "$1" in
  info|pull) exit 0;;
  image) exit 0;;
  ps) printf "%s" "{leftover_containers}";;
esac''')


class WrapperExitStatusTest(unittest.TestCase):
    def test_x1_returns_the_dart_exit_code(self):
        fake = FakeTools()
        mac_tools(fake, dart_exit=7)
        result = fake.run("x1_reconnect_supplemental.sh", "PHYS", "emulator-5554", str(fake.report))
        self.assertEqual(result.returncode, 7)

    def test_x1_success_is_zero(self):
        fake = FakeTools()
        mac_tools(fake, dart_exit=0)
        self.assertEqual(fake.run("x1_reconnect_supplemental.sh", "PHYS", "emulator-5554", str(fake.report)).returncode, 0)

    def test_x2_returns_the_adapter_exit_code(self):
        fake = FakeTools()
        mac_tools(fake, dart_exit=5)
        self.assertEqual(fake.run("x2_device_media.sh", "PHYS", "emulator-5554", str(fake.report)).returncode, 5)

    def test_x3_returns_the_adapter_exit_code(self):
        fake = FakeTools()
        mac_tools(fake, dart_exit=4)
        self.assertEqual(fake.run("x3_device_audio.sh", "PHYS", "emulator-5554", str(fake.report)).returncode, 4)

    def test_x3_fails_when_an_owned_container_is_left(self):
        fake = FakeTools()
        mac_tools(fake, dart_exit=0, leftover_containers="abc123")
        # The pre-flight refuses a leftover before the run, so model a leftover that appears only afterwards.
        fake.tool("docker", '''case "$1" in
  info|image) exit 0;;
  ps) [ -f "$HOME/after" ] && printf "abc123\\n";;
esac''')
        fake.tool("dart", 'touch "$HOME/after"; exit 0')
        result = fake.run("x3_device_audio.sh", "PHYS", "emulator-5554", str(fake.report))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("containers: 1", (fake.report / "cleanup.txt").read_text())

    def test_debug_build_returns_the_flutter_exit_code(self):
        fake = FakeTools()
        fake.tool("flutter", "exit 9")
        log = fake.report.parent / "build.log"
        self.assertEqual(fake.run("build_android_calls_debug.sh", str(log)).returncode, 9)

    def test_h04_debug_returns_the_flutter_exit_code(self):
        fake = FakeTools()
        fake.tool("flutter", "exit 6")
        log = fake.report.parent / "h04.log"
        self.assertEqual(fake.run("h04_ios_sqlcipher_debug.sh", "SIM", str(log)).returncode, 6)

    def test_x4_returns_the_smoke_script_exit_code_and_refuses_bad_scenarios(self):
        fake = FakeTools()
        result = fake.run("x4_ios_notification_sim.sh", "SIMUDID", "bogus:pair", "testNotificationTap", str(fake.report))
        self.assertEqual(result.returncode, 2)
        smoke = fake.dir / "smoke.sh"
        smoke.write_text("#!/bin/bash\nexit 8\n")
        fake.tool("bash-smoke-marker", "true")
        env_result = subprocess.run(
            ["bash", str(WS / "x4_ios_notification_sim.sh"), "SIMUDID", "warm:direct_text", "testNotificationTap",
             str(fake.report)],
            capture_output=True, text=True, cwd=str(ROOT),
            env={"PATH": f"{fake.dir}:/usr/bin:/bin", "X4_SMOKE_SCRIPT": str(smoke)},
        )
        self.assertEqual(env_result.returncode, 8)

    def test_devicectl_probe_returns_the_xcrun_exit_code(self):
        fake = FakeTools()
        fake.tool("xcrun", "exit 3")
        out = fake.report.parent / "probe.txt"
        self.assertEqual(fake.run("devicectl_list_probe.sh", str(out)).returncode, 3)


if __name__ == "__main__":
    unittest.main()
