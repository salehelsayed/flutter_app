import '../models/message_reaction.dart';

/// Repository interface for managing emoji reactions on messages.
abstract class ReactionRepository {
  /// Saves a reaction (upsert — replaces existing for same message+sender).
  Future<void> saveReaction(MessageReaction reaction);

  /// Retrieves all reactions for a message, ordered by timestamp ASC.
  Future<List<MessageReaction>> getReactionsForMessage(String messageId);

  /// Retrieves all reactions for multiple messages, grouped by message ID.
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
      List<String> messageIds);

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
