import '../models/group_message.dart';

/// Repository interface for managing group messages.
abstract class GroupMessageRepository {
  /// Saves a message to the database. Replaces if ID already exists.
  Future<void> saveMessage(GroupMessage message);

  /// Retrieves a page of messages for a group, ordered by timestamp ASC.
  ///
  /// Returns at most [limit] messages starting at [offset].
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  });

  /// Retrieves a single message by ID.
  Future<GroupMessage?> getMessage(String id);

  /// Retrieves the most recent message for a group.
  Future<GroupMessage?> getLatestMessage(String groupId);

  /// Updates the delivery status of a message.
  Future<void> updateMessageStatus(String id, String status);

  /// Returns the total number of messages in a group.
  Future<int> getMessageCount(String groupId);

  /// Returns the number of unread incoming messages in a group.
  Future<int> getUnreadCount(String groupId);

  /// Returns the total number of unread incoming messages across all groups.
  Future<int> getTotalUnreadCount();

  /// Marks all unread incoming messages in a group as read.
  Future<void> markAsRead(String groupId);

  /// Deletes a single message by ID.
  Future<void> deleteMessage(String id);

  /// Deletes all messages for a group. Returns the number of deleted messages.
  Future<int> deleteMessagesForGroup(String groupId);

  /// Returns true if a message with the same content already exists.
  Future<bool> existsByContent(
      String groupId, String senderPeerId, String text, DateTime timestamp);
}
