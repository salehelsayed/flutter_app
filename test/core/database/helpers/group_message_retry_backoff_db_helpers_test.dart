import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/041_group_message_reliability_columns.dart';
import 'package:flutter_app/core/database/migrations/087_group_message_retry_backoff_columns.dart';

/// Host (sqflite_common_ffi) real-DB coverage for the Finding 05 Phase 4 per-row
/// retry-backoff SQL on `group_messages` + migration 087.
///
/// Same SQL as the device proof
/// (`integration_test/group_message_retry_backoff_db_proof_test.dart`) but in the
/// default `flutter test` host suite — no device build — so a regression in the
/// eligibility filter, the terminal-`send_failed` exclusion, the manual/reconnect
/// re-arm queries, or the `toMap`-omit clobber-safety invariant is caught in
/// routine CI. The use-case suite only exercises `InMemoryGroupMessageRepository`
/// (a pure-Dart reimplementation), so without this the production SQL ships
/// untested on the host.
void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupMessagesTablesMigration(db);
    await runGroupMessageReliabilityColumnsMigration(db);
    await runGroupMessageRetryBackoffColumnsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertOutgoing(
    String id, {
    String status = 'failed',
    int isIncoming = 0,
    int? nextEligibleAt,
    String text = 'body',
    String? wireEnvelope,
    String? inboxRetryPayload,
  }) async {
    await db.insert('group_messages', {
      'id': id,
      'group_id': 'g1',
      'sender_peer_id': 'me',
      'text': text,
      'timestamp': '2026-06-17T12:00:00.000Z',
      'status': status,
      'is_incoming': isIncoming,
      'created_at': '2026-06-17T12:00:00.000Z',
      'next_eligible_at': nextEligibleAt,
      'wire_envelope': wireEnvelope,
      'inbox_retry_payload': inboxRetryPayload,
    });
  }

  Future<Map<String, Object?>> row(String id) async => (await db.query(
    'group_messages',
    where: 'id = ?',
    whereArgs: [id],
  )).single;

  group('087 migration', () {
    test('adds backoff columns idempotently with correct defaults', () async {
      // Re-run to prove the column-exists guard (idempotent ALTER).
      await runGroupMessageRetryBackoffColumnsMigration(db);

      final names = (await db.rawQuery(
        'PRAGMA table_info(group_messages)',
      )).map((c) => c['name']).toSet();
      expect(names, containsAll(['retry_attempt_count', 'next_eligible_at']));

      await insertOutgoing('m1');
      final r = await row('m1');
      expect(r['retry_attempt_count'], 0); // NOT NULL DEFAULT 0
      expect(r['next_eligible_at'], isNull); // nullable
    });
  });

  group('dbRecordGroupMessageRetryFailure', () {
    test('increments the attempt count + schedules the next attempt', () async {
      await insertOutgoing('m1');

      await dbRecordGroupMessageRetryFailure(
        db,
        'm1',
        nextEligibleAtMs: 1000,
        markTerminal: false,
      );
      var r = await row('m1');
      expect(r['retry_attempt_count'], 1);
      expect(r['next_eligible_at'], 1000);
      expect(r['status'], 'failed');

      await dbRecordGroupMessageRetryFailure(
        db,
        'm1',
        nextEligibleAtMs: 2000,
        markTerminal: false,
      );
      r = await row('m1');
      expect(r['retry_attempt_count'], 2);
      expect(r['next_eligible_at'], 2000);
    });

    test('markTerminal flips the row to send_failed', () async {
      await insertOutgoing('m1');
      await dbRecordGroupMessageRetryFailure(
        db,
        'm1',
        nextEligibleAtMs: 9000,
        markTerminal: true,
      );
      final r = await row('m1');
      expect(r['status'], 'send_failed');
      expect(r['retry_attempt_count'], 1);
    });

    test('never touches a terminal or incoming row', () async {
      await insertOutgoing('terminal', status: 'send_failed');
      await insertOutgoing('incoming', isIncoming: 1);

      await dbRecordGroupMessageRetryFailure(
        db,
        'terminal',
        nextEligibleAtMs: 1,
        markTerminal: false,
      );
      await dbRecordGroupMessageRetryFailure(
        db,
        'incoming',
        nextEligibleAtMs: 1,
        markTerminal: false,
      );

      expect((await row('terminal'))['retry_attempt_count'], 0);
      expect((await row('incoming'))['retry_attempt_count'], 0);
    });
  });

  group('dbLoadRetryableOutgoingGroupMessages', () {
    test(
      'returns only past/NULL-eligible non-terminal outgoing rows',
      () async {
        await insertOutgoing('eligible-null'); // next_eligible_at NULL
        await insertOutgoing('eligible-past', nextEligibleAt: 500);
        await insertOutgoing('pending-eligible', status: 'pending');
        await insertOutgoing('backed-off', nextEligibleAt: 999999999999);
        await insertOutgoing('terminal', status: 'send_failed');
        await insertOutgoing('incoming', isIncoming: 1);

        final ids = (await dbLoadRetryableOutgoingGroupMessages(
          db,
          nowMs: 1000,
        )).map((r) => r['id']).toSet();
        expect(ids, {'eligible-null', 'eligible-past', 'pending-eligible'});
      },
    );

    test('honours the limit', () async {
      await insertOutgoing('a', text: 'a');
      await insertOutgoing('b', text: 'b');
      await insertOutgoing('c', text: 'c');
      final rows = await dbLoadRetryableOutgoingGroupMessages(
        db,
        nowMs: 1000,
        limit: 2,
      );
      expect(rows, hasLength(2));
    });
  });

  group('dbClearGroupMessageRetryBackoff (reconnect re-arm)', () {
    test(
      'clears the backoff window for retryable rows, leaves terminal',
      () async {
        await insertOutgoing('backed-off', nextEligibleAt: 999999999999);
        await insertOutgoing(
          'terminal',
          status: 'send_failed',
          nextEligibleAt: 999999999999,
        );

        final count = await dbClearGroupMessageRetryBackoff(db);
        expect(count, 1); // only the retryable row re-armed.
        expect((await row('backed-off'))['next_eligible_at'], isNull);
        expect((await row('terminal'))['next_eligible_at'], 999999999999);
      },
    );
  });

  group('dbResetGroupMessageRetryState (manual retry re-arm)', () {
    test('re-arms a terminal row to failed with a fresh budget', () async {
      await insertOutgoing(
        'terminal',
        status: 'send_failed',
        nextEligibleAt: 5000,
        wireEnvelope: '{"type":"group_message"}',
      );
      await db.rawUpdate(
        'UPDATE group_messages SET retry_attempt_count = 12 WHERE id = ?',
        ['terminal'],
      );

      await dbResetGroupMessageRetryState(db, 'terminal');

      final r = await row('terminal');
      expect(r['status'], 'failed');
      expect(r['retry_attempt_count'], 0);
      expect(r['next_eligible_at'], isNull);
    });

    test(
      'leaves a terminal row without durable retry evidence non-rearmable',
      () async {
        await insertOutgoing(
          'terminal-without-evidence',
          status: 'send_failed',
          nextEligibleAt: 5000,
        );

        await dbResetGroupMessageRetryState(db, 'terminal-without-evidence');

        final r = await row('terminal-without-evidence');
        expect(r['status'], 'send_failed');
        expect(r['retry_attempt_count'], 0);
        expect(r['next_eligible_at'], 5000);
      },
    );

    test('is a no-op for a non-terminal row', () async {
      await insertOutgoing('plain', status: 'failed');
      await dbRecordGroupMessageRetryFailure(
        db,
        'plain',
        nextEligibleAtMs: 7000,
        markTerminal: false,
      );

      await dbResetGroupMessageRetryState(db, 'plain');

      final r = await row('plain');
      expect(r['status'], 'failed');
      expect(r['retry_attempt_count'], 1); // untouched
      expect(r['next_eligible_at'], 7000); // untouched
    });
  });

  group('clobber safety (the load-bearing toMap-omit invariant)', () {
    test(
      'a normal re-save via dbInsertGroupMessage preserves backoff state',
      () async {
        // A GroupMessage.toMap()-shaped row (NO backoff columns — toMap omits
        // them) saved the production way.
        final saveRow = <String, Object?>{
          'id': 'm1',
          'group_id': 'g1',
          'sender_peer_id': 'me',
          'sender_username': 'Me',
          'text': 'hello',
          'timestamp': '2026-06-17T12:00:00.000Z',
          'key_generation': 0,
          'status': 'failed',
          'is_incoming': 0,
          'created_at': '2026-06-17T12:00:00.000Z',
        };
        await dbInsertGroupMessage(db, saveRow);

        // The retrier records a backoff attempt out-of-band (dedicated setter).
        await dbRecordGroupMessageRetryFailure(
          db,
          'm1',
          nextEligibleAtMs: 5000,
          markTerminal: false,
        );
        expect((await row('m1'))['retry_attempt_count'], 1);
        expect((await row('m1'))['next_eligible_at'], 5000);

        // The app re-saves the SAME message (e.g. a status refresh). The save map
        // still omits the backoff columns, so the duplicate-insert UPDATE path
        // must NOT clobber them — this is the whole reason toMap omits them.
        await dbInsertGroupMessage(db, {...saveRow, 'text': 'hello (edited)'});

        final r = await row('m1');
        expect(r['text'], 'hello (edited)'); // the UPDATE path did run…
        expect(
          r['retry_attempt_count'],
          1,
          reason: 'toMap omits the column; the UPDATE must leave it intact',
        );
        expect(
          r['next_eligible_at'],
          5000,
          reason: 'the backoff window must survive an ordinary re-save',
        );
      },
    );
  });
}
