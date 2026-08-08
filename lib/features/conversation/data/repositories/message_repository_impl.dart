import 'dart:async';

import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/conversation_message.dart';
import '../../domain/models/conversation_thread_summary.dart';
import '../../domain/models/direct_inbox_custody_outbox_entry.dart';
import '../../domain/models/media_attachment.dart';
import '../../domain/models/outgoing_ordinary_mutation_result.dart';
import '../../domain/repositories/conversation_thread_summary_repository.dart';
import '../../domain/repositories/direct_private_media_lifecycle_repository.dart';
import '../../domain/repositories/message_repository.dart';

/// Implementation of MessageRepository using database helper functions.
class MessageRepositoryImpl
    implements
        MessageRepository,
        DirectPrivateMediaLifecycleRepository,
        DirectPrivateMediaExactOpeningLeaseRepository,
        DirectPrivateMediaIndeterminateQuarantineRepository,
        DirectPrivateDeleteForEveryoneRepository,
        ConversationThreadSummaryRepository,
        DirectUploadRetryProjectionRepository,
        DirectManualUploadRetryRearmRepository,
        OutgoingTransportMutationRepository,
        OutgoingDirectTextInboxCustodyRepository,
        OutgoingDirectPrivateEnvelopeCustodyRepository,
        MessageRepositoryChangeSource,
        MessageRepositoryRemovalSource,
        ConversationReadEventSource {
  final Future<void> Function(Map<String, Object?> row) dbInsertMessage;
  final Future<List<Map<String, Object?>>> Function(String contactPeerId)
  dbLoadMessagesForContact;
  final Future<Map<String, Object?>?> Function(String contactPeerId)
  dbLoadLatestMessageForContact;
  final Future<int> Function(String id, String status) dbUpdateMessageStatus;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMessage;
  final Future<int> Function(String contactPeerId) dbCountMessagesForContact;
  final Future<int> Function(String contactPeerId) dbMarkConversationAsRead;
  final Future<int> Function(String contactPeerId)? projectConversationRead;
  final Future<int> Function(String contactPeerId) dbCountUnreadForContact;
  final Future<int> Function() dbCountTotalUnread;
  final Future<int> Function() dbCountTotalUnreadExcludingArchived;
  final Future<int> Function(String contactPeerId) dbDeleteMessagesForContact;
  final Future<int> Function(String id) dbDeleteMessage;
  final Future<bool> Function(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  )
  dbExistsMessageByContent;
  // F8 tier-2: optional/nullable (fail-open false) so the existing test ctor
  // sites stay untouched; production (main.dart) wires the real helper.
  final Future<bool> Function(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  )?
  dbExistsMessageByDedupKey;
  final Future<List<Map<String, Object?>>> Function(
    String contactPeerId, {
    int limit,
    String? beforeTimestamp,
  })
  dbLoadMessagesPage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadFailedOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function({
    required DateTime olderThan,
    int limit,
  })
  dbLoadUnackedOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function(List<String> contactPeerIds)
  dbLoadConversationThreadSummaries;
  final Future<int> Function({required DateTime olderThan, int limit})
  dbRecoverStuckSendingMessages;
  final Future<void> Function(String id, String wireEnvelope)?
  dbUpdateWireEnvelope;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required OutgoingOrdinaryAttemptKind kind,
  })?
  dbStageOutgoingOrdinaryAttempt;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String messageId,
    required String incarnationId,
    required String wireEnvelope,
  })?
  dbStageOutgoingDirectTextInboxCustody;
  final Future<List<Map<String, Object?>>> Function({int limit})?
  dbLoadDirectInboxCustodyOutbox;
  final Future<Map<String, Object?>?> Function({
    required String recipientPeerId,
    required String messageId,
  })?
  dbLoadDirectInboxCustodyOutboxForMessage;
  final Future<Map<String, Object?>?> Function({required String messageId})?
  dbLoadDirectInboxCustodyOutboxOwnerForMessageId;
  final Future<bool> Function({
    required String recipientPeerId,
    required String messageId,
    required String expectedIncarnationId,
    required String expectedWireEnvelope,
    required String errorCode,
    required String attemptedAt,
  })?
  dbRecordDirectInboxCustodyFailureIfExact;
  final Future<DirectInboxCustodyCompletionOutcome> Function({
    required String recipientPeerId,
    required String messageId,
    required String expectedIncarnationId,
    required String expectedWireEnvelope,
    required int? relayExpiresAt,
  })?
  dbCompleteAcceptedDirectInboxCustodyIfExact;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  })?
  dbSettleOutgoingOrdinaryTransport;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  })?
  dbSettleOutgoingOrdinaryDeleteTombstone;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  })?
  dbInvalidateOutgoingOrdinaryEnvelope;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  })?
  dbQuarantineUnsafeLegacyOutgoingEnvelope;
  final Future<List<MediaAttachment>> Function(String messageId)?
  loadOutgoingOrdinaryMedia;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  })?
  dbInvalidateWireEnvelopeBeforePrivateUpload;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  })?
  dbMarkOutgoingDirectPrivateUploadHandoffFailed;
  final Future<OutgoingDirectPrivateEnvelopeHandoffOutcome> Function(
    Map<String, Object?> completionRow, {
    required String expectedPendingLocalPath,
    required String envelope,
    required bool hasOwnedPendingCompletion,
  })?
  dbCommitOutgoingDirectPrivateWireEnvelope;
  final Future<OutgoingDirectPrivateTransportSettlementOutcome> Function({
    required String messageId,
    required String? attachmentId,
    required String expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
  })?
  dbSettleOutgoingDirectPrivateTransport;
  final Future<bool> Function(
    Map<String, Object?> expectedRow,
    Map<String, Object?> tombstoneRow,
  )?
  dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone;
  final Future<bool> Function(
    Map<String, Object?> tombstoneRow, {
    required String? expectedEnvelope,
    required String envelope,
  })?
  dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope;
  final Future<bool> Function(
    Map<String, Object?> tombstoneRow, {
    required String expectedEnvelope,
  })?
  dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone;
  final Future<List<Map<String, Object?>>> Function({
    required DateTime olderThan,
    int limit,
  })
  dbLoadStuckSendingOutgoingMessages;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadSendingOutgoingMessages;
  final Future<int> Function(
    String id, {
    required String fromStatus,
    required String toStatus,
  })
  dbConditionalTransitionStatus;
  final Future<UploadRetryProjectionResult> Function({
    required String messageId,
    required String attachmentId,
    required UploadMediaDisposition disposition,
  })?
  dbProjectDirectUploadFailure;
  final Future<List<Map<String, Object?>>> Function({
    required Duration recheckOlderThan,
    int limit,
  })?
  dbLoadInboxCustodyOutgoingMessages;
  final Future<void> Function(String id, {int? relayExpiresAtMs})?
  dbMarkInboxCustodyChecked;
  final Future<int> Function(
    String id, {
    required int nowMs,
    bool? isIncoming,
    String? mode,
    String? attachmentId,
    String? storedLocalPath,
  })?
  dbClaimDirectPrivateMediaOpening;
  final Future<int> Function(
    String id, {
    required int nowMs,
    bool? isIncoming,
    String? mode,
    String? attachmentId,
    String? storedLocalPath,
  })?
  dbMarkDirectPrivateMediaViewing;
  final Future<int> Function(
    String id, {
    bool? isIncoming,
    String? mode,
    String? attachmentId,
    String? storedLocalPath,
  })?
  dbRollbackDirectPrivateMediaOpening;
  final Future<int> Function(
    String id, {
    required bool isIncoming,
    required String mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  })?
  dbQuarantineIndeterminateDirectPrivateMediaAvailable;
  final Future<int> Function(
    String id, {
    required int nowMs,
    bool? isIncoming,
    String? mode,
    String? attachmentId,
    String? storedLocalPath,
  })?
  dbConsumeDirectPrivateMedia;
  final Future<int> Function(String id, {required int nowMs})?
  dbAdvanceDirectPrivateMediaClock;
  final Future<int> Function(String id, {required int nowMs})?
  dbFailClosedCorruptDirectPrivateMediaState;
  final Future<int> Function(
    String id, {
    required String hiddenAt,
    required int nowMs,
  })?
  dbHideDirectPrivateMediaForMe;
  final Future<List<Map<String, Object?>>> Function({int limit})?
  dbLoadActiveDirectPrivateMediaDisappearing;
  final Future<List<Map<String, Object?>>> Function({int limit})?
  dbLoadDirectPrivateMediaRecoveryCandidates;
  final Future<int> Function(String id, {required int nowMs})?
  dbRotateDirectPrivateMediaRecoveryCandidate;
  final Future<int?> Function()? dbLoadNextDirectPrivateMediaExpiryAtMs;
  final DirectReactionNotificationProjection? directReactionProjection;
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadLocallyAuthoredMessagesForProjection;
  final Future<bool> Function({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  })?
  dbRearmDirectUploadRetryForManualRetry;
  final DateTime Function() now;
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();
  final StreamController<DirectMessageRemoval> _messageRemovalController =
      StreamController<DirectMessageRemoval>.broadcast(sync: true);
  // 194: conversation-level read-marking signal (peerId), emitted only when a
  // markConversationAsRead call actually flips >=1 row (INV-5).
  final StreamController<String> _conversationReadController =
      StreamController<String>.broadcast();
  final Map<String, ConversationMessage> _messageSnapshots = {};

  MessageRepositoryImpl({
    required this.dbInsertMessage,
    required this.dbLoadMessagesForContact,
    required this.dbLoadLatestMessageForContact,
    required this.dbUpdateMessageStatus,
    required this.dbLoadMessage,
    required this.dbCountMessagesForContact,
    required this.dbMarkConversationAsRead,
    this.projectConversationRead,
    required this.dbCountUnreadForContact,
    required this.dbCountTotalUnread,
    required this.dbCountTotalUnreadExcludingArchived,
    required this.dbDeleteMessagesForContact,
    required this.dbDeleteMessage,
    required this.dbExistsMessageByContent,
    this.dbExistsMessageByDedupKey,
    required this.dbLoadMessagesPage,
    required this.dbLoadFailedOutgoingMessages,
    required this.dbLoadUnackedOutgoingMessages,
    required this.dbLoadConversationThreadSummaries,
    required this.dbRecoverStuckSendingMessages,
    this.dbUpdateWireEnvelope,
    this.dbStageOutgoingOrdinaryAttempt,
    this.dbStageOutgoingDirectTextInboxCustody,
    this.dbLoadDirectInboxCustodyOutbox,
    this.dbLoadDirectInboxCustodyOutboxForMessage,
    this.dbLoadDirectInboxCustodyOutboxOwnerForMessageId,
    this.dbRecordDirectInboxCustodyFailureIfExact,
    this.dbCompleteAcceptedDirectInboxCustodyIfExact,
    this.dbSettleOutgoingOrdinaryTransport,
    this.dbSettleOutgoingOrdinaryDeleteTombstone,
    this.dbInvalidateOutgoingOrdinaryEnvelope,
    this.dbQuarantineUnsafeLegacyOutgoingEnvelope,
    this.loadOutgoingOrdinaryMedia,
    this.dbInvalidateWireEnvelopeBeforePrivateUpload,
    this.dbMarkOutgoingDirectPrivateUploadHandoffFailed,
    this.dbCommitOutgoingDirectPrivateWireEnvelope,
    this.dbSettleOutgoingDirectPrivateTransport,
    this.dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone,
    this.dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope,
    this.dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone,
    required this.dbLoadStuckSendingOutgoingMessages,
    required this.dbLoadSendingOutgoingMessages,
    required this.dbConditionalTransitionStatus,
    this.dbProjectDirectUploadFailure,
    this.dbLoadInboxCustodyOutgoingMessages,
    this.dbMarkInboxCustodyChecked,
    this.dbClaimDirectPrivateMediaOpening,
    this.dbMarkDirectPrivateMediaViewing,
    this.dbRollbackDirectPrivateMediaOpening,
    this.dbQuarantineIndeterminateDirectPrivateMediaAvailable,
    this.dbConsumeDirectPrivateMedia,
    this.dbAdvanceDirectPrivateMediaClock,
    this.dbFailClosedCorruptDirectPrivateMediaState,
    this.dbHideDirectPrivateMediaForMe,
    this.dbLoadActiveDirectPrivateMediaDisappearing,
    this.dbLoadDirectPrivateMediaRecoveryCandidates,
    this.dbRotateDirectPrivateMediaRecoveryCandidate,
    this.dbLoadNextDirectPrivateMediaExpiryAtMs,
    this.directReactionProjection,
    this.dbLoadLocallyAuthoredMessagesForProjection,
    this.dbRearmDirectUploadRetryForManualRetry,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  bool get supportsDirectTextInboxCustody =>
      dbStageOutgoingDirectTextInboxCustody != null &&
      dbLoadDirectInboxCustodyOutbox != null &&
      dbLoadDirectInboxCustodyOutboxForMessage != null &&
      dbLoadDirectInboxCustodyOutboxOwnerForMessageId != null &&
      dbRecordDirectInboxCustodyFailureIfExact != null &&
      dbCompleteAcceptedDirectInboxCustodyIfExact != null;

  @override
  Stream<DirectMessageRemoval> get messageRemovals =>
      _messageRemovalController.stream;

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_SAVE_START',
      details: {
        'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
      },
    );

    try {
      await dbInsertMessage(message.toMap());
      final committedRow = await dbLoadMessage(message.id);
      if (committedRow == null) {
        throw StateError('message save committed without a readable row');
      }
      final committed = _rememberMessage(
        ConversationMessage.fromMap(committedRow),
      );
      // `media` is a transient projection from the separate attachments table.
      // Never retain paths in the row snapshot cache: attachment deletion,
      // eviction, and private-media redaction are owned by a different
      // repository and therefore cannot invalidate this cache safely. The
      // initial ordinary outgoing save may still carry a validated, one-event
      // projection so an already-open conversation can render immediately.
      final saved = committed.copyWith(
        media: _validatedOutgoingSaveMedia(message),
      );
      await directReactionProjection?.upsertAuthoredTarget(committed);

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_SAVE_SUCCESS',
        details: {
          'id': message.id.length > 8 ? message.id.substring(0, 8) : message.id,
        },
      );
      _messageChangeController.add(saved);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final rows = await dbLoadMessagesForContact(contactPeerId);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final row = await dbLoadLatestMessageForContact(contactPeerId);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final updatedCount = await dbUpdateMessageStatus(id, status);
    if (updatedCount <= 0) return;
    final updated =
        _updatedMessageSnapshot(id, status) ??
        await _loadAndRememberMessage(id);
    if (updated != null) {
      _messageChangeController.add(updated);
    }
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async {
    final row = await dbLoadMessage(id);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_UPDATE_WIRE_ENVELOPE',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
    if (dbUpdateWireEnvelope != null) {
      await dbUpdateWireEnvelope!(id, envelope);
      // The generic DB helper deliberately refuses protected/view-once and
      // future-policy parents. Re-read instead of optimistically teaching the
      // cache that a refused write committed.
      await _loadAndRememberMessage(id);
    }
  }

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final stage = dbStageOutgoingOrdinaryAttempt;
    final outcome = stage == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await stage(
            expectedRow: expected?.toMap(),
            stagedRow: staged.toMap(),
            kind: kind,
          );
    return publishOutgoingOrdinaryMutation(
      messageId: staged.id,
      outcome: outcome,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingDirectTextInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String incarnationId,
    required String wireEnvelope,
  }) async {
    if (!supportsDirectTextInboxCustody) {
      return OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: expected,
      );
    }
    // Attachments are transient and intentionally absent from
    // ConversationMessage.toMap(). Reject them before crossing the database
    // seam so this text-only capability cannot accidentally stage media.
    if (staged.media.isNotEmpty) {
      return OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: expected,
      );
    }
    final stage = dbStageOutgoingDirectTextInboxCustody;
    final outcome = stage == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await stage(
            expectedRow: expected?.toMap(),
            stagedRow: staged.toMap(),
            kind: kind,
            recipientPeerId: recipientPeerId,
            messageId: staged.id,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          );
    final published = await _publishCommittedOutgoingOrdinaryMutationBestEffort(
      messageId: staged.id,
      outcome: outcome,
      committedFallback: outcome.authorizesTransport ? staged : null,
    );
    // The atomic helper outcome owns transport authority. A physical message
    // removal may win immediately after that transaction while the independent
    // custody row remains durable. The normal publisher truthfully reports the
    // now-missing projection as `removed`, but that post-commit observation must
    // not revoke the already-committed exact-envelope obligation.
    if (outcome.authorizesTransport && !published.authorizesTransport) {
      return OutgoingOrdinaryMutationResult(outcome: outcome, message: staged);
    }
    return published;
  }

  @override
  Future<List<DirectInboxCustodyOutboxEntry>> loadDirectInboxCustody({
    int limit = 50,
  }) async {
    final load = dbLoadDirectInboxCustodyOutbox;
    if (load == null) return const <DirectInboxCustodyOutboxEntry>[];
    return (await load(
      limit: limit,
    )).map(DirectInboxCustodyOutboxEntry.fromMap).toList(growable: false);
  }

  @override
  Future<DirectInboxCustodyOutboxEntry?> loadDirectInboxCustodyForMessage({
    required String recipientPeerId,
    required String messageId,
  }) async {
    final load = dbLoadDirectInboxCustodyOutboxForMessage;
    if (load == null) return null;
    final row = await load(
      recipientPeerId: recipientPeerId,
      messageId: messageId,
    );
    return row == null ? null : DirectInboxCustodyOutboxEntry.fromMap(row);
  }

  @override
  Future<DirectInboxCustodyOutboxEntry?>
  loadDirectInboxCustodyOwnerForMessageId({required String messageId}) async {
    final load = dbLoadDirectInboxCustodyOutboxOwnerForMessageId;
    if (load == null) return null;
    final row = await load(messageId: messageId);
    return row == null ? null : DirectInboxCustodyOutboxEntry.fromMap(row);
  }

  @override
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  }) {
    final record = dbRecordDirectInboxCustodyFailureIfExact;
    if (record == null) return Future<bool>.value(false);
    return record(
      recipientPeerId: expected.recipientPeerId,
      messageId: expected.messageId,
      expectedIncarnationId: expected.incarnationId,
      expectedWireEnvelope: expected.wireEnvelope,
      errorCode: errorCode,
      attemptedAt: now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) async {
    final complete = dbCompleteAcceptedDirectInboxCustodyIfExact;
    if (complete == null) {
      return const DirectInboxCustodyCompletionResult(
        outcome: DirectInboxCustodyCompletionOutcome.stale,
        message: null,
      );
    }
    final outcome = await complete(
      recipientPeerId: expected.recipientPeerId,
      messageId: expected.messageId,
      expectedIncarnationId: expected.incarnationId,
      expectedWireEnvelope: expected.wireEnvelope,
      relayExpiresAt: relayExpiresAt,
    );
    if (!outcome.completed) {
      return DirectInboxCustodyCompletionResult(
        outcome: outcome,
        message: null,
      );
    }
    if (outcome == DirectInboxCustodyCompletionOutcome.messageRemoved) {
      // The DB helper retains a hidden, scrubbed local tombstone so a delayed
      // generic save cannot recreate the physically removed parent. Keep that
      // internal authority out of the repository's visible completion result.
      _messageSnapshots.remove(expected.messageId);
      return DirectInboxCustodyCompletionResult(
        outcome: outcome,
        message: null,
      );
    }
    final published = await _publishCommittedOutgoingOrdinaryMutationBestEffort(
      messageId: expected.messageId,
      outcome: outcome.messageChanged
          ? OutgoingOrdinaryMutationOutcome.applied
          : OutgoingOrdinaryMutationOutcome.idempotent,
    );
    return DirectInboxCustodyCompletionResult(
      outcome: outcome,
      message: published.message,
    );
  }

  /// Publishes an already-returned ordinary DB mutation without letting
  /// fallible cache, media, reaction-projection, or stream work rewrite it.
  ///
  /// This helper is deliberately entered only after the atomic DB delegate has
  /// returned. Delegate failures still propagate to the caller. Once the DB
  /// outcome is known, publication is a best-effort notification boundary: a
  /// failed reload or projection cannot make committed transport look failed,
  /// committed custody look refused, or a retired exact row look retryable.
  Future<OutgoingOrdinaryMutationResult>
  _publishCommittedOutgoingOrdinaryMutationBestEffort({
    required String messageId,
    required OutgoingOrdinaryMutationOutcome outcome,
    ConversationMessage? committedFallback,
  }) async {
    try {
      return await publishOutgoingOrdinaryMutation(
        messageId: messageId,
        outcome: outcome,
      );
    } catch (error) {
      ConversationMessage? authoritativeFallback;
      var fallbackReloadCompleted = false;
      try {
        final row = await dbLoadMessage(messageId);
        fallbackReloadCompleted = true;
        if (row != null) {
          authoritativeFallback = ConversationMessage.fromMap(row);
        }
      } catch (_) {
        // The DB mutation already committed. A second diagnostic reload is
        // best-effort and must not replace that authoritative outcome either.
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'OUTGOING_ORDINARY_COMMITTED_PUBLICATION_ERROR',
        details: <String, Object?>{
          'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
          'outcome': outcome.name,
          'errorType': error.runtimeType.toString(),
        },
      );
      return OutgoingOrdinaryMutationResult(
        outcome: outcome,
        message: fallbackReloadCompleted
            ? authoritativeFallback
            : committedFallback,
      );
    }
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) async {
    final settle = dbSettleOutgoingOrdinaryTransport;
    final outcome = settle == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await settle(
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          );
    return _publishCommittedOutgoingOrdinaryMutationBestEffort(
      messageId: messageId,
      outcome: outcome,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  }) async {
    final settle = dbSettleOutgoingOrdinaryDeleteTombstone;
    final outcome = settle == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await settle(
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            status: status,
            transport: transport,
            relayExpiresAt: relayExpiresAt,
            mode: mode,
          );
    return publishOutgoingOrdinaryMutation(
      messageId: messageId,
      outcome: outcome,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  }) async {
    final invalidate = dbInvalidateOutgoingOrdinaryEnvelope;
    final outcome = invalidate == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await invalidate(
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
          );
    return publishOutgoingOrdinaryMutation(
      messageId: messageId,
      outcome: outcome,
    );
  }

  @override
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  }) async {
    final quarantine = dbQuarantineUnsafeLegacyOutgoingEnvelope;
    final outcome = quarantine == null
        ? OutgoingOrdinaryMutationOutcome.refused
        : await quarantine(
            messageId: messageId,
            expectedContactPeerId: expectedContactPeerId,
            expectedEnvelope: expectedEnvelope,
            isDeleteTombstone: isDeleteTombstone,
          );
    return publishOutgoingOrdinaryMutation(
      messageId: messageId,
      outcome: outcome,
    );
  }

  /// Shared authoritative publication boundary for text and combined-media
  /// ordinary mutations. MediaAttachmentRepositoryImpl calls this only after
  /// its parent-plus-media transaction has committed.
  Future<OutgoingOrdinaryMutationResult> publishOutgoingOrdinaryMutation({
    required String messageId,
    required OutgoingOrdinaryMutationOutcome outcome,
    List<MediaAttachment>? committedMedia,
  }) async {
    final row = await dbLoadMessage(messageId);
    if (row == null) {
      _messageSnapshots.remove(messageId);
      return OutgoingOrdinaryMutationResult(
        outcome: outcome == OutgoingOrdinaryMutationOutcome.applied
            ? OutgoingOrdinaryMutationOutcome.removed
            : outcome,
        message: null,
      );
    }

    final committed = _rememberMessage(ConversationMessage.fromMap(row));
    final media =
        committedMedia ??
        await loadOutgoingOrdinaryMedia?.call(messageId) ??
        const <MediaAttachment>[];
    final authoritative = committed.copyWith(
      media: media
          .where(
            (attachment) =>
                attachment.messageId == messageId &&
                (attachment.ownerLane == null ||
                    attachment.ownerLane == MediaOwnerLane.direct),
          )
          .map(
            (attachment) =>
                attachment.copyWith(ownerLane: MediaOwnerLane.direct),
          )
          .toList(growable: false),
    );
    if (outcome == OutgoingOrdinaryMutationOutcome.applied) {
      await directReactionProjection?.upsertAuthoredTarget(committed);
      _messageChangeController.add(authoritative);
    }
    return OutgoingOrdinaryMutationResult(
      outcome: outcome,
      message: authoritative,
    );
  }

  @override
  Future<bool> invalidateWireEnvelopeBeforePrivateUpload({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async {
    final invalidate = dbInvalidateWireEnvelopeBeforePrivateUpload;
    if (invalidate == null) return false;
    final changed = await invalidate(
      messageId: messageId,
      attachmentId: attachmentId,
      expectedPendingLocalPath: expectedPendingLocalPath,
    );
    if (changed) {
      final cached = _messageSnapshots[messageId];
      if (cached != null) {
        _rememberMessage(cached.copyWith(wireEnvelope: null));
      }
    }
    return changed;
  }

  @override
  Future<bool> markOutgoingDirectPrivateUploadHandoffFailed({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) async {
    final markFailed = dbMarkOutgoingDirectPrivateUploadHandoffFailed;
    if (markFailed == null) return false;
    final changed = await markFailed(
      messageId: messageId,
      attachmentId: attachmentId,
      expectedPendingLocalPath: expectedPendingLocalPath,
    );
    if (changed) await _loadAndRememberMessage(messageId);
    return changed;
  }

  @override
  Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>
  commitOutgoingDirectPrivateWireEnvelope({
    required String messageId,
    required MediaAttachment completedAttachment,
    required String expectedPendingLocalPath,
    required String envelope,
    required bool hasOwnedPendingCompletion,
  }) async {
    final commit = dbCommitOutgoingDirectPrivateWireEnvelope;
    if (commit == null ||
        messageId.isEmpty ||
        completedAttachment.messageId != messageId ||
        (completedAttachment.ownerLane != null &&
            completedAttachment.ownerLane != MediaOwnerLane.direct)) {
      return OutgoingDirectPrivateEnvelopeHandoffOutcome.refused;
    }
    final outcome = await commit(
      completedAttachment.copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
      expectedPendingLocalPath: expectedPendingLocalPath,
      envelope: envelope,
      hasOwnedPendingCompletion: hasOwnedPendingCompletion,
    );
    if (outcome.authorizesTransport) {
      // Preserve the DB's lifecycle/deletion truth in the repository cache.
      // This write owns only wire_envelope.
      await _loadAndRememberMessage(messageId);
    }
    return outcome;
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
  }) async {
    final settle = dbSettleOutgoingDirectPrivateTransport;
    if (settle == null) {
      return OutgoingDirectPrivateTransportSettlementOutcome.refused;
    }
    final outcome = await settle(
      messageId: messageId,
      attachmentId: attachmentId,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
    );
    final updated = await _loadAndRememberMessage(messageId);
    if (updated != null &&
        (outcome == OutgoingDirectPrivateTransportSettlementOutcome.committed ||
            outcome ==
                OutgoingDirectPrivateTransportSettlementOutcome
                    .preservedUserIntent)) {
      _messageChangeController.add(updated);
    }
    return outcome;
  }

  @override
  Future<ConversationMessage?> commitPrivateDeleteForEveryoneTombstone({
    required ConversationMessage expectedMessage,
    required ConversationMessage tombstone,
  }) async {
    final commit = dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone;
    if (commit == null ||
        expectedMessage.id != tombstone.id ||
        expectedMessage.contactPeerId != tombstone.contactPeerId ||
        expectedMessage.senderPeerId != tombstone.senderPeerId) {
      return null;
    }
    final committed = await commit(expectedMessage.toMap(), tombstone.toMap());
    if (!committed) return null;
    final current = await _loadAndRememberMessage(tombstone.id);
    if (!_isExactPrivateDeleteTombstone(current, tombstone)) return null;
    _messageChangeController.add(current!);
    return current;
  }

  @override
  Future<ConversationMessage?> stagePrivateDeleteForEveryoneRetryEnvelope({
    required ConversationMessage tombstone,
    required String? expectedEnvelope,
    required String envelope,
  }) async {
    final stage = dbStageOutgoingDirectPrivateDeleteForEveryoneRetryEnvelope;
    if (stage == null || envelope.isEmpty) return null;
    final staged = await stage(
      tombstone.toMap(),
      expectedEnvelope: expectedEnvelope,
      envelope: envelope,
    );
    if (!staged) return null;
    final current = await _loadAndRememberMessage(tombstone.id);
    if (!_isSamePrivateDeleteClaim(current, tombstone) ||
        current!.status != 'failed' ||
        current.wireEnvelope != envelope) {
      return null;
    }
    _messageChangeController.add(current);
    return current;
  }

  @override
  Future<ConversationMessage?> settlePrivateDeleteForEveryoneTombstone({
    required ConversationMessage tombstone,
    required String expectedEnvelope,
  }) async {
    final settle = dbSettleOutgoingDirectPrivateDeleteForEveryoneTombstone;
    if (settle == null || expectedEnvelope.isEmpty) return null;
    final settled = await settle(
      tombstone.toMap(),
      expectedEnvelope: expectedEnvelope,
    );
    if (!settled) return null;
    final current = await _loadAndRememberMessage(tombstone.id);
    if (!_isSamePrivateDeleteClaim(current, tombstone)) return null;
    _messageChangeController.add(current!);
    return current;
  }

  bool _isExactPrivateDeleteTombstone(
    ConversationMessage? current,
    ConversationMessage expected,
  ) =>
      _isSamePrivateDeleteClaim(current, expected) &&
      current!.text.isEmpty &&
      current.status == 'sending' &&
      current.wireEnvelope == expected.wireEnvelope;

  bool _isSamePrivateDeleteClaim(
    ConversationMessage? current,
    ConversationMessage expected,
  ) =>
      current != null &&
      !current.isIncoming &&
      current.id == expected.id &&
      current.contactPeerId == expected.contactPeerId &&
      current.senderPeerId == expected.senderPeerId &&
      current.privateMediaPolicy.version == 1 &&
      (current.privateMediaMode == PrivateMediaMode.protected ||
          current.privateMediaMode == PrivateMediaMode.viewOnce) &&
      current.deletedAt == expected.deletedAt &&
      current.deletedByPeerId == expected.deletedByPeerId;

  @override
  Future<bool> messageExists(String id) async {
    final row = await dbLoadMessage(id);
    if (row != null) {
      _rememberMessage(ConversationMessage.fromMap(row));
    }
    return row != null;
  }

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async {
    return dbExistsMessageByContent(
      contactPeerId,
      senderPeerId,
      text,
      timestamp,
    );
  }

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async {
    final fn = dbExistsMessageByDedupKey;
    if (fn == null) return false; // fail-open when tier-2 helper is unwired
    return fn(contactPeerId, senderPeerId, dedupKey);
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return dbCountMessagesForContact(contactPeerId);
  }

  @override
  Stream<String> get conversationReadStream =>
      _conversationReadController.stream;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_MARK_READ_START',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );
    final markedCount =
        await (projectConversationRead ?? dbMarkConversationAsRead)(
          contactPeerId,
        );
    // 194: fire the read-event only when something actually changed (INV-5) so a
    // re-mark of an already-read conversation stays silent.
    if (markedCount > 0) {
      _conversationReadController.add(contactPeerId);
    }
    return markedCount;
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    return dbCountUnreadForContact(contactPeerId);
  }

  @override
  Future<int> getTotalUnreadCount() async {
    return dbCountTotalUnread();
  }

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async {
    return dbCountTotalUnreadExcludingArchived();
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final rows = await dbLoadMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_START',
      details: {
        'contactPeerId': contactPeerId.length > 10
            ? contactPeerId.substring(0, 10)
            : contactPeerId,
      },
    );

    try {
      final count = await dbDeleteMessagesForContact(contactPeerId);
      if (count > 0) {
        _messageSnapshots.removeWhere(
          (_, message) => message.contactPeerId == contactPeerId,
        );
        _messageRemovalController.add(
          DirectMessageRemoval(contactPeerId: contactPeerId, messageId: null),
        );
        await directReactionProjection?.removeAuthoredTargetsForContact(
          contactPeerId,
        );
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_FOR_CONTACT_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<int> deleteMessage(String id) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MESSAGE_REPO_DELETE_START',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );

    try {
      final cached = _messageSnapshots[id];
      final previousRow = cached == null ? await dbLoadMessage(id) : null;
      final previous =
          cached ??
          (previousRow == null
              ? null
              : ConversationMessage.fromMap(previousRow));
      final count = await dbDeleteMessage(id);
      if (count > 0) {
        _messageSnapshots.remove(id);
        if (previous != null) {
          _messageRemovalController.add(
            DirectMessageRemoval(
              contactPeerId: previous.contactPeerId,
              messageId: id,
            ),
          );
        }
        await directReactionProjection?.removeAuthoredTarget(id);
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_DELETE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Launch-time self-healing backfill for locally-authored reaction targets.
  Future<void> mirrorAllDirectReactionAuthoredTargets() async {
    final projection = directReactionProjection;
    final loadRows = dbLoadLocallyAuthoredMessagesForProjection;
    if (projection == null || loadRows == null) return;
    try {
      final rows = await loadRows();
      await projection.replaceAuthoredTargets(
        rows.map(ConversationMessage.fromMap),
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MESSAGE_REPO_REACTION_PROJECTION_BACKFILL_ERROR',
        details: {'error': error.toString()},
      );
    }
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async {
    final rows = await dbLoadFailedOutgoingMessages();
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final rows = await dbLoadUnackedOutgoingMessages(olderThan: cutoff);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    return dbRecoverStuckSendingMessages(olderThan: cutoff);
  }

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    final project = dbProjectDirectUploadFailure;
    if (project == null) {
      return const UploadRetryProjectionResult.notApplied();
    }
    final result = await project(
      messageId: messageId,
      attachmentId: attachmentId,
      disposition: failure.disposition,
    );
    if (result.applied) {
      final updated = await _loadAndRememberMessage(messageId);
      if (updated != null) {
        _messageChangeController.add(updated);
      }
    }
    return result;
  }

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    final rearm = dbRearmDirectUploadRetryForManualRetry;
    if (rearm == null) return false;
    final applied = await rearm(messageId: messageId, attachments: attachments);
    if (applied) {
      final updated = await _loadAndRememberMessage(messageId);
      if (updated != null) {
        _messageChangeController.add(updated);
      }
    }
    return applied;
  }

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final rows = await dbLoadStuckSendingOutgoingMessages(olderThan: cutoff);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
    final rows = await dbLoadSendingOutgoingMessages();
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async {
    final count = await dbConditionalTransitionStatus(
      id,
      fromStatus: fromStatus,
      toStatus: toStatus,
    );
    if (count > 0) {
      final updated =
          _updatedMessageSnapshot(id, toStatus) ??
          await _loadAndRememberMessage(id);
      if (updated != null) {
        _messageChangeController.add(updated);
      }
    }
    return count;
  }

  Future<List<ConversationMessage>> getInboxCustodyOutgoingMessages({
    required Duration recheckOlderThan,
    int limit = 50,
  }) async {
    final loader = dbLoadInboxCustodyOutgoingMessages;
    if (loader == null) return const [];
    final rows = await loader(recheckOlderThan: recheckOlderThan, limit: limit);
    return _rememberMessages(
      rows.map((row) => ConversationMessage.fromMap(row)),
    );
  }

  Future<void> markInboxCustodyChecked(
    String id, {
    int? relayExpiresAtMs,
  }) async {
    final marker = dbMarkInboxCustodyChecked;
    if (marker == null) return;
    await marker(id, relayExpiresAtMs: relayExpiresAtMs);
    final updated = await _loadAndRememberMessage(id);
    if (updated != null) {
      _messageChangeController.add(updated);
    }
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) async {
    final summaries = await getConversationThreadSummaries([contactPeerId]);
    return summaries[contactPeerId] ??
        ConversationThreadSummary(contactPeerId: contactPeerId);
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    final ids = contactPeerIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const <String, ConversationThreadSummary>{};

    final rows = await dbLoadConversationThreadSummaries(ids);
    final summaries = <String, ConversationThreadSummary>{};
    for (final row in rows) {
      final contactPeerId = row['contact_peer_id'] as String;
      final lastOutgoingAtRaw = row['last_outgoing_at'] as String?;
      summaries[contactPeerId] = ConversationThreadSummary(
        contactPeerId: contactPeerId,
        messageCount: row['message_count'] as int? ?? 0,
        unreadCount: row['unread_count'] as int? ?? 0,
        lastOutgoingAt: lastOutgoingAtRaw == null
            ? null
            : DateTime.tryParse(lastOutgoingAtRaw),
        latestMessage: row['latest_id'] == null
            ? null
            : _rememberMessage(
                ConversationMessage.fromMap({
                  'id': row['latest_id'],
                  'contact_peer_id': row['latest_contact_peer_id'],
                  'sender_peer_id': row['latest_sender_peer_id'],
                  'text': row['latest_text'],
                  'timestamp': row['latest_timestamp'],
                  'status': row['latest_status'],
                  'is_incoming': row['latest_is_incoming'],
                  'created_at': row['latest_created_at'],
                  'edited_at': row['latest_edited_at'],
                  'read_at': row['latest_read_at'],
                  'quoted_message_id': row['latest_quoted_message_id'],
                  'deleted_at': row['latest_deleted_at'],
                  'deleted_by_peer_id': row['latest_deleted_by_peer_id'],
                  'hidden_at': row['latest_hidden_at'],
                  'transport': row['latest_transport'],
                  'wire_envelope': row['latest_wire_envelope'],
                }),
              ),
      );
    }
    for (final contactPeerId in ids) {
      summaries.putIfAbsent(
        contactPeerId,
        () => ConversationThreadSummary(contactPeerId: contactPeerId),
      );
    }
    return summaries;
  }

  T _requirePrivateLifecycleClosure<T>(T? closure, String name) {
    if (closure == null) {
      throw StateError(
        'Direct private-media lifecycle closure $name is not wired; '
        'conditional state changes fail closed',
      );
    }
    return closure;
  }

  Future<void> _emitPrivateLifecycleMutation(String id) async {
    final updated = await _loadAndRememberMessage(id);
    if (updated != null) _messageChangeController.add(updated);
  }

  /// Refresh hook for direct-private SQL transactions owned by the media
  /// repository. Emits only when the lifecycle snapshot changed; repeated
  /// ineligible writes against the same terminal parent do not duplicate the
  /// terminal change event.
  Future<void> refreshPrivateMediaLifecycleAfterExternalMutation(
    String messageId,
  ) async {
    final previous = _messageSnapshots[messageId];
    final row = await dbLoadMessage(messageId);
    if (row == null) return;
    final updated = ConversationMessage.fromMap(row);
    final changed = previous == null
        ? updated.privateMediaState.isTerminal ||
              updated.hiddenAt != null ||
              updated.deletedAt != null
        : previous.privateMediaPolicy != updated.privateMediaPolicy ||
              previous.privateMediaState != updated.privateMediaState ||
              previous.privateMediaReceivedAtMs !=
                  updated.privateMediaReceivedAtMs ||
              previous.privateMediaExpiresAtMs !=
                  updated.privateMediaExpiresAtMs ||
              previous.privateMediaRevealedAtMs !=
                  updated.privateMediaRevealedAtMs ||
              previous.privateMediaTerminalAtMs !=
                  updated.privateMediaTerminalAtMs ||
              previous.privateMediaClockHighWaterMs !=
                  updated.privateMediaClockHighWaterMs ||
              previous.hiddenAt != updated.hiddenAt ||
              previous.deletedAt != updated.deletedAt;
    _rememberMessage(updated);
    if (changed) _messageChangeController.add(updated);
  }

  @override
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  ) => getMessage(messageId);

  @override
  Future<bool> claimPrivateMediaOpening(
    String messageId, {
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbClaimDirectPrivateMediaOpening,
      'claimOpening',
    )(messageId, nowMs: nowMs),
  );

  @override
  Future<bool> claimExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbClaimDirectPrivateMediaOpening,
      'claimExactOpening',
    )(
      messageId,
      nowMs: nowMs,
      isIncoming: isIncoming,
      mode: mode.wireValue,
      attachmentId: attachmentId,
      storedLocalPath: storedLocalPath,
    ),
  );

  @override
  Future<bool> markPrivateMediaViewing(
    String messageId, {
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbMarkDirectPrivateMediaViewing,
      'markViewing',
    )(messageId, nowMs: nowMs),
  );

  @override
  Future<bool> markExactPrivateMediaViewing(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbMarkDirectPrivateMediaViewing,
      'markExactViewing',
    )(
      messageId,
      nowMs: nowMs,
      isIncoming: isIncoming,
      mode: mode.wireValue,
      attachmentId: attachmentId,
      storedLocalPath: storedLocalPath,
    ),
  );

  @override
  Future<bool> rollbackPrivateMediaOpening(String messageId) =>
      _runPrivateLifecycleMutation(
        messageId,
        _requirePrivateLifecycleClosure(
          dbRollbackDirectPrivateMediaOpening,
          'rollbackOpening',
        )(messageId),
      );

  @override
  Future<bool> rollbackExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbRollbackDirectPrivateMediaOpening,
      'rollbackExactOpening',
    )(
      messageId,
      isIncoming: isIncoming,
      mode: mode.wireValue,
      attachmentId: attachmentId,
      storedLocalPath: storedLocalPath,
    ),
  );

  @override
  Future<bool> quarantineIndeterminatePrivateMediaAvailable(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbQuarantineIndeterminateDirectPrivateMediaAvailable,
      'quarantineIndeterminateAvailable',
    )(
      messageId,
      isIncoming: isIncoming,
      mode: mode.wireValue,
      attachmentId: attachmentId,
      storedLocalPath: storedLocalPath,
      nowMs: nowMs,
    ),
  );

  @override
  Future<bool> consumePrivateMedia(String messageId, {required int nowMs}) =>
      _runPrivateLifecycleMutation(
        messageId,
        _requirePrivateLifecycleClosure(dbConsumeDirectPrivateMedia, 'consume')(
          messageId,
          nowMs: nowMs,
        ),
      );

  @override
  Future<bool> consumeExactPrivateMedia(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbConsumeDirectPrivateMedia,
      'consumeExact',
    )(
      messageId,
      nowMs: nowMs,
      isIncoming: isIncoming,
      mode: mode.wireValue,
      attachmentId: attachmentId,
      storedLocalPath: storedLocalPath,
    ),
  );

  @override
  Future<bool> advancePrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbAdvanceDirectPrivateMediaClock,
      'advanceClock',
    )(messageId, nowMs: nowMs),
  );

  @override
  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(
      dbFailClosedCorruptDirectPrivateMediaState,
      'failClosedCorruptState',
    )(messageId, nowMs: nowMs),
  );

  @override
  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  }) => _runPrivateLifecycleMutation(
    messageId,
    _requirePrivateLifecycleClosure(dbHideDirectPrivateMediaForMe, 'hideForMe')(
      messageId,
      hiddenAt: hiddenAt,
      nowMs: nowMs,
    ),
  );

  Future<bool> _runPrivateLifecycleMutation(
    String messageId,
    Future<int> mutation,
  ) async {
    final affected = await mutation;
    if (affected <= 0) return false;
    await _emitPrivateLifecycleMutation(messageId);
    return true;
  }

  @override
  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  }) async {
    final rows = await _requirePrivateLifecycleClosure(
      dbLoadActiveDirectPrivateMediaDisappearing,
      'loadActiveDisappearing',
    )(limit: limit);
    return _rememberMessages(rows.map(ConversationMessage.fromMap));
  }

  @override
  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) async {
    final rows = await _requirePrivateLifecycleClosure(
      dbLoadDirectPrivateMediaRecoveryCandidates,
      'loadRecoveryCandidates',
    )(limit: limit);
    return _rememberMessages(rows.map(ConversationMessage.fromMap));
  }

  @override
  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async {
    final affected = await _requirePrivateLifecycleClosure(
      dbRotateDirectPrivateMediaRecoveryCandidate,
      'rotateRecoveryCandidate',
    )(messageId, nowMs: nowMs);
    return affected > 0;
  }

  @override
  Future<int?> loadNextPrivateMediaExpiryAtMs() {
    return _requirePrivateLifecycleClosure(
      dbLoadNextDirectPrivateMediaExpiryAtMs,
      'loadNextExpiry',
    )();
  }

  ConversationMessage _rememberMessage(ConversationMessage message) {
    _messageSnapshots[message.id] = message;
    return message;
  }

  List<MediaAttachment> _validatedOutgoingSaveMedia(
    ConversationMessage message,
  ) {
    final media = message.media;
    if (media.isEmpty ||
        message.isIncoming ||
        message.isDeleted ||
        message.isHidden ||
        message.privateMediaPolicy.requiresRedaction ||
        media.any(
          (attachment) =>
              attachment.messageId != message.id ||
              attachment.ownerLane != MediaOwnerLane.direct,
        )) {
      return const <MediaAttachment>[];
    }
    return List<MediaAttachment>.unmodifiable(media);
  }

  List<ConversationMessage> _rememberMessages(
    Iterable<ConversationMessage> messages,
  ) {
    return messages.map(_rememberMessage).toList();
  }

  ConversationMessage? _updatedMessageSnapshot(String id, String status) {
    final cached = _messageSnapshots[id];
    if (cached == null) return null;
    return _rememberMessage(cached.copyWith(status: status));
  }

  Future<ConversationMessage?> _loadAndRememberMessage(String id) async {
    final row = await dbLoadMessage(id);
    if (row == null) return null;
    return _rememberMessage(ConversationMessage.fromMap(row));
  }
}
