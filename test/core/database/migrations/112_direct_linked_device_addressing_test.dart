// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/112_direct_linked_device_addressing.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _contactPeerId = '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
const _contactPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
const _transportPeerId = '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
const _transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
const _timestamp = '2026-08-11T12:00:00.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_linked_device_addressing_v112_',
    );
    upgradePath = '${tempDirectory.path}/upgrade.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('TC-360-01b v112 remote roster migrates while linked installation '
      'authority cannot move', () async {
    // ── v111: author durable rows the upgrade must preserve untouched. ──
    var db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 111,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    await db.insert('contacts', _contactRow());
    await db.insert('messages', _messageRow());
    await db.insert('direct_inbox_custody_outbox', _v108Row());
    final v111Contacts = await db.query('contacts');
    final v111Messages = await db.query('messages');
    final v111Custody = await db.query('direct_inbox_custody_outbox');
    await db.close();

    // ── v111 -> v112. ──
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });

    expect(currentIdentityDatabaseVersion, 116);
    expect(await _userVersion(db), 116);

    // Registered exactly once in both registries, immediately after v111.
    for (final registry in <List<ProductionMigrationEntry>>[
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      final entries = registry.where((entry) => entry.version == 112);
      expect(entries, hasLength(1));
      expect(entries.single.name, '112_direct_linked_device_addressing');
      expect(
        entries.single.run,
        same(runDirectLinkedDeviceAddressingMigration),
      );
      expect(
        registry[registry.indexOf(entries.single) + 1].version,
        113,
        reason: 'v113 event fanout is the only successor',
      );
      final index111 = registry.indexWhere((entry) => entry.version == 111);
      expect(registry.indexOf(entries.single), index111 + 1);
    }

    // Every durable row survives byte-identically. The v113 successor appends
    // nullable fanout columns to messages/v108, so those two compare on the
    // v111 projection with the appended columns proven NULL.
    expect(await db.query('contacts'), v111Contacts);
    expect(_withoutNullV113Columns(await db.query('messages')), v111Messages);
    expect(
      _withoutNullV113Columns(await db.query('direct_inbox_custody_outbox')),
      v111Custody,
    );

    await _expectExactSchema(db);

    // Historical backfill is EMPTY: legacy canonical contact data is never
    // materialized as an immutable binding.
    expect(await db.query('direct_contact_device_bindings'), isEmpty);
    expect(
      await db.query('direct_contact_device_roster_metadata'),
      isEmpty,
      reason:
          'a pre-existing contact must resolve through the unchanged '
          'ContactModel target until a decision is explicitly recorded',
    );

    await _expectBindingConstraints(db);
    await _expectRosterMetadataConstraints(db);

    // Run-twice idempotent.
    await runDirectLinkedDeviceAddressingMigration(db);
    await runDirectLinkedDeviceAddressingMigration(db);
    await _expectExactSchema(db);
    expect(await _userVersion(db), 116);

    // Stage one real binding, then prove reopen preserves it and that v112
    // is a one-way floor.
    expect(
      await dbStageDirectContactDeviceBinding(
        db,
        contactAccountPeerId: _contactPeerId,
        accountSigningPublicKey: _contactPublicKey,
        deviceId: 'device-alpha',
        transportPeerId: _transportPeerId,
        transportPublicKey: _transportPublicKey,
        deviceMlKemPublicKey: 'mlkem-alpha',
        stagedAt: _timestamp,
      ),
      DirectContactDeviceBindingStageOutcome.staged,
    );
    final snapshot = await db.query(
      'direct_contact_device_bindings',
      orderBy: 'device_id',
    );
    expect(snapshot, hasLength(1));

    await db.close();
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    expect(await _userVersion(db), 116);
    expect(
      await db.query('direct_contact_device_bindings', orderBy: 'device_id'),
      snapshot,
    );

    // One-way local floor: an older binary opening at v111 fails closed.
    await db.close();
    await expectLater(
      databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 111,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    expect(await _userVersion(db), 116);
    expect(
      await db.query('direct_contact_device_bindings', orderBy: 'device_id'),
      snapshot,
    );
  });
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.single.values.first! as int;
}

const _v113Columns = <String>{
  'direct_event_fanout_generation_id',
  'contact_account_peer_id',
  'parent_message_id',
};

List<Map<String, Object?>> _withoutNullV113Columns(
  List<Map<String, Object?>> rows,
) => rows
    .map((row) {
      final projected = Map<String, Object?>.from(row);
      for (final column in _v113Columns) {
        expect(
          projected.remove(column),
          isNull,
          reason: 'v113 never promotes historical rows ($column)',
        );
      }
      return projected;
    })
    .toList(growable: false);

Future<void> _expectExactSchema(Database db) async {
  final bindingColumns = await db.rawQuery(
    'PRAGMA table_info(direct_contact_device_bindings)',
  );
  expect(bindingColumns.map((column) => column['name']), const <String>[
    'contact_account_peer_id',
    'device_id',
    'verified_account_signing_public_key',
    'transport_peer_id',
    'transport_public_key',
    'device_ml_kem_public_key',
    'binding_fingerprint',
    'state',
    'staged_at',
    'decided_at',
  ]);

  // No FK cascade to `contacts`: ordinary contact upsert uses REPLACE
  // semantics, so a cascade would destroy verified authority on a routine
  // key re-announce.
  expect(
    await db.rawQuery(
      'PRAGMA foreign_key_list(direct_contact_device_bindings)',
    ),
    isEmpty,
  );
  expect(
    await db.rawQuery(
      'PRAGMA foreign_key_list(direct_contact_device_roster_metadata)',
    ),
    isEmpty,
  );

  final indexRows = await db.rawQuery(
    'PRAGMA index_list(direct_contact_device_bindings)',
  );
  final transportIndex = indexRows.firstWhere(
    (row) =>
        row['name'] == 'idx_direct_contact_device_bindings_transport_owner',
  );
  expect(
    transportIndex['unique'],
    1,
    reason: 'one transport peer belongs to exactly one linked device globally',
  );
  expect(
    indexRows.map((row) => row['name']),
    contains('idx_direct_contact_device_bindings_contact_state'),
  );

  final metadataColumns = await db.rawQuery(
    'PRAGMA table_info(direct_contact_device_roster_metadata)',
  );
  expect(metadataColumns.map((column) => column['name']), const <String>[
    'contact_account_peer_id',
    'roster_initialized',
    'legacy_target_state',
    'initialized_at',
    'legacy_revoked_at',
    'updated_at',
  ]);
}

Future<void> _expectBindingConstraints(Database db) async {
  Future<void> expectRejected(
    Map<String, Object?> overrides,
    String reason,
  ) async {
    await expectLater(
      db.insert('direct_contact_device_bindings', <String, Object?>{
        ..._bindingRow(),
        ...overrides,
      }),
      throwsA(isA<DatabaseException>()),
      reason: reason,
    );
  }

  await expectRejected(<String, Object?>{
    'transport_peer_id': _contactPeerId,
  }, 'a linked device is never the contact account transport');
  await expectRejected(<String, Object?>{
    'transport_public_key': _contactPublicKey,
  }, 'a device never reuses the account signing key as its transport key');
  await expectRejected(<String, Object?>{
    'state': 'unknown',
  }, 'state is a closed set');
  await expectRejected(<String, Object?>{
    'state': 'active',
    'decided_at': null,
  }, 'only pending may lack a decision timestamp');
  await expectRejected(<String, Object?>{
    'state': 'pending',
    'decided_at': _timestamp,
  }, 'pending must have no decision timestamp');
  await expectRejected(<String, Object?>{
    'binding_fingerprint': 'not-a-sha256',
  }, 'the fingerprint must be exactly 64 lowercase hex characters');
  await expectRejected(<String, Object?>{
    'device_id': '  ',
  }, 'device ids must be non-blank and trimmed');

  // Duplicate transport owner across DIFFERENT contacts is refused by the
  // unique index, not merely by the helper.
  await db.insert('direct_contact_device_bindings', _bindingRow());
  await expectLater(
    db.insert('direct_contact_device_bindings', <String, Object?>{
      ..._bindingRow(),
      'contact_account_peer_id': 'other-account-peer',
      'device_id': 'device-beta',
    }),
    throwsA(isA<DatabaseException>()),
    reason: 'two contacts cannot claim the same transport owner',
  );
  await db.delete('direct_contact_device_bindings');
}

Future<void> _expectRosterMetadataConstraints(Database db) async {
  Future<void> expectRejected(
    Map<String, Object?> overrides,
    String reason,
  ) async {
    await expectLater(
      db.insert('direct_contact_device_roster_metadata', <String, Object?>{
        ..._metadataRow(),
        ...overrides,
      }),
      throwsA(isA<DatabaseException>()),
      reason: reason,
    );
  }

  await expectRejected(<String, Object?>{
    'roster_initialized': 0,
    'initialized_at': _timestamp,
  }, 'an uninitialized roster cannot carry an initialization timestamp');
  await expectRejected(<String, Object?>{
    'roster_initialized': 1,
    'initialized_at': null,
  }, 'an initialized roster must record when');
  await expectRejected(<String, Object?>{
    'legacy_target_state': 'revoked',
    'legacy_revoked_at': null,
  }, 'a revoked legacy target must record when');
  await expectRejected(<String, Object?>{
    'roster_initialized': 0,
    'initialized_at': null,
    'legacy_target_state': 'revoked',
    'legacy_revoked_at': _timestamp,
  }, 'the legacy target can only be revoked inside an initialized roster');
}

Map<String, Object?> _bindingRow() => <String, Object?>{
  'contact_account_peer_id': _contactPeerId,
  'device_id': 'device-alpha',
  'verified_account_signing_public_key': _contactPublicKey,
  'transport_peer_id': _transportPeerId,
  'transport_public_key': _transportPublicKey,
  'device_ml_kem_public_key': 'mlkem-alpha',
  'binding_fingerprint': 'a' * 64,
  'state': 'pending',
  'staged_at': _timestamp,
  'decided_at': null,
};

Map<String, Object?> _metadataRow() => <String, Object?>{
  'contact_account_peer_id': _contactPeerId,
  'roster_initialized': 1,
  'legacy_target_state': 'active',
  'initialized_at': _timestamp,
  'legacy_revoked_at': null,
  'updated_at': _timestamp,
};

Map<String, Object?> _contactRow() => <String, Object?>{
  'peer_id': _contactPeerId,
  'public_key': _contactPublicKey,
  'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
  'username': 'Alice',
  'signature': 'sig-base64',
  'scanned_at': _timestamp,
  'ml_kem_public_key': 'legacy-mlkem',
};

Map<String, Object?> _messageRow() => const <String, Object?>{
  'id': 'message-1',
  'contact_peer_id': _contactPeerId,
  'sender_peer_id': 'peer-self',
  'text': 'historical direct text',
  'timestamp': _timestamp,
  'status': 'sent',
  'is_incoming': 0,
  'created_at': _timestamp,
};

Map<String, Object?> _v108Row() => const <String, Object?>{
  'recipient_peer_id': _contactPeerId,
  'message_id': 'message-1',
  'incarnation_id': '0123456789abcdef0123456789abcdef',
  'wire_envelope': '{"type":"chat","v":2}',
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};
