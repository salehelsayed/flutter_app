@Tags(<String>['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/group_strict_notification_criteria.dart';

const String _proofArtifact = String.fromEnvironment(
  'MKNOON_393_GROUP_STRICT_NOTIFICATION_ARTIFACT',
);

/// Capture-owned binding for the availability-bounded strict Android pair.
/// Device setup, authority construction, actions, and restoration belong to
/// the registered Sims runner; this test accepts only its bound raw artifact.
void main() {
  test(groupStrictNotificationScenarioId, () async {
    if (_proofArtifact.trim().isEmpty) {
      fail(
        'The Plan-393 strict proof artifact is not configured. Run '
        '$groupStrictNotificationCapabilityId and bind '
        'MKNOON_393_GROUP_STRICT_NOTIFICATION_ARTIFACT=<json>.',
      );
    }
    final validation = await validateGroupStrictNotificationArtifact(
      artifactFile: File(_proofArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-393 strict proof: ${validation.detail}',
    );
  });
}
