import 'dart:async';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/conversation_message.dart';
import '../models/conversation_thread_summary.dart';
import '../models/media_attachment.dart';
import 'conversation_thread_summary_repository.dart';
import 'direct_private_media_lifecycle_repository.dart';
import 'message_repository.dart';

/// Implementation of MessageRepository using database helper functions.
class MessageRepositoryImpl
    implements
        MessageRepository,
        DirectPrivateMediaLifecycleRepository,
        DirectPrivateMediaExactOpeningLeaseRepository,
        DirectPrivateMediaIndeterminateQuarantineRepository,
        ConversationThreadSummaryRepository,
        DirectUploadRetryProjectionRepository,
        DirectManualUploadRetryRearmRepository,
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
  });

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

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
      final cached = _messageSnapshots[id];
      if (cached != null) {
        _rememberMessage(cached.copyWith(wireEnvelope: envelope));
      }
    }
  }

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
    final markedCount = await dbMarkConversationAsRead(contactPeerId);
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
