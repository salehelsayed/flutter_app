import 'package:flutter_app/core/database/migrations/046_pending_introduction_responses.dart';
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

  test('creates pending_introduction_responses table', () async {
    await runPendingIntroductionResponsesMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pending_introduction_responses'",
    );
    expect(tables, hasLength(1));

    await db.insert('pending_introduction_responses', {
      'response_key': 'intro-1::peer-b::accept',
      'introduction_id': 'intro-1',
      'action': 'accept',
      'responder_id': 'peer-b',
      'responder_username': 'Bob',
      'created_at': '2026-04-03T10:00:00.000Z',
    });

    final rows = await db.query(
      'pending_introduction_responses',
      where: 'introduction_id = ?',
      whereArgs: ['intro-1'],
      orderBy: 'created_at ASC, response_key ASC',
    );
    expect(rows, hasLength(1));
    expect(rows.single['action'], 'accept');
  });

  test('is idempotent when rerun', () async {
    await runPendingIntroductionResponsesMigration(db);
    await runPendingIntroductionResponsesMigration(db);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'pending_introduction_responses'",
    );
    expect(tables, hasLength(1));
  });
}
