import 'package:flutter_app/core/database/helpers/group_welcome_key_package_tombstones_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/064_group_welcome_key_package_tombstones.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
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
    await runGroupWelcomeKeyPackageTombstonesMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'upserts and loads package tombstones by package device and group',
    () async {
      final consumedAt = DateTime.utc(2026, 4, 29, 12);
      final tombstone = GroupWelcomeKeyPackageTombstone(
        packageId: 'package-1',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
        inviteId: 'invite-1',
        publicMaterialHash: 'a'.padRight(64, 'a'),
        consumedAt: consumedAt,
        expiresAt: consumedAt.add(const Duration(days: 7)),
      );

      await dbUpsertGroupWelcomeKeyPackageTombstone(db, tombstone.toMap());
      final row = await dbLoadGroupWelcomeKeyPackageTombstone(
        db,
        packageId: 'package-1',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
      );

      expect(row, isNotNull);
      expect(row!['invite_id'], 'invite-1');
    },
  );

  test('deleteExpired removes expired package tombstones only', () async {
    await dbUpsertGroupWelcomeKeyPackageTombstone(
      db,
      GroupWelcomeKeyPackageTombstone(
        packageId: 'expired-package',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
        inviteId: 'invite-expired',
        publicMaterialHash: 'b'.padRight(64, 'b'),
        consumedAt: DateTime.utc(2026, 4, 1),
        expiresAt: DateTime.utc(2026, 4, 8),
      ).toMap(),
    );
    await dbUpsertGroupWelcomeKeyPackageTombstone(
      db,
      GroupWelcomeKeyPackageTombstone(
        packageId: 'fresh-package',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
        inviteId: 'invite-fresh',
        publicMaterialHash: 'c'.padRight(64, 'c'),
        consumedAt: DateTime.utc(2026, 4, 5),
        expiresAt: DateTime.utc(2026, 4, 12),
      ).toMap(),
    );

    final deleted = await dbDeleteExpiredGroupWelcomeKeyPackageTombstones(
      db,
      DateTime.utc(2026, 4, 10).toIso8601String(),
    );

    expect(deleted, 1);
    expect(
      await dbLoadGroupWelcomeKeyPackageTombstone(
        db,
        packageId: 'expired-package',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
      ),
      isNull,
    );
    expect(
      await dbLoadGroupWelcomeKeyPackageTombstone(
        db,
        packageId: 'fresh-package',
        recipientDeviceId: 'device-1',
        groupId: 'group-1',
      ),
      isNotNull,
    );
  });
}
