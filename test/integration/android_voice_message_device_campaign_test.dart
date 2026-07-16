import 'dart:io';

import 'package:flutter_app/core/debug/android_voice_message_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_voice_message_device_campaign.dart';

const _artifactDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _voiceDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _sender() => <String, Object?>{
  'schema': androidVoiceMessageE2EEndpointResultSchema,
  'status': 'complete',
  'success': true,
  'scenario': androidVoiceMessageE2EScenario,
  'buildProfile': androidVoiceMessageE2EBuildProfile,
  'role': androidVoiceMessageSenderRole,
  'stepId': 'voice-sender-run-voice-1',
  'runId': 'run-voice-1',
  'nonce': 'nonce-sender-1',
  'sender': <String, Object?>{
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
  'transport': <String, Object?>{
    'realRelayMediaUpload': true,
    'senderCustodyAccepted': true,
    'usedFakeNetwork': false,
    'usedHostFileTransfer': false,
  },
};

Map<String, Object?> _receiver() => <String, Object?>{
  'schema': androidVoiceMessageE2EEndpointResultSchema,
  'status': 'complete',
  'success': true,
  'scenario': androidVoiceMessageE2EScenario,
  'buildProfile': androidVoiceMessageE2EBuildProfile,
  'role': androidVoiceMessageReceiverRole,
  'stepId': 'voice-receiver-run-voice-1',
  'runId': 'run-voice-1',
  'nonce': 'nonce-receiver-1',
  'receiver': <String, Object?>{
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
    'realMessageDelivery': true,
    'realRelayMediaDownload': true,
    'usedFakeNetwork': false,
    'usedHostFileTransfer': false,
  },
};

Map<String, Object?> _aggregate({
  Map<String, Object?>? sender,
  Map<String, Object?>? receiver,
}) => aggregateAndroidVoiceMessageEvidence(
  senderEndpoint: sender ?? _sender(),
  receiverEndpoint: receiver ?? _receiver(),
  runId: 'run-voice-1',
  senderNonce: 'nonce-sender-1',
  receiverNonce: 'nonce-receiver-1',
  artifactSha256: _artifactDigest,
  physicalDeviceId: 'pixel-physical',
  emulatorDeviceId: 'emulator-5554',
);

void main() {
  test(
    'aggregates two independent endpoint receipts into passing evidence',
    () {
      final proof = _aggregate();
      expect(proof['status'], 'passed');
      expect(
        (proof['sharedArtifact']! as Map<String, Object?>)['profileId'],
        'android.e2e.main',
      );
      expect(
        (proof['transport']!
            as Map<String, Object?>)['senderReceiverPeerMatch'],
        isTrue,
      );
    },
  );

  test('rejects stale endpoint nonce and mismatched exact voice bytes', () {
    final stale = _sender()..['nonce'] = 'nonce-stale';
    expect(() => _aggregate(sender: stale), throwsFormatException);

    final mismatch = _receiver();
    (mismatch['receiver']!
            as Map<String, Object?>)['downloadedPlaintextSha256'] =
        _artifactDigest;
    expect(() => _aggregate(receiver: mismatch), throwsFormatException);
  });

  test('rejects host file transfer and mismatched receiver identity', () {
    final hostTransfer = _receiver();
    (hostTransfer['transport']!
            as Map<String, Object?>)['usedHostFileTransfer'] =
        true;
    expect(() => _aggregate(receiver: hostTransfer), throwsFormatException);

    final wrongPeer = _receiver();
    (wrongPeer['receiver']! as Map<String, Object?>)['ownPeerIdSha256'] =
        _voiceDigest;
    expect(() => _aggregate(receiver: wrongPeer), throwsFormatException);
  });

  test(
    'host adapter consumes one guarded APK and contains no build invocation',
    () {
      final source = File(
        'integration_test/scripts/android_voice_message_device_campaign.dart',
      ).readAsStringSync();
      expect(source, contains('stateGuard.prepareFreshInstall('));
      expect(source, contains('artifact: artifact'));
      expect(source, contains('stateGuard.restoreAll()'));
      expect(source, isNot(contains("'pm', 'clear'")));
      expect(source, isNot(contains('flutter build')));
      expect(source, isNot(contains('flutter drive')));
      expect(source, contains('simsAndroidMainProfileId'));
    },
  );
}
