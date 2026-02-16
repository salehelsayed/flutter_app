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
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  );

  /// Retrieves the most recent message for a contact.
  ///
  /// Returns null if no messages exist for the contact.
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  );

  /// Updates the delivery status of a message.
  Future<void> updateMessageStatus(String id, String status);

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
}
