import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/feed/domain/utils/split_thread_by_time_gap.dart';

/// Groups messages into [ThreadFeedItem]s by contact and 24-hour time gap.
///
/// Includes both sent and received messages. Each contact's messages are
/// sorted by timestamp and split into thread chunks using [splitThreadByTimeGap].
/// For each chunk, derives [ConversationState] from read status and direction.
///
/// Sorting: unread/active first (newest-first), then read/replied (newest-first).
List<ThreadFeedItem> groupMessagesIntoThreads({
  required List<ConversationMessage> allMessages,
  required Map<String, String> contactUsernames,
  Map<String, bool> contactBlocked = const {},
}) {
  if (allMessages.isEmpty) return [];

  // Group all messages by contact
  final Map<String, List<ConversationMessage>> byContact = {};
  for (final msg in allMessages) {
    byContact.putIfAbsent(msg.contactPeerId, () => []).add(msg);
  }

  final List<ThreadFeedItem> aboveDivider = []; // unread + active
  final List<ThreadFeedItem> belowDivider = []; // read + replied

  for (final entry in byContact.entries) {
    final peerId = entry.key;
    final msgs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final username = contactUsernames[peerId] ?? 'Unknown';

    // Split into thread chunks by 24-hour gap
    final chunks = splitThreadByTimeGap(msgs);

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      final chunk = chunks[chunkIndex];
      if (chunk.isEmpty) continue;

      // Derive conversation state
      final hasUnreadIncoming = chunk.any((m) => m.isIncoming && m.readAt == null);
      final hasSentMessages = chunk.any((m) => !m.isIncoming);
      final unreadIncomingCount =
          chunk.where((m) => m.isIncoming && m.readAt == null).length;

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

      // Find last replied timestamp
      DateTime? lastRepliedAt;
      if (hasSentMessages) {
        final sentMessages = chunk.where((m) => !m.isIncoming).toList();
        sentMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        lastRepliedAt =
            DateTime.tryParse(sentMessages.last.timestamp);
      }

      final latestTs =
          DateTime.tryParse(chunk.last.timestamp) ?? DateTime.now();

      final threadMessages = chunk
          .map((m) => ThreadMessage(
                id: m.id,
                text: m.text,
                time: formatMessageTime(m.timestamp),
                timestamp:
                    DateTime.tryParse(m.timestamp) ?? DateTime.now(),
                isUnread: m.isIncoming && m.readAt == null,
                isIncoming: m.isIncoming,
                status: m.isIncoming ? null : m.status,
                quotedMessageId: m.quotedMessageId,
              ))
          .toList();

      final item = ThreadFeedItem(
        id: 'thread_${peerId}_$chunkIndex',
        timestamp: latestTs,
        contactPeerId: peerId,
        contactUsername: username,
        unreadCount: unreadIncomingCount,
        isUnreadCard: state == ConversationState.unread ||
            state == ConversationState.active,
        conversationState: state,
        lastRepliedAt: lastRepliedAt,
        messages: threadMessages,
        isBlocked: contactBlocked[peerId] ?? false,
      );

      if (state == ConversationState.unread ||
          state == ConversationState.active) {
        aboveDivider.add(item);
      } else {
        belowDivider.add(item);
      }
    }
  }

  // Sort each section newest-first
  aboveDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  belowDivider.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return [...aboveDivider, ...belowDivider];
}
