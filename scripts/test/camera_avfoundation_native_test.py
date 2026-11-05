"""Receipt classification must distinguish native fault RED from setup failure."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import camera_avfoundation_native as native


def transcript(state, marker=False):
    lines = []
    for method in native.METHODS:
        if marker:
            lines.append("sample.swift:12: error: -[RunnerTests.CameraSampleBufferTests " + method
                         + "] : XCTAssertEqual failed - CAMERA_SWITCH_RECOVERY configuration balanced")
        lines.append("Test Case '-[RunnerTests.CameraSampleBufferTests " + method + "]' " + state)
    lines.append('** TEST SUCCEEDED **' if state == 'passed' else '** TEST FAILED **')
    return '\n'.join(lines)


class CameraNativeReceiptsTest(unittest.TestCase):
    def test_only_complete_fault_assertions_establish_expected_red(self):
        proof = native.adjudicate(transcript('failed', marker=True), 65, False, 'baseline')
        self.assertEqual(proof['status'], 'EXPECTED_RED')
        self.assertEqual(proof['counts']['failed'], 4)

    def test_baseline_compiler_or_setup_error_is_not_red(self):
        for raw in ['** BUILD FAILED **', '', transcript('failed')]:
            with self.subTest(raw=raw):
                self.assertNotEqual(native.adjudicate(raw, 65, False, 'baseline')['status'], 'EXPECTED_RED')

    def test_partial_duplicate_skipped_timeout_and_capacity_are_not_green(self):
        good = transcript('passed')
        cases = [(good.splitlines()[0], 0, False), (good + '\n' + good, 0, False),
                 (transcript('skipped'), 0, False), (good, 0, True), (good, 93, False)]
        for raw, code, timeout in cases:
            with self.subTest(code=code, timeout=timeout, raw=raw):
                self.assertNotEqual(native.adjudicate(raw, code, timeout, 'patched')['status'], 'PASS')

    def test_baseline_success_does_not_prove_regression(self):
        self.assertNotEqual(native.adjudicate(transcript('passed'), 0, False, 'baseline')['status'], 'EXPECTED_RED')

    def test_green_requires_four_exact_native_cases_and_successful_exit(self):
        proof = native.adjudicate(transcript('passed'), 0, False, 'patched')
        self.assertEqual(proof['status'], 'PASS')
        self.assertEqual(proof['counts']['passed'], 4)
        self.assertNotEqual(native.adjudicate(transcript('passed'), 65, False, 'patched')['status'], 'PASS')


if __name__ == '__main__':
    unittest.main()
