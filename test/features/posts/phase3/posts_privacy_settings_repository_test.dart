import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_privacy_state_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/features/posts/domain/models/posts_privacy_settings.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late PostsPrivacySettingsRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsNearbyMigration(db);
    repository = PostsPrivacySettingsRepositoryImpl(
      dbLoadPostPrivacyState: () => dbLoadPostPrivacyState(db),
      dbUpsertPostPrivacyState: (row) => dbUpsertPostPrivacyState(db, row),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('loads the default nearby sharing state from the database', () async {
    final settings = await repository.load();

    expect(settings.sharingEnabled, isFalse);
    expect(settings.permissionState, PostsLocationPermissionState.unknown);
  });

  test('persists updated nearby sharing state', () async {
    await repository.save(
      const PostsPrivacySettings(
        sharingEnabled: true,
        permissionState: PostsLocationPermissionState.granted,
        lastLocalLatE3: 52520,
        lastLocalLngE3: 13405,
        lastLocalCapturedAt: '2026-03-15T09:30:00.000Z',
        lastLocalAccuracyM: 120,
        lastRefreshAttemptAt: '2026-03-15T09:30:05.000Z',
      ),
    );

    final settings = await repository.load();

    expect(settings.sharingEnabled, isTrue);
    expect(settings.permissionState, PostsLocationPermissionState.granted);
    expect(settings.lastLocalLatE3, 52520);
    expect(settings.lastLocalLngE3, 13405);
    expect(settings.lastLocalCapturedAt, '2026-03-15T09:30:00.000Z');
    expect(settings.lastLocalAccuracyM, 120);
  });
}
