import 'conversation_message.dart';

class ConversationThreadSummary {
  final String contactPeerId;
  final int messageCount;
  final int unreadCount;

  /// Timestamp of the newest non-deleted OUTGOING message in the thread, or
  /// null when the thread has no outgoing reply. Lets the feed derive
  /// `hasReply` / `conversationState` / `lastRepliedAt` from the summary rather
  /// than scanning a windowed message slice (where an old reply may be off the
  /// loaded window). Sourced from the `MAX(CASE WHEN is_incoming = 0 …)`
  /// aggregate in `dbLoadConversationThreadSummaries` (160 A0).
  final DateTime? lastOutgoingAt;

  final ConversationMessage? latestMessage;

  const ConversationThreadSummary({
    required this.contactPeerId,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.lastOutgoingAt,
    this.latestMessage,
  });
}
