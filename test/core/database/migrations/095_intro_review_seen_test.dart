import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/095_intro_review_seen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
  });

  tearDown(() async {
    await db.close();
  });

  group('Migration 095: intro_review_seen', () {
    test('TC-207-17 creates durable seen-key table', () async {
      await runIntroReviewSeenMigration(db);

      await db.insert('intro_review_seen', {
        'item_key': 'intro:peer-a',
        'seen_at': '2026-07-06T00:00:00.000Z',
      });
      await db.insert('intro_review_seen', {
        'item_key': 'invite:group-a',
        'seen_at': '2026-07-06T00:00:01.000Z',
      });

      final rows = await db.query(
        'intro_review_seen',
        orderBy: 'item_key ASC',
      );
      expect(rows.map((row) => row['item_key']), [
        'intro:peer-a',
        'invite:group-a',
      ]);
    });

    test('TC-207-23 bumps identity database version to at least 95', () {
      // 096 (228 media library state) superseded the head pin; the exact
      // current-version assertion lives in full_migration_chain_test.dart
      // (TC-228-13).
      expect(currentIdentityDatabaseVersion, greaterThanOrEqualTo(95));
    });
  });
}
