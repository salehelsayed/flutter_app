// ignore_for_file: file_names

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const _migrationName = '101_group_private_media_lifecycle';

const _columnSql = <String, String>{
  'media_policy_version':
      "INTEGER NOT NULL DEFAULT 0 CHECK (typeof(media_policy_version) = 'integer' AND media_policy_version >= 0)",
  'media_lifecycle':
      "TEXT NOT NULL DEFAULT 'standard' CHECK (media_lifecycle IN ('standard','view_once','disappearing','unsupported'))",
  'media_duration_seconds':
      "INTEGER CHECK (media_duration_seconds IS NULL OR (typeof(media_duration_seconds) = 'integer' AND media_duration_seconds IN (3600,86400,604800)))",
  'media_protected':
      'INTEGER NOT NULL DEFAULT 0 CHECK (media_protected IN (0,1))',
  'media_received_at':
      "INTEGER CHECK (media_received_at IS NULL OR (typeof(media_received_at) = 'integer' AND media_received_at >= 0))",
  'media_expires_at':
      "INTEGER CHECK (media_expires_at IS NULL OR (typeof(media_expires_at) = 'integer' AND media_expires_at >= 0))",
  'media_last_checked_at':
      "INTEGER CHECK (media_last_checked_at IS NULL OR (typeof(media_last_checked_at) = 'integer' AND media_last_checked_at >= 0))",
  'media_consumed_at':
      "INTEGER CHECK (media_consumed_at IS NULL OR (typeof(media_consumed_at) = 'integer' AND media_consumed_at >= 0))",
  'media_expired_at':
      "INTEGER CHECK (media_expired_at IS NULL OR (typeof(media_expired_at) = 'integer' AND media_expired_at >= 0))",
  'media_cleanup_pending':
      'INTEGER NOT NULL DEFAULT 0 CHECK (media_cleanup_pending IN (0,1))',
};

/// Adds the message-scoped, device-local group private-media lifecycle seed.
///
/// Existing group rows remain version 0 / standard / unprotected with no
/// lifecycle timestamps. The migration never rebuilds the table and never
/// reads or mutates direct-message or attachment ownership state.
Future<void> runGroupPrivateMediaLifecycleMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_START',
    details: const {'migration': _migrationName},
  );
  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_messages)');
    final existingColumns = columns.map((row) => row['name'] as String).toSet();
    for (final entry in _columnSql.entries) {
      if (existingColumns.add(entry.key)) {
        await db.execute(
          'ALTER TABLE group_messages ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND tbl_name='group_messages'",
    );
    final indexNames = indexes.map((row) => row['name'] as String).toSet();
    if (!indexNames.contains('idx_group_messages_private_media_expiry')) {
      await db.execute(
        'CREATE INDEX idx_group_messages_private_media_expiry '
        'ON group_messages(media_expires_at)',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
