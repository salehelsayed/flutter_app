import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/domain/utils/format_message_time.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/utils/group_message_ordering.dart';

/// Groups group messages into [GroupThreadFeedItem]s — one per group.
///
/// Includes both sent and received messages. Each group's messages are
/// sorted by timestamp. Derives [ConversationState] from read status and
/// direction across ALL messages for that group.
///
/// Messages for groups not found in [groups] are silently ignored.
///
/// Sorting: unread/active first (newest-first), then read/replied (newest-first).
///
/// When [unreadCounts] / [lastOutgoingAtByGroup] / [totalMessageCounts] carry
/// an entry for a group (161 db-persistence-5), the thread is treated as a
/// SUMMARY-BACKED windowed preview: its `unreadCount`, `conversationState`,
/// `hasSentMessage` / `lastRepliedAt` and `totalMessageCount` come from the
/// batched [GroupThreadPreview] instead of re-scanning the (windowed) message
/// list — so a truncated window cannot undercount unread or misclassify state
/// when an old reply is off the loaded window. Absent entries fall back to the
/// legacy full-list derivation, so the group SCREEN and existing callers are
/// unchanged. Mirrors `groupMessagesIntoThreads` (160) for the 1:1 feed.
List<GroupThreadFeedItem> groupGroupMessagesIntoThreads({
  required List<GroupMessage> allGroupMessages,
  required List<GroupModel> groups,
  Map<String, int> totalMessageCounts = const {},
  Map<String, int> unreadCounts = const {},
  Map<String, DateTime?> lastOutgoingAtByGroup = const {},
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
    final msgs = orderGroupMessagesForTimeline(entry.value);
    final group = groupMap[groupId]!;

    // 161 G3/G4: a summary-backed group derives counts + has-outgoing from the
    // batched GroupThreadPreview so a windowed slice cannot undercount unread or
    // false-negative hasSentMessage when the answering outgoing is off-window.
    // Absent → legacy full-list derivation.
    final bool summaryBacked = unreadCounts.containsKey(groupId);

    final bool hasUnreadIncoming;
    final bool hasSentMessages;
    final int unreadIncomingCount;
    DateTime? lastRepliedAt;
    if (summaryBacked) {
      unreadIncomingCount = unreadCounts[groupId] ?? 0;
      hasUnreadIncoming = unreadIncomingCount > 0;
      lastRepliedAt = lastOutgoingAtByGroup[groupId];
      hasSentMessages = lastRepliedAt != null;
    } else {
      hasUnreadIncoming = msgs.any((m) => m.isIncoming && m.readAt == null);
      hasSentMessages = msgs.any((m) => !m.isIncoming);
      unreadIncomingCount = msgs
          .where((m) => m.isIncoming && m.readAt == null)
          .length;
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
      isDissolved: group.isDissolved,
      avatarPath: group.avatarPath,
      avatarCacheBustKey:
          group.lastMetadataEventAt?.toUtc().toIso8601String() ??
          group.avatarBlobId,
      messages: threadMessages,
      unreadCount: unreadIncomingCount,
      conversationState: state,
      totalMessageCount: totalMessageCounts[groupId],
      lastRepliedAt: lastRepliedAt,
    );

    if (state == ConversationState.unread ||
        state == ConversationState.active) {
      aboveDivider.add(item);
    } else {
      belowDivider.add(item);
    }
  }

  // Sort each section newest-first
  aboveDivider.sort(_compareGroupThreadFeedItemsDescending);
  belowDivider.sort(_compareGroupThreadFeedItemsDescending);

  return [...aboveDivider, ...belowDivider];
}

int _compareGroupThreadFeedItemsDescending(
  GroupThreadFeedItem a,
  GroupThreadFeedItem b,
) {
  final timestampCompare = b.timestamp.compareTo(a.timestamp);
  if (timestampCompare != 0) return timestampCompare;
  return a.id.compareTo(b.id);
}
