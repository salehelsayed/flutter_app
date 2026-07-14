import 'package:flutter_app/core/database/helpers/group_forward_authorization_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('maps aliases, no-member row, and current MAX key generation', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
CREATE TABLE groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  topic_name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  created_by TEXT NOT NULL,
  my_role TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE group_members (
  group_id TEXT NOT NULL,
  peer_id TEXT NOT NULL,
  username TEXT,
  role TEXT NOT NULL,
  permissions_json TEXT,
  public_key TEXT,
  ml_kem_public_key TEXT,
  devices_json TEXT,
  joined_at TEXT NOT NULL,
  PRIMARY KEY (group_id, peer_id)
)
''');
    await db.execute('''
CREATE TABLE group_keys (
  group_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL
)
''');
    for (final id in <String>['sql-target', 'empty-target']) {
      await db.insert('groups', <String, Object?>{
        'id': id,
        'name': id,
        'type': 'chat',
        'topic_name': 'topic-$id',
        'created_at': '2026-07-12T00:00:00.000Z',
        'created_by': 'creator',
        'my_role': 'member',
      });
    }
    await db.insert('group_members', <String, Object?>{
      'group_id': 'sql-target',
      'peer_id': 'later',
      'role': 'writer',
      'joined_at': '2026-07-12T00:02:00.000Z',
    });
    await db.insert('group_members', <String, Object?>{
      'group_id': 'sql-target',
      'peer_id': 'earlier',
      'role': 'admin',
      'joined_at': '2026-07-12T00:01:00.000Z',
    });
    await db.insert('group_keys', <String, Object?>{
      'group_id': 'sql-target',
      'key_generation': 2,
    });
    await db.insert('group_keys', <String, Object?>{
      'group_id': 'sql-target',
      'key_generation': 7,
    });

    final snapshot = await dbLoadGroupForwardAuthorizationSnapshot(
      db,
      'sql-target',
    );
    expect(GroupModel.fromMap(snapshot.groupRow!).id, 'sql-target');
    expect(
      snapshot.memberRows
          .map(GroupMember.fromMap)
          .map((member) => member.peerId),
      <String>['earlier', 'later'],
    );
    expect(snapshot.latestKeyGeneration, 7);
    expect(
      snapshot.groupRow!.keys.where(
        (key) => key.startsWith('forward_auth_member_'),
      ),
      isEmpty,
    );

    final noMembers = await dbLoadGroupForwardAuthorizationSnapshot(
      db,
      'empty-target',
    );
    expect(noMembers.groupRow?['id'], 'empty-target');
    expect(noMembers.memberRows, isEmpty);
    expect(noMembers.latestKeyGeneration, isNull);

    final missing = await dbLoadGroupForwardAuthorizationSnapshot(
      db,
      'missing-target',
    );
    expect(missing.groupRow, isNull);
    expect(missing.memberRows, isEmpty);
    expect(missing.latestKeyGeneration, isNull);
  });
}
