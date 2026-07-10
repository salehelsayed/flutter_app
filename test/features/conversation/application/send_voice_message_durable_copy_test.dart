import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

import 'send_chat_message_use_case_test.dart'
    show FakeP2PService, FakeMessageRepository;
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

/// Records every saved attachment for inspection (mirrors the local fake in
/// send_voice_message_use_case_test.dart).
class _RecordingMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> saved = [];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saved.add(attachment);
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => saved.where((a) => a.messageId == messageId).toList();

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => {};

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => const [];

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late _RecordingMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  const mlKemKey = 'test-recipient-mlkem-pub-key';

  final tempDir = Directory.systemTemp.createTempSync('voice_durable_test_');

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = _RecordingMediaAttachmentRepository();
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
        // The persisted attachment row must point at a durable owned copy
        // (media/<peer>/<blobId>.m4a), NOT the recorder temp, so it survives
        // OS temp eviction and never triggers a relay download for a blob that
        // was never uploaded.
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
          blobId: blobId,
        );

        expect(result, SendVoiceMessageResult.uploadFailed);

        expect(mediaAttachmentRepo.saved, isNotEmpty);
        final saved = mediaAttachmentRepo.saved.firstWhere(
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
        // Durable owned copy under the media dir — NOT the recorder temp.
        expect(saved.localPath, isNot(recording.filePath));
        expect(saved.localPath, contains('/media/'));
        expect(saved.localPath, endsWith('.m4a'));

        // The durable copy is a real on-disk file the retry path can re-upload
        // (retry checks File(localPath).existsSync() on the raw stored path).
        expect(File(saved.localPath!).existsSync(), isTrue);
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
        blobId: blobId,
      );

      final saved = mediaAttachmentRepo.saved.firstWhere((a) => a.id == blobId);
      final durablePath = saved.localPath!;

      // Simulate OS temp eviction.
      final temp = File(recording.filePath);
      if (temp.existsSync()) temp.deleteSync();

      // The durable copy is an independent owned file — untouched.
      expect(File(durablePath).existsSync(), isTrue);
      expect(durablePath, isNot(recording.filePath));
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
          blobId: 'voice-blob-ok-1',
        );

        expect(result, SendVoiceMessageResult.success);
        // The encrypted attachment from the upload pipeline is the persisted
        // one (carries encryption metadata).
        expect(
          mediaAttachmentRepo.saved.where((a) => a.encryptionKeyBase64 != null),
          isNotEmpty,
        );
      },
    );
  });
}
