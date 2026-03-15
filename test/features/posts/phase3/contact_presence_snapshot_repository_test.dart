import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/post_location_presence_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/027_posts_core.dart';
import 'package:flutter_app/core/database/migrations/028_posts_engagement.dart';
import 'package:flutter_app/core/database/migrations/029_posts_nearby.dart';
import 'package:flutter_app/features/posts/domain/models/contact_presence_snapshot.dart';
import 'package:flutter_app/features/posts/domain/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late ContactPresenceSnapshotRepositoryImpl repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runPostsCoreMigration(db);
    await runPostsEngagementMigration(db);
    await runPostsNearbyMigration(db);
    repository = ContactPresenceSnapshotRepositoryImpl(
      dbLoadPostLocationPresence: (peerId) =>
          dbLoadPostLocationPresence(db, peerId),
      dbLoadAllPostLocationPresence: () => dbLoadAllPostLocationPresence(db),
      dbUpsertPostLocationPresence: (row) =>
          dbUpsertPostLocationPresence(db, row),
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  test('persists active friend snapshots', () async {
    await repository.save(
      const ContactPresenceSnapshot(
        peerId: 'peer-bob',
        status: ContactPresenceSnapshotStatus.active,
        latE3: 52520,
        lngE3: 13405,
        capturedAt: '2026-03-15T11:10:00.000Z',
        accuracyM: 120,
        updatedAt: '2026-03-15T11:10:05.000Z',
      ),
    );

    final snapshot = await repository.load('peer-bob');

    expect(snapshot, isNotNull);
    expect(snapshot!.status, ContactPresenceSnapshotStatus.active);
    expect(snapshot.latE3, 52520);
    expect(snapshot.lngE3, 13405);
  });

  test('persists inactive snapshots without coordinates', () async {
    await repository.save(
      const ContactPresenceSnapshot(
        peerId: 'peer-bob',
        status: ContactPresenceSnapshotStatus.inactive,
        capturedAt: '2026-03-15T11:15:00.000Z',
        updatedAt: '2026-03-15T11:15:05.000Z',
      ),
    );

    final snapshot = await repository.load('peer-bob');

    expect(snapshot, isNotNull);
    expect(snapshot!.status, ContactPresenceSnapshotStatus.inactive);
    expect(snapshot.latE3, isNull);
    expect(snapshot.lngE3, isNull);
  });
}
