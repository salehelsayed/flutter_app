import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

/// Groups group messages into [GroupThreadFeedItem]s — one per group.
///
/// Includes both sent and received messages. Each group's messages are
/// sorted by timestamp. Derives [ConversationState] from read status and
/// direction across ALL messages for that group.
///
/// Messages for groups not found in [groups] are silently ignored.
///
/// Sorting: unread/active first (newest-first), then read/replied (newest-first).
List<GroupThreadFeedItem> groupGroupMessagesIntoThreads({
  required List<GroupMessage> allGroupMessages,
  required List<GroupModel> groups,
}) {
  if (allGroupMessages.isEmpty || groups.isEmpty) return [];

  // Build lookup map for groups
  final groupMap = <String, GroupModel>{for (final g in groups) g.id: g};

  // Group messages by groupId
  final Map<String, List<GroupMessage>> byGroup = {};
  for (final msg in allGroupMessages) {
    if (!groupMap.containsKey(msg.groupId)) continue;
    byGroup.putIfAbsent(msg.groupId, () => []).add(msg);
  }

  final List<GroupThreadFeedItem> aboveDivider = []; // unread + active
  final List<GroupThreadFeedItem> belowDivider = []; // read + replied

  for (final entry in byGroup.entries) {
    final groupId = entry.key;
    final msgs = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final group = groupMap[groupId]!;

    // Derive conversation state from ALL messages for this group
    final hasUnreadIncoming = msgs.any((m) => m.isIncoming && m.readAt == null);
    final hasSentMessages = msgs.any((m) => !m.isIncoming);
    final unreadIncomingCount = msgs
        .where((m) => m.isIncoming && m.readAt == null)
        .length;

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

    final latestTs = msgs.last.timestamp;

    final threadMessages = msgs
        .map(
          (m) => ThreadMessage(
            id: m.id,
            text: m.text,
            time: formatMessageTime(m.timestamp.toUtc().toIso8601String()),
            timestamp: m.timestamp,
            isUnread: m.isIncoming && m.readAt == null,
            isIncoming: m.isIncoming,
            status: m.isIncoming ? null : m.status,
            quotedMessageId: m.quotedMessageId,
            senderUsername: m.senderUsername,
            senderPeerId: m.senderPeerId,
            media: m.media,
          ),
        )
        .toList();

    final item = GroupThreadFeedItem(
      id: 'group_thread_$groupId',
      timestamp: latestTs,
      groupId: groupId,
      groupName: group.name,
      groupType: group.type,
      myRole: group.myRole,
      messages: threadMessages,
      unreadCount: unreadIncomingCount,
      conversationState: state,
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
