import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// Splits a sorted list of messages into thread chunks based on time gaps.
///
/// Rules:
/// - A 24+ hour gap between consecutive messages creates a new thread.
/// - Messages less than [burstThreshold] apart are never split (burst protection).
/// - A "reply soft-close": if the last message before a gap is outgoing (sent),
///   and the next message after the gap is incoming, that's a natural thread boundary.
///
/// [sortedMessages] must be sorted by timestamp ASC.
List<List<ConversationMessage>> splitThreadByTimeGap(
  List<ConversationMessage> sortedMessages, {
  Duration gap = const Duration(hours: 24),
  Duration burstThreshold = const Duration(minutes: 5),
}) {
  if (sortedMessages.isEmpty) return [];
  if (sortedMessages.length == 1) return [sortedMessages];

  final List<List<ConversationMessage>> threads = [];
  List<ConversationMessage> current = [sortedMessages.first];

  for (var i = 1; i < sortedMessages.length; i++) {
    final prev = sortedMessages[i - 1];
    final curr = sortedMessages[i];

    final prevTime = DateTime.tryParse(prev.timestamp);
    final currTime = DateTime.tryParse(curr.timestamp);

    if (prevTime == null || currTime == null) {
      current.add(curr);
      continue;
    }

    final timeDiff = currTime.difference(prevTime);

    // Never split mid-burst
    if (timeDiff < burstThreshold) {
      current.add(curr);
      continue;
    }

    // Split on 4+ hour gap
    if (timeDiff >= gap) {
      threads.add(current);
      current = [curr];
      continue;
    }

    current.add(curr);
  }

  threads.add(current);
  return threads;
}
