import '../models/conversation_message.dart';

/// Repository interface for managing conversation messages.
abstract class MessageRepository {
  /// Saves a message to the database.
  ///
  /// If a message with the same ID exists, it will be replaced.
  Future<void> saveMessage(ConversationMessage message);

  /// Retrieves all messages for a contact, ordered by timestamp ASC.
  ///
  /// Returns an empty list if no messages exist.
  Future<List<ConversationMessage>> getMessagesForContact(String contactPeerId);

  /// Retrieves the most recent message for a contact.
  ///
  /// Returns null if no messages exist for the contact.
  Future<ConversationMessage?> getLatestMessageForContact(String contactPeerId);

  /// Updates the delivery status of a message.
  Future<void> updateMessageStatus(String id, String status);

  /// Retrieves a single message by ID.
  ///
  /// Returns null if no message with the given ID exists.
  Future<ConversationMessage?> getMessage(String id);

  /// Checks if a message with the given ID exists.
  Future<bool> messageExists(String id);

  /// Returns the total number of messages for a contact.
  Future<int> getMessageCountForContact(String contactPeerId);

  /// Marks all unread incoming messages for a contact as read.
  Future<int> markConversationAsRead(String contactPeerId);

  /// Returns the number of unread incoming messages for a contact.
  Future<int> getUnreadCountForContact(String contactPeerId);

  /// Returns the total number of unread incoming messages across all contacts.
  Future<int> getTotalUnreadCount();

  /// Returns the total unread count excluding archived contacts.
  Future<int> getTotalUnreadCountExcludingArchived();

  /// Deletes all messages for a contact. Returns the count of deleted rows.
  Future<int> deleteMessagesForContact(String contactPeerId);

  /// Deletes a single message by ID. Returns the count of deleted rows.
  Future<int> deleteMessage(String id);

  /// Retrieves all outgoing messages with status='failed'.
  ///
  /// Used by the retry service to find messages that need re-sending.
  Future<List<ConversationMessage>> getFailedOutgoingMessages();

  /// Retrieves all outgoing messages with status='sending'.
  ///
  /// Used by the pause handler to mark in-flight messages as failed
  /// before the OS freezes the process.
  Future<List<ConversationMessage>> getSendingOutgoingMessages();

  /// Transitions a message's status only if its current status matches [fromStatus].
  ///
  /// Returns the number of rows updated (0 if the row already advanced past
  /// [fromStatus], e.g., a concurrent send completed 'sending' -> 'delivered'
  /// before the pause handler could transition it to 'failed').
  ///
  /// Implementations MUST also emit on [MessageRepositoryChangeSource.messageChanges]
  /// when a row is successfully updated, so open UI screens react.
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  });

  /// Retrieves outgoing messages with status='sent' and a non-null wire_envelope
  /// that are older than [olderThan].
  ///
  /// These are messages written to the stream but not ACK'd by the peer.
  /// Used by the unacked retry service to store them in the relay inbox.
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  });

  /// Transitions all outgoing messages with status='sending' that are older
  /// than [olderThan] to status='failed', so the retry service picks them up.
  ///
  /// Returns the count of rows updated.
  Future<int> recoverStuckSendingMessages({required Duration olderThan});

  /// Updates the wire_envelope column for a message by ID.
  ///
  /// Used by sendChatMessage to persist the serialized envelope before the
  /// transport race, so a crash during the race leaves a retryable DB row.
  Future<void> updateWireEnvelope(String id, String envelope);

  /// Retrieves outgoing messages with status='sending' that are older than
  /// [olderThan] and have not yet been transitioned by [recoverStuckSendingMessages].
  ///
  /// NOTE: Currently unused by production code -- the retrier goes through
  /// recoverStuckSendingMessages -> retryFailedMessages instead. Kept as a
  /// diagnostic hook and for potential future recovery strategies.
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  });

  /// Retrieves a page of messages for a contact, ordered by timestamp ASC.
  ///
  /// Returns at most [limit] messages. When [beforeTimestamp] is null,
  /// returns the most recent page. When provided, returns messages older
  /// than that cursor.
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  });
}

/// Optional change stream for repository-backed message mutations.
///
/// Screens can use this to react to background status changes, such as retry
/// success, without polling or reloading the full conversation/feed snapshot.
abstract class MessageRepositoryChangeSource {
  Stream<ConversationMessage> get messageChanges;
}
