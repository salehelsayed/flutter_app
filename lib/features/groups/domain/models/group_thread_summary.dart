import 'group_message.dart';

class GroupThreadSummary {
  final String groupId;
  final int unreadCount;

  /// Newest incoming message timestamp, excluding membership cutoff rows.
  /// Independent of the latest message used for conversation previews.
  final DateTime? lastIncomingAt;
  final GroupMessage? latestMessage;

  const GroupThreadSummary({
    required this.groupId,
    this.unreadCount = 0,
    this.lastIncomingAt,
    this.latestMessage,
  });
}
