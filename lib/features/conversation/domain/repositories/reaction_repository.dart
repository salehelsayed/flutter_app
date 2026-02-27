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

  /// Removes a reaction for a specific message and sender. Returns count.
  Future<int> removeReaction(String messageId, String senderPeerId);

  /// Deletes all reactions for a message. Returns count.
  Future<int> deleteReactionsForMessage(String messageId);

  /// Deletes all reactions for a contact. Returns count.
  Future<int> deleteReactionsForContact(String contactPeerId);
}
