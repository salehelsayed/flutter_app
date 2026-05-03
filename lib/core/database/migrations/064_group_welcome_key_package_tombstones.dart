import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _createGroupWelcomeKeyPackageTombstonesTableSql = '''
CREATE TABLE IF NOT EXISTS group_welcome_key_package_tombstones (
  package_id TEXT NOT NULL,
  recipient_device_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  invite_id TEXT NOT NULL,
  public_material_hash TEXT NOT NULL,
  consumed_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  PRIMARY KEY(package_id, recipient_device_id, group_id)
);
''';

const String _createGroupWelcomeKeyPackageTombstonesExpiresAtIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_welcome_key_package_tombstones_expires_at
ON group_welcome_key_package_tombstones(expires_at);
''';

Future<void> runGroupWelcomeKeyPackageTombstonesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONES_MIGRATION_START',
    details: {'migration': '064_group_welcome_key_package_tombstones'},
  );

  try {
    await db.execute(_createGroupWelcomeKeyPackageTombstonesTableSql);
    await db.execute(_createGroupWelcomeKeyPackageTombstonesExpiresAtIndexSql);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONES_MIGRATION_SUCCESS',
      details: {'migration': '064_group_welcome_key_package_tombstones'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONES_MIGRATION_ERROR',
      details: {
        'migration': '064_group_welcome_key_package_tombstones',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
