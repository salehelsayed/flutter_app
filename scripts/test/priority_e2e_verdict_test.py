import copy
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from priority_e2e_verdict import EMULATOR_CONTACT_CASES, main, template, validate


SOURCE = "a" * 40


class PriorityE2EReceiptTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "mcp.txt").write_text("retained executor observations\n")

    def completed(self, case="RG-002"):
        receipt = template(case, SOURCE)
        receipt["run_id"] = "owned-attempt-1"
        for artifact in receipt["artifacts"].values():
            artifact.update(sha256="b" * 64, version="test-candidate")
        for check in receipt["checks"].values():
            check.update(status="PASS", evidence=["mcp.txt"],
                         observed_by="mcp" if case in EMULATOR_CONTACT_CASES else "human",
                         started_at="2026-10-26T08:30:00+01:00")
        return receipt

    def result(self, receipt, source=SOURCE):
        return validate(receipt, source, self.root)

    def test_template_cannot_be_mistaken_for_execution(self):
        self.assertEqual(self.result(template("RG-002", SOURCE))["status"], "INCOMPLETE")

    def test_malformed_case_and_availability_fail_closed(self):
        receipt = self.completed()
        receipt.update(case=[], availability={})
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_completed_observations_are_recorded_and_evidence_is_hashed(self):
        result = self.result(self.completed())
        self.assertEqual(result["status"], "PASS_RECORDED")
        self.assertEqual(len(result["evidence_sha256"]["mcp.txt"]), 64)

    def test_missing_required_observation_does_not_pass(self):
        receipt = self.completed()
        del receipt["checks"]["first_group_all_members"]
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_expected_revision_cannot_be_replaced_by_receipt_revision(self):
        self.assertEqual(self.result(self.completed(), "c" * 40)["status"], "INCOMPLETE")

    def test_an_unbound_peer_artifact_is_incomplete(self):
        receipt = self.completed()
        receipt["artifacts"]["B"]["source_revision"] = "c" * 40
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_android_pair_cannot_supply_cross_platform_evidence(self):
        receipt = self.completed("CR-009")
        receipt["artifacts"]["A"]["platform"] = "android"
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_two_members_cannot_supply_three_member_group_evidence(self):
        receipt = self.completed("GX-002")
        del receipt["artifacts"]["C"]
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_missing_empty_absolute_and_escaping_evidence_are_rejected(self):
        (self.root / "empty.txt").touch()
        for ref in ["missing.txt", "empty.txt", str(self.root / "mcp.txt"), "../outside.txt"]:
            with self.subTest(ref=ref):
                receipt = self.completed()
                receipt["checks"]["onboarding_ui"]["evidence"] = [ref]
                self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_symlink_cannot_escape_evidence_root(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "private.txt"
            target.write_text("outside evidence\n")
            (self.root / "link.txt").symlink_to(target)
            receipt = self.completed()
            receipt["checks"]["onboarding_ui"]["evidence"] = ["link.txt"]
            self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_connected_screen_cannot_supply_audible_call_evidence(self):
        receipt = self.completed("VC-015")
        receipt["checks"]["ios_origin_audio_both_ways"]["observed_by"] = "mcp"
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_call_gate_uses_berlin_time_and_rejects_missing_timezone(self):
        receipt = self.completed("VC-015")
        self.assertEqual(self.result(receipt)["status"], "PASS_RECORDED")
        receipt["checks"]["ios_calls_android_answered"]["started_at"] = "2026-10-26T07:30:00Z"
        self.assertEqual(self.result(receipt)["status"], "PASS_RECORDED")
        for start in ["2026-10-26T07:29:59Z", "2026-10-26T08:30:00", ""]:
            with self.subTest(start=start):
                changed = copy.deepcopy(receipt)
                changed["checks"]["ios_calls_android_answered"]["started_at"] = start
                self.assertEqual(self.result(changed)["status"], "INCOMPLETE")

    def test_supported_state_exception_does_not_excuse_locked_ring(self):
        receipt = self.completed("VC-014")
        receipt["checks"]["supported_process_termination"].update(
            status="N/A", reason="unsupported_os_state")
        self.assertEqual(self.result(receipt)["status"], "PASS_RECORDED")
        receipt["checks"]["ios_locked_ring_answer_audio"]["status"] = "N/A"
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_unavailable_live_target_is_na_with_evidence_not_a_pass(self):
        receipt = template("VC-015", SOURCE)
        receipt.update(run_id="matrix-1", availability="target_unavailable")
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")
        receipt["availability_evidence"] = ["mcp.txt"]
        self.assertEqual(self.result(receipt)["status"], "N/A_TARGET_UNAVAILABLE")

    def test_cli_rejects_a_complete_receipt_for_the_wrong_requested_case(self):
        path = self.root / "receipt.json"
        path.write_text(json.dumps(self.completed()))
        output = io.StringIO()
        with patch.object(sys, "argv", ["verdict", "check", "--source", SOURCE,
                                       "--case", "VC-015", "--receipt", str(path)]):
            with redirect_stdout(output):
                code = main()
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(output.getvalue())["status"], "INCOMPLETE")

    def test_contact_templates_use_emulators_and_require_actual_consent(self):
        receipt = self.completed("CR-001")
        self.assertEqual(self.result(receipt)["status"], "PASS_RECORDED")
        del receipt["checks"]["explicit_accept_and_reciprocal_keys"]
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_physical_or_ios_roles_cannot_supply_emulator_case(self):
        for field, value in [("target_kind", "android_physical"), ("platform", "ios")]:
            with self.subTest(field=field):
                receipt = self.completed("CR-001")
                receipt["artifacts"]["A"][field] = value
                self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_post_restart_chat_does_not_replace_failed_reciprocal_evidence(self):
        receipt = self.completed("CR-018")
        del receipt["checks"]["failed_reciprocal_retained"]
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_host_only_control_does_not_complete_emulator_observation(self):
        receipt = self.completed("CR-003")
        receipt["checks"]["blocked_pending_sender_not_presented"]["observed_by"] = "host"
        self.assertEqual(self.result(receipt)["status"], "INCOMPLETE")

    def test_crossed_request_verdict_keeps_its_specific_scope(self):
        result = self.result(self.completed("CR-005"))
        self.assertEqual(result["status"], "PASS_RECORDED")
        self.assertEqual(result["scope"], "emulator_crossed_requests_ui")


if __name__ == "__main__":
    unittest.main()
