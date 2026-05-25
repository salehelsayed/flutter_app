import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/database/migrations/017_groups_tables.dart';
import 'package:flutter_app/core/database/migrations/018_group_messages_tables.dart';
import 'package:flutter_app/core/database/migrations/026_group_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/048_groups_last_membership_event_at.dart';
import 'package:flutter_app/core/database/migrations/049_groups_metadata_columns.dart';
import 'package:flutter_app/core/database/migrations/050_groups_mute_column.dart';
import 'package:flutter_app/core/database/migrations/052_groups_dissolve_columns.dart';
import 'package:flutter_app/core/database/migrations/053_groups_backlog_retention_columns.dart';
import 'package:flutter_app/core/database/migrations/057_group_member_permissions.dart';
import 'package:flutter_app/core/database/migrations/062_group_member_device_identities.dart';
import 'package:flutter_app/core/database/migrations/068_removed_group_member_snapshots.dart';
import 'package:flutter_app/core/database/migrations/070_group_key_rotation_drafts.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  late Database db;
  late GroupRepositoryImpl repo;
  late FakeSecureKeyStore groupKeyStore;
  late FakeSecureKeyStore sharedPushKeyStore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupsTablesMigration(db);
    await runGroupMessagesTablesMigration(db);
    await runGroupQuotedMessageIdMigration(db);
    await runGroupsLastMembershipEventAtMigration(db);
    await runGroupsMetadataColumnsMigration(db);
    await runGroupsMuteColumnMigration(db);
    await runGroupsDissolveColumnsMigration(db);
    await runGroupsBacklogRetentionColumnsMigration(db);
    await runGroupMemberPermissionsMigration(db);
    await runGroupMemberDeviceIdentitiesMigration(db);
    await runRemovedGroupMemberSnapshotsMigration(db);
    await runGroupKeyRotationDraftsMigration(db);
    groupKeyStore = FakeSecureKeyStore();
    sharedPushKeyStore = FakeSecureKeyStore();

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
      dbInsertRemovedGroupMemberSnapshot: (row, removedAt) =>
          dbInsertRemovedGroupMemberSnapshot(db, row, removedAt),
      dbLoadRemovedGroupMemberSnapshot: (groupId, peerId) =>
          dbLoadRemovedGroupMemberSnapshot(db, groupId, peerId),
      dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
      dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(db, groupId),
      dbLoadGroupKeyByGeneration: (groupId, gen) =>
          dbLoadGroupKeyByGeneration(db, groupId, gen),
      dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(db, groupId),
      dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(db, groupId),
      dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
          dbDeleteGroupKeysBeforeGeneration(
            db,
            groupId,
            minKeyGenerationToKeep,
          ),
      dbUpsertPendingGroupKeyRotation: (row) =>
          dbUpsertPendingGroupKeyRotation(db, row),
      dbLoadPendingGroupKeyRotation: (groupId) =>
          dbLoadPendingGroupKeyRotation(db, groupId),
      dbDeletePendingGroupKeyRotation: (groupId, keyGeneration) =>
          dbDeletePendingGroupKeyRotation(db, groupId, keyGeneration),
      dbDeletePendingGroupKeyRotations: (groupId) =>
          dbDeletePendingGroupKeyRotations(db, groupId),
      groupKeyStore: groupKeyStore,
      pushSharedKeyStore: sharedPushKeyStore,
    );
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime.utc(2026, 1, 15, 12, 0, 0);

  GroupModel makeGroup({
    String id = 'group-1',
    String topicName = '/mknoon/groups/group-1',
    GroupType type = GroupType.chat,
  }) {
    return GroupModel(
      id: id,
      name: 'Test Group',
      type: type,
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
    String? encryptedKey,
  }) {
    return GroupKeyInfo(
      groupId: groupId,
      keyGeneration: keyGeneration,
      encryptedKey: encryptedKey ?? 'base64-key-$keyGeneration',
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

    test(
      'saveGroup and getGroup preserve announcement type through DB mapping',
      () async {
        await repo.saveGroup(
          makeGroup(
            id: 'announcement-group',
            topicName: '/mknoon/groups/announcement-group',
            type: GroupType.announcement,
          ),
        );

        final result = await repo.getGroup('announcement-group');
        expect(result, isNotNull);
        expect(result!.type, GroupType.announcement);
        expect(result.createdBy, 'peer-creator');
        expect(result.myRole, GroupRole.admin);
      },
    );

    test('updateGroup changes fields', () async {
      await repo.saveGroup(makeGroup());

      final updated = makeGroup().copyWith(name: 'Updated');
      await repo.updateGroup(updated);

      final result = await repo.getGroup('group-1');
      expect(result!.name, 'Updated');
    });

    test('saveGroup and getGroup round-trip membership watermark', () async {
      await repo.saveGroup(
        makeGroup().copyWith(
          lastMembershipEventAt: DateTime.utc(2026, 4, 5, 12, 30),
        ),
      );

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.lastMembershipEventAt, DateTime.utc(2026, 4, 5, 12, 30));
    });

    test('saveGroup and getGroup round-trip metadata fields', () async {
      await repo.saveGroup(
        makeGroup().copyWith(
          avatarBlobId: 'blob-1',
          avatarMime: 'image/jpeg',
          avatarPath: 'media/group_avatars/group-1.jpg',
          lastMetadataEventAt: DateTime.utc(2026, 4, 5, 12, 45),
        ),
      );

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.avatarBlobId, 'blob-1');
      expect(result.avatarMime, 'image/jpeg');
      expect(result.avatarPath, 'media/group_avatars/group-1.jpg');
      expect(result.lastMetadataEventAt, DateTime.utc(2026, 4, 5, 12, 45));
    });

    test('saveGroup and getGroup round-trip mute state', () async {
      await repo.saveGroup(makeGroup().copyWith(isMuted: true));

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.isMuted, isTrue);

      await repo.updateGroup(result.copyWith(isMuted: false));

      final unmuted = await repo.getGroup('group-1');
      expect(unmuted, isNotNull);
      expect(unmuted!.isMuted, isFalse);
    });

    test('saveGroup and getGroup round-trip dissolved state', () async {
      await repo.saveGroup(
        makeGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 15, 0),
          dissolvedBy: 'peer-admin',
        ),
      );

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.isDissolved, isTrue);
      expect(result.dissolvedAt, DateTime.utc(2026, 4, 5, 15, 0));
      expect(result.dissolvedBy, 'peer-admin');

      await repo.updateGroup(
        result.copyWith(
          isDissolved: false,
          dissolvedAt: null,
          dissolvedBy: null,
        ),
      );

      final reopened = await repo.getGroup('group-1');
      expect(reopened, isNotNull);
      expect(reopened!.isDissolved, isFalse);
      expect(reopened.dissolvedAt, isNull);
      expect(reopened.dissolvedBy, isNull);
    });

    test('saveGroup and getGroup round-trip backlog retention state', () async {
      await repo.saveGroup(
        makeGroup().copyWith(
          lastBacklogExpiredAt: DateTime.utc(2026, 4, 1, 9, 0),
          lastBacklogRetainedAt: DateTime.utc(2026, 4, 3, 10, 15),
        ),
      );

      final result = await repo.getGroup('group-1');
      expect(result, isNotNull);
      expect(result!.lastBacklogExpiredAt, DateTime.utc(2026, 4, 1, 9, 0));
      expect(result.lastBacklogRetainedAt, DateTime.utc(2026, 4, 3, 10, 15));

      await repo.updateGroup(
        result.copyWith(
          lastBacklogExpiredAt: null,
          lastBacklogRetainedAt: null,
        ),
      );

      final cleared = await repo.getGroup('group-1');
      expect(cleared, isNotNull);
      expect(cleared!.lastBacklogExpiredAt, isNull);
      expect(cleared.lastBacklogRetainedAt, isNull);
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

    test('saveMember and getMember preserve permission overrides', () async {
      await repo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-permissions',
          username: 'Pat',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(
            inviteMembers: true,
            removeMembers: false,
          ),
          publicKey: 'pk',
          joinedAt: now,
        ),
      );

      final result = await repo.getMember('group-1', 'peer-permissions');
      expect(result, isNotNull);
      expect(
        result!.permissions.allows(
          GroupMemberPermission.inviteMembers,
          result.role,
        ),
        isTrue,
      );
      expect(
        result.permissions.allows(
          GroupMemberPermission.removeMembers,
          result.role,
        ),
        isFalse,
      );
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

    test('removed member snapshot survives active member deletion', () async {
      final removedAt = now.add(const Duration(minutes: 5));
      final member = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-removed',
        username: 'Removed',
        role: MemberRole.writer,
        publicKey: 'pk-removed',
        mlKemPublicKey: 'mlkem-removed',
        joinedAt: now,
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'device-1',
            transportPeerId: 'transport-1',
            deviceSigningPublicKey: 'pk-device-1',
            keyPackageId: 'kp-1',
          ),
        ],
      );

      await repo.saveMember(member);
      await repo.saveRemovedMemberSnapshot(member, removedAt: removedAt);
      await repo.removeMember('group-1', 'peer-removed');

      expect(await repo.getMember('group-1', 'peer-removed'), isNull);
      final snapshot = await repo.getRemovedMemberSnapshot(
        'group-1',
        'peer-removed',
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.publicKey, 'pk-removed');
      expect(snapshot.devices, hasLength(1));
      expect(snapshot.devices.single.deviceSigningPublicKey, 'pk-device-1');
    });
  });

  // --- Key tests ---

  group('Keys', () {
    test(
      'PREREQ-SECRET-STORAGE-WRAPPING saveKey stores group key material in secure storage and only a reference in SQL',
      () async {
        await repo.saveKey(makeKey(keyGeneration: 9));

        final rows = await db.query(
          'group_keys',
          where: 'group_id = ? AND key_generation = ?',
          whereArgs: ['group-1', 9],
        );
        final rawKey = rows.single['encrypted_key'] as String;

        expect(rawKey, isNot('base64-key-9'));
        expect(isSecureStoreReference(rawKey), isTrue);
        expect(
          rawKey,
          secureStoreReferenceForKey(groupKeyMaterialStoreName('group-1', 9)),
        );
        expect(
          await groupKeyStore.read(groupKeyMaterialStoreName('group-1', 9)),
          'base64-key-9',
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getLatestKey and getKeyByGeneration hydrate group key material',
      () async {
        await repo.saveKey(makeKey(keyGeneration: 1));
        await repo.saveKey(makeKey(keyGeneration: 2));

        final latest = await repo.getLatestKey('group-1');
        final first = await repo.getKeyByGeneration('group-1', 1);
        final rawRows = await db.query(
          'group_keys',
          where: 'group_id = ?',
          whereArgs: ['group-1'],
        );

        expect(latest, isNotNull);
        expect(latest!.keyGeneration, 2);
        expect(latest.encryptedKey, 'base64-key-2');
        expect(first, isNotNull);
        expect(first!.encryptedKey, 'base64-key-1');
        expect(
          rawRows.map((row) => row['encrypted_key'] as String),
          everyElement(startsWith(secureStoreReferencePrefix)),
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING mirrorAllKeysToSecureStore writes hydrated material, not SQL reference text',
      () async {
        await repo.saveGroup(makeGroup());
        final secureStoreKey = groupKeyMaterialStoreName('group-1', 11);
        await groupKeyStore.write(secureStoreKey, 'base64-key-11');
        await dbInsertGroupKey(db, {
          'group_id': 'group-1',
          'key_generation': 11,
          'encrypted_key': secureStoreReferenceForKey(secureStoreKey),
          'created_at': now.toIso8601String(),
        });

        await repo.mirrorAllKeysToSecureStore();

        expect(
          await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 11)),
          'base64-key-11',
        );
        expect(
          await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 11)),
          isNot(secureStoreReferenceForKey(secureStoreKey)),
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getLatestKey and getKeyByGeneration fail closed when secure material is missing',
      () async {
        await dbInsertGroupKey(db, {
          'group_id': 'group-1',
          'key_generation': 1,
          'encrypted_key': secureStoreReferenceForKey(
            groupKeyMaterialStoreName('group-1', 1),
          ),
          'created_at': now.toIso8601String(),
        });
        await dbInsertGroupKey(db, {
          'group_id': 'group-1',
          'key_generation': 2,
          'encrypted_key': secureStoreReferenceForKey(
            groupKeyMaterialStoreName('group-1', 2),
          ),
          'created_at': now.toIso8601String(),
        });

        final latest = await repo.getLatestKey('group-1');
        final first = await repo.getKeyByGeneration('group-1', 1);

        expect(latest, isNull);
        expect(first, isNull);
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING mirrorAllKeysToSecureStore skips missing secure material',
      () async {
        await repo.saveGroup(makeGroup());
        final secureStoreKey = groupKeyMaterialStoreName('group-1', 12);
        final reference = secureStoreReferenceForKey(secureStoreKey);
        await dbInsertGroupKey(db, {
          'group_id': 'group-1',
          'key_generation': 12,
          'encrypted_key': reference,
          'created_at': now.toIso8601String(),
        });

        await repo.mirrorAllKeysToSecureStore();

        expect(
          await sharedPushKeyStore.containsKey(
            sharedGroupPushKeyName('group-1', 12),
          ),
          isFalse,
        );
        expect(
          await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 12)),
          isNot(reference),
        );
      },
    );

    test('saveKey and getLatestKey round-trip', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 3));
      await repo.saveKey(makeKey(keyGeneration: 2));

      final latest = await repo.getLatestKey('group-1');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 3);
    });

    test('saveKey mirrors group key to shared push storage', () async {
      await repo.saveKey(makeKey(keyGeneration: 7));

      expect(
        await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 7)),
        'base64-key-7',
      );
    });

    test('getKeyByGeneration returns correct key', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 2));

      final key = await repo.getKeyByGeneration('group-1', 1);
      expect(key, isNotNull);
      expect(key!.keyGeneration, 1);
      expect(key.encryptedKey, 'base64-key-1');
    });

    test(
      'NW-013 pending rotation draft round-trips without becoming latest key',
      () async {
        await repo.saveKey(makeKey(keyGeneration: 1));
        await repo.savePendingKeyRotation(
          makeKey(keyGeneration: 2, encryptedKey: 'draft-key-2'),
        );

        final latest = await repo.getLatestKey('group-1');
        final pending = await repo.getPendingKeyRotation('group-1');
        final rawDrafts = await db.query('group_key_rotation_drafts');

        expect(latest, isNotNull);
        expect(latest!.keyGeneration, 1);
        expect(pending, isNotNull);
        expect(pending!.keyGeneration, 2);
        expect(pending.encryptedKey, 'draft-key-2');
        expect(await repo.getKeyByGeneration('group-1', 2), isNull);
        expect(rawDrafts.single['encrypted_key'], isA<String>());
        expect(
          isSecureStoreReference(rawDrafts.single['encrypted_key'] as String),
          isTrue,
        );

        await repo.saveKey(
          makeKey(keyGeneration: 2, encryptedKey: 'draft-key-2'),
        );
        await repo.clearPendingKeyRotation('group-1', 2);

        expect(await repo.getPendingKeyRotation('group-1'), isNull);
        final promoted = await repo.getLatestKey('group-1');
        expect(promoted, isNotNull);
        expect(promoted!.keyGeneration, 2);
        expect(promoted.encryptedKey, 'draft-key-2');
      },
    );

    test(
      'PGC-013 saveKey retains bounded offline replay key window and prunes only outside it',
      () async {
        for (var generation = 1; generation <= 9; generation++) {
          await repo.saveKey(makeKey(keyGeneration: generation));
        }

        expect(await repo.getKeyByGeneration('group-1', 1), isNull);
        expect(
          await sharedPushKeyStore.containsKey(
            sharedGroupPushKeyName('group-1', 1),
          ),
          isFalse,
        );
        expect(
          await groupKeyStore.containsKey(
            groupKeyMaterialStoreName('group-1', 1),
          ),
          isFalse,
        );

        for (var generation = 2; generation <= 9; generation++) {
          final retained = await repo.getKeyByGeneration('group-1', generation);
          expect(retained, isNotNull, reason: 'generation $generation');
          expect(retained!.encryptedKey, 'base64-key-$generation');
          expect(
            await sharedPushKeyStore.read(
              sharedGroupPushKeyName('group-1', generation),
            ),
            'base64-key-$generation',
            reason: 'shared push mirror generation $generation',
          );
          expect(
            await groupKeyStore.read(
              groupKeyMaterialStoreName('group-1', generation),
            ),
            'base64-key-$generation',
            reason: 'secure material generation $generation',
          );
        }
      },
    );

    test('removeAllKeys clears all keys for group', () async {
      await repo.saveKey(makeKey(keyGeneration: 1));
      await repo.saveKey(makeKey(keyGeneration: 2));

      await repo.removeAllKeys('group-1');

      final latest = await repo.getLatestKey('group-1');
      expect(latest, isNull);
      expect(
        await sharedPushKeyStore.containsKey(
          sharedGroupPushKeyName('group-1', 1),
        ),
        isFalse,
      );
      expect(
        await sharedPushKeyStore.containsKey(
          sharedGroupPushKeyName('group-1', 2),
        ),
        isFalse,
      );
    });

    test(
      'mirrorAllKeysToSecureStore mirrors existing persisted keys',
      () async {
        await repo.saveGroup(makeGroup());
        await dbInsertGroupKey(db, makeKey(keyGeneration: 4).toMap());
        await dbInsertGroupKey(db, makeKey(keyGeneration: 5).toMap());

        await repo.mirrorAllKeysToSecureStore();

        expect(
          await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 4)),
          'base64-key-4',
        );
        expect(
          await sharedPushKeyStore.read(sharedGroupPushKeyName('group-1', 5)),
          'base64-key-5',
        );
      },
    );
  });
}
