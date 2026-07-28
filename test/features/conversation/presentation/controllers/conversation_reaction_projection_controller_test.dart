import 'dart:io';

import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/shared/widgets/conversation/conversation_reaction_projection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MessageReaction reaction({
    required String id,
    required String messageId,
    required String senderPeerId,
    required String emoji,
    String timestamp = '2026-07-28T10:00:00.000Z',
  }) {
    return MessageReaction(
      id: id,
      messageId: messageId,
      emoji: emoji,
      senderPeerId: senderPeerId,
      timestamp: timestamp,
      createdAt: timestamp,
    );
  }

  test(
    'incoming change replaces or removes one sender without touching siblings',
    () {
      final alice = reaction(
        id: 'alice-old',
        messageId: 'message-a',
        senderPeerId: 'alice',
        emoji: '👍',
      );
      final bob = reaction(
        id: 'bob',
        messageId: 'message-a',
        senderPeerId: 'bob',
        emoji: '❤️',
      );
      final charlie = reaction(
        id: 'charlie',
        messageId: 'message-b',
        senderPeerId: 'charlie',
        emoji: '😂',
      );
      final controller = ConversationReactionProjectionController(
        initialReactions: <String, List<MessageReaction>>{
          'message-a': <MessageReaction>[alice, bob],
          'message-b': <MessageReaction>[charlie],
        },
      );
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      final aliceReplacement = reaction(
        id: 'alice-new',
        messageId: 'message-a',
        senderPeerId: 'alice',
        emoji: '🔥',
      );
      expect(
        controller.applyChange(ReactionChange.upsert(aliceReplacement)),
        isTrue,
      );
      expect(notifications, 1);
      expect(
        controller
            .reactionsFor('message-a')
            .map((item) => '${item.senderPeerId}:${item.emoji}')
            .toList(),
        <String>['alice:🔥', 'bob:❤️'],
      );
      expect(controller.reactionsFor('message-b'), <MessageReaction>[charlie]);

      expect(
        controller.applyChange(
          ReactionChange.removed(messageId: 'message-a', senderPeerId: 'alice'),
        ),
        isTrue,
      );
      expect(notifications, 2);
      expect(controller.reactionsFor('message-a'), <MessageReaction>[bob]);
      expect(controller.reactionsFor('message-b'), <MessageReaction>[charlie]);

      expect(
        controller.applyChange(
          ReactionChange.removed(
            messageId: 'message-a',
            senderPeerId: 'nobody',
          ),
        ),
        isFalse,
      );
      expect(notifications, 2);

      expect(
        () => controller.reactions['message-a']!.add(alice),
        throwsUnsupportedError,
      );
      expect(
        () => controller.reactions['other'] = <MessageReaction>[],
        throwsUnsupportedError,
      );
    },
  );

  test('append placement preserves the current group projection order', () {
    final alice = reaction(
      id: 'alice-old',
      messageId: 'message-a',
      senderPeerId: 'alice',
      emoji: '👍',
    );
    final bob = reaction(
      id: 'bob',
      messageId: 'message-a',
      senderPeerId: 'bob',
      emoji: '❤️',
    );
    final replacement = reaction(
      id: 'alice-new',
      messageId: 'message-a',
      senderPeerId: 'alice',
      emoji: '🔥',
    );
    final controller = ConversationReactionProjectionController(
      initialReactions: <String, List<MessageReaction>>{
        'message-a': <MessageReaction>[alice, bob],
      },
    );
    addTearDown(controller.dispose);

    controller.applyChange(
      ReactionChange.upsert(replacement),
      upsertPlacement: ConversationReactionUpsertPlacement.append,
    );

    expect(
      controller
          .reactionsFor('message-a')
          .map((item) => item.senderPeerId)
          .toList(),
      <String>['bob', 'alice'],
    );
  });

  test(
    'semantic no-op publishes zero times and controller has no lane dependency',
    () {
      final original = reaction(
        id: 'stable-id',
        messageId: 'message-a',
        senderPeerId: 'alice',
        emoji: '👍',
      );
      final controller = ConversationReactionProjectionController(
        initialReactions: <String, List<MessageReaction>>{
          'message-a': <MessageReaction>[original],
        },
      );
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      final semanticClone = reaction(
        id: original.id,
        messageId: original.messageId,
        senderPeerId: original.senderPeerId,
        emoji: original.emoji,
      );
      expect(
        controller.replaceAll(<String, List<MessageReaction>>{
          'message-a': <MessageReaction>[semanticClone],
        }),
        isFalse,
      );
      expect(
        controller.applyChange(ReactionChange.upsert(semanticClone)),
        isFalse,
      );
      expect(notifications, 0);

      // MessageReaction.== compares only id. Projection equality must still
      // notice a changed emoji on the same durable row.
      final changedEmojiSameId = reaction(
        id: original.id,
        messageId: original.messageId,
        senderPeerId: original.senderPeerId,
        emoji: '🎉',
      );
      expect(
        controller.applyChange(ReactionChange.upsert(changedEmojiSameId)),
        isTrue,
      );
      expect(notifications, 1);
      expect(controller.reactionsFor('message-a').single.emoji, '🎉');

      final source = File(
        'lib/shared/widgets/conversation/'
        'conversation_reaction_projection_controller.dart',
      ).readAsStringSync();
      for (final forbidden in <String>[
        'conversation_wired.dart',
        'group_conversation_wired.dart',
        'ReactionRepository',
        'StreamSubscription',
        'BuildContext',
        'sendReaction',
        'removeReaction',
        'Bridge',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    },
  );
}
