import '../models/group_message.dart';

int compareGroupMessagesAscending(GroupMessage a, GroupMessage b) {
  final timestampCompare = a.timestamp.compareTo(b.timestamp);
  if (timestampCompare != 0) return timestampCompare;
  return a.id.compareTo(b.id);
}

int compareGroupMessagesDescending(GroupMessage a, GroupMessage b) {
  final timestampCompare = b.timestamp.compareTo(a.timestamp);
  if (timestampCompare != 0) return timestampCompare;
  return b.id.compareTo(a.id);
}

List<GroupMessage> orderGroupMessagesForTimeline(
  Iterable<GroupMessage> messages,
) {
  final sorted = messages.toList()..sort(compareGroupMessagesAscending);
  if (sorted.length < 2) return sorted;

  final byId = <String, GroupMessage>{
    for (final message in sorted) message.id: message,
  };
  final ordered = <GroupMessage>[];
  final placed = <String>{};

  while (ordered.length < sorted.length) {
    var madeProgress = false;

    for (final message in sorted) {
      if (placed.contains(message.id)) continue;

      final quotedMessageId = message.quotedMessageId;
      final parent = quotedMessageId == null || quotedMessageId.isEmpty
          ? null
          : byId[quotedMessageId];
      if (parent != null &&
          parent.groupId == message.groupId &&
          !placed.contains(parent.id)) {
        continue;
      }

      placed.add(message.id);
      ordered.add(message);
      madeProgress = true;
    }

    if (!madeProgress) {
      for (final message in sorted) {
        if (placed.add(message.id)) ordered.add(message);
      }
    }
  }

  return ordered;
}
