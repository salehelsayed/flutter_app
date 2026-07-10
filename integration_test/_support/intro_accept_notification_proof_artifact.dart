import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _proofDir = String.fromEnvironment('MKNOON_252_PROOF_DIR');

/// Validates one Plan 252 D1/D2 campaign artifact captured by
/// `integration_test/scripts/run_intro_accept_notification_android.dart`.
///
/// The runner performs the full self-controlled campaign (setup via the intro
/// E2E config channel, `am kill` terminations with empty-`pidof` proof,
/// dumpsys/UIAutomator copy extraction, bounded exact-title node taps, and
/// logcat route markers) and writes `<scenario>.json`; this test pins that
/// every required check actually passed for the scenario.
Future<void> expect252ProofArtifact({
  required String testCase,
  required String scenario,
}) async {
  if (_proofDir.trim().isEmpty) {
    fail(
      '$testCase/$scenario proof artifact not configured. Run '
      'dart run integration_test/scripts/'
      'run_intro_accept_notification_android.dart --scenario $scenario '
      'with live rediscovered device IDs, then rerun with '
      '--dart-define=MKNOON_252_PROOF_DIR=<artifact-dir>.',
    );
  }
  final file = File('$_proofDir${Platform.pathSeparator}$scenario.json');
  if (!await file.exists()) {
    fail('$testCase/$scenario proof artifact missing at ${file.path}.');
  }

  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    fail('$testCase/$scenario proof artifact root must be a JSON object.');
  }
  expect(decoded['testCase'], testCase);
  expect(decoded['scenario'], scenario);
  expect(decoded['status'], 'passed');
  expect(
    decoded['copyExtractor'],
    anyOf('dumpsys', 'uiautomator'),
    reason: 'copy extraction must have used a probed bounded extractor',
  );
  expect(decoded['devices'], isA<List<dynamic>>());
  expect((decoded['devices'] as List<dynamic>).length, 3);

  final checks = decoded['checks'];
  if (checks is! Map<String, dynamic>) {
    fail('$testCase/$scenario proof artifact must contain a checks object.');
  }
  const requiredChecks = [
    'targetsDiscovered',
    'identitiesCollected',
    'contactsEstablished',
    'introductionSent',
    'copyExtractorFeasibility',
    'b_acceptIntroducerTerminatedBeforeSend',
    'b_acceptIntroducerStillTerminatedBeforeTap',
    'b_acceptAcceptanceCopy',
    'b_acceptBoundedNodeTap',
    'b_acceptFinalPeerIsRecipient',
    'b_acceptStatusContext',
    'c_acceptIntroducerTerminatedBeforeSend',
    'c_acceptIntroducerStillTerminatedBeforeTap',
    'c_acceptAcceptanceCopy',
    'c_acceptBoundedNodeTap',
    'c_acceptFinalPeerIsRecipient',
    'c_acceptStatusContext',
    'zeroNavigationErrors',
  ];
  for (final check in requiredChecks) {
    expect(
      checks[check],
      isTrue,
      reason: '$testCase/$scenario missing required proof check "$check"',
    );
  }
}
