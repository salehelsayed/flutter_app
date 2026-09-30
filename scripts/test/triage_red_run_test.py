"""Host-only contracts for the advisory triage note. No network, no device.

Two properties matter and both are checked offline: the redactor never lets
credential-shaped text leave the machine, and the composition abstains instead
of guessing when a log does not name its own cause. The recorded answers below
are the real ones returned for those runs on 2026-09-21.
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import triage_red_run as triage

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "triage_red_run.py"


def answers(evidence, next_capture="nothing_more_needed", confidence=0.9, **causes):
    built = {cause: {"noul": value} for cause, value in causes.items()}
    for cause in triage.CAUSES:
        built.setdefault(cause, {"noul": 0.02})
    built["evidence_sufficient"] = {"noul": evidence}
    built["next_capture"] = {"choice": next_capture, "confidence": confidence}
    return built


class RedactionTest(unittest.TestCase):
    def test_bridge_token_never_survives(self):
        # Shape observed in a captured `ps` dump in this repo on 2026-09-21.
        text = "docker run -e CLAUDE_HOST_BRIDGE_TOKEN=jwnf_VCXn6emmc1f2VRS4PiwpCA_EKOiAqwPgkbEbN8 img"
        scrubbed, counts = triage.redact(text)
        self.assertNotIn("jwnf_VCXn6emmc1f2VRS4PiwpCA_EKOiAqwPgkbEbN8", scrubbed)
        self.assertIn("<redacted>", scrubbed)
        self.assertEqual(counts.get("credential_assignment"), 1)
        self.assertEqual(triage.residual_risk(scrubbed), [])

    def test_device_and_operator_identifiers_are_removed(self):
        text = ("destination id=00008030-001A6D2801BB802E path=/Users/someone/Library "
                "vol=/Volumes/CrucialX9/flutter_app host=192.168.1.9 "
                "sim=DBE8C32E-9F19-4593-860A-B41113791D79 mail=person@example.com")
        scrubbed, counts = triage.redact(text)
        for secret in ("00008030-001A6D2801BB802E", "someone", "CrucialX9",
                       "192.168.1.9", "DBE8C32E-9F19-4593-860A-B41113791D79",
                       "person@example.com"):
            self.assertNotIn(secret, scrubbed)
        for rule in ("ios_udid", "home_path", "volume_path", "ipv4", "uuid", "email"):
            self.assertIn(rule, counts)

    def test_relay_addresses_and_peer_ids_are_removed(self):
        text = ("--dart-define=MKNOON_RELAY_ADDRESSES=/ip4/192.168.1.9/tcp/59293"
                "/p2p/12D3KooWLRJg5zwYoHqvTTKiW4Vjne9ALKx3XpnpEeUUeQyDQHLq")
        scrubbed, _ = triage.redact(text)
        self.assertNotIn("12D3KooWLRJg5zwYoHqvTTKiW4Vjne9ALKx3XpnpEeUUeQyDQHLq", scrubbed)
        self.assertNotIn("192.168.1.9", scrubbed)

    def test_adb_serial_is_removed_but_emulator_name_is_kept(self):
        scrubbed, _ = triage.redact("adb -s 21071FDF600CSC shell dumpsys")
        self.assertNotIn("21071FDF600CSC", scrubbed)
        kept, _ = triage.redact("adb -s emulator-5554 shell dumpsys")
        self.assertIn("emulator-5554", kept)

    def test_ipv6_relay_multiaddresses_are_removed(self):
        timestamp = "2026-09-22T16:52:00.415368Z"
        for address in ("2001:db8:abcd:1234:1111:2222:3333:4444",
                        "2001:db8::5", "::ffff:192.0.2.1"):
            with self.subTest(address=address):
                text = f"{timestamp} circuit /ip6/{address}/udp/4002/quic-v1"
                scrubbed, counts = triage.redact(text)
                self.assertNotIn(address, scrubbed)
                self.assertIn(timestamp, scrubbed)
                self.assertIn("/ip6/<ip>/udp/4002/quic-v1", scrubbed)
                self.assertEqual(counts.get("ipv6_multiaddr"), 1)

    def test_private_key_material_is_treated_as_unscrubbable(self):
        text = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBg\n-----END PRIVATE KEY-----"
        scrubbed, _ = triage.redact(text)
        self.assertIn("private_key", triage.residual_risk(scrubbed))

    def test_android_serial_in_failure_prose_and_json_is_removed(self):
        text = ('Timed out waiting for no app PID or attached activity on 21071FDF600CSC.\n'
                '{"targetId":"21071FDF600CSC"}\n'
                'TC-00 API37 Flutter 3.47.2 emulator-5554')
        scrubbed, counts = triage.redact(text)
        self.assertNotIn('21071FDF600CSC', scrubbed)
        self.assertEqual(counts['android_serial'], 2)
        self.assertIn('TC-00 API37 Flutter 3.47.2 emulator-5554', scrubbed)

    def test_a_surviving_credential_is_reported_as_residual_risk(self):
        # Not an assignment, so the scrub does not catch it; the guard must.
        self.assertIn("live_credential",
                      triage.residual_risk("authorization bearer: AbCdEf0123456789xyz"))

    def test_redaction_is_idempotent(self):
        once, _ = triage.redact("TOKEN=abcdef0123456789 at /Users/someone")
        twice, _ = triage.redact(once)
        self.assertEqual(once, twice)


class CompositionTest(unittest.TestCase):
    def test_thin_evidence_abstains_instead_of_guessing(self):
        # Real answers for the bare `xcodebuild failed with code 65` run: the model
        # was confidently wrong, and the evidence gate is what withheld it.
        note = triage.decide(answers(0.25, "verbose_build_log", 0.82,
                                     missing_tunnel_or_transport=0.97))
        self.assertEqual(note["verdict"], "abstain")
        self.assertEqual(note["causes"], [])
        self.assertEqual(note["next_capture"], "verbose_build_log")

    def test_stacked_faults_are_both_reported(self):
        note = triage.decide(answers(0.85, "device_system_log", 0.7,
                                     missing_tunnel_or_transport=0.96,
                                     device_os_automation_gate=0.72))
        self.assertEqual(note["verdict"], "report")
        self.assertEqual([c["cause"] for c in note["causes"]],
                         ["missing_tunnel_or_transport", "device_os_automation_gate"])

    def test_a_green_run_reports_nothing(self):
        note = triage.decide(answers(0.05))
        self.assertEqual(note["verdict"], "abstain")
        self.assertEqual(note["causes"], [])

    def test_causes_below_the_firing_threshold_are_dropped(self):
        note = triage.decide(answers(0.9, product_failure=0.39))
        self.assertEqual(note["verdict"], "clean")
        self.assertEqual(note["causes"], [])


class EntryPointTest(unittest.TestCase):
    def run_script(self, *args, env=None):
        environment = {**os.environ, "TYPESAFE_API_KEY": "", **(env or {})}
        environment.pop("MKNOON_TRIAGE", None)
        if env and "MKNOON_TRIAGE" in env:
            environment["MKNOON_TRIAGE"] = env["MKNOON_TRIAGE"]
        return subprocess.run([sys.executable, str(SCRIPT), *args],
                              capture_output=True, text=True, env=environment, timeout=60)

    def test_disabled_by_default_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "run.log"
            log.write_text("xcodebuild failed with code 65\n")
            result = self.run_script(str(log))
            self.assertEqual(result.returncode, 0)
            self.assertIn("disabled", result.stdout)
            self.assertFalse(log.with_suffix(".log.triage.json").exists())

    def test_dry_run_prints_the_scrubbed_text_and_sends_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "run.log"
            log.write_text("TOKEN=abcdef0123456789 destination id=00008030-001A6D2801BB802E\n")
            result = self.run_script("--dry-run", str(log))
            self.assertEqual(result.returncode, 0)
            self.assertNotIn("abcdef0123456789", result.stdout)
            self.assertNotIn("00008030-001A6D2801BB802E", result.stdout)
            self.assertFalse(log.with_suffix(".log.triage.json").exists())

    def test_missing_log_is_a_usage_error(self):
        result = self.run_script("/nonexistent/run.log")
        self.assertEqual(result.returncode, 2)

    def test_enabled_without_a_key_writes_nothing_and_still_exits_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "run.log"
            log.write_text("boom\n")
            result = self.run_script(str(log), env={"MKNOON_TRIAGE": "1"})
            self.assertEqual(result.returncode, 0)
            self.assertIn("no TYPESAFE_API_KEY", result.stdout)
            self.assertFalse(log.with_suffix(".log.triage.json").exists())

    def test_blank_key_does_not_fall_back_to_the_repo_env_file(self):
        # Without this, a caller that blanks the variable still reaches the
        # network via .env, which is how this test first went red.
        os.environ["TYPESAFE_API_KEY"] = ""
        try:
            self.assertIsNone(triage.api_key(pathlib.Path(__file__).resolve().parents[2]))
        finally:
            os.environ.pop("TYPESAFE_API_KEY", None)


class ContractTest(unittest.TestCase):
    def test_the_note_never_carries_a_status(self):
        note = triage.decide(answers(0.9, product_failure=0.95))
        self.assertNotIn("status", note)
        self.assertNotIn("checkpoint", note)
        self.assertEqual(note["verdict"], "report")

    def test_every_cause_has_a_description_the_model_can_use(self):
        for cause, description in triage.CAUSES.items():
            self.assertGreater(len(description), 60, cause)
        built = triage.questions()
        self.assertEqual(built["next_capture"]["type"], "choice")
        self.assertTrue(all(built[c]["type"] == "noul" for c in triage.CAUSES))

    def test_question_set_is_json_serialisable(self):
        json.dumps(triage.questions())


if __name__ == "__main__":
    unittest.main()
