import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';

/// Groups incoming messages into [ThreadFeedItem]s by contact and read session.
///
/// Each contact can have multiple stacks in the feed:
/// - One **unread** stack (messages not yet read, with badge)
/// - One stack per **read session** (messages read at the same time stay
///   together — `markConversationAsRead` sets identical `readAt` values)
///
/// Unread stacks sort first (newest-first), then read stacks (newest-first).
List<ThreadFeedItem> groupMessagesIntoThreads({
  required List<ConversationMessage> allMessages,
  required Map<String, String> contactUsernames,
}) {
  final incoming = allMessages.where((m) => m.isIncoming).toList();
  if (incoming.isEmpty) return [];

  // Separate unread and read
  final unread = incoming.where((m) => m.readAt == null).toList();
  final read = incoming.where((m) => m.readAt != null).toList();

  final List<ThreadFeedItem> unreadCards = [];
  final List<ThreadFeedItem> readCards = [];

  // --- Unread: group by contact ---
  final Map<String, List<ConversationMessage>> unreadByContact = {};
  for (final msg in unread) {
    unreadByContact.putIfAbsent(msg.contactPeerId, () => []).add(msg);
  }

  for (final entry in unreadByContact.entries) {
    final peerId = entry.key;
    final msgs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final username = contactUsernames[peerId] ?? 'Unknown';
    final latestTs =
        DateTime.tryParse(msgs.last.timestamp) ?? DateTime.now();

    unreadCards.add(ThreadFeedItem(
      id: 'thread_unread_$peerId',
      timestamp: latestTs,
      contactPeerId: peerId,
      contactUsername: username,
      unreadCount: msgs.length,
      isUnreadCard: true,
      messages: msgs
          .map((m) => ThreadMessage(
                id: m.id,
                text: m.text,
                time: formatMessageTime(m.timestamp),
                timestamp:
                    DateTime.tryParse(m.timestamp) ?? DateTime.now(),
                isUnread: true,
              ))
          .toList(),
    ));
  }

  // --- Read: group by (contact, readAt) to preserve read-session stacks ---
  final Map<String, List<ConversationMessage>> readGroups = {};
  for (final msg in read) {
    // Key = contactPeerId + readAt timestamp
    final key = '${msg.contactPeerId}::${msg.readAt}';
    readGroups.putIfAbsent(key, () => []).add(msg);
  }

  for (final entry in readGroups.entries) {
    final msgs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final peerId = msgs.first.contactPeerId;
    final username = contactUsernames[peerId] ?? 'Unknown';
    final latestTs =
        DateTime.tryParse(msgs.last.timestamp) ?? DateTime.now();
    // Use readAt in the id so each session gets a unique card
    final readAt = msgs.first.readAt!;

    readCards.add(ThreadFeedItem(
      id: 'thread_read_${peerId}_$readAt',
      timestamp: latestTs,
      contactPeerId: peerId,
      contactUsername: username,
      unreadCount: 0,
      isUnreadCard: false,
      messages: msgs
          .map((m) => ThreadMessage(
                id: m.id,
                text: m.text,
                time: formatMessageTime(m.timestamp),
                timestamp:
                    DateTime.tryParse(m.timestamp) ?? DateTime.now(),
                isUnread: false,
              ))
          .toList(),
    ));
  }

  // Sort each section newest-first
  unreadCards.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  readCards.sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return [...unreadCards, ...readCards];
}
