// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _migrationName = '115_group_media_blob_custody';

/// Generalizes the incumbent v114 physical blob ledger without changing any
/// v114 column value. Historical rows receive deterministic direct ownership;
/// group rows use an independent owner, wire ID, kind, path root and indexes.
Future<void> runGroupMediaBlobCustodyMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEDIA_BLOB_CUSTODY_MIGRATION_START',
    details: const <String, Object?>{'migration': _migrationName},
  );
  try {
    final attachmentColumns = await _columnNames(db, 'media_attachments');
    if (!attachmentColumns.contains('group_media_blob_custody_fingerprint')) {
      await db.execute(
        'ALTER TABLE media_attachments '
        'ADD COLUMN group_media_blob_custody_fingerprint '
        '$_groupMediaBlobFingerprintColumnSql',
      );
    }

    final custodyColumns = await _columnNames(db, 'direct_media_blob_custody');
    if (!custodyColumns.contains('owner_lane')) {
      await db.execute(_createRebuiltMediaBlobCustodyTableSql);
      await db.execute('''
        INSERT INTO direct_media_blob_custody_v115_rebuild (
          attachment_id, message_id, direction, state,
          inbox_custody_incarnation_id, recipient_peer_id,
          contact_account_peer_id, recipient_ml_kem_public_key,
          ciphertext_relative_path, custody_kind, custody_contract,
          content_hash, ciphertext_size, transport_mime, expires_at_ms,
          custody_relay_peer_id, retry_count, last_attempt_at,
          next_attempt_at, created_at, updated_at,
          owner_lane, group_id, custody_blob_id
        )
        SELECT
          attachment_id, message_id, direction, state,
          inbox_custody_incarnation_id, recipient_peer_id,
          contact_account_peer_id, recipient_ml_kem_public_key,
          ciphertext_relative_path, custody_kind, custody_contract,
          content_hash, ciphertext_size, transport_mime, expires_at_ms,
          custody_relay_peer_id, retry_count, last_attempt_at,
          next_attempt_at, created_at, updated_at,
          'direct', NULL, attachment_id
        FROM direct_media_blob_custody
      ''');
      final oldCount = _singleCount(
        await db.rawQuery(
          'SELECT COUNT(*) AS n FROM direct_media_blob_custody',
        ),
      );
      final rebuiltCount = _singleCount(
        await db.rawQuery(
          'SELECT COUNT(*) AS n '
          'FROM direct_media_blob_custody_v115_rebuild',
        ),
      );
      if (oldCount != rebuiltCount) {
        throw StateError(
          'v115 media blob custody rebuild lost rows '
          '($oldCount -> $rebuiltCount)',
        );
      }
      await db.execute('DROP TABLE direct_media_blob_custody');
      await db.execute(
        'ALTER TABLE direct_media_blob_custody_v115_rebuild '
        'RENAME TO direct_media_blob_custody',
      );
    }

    for (final sql in _mediaBlobCustodyIndexSql) {
      await db.execute(sql);
    }
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEDIA_BLOB_CUSTODY_MIGRATION_SUCCESS',
      details: const <String, Object?>{'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEDIA_BLOB_CUSTODY_MIGRATION_ERROR',
      details: <String, Object?>{
        'migration': _migrationName,
        'error': error.toString(),
      },
    );
    rethrow;
  }
}

const String _createRebuiltMediaBlobCustodyTableSql = '''
CREATE TABLE IF NOT EXISTS direct_media_blob_custody_v115_rebuild (
  attachment_id TEXT NOT NULL CHECK(length(trim(attachment_id)) > 0),
  message_id TEXT NOT NULL CHECK(length(trim(message_id)) > 0),
  direction TEXT NOT NULL CHECK(direction IN ('outgoing', 'incoming')),
  state TEXT NOT NULL CHECK(state IN (
    'outgoing_prepared',
    'outgoing_stored',
    'outgoing_cleanup_pending',
    'incoming_committed',
    'incoming_ack_pending'
  )),
  inbox_custody_incarnation_id TEXT CHECK(
    inbox_custody_incarnation_id IS NULL OR (
      typeof(inbox_custody_incarnation_id) = 'text' AND
      length(inbox_custody_incarnation_id) = 32 AND
      length(CAST(inbox_custody_incarnation_id AS BLOB)) = 32 AND
      inbox_custody_incarnation_id NOT GLOB '*[^0-9a-f]*'
    )
  ),
  recipient_peer_id TEXT CHECK(
    recipient_peer_id IS NULL OR length(trim(recipient_peer_id)) > 0
  ),
  contact_account_peer_id TEXT CHECK(
    contact_account_peer_id IS NULL OR
      length(trim(contact_account_peer_id)) > 0
  ),
  recipient_ml_kem_public_key TEXT CHECK(
    recipient_ml_kem_public_key IS NULL OR
      length(trim(recipient_ml_kem_public_key)) > 0
  ),
  ciphertext_relative_path TEXT CHECK(
    ciphertext_relative_path IS NULL OR (
      typeof(ciphertext_relative_path) = 'text' AND
      ciphertext_relative_path = trim(ciphertext_relative_path) AND
      (
        (owner_lane = 'direct' AND
          ciphertext_relative_path LIKE 'direct_media_blob_custody_v1/%/%') OR
        (owner_lane = 'group' AND
          ciphertext_relative_path LIKE 'group_media_blob_custody_v1/%/%/%')
      ) AND
      ciphertext_relative_path NOT LIKE '/%' AND
      ciphertext_relative_path NOT GLOB '[A-Za-z]:*' AND
      instr(ciphertext_relative_path, char(0)) = 0 AND
      instr(ciphertext_relative_path, char(92)) = 0 AND
      instr(ciphertext_relative_path, ':') = 0 AND
      ciphertext_relative_path <> '.' AND
      ciphertext_relative_path <> '..' AND
      ciphertext_relative_path NOT LIKE './%' AND
      ciphertext_relative_path NOT LIKE '../%' AND
      ciphertext_relative_path NOT LIKE '%/./%' AND
      ciphertext_relative_path NOT LIKE '%/../%' AND
      ciphertext_relative_path NOT LIKE '%/.' AND
      ciphertext_relative_path NOT LIKE '%/..' AND
      ciphertext_relative_path NOT LIKE '%//%'
    )
  ),
  custody_kind TEXT NOT NULL,
  custody_contract TEXT NOT NULL CHECK(custody_contract = 'ack_or_expiry_v1'),
  content_hash TEXT NOT NULL CHECK(
    typeof(content_hash) = 'text' AND
    length(content_hash) = 64 AND
    length(CAST(content_hash AS BLOB)) = 64 AND
    content_hash NOT GLOB '*[^0-9a-f]*'
  ),
  ciphertext_size INTEGER NOT NULL CHECK(
    typeof(ciphertext_size) = 'integer' AND ciphertext_size > 0
  ),
  transport_mime TEXT NOT NULL
    CHECK(transport_mime = 'application/octet-stream'),
  expires_at_ms INTEGER CHECK(
    expires_at_ms IS NULL OR (
      typeof(expires_at_ms) = 'integer' AND expires_at_ms > 0
    )
  ),
  custody_relay_peer_id TEXT CHECK(
    custody_relay_peer_id IS NULL OR
      length(trim(custody_relay_peer_id)) > 0
  ),
  retry_count INTEGER NOT NULL DEFAULT 0 CHECK(
    typeof(retry_count) = 'integer' AND retry_count >= 0
  ),
  last_attempt_at TEXT CHECK(
    last_attempt_at IS NULL OR length(trim(last_attempt_at)) > 0
  ),
  next_attempt_at TEXT CHECK(
    next_attempt_at IS NULL OR length(trim(next_attempt_at)) > 0
  ),
  created_at TEXT NOT NULL CHECK(length(trim(created_at)) > 0),
  updated_at TEXT NOT NULL CHECK(length(trim(updated_at)) > 0),
  owner_lane TEXT NOT NULL CHECK(owner_lane IN ('direct', 'group')),
  group_id TEXT CHECK(group_id IS NULL OR length(trim(group_id)) > 0),
  custody_blob_id TEXT NOT NULL CHECK(length(trim(custody_blob_id)) > 0),

  CHECK(
    (owner_lane = 'direct' AND
      group_id IS NULL AND
      custody_blob_id = attachment_id AND
      custody_kind = 'direct_media_blob_v1') OR
    (owner_lane = 'group' AND
      group_id IS NOT NULL AND
      contact_account_peer_id IS NULL AND
      recipient_ml_kem_public_key IS NULL AND
      custody_kind = 'group_media_blob_v1')
  ),
  CHECK(
    (direction = 'outgoing' AND state IN (
      'outgoing_prepared',
      'outgoing_stored',
      'outgoing_cleanup_pending'
    )) OR
    (direction = 'incoming' AND state IN (
      'incoming_committed',
      'incoming_ack_pending'
    ))
  ),
  CHECK(
    (direction = 'outgoing' AND
      recipient_peer_id IS NOT NULL AND
      ciphertext_relative_path IS NOT NULL AND
      retry_count = 0 AND
      last_attempt_at IS NULL AND
      next_attempt_at IS NULL) OR
    (direction = 'incoming' AND
      recipient_peer_id IS NULL AND
      ciphertext_relative_path IS NULL AND
      inbox_custody_incarnation_id IS NULL)
  ),
  CHECK(
    owner_lane = 'group' OR
    (direction = 'outgoing' AND (
      (contact_account_peer_id IS NULL AND
        recipient_ml_kem_public_key IS NULL) OR
      (contact_account_peer_id IS NOT NULL AND
        recipient_ml_kem_public_key IS NOT NULL)
    )) OR
    (direction = 'incoming' AND recipient_ml_kem_public_key IS NULL)
  ),
  CHECK(
    (state = 'outgoing_prepared' AND
      inbox_custody_incarnation_id IS NULL AND
      expires_at_ms IS NULL AND
      custody_relay_peer_id IS NULL) OR
    (state = 'outgoing_stored' AND
      expires_at_ms IS NOT NULL AND
      custody_relay_peer_id IS NOT NULL) OR
    (state = 'outgoing_cleanup_pending' AND (
      (inbox_custody_incarnation_id IS NULL AND
        expires_at_ms IS NULL AND custody_relay_peer_id IS NULL) OR
      (expires_at_ms IS NOT NULL AND custody_relay_peer_id IS NOT NULL)
    )) OR
    (state = 'incoming_committed' AND
      expires_at_ms IS NOT NULL AND
      custody_relay_peer_id IS NULL AND
      retry_count = 0 AND
      last_attempt_at IS NULL AND
      next_attempt_at IS NULL) OR
    (state = 'incoming_ack_pending' AND
      expires_at_ms IS NOT NULL AND
      custody_relay_peer_id IS NOT NULL AND (
        (retry_count = 0 AND
          last_attempt_at IS NULL AND next_attempt_at IS NULL) OR
        (retry_count > 0 AND
          last_attempt_at IS NOT NULL AND next_attempt_at IS NOT NULL)
      ))
  ),
  CHECK(
    inbox_custody_incarnation_id IS NULL OR (
      direction = 'outgoing' AND
      state IN ('outgoing_stored', 'outgoing_cleanup_pending') AND
      expires_at_ms IS NOT NULL AND
      custody_relay_peer_id IS NOT NULL
    )
  )
);
''';

const List<String> _mediaBlobCustodyIndexSql = <String>[
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_direct_media_blob_custody_outgoing_target
ON direct_media_blob_custody(owner_lane, attachment_id, recipient_peer_id)
WHERE owner_lane = 'direct' AND direction = 'outgoing';
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_direct_media_blob_custody_incoming_attachment
ON direct_media_blob_custody(owner_lane, attachment_id)
WHERE owner_lane = 'direct' AND direction = 'incoming';
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_group_media_blob_custody_outgoing_target
ON direct_media_blob_custody(
  owner_lane, group_id, attachment_id, recipient_peer_id
)
WHERE owner_lane = 'group' AND direction = 'outgoing';
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_group_media_blob_custody_incoming_attachment
ON direct_media_blob_custody(owner_lane, group_id, attachment_id)
WHERE owner_lane = 'group' AND direction = 'incoming';
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_message
ON direct_media_blob_custody(
  owner_lane, group_id, message_id, direction, attachment_id, custody_blob_id
);
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_state_retry
ON direct_media_blob_custody(
  owner_lane, direction, state, next_attempt_at, updated_at,
  attachment_id, custody_blob_id
);
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_inbox_incarnation
ON direct_media_blob_custody(
  owner_lane, inbox_custody_incarnation_id, attachment_id, custody_blob_id
)
WHERE inbox_custody_incarnation_id IS NOT NULL;
''',
];

const String _groupMediaBlobFingerprintColumnSql = '''
TEXT CHECK(
  group_media_blob_custody_fingerprint IS NULL OR (
    typeof(group_media_blob_custody_fingerprint) = 'text' AND
    length(group_media_blob_custody_fingerprint) = 64 AND
    length(CAST(group_media_blob_custody_fingerprint AS BLOB)) = 64 AND
    group_media_blob_custody_fingerprint NOT GLOB '*[^0-9a-f]*'
  )
)
''';

int _singleCount(List<Map<String, Object?>> rows) =>
    (rows.single['n'] as num).toInt();

Future<Set<String>> _columnNames(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toSet();
