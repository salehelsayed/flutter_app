import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 011: Adds `avatar_version` column to `identity` and `contacts`.
///
/// Idempotent: catches "duplicate column" errors silently.
Future<void> runAvatarVersionMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'AVATAR_VERSION_MIGRATION_START',
    details: {'migration': '011_avatar_version'},
  );

  try {
    try {
      await db.execute('ALTER TABLE identity ADD COLUMN avatar_version TEXT');
    } catch (e) {
      if (!e.toString().contains('duplicate column')) rethrow;
    }

    try {
      await db.execute('ALTER TABLE contacts ADD COLUMN avatar_version TEXT');
    } catch (e) {
      if (!e.toString().contains('duplicate column')) rethrow;
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'AVATAR_VERSION_MIGRATION_SUCCESS',
      details: {'migration': '011_avatar_version'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'AVATAR_VERSION_MIGRATION_ERROR',
      details: {'migration': '011_avatar_version', 'error': e.toString()},
    );
    rethrow;
  }
}
