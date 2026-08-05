import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/p2p_service.dart'
    show RelayProbeResult;
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p_state;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
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
import '../../contacts/domain/repositories/fake_contact_repository.dart'
    as contact_fakes;

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

class _BlockingEncryptBridge extends FakeBridge {
  final Completer<void> encryptEntered = Completer<void>();
  final Completer<void> releaseEncrypt = Completer<void>();

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'message.encrypt') {
      if (!encryptEntered.isCompleted) encryptEntered.complete();
      await releaseEncrypt.future;
    }
    return super.send(message);
  }
}

class _BlockingDeleteP2PService extends FakeP2PService {
  _BlockingDeleteP2PService({required super.peerId, required super.network});

  final Completer<void> sendEntered = Completer<void>();
  final Completer<void> releaseSend = Completer<void>();

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    if (!sendEntered.isCompleted) sendEntered.complete();
    await releaseSend.future;
    return const SendMessageResult(
      sent: true,
      acked: true,
      transport: 'direct',
    );
  }
}

class _ControlledDeleteP2PService extends FakeP2PService {
  _ControlledDeleteP2PService({
    required super.peerId,
    required super.network,
    required this.sendResult,
    this.sendGate,
  });

  final SendMessageResult sendResult;
  final Completer<SendMessageResult>? sendGate;
  final Completer<void> sendEntered = Completer<void>();
  int sendWithReplyCallCount = 0;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendWithReplyCallCount++;
    if (!sendEntered.isCompleted) sendEntered.complete();
    return sendGate?.future ?? sendResult;
  }
}

class _R3DeleteDeadlineP2PService extends FakeP2PService {
  _R3DeleteDeadlineP2PService({
    required super.peerId,
    required super.network,
    this.defaultSendResult = const SendMessageResult(
      sent: true,
      acked: true,
      transport: 'direct',
    ),
  });

  final SendMessageResult defaultSendResult;
  final List<SendMessageResult> scriptedSendResults = [];
  final List<bool> scriptedDialResults = [];
  final List<Duration> scriptedSendDelays = [];
  final List<Duration> scriptedDialDelays = [];
  Duration scriptedDiscoverDelay = Duration.zero;
  final List<int?> discoverTimeouts = [];
  final List<int?> dialTimeouts = [];
  final List<int?> sendTimeouts = [];
  int sendWithReplyCallCount = 0;
  int _sendIndex = 0;
  int _dialIndex = 0;

  @override
  Future<DiscoveredPeer?> discoverPeer(
    String targetPeerId, {
    int? timeoutMs,
  }) async {
    discoverTimeouts.add(timeoutMs);
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && scriptedDiscoverDelay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      return null;
    }
    if (scriptedDiscoverDelay > Duration.zero) {
      await Future<void>.delayed(scriptedDiscoverDelay);
    }
    return super.discoverPeer(targetPeerId, timeoutMs: timeoutMs);
  }

  @override
  Future<bool> dialPeer(
    String targetPeerId, {
    List<String>? addresses,
    int? timeoutMs,
    bool preferQuic = false,
  }) async {
    dialTimeouts.add(timeoutMs);
    final index = _dialIndex++;
    final delay = index < scriptedDialDelays.length
        ? scriptedDialDelays[index]
        : Duration.zero;
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && delay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      return false;
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (index < scriptedDialResults.length) {
      return scriptedDialResults[index];
    }
    return super.dialPeer(
      targetPeerId,
      addresses: addresses,
      timeoutMs: timeoutMs,
      preferQuic: preferQuic,
    );
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendTimeouts.add(timeoutMs);
    sendWithReplyCallCount++;
    final index = _sendIndex++;
    final delay = index < scriptedSendDelays.length
        ? scriptedSendDelays[index]
        : Duration.zero;
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && delay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      return const SendMessageResult(sent: false);
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return index < scriptedSendResults.length
        ? scriptedSendResults[index]
        : defaultSendResult;
  }
}

class _R3DelayedDeleteEncryptBridge extends PassthroughCryptoBridge {
  _R3DelayedDeleteEncryptBridge(this.delay);

  final Duration delay;

  @override
  Future<String> send(String message) async {
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command == 'message.encrypt' && delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return super.send(message);
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
      size: 2048,
      mediaType: 'image',
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-03-31T10:00:02.000Z',
    );
  }

  Future<ConversationMessage> seedPrivateDeleteForEveryoneParent(
    MediaRepositoryRealDbFixture fixture, {
    required String messageId,
    required String attachmentId,
  }) async {
    await fixture.seedDirectParent(messageId, contactPeerId: 'peer-bob');
    await fixture.db.update(
      'messages',
      <String, Object?>{
        'sender_peer_id': 'peer-alice',
        'status': 'delivered',
        'is_incoming': 0,
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': 'available',
        'private_media_received_at_ms': 1000,
        'private_media_revealed_at_ms': null,
        'private_media_clock_high_water_ms': 1000,
      },
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
    );
    await fixture.repo.saveAttachment(
      makeAttachment(
        id: attachmentId,
        messageId: messageId,
        localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
        downloadStatus: 'upload_pending',
      ),
      owner: MediaOwnerLane.direct,
    );
    return (await fixture.messageRepo.getMessage(messageId))!;
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
      'stale ordinary delete-for-everyone uses authoritative private cleanup',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-delete-everyone';
        const attachmentId = 'private-delete-everyone-att';
        await fixture.seedDirectParent(messageId, contactPeerId: 'peer-bob');
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'sender_peer_id': 'peer-alice',
            'status': 'delivered',
            'is_incoming': 0,
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_revealed_at_ms': null,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'private_media_state': 'opening',
            'private_media_revealed_at_ms': 1100,
            'private_media_clock_high_water_ms': 1100,
          },
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        );
        final original = makeMessage(
          id: messageId,
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
        );
        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        final persisted = await fixture.messageRepo.getMessage(messageId);
        expect(persisted, isNotNull);
        expect(persisted!.deletedAt, isNotNull);
        expect(persisted.privateMediaState, PrivateMediaLifecycleState.opening);
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);

        p2pService.dispose();
        recipient.dispose();
      },
    );

    test(
      'private delete-for-everyone cannot insert its first tombstone after contact deletion',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-delete-contact-before-tombstone';
        const attachmentId =
            'private-delete-contact-before-tombstone-attachment';
        final original = await seedPrivateDeleteForEveryoneParent(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
        );
        final bridge = _BlockingEncryptBridge();
        final network = FakeP2PNetwork();
        final sender = FakeP2PService(peerId: 'peer-alice', network: network);
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);
        addTearDown(sender.dispose);
        addTearDown(recipient.dispose);

        final deletion = deleteMessageForEveryone(
          p2pService: sender,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: bridge,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );
        await bridge.encryptEntered.future.timeout(const Duration(seconds: 5));

        await deleteContactAndMessages(
          contactRepo: contact_fakes.FakeContactRepository(),
          messageRepo: fixture.messageRepo,
          peerId: 'peer-bob',
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
        );
        expect(await fixture.messageRepo.getMessage(messageId), isNull);
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);

        bridge.releaseEncrypt.complete();
        final (result, tombstone) = await deletion.timeout(
          const Duration(seconds: 5),
        );

        expect(result, SendChatMessageResult.invalidMessage);
        expect(tombstone, isNull);
        expect(await fixture.messageRepo.getMessage(messageId), isNull);
        expect(network.deliverCallCount, 0);
      },
    );

    test(
      'private delete-for-everyone final settlement cannot reinsert after contact deletion',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'private-delete-contact-during-send';
        const attachmentId = 'private-delete-contact-during-send-attachment';
        final original = await seedPrivateDeleteForEveryoneParent(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
        );
        final network = FakeP2PNetwork();
        final sender = _BlockingDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);
        addTearDown(sender.dispose);
        addTearDown(recipient.dispose);

        final deletion = deleteMessageForEveryone(
          p2pService: sender,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );
        await sender.sendEntered.future.timeout(const Duration(seconds: 5));
        final pending = await fixture.messageRepo.getMessage(messageId);
        expect(pending, isNotNull);
        expect(pending!.isDeleted, isTrue);
        expect(pending.status, 'sending');

        await deleteContactAndMessages(
          contactRepo: contact_fakes.FakeContactRepository(),
          messageRepo: fixture.messageRepo,
          peerId: 'peer-bob',
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
        );
        expect(await fixture.messageRepo.getMessage(messageId), isNull);

        sender.releaseSend.complete();
        final (result, tombstone) = await deletion.timeout(
          const Duration(seconds: 5),
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNull);
        expect(await fixture.messageRepo.getMessage(messageId), isNull);
        expect(await fixture.rawAttachmentRow(attachmentId), isNull);
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
      'outgoing disappearing delete-for-everyone retains generic cleanup',
      () async {
        final original = makeMessage(
          id: 'disappearing-delete-everyone',
          privateMediaPolicy: PrivateMediaPolicy.disappearing(3600),
        );
        final attachment = makeAttachment(
          id: 'disappearing-delete-everyone-att',
          messageId: original.id,
          localPath: 'media/${original.id}/photo.jpg',
          downloadStatus: 'upload_pending',
        );
        messageRepo.seed([original]);
        mediaAttachmentRepo.seed([attachment]);

        final network = FakeP2PNetwork()..inboxDisabled = true;
        final p2pService = _UnackedDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);
        addTearDown(p2pService.dispose);
        addTearDown(recipient.dispose);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone, isNotNull);
        expect(
          tombstone!.privateMediaPolicy.mode,
          PrivateMediaMode.disappearing,
        );
        expect(messageRepo.saveMessageCallCount, 0);
        expect(messageRepo.ordinaryMutationCallCount, 2);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            original.id,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(endsWith('media/${original.id}/photo.jpg')),
        );
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

    test(
      'R2 delete reuse race and relay require explicit authenticated commitment',
      () async {
        Future<void> runOrdinaryAdapter({
          required String adapter,
          required bool explicitlyAcked,
        }) async {
          final repository = FakeMessageRepository();
          final original = makeMessage(
            id: 'r2-delete-$adapter-${explicitlyAcked ? 'acked' : 'reply'}',
          );
          repository.seed([original]);

          final network = FakeP2PNetwork()..inboxDisabled = true;
          final sender = _ControlledDeleteP2PService(
            peerId: 'peer-alice',
            network: network,
            sendResult: SendMessageResult(
              sent: true,
              acked: explicitlyAcked ? true : null,
              reply: explicitlyAcked ? null : '{"ack":true}',
              transport: adapter == 'relay' ? 'relay' : 'direct',
            ),
          );
          final recipient = FakeP2PService(
            peerId: 'peer-bob',
            network: network,
          );
          addTearDown(sender.dispose);
          addTearDown(recipient.dispose);

          switch (adapter) {
            case 'reuse':
              sender.testConnections.add(
                const p2p_state.ConnectionState(
                  peerId: 'peer-bob',
                  multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
                  direction: 'outbound',
                  status: 'connected',
                ),
              );
              break;
            case 'race':
              break;
            case 'relay':
              sender.discoverAlwaysFails = true;
              sender.probeRelayResult = RelayProbeResult.connected;
              break;
            default:
              fail('unknown adapter $adapter');
          }

          final (result, tombstone) = await deleteMessageForEveryone(
            p2pService: sender,
            messageRepo: repository,
            originalMessage: original,
            bridge: PassthroughCryptoBridge(),
            recipientMlKemPublicKey: recipientMlKemPublicKey,
          );

          expect(result, SendChatMessageResult.success);
          expect(sender.sendWithReplyCallCount, 1);
          expect(tombstone, isNotNull);
          if (explicitlyAcked) {
            expect(tombstone!.status, 'delivered');
            expect(tombstone.isHidden, isTrue);
            expect(tombstone.wireEnvelope, isNull);
          } else {
            expect(tombstone!.status, 'sent');
            expect(tombstone.isHidden, isFalse);
            expect(tombstone.hiddenAt, isNull);
            expect(
              tombstone.wireEnvelope,
              contains('"type":"message_deletion"'),
            );
          }
        }

        for (final adapter in const ['reuse', 'race', 'relay']) {
          await runOrdinaryAdapter(adapter: adapter, explicitlyAcked: false);
          await runOrdinaryAdapter(adapter: adapter, explicitlyAcked: true);
        }

        for (final adapter in const ['reuse', 'race', 'relay']) {
          for (final explicitlyAcked in const [false, true]) {
            final fixture = await MediaRepositoryRealDbFixture.create();
            addTearDown(fixture.dispose);
            final messageId =
                'r2-private-delete-$adapter-${explicitlyAcked ? 'acked' : 'reply'}';
            final original = await seedPrivateDeleteForEveryoneParent(
              fixture,
              messageId: messageId,
              attachmentId: '$messageId-attachment',
            );
            final network = FakeP2PNetwork()..inboxDisabled = true;
            final sender = _ControlledDeleteP2PService(
              peerId: 'peer-alice',
              network: network,
              sendResult: SendMessageResult(
                sent: true,
                acked: explicitlyAcked ? true : null,
                reply: explicitlyAcked ? null : '{"ack":true}',
                transport: adapter == 'relay' ? 'relay' : 'direct',
              ),
            );
            final recipient = FakeP2PService(
              peerId: 'peer-bob',
              network: network,
            );
            addTearDown(sender.dispose);
            addTearDown(recipient.dispose);

            switch (adapter) {
              case 'reuse':
                sender.testConnections.add(
                  const p2p_state.ConnectionState(
                    peerId: 'peer-bob',
                    multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
                    direction: 'outbound',
                    status: 'connected',
                  ),
                );
                break;
              case 'race':
                break;
              case 'relay':
                sender.discoverAlwaysFails = true;
                sender.probeRelayResult = RelayProbeResult.connected;
                break;
            }

            final (result, tombstone) = await deleteMessageForEveryone(
              p2pService: sender,
              messageRepo: fixture.messageRepo,
              originalMessage: original,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: mediaFileManager,
              bridge: PassthroughCryptoBridge(),
              recipientMlKemPublicKey: recipientMlKemPublicKey,
            );

            expect(result, SendChatMessageResult.success);
            expect(sender.sendWithReplyCallCount, 1);
            expect(tombstone, isNotNull);
            if (explicitlyAcked) {
              expect(tombstone!.status, 'delivered');
              expect(tombstone.isHidden, isTrue);
              expect(tombstone.wireEnvelope, isNull);
            } else {
              expect(tombstone!.status, 'sent');
              expect(tombstone.isHidden, isFalse);
              expect(tombstone.hiddenAt, isNull);
              expect(tombstone.wireEnvelope, isNotNull);
            }
          }
        }
      },
    );

    test(
      'R2 authenticated libp2p ACK may settle with local display label',
      () async {
        final original = makeMessage(id: 'r2-delete-local-label');
        messageRepo.seed([original]);
        final network = FakeP2PNetwork()..inboxDisabled = true;
        final sender = _ControlledDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
          sendResult: const SendMessageResult(sent: true, acked: true),
        );
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);
        addTearDown(sender.dispose);
        addTearDown(recipient.dispose);
        sender.localPeers.add('peer-bob');
        sender.testConnections.add(
          const p2p_state.ConnectionState(
            peerId: 'peer-bob',
            multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
            direction: 'outbound',
            status: 'connected',
          ),
        );

        final (_, tombstone) = await deleteMessageForEveryone(
          p2pService: sender,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(sender.sendWithReplyCallCount, 1);
        expect(sender.localSendCallCount, 0);
        expect(tombstone?.status, 'delivered');
        expect(tombstone?.transport, 'local');
        expect(tombstone?.isHidden, isTrue);
        expect(tombstone?.wireEnvelope, isNull);
      },
    );

    test(
      'R2 local delete write waits for pending direct commitment or custody',
      () async {
        final original = makeMessage(id: 'r2-local-delete-waits');
        messageRepo.seed([original]);
        final directGate = Completer<SendMessageResult>();
        final network = FakeP2PNetwork()..inboxDisabled = true;
        final sender = _ControlledDeleteP2PService(
          peerId: 'peer-alice',
          network: network,
          sendResult: const SendMessageResult(sent: false),
          sendGate: directGate,
        )..localPeers.add('peer-bob');
        final recipient = FakeP2PService(peerId: 'peer-bob', network: network);
        addTearDown(sender.dispose);
        addTearDown(recipient.dispose);

        var completed = false;
        final deletion = deleteMessageForEveryone(
          p2pService: sender,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );
        unawaited(deletion.then((_) => completed = true));

        await sender.sendEntered.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        try {
          expect(sender.localSendCallCount, 1);
          expect(completed, isFalse);
          final pending = await messageRepo.getMessage(original.id);
          expect(pending?.status, 'sending');
          expect(pending?.isHidden, isFalse);
          expect(pending?.wireEnvelope, isNotNull);
          expect(network.storeInInboxCallCount, 0);
        } finally {
          directGate.complete(
            const SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
          );
        }

        final (_, tombstone) = await deletion.timeout(
          const Duration(seconds: 5),
        );
        expect(tombstone?.status, 'delivered');
        expect(tombstone?.transport, 'direct');
        expect(tombstone?.isHidden, isTrue);
        expect(tombstone?.wireEnvelope, isNull);
        expect(network.storeInInboxCallCount, 0);
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

    test(
      'R3 delete reuse direct and relay share one committed ACK deadline',
      () {
        const preparationDelay = Duration(milliseconds: 200);
        const committedAckDelay = Duration(milliseconds: 2200);

        for (final adapter in const ['reuse', 'direct', 'relay']) {
          fakeAsync((async) {
            final repository = FakeMessageRepository();
            final original = makeMessage(id: 'r3-delete-$adapter');
            repository.seed([original]);
            final network = FakeP2PNetwork()..inboxDisabled = true;
            final sender = _R3DeleteDeadlineP2PService(
              peerId: 'peer-alice',
              network: network,
              defaultSendResult: SendMessageResult(
                sent: true,
                acked: true,
                transport: adapter == 'relay' ? 'relay' : 'direct',
              ),
            )..scriptedSendDelays.add(committedAckDelay);
            final recipient = FakeP2PService(
              peerId: 'peer-bob',
              network: network,
            );
            if (adapter == 'reuse') {
              sender.testConnections.add(
                const p2p_state.ConnectionState(
                  peerId: 'peer-bob',
                  multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
                  direction: 'outbound',
                  status: 'connected',
                ),
              );
            } else if (adapter == 'relay') {
              sender
                ..discoverAlwaysFails = true
                ..probeRelayResult = RelayProbeResult.connected;
            }
            (SendChatMessageResult, ConversationMessage?)? outcome;

            deleteMessageForEveryone(
              p2pService: sender,
              messageRepo: repository,
              originalMessage: original,
              bridge: _R3DelayedDeleteEncryptBridge(preparationDelay),
              recipientMlKemPublicKey: recipientMlKemPublicKey,
            ).then((value) => outcome = value);
            async.flushMicrotasks();
            async.elapse(preparationDelay);
            async.flushMicrotasks();
            async.elapse(committedAckDelay);
            async.flushMicrotasks();

            expect(outcome, isNotNull, reason: adapter);
            expect(outcome!.$1, SendChatMessageResult.success);
            expect(outcome!.$2!.status, 'delivered', reason: adapter);
            expect(sender.sendTimeouts, <int?>[5300], reason: adapter);
            if (adapter == 'reuse') {
              expect(sender.discoverTimeouts, isEmpty);
              expect(sender.dialTimeouts, isEmpty);
            } else if (adapter == 'direct') {
              expect(sender.discoverTimeouts, <int?>[2000]);
              expect(sender.dialTimeouts, <int?>[1500]);
            } else {
              expect(sender.discoverTimeouts, <int?>[2000]);
              expect(sender.dialTimeouts, <int?>[1500]);
            }
            sender.dispose();
            recipient.dispose();
          });
        }

        fakeAsync((async) {
          final repository = FakeMessageRepository();
          final original = makeMessage(id: 'r3-delete-progressive-sequence');
          repository.seed([original]);
          final network = FakeP2PNetwork()..inboxDisabled = true;
          final sender =
              _R3DeleteDeadlineP2PService(
                  peerId: 'peer-alice',
                  network: network,
                )
                ..testConnections.add(
                  const p2p_state.ConnectionState(
                    peerId: 'peer-bob',
                    multiaddrs: ['/ip4/10.0.0.2/tcp/4001'],
                    direction: 'outbound',
                    status: 'connected',
                  ),
                )
                ..probeRelayResult = RelayProbeResult.connected
                ..scriptedDiscoverDelay = const Duration(milliseconds: 500)
                ..scriptedDialDelays.addAll(const [
                  Duration(milliseconds: 500),
                  Duration(milliseconds: 250),
                ])
                ..scriptedDialResults.addAll(const [false, true])
                ..scriptedSendDelays.addAll(const [
                  Duration(milliseconds: 250),
                  committedAckDelay,
                ])
                ..scriptedSendResults.addAll(const [
                  SendMessageResult(sent: false),
                  SendMessageResult(
                    sent: true,
                    acked: true,
                    transport: 'relay',
                  ),
                ]);
          final recipient = FakeP2PService(
            peerId: 'peer-bob',
            network: network,
          );
          (SendChatMessageResult, ConversationMessage?)? outcome;

          deleteMessageForEveryone(
            p2pService: sender,
            messageRepo: repository,
            originalMessage: original,
            bridge: PassthroughCryptoBridge(),
            recipientMlKemPublicKey: recipientMlKemPublicKey,
          ).then((value) => outcome = value);
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 3700));
          async.flushMicrotasks();

          expect(outcome, isNotNull);
          expect(outcome!.$2!.status, 'delivered');
          expect(outcome!.$2!.transport, 'relay');
          expect(sender.sendTimeouts, <int?>[5500, 4000]);
          expect(sender.discoverTimeouts, <int?>[2000]);
          expect(sender.dialTimeouts, <int?>[1500, 1500]);
          expect(
            sender.sendTimeouts.last!,
            lessThan(sender.sendTimeouts.first!),
          );
          sender.dispose();
          recipient.dispose();
        });
      },
    );
  });
}
