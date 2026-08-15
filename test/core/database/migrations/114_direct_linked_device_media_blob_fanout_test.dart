// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/114_direct_linked_device_media_blob_fanout.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _contactPeerId = '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj';
const _linkedTransportPeerId =
    '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR';
const _timestamp = '2026-08-12T12:00:00.000Z';
const _contentHash =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _newCustodyColumns = <String>[
  'contact_account_peer_id',
  'recipient_ml_kem_public_key',
];
const _newAttachmentColumns = <String>[
  'direct_media_blob_custody_fingerprint_version',
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_linked_device_media_blob_fanout_v114_',
    );
    upgradePath = '${tempDirectory.path}/upgrade.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('TC-362-01a v114 rebuilds only v111 into natural target identity, '
      'rolls back atomically and stays a one-way floor', () async {
    // ── v113: author durable legacy rows the rebuild must copy untouched —
    // one bound outgoing legacy row and one incoming row, plus the strict
    // attachment lineage they belong to. ──
    var db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 113,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    await db.insert('contacts', _contactRow());
    await db.insert('messages', _messageRow('media-message-1'));
    await db.insert('messages', <String, Object?>{
      ..._messageRow('media-message-2'),
      'is_incoming': 1,
      'sender_peer_id': _contactPeerId,
    });
    await db.insert('media_attachments', _attachmentRow('attachment-legacy'));
    await db.insert(
      'media_attachments',
      _attachmentRow('attachment-incoming', messageId: 'media-message-2'),
    );
    await db.insert('direct_media_blob_custody', _legacyOutgoingStoredRow());
    await db.insert('direct_media_blob_custody', _legacyIncomingRow());

    final v113Custody = await db.query(
      'direct_media_blob_custody',
      orderBy: 'attachment_id',
    );
    final v113Attachments = await db.query('media_attachments', orderBy: 'id');
    final v113CustodyColumns = await _columnNames(
      db,
      'direct_media_blob_custody',
    );
    expect(v113CustodyColumns, isNot(containsAll(_newCustodyColumns)));
    expect(
      await _columnNames(db, 'media_attachments'),
      isNot(containsAll(_newAttachmentColumns)),
    );
    // v113 identity: attachment_id is the sole PRIMARY KEY, so a second
    // exact target for the same canonical attachment cannot exist yet.
    await expectLater(
      db.insert('direct_media_blob_custody', <String, Object?>{
        ..._legacyOutgoingStoredRow(),
        'recipient_peer_id': _linkedTransportPeerId,
      }),
      throwsA(isA<DatabaseException>()),
      reason: 'v113 cannot represent a sibling target',
    );

    // ── Injected rebuild failure: a pre-existing blocker under the rebuild
    // name makes the copy fail, and table, indexes, user version and the
    // attachment fingerprint schema must all roll back together. ──
    await db.execute(
      'CREATE TABLE direct_media_blob_custody_v114_rebuild (blocker TEXT)',
    );
    await db.close();
    await expectLater(
      databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 114,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      ),
      throwsA(anything),
      reason: 'a failed rebuild copy must abort the migration',
    );
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 113,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    expect(await _userVersion(db), 113, reason: 'user version rolled back');
    expect(
      await db.query('direct_media_blob_custody', orderBy: 'attachment_id'),
      v113Custody,
      reason: 'rolled-back rebuild leaves every v111 row byte-identical',
    );
    expect(
      await _columnNames(db, 'media_attachments'),
      isNot(containsAll(_newAttachmentColumns)),
      reason: 'the attachment fingerprint schema rolled back with the table',
    );
    await db.execute('DROP TABLE direct_media_blob_custody_v114_rebuild');
    await db.close();

    // ── Real v113 -> v114 rebuild. ──
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 114,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });

    expect(currentIdentityDatabaseVersion, 115);
    expect(await _userVersion(db), 114);

    // Registered exactly once in both registries, immediately after v113;
    // v115 is now the sole successor in the chain.
    for (final registry in <List<ProductionMigrationEntry>>[
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      final entries = registry.where((entry) => entry.version == 114);
      expect(entries, hasLength(1));
      expect(entries.single.name, '114_direct_linked_device_media_blob_fanout');
      expect(
        entries.single.run,
        same(runDirectLinkedDeviceMediaBlobFanoutMigration),
      );
      final index113 = registry.indexWhere((entry) => entry.version == 113);
      expect(registry.indexOf(entries.single), index113 + 1);
      expect(registry[registry.indexOf(entries.single) + 1].version, 115);
    }

    // The rebuild appends exactly the two nullable linked columns after
    // recipient_peer_id and keeps every other column in declaration order.
    expect(await _columnNames(db, 'direct_media_blob_custody'), <String>[
      'attachment_id',
      'message_id',
      'direction',
      'state',
      'inbox_custody_incarnation_id',
      'recipient_peer_id',
      'contact_account_peer_id',
      'recipient_ml_kem_public_key',
      'ciphertext_relative_path',
      'custody_kind',
      'custody_contract',
      'content_hash',
      'ciphertext_size',
      'transport_mime',
      'expires_at_ms',
      'custody_relay_peer_id',
      'retry_count',
      'last_attempt_at',
      'next_attempt_at',
      'created_at',
      'updated_at',
    ]);
    expect(
      await _columnNames(db, 'media_attachments'),
      containsAll(_newAttachmentColumns),
    );

    // Historical preservation: byte-identical rows with the new columns NULL
    // and no inferred fanout authority; the rebuild scratch table is gone.
    _expectPreservedWithNullNewColumns(
      await db.query('direct_media_blob_custody', orderBy: 'attachment_id'),
      v113Custody,
      _newCustodyColumns,
    );
    _expectPreservedWithNullNewColumns(
      await db.query('media_attachments', orderBy: 'id'),
      v113Attachments,
      _newAttachmentColumns,
    );
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name LIKE '%v114_rebuild%'",
      ),
      isEmpty,
    );

    await _expectExactSchema(db);
    await _expectNaturalIdentityAndShapes(db);
    await _expectFingerprintVersionConstraints(db);
    // The lane-qualified typed helper now targets the current v115 schema and
    // is exercised by TC-365-01a. This historical migration sentinel remains
    // pinned to the literal v114 schema it owns.
    if ((await _columnNames(
      db,
      'direct_media_blob_custody',
    )).contains('owner_lane')) {
      await _expectTypedNaturalKeyHelpers(db);
    }

    // Run-twice idempotent on the same open database.
    await runDirectLinkedDeviceMediaBlobFanoutMigration(db);
    await runDirectLinkedDeviceMediaBlobFanoutMigration(db);
    await _expectExactSchema(db);
    expect(await _userVersion(db), 114);

    // Reopen preserves the authored sibling generation exactly.
    final reopenedSnapshot = await db.query(
      'direct_media_blob_custody',
      orderBy: 'attachment_id, direction, recipient_peer_id',
    );
    await db.close();
    db = await databaseFactoryFfi.openDatabase(
      upgradePath,
      options: OpenDatabaseOptions(
        version: 114,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    expect(await _userVersion(db), 114);
    expect(
      await db.query(
        'direct_media_blob_custody',
        orderBy: 'attachment_id, direction, recipient_peer_id',
      ),
      reopenedSnapshot,
    );

    // One-way local floor: an older binary opening at v113 fails closed and
    // leaves every row untouched.
    await db.close();
    await expectLater(
      databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 113,
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
        version: 114,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    expect(await _userVersion(db), 114);
    expect(
      await db.query(
        'direct_media_blob_custody',
        orderBy: 'attachment_id, direction, recipient_peer_id',
      ),
      reopenedSnapshot,
    );

    // Fresh v114 create produces the same schema through the same registry.
    final freshPath = '${tempDirectory.path}/fresh.db';
    final fresh = await databaseFactoryFfi.openDatabase(
      freshPath,
      options: OpenDatabaseOptions(
        version: 114,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        onDowngrade: onDatabaseVersionChangeError,
      ),
    );
    addTearDown(() async {
      if (fresh.isOpen) await fresh.close();
    });
    expect(await _userVersion(fresh), 114);
    expect(
      await _columnNames(fresh, 'direct_media_blob_custody'),
      containsAll(_newCustodyColumns),
    );
    expect(
      await _columnNames(fresh, 'media_attachments'),
      containsAll(_newAttachmentColumns),
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
  // Still FK-free: custody must outlive parents.
  expect(
    await db.rawQuery('PRAGMA foreign_key_list(direct_media_blob_custody)'),
    isEmpty,
  );

  // attachment_id lost its PRIMARY KEY: the rebuilt table has no INTEGER
  // rowid alias and no pk-flagged column.
  final tableInfo = await db.rawQuery(
    'PRAGMA table_info(direct_media_blob_custody)',
  );
  expect(
    tableInfo.where((row) => (row['pk'] as num) != 0),
    isEmpty,
    reason: 'v114 removes the attachment_id PRIMARY KEY',
  );

  // Exactly the two partial unique target indexes plus the three incumbent
  // lookups.
  final indexes = await db.rawQuery(
    'PRAGMA index_list(direct_media_blob_custody)',
  );
  final byName = <String, Map<String, Object?>>{
    for (final row in indexes) row['name'] as String: row,
  };
  final outgoingUnique =
      byName['idx_direct_media_blob_custody_outgoing_target'];
  final incomingUnique =
      byName['idx_direct_media_blob_custody_incoming_attachment'];
  expect(outgoingUnique, isNotNull);
  expect(outgoingUnique!['unique'], 1);
  expect(outgoingUnique['partial'], 1);
  expect(
    (await db.rawQuery(
      "PRAGMA index_info('idx_direct_media_blob_custody_outgoing_target')",
    )).map((row) => row['name']),
    const <String>['attachment_id', 'recipient_peer_id'],
  );
  expect(incomingUnique, isNotNull);
  expect(incomingUnique!['unique'], 1);
  expect(incomingUnique['partial'], 1);
  expect(
    (await db.rawQuery(
      "PRAGMA index_info('idx_direct_media_blob_custody_incoming_attachment')",
    )).map((row) => row['name']),
    const <String>['attachment_id'],
  );
  for (final incumbent in const <String>[
    'idx_direct_media_blob_custody_message',
    'idx_direct_media_blob_custody_state_retry',
    'idx_direct_media_blob_custody_inbox_incarnation',
  ]) {
    expect(byName, contains(incumbent));
  }
}

/// The natural `(attachment, direction, recipient)` identity: one outgoing
/// row per exact target, at most one incoming row, an allowed legacy-primary
/// `recipient == account` target, and every crossed linked shape refused.
Future<void> _expectNaturalIdentityAndShapes(Database db) async {
  // Distinct linked outgoing siblings for ONE canonical attachment: the
  // dynamic legacy-primary target may equal the logical account.
  await db.insert(
    'direct_media_blob_custody',
    _linkedOutgoingPreparedRow(
      attachmentId: 'attachment-fanout',
      recipientPeerId: _contactPeerId,
    ),
  );
  await db.insert(
    'direct_media_blob_custody',
    _linkedOutgoingPreparedRow(
      attachmentId: 'attachment-fanout',
      recipientPeerId: _linkedTransportPeerId,
    ),
  );
  // Linked incoming logical marker: null recipient/key with a nonblank
  // logical contact.
  await db.insert('direct_media_blob_custody', <String, Object?>{
    ..._legacyIncomingRow(),
    'attachment_id': 'attachment-fanout',
    'message_id': 'media-message-2',
    'contact_account_peer_id': _contactPeerId,
  });

  // Duplicate exact identities are refused by the partial unique indexes.
  await expectLater(
    db.insert(
      'direct_media_blob_custody',
      _linkedOutgoingPreparedRow(
        attachmentId: 'attachment-fanout',
        recipientPeerId: _linkedTransportPeerId,
      ),
    ),
    throwsA(isA<DatabaseException>()),
    reason: 'one outgoing row per (attachment, recipient)',
  );
  await expectLater(
    db.insert('direct_media_blob_custody', <String, Object?>{
      ..._legacyIncomingRow(),
      'attachment_id': 'attachment-fanout',
      'message_id': 'media-message-2',
    }),
    throwsA(isA<DatabaseException>()),
    reason: 'one incoming row per attachment',
  );

  // Crossed linked shapes are refused: an outgoing target key without its
  // logical contact, a logical contact without its target key, an incoming
  // recipient key, and blank linked values.
  for (final (row, reason) in <(Map<String, Object?>, String)>[
    (
      _linkedOutgoingPreparedRow(
        attachmentId: 'attachment-crossed-1',
        recipientPeerId: _linkedTransportPeerId,
      )..remove('recipient_ml_kem_public_key'),
      'outgoing linked contact requires the persisted target key',
    ),
    (
      _linkedOutgoingPreparedRow(
        attachmentId: 'attachment-crossed-2',
        recipientPeerId: _linkedTransportPeerId,
      )..remove('contact_account_peer_id'),
      'outgoing target key requires the logical contact',
    ),
    (
      <String, Object?>{
        ..._legacyIncomingRow(),
        'attachment_id': 'attachment-crossed-3',
        'recipient_ml_kem_public_key': 'mlkem-target',
      },
      'incoming rows never persist a recipient key',
    ),
    (
      _linkedOutgoingPreparedRow(
        attachmentId: 'attachment-crossed-4',
        recipientPeerId: _linkedTransportPeerId,
      )..['contact_account_peer_id'] = '   ',
      'blank logical contact is refused',
    ),
    (
      _linkedOutgoingPreparedRow(
        attachmentId: 'attachment-crossed-5',
        recipientPeerId: _linkedTransportPeerId,
      )..['recipient_ml_kem_public_key'] = '',
      'blank target key is refused',
    ),
  ]) {
    await expectLater(
      db.insert('direct_media_blob_custody', row),
      throwsA(isA<DatabaseException>()),
      reason: reason,
    );
  }
}

Future<void> _expectFingerprintVersionConstraints(Database db) async {
  await db.insert('media_attachments', _attachmentRow('attachment-lineage'));
  // Version without a digest is a contradiction.
  await expectLater(
    db.update(
      'media_attachments',
      const <String, Object?>{
        'direct_media_blob_custody_fingerprint_version': 2,
      },
      where: 'id = ?',
      whereArgs: const <Object?>['attachment-lineage'],
    ),
    throwsA(isA<DatabaseException>()),
    reason: 'fingerprint version 2 requires the digest',
  );
  // Only version 2 exists; other values refuse.
  await expectLater(
    db.update(
      'media_attachments',
      <String, Object?>{
        'direct_media_blob_custody_fingerprint': _contentHash,
        'direct_media_blob_custody_fingerprint_version': 1,
      },
      where: 'id = ?',
      whereArgs: const <Object?>['attachment-lineage'],
    ),
    throwsA(isA<DatabaseException>()),
    reason: 'only fingerprint version 2 is defined',
  );
  // Legacy meaning: digest with NULL version stays legal (target-specific),
  // and version 2 with a digest is the new target-independent lineage.
  await db.update(
    'media_attachments',
    <String, Object?>{'direct_media_blob_custody_fingerprint': _contentHash},
    where: 'id = ?',
    whereArgs: const <Object?>['attachment-lineage'],
  );
  await db.update(
    'media_attachments',
    <String, Object?>{
      'direct_media_blob_custody_fingerprint': _contentHash,
      'direct_media_blob_custody_fingerprint_version': 2,
    },
    where: 'id = ?',
    whereArgs: const <Object?>['attachment-lineage'],
  );
  await db.delete(
    'media_attachments',
    where: 'id = ?',
    whereArgs: const <Object?>['attachment-lineage'],
  );
}

/// The typed helpers select ONLY the exact natural identity: a generic
/// attachment lookup returns the complete sibling list, the exact-target
/// lookup returns one row, and an exact transition of target A leaves target
/// B byte-identical.
Future<void> _expectTypedNaturalKeyHelpers(Database db) async {
  final siblings = await dbLoadDirectMediaBlobCustodyRowsForAttachment(
    db,
    attachmentId: 'attachment-fanout',
  );
  expect(siblings, hasLength(3));

  final legacyPrimary = await dbLoadDirectMediaBlobCustodyForTarget(
    db,
    attachmentId: 'attachment-fanout',
    direction: DirectMediaBlobCustodyDirection.outgoing,
    recipientPeerId: _contactPeerId,
  );
  final linkedTarget = await dbLoadDirectMediaBlobCustodyForTarget(
    db,
    attachmentId: 'attachment-fanout',
    direction: DirectMediaBlobCustodyDirection.outgoing,
    recipientPeerId: _linkedTransportPeerId,
  );
  final incoming = await dbLoadDirectMediaBlobCustodyForTarget(
    db,
    attachmentId: 'attachment-fanout',
    direction: DirectMediaBlobCustodyDirection.incoming,
  );
  expect(legacyPrimary?.recipientPeerId, _contactPeerId);
  expect(legacyPrimary?.contactAccountPeerId, _contactPeerId);
  expect(linkedTarget?.recipientPeerId, _linkedTransportPeerId);
  expect(linkedTarget?.isLinkedFanoutRow, isTrue);
  expect(incoming?.recipientPeerId, isNull);
  expect(incoming?.recipientMlKemPublicKey, isNull);
  expect(incoming?.contactAccountPeerId, _contactPeerId);

  // Exact-target transition: only (attachment-fanout, outgoing, linked
  // transport) moves; the legacy-primary sibling stays byte-identical.
  final next = linkedTarget!.copyWith(
    state: DirectMediaBlobCustodyState.outgoingStored,
    expiresAtMs: 1786435200000,
    custodyRelayPeerId: 'peer-relay',
    updatedAt: '2026-08-12T13:00:00.000Z',
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: linkedTarget,
      next: next,
    ),
    isTrue,
  );
  final untouchedSibling = await dbLoadDirectMediaBlobCustodyForTarget(
    db,
    attachmentId: 'attachment-fanout',
    direction: DirectMediaBlobCustodyDirection.outgoing,
    recipientPeerId: _contactPeerId,
  );
  expect(
    untouchedSibling!.exactDatabaseProjectionMatches(legacyPrimary!),
    isTrue,
    reason: 'a sibling target transition never selects this row',
  );
  final transitioned = await dbLoadDirectMediaBlobCustodyForTarget(
    db,
    attachmentId: 'attachment-fanout',
    direction: DirectMediaBlobCustodyDirection.outgoing,
    recipientPeerId: _linkedTransportPeerId,
  );
  expect(transitioned!.exactDatabaseProjectionMatches(next), isTrue);
}

Map<String, Object?> _contactRow() => <String, Object?>{
  'peer_id': _contactPeerId,
  'public_key': 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=',
  'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
  'username': 'Alice',
  'signature': 'sig-base64',
  'scanned_at': _timestamp,
  'ml_kem_public_key': 'legacy-mlkem',
};

Map<String, Object?> _messageRow(String id) => <String, Object?>{
  'id': id,
  'contact_peer_id': _contactPeerId,
  'sender_peer_id': 'peer-self',
  'text': '',
  'timestamp': _timestamp,
  'status': 'sent',
  'is_incoming': 0,
  'created_at': _timestamp,
};

Map<String, Object?> _attachmentRow(
  String id, {
  String messageId = 'media-message-1',
}) => <String, Object?>{
  'id': id,
  'message_id': messageId,
  'mime': 'image/jpeg',
  'size': 1024,
  'media_type': 'image',
  'created_at': _timestamp,
};

Map<String, Object?> _legacyOutgoingStoredRow() => const <String, Object?>{
  'attachment_id': 'attachment-legacy',
  'message_id': 'media-message-1',
  'direction': 'outgoing',
  'state': 'outgoing_stored',
  'inbox_custody_incarnation_id': 'fedcba9876543210fedcba9876543210',
  'recipient_peer_id': _contactPeerId,
  'ciphertext_relative_path':
      'direct_media_blob_custody_v1/scope/attachment-legacy.blob',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': _contentHash,
  'ciphertext_size': 1024,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': 1786435200000,
  'custody_relay_peer_id': 'peer-relay',
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _legacyIncomingRow() => const <String, Object?>{
  'attachment_id': 'attachment-incoming',
  'message_id': 'media-message-2',
  'direction': 'incoming',
  'state': 'incoming_committed',
  'inbox_custody_incarnation_id': null,
  'recipient_peer_id': null,
  'ciphertext_relative_path': null,
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': _contentHash,
  'ciphertext_size': 2048,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': 1786435200000,
  'custody_relay_peer_id': null,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _linkedOutgoingPreparedRow({
  required String attachmentId,
  required String recipientPeerId,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': 'media-message-1',
  'direction': 'outgoing',
  'state': 'outgoing_prepared',
  'inbox_custody_incarnation_id': null,
  'recipient_peer_id': recipientPeerId,
  'contact_account_peer_id': _contactPeerId,
  'recipient_ml_kem_public_key': 'mlkem-$recipientPeerId',
  'ciphertext_relative_path':
      'direct_media_blob_custody_v1/scope/$attachmentId.blob',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': _contentHash,
  'ciphertext_size': 1024,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': null,
  'custody_relay_peer_id': null,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};
