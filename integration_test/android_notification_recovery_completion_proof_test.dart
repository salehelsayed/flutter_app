@Tags(<String>['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/android_notification_recovery_completion_criteria.dart';

const String _proofArtifact = String.fromEnvironment(
  'MKNOON_393_ANDROID_FIXED_WAKE_RECOVERY_ARTIFACT',
);

/// Capture-owned binding for the Plan-393 Android fixed-wake campaign.
/// Device control belongs exclusively to the registered Sims runner.
void main() {
  test(androidNotificationRecoveryCompletionCapabilityId, () {
    if (_proofArtifact.trim().isEmpty) {
      fail(
        'The Plan-393 proof artifact is not configured. Run the registered '
        '$androidNotificationRecoveryCompletionCapabilityId capability and '
        'bind its artifact with '
        '--dart-define=MKNOON_393_ANDROID_FIXED_WAKE_RECOVERY_ARTIFACT='
        '<json>.',
      );
    }

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: File(_proofArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-393 Android proof: ${validation.detail}',
    );
  });
}
