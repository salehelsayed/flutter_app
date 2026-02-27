import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// Loads reactions for a list of message IDs, grouped by message ID.
///
/// Returns an empty map if no message IDs provided.
Future<Map<String, List<MessageReaction>>> loadReactionsForConversation({
  required ReactionRepository reactionRepo,
  required List<String> messageIds,
}) async {
  if (messageIds.isEmpty) return {};

  emitFlowEvent(
    layer: 'FL',
    event: 'LOAD_REACTIONS_START',
    details: {'messageCount': messageIds.length},
  );

  final result = await reactionRepo.getReactionsForMessages(messageIds);

  emitFlowEvent(
    layer: 'FL',
    event: 'LOAD_REACTIONS_SUCCESS',
    details: {
      'messageCount': messageIds.length,
      'reactionCount': result.values.fold<int>(0, (sum, list) => sum + list.length),
    },
  );

  return result;
}
