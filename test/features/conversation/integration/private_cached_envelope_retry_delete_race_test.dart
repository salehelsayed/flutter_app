import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/delivery_receipt_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = 'private-replay-delete-contact';
const _envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
const _deletionEnvelope =
    '{"type":"message_deletion","version":"2","encrypted":{}}';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    flowEventLoggingEnabled = false;
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    flowEventLoggingEnabled = true;
    await fixture.dispose();
  });

  test(
    'cleaned failed private cached replay cannot resurrect a parent physically deleted after network starts',
    () async {
      const messageId = 'private-failed-replay-delete';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: '$messageId-attachment',
        status: 'failed',
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: '$messageId-attachment',
      );
      var networkStartedFromPersistedSnapshot = false;
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          networkStartedFromPersistedSnapshot = true;
          expect(await fixture.messageRepo.getMessage(messageId), isNotNull);
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          expect(await fixture.messageRepo.getMessage(messageId), isNull);
          return true;
        };

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: p2pService,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(networkStartedFromPersistedSnapshot, isTrue);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(retried, 1);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        ),
        isEmpty,
      );
    },
  );

  test(
    'cleaned unacked private cached replay cannot resurrect a parent physically deleted after network starts',
    () async {
      const messageId = 'private-unacked-replay-delete';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: '$messageId-attachment',
        status: 'sent',
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: '$messageId-attachment',
      );
      var networkStartedFromPersistedSnapshot = false;
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          networkStartedFromPersistedSnapshot = true;
          expect(await fixture.messageRepo.getMessage(messageId), isNotNull);
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          expect(await fixture.messageRepo.getMessage(messageId), isNull);
          return true;
        };

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: p2pService,
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(networkStartedFromPersistedSnapshot, isTrue);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(retried, 1);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        ),
        isEmpty,
      );
    },
  );

  test(
    'failed private cached replay settles after terminal local cleanup',
    () async {
      const messageId = 'private-failed-replay-cleaned';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'failed',
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: _p2pService(),
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.wireEnvelope, _envelope);
      expect(persisted?.privateMediaState, PrivateMediaLifecycleState.consumed);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
    },
  );

  test(
    'unacked private cached replay settles after terminal local cleanup',
    () async {
      const messageId = 'private-unacked-replay-cleaned';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'sent',
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: _p2pService(),
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.wireEnvelope, _envelope);
      expect(persisted?.privateMediaState, PrivateMediaLifecycleState.consumed);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
    },
  );

  test(
    'failed private cached replay settles when first-frame cleanup wins during network',
    () async {
      const messageId = 'private-failed-replay-cleanup-race';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'failed',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          await _consumeAndCleanPrivateCachedEnvelope(
            fixture,
            messageId: messageId,
            attachmentId: attachmentId,
          );
          return true;
        };

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: p2pService,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.privateMediaState, PrivateMediaLifecycleState.consumed);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
    },
  );

  test(
    'unacked private cached replay settles when first-frame cleanup wins during network',
    () async {
      const messageId = 'private-unacked-replay-cleanup-race';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'sent',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          await _consumeAndCleanPrivateCachedEnvelope(
            fixture,
            messageId: messageId,
            attachmentId: attachmentId,
          );
          return true;
        };

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: p2pService,
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.privateMediaState, PrivateMediaLifecycleState.consumed);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
    },
  );

  test(
    'failed private DFE cached replay settles without attachments',
    () async {
      const messageId = 'private-dfe-failed-replay';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
      );

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: _p2pService(),
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.deletedAt, isNotNull);
      expect(persisted?.wireEnvelope, _deletionEnvelope);
    },
  );

  test(
    'legacy failed private DFE inbox transport reacquires deletion custody',
    () async {
      const messageId = 'private-dfe-legacy-inherited-inbox';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
      );
      await fixture.db.update(
        'messages',
        const <String, Object?>{'transport': 'inbox'},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      final p2pService = _p2pService();

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: p2pService,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxMessage, _deletionEnvelope);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
    },
  );

  test(
    'inboxed private DFE failure clears inherited custody before cached retry',
    () async {
      const messageId = 'private-dfe-inherited-inbox-custody';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'inboxed',
      );
      await fixture.db.update(
        'messages',
        const <String, Object?>{'transport': 'inbox'},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      final original = (await fixture.messageRepo.getMessage(messageId))!;
      expect(original.status, 'inboxed');
      expect(original.transport, 'inbox');

      final p2pService = _p2pService()
        ..discoverPeerResult = const DiscoveredPeer(
          id: _contactPeerId,
          addresses: <String>['/ip4/127.0.0.1/tcp/4001'],
        )
        ..sendMessageWithReplyResult = const SendMessageResult(sent: false)
        ..storeInInboxResult = false;

      final deletion = await deleteMessageForEveryone(
        p2pService: p2pService,
        messageRepo: fixture.messageRepo,
        originalMessage: original,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: FakeMediaFileManager(),
        bridge: FakeBridge(),
        recipientMlKemPublicKey: 'recipient-mlkem-public-key',
        emitTimingEvent: false,
      );

      expect(p2pService.sendMessageWithReplyCallCount, 1);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(deletion.$2?.status, 'failed');
      expect(deletion.$2?.transport, isNull);

      p2pService.storeInInboxResult = true;
      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: p2pService,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      expect(p2pService.storeInInboxCallCount, 2);
      expect(p2pService.lastStoreInInboxMessage, deletion.$2?.wireEnvelope);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
    },
  );

  test(
    'failed private DFE rebuild stages its envelope update-only before replay',
    () async {
      const messageId = 'private-dfe-failed-rebuild';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
        wireEnvelope: null,
      );
      final contacts = FakeContactRepository()
        ..seed(const <ContactModel>[
          ContactModel(
            peerId: _contactPeerId,
            publicKey: 'public-key',
            rendezvous: '/ip4/127.0.0.1/tcp/4001',
            username: 'Private peer',
            signature: 'signature',
            scannedAt: '2020-01-01T00:00:00.000Z',
            mlKemPublicKey: 'mlkem-public-key',
          ),
        ]);

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: contacts,
        p2pService: _p2pService(),
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.wireEnvelope, contains('message_deletion'));
      expect(persisted?.deletedAt, isNotNull);
    },
  );

  test(
    'failed private DFE cached replay cannot resurrect contact-deleted parent',
    () async {
      const messageId = 'private-dfe-failed-delete-race';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          return true;
        };

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: p2pService,
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 0);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'unacked private DFE cached replay settles without attachments',
    () async {
      const messageId = 'private-dfe-unacked-replay';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'sent',
      );

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: _p2pService(),
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.deletedAt, isNotNull);
      expect(persisted?.wireEnvelope, _deletionEnvelope);
    },
  );

  test(
    'unacked private DFE cached replay cannot resurrect contact-deleted parent',
    () async {
      const messageId = 'private-dfe-unacked-delete-race';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'sent',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          return true;
        };

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: p2pService,
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(retried, 0);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'attachment-free settlement refuses a nonterminal private parent',
    () async {
      const messageId = 'private-live-missing-attachment';
      await fixture.seedDirectParent(messageId, contactPeerId: _contactPeerId);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'sender_peer_id': 'self-peer',
          'status': 'failed',
          'is_incoming': 0,
          'wire_envelope': _envelope,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
          'private_media_revealed_at_ms': null,
          'private_media_terminal_at_ms': null,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );

      final outcome = await fixture.messageRepo
          .settleOutgoingDirectPrivateTransport(
            messageId: messageId,
            attachmentId: null,
            expectedEnvelope: _envelope,
            status: 'inboxed',
            transport: 'inbox',
            relayExpiresAt: null,
          );

      expect(outcome.accepted, isFalse);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'failed');
      expect(persisted?.wireEnvelope, _envelope);
    },
  );

  test(
    'private failed receipt with unknown transport settles through the real listener',
    () async {
      const messageId = 'private-receipt-listener-cleaned';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'failed',
      );
      await fixture.db.update(
        'messages',
        const <String, Object?>{'transport': null},
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final receipts = StreamController<ChatMessage>();
      final listener = DeliveryReceiptListener(
        receiptStream: receipts.stream,
        messageRepo: fixture.messageRepo,
        mediaAttachmentRepo: fixture.repo,
      )..start();
      addTearDown(() async {
        listener.dispose();
        await receipts.close();
      });
      final delivered = fixture.messageRepo.messageChanges.firstWhere(
        (message) => message.id == messageId && message.status == 'delivered',
      );

      receipts.add(_deliveryReceipt(messageId, transport: 'direct'));
      await delivered.timeout(const Duration(seconds: 2));

      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'delivered');
      expect(persisted?.transport, isNull);
      expect(persisted?.wireEnvelope, isNull);
    },
  );

  test(
    'private DFE receipt settles delivered with unknown transport',
    () async {
      const messageId = 'private-dfe-receipt';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
      );

      await handleDeliveryReceipt(
        message: _deliveryReceipt(messageId, transport: 'relay'),
        messageRepo: fixture.messageRepo,
        mediaAttachmentRepo: fixture.repo,
      );

      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'delivered');
      expect(persisted?.transport, isNull);
      expect(persisted?.wireEnvelope, isNull);
      expect(persisted?.hiddenAt, persisted?.deletedAt);
    },
  );

  test(
    'private receipt cannot resurrect a parent deleted after its stale read',
    () async {
      const messageId = 'private-receipt-delete-race';
      const attachmentId = '$messageId-attachment';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
        status: 'failed',
      );
      await _consumeAndCleanPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final deletingRepository = _DeleteAfterReadPrivateMessageRepository(
        fixture.messageRepo,
      );

      await handleDeliveryReceipt(
        message: _deliveryReceipt(messageId, transport: 'direct'),
        messageRepo: deletingRepository,
        mediaAttachmentRepo: fixture.repo,
      );

      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'private DFE receipt cannot resurrect a parent deleted after its stale read',
    () async {
      const messageId = 'private-dfe-receipt-delete-race';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'failed',
      );
      final deletingRepository = _DeleteAfterReadPrivateMessageRepository(
        fixture.messageRepo,
      );

      await handleDeliveryReceipt(
        message: _deliveryReceipt(messageId, transport: 'relay'),
        messageRepo: deletingRepository,
        mediaAttachmentRepo: fixture.repo,
      );

      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'pause flush cannot resurrect a private parent deleted during inbox deposit',
    () async {
      const messageId = 'private-pause-flush-delete-race';
      await _seedPrivateCachedEnvelope(
        fixture,
        messageId: messageId,
        attachmentId: '$messageId-attachment',
        status: 'sending',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          return true;
        };

      final result = await handleAppPaused(
        messageRepo: fixture.messageRepo,
        mediaAttachmentRepo: fixture.repo,
        enablePauseFlush: true,
        p2pService: p2pService,
        bridge: FakeBridge(),
      );

      expect(result.flushDepositedCount, 1);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'pause flush cannot resurrect a private DFE parent deleted during inbox deposit',
    () async {
      const messageId = 'private-dfe-pause-delete-race';
      await _seedPrivateDeleteTombstone(
        fixture,
        messageId: messageId,
        status: 'sending',
      );
      final p2pService = _p2pService()
        ..onStoreInInbox = (peerId, message, {timeoutMs}) async {
          expect(await fixture.messageRepo.deleteMessage(messageId), 1);
          return true;
        };

      final result = await handleAppPaused(
        messageRepo: fixture.messageRepo,
        mediaAttachmentRepo: fixture.repo,
        enablePauseFlush: true,
        p2pService: p2pService,
        bridge: FakeBridge(),
      );

      expect(result.flushDepositedCount, 1);
      expect(await fixture.messageRepo.getMessage(messageId), isNull);
    },
  );

  test(
    'pause leaves a private null-envelope row untouched when typed capabilities are absent',
    () async {
      const messageId = 'private-pause-null-envelope';
      await fixture.seedDirectParent(messageId, contactPeerId: _contactPeerId);
      await fixture.db.update(
        'messages',
        const <String, Object?>{
          'sender_peer_id': 'self-peer',
          'status': 'sending',
          'is_incoming': 0,
          'wire_envelope': null,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
          'private_media_revealed_at_ms': null,
          'private_media_terminal_at_ms': null,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );

      final result = await handleAppPaused(messageRepo: fixture.messageRepo);

      expect(result.transitionedCount, 0);
      expect(
        (await fixture.messageRepo.getMessage(messageId))?.status,
        'sending',
      );
    },
  );

  test(
    'failed ordinary cached replay retains generic inbox persistence',
    () async {
      const messageId = 'ordinary-failed-replay-control';
      await fixture.messageRepo.saveMessage(
        _ordinaryCachedEnvelope(messageId: messageId, status: 'failed'),
      );

      final retried = await retryFailedMessages(
        messageRepo: fixture.messageRepo,
        identityRepo: _identityRepository(),
        contactRepo: FakeContactRepository(),
        p2pService: _p2pService(),
        bridge: FakeBridge(),
        mediaAttachmentRepo: fixture.repo,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.wireEnvelope, _envelope);
    },
  );

  test(
    'unacked ordinary cached replay retains generic inbox persistence',
    () async {
      const messageId = 'ordinary-unacked-replay-control';
      await fixture.messageRepo.saveMessage(
        _ordinaryCachedEnvelope(messageId: messageId, status: 'sent'),
      );

      final retried = await retryUnackedMessages(
        messageRepo: fixture.messageRepo,
        p2pService: _p2pService(),
        mediaAttachmentRepo: fixture.repo,
        olderThan: Duration.zero,
      );

      expect(retried, 1);
      final persisted = await fixture.messageRepo.getMessage(messageId);
      expect(persisted?.status, 'inboxed');
      expect(persisted?.transport, 'inbox');
      expect(persisted?.wireEnvelope, _envelope);
    },
  );
}

Future<void> _seedPrivateCachedEnvelope(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
  required String status,
}) async {
  const createdAt = '2020-01-01T00:00:00.000Z';
  await fixture.seedDirectParent(
    messageId,
    contactPeerId: _contactPeerId,
    timestamp: createdAt,
  );
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'sender_peer_id': 'self-peer',
      'text': '',
      'status': status,
      'is_incoming': 0,
      'wire_envelope': _envelope,
      'private_media_policy_version': 1,
      'private_media_mode': 'protected',
      'private_media_state': 'available',
      'private_media_received_at_ms': 1000,
      'private_media_clock_high_water_ms': 1000,
      'private_media_revealed_at_ms': null,
      'private_media_terminal_at_ms': null,
    },
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
  final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
  const key = 'cHJpdmF0ZS1jYWNoZWQtcmVwbGF5LWtleQ==';
  await fixture.secureKeyStore.write(keyName, key);
  await fixture.db.insert(
    'media_attachments',
    MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 4,
      mediaType: 'image',
      localPath: 'media/$_contactPeerId/$attachmentId.jpg',
      downloadStatus: 'done',
      createdAt: createdAt,
      contentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      encryptionKeyBase64: secureStoreReferenceForKey(keyName),
      encryptionNonce: 'Y2FjaGVkLXJlcGxheS1ub25jZQ==',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      ownerLane: MediaOwnerLane.direct,
    ).toMap(),
  );
}

Future<void> _seedPrivateDeleteTombstone(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String status,
  String? wireEnvelope = _deletionEnvelope,
}) async {
  const createdAt = '2020-01-01T00:00:00.000Z';
  const deletedAt = '2020-01-01T00:01:00.000Z';
  await fixture.seedDirectParent(
    messageId,
    contactPeerId: _contactPeerId,
    timestamp: createdAt,
  );
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'sender_peer_id': 'self-peer',
      'text': '',
      'status': status,
      'transport': status == 'sent' ? 'direct' : null,
      'is_incoming': 0,
      'wire_envelope': wireEnvelope,
      'deleted_at': deletedAt,
      'deleted_by_peer_id': 'self-peer',
      'hidden_at': null,
      'private_media_policy_version': 1,
      'private_media_mode': 'protected',
      'private_media_state': 'consumed',
      'private_media_received_at_ms': 1000,
      'private_media_terminal_at_ms': 2000,
      'private_media_clock_high_water_ms': 2000,
    },
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
}

Future<void> _consumeAndCleanPrivateCachedEnvelope(
  MediaRepositoryRealDbFixture fixture, {
  required String messageId,
  required String attachmentId,
}) async {
  await fixture.db.update(
    'messages',
    <String, Object?>{
      'private_media_state': 'consumed',
      'private_media_terminal_at_ms': 2000,
      'private_media_clock_high_water_ms': 2000,
    },
    where: 'id = ?',
    whereArgs: <Object?>[messageId],
  );
  final engine = PrivateMediaLifecycleEngine(
    adapter: DirectPrivateMediaLifecycle(
      messageRepository: fixture.messageRepo,
      mediaAttachmentRepository: fixture.repo,
      mediaFileManager: FakeMediaFileManager(),
    ),
    lifecycleLock: fixture.repo.lifecycleLock,
    nowMs: () => 3000,
  );

  final reconciled = await engine.reconcileLocalLifecycle();

  expect(reconciled.cleanupCompleted, 1);
  expect(
    await fixture.repo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    ),
    isEmpty,
  );
  expect(
    await fixture.secureKeyStore.containsKey(
      mediaAttachmentEncryptionKeyStoreName(attachmentId),
    ),
    isFalse,
  );
}

ConversationMessage _ordinaryCachedEnvelope({
  required String messageId,
  required String status,
}) => ConversationMessage(
  id: messageId,
  contactPeerId: _contactPeerId,
  senderPeerId: 'self-peer',
  text: 'ordinary cached replay',
  timestamp: '2020-01-01T00:00:00.000Z',
  status: status,
  isIncoming: false,
  createdAt: '2020-01-01T00:00:00.000Z',
  wireEnvelope: _envelope,
  privateMediaPolicy: const PrivateMediaPolicy.ordinary(),
);

FakeIdentityRepository _identityRepository() =>
    FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));

FakeP2PService _p2pService() => FakeP2PService(
  initialState: const NodeState(
    isStarted: true,
    peerId: 'self-peer',
    circuitAddresses: <String>['/p2p-circuit/private-replay'],
  ),
  storeInInboxResult: true,
);

ChatMessage _deliveryReceipt(String messageId, {required String transport}) =>
    ChatMessage(
      from: _contactPeerId,
      to: 'self-peer',
      content: jsonEncode(<String, Object?>{
        'type': 'delivery_receipt',
        'version': '1',
        'payload': <String, Object?>{
          'messageIds': <String>[messageId],
          'ts': '2020-01-01T00:02:00.000Z',
        },
      }),
      timestamp: '2020-01-01T00:02:00.000Z',
      isIncoming: true,
      transport: transport,
    );

class _DeleteAfterReadPrivateMessageRepository
    implements
        MessageRepository,
        OutgoingDirectPrivateEnvelopeCustodyRepository,
        DirectPrivateDeleteForEveryoneRepository {
  _DeleteAfterReadPrivateMessageRepository(this.delegate);

  final dynamic delegate;
  var _deleted = false;

  @override
  Future<ConversationMessage?> getMessage(String id) async {
    final stale = await delegate.getMessage(id) as ConversationMessage?;
    if (stale != null && !_deleted) {
      _deleted = true;
      await delegate.deleteMessage(id);
    }
    return stale;
  }

  @override
  Future<OutgoingDirectPrivateTransportSettlementOutcome>
  settleOutgoingDirectPrivateTransport({
    required String messageId,
    required String? attachmentId,
    required String expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
  }) => delegate.settleOutgoingDirectPrivateTransport(
    messageId: messageId,
    attachmentId: attachmentId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
  );

  @override
  Future<ConversationMessage?> settlePrivateDeleteForEveryoneTombstone({
    required ConversationMessage tombstone,
    required String expectedEnvelope,
  }) => delegate.settlePrivateDeleteForEveryoneTombstone(
    tombstone: tombstone,
    expectedEnvelope: expectedEnvelope,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}
