import 'dart:async';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart'
    show RecoveredInboxChatDisposition;
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_deletion_payload.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

class _MessageRepositoryWithoutOrdinaryApply implements MessageRepository {
  _MessageRepositoryWithoutOrdinaryApply(this.message);

  ConversationMessage message;
  int saveCalls = 0;

  @override
  Future<ConversationMessage?> getMessage(String id) async =>
      id == message.id ? message : null;

  @override
  Future<void> saveMessage(ConversationMessage value) async {
    saveCalls++;
    message = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeMessageRepository messageRepo;
  late FakeContactRepository contactRepo;
  late FakeReactionRepository reactionRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;

  ContactModel makeContact(String peerId) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'User $peerId',
      signature: 'sig-$peerId',
      scannedAt: '2026-03-31T09:00:00.000Z',
      mlKemPublicKey: 'mlkem-$peerId',
    );
  }

  ConversationMessage makeMessage({
    required String id,
    required String contactPeerId,
    required String senderPeerId,
    String text = 'Hello',
    bool isIncoming = true,
    String status = 'delivered',
    PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
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
      privateMediaPolicy: privateMediaPolicy,
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
      size: 1234,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-03-31T10:00:02.000Z',
    );
  }

  setUp(() {
    messageRepo = FakeMessageRepository();
    contactRepo = FakeContactRepository();
    reactionRepo = FakeReactionRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
  });

  group('handleIncomingMessageDeletion', () {
    test(
      'TC-349-03 partial blank or mismatched deletion identity has zero side effects',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        const cases = <({String? outer, String? inner})>[
          (outer: 'outer-only', inner: null),
          (outer: null, inner: 'inner-only'),
          (outer: 'outer', inner: 'inner'),
          (outer: ' ', inner: ' '),
        ];
        for (final tc in cases) {
          final localRepo = FakeMessageRepository();
          localRepo.seed([
            makeMessage(
              id: 'event-parity-target',
              contactPeerId: 'peer-alice',
              senderPeerId: 'peer-alice',
            ),
          ]);
          final inner = MessageDeletionPayload(
            messageId: 'event-parity-target',
            senderPeerId: 'peer-alice',
            timestamp: '2026-08-09T00:00:00.000Z',
            eventId: tc.inner,
          );
          var receiptCalls = 0;

          final (result, tombstone) = await handleIncomingMessageDeletion(
            message: ChatMessage(
              from: 'peer-alice',
              to: 'peer-bob',
              content: MessageDeletionPayload.buildEncryptedEnvelope(
                senderPeerId: 'peer-alice',
                eventId: tc.outer,
                kem: 'kem',
                ciphertext: inner.toInnerJson(),
                nonce: 'nonce',
              ),
              timestamp: '2026-08-09T00:00:00.000Z',
              isIncoming: true,
              transport: 'inbox',
            ),
            messageRepo: localRepo,
            contactRepo: contactRepo,
            bridge: PassthroughCryptoBridge(),
            ownMlKemSecretKey: 'secret',
            sendMutationDeliveryReceipt:
                (_, {required mutationEventId}) async => receiptCalls++,
          );

          expect(result, HandleMessageDeletionResult.unauthorized);
          expect(tombstone, isNull);
          expect(
            (await localRepo.getMessage('event-parity-target'))!.isDeleted,
            isFalse,
          );
          expect(receiptCalls, 0);
        }
      },
    );

    test(
      'TC-349-06 ordinary text deletion capability absence has zero persistence cleanup or receipt',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        final original = makeMessage(
          id: 'ordinary-no-authority',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-alice',
        );
        final localRepo = _MessageRepositoryWithoutOrdinaryApply(original);
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'ordinary-no-authority-reaction',
            messageId: 'ordinary-no-authority',
            emoji: '👍',
            senderPeerId: 'peer-bob',
            timestamp: '2026-08-09T00:00:00.000Z',
            createdAt: '2026-08-09T00:00:00.000Z',
          ),
        );
        var receiptCalls = 0;
        final payload = MessageDeletionPayload(
          messageId: original.id,
          senderPeerId: 'peer-alice',
          timestamp: '2026-08-09T00:01:00.000Z',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: payload.timestamp,
            isIncoming: true,
            transport: 'inbox',
          ),
          messageRepo: localRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          sendDeliveryReceipt: (_) async => receiptCalls++,
        );

        expect(result, HandleMessageDeletionResult.unauthorized);
        expect(tombstone, isNull);
        expect(localRepo.saveCalls, 0);
        expect(localRepo.message.isDeleted, isFalse);
        expect(
          await reactionRepo.getReactionsForMessage(original.id),
          hasLength(1),
        );
        expect(receiptCalls, 0);
      },
    );

    test(
      'applies an authorized tombstone and cleans up local artifacts',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);

        final original = makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-alice',
        );
        messageRepo.seed([original]);
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
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'att-owned',
            messageId: 'msg-1',
            localPath: 'media/msg-1/photo.jpg',
          ),
          makeAttachment(
            id: 'att-external',
            messageId: 'msg-1',
            localPath: '/tmp/external/photo.jpg',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final encryptedEnvelope = MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: 'peer-alice',
          kem: 'fake-kem',
          ciphertext: payload.toInnerJson(),
          nonce: 'fake-nonce',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: encryptedEnvelope,
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'self-secret',
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, 'msg-1');
        expect(tombstone.text, isEmpty);
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.deletedAt, '2026-03-31T10:05:00.000Z');
        expect(tombstone.deletedByPeerId, 'peer-alice');

        final stored = await messageRepo.getMessage('msg-1');
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isTrue);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-1',
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
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
      'authorized incoming protected deletion cleans attachments and local artifacts',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);

        messageRepo.seed([
          makeMessage(
            id: 'msg-incoming-protected',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
          ),
        ]);
        await reactionRepo.saveReaction(
          const MessageReaction(
            id: 'reaction-incoming-protected',
            messageId: 'msg-incoming-protected',
            emoji: '👍',
            senderPeerId: 'peer-bob',
            timestamp: '2026-03-31T10:01:00.000Z',
            createdAt: '2026-03-31T10:01:00.000Z',
          ),
        );
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'att-incoming-protected',
            messageId: 'msg-incoming-protected',
            localPath: 'media/msg-incoming-protected/photo.jpg',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-incoming-protected',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.isDeleted, isTrue);
        expect(tombstone.isIncoming, isTrue);
        expect(
          tombstone.privateMediaPolicy,
          const PrivateMediaPolicy.protected(),
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-incoming-protected',
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        expect(
          await reactionRepo.getReactionsForMessage('msg-incoming-protected'),
          isEmpty,
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(
            endsWith('test_docs/media/msg-incoming-protected/photo.jpg'),
          ),
        );
      },
    );

    test(
      'blocked sender delete still tombstones an already stored authored message',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        await contactRepo.blockContact('peer-alice');

        final original = makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-alice',
        );
        messageRepo.seed([original]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, 'msg-1');
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.deletedByPeerId, 'peer-alice');
      },
    );

    test(
      'blocked sender delete does not stage a missing-message tombstone',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        await contactRepo.blockContact('peer-alice');

        final payload = MessageDeletionPayload(
          messageId: 'missing-msg',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(result, HandleMessageDeletionResult.ignoredMissingMessage);
        expect(tombstone, isNull);
        expect(await messageRepo.getMessage('missing-msg'), isNull);
      },
    );

    test('rejects spoofed delete requests for another sender', () async {
      contactRepo.seed([makeContact('peer-alice')]);
      messageRepo.seed([
        makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-charlie',
        ),
      ]);

      final payload = MessageDeletionPayload(
        messageId: 'msg-1',
        senderPeerId: 'peer-alice',
        timestamp: '2026-03-31T10:05:00.000Z',
      );

      final (result, tombstone) = await handleIncomingMessageDeletion(
        message: ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(result, HandleMessageDeletionResult.unauthorized);
      expect(tombstone, isNull);
      final stored = await messageRepo.getMessage('msg-1');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isFalse);
    });

    test(
      'rejects delete requests when envelope sender mismatches payload sender',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        messageRepo.seed([
          makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'different-envelope-sender',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(result, HandleMessageDeletionResult.unauthorized);
        expect(tombstone, isNull);
        final stored = await messageRepo.getMessage('msg-1');
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isFalse);
      },
    );

    test(
      'rejects delete requests when encrypted envelope sender mismatches payload sender',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        messageRepo.seed([
          makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final encryptedEnvelope = MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: 'different-envelope-sender',
          kem: 'fake-kem',
          ciphertext: payload.toInnerJson(),
          nonce: 'fake-nonce',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: encryptedEnvelope,
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'self-secret',
        );

        expect(result, HandleMessageDeletionResult.unauthorized);
        expect(tombstone, isNull);
        final stored = await messageRepo.getMessage('msg-1');
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isFalse);
      },
    );

    test(
      'creates a tombstone placeholder when delete arrives before the original',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);

        final payload = MessageDeletionPayload(
          messageId: 'missing-message',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: payload.toJson(),
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(tombstone, isNotNull);
        expect(tombstone!.id, 'missing-message');
        expect(tombstone.text, isEmpty);
        expect(tombstone.isDeleted, isTrue);
        expect(tombstone.isHidden, isFalse);
        expect(tombstone.deletedAt, '2026-03-31T10:05:00.000Z');
        final stored = await messageRepo.getMessage('missing-message');
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isTrue);
        expect(stored.text, isEmpty);
      },
    );

    test('duplicate authorized delete deliveries are idempotent', () async {
      contactRepo.seed([makeContact('peer-alice')]);
      messageRepo.seed([
        makeMessage(
          id: 'msg-1',
          contactPeerId: 'peer-alice',
          senderPeerId: 'peer-alice',
        ),
      ]);

      final payload = MessageDeletionPayload(
        messageId: 'msg-1',
        senderPeerId: 'peer-alice',
        timestamp: '2026-03-31T10:05:00.000Z',
      );

      final first = await handleIncomingMessageDeletion(
        message: ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );
      final saveCallsAfterFirst = messageRepo.saveMessageCallCount;

      final second = await handleIncomingMessageDeletion(
        message: ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );

      expect(first.$1, HandleMessageDeletionResult.success);
      expect(second.$1, HandleMessageDeletionResult.success);
      expect(messageRepo.saveMessageCallCount, saveCallsAfterFirst);

      final stored = await messageRepo.getMessage('msg-1');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isTrue);
    });

    test(
      'returns decryptionFailed when encrypted delete lacks key material',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        messageRepo.seed([
          makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final encryptedEnvelope = MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: 'peer-alice',
          kem: 'fake-kem',
          ciphertext: payload.toInnerJson(),
          nonce: 'fake-nonce',
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: encryptedEnvelope,
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
        );

        expect(result, HandleMessageDeletionResult.decryptionFailed);
        expect(tombstone, isNull);
        expect((await messageRepo.getMessage('msg-1'))?.isDeleted, isFalse);
      },
    );

    test(
      'returns decryptionFailed when encrypted delete cannot be decrypted',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        messageRepo.seed([
          makeMessage(
            id: 'msg-1',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);

        final payload = MessageDeletionPayload(
          messageId: 'msg-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final encryptedEnvelope = MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: 'peer-alice',
          kem: 'fake-kem',
          ciphertext: payload.toInnerJson(),
          nonce: 'fake-nonce',
        );
        final bridge = FakeBridge(
          initialResponses: {
            'message.decrypt': {'ok': false, 'errorCode': 'bad_key'},
          },
        );

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: encryptedEnvelope,
            timestamp: '2026-03-31T10:05:00.000Z',
            isIncoming: true,
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: bridge,
          ownMlKemSecretKey: 'self-secret',
        );

        expect(result, HandleMessageDeletionResult.decryptionFailed);
        expect(tombstone, isNull);
        expect((await messageRepo.getMessage('msg-1'))?.isDeleted, isFalse);
      },
    );

    // ─── 115 Phase 2.5 — deletion-apply receipts (D-3) ───────────────────
    // Without deletion receipts, an 'inboxed' delete-for-everyone tombstone
    // would stay pending forever and the sender's tombstone would never
    // hide. Same origin contract as the chat hook: relay-drain only.
    test(
      'inbox-originated message_deletion invokes sendDeliveryReceipt after the deletion is durably applied',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        messageRepo.seed([
          makeMessage(
            id: 'msg-del-rcpt-1',
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);

        final receiptIds = <String>[];
        Future<void> hook(String messageId) async {
          receiptIds.add(messageId);
        }

        final payload = MessageDeletionPayload(
          messageId: 'msg-del-rcpt-1',
          senderPeerId: 'peer-alice',
          timestamp: '2026-03-31T10:05:00.000Z',
        );
        final message = ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: payload.toJson(),
          timestamp: '2026-03-31T10:05:00.000Z',
          isIncoming: true,
          transport: 'inbox',
        );

        // Relay-drain origin → receipt after durable apply.
        final (result, _) = await handleIncomingMessageDeletion(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          stagedEntryId: 'relay-uuid-del-1',
          sendDeliveryReceipt: hook,
        );
        expect(result, HandleMessageDeletionResult.success);
        expect(receiptIds, ['msg-del-rcpt-1']);
        expect(
          (await messageRepo.getMessage('msg-del-rcpt-1'))!.isDeleted,
          isTrue,
        );

        // Duplicate re-application (already-deleted) → re-invoked.
        final (again, _) = await handleIncomingMessageDeletion(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          stagedEntryId: 'relay-uuid-del-1',
          sendDeliveryReceipt: hook,
        );
        expect(again, HandleMessageDeletionResult.success);
        expect(receiptIds, ['msg-del-rcpt-1', 'msg-del-rcpt-1']);

        // 132 Phase 1 (LIVE by default): 'direct:'/'lan:' origins ALSO mint a
        // confirmatory receipt now (the lost-ack repair), so the deleter's
        // tombstone converges even when the live/LAN ack was lost.
        final (direct, _) = await handleIncomingMessageDeletion(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          stagedEntryId: 'direct:n9',
          sendDeliveryReceipt: hook,
        );
        expect(direct, HandleMessageDeletionResult.success);
        final (lan, _) = await handleIncomingMessageDeletion(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          stagedEntryId: 'lan:n9',
          sendDeliveryReceipt: hook,
        );
        expect(lan, HandleMessageDeletionResult.success);
        expect(receiptIds, hasLength(4));
      },
    );
  });

  group('Plan 351 current media deletion convergence', () {
    test(
      'TC-351-05 duplicate current deletion re-drives cleanup and re-mints its '
      'receipt without a second tombstone write',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        const messageId = 'tc351-duplicate-media';
        const eventId = '35100000-0000-4000-8000-000000000099';
        messageRepo.seed([
          makeMessage(
            id: messageId,
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: '$messageId-a',
            messageId: messageId,
            localPath: 'media/peer-alice/$messageId-a.jpg',
          ),
        ]);
        final inner = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: 'peer-alice',
          timestamp: '2026-08-09T00:00:00.000Z',
          eventId: eventId,
        );
        final message = ChatMessage(
          from: 'peer-alice',
          to: 'peer-bob',
          content: MessageDeletionPayload.buildEncryptedEnvelope(
            senderPeerId: 'peer-alice',
            eventId: eventId,
            kem: 'kem',
            ciphertext: inner.toInnerJson(),
            nonce: 'nonce',
          ),
          timestamp: '2026-08-09T00:00:00.000Z',
          isIncoming: true,
          transport: 'inbox',
        );
        final receiptEvents = <String>[];

        Future<HandleMessageDeletionResult> apply() async {
          final (result, _) = await handleIncomingMessageDeletion(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            reactionRepo: reactionRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            bridge: PassthroughCryptoBridge(),
            ownMlKemSecretKey: 'secret',
            stagedEntryId: 'relay-uuid-tc351',
            sendMutationDeliveryReceipt:
                (id, {required mutationEventId}) async =>
                    receiptEvents.add(mutationEventId),
          );
          return result;
        }

        expect(await apply(), HandleMessageDeletionResult.success);
        final stored = await messageRepo.getMessage(messageId);
        expect(stored!.isDeleted, isTrue);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        expect(mediaFileManager.deletedFilePaths, isNotEmpty);

        // A duplicate of the exact same event re-drives the idempotent cleanup
        // and re-mints its receipt without rewriting the durable tombstone.
        mediaFileManager.deletedFilePaths.clear();
        expect(await apply(), HandleMessageDeletionResult.success);
        expect(receiptEvents, <String>[eventId, eventId]);
        expect(
          (await messageRepo.getMessage(messageId))!.deletedAt,
          stored.deletedAt,
        );
      },
    );

    test(
      'TC-351-05 an ownerless current deletion capability fails closed with no '
      'cleanup or receipt',
      () async {
        contactRepo.seed([makeContact('peer-alice')]);
        const messageId = 'tc351-no-authority';
        const eventId = '35100000-0000-4000-8000-000000000098';
        messageRepo.seed([
          makeMessage(
            id: messageId,
            contactPeerId: 'peer-alice',
            senderPeerId: 'peer-alice',
          ),
        ]);
        messageRepo.supportsIncomingDirectDeletionApplyOverride = false;
        addTearDown(
          () => messageRepo.supportsIncomingDirectDeletionApplyOverride = true,
        );
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: '$messageId-a',
            messageId: messageId,
            localPath: 'media/peer-alice/$messageId-a.jpg',
          ),
        ]);
        final inner = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: 'peer-alice',
          timestamp: '2026-08-09T00:00:00.000Z',
          eventId: eventId,
        );
        var receipts = 0;

        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: 'peer-alice',
            to: 'peer-bob',
            content: MessageDeletionPayload.buildEncryptedEnvelope(
              senderPeerId: 'peer-alice',
              eventId: eventId,
              kem: 'kem',
              ciphertext: inner.toInnerJson(),
              nonce: 'nonce',
            ),
            timestamp: '2026-08-09T00:00:00.000Z',
            isIncoming: true,
            transport: 'inbox',
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'secret',
          stagedEntryId: 'relay-uuid-tc351b',
          sendMutationDeliveryReceipt: (_, {required mutationEventId}) async =>
              receipts++,
        );

        expect(result, HandleMessageDeletionResult.unauthorized);
        expect(tombstone, isNull);
        expect(receipts, 0);
        expect((await messageRepo.getMessage(messageId))!.isDeleted, isFalse);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
        expect(mediaFileManager.deletedFilePaths, isEmpty);
      },
    );
  });

  group('Plan 356 current private deletion convergence', () {
    const author = 'peer-alice';
    const t0 = '2026-08-10T09:00:00.000Z';
    const t1 = '2026-08-10T09:00:01.000Z';

    test('TC-356-04b event-bearing protected and view-once deletion use private '
        'cleanup reactions and exact receipt', () async {
      Future<void> proveOneMode({
        required String suffix,
        required String mode,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final messageId = 'tc356-04b-$suffix';
        final attachmentId = '$messageId-blob';
        final eventId =
            '35600000-0000-4000-8000-0000000004${suffix.length.toString().padLeft(2, '0')}';

        await fixture.db.insert('messages', <String, Object?>{
          'id': messageId,
          'contact_peer_id': author,
          'sender_peer_id': author,
          'text': '',
          'timestamp': t0,
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': t0,
          'private_media_policy_version': 1,
          'private_media_mode': mode,
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        });
        final localPath = MediaFilePathConvention.relativePathForAttachment(
          contactPeerId: author,
          blobId: attachmentId,
          mime: 'image/jpeg',
        );
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 4,
            mediaType: 'image',
            localPath: localPath,
            downloadStatus: 'done',
            createdAt: t0,
            encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
            encryptionNonce: 'bm9uY2U=',
            encryptionScheme: 'blob_aes_256_gcm_v1',
          ),
          owner: MediaOwnerLane.direct,
        );
        // The independent no-FK v111 obligation must survive its own owner.
        await fixture.db.insert(
          kDirectMediaBlobCustodyTable,
          DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.incoming,
            state: DirectMediaBlobCustodyState.incomingCommitted,
            inboxCustodyIncarnationId: null,
            recipientPeerId: null,
            ciphertextRelativePath: null,
            contentHash: 'c' * 64,
            ciphertextSize: 64,
            expiresAtMs: 1900003000000,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: t0,
            updatedAt: t0,
          ).toMap(),
        );
        final localReactionRepo = FakeReactionRepository();
        await localReactionRepo.saveReaction(
          MessageReaction(
            id: '$messageId-r',
            messageId: messageId,
            emoji: '👍',
            senderPeerId: author,
            timestamp: t0,
            createdAt: t0,
          ),
        );
        contactRepo.seed([makeContact(author)]);

        final inner = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: author,
          timestamp: t1,
          eventId: eventId,
        );
        final receipts = <String>[];
        final manager = FakeMediaFileManager();

        final (result, stored) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: author,
            to: 'peer-bob',
            content: MessageDeletionPayload.buildEncryptedEnvelope(
              senderPeerId: author,
              eventId: eventId,
              kem: 'kem',
              ciphertext: inner.toInnerJson(),
              nonce: 'nonce',
            ),
            timestamp: t1,
            isIncoming: true,
            transport: 'inbox',
          ),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          reactionRepo: localReactionRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'secret',
          stagedEntryId: 'relay-uuid-tc356-$suffix',
          sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
              receipts.add('$id/$mutationEventId'),
        );

        expect(result, HandleMessageDeletionResult.success);
        expect(stored, isNotNull);
        expect(stored!.isDeleted, isTrue);
        expect(stored.deletedAt, t1);
        expect(
          stored.privateMediaMode,
          mode == 'protected'
              ? PrivateMediaMode.protected
              : PrivateMediaMode.viewOnce,
          reason: 'the private policy survives the deletion transaction',
        );

        // Exact private cleanup, never the generic attachment path: only the
        // private lifecycle engine removes the secure key with the row.
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          isFalse,
          reason: 'generic attachment deletion never retires a secure key',
        );
        expect(
          await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(1),
          reason:
              'the no-FK v111 obligation converges by its own ACK or expiry',
        );
        expect(
          await localReactionRepo.getReactionsForMessage(messageId),
          isEmpty,
          reason: 'reaction records are retired separately',
        );
        expect(receipts, <String>['$messageId/$eventId']);
      }

      await proveOneMode(suffix: 'protected', mode: 'protected');
      await proveOneMode(suffix: 'view-once', mode: 'view_once');
    });
  });

  group('Plan 357 contact deletion versus current deletion', () {
    const author = 'peer-alice';
    const t0 = '2026-08-10T09:00:00.000Z';
    const t1 = '2026-08-10T09:00:01.000Z';

    ChatMessage deletionEvent(String messageId, String eventId) {
      final inner = MessageDeletionPayload(
        messageId: messageId,
        senderPeerId: author,
        timestamp: t1,
        eventId: eventId,
      );
      return ChatMessage(
        from: author,
        to: 'peer-bob',
        content: MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: author,
          eventId: eventId,
          kem: 'kem',
          ciphertext: inner.toInnerJson(),
          nonce: 'nonce',
        ),
        timestamp: t1,
        isIncoming: true,
        transport: 'inbox',
      );
    }

    test('TC-357-02 contact deletion winner prevents current deletion '
        'tombstone resurrection and receipt', () async {
      // --- Order A: real contact deletion wins the shared lease while the
      // handler still holds a stale-positive first contact read. ---
      final lock = _SignallingLifecycleLock();
      final fixture = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: lock,
      );
      addTearDown(fixture.dispose);
      const staleId = 'tc357-02-stale-contact';
      const staleEvent = '35700000-0000-4000-8000-000000000201';
      await fixture.db.insert('messages', <String, Object?>{
        'id': staleId,
        'contact_peer_id': author,
        'sender_peer_id': author,
        'text': 'about to be purged',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': t0,
      });
      final releaseFirstRead = Completer<void>();
      addTearDown(() {
        if (!releaseFirstRead.isCompleted) releaseFirstRead.complete();
      });
      final barrierContacts = _BarrierContactRepository(
        gate: () => releaseFirstRead.future,
      )..contacts[author] = makeContact(author);

      final staleReceipts = <String>[];
      final handled = handleIncomingMessageDeletion(
        message: deletionEvent(staleId, staleEvent),
        messageRepo: fixture.messageRepo,
        contactRepo: barrierContacts,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'secret',
        stagedEntryId: 'relay-uuid-tc357-02a',
        sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
            staleReceipts.add('$id/$mutationEventId'),
      );
      await barrierContacts.firstReadEntered.future.timeout(
        const Duration(seconds: 10),
      );

      // The real contact-delete use case runs to completion under the same
      // exclusive private lifecycle lease.
      await deleteContactAndMessages(
        contactRepo: barrierContacts,
        messageRepo: fixture.messageRepo,
        peerId: author,
        mediaAttachmentRepo: fixture.repo,
        reactionRepo: reactionRepo,
        mediaFileManager: mediaFileManager,
      ).timeout(const Duration(seconds: 10));
      expect(await barrierContacts.getContact(author), isNull);
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[staleId],
        ),
        isEmpty,
      );

      releaseFirstRead.complete();
      final (staleResult, staleStored) = await handled.timeout(
        const Duration(seconds: 10),
      );

      expect(
        staleResult,
        HandleMessageDeletionResult.unauthorized,
        reason: 'a contact removed under the lease revokes deletion authority',
      );
      expect(staleStored, isNull);
      expect(
        mapMessageDeletionReplayResultToDisposition(staleResult).disposition,
        RecoveredInboxChatDisposition.rejected,
        reason: 'recovered replay must be terminal, never retryable',
      );
      expect(staleReceipts, isEmpty);
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[staleId],
        ),
        isEmpty,
        reason: 'no orphan tombstone may follow contact deletion',
      );
      expect(
        await fixture.db.query(
          'messages',
          where: 'contact_peer_id = ?',
          whereArgs: const <Object?>[author],
        ),
        isEmpty,
      );

      // --- Order B: the handler owns the lease first. Deletion-before-initial
      // still converges, receipts exactly once, and the later contact purge
      // leaves nothing behind. ---
      final secondLock = _SignallingLifecycleLock();
      final second = await MediaRepositoryRealDbFixture.create(
        lifecycleLock: secondLock,
      );
      addTearDown(second.dispose);
      const handlerFirstId = 'tc357-02-handler-first';
      const handlerFirstEvent = '35700000-0000-4000-8000-000000000202';
      final liveContacts = _BarrierContactRepository()
        ..contacts[author] = makeContact(author);
      final applyEntered = Completer<void>();
      final releaseApply = Completer<void>();
      addTearDown(() {
        if (!releaseApply.isCompleted) releaseApply.complete();
      });
      // Apply really runs under the handler's exclusive lease, so the section
      // open at that instant IS the lease the receipt must wait for.
      int? handlerSection;
      final gatedRepo = _GatedIncomingDeletionApplyRepository(
        second.messageRepo,
        onApply: () async {
          handlerSection ??= secondLock.outermostOpenSection;
          if (!applyEntered.isCompleted) applyEntered.complete();
          await releaseApply.future;
        },
      );

      final handlerReceipts = <String>[];
      // Sampled inside the receipt callback: the handler's own lease must
      // already have finished when the receipt is emitted. The competing purge
      // may hold the lock by then, so a live active count cannot carry this.
      final leaseReleasedAtReceipt = <bool>[];
      final handlerFirst = handleIncomingMessageDeletion(
        message: deletionEvent(handlerFirstId, handlerFirstEvent),
        messageRepo: gatedRepo,
        contactRepo: liveContacts,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: second.repo,
        mediaFileManager: mediaFileManager,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'secret',
        stagedEntryId: 'relay-uuid-tc357-02b',
        sendMutationDeliveryReceipt: (id, {required mutationEventId}) async {
          leaseReleasedAtReceipt.add(
            secondLock.finishedSections.contains(handlerSection),
          );
          handlerReceipts.add('$id/$mutationEventId');
        },
      );
      await applyEntered.future.timeout(const Duration(seconds: 10));

      // Started from the test zone so the exclusive lease cannot be inherited.
      final contactAttempted = secondLock.nextExclusiveAttempt();
      final purge = deleteContactAndMessages(
        contactRepo: liveContacts,
        messageRepo: second.messageRepo,
        peerId: author,
        mediaAttachmentRepo: second.repo,
        reactionRepo: reactionRepo,
        mediaFileManager: mediaFileManager,
      );
      await contactAttempted.timeout(const Duration(seconds: 10));
      expect(
        await liveContacts.getContact(author),
        isNotNull,
        reason: 'the competing purge cannot run while the handler holds it',
      );
      expect(handlerReceipts, isEmpty);

      releaseApply.complete();
      final (handlerResult, handlerStored) = await handlerFirst.timeout(
        const Duration(seconds: 10),
      );
      expect(handlerResult, HandleMessageDeletionResult.success);
      expect(handlerStored?.isDeleted, isTrue);
      expect(handlerReceipts, <String>['$handlerFirstId/$handlerFirstEvent']);
      expect(
        leaseReleasedAtReceipt,
        const <bool>[true],
        reason: 'the receipt is emitted only after the lease is released',
      );

      await purge.timeout(const Duration(seconds: 10));
      expect(
        await second.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[handlerFirstId],
        ),
        isEmpty,
        reason: 'the later purge removes the durable tombstone it inventoried',
      );
      expect(await liveContacts.getContact(author), isNull);
    });
  });

  group('Plan 359 incoming disappearing deletion authority', () {
    const author = 'peer-alice';
    const t0 = '2026-08-11T09:00:00.000Z';
    const t1 = '2026-08-11T09:00:01.000Z';
    const receivedAtMs = 1900000000000;
    const durationSeconds = 3600;
    const expiresAtMs = receivedAtMs + durationSeconds * 1000;

    ChatMessage deletionEvent(String messageId, String eventId) {
      final inner = MessageDeletionPayload(
        messageId: messageId,
        senderPeerId: author,
        timestamp: t1,
        eventId: eventId,
      );
      return ChatMessage(
        from: author,
        to: 'peer-bob',
        content: MessageDeletionPayload.buildEncryptedEnvelope(
          senderPeerId: author,
          eventId: eventId,
          kem: 'kem',
          ciphertext: inner.toInnerJson(),
          nonce: 'nonce',
        ),
        timestamp: t1,
        isIncoming: true,
        transport: 'inbox',
      );
    }

    /// Seeds one INCOMING v1 disappearing parent with a live receiver clock,
    /// one private attachment, one independent no-FK v111 obligation and one
    /// reaction row.
    Future<String> seedIncomingDisappearing(
      MediaRepositoryRealDbFixture fixture,
      FakeReactionRepository reactions,
      String messageId, {
      String mode = 'disappearing',
      int? duration = durationSeconds,
      Object? intentId,
    }) async {
      final attachmentId = '$messageId-blob';
      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': author,
        'sender_peer_id': author,
        'text': '',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': t0,
        'direct_media_custody_intent_id': intentId,
        'private_media_policy_version': 1,
        'private_media_mode': mode,
        'private_media_duration_seconds': duration,
        'private_media_state': 'available',
        'private_media_received_at_ms': receivedAtMs,
        'private_media_expires_at_ms': expiresAtMs,
        'private_media_clock_high_water_ms': receivedAtMs,
      });
      await fixture.repo.saveAttachment(
        MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          localPath: MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: author,
            blobId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'done',
          createdAt: t0,
          encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: 'blob_aes_256_gcm_v1',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.db.insert(
        kDirectMediaBlobCustodyTable,
        DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.incoming,
          state: DirectMediaBlobCustodyState.incomingCommitted,
          inboxCustodyIncarnationId: null,
          recipientPeerId: null,
          ciphertextRelativePath: null,
          contentHash: 'c' * 64,
          ciphertextSize: 64,
          expiresAtMs: 1900003000000,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: t0,
          updatedAt: t0,
        ).toMap(),
      );
      await reactions.saveReaction(
        MessageReaction(
          id: '$messageId-r',
          messageId: messageId,
          emoji: '👍',
          senderPeerId: author,
          timestamp: t0,
          createdAt: t0,
        ),
      );
      return attachmentId;
    }

    Future<Map<String, Object?>> parentRow(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async => (await fixture.db.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
    )).single;

    test('TC-359-03a incoming disappearing deletion preserves lifecycle and '
        'v111 before exact receipt', () async {
      // 1. Three receiver-local projections built by their REAL owners:
      //    visible-active, hide-generated (`available` + terminal/high-water),
      //    and expiry-generated (`expired`).
      var eventSeq = 0;
      Future<void> proveOneProjection({
        required String suffix,
        required Future<void> Function(
          MediaRepositoryRealDbFixture fixture,
          String messageId,
        )
        project,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final localReactions = FakeReactionRepository();
        final messageId = 'tc359-03a-$suffix';
        final eventId =
            '35900000-0000-4000-8000-${(++eventSeq).toString().padLeft(12, '0')}';
        final attachmentId = await seedIncomingDisappearing(
          fixture,
          localReactions,
          messageId,
        );
        await project(fixture, messageId);
        final before = await parentRow(fixture, messageId);
        contactRepo.seed([makeContact(author)]);
        final receipts = <String>[];
        final manager = FakeMediaFileManager();

        final (result, stored) = await handleIncomingMessageDeletion(
          message: deletionEvent(messageId, eventId),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          reactionRepo: localReactions,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'secret',
          stagedEntryId: 'relay-uuid-tc359-$suffix',
          sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
              receipts.add('$id/$mutationEventId'),
        );

        expect(result, HandleMessageDeletionResult.success, reason: suffix);
        expect(stored, isNotNull, reason: suffix);
        expect(stored!.isDeleted, isTrue, reason: suffix);
        expect(stored.deletedAt, t1, reason: suffix);

        // Every receiver clock, lifecycle state and hide byte is preserved:
        // authenticated author deletion is not a lifecycle transition.
        final after = await parentRow(fixture, messageId);
        for (final column in const <String>[
          'private_media_policy_version',
          'private_media_mode',
          'private_media_duration_seconds',
          'private_media_state',
          'private_media_received_at_ms',
          'private_media_expires_at_ms',
          'private_media_revealed_at_ms',
          'private_media_terminal_at_ms',
          'private_media_clock_high_water_ms',
          'hidden_at',
        ]) {
          expect(
            after[column],
            before[column],
            reason: '$suffix must preserve $column',
          );
        }
        expect(after['deleted_by_peer_id'], author, reason: suffix);
        expect(after['text'], '', reason: suffix);

        // Exact private cleanup, never generic attachment deletion.
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          isFalse,
          reason: 'generic attachment deletion never retires a secure key',
        );
        // The independent no-FK v111 obligation converges on its own.
        expect(
          await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(1),
          reason: suffix,
        );
        expect(
          await localReactions.getReactionsForMessage(messageId),
          isEmpty,
          reason: suffix,
        );
        expect(
          await fixture.db.query(
            'direct_notification_display_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          isEmpty,
          reason: suffix,
        );
        expect(receipts, <String>['$messageId/$eventId'], reason: suffix);
      }

      await proveOneProjection(
        suffix: 'visible-active',
        project: (_, _) async {},
      );
      await proveOneProjection(
        suffix: 'hide-generated',
        project: (fixture, messageId) async {
          // The REAL hide owner leaves state `available` while stamping the
          // terminal and high-water clocks.
          expect(
            await fixture.messageRepo.hidePrivateMediaForMe(
              messageId,
              hiddenAt: t0,
              nowMs: receivedAtMs + 10,
            ),
            isTrue,
          );
          final hidden = await parentRow(fixture, messageId);
          expect(hidden['private_media_state'], 'available');
          expect(hidden['private_media_terminal_at_ms'], isNotNull);
          expect(hidden['hidden_at'], t0);
        },
      );
      await proveOneProjection(
        suffix: 'expiry-generated',
        project: (fixture, messageId) async {
          // The REAL expiry owner terminalizes the visible active card.
          expect(
            await fixture.messageRepo.advancePrivateMediaClock(
              messageId,
              nowMs: expiresAtMs + 1,
            ),
            isTrue,
          );
          expect(
            (await parentRow(fixture, messageId))['private_media_state'],
            'expired',
          );
        },
      );

      // 2. Immutable-authority refusals: zero receipt, zero effect.
      Future<void> expectRefusedWithNoEffect(
        String suffix, {
        String mode = 'disappearing',
        int? duration = durationSeconds,
        Object? intentId,
        String from = author,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final localReactions = FakeReactionRepository();
        final messageId = 'tc359-03a-refused-$suffix';
        final eventId =
            '35900000-0000-4000-8000-${(++eventSeq + 500).toString().padLeft(12, '0')}';
        final attachmentId = await seedIncomingDisappearing(
          fixture,
          localReactions,
          messageId,
          mode: mode,
          duration: duration,
          intentId: intentId,
        );
        final before = await parentRow(fixture, messageId);
        contactRepo.seed([makeContact(author), makeContact(from)]);
        final receipts = <String>[];
        final manager = FakeMediaFileManager();

        final inner = MessageDeletionPayload(
          messageId: messageId,
          senderPeerId: from,
          timestamp: t1,
          eventId: eventId,
        );
        final (result, tombstone) = await handleIncomingMessageDeletion(
          message: ChatMessage(
            from: from,
            to: 'peer-bob',
            content: MessageDeletionPayload.buildEncryptedEnvelope(
              senderPeerId: from,
              eventId: eventId,
              kem: 'kem',
              ciphertext: inner.toInnerJson(),
              nonce: 'nonce',
            ),
            timestamp: t1,
            isIncoming: true,
            transport: 'inbox',
          ),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
          reactionRepo: localReactions,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          bridge: PassthroughCryptoBridge(),
          ownMlKemSecretKey: 'secret',
          stagedEntryId: 'relay-uuid-tc359-refused-$suffix',
          sendMutationDeliveryReceipt: (id, {required mutationEventId}) async =>
              receipts.add('$id/$mutationEventId'),
        );

        expect(
          result,
          isNot(HandleMessageDeletionResult.success),
          reason: suffix,
        );
        expect(tombstone, isNull, reason: suffix);
        expect(receipts, isEmpty, reason: suffix);
        expect(await parentRow(fixture, messageId), before, reason: suffix);
        expect(
          await fixture.rawAttachmentRow(attachmentId),
          isNotNull,
          reason: suffix,
        );
        expect(manager.deletedFilePaths, isEmpty, reason: suffix);
        expect(
          await localReactions.getReactionsForMessage(messageId),
          hasLength(1),
          reason: suffix,
        );
      }

      // An out-of-set duration is already impossible: the frozen v100 CHECK
      // constraint rejects the write itself, which is strictly stronger.
      await expectRefusedWithNoEffect('missing-duration', duration: null);
      await expectRefusedWithNoEffect('unsupported-mode', mode: 'unsupported');
      await expectRefusedWithNoEffect(
        'unconsumed-v110-intent',
        intentId: 'tc359-03a-intent',
      );
      await expectRefusedWithNoEffect('crossed-author', from: 'peer-mallory');
    });
  });
}

/// Signals every exclusive acquisition ATTEMPT on the real repository-wide
/// private lifecycle lock, so a competing contender is observed deterministically
/// instead of by polling or sleeping.
class _SignallingLifecycleLock extends MediaAttachmentLifecycleLock {
  final List<Completer<void>> _attemptWaiters = <Completer<void>>[];
  int exclusiveAttempts = 0;
  int exclusiveActive = 0;
  int _nextSectionId = 0;
  final List<int> _openSections = <int>[];
  final Set<int> finishedSections = <int>{};

  /// The OUTERMOST exclusive section currently open. The engine's per-attachment
  /// sections are reentrant inside it, so only this identity marks the lease a
  /// caller actually owns.
  int? get outermostOpenSection =>
      _openSections.isEmpty ? null : _openSections.first;

  Future<void> nextExclusiveAttempt() {
    final waiter = Completer<void>();
    _attemptWaiters.add(waiter);
    return waiter.future;
  }

  @override
  Future<T> synchronizedAll<T>(Future<T> Function() action) {
    exclusiveAttempts++;
    for (final waiter in _attemptWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _attemptWaiters.clear();
    return super.synchronizedAll(() async {
      final sectionId = ++_nextSectionId;
      _openSections.add(sectionId);
      exclusiveActive++;
      try {
        return await action();
      } finally {
        exclusiveActive--;
        _openSections.remove(sectionId);
        finishedSections.add(sectionId);
      }
    });
  }
}

/// Holds the handler's FIRST contact read open so a real contact deletion can
/// win the shared lease behind it; later reads observe live state.
class _BarrierContactRepository implements ContactRepository {
  _BarrierContactRepository({this.gate});

  final Future<void> Function()? gate;
  final Map<String, ContactModel> contacts = <String, ContactModel>{};
  final Completer<void> firstReadEntered = Completer<void>();
  int getContactCalls = 0;

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCalls++;
    if (getContactCalls == 1 && gate != null) {
      final captured = contacts[peerId];
      if (!firstReadEntered.isCompleted) firstReadEntered.complete();
      await gate!();
      return captured;
    }
    return contacts[peerId];
  }

  @override
  Future<void> deleteContact(String peerId) async {
    contacts.remove(peerId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'barrier contact repository received ${invocation.memberName}',
  );
}

/// Pauses inside the current-deletion apply, which production runs under the
/// exclusive private lifecycle lease.
class _GatedIncomingDeletionApplyRepository
    implements MessageRepository, IncomingDirectDeletionApplyRepository {
  _GatedIncomingDeletionApplyRepository(this.delegate, {required this.onApply});

  final MessageRepositoryImpl delegate;
  final Future<void> Function() onApply;

  @override
  bool get supportsIncomingDirectDeletionApply =>
      delegate.supportsIncomingDirectDeletionApply;

  @override
  Future<IncomingDirectDeletionApplyResult> applyIncomingDirectMessageDeletion({
    required String messageId,
    required String senderPeerId,
    required String deletedAt,
    String? transport,
  }) async {
    await onApply();
    return delegate.applyIncomingDirectMessageDeletion(
      messageId: messageId,
      senderPeerId: senderPeerId,
      deletedAt: deletedAt,
      transport: transport,
    );
  }

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  @override
  Future<void> saveMessage(ConversationMessage message) =>
      delegate.saveMessage(message);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'gated deletion-apply repository received ${invocation.memberName}',
  );
}
