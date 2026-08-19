@Tags(<String>['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/group_muted_notification_android_criteria.dart';

const String _liveArtifact = String.fromEnvironment(
  'MKNOON_379_GROUP_MUTED_MESSAGE_ARTIFACT',
);
const String _backgroundArtifact = String.fromEnvironment(
  'MKNOON_379_GROUP_MUTED_REACTION_ARTIFACT',
);
const String _killedTextCardArtifact = String.fromEnvironment(
  'MKNOON_384_GROUP_TEXT_KILLED_CARD_ARTIFACT',
);

/// Capture-owned binding for the availability-bounded Plan-379 Android pair.
///
/// Device setup and actions belong to
/// `run_group_muted_notification_android.dart`. This file only accepts its
/// content-addressed raw notification-dump, probe-observation, background
/// flow-log, and command-journal evidence; it never drives or builds an app.
void main() {
  test(groupMutedMessageSuppressionScenarioId, () async {
    if (_liveArtifact.trim().isEmpty) {
      fail(
        'The Plan-379 live muted-message proof artifact is not configured. '
        'Run the registered $groupMutedNotificationCapabilityId Sims '
        'capability, then bind its authoritative capture with '
        '--dart-define=MKNOON_379_GROUP_MUTED_MESSAGE_ARTIFACT=<json>.',
      );
    }

    final validation = await validateGroupMutedNotificationAndroidArtifact(
      artifactFile: File(_liveArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-379 live muted proof: ${validation.detail}',
    );
  });

  test(groupMutedReactionBackgroundScenarioId, () async {
    if (_backgroundArtifact.trim().isEmpty) {
      fail(
        'The Plan-379 background muted-reaction proof artifact is not '
        'configured. Run the registered $groupMutedNotificationCapabilityId '
        'Sims capability, then bind its authoritative capture with '
        '--dart-define=MKNOON_379_GROUP_MUTED_REACTION_ARTIFACT=<json>.',
      );
    }

    final validation = await validateGroupMutedNotificationAndroidArtifact(
      artifactFile: File(_backgroundArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-379 background muted proof: ${validation.detail}',
    );
  });

  test(groupTextKilledAppCardScenarioId, () async {
    if (_killedTextCardArtifact.trim().isEmpty) {
      fail(
        'The Plan-384 killed-app group-text card proof artifact is not '
        'configured. Run the registered $groupMutedNotificationCapabilityId '
        'Sims capability, then bind its authoritative capture with '
        '--dart-define=MKNOON_384_GROUP_TEXT_KILLED_CARD_ARTIFACT=<json>.',
      );
    }

    final validation = await validateGroupKilledTextCardAndroidArtifact(
      artifactFile: File(_killedTextCardArtifact),
    );
    expect(
      validation.ok,
      isTrue,
      reason: 'invalid Plan-384 killed-app card proof: ${validation.detail}',
    );
  });
}
