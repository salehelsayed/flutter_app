"""The iOS notification smoke wait loops must see a match that is followed by a lot of later log."""

import pathlib
import re
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SMOKE = ROOT / "scripts" / "run_ios_notification_tap_ui_smoke.sh"


def function_source(name):
    match = re.search(rf"^{name}\(\) {{\n.*?^}}\n", SMOKE.read_text(), re.S | re.M)
    assert match, name
    return match.group(0)


class WaitForAnyPatternAfterLineTest(unittest.TestCase):
    def test_match_followed_by_a_large_log_tail_is_found(self):
        log = pathlib.Path(tempfile.mkdtemp()) / "setup.log"
        lines = ["old line"] * 10 + ['"event":"READY_MARKER"'] + ["later log " + "x" * 200] * 2000
        log.write_text("\n".join(lines) + "\n")
        script = "set -euo pipefail\n" + function_source("wait_for_any_pattern_after_line") + \
            f'wait_for_any_pattern_after_line "{log}" 10 $$ 3 READY_MARKER\n'
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_match_before_the_start_line_is_ignored(self):
        log = pathlib.Path(tempfile.mkdtemp()) / "setup.log"
        log.write_text("READY_MARKER\n" + "later\n" * 5)
        script = "set -euo pipefail\n" + function_source("wait_for_any_pattern_after_line") + \
            f'wait_for_any_pattern_after_line "{log}" 1 $$ 2 READY_MARKER\n'
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
