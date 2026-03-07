import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/feed/application/feed_reaction_store.dart';

MessageReaction _reaction({
  required String id,
  required String messageId,
  required String emoji,
  required String senderPeerId,
}) {
  return MessageReaction(
    id: id,
    messageId: messageId,
    emoji: emoji,
    senderPeerId: senderPeerId,
    timestamp: '2026-02-01T10:00:00.000Z',
    createdAt: '2026-02-01T10:00:00.000Z',
  );
}

void main() {
  group('FeedReactionStore', () {
    test('applyChange updates only the targeted message notifier', () {
      final store = FeedReactionStore();

      store.replaceAll({
        'msg-1': [
          _reaction(
            id: 'r1',
            messageId: 'msg-1',
            emoji: '👍',
            senderPeerId: 'peer-A',
          ),
        ],
        'msg-2': [
          _reaction(
            id: 'r2',
            messageId: 'msg-2',
            emoji: '🔥',
            senderPeerId: 'peer-B',
          ),
        ],
      });

      final msg1 = store.listenableForMessage('msg-1');
      final msg2 = store.listenableForMessage('msg-2');

      var msg1Notifications = 0;
      var msg2Notifications = 0;
      msg1.addListener(() => msg1Notifications++);
      msg2.addListener(() => msg2Notifications++);

      store.applyChange(
        ReactionChange.removed(messageId: 'msg-1', senderPeerId: 'peer-A'),
      );

      expect(msg1.value, isEmpty);
      expect(msg2.value.single.emoji, '🔥');
      expect(msg1Notifications, 1);
      expect(msg2Notifications, 0);

      store.applyChange(
        ReactionChange.upsert(
          _reaction(
            id: 'r3',
            messageId: 'msg-2',
            emoji: '❤️',
            senderPeerId: 'peer-C',
          ),
        ),
      );

      expect(
        msg2.value.map((reaction) => reaction.emoji),
        containsAll(['🔥', '❤️']),
      );
      expect(msg1Notifications, 1);
      expect(msg2Notifications, 1);
    });
  });
}
