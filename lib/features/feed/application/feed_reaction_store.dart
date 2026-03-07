import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';

class FeedReactionStore {
  final Map<String, ValueNotifier<List<MessageReaction>>> _notifiers = {};

  ValueListenable<List<MessageReaction>> listenableForMessage(
    String messageId,
  ) {
    return _notifierFor(messageId);
  }

  List<MessageReaction> reactionsForMessage(String messageId) {
    return _notifiers[messageId]?.value ?? const <MessageReaction>[];
  }

  void replaceAll(Map<String, List<MessageReaction>> reactionsByMessageId) {
    final allMessageIds = {..._notifiers.keys, ...reactionsByMessageId.keys};
    for (final messageId in allMessageIds) {
      _setMessageReactions(
        messageId,
        reactionsByMessageId[messageId] ?? const [],
      );
    }
  }

  void replaceForMessageIds(
    Iterable<String> messageIds,
    Map<String, List<MessageReaction>> reactionsByMessageId,
  ) {
    for (final messageId in messageIds.toSet()) {
      _setMessageReactions(
        messageId,
        reactionsByMessageId[messageId] ?? const [],
      );
    }
  }

  void clearMessageIds(Iterable<String> messageIds) {
    for (final messageId in messageIds.toSet()) {
      if (_notifiers.containsKey(messageId)) {
        _setMessageReactions(messageId, const []);
      }
    }
  }

  void setMessageReactions(String messageId, List<MessageReaction> reactions) {
    _setMessageReactions(messageId, reactions);
  }

  void applyChange(ReactionChange change) {
    final current = List<MessageReaction>.from(
      reactionsForMessage(change.messageId),
    );

    if (change.type == ReactionChangeType.removed) {
      current.removeWhere(
        (reaction) => reaction.senderPeerId == change.senderPeerId,
      );
      _setMessageReactions(change.messageId, current);
      return;
    }

    final reaction = change.reaction;
    if (reaction == null) return;

    final index = current.indexWhere(
      (existing) => existing.senderPeerId == reaction.senderPeerId,
    );
    if (index >= 0) {
      current[index] = reaction;
    } else {
      current.add(reaction);
    }
    _setMessageReactions(change.messageId, current);
  }

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
  }

  ValueNotifier<List<MessageReaction>> _notifierFor(String messageId) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<List<MessageReaction>>(const []),
    );
  }

  void _setMessageReactions(String messageId, List<MessageReaction> reactions) {
    final notifier = _notifierFor(messageId);
    notifier.value = List<MessageReaction>.unmodifiable(reactions);
  }
}
