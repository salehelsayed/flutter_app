import 'package:flutter_app/core/database/helpers/intro_review_seen_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/095_intro_review_seen.dart';
import 'package:flutter_app/features/introduction/data/repositories/intro_review_seen_repository_impl.dart';
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
    await runIntroReviewSeenMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  IntroReviewSeenRepositoryImpl buildRepository() {
    return IntroReviewSeenRepositoryImpl(
      dbLoadSeenKeys: () => dbLoadIntroReviewSeenKeys(db),
      dbMarkAllSeen: (keys, seenAt) =>
          dbMarkIntroReviewItemsSeen(db, keys, seenAt),
    );
  }

  group('IntroReviewSeenRepository (TC-207-16)', () {
    test('reopens persisted intro and invite seen keys', () async {
      final repository = buildRepository();

      await repository.markAllSeen({'intro:peer-a', 'invite:group-a'});

      final reopened = buildRepository();
      expect(await reopened.loadSeenKeys(), {'intro:peer-a', 'invite:group-a'});
    });

    test('markAllSeen is idempotent and replaces seen timestamps', () async {
      final repository = buildRepository();

      await repository.markAllSeen({'intro:peer-a'});
      await repository.markAllSeen({'intro:peer-a', 'invite:group-a'});

      expect(await repository.loadSeenKeys(), {
        'intro:peer-a',
        'invite:group-a',
      });
      final rows = await db.query('intro_review_seen');
      expect(rows.length, 2);
    });
  });
}
