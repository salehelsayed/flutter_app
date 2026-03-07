import 'conversation_message.dart';

class ConversationThreadSummary {
  final String contactPeerId;
  final int messageCount;
  final int unreadCount;
  final ConversationMessage? latestMessage;

  const ConversationThreadSummary({
    required this.contactPeerId,
    this.messageCount = 0,
    this.unreadCount = 0,
    this.latestMessage,
  });
}
