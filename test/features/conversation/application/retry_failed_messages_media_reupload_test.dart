import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../features/conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import 'helpers/fake_upload_media_fn.dart';

class _FakeDirectManualUploadRetryRearmRepository
    implements DirectManualUploadRetryRearmRepository {
  _FakeDirectManualUploadRetryRearmRepository({
    required this.messageRepo,
    required this.mediaAttachmentRepo,
  });

  final FakeMessageRepository messageRepo;
  final FakeMediaAttachmentRepository mediaAttachmentRepo;
  int callCount = 0;
  bool willApply = true;
  List<ManualUploadRetryAttachmentExpectation>? lastExpectations;

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    callCount++;
    lastExpectations = List.unmodifiable(attachments);
    if (!willApply) return false;
    final parent = await messageRepo.getMessage(messageId);
    if (parent == null || parent.isIncoming || parent.status != 'failed') {
      return false;
    }
    final persisted = await mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    final unfinished = persisted
        .where((attachment) => attachment.downloadStatus != 'done')
        .toList(growable: false);
    if (unfinished.length != attachments.length) return false;
    for (final expected in attachments) {
      final matches = unfinished.where(
        (attachment) =>
            attachment.id == expected.attachmentId &&
            attachment.localPath == expected.storedLocalPath &&
            attachment.downloadStatus == expected.downloadStatus &&
            (attachment.uploadRetryCount ?? 0) == expected.uploadRetryCount,
      );
      if (matches.length != 1) return false;
    }

    await messageRepo.saveMessage(
      parent.copyWith(status: 'sending', wireEnvelope: null),
    );
    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final current = unfinished.singleWhere(
        (attachment) => attachment.id == expected.attachmentId,
      );
      await mediaAttachmentRepo.saveAttachment(
        current.copyWith(downloadStatus: 'upload_pending', uploadRetryCount: 0),
        owner: MediaOwnerLane.direct,
      );
    }
    return true;
  }
}

enum _FailedRetryParentCrossing { deleted, settled }

class _CrossingFailedMessageRepository extends FakeMessageRepository {
  _CrossingFailedMessageRepository(this.crossing);

  final _FailedRetryParentCrossing crossing;
  bool crossedAfterListLoad = false;

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    final loaded = await super.getFailedOutgoingMessages();
    if (!crossedAfterListLoad && loaded.isNotEmpty) {
      crossedAfterListLoad = true;
      switch (crossing) {
        case _FailedRetryParentCrossing.deleted:
          await deleteMessage(loaded.single.id);
          break;
        case _FailedRetryParentCrossing.settled:
          await updateMessageStatus(loaded.single.id, 'delivered');
          break;
      }
    }
    return loaded;
  }
}

class _AckCustodyRetryP2PService extends FakeP2PService
    implements AckOrExpiryInboxStore {
  _AckCustodyRetryP2PService()
    : super(
        initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
      );

  int ackCustodyCallCount = 0;
  String? lastAckCustodyPeerId;
  String? lastAckCustodyEnvelope;
  AckCustodyKind? lastAckCustodyKind;

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    ackCustodyCallCount++;
    lastAckCustodyPeerId = toPeerId;
    lastAckCustodyEnvelope = message;
    lastAckCustodyKind = custodyKind;
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      expiresAtMs: 4102444800000,
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

class _RecordingLegacyUploadFailureProjection
    implements DirectUploadRetryProjectionRepository {
  int callCount = 0;
  String? lastMessageId;
  String? lastAttachmentId;
  UploadMediaFailed? lastFailure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    callCount++;
    lastMessageId = messageId;
    lastAttachmentId = attachmentId;
    lastFailure = failure;
    return const UploadRetryProjectionResult(
      state: UploadRetryProjectionState.retryPending,
    );
  }
}

class _ExistingDirectMediaBlobRetryRepository
    extends FakeMediaAttachmentRepository
    implements DirectMediaBlobCustodyRepository {
  _ExistingDirectMediaBlobRetryRepository(this.row);

  DirectMediaBlobCustodyRow row;
  int stageCalls = 0;
  int transitionCalls = 0;

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => action();

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    stageCalls++;
    final persisted = await getAttachmentsForMessage(
      expectedParent.id,
      owner: MediaOwnerLane.direct,
    );
    if (expectedParent.id != row.messageId ||
        expectedParent.contactPeerId != row.recipientPeerId ||
        expectedAttachments.length != 1 ||
        preparedAttachments.length != 1 ||
        custodyRows.length != 1 ||
        persisted.length != 1 ||
        expectedAttachments.single.id != row.attachmentId ||
        preparedAttachments.single.id != row.attachmentId ||
        persisted.single.id != row.attachmentId ||
        preparedAttachments.single.contentHash != row.contentHash ||
        persisted.single.contentHash != row.contentHash ||
        !custodyRows.single.exactDatabaseProjectionMatches(row)) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.idempotent,
      attachments: persisted,
      custodyRows: <DirectMediaBlobCustodyRow>[row],
    );
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async =>
      attachmentId == row.attachmentId
      ? <DirectMediaBlobCustodyRow>[row]
      : const <DirectMediaBlobCustodyRow>[];

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async =>
      attachmentId == row.attachmentId &&
          row.direction == DirectMediaBlobCustodyDirection.incoming
      ? row
      : null;

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async =>
      attachmentId == row.attachmentId &&
          row.direction == DirectMediaBlobCustodyDirection.outgoing &&
          row.recipientPeerId == recipientPeerId
      ? row
      : null;

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => messageId == row.messageId
      ? <DirectMediaBlobCustodyRow>[row]
      : const <DirectMediaBlobCustodyRow>[];

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => states.contains(row.state)
      ? <DirectMediaBlobCustodyRow>[row]
      : const <DirectMediaBlobCustodyRow>[];

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    transitionCalls++;
    if (!row.exactDatabaseProjectionMatches(expected) ||
        !expected.canTransitionTo(next)) {
      return false;
    }
    row = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;
}

IdentityModel _makeIdentity() {
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

ConversationMessage _makeFailedMsg({
  String id = 'msg-fail-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
  String text = 'Hello',
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
    wireEnvelope: wireEnvelope,
  );
}

ContactModel _makeContact({
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

const _testContentHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

MediaAttachment _makeAttachment({
  String id = 'att-001',
  required String messageId,
  String? localPath = '/tmp/img.jpg',
  String downloadStatus = 'failed',
  String mime = 'image/jpeg',
  String mediaType = 'image',
  int? durationMs,
  int? uploadRetryCount,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: mediaType,
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: '2026-01-01T00:00:00.000Z',
    durationMs: durationMs,
    uploadRetryCount: uploadRetryCount,
    contentHash: _testContentHash,
    encryptionKeyBase64: 'test-blob-key-base64',
    encryptionNonce: 'test-blob-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeMessageRepository messageRepo;
  late FakeContactRepository contactRepo;
  late FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeBridge bridge;
  late FakeUploadMediaFn fakeUploadFn;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late MediaUploadInFlightTracker uploadTracker;
  late _FakeDirectManualUploadRetryRearmRepository manualRearmRepo;

  setUp(() {
    identityRepo = FakeIdentityRepository();
    messageRepo = FakeMessageRepository();
    contactRepo = FakeContactRepository();
    mediaAttachmentRepo = FakeMediaAttachmentRepository();
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
    fakeUploadFn = FakeUploadMediaFn();
    mediaFileManager = FakeMediaFileManager();
    uploadTracker = MediaUploadInFlightTracker();
    manualRearmRepo = _FakeDirectManualUploadRetryRearmRepository(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );

    identityRepo.seed(_makeIdentity());
    contactRepo.seed([_makeContact(peerId: 'peer-target')]);

    p2pService = FakeP2PService(
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
  });

  Future<int> retryManual(
    String messageId, {
    FakeMediaFileManager? manager,
    void Function(Iterable<String> attachmentIds)? onClaim,
    DirectUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  }) {
    return retryFailedMessage(
      messageId: messageId,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
      mediaFileManager: manager,
      uploadRetryProjectionRepo: uploadRetryProjectionRepo,
      uploadRetryRearmRepo: manualRearmRepo,
      tryClaimUploadLease: (attachmentIds) {
        onClaim?.call(attachmentIds);
        return uploadTracker.tryClaimAll(
          attachmentIds,
          source: MediaUploadTriggerSource.manual,
        );
      },
      releaseUploadLease: uploadTracker.release,
    );
  }

  group('retryFailedMessages -- re-upload incomplete media', () {
    test(
      'TC-345-07b failed retry respects media intent and existing v108 authority before rebuild',
      () async {
        final owned = _makeFailedMsg(id: 'msg-v108-media-retry');
        final ownedAttachment = _makeAttachment(
          id: 'att-v108-media-retry',
          messageId: owned.id,
          downloadStatus: 'done',
        );
        messageRepo.seed(<ConversationMessage>[owned]);
        mediaAttachmentRepo.seed(<MediaAttachment>[ownedAttachment]);
        messageRepo.seedDirectInboxCustody(
          DirectInboxCustodyOutboxEntry(
            recipientPeerId: owned.contactPeerId,
            messageId: owned.id,
            incarnationId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"owned"}}',
            retryCount: 0,
            lastAttemptAt: null,
            lastErrorCode: null,
            createdAt: '2026-08-07T12:00:00.000Z',
            updatedAt: '2026-08-07T12:00:00.000Z',
          ),
        );

        final ownedCount = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          retryDirectInboxCustody: false,
        );

        expect(ownedCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.storeInInboxCallCount, 0);
        expect(messageRepo.directCustodyRows, hasLength(1));
        expect(
          (await messageRepo.getMessage(owned.id))!.toMap(),
          owned.toMap(),
        );

        // The failed list is a snapshot. A lifecycle mutation may settle or
        // physically remove its parent after that list read but before this
        // candidate executes. The independent v108 row must still be resolved
        // from the loaded scope and must remain the only retry authority.
        for (final crossing in _FailedRetryParentCrossing.values) {
          final crossingMessageRepo = _CrossingFailedMessageRepository(
            crossing,
          );
          final crossingMediaRepo = FakeMediaAttachmentRepository();
          final crossingBridge = FakeBridge();
          final crossingUpload = FakeUploadMediaFn();
          final crossingP2p = _AckCustodyRetryP2PService();
          final crossingMessage = _makeFailedMsg(
            id: 'msg-v108-${crossing.name}-after-list-load',
          );
          final crossingAttachment = _makeAttachment(
            id: 'att-v108-${crossing.name}-after-list-load',
            messageId: crossingMessage.id,
            downloadStatus: 'upload_pending',
          );
          final exactEnvelope =
              '{"type":"chat_message","version":"2",'
              '"id":"${crossingMessage.id}","senderPeerId":"my-peer-id",'
              '"encrypted":{"kem":"kem-${crossing.name}",'
              '"ciphertext":"cipher-${crossing.name}",'
              '"nonce":"nonce-${crossing.name}"}}';
          crossingMessageRepo.seed(<ConversationMessage>[crossingMessage]);
          crossingMediaRepo.seed(<MediaAttachment>[crossingAttachment]);
          crossingMessageRepo.seedDirectInboxCustody(
            DirectInboxCustodyOutboxEntry(
              recipientPeerId: crossingMessage.contactPeerId,
              messageId: crossingMessage.id,
              incarnationId: crossing == _FailedRetryParentCrossing.deleted
                  ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                  : 'cccccccccccccccccccccccccccccccc',
              wireEnvelope: exactEnvelope,
              retryCount: 0,
              lastAttemptAt: null,
              lastErrorCode: null,
              createdAt: '2026-08-07T12:01:00.000Z',
              updatedAt: '2026-08-07T12:01:00.000Z',
            ),
          );

          final crossingCount = await retryFailedMessages(
            messageRepo: crossingMessageRepo,
            mediaAttachmentRepo: crossingMediaRepo,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: crossingP2p,
            bridge: crossingBridge,
            uploadMediaFn: crossingUpload.call,
          );

          expect(crossingMessageRepo.crossedAfterListLoad, isTrue);
          expect(crossingCount, 1, reason: crossing.name);
          expect(crossingMessageRepo.directCustodyRows, isEmpty);
          expect(crossingP2p.ackCustodyCallCount, 1);
          expect(
            crossingP2p.lastAckCustodyPeerId,
            crossingMessage.contactPeerId,
          );
          expect(crossingP2p.lastAckCustodyEnvelope, exactEnvelope);
          expect(crossingP2p.lastAckCustodyKind, AckCustodyKind.directTextV108);
          expect(crossingUpload.callCount, 0);
          expect(crossingBridge.sendCallCount, 0);
          expect(crossingMediaRepo.getAttachmentsForMessageCallCount, 0);
          expect(crossingMediaRepo.allSavedAttachments, isEmpty);
          expect(crossingMessageRepo.ordinaryMutationCallCount, 0);
          expect(crossingP2p.storeInInboxCallCount, 0);
          expect(crossingP2p.sendMessageCallCount, 0);
          expect(crossingP2p.sendMessageWithReplyCallCount, 0);
          final parentAfter = await crossingMessageRepo.getMessage(
            crossingMessage.id,
          );
          if (crossing == _FailedRetryParentCrossing.deleted) {
            expect(parentAfter, isNull);
          } else {
            expect(parentAfter!.status, 'delivered');
          }
        }

        // The parent contact is mutable and can already have drifted before
        // the failed-list snapshot is read. Ownership and replay destination
        // still come from the immutable v108 row, never the parent recipient.
        final driftedMessageRepo = FakeMessageRepository();
        final driftedMediaRepo = FakeMediaAttachmentRepository();
        final driftedBridge = FakeBridge();
        final driftedUpload = FakeUploadMediaFn();
        final driftedP2p = _AckCustodyRetryP2PService();
        final driftedParent = _makeFailedMsg(
          id: 'msg-v108-owner-recipient-drift',
          contactPeerId: 'peer-parent-drifted',
          wireEnvelope:
              '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"stale-parent"}}',
        );
        const storedOwner = 'peer-stored-owner';
        const exactOwnedEnvelope =
            '{"type":"chat_message","version":"2",'
            '"id":"msg-v108-owner-recipient-drift",'
            '"senderPeerId":"my-peer-id",'
            '"encrypted":{"kem":"owner-kem",'
            '"ciphertext":"owner-cipher","nonce":"owner-nonce"}}';
        driftedMessageRepo.seed(<ConversationMessage>[driftedParent]);
        driftedMediaRepo.seed(<MediaAttachment>[
          _makeAttachment(
            id: 'att-v108-owner-recipient-drift',
            messageId: driftedParent.id,
            downloadStatus: 'done',
          ),
        ]);
        driftedMessageRepo.seedDirectInboxCustody(
          DirectInboxCustodyOutboxEntry(
            recipientPeerId: storedOwner,
            messageId: driftedParent.id,
            incarnationId: 'dddddddddddddddddddddddddddddddd',
            wireEnvelope: exactOwnedEnvelope,
            retryCount: 0,
            lastAttemptAt: null,
            lastErrorCode: null,
            createdAt: '2026-08-07T12:02:00.000Z',
            updatedAt: '2026-08-07T12:02:00.000Z',
          ),
        );

        final driftedCount = await retryFailedMessages(
          messageRepo: driftedMessageRepo,
          mediaAttachmentRepo: driftedMediaRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: driftedP2p,
          bridge: driftedBridge,
          uploadMediaFn: driftedUpload.call,
        );

        expect(driftedCount, 1);
        expect(driftedP2p.ackCustodyCallCount, 1);
        expect(driftedP2p.lastAckCustodyPeerId, storedOwner);
        expect(driftedP2p.lastAckCustodyEnvelope, exactOwnedEnvelope);
        expect(driftedP2p.lastAckCustodyKind, AckCustodyKind.directTextV108);
        expect(driftedMessageRepo.directCustodyRows, isEmpty);
        expect(driftedUpload.callCount, 0);
        expect(driftedMediaRepo.getAttachmentsForMessageCallCount, 0);
        expect(driftedMediaRepo.allSavedAttachments, isEmpty);
        expect(driftedBridge.commandLog, isNot(contains('message.encrypt')));
        expect(driftedBridge.sendCallCount, 0);
        expect(driftedP2p.storeInInboxCallCount, 0);
        expect(driftedP2p.sendMessageCallCount, 0);
        expect(driftedP2p.sendMessageWithReplyCallCount, 0);
        expect(driftedMessageRepo.ordinaryMutationCallCount, 0);

        const partialMessageId = 'msg-partial-media-retry';
        const persistedId = 'att-partial-present';
        const missingId = 'att-partial-missing';
        final partial = _makeFailedMsg(id: partialMessageId).copyWith(
          directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
            messageId: partialMessageId,
            attachmentIds: const <String>[persistedId, missingId],
          ),
        );
        messageRepo.seed(<ConversationMessage>[partial]);
        mediaAttachmentRepo.seed(<MediaAttachment>[
          _makeAttachment(
            id: persistedId,
            messageId: partialMessageId,
            downloadStatus: 'done',
          ),
        ]);

        final partialCount = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          retryDirectInboxCustody: false,
        );

        expect(partialCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.storeInInboxCallCount, 0);
        expect(
          (await messageRepo.getMessage(
            partialMessageId,
          ))?.directMediaCustodyIntentId,
          partial.directMediaCustodyIntentId,
        );
      },
    );

    test(
      'TC-345-07d failed retry cannot normalize malformed token preparation through generic save',
      () async {
        const messageId = 'msg-345-07d-malformed-preparation';
        const attachmentId = 'att-345-07d-malformed-preparation';
        final tempDir = Directory.systemTemp.createTempSync(
          'direct_media_custody_retry_malformed_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final source = File('${tempDir.path}/voice.m4a');
        await source.writeAsBytes(<int>[0x01, 0x02, 0x03]);
        final malformedPending = _makeAttachment(
          id: attachmentId,
          messageId: messageId,
          localPath: source.path,
          downloadStatus: 'upload_pending',
          mime: 'audio/mp4',
          mediaType: 'audio',
          durationMs: 3000,
        );
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final prepared = _makeFailedMsg(
          id: messageId,
          text: '',
        ).copyWith(directMediaCustodyIntentId: intent);
        messageRepo.seed(<ConversationMessage>[prepared]);
        mediaAttachmentRepo.seed(<MediaAttachment>[malformedPending]);
        fakeUploadFn.willReturn(
          malformedPending.copyWith(
            localPath: 'media/peer-target/$attachmentId.m4a',
            downloadStatus: 'done',
          ),
        );
        var combinedStageCalls = 0;
        mediaAttachmentRepo.onStageOutgoingDirectMediaInboxCustody =
            ({
              required expected,
              required staged,
              required attachments,
              required kind,
              required recipientPeerId,
              required wireEnvelope,
            }) async {
              combinedStageCalls++;
              throw StateError('malformed preparation reached custody');
            };
        final parentBefore = (await messageRepo.getMessage(messageId))!.toMap();
        final attachmentBefore = (await mediaAttachmentRepo.getAttachmentById(
          attachmentId,
        ))!.toMap();

        final count = await retryManual(messageId);

        expect(count, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(mediaAttachmentRepo.allSavedAttachments, isEmpty);
        expect(combinedStageCalls, 0);
        expect(bridge.commandLog, isNot(contains('message.encrypt')));
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(
          (await messageRepo.getMessage(messageId))?.toMap(),
          parentBefore,
        );
        expect(
          (await mediaAttachmentRepo.getAttachmentById(attachmentId))?.toMap(),
          attachmentBefore,
        );
      },
    );

    test(
      'TC-347-03b strict failed retry reopens exact generation without legacy fallback',
      () async {
        const messageId = 'msg-347-strict-failed-retry';
        const attachmentId = 'att-347-strict-failed-retry';
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final parent = _makeFailedMsg(
          id: messageId,
        ).copyWith(directMediaCustodyIntentId: intent);
        final root = Directory.systemTemp.createTempSync(
          'retry_failed_347_strict_',
        );
        addTearDown(() {
          if (root.existsSync()) root.deleteSync(recursive: true);
        });
        final ciphertextSource = File('${root.path}/accepted.enc')
          ..writeAsBytesSync(const <int>[9, 2, 6, 5, 3, 5, 8, 9]);
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => root,
        );
        final expectedCiphertextHash = sha256
            .convert(ciphertextSource.readAsBytesSync())
            .toString();
        final durable = await store.persistCandidate(
          identityPeerId: 'my-peer-id',
          attachmentId: attachmentId,
          encryptedSourcePath: ciphertextSource.path,
          expectedContentHash: expectedCiphertextHash,
        );
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          localPath: MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'upload_pending',
          createdAt: parent.createdAt,
          contentHash: durable.contentHash,
          encryptionKeyBase64: 'original-durable-key',
          encryptionNonce: 'original-durable-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
        );
        final row = DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          inboxCustodyIncarnationId: null,
          recipientPeerId: parent.contactPeerId,
          ciphertextRelativePath: durable.relativePath,
          contentHash: durable.contentHash,
          ciphertextSize: durable.ciphertextSize,
          expiresAtMs: null,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: '2026-08-08T12:00:00.000Z',
          updatedAt: '2026-08-08T12:00:00.000Z',
        );
        final strictRepository = _ExistingDirectMediaBlobRetryRepository(row)
          ..seed(<MediaAttachment>[attachment]);
        final strictBridge = FakeBridge(
          initialResponses: const <String, Map<String, dynamic>>{
            'media:upload': <String, dynamic>{
              'ok': false,
              'errorCode': 'MEDIA_ERROR',
              'errorMessage': 'connection reset after request body',
            },
          },
        );
        messageRepo.seed(<ConversationMessage>[parent]);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: strictRepository,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: strictBridge,
          uploadMediaFn: fakeUploadFn.call,
          directMediaBlobArtifactStore: store,
          retryDirectInboxCustody: false,
        );

        expect(count, 0);
        expect(
          strictRepository.stageCalls,
          1,
          reason: 'retry must revalidate, not mint, the existing generation',
        );
        expect(strictRepository.transitionCalls, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(strictBridge.commandLog, <String>['media:upload']);
        final request =
            jsonDecode(strictBridge.sentMessages.single)
                as Map<String, dynamic>;
        final payload = request['payload'] as Map<String, dynamic>;
        expect(payload['id'], attachmentId);
        expect(payload['to'], parent.contactPeerId);
        expect(payload['mime'], 'application/octet-stream');
        expect(payload['custodyKind'], 'direct_media_blob_v1');
        expect(payload['custodyContract'], 'ack_or_expiry_v1');
        expect(payload['contentHash'], durable.contentHash);
        expect(
          File(payload['filePath'] as String).readAsBytesSync(),
          const <int>[9, 2, 6, 5, 3, 5, 8, 9],
        );
        expect(await File(durable.absolutePath).exists(), isTrue);
        expect(
          strictRepository.row.state,
          DirectMediaBlobCustodyState.outgoingPrepared,
        );
      },
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    test(
      'TC-358-02c failed disappearing strict retry reopens exact generation',
      () async {
        for (final durationSeconds in <int>[3600, 604800]) {
          messageRepo = FakeMessageRepository();
          mediaAttachmentRepo = FakeMediaAttachmentRepository();
          fakeUploadFn = FakeUploadMediaFn();
          final messageId = 'msg-358-02c-$durationSeconds';
          final attachmentId = 'att-358-02c-$durationSeconds';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          // Exactly the token-bearing disappearing shape Plan 358 authors:
          // no caption, one v110 token, and no sender-side receiver clock.
          final parent = _makeFailedMsg(id: messageId, text: '').copyWith(
            directMediaCustodyIntentId: intent,
            privateMediaPolicy: PrivateMediaPolicy.disappearing(
              durationSeconds,
            ),
            privateMediaState: PrivateMediaLifecycleState.available,
          );
          final root = Directory.systemTemp.createTempSync(
            'retry_failed_358_strict_${durationSeconds}_',
          );
          addTearDown(() {
            if (root.existsSync()) root.deleteSync(recursive: true);
          });
          final ciphertextSource = File('${root.path}/accepted.enc')
            ..writeAsBytesSync(const <int>[3, 5, 8, 9, 1, 4, 1, 5]);
          final store = DirectMediaBlobArtifactStore(
            documentsDirectoryProvider: () async => root,
          );
          final expectedCiphertextHash = sha256
              .convert(ciphertextSource.readAsBytesSync())
              .toString();
          final durable = await store.persistCandidate(
            identityPeerId: 'my-peer-id',
            attachmentId: attachmentId,
            encryptedSourcePath: ciphertextSource.path,
            expectedContentHash: expectedCiphertextHash,
          );
          final attachment = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 1024,
            mediaType: 'image',
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            ),
            downloadStatus: 'upload_pending',
            createdAt: parent.createdAt,
            contentHash: durable.contentHash,
            encryptionKeyBase64: 'disappearing-durable-key',
            encryptionNonce: 'disappearing-durable-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: MediaOwnerLane.direct,
          );
          final row = DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: parent.contactPeerId,
            ciphertextRelativePath: durable.relativePath,
            contentHash: durable.contentHash,
            ciphertextSize: durable.ciphertextSize,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: '2026-08-11T09:00:00.000Z',
            updatedAt: '2026-08-11T09:00:00.000Z',
          );
          final strictRepository = _ExistingDirectMediaBlobRetryRepository(row)
            ..seed(<MediaAttachment>[attachment]);
          final strictBridge = FakeBridge(
            initialResponses: const <String, Map<String, dynamic>>{
              'media:upload': <String, dynamic>{
                'ok': false,
                'errorCode': 'MEDIA_ERROR',
                'errorMessage': 'connection reset after request body',
              },
            },
          );
          messageRepo.seed(<ConversationMessage>[parent]);

          final count = await retryFailedMessages(
            messageRepo: messageRepo,
            mediaAttachmentRepo: strictRepository,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            bridge: strictBridge,
            uploadMediaFn: fakeUploadFn.call,
            directMediaBlobArtifactStore: store,
            retryDirectInboxCustody: false,
          );

          expect(count, 0, reason: '$durationSeconds');
          expect(
            strictRepository.stageCalls,
            1,
            reason:
                'a disappearing retry revalidates, never mints, the existing '
                'generation ($durationSeconds)',
          );
          expect(strictRepository.transitionCalls, 0);
          // Zero legacy upload and zero re-encryption: the byte-identical
          // ciphertext is reopened through the ordinary strict coordinator.
          expect(fakeUploadFn.callCount, 0, reason: '$durationSeconds');
          expect(strictBridge.commandLog, <String>['media:upload']);
          final request =
              jsonDecode(strictBridge.sentMessages.single)
                  as Map<String, dynamic>;
          final payload = request['payload'] as Map<String, dynamic>;
          expect(payload['id'], attachmentId);
          expect(payload['to'], parent.contactPeerId);
          expect(payload['custodyKind'], 'direct_media_blob_v1');
          expect(payload['custodyContract'], 'ack_or_expiry_v1');
          expect(payload['contentHash'], durable.contentHash);
          expect(
            File(payload['filePath'] as String).readAsBytesSync(),
            const <int>[3, 5, 8, 9, 1, 4, 1, 5],
          );
          expect(await File(durable.absolutePath).exists(), isTrue);
          expect(
            strictRepository.row.state,
            DirectMediaBlobCustodyState.outgoingPrepared,
          );
          final retained = (await messageRepo.getMessage(messageId))!;
          expect(retained.privateMediaMode, PrivateMediaMode.disappearing);
          expect(retained.privateMediaDurationSeconds, durationSeconds);
          expect(retained.privateMediaExpiresAtMs, isNull);
          expect(retained.privateMediaClockHighWaterMs, isNull);
        }
      },
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    test(
      'TC-345-07g token-bearing failed reupload failure uses only exact manifest authority',
      () async {
        const scenarios = <String>[
          'unsupported',
          'refused',
          'applied',
          'metadata',
          'partial',
          'token',
          'global-v108',
        ];

        for (final scenario in scenarios) {
          messageRepo = FakeMessageRepository();
          mediaAttachmentRepo = FakeMediaAttachmentRepository();
          fakeUploadFn = FakeUploadMediaFn();
          uploadTracker = MediaUploadInFlightTracker();
          manualRearmRepo = _FakeDirectManualUploadRetryRearmRepository(
            messageRepo: messageRepo,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          final tempDir = Directory.systemTemp.createTempSync(
            'retry_failed_345_07g_${scenario.replaceAll('-', '_')}_',
          );
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final source = File('${tempDir.path}/source.jpg')
            ..writeAsBytesSync(const <int>[0x01, 0x02, 0x03, 0x04]);
          final manager = FakeMediaFileManager()..resolveResult = source.path;
          final messageId = 'msg-345-07g-$scenario';
          final attachmentIds = <String>[
            'att-345-07g-$scenario-a',
            'att-345-07g-$scenario-b',
          ];
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: attachmentIds,
          );
          final preparedParent = _makeFailedMsg(
            id: messageId,
          ).copyWith(directMediaCustodyIntentId: intent);
          final pendingAttachments = attachmentIds
              .map(
                (attachmentId) => MediaAttachment(
                  id: attachmentId,
                  messageId: messageId,
                  mime: 'image/jpeg',
                  size: source.lengthSync(),
                  mediaType: 'image',
                  localPath:
                      MediaFilePathConvention.relativePathForPendingUpload(
                        messageId: messageId,
                        attachmentId: attachmentId,
                        mime: 'image/jpeg',
                      ),
                  downloadStatus: 'upload_pending',
                  createdAt: preparedParent.createdAt,
                  ownerLane: MediaOwnerLane.direct,
                ),
              )
              .toList(growable: false);
          messageRepo.seed(<ConversationMessage>[preparedParent]);
          mediaAttachmentRepo.seed(pendingAttachments);

          var exactProjectionCalls = 0;
          if (scenario != 'unsupported') {
            mediaAttachmentRepo.onProjectDirectMediaCustodyUploadFailure =
                ({
                  required expectedParent,
                  required expectedAttachments,
                  required failedAttachmentId,
                  required failure,
                }) async {
                  exactProjectionCalls++;
                  expect(expectedParent.status, 'sending', reason: scenario);
                  expect(
                    expectedParent.directMediaCustodyIntentId,
                    intent,
                    reason: scenario,
                  );
                  expect(
                    expectedAttachments
                        .map((attachment) => attachment.id)
                        .toSet(),
                    attachmentIds.toSet(),
                    reason: scenario,
                  );
                  expect(
                    expectedAttachments.every(
                      (attachment) =>
                          attachment.ownerLane == MediaOwnerLane.direct &&
                          attachment.downloadStatus == 'upload_pending',
                    ),
                    isTrue,
                    reason: scenario,
                  );
                  expect(failedAttachmentId, attachmentIds.first);
                  expect(
                    failure.disposition,
                    UploadMediaDisposition.terminal,
                    reason: scenario,
                  );
                  if (scenario == 'applied') {
                    messageRepo.seed(<ConversationMessage>[
                      expectedParent.copyWith(status: 'failed'),
                    ]);
                    mediaAttachmentRepo.seed(
                      expectedAttachments
                          .map(
                            (attachment) => attachment.id == failedAttachmentId
                                ? attachment.copyWith(
                                    downloadStatus: 'upload_failed',
                                  )
                                : attachment,
                          )
                          .toList(growable: false),
                    );
                    return const UploadRetryProjectionResult(
                      state: UploadRetryProjectionState.terminal,
                      uploadRetryCount: 0,
                    );
                  }
                  return const UploadRetryProjectionResult.notApplied();
                };
          }

          fakeUploadFn.beforeReturn = switch (scenario) {
            'metadata' => () => messageRepo.seed(<ConversationMessage>[
              preparedParent.copyWith(
                status: 'sending',
                text: 'crossed after upload started',
              ),
            ]),
            'partial' => () => mediaAttachmentRepo.seed(<MediaAttachment>[
              pendingAttachments.first,
            ]),
            'token' => () => messageRepo.seed(<ConversationMessage>[
              preparedParent.copyWith(
                status: 'sending',
                directMediaCustodyIntentId: 'ffffffffffffffffffffffffffffffff',
              ),
            ]),
            _ => null,
          };
          fakeUploadFn.willReturn(null);
          final legacyProjection = _RecordingLegacyUploadFailureProjection();

          final count = await retryManual(
            messageId,
            manager: manager,
            uploadRetryProjectionRepo: legacyProjection,
          );

          final mutationCrossed = const <String>{
            'metadata',
            'partial',
            'token',
          }.contains(scenario);
          expect(count, 0, reason: scenario);
          expect(fakeUploadFn.callCount, 1, reason: scenario);
          expect(manualRearmRepo.callCount, 1, reason: scenario);
          expect(uploadTracker.inFlightCount, 0, reason: scenario);
          expect(
            exactProjectionCalls,
            scenario == 'unsupported' || mutationCrossed ? 0 : 1,
            reason: scenario,
          );
          expect(legacyProjection.callCount, 0, reason: scenario);
          expect(mediaAttachmentRepo.allSavedAttachments, isEmpty);

          final parentAfter = await messageRepo.getMessage(messageId);
          final attachmentsAfter = await mediaAttachmentRepo
              .getAttachmentsForMessage(
                messageId,
                owner: MediaOwnerLane.direct,
              );
          expect(
            parentAfter?.status,
            scenario == 'applied' ? 'failed' : 'sending',
            reason: scenario,
          );
          expect(
            parentAfter?.directMediaCustodyIntentId,
            scenario == 'token' ? 'ffffffffffffffffffffffffffffffff' : intent,
            reason: scenario,
          );
          expect(
            attachmentsAfter,
            hasLength(scenario == 'partial' ? 1 : 2),
            reason: scenario,
          );
          expect(
            attachmentsAfter
                .where(
                  (attachment) => attachment.downloadStatus == 'upload_failed',
                )
                .length,
            scenario == 'applied' ? 1 : 0,
            reason: scenario,
          );
          if (scenario == 'metadata') {
            expect(parentAfter?.text, 'crossed after upload started');
          }
        }
      },
    );

    test(
      'TC-345-07h token-bearing at-ceiling manual retry rearms before strict validation',
      () async {
        const messageId = 'msg-345-07h-terminal-rearm';
        const attachmentId = 'att-345-07h-terminal-rearm';
        final tempDir = Directory.systemTemp.createTempSync(
          'retry_failed_345_07h_terminal_rearm_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final source = File('${tempDir.path}/source.jpg')
          ..writeAsBytesSync(const <int>[0x01, 0x02, 0x03, 0x04]);
        final manager = FakeMediaFileManager()..resolveResult = source.path;
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final preparedParent = _makeFailedMsg(
          id: messageId,
        ).copyWith(directMediaCustodyIntentId: intent);
        final terminalPreparedAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: source.lengthSync(),
          mediaType: 'image',
          localPath: MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: attachmentId,
            mime: 'image/jpeg',
          ),
          downloadStatus: 'upload_failed',
          createdAt: preparedParent.createdAt,
          uploadRetryCount: kMaxUploadRetries,
          ownerLane: MediaOwnerLane.direct,
        );
        messageRepo.seed(<ConversationMessage>[preparedParent]);
        mediaAttachmentRepo.seed(<MediaAttachment>[terminalPreparedAttachment]);
        fakeUploadFn.willReturn(null);

        var exactFailureProjectionCalls = 0;
        mediaAttachmentRepo.onProjectDirectMediaCustodyUploadFailure =
            ({
              required expectedParent,
              required expectedAttachments,
              required failedAttachmentId,
              required failure,
            }) async {
              exactFailureProjectionCalls++;
              expect(expectedParent.status, 'sending');
              expect(expectedParent.directMediaCustodyIntentId, intent);
              expect(expectedAttachments, hasLength(1));
              expect(
                expectedAttachments.single.downloadStatus,
                'upload_pending',
              );
              expect(expectedAttachments.single.uploadRetryCount, 0);
              expect(failedAttachmentId, attachmentId);
              expect(failure.disposition, UploadMediaDisposition.terminal);
              return const UploadRetryProjectionResult.notApplied();
            };

        final automaticCount = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: manager,
        );

        expect(automaticCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(exactFailureProjectionCalls, 0);

        final count = await retryManual(messageId, manager: manager);

        expect(count, 0);
        expect(manualRearmRepo.callCount, 1);
        expect(
          manualRearmRepo.lastExpectations!.single.downloadStatus,
          'upload_failed',
        );
        expect(
          manualRearmRepo.lastExpectations!.single.uploadRetryCount,
          kMaxUploadRetries,
        );
        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastBlobId, attachmentId);
        expect(exactFailureProjectionCalls, 1);
        expect(uploadTracker.inFlightCount, 0);
      },
    );

    test(
      'manual Retry rearms an at-ceiling upload and sends on success',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);

        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/img.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        mediaAttachmentRepo.seed([attachment]);

        // Create a temp file so existsSync() returns true
        final tmpFile = File('/tmp/img.jpg');
        if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

        fakeUploadFn.willReturn(
          attachment.copyWith(id: 'new-blob-id', downloadStatus: 'done'),
        );

        final count = await retryManual(msg.id);

        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastLocalPath, '/tmp/img.jpg');
        expect(fakeUploadFn.lastBlobId, attachment.id);
        expect(manualRearmRepo.callCount, 1);
        expect(
          manualRearmRepo.lastExpectations!.single.uploadRetryCount,
          kMaxUploadRetries,
        );
        expect(uploadTracker.inFlightCount, 0);
        expect(count, 1);
      },
    );

    // F.5.2 File deleted between crash and retry -> left as 'failed'
    test('skips message when local file is missing from disk', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: '/data/media/deleted.jpg',
          downloadStatus: 'failed',
        ),
      ]);
      // File intentionally absent

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.callCount, 0);
      expect(count, 0);
    });

    test('manual Retry releases ownership when re-upload fails', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/img.jpg',
          downloadStatus: 'upload_pending',
        ),
      ]);

      // Ensure file exists for the upload attempt
      final tmpFile = File('/tmp/img.jpg');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(null);
      final legacyProjection = _RecordingLegacyUploadFailureProjection();

      final count = await retryManual(
        msg.id,
        uploadRetryProjectionRepo: legacyProjection,
      );

      expect(fakeUploadFn.callCount, 1);
      expect(manualRearmRepo.callCount, 1);
      expect(uploadTracker.inFlightCount, 0);
      expect(legacyProjection.callCount, 1);
      expect(legacyProjection.lastMessageId, msg.id);
      expect(legacyProjection.lastAttachmentId, 'att-001');
      expect(
        legacyProjection.lastFailure?.disposition,
        UploadMediaDisposition.terminal,
      );
      expect(count, 0);
    });

    test('manual Retry uploads audio with its persisted metadata', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);

      final audioAttachment = _makeAttachment(
        messageId: msg.id,
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'upload_pending',
        mime: 'audio/mp4',
        mediaType: 'audio',
        durationMs: 3000,
      );
      mediaAttachmentRepo.seed([audioAttachment]);

      // Ensure file exists
      final tmpFile = File('/tmp/voice.m4a');
      if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

      fakeUploadFn.willReturn(
        audioAttachment.copyWith(id: 'audio-blob-id', downloadStatus: 'done'),
      );

      final count = await retryManual(msg.id);

      expect(fakeUploadFn.lastMime, 'audio/mp4');
      expect(fakeUploadFn.lastDurationMs, 3000);
      expect(manualRearmRepo.callCount, 1);
      expect(count, 1);
    });

    test(
      'automatic bulk retries done media but never claims or uploads unfinished rows',
      () async {
        final msgPending = _makeFailedMsg(id: 'msg-pending-001');
        final msgTerminal = _makeFailedMsg(id: 'msg-terminal-002');
        final msgCancelled = _makeFailedMsg(id: 'msg-cancelled-003');
        final msgDone = _makeFailedMsg(id: 'msg-done-004');
        messageRepo.seed([msgPending, msgTerminal, msgCancelled, msgDone]);

        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-pending-001',
            messageId: msgPending.id,
            localPath: '/tmp/pending.jpg',
            downloadStatus: 'upload_pending',
          ),
          _makeAttachment(
            id: 'att-terminal-002',
            messageId: msgTerminal.id,
            localPath: '/tmp/terminal.jpg',
            downloadStatus: 'upload_failed',
            uploadRetryCount: kMaxUploadRetries,
          ),
          _makeAttachment(
            id: 'att-cancelled-003',
            messageId: msgCancelled.id,
            localPath: '/tmp/cancelled.jpg',
            downloadStatus: 'upload_cancelled',
          ),
          _makeAttachment(
            id: 'att-done-004',
            messageId: msgDone.id,
            localPath: 'media/peer-target/att-done-004.jpg',
            downloadStatus: 'done',
          ),
        ]);

        fakeUploadFn.willReturn(
          _makeAttachment(
            id: 'must-not-upload',
            messageId: msgPending.id,
            downloadStatus: 'done',
          ),
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(uploadTracker.inFlightCount, 0);
        expect((await messageRepo.getMessage(msgPending.id))?.status, 'failed');
        expect(
          (await messageRepo.getMessage(msgTerminal.id))?.status,
          'failed',
        );
        expect(
          (await messageRepo.getMessage(msgCancelled.id))?.status,
          'failed',
        );
      },
    );

    // F.5.6 Attachment with null localPath -> treated as missing
    test('skips attachment with null localPath', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([
        _makeAttachment(
          messageId: msg.id,
          localPath: null,
          downloadStatus: 'failed',
        ),
      ]);

      final count = await retryFailedMessages(
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        p2pService: p2pService,
        bridge: bridge,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(fakeUploadFn.callCount, 0);
      expect(count, 0);
    });

    // F.5.7 Attachment already uploaded (Part C path): uploadMediaFn NOT called
    test(
      'does NOT re-upload when attachment is already done (Part C path)',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            messageId: msg.id,
            localPath: '/tmp/img.jpg',
            downloadStatus: 'done',
            id: 'existing-blob-id',
          ),
        ]);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(fakeUploadFn.callCount, 0); // Part C path -- no new upload
        expect(count, 1);
      },
    );

    test(
      'cached-envelope inbox success cleans settled media staging',
      () async {
        final msg = _makeFailedMsg(
          id: 'msg-envelope-cleanup',
          wireEnvelope: '{"type":"chat","version":"2","payload":{}}',
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-envelope-cleanup',
            messageId: msg.id,
            localPath: 'media/peer-target/att-envelope-cleanup.jpg',
            downloadStatus: 'done',
          ),
        ]);
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        expect(deletedDirs, [msg.id]);
        expect((await messageRepo.getMessage(msg.id))?.status, 'inboxed');
      },
    );

    test(
      'already-inbox cached-envelope success also cleans media staging',
      () async {
        final msg = _makeFailedMsg(
          id: 'msg-already-inbox-cleanup',
          wireEnvelope: '{"type":"chat","version":"2","payload":{}}',
        ).copyWith(transport: 'inbox');
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            id: 'att-already-inbox-cleanup',
            messageId: msg.id,
            localPath: 'media/peer-target/att-already-inbox-cleanup.jpg',
            downloadStatus: 'done',
          ),
        ]);
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(deletedDirs, [msg.id]);
        expect((await messageRepo.getMessage(msg.id))?.status, 'inboxed');
      },
    );

    test('manual Retry resolves and uploads a relative stored path', () async {
      final msg = _makeFailedMsg(wireEnvelope: null);
      messageRepo.seed([msg]);
      final attachment = _makeAttachment(
        messageId: msg.id,
        localPath: 'pending_uploads/${msg.id}/att-001.jpg',
        downloadStatus: 'upload_pending',
      );
      mediaAttachmentRepo.seed([attachment]);
      final resolvedPath = await mediaFileManager.resolveStoredPath(
        attachment.localPath!,
      );
      await File(resolvedPath).create(recursive: true);
      await File(resolvedPath).writeAsBytes([0xFF]);
      fakeUploadFn.willReturn(
        attachment.copyWith(
          localPath: 'media/peer-target/${attachment.id}.jpg',
          downloadStatus: 'done',
        ),
      );

      final count = await retryManual(msg.id, manager: mediaFileManager);

      expect(fakeUploadFn.callCount, 1);
      expect(fakeUploadFn.lastLocalPath, resolvedPath);
      expect(mediaFileManager.resolveStoredPathCount, greaterThanOrEqualTo(1));
      expect(count, 1);
    });

    // F.5.9 Voice-only retry without mediaAttachments returns invalidMessage
    test(
      'voice-only retry without mediaAttachments returns invalidMessage, not success',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null, text: '');
        messageRepo.seed([msg]);
        // No mediaAttachmentRepo rows seeded -- simulates pre-Part-G state

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0); // invalidMessage -- not a success
      },
    );

    test(
      'skips cancelled media rows without re-uploading or re-sending',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: null);
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([
          _makeAttachment(
            messageId: msg.id,
            localPath: '/tmp/cancelled.jpg',
            downloadStatus: 'upload_cancelled',
          ),
        ]);

        final tmpFile = File('/tmp/cancelled.jpg');
        if (!tmpFile.existsSync()) tmpFile.writeAsBytesSync([0xFF]);

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(fakeUploadFn.callCount, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
        expect((await messageRepo.getMessage(msg.id))?.status, 'failed');
      },
    );

    test(
      'manual Retry refuses a typed-terminal row below the ceiling',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/typed-terminal.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries - 1,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([attachment]);
        await File(attachment.localPath!).writeAsBytes([0xFF]);
        var claimCount = 0;

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentById(attachment.id))?.toMap(),
          attachment.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
        );
      },
    );

    test(
      'held competing lease leaves parent and terminal attachment byte-identical',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final attachment = _makeAttachment(
          messageId: msg.id,
          localPath: '/tmp/held-terminal.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([attachment]);
        await File(attachment.localPath!).writeAsBytes([0xFF]);
        final competitor = uploadTracker.tryClaimAll([
          attachment.id,
        ], source: MediaUploadTriggerSource.foreground);
        expect(competitor, isNotNull);
        final parentBefore = (await messageRepo.getMessage(msg.id))!.toMap();
        final attachmentBefore = (await mediaAttachmentRepo.getAttachmentById(
          attachment.id,
        ))!.toMap();

        final count = await retryManual(msg.id);

        expect(count, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), parentBefore);
        expect(
          (await mediaAttachmentRepo.getAttachmentById(attachment.id))?.toMap(),
          attachmentBefore,
        );
        expect(uploadTracker.release(competitor!), isTrue);
      },
    );

    test(
      'missing source in a multi-attachment set prevents claim and partial rearm',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final present = _makeAttachment(
          id: 'att-present',
          messageId: msg.id,
          localPath: '/tmp/present-for-all-or-none.jpg',
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        );
        final missing = _makeAttachment(
          id: 'att-missing',
          messageId: msg.id,
          localPath: '/tmp/does-not-exist-for-all-or-none.jpg',
          downloadStatus: 'upload_pending',
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed([present, missing]);
        await File(present.localPath!).writeAsBytes([0xFF]);
        final absent = File(missing.localPath!);
        if (absent.existsSync()) await absent.delete();
        var claimCount = 0;
        final before = (await mediaAttachmentRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        )).map((attachment) => attachment.toMap()).toList();

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            msg.id,
            owner: MediaOwnerLane.direct,
          )).map((attachment) => attachment.toMap()).toList(),
          before,
        );
      },
    );

    test(
      'over-limit manual set is refused before claim or terminal rearm',
      () async {
        final msg = _makeFailedMsg(wireEnvelope: 'still-valid');
        final tempDir = Directory.systemTemp.createTempSync(
          'direct_manual_retry_over_limit_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachments = <MediaAttachment>[];
        for (var i = 0; i < kReuploadMaxAttachmentsPerMessage + 1; i++) {
          final path = '${tempDir.path}/$i.jpg';
          await File(path).writeAsBytes([0xFF, i]);
          attachments.add(
            _makeAttachment(
              id: 'att-over-limit-$i',
              messageId: msg.id,
              localPath: path,
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
          );
        }
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seed(attachments);
        var claimCount = 0;
        final before = (await mediaAttachmentRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        )).map((attachment) => attachment.toMap()).toList();

        final count = await retryManual(msg.id, onClaim: (_) => claimCount++);

        expect(count, 0);
        expect(claimCount, 0);
        expect(manualRearmRepo.callCount, 0);
        expect(fakeUploadFn.callCount, 0);
        expect((await messageRepo.getMessage(msg.id))?.toMap(), msg.toMap());
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            msg.id,
            owner: MediaOwnerLane.direct,
          )).map((attachment) => attachment.toMap()).toList(),
          before,
        );
      },
    );

    test('failed parent+attachment CAS releases the manual lease', () async {
      final msg = _makeFailedMsg();
      final attachment = _makeAttachment(
        messageId: msg.id,
        localPath: '/tmp/cas-lost.jpg',
        downloadStatus: 'upload_pending',
      );
      messageRepo.seed([msg]);
      mediaAttachmentRepo.seed([attachment]);
      await File(attachment.localPath!).writeAsBytes([0xFF]);
      manualRearmRepo.willApply = false;

      final count = await retryManual(msg.id);

      expect(count, 0);
      expect(manualRearmRepo.callCount, 1);
      expect(fakeUploadFn.callCount, 0);
      expect(uploadTracker.inFlightCount, 0);
      expect((await messageRepo.getMessage(msg.id))?.status, 'failed');
      expect(
        (await mediaAttachmentRepo.getAttachmentById(
          attachment.id,
        ))?.downloadStatus,
        'upload_pending',
      );
    });
  });
}
