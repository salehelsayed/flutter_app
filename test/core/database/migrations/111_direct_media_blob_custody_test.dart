// ignore_for_file: file_names

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/111_direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _timestamp = '2026-08-08T12:00:00.000Z';
const _laterTimestamp = '2026-08-08T12:01:00.000Z';
const _nextTimestamp = '2026-08-08T12:02:00.000Z';
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _manifestHash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _incarnation = '0123456789abcdef0123456789abcdef';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String upgradePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'direct_media_blob_custody_v111_',
    );
    upgradePath = '${tempDirectory.path}/upgrade.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'TC-347-01 DB v111 adds independent blob custody without historical promotion',
    () async {
      var db = await databaseFactoryFfi.openDatabase(
        upgradePath,
        options: OpenDatabaseOptions(
          version: 110,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await db.insert('messages', _messageRow());
      await db.insert('direct_inbox_custody_outbox', _historicalV108Row());
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
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });

      expect(currentIdentityDatabaseVersion, 116);
      expect(await _userVersion(db), 116);
      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 111);
        expect(entries, hasLength(1));
        expect(entries.single.name, '111_direct_media_blob_custody');
        expect(entries.single.run, same(runDirectMediaBlobCustodyMigration));
        final index110 = registry.indexWhere((entry) => entry.version == 110);
        expect(registry.indexOf(entries.single), index110 + 1);
        // 360: v112 now follows v111, so v111 is no longer the last entry.
        expect(registry[registry.indexOf(entries.single) + 1].version, 112);
      }

      await _expectExactSchema(db);
      final historicalV108 = (await db.query(
        'direct_inbox_custody_outbox',
      )).single;
      expect(historicalV108['media_blob_manifest_hash'], isNull);
      expect(historicalV108['media_blob_expires_at_ms'], isNull);
      expect(await db.query(kDirectMediaBlobCustodyTable), isEmpty);
      expect(
        (await db.query('messages')).single['direct_media_custody_intent_id'],
        _incarnation,
        reason: 'v110 authored intent remains historical, never promoted',
      );

      await _expectV108BindingConstraints(db);
      await _expectCustodyStateConstraints(db);
      await _expectTypedExactStateHelpers(db);

      await runDirectMediaBlobCustodyMigration(db);
      await runDirectMediaBlobCustodyMigration(db);
      await _expectExactSchema(db);

      final snapshotBeforeReopen = await db.query(
        kDirectMediaBlobCustodyTable,
        orderBy: 'attachment_id',
      );
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
        await db.query(kDirectMediaBlobCustodyTable, orderBy: 'attachment_id'),
        snapshotBeforeReopen,
      );

      await db.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          upgradePath,
          options: OpenDatabaseOptions(
            version: 110,
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
        await db.query(kDirectMediaBlobCustodyTable, orderBy: 'attachment_id'),
        snapshotBeforeReopen,
      );
    },
  );
}

Future<void> _expectExactSchema(Database db) async {
  final columns = await db.rawQuery(
    'PRAGMA table_info(direct_media_blob_custody)',
  );
  // 362/365: v114 appended the linked columns after recipient_peer_id and
  // v115 appends the lane-generalized ownership columns. The v111 projection
  // otherwise keeps its declaration order.
  expect(columns.map((column) => column['name']), const <String>[
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
    'owner_lane',
    'group_id',
    'custody_blob_id',
  ]);
  expect(
    await db.rawQuery('PRAGMA foreign_key_list(direct_media_blob_custody)'),
    isEmpty,
    reason: 'cleanup and ACK authority must survive parent deletion',
  );
  final indexRows = await db.rawQuery(
    'PRAGMA index_list(direct_media_blob_custody)',
  );
  expect(
    indexRows.map((row) => row['name']),
    containsAll(const <String>[
      'idx_direct_media_blob_custody_message',
      'idx_direct_media_blob_custody_state_retry',
      'idx_direct_media_blob_custody_inbox_incarnation',
    ]),
  );

  final v108Columns = await db.rawQuery(
    'PRAGMA table_info(direct_inbox_custody_outbox)',
  );
  final v108ByName = <String, Map<String, Object?>>{
    for (final column in v108Columns) column['name']! as String: column,
  };
  for (final name in const <String>[
    'media_blob_manifest_hash',
    'media_blob_expires_at_ms',
  ]) {
    expect(v108ByName[name], isNotNull);
    expect(v108ByName[name]!['notnull'], 0);
    expect(v108ByName[name]!['dflt_value'], isNull);
  }

  final attachmentColumns = await db.rawQuery(
    'PRAGMA table_info(media_attachments)',
  );
  final attachmentFingerprint = attachmentColumns.singleWhere(
    (column) => column['name'] == 'direct_media_blob_custody_fingerprint',
  );
  expect(attachmentFingerprint['type'], 'TEXT');
  expect(attachmentFingerprint['notnull'], 0);
  expect(attachmentFingerprint['dflt_value'], isNull);
}

Future<void> _expectV108BindingConstraints(Database db) async {
  await db.update(
    'direct_inbox_custody_outbox',
    const <String, Object?>{
      'media_blob_manifest_hash': _manifestHash,
      'media_blob_expires_at_ms': 4102444800000,
    },
    where: 'message_id = ?',
    whereArgs: const <Object?>['historical-message'],
  );
  final exact = (await db.query('direct_inbox_custody_outbox')).single;
  expect(exact['media_blob_manifest_hash'], _manifestHash);
  expect(exact['media_blob_expires_at_ms'], 4102444800000);

  for (final invalid in <Map<String, Object?>>[
    const <String, Object?>{
      'media_blob_manifest_hash': null,
      'media_blob_expires_at_ms': 4102444800000,
    },
    const <String, Object?>{
      'media_blob_manifest_hash': _manifestHash,
      'media_blob_expires_at_ms': null,
    },
    const <String, Object?>{
      'media_blob_manifest_hash': 'ABCDEF',
      'media_blob_expires_at_ms': 4102444800000,
    },
    const <String, Object?>{
      'media_blob_manifest_hash': _manifestHash,
      'media_blob_expires_at_ms': 0,
    },
    <String, Object?>{
      'media_blob_manifest_hash': Uint8List.fromList(_manifestHash.codeUnits),
      'media_blob_expires_at_ms': 4102444800000,
    },
  ]) {
    await expectLater(
      db.update(
        'direct_inbox_custody_outbox',
        invalid,
        where: 'message_id = ?',
        whereArgs: const <Object?>['historical-message'],
      ),
      throwsA(isA<DatabaseException>()),
    );
  }
  expect(
    (await db.query('direct_inbox_custody_outbox')).single,
    exact,
    reason: 'failed binding writes preserve the exact historical row',
  );
}

Future<void> _expectCustodyStateConstraints(Database db) async {
  final validRows = <Map<String, Object?>>[
    _outgoingPreparedMap('schema-prepared'),
    _outgoingStoredMap('schema-stored'),
    _outgoingCleanupMap('schema-cleanup-local'),
    _outgoingCleanupMap('schema-cleanup-stored', withProof: true),
    _incomingCommittedMap('schema-incoming'),
    _incomingAckPendingMap('schema-ack'),
    _incomingAckPendingMap('schema-ack-retry', retried: true),
  ];
  for (final row in validRows) {
    await db.insert(kDirectMediaBlobCustodyTable, row);
  }

  final invalidRows = <Map<String, Object?>>[
    {..._outgoingPreparedMap('bad-direction'), 'direction': 'incoming'},
    {..._outgoingPreparedMap('bad-prepared-expiry'), 'expires_at_ms': 99},
    {..._outgoingStoredMap('bad-stored-source'), 'custody_relay_peer_id': null},
    {
      ..._outgoingStoredMap('bad-stored-path'),
      'ciphertext_relative_path': '../outside.blob',
    },
    {
      ..._outgoingStoredMap('bad-stored-hash'),
      'content_hash': _hashA.toUpperCase(),
    },
    {
      ..._outgoingStoredMap('bad-stored-binding'),
      'inbox_custody_incarnation_id': 'not-lower-hex',
    },
    {
      ..._incomingCommittedMap('bad-incoming-source'),
      'custody_relay_peer_id': 'relay-too-early',
    },
    {
      ..._incomingCommittedMap('bad-incoming-path'),
      'ciphertext_relative_path':
          'direct_media_blob_custody_v1/peer/bad-incoming-path.blob',
    },
    {
      ..._incomingAckPendingMap('bad-ack-retry'),
      'retry_count': 1,
      'last_attempt_at': null,
      'next_attempt_at': null,
    },
  ];
  for (final row in invalidRows) {
    await expectLater(
      db.insert(kDirectMediaBlobCustodyTable, row),
      throwsA(isA<DatabaseException>()),
      reason: 'invalid state projection ${row['attachment_id']}',
    );
  }

  await db.delete(
    'messages',
    where: 'id = ?',
    whereArgs: ['historical-message'],
  );
  expect(
    await db.query(kDirectMediaBlobCustodyTable),
    hasLength(validRows.length),
    reason: 'v111 has no parent cascade',
  );
}

Future<void> _expectTypedExactStateHelpers(Database db) async {
  final preparedA = _outgoingPreparedRow('typed-a');
  final preparedB = _outgoingPreparedRow('typed-b', hash: _hashB);
  expect(
    await dbStageInitialDirectMediaBlobCustodyBatch(
      db,
      rows: <DirectMediaBlobCustodyRow>[preparedA, preparedB],
    ),
    DirectMediaBlobCustodyBatchStageOutcome.applied,
  );
  expect(
    await dbStageInitialDirectMediaBlobCustodyBatch(
      db,
      rows: <DirectMediaBlobCustodyRow>[preparedB, preparedA],
    ),
    DirectMediaBlobCustodyBatchStageOutcome.idempotent,
  );

  final stored = preparedA.copyWith(
    state: DirectMediaBlobCustodyState.outgoingStored,
    expiresAtMs: 4102444800000,
    custodyRelayPeerId: 'relay-upload',
    updatedAt: _laterTimestamp,
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: preparedA,
      next: stored,
    ),
    isTrue,
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: preparedA,
      next: stored,
    ),
    isFalse,
    reason: 'a stale prepared writer cannot replace the stored winner',
  );

  final bound = stored.copyWith(
    inboxCustodyIncarnationId: _incarnation,
    updatedAt: _nextTimestamp,
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: stored,
      next: bound,
    ),
    isFalse,
    reason: 'generic transition cannot claim v108 binding authority',
  );
  expect(
    await db.transaction(
      (txn) => dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
        txn,
        expected: stored,
        next: bound,
      ),
    ),
    isTrue,
  );
  final cleanup = bound.copyWith(
    state: DirectMediaBlobCustodyState.outgoingCleanupPending,
    updatedAt: '2026-08-08T12:03:00.000Z',
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: bound,
      next: cleanup,
    ),
    isFalse,
    reason: 'generic transition cannot publish cleanup authority',
  );
  expect(
    await db.transaction(
      (txn) => dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
        txn,
        expected: bound,
        next: cleanup,
      ),
    ),
    isTrue,
  );
  expect(
    await dbDeleteDirectMediaBlobCleanupPendingIfExact(db, expected: cleanup),
    isTrue,
  );
  expect(
    await dbLoadDirectMediaBlobCustodyRowsForAttachment(
      db,
      attachmentId: cleanup.attachmentId,
    ),
    isEmpty,
  );

  final incoming = DirectMediaBlobCustodyRow.fromMap(
    _incomingCommittedMap('typed-incoming'),
  );
  expect(
    await dbStageInitialDirectMediaBlobCustodyBatch(db, rows: [incoming]),
    DirectMediaBlobCustodyBatchStageOutcome.applied,
  );
  final ackPending = incoming.copyWith(
    state: DirectMediaBlobCustodyState.incomingAckPending,
    custodyRelayPeerId: 'relay-source',
    updatedAt: _laterTimestamp,
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: incoming,
      next: ackPending,
    ),
    isTrue,
  );
  final retry = ackPending.copyWith(
    retryCount: 1,
    lastAttemptAt: _laterTimestamp,
    nextAttemptAt: _nextTimestamp,
    updatedAt: _nextTimestamp,
  );
  expect(
    await dbTransitionDirectMediaBlobCustodyIfExact(
      db,
      expected: ackPending,
      next: retry,
    ),
    isTrue,
  );
  expect(
    DirectMediaBlobCustodyRow.fromMap(retry.toMap()).toMap(),
    retry.toMap(),
  );
}

Map<String, Object?> _messageRow() => const <String, Object?>{
  'id': 'historical-message',
  'contact_peer_id': 'peer-history',
  'sender_peer_id': 'peer-self',
  'text': 'historical media message',
  'timestamp': _timestamp,
  'status': 'sending',
  'is_incoming': 0,
  'created_at': _timestamp,
  'direct_media_custody_intent_id': _incarnation,
};

Map<String, Object?> _historicalV108Row() => const <String, Object?>{
  'recipient_peer_id': 'peer-history',
  'message_id': 'historical-message',
  'incarnation_id': _incarnation,
  'wire_envelope': '{"type":"chat","v":2}',
  'retry_count': 0,
  'last_attempt_at': null,
  'last_error_code': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _outgoingPreparedMap(
  String id, {
  String hash = _hashA,
}) => <String, Object?>{
  'attachment_id': id,
  'message_id': id.startsWith('typed') ? 'typed-message' : 'schema-message',
  'owner_lane': 'direct',
  'group_id': null,
  'custody_blob_id': id,
  'direction': 'outgoing',
  'state': 'outgoing_prepared',
  'inbox_custody_incarnation_id': null,
  'recipient_peer_id': 'peer-recipient',
  'ciphertext_relative_path': 'direct_media_blob_custody_v1/peer-self/$id.blob',
  'custody_kind': kDirectMediaBlobCustodyKind,
  'custody_contract': kDirectMediaBlobCustodyContract,
  'content_hash': hash,
  'ciphertext_size': 128,
  'transport_mime': kDirectMediaBlobTransportMime,
  'expires_at_ms': null,
  'custody_relay_peer_id': null,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

DirectMediaBlobCustodyRow _outgoingPreparedRow(
  String id, {
  String hash = _hashA,
}) => DirectMediaBlobCustodyRow.fromMap(_outgoingPreparedMap(id, hash: hash));

Map<String, Object?> _outgoingStoredMap(String id) => <String, Object?>{
  ..._outgoingPreparedMap(id),
  'state': 'outgoing_stored',
  'expires_at_ms': 4102444800000,
  'custody_relay_peer_id': 'relay-upload',
};

Map<String, Object?> _outgoingCleanupMap(String id, {bool withProof = false}) =>
    <String, Object?>{
      ..._outgoingPreparedMap(id),
      'state': 'outgoing_cleanup_pending',
      if (withProof) ...<String, Object?>{
        'expires_at_ms': 4102444800000,
        'custody_relay_peer_id': 'relay-upload',
        'inbox_custody_incarnation_id': _incarnation,
      },
    };

Map<String, Object?> _incomingCommittedMap(String id) => <String, Object?>{
  'attachment_id': id,
  'message_id': id.startsWith('typed')
      ? 'typed-incoming-message'
      : 'schema-incoming-message',
  'owner_lane': 'direct',
  'group_id': null,
  'custody_blob_id': id,
  'direction': 'incoming',
  'state': 'incoming_committed',
  'inbox_custody_incarnation_id': null,
  'recipient_peer_id': null,
  'ciphertext_relative_path': null,
  'custody_kind': kDirectMediaBlobCustodyKind,
  'custody_contract': kDirectMediaBlobCustodyContract,
  'content_hash': _hashA,
  'ciphertext_size': 128,
  'transport_mime': kDirectMediaBlobTransportMime,
  'expires_at_ms': 4102444800000,
  'custody_relay_peer_id': null,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _incomingAckPendingMap(
  String id, {
  bool retried = false,
}) => <String, Object?>{
  ..._incomingCommittedMap(id),
  'state': 'incoming_ack_pending',
  'custody_relay_peer_id': 'relay-source',
  'retry_count': retried ? 1 : 0,
  'last_attempt_at': retried ? _laterTimestamp : null,
  'next_attempt_at': retried ? _nextTimestamp : null,
};

Future<int> _userVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return (rows.single.values.single as num).toInt();
}
