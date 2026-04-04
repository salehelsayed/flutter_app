import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

bool isOutgoingDeletedTombstone(ConversationMessage message) {
  return !message.isIncoming && message.isDeleted;
}

ConversationMessage normalizeOutgoingDeleteTombstoneVisibility(
  ConversationMessage message,
) {
  if (!isOutgoingDeletedTombstone(message)) {
    return message;
  }

  final hiddenAt = message.status == 'delivered' ? message.deletedAt : null;
  if (message.hiddenAt == hiddenAt) {
    return message;
  }

  return message.copyWith(hiddenAt: hiddenAt);
}
