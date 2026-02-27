import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/load_reactions_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';

import '../domain/repositories/fake_reaction_repository.dart';

void main() {
  late FakeReactionRepository reactionRepo;

  setUp(() {
    reactionRepo = FakeReactionRepository();
  });

  group('loadReactionsForConversation', () {
    test('returns empty map for empty messageIds', () async {
      final result = await loadReactionsForConversation(
        reactionRepo: reactionRepo,
        messageIds: [],
      );
      expect(result, isEmpty);
    });

    test('returns empty map when no reactions exist', () async {
      final result = await loadReactionsForConversation(
        reactionRepo: reactionRepo,
        messageIds: ['msg-1', 'msg-2'],
      );
      expect(result, isEmpty);
    });

    test('returns reactions grouped by messageId', () async {
      await reactionRepo.saveReaction(const MessageReaction(
        id: 'r1',
        messageId: 'msg-1',
        emoji: '👍',
        senderPeerId: 'sender-1',
        timestamp: '2026-02-27T10:00:00.000Z',
        createdAt: '2026-02-27T10:00:01.000Z',
      ));
      await reactionRepo.saveReaction(const MessageReaction(
        id: 'r2',
        messageId: 'msg-1',
        emoji: '❤️',
        senderPeerId: 'sender-2',
        timestamp: '2026-02-27T10:01:00.000Z',
        createdAt: '2026-02-27T10:01:01.000Z',
      ));
      await reactionRepo.saveReaction(const MessageReaction(
        id: 'r3',
        messageId: 'msg-2',
        emoji: '😂',
        senderPeerId: 'sender-1',
        timestamp: '2026-02-27T10:02:00.000Z',
        createdAt: '2026-02-27T10:02:01.000Z',
      ));

      final result = await loadReactionsForConversation(
        reactionRepo: reactionRepo,
        messageIds: ['msg-1', 'msg-2'],
      );

      expect(result.keys, containsAll(['msg-1', 'msg-2']));
      expect(result['msg-1']!.length, 2);
      expect(result['msg-2']!.length, 1);
    });
  });
}
