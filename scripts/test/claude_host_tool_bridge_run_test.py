"""Bridge job execution must finish when the direct child exits, even if it leaves descendants behind."""

import os
import pathlib
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import claude_host_tool_bridge as bridge

LINGER = (
    "import subprocess, sys\n"
    "subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(8)'])\n"
    "print('done')\n"
    "print('warn', file=sys.stderr)\n"
)


class RunChildTest(unittest.TestCase):
    def setUp(self):
        self.cwd = pathlib.Path(tempfile.mkdtemp())
        self.env = dict(os.environ)

    def test_returns_when_direct_child_exits_despite_lingering_descendant(self):
        started = time.monotonic()
        code, out, err = bridge._run_child([sys.executable, "-c", LINGER], cwd=self.cwd, env=self.env)
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 5, "bridge waited for a descendant that inherited its output")
        self.assertEqual(code, 0)
        self.assertEqual(out, "done\n")
        self.assertEqual(err, "warn\n")

    def test_descendant_that_keeps_writing_cannot_corrupt_the_direct_child_output(self):
        writer = (
            "import subprocess, sys\n"
            "sys.stdout.write('RESULT-' * 200 + 'END\\n'); sys.stdout.flush()\n"
            "subprocess.Popen([sys.executable, '-c', "
            "'import sys, time\\nend = time.time() + 1.5\\nwhile time.time() < end:\\n    sys.stdout.write(\"x\" * 50); sys.stdout.flush()'])\n"
            "import time; time.sleep(0.4)\n"
        )
        code, out, _ = bridge._run_child([sys.executable, "-c", writer], cwd=self.cwd, env=self.env)
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("RESULT-" * 200 + "END\n"), out[:80])
        self.assertNotIn("x", out[: len("RESULT-" * 200)])

    def test_exit_code_and_both_streams_are_kept(self):
        code, out, err = bridge._run_child(
            [sys.executable, "-c", "import sys; print('a'); print('b', file=sys.stderr); sys.exit(3)"],
            cwd=self.cwd, env=self.env)
        self.assertEqual((code, out, err), (3, "a\n", "b\n"))

    def test_undecodable_output_is_replaced_not_fatal(self):
        code, out, _ = bridge._run_child(
            [sys.executable, "-c", "import sys; sys.stdout.buffer.write(b'\\xff ok')"], cwd=self.cwd, env=self.env)
        self.assertEqual(code, 0)
        self.assertTrue(out.endswith(" ok"))

    def test_stdin_is_not_inherited(self):
        code, out, _ = bridge._run_child(
            [sys.executable, "-c", "import sys; print(repr(sys.stdin.read()))"], cwd=self.cwd, env=self.env)
        self.assertEqual((code, out), (0, "''\n"))

    def test_missing_executable_raises_file_not_found(self):
        with self.assertRaises(FileNotFoundError):
            bridge._run_child(["/nonexistent/tool"], cwd=self.cwd, env=self.env)

    def test_failed_second_temp_file_removes_the_first_and_launches_nothing(self):
        import errno
        from unittest import mock
        real = tempfile.NamedTemporaryFile
        made = []

        def named_temp(*args, **kwargs):
            if made:
                raise OSError(errno.EMFILE, "Too many open files")
            handle = real(*args, **kwargs)
            made.append(handle.name)
            return handle

        with mock.patch.object(bridge.tempfile, "NamedTemporaryFile", named_temp), \
                mock.patch.object(bridge.subprocess, "Popen") as popen:
            with self.assertRaises(OSError):
                bridge._run_child([sys.executable, "-c", "pass"], cwd=self.cwd, env=self.env)
        popen.assert_not_called()
        self.assertEqual(len(made), 1)
        self.assertFalse(os.path.exists(made[0]), "first temp file was left on disk")


class OpenFileLimitTest(unittest.TestCase):
    def fake_resource(self, soft, hard, reject=False):
        import types
        calls = []

        def setrlimit(kind, limits):
            if reject:
                raise ValueError("rejected")
            calls.append(limits)

        module = types.SimpleNamespace(RLIMIT_NOFILE=8, RLIM_INFINITY=-1,
                                       getrlimit=lambda kind: (soft, hard), setrlimit=setrlimit)
        return module, calls

    def run_with(self, module):
        from unittest import mock
        with mock.patch.dict(sys.modules, {"resource": module}):
            return bridge._raise_open_file_limit()

    def test_low_soft_limit_is_raised_to_target_under_unlimited_hard(self):
        module, calls = self.fake_resource(256, -1)
        self.assertEqual(self.run_with(module), 10240)
        self.assertEqual(calls, [(10240, -1)])

    def test_raise_is_capped_by_hard_limit(self):
        module, calls = self.fake_resource(256, 4096)
        self.assertEqual(self.run_with(module), 4096)
        self.assertEqual(calls, [(4096, 4096)])

    def test_high_soft_limit_is_left_alone(self):
        module, calls = self.fake_resource(20000, -1)
        self.assertEqual(self.run_with(module), 20000)
        self.assertEqual(calls, [])

    def test_rejected_raise_keeps_current_limit(self):
        module, _ = self.fake_resource(256, -1, reject=True)
        self.assertEqual(self.run_with(module), 256)


if __name__ == "__main__":
    unittest.main()
