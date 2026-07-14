import 'package:sqflite_sqlcipher/sqflite.dart';

const _memberPrefix = 'forward_auth_member_';
const _latestKeyGenerationAlias = 'forward_auth_latest_key_generation';

typedef GroupForwardAuthorizationSnapshotRows = ({
  Map<String, Object?>? groupRow,
  List<Map<String, Object?>> memberRows,
  int? latestKeyGeneration,
});

/// Loads the complete forwarding authorization surface with one SQL statement.
///
/// A single SELECT gives SQLite statement-snapshot consistency without holding
/// a write transaction across secure-store key hydration or media upload. The
/// member aliases avoid collisions with `groups.*`; the scalar key-generation
/// subquery is evaluated in that same snapshot.
Future<GroupForwardAuthorizationSnapshotRows>
dbLoadGroupForwardAuthorizationSnapshot(Database db, String groupId) async {
  final rows = await db.rawQuery(
    '''
SELECT
  groups.*,
  members.group_id AS ${_memberPrefix}group_id,
  members.peer_id AS ${_memberPrefix}peer_id,
  members.username AS ${_memberPrefix}username,
  members.role AS ${_memberPrefix}role,
  members.permissions_json AS ${_memberPrefix}permissions_json,
  members.public_key AS ${_memberPrefix}public_key,
  members.ml_kem_public_key AS ${_memberPrefix}ml_kem_public_key,
  members.devices_json AS ${_memberPrefix}devices_json,
  members.joined_at AS ${_memberPrefix}joined_at,
  (
    SELECT MAX(keys.key_generation)
    FROM group_keys AS keys
    WHERE keys.group_id = groups.id
  ) AS $_latestKeyGenerationAlias
FROM groups
LEFT JOIN group_members AS members ON members.group_id = groups.id
WHERE groups.id = ?
ORDER BY members.joined_at ASC, members.peer_id ASC
''',
    <Object?>[groupId],
  );
  if (rows.isEmpty) {
    return (
      groupRow: null,
      memberRows: const <Map<String, Object?>>[],
      latestKeyGeneration: null,
    );
  }

  final first = rows.first;
  final groupRow = Map<String, Object?>.from(first)
    ..removeWhere(
      (key, _) =>
          key.startsWith(_memberPrefix) || key == _latestKeyGenerationAlias,
    );
  final memberRows = <Map<String, Object?>>[];
  for (final row in rows) {
    if (row['${_memberPrefix}peer_id'] == null) continue;
    memberRows.add(<String, Object?>{
      'group_id': row['${_memberPrefix}group_id'],
      'peer_id': row['${_memberPrefix}peer_id'],
      'username': row['${_memberPrefix}username'],
      'role': row['${_memberPrefix}role'],
      'permissions_json': row['${_memberPrefix}permissions_json'],
      'public_key': row['${_memberPrefix}public_key'],
      'ml_kem_public_key': row['${_memberPrefix}ml_kem_public_key'],
      'devices_json': row['${_memberPrefix}devices_json'],
      'joined_at': row['${_memberPrefix}joined_at'],
    });
  }
  final rawGeneration = first[_latestKeyGenerationAlias];
  return (
    groupRow: groupRow,
    memberRows: memberRows,
    latestKeyGeneration: rawGeneration is num ? rawGeneration.toInt() : null,
  );
}
