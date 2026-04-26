import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/bridge/fake_bridge.dart';

// ---------------------------------------------------------------------------
// Test-local FakeMediaAttachmentRepository
// ---------------------------------------------------------------------------
class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> _attachments = [];

  // Call tracking
  int getAttachmentsForMessageCallCount = 0;
  int saveAttachmentCallCount = 0;
  String? lastQueriedMessageId;

  /// Seed attachments for a specific message. Can be called multiple times
  /// for different messages.
  void seedAttachments({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) {
    for (final a in attachments) {
      _attachments.add(a.copyWith(messageId: messageId));
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    getAttachmentsForMessageCallCount++;
    lastQueriedMessageId = messageId;
    return _attachments.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    saveAttachmentCallCount++;
    final idx = _attachments.indexWhere((a) => a.id == attachment.id);
    if (idx >= 0) {
      _attachments[idx] = attachment;
    } else {
      _attachments.add(attachment);
    }
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    final result = <String, List<MediaAttachment>>{};
    for (final messageId in messageIds) {
      final attachments = await getAttachmentsForMessage(messageId);
      if (attachments.isNotEmpty) {
        result[messageId] = attachments;
      }
    }
    return result;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async {
    var count = 0;
    for (var i = 0; i < _attachments.length; i++) {
      final attachment = _attachments[i];
      if (attachment.messageId == messageId &&
          attachment.downloadStatus == 'upload_pending') {
        _attachments[i] = attachment.copyWith(downloadStatus: 'upload_failed');
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => [];

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------
const _testTs = '2026-01-01T00:00:00.000Z';

ConversationMessage _makeFailedMessage({
  String id = 'msg-failed-media-001',
  String contactPeerId = 'peer-bob',
  String text = 'Check this photo',
  String? wireEnvelope,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: _testTs,
    status: 'failed',
    isIncoming: false,
    createdAt: _testTs,
    wireEnvelope: wireEnvelope,
  );
}

MediaAttachment _makeDoneAttachment({
  String id = 'blob-uploaded-001',
  String messageId = 'msg-failed-media-001',
  String mime = 'image/jpeg',
  int size = 102400,
  String mediaType = 'image',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: mediaType,
    downloadStatus: 'done',
    createdAt: _testTs,
    localPath: '/tmp/photo.jpg',
  );
}

MediaAttachment _makeUploadPendingAttachment({
  String id = 'placeholder-uuid-001',
  String messageId = 'msg-failed-media-001',
  String mime = 'image/jpeg',
  int size = 102400,
  String mediaType = 'image',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: mediaType,
    downloadStatus: 'upload_pending',
    createdAt: _testTs,
    localPath: '/tmp/photo_pending.jpg',
  );
}

void main() {
  late FakeMessageRepository messageRepo;
  late _FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  setUp(() {
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = _FakeMediaAttachmentRepository();
    identityRepo = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          privateKey: 'sk-alice',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          createdAt: _testTs,
          updatedAt: _testTs,
        ),
      );
    contactRepo = FakeContactRepository()
      ..seed([
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Bob',
          signature: 'sig',
          scannedAt: _testTs,
          mlKemPublicKey: 'mlkem-peer-bob',
        ),
      ]);
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-alice',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
      storeInInboxResult: true,
    );
    bridge = PassthroughCryptoBridge();
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('retryFailedMessages -- media-aware retry', () {
    // ------------------------------------------------------------------
    // C.1-TEST-1: retryFailedMessages queries mediaAttachmentRepo before
    //             calling sendChatMessage
    // ------------------------------------------------------------------
    test(
      'queries mediaAttachmentRepo.getAttachmentsForMessage before re-sending',
      () async {
        final msg = _makeFailedMessage();
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg.id,
          attachments: [_makeDoneAttachment(messageId: msg.id)],
        );

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // One query resolves retry attachments, and the successful resend
        // re-queries once more before clearing stale upload_pending rows.
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 2);
        expect(mediaAttachmentRepo.lastQueriedMessageId, msg.id);
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-2: done attachments are passed to sendChatMessage
    // ------------------------------------------------------------------
    test('passes done attachments to sendChatMessage on retry', () async {
      final msg = _makeFailedMessage();
      final doneAttachment = _makeDoneAttachment(messageId: msg.id);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seedAttachments(
        messageId: msg.id,
        attachments: [doneAttachment],
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(count, 1);

      // The retried message was sent via inbox fallback; verify the wire
      // content includes the attachment id (sendChatMessage serializes
      // media into the MessagePayload -> wire JSON).
      expect(p2pService.lastStoreInInboxMessage, isNotNull);
      expect(p2pService.lastStoreInInboxMessage!, contains(doneAttachment.id));
    });

    // ------------------------------------------------------------------
    // C.1-TEST-3: text-only message retries with empty attachment list
    //             when no attachment rows exist
    // ------------------------------------------------------------------
    test(
      'retries text-only message with mediaAttachments=[] when no attachments in DB',
      () async {
        final msg = _makeFailedMessage(text: 'Just text, no media');
        messageRepo.seed([msg]);
        // No attachments seeded in mediaAttachmentRepo

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(count, 1);
        // Queried but found nothing
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 1);

        // Message was still sent (text-only)
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('Just text, no media'),
        );
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-4: mixed done+upload_pending attachments route to
    //             re-upload branch (Part F). Without local files the
    //             re-upload fails and the message is skipped (left as
    //             failed for the next retry cycle).
    // ------------------------------------------------------------------
    test(
      'filters out upload_pending attachments -- mixed state skips message when re-upload cannot find files',
      () async {
        final msg = _makeFailedMessage();
        final doneAttachment = _makeDoneAttachment(
          id: 'blob-done-001',
          messageId: msg.id,
        );
        final pendingAttachment = _makeUploadPendingAttachment(
          id: 'placeholder-pending-001',
          messageId: msg.id,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg.id,
          attachments: [doneAttachment, pendingAttachment],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Message skipped because re-upload branch can't find local files
        // for the pending attachment. The message stays 'failed' for the
        // next retry after the upload completes.
        expect(count, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-5: voice message with text='' and done attachment passes
    //             the empty-text guard because hasAttachments=true
    // ------------------------------------------------------------------
    test(
      'voice message with empty text and done attachment retries successfully',
      () async {
        final voiceMsg = _makeFailedMessage(id: 'msg-voice-001', text: '');
        final voiceAttachment = _makeDoneAttachment(
          id: 'blob-voice-001',
          messageId: voiceMsg.id,
          mime: 'audio/m4a',
          mediaType: 'audio',
          size: 48000,
        );
        messageRepo.seed([voiceMsg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: voiceMsg.id,
          attachments: [voiceAttachment],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Must succeed -- sendChatMessage allows empty text when hasAttachments
        expect(count, 1);
        expect(p2pService.lastStoreInInboxMessage!, contains('blob-voice-001'));
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-6:      legacy callers without mediaAttachmentRepo send
    //                  text-only (no crash, media silently dropped)
    // ------------------------------------------------------------------
    test(
      'retryFailedMessages without mediaAttachmentRepo sends text-only for media message',
      () async {
        final msg = _makeFailedMessage(text: 'Photo attached');
        messageRepo.seed([msg]);
        // Attachments exist in the hypothetical DB but mediaAttachmentRepo
        // is not passed -- legacy caller path.

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          // mediaAttachmentRepo: NOT passed
        );

        expect(count, 1);
        // Message was sent but without media (text-only)
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(p2pService.lastStoreInInboxMessage!, contains('Photo attached'));
        // mediaAttachmentRepo was never queried
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-7:     multiple failed messages with mixed media states
    // ------------------------------------------------------------------
    test(
      'retries multiple messages: one with media, one text-only, one with only pending attachments',
      () async {
        // Message 1: has done attachments
        final msg1 = _makeFailedMessage(
          id: 'msg-with-media',
          text: 'Photo msg',
        );
        final att1 = _makeDoneAttachment(
          id: 'blob-img-001',
          messageId: 'msg-with-media',
        );

        // Message 2: text-only, no attachments in DB
        final msg2 = _makeFailedMessage(id: 'msg-text-only', text: 'Just text');

        // Message 3: only upload_pending attachments (Part F territory)
        final msg3 = _makeFailedMessage(
          id: 'msg-pending-only',
          text: 'Pending upload',
        );
        final att3 = _makeUploadPendingAttachment(
          id: 'placeholder-003',
          messageId: 'msg-pending-only',
        );

        messageRepo.seed([msg1, msg2, msg3]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg1.id,
          attachments: [att1],
        );
        mediaAttachmentRepo.seedAttachments(
          messageId: msg3.id,
          attachments: [att3],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // msg1 (done attachments) → sent, msg2 (text-only) → sent,
        // msg3 (only pending) → skipped (re-upload branch, no local files)
        expect(count, 2);
        // msg1 is queried twice (retry resolution + resend persistence),
        // msg2 once, and msg3 once before the skip path.
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 4);
      },
    );

    test('retryFailedMessage only retries the requested failed row', () async {
      final target = _makeFailedMessage(
        id: 'msg-targeted-media',
        text: 'Retry only me',
      );
      final untouched = _makeFailedMessage(
        id: 'msg-untouched-media',
        text: 'Leave me failed',
      );
      messageRepo.seed([target, untouched]);
      mediaAttachmentRepo.seedAttachments(
        messageId: target.id,
        attachments: [_makeDoneAttachment(messageId: target.id)],
      );
      mediaAttachmentRepo.seedAttachments(
        messageId: untouched.id,
        attachments: [_makeDoneAttachment(messageId: untouched.id)],
      );

      final count = await retryFailedMessage(
        messageId: target.id,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(count, 1);
      expect(p2pService.lastStoreInInboxMessage, contains('Retry only me'));
      expect((await messageRepo.getMessage(untouched.id))!.status, 'failed');
      expect(mediaAttachmentRepo.lastQueriedMessageId, target.id);
    });
  });
}
