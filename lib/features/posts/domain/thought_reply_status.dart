import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

typedef ThoughtReplySender =
    Future<ThoughtReplyStatus> Function(
      String text,
      String postId,
      String messageId,
    );

enum ThoughtReplyStatus {
  sent,
  queued,
  failed;

  static ThoughtReplyStatus fromMessage(ConversationMessage message) {
    if (message.isDeleted || message.isHidden) return failed;
    return switch (message.status) {
      'delivered' || 'read' || 'inboxed' => sent,
      'failed' => failed,
      _ => queued,
    };
  }
}
