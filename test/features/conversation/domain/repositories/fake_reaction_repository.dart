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
    // Tombstoned (removed) reactions are hidden from UI loaders (INV-T1).
    return _reactions
        .where((r) => r.messageId == messageId && r.removedAt == null)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  @override
  Future<Map<String, List<MessageReaction>>> getReactionsForMessages(
      List<String> messageIds) async {
    final ids = messageIds.toSet();
    final Map<String, List<MessageReaction>> result = {};
    for (final r in _reactions) {
      if (ids.contains(r.messageId) && r.removedAt == null) {
        result.putIfAbsent(r.messageId, () => []).add(r);
      }
    }
    return result;
  }

  @override
  Future<MessageReaction?> getReactionForSenderIncludingRemoved({
    required String messageId,
    required String senderPeerId,
  }) async {
    for (final r in _reactions) {
      if (r.messageId == messageId && r.senderPeerId == senderPeerId) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<int> removeReaction(
    String messageId,
    String senderPeerId, {
    String? removedAtTimestamp,
  }) async {
    removeReactionCallCount++;
    // Soft-delete: tombstone the existing row in place (INV-T1).
    final removedAt =
        removedAtTimestamp ?? DateTime.now().toUtc().toIso8601String();
    var affected = 0;
    for (var i = 0; i < _reactions.length; i++) {
      final r = _reactions[i];
      if (r.messageId == messageId && r.senderPeerId == senderPeerId) {
        _reactions[i] = r.copyWith(removedAt: removedAt);
        affected++;
      }
    }
    return affected;
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
