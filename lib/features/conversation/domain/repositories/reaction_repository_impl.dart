import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/message_reaction.dart';
import 'reaction_repository.dart';

/// Implementation of ReactionRepository using database helper functions.
class ReactionRepositoryImpl implements ReactionRepository {
  final Future<void> Function(Map<String, Object?> row) dbInsertReaction;
  final Future<List<Map<String, Object?>>> Function(String messageId)
      dbLoadReactionsForMessage;
  final Future<List<Map<String, Object?>>> Function(List<String> messageIds)
      dbLoadReactionsForMessages;
  final Future<int> Function(String messageId, String senderPeerId)
      dbDeleteReaction;
  final Future<int> Function(String messageId) dbDeleteReactionsForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteReactionsForContact;

  ReactionRepositoryImpl({
    required this.dbInsertReaction,
    required this.dbLoadReactionsForMessage,
    required this.dbLoadReactionsForMessages,
    required this.dbDeleteReaction,
    required this.dbDeleteReactionsForMessage,
    required this.dbDeleteReactionsForContact,
  });

  @override
  Future<void> saveReaction(MessageReaction reaction) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'REACTION_REPO_SAVE_START',
      details: {
        'id': reaction.id.length > 8
            ? reaction.id.substring(0, 8)
            : reaction.id,
      },
    );

    try {
      await dbInsertReaction(reaction.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REPO_SAVE_SUCCESS',
        details: {
          'id': reaction.id.length > 8
              ? reaction.id.substring(0, 8)
              : reaction.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REACTION_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<MessageReaction>> getReactionsForMessage(
      String messageId) async {
    final rows = await dbLoadReactionsForMessage(messageId);
    return rows.map((row) => MessageReaction.fromMap(row)).toList();
  }

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadReactionsForMessages(messageIds);
    final Map<String, List<MessageReaction>> result = {};
    for (final row in rows) {
      final reaction = MessageReaction.fromMap(row);
      result.putIfAbsent(reaction.messageId, () => []).add(reaction);
    }
    return result;
  }

  @override
  Future<int> removeReaction(String messageId, String senderPeerId) async {
    return await dbDeleteReaction(messageId, senderPeerId);
  }

  @override
  Future<int> deleteReactionsForMessage(String messageId) async {
    return await dbDeleteReactionsForMessage(messageId);
  }

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    return await dbDeleteReactionsForContact(contactPeerId);
  }
}
