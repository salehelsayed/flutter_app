import 'group_message.dart';

class GroupThreadSummary {
  final String groupId;
  final int unreadCount;
  final GroupMessage? latestMessage;

  const GroupThreadSummary({
    required this.groupId,
    this.unreadCount = 0,
    this.latestMessage,
  });
}
