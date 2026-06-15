import 'dart:convert';

import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

class _UnackedDeleteP2PService extends FakeP2PService {
  _UnackedDeleteP2PService({
    required super.peerId,
    required super.network,
    this.transport = 'direct',
  });

  final String transport;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    return SendMessageResult(sent: true, acked: false, transport: transport);
  }
}

void main() {
  late FakeMessageRepository messageRepo;
  late FakeReactionRepository reactionRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  const recipientMlKemPublicKey = 'recipient-mlkem-public-key';

  ConversationMessage makeMessage({
    String id = 'msg-1',
    String contactPeerId = 'peer-bob',
    String senderPeerId = 'peer-alice',
    String text = 'Hello Bob',
    String status = 'delivered',
    bool isIncoming = false,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: '2026-03-31T10:00:00.000Z',
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-03-31T10:00:01.000Z',
    );
  }

  MediaAttachment makeAttachment({
    required String id,
    required String messageId,
    required String localPath,
    String downloadStatus = 'done',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 2048,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-03-31T10:00:02.000Z',
    );
  }

  setUp(() {
    messageRepo = FakeMessageRepository();
    reactionRepo = FakeReactionRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
  });

  group('delete_message_use_case', () {
    test(
      'deleteMessageForMe hard-deletes the row after local cleanup',
      () async {
        final message = makeMessage();
        messageRepo.seed([message]);
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'att-owned',
            messageId: message.id,
            localPath: 'media/msg-1/photo.jpg',
          ),
          makeAttachment(
            id: 'att-external',
            messageId: message.id,
            localPath: '/tmp/external/photo.jpg',
          ),
        ]);
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'reaction-1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'peer-bob',
            timestamp: '2026-03-31T10:01:00.000Z',
            createdAt: '2026-03-31T10:01:00.000Z',
          ),
        );

        final count = await deleteMessageForMe(
          message: message,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(await messageRepo.getMessage(message.id), isNull);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(message.id),
          isEmpty,
        );
        expect(await reactionRepo.getReactionsForMessage(message.id), isEmpty);
        expect(
          mediaFileManager.deletedFilePaths,
          contains(endsWith('test_docs/media/msg-1/photo.jpg')),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(contains('/tmp/external/photo.jpg')),
        );
      },
    );

    test(
      'deleteMessageForEveryone keeps a sender-visible failed tombstone on send failure',
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = FakeP2PService(
          peerId: 'peer-alice',
          network: network,
        );

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.peerNotFound);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, original.id);
        expect(tombstone.text, isEmpty);
        expect(tombstone.status, 'failed');
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.deletedByPeerId, 'peer-alice');
        expect(tombstone.wireEnvelope, contains('"type":"message_deletion"'));
        expect(tombstone.wireEnvelope, contains('"version":"2"'));
        expect(tombstone.wireEnvelope, isNot(contains('"payload"')));

        final stored = await messageRepo.getMessage(original.id);
        expect(stored, isNotNull);
        expect(stored!.status, 'failed');
        expect(stored.isHidden, isFalse);
        expect(
          await messageRepo.getMessagesForContact(original.contactPeerId),
          hasLength(1),
        );

        p2pService.dispose();
      },
    );

    test(
      'deleteMessageForEveryone returns encryptionRequired when recipient ML-KEM key is missing',
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
        );

        expect(result, SendChatMessageResult.encryptionRequired);
        expect(tombstone, isNull);
        expect(await messageRepo.getMessage(original.id), original);

        p2pService.dispose();
      },
    );

    test(
      'deleteMessageForEveryone sends encrypted v2 deletion when key is present',
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        final envelope =
            jsonDecode(tombstone!.wireEnvelope ?? '{}') as Map<String, dynamic>;
        expect(envelope['type'], 'message_deletion');
        expect(envelope['version'], '2');
        expect(envelope.containsKey('payload'), isFalse);
        expect(envelope['encrypted'], isA<Map<String, dynamic>>());

        p2pService.dispose();
        recipient.dispose();
      },
    );

    test(
      'buildDeletionWireEnvelope emits encrypted v2 deletion envelope',
      () async {
        final original = makeMessage();

        final wireEnvelope = await buildDeletionWireEnvelope(
          bridge: PassthroughCryptoBridge(),
          originalMessage: original,
          deletedAt: '2026-03-31T10:02:00.000Z',
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        final envelope = jsonDecode(wireEnvelope) as Map<String, dynamic>;
        expect(envelope['type'], 'message_deletion');
        expect(envelope['version'], '2');
        expect(envelope['encrypted'], isA<Map<String, dynamic>>());
        expect(envelope.containsKey('payload'), isFalse);
      },
    );

    test(
      'deleteMessageForEveryone keeps a visible sent tombstone when live delivery is unacked and inbox fallback also fails',
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
          transport: 'direct',
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, original.id);
        expect(tombstone.text, isEmpty);
        expect(tombstone.status, 'sent');
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.hiddenAt, isNull);
        expect(tombstone.transport, 'direct');
        expect(tombstone.wireEnvelope, contains('"type":"message_deletion"'));
        expect(tombstone.wireEnvelope, contains('"version":"2"'));

        final stored = await messageRepo.getMessage(original.id);
        expect(stored, isNotNull);
        expect(stored!.status, 'sent');
        expect(stored.isHidden, isFalse);
        expect(stored.hiddenAt, isNull);
        expect(
          await messageRepo.getMessagesForContact(original.contactPeerId),
          hasLength(1),
        );

        p2pService.dispose();
        recipient.dispose();
      },
    );
  });

  // ─── 115 Phase 1 — deletion tombstones ride inbox custody honestly ──────
  // A 'delivered' deletion whose relay entry was cap-evicted is exactly the
  // original bug class: the sender hides the tombstone, the receiver never
  // deletes (doc 115 D-3). Inbox custody persists 'inboxed' with the envelope
  // retained, and the tombstone stays VISIBLE until receipt-driven delivery.
  group('115 Phase 1 — deletion tombstone inbox custody', () {
    test(
      "delete-for-everyone via sequential inbox fallback persists tombstone status 'inboxed' and retains wire_envelope",
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        // Recipient unreachable (not registered) → race fails; inbox enabled
        // → the sequential inbox tail takes custody.
        final network = FakeP2PNetwork();
        final p2pService = FakeP2PService(
          peerId: 'peer-alice',
          network: network,
        );

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.status, 'inboxed');
        expect(tombstone.transport, 'inbox');
        expect(
          tombstone.wireEnvelope,
          contains('"type":"message_deletion"'),
          reason: 'custody sweep re-store needs the envelope retained',
        );
        expect(
          tombstone.isHidden,
          isFalse,
          reason:
              'tombstone stays visible until receipt-confirmed delivery (D-3)',
        );

        final stored = await messageRepo.getMessage(original.id);
        expect(stored!.status, 'inboxed');
        expect(stored.isHidden, isFalse);
        expect(stored.wireEnvelope, isNotNull);

        p2pService.dispose();
      },
    );

    test(
      "unacked delete handoff persists 'inboxed', not 'delivered'",
      () async {
        final original = makeMessage();
        messageRepo.seed([original]);

        final network = FakeP2PNetwork();
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.status, 'inboxed');
        expect(tombstone.transport, 'inbox');
        expect(tombstone.wireEnvelope, contains('"type":"message_deletion"'));
        expect(tombstone.isHidden, isFalse);

        p2pService.dispose();
        recipient.dispose();
      },
    );

    // Green-on-arrival PIN (does not count toward the phase RED count):
    // the pure visibility function already hides only on 'delivered'. This
    // pin blocks anyone "fixing" lingering tombstones by widening that gate
    // instead of landing 115 Phase 2's deletion receipts (D-3).
    test(
      "an 'inboxed' outgoing tombstone stays visible (hiddenAt null) until receipt-driven delivered",
      () {
        final tombstone = makeMessage().copyWith(
          text: '',
          status: 'inboxed',
          deletedAt: '2026-06-13T10:00:00.000Z',
          deletedByPeerId: 'peer-alice',
        );

        final normalized = normalizeOutgoingDeleteTombstoneVisibility(
          tombstone,
        );

        expect(normalized.hiddenAt, isNull);
        expect(
          normalizeOutgoingDeleteTombstoneVisibility(
            tombstone.copyWith(status: 'delivered'),
          ).hiddenAt,
          '2026-06-13T10:00:00.000Z',
          reason: "only 'delivered' hides the tombstone",
        );
      },
    );
  });
}
