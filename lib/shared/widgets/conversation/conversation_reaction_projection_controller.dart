import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';

/// Controls where an updated sender stays in a message's reaction projection.
///
/// Direct conversation currently preserves the sender's existing slot, while
/// group conversation removes and appends that sender. The adapter chooses the
/// projection behavior without moving any lane policy into this controller.
enum ConversationReactionUpsertPlacement { preserveExistingIndex, append }

/// Owns the immutable reaction projection consumed by conversation screens.
///
/// Durable loads, stream admission, subscriptions, optimistic result policy,
/// and transport all stay in the direct/group adapters.
class ConversationReactionProjectionController extends ChangeNotifier {
  ConversationReactionProjectionController({
    Map<String, List<MessageReaction>> initialReactions =
        const <String, List<MessageReaction>>{},
  }) : _reactions = _freezeProjection(initialReactions);

  Map<String, List<MessageReaction>> _reactions;

  /// Deeply immutable map and message lists.
  Map<String, List<MessageReaction>> get reactions => _reactions;

  List<MessageReaction> reactionsFor(String messageId) =>
      _reactions[messageId] ?? const <MessageReaction>[];

  bool replaceAll(Map<String, List<MessageReaction>> reactions) {
    final next = _freezeProjection(reactions);
    if (_projectionsEqual(_reactions, next)) return false;
    _reactions = next;
    notifyListeners();
    return true;
  }

  bool replaceForMessage(
    String messageId,
    Iterable<MessageReaction> reactions,
  ) {
    final next = Map<String, List<MessageReaction>>.from(_reactions)
      ..[messageId] = List<MessageReaction>.unmodifiable(reactions);
    return replaceAll(next);
  }

  /// Applies the common one-reaction-per-sender projection reducer.
  bool applyChange(
    ReactionChange change, {
    ConversationReactionUpsertPlacement upsertPlacement =
        ConversationReactionUpsertPlacement.preserveExistingIndex,
  }) {
    final current = reactionsFor(change.messageId);
    final existingIndex = current.indexWhere(
      (reaction) => reaction.senderPeerId == change.senderPeerId,
    );

    if (change.type == ReactionChangeType.removed) {
      if (existingIndex < 0) return false;
      final next = List<MessageReaction>.from(current)..removeAt(existingIndex);
      return replaceForMessage(change.messageId, next);
    }

    final incoming = change.reaction;
    if (incoming == null) return false;
    if (existingIndex >= 0 &&
        _reactionSemanticallyEqual(current[existingIndex], incoming)) {
      return false;
    }

    final next = List<MessageReaction>.from(current);
    if (existingIndex < 0) {
      next.add(incoming);
    } else if (upsertPlacement == ConversationReactionUpsertPlacement.append) {
      next
        ..removeAt(existingIndex)
        ..add(incoming);
    } else {
      next[existingIndex] = incoming;
    }
    return replaceForMessage(change.messageId, next);
  }

  bool clear() => replaceAll(const <String, List<MessageReaction>>{});
}

Map<String, List<MessageReaction>> _freezeProjection(
  Map<String, List<MessageReaction>> reactions,
) {
  return Map<String, List<MessageReaction>>.unmodifiable({
    for (final entry in reactions.entries)
      entry.key: List<MessageReaction>.unmodifiable(entry.value),
  });
}

bool _projectionsEqual(
  Map<String, List<MessageReaction>> left,
  Map<String, List<MessageReaction>> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final rightReactions = right[entry.key];
    if (rightReactions == null ||
        !_reactionListsEqual(entry.value, rightReactions)) {
      return false;
    }
  }
  return true;
}

bool _reactionListsEqual(
  List<MessageReaction> left,
  List<MessageReaction> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (!_reactionSemanticallyEqual(left[index], right[index])) return false;
  }
  return true;
}

bool _reactionSemanticallyEqual(MessageReaction left, MessageReaction right) {
  return left.id == right.id &&
      left.messageId == right.messageId &&
      left.emoji == right.emoji &&
      left.senderPeerId == right.senderPeerId &&
      left.timestamp == right.timestamp &&
      left.createdAt == right.createdAt &&
      left.removedAt == right.removedAt;
}
