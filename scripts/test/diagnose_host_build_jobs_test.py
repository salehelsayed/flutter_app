"""Contracts for the read-only host build-job diagnostic. Offline: every ps/lsof call is faked."""

import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import claude_host_tool_bridge as bridge
import diagnose_host_build_jobs as diag

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "diagnose_host_build_jobs.py"
ROOT = "/Volumes/CrucialX9/flutter_app"

PS = (
    "  100     1 Wed Oct 14 16:00:00 2026    20:00:00 Ss   /usr/bin/python3\n"
    "  200   100 Wed Oct 14 16:47:55 2026    19:00:00 S    /bin/bash\n"
    "  210   200 Wed Oct 14 16:48:00 2026    18:59:00 S    /Users/secret/fvm/bin/cache/dart-sdk/bin/dart\n"
    "  300   100 Thu Oct 15 01:11:05 2026    11:00:00 S    /Users/secret/flutter/bin/cache/dart-sdk/bin/dart\n"
    "  310   300 Thu Oct 15 01:12:00 2026    10:59:00 S    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild\n"
    "  400     1 Wed Oct 14 09:00:00 2026  1-02:00:00 Ss   /bin/zsh\n"
)
DEFAULT_CWDS = {200: ROOT, 300: ROOT}


def cwd_out(pid, path):
    return f"p{pid}\nfcwd\nn{path}\n".encode()


def fd_out(pid, entries):
    lines = [f"p{pid}"]
    for fd, access, kind, name in entries:
        lines += [f"f{fd}", f"a{access}", f"t{kind}", f"n{name}"]
    return ("\n".join(lines) + "\n").encode()


class FakeRunner:
    def __init__(self, ps=PS, cwds=None, fds=None, ps_second=None, fail=None, raw=None):
        self.calls = []
        self.ps = [ps.encode(), (ps_second if ps_second is not None else ps).encode()]
        self.cwds = DEFAULT_CWDS if cwds is None else cwds
        self.fds = {} if fds is None else fds
        self.fail = {} if fail is None else fail
        self.raw = {} if raw is None else raw

    def __call__(self, vector, timeout):
        self.calls.append((list(vector), timeout))
        kind = diag.classify_vector(vector)
        if kind in self.fail:
            outcome = self.fail[kind]
            if isinstance(outcome, BaseException):
                raise outcome
            return outcome
        if kind == "ps":
            count = len([c for c in self.calls if c[0][0] == "/bin/ps"])
            return 0, self.ps[min(count - 1, 1)]
        pid = int(vector[4])
        if (kind, pid) in self.raw:
            return 0, self.raw[(kind, pid)]
        if kind == "cwd":
            return 0, cwd_out(pid, self.cwds.get(pid, "/Users/secret/elsewhere"))
        return 0, fd_out(pid, self.fds.get(pid, []))


class FakePopen:
    """A real pipe stands in for the query child's stdout."""
    instances = []

    def __init__(self, vector, payload=b"", close=True, code=0, **kwargs):
        self.vector, self.kwargs, self.code, self.killed = vector, kwargs, code, 0
        read_end, write_end = os.pipe()
        self._write_end = None if close else write_end
        if close:
            # Pipe capacity differs by OS (macOS is small), so feed it from a thread.
            threading.Thread(target=self._feed, args=(write_end, payload), daemon=True).start()
        self.stdout = os.fdopen(read_end, "rb", buffering=0)
        FakePopen.instances.append(self)

    @staticmethod
    def _feed(write_end, payload):
        try:
            view = memoryview(payload)
            while view:
                view = view[os.write(write_end, view):]
        except OSError:
            pass
        finally:
            os.close(write_end)

    def poll(self):
        return None if self._write_end is not None and not self.killed else self.code

    def kill(self):
        self.killed += 1
        if self._write_end is not None:
            os.close(self._write_end)
            self._write_end = None

    def wait(self, timeout=None):
        return self.code


def render(result):
    return json.dumps(result, sort_keys=True)


def procs(result):
    return {p["pid"]: p for p in result["observed_processes"]}


class ArgumentContractTest(unittest.TestCase):
    def test_any_argument_is_rejected_before_spawning(self):
        with mock.patch.object(subprocess, "run") as run, mock.patch.object(subprocess, "Popen") as popen:
            out = []
            code = diag.main(["--pid", "1"], write=out.append)
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(out[0])["status"], "REJECTED")
        run.assert_not_called()
        popen.assert_not_called()

    def test_script_is_executable_with_absolute_system_interpreter(self):
        self.assertTrue(os.stat(SCRIPT).st_mode & stat.S_IXUSR)
        self.assertEqual(SCRIPT.read_text().splitlines()[0], "#!/usr/bin/python3")


class CommandVectorTest(unittest.TestCase):
    def test_vector_shapes_are_exact(self):
        self.assertEqual(diag.PS_VECTOR, ["/bin/ps", "-axo", "pid=,ppid=,lstart=,etime=,stat=,comm="])
        self.assertEqual(diag.cwd_vector(42), ["/usr/sbin/lsof", "-nP", "-a", "-p", "42", "-d", "cwd", "-Fn"])
        self.assertEqual(diag.fd_vector(42), ["/usr/sbin/lsof", "-nP", "-a", "-p", "42", "-F", "pftan"])
        for bad in (0, -1, True, "42", 4.2):
            with self.assertRaises(ValueError):
                diag.cwd_vector(bad)
        self.assertIsNone(diag.classify_vector(["/bin/ps", "-ef"]))
        self.assertIsNone(diag.classify_vector(["/usr/sbin/lsof", "-p", "42"]))
        with self.assertRaises(ValueError):
            diag.run_query(["/bin/sh", "-c", "true"], 1)

    def test_every_spawn_is_fixed_vector_without_shell_and_stderr_discarded(self):
        fake = FakeRunner()
        FakePopen.instances = []

        def spawn(vector, **kwargs):
            code, data = fake(vector, 1)
            return FakePopen(vector, payload=data, code=code, **kwargs)

        with mock.patch.object(subprocess, "Popen", side_effect=spawn):
            diag.diagnose(diag.run_query)
        self.assertTrue(FakePopen.instances)
        for child in FakePopen.instances:
            self.assertIn(diag.classify_vector(child.vector), {"ps", "cwd", "fds"})
            self.assertFalse(child.kwargs["shell"])
            self.assertIs(child.kwargs["stderr"], subprocess.DEVNULL)
            self.assertIs(child.kwargs["stdout"], subprocess.PIPE)
            self.assertEqual(child.kwargs["env"], diag.QUERY_ENV)
            self.assertEqual(child.killed, 0)

    def test_output_collection_stops_at_limit_and_ends_only_the_query_child(self):
        with mock.patch.object(diag, "MAX_OUTPUT_BYTES", 1000), \
                mock.patch.object(subprocess, "Popen", side_effect=lambda v, **k: FakePopen(v, b"x" * 5000, **k)):
            FakePopen.instances = []
            with self.assertRaises(diag.QueryLimit):
                diag.run_query(diag.PS_VECTOR, 5)
        self.assertEqual(FakePopen.instances[0].killed, 0)

    def test_silent_query_times_out_and_only_its_own_child_is_ended(self):
        with mock.patch.object(diag, "QUERY_TIMEOUT_S", 0.2), \
                mock.patch.object(subprocess, "Popen", side_effect=lambda v, **k: FakePopen(v, close=False, **k)):
            FakePopen.instances = []
            with self.assertRaises(diag.QueryLimit):
                diag.run_query(diag.PS_VECTOR, 5)
        self.assertEqual(FakePopen.instances[0].killed, 1)

    def test_query_timeouts_never_exceed_remaining_budget(self):
        fake = FakeRunner()
        ticks = iter([0.0] + [85.0 + i for i in range(100)])
        with mock.patch.object(diag.time, "monotonic", side_effect=lambda: next(ticks)):
            result = diag.diagnose(fake)
        self.assertTrue(all(timeout <= diag.QUERY_TIMEOUT_S for _, timeout in fake.calls))
        self.assertLessEqual(fake.calls[0][1], diag.QUERY_TIMEOUT_S)
        self.assertTrue(any(timeout <= 5.0 for _, timeout in fake.calls))
        self.assertIn("budget_exceeded", result["reasons"])
        self.assertEqual(result["status"], "INCONCLUSIVE")

    def test_source_has_no_signal_network_write_or_environment_reads(self):
        source = SCRIPT.read_text()
        for forbidden in ("os.kill", "killpg", "signal", "socket", "urllib", "http", "os.environ",
                          "getenv", "shell=True", "write_text", "write_bytes", "shutil", "pgrep", "pkill",
                          "start_new_session", "setsid"):
            self.assertNotIn(forbidden, source, forbidden)
        self.assertIsNone(re.search(r"(?<![\w.])open\(", source))


class AttributionTest(unittest.TestCase):
    def test_unique_candidates_are_reported_with_relevant_writers_only(self):
        fake = FakeRunner(fds={
            200: [("1", "w", "PIPE", "->0x1"), ("5", "w", "REG", ROOT + "/build/app/outputs/flutter-apk/app-release.apk")],
            300: [("7", "r", "REG", ROOT + "/build/ios/iphoneos/Runner.app/Info.plist"),
                  ("8", "w", "REG", "/Users/secret/.ssh/id_rsa"),
                  ("9", "w", "REG", ROOT + "/build/application/x"),
                  ("10", "u", "REG", ROOT + "/lib/main.dart")],
            310: [("11", "w", "REG", ROOT + "/build/ios/XCBuildData/build.db")],
        })
        result = diag.diagnose(fake)
        jobs = result["jobs"]
        self.assertEqual(jobs["store_release_build"]["attribution"], "UNIQUE_CANDIDATE")
        self.assertEqual(jobs["store_release_build"]["candidate_pids"], [200])
        self.assertEqual(jobs["ios_profile_build"]["attribution"], "UNIQUE_CANDIDATE")
        self.assertEqual(jobs["ios_profile_build"]["candidate_pids"], [300])
        by_pid = procs(result)
        self.assertEqual(by_pid[200]["build_fds"], [{"root": "build/app", "access": "w",
                                                      "relpath": "outputs/flutter-apk/app-release.apk"}])
        self.assertEqual(by_pid[300]["build_fds"], [{"root": "build/ios", "access": "r",
                                                      "relpath": "iphoneos/Runner.app/Info.plist"}])
        self.assertEqual(by_pid[310]["ancestry"], ["dart", "python3"])
        self.assertEqual(by_pid[200]["parent_kind"], "python")
        text = render(result)
        for leaked in ("/Users", "secret", ".ssh", "id_rsa", "application", "lib/main.dart", "Xcode.app", "/bin/"):
            self.assertNotIn(leaked, text)
        self.assertEqual(result["status"], "INCONCLUSIVE")
        self.assertEqual(result["reasons"], ["no_positive_control"])
        self.assertTrue(result["coverage"]["complete"])

    def test_candidate_found_without_any_bridge_parent_assumption(self):
        ps = PS + "  500     1 Wed Oct 14 16:47:55 2026    19:00:00 S    /bin/bash\n"
        result = diag.diagnose(FakeRunner(ps=ps, cwds={500: ROOT}))
        self.assertEqual(result["jobs"]["store_release_build"]["candidate_pids"], [500])
        self.assertEqual(procs(result)[500]["parent_kind"], "launchd")

    def test_unrelated_python_parent_with_other_cwd_is_not_attributed(self):
        result = diag.diagnose(FakeRunner(cwds={300: ROOT}))
        self.assertEqual(result["jobs"]["store_release_build"]["attribution"], "NONE_OBSERVED")
        self.assertNotIn(200, procs(result))
        self.assertIn("job_not_positively_resolved", result["reasons"])

    def test_repo_subdirectory_is_explicit_uncertainty_without_path(self):
        result = diag.diagnose(FakeRunner(cwds={200: "/Users/secret/project", 300: ROOT + "/ios"}))
        by_pid = procs(result)
        self.assertNotIn(200, by_pid)
        self.assertEqual(by_pid[300]["cwd_class"], "repo_subdir")
        self.assertIn("out_of_scope_repo_cwd", result["reasons"])
        self.assertEqual(result["jobs"]["ios_profile_build"]["attribution"], "NONE_OBSERVED")
        self.assertIn("not proof", result["jobs"]["store_release_build"]["note"])
        self.assertNotIn("secret", render(result))
        self.assertNotIn("/ios", render(result))

    def test_ambiguous_candidates_make_result_inconclusive(self):
        ps = PS + "  220   100 Wed Oct 14 16:50:00 2026    18:57:00 S    /bin/bash\n"
        result = diag.diagnose(FakeRunner(ps=ps, cwds={200: ROOT, 220: ROOT, 300: ROOT}))
        self.assertEqual(result["jobs"]["store_release_build"]["attribution"], "AMBIGUOUS")
        self.assertIn("ambiguous_attribution", result["reasons"])

    def test_no_matches_is_inconclusive_not_an_idle_certificate(self):
        ps = "  400     1 Wed Oct 14 09:00:00 2026  1-02:00:00 Ss   /bin/zsh\n"
        result = diag.diagnose(FakeRunner(ps=ps, cwds={}))
        self.assertEqual(result["jobs"]["ios_profile_build"]["attribution"], "NONE_OBSERVED")
        self.assertEqual(result["observed_processes"], [])
        self.assertEqual(result["status"], "INCONCLUSIVE")
        self.assertIn("job_not_positively_resolved", result["reasons"])
        self.assertIn("not a host-idle certificate", result["limits"]["scope"])

    def test_explicit_empty_cwd_fixture_is_respected(self):
        result = diag.diagnose(FakeRunner(cwds={}))
        self.assertEqual(result["observed_processes"], [])

    def test_pid_reuse_between_snapshots_is_flagged(self):
        second = PS.replace("Thu Oct 15 01:11:05 2026", "Thu Oct 15 09:00:00 2026")
        result = diag.diagnose(FakeRunner(ps_second=second))
        self.assertFalse(procs(result)[300]["revalidated"])
        self.assertIn("process_changed_during_queries", result["reasons"])

    def test_disappearing_process_is_flagged(self):
        second = "\n".join(l for l in PS.splitlines() if not l.strip().startswith("310 ")) + "\n"
        result = diag.diagnose(FakeRunner(ps_second=second))
        self.assertFalse(procs(result)[310]["revalidated"])
        self.assertIn("process_changed_during_queries", result["reasons"])

    def test_descendant_expansion_is_truncated_deterministically(self):
        kids = "".join(f"  {700 + i}   200 Wed Oct 14 16:49:00 2026    18:00:00 S    /usr/bin/make\n" for i in range(5))
        with mock.patch.object(diag, "MAX_FD_QUERIES", 3):
            result = diag.diagnose(FakeRunner(ps=PS + kids))
        self.assertIn("descendant_limit_exceeded", result["reasons"])
        self.assertFalse(result["coverage"]["complete"])
        self.assertEqual(result["coverage"]["fd_targets"], 3)

    def test_build_fd_truncation_adds_uncertainty(self):
        entries = [(str(i), "w", "REG", f"{ROOT}/build/app/f{i}") for i in range(3)]
        with mock.patch.object(diag, "MAX_BUILD_FDS", 1):
            result = diag.diagnose(FakeRunner(fds={200: entries}))
        self.assertTrue(procs(result)[200]["build_fds_truncated"])
        self.assertIn("build_fd_list_truncated", result["reasons"])

    def test_ancestry_clipping_is_explicit(self):
        with mock.patch.object(diag, "MAX_ANCESTRY_DEPTH", 1):
            result = diag.diagnose(FakeRunner())
        self.assertEqual(procs(result)[310]["ancestry"], ["dart"])
        self.assertTrue(procs(result)[310]["ancestry_truncated"])

    def test_unsafe_relative_names_are_omitted(self):
        result = diag.diagnose(FakeRunner(fds={200: [("5", "w", "REG", ROOT + "/build/app/my secret file")]}))
        self.assertEqual(procs(result)[200]["build_fds"][0]["relpath"], "<omitted-unsafe-name>")
        self.assertNotIn("secret", render(result))


class UncertaintyTest(unittest.TestCase):
    def assert_inconclusive(self, result, reason):
        self.assertEqual(result["status"], "INCONCLUSIVE")
        self.assertIn(reason, result["reasons"])
        self.assertNotIn("Traceback", render(result))
        self.assertNotIn("secret", render(result))

    def test_malformed_ps(self):
        self.assert_inconclusive(diag.diagnose(FakeRunner(ps="garbage line\n")), "ps_unparseable")

    def test_ps_fields_are_validated(self):
        bad_etime = PS.replace("19:00:00 S ", "/Users/x S ")
        self.assert_inconclusive(diag.diagnose(FakeRunner(ps=bad_etime)), "ps_unparseable")
        bad_stat = PS.replace("19:00:00 S ", "19:00:00 S/x ")
        self.assert_inconclusive(diag.diagnose(FakeRunner(ps=bad_stat)), "ps_unparseable")

    def test_nonzero_ps(self):
        self.assert_inconclusive(diag.diagnose(FakeRunner(fail={"ps": (1, b"/Users/secret denied")})), "ps_failed")

    def test_timeout_ps(self):
        self.assert_inconclusive(diag.diagnose(FakeRunner(fail={"ps": diag.QueryLimit("timeout")})), "ps_failed")

    def test_oversized_ps(self):
        big = b"x" * (diag.MAX_OUTPUT_BYTES + 1)
        self.assert_inconclusive(diag.diagnose(FakeRunner(fail={"ps": (0, big)})), "ps_failed")

    def test_denied_lsof_marks_missing_evidence(self):
        result = diag.diagnose(FakeRunner(fail={"fds": (1, b"lsof: WARNING /Users/secret")}))
        self.assert_inconclusive(result, "fd_query_failed")
        self.assertTrue(all(p["fd_query"] == "failed" for p in result["observed_processes"]))

    def test_malformed_lsof_fd_output_is_not_treated_as_no_files(self):
        cases = {
            "garbage": b"hello\n",
            "empty": b"",
            "pid_mismatch": b"p999\nf1\nn/x\n",
            "two_headers": b"p200\nf1\np201\nf2\n",
            "missing_header": b"f1\nn/x\n",
            "field_before_fd": b"p200\nn/x\n",
            "duplicate_field": b"p200\nf1\nn/x\nn/y\n",
        }
        for label, raw in cases.items():
            with self.subTest(label):
                result = diag.diagnose(FakeRunner(raw={("fds", 200): raw}))
                self.assertEqual(procs(result)[200]["fd_query"], "malformed")
                self.assert_inconclusive(result, "lsof_unparseable")

    def test_valid_output_with_no_relevant_files_is_distinct(self):
        result = diag.diagnose(FakeRunner(raw={("fds", 200): b"p200\nf1\naw\ntREG\nn/Users/secret/x\n"}))
        self.assertEqual(procs(result)[200]["fd_query"], "ok")
        self.assertEqual(procs(result)[200]["build_fds"], [])

    def test_malformed_cwd_output(self):
        result = diag.diagnose(FakeRunner(raw={("cwd", 200): b"p999\nfcwd\nn" + ROOT.encode() + b"\n"}))
        self.assertEqual(procs(result)[200]["cwd_class"], "malformed")
        self.assert_inconclusive(result, "lsof_unparseable")

    def test_cwd_failure(self):
        self.assert_inconclusive(diag.diagnose(FakeRunner(fail={"cwd": OSError("/Users/secret")})), "cwd_query_failed")

    def test_too_many_candidates(self):
        rows = "".join(f"  {1000 + i}   100 Wed Oct 14 16:00:00 2026    20:00:00 S    /bin/bash\n"
                       for i in range(diag.MAX_CWD_QUERIES + 1))
        fake = FakeRunner(ps=PS + rows)
        result = diag.diagnose(fake)
        self.assert_inconclusive(result, "candidate_limit_exceeded")
        self.assertLessEqual(len([c for c in fake.calls if diag.classify_vector(c[0]) == "cwd"]),
                             diag.MAX_CWD_QUERIES)

    def test_unexpected_exception_is_contained(self):
        def boom(vector, timeout):
            raise RuntimeError("/Users/secret/token=abc")
        out = []
        with mock.patch.object(diag, "run_query", boom):
            code = diag.main([], write=out.append)
        result = json.loads(out[0])
        self.assertEqual(code, 0)
        self.assertEqual(result["status"], "INCONCLUSIVE")
        self.assertNotIn("secret", out[0])
        self.assertNotIn("token", out[0])

    def test_internal_error_output_is_sanitized(self):
        out = []
        with mock.patch.object(diag, "diagnose", side_effect=RuntimeError("/Users/secret")):
            diag.main([], write=out.append)
        self.assertEqual(json.loads(out[0])["reasons"], ["internal_error"])
        self.assertNotIn("secret", out[0])


class BridgeRouteTest(unittest.TestCase):
    def test_existing_policy_allows_only_the_direct_repo_executable_form(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "scripts").mkdir()
            target = root / "scripts" / "diagnose_host_build_jobs.py"
            target.write_text("#!/usr/bin/python3\n")
            target.chmod(0o755)
            env = {"PATH": "/usr/bin:/bin"}
            tools = set(bridge.DEFAULT_ALLOWED_TOOLS)

            def allowed(argv, cwd=root):
                return bridge._allowed_invocation(argv, cwd=cwd, host_repo_root=root, allowed_tools=tools, env=env)[0]

            self.assertTrue(allowed(["./scripts/diagnose_host_build_jobs.py"]))
            self.assertFalse(allowed(["python3", "scripts/diagnose_host_build_jobs.py"]))
            self.assertFalse(allowed(["bash", "-c", "ps -ax"]))
            self.assertFalse(allowed(["/bin/ps", "-ax"]))
            self.assertFalse(allowed(["/usr/sbin/lsof", "-p", "1"]))
            self.assertFalse(allowed(["bash", "/etc/outside.sh"]))


if __name__ == "__main__":
    unittest.main()
