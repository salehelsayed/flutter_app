import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

enum ReactionChangeType { upserted, removed }

class ReactionChange {
  final ReactionChangeType type;
  final String messageId;
  final String senderPeerId;
  final MessageReaction? reaction;

  ReactionChange.upsert(MessageReaction reaction)
    : this._(
        type: ReactionChangeType.upserted,
        messageId: reaction.messageId,
        senderPeerId: reaction.senderPeerId,
        reaction: reaction,
      );

  ReactionChange.removed({required this.messageId, required this.senderPeerId})
    : type = ReactionChangeType.removed,
      reaction = null;

  const ReactionChange._({
    required this.type,
    required this.messageId,
    required this.senderPeerId,
    this.reaction,
  });
}
