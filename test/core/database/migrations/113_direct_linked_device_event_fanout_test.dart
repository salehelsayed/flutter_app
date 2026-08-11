// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/113_direct_linked_device_event_fanout.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _contactPeerId = '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
const _contactPublicKey = 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=';
const _transportPeerId = '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
const _transportPublicKey = 'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=';
const _timestamp = '2026-08-11T12:00:00.000Z';

const _newV108Columns = <String>['contact_account_peer_id'];
const _newV109Columns = <String>[
  'contact_account_peer_id',
  'parent_message_id',
];
const _newMessageColumns = <String>['direct_event_fanout_generation_id'];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_linked_device_event_fanout_v113_',
    );
    upgradePath = '${tempDirectory.path}/upgrade.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('TC-361-01a v113 adds only nullable blob-free fanout facts and stays '
      'a one-way floor', () async {
    // ── v112: author durable rows the upgrade must preserve untouched,
    // including a parentless/contactless historical v109 deletion event and
    // v111 blob bindings. ──
    var db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 112,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    await db.insert('contacts', _contactRow());
    await db.insert('messages', _messageRow());
    await db.insert('direct_inbox_custody_outbox', _v108Row());
    await db.insert('direct_reaction_inbox_custody_outbox', _v109DeletionRow());
    await db.insert('direct_media_blob_custody', _v111Row());
    await db.insert('direct_contact_device_bindings', _bindingRow());
    await db.insert('direct_contact_device_roster_metadata', _metadataRow());

    final v112Contacts = await db.query('contacts');
    final v112Messages = await db.query('messages');
    final v112Custody = await db.query('direct_inbox_custody_outbox');
    final v112Events = await db.query('direct_reaction_inbox_custody_outbox');
    final v112Blobs = await db.query('direct_media_blob_custody');
    final v112Bindings = await db.query('direct_contact_device_bindings');
    final v112Roster = await db.query('direct_contact_device_roster_metadata');
    final v112MessageColumns = await _columnNames(db, 'messages');
    final v112CustodyColumns = await _columnNames(
      db,
      'direct_inbox_custody_outbox',
    );
    final v112EventColumns = await _columnNames(
      db,
      'direct_reaction_inbox_custody_outbox',
    );
    expect(v112MessageColumns, isNot(containsAll(_newMessageColumns)));
    expect(v112CustodyColumns, isNot(containsAll(_newV108Columns)));
    expect(v112EventColumns, isNot(containsAll(_newV109Columns)));
    await db.close();

    // ── v112 -> v113. ──
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

    expect(currentIdentityDatabaseVersion, 113);
    expect(await _userVersion(db), 113);

    // Registered exactly once in both registries, immediately after v112.
    for (final registry in <List<ProductionMigrationEntry>>[
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      final entries = registry.where((entry) => entry.version == 113);
      expect(entries, hasLength(1));
      expect(entries.single.name, '113_direct_linked_device_event_fanout');
      expect(
        entries.single.run,
        same(runDirectLinkedDeviceEventFanoutMigration),
      );
      expect(registry.last, same(entries.single));
      final index112 = registry.indexWhere((entry) => entry.version == 112);
      expect(registry.indexOf(entries.single), index112 + 1);
    }

    // Additive only: exactly the four new nullable columns, appended, with
    // every pre-existing column preserved in order (no table rebuild).
    expect(await _columnNames(db, 'messages'), <String>[
      ...v112MessageColumns,
      ..._newMessageColumns,
    ]);
    expect(await _columnNames(db, 'direct_inbox_custody_outbox'), <String>[
      ...v112CustodyColumns,
      ..._newV108Columns,
    ]);
    expect(
      await _columnNames(db, 'direct_reaction_inbox_custody_outbox'),
      <String>[...v112EventColumns, ..._newV109Columns],
    );

    // Every durable row survives byte-identically: old columns untouched and
    // every new column NULL — historical rows are never promoted or guessed.
    expect(await db.query('contacts'), v112Contacts);
    expect(await db.query('direct_media_blob_custody'), v112Blobs);
    expect(await db.query('direct_contact_device_bindings'), v112Bindings);
    expect(await db.query('direct_contact_device_roster_metadata'), v112Roster);
    _expectPreservedWithNullNewColumns(
      await db.query('messages'),
      v112Messages,
      _newMessageColumns,
    );
    _expectPreservedWithNullNewColumns(
      await db.query('direct_inbox_custody_outbox'),
      v112Custody,
      _newV108Columns,
    );
    _expectPreservedWithNullNewColumns(
      await db.query('direct_reaction_inbox_custody_outbox'),
      v112Events,
      _newV109Columns,
    );

    // A historical v109 deletion keeps NULL parent/contact even though its
    // parent message and contact still exist — no backfill, no guessing.
    final historicalDeletion = (await db.query(
      'direct_reaction_inbox_custody_outbox',
      where: 'event_id = ?',
      whereArgs: const <Object?>['historical-deletion-event'],
    )).single;
    expect(historicalDeletion['contact_account_peer_id'], isNull);
    expect(historicalDeletion['parent_message_id'], isNull);

    await _expectExactSchema(db);
    await _expectColumnConstraints(db);

    // Run-twice idempotent.
    await runDirectLinkedDeviceEventFanoutMigration(db);
    await runDirectLinkedDeviceEventFanoutMigration(db);
    await _expectExactSchema(db);
    expect(await _userVersion(db), 113);

    // Author one real fanout-marked row set, then prove reopen preserves it
    // and that v113 is a one-way floor.
    await db.insert('direct_inbox_custody_outbox', <String, Object?>{
      ..._v108Row(),
      'message_id': 'fanout-message-1',
      'incarnation_id': '11111111111111111111111111111111',
      'recipient_peer_id': _transportPeerId,
      'contact_account_peer_id': _contactPeerId,
    });
    await db.insert('direct_reaction_inbox_custody_outbox', <String, Object?>{
      ..._v109DeletionRow(),
      'event_id': 'fanout-event-1',
      'recipient_peer_id': _transportPeerId,
      'contact_account_peer_id': _contactPeerId,
      'parent_message_id': 'message-1',
    });
    await db.update(
      'messages',
      const <String, Object?>{'direct_event_fanout_generation_id': 'message-1'},
      where: 'id = ?',
      whereArgs: const <Object?>['message-1'],
    );
    final markedCustody = await db.query(
      'direct_inbox_custody_outbox',
      orderBy: 'message_id',
    );
    final markedEvents = await db.query(
      'direct_reaction_inbox_custody_outbox',
      orderBy: 'event_id',
    );
    final markedMessages = await db.query('messages', orderBy: 'id');

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
    expect(await _userVersion(db), 113);
    expect(
      await db.query('direct_inbox_custody_outbox', orderBy: 'message_id'),
      markedCustody,
    );
    expect(
      await db.query(
        'direct_reaction_inbox_custody_outbox',
        orderBy: 'event_id',
      ),
      markedEvents,
    );
    expect(await db.query('messages', orderBy: 'id'), markedMessages);

    // One-way local floor: an older binary opening at v112 fails closed and
    // leaves every row untouched.
    await db.close();
    await expectLater(
      databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 112,
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
    expect(await _userVersion(db), 113);
    expect(
      await db.query('direct_inbox_custody_outbox', orderBy: 'message_id'),
      markedCustody,
    );

    // Fresh v113 create produces the same schema through the same registry.
    final freshPath = '${tempDirectory.path}/fresh.db';
    final fresh = await databaseFactoryFfi.openDatabase(
      freshPath,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    addTearDown(() async {
      if (fresh.isOpen) await fresh.close();
    });
    expect(await _userVersion(fresh), 113);
    expect(
      await _columnNames(fresh, 'messages'),
      containsAll(_newMessageColumns),
    );
    expect(
      await _columnNames(fresh, 'direct_inbox_custody_outbox'),
      containsAll(_newV108Columns),
    );
    expect(
      await _columnNames(fresh, 'direct_reaction_inbox_custody_outbox'),
      containsAll(_newV109Columns),
    );
    await _expectExactSchema(fresh);
  });
}

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.single.values.first! as int;
}

Future<List<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toList(growable: false);
}

void _expectPreservedWithNullNewColumns(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> before,
  List<String> newColumns,
) {
  expect(current, hasLength(before.length));
  for (var index = 0; index < before.length; index++) {
    final row = current[index];
    for (final column in newColumns) {
      expect(
        row[column],
        isNull,
        reason: 'historical rows are never promoted ($column)',
      );
    }
    final projected = Map<String, Object?>.from(row)
      ..removeWhere((key, _) => newColumns.contains(key));
    expect(projected, before[index]);
  }
}

Future<void> _expectExactSchema(Database db) async {
  // No FK was added anywhere: the no-FK lifetime of both outboxes is a frozen
  // schema decision.
  for (final table in const <String>[
    'messages',
    'direct_inbox_custody_outbox',
    'direct_reaction_inbox_custody_outbox',
  ]) {
    expect(
      await db.rawQuery('PRAGMA foreign_key_list($table)'),
      isEmpty,
      reason: '$table must stay FK-free',
    );
  }

  // v108 keeps its PK and unique incarnation; both tables gain exactly one
  // non-unique generation-first lookup index.
  final custodyIndexes = await db.rawQuery(
    'PRAGMA index_list(direct_inbox_custody_outbox)',
  );
  final generationIndex = custodyIndexes.firstWhere(
    (row) => row['name'] == 'idx_direct_inbox_custody_outbox_generation',
    orElse: () => throw StateError('missing v108 generation index'),
  );
  expect(generationIndex['unique'], 0);
  expect(
    (await db.rawQuery(
      "PRAGMA index_info('idx_direct_inbox_custody_outbox_generation')",
    )).map((row) => row['name']),
    const <String>['message_id'],
  );
  expect(
    custodyIndexes.map((row) => row['name']),
    contains('idx_direct_inbox_custody_outbox_fair_load'),
  );

  final eventIndexes = await db.rawQuery(
    'PRAGMA index_list(direct_reaction_inbox_custody_outbox)',
  );
  final eventGenerationIndex = eventIndexes.firstWhere(
    (row) =>
        row['name'] == 'idx_direct_reaction_inbox_custody_outbox_generation',
    orElse: () => throw StateError('missing v109 generation index'),
  );
  expect(eventGenerationIndex['unique'], 0);
  expect(
    (await db.rawQuery(
      "PRAGMA index_info('idx_direct_reaction_inbox_custody_outbox_generation')",
    )).map((row) => row['name']),
    const <String>['event_id'],
  );

  // The unique incarnation constraint survives untouched.
  await db.insert('direct_inbox_custody_outbox', <String, Object?>{
    ..._v108Row(),
    'message_id': 'incarnation-probe',
    'recipient_peer_id': 'peer-incarnation-probe',
    'incarnation_id': '33333333333333333333333333333333',
  });
  await expectLater(
    db.insert('direct_inbox_custody_outbox', <String, Object?>{
      ..._v108Row(),
      'message_id': 'incarnation-probe-2',
      'recipient_peer_id': 'peer-incarnation-probe-2',
      'incarnation_id': '33333333333333333333333333333333',
    }),
    throwsA(isA<DatabaseException>()),
    reason: 'fanout preserves the globally unique v108 incarnation',
  );
  await db.delete(
    'direct_inbox_custody_outbox',
    where: 'message_id = ?',
    whereArgs: const <Object?>['incarnation-probe'],
  );
}

Future<void> _expectColumnConstraints(Database db) async {
  // Each added TEXT column is NULL or nonblank via a column-local CHECK.
  Future<void> expectRejected(
    String table,
    Map<String, Object?> row,
    String reason,
  ) async {
    await expectLater(
      db.insert(table, row),
      throwsA(isA<DatabaseException>()),
      reason: reason,
    );
  }

  await expectRejected(
    'direct_inbox_custody_outbox',
    <String, Object?>{
      ..._v108Row(),
      'message_id': 'blank-contact-probe',
      'incarnation_id': '22222222222222222222222222222222',
      'recipient_peer_id': 'peer-blank-contact-probe',
      'contact_account_peer_id': '   ',
    },
    'a blank logical contact is refused by the column CHECK',
  );
  await expectRejected(
    'direct_reaction_inbox_custody_outbox',
    <String, Object?>{
      ..._v109DeletionRow(),
      'event_id': 'blank-contact-event',
      'contact_account_peer_id': '',
    },
    'a blank v109 logical contact is refused by the column CHECK',
  );
  await expectRejected(
    'direct_reaction_inbox_custody_outbox',
    <String, Object?>{
      ..._v109DeletionRow(),
      'event_id': 'blank-parent-event',
      'parent_message_id': '   ',
    },
    'a blank v109 parent is refused by the column CHECK',
  );
  await expectLater(
    db.update(
      'messages',
      const <String, Object?>{'direct_event_fanout_generation_id': ' '},
      where: 'id = ?',
      whereArgs: const <Object?>['message-1'],
    ),
    throwsA(isA<DatabaseException>()),
    reason: 'a blank generation is refused by the column CHECK',
  );
}

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

/// A historical deletion event: the clear outer envelope does not disclose its
/// target message, and pre-v113 rows have no parent/contact columns at all.
Map<String, Object?> _v109DeletionRow() => const <String, Object?>{
  'recipient_peer_id': _contactPeerId,
  'event_id': 'historical-deletion-event',
  'wire_envelope': '{"type":"message_deletion","version":"2"}',
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _v111Row() => const <String, Object?>{
  'attachment_id': 'attachment-1',
  'message_id': 'media-message-1',
  'direction': 'outgoing',
  'state': 'outgoing_stored',
  'inbox_custody_incarnation_id': 'fedcba9876543210fedcba9876543210',
  'recipient_peer_id': _contactPeerId,
  'ciphertext_relative_path':
      'direct_media_blob_custody_v1/media-message-1/attachment-1.bin',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash':
      '1111111111111111111111111111111111111111111111111111111111111111',
  'ciphertext_size': 1024,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': 1754899200000,
  'custody_relay_peer_id': 'peer-relay',
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _bindingRow() => <String, Object?>{
  'contact_account_peer_id': _contactPeerId,
  'device_id': 'device-alpha',
  'verified_account_signing_public_key': _contactPublicKey,
  'transport_peer_id': _transportPeerId,
  'transport_public_key': _transportPublicKey,
  'device_ml_kem_public_key': 'mlkem-alpha',
  'binding_fingerprint': 'a' * 64,
  'state': 'active',
  'staged_at': _timestamp,
  'decided_at': _timestamp,
};

Map<String, Object?> _metadataRow() => <String, Object?>{
  'contact_account_peer_id': _contactPeerId,
  'roster_initialized': 1,
  'legacy_target_state': 'active',
  'initialized_at': _timestamp,
  'legacy_revoked_at': null,
  'updated_at': _timestamp,
};
