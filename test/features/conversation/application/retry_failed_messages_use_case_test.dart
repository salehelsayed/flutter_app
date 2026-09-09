import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;
import 'package:flutter_app/core/bridge/bridge.dart' show Bridge;
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart'
    show computeDirectEventFanoutIncarnation;
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show DirectMediaFanoutStageAuthority, DirectMediaFanoutTargetBinding;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/direct_reaction_custody_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import 'helpers/fake_upload_media_fn.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

class _PrivateFanoutExpiryP2PService extends DirectReactionCustodyP2PService
    implements MediaExpiryBoundedInboxStore {
  _PrivateFanoutExpiryP2PService({required super.initialState});

  final List<String> mediaBoundedPeerIds = <String>[];

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    mediaBoundedPeerIds.add(toPeerId);
    return storeInInboxDetailed(toPeerId, message, timeoutMs: timeoutMs);
  }
}

IdentityModel makeIdentity() {
  return IdentityModel(
    peerId: 'my-peer-id',
    publicKey: 'my-pk-base64',
    privateKey: 'my-privkey-base64',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

ConversationMessage makeFailedMessage({
  String id = 'msg-fail-001',
  String contactPeerId = 'peer-target',
  String text = 'Hello',
  String? quotedMessageId,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: text,
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    quotedMessageId: quotedMessageId,
  );
}

ConversationMessage makeFailedDeletedMessage({
  String id = 'msg-delete-fail-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: '',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    deletedAt: '2026-01-01T00:01:00.000Z',
    deletedByPeerId: 'my-peer-id',
    wireEnvelope: '{"type":"message_deletion","version":"2","encrypted":{}}',
  );
}

ConversationMessage makeFailedLegacyChatMessage({
  String id = 'msg-legacy-chat-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Legacy leak sentinel',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"1","payload":{"id":"$id","text":"Legacy leak sentinel"}}',
  );
}

ConversationMessage makeFailedLegacyDeletedMessage({
  String id = 'msg-legacy-delete-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: '',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    deletedAt: '2026-01-01T00:01:00.000Z',
    deletedByPeerId: 'my-peer-id',
    wireEnvelope:
        '{"type":"message_deletion","version":"1","payload":{"messageId":"$id","senderPeerId":"my-peer-id"}}',
  );
}

ConversationMessage makeFailedEditMessage({
  String id = 'msg-edit-fail-001',
  String contactPeerId = 'peer-target',
  String? eventId,
}) {
  final resolvedEventId = eventId ?? 'edit-event-$id';
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'edited text',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    editedAt: '2026-01-01T00:05:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"2","id":"$id","eventId":"$resolvedEventId","senderPeerId":"my-peer-id","encrypted":{"kem":"fake-kem","ciphertext":"{\\"id\\":\\"$id\\",\\"action\\":\\"edit\\",\\"eventId\\":\\"$resolvedEventId\\"}","nonce":"fake-nonce"}}',
  );
}

ConversationMessage makeFailedV2EditWithoutEventId({
  String id = 'msg-v2-edit-without-event-id',
  String contactPeerId = 'peer-target',
}) {
  return makeFailedEditMessage(id: id, contactPeerId: contactPeerId).copyWith(
    wireEnvelope:
        '{"type":"chat_message","version":"2","id":"$id","senderPeerId":"my-peer-id","encrypted":{"kem":"fake-kem","ciphertext":"{\\"id\\":\\"$id\\",\\"action\\":\\"edit\\"}","nonce":"fake-nonce"}}',
  );
}

ConversationMessage makeFailedLegacyEditMessage({
  String id = 'msg-legacy-edit-001',
  String contactPeerId = 'peer-target',
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'edited legacy text',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'failed',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    editedAt: '2026-01-01T00:05:00.000Z',
    wireEnvelope:
        '{"type":"chat_message","version":"1","payload":{"id":"$id","text":"edited legacy text"}}',
  );
}

ContactModel makeContact({
  String peerId = 'peer-target',
  String? mlKemPublicKey = 'test-mlkem-pk',
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'test-pk',
    rendezvous: '/ip4/127.0.0.1/tcp/4001',
    username: 'TestUser',
    signature: 'test-sig',
    scannedAt: '2026-01-01T00:00:00.000Z',
    mlKemPublicKey: mlKemPublicKey,
  );
}

MediaAttachment _historicalRetryAttachment({
  required String messageId,
  required String attachmentId,
  required String downloadStatus,
}) {
  return MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: 128,
    mediaType: 'image',
    localPath: '/tmp/$attachmentId.jpg',
    downloadStatus: downloadStatus,
    createdAt: '2026-08-12T08:00:00.000Z',
    ownerLane: MediaOwnerLane.direct,
  );
}

Map<String, dynamic> decodeWirePayload(String wireJson) {
  final envelope = jsonDecode(wireJson) as Map<String, dynamic>;
  final payload = envelope['payload'];
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

/// 116 P2.2: FakeP2PService whose storeInInbox blocks on a test-held gate so
/// two concurrent retries of the same row can be caught in flight.
class _GatedInboxP2PService extends FakeP2PService {
  final gate = Completer<void>();
  final entered = Completer<void>();

  _GatedInboxP2PService({required super.initialState})
    : super(storeInInboxResult: true);

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    lastStoreInInboxPeerId = toPeerId;
    lastStoreInInboxMessage = message;
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return storeInInboxResult;
  }
}

/// FakeP2PService subclass that throws on sendMessageWithReply for specific
/// call indices, allowing us to test per-message error resilience.
class _PerMessageThrowingP2PService extends FakeP2PService {
  final Set<int> throwOnCallIndices;
  int _sendWithReplyIndex = 0;

  _PerMessageThrowingP2PService({
    required super.initialState,
    required this.throwOnCallIndices,
    super.discoverPeerResult,
    super.dialPeerResult,
    super.sendMessageWithReplyResult,
    super.storeInInboxResult,
  });

  @override
  Future<p2p.SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendMessageWithReplyCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    final idx = _sendWithReplyIndex++;
    if (throwOnCallIndices.contains(idx)) {
      throw Exception('sendMessageWithReply error at index $idx');
    }
    return sendMessageWithReplyResult;
  }
}

class _R3RetryDeadlineP2PService extends FakeP2PService {
  _R3RetryDeadlineP2PService({
    required super.initialState,
    required super.sendMessageWithReplyResult,
    this.inboxDelay = Duration.zero,
    this.committedAckDelay = Duration.zero,
  }) : super(storeInInboxResult: false);

  final Duration inboxDelay;
  final Duration committedAckDelay;
  final List<String> callOrder = [];
  final List<int?> sendTimeouts = [];

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    callOrder.add('inbox_start');
    if (inboxDelay > Duration.zero) await Future<void>.delayed(inboxDelay);
    callOrder.add('inbox_done');
    return super.storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
  }

  @override
  Future<p2p.SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    callOrder.add('send_start');
    sendTimeouts.add(timeoutMs);
    final nativeBudget = timeoutMs == null
        ? null
        : Duration(milliseconds: timeoutMs);
    if (nativeBudget != null && committedAckDelay > nativeBudget) {
      await Future<void>.delayed(nativeBudget);
      callOrder.add('send_timeout');
      sendMessageWithReplyCallCount++;
      return const p2p.SendMessageResult(sent: false);
    }
    if (committedAckDelay > Duration.zero) {
      await Future<void>.delayed(committedAckDelay);
    }
    callOrder.add('send_done');
    return super.sendMessageWithReply(peerId, message, timeoutMs: timeoutMs);
  }
}

/// Plan 362 linked-fanout blob repository fake.
///
/// Publishes a PLURAL linked (fanout) v114 row set and records every
/// consultation — lifecycle-lease runs, per-message loads, singular reopen
/// stages, plural stages, roster snapshot reads — so a failed-message retry
/// can be proved to route ONLY through the shared fanout owner (or fail
/// closed) without a roster resolution, a re-encryption, or a singular
/// reopen.
class _LinkedFanoutDirectMediaBlobRepository
    extends FakeMediaAttachmentRepository
    implements
        DirectMediaBlobCustodyRepository,
        OutgoingDirectLinkedMediaBlobFanoutRepository {
  final List<DirectMediaBlobCustodyRow> rows = <DirectMediaBlobCustodyRow>[];
  int lifecycleRuns = 0;
  int blobLoads = 0;
  final List<String> loadedMessageIds = <String>[];
  int ordinaryStageCalls = 0;
  int fanoutGenerationStageCalls = 0;
  int fanoutInboxStageCalls = 0;
  int snapshotReads = 0;
  bool throwOnSnapshotRead = false;
  bool applyFanoutInboxStage = false;
  DirectContactFanoutSnapshot? snapshot;
  DirectMediaFanoutStageAuthority? fanoutInboxAuthority;
  DirectContactFanoutSnapshot? fanoutInboxSnapshot;
  List<DirectMediaFanoutTargetBinding> fanoutInboxBindings =
      const <DirectMediaFanoutTargetBinding>[];

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  bool get supportsDirectLinkedMediaBlobFanout => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(Future<T> Function() action) {
    lifecycleRuns++;
    return action();
  }

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    ordinaryStageCalls++;
    return const DirectMediaBlobGenerationStageResult.refused();
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async => rows
      .where((row) => row.attachmentId == attachmentId)
      .toList(growable: false);

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async =>
      null;

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async => rows
      .where(
        (row) =>
            row.attachmentId == attachmentId &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.recipientPeerId == recipientPeerId,
      )
      .firstOrNull;

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async {
    blobLoads++;
    loadedMessageIds.add(messageId);
    return rows
        .where((row) => row.messageId == messageId)
        .toList(growable: false);
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => const <DirectMediaBlobCustodyRow>[];

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].exactDatabaseProjectionMatches(expected)) {
        rows[index] = next;
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshotForMedia(
    String contactAccountPeerId,
  ) async {
    snapshotReads++;
    if (throwOnSnapshotRead) {
      throw StateError('persisted survivor retry must not resolve the roster');
    }
    return snapshot;
  }

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectLinkedMediaBlobFanoutGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    bool allowFreshParent = false,
    String? authorizedForwardDedupKey,
  }) async {
    fanoutGenerationStageCalls++;
    return const DirectMediaBlobGenerationStageResult.refused();
  }

  @override
  Future<DirectMediaFanoutInboxCustodyStageResult>
  stageOutgoingDirectMediaFanoutInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required String senderTransportPeerId,
    required String contactAccountPeerId,
    required DirectMediaFanoutStageAuthority authority,
    required DirectContactFanoutSnapshot? expectedSnapshot,
    required List<DirectMediaFanoutTargetBinding> targetBindings,
  }) async {
    fanoutInboxStageCalls++;
    fanoutInboxAuthority = authority;
    fanoutInboxSnapshot = expectedSnapshot;
    fanoutInboxBindings = List<DirectMediaFanoutTargetBinding>.of(
      targetBindings,
    );
    if (!applyFanoutInboxStage) {
      return const DirectMediaFanoutInboxCustodyStageResult.refused();
    }
    return DirectMediaFanoutInboxCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      message: staged.copyWith(
        directMediaCustodyIntentId: null,
        media: attachments,
      ),
      attachments: attachments,
      custodyRows: <Map<String, Object?>>[
        for (final binding in targetBindings)
          <String, Object?>{
            'recipient_peer_id': binding.recipientPeerId,
            'message_id': staged.id,
            'incarnation_id': computeDirectEventFanoutIncarnation(
              messageId: staged.id,
              recipientPeerId: binding.recipientPeerId,
            ),
            'wire_envelope': binding.wireEnvelope,
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'media_blob_manifest_hash': binding.wireMediaBlobManifestHash,
            'media_blob_expires_at_ms': binding.wireMediaBlobExpiresAtMs,
            'contact_account_peer_id': contactAccountPeerId,
            'created_at': staged.createdAt,
            'updated_at': staged.createdAt,
          },
      ],
    );
  }
}

class _CrossedTerminalizationMediaRepository
    extends _LinkedFanoutDirectMediaBlobRepository {
  int terminalizationAttempts = 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    terminalizationAttempts++;
    return 0;
  }
}

void main() {
  group('retryFailedMessages', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;
    late FakeBridge bridge;

    setUp(() {
      identityRepo = FakeIdentityRepository();
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
    });

    test('returns 0 when no identity exists', () async {
      // identityRepo has no identity seeded
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 0);
    });

    test('returns 0 when no failed messages exist', () async {
      identityRepo.seed(makeIdentity());
      // messageRepo has no messages seeded
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 0);
    });

    test('TC-361-01b a failed wrapper without the plural capability refuses a '
        'marked generation with zero siblings before re-encryption', () async {
      identityRepo.seed(makeIdentity());
      final marked = makeFailedMessage().copyWith(
        directEventFanoutGenerationId: makeFailedMessage().id,
      );
      messageRepo.seed(<ConversationMessage>[marked]);
      contactRepo.seed(<ContactModel>[makeContact()]);
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 0);
      expect(
        bridge.sendCallCount,
        0,
        reason: 'a marked generation must never be re-encrypted',
      );
      expect(p2pService.storeInInboxCallCount, 0);
      expect(p2pService.sendMessageCallCount, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect((await messageRepo.getMessage(marked.id))!.status, 'failed');
    });

    test(
      'TC-366-01a failed voice and four-share drain persisted v114 before reconstruction',
      () async {
        const contactPeerId = 'peer-target';
        const authoredAt = '2026-08-11T08:30:00.000Z';
        final ciphertextBytes = utf8.encode('tc362 failed survivor artifact');
        final contentHash = sha256.convert(ciphertextBytes).toString();
        identityRepo.seed(makeIdentity());
        contactRepo.seed(<ContactModel>[makeContact()]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        ({ConversationMessage message, MediaAttachment published})
        publishedFixture(String messageId, String attachmentId) {
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          final pendingPath =
              MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: attachmentId,
                mime: 'image/jpeg',
              );
          final message = ConversationMessage(
            id: messageId,
            contactPeerId: contactPeerId,
            senderPeerId: 'my-peer-id',
            text: '',
            timestamp: authoredAt,
            status: 'failed',
            isIncoming: false,
            createdAt: authoredAt,
            directMediaCustodyIntentId: intent,
          ).copyWith(directEventFanoutGenerationId: messageId);
          final published = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: pendingPath,
            downloadStatus: 'upload_pending',
            createdAt: authoredAt,
            ownerLane: MediaOwnerLane.direct,
            contentHash: contentHash,
            encryptionKeyBase64: 'tc362-raw-key',
            encryptionNonce: 'tc362-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          );
          return (message: message, published: published);
        }

        DirectMediaBlobCustodyRow linkedStoredRow({
          required String messageId,
          required String attachmentId,
          required String recipientPeerId,
          required String recipientMlKemPublicKey,
          required int expiresAtMs,
          required String ciphertextRelativePath,
          required int ciphertextSize,
        }) => DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingStored,
          inboxCustodyIncarnationId: null,
          recipientPeerId: recipientPeerId,
          contactAccountPeerId: contactPeerId,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          ciphertextRelativePath: ciphertextRelativePath,
          contentHash: contentHash,
          ciphertextSize: ciphertextSize,
          expiresAtMs: expiresAtMs,
          custodyRelayPeerId: 'peer-relay',
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: authoredAt,
          updatedAt: authoredAt,
        );

        PreparedDirectMediaBlobCustodyCoordinator recordingCoordinator(
          _LinkedFanoutDirectMediaBlobRepository repository,
          void Function() onPrepareArtifact,
          void Function() onStrictUpload, {
          DirectMediaBlobArtifactStore? artifactStore,
        }) => PreparedDirectMediaBlobCustodyCoordinator(
          repository: repository,
          artifactStore:
              artifactStore ??
              DirectMediaBlobArtifactStore(
                documentsDirectoryProvider: () async =>
                    Directory.systemTemp.createTempSync('tc362_02b_failed_'),
              ),
          prepareArtifact:
              ({required Bridge bridge, required String localFilePath}) async {
                onPrepareArtifact();
                throw StateError(
                  'a persisted fanout generation must never re-encrypt',
                );
              },
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                onStrictUpload();
                return const <String, dynamic>{'ok': false};
              },
        );

        // Leg 1: a durable fanout marker with ZERO v114 rows is TERMINAL —
        // the failed lane skips silently with no coordinator call at all.
        final terminal = publishedFixture(
          'msg-362-failed-terminal',
          'att-362-failed-terminal',
        );
        final terminalRepo = _LinkedFanoutDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[terminal.published]);
        messageRepo.seed(<ConversationMessage>[terminal.message]);
        var terminalPrepares = 0;
        var terminalUploads = 0;
        final terminalCount = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: terminalRepo,
          directMediaBlobCustodyCoordinator: recordingCoordinator(
            terminalRepo,
            () => terminalPrepares++,
            () => terminalUploads++,
          ),
        );
        expect(terminalCount, 0);
        expect(
          terminalRepo.lifecycleRuns,
          0,
          reason: 'terminal skip: no coordinator call at all',
        );
        expect(terminalPrepares, 0);
        expect(terminalUploads, 0);
        expect(terminalRepo.ordinaryStageCalls, 0);
        expect(terminalRepo.snapshotReads, 0);
        expect(bridge.sendCallCount, 0, reason: 'zero re-encryption');
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(
          (await messageRepo.getMessage(terminal.message.id))!.status,
          'failed',
        );

        // Leg 2: persisted LINKED rows are the exclusive survivor-first
        // retry authority: the shared fanout owner replays THEM —
        // reopenAndUpload is never invoked, nothing re-encrypts, and no
        // roster resolution substitutes for the persisted rows.
        final linked = publishedFixture(
          'msg-362-failed-linked',
          'att-362-failed-linked',
        );
        final expiresAtMs = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch;
        final linkedDocuments = await Directory.systemTemp.createTemp(
          'tc362_02b_failed_survivor_',
        );
        addTearDown(() async {
          if (await linkedDocuments.exists()) {
            await linkedDocuments.delete(recursive: true);
          }
        });
        final ciphertextSource = File(
          '${linkedDocuments.path}/survivor-source.blob',
        );
        await ciphertextSource.writeAsBytes(ciphertextBytes, flush: true);
        final linkedArtifactStore = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => linkedDocuments,
        );
        final survivorArtifact = await linkedArtifactStore.persistCandidate(
          identityPeerId: 'my-peer-id',
          attachmentId: 'att-362-failed-linked',
          encryptedSourcePath: ciphertextSource.path,
          expectedContentHash: contentHash,
        );
        final linkedRepo = _LinkedFanoutDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[linked.published])
          ..throwOnSnapshotRead = true
          ..applyFanoutInboxStage = true
          ..rows.addAll(<DirectMediaBlobCustodyRow>[
            linkedStoredRow(
              messageId: linked.message.id,
              attachmentId: 'att-362-failed-linked',
              recipientPeerId: contactPeerId,
              recipientMlKemPublicKey: 'mlkem-legacy-account',
              expiresAtMs: expiresAtMs,
              ciphertextRelativePath: survivorArtifact.relativePath,
              ciphertextSize: survivorArtifact.ciphertextSize,
            ),
            linkedStoredRow(
              messageId: linked.message.id,
              attachmentId: 'att-362-failed-linked',
              recipientPeerId: 'peer-target-device-a',
              recipientMlKemPublicKey: 'mlkem-device-a',
              expiresAtMs: expiresAtMs + 60000,
              ciphertextRelativePath: survivorArtifact.relativePath,
              ciphertextSize: survivorArtifact.ciphertextSize,
            ),
          ]);
        final rowsBefore = linkedRepo.rows
            .map((row) => row.toMap())
            .toList(growable: false);
        final linkedMessages = FakeMessageRepository()
          ..seed(<ConversationMessage>[linked.message]);
        contactRepo.seed(const <ContactModel>[]);
        contactRepo.resetGetContactCounts();
        var linkedPrepares = 0;
        var linkedUploads = 0;
        var linkedCount = 0;
        final linkedEvents = await captureFlowEvents(() async {
          linkedCount = await retryFailedMessages(
            messageRepo: linkedMessages,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            mediaAttachmentRepo: linkedRepo,
            directMediaBlobCustodyCoordinator: recordingCoordinator(
              linkedRepo,
              () => linkedPrepares++,
              () => linkedUploads++,
              artifactStore: linkedArtifactStore,
            ),
          );
        });

        expect(
          linkedCount,
          1,
          reason:
              'loads=${linkedRepo.blobLoads} lifecycle=${linkedRepo.lifecycleRuns} '
              'snapshot=${linkedRepo.snapshotReads} stage=${linkedRepo.fanoutInboxStageCalls} '
              'bridge=${bridge.sendCallCount} events='
              '${linkedEvents.map((event) => event['event']).join(',')}',
        );
        expect(
          linkedRepo.lifecycleRuns,
          1,
          reason:
              'persisted v114 survivors are recovery authority independent '
              'of the fresh-authoring selector',
        );
        expect(
          linkedRepo.blobLoads,
          3,
          reason:
              'the global media guard, strict-intent lane, and fanout retry '
              'owner each read the EXACT persisted rows for this parent',
        );
        expect(linkedRepo.loadedMessageIds.toSet(), <String>{
          linked.message.id,
        });
        expect(
          linkedRepo.snapshotReads,
          0,
          reason: 'pre-v108 restart must never consult the unavailable roster',
        );
        expect(contactRepo.getContactCallCount, 0);
        expect(linkedPrepares, 0, reason: 'no re-encryption');
        expect(linkedUploads, 0);
        expect(
          linkedRepo.ordinaryStageCalls,
          0,
          reason:
              'reopenAndUpload (the singular reopen CAS) is NOT invoked '
              'over a linked generation',
        );
        expect(linkedRepo.fanoutGenerationStageCalls, 0);
        expect(linkedRepo.fanoutInboxStageCalls, 1);
        expect(
          linkedRepo.fanoutInboxAuthority,
          DirectMediaFanoutStageAuthority.persistedV114Survivors,
        );
        expect(linkedRepo.fanoutInboxSnapshot, isNull);
        expect(
          linkedRepo.fanoutInboxBindings
              .map(
                (binding) =>
                    '${binding.recipientPeerId}:${binding.recipientMlKemPublicKey}',
              )
              .toList(),
          const <String>[
            'peer-target:mlkem-legacy-account',
            'peer-target-device-a:mlkem-device-a',
          ],
          reason: 'v108 addressing is copied only from persisted v114 rows',
        );
        expect(
          bridge.sendCallCount,
          2,
          reason: 'one event envelope is encrypted per persisted target',
        );
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 2);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          linkedRepo.rows.map((row) => row.toMap()).toList(growable: false),
          rowsBefore,
          reason: 'every exact persisted fanout row is byte-identical',
        );
      },
    );

    test(
      'TC-366-01b failed private fanout drains persisted targets without singular assumptions',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        const messageId = 'tc366-01b-failed-private';
        const attachmentId = 'tc366-01b-failed-private-attachment';
        const contactPeerId = 'tc366-01b-failed-private-account';
        const devicePeerId = 'tc366-01b-failed-private-device-b';
        const authoredAt = '2026-08-14T08:30:00.000Z';
        final ciphertextBytes = utf8.encode('tc366 failed private ciphertext');
        final contentHash = sha256.convert(ciphertextBytes).toString();
        final fileManager = FakeMediaFileManager();
        final pendingPath =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            );
        final pendingFile = File(
          '${FakeMediaFileManager.testRootPath}/$pendingPath',
        );
        await pendingFile.parent.create(recursive: true);
        await pendingFile.writeAsBytes(const <int>[4, 5, 6], flush: true);
        addTearDown(() async {
          final root = Directory(FakeMediaFileManager.testRootPath);
          if (await root.exists()) await root.delete(recursive: true);
        });

        const signingKey = 'tc366-01b-failed-contact-signing-key';
        await fixture.db.insert('contacts', <String, Object?>{
          'peer_id': contactPeerId,
          'public_key': signingKey,
          'rendezvous': '/dns4/relay.example/tcp/443/wss/p2p/relay-id',
          'username': 'Failed private target',
          'signature': 'signature',
          'scanned_at': authoredAt,
          'ml_kem_public_key': 'mlkem-failed-private-account',
        });
        await fixture.db
            .insert('direct_contact_device_roster_metadata', <String, Object?>{
              'contact_account_peer_id': contactPeerId,
              'roster_initialized': 1,
              'legacy_target_state': 'active',
              'initialized_at': authoredAt,
              'legacy_revoked_at': null,
              'updated_at': authoredAt,
            });
        await fixture.db
            .insert('direct_contact_device_bindings', <String, Object?>{
              'contact_account_peer_id': contactPeerId,
              'device_id': 'tc366-01b-failed-device-id-b',
              'verified_account_signing_public_key': signingKey,
              'transport_peer_id': devicePeerId,
              'transport_public_key': 'tc366-01b-failed-device-signing-key-b',
              'device_ml_kem_public_key': 'mlkem-failed-private-device-b',
              'binding_fingerprint': '366c' * 16,
              'state': 'active',
              'staged_at': authoredAt,
              'decided_at': authoredAt,
            });
        final snapshot =
            await (fixture.repo
                    as OutgoingDirectLinkedMediaBlobFanoutRepository)
                .readDirectContactFanoutSnapshotForMedia(contactPeerId);
        expect(snapshot?.targets, hasLength(2));

        final parent = ConversationMessage(
          id: messageId,
          contactPeerId: contactPeerId,
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: authoredAt,
          status: 'failed',
          isIncoming: false,
          createdAt: authoredAt,
          dedupKey: messageId,
          privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
          privateMediaState: PrivateMediaLifecycleState.available,
        );
        final pending = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 3,
          mediaType: 'image',
          localPath: pendingPath,
          downloadStatus: 'upload_pending',
          createdAt: authoredAt,
          ownerLane: MediaOwnerLane.direct,
        );
        final prepared = pending.copyWith(
          contentHash: contentHash,
          encryptionKeyBase64: 'tc366-01b-failed-private-key',
          encryptionNonce: 'tc366-01b-failed-private-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await fixture.db.insert('messages', parent.toMap());
        await fixture.db.insert('media_attachments', pending.toMap());

        final artifactDocuments = await Directory.systemTemp.createTemp(
          'tc366_01b_failed_artifact_',
        );
        addTearDown(() async {
          if (await artifactDocuments.exists()) {
            await artifactDocuments.delete(recursive: true);
          }
        });
        final artifactSource = File('${artifactDocuments.path}/source.blob');
        await artifactSource.writeAsBytes(ciphertextBytes, flush: true);
        final artifactStore = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => artifactDocuments,
        );
        final artifact = await artifactStore.persistCandidate(
          identityPeerId: 'my-peer-id',
          attachmentId: attachmentId,
          encryptedSourcePath: artifactSource.path,
          expectedContentHash: contentHash,
        );
        final generationRows = <DirectMediaBlobCustodyRow>[
          for (final target in snapshot!.targets)
            DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: target.peerId,
              contactAccountPeerId: contactPeerId,
              recipientMlKemPublicKey: target.mlKemPublicKey,
              ciphertextRelativePath: artifact.relativePath,
              contentHash: contentHash,
              ciphertextSize: artifact.ciphertextSize,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: authoredAt,
              updatedAt: authoredAt,
            ),
        ];
        final staged =
            await (fixture.repo
                    as OutgoingDirectPrivateMediaBlobFanoutGenerationRepository)
                .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
                  expectedParent: parent,
                  expectedAttachment: pending,
                  preparedAttachment: prepared,
                  custodyRows: generationRows,
                  contactAccountPeerId: contactPeerId,
                  expectedSnapshot: snapshot,
                );
        expect(staged.outcome, DirectMediaBlobGenerationStageOutcome.applied);
        final blobRepository = fixture.repo as DirectMediaBlobCustodyRepository;
        for (final row in staged.custodyRows) {
          expect(
            await blobRepository.transitionDirectMediaBlobCustodyIfExact(
              expected: row,
              next: row.copyWith(
                state: DirectMediaBlobCustodyState.outgoingStored,
                expiresAtMs: 2000000000000,
                custodyRelayPeerId: 'relay-${row.recipientPeerId}',
                updatedAt: '2026-08-14T08:30:01.000Z',
              ),
            ),
            isTrue,
          );
        }

        var prepareArtifactCalls = 0;
        var strictUploadCalls = 0;
        final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: blobRepository,
          artifactStore: artifactStore,
          prepareArtifact:
              ({required Bridge bridge, required String localFilePath}) async {
                prepareArtifactCalls++;
                throw StateError('persisted private fanout must not encrypt');
              },
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                strictUploadCalls++;
                throw StateError('every persisted v114 row is already stored');
              },
        );
        identityRepo.seed(makeIdentity());
        contactRepo.seed(const <ContactModel>[]);
        contactRepo.resetGetContactCounts();
        final genericUpload = FakeUploadMediaFn();
        final transport =
            _PrivateFanoutExpiryP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'my-peer-id',
                ),
              )
              ..detailedInboxOutcome = const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                storeStatus: 'stored',
                expiresAtMs: 2000000000000,
                custodyContract: ackOrExpiryInboxCustodyContract,
              );

        var retried = 0;
        final retryEvents = await captureFlowEvents(() async {
          retried = await retryFailedMessages(
            messageRepo: fixture.messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: transport,
            bridge: bridge,
            mediaAttachmentRepo: fixture.repo,
            uploadMediaFn: genericUpload.call,
            mediaFileManager: fileManager,
            directMediaBlobArtifactStore: artifactStore,
            directMediaBlobCustodyCoordinator: coordinator,
          );
        });
        expect(
          retried,
          1,
          reason: retryEvents.map((event) => event['event']).join(', '),
        );
        expect(prepareArtifactCalls, 0);
        expect(strictUploadCalls, 0);
        expect(genericUpload.callCount, 0);
        expect(contactRepo.getContactCallCount, 0);
        expect(
          transport.mediaBoundedPeerIds.toSet(),
          <String>{contactPeerId, devicePeerId},
          reason:
              'both persisted physical targets drain independently; '
              '${retryEvents.map((event) => event['event']).join(', ')}',
        );
        expect(
          (await blobRepository.loadDirectMediaBlobCustodyForMessage(
            messageId,
          )).map((row) => row.contentHash),
          everyElement(contentHash),
        );
        expect(
          (await fixture.messageRepo.getMessage(
            messageId,
          ))?.directMediaCustodyIntentId,
          isNull,
        );
      },
    );

    test(
      'TC-362-02c completed, retry-ceiling, and media-mutation parents refuse '
      'before singular reconstruction or egress',
      () async {
        identityRepo.seed(makeIdentity());
        contactRepo.seed(<ContactModel>[makeContact()]);
        final completed = makeFailedMessage(
          id: 'msg-362-completed',
        ).copyWith(wireEnvelope: 'cached-completed-singular-envelope');
        final retryCeiling = makeFailedMessage(
          id: 'msg-362-retry-ceiling',
        ).copyWith(wireEnvelope: 'cached-ceiling-singular-envelope');
        final mutation = makeFailedEditMessage(id: 'msg-362-media-edit');
        messageRepo.seed(<ConversationMessage>[
          completed,
          retryCeiling,
          mutation,
        ]);
        final mediaRepository = _LinkedFanoutDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[
            _historicalRetryAttachment(
              messageId: completed.id,
              attachmentId: 'att-362-completed',
              downloadStatus: 'done',
            ),
            _historicalRetryAttachment(
              messageId: retryCeiling.id,
              attachmentId: 'att-362-retry-ceiling',
              downloadStatus: 'upload_failed',
            ),
            _historicalRetryAttachment(
              messageId: mutation.id,
              attachmentId: 'att-362-media-edit',
              downloadStatus: 'done',
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepository,
        );

        expect(count, 0);
        expect(bridge.sendCallCount, 0, reason: 'zero reconstruction crypto');
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          mediaRepository.allSavedAttachments,
          isEmpty,
          reason: 'no retry state or attachment projection is rewritten',
        );
      },
    );

    test('TC-362-02d a crossed pending-row terminalization CAS still refuses '
        'the retry attempt', () async {
      identityRepo.seed(makeIdentity());
      contactRepo.seed(<ContactModel>[makeContact()]);
      final message = makeFailedMessage(id: 'msg-362-crossed-cas');
      messageRepo.seed(<ConversationMessage>[message]);
      final mediaRepository = _CrossedTerminalizationMediaRepository()
        ..seed(<MediaAttachment>[
          _historicalRetryAttachment(
            messageId: message.id,
            attachmentId: 'att-362-crossed-cas',
            downloadStatus: 'upload_pending',
          ),
        ]);
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      late int count;
      final events = await captureFlowEvents(() async {
        count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepository,
        );
      });

      expect(count, 0);
      expect(mediaRepository.terminalizationAttempts, 1);
      expect(
        events.map((event) => event['event']),
        contains('RETRY_FAILED_MEDIA_FANOUT_TERMINALIZATION_CAS_REFUSED'),
      );
      expect(bridge.sendCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
    });

    test(
      'Plan 344 pending v108 retry cannot wrap bool success as protected receipt',
      () async {
        identityRepo.seed(makeIdentity());
        final message = makeFailedMessage().copyWith(
          wireEnvelope: 'message-row-envelope-must-not-own-retry',
        );
        messageRepo
          ..seed(<ConversationMessage>[message])
          ..seedDirectInboxCustody(
            DirectInboxCustodyOutboxEntry(
              recipientPeerId: message.contactPeerId,
              messageId: message.id,
              incarnationId: '0123456789abcdef0123456789abcdef',
              wireEnvelope: 'exact-v108-custody-envelope',
              retryCount: 0,
              lastAttemptAt: null,
              lastErrorCode: null,
              createdAt: '2026-08-06T10:00:00.000Z',
              updatedAt: '2026-08-06T10:00:00.000Z',
            ),
          );
        contactRepo.seed(<ContactModel>[makeContact()]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.storeInInboxLog, isEmpty);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(bridge.sendCallCount, 0);
        final retained = messageRepo.directCustodyRows.values.single;
        expect(retained.retryCount, 1);
        expect(retained.lastErrorCode, DirectInboxCustodyErrorCode.storeFailed);
        expect((await messageRepo.getMessage(message.id))!.status, 'failed');
      },
    );

    test(
      'retries each failed message and calls sendMessageWithReply',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // sendChatMessage should have called sendMessageWithReply at least once
        expect(
          p2pService.sendMessageWithReplyCallCount,
          greaterThanOrEqualTo(1),
        );
      },
    );

    test(
      'returns success count of 1 when one message retried successfully',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
      },
    );

    test(
      'TC-353-03 failed media caption edit with a v109 owner blocks legacy send',
      () async {
        identityRepo.seed(makeIdentity());
        const messageId = 'tc353-failed-media-edit';
        const eventId = '35300000-0000-4000-8000-000000000302';
        const recipient = 'peer-target';
        const envelope =
            '{"type":"chat_message","version":"2","id":"$messageId",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
        messageRepo.seed(<ConversationMessage>[
          makeFailedMessage(
            id: messageId,
            contactPeerId: recipient,
            text: 'edited caption',
          ).copyWith(
            wireEnvelope: envelope,
            editedAt: '2026-01-01T00:00:01.000Z',
            media: const <MediaAttachment>[
              MediaAttachment(
                id: '$messageId-a',
                messageId: messageId,
                mime: 'image/jpeg',
                size: 800,
                mediaType: 'image',
                downloadStatus: 'done',
                createdAt: '2026-01-01T00:00:00.000Z',
              ),
            ],
          ),
        ]);
        contactRepo.seed([makeContact(peerId: recipient)]);
        messageRepo.directMutationCustodyRows['$recipient\u0000$eventId'] =
            const DirectReactionInboxCustodyOutboxEntry(
              recipientPeerId: recipient,
              eventId: eventId,
              wireEnvelope: envelope,
              retryCount: 0,
              lastAttemptAt: null,
              lastErrorCode: null,
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            );

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: recipient,
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );

        final count = await retryFailedMessage(
          messageId: messageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 0);
        expect(
          p2pService.sendMessageWithReplyCallCount,
          0,
          reason: 'the exact v109 owner blocks the legacy send leg',
        );
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.ordinaryAttemptStages, isEmpty);
        expect(
          messageRepo.directMutationCustodyRows,
          hasLength(1),
          reason: 'the exact event is retained for its own drain',
        );
      },
    );

    test('TC-356-03a failed private deletion with lifecycle-only v109 owner '
        'blocks legacy replay', () async {
      // 357: ownership is resolved from the REAL physical v109 table through
      // the same production helpers main.dart wires, never from a map fake.
      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      const recipient = 'peer-target';

      Future<void> seedPhysicalEvent(String eventId, String envelope) async {
        await fixture.db
            .insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
              'recipient_peer_id': recipient,
              'event_id': eventId,
              'wire_envelope': envelope,
              'retry_count': 0,
              'last_attempt_at': null,
              'last_error_code': null,
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            });
      }

      Future<List<Map<String, Object?>>> physicalRows(String eventId) =>
          fixture.db.query(
            'direct_reaction_inbox_custody_outbox',
            where: 'event_id = ?',
            whereArgs: <Object?>[eventId],
          );

      FakeP2PService makeHealthyP2P() => FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: recipient,
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      // 1. A private deletion whose exact event is a physical v109 row is owned
      //    at its FIRST lookup and can never reach any legacy leg.
      identityRepo.seed(makeIdentity());
      const messageId = 'tc356-03a-protected';
      const eventId = '35600000-0000-4000-8000-000000000301';
      const envelope =
          '{"type":"message_deletion","version":"2","eventId":"$eventId",'
          '"senderPeerId":"my-peer-id",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final backing = FakeMessageRepository();
      backing.seed(<ConversationMessage>[
        makeFailedMessage(
          id: messageId,
          contactPeerId: recipient,
          text: '',
        ).copyWith(
          deletedAt: '2026-01-01T00:00:02.000Z',
          deletedByPeerId: 'my-peer-id',
          wireEnvelope: envelope,
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
        ),
      ]);
      await seedPhysicalEvent(eventId, envelope);
      final messageRepository = _LifecycleOnlyMutationCustodyRepository(
        backing,
        db: fixture.db,
      );
      contactRepo.seed([makeContact(peerId: recipient)]);
      final p2pService = makeHealthyP2P();

      expect(
        await retryFailedMessage(
          messageId: messageId,
          messageRepo: messageRepository,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        ),
        0,
      );
      expect(
        messageRepository.ownedAtLookups,
        contains(1),
        reason: 'a physical owner wins at the first generic lifecycle lookup',
      );
      expect(
        p2pService.sendMessageWithReplyCallCount,
        0,
        reason: 'the exact v109 owner blocks the legacy send leg',
      );
      expect(p2pService.storeInInboxCallCount, 0);
      expect(backing.ordinaryAttemptStages, isEmpty);
      final retained = await physicalRows(eventId);
      expect(
        retained,
        hasLength(1),
        reason: 'a retained failure leaves the exact event retryable',
      );
      expect(
        retained.single['last_error_code'],
        isNotNull,
        reason: 'the real physical row recorded its own bounded failure',
      );
      expect(
        (await backing.getMessage(messageId))!.status,
        'failed',
        reason: 'retry never settles the tombstone on its own',
      );

      // 2. An event-bearing private deletion with NO physical owner fails
      //    closed at that same first lookup. There is no later checkpoint it
      //    could legitimately reach.
      identityRepo.seed(makeIdentity());
      const orphanId = 'tc356-03a-ownerless';
      const orphanEvent = '35600000-0000-4000-8000-000000000999';
      const orphanEnvelope =
          '{"type":"message_deletion","version":"2",'
          '"eventId":"$orphanEvent","senderPeerId":"my-peer-id",'
          '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
      final orphanBacking = FakeMessageRepository();
      orphanBacking.seed(<ConversationMessage>[
        makeFailedMessage(
          id: orphanId,
          contactPeerId: recipient,
          text: '',
        ).copyWith(
          deletedAt: '2026-01-01T00:00:02.000Z',
          deletedByPeerId: 'my-peer-id',
          wireEnvelope: orphanEnvelope,
          privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
        ),
      ]);
      final orphanRepository = _LifecycleOnlyMutationCustodyRepository(
        orphanBacking,
        db: fixture.db,
      );
      final orphanP2p = makeHealthyP2P();

      expect(
        await retryFailedMessage(
          messageId: orphanId,
          messageRepo: orphanRepository,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: orphanP2p,
          bridge: PassthroughCryptoBridge(),
        ),
        0,
      );
      expect(
        orphanRepository.lifecycleLookups,
        1,
        reason: 'an ownerless current deletion is terminal at its first look',
      );
      expect(orphanRepository.ownedAtLookups, isEmpty);
      expect(orphanP2p.sendMessageWithReplyCallCount, 0);
      expect(orphanP2p.storeInInboxCallCount, 0);
      expect(await physicalRows(orphanEvent), isEmpty);

      // 3. The applicable LATER owner check: a compatible current EDIT is
      //    ownerless at load and at the fresh re-read, then acquires its exact
      //    physical v109 row before egress. The pre-egress lookup must find it.
      identityRepo.seed(makeIdentity());
      const editId = 'tc356-03a-edit-pre-egress';
      const editEvent = '35600000-0000-4000-8000-000000000302';
      final edit = makeFailedEditMessage(id: editId, eventId: editEvent);
      final editBacking = FakeMessageRepository();
      editBacking.seed(<ConversationMessage>[edit]);
      final editRepository = _LifecycleOnlyMutationCustodyRepository(
        editBacking,
        db: fixture.db,
        onLookup: (index) async {
          if (index == 3) {
            await seedPhysicalEvent(editEvent, edit.wireEnvelope!);
          }
        },
      );
      // No direct leg: this is the cached-envelope relay route the pre-egress
      // barrier guards.
      final editP2p = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      expect(
        await retryFailedMessage(
          messageId: editId,
          messageRepo: editRepository,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: editP2p,
          bridge: PassthroughCryptoBridge(),
        ),
        0,
      );
      expect(
        editRepository.lifecycleLookups,
        3,
        reason: 'load, fresh re-read, then the pre-egress owner barrier',
      );
      expect(
        editRepository.ownedAtLookups,
        <int>[3],
        reason: 'only the pre-egress lookup could see the physical owner',
      );
      expect(
        editP2p.storeInInboxCallCount,
        0,
        reason: 'the pre-egress owner check blocks the legacy relay store',
      );
      expect(editP2p.sendMessageWithReplyCallCount, 0);
      expect(editBacking.ordinaryAttemptStages, isEmpty);
      expect(await physicalRows(editEvent), hasLength(1));
    });

    test(
      'TC-362-02d attachmentless ownerless historical DFE is roster-admitted after exact v109 gets first chance',
      () async {
        identityRepo.seed(makeIdentity());
        const recipient = 'peer-target';
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );

        // Historical v2 deletion envelopes had no eventId and can outlive all
        // attachment rows. With no v109 owner, initialized-zero roster state
        // must refuse before cached-envelope storage or singular replay.
        const ownerlessId = 'tc362-02d-ownerless-dfe';
        const ownerlessEnvelope =
            '{"type":"message_deletion","version":"2",'
            '"senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
        final ownerlessMessages = FakeMessageRepository()
          ..seed(<ConversationMessage>[
            makeFailedMessage(
              id: ownerlessId,
              contactPeerId: recipient,
              text: '',
            ).copyWith(
              deletedAt: '2026-08-13T10:00:00.000Z',
              deletedByPeerId: 'my-peer-id',
              wireEnvelope: ownerlessEnvelope,
            ),
          ]);
        final ownerlessMedia = _LinkedFanoutDirectMediaBlobRepository()
          ..snapshot = const DirectContactFanoutSnapshot(
            contactAccountPeerId: recipient,
            contactAccountSigningPublicKey: 'contact-signing-key',
            rosterInitialized: true,
            targets: <DirectContactFanoutTargetFact>[],
          );

        expect(
          await retryFailedMessage(
            messageId: ownerlessId,
            messageRepo: ownerlessMessages,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            mediaAttachmentRepo: ownerlessMedia,
          ),
          0,
        );
        expect(ownerlessMedia.snapshotReads, 1);
        expect(ownerlessMedia.blobLoads, 1);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(ownerlessMessages.ordinaryAttemptStages, isEmpty);

        // The exact v109 survivor is stronger authority and is attempted
        // before the same roster boundary. Its failed exact drain remains
        // durable; no roster read and no singular deletion leg are allowed.
        const ownedId = 'tc362-02d-owned-dfe';
        const ownedEvent = '36200000-0000-4000-8000-00000000020d';
        const ownedEnvelope =
            '{"type":"message_deletion","version":"2",'
            '"eventId":"$ownedEvent","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}';
        final ownedMessages = FakeMessageRepository()
          ..seed(<ConversationMessage>[
            makeFailedMessage(
              id: ownedId,
              contactPeerId: recipient,
              text: '',
            ).copyWith(
              deletedAt: '2026-08-13T10:01:00.000Z',
              deletedByPeerId: 'my-peer-id',
              wireEnvelope: ownedEnvelope,
            ),
          ])
          ..directMutationCustodyRows['$recipient\u0000$ownedEvent'] =
              const DirectReactionInboxCustodyOutboxEntry(
                recipientPeerId: recipient,
                eventId: ownedEvent,
                wireEnvelope: ownedEnvelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: '2026-08-13T10:01:00.000Z',
                updatedAt: '2026-08-13T10:01:00.000Z',
              );
        final ownedMedia = _LinkedFanoutDirectMediaBlobRepository()
          ..throwOnSnapshotRead = true;

        expect(
          await retryFailedMessage(
            messageId: ownedId,
            messageRepo: ownedMessages,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
            mediaAttachmentRepo: ownedMedia,
          ),
          0,
        );
        expect(ownedMedia.snapshotReads, 0);
        expect(ownedMedia.blobLoads, 0);
        expect(ownedMessages.directMutationCustodyRows, hasLength(1));
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
      },
    );

    test(
      'TC-366-02a failed media caption edit drains only persisted v109 siblings',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        identityRepo.seed(makeIdentity());
        const contact = 'peer-caption-account';
        const survivor = 'peer-caption-device-b';
        const messageId = 'tc366-02a-retry-caption';
        const eventId = '36600000-0000-4000-8000-00000000020a';
        const parentEnvelope =
            '{"type":"chat_message","version":"2","id":"$messageId",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"ka","ciphertext":"ca","nonce":"na"}}';
        const survivorEnvelope =
            '{"type":"chat_message","version":"2","id":"$messageId",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"kb","ciphertext":"cb","nonce":"nb"}}';
        final backing = FakeMessageRepository()
          ..seed(<ConversationMessage>[
            makeFailedMessage(
              id: messageId,
              contactPeerId: contact,
              text: 'edited caption',
            ).copyWith(
              editedAt: '2026-08-14T12:00:01.000Z',
              wireEnvelope: parentEnvelope,
              directEventFanoutGenerationId: eventId,
              media: const <MediaAttachment>[],
            ),
          ]);
        await fixture.db.insert(
          kDirectReactionInboxCustodyOutboxTable,
          const <String, Object?>{
            'recipient_peer_id': survivor,
            'event_id': eventId,
            'wire_envelope': survivorEnvelope,
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'contact_account_peer_id': contact,
            'parent_message_id': messageId,
            'created_at': '2026-08-14T12:00:00.000Z',
            'updated_at': '2026-08-14T12:00:00.000Z',
          },
        );
        final repository = _LifecycleOnlyMutationCustodyRepository(
          backing,
          db: fixture.db,
        );
        final service =
            DirectReactionCustodyP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'my-peer-id',
                ),
              )
              ..detailedInboxOutcome = const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                storeStatus: 'stored',
                expiresAtMs: 1900000000000,
                custodyContract: ackOrExpiryInboxCustodyContract,
              );
        final bridge = FakeBridge();

        expect(
          await retryFailedMessage(
            messageId: messageId,
            messageRepo: repository,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: service,
            bridge: bridge,
          ),
          1,
        );
        expect(service.storeInInboxLog.map((call) => call.toPeerId), [
          survivor,
        ]);
        expect(
          repository.lifecycleLookups,
          0,
          reason: 'no logical-target lookup',
        );
        expect(
          bridge.sendCallCount,
          0,
          reason: 'persisted bytes are not reminted',
        );
        expect(
          await dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
            fixture.db,
            eventId: eventId,
          ),
          isEmpty,
        );
      },
    );

    test(
      'TC-366-02b attachmentless B drains from persisted v109 after A settles',
      () async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        identityRepo.seed(makeIdentity());
        const contact = 'peer-dfe-account';
        const survivor = 'peer-dfe-device-b';
        const messageId = 'tc366-02b-retry-dfe';
        const eventId = '36600000-0000-4000-8000-00000000020b';
        const parentEnvelope =
            '{"type":"message_deletion","version":"2",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"ka","ciphertext":"ca","nonce":"na"}}';
        const survivorEnvelope =
            '{"type":"message_deletion","version":"2",'
            '"eventId":"$eventId","senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"kb","ciphertext":"cb","nonce":"nb"}}';
        final backing = FakeMessageRepository()
          ..seed(<ConversationMessage>[
            makeFailedMessage(
              id: messageId,
              contactPeerId: contact,
              text: '',
            ).copyWith(
              deletedAt: '2026-08-14T12:00:01.000Z',
              deletedByPeerId: 'my-peer-id',
              wireEnvelope: parentEnvelope,
              directEventFanoutGenerationId: eventId,
              media: const <MediaAttachment>[],
            ),
          ]);
        await fixture.db.insert(
          kDirectReactionInboxCustodyOutboxTable,
          const <String, Object?>{
            'recipient_peer_id': survivor,
            'event_id': eventId,
            'wire_envelope': survivorEnvelope,
            'retry_count': 0,
            'last_attempt_at': null,
            'last_error_code': null,
            'contact_account_peer_id': contact,
            'parent_message_id': messageId,
            'created_at': '2026-08-14T12:00:00.000Z',
            'updated_at': '2026-08-14T12:00:00.000Z',
          },
        );
        final repository = _LifecycleOnlyMutationCustodyRepository(
          backing,
          db: fixture.db,
        );
        final service =
            DirectReactionCustodyP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'my-peer-id',
                ),
              )
              ..detailedInboxOutcome = const InboxStoreOutcome(
                status: InboxStoreStatus.stored,
                storeStatus: 'stored',
                expiresAtMs: 1900000000000,
                custodyContract: ackOrExpiryInboxCustodyContract,
              );
        final bridge = FakeBridge();

        expect(
          await retryFailedMessage(
            messageId: messageId,
            messageRepo: repository,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: service,
            bridge: bridge,
          ),
          1,
        );
        expect(service.storeInInboxLog.map((call) => call.toPeerId), [
          survivor,
        ]);
        expect(
          repository.lifecycleLookups,
          0,
          reason: 'B comes from event rows',
        );
        expect(bridge.sendCallCount, 0);
        expect(service.sendMessageWithReplyCallCount, 0);
        expect(
          await dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
            fixture.db,
            eventId: eventId,
          ),
          isEmpty,
        );
      },
    );

    test(
      'targeted failed text retry reuses the original row as first delivery',
      () async {
        identityRepo.seed(makeIdentity());
        const failedMessageId = 'msg-failed-text-001';
        const failedTimestamp = '2026-01-01T00:00:00.000Z';
        messageRepo.seed([
          makeFailedMessage(
            id: failedMessageId,
            contactPeerId: 'peer-target',
            text: 'Recover this text',
            quotedMessageId: 'quoted-parent-001',
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
        );

        final count = await retryFailedMessage(
          messageId: failedMessageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(messageRepo.lastSavedMessage, isNotNull);
        expect(messageRepo.lastSavedMessage!.id, failedMessageId);
        expect(messageRepo.lastSavedMessage!.timestamp, failedTimestamp);
        expect(messageRepo.ordinaryAttemptStages, hasLength(1));
        expect(messageRepo.ordinaryAttemptStages.single.id, failedMessageId);

        final payload = decodeWirePayload(p2pService.lastSendMessageContent!);
        expect(payload['id'], failedMessageId);
        expect(payload['timestamp'], failedTimestamp);
        expect(payload['text'], 'Recover this text');
        expect(payload['quotedMessageId'], 'quoted-parent-001');
        // 116 P1 re-frame: action != edit / editedAt == null is CORRECT for
        // PLAIN rows (no fabricated edit metadata). It is NOT the contract
        // for edit rows — those are covered by the '116 Phase 1 — edit retry
        // fidelity' group below (row-derived action metadata).
        expect(payload['action'], isNot(MessagePayload.actionEdit));
        expect(payload['editedAt'], isNull);
      },
    );

    test(
      'targeted failed text retry is a no-op after the row already settled',
      () async {
        identityRepo.seed(makeIdentity());
        const messageId = 'msg-recovered-text-001';
        messageRepo.seed([
          ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-target',
            senderPeerId: 'my-peer-id',
            text: 'Already recovered',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            transport: 'inbox',
            wireEnvelope: null,
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessage(
          messageId: messageId,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect((await messageRepo.getMessage(messageId))?.status, 'delivered');
      },
    );

    test(
      'failed delete tombstone retries over direct deletion route when inbox store fails',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedDeletedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            acked: true,
            reply: 'ack',
          ),
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 1);
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 1);
        expect(
          events.any((event) => event['event'] == 'CHAT_MSG_SEND_START'),
          isFalse,
        );

        final directEnvelope =
            jsonDecode(p2pService.lastSendMessageContent!)
                as Map<String, dynamic>;
        expect(directEnvelope['type'], 'message_deletion');
        expect(directEnvelope['version'], '2');
        expect(directEnvelope.containsKey('payload'), isFalse);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'delivered');
        expect(saved.transport, 'direct');
        expect(saved.wireEnvelope, isNull);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isTrue);
        expect(saved.hiddenAt, saved.deletedAt);
        expect(
          events.any(
            (event) =>
                event['event'] == 'RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS',
          ),
          isTrue,
        );
      },
    );

    test('R2 failed delete retry requires explicit committed ACK', () async {
      Future<ConversationMessage> runOrdinary({
        required String suffix,
        required p2p.SendMessageResult sendResult,
      }) async {
        final repository = FakeMessageRepository();
        final message = makeFailedDeletedMessage(
          id: 'r2-delete-retry-ordinary-$suffix',
        );
        repository.seed([message]);
        final identities = FakeIdentityRepository()..seed(makeIdentity());
        final contacts = FakeContactRepository()
          ..seed([makeContact(peerId: 'peer-target')]);
        final service = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: sendResult,
        );

        expect(
          await retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ),
          1,
        );
        expect(service.storeInInboxCallCount, 1);
        expect(service.sendMessageWithReplyCallCount, 1);
        return (await repository.getMessage(message.id))!;
      }

      final replyOnlyOrdinary = await runOrdinary(
        suffix: 'reply-only',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          reply: '{"ack":true}',
          transport: 'direct',
        ),
      );
      expect(replyOnlyOrdinary.status, 'sent');
      expect(replyOnlyOrdinary.transport, 'direct');
      expect(replyOnlyOrdinary.wireEnvelope, isNotNull);
      expect(replyOnlyOrdinary.isHidden, isFalse);
      expect(replyOnlyOrdinary.hiddenAt, isNull);

      final ackedOrdinary = await runOrdinary(
        suffix: 'explicit-ack',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          acked: true,
          reply: '{"ack":true}',
          transport: 'direct',
        ),
      );
      expect(ackedOrdinary.status, 'delivered');
      expect(ackedOrdinary.transport, 'direct');
      expect(ackedOrdinary.wireEnvelope, isNull);
      expect(ackedOrdinary.isHidden, isTrue);
      expect(ackedOrdinary.hiddenAt, ackedOrdinary.deletedAt);

      Future<ConversationMessage> runPrivate({
        required String suffix,
        required p2p.SendMessageResult sendResult,
      }) async {
        final fixture = await MediaRepositoryRealDbFixture.create();
        addTearDown(fixture.dispose);
        final messageId = 'r2-delete-retry-private-$suffix';
        await fixture.seedDirectParent(messageId, contactPeerId: 'peer-target');
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'sender_peer_id': 'my-peer-id',
            'text': '',
            'status': 'failed',
            'is_incoming': 0,
            'wire_envelope':
                '{"type":"message_deletion","version":"2","encrypted":{}}',
            'deleted_at': '2026-01-01T00:01:00.000Z',
            'deleted_by_peer_id': 'my-peer-id',
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
        final identities = FakeIdentityRepository()..seed(makeIdentity());
        final contacts = FakeContactRepository()
          ..seed([makeContact(peerId: 'peer-target')]);
        final service = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: false,
          sendMessageWithReplyResult: sendResult,
        );

        expect(
          await retryFailedMessages(
            messageRepo: fixture.messageRepo,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ),
          1,
        );
        return (await fixture.messageRepo.getMessage(messageId))!;
      }

      final replyOnlyPrivate = await runPrivate(
        suffix: 'reply-only',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          reply: '{"ack":true}',
          transport: 'relay',
        ),
      );
      expect(replyOnlyPrivate.status, 'sent');
      expect(replyOnlyPrivate.transport, 'relay');
      expect(replyOnlyPrivate.wireEnvelope, isNotNull);
      expect(replyOnlyPrivate.isHidden, isFalse);
      expect(replyOnlyPrivate.hiddenAt, isNull);

      final ackedPrivate = await runPrivate(
        suffix: 'explicit-ack',
        sendResult: const p2p.SendMessageResult(
          sent: true,
          acked: true,
          reply: '{"ack":true}',
          transport: 'relay',
        ),
      );
      expect(ackedPrivate.status, 'delivered');
      expect(ackedPrivate.transport, 'relay');
      expect(ackedPrivate.wireEnvelope, isNull);
      expect(ackedPrivate.isHidden, isTrue);
      expect(ackedPrivate.hiddenAt, ackedPrivate.deletedAt);
    });

    test(
      'R3 failed delete replay reserves committed ACK after inbox failure',
      () {
        fakeAsync((async) {
          const messageId = 'r3-delete-retry-acked';
          final repository = FakeMessageRepository()
            ..seed([makeFailedDeletedMessage(id: messageId)]);
          final identities = FakeIdentityRepository()..seed(makeIdentity());
          final contacts = FakeContactRepository()
            ..seed([makeContact(peerId: 'peer-target')]);
          final service = _R3RetryDeadlineP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            sendMessageWithReplyResult: const p2p.SendMessageResult(
              sent: true,
              acked: true,
              transport: 'direct',
            ),
            inboxDelay: const Duration(milliseconds: 1200),
            committedAckDelay: const Duration(milliseconds: 2200),
          );
          int? retryCount;
          ConversationMessage? stored;

          retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ).then((value) {
            retryCount = value;
            repository.getMessage(messageId).then((value) => stored = value);
          });
          async.flushMicrotasks();
          expect(service.callOrder, <String>['inbox_start']);

          async.elapse(const Duration(milliseconds: 1200));
          async.flushMicrotasks();
          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
          ]);
          expect(
            service.sendTimeouts,
            <int?>[5500],
            reason: 'the live T0 begins only after inbox custody fails',
          );

          async.elapse(const Duration(milliseconds: 2200));
          async.flushMicrotasks();
          expect(retryCount, 1);
          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
            'send_done',
          ]);
          expect(stored, isNotNull);
          expect(stored!.status, 'delivered');
          expect(stored!.wireEnvelope, isNull);
        });

        fakeAsync((async) {
          const messageId = 'r3-delete-retry-uncommitted';
          final repository = FakeMessageRepository()
            ..seed([makeFailedDeletedMessage(id: messageId)]);
          final identities = FakeIdentityRepository()..seed(makeIdentity());
          final contacts = FakeContactRepository()
            ..seed([makeContact(peerId: 'peer-target')]);
          final service = _R3RetryDeadlineP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
            sendMessageWithReplyResult: const p2p.SendMessageResult(
              sent: true,
              acked: false,
              transport: 'direct',
            ),
          );
          ConversationMessage? stored;

          retryFailedMessages(
            messageRepo: repository,
            identityRepo: identities,
            contactRepo: contacts,
            p2pService: service,
            bridge: PassthroughCryptoBridge(),
          ).then(
            (_) => repository
                .getMessage(messageId)
                .then((value) => stored = value),
          );
          async.flushMicrotasks();

          expect(service.callOrder, <String>[
            'inbox_start',
            'inbox_done',
            'send_start',
            'send_done',
          ]);
          expect(service.sendTimeouts.single, greaterThan(3000));
          expect(stored, isNotNull);
          expect(stored!.status, 'sent');
          expect(stored!.wireEnvelope, isNotNull);
        });
      },
    );

    test(
      'v2 tombstone inbox custody success is inboxed and keeps the tombstone visible',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedDeletedMessage()]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, makeFailedDeletedMessage().wireEnvelope);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
        expect(saved.hiddenAt, isNull);
      },
    );

    test(
      'emits RETRY_FAILED_MESSAGES_TIMING with total and succeeded counts',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: bridge,
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_FAILED_MESSAGES_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['total'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'returns 0 when all retries fail (sendMessageWithReply not sent)',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        // discoverPeer returns null so sendChatMessage gets peerNotFound
        // and after 3 retries falls back to storeInInbox which also fails
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: null, // peer not found
          dialPeerResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(sent: false),
          storeInInboxResult: false, // inbox fallback also fails
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
      },
    );

    test('continues on per-message error and still tries next message', () async {
      identityRepo.seed(makeIdentity());
      messageRepo.seed([
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-a'),
        makeFailedMessage(id: 'msg-fail-002', contactPeerId: 'peer-b'),
      ]);
      contactRepo.seed([
        makeContact(peerId: 'peer-a'),
        makeContact(peerId: 'peer-b'),
      ]);

      // First call to sendMessageWithReply throws, second succeeds.
      // sendChatMessage uses maxAttempts=1 per message, so index 0 is
      // the first message's single attempt, and index 1 is the second
      // message's single attempt. We throw on index 0 (msg 1 fails)
      // and let index 1 succeed (msg 2).
      final p2pService = _PerMessageThrowingP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        throwOnCallIndices: {0},
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-b',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: false, // inbox fallback fails for msg 1
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // msg-fail-001 failed (single attempt threw + inbox failed), msg-fail-002 succeeded
      expect(count, 1);
    });

    test('returns correct count when multiple messages all succeed', () async {
      identityRepo.seed(makeIdentity());
      messageRepo.seed([
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-a'),
        makeFailedMessage(id: 'msg-fail-002', contactPeerId: 'peer-b'),
        makeFailedMessage(id: 'msg-fail-003', contactPeerId: 'peer-c'),
      ]);
      contactRepo.seed([
        makeContact(peerId: 'peer-a'),
        makeContact(peerId: 'peer-b'),
        makeContact(peerId: 'peer-c'),
      ]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'any-peer',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 3);
    });

    test('does not retry messages that are not failed', () async {
      identityRepo.seed(makeIdentity());
      // Seed a delivered message and a failed message
      messageRepo.seed([
        ConversationMessage(
          id: 'msg-ok-001',
          contactPeerId: 'peer-a',
          senderPeerId: 'my-peer-id',
          text: 'Already sent',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
        makeFailedMessage(id: 'msg-fail-001', contactPeerId: 'peer-b'),
      ]);
      contactRepo.seed([makeContact(peerId: 'peer-b')]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-b',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // Only the failed message should be retried
      expect(count, 1);
    });

    test(
      'returns 0 when node is not running (sendChatMessage fails)',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);

        // Node NOT started -- sendChatMessage returns nodeNotRunning
        final p2pService = FakeP2PService(initialState: NodeState.stopped);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
      },
    );

    test(
      'does not retry message without ML-KEM key using plaintext fallback',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        // Contact exists but has no ML-KEM public key
        contactRepo.seed([
          makeContact(peerId: 'peer-target', mlKemPublicKey: null),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'does not retry message when contact is missing using plaintext fallback',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedMessage()]);
        // No contact seeded — contactRepo returns null → mlKemPublicKey is null

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'does not replay persisted v1 chat wireEnvelope to inbox after restart',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyChatMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('Legacy leak sentinel')),
        );
        expect(p2pService.lastStoreInInboxMessage, contains('"version":"2"'));
      },
    );

    test(
      'legacy v1 delete tombstone is rebuilt as encrypted v2 when key exists',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyDeletedMessage()]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = _GatedInboxP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        final retry = retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );
        await p2pService.entered.future;
        try {
          expect(messageRepo.ordinaryAttemptStages, hasLength(1));
          final staged = await messageRepo.getMessage('msg-legacy-delete-001');
          expect(staged, isNotNull);
          expect(staged!.status, 'sending');
          expect(staged.transport, isNull);
          expect(staged.wireEnvelope, p2pService.lastStoreInInboxMessage);
          expect(staged.wireEnvelope, contains('"version":"2"'));
          expect(staged.isDeleted, isTrue);
          expect(staged.isHidden, isFalse);
        } finally {
          p2pService.gate.complete();
        }
        final count = await retry;

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('"version":"1"')),
        );
        expect(
          p2pService.lastStoreInInboxMessage,
          isNot(contains('"payload"')),
        );
        final envelope =
            jsonDecode(p2pService.lastStoreInInboxMessage!)
                as Map<String, dynamic>;
        expect(envelope['type'], 'message_deletion');
        expect(envelope['version'], '2');
        expect(envelope['encrypted'], isA<Map<String, dynamic>>());
        expect(envelope.containsKey('payload'), isFalse);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, p2pService.lastStoreInInboxMessage);
        expect(saved.isDeleted, isTrue);
        expect(saved.isHidden, isFalse);
      },
    );

    test(
      'legacy tombstone without recipient key stays failed with explicit telemetry',
      () async {
        identityRepo.seed(makeIdentity());
        messageRepo.seed([makeFailedLegacyDeletedMessage()]);
        contactRepo.seed([
          makeContact(peerId: 'peer-target', mlKemPublicKey: null),
        ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 0);
        });

        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(messageRepo.lastSavedMessage, isNull);
        final saved = await messageRepo.getMessage('msg-legacy-delete-001');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, contains('"version":"1"'));

        final unavailable = events.singleWhere(
          (event) =>
              event['event'] == 'RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE',
        );
        expect(
          (unavailable['details'] as Map<String, dynamic>)['reason'],
          'missing_recipient_key',
        );
      },
    );

    test('wire_envelope inbox path sets transport to inbox', () async {
      identityRepo.seed(makeIdentity());
      // Failed message with wire_envelope — should use inbox fast path
      final msgWithEnvelope = ConversationMessage(
        id: 'msg-env-001',
        contactPeerId: 'peer-target',
        senderPeerId: 'my-peer-id',
        text: 'Hello',
        timestamp: '2026-01-01T00:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-01-01T00:00:00.000Z',
        wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{}}',
      );
      messageRepo.seed([msgWithEnvelope]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(count, 1);
      expect(p2pService.storeInInboxCallCount, 1);

      // F6: relay STORE success is custody, not receiver delivery — 'inboxed'
      // with the wire envelope retained for the custody sweep + receipt repair.
      final saved = messageRepo.lastSavedMessage;
      expect(saved, isNotNull);
      expect(saved!.status, 'inboxed');
      expect(saved.transport, 'inbox');
      expect(saved.wireEnvelope, isNotNull);
    });

    test(
      'wire_envelope inbox path preserves GIF metadata for GIF retries',
      () async {
        identityRepo.seed(makeIdentity());
        final msgWithEnvelope = ConversationMessage(
          id: 'msg-gif-env-001',
          contactPeerId: 'peer-target',
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          wireEnvelope: jsonEncode({
            'type': 'chat_message',
            'version': '2',
            'payload': {
              'id': 'msg-gif-env-001',
              'text': '',
              'media': [
                {
                  'id': 'gif-1',
                  'mime': 'image/gif',
                  'size': 4096,
                  'mediaType': 'image',
                },
              ],
            },
          }),
        );
        messageRepo.seed([msgWithEnvelope]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastStoreInInboxMessage,
          contains('"mime":"image/gif"'),
        );

        // F6: 'inboxed' custody, envelope (incl GIF media metadata) retained.
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, isNotNull);
      },
    );

    for (final storeAccepted in [false, true]) {
      test('failed inbox transport requires a new custody receipt '
          '(accepted=$storeAccepted)', () async {
        identityRepo.seed(makeIdentity());
        // An inbox route can survive a rejected STORE or an older UI recovery.
        // The route is not evidence that the relay accepted the envelope.
        final msgWithInboxTransport = ConversationMessage(
          id: 'msg-crash-001',
          contactPeerId: 'peer-target',
          senderPeerId: 'my-peer-id',
          text: 'Crash test',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          transport: 'inbox',
          wireEnvelope:
              '{"type":"chat_message","version":"2","id":"msg-crash-001",'
              '"senderPeerId":"my-peer-id","encrypted":'
              '{"kem":"test-kem","ciphertext":"test-cipher","nonce":"test-nonce"}}',
        );
        messageRepo.seed([msgWithInboxTransport]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: storeAccepted,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(p2pService.storeInInboxCallCount, 1);
        expect(
          p2pService.lastStoreInInboxMessage,
          msgWithInboxTransport.wireEnvelope,
        );
        expect(count, storeAccepted ? 1 : 0);
        final saved = await messageRepo.getMessage(msgWithInboxTransport.id);
        expect(saved, isNotNull);
        expect(saved!.status, storeAccepted ? 'inboxed' : 'failed');
        expect(saved.wireEnvelope, msgWithInboxTransport.wireEnvelope);
      });
    }

    test('calls getFailedOutgoingMessages on messageRepo', () async {
      identityRepo.seed(makeIdentity());
      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

      await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      expect(messageRepo.getFailedOutgoingCallCount, 1);
    });

    // --- NET-REL-05 R1: concurrent-fallback interaction (regression) ---
    //
    // The new concurrent durable fallback (U-P1P4) settles a low-confidence send
    // as a row with status='delivered', transport='inbox', wireEnvelope=null once
    // the relay takes custody. This is the SAME terminal shape the existing inbox
    // tail produces. These tests pin that such a row is invisible to the failed
    // retrier so the concurrent copy is never sent a SECOND time.
    test('concurrently-inboxed message (delivered/inbox/null-envelope) is NOT '
        'picked up by the failed retrier', () async {
      identityRepo.seed(makeIdentity());
      // The exact row shape persistInboxDelivered writes for a concurrent
      // fallback that took custody: terminal delivered, transport inbox,
      // wireEnvelope cleared.
      messageRepo.seed([
        ConversationMessage(
          id: 'msg-concurrent-inbox-001',
          contactPeerId: 'peer-target',
          senderPeerId: 'my-peer-id',
          text: 'Low-confidence send',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-01-01T00:00:00.000Z',
          transport: 'inbox',
          wireEnvelope: null,
        ),
      ]);
      contactRepo.seed([makeContact(peerId: 'peer-target')]);

      final p2pService = FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        discoverPeerResult: const DiscoveredPeer(
          id: 'peer-target',
          addresses: ['/ip4/127.0.0.1/tcp/4001'],
        ),
        dialPeerResult: true,
        sendMessageWithReplyResult: const p2p.SendMessageResult(
          sent: true,
          reply: 'ack',
        ),
        storeInInboxResult: true,
      );

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
      );

      // NEGATIVE CONTROL: the durable copy must NOT be re-sent. No live send,
      // no second inbox store, nothing retried.
      expect(count, 0);
      expect(p2pService.sendMessageWithReplyCallCount, 0);
      expect(p2pService.storeInInboxCallCount, 0);
      // Row is untouched / still delivered (no resave that could regress it).
      expect(
        (await messageRepo.getMessage('msg-concurrent-inbox-001'))?.status,
        'delivered',
      );
    });

    test(
      'failed retrier still prefers inbox-only re-store from persisted '
      'wireEnvelope and does not double-send live alongside concurrent fallback',
      () async {
        identityRepo.seed(makeIdentity());
        // A genuinely failed row that DID persist a safe v2 envelope. The
        // retrier must re-store it via inbox ONLY (one storeInInbox, no live
        // sendMessageWithReply), proving the inbox-first preference is intact
        // and never escalates to a duplicate live send.
        messageRepo.seed([
          ConversationMessage(
            id: 'msg-failed-with-envelope-001',
            contactPeerId: 'peer-target',
            senderPeerId: 'my-peer-id',
            text: 'Hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'failed',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{}}',
          ),
        ]);
        contactRepo.seed([makeContact(peerId: 'peer-target')]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-target',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        expect(count, 1);
        // Inbox-only re-store: exactly one store, ZERO live sends.
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        // F6: settled custody — 'inboxed'/inbox/envelope-retained. Invisible to
        // the FAILED retrier (status != 'failed'); rides the custody sweep +
        // DeliveryReceiptListener for the receiver-confirmed 'delivered'.
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'inboxed');
        expect(saved.transport, 'inbox');
        expect(saved.wireEnvelope, isNotNull);
      },
    );
  });

  // ─── 116 Phase 1 — edit retry fidelity through the full-send fallback ───
  // A failed edit retried via the fallback must STAY an edit: row-derived
  // action metadata (EF-1), never caller defaults. Without it the retry goes
  // out as a plain send under the original id, the receiver dedups it by id,
  // and sender/receiver text silently diverge (doc 116 §1).
  group('116 Phase 1 — edit retry fidelity', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;

    setUp(() {
      identityRepo = FakeIdentityRepository()..seed(makeIdentity());
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository()
        ..seed([makeContact(peerId: 'peer-target')]);
    });

    FakeP2PService makeHealthyDirectInboxDownP2P() => FakeP2PService(
      initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      discoverPeerResult: const DiscoveredPeer(
        id: 'peer-target',
        addresses: ['/ip4/127.0.0.1/tcp/4001'],
      ),
      dialPeerResult: true,
      sendMessageWithReplyResult: const p2p.SendMessageResult(
        sent: true,
        acked: true,
        reply: 'ack',
      ),
      // Envelope replay fails → the full-send fallback fires.
      storeInInboxResult: false,
    );

    test(
      'cached current edit replays exact bytes with one stable event id',
      () async {
        final failed = makeFailedEditMessage(eventId: 'edit-event-exact');
        messageRepo.seed([failed]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.lastStoreInInboxMessage, failed.wireEnvelope);
        final envelope =
            jsonDecode(failed.wireEnvelope!) as Map<String, dynamic>;
        expect(envelope['id'], failed.id);
        expect(envelope['eventId'], 'edit-event-exact');
      },
    );

    test(
      'current edit store failure retains exact envelope without re-encryption',
      () async {
        final failed = makeFailedEditMessage(eventId: 'edit-event-stable');
        messageRepo.seed([failed]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          expect(
            await retryFailedMessages(
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            0,
          );
        });

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxMessage, failed.wireEnvelope);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(messageRepo.ordinaryAttemptStages, isEmpty);
        expect(
          (await messageRepo.getMessage(failed.id))?.wireEnvelope,
          failed.wireEnvelope,
        );
        expect(
          events.any(
            (event) =>
                event['event'] == 'RETRY_FAILED_EDIT_EXACT_ENVELOPE_RETAINED',
          ),
          isTrue,
        );
      },
    );

    test(
      'v2 legacy edit without event id never replays cached bytes and mints once before transport',
      () async {
        final failed = makeFailedV2EditWithoutEventId();
        messageRepo.seed([failed]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          expect(
            await retryFailedMessages(
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            1,
          );
        });

        expect(
          p2pService.storeInInboxLog
              .map((entry) => entry.message)
              .contains(failed.wireEnvelope),
          isFalse,
          reason: 'legacy same-target bytes must not enter relay dedupe',
        );
        expect(
          events.any(
            (event) =>
                event['event'] ==
                'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          ),
          isTrue,
        );
        final rebuilt = p2pService.lastSendMessageContent!;
        final outer = jsonDecode(rebuilt) as Map<String, dynamic>;
        final inner = decodeWirePayload(rebuilt);
        expect(outer['id'], failed.id);
        expect(outer['eventId'], isA<String>());
        expect((outer['eventId'] as String).trim(), isNotEmpty);
        expect(inner['eventId'], outer['eventId']);
        expect(inner['action'], MessagePayload.actionEdit);
        expect(inner['editedAt'], '2026-01-01T00:05:00.000001Z');
        expect(inner['timestamp'], '2026-01-01T00:00:00.000Z');
        expect(
          messageRepo.lastSavedMessage?.editedAt,
          '2026-01-01T00:05:00.000001Z',
        );
        expect(
          messageRepo.lastSavedMessage?.createdAt,
          '2026-01-01T00:00:00.000Z',
        );
        final stagedOuter =
            jsonDecode(messageRepo.ordinaryAttemptStages.single.wireEnvelope!)
                as Map<String, dynamic>;
        expect(stagedOuter['eventId'], outer['eventId']);
      },
    );

    test(
      'edit metadata survives a fallback attempt that fails terminally',
      () async {
        messageRepo.seed([
          makeFailedV2EditWithoutEventId(id: 'msg-edit-fail-001'),
        ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          // ALL transports fail: no discover, no send, no inbox.
          discoverPeerResult: null,
          dialPeerResult: false,
          sendMessageWithReplyResult: const p2p.SendMessageResult(sent: false),
          storeInInboxResult: false,
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 0);
        final row = await messageRepo.getMessage('msg-edit-fail-001');
        expect(row!.status, 'failed');
        expect(
          row.editedAt,
          '2026-01-01T00:05:00.000001Z',
          reason: 'a failed fallback attempt must never null the edit metadata',
        );
        // The last persisted envelope must still be an EDIT envelope — the
        // edit must remain recoverable by the next retry cycle.
        final lastEnvelope = decodeWirePayload(
          messageRepo.ordinaryAttemptStages.last.wireEnvelope!,
        );
        expect(lastEnvelope['action'], MessagePayload.actionEdit);
      },
    );

    test(
      'v1-legacy failed edit row reconstructs edit params from the DB row',
      () async {
        messageRepo.seed([makeFailedLegacyEditMessage()]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 1);
        });

        // Leak guard preserved: the v1 envelope never reaches any transport.
        // FDC-03: the rebuilt (NOT legacy) payload now also fires one concurrent
        // durable copy on this unknown-presence retry. The direct send carries
        // the rebuilt edit payload (asserted below) and the inbox attempt carries
        // the same rebuilt jsonString — so no v1 envelope leaks.
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'newly authored edits never use the legacy bool store',
        );
        expect(
          events.any(
            (e) =>
                e['event'] == 'RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE',
          ),
          isTrue,
        );
        // The rebuilt outgoing payload carries the row's edit metadata.
        final payload = decodeWirePayload(p2pService.lastSendMessageContent!);
        expect(payload['action'], MessagePayload.actionEdit);
        expect(payload['editedAt'], '2026-01-01T00:05:00.000001Z');
        expect(payload['id'], 'msg-legacy-edit-001');
        expect(payload['timestamp'], '2026-01-01T00:00:00.000Z');
      },
    );

    test(
      'plain failed retry preserves the original createdAt on the settled row',
      () async {
        messageRepo.seed([makeFailedMessage()]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        expect(count, 1);
        expect(
          messageRepo.lastSavedMessage!.createdAt,
          '2026-01-01T00:00:00.000Z',
          reason: 'the fallback must not re-mint createdAt for retried rows',
        );
      },
    );

    // 116 P2.2 companion PIN (green-on-arrival post-P1): the pre-race
    // guarded attempt stage of a retried edit writes an EDIT envelope.
    // This is the explicit prerequisite the 115 P3 custody sweep inherits:
    // a sweep re-store of an edit row's wire_envelope carries action:edit.
    test(
      'retried edit pre-race envelope persist writes an edit envelope',
      () async {
        messageRepo.seed([
          makeFailedV2EditWithoutEventId(id: 'msg-edit-fail-001'),
        ]);
        final p2pService = makeHealthyDirectInboxDownP2P();

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: PassthroughCryptoBridge(),
        );

        final persisted = decodeWirePayload(
          messageRepo.ordinaryAttemptStages.single.wireEnvelope!,
        );
        expect(persisted['action'], MessagePayload.actionEdit);
        expect(persisted['editedAt'], '2026-01-01T00:05:00.000001Z');
      },
    );
  });

  // ─── 116 Phase 2 — single-flight + settled-skip (EF-3) ──────────────────
  // PendingMessageRetrier periodic + reconnect debounce + app-resume 8c + the
  // UI retry button can overlap: at most ONE retry per message id may be in
  // flight, and a candidate whose row settled between load and execution is
  // skipped, not re-sent.
  group('116 Phase 2 — single-flight and settled-skip', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;

    setUp(() {
      identityRepo = FakeIdentityRepository()..seed(makeIdentity());
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository()
        ..seed([makeContact(peerId: 'peer-target')]);
    });

    test(
      'concurrent retries of the same failed row send at most once (single-flight per message id)',
      () async {
        messageRepo.seed([makeFailedEditMessage()]);
        final p2pService = _GatedInboxP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        late List<int> results;
        final events = await captureFlowEvents(() async {
          final futures = Future.wait([
            retryFailedMessage(
              messageId: 'msg-edit-fail-001',
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
            retryFailedMessage(
              messageId: 'msg-edit-fail-001',
              messageRepo: messageRepo,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: p2pService,
              bridge: PassthroughCryptoBridge(),
            ),
          ]);
          // Let both invocations reach the candidate before releasing.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          p2pService.gate.complete();
          results = await futures;
        });

        expect(
          p2pService.storeInInboxCallCount,
          1,
          reason: 'exactly one in-flight retry per message id (EF-3)',
        );
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(results..sort(), [0, 1]);
        expect(
          events
              .where(
                (e) => e['event'] == 'RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT',
              )
              .length,
          1,
        );
      },
    );

    test(
      'retry candidate skips a row that settled between load and execution',
      () async {
        // Stored state: the row already settled 'delivered'. The sweep's loaded
        // list still holds a STALE 'failed' snapshot of the same row.
        final staleSnapshot = makeFailedEditMessage(id: 'msg-stale-001');
        messageRepo.seed([
          staleSnapshot.copyWith(status: 'delivered', wireEnvelope: null),
        ]);
        messageRepo.failedOutgoingOverride = [staleSnapshot];

        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
          storeInInboxResult: true,
        );

        final events = await captureFlowEvents(() async {
          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: PassthroughCryptoBridge(),
          );
          expect(count, 0);
        });

        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'a settled row must never be re-sent from a stale snapshot',
        );
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(
          events.any(
            (e) => e['event'] == 'RETRY_FAILED_MESSAGE_SKIPPED_SETTLED',
          ),
          isTrue,
        );
        expect(
          (await messageRepo.getMessage('msg-stale-001'))!.status,
          'delivered',
        );
      },
    );
  });
}

/// Exposes ONLY the shared v109 lifecycle capability.
///
/// 356: a private deletion event is staged by the private owner, so retry must
/// resolve its exact custody through [DirectMutationInboxCustodyLifecycleRepository]
/// and never through the ordinary text-stage capability. Anything this wrapper
/// does not forward is a call the retry path had no business making.
class _LifecycleOnlyMutationCustodyRepository
    implements
        MessageRepository,
        OutgoingTransportMutationRepository,
        DirectMutationInboxCustodyLifecycleRepository,
        OutgoingDirectEventFanoutRepository {
  _LifecycleOnlyMutationCustodyRepository(
    this.delegate, {
    required this.db,
    this.onLookup,
  });

  final FakeMessageRepository delegate;

  /// The REAL physical v109 outbox, read through the same helpers production
  /// wires into [MessageRepositoryImpl].
  final Database db;

  /// Fires before each lookup with its 1-based index, so a test can move
  /// ownership at an exact production checkpoint without a production hook.
  final Future<void> Function(int lookupIndex)? onLookup;

  int lifecycleLookups = 0;

  /// The lookup indexes that actually resolved an owner.
  final List<int> ownedAtLookups = <int>[];

  @override
  bool get supportsDirectMutationInboxCustodyLifecycle => true;

  @override
  bool get supportsDirectEventFanout => true;

  @override
  Future<List<Map<String, Object?>>> loadDirectEventFanoutSiblings(
    String eventId,
  ) => dbLoadDirectReactionInboxCustodyOutboxRowsForEventId(
    db,
    eventId: eventId,
  );

  @override
  Future<List<Map<String, Object?>>> loadDirectTextFanoutSiblings(
    String messageId,
  ) => Future<List<Map<String, Object?>>>.value(const []);

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshot(
    String contactAccountPeerId,
  ) => throw StateError('retry must not read the current roster');

  @override
  Future<DbDirectEventFanoutStageResult> stageDirectTextFanout({
    required Map<String, Object?> stagedRow,
    required String messageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  }) => throw StateError('retry must not stage a fanout generation');

  @override
  Future<DbDirectEventFanoutStageResult> stageDirectTextMutationFanout({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required OutgoingOrdinaryAttemptKind kind,
    required String eventId,
    required String parentMessageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  }) => throw StateError('retry must not restage a mutation fanout');

  @override
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  }) async {
    lifecycleLookups++;
    await onLookup?.call(lifecycleLookups);
    final row = await dbLoadDirectReactionInboxCustodyOutboxForEvent(
      db,
      recipientPeerId: recipientPeerId,
      eventId: eventId,
    );
    if (row == null) return null;
    ownedAtLookups.add(lifecycleLookups);
    return DirectReactionInboxCustodyOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) => dbRecordDirectReactionInboxCustodyFailureIfExact(
    db,
    recipientPeerId: expected.recipientPeerId,
    eventId: expected.eventId,
    expectedWireEnvelope: expected.wireEnvelope,
    errorCode: errorCode,
    attemptedAt: DateTime.utc(2026).toIso8601String(),
  );

  @override
  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) => dbCompleteAcceptedDirectMutationInboxCustodyIfExact(
    db,
    recipientPeerId: expected.recipientPeerId,
    eventId: expected.eventId,
    expectedWireEnvelope: expected.wireEnvelope,
    relayExpiresAt: relayExpiresAt,
  );

  @override
  Future<ConversationMessage?> getMessage(String id) => delegate.getMessage(id);

  // The incumbent ordinary settlement surface stays available: only the
  // TEXT-STAGE custody capability is withheld, so a retry that casts through
  // it misses an owner the shared v109 lifecycle would have found.
  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) => delegate.stageOutgoingOrdinaryAttempt(
    expected: expected,
    staged: staged,
    kind: kind,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => delegate.settleOutgoingOrdinaryTransport(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) => delegate.settleOutgoingOrdinaryDeleteTombstone(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    status: status,
    transport: transport,
    relayExpiresAt: relayExpiresAt,
    mode: mode,
  );

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) => delegate.invalidateOutgoingOrdinaryEnvelope(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
  );

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) => delegate.quarantineUnsafeLegacyOutgoingEnvelope(
    messageId: messageId,
    expectedContactPeerId: expectedContactPeerId,
    expectedEnvelope: expectedEnvelope,
    isDeleteTombstone: isDeleteTombstone,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'lifecycle-only repository received ${invocation.memberName}',
  );
}
