// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 096 (228): shared media library + local viewer-state columns.
///
/// Adds to `media_attachments`:
///  - `owner_lane TEXT NOT NULL DEFAULT 'unresolved'` with an enforced
///    three-value CHECK (`direct` / `group` / `unresolved`). Direct and group
///    message IDs are independent table-local primary keys, so the same
///    parent ID can legally exist in BOTH lanes — the attachment row itself
///    must carry its owner.
///  - `is_bookmarked INTEGER NOT NULL DEFAULT 0` (local-only, never on wire).
///  - `last_playback_position_ms INTEGER NOT NULL DEFAULT 0` (local-only).
///
/// Backfill is deterministic and fail-closed: a row still `unresolved` is
/// classified `direct` only when its parent exists SOLELY in `messages`, and
/// `group` only when it exists SOLELY in `group_messages`. Rows whose parent
/// exists in both lanes (ambiguous) or neither (orphan) stay `unresolved` and
/// are excluded from owner-scoped reads/mutations. Parent-existence inference
/// is migration-only — ordinary writes must carry an explicit owner.
///
/// Idempotent and crash-resumable: each ALTER is guarded by column presence,
/// the backfill only touches `unresolved` rows with a uniquely-owned parent,
/// and the indexes use IF NOT EXISTS. A second run never mutates an owner
/// that is no longer `unresolved`.
Future<void> runMediaLibraryStateMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_LIBRARY_STATE_MIGRATION_START',
    details: {'migration': '096_media_library_state'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(media_attachments)');
    final columnNames = columns.map((col) => col['name'] as String).toSet();

    if (!columnNames.contains('owner_lane')) {
      await db.execute(
        "ALTER TABLE media_attachments ADD COLUMN owner_lane TEXT NOT NULL "
        "DEFAULT 'unresolved' "
        "CHECK (owner_lane IN ('direct', 'group', 'unresolved'))",
      );
    }
    if (!columnNames.contains('is_bookmarked')) {
      await db.execute(
        'ALTER TABLE media_attachments ADD COLUMN is_bookmarked INTEGER '
        'NOT NULL DEFAULT 0',
      );
    }
    if (!columnNames.contains('last_playback_position_ms')) {
      await db.execute(
        'ALTER TABLE media_attachments ADD COLUMN last_playback_position_ms '
        'INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Deterministic fail-closed backfill (unique parent only).
    await db.execute('''
      UPDATE media_attachments SET owner_lane = 'direct'
      WHERE owner_lane = 'unresolved'
        AND message_id IN (SELECT id FROM messages)
        AND message_id NOT IN (SELECT id FROM group_messages)
    ''');
    await db.execute('''
      UPDATE media_attachments SET owner_lane = 'group'
      WHERE owner_lane = 'unresolved'
        AND message_id IN (SELECT id FROM group_messages)
        AND message_id NOT IN (SELECT id FROM messages)
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_attachments_owner_message '
      'ON media_attachments(owner_lane, message_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_attachments_owner_bookmark_message '
      'ON media_attachments(owner_lane, is_bookmarked, message_id)',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_LIBRARY_STATE_MIGRATION_SUCCESS',
      details: {'migration': '096_media_library_state'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_LIBRARY_STATE_MIGRATION_ERROR',
      details: {'migration': '096_media_library_state', 'error': e.toString()},
    );
    rethrow;
  }
}
