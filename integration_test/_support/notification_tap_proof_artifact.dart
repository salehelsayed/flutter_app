import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _proofDir = String.fromEnvironment('MKNOON_225_PROOF_DIR');
const String _proofArtifact = String.fromEnvironment(
  'MKNOON_225_PROOF_ARTIFACT',
);

Future<void> expect225ProofArtifact({
  required String testCase,
  required String scenario,
  required List<String> requiredChecks,
  required String blocker,
}) async {
  final file = _artifactFileForScenario(scenario);
  if (file == null) {
    fail(
      '$testCase/$scenario proof artifact not configured. Exact blocker: '
      '$blocker. Capture real proof, then rerun with '
      '--dart-define=MKNOON_225_PROOF_DIR=<dir> containing $scenario.json '
      'or --dart-define=MKNOON_225_PROOF_ARTIFACT=<file>.',
    );
  }
  if (!await file.exists()) {
    fail(
      '$testCase/$scenario proof artifact missing at ${file.path}. '
      'Exact blocker: $blocker.',
    );
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    fail('$testCase/$scenario proof artifact root must be a JSON object.');
  }
  expect(decoded['testCase'], testCase);
  expect(decoded['scenario'], scenario);
  expect(decoded['status'], 'passed');
  expect(
    decoded['capturedAt'],
    isA<String>().having((value) => value.trim().isNotEmpty, 'non-empty', true),
  );

  final checks = decoded['checks'];
  if (checks is! Map<String, dynamic>) {
    fail('$testCase/$scenario proof artifact must contain a checks object.');
  }
  for (final check in requiredChecks) {
    expect(
      checks[check],
      isTrue,
      reason: '$testCase/$scenario missing required proof check "$check"',
    );
  }
}

File? _artifactFileForScenario(String scenario) {
  if (_proofDir.trim().isNotEmpty) {
    return File('$_proofDir${Platform.pathSeparator}$scenario.json');
  }
  if (_proofArtifact.trim().isNotEmpty) {
    return File(_proofArtifact);
  }
  return null;
}
