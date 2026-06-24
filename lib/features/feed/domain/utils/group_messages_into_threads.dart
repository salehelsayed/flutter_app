import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';

/// Groups messages into [ThreadFeedItem]s — one per contact.
///
/// Includes both sent and received messages. Each contact's messages are
/// sorted by timestamp. Derives [ConversationState] from read status and
/// direction across ALL messages for that contact.
///
/// Sorting: unread/active first (newest-first), then read/replied (newest-first).
/// When [unreadCounts] / [lastOutgoingAtByContact] / [totalMessageCounts]
/// carry an entry for a contact (160 A3/A4), the thread is treated as a
/// SUMMARY-BACKED windowed preview: its `unreadCount`, `conversationState`,
/// `hasReply`/`lastRepliedAt` and `totalMessageCount` are sourced from the
/// batched `ConversationThreadSummary` instead of re-scanning the (possibly
/// partial) [allMessages] window. Absent entries fall back to the legacy
/// full-list derivation, so the snapshot path and existing callers are
/// unchanged.
List<ThreadFeedItem> groupMessagesIntoThreads({
  required List<ConversationMessage> allMessages,
  required Map<String, String> contactUsernames,
  Map<String, bool> contactBlocked = const {},
  Map<String, int> totalMessageCounts = const {},
  Map<String, int> unreadCounts = const {},
  Map<String, DateTime?> lastOutgoingAtByContact = const {},
}) {
  // Filter out system messages (e.g. "Connected through X") from feed threads
  final filteredMessages = allMessages
      .where((m) => m.transport != 'system')
      .toList();
  if (filteredMessages.isEmpty) return [];

  // Group all messages by contact
  final Map<String, List<ConversationMessage>> byContact = {};
  for (final msg in filteredMessages) {
    byContact.putIfAbsent(msg.contactPeerId, () => []).add(msg);
  }

  final List<ThreadFeedItem> aboveDivider = []; // unread + active
  final List<ThreadFeedItem> belowDivider = []; // read + replied

  for (final entry in byContact.entries) {
    final peerId = entry.key;
    final msgs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final username = contactUsernames[peerId] ?? 'Unknown';

    // 160 A3/A4: a summary-backed contact derives counts + has-outgoing from the
    // batched ConversationThreadSummary so a windowed slice cannot undercount
    // unread or false-negative hasReply when the answering outgoing is off the
    // window. Absent → legacy full-list derivation.
    final bool summaryBacked = unreadCounts.containsKey(peerId);

    final bool hasUnreadIncoming;
    final bool hasSentMessages;
    final int unreadIncomingCount;
    DateTime? lastRepliedAt;
    if (summaryBacked) {
      unreadIncomingCount = unreadCounts[peerId] ?? 0;
      hasUnreadIncoming = unreadIncomingCount > 0;
      lastRepliedAt = lastOutgoingAtByContact[peerId];
      hasSentMessages = lastRepliedAt != null;
    } else {
      hasUnreadIncoming = msgs.any(
        (m) => !m.isDeleted && m.isIncoming && m.readAt == null,
      );
      hasSentMessages = msgs.any((m) => !m.isIncoming && !m.isDeleted);
      unreadIncomingCount = msgs
          .where((m) => !m.isDeleted && m.isIncoming && m.readAt == null)
          .length;
      if (hasSentMessages) {
        final sentMessages = msgs
            .where((m) => !m.isIncoming && !m.isDeleted)
            .toList();
        sentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        lastRepliedAt = DateTime.tryParse(sentMessages.last.timestamp);
      }
    }

    final ConversationState state;
    if (hasUnreadIncoming && hasSentMessages) {
      state = ConversationState.active;
    } else if (hasUnreadIncoming) {
      state = ConversationState.unread;
    } else if (hasSentMessages) {
      state = ConversationState.replied;
    } else {
      state = ConversationState.read;
    }

    final latestTs = DateTime.tryParse(msgs.last.timestamp) ?? DateTime.now();

    final threadMessages = msgs
        .map(
          (m) => ThreadMessage(
            id: m.id,
            text: m.text,
            time: formatMessageTime(m.timestamp),
            timestamp: DateTime.tryParse(m.timestamp) ?? DateTime.now(),
            isUnread: !m.isDeleted && m.isIncoming && m.readAt == null,
            isIncoming: m.isIncoming,
            isDeleted: m.isDeleted,
            status: m.isIncoming ? null : m.status,
            editedAt: m.editedAt,
            quotedMessageId: m.quotedMessageId,
            media: m.media,
          ),
        )
        .toList();

    final item = ThreadFeedItem(
      id: 'thread_$peerId',
      timestamp: latestTs,
      contactPeerId: peerId,
      contactUsername: username,
      unreadCount: unreadIncomingCount,
      isUnreadCard:
          state == ConversationState.unread ||
          state == ConversationState.active,
      conversationState: state,
      lastRepliedAt: lastRepliedAt,
      messages: threadMessages,
      isBlocked: contactBlocked[peerId] ?? false,
      totalMessageCount: totalMessageCounts[peerId],
    );

    if (state == ConversationState.unread ||
        state == ConversationState.active) {
      aboveDivider.add(item);
    } else {
      belowDivider.add(item);
    }
  }

  // Sort each section newest-first
  aboveDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  belowDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return [...aboveDivider, ...belowDivider];
}
