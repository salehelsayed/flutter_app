import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

import 'send_chat_message_use_case_test.dart'
    show FakeP2PService, FakeMessageRepository;
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  const mlKemKey = 'test-recipient-mlkem-pub-key';

  final tempDir = Directory.systemTemp.createTempSync('voice_durable_test_');

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'fake-kem',
          'ciphertext': 'fake-ct',
          'nonce': 'fake-nonce',
        },
        'media:upload': {'ok': true},
      },
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  AudioRecording createRecording() {
    final path =
        '${tempDir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    File(path).writeAsBytesSync(List<int>.filled(48000, 7));
    return AudioRecording(filePath: path, durationMs: 3000, sizeBytes: 48000);
  }

  group('sendVoiceMessage durable copy on upload failure', () {
    test(
      'relay upload failure persists a durable owned copy, not the temp path',
      () async {
        // 117 Session 4 / finding #3c: when the relay upload fails (e.g. a
        // LAN-only delivery), the sender's own voice note must remain playable.
        // The persisted attachment row must point at retry staging
        // (pending_uploads/<message>/<blobId>.m4a), NOT the recorder temp, so
        // it survives OS temp eviction without pretending that a relay-backed
        // media copy already exists.
        bridge.responses['media:upload'] = {
          'ok': false,
          'errorMessage': 'relay unreachable',
        };
        const blobId = 'voice-blob-durable-1';
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
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          messageId: 'msg-durable-1',
          preassignedMessageIdIsFresh: true,
          blobId: blobId,
        );

        expect(result, SendVoiceMessageResult.uploadFailed);

        expect(mediaAttachmentRepo.allSavedAttachments, isNotEmpty);
        final saved = mediaAttachmentRepo.allSavedAttachments.firstWhere(
          (a) => a.id == blobId,
        );
        // MUST be 'upload_pending', NOT 'done': 'done' is the relay-blob-exists
        // signal that retryIncompleteUploads reuses (skipping re-upload). Since
        // the upload just failed, marking 'done' would make a retry reference a
        // never-uploaded blob → permanent "Media unavailable" on the recipient.
        expect(saved.downloadStatus, 'upload_pending');
        expect(saved.mediaType, 'audio');
        expect(saved.messageId, 'msg-durable-1');
        expect(saved.localPath, isNotNull);
        // Container-safe retry staging — NOT the recorder temp and not a
        // forged successful `media/` copy.
        expect(saved.localPath, isNot(recording.filePath));
        expect(saved.localPath, 'pending_uploads/msg-durable-1/$blobId.m4a');
        expect(saved.localPath, endsWith('.m4a'));

        // Stored paths are resolved through MediaFileManager so the row stays
        // valid when the application container moves.
        final resolvedPath = await mediaFileManager.resolveStoredPath(
          saved.localPath!,
        );
        expect(File(resolvedPath).existsSync(), isTrue);
      },
    );

    test('durable copy survives deletion of the recorder temp file', () async {
      // The whole point: deleting the OS temp (eviction / container
      // rotation) must NOT lose the sender's voice note — the durable copy
      // is an independent file under the owned media dir.
      bridge.responses['media:upload'] = {'ok': false};
      const blobId = 'voice-blob-survives-1';
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
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        messageId: 'msg-survives-1',
        preassignedMessageIdIsFresh: true,
        blobId: blobId,
      );

      final saved = mediaAttachmentRepo.allSavedAttachments.firstWhere(
        (a) => a.id == blobId,
      );
      final durablePath = await mediaFileManager.resolveStoredPath(
        saved.localPath!,
      );

      // Simulate OS temp eviction.
      final temp = File(recording.filePath);
      if (temp.existsSync()) temp.deleteSync();

      // The durable copy is an independent owned file — untouched.
      expect(File(durablePath).existsSync(), isTrue);
      expect(durablePath, isNot(recording.filePath));
      expect(saved.localPath, 'pending_uploads/msg-survives-1/$blobId.m4a');
    });

    test(
      'no durable row is forced on the success path (upload owns durability)',
      () async {
        // On success, uploadMedia + sendChatMessage already persist the
        // encrypted, durable attachment. The failure-path durable copy must
        // not double-persist a plaintext row.
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
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          messageId: 'msg-ok-1',
          preassignedMessageIdIsFresh: true,
          blobId: 'voice-blob-ok-1',
        );

        expect(result, SendVoiceMessageResult.success);
        // The encrypted attachment from the upload pipeline is the persisted
        // one (carries encryption metadata).
        final committed = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-ok-1',
          owner: MediaOwnerLane.direct,
        );
        expect(
          committed.where((a) => a.encryptionKeyBase64 != null),
          isNotEmpty,
        );
      },
    );
  });
}
