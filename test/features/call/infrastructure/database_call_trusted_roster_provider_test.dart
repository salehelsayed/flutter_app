import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/contacts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _account = 'contact-account';
const _now = '2026-08-30T12:00:00.000Z';

ContactModel _contact({bool blocked = false}) => ContactModel(
  peerId: _account,
  publicKey: 'contact-account-signing-key',
  rendezvous: '/dns4/relay.invalid/tcp/443/wss/p2p/relay',
  username: 'Contact',
  signature: 'contact-signature',
  scannedAt: _now,
  mlKemPublicKey: 'legacy-mlkem-key',
  isBlocked: blocked,
  blockedAt: blocked ? _now : null,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late DatabaseCallTrustedRosterProvider provider;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    provider = DatabaseCallTrustedRosterProvider(db);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  test('loads only key-current ACTIVE linked device authority', () async {
    await dbUpsertContact(db, _contact().toMap());
    await db.insert('direct_contact_device_roster_metadata', <String, Object?>{
      'contact_account_peer_id': _account,
      'roster_initialized': 1,
      'legacy_target_state': 'revoked',
      'initialized_at': _now,
      'legacy_revoked_at': _now,
      'updated_at': _now,
    });
    for (final row in <(String, String, String, String)>[
      ('active-device', 'active-peer', 'active', 'a'),
      ('pending-device', 'pending-peer', 'pending', 'b'),
      ('revoked-device', 'revoked-peer', 'revoked', 'c'),
    ]) {
      await db.insert('direct_contact_device_bindings', <String, Object?>{
        'contact_account_peer_id': _account,
        'device_id': row.$1,
        'verified_account_signing_public_key': 'contact-account-signing-key',
        'transport_peer_id': row.$2,
        'transport_public_key': '${row.$2}-signing-key',
        'device_ml_kem_public_key': '${row.$2}-mlkem-key',
        'binding_fingerprint': row.$4 * 64,
        'state': row.$3,
        'staged_at': _now,
        'decided_at': row.$3 == 'pending' ? null : _now,
      });
    }

    final roster = await provider.loadForContact(_account);

    expect(roster.contactAccepted, isTrue);
    expect(roster.contactBlocked, isFalse);
    expect(roster.devices, hasLength(1));
    expect(roster.devices.single.devicePeerId, 'active-peer');
    expect(roster.devices.single.signingPublicKey, 'active-peer-signing-key');
    expect(roster.devices.single.mlKemPublicKey, 'active-peer-mlkem-key');
    expect(
      roster.devices.single.deviceKeyEpoch,
      callDeviceKeyEpochFromFingerprint('a' * 64),
    );

    final reverse = await provider.resolveAuthenticatedTransport('active-peer');
    expect(reverse?.accountPeerId, _account);
    expect(reverse?.devicePeerId, 'active-peer');
    expect(
      await provider.resolveAuthenticatedTransport('pending-peer'),
      isNull,
    );
  });

  test(
    'legacy authority is current contact data and block wins immediately',
    () async {
      await dbUpsertContact(db, _contact().toMap());

      final legacy = await provider.loadForContact(_account);
      expect(legacy.contactAccepted, isTrue);
      expect(legacy.devices, hasLength(1));
      expect(legacy.devices.single.devicePeerId, _account);
      expect(
        legacy.devices.single.signingPublicKey,
        'contact-account-signing-key',
      );
      expect(
        (await provider.resolveAuthenticatedTransport(_account))?.devicePeerId,
        _account,
      );

      await db.update(
        'contacts',
        <String, Object?>{'is_blocked': 1, 'blocked_at': _now},
        where: 'peer_id = ?',
        whereArgs: <Object?>[_account],
      );
      final blocked = await provider.loadForContact(_account);
      expect(blocked.contactAccepted, isTrue);
      expect(blocked.contactBlocked, isTrue);
      expect(blocked.devices, isEmpty);
      expect(await provider.resolveAuthenticatedTransport(_account), isNull);
    },
  );

  test('unknown contact yields no accepted authority', () async {
    final roster = await provider.loadForContact('unknown-account');

    expect(roster.contactAccepted, isFalse);
    expect(roster.contactBlocked, isFalse);
    expect(roster.devices, isEmpty);
  });

  test('device-key equality epoch uses JSON-safe 53-bit digest width', () {
    final epochs = <int>[
      for (var index = 0; index < 64; index++)
        callDeviceKeyEpochFromFingerprint(
          index.toRadixString(16).padLeft(64, '0'),
        ),
    ];

    expect(epochs.toSet(), hasLength(epochs.length));
    expect(epochs.every((epoch) => epoch >= 0), isTrue);
    expect(epochs.every((epoch) => epoch <= 0x1fffffffffffff), isTrue);
    expect(
      epochs.map((epoch) => epoch.bitLength).reduce((a, b) => a > b ? a : b),
      greaterThanOrEqualTo(50),
    );
    expect(
      callDeviceKeyEpochFromFingerprint('a' * 64),
      isNot(callDeviceKeyEpochFromFingerprint('b' * 64)),
      reason: 'rotated immutable key material must change the equality epoch',
    );
  });
}
