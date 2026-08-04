@Tags(<String>['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/android_notification_recovery_completion_criteria.dart';

const String _proofArtifact = String.fromEnvironment(
  'MKNOON_331_ANDROID_NOTIFICATION_RECOVERY_ARTIFACT',
);

/// Capture-owned binding for the paired Android/real-relay Plan-331 campaign.
/// Device control belongs exclusively to the registered Sims runner.
void main() {
  test(androidNotificationRecoveryCompletionCapabilityId, () {
    if (_proofArtifact.trim().isEmpty) {
      fail(
        'The Plan-331 proof artifact is not configured. Run the registered '
        '$androidNotificationRecoveryCompletionCapabilityId capability and '
        'bind its artifact with '
        '--dart-define=MKNOON_331_ANDROID_NOTIFICATION_RECOVERY_ARTIFACT='
        '<json>.',
      );
    }

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: File(_proofArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-331 Android proof: ${validation.detail}',
    );
  });
}
