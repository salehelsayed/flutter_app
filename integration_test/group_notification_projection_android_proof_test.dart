@Tags(<String>['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/group_notification_projection_android_criteria.dart';

const String _proofArtifact = String.fromEnvironment(
  'MKNOON_330_GROUP_NOTIFICATION_PROJECTION_ARTIFACT',
);

/// Capture-owned binding for the availability-bounded Plan-330 Android pair.
///
/// Device setup and actions belong to
/// `run_group_notification_projection_android.dart`. This file only accepts
/// its content-addressed raw UI, flow-log, SQL/media-target, and Android
/// notification evidence; it never drives or builds an app.
void main() {
  test(groupNotificationProjectionScenarioId, () async {
    if (_proofArtifact.trim().isEmpty) {
      fail(
        'The Plan-330 proof artifact is not configured. Run the registered '
        '$groupNotificationProjectionCapabilityId Sims capability, then bind '
        'its authoritative capture with '
        '--dart-define=MKNOON_330_GROUP_NOTIFICATION_PROJECTION_ARTIFACT='
        '<json>.',
      );
    }

    final validation = await validateGroupNotificationProjectionAndroidArtifact(
      artifactFile: File(_proofArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-330 Android proof: ${validation.detail}',
    );
  });
}
