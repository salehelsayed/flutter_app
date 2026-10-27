import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// Ordinary replies to one Thought, across its recipients' conversations.
abstract interface class ThoughtReactionMessageRepository {
  Future<List<ConversationMessage>> loadThoughtReactionMessages(String postId);
}
