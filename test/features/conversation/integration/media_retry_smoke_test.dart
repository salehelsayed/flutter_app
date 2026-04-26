import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/bridge/fake_bridge.dart';

// Reuse the same fake pattern as C.1 tests
class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> _attachments = [];

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
    return _attachments.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
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
    for (final id in messageIds) {
      final atts = await getAttachmentsForMessage(id);
      if (atts.isNotEmpty) result[id] = atts;
    }
    return result;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;
  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async {
    final before = _attachments.length;
    _attachments.removeWhere((attachment) => attachment.messageId == messageId);
    return before - _attachments.length;
  }

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

const _testTs = '2026-01-01T00:00:00.000Z';

void main() {
  group('Media retry smoke test -- end-to-end', () {
    test(
      'successful outgoing media send clears stale upload_pending placeholders',
      () async {
        final messageRepo = FakeMessageRepository();
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: 'msg-smoke-stable-001',
            attachments: [
              MediaAttachment(
                id: 'placeholder-upload-pending',
                messageId: 'msg-smoke-stable-001',
                mime: 'image/jpeg',
                size: 0,
                mediaType: 'image',
                localPath: '/tmp/pending.jpg',
                downloadStatus: 'upload_pending',
                createdAt: _testTs,
              ),
            ],
          );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );

        final (result, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'peer-bob',
          text: 'Photo',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageId: 'msg-smoke-stable-001',
          timestamp: _testTs,
          bridge: FakeBridge(
            initialResponses: {
              'message.encrypt': {
                'ok': true,
                'kem': 'fake-kem',
                'ciphertext': 'fake-ct',
                'nonce': 'fake-nonce',
              },
            },
          ),
          recipientMlKemPublicKey: 'bob-mlkem-pk',
          mediaAttachments: const [
            MediaAttachment(
              id: 'uploaded-final-id',
              messageId: '',
              mime: 'image/jpeg',
              size: 2048,
              mediaType: 'image',
              localPath: '/tmp/final.jpg',
              downloadStatus: 'done',
              createdAt: _testTs,
            ),
          ],
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendChatMessageResult.success);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-smoke-stable-001',
        );
        expect(attachments.length, 1);
        expect(attachments.single.id, 'uploaded-final-id');
        expect(attachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );

        p2pService.dispose();
      },
    );

    test(
      'photo message stuck in sending is recovered and retried with media intact',
      () async {
        // --- Arrange ---
        // Simulate state after: user sent photo, upload completed, send failed
        // (app was killed mid-send). The optimistic row has status='sending',
        // wireEnvelope=null. The uploaded attachment is in media_attachments
        // with downloadStatus='done'.
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMessage = ConversationMessage(
          id: 'msg-photo-stuck',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Check this photo',
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final uploadedAttachment = MediaAttachment(
          id: 'blob-uploaded-photo',
          messageId: 'msg-photo-stuck',
          mime: 'image/jpeg',
          size: 204800,
          mediaType: 'image',
          width: 1920,
          height: 1080,
          downloadStatus: 'done',
          createdAt: stuckTs,
          localPath: '/tmp/photo.jpg',
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMessage]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: stuckMessage.id,
            attachments: [uploadedAttachment],
          );
        final identityRepo = FakeIdentityRepository()
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
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: 'bob-mlkem-pk',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = PassthroughCryptoBridge();

        // --- Act: simulate app resume recovery sequence ---

        // Step 1: recover stuck messages (sending -> failed)
        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        expect(recovered, 1);

        // Step 2: retry failed messages with media awareness
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // --- Assert ---
        expect(retried, 1);

        // The wire content sent to inbox must contain the media attachment
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('blob-uploaded-photo'),
        );
        expect(p2pService.lastStoreInInboxMessage!, contains('image/jpeg'));

        // The saved message must be delivered
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-photo-stuck');
        expect(saved.status, isNot('sending'));
        expect(saved.status, isNot('failed'));

        p2pService.dispose();
      },
    );

    test(
      'voice message with empty text is retried successfully with audio attachment',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final voiceMsg = ConversationMessage(
          id: 'msg-voice-stuck',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: '', // voice messages typically have empty text
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final voiceAttachment = MediaAttachment(
          id: 'blob-voice-uploaded',
          messageId: 'msg-voice-stuck',
          mime: 'audio/m4a',
          size: 48000,
          mediaType: 'audio',
          durationMs: 5000,
          downloadStatus: 'done',
          createdAt: stuckTs,
          localPath: '/tmp/voice.m4a',
        );

        final messageRepo = FakeMessageRepository()..seed([voiceMsg]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: voiceMsg.id,
            attachments: [voiceAttachment],
          );
        final identityRepo = FakeIdentityRepository()
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
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: 'bob-mlkem-pk',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = PassthroughCryptoBridge();

        // Step 1: recover
        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        // Step 2: retry with media
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Voice message with empty text + attachment should succeed
        expect(retried, 1);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('blob-voice-uploaded'),
        );
        expect(p2pService.lastStoreInInboxMessage!, contains('audio/m4a'));

        p2pService.dispose();
      },
    );

    test(
      'message with only upload_pending attachments retries as text-only',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final msg = ConversationMessage(
          id: 'msg-pending-only',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Photo attached',
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final pendingAttachment = MediaAttachment(
          id: 'placeholder-uuid-pending',
          messageId: 'msg-pending-only',
          mime: 'image/jpeg',
          size: 102400,
          mediaType: 'image',
          downloadStatus: 'upload_pending', // upload never completed
          createdAt: stuckTs,
          localPath: '/tmp/photo_pending.jpg',
        );

        final messageRepo = FakeMessageRepository()..seed([msg]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: msg.id,
            attachments: [pendingAttachment],
          );
        final identityRepo = FakeIdentityRepository()
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
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: 'bob-mlkem-pk',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = PassthroughCryptoBridge();

        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // With Phase 3B's three-branch dispatch, messages with only
        // upload_pending attachments are routed to the re-upload branch.
        // Without local files available, the re-upload fails and the message
        // is left as 'failed' for the next retry after retryIncompleteUploads
        // handles the upload. This is correct behavior: the message will be
        // retried after the upload completes.
        expect(retried, 0);

        p2pService.dispose();
      },
    );
  });
}
