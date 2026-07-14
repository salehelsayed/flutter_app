// ignore_for_file: file_names

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const _migrationName = '100_direct_private_media_lifecycle';

const _columnSql = <String, String>{
  'private_media_policy_version':
      'INTEGER NOT NULL DEFAULT 0 '
      'CHECK (private_media_policy_version >= 0)',
  'private_media_mode':
      "TEXT NOT NULL DEFAULT 'ordinary' "
      "CHECK (private_media_mode IN "
      "('ordinary','protected','view_once','disappearing','unsupported'))",
  'private_media_duration_seconds':
      'INTEGER CHECK (private_media_duration_seconds IS NULL OR '
      'private_media_duration_seconds IN (3600,86400,604800))',
  'private_media_state':
      "TEXT NOT NULL DEFAULT 'none' "
      "CHECK (private_media_state IN "
      "('none','available','opening','viewing','consumed','expired','unsupported'))",
  'private_media_received_at_ms':
      'INTEGER CHECK (private_media_received_at_ms IS NULL OR '
      'private_media_received_at_ms >= 0)',
  'private_media_expires_at_ms':
      'INTEGER CHECK (private_media_expires_at_ms IS NULL OR '
      'private_media_expires_at_ms >= 0)',
  'private_media_revealed_at_ms':
      'INTEGER CHECK (private_media_revealed_at_ms IS NULL OR '
      'private_media_revealed_at_ms >= 0)',
  'private_media_terminal_at_ms':
      'INTEGER CHECK (private_media_terminal_at_ms IS NULL OR '
      'private_media_terminal_at_ms >= 0)',
  'private_media_clock_high_water_ms':
      'INTEGER CHECK (private_media_clock_high_water_ms IS NULL OR '
      'private_media_clock_high_water_ms >= 0)',
};

/// Adds the durable device-local private-media seed to direct parent rows.
///
/// Every legacy row remains version 0 / ordinary / none. The migration never
/// reads or mutates attachment owner lanes or group-message rows.
Future<void> runDirectPrivateMediaLifecycleMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DIRECT_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_START',
    details: const {'migration': _migrationName},
  );
  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final existingColumns = columns.map((row) => row['name'] as String).toSet();
    for (final entry in _columnSql.entries) {
      if (existingColumns.add(entry.key)) {
        await db.execute(
          'ALTER TABLE messages ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND tbl_name='messages'",
    );
    final indexNames = indexes.map((row) => row['name'] as String).toSet();
    if (!indexNames.contains('idx_messages_private_media_expiry')) {
      await db.execute(
        'CREATE INDEX idx_messages_private_media_expiry '
        'ON messages(private_media_expires_at_ms)',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'DIRECT_PRIVATE_MEDIA_LIFECYCLE_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
