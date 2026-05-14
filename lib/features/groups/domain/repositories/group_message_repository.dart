import '../models/group_message.dart';
import '../models/group_message_receipt.dart';

const groupRemovalCutoffMessageIdPrefix = 'sys-member_removed_cutoff';

bool isGroupRemovalCutoffMessageId(String id) =>
    id.startsWith('$groupRemovalCutoffMessageIdPrefix:');

String buildGroupRemovalCutoffMessageId({
  required String groupId,
  required String senderPeerId,
  required DateTime removedAt,
}) {
  return '$groupRemovalCutoffMessageIdPrefix:'
      '$groupId:$senderPeerId:${removedAt.toUtc().microsecondsSinceEpoch}';
}

/// Repository interface for managing group messages.
abstract class GroupMessageRepository {
  /// Saves a message to the database. Replaces if ID already exists.
  Future<void> saveMessage(GroupMessage message);

  /// Retrieves a page of messages for a group in deterministic timeline order.
  ///
  /// Unrelated messages are ordered by timestamp ASC, id ASC. Quoted replies
  /// are placed after their quoted parent when both rows are loaded.
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

  /// Transitions all outgoing messages with status='sending' to status='failed'.
  Future<int> transitionSendingToFailed();

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
    String groupId,
    String senderPeerId,
    String text,
    DateTime timestamp,
  );

  /// Returns true if a message with the given ID already exists.
  Future<bool> existsByMessageId(String messageId);

  /// Returns the latest persisted synthetic removal-event timestamp for the
  /// given sender in this group, if one exists.
  ///
  /// Implementations may override this for indexed lookups. The default keeps
  /// compatibility for lightweight test doubles that do not need this query.
  Future<DateTime?> getLatestRemovalTimestampForSender(
    String groupId,
    String senderPeerId,
  ) async => null;

  /// Returns the latest persisted synthetic system-event timestamp for a
  /// deterministic target row, if one exists.
  Future<DateTime?> getLatestSystemEventTimestampForTarget(
    String groupId, {
    required String eventType,
    required String targetId,
  }) async {
    final prefix = 'sys-$eventType:$groupId:$targetId:';
    const pageSize = 500;
    var offset = 0;
    DateTime? latest;
    while (true) {
      final page = await getMessagesPage(
        groupId,
        limit: pageSize,
        offset: offset,
      );
      for (final message in page) {
        if (!message.id.startsWith(prefix)) {
          continue;
        }
        final timestamp = message.timestamp.toUtc();
        if (latest == null || timestamp.isAfter(latest)) {
          latest = timestamp;
        }
      }
      if (page.length < pageSize) {
        break;
      }
      offset += page.length;
    }
    return latest;
  }

  /// Retrieves all outgoing messages with status='failed'.
  ///
  /// Used by the retry service to find messages that need re-sending.
  Future<List<GroupMessage>> getFailedOutgoingMessages();

  /// Transitions all outgoing messages with status='sending' that are older
  /// than [olderThan] to status='failed', so the retry service picks them up.
  ///
  /// Returns the count of rows updated.
  Future<int> recoverStuckSendingMessages({required Duration olderThan});

  /// Loads outgoing messages where inbox store failed and retry payload exists.
  ///
  /// Returns messages with `is_incoming = 0`, `inbox_stored = 0`,
  /// `status IN ('sent', 'pending')`, and `inbox_retry_payload IS NOT NULL`.
  Future<List<GroupMessage>> getMessagesWithFailedInboxStore({int limit = 20});

  /// Updates the inbox_stored flag for a message.
  Future<void> updateInboxStored(String id, {required bool stored});

  /// Updates (or clears) the inbox_retry_payload for a message.
  Future<void> updateInboxRetryPayload(String id, String? payload);

  /// Updates (or clears) the wire_envelope for a message.
  Future<void> updateWireEnvelope(String id, String? envelope);

  /// Loads the durable group inbox cursor for the next replay request.
  Future<String?> getInboxCursor(String groupId) async => null;

  /// Loads durable group message receipts for a message.
  Future<List<GroupMessageReceipt>> getReceiptsForMessage(
    String groupId,
    String messageId, {
    String? receiptType,
  }) async => const [];

  /// Runs inbox page application through one repository-owned transaction.
  ///
  /// Implementations without durable transaction support fall back to applying
  /// through this repository and do not advance durable cursor/receipt state.
  Future<void> runInboxPageTransaction({
    required String groupId,
    required String nextCursor,
    required Future<void> Function(GroupMessageRepository transactionRepo)
    apply,
    List<GroupMessageReceipt> receipts = const [],
    List<String> markReadMessageIds = const [],
  }) async {
    await apply(this);
  }
}
