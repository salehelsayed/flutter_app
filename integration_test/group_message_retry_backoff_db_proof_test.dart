/// Real-SQLCipher device proof for Finding 05 Phase 4 (per-row retry backoff +
/// terminal `send_failed`), the DB-layer behavior that the host suites cover
/// only against the in-memory fake — the device runs sqflite_sqlcipher, where
/// the migration-087 ALTERs and the raw SQL of the backoff helpers must behave
/// identically.
@Tags(['device'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/087_group_message_retry_backoff_columns.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('real-SQLCipher group-message retry backoff proof (Finding 05 P4)', () {
    late Database db;
    late String path;

    setUp(() async {
      final dir = await getDatabasesPath();
      path =
          '$dir/retry_backoff_proof_'
          '${DateTime.now().microsecondsSinceEpoch}.db';
      await databaseFactory.deleteDatabase(path);
      db = await openDatabase(path, password: 'proof-key');
      await runGroupMessagesTablesMigration(db);
      await runGroupMessageRetryBackoffColumnsMigration(db);
    });

    tearDown(() async {
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });

    Future<void> insertFailed(
      String id, {
      String status = 'failed',
      int isIncoming = 0,
      int? nextEligibleAt,
    }) async {
      await db.insert('group_messages', {
        'id': id,
        'group_id': 'g1',
        'sender_peer_id': 'me',
        'text': 'body',
        'timestamp': '2026-06-17T12:00:00.000Z',
        'status': status,
        'is_incoming': isIncoming,
        'created_at': '2026-06-17T12:00:00.000Z',
        'next_eligible_at': nextEligibleAt,
      });
    }

    Future<Map<String, Object?>> row(String id) async {
      return (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
    }

    testWidgets('087 adds backoff columns with the right defaults', (t) async {
      final cols = await db.rawQuery('PRAGMA table_info(group_messages)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, containsAll(['retry_attempt_count', 'next_eligible_at']));

      await insertFailed('m1');
      final r = await row('m1');
      expect(r['retry_attempt_count'], 0);
      expect(r['next_eligible_at'], isNull);
    });

    testWidgets('recordRetryFailure increments + schedules; terminal flips', (
      t,
    ) async {
      await insertFailed('m1');

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
        markTerminal: true,
      );
      r = await row('m1');
      expect(r['retry_attempt_count'], 2);
      expect(r['next_eligible_at'], 2000);
      expect(r['status'], 'send_failed');
    });

    testWidgets('eligibility filter skips backed-off + terminal + incoming', (
      t,
    ) async {
      await insertFailed('eligible-null');
      await insertFailed('eligible-past', nextEligibleAt: 500);
      await insertFailed('backed-off', nextEligibleAt: 999999999999);
      await insertFailed('terminal', status: 'send_failed');
      await insertFailed('incoming', isIncoming: 1);

      final rows = await dbLoadRetryableOutgoingGroupMessages(db, nowMs: 1000);
      final ids = rows.map((r) => r['id']).toSet();
      expect(ids, {'eligible-null', 'eligible-past'});
    });

    testWidgets('resetRetryStateForManualRetry re-arms a terminal row only', (
      t,
    ) async {
      await insertFailed('terminal', status: 'send_failed', nextEligibleAt: 5000);
      await db.rawUpdate(
        'UPDATE group_messages SET retry_attempt_count = 12 WHERE id = ?',
        ['terminal'],
      );
      await insertFailed('plain-failed');

      await dbResetGroupMessageRetryState(db, 'terminal');
      await dbResetGroupMessageRetryState(db, 'plain-failed');

      final reset = await row('terminal');
      expect(reset['status'], 'failed');
      expect(reset['retry_attempt_count'], 0);
      expect(reset['next_eligible_at'], isNull);
      // A non-terminal row is left untouched by the manual re-arm.
      expect((await row('plain-failed'))['status'], 'failed');
    });

    testWidgets('clearRetryBackoff re-arms backed-off rows, leaves terminal', (
      t,
    ) async {
      await insertFailed('backed-off', nextEligibleAt: 999999999999);
      await insertFailed(
        'terminal',
        status: 'send_failed',
        nextEligibleAt: 999999999999,
      );

      final count = await dbClearGroupMessageRetryBackoff(db);
      expect(count, 1);
      expect((await row('backed-off'))['next_eligible_at'], isNull);
      expect((await row('terminal'))['next_eligible_at'], 999999999999);
    });
  });
}
