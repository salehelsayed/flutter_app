import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/migrations/016_message_reactions.dart';
import 'package:flutter_app/core/database/migrations/082_message_reaction_tombstone.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // 082 alters the table created by 016; run the prerequisite first.
    await runMessageReactionsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> columnExists(String column) async {
    final cols = await db.rawQuery('PRAGMA table_info(message_reactions)');
    return cols.any((c) => c['name'] == column);
  }

  test('082 adds the removed_at column', () async {
    expect(await columnExists('removed_at'), isFalse);

    await runMessageReactionTombstoneMigration(db);

    expect(await columnExists('removed_at'), isTrue);
  });

  test('082 is idempotent on re-run', () async {
    await runMessageReactionTombstoneMigration(db);
    await runMessageReactionTombstoneMigration(db);

    expect(await columnExists('removed_at'), isTrue);
  });

  test('082 preserves existing reaction rows (additive)', () async {
    await db.insert('message_reactions', {
      'id': 'r-1',
      'message_id': 'msg-1',
      'emoji': '👍',
      'sender_peer_id': 'peer-1',
      'timestamp': '2026-03-08T00:00:00.000Z',
      'created_at': '2026-03-08T00:00:00.000Z',
    });

    await runMessageReactionTombstoneMigration(db);

    final rows = await db.query('message_reactions');
    expect(rows, hasLength(1));
    expect(rows.single['removed_at'], isNull);
  });
}
