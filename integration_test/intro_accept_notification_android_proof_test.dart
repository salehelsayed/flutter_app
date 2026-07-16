// Capture-owned artifact binding. It performs no device action and is invoked
// only after the intro Android capture owner writes the TC-12/TC-13 artifact.
library;

import 'package:flutter_test/flutter_test.dart';

import '_support/intro_accept_notification_proof_artifact.dart';

/// Plan 252 TC-12/TC-13 device proof targets.
///
/// Each scenario is captured by the self-controlled three-party campaign
/// orchestrator (`integration_test/scripts/
/// run_intro_accept_notification_android.dart`) against a staging relay
/// running the Plan 252 relay build; this test validates the emitted
/// artifact so the proof is machine-checked, never a human judgment.
void main() {
  test('physical_introducer', () async {
    await expect252ProofArtifact(
      testCase: 'TC-12',
      scenario: 'physical_introducer',
    );
  });

  test('emulator_introducer', () async {
    await expect252ProofArtifact(
      testCase: 'TC-13',
      scenario: 'emulator_introducer',
    );
  });
}
