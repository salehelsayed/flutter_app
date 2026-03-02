import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';

void main() {
  late Database db;
  late GroupRepositoryImpl repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);

    repo = GroupRepositoryImpl(
      dbInsertGroup: (row) => dbInsertGroup(db, row),
      dbLoadAllGroups: () => dbLoadAllGroups(db),
      dbLoadGroup: (id) => dbLoadGroup(db, id),
      dbUpdateGroup: (row) => dbUpdateGroup(db, row),
      dbDeleteGroup: (id) => dbDeleteGroup(db, id),
      dbLoadActiveGroups: () => dbLoadActiveGroups(db),
      dbArchiveGroup: (id) => dbArchiveGroup(db, id),
      dbUnarchiveGroup: (id) => dbUnarchiveGroup(db, id),
      dbInsertGroupMember: (row) => dbInsertGroupMember(db, row),
      dbLoadAllGroupMembers: (groupId) => dbLoadAllGroupMembers(db, groupId),
      dbLoadGroupMember: (groupId, peerId) =>
          dbLoadGroupMember(db, groupId, peerId),
      dbUpdateGroupMemberRole: (groupId, peerId, role) =>
          dbUpdateGroupMemberRole(db, groupId, peerId, role),
      dbDeleteGroupMember: (groupId, peerId) =>
          dbDeleteGroupMember(db, groupId, peerId),
      dbDeleteAllGroupMembers: (groupId) =>
          dbDeleteAllGroupMembers(db, groupId),
      dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
      dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
      dbLoadGroupKeyByGeneration: (groupId, gen) =>
          dbLoadGroupKeyByGeneration(db, groupId, gen),
      dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
    );
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime.utc(2026, 1, 15, 12, 0, 0);

  GroupModel makeGroup({
    String id = 'group-1',
    String topicName = '/mknoon/groups/group-1',
  }) {
    return GroupModel(
      id: id,
      name: 'Test Group',
      type: GroupType.chat,
      topicName: topicName,
      description: 'A test group',
      createdAt: now,
      createdBy: 'peer-creator',
      myRole: GroupRole.admin,
    );
  }

  GroupMember makeMember({
    String groupId = 'group-1',
    String peerId = 'peer-1',
    MemberRole role = MemberRole.writer,
  }) {
    return GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: 'Alice',
      role: role,
      publicKey: 'pk',
      mlKemPublicKey: 'mlkem',
      joinedAt: now,
    );
  }

  GroupKeyInfo makeKey({
    String groupId = 'group-1',
    int keyGeneration = 1,
  }) {
    return GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyGeneration,
      encryptedKey: 'base64-key-$keyGeneration',
      createdAt: now,
    );
  }

  // --- Group tests ---

  group('Groups', () {
    test('saveGroup and getGroup round-trip', () async {
      final group = makeGroup();
      await repo.saveGroup(group);

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.name, 'Test Group');
      expect(result.type, GroupType.chat);
    });

    test('getAllGroups returns all groups', () async {
      await repo.saveGroup(makeGroup(id: 'g1', topicName: '/t/1'));
      await repo.saveGroup(makeGroup(id: 'g2', topicName: '/t/2'));

      final all = await repo.getAllGroups();
      expect(all.length, 2);
    });

    test('updateGroup changes fields', () async {
      await repo.saveGroup(makeGroup());

      final updated = makeGroup().copyWith(name: 'Updated');
      await repo.updateGroup(updated);

      final result = await repo.getGroup('group-1');
      expect(result!.name, 'Updated');
    });

    test('deleteGroup removes the group', () async {
      await repo.saveGroup(makeGroup());
      await repo.deleteGroup('group-1');

      final result = await repo.getGroup('group-1');
      expect(result, isNull);
    });

    test('archiveGroup and unarchiveGroup work', () async {
      await repo.saveGroup(makeGroup());

      await repo.archiveGroup('group-1');
      var result = await repo.getGroup('group-1');
      expect(result!.isArchived, true);
      expect(result.archivedAt, isNotNull);

      await repo.unarchiveGroup('group-1');
      result = await repo.getGroup('group-1');
      expect(result!.isArchived, false);
      expect(result.archivedAt, isNull);
    });

    test('getActiveGroups excludes archived', () async {
      await repo.saveGroup(makeGroup(id: 'active', topicName: '/t/a'));
      await repo.saveGroup(makeGroup(id: 'archived', topicName: '/t/b'));
      await repo.archiveGroup('archived');

      final active = await repo.getActiveGroups();
      expect(active.length, 1);
      expect(active[0].id, 'active');
    });
  });

  // --- Member tests ---

  group('Members', () {
    test('saveMember and getMember round-trip', () async {
      await repo.saveMember(makeMember());

      final result = await repo.getMember('group-1', 'peer-1');
      expect(result, isNotNull);
      expect(result!.username, 'Alice');
      expect(result.role, MemberRole.writer);
    });

    test('getMembers returns all members for group', () async {
      await repo.saveMember(makeMember(peerId: 'peer-1'));
      await repo.saveMember(makeMember(peerId: 'peer-2'));

      final members = await repo.getMembers('group-1');
      expect(members.length, 2);
    });

    test('updateMemberRole changes the role', () async {
      await repo.saveMember(makeMember(role: MemberRole.writer));

      await repo.updateMemberRole('group-1', 'peer-1', MemberRole.admin);

      final result = await repo.getMember('group-1', 'peer-1');
      expect(result!.role, MemberRole.admin);
    });

    test('removeMember and removeAllMembers work', () async {
      await repo.saveMember(makeMember(peerId: 'peer-1'));
      await repo.saveMember(makeMember(peerId: 'peer-2'));

      await repo.removeMember('group-1', 'peer-1');
      expect((await repo.getMembers('group-1')).length, 1);

      await repo.removeAllMembers('group-1');
      expect((await repo.getMembers('group-1')).length, 0);
    });
  });

  // --- Key tests ---

  group('Keys', () {
    test('saveKey and getLatestKey round-trip', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 3));
      await repo.saveKey(makeKey(keyGeneration: 2));

      final latest = await repo.getLatestKey('group-1');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 3);
    });

    test('getKeyByGeneration returns correct key', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 2));

      final key = await repo.getKeyByGeneration('group-1', 1);
      expect(key, isNotNull);
      expect(key!.keyGeneration, 1);
      expect(key.encryptedKey, 'base64-key-1');
    });

    test('removeAllKeys clears all keys for group', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 2));

      await repo.removeAllKeys('group-1');

      final latest = await repo.getLatestKey('group-1');
      expect(latest, isNull);
    });
  });
}
