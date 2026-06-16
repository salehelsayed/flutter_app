import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository_impl.dart';

void main() {
  late ReactionRepositoryImpl repo;
  late List<Map<String, Object?>> insertedRows;
  late Map<String, List<Map<String, Object?>>> storedRows;
  late Map<String, Object?>? tombstoneAwareRow;
  String? lastRemovedAtTimestamp;

  const testReaction = MessageReaction(
    id: 'r1',
    messageId: 'msg-1',
    emoji: '👍',
    senderPeerId: 'sender-1',
    timestamp: '2026-02-27T10:00:00.000Z',
    createdAt: '2026-02-27T10:00:01.000Z',
  );

  setUp(() {
    insertedRows = [];
    storedRows = {};
    tombstoneAwareRow = null;
    lastRemovedAtTimestamp = null;

    repo = ReactionRepositoryImpl(
      dbInsertReaction: (row) async {
        insertedRows.add(row);
      },
      dbLoadReactionsForMessage: (messageId) async {
        return storedRows[messageId] ?? [];
      },
      dbLoadReactionsForMessages: (messageIds) async {
        final results = <Map<String, Object?>>[];
        for (final id in messageIds) {
          results.addAll(storedRows[id] ?? []);
        }
        return results;
      },
      dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) async {
        return tombstoneAwareRow;
      },
      dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) async {
        lastRemovedAtTimestamp = removedAtTimestamp;
        return 1;
      },
      dbDeleteReactionsForMessage: (messageId) async {
        return storedRows[messageId]?.length ?? 0;
      },
      dbDeleteReactionsForContact: (contactPeerId) async {
        return 2;
      },
    );
  });

  group('ReactionRepositoryImpl', () {
    test('saveReaction delegates to dbInsertReaction', () async {
      await repo.saveReaction(testReaction);

      expect(insertedRows.length, 1);
      expect(insertedRows[0]['id'], 'r1');
      expect(insertedRows[0]['message_id'], 'msg-1');
      expect(insertedRows[0]['emoji'], '👍');
    });

    test('getReactionsForMessage maps rows to MessageReaction', () async {
      storedRows['msg-1'] = [testReaction.toMap()];

      final reactions = await repo.getReactionsForMessage('msg-1');
      expect(reactions.length, 1);
      expect(reactions[0].id, 'r1');
      expect(reactions[0].emoji, '👍');
    });

    test('getReactionsForMessages returns Map grouped by messageId', () async {
      storedRows['msg-1'] = [testReaction.toMap()];
      storedRows['msg-2'] = [
        testReaction.copyWith(id: 'r2', messageId: 'msg-2').toMap(),
      ];

      final result =
          await repo.getReactionsForMessages(['msg-1', 'msg-2']);
      expect(result.keys, containsAll(['msg-1', 'msg-2']));
      expect(result['msg-1']!.length, 1);
      expect(result['msg-2']!.length, 1);
    });

    test('getReactionsForMessages returns empty map for empty input', () async {
      final result = await repo.getReactionsForMessages([]);
      expect(result, isEmpty);
    });

    test('removeReaction delegates to dbDeleteReaction', () async {
      final count = await repo.removeReaction('msg-1', 'sender-1');
      expect(count, 1);
    });

    test('removeReaction threads the removedAtTimestamp to the helper', () async {
      await repo.removeReaction(
        'msg-1',
        'sender-1',
        removedAtTimestamp: '2026-02-27T11:00:00.000Z',
      );
      expect(lastRemovedAtTimestamp, '2026-02-27T11:00:00.000Z');
    });

    test('getReactionForSenderIncludingRemoved maps a tombstoned row', () async {
      tombstoneAwareRow = testReaction
          .copyWith(removedAt: '2026-02-27T11:00:00.000Z')
          .toMap();

      final reaction = await repo.getReactionForSenderIncludingRemoved(
        messageId: 'msg-1',
        senderPeerId: 'sender-1',
      );
      expect(reaction, isNotNull);
      expect(reaction!.id, 'r1');
      expect(reaction.removedAt, '2026-02-27T11:00:00.000Z');
      expect(reaction.isRemoved, isTrue);
    });

    test('getReactionForSenderIncludingRemoved returns null for no row', () async {
      tombstoneAwareRow = null;
      final reaction = await repo.getReactionForSenderIncludingRemoved(
        messageId: 'msg-1',
        senderPeerId: 'sender-1',
      );
      expect(reaction, isNull);
    });

    test('deleteReactionsForMessage delegates', () async {
      storedRows['msg-1'] = [testReaction.toMap()];
      final count = await repo.deleteReactionsForMessage('msg-1');
      expect(count, 1);
    });

    test('deleteReactionsForContact delegates', () async {
      final count = await repo.deleteReactionsForContact('contact-1');
      expect(count, 2);
    });
  });
}
