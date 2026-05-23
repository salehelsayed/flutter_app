import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
import 'package:flutter_app/core/database/migrations/071_pending_introduction_response_transport_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'adds and backfills transport sender on old pending response rows',
    () async {
      await db.execute('''
      CREATE TABLE pending_introduction_responses (
        response_key TEXT PRIMARY KEY,
        introduction_id TEXT NOT NULL,
        action TEXT NOT NULL CHECK(action IN ('accept', 'pass')),
        responder_id TEXT NOT NULL,
        responder_username TEXT,
        created_at TEXT NOT NULL
      )
    ''');
      await db.insert('pending_introduction_responses', {
        'response_key': 'intro-1::peer-b::accept',
        'introduction_id': 'intro-1',
        'action': 'accept',
        'responder_id': 'peer-b',
        'responder_username': 'Bob',
        'created_at': '2026-04-03T10:00:00.000Z',
      });

      await runPendingIntroductionResponseTransportSenderMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(pending_introduction_responses)',
      );
      expect(
        columns.map((column) => column['name']),
        contains('transport_sender_peer_id'),
      );

      final rows = await db.query('pending_introduction_responses');
      expect(rows.single['transport_sender_peer_id'], 'peer-b');
    },
  );

  test(
    'is idempotent after the fresh create migration already has the column',
    () async {
      await runPendingIntroductionResponsesMigration(db);
      await runPendingIntroductionResponseTransportSenderMigration(db);
      await runPendingIntroductionResponseTransportSenderMigration(db);

      final columns = await db.rawQuery(
        'PRAGMA table_info(pending_introduction_responses)',
      );
      expect(
        columns
            .where((column) => column['name'] == 'transport_sender_peer_id')
            .length,
        1,
      );
    },
  );
}
