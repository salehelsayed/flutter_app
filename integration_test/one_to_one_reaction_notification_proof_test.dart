@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scripts/reaction_notification_proof_support.dart';

const String _proofDir = String.fromEnvironment('MKNOON_256_PROOF_DIR');
const String _proofArtifact = String.fromEnvironment(
  'MKNOON_256_PROOF_ARTIFACT',
);

void main() {
  test('head_provenance', () async {
    final file = _artifactFile('head_provenance');
    if (file == null) {
      fail(
        'TC-00 proof artifact is not configured. Capture the clean-current-'
        'build producer boundary, then rerun with '
        '--dart-define=MKNOON_256_PROOF_DIR=<dir> or '
        '--dart-define=MKNOON_256_PROOF_ARTIFACT=<file>.',
      );
    }
    expect(await file.exists(), isTrue, reason: 'missing ${file.path}');

    final decoded = jsonDecode(await file.readAsString());
    expect(decoded, isA<Map<String, dynamic>>());
    final artifact = decoded as Map<String, dynamic>;
    expect(artifact['testCase'], 'TC-00');
    expect(artifact['scenario'], 'head_provenance');
    expect(artifact['status'], 'passed');
    expect(_nonEmpty(artifact['capturedAt']), isTrue);

    final app = _object(artifact, 'app');
    expect(_nonEmpty(app['revision']), isTrue);
    expect(app['cleanCurrentBuild'], isTrue);
    expect(_nonEmpty(app['apkSha256']), isTrue);

    final relay = _object(artifact, 'relay');
    expect(_nonEmpty(relay['revision']), isTrue);
    expect(_nonEmpty(relay['evidencePath']), isTrue);
    expect(relay['adminAccessReadOnly'], isTrue);
    expect(relay['testTrafficWritesExpected'], isTrue);

    final reaction = _object(artifact, 'reaction');
    expect(_nonEmpty(reaction['eventId']), isTrue);
    expect(reaction['remoteType'], 'message_reaction');

    final observation = _object(artifact, 'observation');
    final cardPresent = observation['cardPresent'];
    expect(cardPresent, isA<bool>());
    expect(observation['unrelatedCardsRejected'], isTrue);
    expect(observation['matchedReactionEventId'], isTrue);
    expect(_nonEmpty(observation['producer']), isTrue);
    expect(_nonEmpty(observation['lifecycle']), isTrue);
    expect(_nonEmpty(observation['tapRoute']), isTrue);

    final attribution = _object(artifact, 'sourceAttribution');
    expect(attribution['relayMatchedEvent'], isTrue);
    expect(attribution['providerEvidenceCaptured'], isTrue);
    expect(
      attribution['providerObservationWindowSeconds'],
      isA<num>().having(
        (value) => value.toInt(),
        'seconds',
        greaterThanOrEqualTo(8),
      ),
    );

    if (cardPresent == true) {
      expect(observation['producer'], isNot('none'));
      expect(_nonEmpty(observation['title']), isTrue);
      expect(_nonEmpty(observation['body']), isTrue);
      expect(attribution['providerMatchedEvent'], isTrue);
    } else {
      expect(observation['producer'], 'none');
      expect(observation['lifecycle'], 'not_emitted');
      expect(observation['tapRoute'], 'not_applicable');
      expect(attribution['providerConfirmedNoSend'], isTrue);
    }
  });

  // Plan 391 TC-391-10. The runner shells this test with
  // --plain-name <scenario.id> after every successful capture, so this is the
  // evidence oracle for the killed-path 1:1 reaction leg: it is what makes the
  // device command's exit 0 mean the capture proved what it claims.
  test('android_typed_reaction_smoke', () async {
    final file = _artifactFile('android_typed_reaction_smoke');
    if (file == null) {
      fail(
        'TC-13-core-smoke proof artifact is not configured. Capture the '
        'killed-recipient typed reaction smoke, then rerun with '
        '--dart-define=MKNOON_256_PROOF_DIR=<dir> or '
        '--dart-define=MKNOON_256_PROOF_ARTIFACT=<file>.',
      );
    }
    expect(await file.exists(), isTrue, reason: 'missing ${file.path}');

    final decoded = jsonDecode(await file.readAsString());
    expect(decoded, isA<Map<String, dynamic>>());
    final artifact = decoded as Map<String, dynamic>;
    expect(artifact['testCase'], 'TC-13-core-smoke');
    expect(artifact['scenario'], 'android_typed_reaction_smoke');
    expect(artifact['status'], 'passed');
    expect(_nonEmpty(artifact['capturedAt']), isTrue);

    final app = _object(artifact, 'app');
    expect(_nonEmpty(app['revision']), isTrue);
    expect(
      app['workingTreeCandidate'],
      isTrue,
      reason: 'the typed smoke grades the working tree, not clean HEAD',
    );
    expect(_nonEmpty(app['apkSha256']), isTrue);

    final relay = _object(artifact, 'relay');
    expect(_nonEmpty(relay['revision']), isTrue);
    expect(_nonEmpty(relay['evidencePath']), isTrue);

    final reaction = _object(artifact, 'reaction');
    expect(_nonEmpty(reaction['eventId']), isTrue);
    expect(reaction['remoteType'], 'message_reaction');

    final observation = _object(artifact, 'observation');
    expect(
      observation['cardPresent'],
      isTrue,
      reason: 'a killed recipient must still be alerted for the reaction',
    );
    expect(
      observation['recipientProcessAbsentBeforeReaction'],
      isTrue,
      reason:
          'the recipient app must have been measured absent at the moment the '
          'reaction was driven, or this is not a killed-path proof',
    );
    expect(observation['typedCopyRequired'], isTrue);
    expect(observation['genericNewMessageRejected'], isTrue);
    expect(observation['unrelatedCardsRejected'], isTrue);
    expect(observation['matchedReactionEventId'], isTrue);
    expect(observation['producer'], isNot('none'));
    expect(_nonEmpty(observation['lifecycle']), isTrue);
    expect(_nonEmpty(observation['tapRoute']), isTrue);
    expect(_nonEmpty(observation['title']), isTrue);
    expect(_nonEmpty(observation['body']), isTrue);

    final attribution = _object(artifact, 'sourceAttribution');
    expect(attribution['relayMatchedEvent'], isTrue);
    expect(attribution['providerEvidenceCaptured'], isTrue);
    expect(
      attribution['providerMatchedEvent'],
      isTrue,
      reason: 'the card must be attributed to an observed provider send',
    );
    expect(
      attribution['recipientBackgroundPushObserved'],
      isTrue,
      reason:
          'the send is attributed on the recipient device: the relay no longer '
          'emits a peer-attributed push line',
    );
    expect(attribution['providerEvidenceSource'], 'recipient_background_push');
    expect(_nonEmpty(attribution['providerEvidencePath']), isTrue);

    expect(
      artifact['unreadLifecycle'],
      isA<Map<String, dynamic>>(),
      reason: 'the typed smoke captures the unread lifecycle after the tap',
    );
  });

  // The alive-connected durable leg. The runner shells this test with
  // --plain-name <scenario.id> after every successful capture, so it is the
  // evidence oracle for the one claim the killed-path leg could not make.
  //
  // Read it beside android_typed_reaction_smoke: that leg proves a killed 1:1
  // recipient IS alerted, but its card came from the NON-DURABLE FALLBACK. The
  // durable arm resolves an exact direct_notification_display_outbox row, and
  // only the live runtime writes those, so a killed app can never take it. This
  // leg keeps the recipient alive and backgrounded, which is the only place the
  // arm can execute at all.
  test('android_durable_reaction_background_connected', () async {
    final file = _artifactFile('android_durable_reaction_background_connected');
    if (file == null) {
      fail(
        'TC-DURABLE-DIRECT-REACTION proof artifact is not configured. Capture '
        'the alive-connected durable reaction leg, then rerun with '
        '--dart-define=MKNOON_256_PROOF_DIR=<dir> or '
        '--dart-define=MKNOON_256_PROOF_ARTIFACT=<file>.',
      );
    }
    expect(await file.exists(), isTrue, reason: 'missing ${file.path}');

    final decoded = jsonDecode(await file.readAsString());
    expect(decoded, isA<Map<String, dynamic>>());
    final artifact = decoded as Map<String, dynamic>;
    expect(artifact['testCase'], 'TC-DURABLE-DIRECT-REACTION');
    expect(
      artifact['scenario'],
      'android_durable_reaction_background_connected',
    );
    expect(artifact['status'], 'passed');
    expect(_nonEmpty(artifact['capturedAt']), isTrue);

    final app = _object(artifact, 'app');
    expect(_nonEmpty(app['revision']), isTrue);
    expect(app['workingTreeCandidate'], isTrue);
    expect(_nonEmpty(app['apkSha256']), isTrue);

    final relay = _object(artifact, 'relay');
    expect(_nonEmpty(relay['revision']), isTrue);
    expect(_nonEmpty(relay['evidencePath']), isTrue);

    final reaction = _object(artifact, 'reaction');
    expect(_nonEmpty(reaction['eventId']), isTrue);
    expect(reaction['remoteType'], 'message_reaction');

    final observation = _object(artifact, 'observation');
    expect(
      observation['recipientProcessAliveBeforeReaction'],
      isTrue,
      reason:
          'the recipient must have been measured alive and backgrounded at the '
          'moment the reaction was driven, or the durable arm had no live '
          'runtime to have projected the event',
    );
    expect(
      observation['recipientProcessAbsentBeforeReaction'],
      isFalse,
      reason:
          'this is deliberately NOT a killed-path leg; a true here would mean '
          'the artifact and the scenario disagree about what was proven',
    );
    expect(observation['cardPresent'], isTrue);
    expect(observation['typedCopyRequired'], isTrue);
    expect(observation['genericNewMessageRejected'], isTrue);
    expect(observation['unrelatedCardsRejected'], isTrue);
    expect(observation['durableEffectRequired'], isTrue);
    expect(
      observation['durableEffectObserved'],
      isTrue,
      reason:
          'the recipient device must have logged PUSH_BACKGROUND_NOTIFICATION_'
          'SHOWN with durable: true and the direct_reaction producer',
    );
    expect(
      observation['durableEffectDisposition'],
      'osPosted',
      reason: 'a durable effect the OS did not post is not an alert',
    );
    expect(
      observation['durableEffectDeferralReasons'],
      isEmpty,
      reason:
          'exact_sql_authority_unavailable here means the arm deferred and the '
          'card came from the non-durable fallback, which is the killed-path '
          'outcome this leg exists to distinguish itself from',
    );
    expect(_nonEmpty(observation['durableEffectEvidencePath']), isTrue);
    expect(_nonEmpty(observation['title']), isTrue);
    expect(_nonEmpty(observation['body']), isTrue);
    expect(_nonEmpty(observation['tapRoute']), isTrue);

    final attribution = _object(artifact, 'sourceAttribution');
    expect(attribution['relayMatchedEvent'], isTrue);
    expect(attribution['providerEvidenceCaptured'], isTrue);
    expect(attribution['providerMatchedEvent'], isTrue);
    expect(attribution['recipientBackgroundPushObserved'], isTrue);
    expect(attribution['providerEvidenceSource'], 'recipient_background_push');
    expect(_nonEmpty(attribution['providerEvidencePath']), isTrue);
  });

  test('android_background_crypto_preflight', () async {
    final file = _artifactFile('android_background_crypto_preflight');
    if (file == null) {
      fail('TC-07 proof artifact is not configured.');
    }
    expect(await file.exists(), isTrue, reason: 'missing ${file.path}');

    final raw = await file.readAsString();
    final artifact = jsonDecode(raw) as Map<String, dynamic>;
    expect(artifact['testCase'], 'TC-07');
    expect(artifact['scenario'], 'android_background_crypto_preflight');
    expect(artifact['status'], 'passed');
    expect(_nonEmpty(artifact['capturedAt']), isTrue);

    final recipient = _object(artifact, 'recipient');
    expect(recipient['platform'], 'android');
    expect(recipient['activityAbsentBeforeFcm'], isTrue);
    expect(recipient['activityAbsentDuringCallback'], isTrue);

    final reaction = _object(artifact, 'reaction');
    expect(reaction['remoteType'], 'message_reaction');
    expect(reaction['eventIdSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(reaction['targetIdSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));

    final background = _object(artifact, 'background');
    expect(background['generatedPluginRegistration'], isTrue);
    expect(background['nativeSurface'], 'decryptMessage_only');
    expect(background['cryptoPluginCallObserved'], isTrue);
    expect(background['decryptSucceeded'], isTrue);
    expect(background['trustedActorTitle'], 'TC256 Alice');
    expect(background['semanticBody'], 'Reacted 👍 to your message');
    expect(background['matchingCards'], 1);

    final foreground = _object(artifact, 'foreground');
    expect(foreground['goEventCallbackObserved'], isTrue);
    expect(foreground['event'], 'node:startup_timing');
    expect(foreground['afterBackgroundDecrypt'], isTrue);

    final redaction = _object(artifact, 'redaction');
    expect(redaction.values, everyElement(isFalse));
    final cleanup = _object(artifact, 'cleanup');
    expect(cleanup['syntheticRowsRemoved'], isTrue);
    expect(cleanup['syntheticNotificationDismissed'], isTrue);
    expect(cleanup['syntheticClaimsRemoved'], isTrue);
    expect(cleanup['installedCandidateRestored'], isTrue);
    expect(cleanup['localBuildArtifactRestoredToPriorState'], isTrue);
    for (final forbidden in const [
      '"secretKey":',
      '"ciphertext":',
      '"fcmToken":',
      'recipient-secret',
    ]) {
      expect(raw, isNot(contains(forbidden)));
    }

    final evidence = File(artifact['evidencePath'] as String);
    expect(await evidence.exists(), isTrue);
    final evidenceText = await evidence.readAsString();
    expect(evidenceText, contains('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK'));
    expect(evidenceText, contains('cleanup_complete'));
    expect(evidenceText, contains('node:startup_timing'));
  });

  test('android_physical_recipient', () async {
    await _validateClosureArtifact('android_physical_recipient');
  });

  test('ios_physical_recipient', () async {
    await _validateClosureArtifact('ios_physical_recipient');
  });

  test('android_message_unread_lifecycle', () async {
    await _validateClosureArtifact('android_message_unread_lifecycle');
  });
}

Future<void> _validateClosureArtifact(String scenario) async {
  final file = _artifactFile(scenario);
  if (file == null) {
    fail('$scenario proof artifact is not configured.');
  }
  expect(await file.exists(), isTrue, reason: 'missing ${file.path}');

  final raw = await file.readAsString();
  final decoded = jsonDecode(raw);
  expect(decoded, isA<Map<String, dynamic>>());
  final artifact = decoded as Map<String, dynamic>;
  final contract = validatePlan256ArtifactContract(
    scenario: scenario,
    artifact: artifact,
    rawJson: raw,
  );
  expect(
    contract.errors,
    isEmpty,
    reason: 'invalid $scenario artifact:\n${contract.errors.join('\n')}',
  );

  final evidenceByKind = await _readAndVerifyEvidence(file, artifact);
  switch (scenario) {
    case 'android_physical_recipient':
      _expectEvidenceContains(evidenceByKind, 'relay_provider', const [
        'message_reaction',
        'event_id_sha256=',
      ]);
      _expectEvidenceContains(evidenceByKind, 'android_logcat', const [
        'PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK',
        'PUSH_ANDROID_DATA_DECRYPT_OK',
        'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
      ]);
      _expectEvidenceContains(evidenceByKind, 'notification_records', const [
        'Reacted ',
        ' to your message',
        'category=message',
      ]);
      _expectEvidenceContains(evidenceByKind, 'ui_automation', const [
        'conversation_rendered=true',
        'orbit_indicators=0',
      ]);
      _expectEvidenceContains(evidenceByKind, 'sqlcipher_state', const [
        'target_reaction_rows=1',
        'negative_reaction_rows=1',
        'reaction_created_message_rows=0',
        'unread_after_tap=0',
      ]);
    case 'ios_physical_recipient':
      _expectEvidenceContains(evidenceByKind, 'relay_provider', const [
        'message_reaction',
        'event_id_sha256=',
      ]);
      _expectEvidenceContains(evidenceByKind, 'apns_delivery', const [
        'mutable-content=1',
        'fallback_title=New reaction',
      ]);
      _expectEvidenceContains(evidenceByKind, 'nse_log', const [
        'REACTION_NSE_DECRYPT_OK',
        'same_peer_thread=true',
      ]);
      _expectEvidenceContains(evidenceByKind, 'xcuitest', const [
        'testReactionNotificationTap',
        'conversation_rendered=true',
      ]);
      _expectEvidenceContains(evidenceByKind, 'local_state', const [
        'reaction_rows=1',
        'reaction_created_message_rows=0',
        'unread_after_tap=0',
      ]);
    case 'android_message_unread_lifecycle':
      _expectEvidenceContains(evidenceByKind, 'relay_provider', const [
        'new_message',
        'message_id_sha256=',
      ]);
      _expectEvidenceContains(evidenceByKind, 'android_logcat', const [
        'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        'CONVERSATION_READ_COMMITTED',
      ]);
      _expectEvidenceContains(evidenceByKind, 'notification_records', const [
        'category=message',
        'replacement_observed=true',
      ]);
      _expectEvidenceContains(evidenceByKind, 'ui_automation', const [
        'orbit=0,1,1,2,0',
        'both_messages_visible=true',
        'orbit_indicators_after_return=0',
      ]);
      _expectEvidenceContains(evidenceByKind, 'sqlcipher_state', const [
        'unread=0,1,1,2,0',
        'read_commit_before_tap=false',
      ]);
  }
}

Future<Map<String, String>> _readAndVerifyEvidence(
  File artifactFile,
  Map<String, dynamic> artifact,
) async {
  final artifactDirectory = await artifactFile.parent.resolveSymbolicLinks();
  final values = artifact['evidence'] as List<dynamic>;
  final evidenceByKind = <String, String>{};
  for (final value in values) {
    final record = Map<String, dynamic>.from(value as Map);
    final rawPath = record['path'] as String;
    final candidate = File(rawPath).isAbsolute
        ? File(rawPath)
        : File('${artifactFile.parent.path}${Platform.pathSeparator}$rawPath');
    expect(await candidate.exists(), isTrue, reason: 'missing $rawPath');
    final resolvedPath = await candidate.resolveSymbolicLinks();
    expect(
      resolvedPath.startsWith('$artifactDirectory${Platform.pathSeparator}'),
      isTrue,
      reason: 'evidence must remain inside the artifact directory: $rawPath',
    );
    final bytes = await candidate.readAsBytes();
    expect(
      bytes.length,
      record['bytes'],
      reason: 'byte count mismatch $rawPath',
    );
    expect(
      sha256.convert(bytes).toString(),
      record['sha256'],
      reason: 'SHA-256 mismatch $rawPath',
    );
    final text = utf8.decode(bytes);
    for (final forbidden in const <String>[
      '"fcmToken":',
      '"apnsToken":',
      '"secretKey":',
      '"ciphertext":',
      '"senderPeerId":',
      '"recipientPeerId":',
    ]) {
      expect(
        text,
        isNot(contains(forbidden)),
        reason: '$rawPath is not redacted',
      );
    }
    evidenceByKind[record['kind'] as String] = text;
  }
  return evidenceByKind;
}

void _expectEvidenceContains(
  Map<String, String> evidenceByKind,
  String kind,
  List<String> markers,
) {
  final evidence = evidenceByKind[kind];
  expect(evidence, isNotNull, reason: 'missing evidence kind $kind');
  for (final marker in markers) {
    expect(evidence, contains(marker), reason: '$kind missing $marker');
  }
}

File? _artifactFile(String scenario) {
  if (_proofDir.trim().isNotEmpty) {
    final direct = File('$_proofDir${Platform.pathSeparator}$scenario.json');
    if (direct.existsSync()) return direct;
    return File(
      '$_proofDir${Platform.pathSeparator}$scenario'
      '${Platform.pathSeparator}$scenario.json',
    );
  }
  if (_proofArtifact.trim().isNotEmpty) {
    return File(_proofArtifact);
  }
  return null;
}

Map<String, dynamic> _object(Map<String, dynamic> parent, String key) {
  final value = parent[key];
  expect(value, isA<Map<String, dynamic>>(), reason: '$key must be an object');
  return value as Map<String, dynamic>;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;
