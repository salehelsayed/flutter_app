import 'package:flutter_app/core/debug/android_voice_message_e2e.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _config({String role = androidVoiceMessageSenderRole}) =>
    <String, dynamic>{
      'schema': androidVoiceMessageE2ERequestSchema,
      'transport_action': androidVoiceMessageE2EAction,
      'scenario': androidVoiceMessageE2EScenario,
      'role': role,
      'runId': 'run-voice-1',
      'nonce': 'nonce-voice-1',
      'stepId': 'voice-$role-run-voice-1',
      'contactPeerId': 'peer-contact-1',
      'messageId': 'message-voice-1',
      'attachmentId': 'attachment-voice-1',
      'timeoutMs': 90000,
    };

void main() {
  test('parses exact sender and receiver runtime tuples', () {
    final sender = AndroidVoiceMessageE2ERequest.fromConfig(_config());
    expect(sender.isSender, isTrue);
    expect(sender.timeout, const Duration(seconds: 90));
    expect(sender.messageId, 'message-voice-1');
    expect(sender.attachmentId, 'attachment-voice-1');

    final receiver = AndroidVoiceMessageE2ERequest.fromConfig(
      _config(role: androidVoiceMessageReceiverRole),
    );
    expect(receiver.isSender, isFalse);
    expect(receiver.role, androidVoiceMessageReceiverRole);
  });

  test('rejects stale schema action scenario and step bindings', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['schema'] = 'stale',
      (value) => value['transport_action'] = 'chat',
      (value) => value['scenario'] = 'android.other',
      (value) => value['stepId'] = 'voice-sender-stale',
      (value) => value['nonce'] = '../unsafe',
    ]) {
      final value = _config();
      mutation(value);
      expect(
        () => AndroidVoiceMessageE2ERequest.fromConfig(value),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid role and unsafe identity tuple tokens', () {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value['role'] = 'primary',
      (value) => value['contactPeerId'] = '',
      (value) => value['messageId'] = 'message/escape',
      (value) => value['attachmentId'] = 'attachment with space',
    ]) {
      final value = _config();
      mutation(value);
      expect(
        () => AndroidVoiceMessageE2ERequest.fromConfig(value),
        throwsFormatException,
      );
    }
  });

  test('clamps endpoint timeout to the bounded device window', () {
    final low = _config()..['timeoutMs'] = 1;
    final high = _config()..['timeoutMs'] = 999999;
    expect(
      AndroidVoiceMessageE2ERequest.fromConfig(low).timeout,
      const Duration(seconds: 30),
    );
    expect(
      AndroidVoiceMessageE2ERequest.fromConfig(high).timeout,
      const Duration(minutes: 3),
    );
  });

  test(
    'failure receipt preserves only the bound tuple and safe error type',
    () {
      final receipt = androidVoiceMessageE2EFailureReceipt(
        config: _config(role: androidVoiceMessageReceiverRole),
        error: StateError('secret peer and audio material'),
      );

      expect(receipt['schema'], androidVoiceMessageE2EEndpointResultSchema);
      expect(receipt['status'], 'failed');
      expect(receipt['success'], isFalse);
      expect(receipt['role'], androidVoiceMessageReceiverRole);
      expect(receipt['runId'], 'run-voice-1');
      expect(receipt['nonce'], 'nonce-voice-1');
      expect(receipt['errorType'], 'StateError');
      expect(receipt.toString(), isNot(contains('secret peer')));
    },
  );

  test(
    'receiver reloads the exact row after a competing download race',
    () async {
      var persisted = _voiceAttachment(downloadStatus: 'pending');
      final downloadInputs = <MediaAttachment>[];

      final result = await waitForAndroidVoiceMessageDownloadForE2E(
        messageId: persisted.messageId,
        attachmentId: persisted.id,
        loadAttachments: () async => <MediaAttachment>[persisted],
        downloadAttachment: (attachment) async {
          downloadInputs.add(attachment);
          if (downloadInputs.length == 1) {
            persisted = persisted.copyWith(downloadStatus: 'failed');
            return null;
          }
          persisted = attachment.copyWith(
            downloadStatus: 'done',
            localPath: 'media/exact-voice.m4a',
          );
          return persisted;
        },
        resolveStoredPath: (path) async => '/absolute/$path',
        fileExists: (_) async => true,
        pollInterval: Duration.zero,
        timeout: const Duration(seconds: 1),
      );

      expect(downloadInputs, hasLength(2));
      expect(downloadInputs.first.downloadStatus, 'pending');
      expect(downloadInputs.last.downloadStatus, 'failed');
      expect(result.attachment.downloadStatus, 'done');
      expect(result.localPath, '/absolute/media/exact-voice.m4a');
    },
  );

  test(
    'receiver accepts exact durable bytes completed by the competing path',
    () async {
      var persisted = _voiceAttachment(downloadStatus: 'pending');
      var downloadCalls = 0;

      final result = await waitForAndroidVoiceMessageDownloadForE2E(
        messageId: persisted.messageId,
        attachmentId: persisted.id,
        loadAttachments: () async => <MediaAttachment>[persisted],
        downloadAttachment: (_) async {
          downloadCalls++;
          persisted = persisted.copyWith(
            downloadStatus: 'done',
            localPath: 'media/concurrent-voice.m4a',
          );
          return null;
        },
        resolveStoredPath: (path) async => '/absolute/$path',
        fileExists: (_) async => true,
        pollInterval: Duration.zero,
        timeout: const Duration(seconds: 1),
      );

      expect(downloadCalls, 1);
      expect(result.attachment.id, 'attachment-voice-1');
      expect(result.localPath, '/absolute/media/concurrent-voice.m4a');
    },
  );

  test('receiver rejects duplicate exact attachment rows', () async {
    final attachment = _voiceAttachment(downloadStatus: 'pending');

    expect(
      () => waitForAndroidVoiceMessageDownloadForE2E(
        messageId: attachment.messageId,
        attachmentId: attachment.id,
        loadAttachments: () async => <MediaAttachment>[attachment, attachment],
        downloadAttachment: (_) async => null,
        resolveStoredPath: (path) async => path,
        fileExists: (_) async => false,
        pollInterval: Duration.zero,
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
  });
}

MediaAttachment _voiceAttachment({required String downloadStatus}) =>
    MediaAttachment(
      id: 'attachment-voice-1',
      messageId: 'message-voice-1',
      mime: 'audio/mp4',
      size: 48000,
      mediaType: 'audio',
      durationMs: 2000,
      localPath: null,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-15T00:00:00.000Z',
    );
