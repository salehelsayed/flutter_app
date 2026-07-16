import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_voice_message_evidence.dart';
import '../../integration_test/support/sims_runtime_protocol.dart';
import '../../tool/sims/artifact_evidence.dart';

const _artifactDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _voiceDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

SimsRuntimeInvocation _roleInvocation(String role) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: simsAndroidMainProfileId,
  scenarioId: simsAndroidVoiceMessageScenarioId,
  role: role,
  runId: 'run-voice-1',
  nonce: 'nonce-voice-1',
  values: <String, Object?>{
    'targetId': role == simsVoiceMessageSenderRole
        ? 'pixel-physical'
        : 'emulator-5554',
    'counterpartTargetId': role == simsVoiceMessageSenderRole
        ? 'emulator-5554'
        : 'pixel-physical',
    'targetKind': role == simsVoiceMessageSenderRole ? 'physical' : 'emulator',
    'buildArtifactSha256': _artifactDigest,
    'campaignId': 'voice-campaign-1',
  },
);

Map<String, Object?> _evidence() => <String, Object?>{
  'schema': androidVoiceMessageEvidenceSchema,
  'scenario': simsAndroidVoiceMessageScenarioId,
  'status': 'passed',
  'platform': 'android',
  'runtimeDispatched': true,
  'runId': 'run-voice-1',
  'sharedArtifact': <String, Object?>{
    'profileId': simsAndroidMainProfileId,
    'sha256': _artifactDigest,
  },
  'deviceIds': <String>['pixel-physical', 'emulator-5554'],
  'targetKinds': <String, Object?>{
    'sender': 'physical',
    'receiver': 'emulator',
  },
  'sender': <String, Object?>{
    'role': simsVoiceMessageSenderRole,
    'deviceId': 'pixel-physical',
    'permissionPregranted': true,
    'realRecordPlugin': true,
    'mime': 'audio/mp4',
    'recordedSizeBytes': 48000,
    'recordedDurationMs': 2100,
    'recordedPlaintextSha256': _voiceDigest,
    'productionSendVoiceMessage': true,
    'productionGoBridge': true,
    'sendResult': 'success',
    'messageId': 'message-voice-1',
    'attachmentId': 'attachment-voice-1',
    'receiverPeerIdSha256': _artifactDigest,
    'messageStatus': 'delivered',
    'messageTransport': 'relay',
    'temporaryRecordingDeleted': true,
  },
  'receiver': <String, Object?>{
    'role': simsVoiceMessageReceiverRole,
    'deviceId': 'emulator-5554',
    'ownPeerIdSha256': _artifactDigest,
    'productionIncomingListener': true,
    'productionGoBridge': true,
    'messagePersisted': true,
    'realMediaDownload': true,
    'downloadStatus': 'done',
    'messageId': 'message-voice-1',
    'attachmentId': 'attachment-voice-1',
    'downloadedSizeBytes': 48000,
    'downloadedPlaintextSha256': _voiceDigest,
    'realAudioPlayerPlugin': true,
    'playbackStarted': true,
    'playbackProgressObserved': true,
    'playbackCompleted': true,
    'playbackStopped': true,
    'playbackDurationMs': 2050,
    'durableAttachmentRetained': true,
  },
  'transport': <String, Object?>{
    'realRelayMediaUpload': true,
    'senderCustodyAccepted': true,
    'realMessageDelivery': true,
    'realRelayMediaDownload': true,
    'senderReceiverPeerMatch': true,
    'usedFakeNetwork': false,
    'usedHostFileTransfer': false,
  },
  'assertionsAttempted': 1,
};

void main() {
  test('runtime roles bind the physical sender and emulator receiver', () {
    expect(
      validateAndroidVoiceMessageRoleInvocation(
        _roleInvocation(simsVoiceMessageSenderRole),
      ).ok,
      isTrue,
    );
    expect(
      validateAndroidVoiceMessageRoleInvocation(
        _roleInvocation(simsVoiceMessageReceiverRole),
      ).ok,
      isTrue,
    );

    final wrongTopology = _roleInvocation(simsVoiceMessageSenderRole).copyWith(
      values: <String, Object?>{
        ..._roleInvocation(simsVoiceMessageSenderRole).values,
        'targetKind': 'emulator',
      },
    );
    expect(
      validateAndroidVoiceMessageRoleInvocation(wrongTopology).ok,
      isFalse,
    );
  });

  test('full real-stack record send receive and playback evidence passes', () {
    expect(validateAndroidVoiceMessageEvidence(_evidence()).ok, isTrue);
  });

  test('voice result is durable and bound to validateVoiceMessageArtifact', () {
    final directory = Directory.systemTemp.createTempSync(
      'sims-voice-evidence-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final evidence = writeSimsArtifactEvidenceSync(
      directory: directory,
      capabilityId: simsAndroidVoiceMessageScenarioId,
      validatorIds: const <String>[androidVoiceMessageArtifactValidatorId],
      payload: androidVoiceMessageDurablePayload(_evidence()),
    );

    final durableJson = jsonDecode(File(evidence.path).readAsStringSync());
    expect(durableJson, isA<Map>());
    expect(
      validateAndroidVoiceMessageDurableArtifact(
        (durableJson as Map).map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        ),
      ).ok,
      isTrue,
    );

    expect(
      auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>[
          androidVoiceMessageArtifactValidatorId,
        ],
      ).isValid,
      isTrue,
    );
    File(evidence.path).writeAsStringSync('tampered\n');
    expect(
      auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>[
          androidVoiceMessageArtifactValidatorId,
        ],
      ).isValid,
      isFalse,
    );
  });

  test(
    'fake transport, byte mismatch, or incomplete playback fails closed',
    () {
      final fakeTransport = _evidence();
      (fakeTransport['transport']! as Map<String, Object?>)['usedFakeNetwork'] =
          true;
      expect(validateAndroidVoiceMessageEvidence(fakeTransport).ok, isFalse);

      final byteMismatch = _evidence();
      (byteMismatch['receiver']!
              as Map<String, Object?>)['downloadedPlaintextSha256'] =
          _artifactDigest;
      expect(validateAndroidVoiceMessageEvidence(byteMismatch).ok, isFalse);

      final noPlayback = _evidence();
      (noPlayback['receiver']! as Map<String, Object?>)['playbackCompleted'] =
          false;
      expect(validateAndroidVoiceMessageEvidence(noPlayback).ok, isFalse);

      final noProgress = _evidence();
      (noProgress['receiver']!
              as Map<String, Object?>)['playbackProgressObserved'] =
          false;
      expect(validateAndroidVoiceMessageEvidence(noProgress).ok, isFalse);

      final notStopped = _evidence();
      (notStopped['receiver']! as Map<String, Object?>)['playbackStopped'] =
          false;
      expect(validateAndroidVoiceMessageEvidence(notStopped).ok, isFalse);
    },
  );

  test('durable evidence rejects raw audio and secret material', () {
    for (final forbidden in <String>[
      'rawAudio',
      'audioBase64',
      'encryptionKey',
      'privateKey',
      'mlKemSecret',
    ]) {
      final artifact = _evidence();
      (artifact['sender']! as Map<String, Object?>)[forbidden] = 'secret';
      expect(
        validateAndroidVoiceMessageEvidence(artifact).ok,
        isFalse,
        reason: forbidden,
      );
    }
  });
}
