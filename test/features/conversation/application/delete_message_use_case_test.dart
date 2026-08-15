import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/database/direct_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/services/p2p_service.dart'
    show RelayProbeResult;
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';
import 'package:flutter_app/core/config/direct_linked_event_fanout_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/features/conversation/application/direct_event_fanout_coordinator.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/delete_message_tombstone_visibility.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p_state;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
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

/// Plan 359 post-drain lineage digest: a well-formed 64-char lowercase hex
/// fingerprint is the only surviving strict proof once v108/v111 have drained.
const _tc359Fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A node that is not running: the delete lane must still retain its exact
/// v109 event and perform zero network work.
class _StoppedDeleteP2PService extends FakeP2PService {
  _StoppedDeleteP2PService({required super.peerId, required super.network});

  @override
  NodeState get currentState => NodeState(isStarted: false, peerId: peerId);
}

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

class _LifecycleOrderedDeleteP2PService extends FakeP2PService {
  _LifecycleOrderedDeleteP2PService({
    required super.peerId,
    required super.network,
    required this.events,
    required this.competingLeaseAcquired,
  });

  final List<String> events;
  final Future<void> competingLeaseAcquired;
  final Completer<void> firstSendEntered = Completer<void>();

  @override
  Future<bool> sendMessage(String targetPeerId, String message) async {
    // If the deletion starts transport before releasing its stage+cleanup
    // lease, the independently queued exclusive waiter can never complete and
    // this proof times out.
    await competingLeaseAcquired;
    events.add('network:$targetPeerId');
    if (!firstSendEntered.isCompleted) firstSendEntered.complete();
    return true;
  }
}

DirectEventFanoutAuthoring _lifecycleDeletionFanoutAuthoring({
  required List<String> events,
  required void Function({
    required OutgoingOrdinaryAttemptKind kind,
    required String eventId,
    required String parentMessageId,
    required List<DirectEventFanoutTargetCandidate> candidates,
  })
  onStageMutation,
}) => DirectEventFanoutAuthoring(
  selector: const DirectLinkedEventFanoutSelector.enabled(),
  linkedOrigin: false,
  senderTransportPeerId: 'peer-alice',
  readSnapshot: (contact) async {
    events.add('resolve');
    return DirectContactFanoutSnapshot(
      contactAccountPeerId: contact,
      contactAccountSigningPublicKey: 'signing-key',
      rosterInitialized: true,
      targets: const <DirectContactFanoutTargetFact>[
        DirectContactFanoutTargetFact(
          peerId: 'peer-device-a',
          mlKemPublicKey: 'mlkem-a',
          isLegacyAccountTarget: false,
          fingerprint:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          deviceId: 'device-a',
        ),
        DirectContactFanoutTargetFact(
          peerId: 'peer-device-b',
          mlKemPublicKey: 'mlkem-b',
          isLegacyAccountTarget: false,
          fingerprint:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          deviceId: 'device-b',
        ),
      ],
    );
  },
  encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
    events.add('encrypt:$recipientMlKemPublicKey');
    return (
      kem: 'kem-$recipientMlKemPublicKey',
      ciphertext: 'cipher-$recipientMlKemPublicKey',
      nonce: 'nonce-$recipientMlKemPublicKey',
    );
  },
  loadTextSiblings: (_) async => const [],
  stageTextFanout:
      ({
        required stagedRow,
        required messageId,
        required contactAccountPeerId,
        required senderTransportPeerId,
        required expectedSnapshot,
        required candidates,
      }) async => throw StateError('deletion never stages fresh text'),
  loadEventSiblings: (_) async => const [],
  stageMutationFanout:
      ({
        required expectedRow,
        required stagedRow,
        required kind,
        required eventId,
        required parentMessageId,
        required contactAccountPeerId,
        required senderTransportPeerId,
        required expectedSnapshot,
        required candidates,
      }) async {
        events.add('stage:${kind.name}');
        onStageMutation(
          kind: kind,
          eventId: eventId,
          parentMessageId: parentMessageId,
          candidates: candidates,
        );
        return DbDirectEventFanoutStageResult(
          outcome: DirectEventFanoutStageOutcome.applied,
          rows: <Map<String, Object?>>[
            for (final candidate in candidates)
              <String, Object?>{
                'recipient_peer_id': candidate.recipientPeerId,
                'event_id': eventId,
                'wire_envelope': candidate.wireEnvelope,
                'retry_count': 0,
                'last_attempt_at': null,
                'last_error_code': null,
                'contact_account_peer_id': contactAccountPeerId,
                'parent_message_id': parentMessageId,
                'created_at': '2026-08-14T12:00:00.000Z',
                'updated_at': '2026-08-14T12:00:00.000Z',
              },
          ],
        );
      },
  stageReactionFanout:
      ({
        required reactionRow,
        required action,
        required parentMessageId,
        required contactAccountPeerId,
        required senderTransportPeerId,
        required expectedSnapshot,
        required candidates,
      }) async => throw StateError('deletion never stages reactions'),
);

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
    DirectEventFanoutAuthoring deletionFanoutAuthoring({
      required bool selectorOn,
      required List<String> events,
      void Function({
        required OutgoingOrdinaryAttemptKind kind,
        required String eventId,
        required String parentMessageId,
        required List<DirectEventFanoutTargetCandidate> candidates,
      })?
      onStageMutation,
    }) => DirectEventFanoutAuthoring(
      selector: selectorOn
          ? const DirectLinkedEventFanoutSelector.enabled()
          : const DirectLinkedEventFanoutSelector.disabled(),
      linkedOrigin: false,
      senderTransportPeerId: 'peer-alice',
      readSnapshot: (contact) async {
        events.add('resolve');
        return DirectContactFanoutSnapshot(
          contactAccountPeerId: contact,
          contactAccountSigningPublicKey: 'signing-key',
          rosterInitialized: true,
          targets: const <DirectContactFanoutTargetFact>[
            DirectContactFanoutTargetFact(
              peerId: 'peer-device-a',
              mlKemPublicKey: 'mlkem-a',
              isLegacyAccountTarget: false,
              fingerprint:
                  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
              deviceId: 'device-a',
            ),
            DirectContactFanoutTargetFact(
              peerId: 'peer-device-b',
              mlKemPublicKey: 'mlkem-b',
              isLegacyAccountTarget: false,
              fingerprint:
                  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
              deviceId: 'device-b',
            ),
          ],
        );
      },
      encrypt: ({required recipientMlKemPublicKey, required plaintext}) async {
        events.add('encrypt:$recipientMlKemPublicKey');
        return (
          kem: 'k',
          ciphertext: 'ct-$recipientMlKemPublicKey',
          nonce: 'n',
        );
      },
      loadTextSiblings: (_) async => const [],
      stageTextFanout:
          ({
            required stagedRow,
            required messageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async => throw StateError('deletion never stages fresh text'),
      loadEventSiblings: (_) async => const [],
      stageMutationFanout:
          ({
            required expectedRow,
            required stagedRow,
            required kind,
            required eventId,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async {
            events.add('stage:${kind.name}');
            onStageMutation?.call(
              kind: kind,
              eventId: eventId,
              parentMessageId: parentMessageId,
              candidates: candidates,
            );
            return DbDirectEventFanoutStageResult(
              outcome: DirectEventFanoutStageOutcome.applied,
              rows: <Map<String, Object?>>[
                for (final candidate in candidates)
                  <String, Object?>{
                    'recipient_peer_id': candidate.recipientPeerId,
                    'event_id': eventId,
                    'wire_envelope': candidate.wireEnvelope,
                    'retry_count': 0,
                    'last_attempt_at': null,
                    'last_error_code': null,
                    'contact_account_peer_id': contactAccountPeerId,
                    'parent_message_id': parentMessageId,
                    'created_at': '2026-08-11T12:00:00.000Z',
                    'updated_at': '2026-08-11T12:00:00.000Z',
                  },
              ],
            );
          },
      stageReactionFanout:
          ({
            required reactionRow,
            required action,
            required parentMessageId,
            required contactAccountPeerId,
            required senderTransportPeerId,
            required expectedSnapshot,
            required candidates,
          }) async => throw StateError('deletion never stages reactions'),
    );

    test('TC-361-02a selector OFF refuses a blob-free DFE pre-crypto without '
        'demoting to the legacy single target', () async {
      final events = <String>[];
      final messageRepo = FakeMessageRepository();
      final original = makeMessage();
      await messageRepo.saveMessage(original);
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: 'peer-alice', network: network);
      addTearDown(p2pService.dispose);

      final (result, tombstone) = await deleteMessageForEveryone(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: original,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        directEventFanout: deletionFanoutAuthoring(
          selectorOn: false,
          events: events,
        ),
      );

      expect(result, SendChatMessageResult.sendFailed);
      expect(tombstone, isNull);
      expect(events, ['resolve']);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      final persisted = await messageRepo.getMessage(original.id);
      expect(persisted!.isDeleted, isFalse);
    });

    test('TC-361-02a ON stages the DFE batch through the shared owner with the '
        'persisted parent identity', () async {
      final events = <String>[];
      OutgoingOrdinaryAttemptKind? stagedKind;
      String? stagedEventId;
      String? stagedParent;
      List<DirectEventFanoutTargetCandidate>? stagedCandidates;
      final messageRepo = FakeMessageRepository();
      final original = makeMessage();
      await messageRepo.saveMessage(original);
      final p2pService = FakeP2PService(
        peerId: 'peer-alice',
        network: FakeP2PNetwork(),
      );
      addTearDown(p2pService.dispose);
      var stores = 0;
      Future<InboxStoreOutcome> store(
        String toPeerId,
        String message, {
        required AckCustodyKind custodyKind,
        int? timeoutMs,
      }) async {
        stores++;
        expect(custodyKind, AckCustodyKind.directMutationV109);
        return const InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          storeStatus: 'stored',
          custodyContract: ackOrExpiryInboxCustodyContract,
          expiresAtMs: 1900000060000,
        );
      }

      final (result, _) = await deleteMessageForEveryone(
        p2pService: p2pService,
        messageRepo: messageRepo,
        originalMessage: original,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        storeInAckCustodyInboxDetailed: store,
        directEventFanout: deletionFanoutAuthoring(
          selectorOn: true,
          events: events,
          onStageMutation:
              ({
                required kind,
                required eventId,
                required parentMessageId,
                required candidates,
              }) {
                stagedKind = kind;
                stagedEventId = eventId;
                stagedParent = parentMessageId;
                stagedCandidates = candidates;
              },
        ),
      );

      expect(result, SendChatMessageResult.success);
      expect(stagedKind, OutgoingOrdinaryAttemptKind.tombstoneInitial);
      expect(stagedEventId, isNotNull);
      expect(
        stagedParent,
        original.id,
        reason:
            'the clear deletion envelope hides its target, so the '
            'batch persists the logical parent explicitly',
      );
      expect(stagedCandidates, hasLength(2));
      expect(
        stagedCandidates!.map((candidate) => candidate.wireEnvelope).toSet(),
        hasLength(2),
      );
      expect(
        events.indexOf('stage:tombstoneInitial'),
        greaterThan(events.lastIndexOf('resolve')),
      );
      expect(stores, 2, reason: 'each committed row rides its own store');
    });

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
        expect(
          pending.status,
          anyOf('sending', 'inboxed'),
          reason:
              '356: the private lane now owns an exact v109 event, so accepted '
              'protected custody may already have projected the durable '
              'tombstone to inboxed while the live leg is still in flight',
        );

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
      'Plan 349 protected mutation custody wins after every live delete leg fails',
      () async {
        final original = makeMessage(id: 'delete-mutation-custody-tail');
        messageRepo.seed([original]);

        final network = FakeP2PNetwork();
        final p2pService = FakeP2PService(
          peerId: 'peer-alice',
          network: network,
        );
        addTearDown(p2pService.dispose);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: messageRepo,
          originalMessage: original,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.success);
        expect(tombstone?.status, 'inboxed');
        expect(tombstone?.transport, 'inbox');
        expect(tombstone?.isHidden, isFalse);
        expect(network.storeInInboxCallCount, 1);
        expect(messageRepo.directMutationCustodyRows, isEmpty);
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

    test('outgoing proof-less disappearing delete-for-everyone keeps legacy '
        'transport under private-owner cleanup', () async {
      // 359: the historical proof-less row still takes ordinary legacy
      // transport with no event id, but its artifacts belong to the private
      // lifecycle owner — never to generic attachment deletion.
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const messageId = 'disappearing-delete-everyone';
      const attachmentId = '$messageId-att';
      await fixture.seedDirectParent(messageId, contactPeerId: 'peer-bob');
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'sender_peer_id': 'peer-alice',
          'status': 'delivered',
          'is_incoming': 0,
          'private_media_policy_version': 1,
          'private_media_mode': 'disappearing',
          'private_media_duration_seconds': 3600,
          'private_media_state': 'available',
        },
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: attachmentId,
          messageId: messageId,
          localPath: MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: 'peer-bob',
            blobId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'done',
        ).copyWith(
          encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: 'blob_aes_256_gcm_v1',
        ),
        owner: MediaOwnerLane.direct,
      );
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        isTrue,
      );
      final original = (await fixture.messageRepo.getMessage(messageId))!;

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
        messageRepo: fixture.messageRepo,
        originalMessage: original,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(result, SendChatMessageResult.success);
      expect(tombstone, isNotNull);
      expect(tombstone!.privateMediaPolicy.mode, PrivateMediaMode.disappearing);
      expect(
        await fixture.db.query('direct_reaction_inbox_custody_outbox'),
        isEmpty,
        reason: 'a proof-less disappearing row never gains a v109 event',
      );
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
        reason: 'only the private lifecycle owner retires the secure key',
      );
    });

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
          expect(
            network.storeInInboxCallCount,
            1,
            reason: 'the mutation custody hedge starts beside live delivery',
          );
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
        expect(network.storeInInboxCallCount, 1);
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
        final original = makeMessage(
          privateMediaPolicy: PrivateMediaPolicy.disappearing(3600),
        );
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

  group('Plan 351 ordinary direct-media delete-for-everyone custody', () {
    const sender = 'peer-alice';
    const recipient = 'contact-1';
    const t0 = '2026-08-09T09:00:00.000Z';
    const nowMs = 1900000000000;

    /// Seeds one delivered strict ordinary direct-media parent whose complete
    /// v111 generation is still bound to its live v108 incarnation.
    Future<ConversationMessage> seedStrictMediaParent(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async {
      const incarnationId = 'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0';
      final attachmentId = '$messageId-a';
      const contentHash =
          '1111111111111111111111111111111111111111111111111111111111111111';
      const ciphertextSize = 41;
      const expiresAtMs = nowMs + 60000;
      final initialEnvelope = jsonEncode(<String, Object?>{
        'type': 'chat_message',
        'version': '2',
        'id': messageId,
        'senderPeerId': sender,
        'encrypted': const <String, Object?>{
          'kem': 'kem-initial',
          'ciphertext': 'cipher-initial',
          'nonce': 'nonce-initial',
        },
      });
      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': recipient,
        'sender_peer_id': sender,
        'text': 'strict media',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': t0,
        'wire_envelope': initialEnvelope,
      });
      await fixture.db.insert('media_attachments', <String, Object?>{
        'id': attachmentId,
        'message_id': messageId,
        'owner_lane': 'direct',
        'mime': 'image/jpeg',
        'size': 800,
        'media_type': 'image',
        'local_path': 'media/direct/$attachmentId.jpg',
        'download_status': 'done',
        'created_at': t0,
        'content_hash': contentHash,
      });
      final commitment = DirectMediaBlobCustodyCommitment(
        contentHash: contentHash,
        ciphertextSize: ciphertextSize,
        expiresAtMs: expiresAtMs,
      );
      await fixture.db.insert(
        kDirectMediaBlobCustodyTable,
        DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingStored,
          inboxCustodyIncarnationId: incarnationId,
          recipientPeerId: recipient,
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'a' * 64}/$attachmentId.blob',
          contentHash: contentHash,
          ciphertextSize: ciphertextSize,
          expiresAtMs: expiresAtMs,
          custodyRelayPeerId: 'relay-1',
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: t0,
          updatedAt: t0,
        ).toMap(),
      );
      await fixture.db.insert('direct_inbox_custody_outbox', <String, Object?>{
        'recipient_peer_id': recipient,
        'message_id': messageId,
        'incarnation_id': incarnationId,
        'wire_envelope': initialEnvelope,
        'retry_count': 0,
        'created_at': t0,
        'updated_at': t0,
        'media_blob_manifest_hash': computeDirectMediaBlobManifestHash(
          <DirectMediaBlobManifestProjection>[
            DirectMediaBlobManifestProjection(
              attachmentId: attachmentId,
              commitment: commitment,
            ),
          ],
        ),
        'media_blob_expires_at_ms': expiresAtMs,
      });
      return (await fixture.messageRepo.getMessage(messageId))!;
    }

    test(
      'TC-351-03 node-off media deletion retains one exact v109 event, cleans '
      'up only after stage, and performs zero network',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final original = await seedStrictMediaParent(fixture, 'tc351-node-off');

        final network = FakeP2PNetwork();
        final p2pService = _StoppedDeleteP2PService(
          peerId: sender,
          network: network,
        );
        addTearDown(p2pService.dispose);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.nodeNotRunning);
        expect(tombstone, isNotNull);
        expect(tombstone!.isDeleted, isTrue);
        expect(network.storeInInboxCallCount, 0);

        final custody = await fixture.db.query(
          'direct_reaction_inbox_custody_outbox',
        );
        expect(custody, hasLength(1), reason: 'the exact event is retained');
        expect(custody.single['recipient_peer_id'], recipient);
        final envelope =
            jsonDecode(custody.single['wire_envelope']! as String)
                as Map<String, dynamic>;
        expect(envelope['type'], 'message_deletion');
        expect(envelope['eventId'], custody.single['event_id']);

        // Post-authority cleanup ran even though the node was stopped.
        expect(
          await fixture.repo.getAttachmentsForMessage(
            original.id,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
        );
        // The live v108 and its bound v111 generation are preserved.
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[original.id],
          ),
          hasLength(1),
        );
        expect(
          (await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[original.id],
          )).single['state'],
          'outgoing_stored',
        );
      },
    );

    test(
      'TC-351-03 protected acceptance settles the exact media tombstone after '
      'cleanup has already removed its attachments',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final original = await seedStrictMediaParent(fixture, 'tc351-accepted');

        final network = FakeP2PNetwork();
        final p2pService = FakeP2PService(peerId: sender, network: network);
        addTearDown(p2pService.dispose);

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
        expect(tombstone?.isDeleted, isTrue);
        expect(
          await fixture.db.query('direct_reaction_inbox_custody_outbox'),
          isEmpty,
          reason: 'accepted protected custody retires the exact event',
        );
        final settled = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[original.id],
        )).single;
        expect(settled['status'], 'inboxed');
        expect(settled['transport'], 'inbox');
        expect(settled['deleted_at'], isNotNull);
        expect(
          await fixture.repo.getAttachmentsForMessage(
            original.id,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
          reason: 'attachment absence cannot invalidate terminal settlement',
        );
      },
    );

    test(
      'TC-351-03 a contradictory blob generation refuses without mutating the '
      'parent, v111 or v109',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final original = await seedStrictMediaParent(fixture, 'tc351-crossed');
        // Retire the exact v108 while its generation stays bound: a bound
        // generation without its incarnation is a contradiction.
        await fixture.db.delete(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[original.id],
        );

        final network = FakeP2PNetwork();
        final p2pService = FakeP2PService(peerId: sender, network: network);
        addTearDown(p2pService.dispose);

        final (result, tombstone) = await deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(result, SendChatMessageResult.invalidMessage);
        expect(tombstone, isNull);
        expect(network.storeInInboxCallCount, 0);
        expect(
          await fixture.db.query('direct_reaction_inbox_custody_outbox'),
          isEmpty,
        );
        expect(
          (await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[original.id],
          )).single['deleted_at'],
          isNull,
        );
        expect(
          (await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[original.id],
          )).single['state'],
          'outgoing_stored',
        );
        expect(
          await fixture.repo.getAttachmentsForMessage(
            original.id,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
          reason: 'no cleanup may precede stage authorization',
        );
      },
    );

    test('TC-352-03 post-drain strict-media delete retains v109 while node '
        'stopped', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      final original = await seedStrictMediaParent(fixture, 'tc352-post-drain');
      final attachmentId = '${original.id}-a';
      final v108 = (await fixture.db.query(
        'direct_inbox_custody_outbox',
        where: 'message_id = ?',
        whereArgs: <Object?>[original.id],
      )).single;
      final stored = DirectMediaBlobCustodyRow.fromMap(
        (await fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[original.id],
        )).single,
      );
      final expectedFingerprint = computeDirectMediaBlobCommitmentFingerprint(
        attachmentId: stored.attachmentId,
        commitment: DirectMediaBlobCustodyCommitment(
          kind: stored.custodyKind,
          contract: stored.custodyContract,
          contentHash: stored.contentHash,
          ciphertextSize: stored.ciphertextSize,
          transportMime: stored.transportMime,
          expiresAtMs: stored.expiresAtMs!,
        ),
      );

      // Protected inbox custody accepts the initial: the delivered parent
      // is preserved and its lineage becomes durable.
      expect(
        await dbCompleteAcceptedDirectInboxCustodyIfExact(
          fixture.db,
          recipientPeerId: recipient,
          messageId: original.id,
          expectedIncarnationId: v108['incarnation_id']! as String,
          expectedWireEnvelope: v108['wire_envelope']! as String,
          relayExpiresAt:
              (v108['media_blob_expires_at_ms']! as num).toInt() - 1,
        ),
        DirectInboxCustodyCompletionOutcome.messagePreserved,
      );
      final completedParent = (await fixture.messageRepo.getMessage(
        original.id,
      ))!;
      expect(completedParent.status, 'delivered');
      expect(completedParent.wireEnvelope, original.wireEnvelope);
      expect(
        (await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[attachmentId],
        )).single['direct_media_blob_custody_fingerprint'],
        expectedFingerprint,
      );

      // Cleanup physically drains every remaining v111 row: the lineage
      // fingerprint is now the only surviving strict proof.
      for (final row in (await fixture.db.query(
        kDirectMediaBlobCustodyTable,
        where: 'message_id = ?',
        whereArgs: <Object?>[original.id],
      )).map(DirectMediaBlobCustodyRow.fromMap)) {
        expect(
          await dbDeleteDirectMediaBlobCleanupPendingIfExact(
            fixture.db,
            expected: row,
          ),
          isTrue,
        );
      }
      expect(
        await fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[original.id],
        ),
        isEmpty,
      );
      expect(
        (await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[attachmentId],
        )).single['direct_media_blob_custody_fingerprint'],
        expectedFingerprint,
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          fixture.db,
          messageId: original.id,
        ),
        OutgoingDirectDeletionLane.strictMedia,
      );

      final network = FakeP2PNetwork();
      final p2pService = _StoppedDeleteP2PService(
        peerId: sender,
        network: network,
      );
      addTearDown(p2pService.dispose);

      final (result, tombstone) = await deleteMessageForEveryone(
        p2pService: p2pService,
        messageRepo: fixture.messageRepo,
        originalMessage: completedParent,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(result, SendChatMessageResult.nodeNotRunning);
      expect(tombstone, isNotNull);
      expect(tombstone!.isDeleted, isTrue);
      expect(network.storeInInboxCallCount, 0);

      final custody = await fixture.db.query(
        'direct_reaction_inbox_custody_outbox',
      );
      expect(
        custody,
        hasLength(1),
        reason: 'a fully drained strict parent still owns protected custody',
      );
      expect(custody.single['recipient_peer_id'], recipient);
      final envelope =
          jsonDecode(custody.single['wire_envelope']! as String)
              as Map<String, dynamic>;
      expect(envelope['type'], 'message_deletion');
      expect(envelope['eventId'], custody.single['event_id']);
    });

    test(
      'TC-366-02b media DFE stages all targets inside the lifecycle lease before cleanup',
      () async {
        final lifecycleLock = MediaAttachmentLifecycleLock();
        final fixture = await MediaRepositoryRealDbFixture.create(
          lifecycleLock: lifecycleLock,
        );
        addTearDown(fixture.dispose);
        final original = await seedStrictMediaParent(
          fixture,
          'tc366-02b-media-dfe',
        );
        final events = <String>[];
        final competingLeaseAcquired = Completer<void>();
        final releaseCompetingLease = Completer<void>();
        Future<void>? competingLease;
        List<DirectEventFanoutTargetCandidate>? stagedTargets;

        final manager = _ObservingDeleteMediaFileManager(
          onFirstDelete: () async {
            events.add('cleanup');
            expect(stagedTargets, hasLength(2));
            expect(
              competingLeaseAcquired.isCompleted,
              isFalse,
              reason:
                  'cleanup remains inside the incumbent exclusive lease that '
                  'already staged every physical target',
            );
          },
        );
        final network = FakeP2PNetwork();
        final service = _LifecycleOrderedDeleteP2PService(
          peerId: sender,
          network: network,
          events: events,
          competingLeaseAcquired: competingLeaseAcquired.future,
        );
        addTearDown(service.dispose);
        addTearDown(() {
          if (!releaseCompetingLease.isCompleted) {
            releaseCompetingLease.complete();
          }
        });

        final authoring = _lifecycleDeletionFanoutAuthoring(
          events: events,
          onStageMutation:
              ({
                required kind,
                required eventId,
                required parentMessageId,
                required candidates,
              }) {
                expect(kind, OutgoingOrdinaryAttemptKind.tombstoneInitial);
                expect(parentMessageId, original.id);
                stagedTargets = List<DirectEventFanoutTargetCandidate>.of(
                  candidates,
                );
                // Run outside the inherited lock Zone. It can enter only
                // after the use case releases its stage+cleanup lease.
                competingLease = Zone.root.run(
                  () => lifecycleLock.synchronizedAll(() async {
                    events.add('competing-lease');
                    if (!competingLeaseAcquired.isCompleted) {
                      competingLeaseAcquired.complete();
                    }
                    await releaseCompetingLease.future;
                  }),
                );
              },
        );

        final (result, _) = await deleteMessageForEveryone(
          p2pService: service,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: manager,
          directEventFanout: authoring,
          // A plural route owns per-target encryption and must not require the
          // legacy single-recipient bridge/key pair.
        );

        expect(result, SendChatMessageResult.success);
        expect(stagedTargets, hasLength(2));
        await service.firstSendEntered.future.timeout(
          const Duration(seconds: 5),
        );
        expect(
          events.indexOf('stage:tombstoneInitial'),
          greaterThanOrEqualTo(0),
        );
        expect(
          events.indexOf('cleanup'),
          greaterThan(events.indexOf('stage:tombstoneInitial')),
        );
        expect(
          events.indexOf('competing-lease'),
          greaterThan(events.indexOf('cleanup')),
        );
        expect(
          events.indexWhere((event) => event.startsWith('network:')),
          greaterThan(events.indexOf('competing-lease')),
          reason: 'all network begins after the incumbent lease is released',
        );

        releaseCompetingLease.complete();
        await competingLease;
      },
    );
  });

  group('Plan 354 private local hide and strict handoff', () {
    test('TC-354-02d private local hide and strict handoff have no post-terminal '
        'egress', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const messageId = 'tc354-02d-hide';
      const attachmentId = 'tc354-02d-hide-attachment';
      final original = await seedPrivateDeleteForEveryoneParent(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      // A live prepared v111 generation exists for this parent.
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.outgoing,
        state: DirectMediaBlobCustodyState.outgoingPrepared,
        inboxCustodyIncarnationId: null,
        recipientPeerId: 'peer-bob',
        ciphertextRelativePath:
            'direct_media_blob_custody_v1/'
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'
            '$attachmentId.blob',
        contentHash:
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        ciphertextSize: 4096,
        expiresAtMs: null,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-10T12:00:00.000Z',
        updatedAt: '2026-08-10T12:00:00.000Z',
      );
      await fixture.db.insert(kDirectMediaBlobCustodyTable, custody.toMap());

      final count = await deleteMessageForMe(
        message: original,
        messageRepo: fixture.messageRepo,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: mediaFileManager,
      );
      expect(count, 1);

      // The hide is durable and terminal.
      final hidden = await fixture.messageRepo.getMessage(messageId);
      expect(hidden?.hiddenAt, isNotNull);

      // A hide that wins before the strict handoff produces ZERO later
      // egress: the strict envelope+v108+v111 transaction refuses because
      // its parent is no longer a live private owner.
      final blocked =
          await dbCommitOutgoingDirectPrivateWireEnvelopeWithInboxCustody(
            fixture.db,
            <String, Object?>{
              'id': attachmentId,
              'message_id': messageId,
              'owner_lane': 'direct',
              'mime': 'image/jpeg',
              'size': 1024,
              'media_type': 'image',
              'local_path': MediaFilePathConvention.relativePathForAttachment(
                contactPeerId: 'peer-bob',
                blobId: attachmentId,
                mime: 'image/jpeg',
              ),
              'download_status': 'done',
              'created_at': '2026-08-10T12:00:00.000Z',
              'content_hash': custody.contentHash,
              'encryption_key_base64': 'ref',
              'encryption_nonce': 'nonce',
              'encryption_scheme': 'blob_aes_256_gcm_v1',
            },
            expectedPendingLocalPath:
                'pending_uploads/$messageId/$attachmentId.jpg',
            envelope: '{"type":"chat_message"}',
            hasOwnedPendingCompletion: false,
            wireMediaBlobManifestHash: 'f' * 64,
            wireMediaBlobExpiresAtMs: 2100000000000,
          );
      expect(
        blocked.authorizesTransport,
        isFalse,
        reason: 'a hidden parent can never authorize chat egress',
      );
      expect(
        await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        ),
        isEmpty,
        reason: 'no v108 obligation may be created behind a hide',
      );

      // Retention-first cleanup: the live prepared generation keeps its
      // complete projection so the global drain can still terminalize it.
      expect(
        await fixture.rawAttachmentRow(attachmentId),
        isNotNull,
        reason:
            'a live outgoing_prepared v111 retains its attachment until the '
            'global blob drain terminalizes that independent authority',
      );
      expect(
        await fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        ),
        hasLength(1),
      );
    });
  });

  group('Plan 356 private delete-for-everyone v109 custody', () {
    const sender = 'peer-alice';
    const recipient = 'peer-bob';

    /// Reads the one physical v109 outbox, which the private deletion event
    /// must share byte-for-byte with every other direct mutation owner.
    Future<List<Map<String, Object?>>> v109Rows(
      MediaRepositoryRealDbFixture fixture,
    ) => fixture.db.query('direct_reaction_inbox_custody_outbox');

    /// In-memory fixtures share one SQLite instance in a test file, so every
    /// v109 assertion here is scoped to its own deletion target.
    Future<List<Map<String, Object?>>> v109RowsFor(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async => (await v109Rows(fixture))
        .where((row) => (row['wire_envelope']! as String).contains(messageId))
        .toList(growable: false);

    Future<Map<String, Object?>?> parentRow(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async {
      final rows = await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      return rows.isEmpty ? null : rows.single;
    }

    test('TC-356-01a private deletion atomically stages tombstone and v109 '
        'before cleanup or network', () async {
      Future<void> proveOneMode({
        required String suffix,
        required String mode,
        required String parentStatus,
        String? hiddenAt,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final messageId = 'tc356-01a-$suffix';
        final attachmentId = '$messageId-att';
        await seedPrivateDeleteForEveryoneParent(
          fixture,
          messageId: messageId,
          attachmentId: attachmentId,
        );
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'private_media_mode': mode,
            'status': parentStatus,
            'hidden_at': hiddenAt,
          },
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        );
        final original = (await fixture.messageRepo.getMessage(messageId))!;

        // The first artifact removal must already observe the durable
        // tombstone AND its exact v109 obligation.
        List<Map<String, Object?>>? custodyAtFirstCleanup;
        Map<String, Object?>? parentAtFirstCleanup;
        final fileManager = _ObservingDeleteMediaFileManager(
          onFirstDelete: () async {
            custodyAtFirstCleanup = await v109Rows(fixture);
            parentAtFirstCleanup = await parentRow(fixture, messageId);
          },
        );

        final network = FakeP2PNetwork();
        final p2pService = _GatedNetworkDeleteP2PService(
          peerId: sender,
          network: network,
        );
        final peer = FakeP2PService(peerId: recipient, network: network);
        addTearDown(p2pService.releaseAll);
        addTearDown(p2pService.dispose);
        addTearDown(peer.dispose);

        final deletion = deleteMessageForEveryone(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          originalMessage: original,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: fileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );
        await p2pService.sendEntered.future.timeout(const Duration(seconds: 5));
        expect(
          p2pService.legacyStoreInInboxCalls,
          0,
          reason: 'a v109 owner never enters the legacy inbox store',
        );

        // Network entered: the exact event is already durable.
        final custodyAtNetwork = await v109RowsFor(fixture, messageId);
        expect(
          custodyAtNetwork,
          hasLength(1),
          reason: 'no live transport may precede the exact v109 obligation',
        );
        final custody = custodyAtNetwork.single;
        expect(custody['recipient_peer_id'], recipient);
        final eventId = custody['event_id'] as String?;
        expect(eventId, isNotNull);
        expect(eventId!.trim(), isNotEmpty);

        // One raw identity across the v109 key, the clear outer envelope and
        // the decrypted inner deletion payload.
        final outer =
            jsonDecode(custody['wire_envelope']! as String)
                as Map<String, dynamic>;
        expect(outer['type'], 'message_deletion');
        expect(outer['version'], '2');
        expect(outer['eventId'], eventId);
        expect(outer['senderPeerId'], sender);
        final inner =
            jsonDecode(
                  (outer['encrypted'] as Map<String, dynamic>)['ciphertext']!
                      as String,
                )
                as Map<String, dynamic>;
        expect(inner['eventId'], eventId);
        expect(inner['senderPeerId'], sender);
        expect(inner['messageId'], messageId);

        final tombstoneAtNetwork = (await parentRow(fixture, messageId))!;
        expect(tombstoneAtNetwork['text'], '');
        expect(tombstoneAtNetwork['deleted_by_peer_id'], sender);
        expect(tombstoneAtNetwork['deleted_at'], isNotNull);
        expect(
          tombstoneAtNetwork['wire_envelope'],
          custody['wire_envelope'],
          reason: 'the parent projects the exact retained event',
        );
        expect(tombstoneAtNetwork['private_media_policy_version'], 1);
        expect(tombstoneAtNetwork['private_media_mode'], mode);

        // Cleanup observed the same atomic commit, never a half state.
        expect(
          custodyAtFirstCleanup,
          hasLength(1),
          reason: 'private artifact cleanup may not precede the v109 stage',
        );
        expect(parentAtFirstCleanup?['deleted_at'], isNotNull);

        p2pService.releaseSend.complete();
        final (result, tombstone) = await deletion.timeout(
          const Duration(seconds: 5),
        );
        expect(result, SendChatMessageResult.success);
        expect(tombstone?.isDeleted, isTrue);
        expect(
          await v109RowsFor(fixture, messageId),
          hasLength(1),
          reason: 'a live ACK never awaits or cancels the scheduled hedge',
        );
        p2pService.releaseAckCustody.complete();
        await p2pService.ackCustodySettled.timeout(const Duration(seconds: 5));
        expect(p2pService.legacyStoreInInboxCalls, 0);
        expect(
          await fixture.repo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
          reason: 'the terminal private claim removes its artifacts',
        );
      }

      await proveOneMode(
        suffix: 'protected-delivered',
        mode: 'protected',
        parentStatus: 'delivered',
      );
      await proveOneMode(
        suffix: 'view-once-inboxed',
        mode: 'view_once',
        parentStatus: 'inboxed',
      );
      await proveOneMode(
        suffix: 'protected-hidden',
        mode: 'protected',
        parentStatus: 'delivered',
        hiddenAt: '2026-08-10T12:30:00.000Z',
      );
    });

    test(
      'TC-356-02 protected and view-once delete retain v109 across lifecycle '
      'node-off and live ACK',
      () async {
        // 1. Node-off: the exact owner is staged, private cleanup runs, the
        //    still-present tombstone settles to failed and nothing is sent.
        final offline = await MediaRepositoryRealDbFixture.create();
        addTearDown(offline.dispose);
        const offlineId = 'tc356-02-node-off';
        final offlineParent = await seedPrivateDeleteForEveryoneParent(
          offline,
          messageId: offlineId,
          attachmentId: '$offlineId-att',
        );
        final offlineNetwork = FakeP2PNetwork();
        final stopped = _StoppedDeleteP2PService(
          peerId: sender,
          network: offlineNetwork,
        );
        addTearDown(stopped.dispose);

        final (
          offlineResult,
          offlineTombstone,
        ) = await deleteMessageForEveryone(
          p2pService: stopped,
          messageRepo: offline.messageRepo,
          originalMessage: offlineParent,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: offline.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(offlineResult, SendChatMessageResult.nodeNotRunning);
        expect(offlineTombstone, isNotNull);
        expect(offlineTombstone!.isDeleted, isTrue);
        expect(offlineTombstone.status, 'failed');
        expect(offlineNetwork.storeInInboxCallCount, 0);
        expect(offlineNetwork.deliverCallCount, 0);
        expect(
          await v109RowsFor(offline, offlineId),
          hasLength(1),
          reason: 'a stopped node never discards the exact deletion event',
        );
        final offlineRow = (await parentRow(offline, offlineId))!;
        expect(offlineRow['status'], 'failed');
        expect(offlineRow['deleted_at'], isNotNull);
        expect(offlineRow['private_media_policy_version'], 1);
        expect(
          await offline.repo.getAttachmentsForMessage(
            offlineId,
            owner: MediaOwnerLane.direct,
          ),
          isEmpty,
          reason: 'incumbent private cleanup still runs behind the stage',
        );

        // 2. Live ACK returns without awaiting the scheduled hedge, and the
        //    accepted protected custody settles the exact tombstone.
        final live = await MediaRepositoryRealDbFixture.create();
        addTearDown(live.dispose);
        const liveId = 'tc356-02-live-ack';
        final liveParent = await seedPrivateDeleteForEveryoneParent(
          live,
          messageId: liveId,
          attachmentId: '$liveId-att',
        );
        final liveNetwork = FakeP2PNetwork();
        final liveService = _GatedNetworkDeleteP2PService(
          peerId: sender,
          network: liveNetwork,
        );
        final livePeer = FakeP2PService(
          peerId: recipient,
          network: liveNetwork,
        );
        addTearDown(liveService.releaseAll);
        addTearDown(liveService.dispose);
        addTearDown(livePeer.dispose);
        // The live leg answers immediately; only the protected hedge is gated.
        liveService.releaseSend.complete();

        final (liveResult, liveTombstone) = await deleteMessageForEveryone(
          p2pService: liveService,
          messageRepo: live.messageRepo,
          originalMessage: liveParent,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: live.repo,
          mediaFileManager: mediaFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(liveResult, SendChatMessageResult.success);
        expect(liveTombstone, isNotNull);
        expect(liveTombstone!.isDeleted, isTrue);
        expect(
          liveService.legacyStoreInInboxCalls,
          0,
          reason: 'a v109 owner never enters the legacy inbox store',
        );
        expect(
          await v109RowsFor(live, liveId),
          hasLength(1),
          reason: 'the live ACK returned without awaiting the hedge',
        );

        // Accepted protected custody then settles the exact tombstone and
        // retires only that event.
        liveService.releaseAckCustody.complete();
        await liveService.ackCustodySettled.timeout(const Duration(seconds: 5));
        expect(await v109RowsFor(live, liveId), isEmpty);
        final settledLive = (await parentRow(live, liveId))!;
        expect(settledLive['deleted_at'], isNotNull);
        expect(settledLive['private_media_policy_version'], 1);

        // 3. A repository without the private staging capability performs zero
        //    cleanup and zero transport.
        final refused = await MediaRepositoryRealDbFixture.create();
        addTearDown(refused.dispose);
        const refusedId = 'tc356-02-capability-absent';
        final refusedParent = await seedPrivateDeleteForEveryoneParent(
          refused,
          messageId: refusedId,
          attachmentId: '$refusedId-att',
        );
        final refusedNetwork = FakeP2PNetwork();
        final refusedService = FakeP2PService(
          peerId: sender,
          network: refusedNetwork,
        );
        addTearDown(refusedService.dispose);
        final refusedFileManager = FakeMediaFileManager();

        final (
          capabilityResult,
          capabilityTombstone,
        ) = await deleteMessageForEveryone(
          p2pService: refusedService,
          messageRepo: _PrivateStageIncapableMessageRepository(
            refused.messageRepo,
          ),
          originalMessage: refusedParent,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: refused.repo,
          mediaFileManager: refusedFileManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(capabilityResult, SendChatMessageResult.sendFailed);
        expect(capabilityTombstone, isNull);
        expect(refusedNetwork.deliverCallCount, 0);
        expect(refusedNetwork.storeInInboxCallCount, 0);
        expect(await v109RowsFor(refused, refusedId), isEmpty);
        expect((await parentRow(refused, refusedId))!['deleted_at'], isNull);
        expect(refusedFileManager.deletedFilePaths, isEmpty);
        expect(
          await refused.repo.getAttachmentsForMessage(
            refusedId,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
        );
      },
    );
  });

  group('Plan 357 private deletion closure repair', () {
    const sender = 'peer-alice';

    Future<List<Map<String, Object?>>> v109RowsFor(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async => (await fixture.db.query('direct_reaction_inbox_custody_outbox'))
        .where((row) => (row['wire_envelope']! as String).contains(messageId))
        .toList(growable: false);

    test('TC-357-01b private deletion replay without a committed tombstone '
        'cannot clean or transmit', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const messageId = 'tc357-01b-null-row';
      const attachmentId = '$messageId-att';
      final original = await seedPrivateDeleteForEveryoneParent(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(peerId: sender, network: network);
      final peer = FakeP2PService(peerId: 'peer-bob', network: network);
      addTearDown(p2pService.dispose);
      addTearDown(peer.dispose);
      final fileManager = FakeMediaFileManager();
      final localReactions = _RecordingReactionRepository();

      // The physical v109 stage really runs and really authorizes: only its
      // committed transaction row is withheld.
      final repository = _NullCommittedRowPrivateStageRepository(
        fixture.messageRepo,
      );

      final (result, tombstone) = await deleteMessageForEveryone(
        p2pService: p2pService,
        messageRepo: repository,
        originalMessage: original,
        reactionRepo: localReactions,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: fileManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(result, SendChatMessageResult.invalidMessage);
      expect(tombstone, isNull);
      expect(
        repository.stageCalls,
        1,
        reason: 'the authorized stage really ran before the guard refused',
      );
      expect(
        repository.lastAuthorizedTransport,
        isTrue,
        reason: 'an authorized custody result reached the application guard',
      );
      expect(
        network.deliverCallCount,
        0,
        reason: 'an uncommitted in-memory tombstone can never be transmitted',
      );
      expect(network.storeInInboxCallCount, 0);
      expect(fileManager.deletedFilePaths, isEmpty);
      expect(
        localReactions.deleteForMessageCalls,
        isEmpty,
        reason: 'terminal cleanup never starts without a committed tombstone',
      );
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
        reason: 'no private artifact may be cleaned without a durable row',
      );
    });

    test('TC-357-03 reaction retirement failure after private stage cannot '
        'suppress cleanup or settlement', () async {
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const messageId = 'tc357-03-reaction-failure';
      const attachmentId = '$messageId-att';
      final original = await seedPrivateDeleteForEveryoneParent(
        fixture,
        messageId: messageId,
        attachmentId: attachmentId,
      );

      final network = FakeP2PNetwork();
      final stopped = _StoppedDeleteP2PService(
        peerId: sender,
        network: network,
      );
      addTearDown(stopped.dispose);
      final throwingReactions = _ThrowingReactionRepository();
      final fileManager = FakeMediaFileManager();

      final (result, tombstone) = await deleteMessageForEveryone(
        p2pService: stopped,
        messageRepo: fixture.messageRepo,
        originalMessage: original,
        reactionRepo: throwingReactions,
        mediaAttachmentRepo: fixture.repo,
        mediaFileManager: fileManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(
        throwingReactions.deleteForMessageCalls,
        contains(messageId),
        reason: 'reaction retirement really was attempted and really threw',
      );
      expect(
        result,
        SendChatMessageResult.nodeNotRunning,
        reason: 'a non-authoritative reaction failure cannot escape the lane',
      );
      expect(tombstone, isNotNull);
      expect(tombstone!.isDeleted, isTrue);
      expect(tombstone.status, 'failed');
      expect(tombstone.transport, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
      expect(
        await v109RowsFor(fixture, messageId),
        hasLength(1),
        reason: 'the exact event stays retryable behind the durable tombstone',
      );
      final row = (await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      )).single;
      expect(row['status'], 'failed');
      expect(row['deleted_at'], isNotNull);
      expect(
        await fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
        reason: 'incumbent private lifecycle cleanup still ran',
      );
      expect(await fixture.rawAttachmentRow(attachmentId), isNull);
      expect(fileManager.deletedFilePaths, isNotEmpty);
    });
  });

  group('Plan 359 disappearing delete-for-everyone v109 custody', () {
    const sender = 'peer-alice';
    const recipient = 'peer-bob';
    const t0 = '2026-08-11T09:00:00.000Z';

    Future<List<Map<String, Object?>>> v109RowsFor(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async => (await fixture.db.query('direct_reaction_inbox_custody_outbox'))
        .where((row) => (row['wire_envelope']! as String).contains(messageId))
        .toList(growable: false);

    Future<Map<String, Object?>?> parentRow(
      MediaRepositoryRealDbFixture fixture,
      String messageId,
    ) async {
      final rows = await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[messageId],
      );
      return rows.isEmpty ? null : rows.single;
    }

    /// Seeds one delivered outgoing disappearing parent whose Plan 358 lineage
    /// has already fully drained: the per-attachment fingerprint is the only
    /// surviving strict proof. A [fingerprint] of null keeps it legacy.
    Future<ConversationMessage> seedDisappearingParent(
      MediaRepositoryRealDbFixture fixture,
      String messageId, {
      String? fingerprint = _tc359Fingerprint,
      int durationSeconds = 3600,
    }) async {
      final attachmentId = '$messageId-a';
      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': recipient,
        'sender_peer_id': sender,
        'text': '',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': t0,
        'wire_envelope': jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'senderPeerId': sender,
          'encrypted': const <String, Object?>{
            'kem': 'kem-initial',
            'ciphertext': 'cipher-initial',
            'nonce': 'nonce-initial',
          },
        }),
        'private_media_policy_version': 1,
        'private_media_mode': 'disappearing',
        'private_media_duration_seconds': durationSeconds,
        'private_media_state': 'available',
      });
      await fixture.repo.saveAttachment(
        MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: recipient,
            blobId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'done',
          createdAt: t0,
          contentHash: '1' * 64,
          encryptionKeyBase64: 'cHJpdmF0ZS1rZXk=',
          encryptionNonce: 'bm9uY2U=',
          encryptionScheme: 'blob_aes_256_gcm_v1',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.db.update(
        'media_attachments',
        <String, Object?>{'direct_media_blob_custody_fingerprint': fingerprint},
        where: 'id = ?',
        whereArgs: <Object?>[attachmentId],
      );
      return (await fixture.messageRepo.getMessage(messageId))!;
    }

    test('TC-359-02a disappearing DFE uses physical lineage and ordinary '
        'settlement without promoting legacy rows', () async {
      // 1. Exact post-drain lineage: the DB lane alone selects the strict media
      //    owner, the exact v109 lands before cleanup and before any network,
      //    and node-off settles through the ORDINARY owner as `failed`.
      final strict = await MediaRepositoryRealDbFixture.create();
      addTearDown(strict.dispose);
      const strictId = 'tc359-02a-strict';
      final strictParent = await seedDisappearingParent(strict, strictId);
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          strict.db,
          messageId: strictId,
        ),
        OutgoingDirectDeletionLane.strictMedia,
      );
      expect(
        await strict.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('$strictId-a'),
        ),
        isTrue,
      );

      List<Map<String, Object?>>? custodyAtFirstCleanup;
      Map<String, Object?>? parentAtFirstCleanup;
      final observingManager = _ObservingDeleteMediaFileManager(
        onFirstDelete: () async {
          custodyAtFirstCleanup = await v109RowsFor(strict, strictId);
          parentAtFirstCleanup = await parentRow(strict, strictId);
        },
      );
      final strictNetwork = FakeP2PNetwork();
      final stopped = _StoppedDeleteP2PService(
        peerId: sender,
        network: strictNetwork,
      );
      addTearDown(stopped.dispose);

      final (strictResult, strictTombstone) = await deleteMessageForEveryone(
        p2pService: stopped,
        messageRepo: strict.messageRepo,
        originalMessage: strictParent.copyWith(
          // A forged caller snapshot must never decide the owner.
          media: <MediaAttachment>[
            makeAttachment(
              id: 'ghost-attachment',
              messageId: strictId,
              localPath: 'media/$strictId/ghost.jpg',
            ),
          ],
        ),
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: strict.repo,
        mediaFileManager: observingManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(strictResult, SendChatMessageResult.nodeNotRunning);
      expect(strictTombstone, isNotNull);
      expect(strictTombstone!.isDeleted, isTrue);
      expect(strictTombstone.status, 'failed');
      expect(
        strictTombstone.privateMediaMode,
        PrivateMediaMode.disappearing,
        reason: 'the deletion never rewrites the disappearing policy',
      );
      expect(strictNetwork.deliverCallCount, 0);
      expect(strictNetwork.storeInInboxCallCount, 0);
      expect(
        await v109RowsFor(strict, strictId),
        hasLength(1),
        reason: 'a stopped node never discards the exact deletion event',
      );
      expect(
        custodyAtFirstCleanup,
        hasLength(1),
        reason: 'private cleanup may not precede the exact v109 stage',
      );
      expect(parentAtFirstCleanup?['deleted_at'], isNotNull);
      final strictSettled = (await parentRow(strict, strictId))!;
      expect(strictSettled['status'], 'failed');
      expect(strictSettled['private_media_mode'], 'disappearing');
      expect(strictSettled['private_media_duration_seconds'], 3600);
      expect(strictSettled['private_media_state'], 'available');
      // Exact private lifecycle cleanup, never generic attachment deletion.
      expect(
        await strict.repo.getAttachmentsForMessage(
          strictId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        await strict.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('$strictId-a'),
        ),
        isFalse,
        reason: 'only the private lifecycle owner retires the secure key',
      );

      // 2. A proof-less historical disappearing row keeps legacy transport with
      //    NO event id and no v109, but still uses private-owner cleanup.
      final legacy = await MediaRepositoryRealDbFixture.create();
      addTearDown(legacy.dispose);
      const legacyId = 'tc359-02a-legacy';
      final legacyParent = await seedDisappearingParent(
        legacy,
        legacyId,
        fingerprint: null,
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          legacy.db,
          messageId: legacyId,
        ),
        OutgoingDirectDeletionLane.legacyMedia,
      );
      final legacyNetwork = FakeP2PNetwork();
      final legacyService = FakeP2PService(
        peerId: sender,
        network: legacyNetwork,
      );
      final legacyPeer = FakeP2PService(
        peerId: recipient,
        network: legacyNetwork,
      );
      addTearDown(legacyService.dispose);
      addTearDown(legacyPeer.dispose);
      final legacyManager = FakeMediaFileManager();

      final (legacyResult, legacyTombstone) = await deleteMessageForEveryone(
        p2pService: legacyService,
        messageRepo: legacy.messageRepo,
        originalMessage: legacyParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: legacy.repo,
        mediaFileManager: legacyManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(legacyResult, SendChatMessageResult.success);
      expect(legacyTombstone?.isDeleted, isTrue);
      expect(
        await v109RowsFor(legacy, legacyId),
        isEmpty,
        reason: 'a proof-less disappearing row never gains a v109 event',
      );
      expect(
        legacyTombstone!.wireEnvelope == null ||
            !legacyTombstone.wireEnvelope!.contains('"eventId"'),
        isTrue,
        reason: 'no event identity is minted for legacy transport',
      );
      expect(
        await legacy.repo.getAttachmentsForMessage(
          legacyId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        await legacy.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('$legacyId-a'),
        ),
        isFalse,
        reason: 'the legacy row still uses private-owner cleanup',
      );

      // 3. A contradictory lineage is all-zero: no tombstone, no v109, no
      //    cleanup and no network.
      final crossed = await MediaRepositoryRealDbFixture.create();
      addTearDown(crossed.dispose);
      const crossedId = 'tc359-02a-crossed';
      final crossedParent = await seedDisappearingParent(crossed, crossedId);
      // A well-formed but non-recomputable digest on a live v111 row is a
      // crossed proof, so every owner must fail closed.
      await crossed.db.insert(
        kDirectMediaBlobCustodyTable,
        DirectMediaBlobCustodyRow(
          attachmentId: '$crossedId-a',
          messageId: crossedId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingStored,
          inboxCustodyIncarnationId: null,
          recipientPeerId: recipient,
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'b' * 64}/$crossedId-a.blob',
          contentHash: '1' * 64,
          ciphertextSize: 41,
          expiresAtMs: 1900000060000,
          custodyRelayPeerId: 'relay-1',
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: t0,
          updatedAt: t0,
        ).toMap(),
      );
      expect(
        await dbClassifyOutgoingDirectDeletionLane(
          crossed.db,
          messageId: crossedId,
        ),
        OutgoingDirectDeletionLane.contradiction,
      );
      final crossedNetwork = FakeP2PNetwork();
      final crossedService = FakeP2PService(
        peerId: sender,
        network: crossedNetwork,
      );
      addTearDown(crossedService.dispose);
      final crossedManager = FakeMediaFileManager();

      final (crossedResult, crossedTombstone) = await deleteMessageForEveryone(
        p2pService: crossedService,
        messageRepo: crossed.messageRepo,
        originalMessage: crossedParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: crossed.repo,
        mediaFileManager: crossedManager,
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(crossedResult, SendChatMessageResult.invalidMessage);
      expect(crossedTombstone, isNull);
      expect(crossedNetwork.deliverCallCount, 0);
      expect(crossedNetwork.storeInInboxCallCount, 0);
      expect(await v109RowsFor(crossed, crossedId), isEmpty);
      expect((await parentRow(crossed, crossedId))!['deleted_at'], isNull);
      expect(crossedManager.deletedFilePaths, isEmpty);
      expect(
        await crossed.repo.getAttachmentsForMessage(
          crossedId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );

      // 4. Missing private cleanup capability is all-zero as well.
      final incapable = await MediaRepositoryRealDbFixture.create();
      addTearDown(incapable.dispose);
      const incapableId = 'tc359-02a-incapable';
      final incapableParent = await seedDisappearingParent(
        incapable,
        incapableId,
      );
      final incapableNetwork = FakeP2PNetwork();
      final incapableService = FakeP2PService(
        peerId: sender,
        network: incapableNetwork,
      );
      addTearDown(incapableService.dispose);

      final (incapableResult, _) = await deleteMessageForEveryone(
        p2pService: incapableService,
        messageRepo: incapable.messageRepo,
        originalMessage: incapableParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: incapable.repo,
        // No media file manager: the private cleanup owner is unavailable.
        bridge: PassthroughCryptoBridge(),
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(incapableResult, SendChatMessageResult.sendFailed);
      expect(incapableNetwork.deliverCallCount, 0);
      expect(incapableNetwork.storeInInboxCallCount, 0);
      expect(await v109RowsFor(incapable, incapableId), isEmpty);
      expect((await parentRow(incapable, incapableId))!['deleted_at'], isNull);
      expect(
        await incapable.repo.getAttachmentsForMessage(
          incapableId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );

      // 5. A genuinely unwired DB deletion-lane selector is all-zero too. The
      //    lane is the ONLY authority that may promote strict lineage, so its
      //    absence must refuse rather than silently demote a fingerprinted
      //    generation onto the legacy ordinary stage with no event id or v109.
      final laneless = await MediaRepositoryRealDbFixture.create(
        wireOutgoingDirectDeletionLaneSelection: false,
      );
      addTearDown(laneless.dispose);
      const lanelessId = 'tc359-02a-laneless';
      final lanelessParent = await seedDisappearingParent(laneless, lanelessId);
      expect(
        laneless.repo.supportsOutgoingDirectDeletionLaneSelection,
        isFalse,
        reason: 'the real repository is composed without the lane selector',
      );
      final lanelessNetwork = FakeP2PNetwork();
      final lanelessService = FakeP2PService(
        peerId: sender,
        network: lanelessNetwork,
      );
      addTearDown(lanelessService.dispose);
      final lanelessManager = FakeMediaFileManager();
      final lanelessBridge = PassthroughCryptoBridge();

      final (
        lanelessResult,
        lanelessTombstone,
      ) = await deleteMessageForEveryone(
        p2pService: lanelessService,
        messageRepo: laneless.messageRepo,
        originalMessage: lanelessParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: laneless.repo,
        mediaFileManager: lanelessManager,
        bridge: lanelessBridge,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(lanelessResult, SendChatMessageResult.sendFailed);
      expect(lanelessTombstone, isNull);
      expect(
        lanelessBridge.commandLog,
        isEmpty,
        reason: 'missing lane authority refuses before envelope encryption',
      );
      expect(lanelessNetwork.deliverCallCount, 0);
      expect(lanelessNetwork.storeInInboxCallCount, 0);
      expect(await v109RowsFor(laneless, lanelessId), isEmpty);
      expect(
        (await parentRow(laneless, lanelessId))!['deleted_at'],
        isNull,
        reason: 'strict lineage never demotes to the legacy ordinary stage',
      );
      expect(lanelessManager.deletedFilePaths, isEmpty);
      expect(
        await laneless.repo.getAttachmentsForMessage(
          lanelessId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );
      expect(
        await laneless.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('$lanelessId-a'),
        ),
        isTrue,
        reason: 'a refused deletion never retires private custody',
      );

      // 6. BOTH disappearing lanes settle through the ordinary owner, so its
      //    absence must also be discovered before encryption. Strict lineage
      //    would otherwise stage its v109 and destroy private custody before
      //    settlement silently returned no durable row.
      final unsettleable = await MediaRepositoryRealDbFixture.create();
      addTearDown(unsettleable.dispose);
      const unsettleableId = 'tc359-02a-unsettleable';
      final unsettleableParent = await seedDisappearingParent(
        unsettleable,
        unsettleableId,
      );
      final unsettleableNetwork = FakeP2PNetwork();
      final unsettleableService = FakeP2PService(
        peerId: sender,
        network: unsettleableNetwork,
      );
      addTearDown(unsettleableService.dispose);
      final unsettleableManager = FakeMediaFileManager();
      final unsettleableBridge = PassthroughCryptoBridge();

      final (
        unsettleableResult,
        unsettleableTombstone,
      ) = await deleteMessageForEveryone(
        p2pService: unsettleableService,
        messageRepo: _OrdinaryTransportIncapableMessageRepository(
          unsettleable.messageRepo,
        ),
        originalMessage: unsettleableParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: unsettleable.repo,
        mediaFileManager: unsettleableManager,
        bridge: unsettleableBridge,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(unsettleableResult, SendChatMessageResult.invalidMessage);
      expect(unsettleableTombstone, isNull);
      expect(
        unsettleableBridge.commandLog,
        isEmpty,
        reason: 'missing settlement authority refuses before encryption',
      );
      expect(unsettleableNetwork.deliverCallCount, 0);
      expect(unsettleableNetwork.storeInInboxCallCount, 0);
      expect(await v109RowsFor(unsettleable, unsettleableId), isEmpty);
      expect(
        (await parentRow(unsettleable, unsettleableId))!['deleted_at'],
        isNull,
        reason: 'no event may be staged for a tombstone nothing can settle',
      );
      expect(unsettleableManager.deletedFilePaths, isEmpty);
      expect(
        await unsettleable.repo.getAttachmentsForMessage(
          unsettleableId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );
      expect(
        await unsettleable.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName('$unsettleableId-a'),
        ),
        isTrue,
      );

      // The proof-less legacy lane force-unwraps the very same owner during its
      // stage, so it must refuse identically instead of crashing.
      final unsettleableLegacy = await MediaRepositoryRealDbFixture.create();
      addTearDown(unsettleableLegacy.dispose);
      const unsettleableLegacyId = 'tc359-02a-unsettleable-legacy';
      final unsettleableLegacyParent = await seedDisappearingParent(
        unsettleableLegacy,
        unsettleableLegacyId,
        fingerprint: null,
      );
      final unsettleableLegacyNetwork = FakeP2PNetwork();
      final unsettleableLegacyService = FakeP2PService(
        peerId: sender,
        network: unsettleableLegacyNetwork,
      );
      addTearDown(unsettleableLegacyService.dispose);
      final unsettleableLegacyManager = FakeMediaFileManager();
      final unsettleableLegacyBridge = PassthroughCryptoBridge();

      final (
        legacyUnsettleableResult,
        legacyUnsettleableTombstone,
      ) = await deleteMessageForEveryone(
        p2pService: unsettleableLegacyService,
        messageRepo: _OrdinaryTransportIncapableMessageRepository(
          unsettleableLegacy.messageRepo,
        ),
        originalMessage: unsettleableLegacyParent,
        reactionRepo: reactionRepo,
        mediaAttachmentRepo: unsettleableLegacy.repo,
        mediaFileManager: unsettleableLegacyManager,
        bridge: unsettleableLegacyBridge,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
      );

      expect(legacyUnsettleableResult, SendChatMessageResult.invalidMessage);
      expect(legacyUnsettleableTombstone, isNull);
      expect(
        unsettleableLegacyBridge.commandLog,
        isEmpty,
        reason: 'legacy missing settlement authority also refuses pre-crypto',
      );
      expect(unsettleableLegacyNetwork.deliverCallCount, 0);
      expect(
        (await parentRow(
          unsettleableLegacy,
          unsettleableLegacyId,
        ))!['deleted_at'],
        isNull,
      );
      expect(unsettleableLegacyManager.deletedFilePaths, isEmpty);
      expect(
        await unsettleableLegacy.repo.getAttachmentsForMessage(
          unsettleableLegacyId,
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );

      // 7. A caption/edit predecessor is lineage this modality could never have
      //    authored. The application predicate deliberately stays broad so such
      //    drift keeps the PRIVATE cleanup owner and the storage predicate
      //    refuses it all-zero under the lease — narrowing it here would route
      //    a private row to the ordinary stage and generic artifact cleanup.
      for (final drift
          in const <({String label, String text, String? editedAt})>[
            (label: 'captioned', text: 'disappearing media', editedAt: null),
            (label: 'edited', text: '', editedAt: t0),
          ]) {
        final drifted = await MediaRepositoryRealDbFixture.create();
        addTearDown(drifted.dispose);
        final driftedId = 'tc359-02a-drift-${drift.label}';
        final driftedParent = await seedDisappearingParent(drifted, driftedId);
        await drifted.db.update(
          'messages',
          <String, Object?>{'text': drift.text, 'edited_at': drift.editedAt},
          where: 'id = ?',
          whereArgs: <Object?>[driftedId],
        );
        final driftedNetwork = FakeP2PNetwork();
        final driftedService = FakeP2PService(
          peerId: sender,
          network: driftedNetwork,
        );
        addTearDown(driftedService.dispose);
        final driftedManager = FakeMediaFileManager();

        final (
          driftedResult,
          driftedTombstone,
        ) = await deleteMessageForEveryone(
          p2pService: driftedService,
          messageRepo: drifted.messageRepo,
          originalMessage: driftedParent,
          reactionRepo: reactionRepo,
          mediaAttachmentRepo: drifted.repo,
          mediaFileManager: driftedManager,
          bridge: PassthroughCryptoBridge(),
          recipientMlKemPublicKey: recipientMlKemPublicKey,
        );

        expect(
          driftedResult,
          SendChatMessageResult.invalidMessage,
          reason: drift.label,
        );
        expect(driftedTombstone, isNull, reason: drift.label);
        expect(driftedNetwork.deliverCallCount, 0, reason: drift.label);
        expect(driftedNetwork.storeInInboxCallCount, 0, reason: drift.label);
        expect(
          await v109RowsFor(drifted, driftedId),
          isEmpty,
          reason: drift.label,
        );
        expect(
          (await parentRow(drifted, driftedId))!['deleted_at'],
          isNull,
          reason: drift.label,
        );
        expect(driftedManager.deletedFilePaths, isEmpty, reason: drift.label);
        expect(
          await drifted.repo.getAttachmentsForMessage(
            driftedId,
            owner: MediaOwnerLane.direct,
          ),
          hasLength(1),
          reason: drift.label,
        );
        expect(
          await drifted.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('$driftedId-a'),
          ),
          isTrue,
          reason: 'generic cleanup never retires a private key: ${drift.label}',
        );
      }
    });
  });
}

/// Composes the real message repository WITHOUT the ordinary transport
/// mutation authority, exactly as an implementation that never adopted it
/// would. Every owner a disappearing deletion legitimately needs — private
/// lifecycle cleanup and the shared v109 lifecycle — is forwarded unchanged,
/// so the flow really reaches its stage/cleanup/settlement boundaries.
class _OrdinaryTransportIncapableMessageRepository
    implements
        MessageRepository,
        DirectPrivateMediaLifecycleRepository,
        DirectMutationInboxCustodyLifecycleRepository {
  _OrdinaryTransportIncapableMessageRepository(this.delegate);

  final MessageRepositoryImpl delegate;

  @override
  bool get supportsDirectMutationInboxCustodyLifecycle =>
      delegate.supportsDirectMutationInboxCustodyLifecycle;

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) => delegate.loadDirectTextMutationInboxCustodyForEvent(
    recipientPeerId: recipientPeerId,
    eventId: eventId,
  );

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) => delegate.recordDirectTextMutationInboxCustodyFailureIfExact(
    expected: expected,
    errorCode: errorCode,
  );

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) => delegate.completeAcceptedDirectTextMutationInboxCustodyIfExact(
    expected: expected,
    relayExpiresAt: relayExpiresAt,
  );

  @override
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  ) => delegate.loadPrivateMediaLifecycleMessage(messageId);

  @override
  Future<bool> claimPrivateMediaOpening(
    String messageId, {
    required int nowMs,
  }) => delegate.claimPrivateMediaOpening(messageId, nowMs: nowMs);

  @override
  Future<bool> markPrivateMediaViewing(
    String messageId, {
    required int nowMs,
  }) => delegate.markPrivateMediaViewing(messageId, nowMs: nowMs);

  @override
  Future<bool> rollbackPrivateMediaOpening(String messageId) =>
      delegate.rollbackPrivateMediaOpening(messageId);

  @override
  Future<bool> consumePrivateMedia(String messageId, {required int nowMs}) =>
      delegate.consumePrivateMedia(messageId, nowMs: nowMs);

  @override
  Future<bool> advancePrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) => delegate.advancePrivateMediaClock(messageId, nowMs: nowMs);

  @override
  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  }) => delegate.failClosedCorruptPrivateMediaState(messageId, nowMs: nowMs);

  @override
  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  }) => delegate.hidePrivateMediaForMe(
    messageId,
    hiddenAt: hiddenAt,
    nowMs: nowMs,
  );

  @override
  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  }) => delegate.loadActiveDisappearingPrivateMedia(limit: limit);

  @override
  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) => delegate.loadPrivateMediaRecoveryCandidates(limit: limit);

  @override
  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) => delegate.rotatePrivateMediaRecoveryCandidate(messageId, nowMs: nowMs);

  @override
  Future<int?> loadNextPrivateMediaExpiryAtMs() =>
      delegate.loadNextPrivateMediaExpiryAtMs();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'ordinary-transport-incapable repository received ${invocation.memberName}',
  );
}

/// Runs the REAL physical-v109 private deletion stage and then withholds only
/// its committed transaction row, so the application guard is reached with an
/// otherwise authorized exact custody result.
class _NullCommittedRowPrivateStageRepository
    implements
        MessageRepository,
        DirectPrivateMediaLifecycleRepository,
        DirectPrivateDeleteForEveryoneRepository,
        OutgoingDirectPrivateDeletionInboxCustodyRepository,
        DirectMutationInboxCustodyLifecycleRepository {
  _NullCommittedRowPrivateStageRepository(this.delegate);

  final MessageRepositoryImpl delegate;
  int stageCalls = 0;
  bool? lastAuthorizedTransport;

  @override
  bool get supportsDirectPrivateDeletionInboxCustody =>
      delegate.supportsDirectPrivateDeletionInboxCustody;

  @override
  bool get supportsDirectMutationInboxCustodyLifecycle =>
      delegate.supportsDirectMutationInboxCustodyLifecycle;

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  // Everything after the guard is forwarded unchanged, so a HEAD run really
  // reaches cleanup and transport instead of failing on a missing member.
  @override
  Future<ConversationMessage?> settlePrivateDeleteForEveryoneTombstone({
    required ConversationMessage tombstone,
    required String expectedEnvelope,
  }) => delegate.settlePrivateDeleteForEveryoneTombstone(
    tombstone: tombstone,
    expectedEnvelope: expectedEnvelope,
  );

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) => delegate.loadDirectTextMutationInboxCustodyForEvent(
    recipientPeerId: recipientPeerId,
    eventId: eventId,
  );

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) => delegate.recordDirectTextMutationInboxCustodyFailureIfExact(
    expected: expected,
    errorCode: errorCode,
  );

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) => delegate.completeAcceptedDirectTextMutationInboxCustodyIfExact(
    expected: expected,
    relayExpiresAt: relayExpiresAt,
  );

  @override
  Future<OutgoingDirectPrivateDeletionCustodyStageResult>
  stageOutgoingDirectPrivateDeletionInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage tombstone,
    required String recipientPeerId,
    required String eventId,
    required String wireEnvelope,
  }) async {
    stageCalls++;
    final result = await delegate
        .stageOutgoingDirectPrivateDeletionInboxCustody(
          expected: expected,
          tombstone: tombstone,
          recipientPeerId: recipientPeerId,
          eventId: eventId,
          wireEnvelope: wireEnvelope,
        );
    lastAuthorizedTransport = result.authorizesTransport;
    return OutgoingDirectPrivateDeletionCustodyStageResult(
      outcome: result.outcome,
      custody: result.custody,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'null-committed-row repository received ${invocation.memberName}',
  );
}

/// Fails only reaction retirement, which is never deletion authority.
class _ThrowingReactionRepository extends FakeReactionRepository {
  final List<String> deleteForMessageCalls = <String>[];

  @override
  Future<int> deleteReactionsForMessage(String messageId) async {
    deleteForMessageCalls.add(messageId);
    throw StateError('injected reaction store failure');
  }
}

/// Records the first step of private terminal cleanup, so a refusal can be
/// proven to have performed none of it.
class _RecordingReactionRepository extends FakeReactionRepository {
  final List<String> deleteForMessageCalls = <String>[];

  @override
  Future<int> deleteReactionsForMessage(String messageId) {
    deleteForMessageCalls.add(messageId);
    return super.deleteReactionsForMessage(messageId);
  }
}

/// Gates BOTH network legs a v109-owning deletion uses: the live send and the
/// protected ack-or-expiry hedge. Legacy inbox stores are counted separately so
/// a test can prove an owned event never falls back to them.
class _GatedNetworkDeleteP2PService extends FakeP2PService {
  _GatedNetworkDeleteP2PService({
    required super.peerId,
    required super.network,
  });

  final Completer<void> sendEntered = Completer<void>();
  final Completer<void> releaseSend = Completer<void>();
  final Completer<void> ackCustodyEntered = Completer<void>();
  final Completer<void> releaseAckCustody = Completer<void>();
  final Completer<void> _ackCustodySettled = Completer<void>();
  int legacyStoreInInboxCalls = 0;

  Future<void> get ackCustodySettled => _ackCustodySettled.future;

  void releaseAll() {
    if (!releaseSend.isCompleted) releaseSend.complete();
    if (!releaseAckCustody.isCompleted) releaseAckCustody.complete();
  }

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

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    legacyStoreInInboxCalls++;
    return super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
  }

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    if (!ackCustodyEntered.isCompleted) ackCustodyEntered.complete();
    await releaseAckCustody.future;
    try {
      return await super.storeInAckCustodyInboxDetailed(
        toPeerId,
        message,
        custodyKind: custodyKind,
        timeoutMs: timeoutMs,
      );
    } finally {
      // Completion runs after this future resolves; yield once so the caller's
      // exact-event retirement lands before the test observes it.
      Future<void>.delayed(Duration.zero, () {
        if (!_ackCustodySettled.isCompleted) _ackCustodySettled.complete();
      });
    }
  }
}

/// A repository that keeps every incumbent private capability but deliberately
/// withholds the Plan-356 staging capability.
class _PrivateStageIncapableMessageRepository
    implements
        MessageRepository,
        DirectPrivateMediaLifecycleRepository,
        DirectPrivateDeleteForEveryoneRepository,
        OutgoingDirectPrivateDeletionInboxCustodyRepository {
  _PrivateStageIncapableMessageRepository(this.delegate);

  final MessageRepositoryImpl delegate;

  @override
  bool get supportsDirectPrivateDeletionInboxCustody => false;

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'private-stage-incapable repository received ${invocation.memberName}',
  );
}

/// Snapshots durable state at the FIRST artifact removal, so a test can prove
/// the deletion event was already retained before any cleanup ran.
class _ObservingDeleteMediaFileManager extends FakeMediaFileManager {
  _ObservingDeleteMediaFileManager({required this.onFirstDelete});

  final Future<void> Function() onFirstDelete;
  bool _observed = false;

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {
    if (!_observed) {
      _observed = true;
      await onFirstDelete();
    }
    return super.deleteFile(
      localPath,
      caller: caller,
      reason: reason,
      storedPath: storedPath,
      details: details,
      redactTelemetry: redactTelemetry,
    );
  }
}
