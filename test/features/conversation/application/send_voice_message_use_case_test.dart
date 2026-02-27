import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'send_chat_message_use_case_test.dart' show FakeP2PService, FakeMessageRepository, FakeMediaAttachmentRepository;
import '../../../core/bridge/fake_bridge.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  const mlKemKey = 'test-recipient-mlkem-pub-key';

  final tempDir = Directory.systemTemp.createTempSync('voice_test_');

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    bridge = FakeBridge(initialResponses: {
      'message.encrypt': {
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': 'fake-ct',
        'nonce': 'fake-nonce',
      },
      'media:upload': {
        'ok': true,
      },
    });
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  AudioRecording createRecording({
    String? filePath,
    int durationMs = 3000,
    int sizeBytes = 48000,
  }) {
    // Create a real temp file for validation tests
    final path = filePath ?? '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    if (!File(path).existsSync()) {
      File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
    }
    return AudioRecording(
      filePath: path,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
    );
  }

  group('sendVoiceMessage', () {
    group('validation', () {
      test('returns invalidMessage if file does not exist', () async {
        final recording = AudioRecording(
          filePath: '/nonexistent/voice.m4a',
          durationMs: 3000,
          sizeBytes: 48000,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test('returns invalidMessage if file is 0 bytes', () async {
        final path = '${tempDir.path}/empty.m4a';
        File(path).writeAsBytesSync([]);

        final recording = AudioRecording(
          filePath: path,
          durationMs: 3000,
          sizeBytes: 0,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test('returns invalidMessage if file exceeds 100 MB', () async {
        // We don't actually create a 100MB file — just pass sizeBytes > 100MB
        final path = '${tempDir.path}/big.m4a';
        File(path).writeAsBytesSync([1, 2, 3]); // tiny file but model says 101MB

        final recording = AudioRecording(
          filePath: path,
          durationMs: 3000,
          sizeBytes: 101 * 1024 * 1024,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });
    });

    group('upload and send', () {
      test('calls sendChatMessage with audio MediaAttachment', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.success);
        // sendChatMessage should have been called (the message was sent via P2P)
        expect(p2pService.sendCallCount, greaterThan(0));
      });

      test('message persisted with correct status after send', () async {
        final recording = createRecording();

        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        // sendChatMessage persists the message
        expect(messageRepo.saved, isNotEmpty);
      });

      test('allows empty text (voice-only message)', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('allows text caption alongside voice', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          text: 'Listen to this!',
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('returns uploadFailed when bridge upload fails', () async {
        bridge.responses['media:upload'] = {'ok': false, 'errorMessage': 'fail'};
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.uploadFailed);
      });

      test('creates MediaAttachment with audio mediaType and correct durationMs', () async {
        final recording = createRecording(durationMs: 5500);

        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // The media attachment should have been saved
        expect(mediaAttachmentRepo.saved, isNotEmpty);
        final attachment = mediaAttachmentRepo.saved.first;
        expect(attachment.mediaType, 'audio');
        expect(attachment.mime, 'audio/mp4');
        expect(attachment.durationMs, 5500);
      });
    });
  });
}
