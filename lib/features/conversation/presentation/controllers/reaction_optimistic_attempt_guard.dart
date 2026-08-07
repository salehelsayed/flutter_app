import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

/// Identifies one optimistic reaction mutation without serializing taps.
class ReactionOptimisticAttempt {
  const ReactionOptimisticAttempt({
    required this.messageId,
    required this.generation,
  });

  final String messageId;
  final int generation;

  String get optimisticReactionId => 'optimistic-reaction-$generation';
}

/// Prevents a delayed ADD completion from replacing newer visible intent.
class ReactionOptimisticAttemptGuard {
  int _nextGeneration = 0;
  final Map<String, int> _latestGenerationByMessage = <String, int>{};

  ReactionOptimisticAttempt begin(String messageId) {
    final attempt = ReactionOptimisticAttempt(
      messageId: messageId,
      generation: ++_nextGeneration,
    );
    _latestGenerationByMessage[messageId] = attempt.generation;
    return attempt;
  }

  bool canAdopt({
    required ReactionOptimisticAttempt attempt,
    required String senderPeerId,
    required Iterable<MessageReaction> visibleReactions,
  }) {
    if (_latestGenerationByMessage[attempt.messageId] != attempt.generation) {
      return false;
    }
    return visibleReactions.any(
      (reaction) =>
          reaction.senderPeerId == senderPeerId &&
          reaction.id == attempt.optimisticReactionId,
    );
  }
}
