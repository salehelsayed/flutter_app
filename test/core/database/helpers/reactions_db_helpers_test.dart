import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';

Map<String, Object?> makeReactionRow({
  String id = 'r1',
  String messageId = 'msg-1',
  String emoji = '👍',
  String senderPeerId = 'sender-1',
  String timestamp = '2026-02-27T10:00:00.000Z',
  String createdAt = '2026-02-27T10:00:01.000Z',
}) {
  return {
    'id': id,
    'message_id': messageId,
    'emoji': emoji,
    'sender_peer_id': senderPeerId,
    'timestamp': timestamp,
    'created_at': createdAt,
  };
}

Map<String, Object?> makeMessageRow({
  String id = 'msg-1',
  String contactPeerId = 'contact-1',
  String senderPeerId = 'sender-1',
  String text = 'Hello',
  String timestamp = '2026-02-27T09:00:00.000Z',
  String status = 'delivered',
  int isIncoming = 1,
  String createdAt = '2026-02-27T09:00:01.000Z',
}) {
  return {
    'id': id,
    'contact_peer_id': contactPeerId,
    'sender_peer_id': senderPeerId,
    'text': text,
    'timestamp': timestamp,
    'status': status,
    'is_incoming': isIncoming,
    'created_at': createdAt,
  };
}

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMessageReactionsMigration(db);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
    await runMessageReactionTombstoneMigration(db);
    await runGroupNotificationDisplayOutboxMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('dbInsertReaction', () {
    test('inserts a reaction', () async {
      await dbInsertReaction(db, makeReactionRow());

      final rows = await db.query('message_reactions');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'r1');
      expect(rows[0]['emoji'], '👍');
    });

    test('upsert — REPLACE on conflict replaces existing row', () async {
      await dbInsertReaction(db, makeReactionRow());
      // Same message_id + sender_peer_id, different emoji
      await dbInsertReaction(db, makeReactionRow(id: 'r2', emoji: '❤️'));

      final rows = await db.query('message_reactions');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'r2');
      expect(rows[0]['emoji'], '❤️');
    });
  });

  group('dbLoadReactionsForMessage', () {
    test('returns empty list for no reactions', () async {
      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results, isEmpty);
    });

    test('returns matching reactions', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r2', messageId: 'msg-1', senderPeerId: 'sender-2'),
      );
      await dbInsertReaction(db, makeReactionRow(id: 'r3', messageId: 'msg-2'));

      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results.length, 2);
    });

    test('ordered by timestamp ASC', () async {
      await dbInsertReaction(
        db,
        makeReactionRow(
          id: 'r1',
          senderPeerId: 'sender-1',
          timestamp: '2026-02-27T10:02:00.000Z',
        ),
      );
      await dbInsertReaction(
        db,
        makeReactionRow(
          id: 'r2',
          senderPeerId: 'sender-2',
          timestamp: '2026-02-27T10:01:00.000Z',
        ),
      );

      final results = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(results[0]['id'], 'r2'); // earlier timestamp first
      expect(results[1]['id'], 'r1');
    });
  });

  group('dbLoadReactionsForMessages', () {
    test('returns empty for empty input', () async {
      final results = await dbLoadReactionsForMessages(db, []);
      expect(results, isEmpty);
    });

    test('batch loads reactions for multiple messages', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r2', messageId: 'msg-2', senderPeerId: 'sender-2'),
      );
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r3', messageId: 'msg-3', senderPeerId: 'sender-3'),
      );

      final results = await dbLoadReactionsForMessages(db, ['msg-1', 'msg-2']);
      expect(results.length, 2);
      final messageIds = results.map((r) => r['message_id'] as String).toSet();
      expect(messageIds, containsAll(['msg-1', 'msg-2']));
    });
  });

  group('dbDeleteReaction (tombstone)', () {
    test(
      'INV-T1 tombstones the row in place and hides it from loaders',
      () async {
        await dbInsertReaction(db, makeReactionRow());
        final count = await dbDeleteReaction(
          db,
          'msg-1',
          'sender-1',
          removedAtTimestamp: '2026-02-27T11:00:00.000Z',
        );
        expect(count, 1);

        // Row is retained as a tombstone...
        final rawRows = await db.query('message_reactions');
        expect(rawRows, hasLength(1));
        expect(rawRows.single['removed_at'], '2026-02-27T11:00:00.000Z');

        // ...but hidden from the UI loaders.
        expect(await dbLoadReactionsForMessage(db, 'msg-1'), isEmpty);
        expect(await dbLoadReactionsForMessages(db, ['msg-1']), isEmpty);
      },
    );

    test('returns 0 when no match (no tombstone is created)', () async {
      final count = await dbDeleteReaction(db, 'msg-999', 'sender-999');
      expect(count, 0);
      expect(await db.query('message_reactions'), isEmpty);
    });

    test('INV-T3 re-inserting a reaction clears the tombstone', () async {
      await dbInsertReaction(db, makeReactionRow());
      await dbDeleteReaction(
        db,
        'msg-1',
        'sender-1',
        removedAtTimestamp: '2026-02-27T11:00:00.000Z',
      );

      // A fresh add (removed_at null) REPLACEs the tombstone row.
      await dbInsertReaction(db, {
        ...makeReactionRow(id: 'r2', emoji: '🔥'),
        'removed_at': null,
      });

      final visible = await dbLoadReactionsForMessage(db, 'msg-1');
      expect(visible, hasLength(1));
      expect(visible.single['emoji'], '🔥');
      expect(visible.single['removed_at'], isNull);
    });
  });

  group('dbApplyIncomingReactionMutation group ADD custody', () {
    test(
      'REMOVE preserves displayed ADD identity for the provisional post-show fence',
      () async {
        const addAt = '2026-08-03T08:00:01.000Z';
        const removeAt = '2026-08-03T08:00:02.000Z';
        await db.insert('group_messages', <String, Object?>{
          'id': 'message-fence',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-self',
          'text': 'target',
          'timestamp': addAt,
          'created_at': addAt,
          'is_incoming': 0,
        });
        await dbApplyIncomingReactionMutation(
          db,
          makeReactionRow(
            id: 'reaction-fence',
            messageId: 'message-fence',
            senderPeerId: 'peer-reactor',
            timestamp: addAt,
            createdAt: addAt,
          ),
          mutation: DbIncomingReactionMutation.add,
        );
        await db.update(
          'message_reactions',
          const <String, Object?>{
            'notification_display_terminal_event_id': 'bounded-add-event',
          },
          where: 'message_id = ? AND sender_peer_id = ?',
          whereArgs: const <Object?>['message-fence', 'peer-reactor'],
        );

        await dbApplyIncomingReactionMutation(
          db,
          makeReactionRow(
            id: 'reaction-fence',
            messageId: 'message-fence',
            senderPeerId: 'peer-reactor',
            timestamp: removeAt,
            createdAt: removeAt,
          ),
          mutation: DbIncomingReactionMutation.remove,
          groupIdForNotificationCleanup: 'group-a',
        );

        final tombstone = await dbLoadActiveOrTombstonedReactionForSender(
          db,
          'message-fence',
          'peer-reactor',
        );
        expect(
          tombstone,
          containsPair(
            'notification_display_terminal_event_id',
            'bounded-add-event',
          ),
        );
        expect(
          evaluateBackgroundGroupNotificationPostShowState(
            comparand:
                const BackgroundProvisionalGroupReactionNotificationComparand(
                  groupId: 'group-a',
                  messageId: 'message-fence',
                  senderPeerId: 'peer-reactor',
                  notificationEventIdentity: 'bounded-add-event',
                ),
            localPeerId: 'peer-self',
            groupRow: const <String, Object?>{
              'id': 'group-a',
              'type': 'chat',
              'is_muted': 0,
              'is_archived': 0,
              'is_dissolved': 0,
              'dissolved_at': null,
              'self_removed_at': null,
            },
            localMemberRow: const <String, Object?>{
              'group_id': 'group-a',
              'peer_id': 'peer-self',
            },
            reactionRow: tombstone,
            targetMessageRow: await db
                .query(
                  'group_messages',
                  where: 'id = ?',
                  whereArgs: const <Object?>['message-fence'],
                  limit: 1,
                )
                .then((rows) => rows.single),
          ),
          BackgroundGroupNotificationPostShowDecision.retire,
        );

        await dbApplyIncomingReactionMutation(
          db,
          makeReactionRow(
            id: 'reaction-fence-readd',
            messageId: 'message-fence',
            senderPeerId: 'peer-reactor',
            timestamp: '2026-08-03T08:00:03.000Z',
            createdAt: '2026-08-03T08:00:03.000Z',
          ),
          mutation: DbIncomingReactionMutation.add,
        );
        expect(
          await dbLoadActiveOrTombstonedReactionForSender(
            db,
            'message-fence',
            'peer-reactor',
          ),
          containsPair('notification_display_terminal_event_id', isNull),
        );
      },
    );

    test(
      'exact ADD replay preserves its not-ready marker for ready promotion',
      () async {
        const eventAt = '2026-08-03T08:00:01.000Z';
        await db.insert('group_messages', <String, Object?>{
          'id': 'message-replay',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-self',
          'text': 'target',
          'timestamp': eventAt,
          'created_at': eventAt,
        });
        final row = makeReactionRow(
          id: 'replay-add-state',
          messageId: 'message-replay',
          senderPeerId: 'peer-reactor',
          timestamp: eventAt,
          createdAt: eventAt,
        );
        expect(
          await dbApplyIncomingReactionMutation(
            db,
            row,
            mutation: DbIncomingReactionMutation.add,
          ),
          DbIncomingReactionApplyResult.inserted,
        );
        await dbStageGroupNotificationDisplayOutboxEntry(
          db,
          GroupNotificationDisplayOutboxEntry.reaction(
            eventId: 'replay-add-event',
            groupId: 'group-a',
            messageId: 'message-replay',
            actorPeerId: 'peer-reactor',
            eventTimestamp: eventAt,
            reactionId: 'replay-add-state',
            reactionAction: 'add',
            reactionTombstone: false,
            createdAt: eventAt,
            updatedAt: eventAt,
          ).toMap(),
        );

        final replay = await dbApplyIncomingReactionMutation(
          db,
          row,
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: 'replay-add-event',
        );

        expect(replay, DbIncomingReactionApplyResult.exactReplay);
        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(
            db,
            'replay-add-event',
          ),
          containsPair('readiness', 'not_ready'),
        );
        expect(
          await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
            db,
            eventId: 'replay-add-event',
            expectedRevision: 1,
            updatedAt: '2026-08-03T08:00:02.000Z',
          ),
          isTrue,
        );
        expect(
          await dbLoadGroupNotificationDisplayOutboxEntry(
            db,
            'replay-add-event',
          ),
          containsPair('readiness', 'ready'),
        );
      },
    );

    test(
      'stale ADD deletes only its exact staged event and preserves newer actor custody',
      () async {
        const staleAt = '2026-08-03T08:00:01.000Z';
        const removeAt = '2026-08-03T08:00:02.000Z';
        const newerAt = '2026-08-03T08:00:03.000Z';
        await db.insert('group_messages', <String, Object?>{
          'id': 'message-a',
          'group_id': 'group-a',
          'sender_peer_id': 'peer-self',
          'text': 'target',
          'timestamp': staleAt,
          'created_at': staleAt,
        });
        await dbApplyIncomingReactionMutation(
          db,
          makeReactionRow(
            id: 'newer-remove-state',
            messageId: 'message-a',
            senderPeerId: 'peer-reactor',
            timestamp: removeAt,
            createdAt: removeAt,
          ),
          mutation: DbIncomingReactionMutation.remove,
        );

        Future<void> stage(
          String eventId, {
          String groupId = 'group-a',
          String actorPeerId = 'peer-reactor',
          String reactionId = 'stale-add-state',
          String timestamp = staleAt,
        }) => dbStageGroupNotificationDisplayOutboxEntry(
          db,
          GroupNotificationDisplayOutboxEntry.reaction(
            eventId: eventId,
            groupId: groupId,
            messageId: 'message-a',
            actorPeerId: actorPeerId,
            eventTimestamp: timestamp,
            reactionId: reactionId,
            reactionAction: 'add',
            reactionTombstone: false,
            createdAt: staleAt,
            updatedAt: staleAt,
          ).toMap(),
        );

        await stage('stale-add-event');
        await stage(
          'newer-same-actor-event',
          reactionId: 'newer-add-state',
          timestamp: newerAt,
        );
        await stage('sibling-actor-event', actorPeerId: 'peer-other');
        await stage('sibling-group-event', groupId: 'group-b');

        final result = await dbApplyIncomingReactionMutation(
          db,
          makeReactionRow(
            id: 'stale-add-state',
            messageId: 'message-a',
            senderPeerId: 'peer-reactor',
            timestamp: staleAt,
            createdAt: staleAt,
          ),
          mutation: DbIncomingReactionMutation.add,
          groupIdForNotificationCleanup: 'group-a',
          notificationEventIdForStaleAddCleanup: 'stale-add-event',
        );

        expect(result, DbIncomingReactionApplyResult.stale);
        expect(
          await dbLoadActiveOrTombstonedReactionForSender(
            db,
            'message-a',
            'peer-reactor',
          ),
          allOf(
            containsPair('removed_at', removeAt),
            containsPair(
              'notification_display_terminal_event_id',
              boundedReactionEventIdentity('stale-add-event'),
            ),
          ),
        );
        expect(
          (await db.query(
            'group_notification_display_outbox',
            orderBy: 'event_id',
          )).map((row) => row['event_id']),
          <String>[
            'newer-same-actor-event',
            'sibling-actor-event',
            'sibling-group-event',
          ],
        );
      },
    );
  });

  group('dbLoadActiveOrTombstonedReactionForSender', () {
    test('returns null when no row exists', () async {
      final row = await dbLoadActiveOrTombstonedReactionForSender(
        db,
        'msg-1',
        'sender-1',
      );
      expect(row, isNull);
    });

    test('INV-T2 returns the tombstoned row for the LWW comparand', () async {
      await dbInsertReaction(db, makeReactionRow());
      await dbDeleteReaction(
        db,
        'msg-1',
        'sender-1',
        removedAtTimestamp: '2026-02-27T11:00:00.000Z',
      );

      final row = await dbLoadActiveOrTombstonedReactionForSender(
        db,
        'msg-1',
        'sender-1',
      );
      expect(row, isNotNull);
      expect(row!['removed_at'], '2026-02-27T11:00:00.000Z');
    });
  });

  group('dbDeleteReactionsForMessage', () {
    test('deletes all reactions for a message', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r2', messageId: 'msg-1', senderPeerId: 'sender-2'),
      );
      await dbInsertReaction(db, makeReactionRow(id: 'r3', messageId: 'msg-2'));

      final count = await dbDeleteReactionsForMessage(db, 'msg-1');
      expect(count, 2);

      final remaining = await db.query('message_reactions');
      expect(remaining.length, 1);
      expect(remaining[0]['message_id'], 'msg-2');
    });

    test('INV-T4 hard-deletes tombstones too (no orphan leak)', () async {
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbDeleteReaction(
        db,
        'msg-1',
        'sender-1',
        removedAtTimestamp: '2026-02-27T11:00:00.000Z',
      );

      // The bulk cleanup removes the tombstone row entirely (raw query).
      final count = await dbDeleteReactionsForMessage(db, 'msg-1');
      expect(count, 1);
      expect(await db.query('message_reactions'), isEmpty);
    });
  });

  group('dbDeleteReactionsForContact', () {
    test('deletes via subquery on messages table', () async {
      // Insert messages for two different contacts
      await db.insert(
        'messages',
        makeMessageRow(id: 'msg-1', contactPeerId: 'contact-1'),
      );
      await db.insert(
        'messages',
        makeMessageRow(id: 'msg-2', contactPeerId: 'contact-1'),
      );
      await db.insert(
        'messages',
        makeMessageRow(id: 'msg-3', contactPeerId: 'contact-2'),
      );

      // Insert reactions on messages from both contacts
      await dbInsertReaction(db, makeReactionRow(id: 'r1', messageId: 'msg-1'));
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r2', messageId: 'msg-2', senderPeerId: 'sender-2'),
      );
      await dbInsertReaction(
        db,
        makeReactionRow(id: 'r3', messageId: 'msg-3', senderPeerId: 'sender-3'),
      );

      final count = await dbDeleteReactionsForContact(db, 'contact-1');
      expect(count, 2);

      // Only contact-2's reaction remains
      final remaining = await db.query('message_reactions');
      expect(remaining.length, 1);
      expect(remaining[0]['message_id'], 'msg-3');
    });
  });
}
