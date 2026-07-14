@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scripts/group_reaction_notification_device_criteria.dart';

const String _proofDirectory = String.fromEnvironment('MKNOON_257_PROOF_DIR');
const String _proofArtifact = String.fromEnvironment(
  'MKNOON_257_PROOF_ARTIFACT',
);

void main() {
  test('android_group_message_unread_lifecycle', () async {
    await _validateScenario('android_group_message_unread_lifecycle');
  });

  test('android_announcement_message_unread_lifecycle', () async {
    await _validateScenario('android_announcement_message_unread_lifecycle');
  });

  test('android_group_reaction_recipient', () async {
    await _validateScenario('android_group_reaction_recipient');
  });

  test('android_announcement_reaction_recipient', () async {
    await _validateScenario('android_announcement_reaction_recipient');
  });

  test('ios_announcement_reaction_recipient', () async {
    await _validateScenario('ios_announcement_reaction_recipient');
  });
}

Future<void> _validateScenario(String scenario) async {
  final artifact = _artifactFor(scenario);
  if (artifact == null) {
    fail(
      '$scenario proof artifact is not configured. Capture the real '
      'app/SQLCipher/relay/provider/OS evidence and rerun with '
      '--dart-define=MKNOON_257_PROOF_DIR=<dir> or '
      '--dart-define=MKNOON_257_PROOF_ARTIFACT=<json>.',
    );
  }
  final validation = await validateGroupReactionNotificationArtifact(
    scenario: scenario,
    artifactFile: artifact,
  );
  expect(
    validation.ok,
    isTrue,
    reason: 'invalid $scenario proof artifact: ${validation.detail}',
  );
}

File? _artifactFor(String scenario) {
  if (_proofArtifact.trim().isNotEmpty) return File(_proofArtifact);
  if (_proofDirectory.trim().isEmpty) return null;
  final direct = File(
    '$_proofDirectory${Platform.pathSeparator}$scenario.json',
  );
  if (direct.existsSync()) return direct;
  return File(
    '$_proofDirectory${Platform.pathSeparator}$scenario'
    '${Platform.pathSeparator}$scenario.json',
  );
}
