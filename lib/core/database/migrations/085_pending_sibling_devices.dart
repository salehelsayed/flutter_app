import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// R2 (12-P2): same-user sibling devices that announced themselves and are
/// awaiting an explicit user trust decision before admission. Persisted so a
/// pending request survives restart.
const String _createPendingSiblingDevicesSql = '''
CREATE TABLE IF NOT EXISTS pending_sibling_devices (
  group_id TEXT NOT NULL,
  member_peer_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  transport_peer_id TEXT NOT NULL,
  device_signing_public_key TEXT NOT NULL,
  ml_kem_public_key TEXT,
  key_package_id TEXT,
  verified_account_signing_public_key TEXT NOT NULL,
  announced_at TEXT NOT NULL,
  PRIMARY KEY (group_id, member_peer_id, device_id)
);
''';

const String _createPendingSiblingDevicesIndexSql = '''
CREATE INDEX IF NOT EXISTS idx_pending_sibling_devices_group
ON pending_sibling_devices(group_id, announced_at DESC);
''';

Future<void> runPendingSiblingDevicesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_SIBLING_DEVICES_MIGRATION_START',
    details: {'migration': '085_pending_sibling_devices'},
  );
  try {
    await db.execute(_createPendingSiblingDevicesSql);
    await db.execute(_createPendingSiblingDevicesIndexSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_SIBLING_DEVICES_MIGRATION_SUCCESS',
      details: {'migration': '085_pending_sibling_devices'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_SIBLING_DEVICES_MIGRATION_ERROR',
      details: {'migration': '085_pending_sibling_devices', 'error': e.toString()},
    );
    rethrow;
  }
}
