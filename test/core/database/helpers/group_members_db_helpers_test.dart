import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/057_group_member_permissions.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupsTablesMigration(db);
    await runGroupMemberPermissionsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeMemberRow({
    String groupId = 'group-1',
    String peerId = 'peer-1',
    String? username = 'Alice',
    String role = 'writer',
    String? publicKey = 'pk-base64',
    String? mlKemPublicKey = 'mlkem-base64',
    String? permissionsJson,
    String joinedAt = '2026-01-15T12:00:00.000Z',
  }) {
    return {
      'group_id': groupId,
      'peer_id': peerId,
      'username': username,
      'role': role,
      'public_key': publicKey,
      'ml_kem_public_key': mlKemPublicKey,
      'permissions_json': permissionsJson,
      'joined_at': joinedAt,
    };
  }

  group('dbInsertGroupMember', () {
    test('inserts a new member', () async {
      await dbInsertGroupMember(db, makeMemberRow());

      final rows = await db.query('group_members');
      expect(rows.length, 1);
      expect(rows[0]['peer_id'], 'peer-1');
      expect(rows[0]['username'], 'Alice');
    });
  });

  group('dbLoadAllGroupMembers', () {
    test('returns all members for a group ordered by joined_at ASC', () async {
      await dbInsertGroupMember(
        db,
        makeMemberRow(peerId: 'peer-2', joinedAt: '2026-01-16T00:00:00.000Z'),
      );
      await dbInsertGroupMember(
        db,
        makeMemberRow(peerId: 'peer-1', joinedAt: '2026-01-15T00:00:00.000Z'),
      );

      final results = await dbLoadAllGroupMembers(db, 'group-1');
      expect(results.length, 2);
      expect(results[0]['peer_id'], 'peer-1');
      expect(results[1]['peer_id'], 'peer-2');
    });
  });

  group('dbLoadGroupMember', () {
    test('returns null for non-existent member', () async {
      final result = await dbLoadGroupMember(db, 'group-1', 'peer-999');
      expect(result, isNull);
    });

    test('returns member when it exists', () async {
      await dbInsertGroupMember(db, makeMemberRow());

      final result = await dbLoadGroupMember(db, 'group-1', 'peer-1');
      expect(result, isNotNull);
      expect(result!['username'], 'Alice');
    });

    test('preserves permissions_json', () async {
      await dbInsertGroupMember(
        db,
        makeMemberRow(permissionsJson: '{"inviteMembers":true}'),
      );

      final result = await dbLoadGroupMember(db, 'group-1', 'peer-1');
      expect(result, isNotNull);
      expect(result!['permissions_json'], '{"inviteMembers":true}');
    });
  });

  group('dbUpdateGroupMemberRole', () {
    test('updates the role field', () async {
      await dbInsertGroupMember(db, makeMemberRow(role: 'writer'));

      await dbUpdateGroupMemberRole(db, 'group-1', 'peer-1', 'admin');

      final result = await dbLoadGroupMember(db, 'group-1', 'peer-1');
      expect(result!['role'], 'admin');
    });
  });

  group('dbDeleteGroupMember', () {
    test('deletes a single member', () async {
      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-1'));
      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-2'));

      await dbDeleteGroupMember(db, 'group-1', 'peer-1');

      final results = await dbLoadAllGroupMembers(db, 'group-1');
      expect(results.length, 1);
      expect(results[0]['peer_id'], 'peer-2');
    });
  });

  group('dbCountGroupMembers', () {
    test('returns correct count', () async {
      expect(await dbCountGroupMembers(db, 'group-1'), 0);

      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-1'));
      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-2'));

      expect(await dbCountGroupMembers(db, 'group-1'), 2);
    });
  });

  group('dbDeleteAllGroupMembers', () {
    test('deletes all members for a group', () async {
      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-1'));
      await dbInsertGroupMember(db, makeMemberRow(peerId: 'peer-2'));
      await dbInsertGroupMember(
        db,
        makeMemberRow(groupId: 'group-2', peerId: 'peer-3'),
      );

      await dbDeleteAllGroupMembers(db, 'group-1');

      expect(await dbCountGroupMembers(db, 'group-1'), 0);
      expect(await dbCountGroupMembers(db, 'group-2'), 1);
    });
  });
}
