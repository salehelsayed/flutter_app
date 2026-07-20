// ignore_for_file: file_names
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// B4 (12-P2 R3): the persisted "last known device-set" baseline a group member
/// is compared against, so adding/swapping a per-device key surfaces a
/// safety-number warning even when the account keys are unchanged.
///
/// Keyed by (group_id, peer_id) like `removed_group_member_snapshots` (068), but
/// written on the verify/observe path (TOFU) rather than at removal.
const String _createGroupMemberDeviceSnapshotsSql = '''
CREATE TABLE IF NOT EXISTS group_member_device_snapshots (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  public_key TEXT,
  ml_kem_public_key TEXT,
  devices_json TEXT,
  saved_at TEXT NOT NULL,
  PRIMARY KEY (group_id, peer_id)
);
''';

const String _createGroupMemberDeviceSnapshotsIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_group_member_device_snapshots_group
ON group_member_device_snapshots(group_id, saved_at DESC);
''';

Future<void> runGroupMemberDeviceSnapshotsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBER_DEVICE_SNAPSHOTS_MIGRATION_START',
    details: {'migration': '084_group_member_device_snapshots'},
  );

  try {
    await db.execute(_createGroupMemberDeviceSnapshotsSql);
    await db.execute(_createGroupMemberDeviceSnapshotsIndexSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_DEVICE_SNAPSHOTS_MIGRATION_SUCCESS',
      details: {'migration': '084_group_member_device_snapshots'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_DEVICE_SNAPSHOTS_MIGRATION_ERROR',
      details: {
        'migration': '084_group_member_device_snapshots',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
