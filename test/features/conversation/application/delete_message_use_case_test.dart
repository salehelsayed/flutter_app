import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
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
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
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

class _ThrowingReadMessageRepository extends FakeMessageRepository {
  @override
  Future<ConversationMessage?> getMessage(String id) async {
    throw StateError('injected authority read failure');
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
      'authority read failure returns zero with no cleanup mutation',
      () async {
        final message = makeMessage(id: 'delete-read-failure');
        mediaAttachmentRepo.seed([
          makeAttachment(
            id: 'delete-read-failure-att',
            messageId: message.id,
            localPath: 'media/peer-bob/delete-read-failure-att.jpg',
          ),
        ]);

        expect(
          await deleteMessageForMe(
            message: message,
            messageRepo: _ThrowingReadMessageRepository(),
            reactionRepo: reactionRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
          0,
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
        expect(mediaFileManager.deletedFilePaths, isEmpty);
      },
    );

    test(
      'stale ordinary snapshot cannot physically delete current private parent',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const id = 'private-delete-stale-ordinary';
        await fixture.seedDirectParent(id);
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        final current = (await fixture.messageRepo.getMessage(id))!;
        final staleOrdinary = current.copyWith(
          privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
          privateMediaState: PrivateMediaLifecycleState.none,
        );

        expect(
          await deleteMessageForMe(
            message: staleOrdinary,
            messageRepo: fixture.messageRepo,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: mediaFileManager,
          ),
          1,
        );
        final after = await fixture.messageRepo.getMessage(id);
        expect(after, isNotNull);
        expect(after!.hiddenAt, isNotNull);
        expect(after.privateMediaPolicy.mode, PrivateMediaMode.protected);
        expect(after.privateMediaState, PrivateMediaLifecycleState.available);
      },
    );

    test(
      'stale private snapshot preserves current terminal checkpoint',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const id = 'private-delete-stale-terminal';
        await fixture.seedDirectParent(id);
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'consumed',
            'private_media_received_at_ms': 1000,
            'private_media_terminal_at_ms': 2000,
            'private_media_clock_high_water_ms': 2000,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        final current = (await fixture.messageRepo.getMessage(id))!;
        final stalePrivate = current.copyWith(
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          privateMediaState: PrivateMediaLifecycleState.available,
          privateMediaTerminalAtMs: null,
        );

        expect(
          await deleteMessageForMe(
            message: stalePrivate,
            messageRepo: fixture.messageRepo,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: mediaFileManager,
          ),
          1,
        );
        final after = await fixture.messageRepo.getMessage(id);
        expect(after, isNotNull);
        expect(after!.hiddenAt, isNotNull);
        expect(after.privateMediaPolicy.mode, PrivateMediaMode.viewOnce);
        expect(after.privateMediaState, PrivateMediaLifecycleState.consumed);
        expect(after.privateMediaTerminalAtMs, 2000);
      },
    );

    test(
      'private delete retains truthful hidden parent before exact cleanup',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        await fixture.seedDirectParent('private-delete');
        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: ['private-delete'],
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'private-delete-att',
            messageId: 'private-delete',
            localPath: 'media/contact-1/private-delete-att.jpg',
          ).copyWith(encryptionKeyBase64: 'a2V5', encryptionNonce: 'bm9uY2U='),
          owner: MediaOwnerLane.direct,
        );
        final privateMessage = (await fixture.messageRepo.getMessage(
          'private-delete',
        ))!;

        final count = await deleteMessageForMe(
          message: privateMessage,
          messageRepo: fixture.messageRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
        );

        final tombstone = await fixture.messageRepo.getMessage(
          'private-delete',
        );
        expect(count, 1);
        expect(tombstone, isNotNull);
        expect(tombstone!.hiddenAt, isNotNull);
        expect(tombstone.privateMediaState.name, 'available');
        expect(tombstone.privateMediaPolicy.mode.name, 'protected');
        expect(await fixture.rawAttachmentRow('private-delete-att'), isNull);
      },
    );

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
          await mediaAttachmentRepo.getAttachmentsForMessage(
            message.id,
            owner: MediaOwnerLane.direct,
          ),
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
      'delete for me cleanup preserves same id group and unresolved media',
      () async {
        // 228 TC-228-11W: direct and group message ids can legally collide.
        // Delete-for-me cleanup runs against the REAL repository
        // (production-registry schema) and must remove ONLY direct-owned
        // rows and app-owned files — the same-ID group sibling and the
        // legacy 'unresolved' row survive byte-identical, and no file
        // deletion is recorded for the group sibling's path.
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);

        final message = makeMessage(id: 'msg-collide');
        messageRepo.seed([message]);
        await fixture.seedDirectParent(
          message.id,
          contactPeerId: message.contactPeerId,
        );
        await fixture.seedGroupParent(message.id);

        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-collide-direct',
            messageId: message.id,
            localPath: 'media/msg-collide/photo.jpg',
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-collide-group',
            messageId: message.id,
            localPath: 'media/msg-collide/group-photo.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        // 231: non-default plan-228 viewer state on BOTH surviving siblings so
        // byte-for-byte preservation covers bookmark/playback, not just the
        // schema defaults a lossy rewrite would reproduce for free.
        await fixture.db.update(
          'media_attachments',
          {'is_bookmarked': 1, 'last_playback_position_ms': 4321},
          where: 'id = ?',
          whereArgs: ['att-collide-group'],
        );
        // Legacy row: addressable through NO lane, must survive cleanup.
        await fixture.db.insert('media_attachments', {
          'id': 'att-collide-unresolved',
          'message_id': message.id,
          'owner_lane': kMediaOwnerLaneUnresolved,
          'mime': 'image/jpeg',
          'size': 2048,
          'media_type': 'image',
          'local_path': 'media/msg-collide/unresolved-photo.jpg',
          'is_bookmarked': 1,
          'last_playback_position_ms': 7777,
          'download_status': 'done',
          'created_at': '2026-03-31T10:00:02.000Z',
        });

        final groupRowBefore = await fixture.rawAttachmentRow(
          'att-collide-group',
        );
        final unresolvedRowBefore = await fixture.rawAttachmentRow(
          'att-collide-unresolved',
        );
        expect(groupRowBefore, isNotNull);
        expect(unresolvedRowBefore, isNotNull);
        // The preservation assertion below must be over NON-default state.
        expect(groupRowBefore!['is_bookmarked'], 1);
        expect(groupRowBefore['last_playback_position_ms'], 4321);
        expect(unresolvedRowBefore!['is_bookmarked'], 1);
        expect(unresolvedRowBefore['last_playback_position_ms'], 7777);

        final count = await deleteMessageForMe(
          message: message,
          messageRepo: messageRepo,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(await messageRepo.getMessage(message.id), isNull);
        // Direct-owned row and its message-owned file are gone.
        expect(await fixture.rawAttachmentRow('att-collide-direct'), isNull);
        expect(
          mediaFileManager.deletedFilePaths,
          contains(endsWith('media/msg-collide/photo.jpg')),
        );
        // Same-ID group sibling and unresolved legacy rows are untouched.
        expect(
          await fixture.rawAttachmentRow('att-collide-group'),
          groupRowBefore,
        );
        expect(
          await fixture.rawAttachmentRow('att-collide-unresolved'),
          unresolvedRowBefore,
        );
        // NO file deletion recorded for either surviving sibling's path.
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(contains(endsWith('media/msg-collide/group-photo.jpg'))),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(contains(endsWith('media/msg-collide/unresolved-photo.jpg'))),
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
