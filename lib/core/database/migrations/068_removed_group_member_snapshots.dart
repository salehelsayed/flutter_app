import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _createRemovedGroupMemberSnapshotsSql = '''
CREATE TABLE IF NOT EXISTS removed_group_member_snapshots (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  username TEXT,
  role TEXT NOT NULL CHECK(role IN ('admin','writer','reader')),
  public_key TEXT,
  ml_kem_public_key TEXT,
  joined_at TEXT NOT NULL,
  permissions_json TEXT,
  devices_json TEXT,
  removed_at TEXT NOT NULL,
  PRIMARY KEY (group_id, peer_id)
);
''';

const String _createRemovedGroupMemberSnapshotsIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_removed_group_member_snapshots_group
ON removed_group_member_snapshots(group_id, removed_at DESC);
''';

Future<void> runRemovedGroupMemberSnapshotsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'REMOVED_GROUP_MEMBER_SNAPSHOTS_MIGRATION_START',
    details: {'migration': '068_removed_group_member_snapshots'},
  );

  try {
    await db.execute(_createRemovedGroupMemberSnapshotsSql);
    await db.execute(_createRemovedGroupMemberSnapshotsIndexSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'REMOVED_GROUP_MEMBER_SNAPSHOTS_MIGRATION_SUCCESS',
      details: {'migration': '068_removed_group_member_snapshots'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'REMOVED_GROUP_MEMBER_SNAPSHOTS_MIGRATION_ERROR',
      details: {
        'migration': '068_removed_group_member_snapshots',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
