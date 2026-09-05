// ignore_for_file: file_names

import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/115_group_media_blob_custody.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _timestamp = '2026-08-14T12:00:00.000Z';
const _laterTimestamp = '2026-08-14T12:01:00.000Z';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _groupHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _incarnation = '0123456789abcdef0123456789abcdef';
const _groupId = 'group-v115';
const _groupMessageId = 'group-message-v115';
const _groupAttachmentId = 'group-attachment-v115';
const _groupPath =
    'group_media_blob_custody_v1/identity-scope/group-scope/blob.blob';

const _v114Columns = <String>[
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
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDirectory;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'group_media_blob_custody_v115_',
    );
    databasePath = '${tempDirectory.path}/upgrade.db';
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'TC-365-01a v115 generalizes strict media custody without altering the v114 projection',
    () async {
      var db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 114,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      for (final row in _allLegalV114StateRows()) {
        await db.insert(kDirectMediaBlobCustodyTable, row);
      }
      await db.insert('media_attachments', _attachmentRow('historical'));
      final historical = await db.query(
        kDirectMediaBlobCustodyTable,
        orderBy: 'attachment_id',
      );
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        databasePath,
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

      expect(currentIdentityDatabaseVersion, 118);
      expect(await _userVersion(db), 118);
      for (final registry in <List<ProductionMigrationEntry>>[
        productionCreateMigrations,
        productionUpgradeMigrations,
      ]) {
        final entries = registry.where((entry) => entry.version == 115);
        expect(entries, hasLength(1));
        expect(entries.single.name, '115_group_media_blob_custody');
        expect(entries.single.run, same(runGroupMediaBlobCustodyMigration));
        final index114 = registry.indexWhere((entry) => entry.version == 114);
        expect(registry.indexOf(entries.single), index114 + 1);
        expect(registry[registry.indexOf(entries.single) + 1].version, 116);
        expect(registry.last.version, 118);
      }

      final columns = await _columnNames(db, kDirectMediaBlobCustodyTable);
      expect(columns, <String>[
        ..._v114Columns,
        'owner_lane',
        'group_id',
        'custody_blob_id',
      ]);
      final upgraded = await db.query(
        kDirectMediaBlobCustodyTable,
        orderBy: 'attachment_id',
      );
      expect(upgraded, hasLength(historical.length));
      for (var index = 0; index < historical.length; index++) {
        expect(<String, Object?>{
          for (final column in _v114Columns) column: upgraded[index][column],
        }, historical[index]);
        expect(upgraded[index]['owner_lane'], 'direct');
        expect(upgraded[index]['group_id'], isNull);
        expect(
          upgraded[index]['custody_blob_id'],
          upgraded[index]['attachment_id'],
        );
      }
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>['historical'],
        )).single['group_media_blob_custody_fingerprint'],
        isNull,
      );

      await _expectLaneQualifiedIndexesAndChecks(db);
      await _expectGroupStageCasAndDirectIsolation(db);
      await _expectSoleGroupEmptyTargetStage(db);

      final snapshot = await db.query(
        kDirectMediaBlobCustodyTable,
        orderBy: 'owner_lane, attachment_id, recipient_peer_id',
      );
      await runGroupMediaBlobCustodyMigration(db);
      await runGroupMediaBlobCustodyMigration(db);
      expect(
        await db.query(
          kDirectMediaBlobCustodyTable,
          orderBy: 'owner_lane, attachment_id, recipient_peer_id',
        ),
        snapshot,
      );

      await db.close();
      await expectLater(
        databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: 114,
            singleInstance: false,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
            onDowngrade: onDatabaseVersionChangeError,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      expect(await _userVersion(db), 118);
    },
  );

  test(
    'TC-366-04b migration remains no-backfill for historical attachment fingerprints',
    () async {
      var db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 114,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      await db.insert(
        'media_attachments',
        _attachmentRow('historical-direct', ownerLane: 'direct'),
      );
      await db.insert(
        'media_attachments',
        _attachmentRow('historical-group', ownerLane: 'group'),
      );
      expect(
        await _columnNames(db, 'media_attachments'),
        isNot(contains('group_media_blob_custody_fingerprint')),
      );
      await db.close();

      db = await databaseFactoryFfi.openDatabase(
        databasePath,
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

      final historical = await db.query(
        'media_attachments',
        columns: const <String>[
          'id',
          'owner_lane',
          'group_media_blob_custody_fingerprint',
        ],
        where: 'id IN (?, ?)',
        whereArgs: const <Object?>['historical-direct', 'historical-group'],
        orderBy: 'id',
      );
      expect(historical, hasLength(2));
      expect(historical.map((row) => row['owner_lane']), <Object?>[
        'direct',
        'group',
      ]);
      expect(
        historical.every(
          (row) => row['group_media_blob_custody_fingerprint'] == null,
        ),
        isTrue,
        reason: 'v115 is schema-only for historical attachment rows',
      );
      expect(
        await db.query(kDirectMediaBlobCustodyTable),
        isEmpty,
        reason: 'migration cannot promote history into blob custody',
      );
    },
  );
}

Future<void> _expectLaneQualifiedIndexesAndChecks(Database db) async {
  final indexes = await db.rawQuery(
    'PRAGMA index_list($kDirectMediaBlobCustodyTable)',
  );
  final names = indexes.map((row) => row['name']);
  expect(
    names,
    containsAll(const <String>[
      'idx_direct_media_blob_custody_outgoing_target',
      'idx_direct_media_blob_custody_incoming_attachment',
      'idx_group_media_blob_custody_outgoing_target',
      'idx_group_media_blob_custody_incoming_attachment',
    ]),
  );
  expect(
    await _indexColumns(db, 'idx_direct_media_blob_custody_outgoing_target'),
    const <String>['owner_lane', 'attachment_id', 'recipient_peer_id'],
  );
  expect(
    await _indexColumns(db, 'idx_group_media_blob_custody_outgoing_target'),
    const <String>[
      'owner_lane',
      'group_id',
      'attachment_id',
      'recipient_peer_id',
    ],
  );

  await expectLater(
    db.insert(kDirectMediaBlobCustodyTable, <String, Object?>{
      ..._groupPreparedRow(recipient: 'target-crossed'),
      'custody_kind': 'direct_media_blob_v1',
    }),
    throwsA(isA<DatabaseException>()),
  );
  await expectLater(
    db.insert(kDirectMediaBlobCustodyTable, <String, Object?>{
      ..._groupPreparedRow(recipient: 'target-path-crossed'),
      'ciphertext_relative_path':
          'direct_media_blob_custody_v1/identity/blob.blob',
    }),
    throwsA(isA<DatabaseException>()),
  );
}

Future<void> _expectGroupStageCasAndDirectIsolation(Database db) async {
  await db.insert('group_messages', _groupMessageRow(_groupMessageId));
  await db.insert(
    'media_attachments',
    _attachmentRow(
      _groupAttachmentId,
      messageId: _groupMessageId,
      ownerLane: 'group',
    ),
  );
  final rows = <Map<String, Object?>>[
    _groupPreparedRow(recipient: 'physical-a'),
    _groupPreparedRow(recipient: 'physical-b'),
  ].map(DirectMediaBlobCustodyRow.fromMap).toList(growable: false);
  final fingerprint = computeGroupMediaBlobCustodyFingerprint(
    groupId: _groupId,
    messageId: _groupMessageId,
    attachmentId: _groupAttachmentId,
    custodyBlobId: _groupAttachmentId,
    contentHash: _groupHash,
    ciphertextSize: 48,
    recipientPeerIds: const <String>['physical-b', 'physical-a'],
  );
  final outcome = await db.transaction(
    (txn) => dbStageGroupMediaBlobCustodyWithinTransaction(
      txn,
      groupId: _groupId,
      messageId: _groupMessageId,
      attachmentRows: <Map<String, Object?>>[
        <String, Object?>{
          ..._attachmentRow(
            _groupAttachmentId,
            messageId: _groupMessageId,
            ownerLane: 'group',
          ),
          'group_media_blob_custody_fingerprint': fingerprint,
        },
      ],
      custodyRows: rows,
    ),
  );
  expect(outcome, DirectMediaBlobCustodyBatchStageOutcome.applied);
  expect(
    await dbLoadGroupMediaBlobCustodyForMessage(
      db,
      groupId: _groupId,
      messageId: _groupMessageId,
    ),
    hasLength(2),
  );
  expect(
    await dbLoadDirectMediaBlobCustodyRowsForAttachment(
      db,
      attachmentId: _groupAttachmentId,
    ),
    isEmpty,
  );
  expect(
    await dbLoadDirectMediaBlobCustodyByStates(
      db,
      states: const <DirectMediaBlobCustodyState>{
        DirectMediaBlobCustodyState.outgoingPrepared,
      },
      limit: 50,
    ),
    everyElement(
      isA<DirectMediaBlobCustodyRow>().having(
        (row) => row.ownerLane,
        'owner lane',
        MediaBlobCustodyOwnerLane.direct,
      ),
    ),
  );

  final expected = rows.first;
  final next = expected.copyWith(
    state: DirectMediaBlobCustodyState.outgoingStored,
    expiresAtMs: 2000,
    custodyRelayPeerId: 'relay-a',
    updatedAt: _laterTimestamp,
  );
  expect(
    await dbTransitionGroupMediaBlobCustodyIfExact(
      db,
      expected: expected,
      next: next,
    ),
    isTrue,
  );
  expect(
    await dbCountOtherGroupMediaBlobCustodyRowsReferencingArtifact(
      db,
      ciphertextRelativePath: _groupPath,
      contentHash: _groupHash,
      ciphertextSize: 48,
      excluding: DirectMediaBlobCustodyNaturalKey.ofRow(next),
    ),
    1,
  );
}

Future<void> _expectSoleGroupEmptyTargetStage(Database db) async {
  const messageId = 'sole-group-message';
  const attachmentId = 'sole-group-attachment';
  const custodyBlobId = 'sole-group-deterministic-blob';
  final fingerprint = computeGroupMediaBlobCustodyFingerprint(
    groupId: _groupId,
    messageId: messageId,
    attachmentId: attachmentId,
    custodyBlobId: custodyBlobId,
    contentHash: _groupHash,
    ciphertextSize: 48,
    recipientPeerIds: const <String>[],
  );
  final parentRow = _groupMessageRow(messageId);
  final attachmentRows = <Map<String, Object?>>[
    <String, Object?>{
      ..._attachmentRow(attachmentId, messageId: messageId, ownerLane: 'group'),
      'content_hash': _groupHash,
      'size': 32,
      'encryption_key_base64': 'secure:v1:media_attachment_key:$attachmentId',
      'encryption_nonce': 'bm9uY2U=',
      'encryption_scheme': 'blob_aes_256_gcm_v1',
      'group_media_blob_custody_fingerprint': fingerprint,
    },
  ];
  const custodyBlobIds = <String, String>{attachmentId: custodyBlobId};
  final outcome = await dbStageFreshOutgoingGroupMediaBlobGeneration(
    db,
    parentRow: parentRow,
    attachmentRows: attachmentRows,
    custodyRows: const <DirectMediaBlobCustodyRow>[],
    custodyBlobIdsByAttachmentId: custodyBlobIds,
  );
  expect(outcome, DirectMediaBlobCustodyBatchStageOutcome.applied);
  expect(
    await dbLoadGroupMediaBlobCustodyForMessage(
      db,
      groupId: _groupId,
      messageId: messageId,
    ),
    isEmpty,
  );
  expect(
    (await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: const <Object?>[attachmentId],
    )).single['group_media_blob_custody_fingerprint'],
    fingerprint,
  );
  expect(
    await dbStageFreshOutgoingGroupMediaBlobGeneration(
      db,
      parentRow: parentRow,
      attachmentRows: attachmentRows,
      custodyRows: const <DirectMediaBlobCustodyRow>[],
      custodyBlobIdsByAttachmentId: custodyBlobIds,
    ),
    DirectMediaBlobCustodyBatchStageOutcome.idempotent,
  );

  const partialMessageId = 'partial-sole-message';
  const partialAttachmentId = 'partial-sole-attachment';
  const partialBlobId = 'partial-sole-deterministic-blob';
  await db.insert('group_messages', _groupMessageRow(partialMessageId));
  final partialFingerprint = computeGroupMediaBlobCustodyFingerprint(
    groupId: _groupId,
    messageId: partialMessageId,
    attachmentId: partialAttachmentId,
    custodyBlobId: partialBlobId,
    contentHash: _groupHash,
    ciphertextSize: 48,
    recipientPeerIds: const <String>[],
  );
  expect(
    await dbStageFreshOutgoingGroupMediaBlobGeneration(
      db,
      parentRow: _groupMessageRow(partialMessageId),
      attachmentRows: <Map<String, Object?>>[
        <String, Object?>{
          ..._attachmentRow(
            partialAttachmentId,
            messageId: partialMessageId,
            ownerLane: 'group',
          ),
          'content_hash': _groupHash,
          'size': 32,
          'encryption_key_base64': 'secure:v1:partial',
          'encryption_nonce': 'bm9uY2U=',
          'encryption_scheme': 'blob_aes_256_gcm_v1',
          'group_media_blob_custody_fingerprint': partialFingerprint,
        },
      ],
      custodyRows: const <DirectMediaBlobCustodyRow>[],
      custodyBlobIdsByAttachmentId: const <String, String>{
        partialAttachmentId: partialBlobId,
      },
    ),
    DirectMediaBlobCustodyBatchStageOutcome.refused,
  );
  expect(
    await db.query(
      'media_attachments',
      where: 'id = ?',
      whereArgs: const <Object?>[partialAttachmentId],
    ),
    isEmpty,
    reason: 'a partial parent is never completed outside the fresh stage',
  );

  final crossed = await dbStageFreshOutgoingGroupMediaBlobGeneration(
    db,
    parentRow: _groupMessageRow('crossed-sole-message'),
    attachmentRows: <Map<String, Object?>>[
      <String, Object?>{
        ..._attachmentRow(
          'crossed-sole-attachment',
          messageId: 'crossed-sole-message',
          ownerLane: 'group',
        ),
        'content_hash': _groupHash,
        'size': 32,
        'encryption_key_base64': 'secure:v1:crossed',
        'encryption_nonce': 'bm9uY2U=',
        'encryption_scheme': 'blob_aes_256_gcm_v1',
        'group_media_blob_custody_fingerprint': _hash,
      },
    ],
    custodyRows: const <DirectMediaBlobCustodyRow>[],
    custodyBlobIdsByAttachmentId: const <String, String>{
      'crossed-sole-attachment': 'crossed-sole-deterministic-blob',
    },
  );
  expect(crossed, DirectMediaBlobCustodyBatchStageOutcome.refused);
  expect(
    await db.query(
      'group_messages',
      where: 'id = ?',
      whereArgs: const <Object?>['crossed-sole-message'],
    ),
    isEmpty,
  );
}

List<Map<String, Object?>> _allLegalV114StateRows() => <Map<String, Object?>>[
  _directRow('direct-prepared', 'outgoing_prepared'),
  _directRow(
    'direct-stored',
    'outgoing_stored',
    expiresAtMs: 2000,
    relayPeerId: 'relay-stored',
  ),
  _directRow(
    'direct-cleanup',
    'outgoing_cleanup_pending',
    expiresAtMs: 2000,
    relayPeerId: 'relay-cleanup',
    incarnation: _incarnation,
  ),
  _directRow(
    'direct-incoming-committed',
    'incoming_committed',
    incoming: true,
    expiresAtMs: 2000,
  ),
  _directRow(
    'direct-incoming-ack',
    'incoming_ack_pending',
    incoming: true,
    expiresAtMs: 2000,
    relayPeerId: 'relay-incoming',
  ),
];

Map<String, Object?> _directRow(
  String attachmentId,
  String state, {
  bool incoming = false,
  int? expiresAtMs,
  String? relayPeerId,
  String? incarnation,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': 'message-$attachmentId',
  'direction': incoming ? 'incoming' : 'outgoing',
  'state': state,
  'inbox_custody_incarnation_id': incarnation,
  'recipient_peer_id': incoming ? null : 'recipient-$attachmentId',
  'contact_account_peer_id': null,
  'recipient_ml_kem_public_key': null,
  'ciphertext_relative_path': incoming
      ? null
      : 'direct_media_blob_custody_v1/identity/$attachmentId.blob',
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': _hash,
  'ciphertext_size': 32,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': expiresAtMs,
  'custody_relay_peer_id': relayPeerId,
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': _timestamp,
  'updated_at': _timestamp,
};

Map<String, Object?> _groupPreparedRow({required String recipient}) =>
    <String, Object?>{
      'attachment_id': _groupAttachmentId,
      'message_id': _groupMessageId,
      'direction': 'outgoing',
      'state': 'outgoing_prepared',
      'inbox_custody_incarnation_id': null,
      'recipient_peer_id': recipient,
      'contact_account_peer_id': null,
      'recipient_ml_kem_public_key': null,
      'ciphertext_relative_path': _groupPath,
      'custody_kind': kGroupMediaBlobCustodyKind,
      'custody_contract': 'ack_or_expiry_v1',
      'content_hash': _groupHash,
      'ciphertext_size': 48,
      'transport_mime': 'application/octet-stream',
      'expires_at_ms': null,
      'custody_relay_peer_id': null,
      'retry_count': 0,
      'last_attempt_at': null,
      'next_attempt_at': null,
      'created_at': _timestamp,
      'updated_at': _timestamp,
      'owner_lane': 'group',
      'group_id': _groupId,
      'custody_blob_id': _groupAttachmentId,
    };

Map<String, Object?> _groupMessageRow(String id) => <String, Object?>{
  'id': id,
  'group_id': _groupId,
  'sender_peer_id': 'sender-peer',
  'sender_username': 'Sender',
  'text': '',
  'timestamp': _timestamp,
  'key_generation': 1,
  'status': 'pending',
  'is_incoming': 0,
  'created_at': _timestamp,
};

Map<String, Object?> _attachmentRow(
  String id, {
  String? messageId,
  String ownerLane = 'direct',
}) => <String, Object?>{
  'id': id,
  'message_id': messageId ?? 'message-$id',
  'mime': 'image/jpeg',
  'size': 32,
  'media_type': 'image',
  'local_path': '/tmp/$id.jpg',
  'download_status': 'done',
  'created_at': _timestamp,
  'owner_lane': ownerLane,
};

Future<int> _userVersion(Database db) async =>
    (await db.rawQuery('PRAGMA user_version')).single.values.first! as int;

Future<List<String>> _columnNames(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toList(growable: false);

Future<List<String>> _indexColumns(Database db, String index) async =>
    (await db.rawQuery(
      "PRAGMA index_info('$index')",
    )).map((row) => row['name'] as String).toList(growable: false);
