import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// In-memory fake of ReactionRepository for unit tests.
class FakeReactionRepository implements ReactionRepository {
  final List<MessageReaction> _reactions = [];

  int saveReactionCallCount = 0;
  MessageReaction? lastSavedReaction;
  int removeReactionCallCount = 0;

  /// All reactions currently stored.
  List<MessageReaction> get reactions => List.unmodifiable(_reactions);

  @override
  Future<void> saveReaction(MessageReaction reaction) async {
    saveReactionCallCount++;
    lastSavedReaction = reaction;

    // Upsert: remove existing for same message + sender
    _reactions.removeWhere((r) =>
        r.messageId == reaction.messageId &&
        r.senderPeerId == reaction.senderPeerId);
    _reactions.add(reaction);
  }

  @override
  Future<List<MessageReaction>> getReactionsForMessage(
      String messageId) async {
    return _reactions
        .where((r) => r.messageId == messageId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
      List<String> messageIds) async {
    final ids = messageIds.toSet();
    final Map<String, List<MessageReaction>> result = {};
    for (final r in _reactions) {
      if (ids.contains(r.messageId)) {
        result.putIfAbsent(r.messageId, () => []).add(r);
      }
    }
    return result;
  }

  @override
  Future<int> removeReaction(String messageId, String senderPeerId) async {
    removeReactionCallCount++;
    final before = _reactions.length;
    _reactions.removeWhere(
        (r) => r.messageId == messageId && r.senderPeerId == senderPeerId);
    return before - _reactions.length;
  }

  @override
  Future<int> deleteReactionsForMessage(String messageId) async {
    final before = _reactions.length;
    _reactions.removeWhere((r) => r.messageId == messageId);
    return before - _reactions.length;
  }

  @override
  Future<int> deleteReactionsForContact(String contactPeerId) async {
    // In tests, we don't have messages table, so this is a no-op
    return 0;
  }
}
