import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show DirectMediaFanoutTargetBinding;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_direct_media_custody_stage_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/direct_reaction_custody_p2p_service.dart';
import 'helpers/fake_upload_media_fn.dart';

Future<void> _waitUntilAsync(
  Future<bool> Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for asynchronous retry state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

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

const _testContentHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

MediaAttachment _pendingAtt({
  String id = 'att-00001',
  String messageId = 'msg-00001',
  String localPath = '/tmp/recording.m4a',
  String mime = 'audio/mpeg',
  int? durationMs = 3000,
  String mediaType = 'audio',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: mediaType,
    localPath: localPath,
    durationMs: durationMs,
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

ConversationMessage _makeMsg(
  String id, {
  required String status,
  String contactPeerId = 'peer-bob-001',
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice-001',
    text: 'test-text',
    timestamp: now,
    status: status,
    isIncoming: false,
    createdAt: now,
  );
}

MediaAttachment _doneAttachment(
  String id,
  String messageId, {
  String mime = 'audio/mpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: '/tmp/recording.m4a',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    contentHash: _testContentHash,
    encryptionKeyBase64: 'test-blob-key-base64',
    encryptionNonce: 'test-blob-nonce',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
  );
}

ContactModel _contactWithMlKem(String peerId) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Contact-$peerId',
    signature: 'sig-$peerId',
    scannedAt: now,
    mlKemPublicKey: 'mlkem-$peerId',
  );
}

class _RecordingDirectUploadRetryProjection
    implements DirectUploadRetryProjectionRepository {
  int callCount = 0;
  String? messageId;
  String? attachmentId;
  UploadMediaFailed? failure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    callCount++;
    this.messageId = messageId;
    this.attachmentId = attachmentId;
    this.failure = failure;
    return const UploadRetryProjectionResult(
      state: UploadRetryProjectionState.terminal,
    );
  }
}

class _AbsentDirectMediaBlobRepository extends FakeMediaAttachmentRepository
    implements DirectMediaBlobCustodyRepository {
  int blobLoads = 0;
  int blobStages = 0;

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
    blobStages++;
    return const DirectMediaBlobGenerationStageResult.refused();
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async =>
      const <DirectMediaBlobCustodyRow>[];

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async =>
      null;

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async => null;

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async {
    blobLoads++;
    return const <DirectMediaBlobCustodyRow>[];
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
  }) async => false;

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;
}

/// Plan 358 token-bearing strict reopen fake.
///
/// Publishes one durable `outgoing_prepared` v111 row for the seeded parent's
/// attachment and records every ORDINARY-strict stage/private-stage call, so a
/// disappearing retry can be proved to reopen the exact existing generation
/// through the ordinary coordinator and never through the private one.
class _ExistingDirectMediaBlobRepository extends FakeMediaAttachmentRepository
    implements
        DirectMediaBlobCustodyRepository,
        OutgoingDirectPrivateMediaBlobGenerationRepository {
  _ExistingDirectMediaBlobRepository(this.row);

  DirectMediaBlobCustodyRow row;
  int blobLoads = 0;
  int ordinaryStageCalls = 0;
  int privateStageCalls = 0;
  int transitionCalls = 0;

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  bool get supportsOutgoingDirectPrivateMediaBlobGeneration => true;

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
    ordinaryStageCalls++;
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.idempotent,
      attachments: preparedAttachments,
      custodyRows: <DirectMediaBlobCustodyRow>[row],
    );
  }

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectPrivateMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required MediaAttachment expectedAttachment,
    required MediaAttachment preparedAttachment,
    required DirectMediaBlobCustodyRow custodyRow,
  }) async {
    privateStageCalls++;
    return const DirectMediaBlobGenerationStageResult.refused();
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
  ) async {
    blobLoads++;
    return messageId == row.messageId
        ? <DirectMediaBlobCustodyRow>[row]
        : const <DirectMediaBlobCustodyRow>[];
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
    transitionCalls++;
    if (!expected.exactDatabaseProjectionMatches(row)) return false;
    row = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;
}

/// Plan 362 linked-fanout blob repository fake.
///
/// Publishes a PLURAL linked (fanout) v114 row set and records every
/// consultation — lifecycle-lease runs, per-message loads, singular reopen
/// stages, plural stages, roster snapshot reads — so a retry can be proved to
/// route ONLY through the shared fanout owner (or fail closed) without a
/// roster resolution, a re-encryption, or a singular reopen.
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
    return null;
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
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectMediaFanoutTargetBinding> targetBindings,
  }) async {
    fanoutInboxStageCalls++;
    return const DirectMediaFanoutInboxCustodyStageResult.refused();
  }
}

/// Plan 354 private strict reopen fake.
///
/// Publishes one durable `outgoing_prepared` v111 row for the seeded parent and
/// records every stage/reopen call so the test can prove the retry adopted the
/// exact generation rather than minting or re-encrypting one.
class _PrivateStrictBlobRepository extends FakeMediaAttachmentRepository
    implements
        DirectMediaBlobCustodyRepository,
        OutgoingDirectPrivateMediaBlobGenerationRepository,
        OutgoingDirectPrivateMutationRepository,
        DirectPrivateMediaCleanupRuntime {
  _PrivateStrictBlobRepository(this.row);

  DirectMediaBlobCustodyRow row;
  int privateStageCalls = 0;
  int completionCalls = 0;
  final List<MediaAttachment> completedAttachments = <MediaAttachment>[];
  final MediaAttachmentLifecycleLock _lock = MediaAttachmentLifecycleLock();
  late final OutgoingDirectPrivateMutationCoordinator _coordinator =
      OutgoingDirectPrivateMutationCoordinator(
        lifecycleLock: _lock,
        classifyCompletion: (attachment, fingerprint) async =>
            OutgoingDirectPrivateCompletionQualification.availablePending,
        commitAvailable: (attachment, fingerprint) async {
          completionCalls++;
          completedAttachments.add(attachment);
          return true;
        },
        commitRollback: (attachment, fingerprint, {required mode}) async =>
            true,
      );

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock => _lock;

  @override
  OutgoingDirectPrivateMutationCoordinator
  get outgoingDirectPrivateMutationCoordinator => _coordinator;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  applyOutgoingDirectPrivateNonCompletionMutation(
    MediaAttachment attachment,
  ) async => OutgoingDirectPrivateNonCompletionMutationOutcome.applied;

  @override
  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  prepareOutgoingDirectPrivatePendingAttachments(
    List<MediaAttachment> attachments,
  ) async => OutgoingDirectPrivatePendingPreparationOutcome.inserted;

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
    String messageId, {
    required MediaFileManager mediaFileManager,
  }) async => OutgoingDirectPrivateNonCompletionMutationOutcome.applied;

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  bool get supportsOutgoingDirectPrivateMediaBlobGeneration => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => _lock.synchronizedAll(action);

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectPrivateMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required MediaAttachment expectedAttachment,
    required MediaAttachment preparedAttachment,
    required DirectMediaBlobCustodyRow custodyRow,
  }) async {
    privateStageCalls++;
    // A reopen can only ever be idempotent: the generation already exists.
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.idempotent,
      attachments: <MediaAttachment>[preparedAttachment],
      custodyRows: <DirectMediaBlobCustodyRow>[row],
    );
  }

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async => const DirectMediaBlobGenerationStageResult.refused();

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
    if (!row.exactDatabaseProjectionMatches(expected)) return false;
    row = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;
}

void main() {
  late FakeMediaAttachmentRepository mediaRepo;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeUploadMediaFn fakeUploadFn;

  setUp(() {
    mediaRepo = FakeMediaAttachmentRepository();
    messageRepo = FakeMessageRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-alice',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
      storeInInboxResult: true,
    );
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRepo.seed([
      _contactWithMlKem('peer-bob'),
      _contactWithMlKem('peer-bob-001'),
    ]);
    fakeUploadFn = FakeUploadMediaFn();
  });

  group('retryIncompleteUploads', () {
    test(
      'TC-345-07 fresh-media restart and global v108 ownership survive recipient drift',
      () async {
        const messageId = 'msg-345-resumed-upload';
        const attachmentId = 'att-345-resumed-upload';
        final source = File(
          '${Directory.systemTemp.path}/$attachmentId-${DateTime.now().microsecondsSinceEpoch}.m4a',
        );
        await source.writeAsBytes(<int>[1, 2, 3, 4]);
        addTearDown(() async {
          if (await source.exists()) await source.delete();
        });
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final pendingPath =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'audio/mpeg',
            );
        final fileManager = FakeMediaFileManager()..resolveResult = source.path;
        final prepared = ConversationMessage(
          id: messageId,
          contactPeerId: 'peer-bob-001',
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: '2026-08-07T12:00:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T12:00:00.000Z',
          directMediaCustodyIntentId: intent,
        );
        final pending = _pendingAtt(
          id: attachmentId,
          messageId: messageId,
          localPath: pendingPath,
        );
        messageRepo.seed(<ConversationMessage>[prepared]);
        mediaRepo.seed(<MediaAttachment>[pending]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(
          _doneAttachment(
            attachmentId,
            messageId,
          ).copyWith(durationMs: pending.durationMs),
        );
        var combinedStageCalls = 0;
        mediaRepo.onStageOutgoingDirectMediaInboxCustody =
            ({
              required expected,
              required staged,
              required attachments,
              required kind,
              required recipientPeerId,
              required wireEnvelope,
            }) async {
              combinedStageCalls++;
              expect(kind, OutgoingOrdinaryAttemptKind.existing);
              expect(expected?.directMediaCustodyIntentId, intent);
              expect(attachments.map((attachment) => attachment.id), <String>[
                attachmentId,
              ]);
              expect(
                attachments.every(
                  (attachment) => attachment.downloadStatus == 'done',
                ),
                isTrue,
              );
              final committed = staged.copyWith(
                directMediaCustodyIntentId: null,
                media: attachments,
              );
              await messageRepo.saveMessage(committed);
              mediaRepo.seed(attachments);
              final custody = DirectInboxCustodyOutboxEntry(
                recipientPeerId: recipientPeerId,
                messageId: staged.id,
                incarnationId: intent,
                wireEnvelope: wireEnvelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: committed.createdAt,
                updatedAt: committed.createdAt,
              );
              messageRepo.seedDirectInboxCustody(custody);
              return OutgoingDirectMediaCustodyStageResult(
                outcome: OutgoingOrdinaryMutationOutcome.applied,
                message: committed,
                custody: custody,
              );
            };
        final strictP2p = DirectReactionCustodyP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'my-peer-id'),
        );

        Future<int> runRestartedPass() => retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: strictP2p,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: fileManager,
        );

        expect(await runRestartedPass(), 1);
        expect(fakeUploadFn.callCount, 1);
        expect(combinedStageCalls, 1);
        expect(messageRepo.directCustodyRows, isEmpty);
        expect(
          (await messageRepo.getMessage(messageId))?.directMediaCustodyIntentId,
          isNull,
        );
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          )).single.downloadStatus,
          'done',
        );

        // A process-recreated pass observes no pending work and cannot mint a
        // second incarnation or upload the same blob again.
        expect(await runRestartedPass(), 0);
        expect(fakeUploadFn.callCount, 1);
        expect(combinedStageCalls, 1);

        const partialMessageId = 'msg-345-partial-resume';
        const presentId = 'att-345-partial-present';
        const missingId = 'att-345-partial-missing';
        final partialIntent = computeDirectMediaCustodyIntentId(
          messageId: partialMessageId,
          attachmentIds: const <String>[presentId, missingId],
        );
        final partial = ConversationMessage(
          id: partialMessageId,
          contactPeerId: 'peer-bob-001',
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: '2026-08-07T12:01:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T12:01:00.000Z',
          directMediaCustodyIntentId: partialIntent,
        );
        messageRepo.seed(<ConversationMessage>[partial]);
        mediaRepo.seed(<MediaAttachment>[
          _pendingAtt(
            id: presentId,
            messageId: partialMessageId,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: partialMessageId,
              attachmentId: presentId,
              mime: 'audio/mpeg',
            ),
          ),
        ]);
        final encryptionsBeforePartial = bridge.commandLog
            .where((command) => command == 'message.encrypt')
            .length;

        expect(await runRestartedPass(), 0);
        expect(fakeUploadFn.callCount, 1);
        expect(combinedStageCalls, 1);
        expect(
          bridge.commandLog
              .where((command) => command == 'message.encrypt')
              .length,
          encryptionsBeforePartial,
        );
        expect(
          (await messageRepo.getMessage(
            partialMessageId,
          ))?.directMediaCustodyIntentId,
          partialIntent,
        );

        const ownedMessageId = 'msg-345-outbox-owned-upload';
        final owned = ConversationMessage(
          id: ownedMessageId,
          contactPeerId: 'peer-parent-drifted',
          senderPeerId: 'my-peer-id',
          text: 'owned',
          timestamp: '2026-08-07T12:02:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-08-07T12:02:00.000Z',
          wireEnvelope:
              '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"stale-parent"}}',
        );
        messageRepo.seed(<ConversationMessage>[owned]);
        mediaRepo.seed(<MediaAttachment>[
          _pendingAtt(
            id: 'att-345-outbox-owned-upload',
            messageId: ownedMessageId,
            localPath: source.path,
          ),
        ]);
        messageRepo.seedDirectInboxCustody(
          DirectInboxCustodyOutboxEntry(
            recipientPeerId: 'peer-stored-owner',
            messageId: owned.id,
            incarnationId: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"ciphertext":"owned"}}',
            retryCount: 0,
            lastAttemptAt: null,
            lastErrorCode: null,
            createdAt: owned.createdAt,
            updatedAt: owned.createdAt,
          ),
        );

        final uploadsBeforeOwnedDrift = fakeUploadFn.callCount;
        final combinedStagesBeforeOwnedDrift = combinedStageCalls;
        final ordinaryMutationsBeforeOwnedDrift =
            messageRepo.ordinaryMutationCallCount;
        final attachmentSavesBeforeOwnedDrift =
            mediaRepo.allSavedAttachments.length;
        final encryptionsBeforeOwnedDrift = bridge.commandLog
            .where((command) => command == 'message.encrypt')
            .length;
        final bridgeSendsBeforeOwnedDrift = bridge.sendCallCount;
        final genericStoresBeforeOwnedDrift = strictP2p.storeInInboxCallCount;
        final directSendsBeforeOwnedDrift = strictP2p.sendMessageCallCount;

        expect(await runRestartedPass(), 0);
        expect(fakeUploadFn.callCount, uploadsBeforeOwnedDrift);
        expect(combinedStageCalls, combinedStagesBeforeOwnedDrift);
        expect(
          messageRepo.ordinaryMutationCallCount,
          ordinaryMutationsBeforeOwnedDrift,
        );
        expect(
          mediaRepo.allSavedAttachments.length,
          attachmentSavesBeforeOwnedDrift,
        );
        expect(
          bridge.commandLog
              .where((command) => command == 'message.encrypt')
              .length,
          encryptionsBeforeOwnedDrift,
        );
        expect(bridge.sendCallCount, bridgeSendsBeforeOwnedDrift);
        expect(strictP2p.storeInInboxCallCount, genericStoresBeforeOwnedDrift);
        expect(strictP2p.sendMessageCallCount, directSendsBeforeOwnedDrift);
        expect(messageRepo.directCustodyRows, hasLength(1));
        expect(
          messageRepo.directCustodyRows.values.single.recipientPeerId,
          'peer-stored-owner',
        );
      },
    );

    test(
      'TC-345-07c token-bearing incomplete retry rejects malformed prepared identity before upload',
      () async {
        for (final variant in <String>[
          'noncanonical-path',
          'unstable-metadata',
          'preexisting-crypto',
          'malformed-completed-sibling',
          'malformed-completed-status',
        ]) {
          final localMediaRepo = FakeMediaAttachmentRepository();
          final localMessageRepo = FakeMessageRepository();
          final localBridge = FakeBridge();
          final localP2p = FakeP2PService(
            initialState: const NodeState(
              isStarted: true,
              peerId: 'my-peer-id',
            ),
          );
          final localIdentityRepo = FakeIdentityRepository()
            ..seed(FakeIdentityRepository.makeIdentity());
          final localContactRepo = FakeContactRepository()
            ..seed(<ContactModel>[_contactWithMlKem('peer-bob-001')]);
          final localUpload = FakeUploadMediaFn();
          final messageId = 'msg-345-07c-$variant';
          final pendingId = 'att-345-07c-pending-$variant';
          final doneId = 'att-345-07c-done-$variant';
          final canonicalPath =
              MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: pendingId,
                mime: 'audio/mpeg',
              );
          final exactPending = _pendingAtt(
            id: pendingId,
            messageId: messageId,
            localPath: canonicalPath,
          );
          final rows = switch (variant) {
            'noncanonical-path' => <MediaAttachment>[
              exactPending.copyWith(localPath: '/tmp/not-prepared.m4a'),
            ],
            'unstable-metadata' => <MediaAttachment>[
              exactPending.copyWith(mediaType: 'video'),
            ],
            'preexisting-crypto' => <MediaAttachment>[
              exactPending.copyWith(
                contentHash: _testContentHash,
                encryptionKeyBase64: 'premature-key',
                encryptionNonce: 'premature-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
            ],
            'malformed-completed-status' => <MediaAttachment>[
              exactPending,
              _doneAttachment(
                doneId,
                messageId,
              ).copyWith(downloadStatus: 'upload_failed'),
            ],
            _ => <MediaAttachment>[
              exactPending,
              _doneAttachment(
                doneId,
                messageId,
              ).copyWith(clearContentHash: true),
            ],
          };
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: rows.map((attachment) => attachment.id),
          );
          final prepared = ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-bob-001',
            senderPeerId: 'my-peer-id',
            text: '',
            timestamp: '2026-08-07T12:03:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-07T12:03:00.000Z',
            directMediaCustodyIntentId: intent,
          );
          localMessageRepo.seed(<ConversationMessage>[prepared]);
          localMediaRepo.seed(rows);
          localUpload.willReturn(_doneAttachment(pendingId, messageId));
          var combinedStageCalls = 0;
          localMediaRepo.onStageOutgoingDirectMediaInboxCustody =
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

          final count = await retryIncompleteUploads(
            mediaAttachmentRepo: localMediaRepo,
            messageRepo: localMessageRepo,
            bridge: localBridge,
            p2pService: localP2p,
            identityRepo: localIdentityRepo,
            contactRepo: localContactRepo,
            uploadMediaFn: localUpload.call,
          );

          expect(count, 0, reason: variant);
          expect(localUpload.callCount, 0, reason: variant);
          expect(combinedStageCalls, 0, reason: variant);
          expect(localMediaRepo.allSavedAttachments, isEmpty, reason: variant);
          expect(
            localBridge.commandLog,
            isNot(contains('message.encrypt')),
            reason: variant,
          );
          expect(localP2p.sendMessageCallCount, 0, reason: variant);
          expect(localP2p.storeInInboxCallCount, 0, reason: variant);
          expect(
            (await localMessageRepo.getMessage(
              messageId,
            ))?.directMediaCustodyIntentId,
            intent,
            reason: variant,
          );
        }
      },
    );

    test(
      'TC-345-07e uploaded retry completion cannot omit authored media identity',
      () {
        final prepared =
            _pendingAtt(
              id: 'att-345-07e',
              messageId: 'msg-345-07e',
              localPath: MediaFilePathConvention.relativePathForPendingUpload(
                messageId: 'msg-345-07e',
                attachmentId: 'att-345-07e',
                mime: 'audio/mpeg',
              ),
            ).copyWith(
              width: 320,
              height: 180,
              waveform: const <double>[0.2, 0.8],
              ownerLane: MediaOwnerLane.direct,
            );

        MediaAttachment uploaded({
          int? width = 320,
          int? durationMs = 3000,
          List<double>? waveform = const <double>[0.2, 0.8],
        }) => MediaAttachment(
          id: prepared.id,
          messageId: '',
          mime: prepared.mime,
          size: prepared.size,
          mediaType: prepared.mediaType,
          width: width,
          height: prepared.height,
          durationMs: durationMs,
          localPath: 'media/peer-bob-001/${prepared.id}.m4a',
          downloadStatus: 'done',
          createdAt: '2099-01-01T00:00:00.000Z',
          waveform: waveform,
          contentHash: _testContentHash,
          encryptionKeyBase64: 'key-345-07e',
          encryptionNonce: 'nonce-345-07e',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        expect(
          completeDirectMediaCustodyRetryAttachment(
            prepared: prepared,
            uploaded: uploaded(),
          ),
          isNotNull,
        );
        expect(
          completeDirectMediaCustodyRetryAttachment(
            prepared: prepared,
            uploaded: uploaded(width: null),
          ),
          isNull,
        );
        expect(
          completeDirectMediaCustodyRetryAttachment(
            prepared: prepared,
            uploaded: uploaded(durationMs: null),
          ),
          isNull,
        );
        expect(
          completeDirectMediaCustodyRetryAttachment(
            prepared: prepared,
            uploaded: uploaded(waveform: null),
          ),
          isNull,
        );
      },
    );

    test(
      'TC-345-07f token-bearing upload failure uses only exact manifest authority',
      () async {
        for (final variant in <String>['unsupported', 'refused', 'applied']) {
          final localMediaRepo = FakeMediaAttachmentRepository();
          final localMessageRepo = FakeMessageRepository();
          final localIdentityRepo = FakeIdentityRepository()
            ..seed(FakeIdentityRepository.makeIdentity());
          final localUpload = FakeUploadMediaFn();
          final legacyProjection = _RecordingDirectUploadRetryProjection();
          final messageId = 'msg-345-07f-$variant';
          final attachmentId = 'att-345-07f-$variant';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          final prepared = ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-bob-001',
            senderPeerId: 'my-peer-id',
            text: '',
            timestamp: '2026-08-07T15:10:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-07T15:10:00.000Z',
            directMediaCustodyIntentId: intent,
          );
          final pending = _pendingAtt(
            id: attachmentId,
            messageId: messageId,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'audio/mpeg',
            ),
          );
          localMessageRepo.seed(<ConversationMessage>[prepared]);
          localMediaRepo.seed(<MediaAttachment>[pending]);
          var exactProjectionCalls = 0;
          if (variant != 'unsupported') {
            localMediaRepo.onProjectDirectMediaCustodyUploadFailure =
                ({
                  required expectedParent,
                  required expectedAttachments,
                  required failedAttachmentId,
                  required failure,
                }) async {
                  exactProjectionCalls++;
                  expect(expectedParent.toMap(), prepared.toMap());
                  expect(
                    expectedAttachments.map((attachment) => attachment.toMap()),
                    <Map<String, Object?>>[
                      pending
                          .copyWith(ownerLane: MediaOwnerLane.direct)
                          .toMap(),
                    ],
                  );
                  expect(failedAttachmentId, attachmentId);
                  expect(failure.disposition, UploadMediaDisposition.terminal);
                  return variant == 'applied'
                      ? const UploadRetryProjectionResult(
                          state: UploadRetryProjectionState.terminal,
                          uploadRetryCount: 0,
                        )
                      : const UploadRetryProjectionResult.notApplied();
                };
          }

          final count = await retryIncompleteUploads(
            mediaAttachmentRepo: localMediaRepo,
            messageRepo: localMessageRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: localIdentityRepo,
            contactRepo: contactRepo,
            uploadMediaFn: localUpload.call,
            uploadRetryProjectionRepo: legacyProjection,
          );

          expect(count, 0, reason: variant);
          expect(localUpload.callCount, 1, reason: variant);
          expect(
            exactProjectionCalls,
            variant == 'unsupported' ? 0 : 1,
            reason: variant,
          );
          expect(legacyProjection.callCount, 0, reason: variant);
          expect(localMediaRepo.allSavedAttachments, isEmpty, reason: variant);
          expect(
            (await localMediaRepo.getAttachmentsForMessage(
              messageId,
              owner: MediaOwnerLane.direct,
            )).single.toMap(),
            pending.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
            reason: variant,
          );
          expect(
            (await localMessageRepo.getMessage(
              messageId,
            ))?.directMediaCustodyIntentId,
            intent,
            reason: variant,
          );
        }
      },
    );

    test(
      'automatic pass with no OS connectivity issues zero uploads and leaves rows untouched',
      () async {
        mediaRepo.seed([_pendingAtt()]);
        messageRepo.seed([_makeMsg('msg-00001', status: 'sending')]);

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          requireOsConnectivity: true,
          connectivityProbe: () async => false,
        );

        expect(count, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(identityRepo.loadIdentityCallCount, 0);
        final rows = await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
          owner: MediaOwnerLane.direct,
        );
        expect(rows.single.downloadStatus, 'upload_pending');
        expect(rows.single.uploadRetryCount, isNull);
        expect((await messageRepo.getMessage('msg-00001'))!.status, 'sending');
      },
    );

    test(
      'explicit/manual invocation bypasses the OS connectivity probe',
      () async {
        final source = File(
          '${Directory.systemTemp.path}/manual-upload-${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await source.writeAsBytes([1, 2, 3]);
        addTearDown(() async {
          if (await source.exists()) await source.delete();
        });
        mediaRepo.seed([
          _pendingAtt(localPath: source.path, mime: 'image/jpeg'),
        ]);
        messageRepo.seed([_makeMsg('msg-00001', status: 'sending')]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        var probeCalls = 0;

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          connectivityProbe: () async {
            probeCalls++;
            return false;
          },
        );

        expect(probeCalls, 0);
        expect(fakeUploadFn.callCount, 1);
      },
    );

    test(
      'typed failure invokes the atomic projection exactly once with no sequential child write',
      () async {
        mediaRepo.seed([_pendingAtt()]);
        messageRepo.seed([_makeMsg('msg-00001', status: 'sending')]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        final projection = _RecordingDirectUploadRetryProjection();

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          uploadRetryProjectionRepo: projection,
        );

        expect(count, 0);
        expect(fakeUploadFn.callCount, 1);
        expect(projection.callCount, 1);
        expect(projection.messageId, 'msg-00001');
        expect(projection.attachmentId, 'att-00001');
        expect(
          projection.failure?.disposition,
          UploadMediaDisposition.terminal,
        );
        expect(mediaRepo.allSavedAttachments, isEmpty);
      },
    );

    test('returns 0 when no upload_pending attachments exist', () async {
      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('returns 0 when identity cannot be loaded', () async {
      mediaRepo.seed([_pendingAtt()]);
      // identityRepo has no seeded identity

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message whose parent message row does not exist', () async {
      mediaRepo.seed([_pendingAtt(messageId: 'nonexistent-msg')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message when parent message is already delivered', () async {
      final msg = _makeMsg('msg-00001', status: 'delivered');
      messageRepo.seed([msg]);
      mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test(
      'skips message when any attachment has null localPath — marks ALL as upload_failed',
      () async {
        final noPathAtt = MediaAttachment(
          id: 'att-no-path',
          messageId: 'msg-00001',
          mime: 'image/jpeg',
          size: 1024,
          mediaType: 'image',
          localPath: null,
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );
        final msg = _makeMsg('msg-00001', status: 'failed');
        messageRepo.seed([msg]);
        mediaRepo.seed([noPathAtt]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );
        expect(count, 0);
        // Attachment should be marked upload_failed
        expect(mediaRepo.lastSavedAttachment?.downloadStatus, 'upload_failed');
      },
    );

    test(
      'first transient upload failure keeps ALL attachments as upload_pending with retryCount=1',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-00001',
            messageId: 'msg-00001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-00002',
            messageId: 'msg-00001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null); // transient failure

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Both attachments stay upload_pending (transient, retryable)
        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(pending.length, 2);
        expect(
          pending.every((a) => a.uploadRetryCount == 1),
          isTrue,
          reason: 'retryCount must be incremented to 1',
        );
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'sendChatMessage must not be called on failed upload',
        );
      },
    );

    test(
      'transient upload failure does not downgrade an attachment completed concurrently',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final pending = _pendingAtt(
          id: 'att-00001',
          messageId: 'msg-00001',
          localPath: '/tmp/img1.jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
        ).copyWith(uploadRetryCount: kMaxUploadRetries - 1);
        messageRepo.seed([msg]);
        mediaRepo.seed([pending]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                await mediaRepo.saveAttachment(
                  owner: MediaOwnerLane.direct,
                  pending.copyWith(downloadStatus: 'done'),
                );
                return const UploadMediaFailed(
                  stage: UploadMediaStage.consumerBoundary,
                  disposition: UploadMediaDisposition.terminal,
                  errorCode: 'TEST_UPLOAD_FAILED',
                );
              },
        );

        final attachments = await mediaRepo.getAttachmentsForMessage(
          owner: MediaOwnerLane.direct,
          'msg-00001',
        );
        expect(count, 0);
        expect(attachments.single.downloadStatus, 'done');
        expect(
          mediaRepo.allSavedAttachments
              .where(
                (attachment) =>
                    attachment.id == 'att-00001' &&
                    attachment.downloadStatus == 'upload_failed',
              )
              .isEmpty,
          isTrue,
        );
      },
    );

    test(
      'completed upload result does not overwrite a concurrently cancelled attachment',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final pending = _pendingAtt(
          id: 'att-00001',
          messageId: 'msg-00001',
          localPath: '/tmp/img1.jpg',
          mime: 'image/jpeg',
          mediaType: 'image',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([pending]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                await mediaRepo.saveAttachment(
                  owner: MediaOwnerLane.direct,
                  pending.copyWith(downloadStatus: 'upload_cancelled'),
                );
                return UploadMediaSucceeded(
                  _doneAttachment('att-00001', 'msg-00001'),
                );
              },
        );

        final attachments = await mediaRepo.getAttachmentsForMessage(
          owner: MediaOwnerLane.direct,
          'msg-00001',
        );
        expect(count, 0);
        expect(attachments.single.downloadStatus, 'upload_cancelled');
        expect(p2pService.storeInInboxCallCount, 0);
      },
    );

    test(
      'transient failure: attachment IS retried on second call (still upload_pending)',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null); // transient failure

        // First attempt: retryCount 0 -> 1, stays upload_pending
        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Second attempt: still upload_pending, so it IS retried
        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(
          pending.length,
          1,
          reason: 'Row must still be upload_pending after first failure',
        );

        // Now succeed on second attempt
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final count2 = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count2, 1, reason: 'Second attempt should succeed');
      },
    );

    test(
      'upload_failed attachment is not picked up after kMaxUploadRetries exhaustion',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        // Seed with retryCount already at kMaxUploadRetries - 1
        mediaRepo.seed([
          _pendingAtt(
            messageId: 'msg-00001',
          ).copyWith(uploadRetryCount: kMaxUploadRetries - 1),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(null);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // Now upload_failed -- not picked up on next call
        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(
          pending,
          isEmpty,
          reason: 'Row must be upload_failed after max retries',
        );

        final count2 = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count2, 0);
      },
    );

    test(
      'returns 1 after successful re-upload and send (single attachment)',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        expect(count, 1);
      },
    );

    // 228: attachment ids are globally unique, but message ids can collide
    // across the direct and group lanes. The direct retrier's lane-scoped
    // pending query must never surface — let alone consume — a group-lane
    // upload_pending row that shares its parent message id.
    test('direct retrier never consumes same id group pending media', () async {
      const collidingMessageId = 'msg-collide-00001';
      final msg = _makeMsg(
        collidingMessageId,
        status: 'failed',
        contactPeerId: 'peer-bob',
      );
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      // SAME messageId in BOTH lanes, distinct attachment ids.
      mediaRepo.seed([
        _pendingAtt(
          id: 'att-direct-collide',
          messageId: collidingMessageId,
          localPath: '/tmp/direct-collide.m4a',
        ),
        _pendingAtt(
          id: 'att-group-collide',
          messageId: collidingMessageId,
          localPath: '/tmp/group-collide.m4a',
        ).copyWith(ownerLane: MediaOwnerLane.group),
      ]);
      fakeUploadFn.willReturn(
        _doneAttachment('blob-uploaded', collidingMessageId),
      );

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      // Only the DIRECT row was re-read and re-uploaded.
      expect(count, 1);
      expect(fakeUploadFn.callCount, 1);
      expect(fakeUploadFn.lastLocalPath, '/tmp/direct-collide.m4a');
      expect(
        await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
        reason: 'the direct pending row must be consumed by the retry',
      );
      // Every save the retrier performed used the direct lane.
      expect(mediaRepo.savedOwnerLanes, everyElement(MediaOwnerLane.direct));
      // The group-lane row is untouched: still upload_pending, same path.
      final groupRows = await mediaRepo.getAttachmentsForMessage(
        collidingMessageId,
        owner: MediaOwnerLane.group,
      );
      expect(groupRows, hasLength(1));
      expect(groupRows.single.id, 'att-group-collide');
      expect(groupRows.single.downloadStatus, 'upload_pending');
      expect(groupRows.single.localPath, '/tmp/group-collide.m4a');
    });

    test(
      'emits RETRY_INCOMPLETE_UPLOADS_TIMING with attachment and message counts',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-00001'));

        final events = await captureFlowEvents(() async {
          await retryIncompleteUploads(
            mediaAttachmentRepo: mediaRepo,
            messageRepo: messageRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            uploadMediaFn: fakeUploadFn.call,
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_INCOMPLETE_UPLOADS_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['attachmentCount'], 1);
        expect(timing['details']['messageCount'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      '127-Bug-B: defers (no re-encrypt/re-upload) when the blob is in-flight '
      'from the foreground send',
      () async {
        final msg = _makeMsg(
          'msg-00001',
          status: 'sending',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(id: 'blob-inflight', messageId: 'msg-00001'),
        ]);
        // If the guard failed, this would be returned and the row marked done.
        fakeUploadFn.willReturn(_doneAttachment('blob-inflight', 'msg-00001'));

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          isUploadInFlight: (blobId) => blobId == 'blob-inflight',
        );

        // The foreground send owns this blob: no re-encrypt, no send, no
        // terminalization — the row stays retryable.
        expect(count, 0);
        expect(fakeUploadFn.callCount, 0);
        final latest = await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
          owner: MediaOwnerLane.direct,
        );
        expect(latest.single.downloadStatus, 'upload_pending');
      },
    );

    test(
      'TC-15 token ownership defers to a foreground winner and releases after '
      'the full retry settles',
      () async {
        const attachmentId = 'blob-token-owned';
        final tracker = MediaUploadInFlightTracker();
        final foregroundLease = tracker.tryClaimAll(const [
          attachmentId,
        ], source: MediaUploadTriggerSource.foreground)!;
        messageRepo.seed([
          _makeMsg('msg-00001', status: 'sending', contactPeerId: 'peer-bob'),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(id: attachmentId, messageId: 'msg-00001')]);
        fakeUploadFn.willReturn(_doneAttachment(attachmentId, 'msg-00001'));

        Future<int> runFullRetry() => retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.full,
          ),
          releaseUploadLease: tracker.release,
        );

        expect(await runFullRetry(), 0);
        expect(fakeUploadFn.callCount, 0);
        expect(tracker.isInFlight(attachmentId), isTrue);

        expect(tracker.release(foregroundLease), isTrue);
        expect(await runFullRetry(), 1);
        expect(fakeUploadFn.callCount, 1);
        expect(
          tracker.isInFlight(attachmentId),
          isFalse,
          reason:
              'the retry lease must cover settlement and release in finally',
        );
      },
    );

    test('also retries when message is still in sending status', () async {
      final msg = _makeMsg(
        'msg-00001',
        status: 'sending',
        contactPeerId: 'peer-bob',
      );
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([_pendingAtt(messageId: 'msg-00001')]);
      fakeUploadFn.willReturn(_doneAttachment('blob-id', 'msg-00001'));

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count, 1);
    });

    test(
      'skips the final send when the message is deleted after upload work completes',
      () async {
        final msg = _makeMsg(
          'msg-late-delete',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        var deleted = false;
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([_pendingAtt(messageId: msg.id)]);
        mediaRepo.onSaveAttachment = (attachment) {
          if (!deleted &&
              attachment.messageId == msg.id &&
              attachment.downloadStatus == 'done') {
            deleted = true;
            messageRepo.deleteMessage(msg.id);
          }
        };
        fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', msg.id));

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0);
        expect(await messageRepo.getMessage(msg.id), isNull);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'late-send guard must suppress sendChatMessage',
        );
      },
    );

    test(
      'late extra pending sibling blocks send and cleanup while preserving the stable blob id',
      () async {
        const messageId = 'msg-late-extra-sibling';
        const originalId = 'att-original-stable';
        const extraId = 'att-late-extra';
        final tempDir = Directory.systemTemp.createTempSync(
          'direct_retry_late_extra_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final originalPath = '${tempDir.path}/original.jpg';
        final extraPath = '${tempDir.path}/extra.jpg';
        await File(originalPath).writeAsBytes([0xFF, 0xD8, 0xFF]);
        await File(extraPath).writeAsBytes([0xFF, 0xD8, 0xFE]);

        messageRepo.seed([
          _makeMsg(messageId, status: 'failed', contactPeerId: 'peer-bob'),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: originalId,
            messageId: messageId,
            localPath: originalPath,
            mime: 'image/jpeg',
            mediaType: 'image',
            durationMs: null,
          ),
        ]);
        var insertedExtraSibling = false;
        mediaRepo.onSaveAttachment = (attachment) {
          if (!insertedExtraSibling &&
              attachment.id == originalId &&
              attachment.downloadStatus == 'done') {
            insertedExtraSibling = true;
            mediaRepo.seedAttachments(
              messageId: messageId,
              attachments: [
                _pendingAtt(
                  id: extraId,
                  messageId: messageId,
                  localPath: extraPath,
                  mime: 'image/jpeg',
                  mediaType: 'image',
                  durationMs: null,
                ),
              ],
            );
          }
        };
        fakeUploadFn.willReturn(
          _doneAttachment(
            'server-reassigned-id',
            messageId,
            mime: 'image/jpeg',
          ),
        );
        final manager = FakeMediaFileManager();
        var cleanupCalled = false;
        manager.onDeletePendingUploadDir = (_) => cleanupCalled = true;

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          mediaFileManager: manager,
        );

        expect(count, 0);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(cleanupCalled, isFalse);
        final rows = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        expect(
          rows.map((row) => row.id),
          unorderedEquals([originalId, extraId]),
        );
        expect(
          rows.singleWhere((row) => row.id == originalId).downloadStatus,
          'done',
        );
        expect(
          rows.singleWhere((row) => row.id == extraId).downloadStatus,
          'upload_pending',
        );
        expect(rows.any((row) => row.id == 'server-reassigned-id'), isFalse);
      },
    );

    // ---- Multi-attachment per-message tests ----

    test(
      'multi-attachment message: uploads ALL then sends ONCE with full list',
      () async {
        final msg = _makeMsg(
          'msg-multi-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-0000a',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000b',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000c',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img3.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        fakeUploadFn.willReturnForPath(
          '/tmp/img1.jpg',
          _doneAttachment('blob-a', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/img2.jpg',
          _doneAttachment('blob-b', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/img3.jpg',
          _doneAttachment('blob-c', 'msg-multi-001', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        // ONE message successfully sent
        expect(count, 1);
        // uploadMedia called 3 times (once per attachment)
        expect(fakeUploadFn.callCount, 3);
        // sendChatMessage called ONCE (inbox path)
        expect(p2pService.storeInInboxCallCount, 1);
        // The wire payload preserves all three logical attachment IDs even if
        // the uploader returns different physical identifiers.
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('att-0000a'));
        expect(payload, contains('att-0000b'));
        expect(payload, contains('att-0000c'));
      },
    );

    test(
      'multi-attachment: successful sibling stays done when second upload fails and send is suppressed',
      () async {
        final msg = _makeMsg(
          'msg-multi-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-0000a',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img1.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-0000b',
            messageId: 'msg-multi-001',
            localPath: '/tmp/img2.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        // First upload succeeds, second returns null (transient)
        fakeUploadFn.willReturnForPath(
          '/tmp/img1.jpg',
          _doneAttachment('blob-a', 'msg-multi-001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath('/tmp/img2.jpg', null);

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0);
        expect(
          p2pService.storeInInboxCallCount,
          0,
          reason: 'must NOT send partial attachment list',
        );
        // Preserve committed work; only the failed pending sibling consumes a
        // retry attempt. The complete-set final gate still suppresses send.
        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(pending, hasLength(1));
        expect(pending.single.id, 'att-0000b');
        expect(pending.single.uploadRetryCount, 1);
        final rows = await mediaRepo.getAttachmentsForMessage(
          msg.id,
          owner: MediaOwnerLane.direct,
        );
        expect(
          rows
              .singleWhere((attachment) => attachment.id == 'att-0000a')
              .downloadStatus,
          'done',
        );
      },
    );

    test(
      'non-fatal: transient error on first message does not prevent processing second message',
      () async {
        final msg1 = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final msg2 = _makeMsg(
          'msg-00002',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg1, msg2]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-00001',
            messageId: 'msg-00001',
            localPath: '/tmp/file1.m4a',
          ),
          _pendingAtt(
            id: 'att-00002',
            messageId: 'msg-00002',
            localPath: '/tmp/file2.m4a',
          ),
        ]);
        fakeUploadFn.willReturnForPath('/tmp/file1.m4a', null); // transient
        fakeUploadFn.willReturnForPath(
          '/tmp/file2.m4a',
          _doneAttachment('blob-2', 'msg-00002'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );
        // msg-1 deferred (transient), msg-2 succeeded
        expect(count, 1);
        // sendChatMessage called once (for msg-2 only)
        expect(p2pService.storeInInboxCallCount, 1);
        // att-1 stays upload_pending (retryable on next cycle)
        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(pending.any((a) => a.id == 'att-00001'), isTrue);
      },
    );

    test(
      'two messages each with multiple attachments: independent recovery',
      () async {
        final msg1 = _makeMsg(
          'msg-00001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        final msg2 = _makeMsg(
          'msg-00002',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg1, msg2]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-001-a',
            messageId: 'msg-00001',
            localPath: '/tmp/1a.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-001-b',
            messageId: 'msg-00001',
            localPath: '/tmp/1b.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          _pendingAtt(
            id: 'att-002-a',
            messageId: 'msg-00002',
            localPath: '/tmp/2a.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);
        fakeUploadFn.willReturnForPath(
          '/tmp/1a.jpg',
          _doneAttachment('blob-1a', 'msg-00001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/1b.jpg',
          _doneAttachment('blob-1b', 'msg-00001', mime: 'image/jpeg'),
        );
        fakeUploadFn.willReturnForPath(
          '/tmp/2a.jpg',
          _doneAttachment('blob-2a', 'msg-00002', mime: 'image/jpeg'),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 2); // both messages recovered
        expect(fakeUploadFn.callCount, 3); // 3 uploads total
        expect(
          p2pService.storeInInboxCallCount,
          2,
        ); // 2 sends (one per message)
      },
    );

    // G.8.2.1
    test(
      'first upload failure keeps row as upload_pending (retryable)',
      () async {
        final msg = _makeMsg(
          'msg-test-t1',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-test-t1',
            messageId: 'msg-test-t1',
            localPath: '/durable/photo.jpg',
          ),
        ]);
        fakeUploadFn.willReturn(null); // transient failure

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(pending.length, 1);
        expect(pending.first.uploadRetryCount, 1);
        expect(pending.first.downloadStatus, 'upload_pending');
      },
    );

    // G.8.2.2
    test(
      'after kMaxUploadRetries failures, row transitions to upload_failed',
      () async {
        final msg = _makeMsg(
          'msg-test-t2',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'att-test-t2',
            messageId: 'msg-test-t2',
            localPath: '/durable/photo.jpg',
          ).copyWith(uploadRetryCount: kMaxUploadRetries - 1),
        ]);
        fakeUploadFn.willReturn(null);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(pending, isEmpty);
        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved?.downloadStatus, 'upload_failed');
        expect(lastSaved?.uploadRetryCount, kMaxUploadRetries);
      },
    );

    // G.8.2.3
    test(
      'missing local file is immediately terminal regardless of retryCount',
      () async {
        final msg = _makeMsg(
          'msg-test-t3',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          MediaAttachment(
            id: 'att-test-t3',
            messageId: 'msg-test-t3',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: null,
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ]);

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved?.downloadStatus, 'upload_failed');
      },
    );

    // G.8.3.1
    test(
      'TC-347-08c absent-v111 partial legacy attempt never promotes to strict',
      () async {
        const messageId = 'msg-347-absent-v111-partial';
        const doneId = 'att-347-legacy-done';
        const pendingId = 'att-347-legacy-pending';
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[doneId, pendingId],
        );
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: 'peer-bob-001',
          senderPeerId: 'my-peer-id',
          text: '',
          timestamp: '2026-08-08T12:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-08-08T12:00:00.000Z',
          directMediaCustodyIntentId: intent,
        );
        final pending = _pendingAtt(
          id: pendingId,
          messageId: messageId,
          localPath: MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: pendingId,
            mime: 'audio/mpeg',
          ),
        ).copyWith(ownerLane: MediaOwnerLane.direct);
        final done = _doneAttachment(
          doneId,
          messageId,
        ).copyWith(ownerLane: MediaOwnerLane.direct);
        final absentBlobRepo = _AbsentDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[done, pending]);
        messageRepo.seed(<ConversationMessage>[message]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        fakeUploadFn.willReturn(
          _doneAttachment(
            pendingId,
            messageId,
          ).copyWith(durationMs: pending.durationMs),
        );

        await retryIncompleteUploads(
          mediaAttachmentRepo: absentBlobRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(absentBlobRepo.blobLoads, 1);
        expect(absentBlobRepo.blobStages, 0);
        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastBlobId, pendingId);
        expect(
          bridge.commandLog.where((command) => command == 'media:upload'),
          isEmpty,
          reason: 'absent v111 must not enter the strict upload owner',
        );
      },
      skip: !kDirectMediaBlobCustodyClientEnabled,
    );

    test('TC-358-02b disappearing strict restart reopens exact v111 without '
        'legacy upload', () async {
      const messageId = 'msg-358-02b-disappearing';
      const attachmentId = 'att-358-02b-disappearing';
      const contentHash =
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      final intent = computeDirectMediaCustodyIntentId(
        messageId: messageId,
        attachmentIds: const <String>[attachmentId],
      );
      final pendingPath = MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: 'image/jpeg',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: 'peer-bob',
        senderPeerId: 'my-peer-id',
        text: '',
        timestamp: '2026-08-11T09:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-08-11T09:00:00.000Z',
        directMediaCustodyIntentId: intent,
        privateMediaPolicy: PrivateMediaPolicy.disappearing(3600),
        privateMediaState: PrivateMediaLifecycleState.available,
      );
      // The already-published generation: an exact convention-pending row
      // carrying the SAME ciphertext identity as the durable v111 row.
      final published = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: pendingPath,
        downloadStatus: 'upload_pending',
        createdAt: '2026-08-11T09:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
        contentHash: contentHash,
        encryptionKeyBase64: 'tc358-02b-raw-key',
        encryptionNonce: 'tc358-02b-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final repo = _ExistingDirectMediaBlobRepository(
        DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          inboxCustodyIncarnationId: null,
          recipientPeerId: 'peer-bob',
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'6' * 64}/$attachmentId.blob',
          contentHash: contentHash,
          ciphertextSize: 4096,
          expiresAtMs: null,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: '2026-08-11T09:00:01.000Z',
          updatedAt: '2026-08-11T09:00:01.000Z',
        ),
      )..seed(<MediaAttachment>[published]);
      messageRepo.seed(<ConversationMessage>[message]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      var prepareArtifactCalls = 0;
      var strictUploadCalls = 0;
      final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: repo,
        artifactStore: DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async =>
              Directory.systemTemp.createTempSync('tc358_02b_'),
        ),
        prepareArtifact:
            ({required Bridge bridge, required String localFilePath}) async {
              prepareArtifactCalls++;
              throw StateError('reopen must never re-encrypt');
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
              return <String, dynamic>{'ok': false};
            },
      );

      await retryIncompleteUploads(
        mediaAttachmentRepo: repo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
        directMediaBlobCustodyCoordinator: coordinator,
      );

      expect(
        repo.ordinaryStageCalls,
        1,
        reason:
            'a complete disappearing v111 generation reopens through the '
            'ORDINARY strict coordinator',
      );
      expect(
        repo.privateStageCalls,
        0,
        reason: 'disappearing never enters the P/VO private coordinator',
      );
      expect(
        prepareArtifactCalls,
        0,
        reason: 'an exact reopen must never re-encrypt the blob',
      );
      expect(
        fakeUploadFn.callCount,
        0,
        reason:
            'a proven strict generation never falls back to legacy '
            'upload',
      );
      // Byte-identical ciphertext identity survives the reopen.
      final retained = (await repo.getAttachmentById(attachmentId))!;
      expect(retained.contentHash, contentHash);
      expect(retained.encryptionKeyBase64, 'tc358-02b-raw-key');
      expect(retained.encryptionNonce, 'tc358-02b-nonce');
      expect(repo.row.contentHash, contentHash);
      expect(strictUploadCalls, lessThanOrEqualTo(1));
    }, skip: !kDirectMediaBlobCustodyClientEnabled);

    test(
      'TC-362-02b failed and incomplete retries replay exact persisted fanout rows without resolver or re-encryption',
      () async {
        const contactPeerId = 'peer-bob';
        const authoredAt = '2026-08-11T08:00:00.000Z';
        const contentHash =
            'efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef';
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

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
        }) => DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingStored,
          inboxCustodyIncarnationId: null,
          recipientPeerId: recipientPeerId,
          contactAccountPeerId: contactPeerId,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/$contentHash/$attachmentId.blob',
          contentHash: contentHash,
          ciphertextSize: 4096,
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
          void Function() onStrictUpload,
        ) => PreparedDirectMediaBlobCustodyCoordinator(
          repository: repository,
          artifactStore: DirectMediaBlobArtifactStore(
            documentsDirectoryProvider: () async =>
                Directory.systemTemp.createTempSync('tc362_02b_incomplete_'),
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
        // the lane skips silently with no coordinator call at all, no roster
        // read, and no legacy upload.
        final terminal = publishedFixture(
          'msg-362-terminal-skip',
          'att-362-terminal-skip',
        );
        final terminalRepo = _LinkedFanoutDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[terminal.published]);
        messageRepo.seed(<ConversationMessage>[terminal.message]);
        var terminalPrepares = 0;
        var terminalUploads = 0;
        final terminalEvents = await captureFlowEvents(() async {
          await retryIncompleteUploads(
            mediaAttachmentRepo: terminalRepo,
            messageRepo: messageRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            uploadMediaFn: fakeUploadFn.call,
            directMediaBlobCustodyCoordinator: recordingCoordinator(
              terminalRepo,
              () => terminalPrepares++,
              () => terminalUploads++,
            ),
          );
        });
        expect(
          terminalEvents.map((event) => event['event']),
          contains('RETRY_INCOMPLETE_UPLOAD_SKIPPED_FANOUT_GENERATION'),
          reason: 'marker without linked rows is a terminal no-remint fact',
        );
        expect(
          terminalRepo.lifecycleRuns,
          0,
          reason: 'terminal skip: no coordinator call at all',
        );
        expect(terminalPrepares, 0);
        expect(terminalUploads, 0);
        expect(terminalRepo.ordinaryStageCalls, 0);
        expect(terminalRepo.snapshotReads, 0);
        expect(fakeUploadFn.callCount, 0);
        expect(
          (await messageRepo.getMessage(terminal.message.id))!.status,
          'failed',
        );

        // Leg 2: persisted LINKED rows are the exclusive survivor-first retry
        // authority. The lane must replay THEM through the shared fanout
        // owner (retryPersistedFanoutGeneration) — never reopenAndUpload, a
        // roster resolution, a re-encryption, or the legacy upload lane.
        final linked = publishedFixture('msg-362-linked', 'att-362-linked');
        final expiresAtMs = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .millisecondsSinceEpoch;
        final linkedRepo = _LinkedFanoutDirectMediaBlobRepository()
          ..seed(<MediaAttachment>[linked.published])
          ..rows.addAll(<DirectMediaBlobCustodyRow>[
            linkedStoredRow(
              messageId: linked.message.id,
              attachmentId: 'att-362-linked',
              recipientPeerId: contactPeerId,
              recipientMlKemPublicKey: 'mlkem-legacy-account',
              expiresAtMs: expiresAtMs,
            ),
            linkedStoredRow(
              messageId: linked.message.id,
              attachmentId: 'att-362-linked',
              recipientPeerId: 'peer-bob-device-a',
              recipientMlKemPublicKey: 'mlkem-device-a',
              expiresAtMs: expiresAtMs + 60000,
            ),
          ]);
        final rowsBefore = linkedRepo.rows
            .map((row) => row.toMap())
            .toList(growable: false);
        final linkedMessages = FakeMessageRepository()
          ..seed(<ConversationMessage>[linked.message]);
        var linkedPrepares = 0;
        var linkedUploads = 0;
        await retryIncompleteUploads(
          mediaAttachmentRepo: linkedRepo,
          messageRepo: linkedMessages,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
          directMediaBlobCustodyCoordinator: recordingCoordinator(
            linkedRepo,
            () => linkedPrepares++,
            () => linkedUploads++,
          ),
        );

        if (kDirectMediaBlobCustodyClientEnabled) {
          expect(
            linkedRepo.lifecycleRuns,
            1,
            reason:
                'retryPersistedFanoutGeneration ran once under the '
                'coordinator lifecycle lease',
          );
          expect(
            linkedRepo.blobLoads,
            2,
            reason:
                'the lane and the fanout retry owner both read the '
                'EXACT persisted rows for this parent',
          );
          expect(linkedRepo.loadedMessageIds.toSet(), <String>{
            linked.message.id,
          });
          expect(
            linkedRepo.snapshotReads,
            0,
            reason:
                'the live roster snapshot is consulted only AFTER a '
                'complete replay — never as retry authority',
          );
        } else {
          expect(
            linkedRepo.lifecycleRuns,
            0,
            reason:
                'selector-off compilations fail closed without any '
                'coordinator work',
          );
          expect(linkedRepo.blobLoads, 0);
        }
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
        expect(linkedRepo.fanoutInboxStageCalls, 0);
        expect(fakeUploadFn.callCount, 0, reason: 'no legacy upload');
        expect(
          linkedRepo.rows.map((row) => row.toMap()).toList(growable: false),
          rowsBefore,
          reason: 'every exact persisted fanout row is byte-identical',
        );
        expect(
          (await linkedMessages.getMessage(linked.message.id))!.status,
          'failed',
          reason: 'the durable parent is retained for the next attempt',
        );
      },
    );

    test('TC-354-03a private strict restart reopens completes and binds exact '
        'generation', () async {
      const messageId = 'tc354-03a-private';
      const attachmentId = 'tc354-03a-private-att';
      const contentHash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final pendingPath = MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: 'image/jpeg',
      );
      final message = ConversationMessage(
        id: messageId,
        contactPeerId: 'peer-bob',
        senderPeerId: 'my-peer-id',
        text: '',
        timestamp: '2026-08-10T13:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-08-10T13:00:00.000Z',
        privateMediaPolicy: const PrivateMediaPolicy.protected(),
        privateMediaState: PrivateMediaLifecycleState.available,
      );
      // The already-published generation: prepared v111 plus its exact
      // convention-pending row carrying the SAME ciphertext identity.
      final published = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: pendingPath,
        downloadStatus: 'upload_pending',
        createdAt: '2026-08-10T13:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
        contentHash: contentHash,
        encryptionKeyBase64: 'tc354-03a-raw-key',
        encryptionNonce: 'tc354-03a-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final repo = _PrivateStrictBlobRepository(
        DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          inboxCustodyIncarnationId: null,
          recipientPeerId: 'peer-bob',
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'7' * 64}/$attachmentId.blob',
          contentHash: contentHash,
          ciphertextSize: 4096,
          expiresAtMs: null,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: '2026-08-10T13:00:01.000Z',
          updatedAt: '2026-08-10T13:00:01.000Z',
        ),
      )..seed(<MediaAttachment>[published]);
      messageRepo.seed(<ConversationMessage>[message]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      // The reopen owner is the exact production seam both retry lanes
      // call. It must revalidate through the private staging CAS, never
      // re-encrypt, and never mint a missing generation.
      var prepareArtifactCalls = 0;
      var strictUploadCalls = 0;
      final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: repo,
        artifactStore: DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async =>
              Directory.systemTemp.createTempSync('tc354_03a_'),
        ),
        prepareArtifact:
            ({required Bridge bridge, required String localFilePath}) async {
              prepareArtifactCalls++;
              throw StateError('reopen must never re-encrypt');
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
              return <String, dynamic>{'ok': false};
            },
      );

      final reopened = await coordinator.reopenAndUploadPrivate(
        bridge: bridge,
        identityPeerId: 'my-peer-id',
        recipientPeerId: 'peer-bob',
        expectedParent: message,
        expectedAttachment: published,
      );

      expect(
        prepareArtifactCalls,
        0,
        reason: 'an exact reopen must never re-encrypt the blob',
      );
      expect(
        repo.privateStageCalls,
        1,
        reason: 'the reopen revalidates through the private staging CAS',
      );
      // The artifact store cannot verify a fixture-only ciphertext, so this
      // reopen retains durable authority instead of uploading. What matters
      // is that it never fell back to encrypt-and-upload.
      expect(reopened.isComplete, isFalse);
      expect(strictUploadCalls, 0);
      expect(
        repo.row.state,
        DirectMediaBlobCustodyState.outgoingPrepared,
        reason: 'the exact durable generation is retained for a later try',
      );
      expect(repo.row.contentHash, contentHash);

      // The whole retry lane also refuses to route this parent through the
      // legacy upload helper.
      await retryIncompleteUploads(
        mediaAttachmentRepo: repo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
        directMediaBlobCustodyCoordinator: coordinator,
      );
      expect(
        fakeUploadFn.callCount,
        0,
        reason:
            'a published private generation must never reach the legacy '
            'upload lane',
      );
      expect(
        bridge.commandLog.where((command) => command == 'media:upload'),
        isEmpty,
      );
      final durable = await repo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      expect(durable.single.contentHash, contentHash);
      expect(durable.single.encryptionNonce, 'tc354-03a-nonce');
      expect(durable.single.localPath, pendingPath);
    }, skip: !kDirectMediaBlobCustodyClientEnabled);

    test(
      'partial upload crash: re-uploads only pending, combines with done',
      () async {
        final msg = _makeMsg(
          'msg-partial-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        mediaRepo.seed([
          _doneAttachment('att-done-1', 'msg-partial-001', mime: 'image/jpeg'),
          _doneAttachment('att-done-2', 'msg-partial-001', mime: 'image/jpeg'),
          _pendingAtt(
            id: 'att-pending-3',
            messageId: 'msg-partial-001',
            localPath: '/durable/img3.jpg',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
        ]);

        fakeUploadFn.willReturn(
          _doneAttachment(
            'att-pending-3',
            'msg-partial-001',
            mime: 'image/jpeg',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(p2pService.storeInInboxCallCount, 1);
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('att-done-1'));
        expect(payload, contains('att-done-2'));
        expect(payload, contains('att-pending-3'));
      },
    );

    test(
      'partial upload crash re-uploads only pending GIF and keeps done JPEG sibling',
      () async {
        final msg = _makeMsg(
          'msg-gif-partial-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        mediaRepo.seed([
          _doneAttachment(
            'att-jpeg-done',
            'msg-gif-partial-001',
            mime: 'image/jpeg',
          ),
          _pendingAtt(
            id: 'att-gif-pending',
            messageId: 'msg-gif-partial-001',
            localPath: '/durable/funny.gif',
            mime: 'image/gif',
            mediaType: 'image',
            durationMs: null,
          ),
        ]);

        fakeUploadFn.willReturn(
          _doneAttachment(
            'att-gif-pending',
            'msg-gif-partial-001',
            mime: 'image/gif',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(fakeUploadFn.lastMime, 'image/gif');
        expect(fakeUploadFn.lastBlobId, 'att-gif-pending');
        final payload = p2pService.lastStoreInInboxMessage!;
        expect(payload, contains('att-jpeg-done'));
        expect(payload, contains('att-gif-pending'));
        final envelope = jsonDecode(payload) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final ciphertext = encrypted['ciphertext'] as String;
        expect(ciphertext, contains('"mime":"image/gif"'));
      },
    );

    test(
      'promotes to canonical storage before envelope settlement and cleans staging only after success',
      () async {
        final suffix = DateTime.now().microsecondsSinceEpoch;
        final messageId = 'msg-promote-$suffix';
        final attachmentId = 'att-promote-$suffix';
        final storedStagingPath =
            'pending_uploads/$messageId/$attachmentId.jpg';
        final manager = FakeMediaFileManager();
        final stagingPath = await manager.resolveStoredPath(storedStagingPath);
        final stagingFile = File(stagingPath);
        await stagingFile.create(recursive: true);
        await stagingFile.writeAsBytes(List<int>.filled(512, 0x42));
        final stagingDir = stagingFile.parent;
        var cleanupCalled = false;
        manager.onDeletePendingUploadDir = (deletedMessageId) {
          expect(deletedMessageId, messageId);
          cleanupCalled = true;
          if (stagingDir.existsSync()) {
            stagingDir.deleteSync(recursive: true);
          }
        };
        addTearDown(() async {
          if (await stagingDir.exists()) {
            await stagingDir.delete(recursive: true);
          }
          final canonical = await manager.resolveStoredPath(
            'media/peer-bob/$attachmentId.jpg',
          );
          if (await File(canonical).exists()) await File(canonical).delete();
        });

        messageRepo.seed([
          _makeMsg(messageId, status: 'failed', contactPeerId: 'peer-bob'),
        ]);
        mediaRepo.seed([
          _pendingAtt(
            id: attachmentId,
            messageId: messageId,
            localPath: storedStagingPath,
            mime: 'image/jpeg',
            mediaType: 'image',
            durationMs: null,
          ),
        ]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        final sendGate = Completer<void>();
        p2pService.sendMessageWithReplyResult = const p2p.SendMessageResult(
          sent: false,
        );
        p2pService.onStoreInInbox = (_, _, {timeoutMs}) async {
          await sendGate.future;
          return true;
        };
        final tracker = MediaUploadInFlightTracker();
        final realBridge = PassthroughCryptoBridge();

        final retryFuture = retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: realBridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          mediaFileManager: manager,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.full,
          ),
          releaseUploadLease: tracker.release,
        );

        await _waitUntilAsync(() async {
          final rows = await mediaRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          );
          return rows.single.downloadStatus == 'done' &&
              p2pService.storeInInboxCallCount > 0;
        });

        final committed = (await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        )).single;
        expect(committed.downloadStatus, 'done');
        expect(committed.localPath, startsWith('media/'));
        expect(committed.localPath, isNot(contains('pending_uploads')));
        final canonicalPath = await manager.resolveStoredPath(
          committed.localPath!,
        );
        expect(await File(canonicalPath).exists(), isTrue);
        expect(await stagingFile.exists(), isTrue);
        expect(cleanupCalled, isFalse);
        expect(tracker.isInFlight(attachmentId), isTrue);

        sendGate.complete();
        expect(await retryFuture, 1);
        expect(cleanupCalled, isTrue);
        expect(await stagingDir.exists(), isFalse);
        expect(await File(canonicalPath).exists(), isTrue);
        expect(tracker.isInFlight(attachmentId), isFalse);
      },
    );

    test('failed envelope settlement preserves retry staging', () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final messageId = 'msg-send-fail-$suffix';
      final attachmentId = 'att-send-fail-$suffix';
      final storedStagingPath = 'pending_uploads/$messageId/$attachmentId.jpg';
      final manager = FakeMediaFileManager();
      final stagingPath = await manager.resolveStoredPath(storedStagingPath);
      final stagingFile = File(stagingPath);
      await stagingFile.create(recursive: true);
      await stagingFile.writeAsBytes(List<int>.filled(512, 0x17));
      final stagingDir = stagingFile.parent;
      var cleanupCalled = false;
      manager.onDeletePendingUploadDir = (_) => cleanupCalled = true;
      addTearDown(() async {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
        final canonical = await manager.resolveStoredPath(
          'media/peer-bob/$attachmentId.jpg',
        );
        if (await File(canonical).exists()) await File(canonical).delete();
      });

      messageRepo.seed([
        _makeMsg(messageId, status: 'failed', contactPeerId: 'peer-bob'),
      ]);
      mediaRepo.seed([
        _pendingAtt(
          id: attachmentId,
          messageId: messageId,
          localPath: storedStagingPath,
          mime: 'image/jpeg',
          mediaType: 'image',
          durationMs: null,
        ),
      ]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      p2pService.storeInInboxResult = false;
      p2pService.sendMessageWithReplyResult = const p2p.SendMessageResult(
        sent: false,
      );

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: PassthroughCryptoBridge(),
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        mediaFileManager: manager,
      );

      expect(count, 0);
      final committed = (await mediaRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      )).single;
      expect(committed.downloadStatus, 'done');
      expect(committed.localPath, startsWith('media/'));
      final canonicalPath = await manager.resolveStoredPath(
        committed.localPath!,
      );
      expect(await File(canonicalPath).exists(), isTrue);
      expect(await stagingFile.exists(), isTrue);
      expect(cleanupCalled, isFalse);
    });

    // G.10.1.1
    test(
      'retry after interrupted sendLocalMedia uses relay, not local WiFi',
      () async {
        final msg = _makeMsg(
          'msg-voice-local-001',
          status: 'failed',
          contactPeerId: 'peer-bob',
        );
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());
        mediaRepo.seed([
          _pendingAtt(
            id: 'voice-local-att',
            messageId: 'msg-voice-local-001',
            localPath: '/tmp/voice.m4a',
            mime: 'audio/mp4',
            mediaType: 'audio',
            durationMs: 3000,
          ),
        ]);
        fakeUploadFn.willReturn(
          _doneAttachment(
            'voice-local-att',
            'msg-voice-local-001',
            mime: 'audio/mp4',
          ),
        );

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 1);
        expect(fakeUploadFn.callCount, 1);
        expect(
          p2pService.sendLocalMediaCallCount,
          0,
          reason: 'Retry must use relay, not local WiFi',
        );
      },
    );
  });

  // --- 112 Phase 3: retry/replay key coherence (KC-2) ---
  // These wire the REAL uploadMedia (not the typedef stub): R6 — the
  // stubbed suite above stays green while crypto behavior changes
  // underneath and cannot observe key minting or envelope coherence.
  group('KC-2 key coherence', () {
    late Directory tempDir;
    late File sourceFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kc2_retry_');
      sourceFile = File('${tempDir.path}/recording.m4a');
      await sourceFile.writeAsBytes(List<int>.filled(4096, 0x42), flush: true);
      identityRepo.seed(
        FakeIdentityRepository.makeIdentity(peerId: 'peer-alice-001'),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    MediaAttachment seedOldKeyPending() =>
        _pendingAtt(localPath: sourceFile.path).copyWith(
          contentHash: _testContentHash,
          encryptionKeyBase64: 'old-key',
          encryptionNonce: 'old-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

    test('retry re-encrypts with a fresh key and persists updated metadata to '
        'the attachment row', () async {
      // Green-on-arrival pin in plan order (1→2→3): after Phase 2 the
      // real uploadMedia mints a fresh key per call and retry persists
      // the re-uploaded attachment row.
      await messageRepo.saveMessage(_makeMsg('msg-00001', status: 'failed'));
      await mediaRepo.saveAttachment(
        seedOldKeyPending(),
        owner: MediaOwnerLane.direct,
      );

      final realBridge = PassthroughCryptoBridge();
      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: realBridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(count, 1);
      expect(
        realBridge.commandLog,
        containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
      );
      final row = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-00001',
      )).single;
      expect(row.downloadStatus, 'done');
      expect(row.encryptionKeyBase64, isNotNull);
      expect(row.encryptionKeyBase64, isNot('old-key'));
      expect(row.encryptionNonce, isNot('old-nonce'));
    });

    test(
      'retry never reuses a prior key for a new blob:encrypt call',
      () async {
        // Green-on-arrival pin (KC-2 defense-in-depth): distinct blobs get
        // distinct keys even within one retry pass.
        final secondFile = File('${tempDir.path}/second.m4a');
        await secondFile.writeAsBytes(
          List<int>.filled(2048, 0x17),
          flush: true,
        );
        await messageRepo.saveMessage(_makeMsg('msg-00001', status: 'failed'));
        await mediaRepo.saveAttachment(
          seedOldKeyPending(),
          owner: MediaOwnerLane.direct,
        );
        await mediaRepo.saveAttachment(
          owner: MediaOwnerLane.direct,
          _pendingAtt(
            id: 'att-00002',
            messageId: 'msg-00001',
            localPath: secondFile.path,
          ),
        );

        final realBridge = PassthroughCryptoBridge();
        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: realBridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        final rows = await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
          owner: MediaOwnerLane.direct,
        );
        final keys = rows
            .map((row) => row.encryptionKeyBase64)
            .whereType<String>()
            .toSet();
        expect(rows, hasLength(2));
        expect(keys, hasLength(2), reason: 'each blob must get a fresh key');
      },
    );

    test('successful re-upload with changed key invalidates the persisted wire '
        'envelope of the parent message', () async {
      // THE genuine RED of this phase: the Section-4 replay contract
      // persists the envelope verbatim while retry re-encrypts the blob
      // under a new key — a replayed stale envelope would reference a
      // dead key (undecryptable media). Node is STOPPED so the rebuild
      // inside this use case cannot mask the invalidation.
      await messageRepo.saveMessage(
        _makeMsg(
          'msg-00001',
          status: 'failed',
        ).copyWith(wireEnvelope: '{"stale":"envelope-with-old-key"}'),
      );
      await mediaRepo.saveAttachment(
        seedOldKeyPending(),
        owner: MediaOwnerLane.direct,
      );
      var observedSafeCommitOrder = false;
      mediaRepo.onSaveAttachment = (attachment) {
        if (attachment.downloadStatus == 'done' &&
            attachment.encryptionKeyBase64 != 'old-key') {
          observedSafeCommitOrder = true;
          expect(
            messageRepo.lastSavedMessage?.wireEnvelope,
            isNull,
            reason:
                'the stale envelope must be cleared before new attachment '
                'keys become durable',
          );
        }
      };
      p2pService.emitState(NodeState.stopped);

      final realBridge = PassthroughCryptoBridge();
      await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: realBridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      final row = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-00001',
      )).single;
      expect(row.encryptionKeyBase64, isNot('old-key'));
      expect(observedSafeCommitOrder, isTrue);
      final message = await messageRepo.getMessage('msg-00001');
      expect(
        message!.wireEnvelope,
        isNull,
        reason:
            'the stale envelope referencing the dead key must be '
            'invalidated so no replay path can ship it',
      );
    });

    test(
      'invalidation refusal aborts attachment completion and send',
      () async {
        final pending = seedOldKeyPending();
        final original = _makeMsg(
          'msg-00001',
          status: 'failed',
        ).copyWith(wireEnvelope: '{"attempt":"old-key"}');
        final crossedWinner = original.copyWith(
          text: 'concurrent edited winner',
          editedAt: '2026-08-05T12:20:00.000Z',
          wireEnvelope: '{"attempt":"new-key"}',
          transport: 'direct',
          relayExpiresAt: 8005,
          custodyCheckedAt: '2026-08-05T12:21:00.000Z',
        );
        messageRepo.seed([original]);
        mediaRepo.seed([pending]);
        fakeUploadFn.willReturn(_doneAttachment('att-00001', 'msg-00001'));
        fakeUploadFn.beforeReturn = () {
          messageRepo.seed([crossedWinner]);
        };

        final count = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: fakeUploadFn.call,
        );

        expect(count, 0);
        expect(fakeUploadFn.callCount, 1);
        expect(
          (await messageRepo.getMessage('msg-00001'))!.toMap(),
          crossedWinner.toMap(),
        );
        final durableAttachment = (await mediaRepo.getAttachmentsForMessage(
          'msg-00001',
          owner: MediaOwnerLane.direct,
        )).single;
        expect(
          durableAttachment.toMap(),
          pending.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
        );
        expect(mediaRepo.allSavedAttachments, isEmpty);
        expect(messageRepo.saveMessageCallCount, 0);
        expect(messageRepo.ordinaryMutationCallCount, 1);
        expect(p2pService.storeInInboxCallCount, 0);
        expect(p2pService.sendMessageCallCount, 0);
        expect(p2pService.sendMessageWithReplyCallCount, 0);
        expect(p2pService.discoverPeerCallCount, 0);
        expect(p2pService.dialPeerCallCount, 0);
        expect(p2pService.sendLocalMediaCallCount, 0);
      },
    );

    test('re-sent message after media re-upload carries the attachment row\'s '
        'current key in its envelope', () async {
      // End-to-end KC-2 contract: the envelope persisted after the
      // retry's rebuild references the row's CURRENT key.
      await messageRepo.saveMessage(
        _makeMsg(
          'msg-00001',
          status: 'failed',
        ).copyWith(wireEnvelope: '{"stale":"envelope-with-old-key"}'),
      );
      await mediaRepo.saveAttachment(
        seedOldKeyPending(),
        owner: MediaOwnerLane.direct,
      );

      final realBridge = PassthroughCryptoBridge();
      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: realBridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );

      expect(count, 1);
      final row = (await mediaRepo.getAttachmentsForMessage(
        owner: MediaOwnerLane.direct,
        'msg-00001',
      )).single;
      final rebuiltEnvelope =
          messageRepo.ordinaryAttemptStages.last.wireEnvelope;
      expect(rebuiltEnvelope, isNotNull);
      final envelope = jsonDecode(rebuiltEnvelope!) as Map<String, dynamic>;
      final inner =
          jsonDecode(
                (envelope['encrypted'] as Map<String, dynamic>)['ciphertext']
                    as String,
              )
              as Map<String, dynamic>;
      final media = inner['media'] as List<dynamic>;
      final wireAttachment = media.single as Map<String, dynamic>;
      expect(wireAttachment['encryptionKeyBase64'], row.encryptionKeyBase64);
      expect(wireAttachment['encryptionNonce'], row.encryptionNonce);
    });
  });
}
