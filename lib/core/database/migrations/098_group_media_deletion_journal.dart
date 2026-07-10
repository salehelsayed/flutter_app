// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// 235: local-only per-attachment deletion journal for group received-media
/// "Delete for me".
///
/// An explicit journal row — written in the SAME transaction that tombstones
/// and deletes the exact `(group_id, message_id)` parent — is the ONLY
/// authority for post-commit file/key/row cleanup. Orphan shape (a group-owned
/// attachment next to a same-ID tombstone) is never inferred as a deletion:
/// a same-ID parent in ANOTHER group can be silently rejected by the
/// migration-069 tombstone while its attachments were legitimately stored.
///
/// Deliberately: no wire mapping, no FOREIGN KEY, no cascade, and NO legacy
/// backfill — the upgrade starts empty because pre-v98 orphans cannot be
/// classified safely.
const _createGroupMediaDeletionJournalSql = '''
CREATE TABLE IF NOT EXISTS group_media_deletion_journal (
  attachment_id TEXT PRIMARY KEY,
  operation_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  operation_intent TEXT NOT NULL CHECK (operation_intent = 'delete_for_me'),
  normalized_mime TEXT NOT NULL,
  canonical_relative_path TEXT,
  created_at TEXT NOT NULL
);
''';

const _createGroupMediaDeletionJournalGroupMessageIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_media_deletion_journal_group_message
ON group_media_deletion_journal(group_id, message_id, operation_intent, attachment_id);
''';

const _createGroupMediaDeletionJournalOperationIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_media_deletion_journal_operation
ON group_media_deletion_journal(operation_id, attachment_id);
''';

Future<void> runGroupMediaDeletionJournalMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEDIA_DELETION_JOURNAL_MIGRATION_START',
    details: {'migration': '098_group_media_deletion_journal'},
  );

  try {
    await db.execute(_createGroupMediaDeletionJournalSql);
    await db.execute(_createGroupMediaDeletionJournalGroupMessageIndexSql);
    await db.execute(_createGroupMediaDeletionJournalOperationIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEDIA_DELETION_JOURNAL_MIGRATION_SUCCESS',
      details: {'migration': '098_group_media_deletion_journal'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEDIA_DELETION_JOURNAL_MIGRATION_ERROR',
      details: {
        'migration': '098_group_media_deletion_journal',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
