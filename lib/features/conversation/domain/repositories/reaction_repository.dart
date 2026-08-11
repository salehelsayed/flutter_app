import '../models/message_reaction.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import '../models/direct_reaction_inbox_custody_outbox_entry.dart';

/// Result of atomically applying an incoming ADD event.
enum ReactionAddApplyResult {
  /// No reaction existed for this message/sender pair.
  inserted,

  /// A distinct, newer ADD replaced the previous state.
  updated,

  /// This exact event id was already applied.
  exactReplay,

  /// A newer ADD or REMOVE is already authoritative.
  stale,
}

/// Result of atomically applying an incoming REMOVE event.
enum ReactionRemoveApplyResult {
  /// The REMOVE became authoritative (including a remove-before-add tombstone).
  applied,

  /// This exact REMOVE event was already applied.
  exactReplay,

  /// A newer ADD or REMOVE is already authoritative.
  stale,
}

/// Repository interface for managing emoji reactions on messages.
abstract class ReactionRepository {
  /// Saves a reaction (upsert — replaces existing for same message+sender).
  Future<void> saveReaction(MessageReaction reaction);

  /// Applies an incoming ADD as one serialized read/compare/write decision.
  ///
  /// Implementations backed by a database should override this with their
  /// atomic primitive. The default keeps alternate fakes/source-compatible;
  /// it is deliberately expressed in terms of the existing repository API.
  Future<ReactionAddApplyResult> applyIncomingAdd(
    MessageReaction reaction,
  ) async {
    final current = await getReactionForSenderIncludingRemoved(
      messageId: reaction.messageId,
      senderPeerId: reaction.senderPeerId,
    );
    if (_incomingReactionIsOlder(reaction, current)) {
      return ReactionAddApplyResult.stale;
    }
    if (current?.id == reaction.id &&
        current?.isRemoved == false &&
        current?.timestamp == reaction.timestamp) {
      return ReactionAddApplyResult.exactReplay;
    }
    await saveReaction(reaction);
    return current == null
        ? ReactionAddApplyResult.inserted
        : ReactionAddApplyResult.updated;
  }

  /// Retrieves all reactions for a message, ordered by timestamp ASC.
  Future<List<MessageReaction>> getReactionsForMessage(String messageId);

  /// Retrieves all reactions for multiple messages, grouped by message ID.
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
    List<String> messageIds,
  );

  /// Retrieves the single reaction for (message, sender) INCLUDING a tombstoned
  /// (removed) one, for the last-writer-wins comparand. Returns null if none.
  Future<MessageReaction?> getReactionForSenderIncludingRemoved({
    required String messageId,
    required String senderPeerId,
  });

  /// Removes (tombstones) a reaction for a specific message and sender, stamping
  /// [removedAtTimestamp] (the remove's sender-authored timestamp) so a later
  /// stale add can be dropped. Returns the number of rows affected.
  Future<int> removeReaction(
    String messageId,
    String senderPeerId, {
    String? removedAtTimestamp,
  });

  /// Deletes all reactions for a message. Returns count.
  Future<int> deleteReactionsForMessage(String messageId);

  /// Deletes all reactions for a contact. Returns count.
  Future<int> deleteReactionsForContact(String contactPeerId);
}

/// Optional capability for repositories that can apply an incoming REMOVE as
/// one atomic compare/write decision. Keeping this separate preserves source
/// compatibility for lightweight repositories that implement
/// [ReactionRepository] directly.
abstract interface class AtomicIncomingReactionMutationRepository {
  Future<ReactionRemoveApplyResult> applyIncomingRemove(
    MessageReaction reaction,
  );
}

/// Optional group-owned ADD capability. The explicit [groupId] and
/// [notificationEventId] bind a staged display marker to the exact incoming
/// transition while the canonical reaction comparand is decided atomically.
/// A stale decision must retire only that exact staged marker.
abstract interface class AtomicGroupReactionAdditionRepository {
  Future<ReactionAddApplyResult> applyGroupAdd({
    required String groupId,
    required String notificationEventId,
    required MessageReaction reaction,
  });
}

/// Optional group-owned REMOVE capability. Implementations use the explicit
/// [groupId] to tombstone the canonical reaction and retire any notification
/// display custody for the same actor in one database transaction.
///
/// The explicit lane discriminator is required because direct and group
/// message ids may collide, while a REMOVE payload has a different identity
/// from the ADD transition whose display marker must be retired.
abstract interface class AtomicGroupReactionRemovalRepository {
  Future<ReactionRemoveApplyResult> applyGroupRemove({
    required String groupId,
    required MessageReaction reaction,
  });
}

/// Optional, fail-closed authority for newly authored direct-reaction inbox
/// custody. It stays beside [ReactionRepository] so incoming/group-only fakes
/// do not acquire sender-custody methods.
abstract interface class OutgoingDirectReactionInboxCustodyRepository {
  /// True only when the complete atomic stage/drain/completion surface is
  /// configured. An authored direct reaction must fail closed when false.
  bool get supportsDirectReactionInboxCustody;

  /// Commits the canonical ADD/REMOVE projection and immutable encrypted event
  /// in one transaction before any live or inbox work.
  Future<DirectReactionCustodyStageResult>
  stageOutgoingDirectReactionInboxCustody({
    required MessageReaction reaction,
    required String recipientPeerId,
    required String action,
    required String wireEnvelope,
  });

  /// Loads at most 50 rows in fair retry order. Storage clamps larger limits.
  Future<List<DirectReactionInboxCustodyOutboxEntry>>
  loadDirectReactionInboxCustody({int limit = 50});

  /// Loads one exact recipient/event tuple, or null when it has converged.
  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectReactionInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  });

  /// Records one retained failure only while [expected]'s exact bytes own the
  /// recipient/event tuple.
  Future<bool> recordDirectReactionInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  });

  /// Retires an accepted exact event. Concurrent absence is convergence;
  /// envelope replacement is stale and must not be deleted.
  Future<DirectReactionInboxCustodyCompletionOutcome>
  completeAcceptedDirectReactionInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
  });
}

/// 361: optional fail-closed authority for linked-transport reaction applies.
/// The physical transport re-authorizes to the logical sender INSIDE the
/// durable apply transaction.
abstract interface class LinkedTransportReactionApplyRepository {
  bool get supportsLinkedTransportReactionApply;

  Future<ReactionAddApplyResult> applyIncomingAddWithTransportAuthority(
    MessageReaction reaction, {
    required String authenticatedTransportPeerId,
  });

  Future<ReactionRemoveApplyResult> applyIncomingRemoveWithTransportAuthority(
    MessageReaction reaction, {
    required String authenticatedTransportPeerId,
  });
}

/// 361: optional fail-closed authority for v113 blob-free reaction fanout.
abstract interface class OutgoingDirectReactionEventFanoutRepository {
  bool get supportsDirectReactionEventFanout;

  Future<DbDirectEventFanoutStageResult> stageDirectReactionFanout({
    required Map<String, Object?> reactionRow,
    required String action,
    required String parentMessageId,
    required String contactAccountPeerId,
    required String senderTransportPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
    required List<DirectEventFanoutTargetCandidate> candidates,
  });
}

bool _incomingReactionIsOlder(
  MessageReaction incoming,
  MessageReaction? current,
) {
  if (current == null) return false;
  final incomingAt = DateTime.tryParse(incoming.timestamp);
  final currentAt = DateTime.tryParse(current.removedAt ?? current.timestamp);
  return incomingAt != null &&
      currentAt != null &&
      incomingAt.isBefore(currentAt);
}
