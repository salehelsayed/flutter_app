import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/pending_sibling_devices_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/085_pending_sibling_devices.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await runPendingSiblingDevicesMigration(db);
  });

  tearDown(() => db.close());

  Map<String, Object?> row({String deviceId = 'bob-tablet'}) => {
    'group_id': 'g1',
    'member_peer_id': 'bob',
    'device_id': deviceId,
    'transport_peer_id': deviceId,
    'device_signing_public_key': 'sign',
    'ml_kem_public_key': 'mlkem',
    'key_package_id': null,
    'verified_account_signing_public_key': 'pk-bob',
    'announced_at': '2026-06-17T00:00:00.000Z',
  };

  test('upsert + load-for-group + delete round-trip', () async {
    await dbUpsertPendingSiblingDevice(db, row());
    await dbUpsertPendingSiblingDevice(db, row(deviceId: 'bob-laptop'));

    final all = await dbLoadPendingSiblingDevicesForGroup(db, 'g1');
    expect(all, hasLength(2));

    final one = await dbLoadPendingSiblingDevice(db, 'g1', 'bob', 'bob-tablet');
    expect(one!['device_signing_public_key'], 'sign');

    await dbDeletePendingSiblingDevice(db, 'g1', 'bob', 'bob-tablet');
    expect(await dbLoadPendingSiblingDevice(db, 'g1', 'bob', 'bob-tablet'), isNull);
    expect(await dbLoadPendingSiblingDevicesForGroup(db, 'g1'), hasLength(1));
  });

  test('upsert replaces on the (group,member,device) primary key', () async {
    await dbUpsertPendingSiblingDevice(db, row());
    await dbUpsertPendingSiblingDevice(db, {
      ...row(),
      'verified_account_signing_public_key': 'pk-bob-2',
    });
    final all = await dbLoadPendingSiblingDevicesForGroup(db, 'g1');
    expect(all, hasLength(1));
    expect(all.single['verified_account_signing_public_key'], 'pk-bob-2');
  });
}
