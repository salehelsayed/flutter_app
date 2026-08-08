// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '111_direct_media_blob_custody';

const _createDirectMediaBlobCustodyTableSql = '''
CREATE TABLE IF NOT EXISTS direct_media_blob_custody (
  attachment_id TEXT NOT NULL PRIMARY KEY
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

const _createDirectMediaBlobCustodyMessageIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_message
ON direct_media_blob_custody(message_id, direction, attachment_id);
''';

const _createDirectMediaBlobCustodyStateRetryIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_state_retry
ON direct_media_blob_custody(
  direction,
  state,
  next_attempt_at,
  updated_at,
  attachment_id
);
''';

const _createDirectMediaBlobCustodyInboxIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_direct_media_blob_custody_inbox_incarnation
ON direct_media_blob_custody(inbox_custody_incarnation_id, attachment_id)
WHERE inbox_custody_incarnation_id IS NOT NULL;
''';

const _v108MediaBlobExpiresColumnSql = '''
INTEGER CHECK(
  media_blob_expires_at_ms IS NULL OR (
    typeof(media_blob_expires_at_ms) = 'integer' AND
    media_blob_expires_at_ms > 0
  )
)
''';

// This column is added after `media_blob_expires_at_ms`, allowing its CHECK to
// enforce the all-or-none v108 binding without rebuilding the immutable table.
const _v108MediaBlobManifestHashColumnSql = '''
TEXT CHECK(
  (media_blob_manifest_hash IS NULL AND
    media_blob_expires_at_ms IS NULL) OR
  (
    typeof(media_blob_manifest_hash) = 'text' AND
    length(media_blob_manifest_hash) = 64 AND
    length(CAST(media_blob_manifest_hash AS BLOB)) = 64 AND
    media_blob_manifest_hash NOT GLOB '*[^0-9a-f]*' AND
    media_blob_expires_at_ms IS NOT NULL
  )
)
''';

const _mediaAttachmentDirectMediaBlobFingerprintColumnSql = '''
TEXT CHECK(
  direct_media_blob_custody_fingerprint IS NULL OR (
    typeof(direct_media_blob_custody_fingerprint) = 'text' AND
    length(direct_media_blob_custody_fingerprint) = 64 AND
    length(CAST(direct_media_blob_custody_fingerprint AS BLOB)) = 64 AND
    direct_media_blob_custody_fingerprint NOT GLOB '*[^0-9a-f]*'
  )
)
''';

/// Adds independent direct-media blob custody and nullable bindings on v108.
///
/// No table in this migration has a foreign key to a parent message or media
/// row. Ciphertext cleanup and incoming ACK obligations must survive parent
/// deletion. Existing v108 rows remain unbound: exact blob proofs cannot be
/// reconstructed safely from historical envelopes.
Future<void> runDirectMediaBlobCustodyMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_MEDIA_BLOB_CUSTODY_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    final attachmentColumns = await db.rawQuery(
      'PRAGMA table_info(media_attachments)',
    );
    final existingAttachmentColumns = attachmentColumns
        .map((row) => row['name'] as String)
        .toSet();
    if (existingAttachmentColumns.add(
      'direct_media_blob_custody_fingerprint',
    )) {
      await db.execute(
        'ALTER TABLE media_attachments '
        'ADD COLUMN direct_media_blob_custody_fingerprint '
        '$_mediaAttachmentDirectMediaBlobFingerprintColumnSql',
      );
    }

    final v108Columns = await db.rawQuery(
      'PRAGMA table_info(direct_inbox_custody_outbox)',
    );
    final existingV108Columns = v108Columns
        .map((row) => row['name'] as String)
        .toSet();
    if (existingV108Columns.add('media_blob_expires_at_ms')) {
      await db.execute(
        'ALTER TABLE direct_inbox_custody_outbox '
        'ADD COLUMN media_blob_expires_at_ms '
        '$_v108MediaBlobExpiresColumnSql',
      );
    }
    if (existingV108Columns.add('media_blob_manifest_hash')) {
      await db.execute(
        'ALTER TABLE direct_inbox_custody_outbox '
        'ADD COLUMN media_blob_manifest_hash '
        '$_v108MediaBlobManifestHashColumnSql',
      );
    }

    await db.execute(_createDirectMediaBlobCustodyTableSql);
    await db.execute(_createDirectMediaBlobCustodyMessageIndexSql);
    await db.execute(_createDirectMediaBlobCustodyStateRetryIndexSql);
    await db.execute(_createDirectMediaBlobCustodyInboxIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MEDIA_BLOB_CUSTODY_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_MEDIA_BLOB_CUSTODY_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
