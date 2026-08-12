// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '114_direct_linked_device_media_blob_fanout';

/// DB v114 rebuilds ONLY the incumbent v111 `direct_media_blob_custody` owner
/// so one canonical attachment can own several physical-recipient blob
/// obligations (Plan 362 / GAP-N01 adopter).
///
/// * `attachment_id` loses its PRIMARY KEY and stays non-unique; the natural
///   exact row identity becomes `(attachment_id, direction,
///   recipient_peer_id)` with `recipient_peer_id IS NULL` for incoming.
///   Two explicit partial unique indexes enforce one outgoing row per
///   `(attachment_id, recipient_peer_id)` and one incoming row per
///   `attachment_id`. No synthetic row ID and no FK is added.
/// * Nullable `contact_account_peer_id` records the LOGICAL contact of a
///   newly authored LINKED row. Nullable `recipient_ml_kem_public_key`
///   persists the exact target key an outgoing linked row was encrypted for.
///   Outgoing rows carry both together or neither (historical rows keep both
///   NULL and gain no inferred fanout authority); incoming rows never carry a
///   recipient key, and linked incoming keeps `recipient_peer_id` NULL. The
///   dynamic legacy-primary target may have `recipient_peer_id ==
///   contact_account_peer_id`, so no blanket inequality is imposed.
/// * `media_attachments.direct_media_blob_custody_fingerprint_version` is
///   added nullable. NULL retains the incumbent exact target-specific digest
///   contract; version 2 marks the sender-local OUTGOING ordinary/disappearing
///   target-independent generation digest and requires the fingerprint itself
///   to be present. Contradictory shapes are refused by the CHECK.
///
/// Every historical row is copied byte-for-byte with the new columns NULL.
/// The rebuild, its indexes and the attachment fingerprint schema commit (or
/// roll back) together with the migration transaction; v114 remains a one-way
/// schema floor.
Future<void> runDirectLinkedDeviceMediaBlobFanoutMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_LINKED_DEVICE_MEDIA_BLOB_FANOUT_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    final attachmentColumns = await _columnNames(db, 'media_attachments');
    if (!attachmentColumns.contains(
      'direct_media_blob_custody_fingerprint_version',
    )) {
      await db.execute(
        'ALTER TABLE media_attachments '
        'ADD COLUMN direct_media_blob_custody_fingerprint_version '
        '$_mediaAttachmentFingerprintVersionColumnSql',
      );
    }

    final custodyColumns = await _columnNames(db, 'direct_media_blob_custody');
    if (!custodyColumns.contains('contact_account_peer_id')) {
      await db.execute(_createRebuiltDirectMediaBlobCustodyTableSql);
      await db.execute('''
        INSERT INTO direct_media_blob_custody_v114_rebuild (
          attachment_id, message_id, direction, state,
          inbox_custody_incarnation_id, recipient_peer_id,
          contact_account_peer_id, recipient_ml_kem_public_key,
          ciphertext_relative_path, custody_kind, custody_contract,
          content_hash, ciphertext_size, transport_mime, expires_at_ms,
          custody_relay_peer_id, retry_count, last_attempt_at,
          next_attempt_at, created_at, updated_at
        )
        SELECT
          attachment_id, message_id, direction, state,
          inbox_custody_incarnation_id, recipient_peer_id,
          NULL, NULL,
          ciphertext_relative_path, custody_kind, custody_contract,
          content_hash, ciphertext_size, transport_mime, expires_at_ms,
          custody_relay_peer_id, retry_count, last_attempt_at,
          next_attempt_at, created_at, updated_at
        FROM direct_media_blob_custody
      ''');
      final legacyCount = _singleCount(
        await db.rawQuery(
          'SELECT COUNT(*) AS n FROM direct_media_blob_custody',
        ),
      );
      final rebuiltCount = _singleCount(
        await db.rawQuery(
          'SELECT COUNT(*) AS n FROM direct_media_blob_custody_v114_rebuild',
        ),
      );
      if (legacyCount != rebuiltCount) {
        throw StateError(
          'v114 direct_media_blob_custody rebuild lost rows '
          '($legacyCount -> $rebuiltCount)',
        );
      }
      await db.execute('DROP TABLE direct_media_blob_custody');
      await db.execute(
        'ALTER TABLE direct_media_blob_custody_v114_rebuild '
        'RENAME TO direct_media_blob_custody',
      );
    }

    for (final indexSql in _directMediaBlobCustodyIndexSql) {
      await db.execute(indexSql);
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_MEDIA_BLOB_FANOUT_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_LINKED_DEVICE_MEDIA_BLOB_FANOUT_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}

/// The v114 rebuild preserves every v111 column, CHECK and state shape
/// verbatim, removes only the `attachment_id` PRIMARY KEY, and adds the two
/// nullable linked-fanout columns with their cross-column shape CHECK.
const _createRebuiltDirectMediaBlobCustodyTableSql = '''
CREATE TABLE IF NOT EXISTS direct_media_blob_custody_v114_rebuild (
  attachment_id TEXT NOT NULL
    CHECK(length(trim(attachment_id)) > 0),
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
      ciphertext_relative_path LIKE 'direct_media_blob_custody_v1/%/%' AND
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
  custody_kind TEXT NOT NULL CHECK(custody_kind = 'direct_media_blob_v1'),
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

const _directMediaBlobCustodyIndexSql = <String>[
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_direct_media_blob_custody_outgoing_target
ON direct_media_blob_custody(attachment_id, recipient_peer_id)
WHERE direction = 'outgoing';
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS
  idx_direct_media_blob_custody_incoming_attachment
ON direct_media_blob_custody(attachment_id)
WHERE direction = 'incoming';
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_message
ON direct_media_blob_custody(message_id, direction, attachment_id);
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_state_retry
ON direct_media_blob_custody(
  direction,
  state,
  next_attempt_at,
  updated_at,
  attachment_id
);
''',
  '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_inbox_incarnation
ON direct_media_blob_custody(inbox_custody_incarnation_id, attachment_id)
WHERE inbox_custody_incarnation_id IS NOT NULL;
''',
];

// Added after `direct_media_blob_custody_fingerprint` (v111), so the CHECK may
// reference it and refuse a version without a digest, without rebuilding the
// immutable media_attachments table.
const _mediaAttachmentFingerprintVersionColumnSql = '''
INTEGER CHECK(
  direct_media_blob_custody_fingerprint_version IS NULL OR (
    typeof(direct_media_blob_custody_fingerprint_version) = 'integer' AND
    direct_media_blob_custody_fingerprint_version = 2 AND
    direct_media_blob_custody_fingerprint IS NOT NULL
  )
)
''';

int _singleCount(List<Map<String, Object?>> rows) =>
    (rows.single['n'] as num).toInt();

Future<Set<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}
