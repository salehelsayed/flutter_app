"""Receipt classification must distinguish native fault RED from setup failure."""
from pathlib import Path
import contextlib
import io
import json
import sys
import tempfile
import unittest
from unittest import mock

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


def fixture_execution(case, args, output):
    """Fresh synthetic native receipts for the existing SIMS process contract.

    Only execute() is substituted. Production main(), proof emission, sentinel
    parsing, durable artifact audits and the outer wrapper run unchanged.
    These fixtures never launch native tools or import saved execution evidence.
    """
    if case in ('blocked', 'failed', 'unavailable', 'setup'):
        status = {'blocked': 'BLOCKED', 'failed': 'FAIL', 'unavailable': 'N/A',
                  'setup': 'SETUP_READY'}[case]
        result = dict(status=status, assertionsAttempted=0)
        if case == 'blocked':
            result['blocker'] = 'harness'
        elif case == 'failed':
            result.update(assertionsAttempted=4, blocker='test')
        elif case == 'unavailable':
            result.update(blocker='targetUnavailable', targetCapabilityAvailable=False,
                          reason=native.NA)
        return result, 2 if case in ('blocked', 'failed') else 0
    variants, sources = {}, {}
    names = ('baseline', 'patched') if args.variant == 'both' else (args.variant,)
    for variant in names:
        folder = output / variant
        folder.mkdir()
        raw = transcript('failed', marker=True) if variant == 'baseline' else transcript('passed')
        if case == 'partial-native' and variant == 'patched':
            raw = raw.splitlines()[0]
        (folder / 'xctest.raw.log').write_text(raw)
        sources[variant] = {str(native.RUNTIME): variant, 'darwin/Tests/SampleBufferTests.swift': 'same-fixture'}
        native.save(folder / 'inputs.json', dict(variant=variant, fixture=True,
                    fixture_selectors=list(native.METHODS), source_sha256=sources[variant]))
        native.save(folder / 'build-inputs.json', dict(source_sha256=sources[variant], fixture=True))
        code = 65 if variant == 'baseline' else 0
        native.save(folder / 'xctest.json', dict(exit_status=code, timed_out=False,
                    raw_sha256=native.sha(folder / 'xctest.raw.log')))
        # Retain an asserted success for the partial-native mutation: proof
        # emission must reject it using the actual incomplete raw receipt.
        proof = native.adjudicate(transcript('failed', marker=True) if variant == 'baseline'
                                  else transcript('passed'), code, False, variant)
        proof.update(input_identity_sha256=native.sha(folder / 'inputs.json'),
                     build_inputs_sha256=native.sha(folder / 'build-inputs.json'))
        native.save(folder / 'result.json', proof)
        bundle = folder / 'native.xcresult'
        bundle.mkdir()
        (bundle / 'fixture.txt').write_text('Synthetic process-contract fixture; no native execution.')
        variants[variant] = proof
    comparison = dict(variants=variants, same_fixture=True, runtime_only_delta=str(native.RUNTIME),
                      source_identities=sources)
    if case == 'incomplete-comparison':
        comparison['variants'] = {'patched': variants['patched']}
    if case != 'missing-comparison':
        native.save(output / 'comparison.json', comparison)
    return dict(status='EXPECTED_RED' if args.variant == 'baseline' else 'PASS',
                assertionsAttempted=4, variants=variants), 0


def run_fixture(case, output, variant='both'):
    with mock.patch.object(native, 'execute', side_effect=lambda args, path: fixture_execution(case, args, path)):
        with contextlib.redirect_stdout(io.StringIO()) as stream:
            code = native.main(['--output', str(output), '--variant', variant])
    text = stream.getvalue()
    # Mutate only the newly generated fixture, after production published it,
    # so the real executor must independently reject the evidence claim.
    if case in ('missing-artifact', 'tampered-artifact', 'wrong-validator'):
        sentinel = next(line for line in text.splitlines() if line.startswith('SIMS_RESULT_JSON='))
        wire = json.loads(sentinel.split('=', 1)[1])
        artifact = Path(wire['artifactEvidence']['path'])
        if case == 'missing-artifact':
            artifact.unlink()
        elif case == 'tampered-artifact':
            artifact.write_text(artifact.read_text() + 'tampered')
        else:
            wire['artifactEvidence']['validatorIds'] = ['fixture.wrong-validator']
            text = text.replace(sentinel, 'SIMS_RESULT_JSON=' + json.dumps(wire))
    return code, text


class CameraNativeArtifactTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='camera-evidence-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def invoke(self, case, variant='both'):
        output = self.root / (case + '-' + variant)
        code, text = run_fixture(case, output, variant)
        sentinels = [json.loads(line.split('=', 1)[1]) for line in text.splitlines()
                     if line.startswith('SIMS_RESULT_JSON=')]
        self.assertLessEqual(len(sentinels), 1)
        return output, code, sentinels[0] if sentinels else None

    def test_completed_comparison_binds_real_canonical_content_and_native_references(self):
        output, code, wire = self.invoke('pass')
        self.assertEqual(code, 0)
        self.assertEqual(wire['status'], 'PASS')
        evidence = wire['artifactEvidence']
        artifact = Path(evidence['path'])
        self.assertEqual(str(artifact), str(artifact.resolve(strict=True)))
        self.assertEqual(native.sha(artifact), evidence['sha256'])
        self.assertEqual(evidence['validatorIds'], [native.ARTIFACT_VALIDATOR])
        payload = json.loads(artifact.read_text())
        self.assertEqual(payload['schema'], 'mknoon.sims.proof.v1')
        self.assertEqual(payload['capabilityId'], native.CAPABILITY)
        self.assertEqual(payload['validatorIds'], evidence['validatorIds'])
        self.assertEqual(native.sha(output / 'comparison.json'), payload['comparison']['sha256'])
        self.assertEqual(set(payload['variants']), {'baseline', 'patched'})
        for variant, references in payload['variants'].items():
            for name in ('result.json', 'inputs.json', 'build-inputs.json', 'xctest.json', 'xctest.raw.log'):
                self.assertEqual(references[name]['sha256'], native.sha(output / variant / name))
                self.assertEqual(references[name]['path'], str((output / variant / name).resolve()))
            self.assertTrue(Path(references['xcresult']['path']).is_dir())

    def test_missing_or_incomplete_comparison_cannot_publish_artifact_success(self):
        for case in ('missing-comparison', 'incomplete-comparison', 'partial-native'):
            with self.subTest(case=case):
                output, code, wire = self.invoke(case)
                self.assertEqual(code, 2)
                self.assertEqual(wire['status'], 'BLOCKED')
                self.assertFalse(wire['artifactPresent'])
                self.assertNotIn('artifactEvidence', wire)
                self.assertFalse((output / 'comparison-proof.json').exists())
                # Completed native result receipts survive reporting refusal.
                self.assertTrue((output / 'baseline/result.json').is_file())
                self.assertTrue((output / 'patched/result.json').is_file())

    def test_failure_setup_unavailable_and_single_variant_do_not_claim_comparison_proof(self):
        for case in ('blocked', 'failed', 'unavailable', 'setup'):
            with self.subTest(case=case):
                output, _, wire = self.invoke(case)
                self.assertFalse((output / 'comparison-proof.json').exists())
                if wire is not None:
                    self.assertFalse(wire['artifactPresent'])
                    self.assertNotIn('artifactEvidence', wire)
        for variant in ('baseline', 'patched'):
            with self.subTest(variant=variant):
                output, _, wire = self.invoke('pass', variant)
                self.assertFalse((output / 'comparison-proof.json').exists())
                if wire is not None:
                    self.assertFalse(wire['artifactPresent'])
                    self.assertNotIn('artifactEvidence', wire)


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == '--sims-fixture':
        exit_code, stdout = run_fixture(sys.argv[2], Path(sys.argv[3]))
        print(stdout, end='')
        sys.exit(exit_code)
    unittest.main()
