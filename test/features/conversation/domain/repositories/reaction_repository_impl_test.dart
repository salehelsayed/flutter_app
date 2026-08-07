import 'dart:async';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TwoPartyBarrier {
  final Completer<void> _released = Completer<void>();
  var _arrivals = 0;

  Future<void> arrive() {
    _arrivals++;
    if (_arrivals == 2) {
      _released.complete();
    }
    return _released.future;
  }
}

ReactionAddApplyResult _mapAddResult(DbIncomingReactionApplyResult result) {
  return switch (result) {
    DbIncomingReactionApplyResult.inserted => ReactionAddApplyResult.inserted,
    DbIncomingReactionApplyResult.updated => ReactionAddApplyResult.updated,
    DbIncomingReactionApplyResult.exactReplay =>
      ReactionAddApplyResult.exactReplay,
    DbIncomingReactionApplyResult.stale => ReactionAddApplyResult.stale,
    DbIncomingReactionApplyResult.removed => throw StateError(
      'ADD transaction returned REMOVE result',
    ),
  };
}

ReactionRemoveApplyResult _mapRemoveResult(
  DbIncomingReactionApplyResult result,
) {
  return switch (result) {
    DbIncomingReactionApplyResult.removed => ReactionRemoveApplyResult.applied,
    DbIncomingReactionApplyResult.exactReplay =>
      ReactionRemoveApplyResult.exactReplay,
    DbIncomingReactionApplyResult.stale => ReactionRemoveApplyResult.stale,
    DbIncomingReactionApplyResult.inserted ||
    DbIncomingReactionApplyResult.updated => throw StateError(
      'REMOVE transaction returned ADD result',
    ),
  };
}

ReactionRepositoryImpl _databaseBackedRepository(
  Database db, {
  _TwoPartyBarrier? barrier,
}) {
  return ReactionRepositoryImpl(
    dbInsertReaction: (row) => dbInsertReaction(db, row),
    dbApplyIncomingAdd: (row) async {
      await barrier?.arrive();
      return _mapAddResult(
        await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.add,
        ),
      );
    },
    dbApplyIncomingRemove: (row) async {
      await barrier?.arrive();
      return _mapRemoveResult(
        await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.remove,
        ),
      );
    },
    dbLoadReactionsForMessage: (messageId) =>
        dbLoadReactionsForMessage(db, messageId),
    dbLoadReactionsForMessages: (messageIds) =>
        dbLoadReactionsForMessages(db, messageIds),
    dbLoadActiveOrTombstonedReactionForSender: (messageId, senderPeerId) =>
        dbLoadActiveOrTombstonedReactionForSender(db, messageId, senderPeerId),
    dbDeleteReaction: (messageId, senderPeerId, {removedAtTimestamp}) =>
        dbDeleteReaction(
          db,
          messageId,
          senderPeerId,
          removedAtTimestamp: removedAtTimestamp,
        ),
    dbDeleteReactionsForMessage: (messageId) =>
        dbDeleteReactionsForMessage(db, messageId),
    dbDeleteReactionsForContact: (contactPeerId) =>
        dbDeleteReactionsForContact(db, contactPeerId),
  );
}

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

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

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
      dbLoadActiveOrTombstonedReactionForSender:
          (messageId, senderPeerId) async {
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

    test(
      'TC-343-06a outgoing reaction custody capability requires all exact delegates',
      () {
        ReactionRepositoryImpl build({String? omit}) => ReactionRepositoryImpl(
          dbInsertReaction: (_) async {},
          dbLoadReactionsForMessage: (_) async => const [],
          dbLoadReactionsForMessages: (_) async => const [],
          dbLoadActiveOrTombstonedReactionForSender: (_, _) async => null,
          dbDeleteReaction: (_, _, {removedAtTimestamp}) async => 0,
          dbDeleteReactionsForMessage: (_) async => 0,
          dbDeleteReactionsForContact: (_) async => 0,
          dbStageOutgoingDirectReactionInboxCustody: omit == 'stage'
              ? null
              : ({
                  required reactionRow,
                  required recipientPeerId,
                  required action,
                  required wireEnvelope,
                }) async => const DbDirectReactionCustodyStageResult(
                  outcome: DirectReactionCustodyStageOutcome.refused,
                  custodyRow: null,
                ),
          dbLoadDirectReactionInboxCustodyOutbox: omit == 'loadBatch'
              ? null
              : ({limit = 50}) async => const [],
          dbLoadDirectReactionInboxCustodyOutboxForEvent: omit == 'loadEvent'
              ? null
              : ({required recipientPeerId, required eventId}) async => null,
          dbRecordDirectReactionInboxCustodyFailureIfExact:
              omit == 'recordFailure'
              ? null
              : ({
                  required recipientPeerId,
                  required eventId,
                  required expectedWireEnvelope,
                  required errorCode,
                  required attemptedAt,
                }) async => false,
          dbCompleteAcceptedDirectReactionInboxCustodyIfExact:
              omit == 'complete'
              ? null
              : ({
                  required recipientPeerId,
                  required eventId,
                  required expectedWireEnvelope,
                }) async => DirectReactionInboxCustodyCompletionOutcome.absent,
        );

        expect(build().supportsDirectReactionInboxCustody, isTrue);
        for (final omitted in const <String>[
          'stage',
          'loadBatch',
          'loadEvent',
          'recordFailure',
          'complete',
        ]) {
          expect(
            build(omit: omitted).supportsDirectReactionInboxCustody,
            isFalse,
            reason: 'custody must fail closed when $omitted is absent',
          );
        }
      },
    );

    test(
      'outgoing reaction custody delegates exact tuple bytes time and outcomes',
      () async {
        const envelope = '{"cipher":"exact"}';
        final custodyRow = <String, Object?>{
          'recipient_peer_id': 'recipient-1',
          'event_id': testReaction.id,
          'wire_envelope': envelope,
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'created_at': testReaction.createdAt,
          'updated_at': testReaction.createdAt,
        };
        Map<String, Object?>? capturedStageRow;
        String? capturedStageRecipient;
        String? capturedStageAction;
        String? capturedStageEnvelope;
        int? capturedLimit;
        List<Object?>? capturedFailure;
        List<Object?>? capturedCompletion;
        repo = ReactionRepositoryImpl(
          dbInsertReaction: (_) async {},
          dbLoadReactionsForMessage: (_) async => const [],
          dbLoadReactionsForMessages: (_) async => const [],
          dbLoadActiveOrTombstonedReactionForSender: (_, _) async => null,
          dbDeleteReaction: (_, _, {removedAtTimestamp}) async => 0,
          dbDeleteReactionsForMessage: (_) async => 0,
          dbDeleteReactionsForContact: (_) async => 0,
          dbStageOutgoingDirectReactionInboxCustody:
              ({
                required reactionRow,
                required recipientPeerId,
                required action,
                required wireEnvelope,
              }) async {
                capturedStageRow = Map<String, Object?>.from(reactionRow);
                capturedStageRecipient = recipientPeerId;
                capturedStageAction = action;
                capturedStageEnvelope = wireEnvelope;
                return DbDirectReactionCustodyStageResult(
                  outcome: DirectReactionCustodyStageOutcome.applied,
                  custodyRow: custodyRow,
                );
              },
          dbLoadDirectReactionInboxCustodyOutbox: ({limit = 50}) async {
            capturedLimit = limit;
            return <Map<String, Object?>>[custodyRow];
          },
          dbLoadDirectReactionInboxCustodyOutboxForEvent:
              ({required recipientPeerId, required eventId}) async {
                expect(recipientPeerId, 'recipient-1');
                expect(eventId, testReaction.id);
                return custodyRow;
              },
          dbRecordDirectReactionInboxCustodyFailureIfExact:
              ({
                required recipientPeerId,
                required eventId,
                required expectedWireEnvelope,
                required errorCode,
                required attemptedAt,
              }) async {
                capturedFailure = <Object?>[
                  recipientPeerId,
                  eventId,
                  expectedWireEnvelope,
                  errorCode,
                  attemptedAt,
                ];
                return true;
              },
          dbCompleteAcceptedDirectReactionInboxCustodyIfExact:
              ({
                required recipientPeerId,
                required eventId,
                required expectedWireEnvelope,
              }) async {
                capturedCompletion = <Object?>[
                  recipientPeerId,
                  eventId,
                  expectedWireEnvelope,
                ];
                return DirectReactionInboxCustodyCompletionOutcome.completed;
              },
          now: () => DateTime.parse('2026-08-07T09:00:00.000Z'),
        );

        final staged = await repo.stageOutgoingDirectReactionInboxCustody(
          reaction: testReaction,
          recipientPeerId: 'recipient-1',
          action: 'add',
          wireEnvelope: envelope,
        );
        expect(staged.outcome, DirectReactionCustodyStageOutcome.applied);
        expect(staged.reaction, same(testReaction));
        expect(staged.custody?.toMap(), custodyRow);
        expect(capturedStageRow, testReaction.toMap());
        expect(capturedStageRecipient, 'recipient-1');
        expect(capturedStageAction, 'add');
        expect(capturedStageEnvelope, envelope);

        final loaded = await repo.loadDirectReactionInboxCustody(limit: 99);
        expect(capturedLimit, 99);
        expect(loaded.single.toMap(), custodyRow);
        final exact = await repo.loadDirectReactionInboxCustodyForEvent(
          recipientPeerId: 'recipient-1',
          eventId: testReaction.id,
        );
        expect(exact?.toMap(), custodyRow);
        expect(
          await repo.recordDirectReactionInboxCustodyFailureIfExact(
            expected: exact!,
            errorCode: DirectReactionInboxCustodyErrorCode.storeThrew,
          ),
          isTrue,
        );
        expect(capturedFailure, <Object?>[
          'recipient-1',
          testReaction.id,
          envelope,
          DirectReactionInboxCustodyErrorCode.storeThrew,
          '2026-08-07T09:00:00.000Z',
        ]);
        expect(
          await repo.completeAcceptedDirectReactionInboxCustodyIfExact(
            expected: exact,
          ),
          DirectReactionInboxCustodyCompletionOutcome.completed,
        );
        expect(capturedCompletion, <Object?>[
          'recipient-1',
          testReaction.id,
          envelope,
        ]);
      },
    );

    test(
      'group ADD adapter threads exact group and notification transition identity',
      () async {
        String? capturedGroupId;
        String? capturedNotificationEventId;
        Map<String, Object?>? capturedRow;
        repo = ReactionRepositoryImpl(
          dbInsertReaction: (_) async {},
          dbApplyGroupAdd:
              ({
                required groupId,
                required notificationEventId,
                required row,
              }) async {
                capturedGroupId = groupId;
                capturedNotificationEventId = notificationEventId;
                capturedRow = Map<String, Object?>.from(row);
                return ReactionAddApplyResult.stale;
              },
          dbLoadReactionsForMessage: (_) async => const [],
          dbLoadReactionsForMessages: (_) async => const [],
          dbLoadActiveOrTombstonedReactionForSender: (_, _) async => null,
          dbDeleteReaction: (_, _, {removedAtTimestamp}) async => 0,
          dbDeleteReactionsForMessage: (_) async => 0,
          dbDeleteReactionsForContact: (_) async => 0,
        );

        final result = await repo.applyGroupAdd(
          groupId: 'group-1',
          notificationEventId: 'reaction-event-1',
          reaction: testReaction,
        );

        expect(result, ReactionAddApplyResult.stale);
        expect(capturedGroupId, 'group-1');
        expect(capturedNotificationEventId, 'reaction-event-1');
        expect(capturedRow, containsPair('id', 'r1'));
      },
    );

    test(
      'callback fallback distinguishes insert from exact replay for fakes',
      () async {
        repo = ReactionRepositoryImpl(
          dbInsertReaction: (row) async {
            insertedRows.add(row);
            tombstoneAwareRow = Map<String, Object?>.from(row);
          },
          dbLoadReactionsForMessage: (_) async => const [],
          dbLoadReactionsForMessages: (_) async => const [],
          dbLoadActiveOrTombstonedReactionForSender: (_, _) async {
            // Yield so both callers genuinely overlap before the repository's
            // serialization primitive orders their compare/write decisions.
            await Future<void>.delayed(Duration.zero);
            return tombstoneAwareRow;
          },
          dbDeleteReaction: (_, _, {removedAtTimestamp}) async => 0,
          dbDeleteReactionsForMessage: (_) async => 0,
          dbDeleteReactionsForContact: (_) async => 0,
        );

        final results = await Future.wait([
          repo.applyIncomingAdd(testReaction),
          repo.applyIncomingAdd(testReaction),
        ]);

        expect(
          results,
          containsAll(<ReactionAddApplyResult>[
            ReactionAddApplyResult.inserted,
            ReactionAddApplyResult.exactReplay,
          ]),
        );
        expect(insertedRows, hasLength(1));
      },
    );

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

      final result = await repo.getReactionsForMessages(['msg-1', 'msg-2']);
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

    test(
      'removeReaction threads the removedAtTimestamp to the helper',
      () async {
        await repo.removeReaction(
          'msg-1',
          'sender-1',
          removedAtTimestamp: '2026-02-27T11:00:00.000Z',
        );
        expect(lastRemovedAtTimestamp, '2026-02-27T11:00:00.000Z');
      },
    );

    test(
      'getReactionForSenderIncludingRemoved maps a tombstoned row',
      () async {
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
      },
    );

    test(
      'getReactionForSenderIncludingRemoved returns null for no row',
      () async {
        tombstoneAwareRow = null;
        final reaction = await repo.getReactionForSenderIncludingRemoved(
          messageId: 'msg-1',
          senderPeerId: 'sender-1',
        );
        expect(reaction, isNull);
      },
    );

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

  group('database-backed atomic incoming mutations', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath);
      await runProductionOnCreate(db, currentIdentityDatabaseVersion);
    });

    tearDown(() => db.close());

    test(
      'atomic reaction event claim distinguishes insert from exact replay',
      () async {
        final barrier = _TwoPartyBarrier();
        final firstRepository = _databaseBackedRepository(db, barrier: barrier);
        final secondRepository = _databaseBackedRepository(
          db,
          barrier: barrier,
        );

        final results = await Future.wait([
          firstRepository.applyIncomingAdd(testReaction),
          secondRepository.applyIncomingAdd(testReaction),
        ]);

        expect(
          results,
          containsAll(<ReactionAddApplyResult>[
            ReactionAddApplyResult.inserted,
            ReactionAddApplyResult.exactReplay,
          ]),
        );
        expect(await db.query('message_reactions'), hasLength(1));
      },
    );

    test(
      'concurrent ADD vs REMOVE is last-writer-wins across repositories',
      () async {
        Future<void> runRace({
          required MessageReaction add,
          required MessageReaction remove,
          required bool expectRemoved,
        }) async {
          await db.delete('message_reactions');
          final barrier = _TwoPartyBarrier();
          final addRepository = _databaseBackedRepository(db, barrier: barrier);
          final removeRepository = _databaseBackedRepository(
            db,
            barrier: barrier,
          );

          await Future.wait<Object>([
            addRepository.applyIncomingAdd(add),
            removeRepository.applyIncomingRemove(remove),
          ]);

          final raw = await db.query('message_reactions');
          expect(raw, hasLength(1));
          expect(raw.single['removed_at'] != null, expectRemoved);
          expect(raw.single['id'], expectRemoved ? remove.id : add.id);
        }

        await runRace(
          add: testReaction,
          remove: testReaction.copyWith(
            id: 'r-remove-newer',
            timestamp: '2026-02-27T10:01:00.000Z',
          ),
          expectRemoved: true,
        );
        await runRace(
          add: testReaction.copyWith(
            id: 'r-add-newer',
            timestamp: '2026-02-27T10:02:00.000Z',
          ),
          remove: testReaction.copyWith(
            id: 'r-remove-older',
            timestamp: '2026-02-27T10:01:00.000Z',
          ),
          expectRemoved: false,
        );
      },
    );
  });
}
