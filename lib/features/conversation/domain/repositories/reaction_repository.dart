import '../models/message_reaction.dart';

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
