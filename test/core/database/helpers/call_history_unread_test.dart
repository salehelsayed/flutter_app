import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/call_history_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/117_call_history.dart';
import 'package:flutter_app/core/database/migrations/118_call_history_read_state.dart';

/// 410: which calls the unread badge may count.
///
/// Only an INCOMING call the user never took: missed, cancelled (the caller
/// hung up first — a missed call from the callee's side) or busy. An answered
/// call, a call the user declined, a failed call, and everything outgoing are
/// all things the user already knows about.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<Database> open() async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await runCallHistoryMigration(db);
    await runCallHistoryReadStateMigration(db);
    return db;
  }

  Future<void> insert(
    Database db, {
    required String id,
    String contact = 'peer-A',
    String direction = 'incoming',
    String status = 'missed',
    String reason = 'caller_cancelled',
    String? readAt,
  }) => db.insert(kCallHistoryTable, <String, Object?>{
    'call_id': 'a2f0a1d6-0000-4000-8000-00000000041$id',
    'contact_account_peer_id': contact,
    'direction': direction,
    'terminal_reason': reason,
    'status': status,
    'started_at': '2026-02-09T15:30:00.000Z',
    'connected_at': null,
    'ended_at': '2026-02-09T15:30:20.000Z',
    'transport_route_class': null,
    'created_at': '2026-02-09T15:30:20.000Z',
    'updated_at': '2026-02-09T15:30:20.000Z',
    'read_at': readAt,
  });

  test(
    'TC-410-10 counts only unseen incoming calls the user never took',
    () async {
      final db = await open();
      addTearDown(db.close);
      await insert(db, id: '0', status: 'missed');
      await insert(db, id: '1', status: 'cancelled');
      await insert(db, id: '2', status: 'busy', reason: 'busy');
      // Things the user already knows about:
      await insert(db, id: '3', status: 'completed', reason: 'local_hangup');
      await insert(db, id: '4', status: 'declined', reason: 'declined');
      await insert(db, id: '5', status: 'failed', reason: 'media_failed');
      await insert(db, id: '6', status: 'missed', direction: 'outgoing');
      await insert(
        db,
        id: '7',
        status: 'missed',
        readAt: '2026-02-09T16:00:00.000Z',
      );

      final counts = await loadUnreadCallCountsForContacts(db, ['peer-A']);

      expect(counts['peer-A'], 3);
    },
  );

  test(
    'TC-410-11 counts are per contact and omit contacts with none',
    () async {
      final db = await open();
      addTearDown(db.close);
      await insert(db, id: '0', contact: 'peer-A');
      await insert(db, id: '1', contact: 'peer-A');
      await insert(
        db,
        id: '2',
        contact: 'peer-B',
        status: 'completed',
        reason: 'local_hangup',
      );

      final counts = await loadUnreadCallCountsForContacts(db, [
        'peer-A',
        'peer-B',
        'peer-C',
      ]);

      expect(counts['peer-A'], 2);
      expect(counts.containsKey('peer-B'), isFalse);
      expect(counts.containsKey('peer-C'), isFalse);
    },
  );

  test('TC-410-12 an empty contact list asks the database nothing', () async {
    final db = await open();
    addTearDown(db.close);

    expect(await loadUnreadCallCountsForContacts(db, const []), isEmpty);
  });

  test(
    'TC-410-13 marking read clears the badge for that contact only',
    () async {
      final db = await open();
      addTearDown(db.close);
      await insert(db, id: '0', contact: 'peer-A');
      await insert(db, id: '1', contact: 'peer-B');

      final marked = await markCallHistoryRead(
        db,
        'peer-A',
        DateTime.utc(2026, 2, 9, 17),
      );

      expect(marked, 1);
      final counts = await loadUnreadCallCountsForContacts(db, [
        'peer-A',
        'peer-B',
      ]);
      expect(counts.containsKey('peer-A'), isFalse);
      expect(counts['peer-B'], 1);
    },
  );

  test('TC-410-14 marking read twice is a no-op the second time', () async {
    final db = await open();
    addTearDown(db.close);
    await insert(db, id: '0', contact: 'peer-A');

    await markCallHistoryRead(db, 'peer-A', DateTime.utc(2026, 2, 9, 17));
    final again = await markCallHistoryRead(
      db,
      'peer-A',
      DateTime.utc(2026, 2, 9, 18),
    );

    expect(again, 0, reason: 'an already-read call must not be re-stamped');
  });

  test(
    'TC-410-15 marking read never touches a call the badge ignores',
    () async {
      final db = await open();
      addTearDown(db.close);
      await insert(
        db,
        id: '0',
        contact: 'peer-A',
        status: 'completed',
        reason: 'local_hangup',
      );

      final marked = await markCallHistoryRead(
        db,
        'peer-A',
        DateTime.utc(2026, 2, 9, 17),
      );

      expect(marked, 0);
      final rows = await db.query(kCallHistoryTable);
      expect(
        rows.single['read_at'],
        isNull,
        reason:
            'only rows the badge could have counted are worth stamping; the '
            'rest stay untouched so the column keeps one meaning',
      );
    },
  );
}
