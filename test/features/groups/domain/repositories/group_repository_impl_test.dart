import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/linked_group_bootstrap_db_helpers.dart';
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
import 'package:flutter_app/core/database/migrations/083_groups_last_membership_event_id.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/linked_group_bootstrap_repository.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';

/// 164 (cold-start-3): a [FakeSecureKeyStore] that counts write/delete/
/// containsKey/read calls so the presence-diff (zero redundant writes on an
/// already-populated projection) is directly observable.
class _CountingSecureKeyStore extends FakeSecureKeyStore {
  int writeCount = 0;
  int deleteCount = 0;
  int containsKeyCount = 0;
  int readCount = 0;

  @override
  Future<void> write(String key, String value) {
    writeCount++;
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    deleteCount++;
    return super.delete(key);
  }

  @override
  Future<bool> containsKey(String key) {
    containsKeyCount++;
    return super.containsKey(key);
  }

  @override
  Future<String?> read(String key) {
    readCount++;
    return super.read(key);
  }
}

class _OrderedSecureKeyStore extends FakeSecureKeyStore {
  _OrderedSecureKeyStore(this.label, this.order);

  final String label;
  final List<String> order;
  String? failDeleteContaining;

  @override
  Future<void> delete(String key) async {
    order.add('$label:$key');
    if (failDeleteContaining != null && key.contains(failDeleteContaining!)) {
      throw StateError('$label delete failed');
    }
    await super.delete(key);
  }
}

class _InspectingAcceptedWriteStore extends FakeSecureKeyStore {
  Future<void> Function(String key, String value)? onAcceptedWrite;
  int acceptedWriteCount = 0;

  @override
  Future<void> write(String key, String value) async {
    if (key.contains(':accepted:')) {
      acceptedWriteCount++;
      await onAcceptedWrite?.call(key, value);
    }
    await super.write(key, value);
  }
}

class _BlockingWriteSecureKeyStore extends FakeSecureKeyStore {
  _BlockingWriteSecureKeyStore(this.blockedKey);

  final String blockedKey;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool _hasBlocked = false;

  @override
  Future<void> write(String key, String value) async {
    if (!_hasBlocked && key == blockedKey) {
      _hasBlocked = true;
      entered.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

class _RecordingProjection extends GroupReactionNotificationProjection {
  _RecordingProjection(this.order) : super(store: FakeSecureKeyStore());

  final List<String> order;
  bool failStrictRemoval = false;
  bool failAcceptedReplacement = false;
  bool failCompensatingStrictRemoval = false;
  bool acceptedContextPublished = false;

  @override
  Future<void> removeGroupStrict(String groupId) async {
    order.add('projection:$groupId');
    if (failStrictRemoval) throw StateError('projection failed');
    acceptedContextPublished = false;
  }

  @override
  Future<void> replaceAcceptedGroupContextStrict({
    required GroupModel group,
    required Iterable<GroupMember> members,
    required GroupKeyInfo key,
  }) async {
    order.add('projection:accepted:${group.id}');
    // The strict replacement boundary may fail after partially publishing.
    acceptedContextPublished = true;
    if (failAcceptedReplacement) {
      if (failCompensatingStrictRemoval) failStrictRemoval = true;
      throw StateError('accepted projection failed');
    }
  }
}

void main() {
  late Database db;
  late GroupRepositoryImpl repo;
  late FakeSecureKeyStore groupKeyStore;
  late FakeSecureKeyStore sharedPushKeyStore;

  // 164: extracted so a test can inject a counting push store (the produced
  // repo is byte-identical to the original setUp construction otherwise).
  GroupRepositoryImpl makeRepo(
    FakeSecureKeyStore? pushStore, {
    GroupReactionNotificationProjection? projection,
    bool selfRemovedShellAuthorityEnabled = false,
    void Function()? beforeSelfRemovedReferenceFinalize,
    Future<List<Map<String, Object?>>> Function()? loadAllGroupsOverride,
    Future<bool> Function(String groupId)? hasExitCleanupPending,
    Future<void> Function(Map<String, Object?> row)?
    commitDissolvedGroupOverride,
    Future<LinkedGroupBootstrapMaterializationDbDisposition> Function({
      required Map<String, Object?> groupRow,
      required List<Map<String, Object?>> memberRows,
      required Map<String, Object?> keyRow,
      required String authorityGenesisSourcePeerId,
      required String authorityGenesisSourceEventId,
      required String authorityGenesisSourceTimestamp,
      required Map<String, Object?> authorityGenesisPayload,
    })?
    commitLinkedBootstrapMaterializationOverride,
  }) {
    return GroupRepositoryImpl(
      dbInsertGroup: (row) => dbInsertGroup(db, row),
      dbLoadAllGroups: loadAllGroupsOverride ?? () => dbLoadAllGroups(db),
      dbLoadGroup: (id) => dbLoadGroup(db, id),
      dbUpdateGroup: (row) => dbUpdateGroup(db, row),
      dbCommitDissolvedGroup:
          commitDissolvedGroupOverride ??
          (row) =>
              dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(db, row),
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
      dbCommitLinkedGroupBootstrapMaterializationFn:
          commitLinkedBootstrapMaterializationOverride ??
          ({
            required groupRow,
            required memberRows,
            required keyRow,
            required authorityGenesisSourcePeerId,
            required authorityGenesisSourceEventId,
            required authorityGenesisSourceTimestamp,
            required authorityGenesisPayload,
          }) => dbCommitLinkedGroupBootstrapMaterialization(
            db,
            groupRow: groupRow,
            memberRows: memberRows,
            keyRow: keyRow,
            authorityGenesisSourcePeerId: authorityGenesisSourcePeerId,
            authorityGenesisSourceEventId: authorityGenesisSourceEventId,
            authorityGenesisSourceTimestamp: authorityGenesisSourceTimestamp,
            authorityGenesisPayload: authorityGenesisPayload,
          ),
      pushSharedKeyStore: pushStore,
      groupReactionProjection: projection,
      dbHasGroupExitCleanupPending: hasExitCleanupPending,
      selfRemovedShellAuthorityEnabled: selfRemovedShellAuthorityEnabled,
      dbLoadSelfRemovedGroupShellAuthority:
          ({required groupId, required selfPeerId}) =>
              dbLoadSelfRemovedGroupShellAuthoritySnapshot(
                db,
                groupId: groupId,
                selfPeerId: selfPeerId,
              ),
      dbCommitSelfRemovalAuthorityFn:
          ({required expected, required removalAt, required removalEventId}) =>
              dbCommitSelfRemovalAuthority(
                db,
                expected: expected,
                removalAt: removalAt,
                removalEventId: removalEventId,
              ),
      dbLoadRawSelfRemovedGroupKeyReferencesFn: ({required expected}) =>
          dbLoadRawSelfRemovedGroupKeyReferences(db, expected: expected),
      dbFinalizeSelfRemovedGroupKeyReferencesFn:
          ({required expected, required expectedReferences}) async {
            beforeSelfRemovedReferenceFinalize?.call();
            return dbFinalizeSelfRemovedGroupKeyReferences(
              db,
              expected: expected,
              expectedReferences: expectedReferences,
            );
          },
      dbLoadSelfRemovedGroupMediaParentsFn:
          ({required expected, required limit}) =>
              dbLoadSelfRemovedGroupMediaParents(
                db,
                expected: expected,
                limit: limit,
              ),
      dbAppendSelfRemovedGroupFreshnessFloorFn: ({required expected}) =>
          dbAppendSelfRemovedGroupFreshnessFloor(db, expected: expected),
      dbLoadSelfRemovedGroupFreshnessFloorFn: (groupId) =>
          dbLoadLatestSelfRemovedGroupFreshnessFloor(db, groupId),
      dbPrepareSelfRemovedGroupAcceptedReentryFn:
          ({
            required groupRow,
            required rosterRows,
            required stagedKeyRow,
            required selfPeerId,
            required authorizationId,
            required signedMembershipWatermark,
            required signedIssuedAt,
            required bindingNonce,
          }) => dbPrepareSelfRemovedGroupAcceptedReentry(
            db,
            groupRow: groupRow,
            rosterRows: rosterRows,
            stagedKeyRow: stagedKeyRow,
            selfPeerId: selfPeerId,
            authorizationId: authorizationId,
            signedMembershipWatermark: signedMembershipWatermark,
            signedIssuedAt: signedIssuedAt,
            bindingNonce: bindingNonce,
          ),
      dbStageSelfRemovedGroupAcceptedReentryKeyFn:
          ({required preparation, required stagedKeyRow}) =>
              dbStageSelfRemovedGroupAcceptedReentryKey(
                db,
                preparation: preparation,
                stagedKeyRow: stagedKeyRow,
              ),
      dbCommitSelfRemovedGroupAcceptedReentryFn:
          ({
            required preparation,
            required groupRow,
            required rosterRows,
            required stagedKeyRow,
            required selfPeerId,
            required authorizationId,
            required signedMembershipWatermark,
            required signedIssuedAt,
            required bindingNonce,
          }) => dbCommitSelfRemovedGroupAcceptedReentry(
            db,
            preparation: preparation,
            groupRow: groupRow,
            rosterRows: rosterRows,
            stagedKeyRow: stagedKeyRow,
            selfPeerId: selfPeerId,
            authorizationId: authorizationId,
            signedMembershipWatermark: signedMembershipWatermark,
            signedIssuedAt: signedIssuedAt,
            bindingNonce: bindingNonce,
          ),
      dbFinalizeSelfRemovedGroupAcceptedReentryStagingFn:
          ({required preparation, required stagedKeyRow}) =>
              dbFinalizeSelfRemovedGroupAcceptedReentryStaging(
                db,
                preparation: preparation,
                stagedKeyRow: stagedKeyRow,
              ),
      dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn:
          ({required groupId, required selfPeerId, required binding}) =>
              dbFinalizeSelfRemovedGroupAcceptedRollbackKey(
                db,
                groupId: groupId,
                selfPeerId: selfPeerId,
                binding: binding,
              ),
      dbRollbackSelfRemovedGroupAcceptedReentryFn:
          ({
            required groupId,
            required selfPeerId,
            required authorizationId,
            required qualification,
          }) => dbRollbackSelfRemovedGroupAcceptedReentry(
            db,
            groupId: groupId,
            selfPeerId: selfPeerId,
            authorizationId: authorizationId,
            qualification: qualification,
          ),
      dbQualifySelfRemovedGroupAcceptedRollbackFn:
          ({required groupId, required selfPeerId, required authorizationId}) =>
              dbQualifySelfRemovedGroupAcceptedRollback(
                db,
                groupId: groupId,
                selfPeerId: selfPeerId,
                authorizationId: authorizationId,
              ),
      dbPrepareFreshAcceptedMaterializationRollbackFn:
          ({
            required groupId,
            required selfPeerId,
            required keyGeneration,
            required expectedMembershipAt,
            required expectedMetadataAt,
          }) => dbPrepareFreshAcceptedMaterializationRollback(
            db,
            groupId: groupId,
            selfPeerId: selfPeerId,
            keyGeneration: keyGeneration,
            expectedMembershipAt: expectedMembershipAt,
            expectedMetadataAt: expectedMetadataAt,
          ),
      dbCommitFreshAcceptedMaterializationRollbackFn:
          ({required preparation}) =>
              dbCommitFreshAcceptedMaterializationRollback(
                db,
                preparation: preparation,
              ),
      dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn:
          ({
            required groupId,
            required selfPeerId,
            required authorizationId,
            required signedMembershipWatermark,
            required signedIssuedAt,
            required keyGeneration,
          }) => dbAuthorizeSelfRemovedGroupAcceptedReentryRetry(
            db,
            groupId: groupId,
            selfPeerId: selfPeerId,
            authorizationId: authorizationId,
            signedMembershipWatermark: signedMembershipWatermark,
            signedIssuedAt: signedIssuedAt,
            keyGeneration: keyGeneration,
          ),
      dbPurgeSelfRemovedGroupShellFn:
          ({required expected, required floor, required deletedAt}) =>
              dbPurgeSelfRemovedGroupShell(
                db,
                expected: expected,
                floor: floor,
                deletedAt: deletedAt,
              ),
    );
  }

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
    await runGroupsLastMembershipEventIdMigration(db);
    groupKeyStore = FakeSecureKeyStore();
    sharedPushKeyStore = FakeSecureKeyStore();

    repo = makeRepo(sharedPushKeyStore);
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

  Future<GroupModel> resetToMarkedV102({String groupId = 'group-1'}) async {
    await db.close();
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, 102);
    final marker = DateTime.utc(2026, 7, 20, 12);
    final group = makeGroup(id: groupId).copyWith(
      selfRemovedAt: marker,
      lastMembershipEventAt: marker,
      lastMembershipEventId: 'remove-1',
    );
    await dbInsertGroup(db, group.toMap());
    return group;
  }

  Future<GroupModel> resetToActiveV102({
    String groupId = 'group-1',
    bool isMuted = false,
  }) async {
    await db.close();
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, 102);
    final group = makeGroup(id: groupId).copyWith(isMuted: isMuted);
    await dbInsertGroup(db, group.toMap());
    await dbInsertGroupMember(
      db,
      makeMember(groupId: groupId, peerId: 'peer-self').toMap(),
    );
    return group;
  }

  // --- Group tests ---

  group('Groups', () {
    test(
      'TC-363-01b protected self bootstrap commits atomically before exact relay ACK',
      () async {
        await db.close();
        db = await openDatabase(inMemoryDatabasePath, version: 1);
        await runProductionOnCreate(db, currentIdentityDatabaseVersion);
        groupKeyStore = FakeSecureKeyStore();
        final bootstrapRepo = makeRepo(FakeSecureKeyStore());
        final capability = bootstrapRepo as LinkedGroupBootstrapRepository;
        final group = makeGroup(
          id: 'linked-bootstrap-group',
        ).copyWith(myRole: GroupRole.admin);
        final self = makeMember(
          groupId: group.id,
          peerId: 'account-self',
          role: MemberRole.admin,
        );
        final witness = makeMember(
          groupId: group.id,
          peerId: 'peer-witness',
          role: MemberRole.writer,
        );
        final key = makeKey(groupId: group.id, encryptedKey: 'raw-group-key');
        const genesis = LinkedGroupBootstrapAuthorityGenesis(
          sourcePeerId: 'account-self',
          sourceEventId: 'pga1:g:bootstrap-one',
          sourceTimestamp: '2026-08-13T10:00:00.000000Z',
          payload: <String, Object?>{
            'proof': <String, Object?>{
              'signature': 'authenticated-bootstrap-signature',
              'keyMaterialHash': 'safe-key-material-hash',
            },
          },
        );

        expect(
          await capability.commitLinkedGroupBootstrapMaterialization(
            bootstrapId: 'bootstrap-one',
            group: group,
            members: <GroupMember>[self, witness],
            key: key,
            authorityGenesis: genesis,
          ),
          LinkedGroupBootstrapMaterializationOutcome.committed,
        );
        expect(
          (await bootstrapRepo.getGroup(group.id))?.myRole,
          GroupRole.admin,
        );
        expect(await bootstrapRepo.getMembers(group.id), hasLength(2));
        expect(
          (await bootstrapRepo.getLatestKey(group.id))?.encryptedKey,
          'raw-group-key',
        );
        final keyRow = (await db.query(
          'group_keys',
          where: 'group_id = ?',
          whereArgs: <Object?>[group.id],
        )).single;
        final storeName = groupLinkedBootstrapKeyMaterialStoreName(
          group.id,
          1,
          'bootstrap-one',
        );
        expect(keyRow['encrypted_key'], secureStoreReferenceForKey(storeName));
        expect(await groupKeyStore.read(storeName), 'raw-group-key');
        final genesisRows = await db.query(
          'group_event_log',
          where: 'group_id = ? AND event_type = ?',
          whereArgs: <Object?>[group.id, 'protected_authority_genesis'],
        );
        expect(genesisRows, hasLength(1));
        expect(
          genesisRows.single['canonical_payload'],
          allOf(
            contains('authenticated-bootstrap-signature'),
            isNot(contains('raw-group-key')),
          ),
        );

        expect(
          await capability.commitLinkedGroupBootstrapMaterialization(
            bootstrapId: 'bootstrap-one',
            group: group,
            members: <GroupMember>[self, witness],
            key: key,
            authorityGenesis: genesis,
          ),
          LinkedGroupBootstrapMaterializationOutcome.duplicate,
        );
        expect(
          await capability.commitLinkedGroupBootstrapMaterialization(
            bootstrapId: 'bootstrap-one',
            group: group.copyWith(myRole: GroupRole.member),
            members: <GroupMember>[self, witness],
            key: key,
            authorityGenesis: genesis,
          ),
          LinkedGroupBootstrapMaterializationOutcome.refusedConflict,
          reason:
              'a replay can never hard-code or demote the signed admin role',
        );

        final pendingDevice = PendingSiblingDevice(
          groupId: group.id,
          memberPeerId: self.peerId,
          deviceId: 'linked-device',
          transportPeerId: 'linked-transport',
          deviceSigningPublicKey: 'linked-signing-key',
          mlKemPublicKey: 'linked-mlkem',
          keyPackageId: 'linked-key-package',
          verifiedAccountSigningPublicKey: 'account-signing-key',
          announcedAt: now,
        );
        final pendingBroadcast = GroupPendingBroadcast(
          id: 'linked-bootstrap:bootstrap-one',
          groupId: group.id,
          kind: groupPendingBroadcastKindLinkedBootstrap,
          sysText: '{"protected":"exact"}',
          recipientPeerIds: const <String>['linked-transport'],
          eventAt: now,
          sourceMessageId: 'bootstrap-one',
          createdAt: now,
          updatedAt: now,
        );
        await db.insert('pending_sibling_devices', pendingDevice.toMap());
        await db.insert('pending_group_broadcasts', pendingBroadcast.toMap());
        await db.update(
          'pending_group_broadcasts',
          <String, Object?>{
            'updated_at': now.add(const Duration(seconds: 1)).toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: <Object?>[pendingBroadcast.id],
        );
        expect(
          await dbCompleteLinkedGroupBootstrapCustody(
            db,
            expectedDevice: pendingDevice.toMap(),
            expectedBroadcast: pendingBroadcast.toMap(),
          ),
          isFalse,
          reason: 'an inexact paired owner cannot trigger a partial delete',
        );
        expect(await db.query('pending_sibling_devices'), hasLength(1));
        expect(await db.query('pending_group_broadcasts'), hasLength(1));

        await db.update(
          'pending_group_broadcasts',
          pendingBroadcast.toMap(),
          where: 'id = ?',
          whereArgs: <Object?>[pendingBroadcast.id],
        );
        expect(
          await dbCompleteLinkedGroupBootstrapCustody(
            db,
            expectedDevice: pendingDevice.toMap(),
            expectedBroadcast: pendingBroadcast.toMap(),
          ),
          isTrue,
        );
        expect(await db.query('pending_sibling_devices'), isEmpty);
        expect(await db.query('pending_group_broadcasts'), isEmpty);

        final refusedStore = FakeSecureKeyStore();
        groupKeyStore = refusedStore;
        final refusingRepo = makeRepo(
          FakeSecureKeyStore(),
          commitLinkedBootstrapMaterializationOverride:
              ({
                required groupRow,
                required memberRows,
                required keyRow,
                required authorityGenesisSourcePeerId,
                required authorityGenesisSourceEventId,
                required authorityGenesisSourceTimestamp,
                required authorityGenesisPayload,
              }) async => LinkedGroupBootstrapMaterializationDbDisposition
                  .refusedConflict,
        );
        final secondGroup = makeGroup(id: 'refused-bootstrap');
        final secondKey = makeKey(
          groupId: secondGroup.id,
          encryptedKey: 'must-be-purged',
        );
        expect(
          await (refusingRepo as LinkedGroupBootstrapRepository)
              .commitLinkedGroupBootstrapMaterialization(
                bootstrapId: 'bootstrap-refused',
                group: secondGroup,
                members: <GroupMember>[
                  makeMember(groupId: secondGroup.id, peerId: 'account-self'),
                ],
                key: secondKey,
                authorityGenesis: const LinkedGroupBootstrapAuthorityGenesis(
                  sourcePeerId: 'account-self',
                  sourceEventId: 'pga1:g:bootstrap-refused',
                  sourceTimestamp: '2026-08-13T10:01:00.000000Z',
                  payload: <String, Object?>{'proof': 'refused-proof'},
                ),
              ),
          LinkedGroupBootstrapMaterializationOutcome.refusedConflict,
        );
        expect(
          await refusedStore.containsKey(
            groupLinkedBootstrapKeyMaterialStoreName(
              secondGroup.id,
              1,
              'bootstrap-refused',
            ),
          ),
          isFalse,
          reason: 'SQL refusal purges deterministic pre-commit key staging',
        );
        expect(
          await db.query(
            'groups',
            where: 'id = ?',
            whereArgs: <Object?>[secondGroup.id],
          ),
          isEmpty,
        );
      },
    );

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

    test(
      'commitDissolvedGroup routes through the terminal DB capability',
      () async {
        await repo.saveGroup(makeGroup());

        await repo.commitDissolvedGroup(
          makeGroup().copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 8, 3, 8),
            dissolvedBy: 'peer-admin',
          ),
        );

        final result = await repo.getGroup('group-1');
        expect(result, isNotNull);
        expect(result!.isDissolved, isTrue);
        expect(result.dissolvedBy, 'peer-admin');
      },
    );

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
      'PB264-12 exact exit keeps SQL retry addresses until strict external cleanup and finalizes last',
      () async {
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        final projection = _RecordingProjection(order);
        groupKeyStore = primary;
        repo = makeRepo(mirror, projection: projection);

        await repo.saveGroup(makeGroup());
        await repo.saveMember(makeMember(peerId: 'peer-self'));
        await repo.saveKey(makeKey(keyGeneration: 1));
        await repo.savePendingKeyRotation(makeKey(keyGeneration: 2));
        await mirror.write(sharedGroupMutedKeyName('group-1'), '1');
        order.clear();

        final cleanup = repo as GroupExitCleanupRepository;
        var finalSqlCalls = 0;
        mirror.failDeleteContaining = sharedGroupPushKeyName('group-1', 1);
        await expectLater(
          cleanup.cleanupExactVoluntaryExit<void>(
            groupId: 'group-1',
            selfPeerId: 'peer-self',
            selfJoinedAt: now,
            finalizeSql: () async {
              finalSqlCalls++;
              order.add('sql');
            },
          ),
          throwsStateError,
        );

        expect(finalSqlCalls, 0);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));
        expect(await dbLoadPendingGroupKeyRotation(db, 'group-1'), isNotNull);
        expect(await dbLoadGroup(db, 'group-1'), isNotNull);
        expect(
          order,
          containsAllInOrder(<String>[
            'projection:group-1',
            'primary:${groupKeyMaterialStoreName('group-1', 1)}',
            'primary:${groupKeyMaterialStoreName('group-1', 2)}',
            'mirror:${sharedGroupPushKeyName('group-1', 1)}',
          ]),
        );

        order.clear();
        mirror.failDeleteContaining = null;
        await expectLater(
          cleanup.cleanupExactVoluntaryExit<void>(
            groupId: 'group-1',
            selfPeerId: 'peer-self',
            selfJoinedAt: now,
            finalizeSql: () async {
              finalSqlCalls++;
              order.add('sql');
              throw StateError('injected final SQL failure');
            },
          ),
          throwsStateError,
        );
        expect(finalSqlCalls, 1);
        expect(order.last, 'sql');
        expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));
        expect(await dbLoadPendingGroupKeyRotation(db, 'group-1'), isNotNull);
        expect(await dbLoadGroup(db, 'group-1'), isNotNull);
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 1)),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupMutedKeyName('group-1')),
          isFalse,
        );

        order.clear();
        await cleanup.cleanupExactVoluntaryExit<void>(
          groupId: 'group-1',
          selfPeerId: 'peer-self',
          selfJoinedAt: now,
          finalizeSql: () async {
            finalSqlCalls++;
            expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));
            expect(
              await dbLoadPendingGroupKeyRotation(db, 'group-1'),
              isNotNull,
            );
            order.add('sql');
            await dbDeleteAllGroupKeys(db, 'group-1');
            await dbDeletePendingGroupKeyRotations(db, 'group-1');
            await dbDeleteAllGroupMembers(db, 'group-1');
            await dbDeleteGroup(db, 'group-1');
          },
        );

        expect(finalSqlCalls, 2);
        expect(order.last, 'sql');
        expect(await dbLoadGroup(db, 'group-1'), isNull);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), isEmpty);
        expect(await dbLoadPendingGroupKeyRotation(db, 'group-1'), isNull);
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 1)),
          isFalse,
        );
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 2)),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupPushKeyName('group-1', 1)),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupMutedKeyName('group-1')),
          isFalse,
        );
      },
    );

    test(
      'PB264-12 non-iOS cleanup treats absent shared notification stores as unconfigured',
      () async {
        repo = makeRepo(null);
        await repo.saveGroup(makeGroup());
        await repo.saveMember(makeMember(peerId: 'peer-self'));
        await repo.saveKey(makeKey(keyGeneration: 1));
        await repo.savePendingKeyRotation(makeKey(keyGeneration: 2));

        final primaryGenerationOne = groupKeyMaterialStoreName('group-1', 1);
        final primaryGenerationTwo = groupKeyMaterialStoreName('group-1', 2);
        expect(await groupKeyStore.containsKey(primaryGenerationOne), isTrue);
        expect(await groupKeyStore.containsKey(primaryGenerationTwo), isTrue);

        await (repo as GroupExitCleanupRepository)
            .cleanupExactVoluntaryExit<void>(
              groupId: 'group-1',
              selfPeerId: 'peer-self',
              selfJoinedAt: now,
              finalizeSql: () async {
                await dbDeleteAllGroupKeys(db, 'group-1');
                await dbDeletePendingGroupKeyRotations(db, 'group-1');
                await dbDeleteAllGroupMembers(db, 'group-1');
                await dbDeleteGroup(db, 'group-1');
              },
            );

        expect(await groupKeyStore.containsKey(primaryGenerationOne), isFalse);
        expect(await groupKeyStore.containsKey(primaryGenerationTwo), isFalse);
        expect(await dbLoadGroup(db, 'group-1'), isNull);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), isEmpty);
        expect(await dbLoadPendingGroupKeyRotation(db, 'group-1'), isNull);
      },
    );

    test(
      'PB264-12 newer same-ID membership refuses external exit cleanup',
      () async {
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        repo = makeRepo(mirror, projection: _RecordingProjection(order));
        final newerJoinedAt = now.add(const Duration(days: 1));

        await repo.saveGroup(makeGroup());
        await repo.saveMember(
          makeMember(peerId: 'peer-self').copyWith(joinedAt: newerJoinedAt),
        );
        await repo.saveKey(makeKey(keyGeneration: 1));
        order.clear();
        var finalSqlCalled = false;

        await expectLater(
          (repo as GroupExitCleanupRepository).cleanupExactVoluntaryExit<void>(
            groupId: 'group-1',
            selfPeerId: 'peer-self',
            selfJoinedAt: now,
            finalizeSql: () async => finalSqlCalled = true,
          ),
          throwsStateError,
        );

        expect(order, isEmpty);
        expect(finalSqlCalled, isFalse);
        expect(await dbLoadGroup(db, 'group-1'), isNotNull);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 1)),
          isTrue,
        );
        expect(
          await mirror.containsKey(sharedGroupPushKeyName('group-1', 1)),
          isTrue,
        );
      },
    );

    test(
      'PB264-12 final SQL stays inside the group mutation lock and rejects queued key writers',
      () async {
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        repo = makeRepo(
          mirror,
          projection: _RecordingProjection(order),
          selfRemovedShellAuthorityEnabled: true,
        );
        await repo.saveGroup(makeGroup());
        await repo.saveMember(makeMember(peerId: 'peer-self'));
        await repo.saveKey(makeKey(keyGeneration: 1));
        order.clear();

        final finalSqlEntered = Completer<void>();
        final releaseFinalSql = Completer<void>();
        final cleanupFuture = (repo as GroupExitCleanupRepository)
            .cleanupExactVoluntaryExit<void>(
              groupId: 'group-1',
              selfPeerId: 'peer-self',
              selfJoinedAt: now,
              finalizeSql: () async {
                order.add('sql-entered');
                finalSqlEntered.complete();
                await releaseFinalSql.future;
                await dbDeleteAllGroupKeys(db, 'group-1');
                await dbDeletePendingGroupKeyRotations(db, 'group-1');
                await dbDeleteAllGroupMembers(db, 'group-1');
                await dbDeleteGroup(db, 'group-1');
                order.add('sql-committed');
              },
            );
        await finalSqlEntered.future;

        final queuedKeyWrite = expectLater(
          repo.saveKey(makeKey(keyGeneration: 2)),
          throwsStateError,
        );
        final queuedDraftWrite = expectLater(
          repo.savePendingKeyRotation(makeKey(keyGeneration: 3)),
          throwsStateError,
        );
        await Future<void>.delayed(Duration.zero);
        expect(await dbLoadGroupKeyByGeneration(db, 'group-1', 2), isNull);
        expect(await dbLoadPendingGroupKeyRotation(db, 'group-1'), isNull);

        releaseFinalSql.complete();
        await cleanupFuture;
        await queuedKeyWrite;
        await queuedDraftWrite;

        expect(
          order,
          containsAllInOrder(<String>['sql-entered', 'sql-committed']),
        );
        expect(await dbLoadGroup(db, 'group-1'), isNull);
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 2)),
          isFalse,
        );
        expect(
          await primary.containsKey(groupKeyMaterialStoreName('group-1', 3)),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupPushKeyName('group-1', 2)),
          isFalse,
        );
      },
    );

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

    // 04-P0 SI-1 NSE — the app mirrors group mute into the shared Keychain so
    // the out-of-process iOS NSE can honor it.
    test(
      'updateGroup mirrors the mute projection; unmuting deletes it',
      () async {
        await repo.saveGroup(makeGroup());

        await repo.updateGroup(makeGroup().copyWith(isMuted: true));
        expect(
          await sharedPushKeyStore.read(sharedGroupMutedKeyName('group-1')),
          '1',
        );

        await repo.updateGroup(makeGroup().copyWith(isMuted: false));
        expect(
          await sharedPushKeyStore.read(sharedGroupMutedKeyName('group-1')),
          isNull,
        );
      },
    );

    test(
      'mirrorAllMutedGroups backfills a DB-muted group whose projection is missing',
      () async {
        // Recreate the pre-feature state: muted in the DB, mirror absent.
        await repo.saveGroup(makeGroup());
        await repo.updateGroup(makeGroup().copyWith(isMuted: true));
        expect((await repo.getGroup('group-1'))!.isMuted, isTrue);
        await sharedPushKeyStore.delete(sharedGroupMutedKeyName('group-1'));
        expect(
          await sharedPushKeyStore.read(sharedGroupMutedKeyName('group-1')),
          isNull,
        );

        await repo.mirrorAllMutedGroups();

        expect(
          await sharedPushKeyStore.read(sharedGroupMutedKeyName('group-1')),
          '1',
        );
      },
    );

    test(
      'PB264-12 restart backfill cannot resurrect cleanup-pending iOS authority',
      () async {
        final sharedStore = FakeSecureKeyStore();
        final firstProjection = GroupReactionNotificationProjection(
          store: sharedStore,
        );
        await firstProjection.replaceLocalIdentity(
          accountPeerId: 'peer-self',
          deviceId: 'device-1',
          transportPeerId: 'transport-1',
        );
        final firstProcess = makeRepo(sharedStore, projection: firstProjection);
        await firstProcess.saveGroup(makeGroup().copyWith(isMuted: true));
        await firstProcess.saveMember(makeMember(peerId: 'peer-self'));
        await firstProcess.saveKey(makeKey(keyGeneration: 1));
        await firstProcess.updateGroup(makeGroup().copyWith(isMuted: true));

        final pushKey = sharedGroupPushKeyName('group-1', 1);
        final muteKey = sharedGroupMutedKeyName('group-1');
        expect(await sharedStore.containsKey(pushKey), isTrue);
        expect(await sharedStore.containsKey(muteKey), isTrue);
        expect(
          await sharedStore.read(sharedGroupReactionContextsKey),
          contains('group-1'),
        );

        // Model a cleanup attempt that removed all external addresses but
        // faulted before final SQL, leaving those SQL rows as retry authority.
        await firstProjection.removeGroupStrict('group-1');
        await sharedStore.delete(pushKey);
        await sharedStore.delete(muteKey);
        expect(await dbLoadGroup(db, 'group-1'), isNotNull);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));

        // A new process has an empty in-memory terminal set. Durable
        // cleanup_pending must still prevent every launch-time self-heal from
        // recreating the deleted key, mute, or reaction projection.
        final restartedProjection = GroupReactionNotificationProjection(
          store: sharedStore,
        );
        await restartedProjection.replaceLocalIdentity(
          accountPeerId: 'peer-self',
          deviceId: 'device-1',
          transportPeerId: 'transport-1',
        );
        final restarted = makeRepo(
          sharedStore,
          projection: restartedProjection,
          hasExitCleanupPending: (_) async => true,
        );
        await restarted.mirrorAllKeysToSecureStore();
        await restarted.mirrorAllMutedGroups();
        await restarted.mirrorAllGroupReactionNotificationContexts();

        expect(await sharedStore.containsKey(pushKey), isFalse);
        expect(await sharedStore.containsKey(muteKey), isFalse);
        expect(
          await sharedStore.read(sharedGroupReactionContextsKey),
          isNot(contains('group-1')),
        );
        expect(await dbLoadGroup(db, 'group-1'), isNotNull);
        expect(await dbLoadAllGroupKeys(db, 'group-1'), hasLength(1));
      },
    );

    test('mirrorAllMutedGroups does not mirror an unmuted group', () async {
      await repo.saveGroup(makeGroup());

      await repo.mirrorAllMutedGroups();

      expect(
        await sharedPushKeyStore.read(sharedGroupMutedKeyName('group-1')),
        isNull,
      );
    });

    test(
      'TC-164-04 cold key mirror writes each key once; a second mirror with the '
      'projection already populated writes ZERO keys (presence-diff)',
      () async {
        final counting = _CountingSecureKeyStore();
        final countingRepo = makeRepo(counting);

        await repo.saveGroup(makeGroup());
        await dbInsertGroupKey(db, makeKey(keyGeneration: 4).toMap());
        await dbInsertGroupKey(db, makeKey(keyGeneration: 5).toMap());

        // First mirror: both generations written exactly once.
        await countingRepo.mirrorAllKeysToSecureStore();
        expect(counting.writeCount, 2);
        expect(
          await counting.read(sharedGroupPushKeyName('group-1', 4)),
          'base64-key-4',
        );
        expect(
          await counting.read(sharedGroupPushKeyName('group-1', 5)),
          'base64-key-5',
        );

        // Second mirror on an already-populated projection: ZERO redundant
        // writes; entries still present (completeness preserved).
        counting.writeCount = 0;
        await countingRepo.mirrorAllKeysToSecureStore();
        expect(counting.writeCount, 0);
        expect(
          await counting.containsKey(sharedGroupPushKeyName('group-1', 4)),
          isTrue,
        );
        expect(
          await counting.containsKey(sharedGroupPushKeyName('group-1', 5)),
          isTrue,
        );

        // A newly-added key generation still mirrors exactly once — proves it is
        // a per-key presence-diff, NOT a global one-shot sentinel that would
        // silently drop new keys (and break NSE preview decrypt).
        await dbInsertGroupKey(db, makeKey(keyGeneration: 6).toMap());
        counting.writeCount = 0;
        await countingRepo.mirrorAllKeysToSecureStore();
        expect(counting.writeCount, 1);
        expect(
          await counting.read(sharedGroupPushKeyName('group-1', 6)),
          'base64-key-6',
        );
        expect(
          await counting.containsKey(sharedGroupPushKeyName('group-1', 4)),
          isTrue,
        );
      },
    );

    test('TC-164-05 cold mute-mirror backfills missing/changed projections but '
        'writes ZERO when already correct (presence/value-diff)', () async {
      final counting = _CountingSecureKeyStore();
      final countingRepo = makeRepo(counting);

      // group-1 muted (set directly in the DB so the counting store is not
      // pre-populated by a repo.updateGroup mirror); group-2 unmuted.
      await repo.saveGroup(makeGroup());
      await db.update(
        'groups',
        {'is_muted': 1},
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      await repo.saveGroup(makeGroup(id: 'group-2', topicName: '/t/2'));

      // First mirror: exactly one write (the muted group); the unmuted group's
      // projection is already absent → no redundant delete.
      await countingRepo.mirrorAllMutedGroups();
      expect(counting.writeCount, 1);
      expect(counting.deleteCount, 0);
      expect(await counting.read(sharedGroupMutedKeyName('group-1')), '1');

      // Second mirror, both projections already correct: ZERO writes/deletes.
      counting.writeCount = 0;
      counting.deleteCount = 0;
      await countingRepo.mirrorAllMutedGroups();
      expect(counting.writeCount, 0);
      expect(counting.deleteCount, 0);
      expect(await counting.read(sharedGroupMutedKeyName('group-1')), '1');

      // Unmute group-1 in the DB (again directly, leaving the stale '1'
      // projection in place) → the next mirror self-heals with exactly one
      // delete (1 → absent transition) and the mute key is gone.
      await db.update(
        'groups',
        {'is_muted': 0},
        where: 'id = ?',
        whereArgs: ['group-1'],
      );
      counting.writeCount = 0;
      counting.deleteCount = 0;
      await countingRepo.mirrorAllMutedGroups();
      expect(counting.deleteCount, 1);
      expect(
        await counting.containsKey(sharedGroupMutedKeyName('group-1')),
        isFalse,
      );
    });

    test(
      'terminal self-removal removes projection then primary and mirrors while retaining retry addresses',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final terminalRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
          beforeSelfRemovedReferenceFinalize: () => order.add('sql'),
        );
        for (final (table, generation) in [
          ('group_keys', 1),
          ('group_key_rotation_drafts', 2),
        ]) {
          final storeName = groupKeyMaterialStoreName(marked.id, generation);
          await primary.write(storeName, 'secret-$generation');
          await mirror.write(
            sharedGroupPushKeyName(marked.id, generation),
            'secret-$generation',
          );
          await db.insert(table, {
            'group_id': marked.id,
            'key_generation': generation,
            'encrypted_key': secureStoreReferenceForKey(storeName),
            'created_at': now.toIso8601String(),
          });
        }
        await mirror.write(sharedGroupMutedKeyName(marked.id), '1');
        final authority = await terminalRepo.loadSelfRemovedShellAuthority(
          groupId: marked.id,
          selfPeerId: 'peer-self',
        );

        projection.failStrictRemoval = true;
        await expectLater(
          terminalRepo.terminalizeSelfRemovedShell(expected: authority),
          throwsStateError,
        );
        expect(order, ['projection:${marked.id}']);
        expect(await db.query('group_keys'), hasLength(1));

        projection.failStrictRemoval = false;
        order.clear();
        primary.failDeleteContaining = ':1';
        await expectLater(
          terminalRepo.terminalizeSelfRemovedShell(expected: authority),
          throwsStateError,
        );
        expect(order.first, 'projection:${marked.id}');
        expect(order.where((entry) => entry.startsWith('mirror:')), isEmpty);
        expect(await db.query('group_keys'), hasLength(1));
        expect(await db.query('group_key_rotation_drafts'), hasLength(1));

        primary.failDeleteContaining = null;
        order.clear();
        expect(
          await terminalRepo.terminalizeSelfRemovedShell(expected: authority),
          SelfRemovedShellMutationOutcome.committed,
        );
        expect(order.first, 'projection:${marked.id}');
        expect(
          order.indexOf('sql'),
          greaterThan(
            order.lastIndexWhere((entry) => entry.startsWith('mirror:')),
          ),
        );
        expect(await db.query('group_keys'), isEmpty);
        expect(await db.query('group_key_rotation_drafts'), isEmpty);

        order.clear();
        expect(
          await terminalRepo.terminalizeSelfRemovedShell(expected: authority),
          SelfRemovedShellMutationOutcome.committed,
        );
        expect(order, [
          'projection:${marked.id}',
          'mirror:${sharedGroupMutedKeyName(marked.id)}',
          'sql',
        ]);

        final floor = await terminalRepo.appendSelfRemovedShellFreshnessFloor(
          expected: authority,
        );
        projection.failStrictRemoval = true;
        order.clear();
        expect(
          await terminalRepo.purgeSelfRemovedShell(
            expected: authority,
            floor: floor,
            deletedAt: DateTime.utc(2026, 7, 20, 13),
          ),
          SelfRemovedShellMutationOutcome.committed,
        );
        expect(await db.query('groups'), isEmpty);
        expect(
          order,
          isEmpty,
          reason: 'no fallible external projection may follow group-last SQL',
        );
      },
    );

    test(
      'launch key backfill serializes action-first so B3 terminal cleanup wins last',
      () async {
        final active = await resetToActiveV102();
        final pushKey = sharedGroupPushKeyName(active.id, 1);
        final mirror = _BlockingWriteSecureKeyStore(pushKey);
        final storeName = groupKeyMaterialStoreName(active.id, 1);
        groupKeyStore = FakeSecureKeyStore();
        await groupKeyStore.write(storeName, 'secret');
        await dbInsertGroupKey(
          db,
          makeKey(
            groupId: active.id,
            encryptedKey: secureStoreReferenceForKey(storeName),
          ).toMap(),
        );
        final guarded = makeRepo(
          mirror,
          selfRemovedShellAuthorityEnabled: true,
        );

        final backfill = guarded.mirrorAllKeysToSecureStore();
        await mirror.entered.future;
        var commitCompleted = false;
        final commit = guarded
            .commitSelfRemovalAuthority(
              groupId: active.id,
              selfPeerId: 'peer-self',
              expectedSelfJoinedAt: now,
              removalAt: DateTime.utc(2026, 7, 20, 12),
              removalEventId: 'remove-race',
              leaveNative: () async {},
            )
            .then((outcome) {
              commitCompleted = true;
              return outcome;
            });
        await Future<void>.delayed(Duration.zero);
        expect(commitCompleted, isFalse);

        mirror.release.complete();
        await backfill;
        expect(await commit, SelfRemovalAuthorityCommitOutcome.committed);
        final marked = await guarded.loadSelfRemovedShellAuthority(
          groupId: active.id,
          selfPeerId: 'peer-self',
        );
        expect(
          await guarded.terminalizeSelfRemovedShell(expected: marked),
          SelfRemovedShellMutationOutcome.committed,
        );
        expect(await mirror.containsKey(pushKey), isFalse);
      },
    );

    test(
      'launch mute backfill fresh-checks after B3 and cannot resurrect a purged shell',
      () async {
        final active = await resetToActiveV102(isMuted: true);
        final muteKey = sharedGroupMutedKeyName(active.id);
        final mirror = FakeSecureKeyStore();
        await mirror.write(muteKey, '1');
        final snapshotLoaded = Completer<void>();
        final releaseSnapshot = Completer<void>();
        var interceptSnapshot = true;
        final guarded = makeRepo(
          mirror,
          selfRemovedShellAuthorityEnabled: true,
          loadAllGroupsOverride: () async {
            final rows = await dbLoadAllGroups(db);
            if (interceptSnapshot) {
              interceptSnapshot = false;
              snapshotLoaded.complete();
              await releaseSnapshot.future;
            }
            return rows;
          },
        );

        final staleBackfill = guarded.mirrorAllMutedGroups();
        await snapshotLoaded.future;
        expect(
          await guarded.commitSelfRemovalAuthority(
            groupId: active.id,
            selfPeerId: 'peer-self',
            expectedSelfJoinedAt: now,
            removalAt: DateTime.utc(2026, 7, 20, 12),
            removalEventId: 'remove-race',
            leaveNative: () async {},
          ),
          SelfRemovalAuthorityCommitOutcome.committed,
        );
        final marked = await guarded.loadSelfRemovedShellAuthority(
          groupId: active.id,
          selfPeerId: 'peer-self',
        );
        expect(
          await guarded.terminalizeSelfRemovedShell(expected: marked),
          SelfRemovedShellMutationOutcome.committed,
        );
        final floor = await guarded.appendSelfRemovedShellFreshnessFloor(
          expected: marked,
        );
        expect(
          await guarded.purgeSelfRemovedShell(
            expected: marked,
            floor: floor,
            deletedAt: DateTime.utc(2026, 7, 20, 13),
          ),
          SelfRemovedShellMutationOutcome.committed,
        );

        releaseSnapshot.complete();
        await staleBackfill;
        expect(await mirror.containsKey(muteKey), isFalse);
      },
    );

    test(
      'accepted re-entry removes prior projection before old key cleanup and then exposes only the committed epoch',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final acceptedRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        for (final (table, generation) in [
          ('group_keys', 1),
          ('group_key_rotation_drafts', 2),
        ]) {
          final storeName = groupKeyMaterialStoreName(marked.id, generation);
          await primary.write(storeName, 'old-secret-$generation');
          await mirror.write(
            sharedGroupPushKeyName(marked.id, generation),
            'old-secret-$generation',
          );
          await db.insert(table, {
            'group_id': marked.id,
            'key_generation': generation,
            'encrypted_key': secureStoreReferenceForKey(storeName),
            'created_at': now.toIso8601String(),
          });
        }
        await mirror.write(sharedGroupMutedKeyName(marked.id), '1');

        const nonce = 'accepted-phase-1';
        final acceptedKey = makeKey(keyGeneration: 3);
        final result = await acceptedRepo.commitAcceptedReentry(
          group: makeGroup().copyWith(selfRemovedAt: null),
          roster: <GroupMember>[
            makeMember(peerId: 'peer-self').copyWith(
              joinedAt: marked.selfRemovedAt!.add(const Duration(minutes: 2)),
            ),
          ],
          key: acceptedKey,
          selfPeerId: 'peer-self',
          authorizationId: 'invite-accepted-1',
          signedMembershipWatermark: marked.selfRemovedAt!
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          signedIssuedAt: marked.selfRemovedAt!
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          bindingNonce: nonce,
        );

        expect(result.committed, isTrue);
        expect(
          result.acceptedAt,
          marked.selfRemovedAt!.add(const Duration(minutes: 2)),
        );
        final storedGroup = await acceptedRepo.getGroup(marked.id);
        expect(storedGroup, isNotNull);
        expect(storedGroup!.selfRemovedAt, isNull);
        expect(storedGroup.lastMembershipEventId, isNull);
        expect(
          (await acceptedRepo.getMembers(
            marked.id,
          )).map((member) => member.peerId),
          contains('peer-self'),
        );
        expect(
          (await acceptedRepo.getLatestKey(marked.id))!.encryptedKey,
          'base64-key-3',
        );

        final strictProjection = order.indexOf('projection:${marked.id}');
        final firstPrimary = order.indexWhere(
          (entry) => entry.startsWith('primary:'),
        );
        final firstMirror = order.indexWhere(
          (entry) => entry.startsWith('mirror:'),
        );
        final acceptedProjection = order.indexOf(
          'projection:accepted:${marked.id}',
        );
        expect(strictProjection, greaterThanOrEqualTo(0));
        expect(firstPrimary, greaterThan(strictProjection));
        expect(firstMirror, greaterThan(firstPrimary));
        expect(acceptedProjection, greaterThan(firstMirror));
        expect(projection.acceptedContextPublished, isTrue);

        expect(
          await primary.containsKey(groupKeyMaterialStoreName(marked.id, 1)),
          isFalse,
        );
        expect(
          await primary.containsKey(groupKeyMaterialStoreName(marked.id, 2)),
          isFalse,
        );
        expect(
          await primary.read(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          'base64-key-3',
        );
        expect(
          await mirror.read(sharedGroupPushKeyName(marked.id, 3)),
          'base64-key-3',
        );
        expect(await db.query('group_keys'), hasLength(1));
        expect(await db.query('group_key_rotation_drafts'), isEmpty);
      },
    );

    test(
      'accepted re-entry durably owns floor origin and SQL address before primary write at the same generation',
      () async {
        final marked = await resetToMarkedV102();
        final primary = _InspectingAcceptedWriteStore();
        final mirror = FakeSecureKeyStore();
        groupKeyStore = primary;
        final projection = _RecordingProjection(<String>[]);
        final acceptedRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        final oldStoreName = groupKeyMaterialStoreName(marked.id, 3);
        await primary.write(oldStoreName, 'old-same-generation');
        await db.insert('group_keys', <String, Object?>{
          'group_id': marked.id,
          'key_generation': 3,
          'encrypted_key': secureStoreReferenceForKey(oldStoreName),
          'created_at': now.toIso8601String(),
        });

        const nonce = 'sql-before-primary';
        primary.onAcceptedWrite = (storeKey, value) async {
          expect(value, 'base64-key-3');
          final events = await db.query(
            'group_event_log',
            where: 'group_id = ?',
            whereArgs: <Object?>[marked.id],
            orderBy: 'sequence ASC',
          );
          expect(events.map((row) => row['event_type']), <Object?>[
            kLocalSelfRemovedFreshnessFloorEventType,
            kLocalSelfRemovedAcceptOriginEventType,
          ]);
          final groupRow = (await db.query(
            'groups',
            where: 'id = ?',
            whereArgs: <Object?>[marked.id],
          )).single;
          expect(groupRow['self_removed_at'], isNotNull);
          final keyRows = await db.query(
            'group_keys',
            where: 'group_id = ?',
            whereArgs: <Object?>[marked.id],
          );
          expect(keyRows, hasLength(1));
          expect(
            keyRows.single['encrypted_key'],
            secureStoreReferenceForKey(storeKey),
          );
          expect(await primary.containsKey(oldStoreName), isFalse);
        };

        final result = await acceptedRepo.commitAcceptedReentry(
          group: makeGroup().copyWith(selfRemovedAt: null),
          roster: <GroupMember>[
            makeMember(peerId: 'peer-self').copyWith(
              joinedAt: marked.selfRemovedAt!.add(const Duration(minutes: 2)),
            ),
          ],
          key: makeKey(keyGeneration: 3),
          selfPeerId: 'peer-self',
          authorizationId: 'invite-sql-before-primary',
          signedMembershipWatermark: marked.selfRemovedAt!
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          signedIssuedAt: marked.selfRemovedAt!
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          bindingNonce: nonce,
        );

        expect(result.committed, isTrue);
        expect(primary.acceptedWriteCount, 1);
        expect(
          await primary.read(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          'base64-key-3',
        );
      },
    );

    test(
      'accepted re-entry refusal compensates its phase-unique key and preserves prior retry material',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final acceptedRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        final priorStoreName = groupKeyMaterialStoreName(marked.id, 1);
        await primary.write(priorStoreName, 'old-secret');
        await mirror.write(sharedGroupPushKeyName(marked.id, 1), 'old-secret');
        await db.insert('group_keys', {
          'group_id': marked.id,
          'key_generation': 1,
          'encrypted_key': secureStoreReferenceForKey(priorStoreName),
          'created_at': now.toIso8601String(),
        });

        const nonce = 'stale-phase';
        final result = await acceptedRepo.commitAcceptedReentry(
          group: makeGroup().copyWith(selfRemovedAt: null),
          roster: <GroupMember>[makeMember(peerId: 'peer-self')],
          key: makeKey(keyGeneration: 3),
          selfPeerId: 'peer-self',
          authorizationId: 'invite-stale',
          signedMembershipWatermark: marked.selfRemovedAt!.toIso8601String(),
          signedIssuedAt: marked.selfRemovedAt!.toIso8601String(),
          bindingNonce: nonce,
        );

        expect(
          result.outcome,
          SelfRemovedAcceptedReentryOutcome.refusedStaleAuthority,
        );
        expect(
          await primary.containsKey(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          isFalse,
        );
        expect(await primary.read(priorStoreName), 'old-secret');
        expect(
          await mirror.read(sharedGroupPushKeyName(marked.id, 1)),
          'old-secret',
        );
        expect(await db.query('group_keys'), hasLength(1));
        expect(
          order.where((entry) => entry.startsWith('projection:')),
          isEmpty,
        );
      },
    );

    test(
      'accepted projection failure removes partial context rolls authority back and purges only the accepted address',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order)
          ..failAcceptedReplacement = true;
        final acceptedRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        final priorStoreName = groupKeyMaterialStoreName(marked.id, 1);
        await primary.write(priorStoreName, 'old-secret');
        await mirror.write(sharedGroupPushKeyName(marked.id, 1), 'old-secret');
        await db.insert('group_keys', {
          'group_id': marked.id,
          'key_generation': 1,
          'encrypted_key': secureStoreReferenceForKey(priorStoreName),
          'created_at': now.toIso8601String(),
        });

        const nonce = 'projection-failure-phase';
        await expectLater(
          acceptedRepo.commitAcceptedReentry(
            group: makeGroup().copyWith(selfRemovedAt: null),
            roster: <GroupMember>[
              makeMember(peerId: 'peer-self').copyWith(
                joinedAt: marked.selfRemovedAt!.add(const Duration(minutes: 2)),
              ),
            ],
            key: makeKey(keyGeneration: 3),
            selfPeerId: 'peer-self',
            authorizationId: 'invite-projection-failure',
            signedMembershipWatermark: marked.selfRemovedAt!
                .add(const Duration(minutes: 1))
                .toIso8601String(),
            signedIssuedAt: marked.selfRemovedAt!
                .add(const Duration(minutes: 2))
                .toIso8601String(),
            bindingNonce: nonce,
          ),
          throwsStateError,
        );

        final restored = await acceptedRepo.getGroup(marked.id);
        expect(restored, isNotNull);
        expect(restored!.selfRemovedAt, marked.selfRemovedAt);
        expect(await db.query('group_members'), isEmpty);
        final restoredRows = await db.query('group_keys');
        expect(restoredRows, isEmpty);
        expect(await primary.containsKey(priorStoreName), isFalse);
        expect(
          await primary.containsKey(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupPushKeyName(marked.id, 3)),
          isFalse,
        );
        expect(projection.acceptedContextPublished, isFalse);
        expect(
          order.where((entry) => entry == 'projection:${marked.id}'),
          hasLength(2),
        );
        expect(order, contains('projection:accepted:${marked.id}'));
      },
    );

    test(
      'accepted rollback removes projection then staged primary mirrors and SQL without resurrecting retired addresses',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final acceptedRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        final priorStoreName = groupKeyMaterialStoreName(marked.id, 1);
        await primary.write(priorStoreName, 'old-secret');
        await db.insert('group_keys', {
          'group_id': marked.id,
          'key_generation': 1,
          'encrypted_key': secureStoreReferenceForKey(priorStoreName),
          'created_at': now.toIso8601String(),
        });

        const nonce = 'rollback-phase';
        final committed = await acceptedRepo.commitAcceptedReentry(
          group: makeGroup().copyWith(selfRemovedAt: null),
          roster: <GroupMember>[
            makeMember(peerId: 'peer-self').copyWith(
              joinedAt: marked.selfRemovedAt!.add(const Duration(minutes: 2)),
            ),
          ],
          key: makeKey(keyGeneration: 3),
          selfPeerId: 'peer-self',
          authorizationId: 'invite-rollback',
          signedMembershipWatermark: marked.selfRemovedAt!
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          signedIssuedAt: marked.selfRemovedAt!
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          bindingNonce: nonce,
        );
        expect(committed.committed, isTrue);
        order.clear();

        final rollback = await acceptedRepo.rollbackAcceptedReentry(
          groupId: marked.id,
          selfPeerId: 'peer-self',
          authorizationId: 'invite-rollback',
        );

        expect(rollback, SelfRemovedAcceptedRollbackOutcome.rolledBack);
        final restored = await acceptedRepo.getGroup(marked.id);
        expect(restored, isNotNull);
        expect(restored!.selfRemovedAt, marked.selfRemovedAt);
        expect(await db.query('group_members'), isEmpty);
        final restoredRows = await db.query('group_keys');
        expect(restoredRows, isEmpty);
        expect(
          await primary.containsKey(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupPushKeyName(marked.id, 3)),
          isFalse,
        );
        expect(projection.acceptedContextPublished, isFalse);
        expect(order.first, 'projection:${marked.id}');
        expect(
          order.indexWhere((entry) => entry.startsWith('primary:')),
          greaterThan(0),
        );
        expect(
          order.indexWhere((entry) => entry.startsWith('mirror:')),
          greaterThan(
            order.lastIndexWhere((entry) => entry.startsWith('primary:')),
          ),
        );
      },
    );

    test(
      'accepted projection partial write with failed compensation preserves committed binding key and authority',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order)
          ..failAcceptedReplacement = true
          ..failCompensatingStrictRemoval = true;
        final acceptedRepo = makeRepo(
          FakeSecureKeyStore(),
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        final watermark = marked.selfRemovedAt!.add(const Duration(minutes: 1));
        final issuedAt = marked.selfRemovedAt!.add(const Duration(minutes: 2));
        const nonce = 'failed-compensation-phase';

        await expectLater(
          acceptedRepo.commitAcceptedReentry(
            group: makeGroup().copyWith(selfRemovedAt: null),
            roster: <GroupMember>[
              makeMember(peerId: 'peer-self').copyWith(joinedAt: issuedAt),
            ],
            key: makeKey(keyGeneration: 3),
            selfPeerId: 'peer-self',
            authorizationId: 'invite-preserved-accepted',
            signedMembershipWatermark: watermark.toIso8601String(),
            signedIssuedAt: issuedAt.toIso8601String(),
            bindingNonce: nonce,
          ),
          throwsStateError,
        );

        final preserved = await acceptedRepo.getGroup(marked.id);
        expect(preserved?.selfRemovedAt, isNull);
        expect(await acceptedRepo.getMember(marked.id, 'peer-self'), isNotNull);
        expect(
          (await acceptedRepo.getLatestKey(marked.id))?.encryptedKey,
          'base64-key-3',
        );
        expect(
          await primary.read(
            groupAcceptedKeyMaterialStoreName(marked.id, 3, nonce),
          ),
          'base64-key-3',
        );
        expect(
          await acceptedRepo.authorizeAcceptedReentryRetry(
            groupId: marked.id,
            selfPeerId: 'peer-self',
            authorizationId: 'invite-preserved-accepted',
            signedMembershipWatermark: watermark.toIso8601String(),
            signedIssuedAt: issuedAt.toIso8601String(),
            keyGeneration: 3,
          ),
          SelfRemovedAcceptedRetryAuthorizationOutcome.authorized,
        );
        expect(projection.acceptedContextPublished, isTrue);
      },
    );

    test(
      'accepted rollback refusal leaves projection and accepted state untouched',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        groupKeyStore = FakeSecureKeyStore();
        final projection = _RecordingProjection(order);
        final acceptedRepo = makeRepo(
          FakeSecureKeyStore(),
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        const nonce = 'rollback-refusal-phase';
        final committed = await acceptedRepo.commitAcceptedReentry(
          group: makeGroup().copyWith(selfRemovedAt: null),
          roster: <GroupMember>[
            makeMember(peerId: 'peer-self').copyWith(
              joinedAt: marked.selfRemovedAt!.add(const Duration(minutes: 2)),
            ),
          ],
          key: makeKey(keyGeneration: 3),
          selfPeerId: 'peer-self',
          authorizationId: 'newest-invite',
          signedMembershipWatermark: marked.selfRemovedAt!
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          signedIssuedAt: marked.selfRemovedAt!
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          bindingNonce: nonce,
        );
        expect(committed.committed, isTrue);
        order.clear();

        final refused = await acceptedRepo.rollbackAcceptedReentry(
          groupId: marked.id,
          selfPeerId: 'peer-self',
          authorizationId: 'older-invite',
        );

        expect(
          refused,
          SelfRemovedAcceptedRollbackOutcome.refusedAuthorizationMismatch,
        );
        expect(
          order,
          isEmpty,
          reason: 'refusal must precede projection revoke',
        );
        expect(projection.acceptedContextPublished, isTrue);
        expect((await acceptedRepo.getGroup(marked.id))?.selfRemovedAt, isNull);
        expect(
          (await acceptedRepo.getLatestKey(marked.id))?.encryptedKey,
          'base64-key-3',
        );
      },
    );

    test(
      'fresh accepted rollback refuses newer metadata before projection or key deletion',
      () async {
        await db.close();
        db = await openDatabase(inMemoryDatabasePath, version: 1);
        await runProductionOnCreate(db, 102);
        final membershipAt = DateTime.utc(2026, 7, 20, 13);
        final metadataAt = DateTime.utc(2026, 7, 20, 12, 30);
        final group = makeGroup().copyWith(
          lastMembershipEventAt: membershipAt,
          lastMetadataEventAt: metadataAt,
        );
        await dbInsertGroup(db, group.toMap());
        await dbInsertGroupMember(db, makeMember(peerId: 'peer-self').toMap());
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final freshRepo = makeRepo(
          FakeSecureKeyStore(),
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        await freshRepo.saveKey(makeKey(keyGeneration: 3));
        order.clear();
        await db.update(
          'groups',
          <String, Object?>{
            'last_metadata_event_at': metadataAt
                .add(const Duration(seconds: 1))
                .toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: <Object?>[group.id],
        );

        final result = await freshRepo.rollbackFreshAcceptedMaterialization(
          groupId: group.id,
          selfPeerId: 'peer-self',
          keyGeneration: 3,
          expectedKeyMaterial: 'base64-key-3',
          expectedMembershipAt: membershipAt,
          latestAllowedMetadataAt: metadataAt,
        );

        expect(result, SelfRemovedAcceptedRollbackOutcome.refusedStateChanged);
        expect(order, isEmpty);
        expect(await freshRepo.getGroup(group.id), isNotNull);
        expect(
          (await freshRepo.getLatestKey(group.id))?.encryptedKey,
          'base64-key-3',
        );
      },
    );

    test(
      'fresh accepted rollback restart accepts exact SQL fingerprint when primary is already missing',
      () async {
        await db.close();
        db = await openDatabase(inMemoryDatabasePath, version: 1);
        await runProductionOnCreate(db, 102);
        final membershipAt = DateTime.utc(2026, 7, 20, 13);
        final metadataAt = DateTime.utc(2026, 7, 20, 12, 30);
        final group = makeGroup().copyWith(
          isMuted: true,
          lastMembershipEventAt: membershipAt,
          lastMetadataEventAt: metadataAt,
        );
        await dbInsertGroup(db, group.toMap());
        await dbInsertGroupMember(db, makeMember(peerId: 'peer-self').toMap());
        final order = <String>[];
        final primary = _OrderedSecureKeyStore('primary', order);
        final mirror = _OrderedSecureKeyStore('mirror', order);
        groupKeyStore = primary;
        final projection = _RecordingProjection(order);
        final freshRepo = makeRepo(
          mirror,
          projection: projection,
          selfRemovedShellAuthorityEnabled: true,
        );
        await freshRepo.saveKey(makeKey(keyGeneration: 3));
        await mirror.write(sharedGroupMutedKeyName(group.id), '1');
        final primaryStoreKey = groupKeyMaterialStoreName(group.id, 3);
        expect(await primary.read(primaryStoreKey), 'base64-key-3');
        expect(
          await freshRepo.rollbackFreshAcceptedMaterialization(
            groupId: group.id,
            selfPeerId: 'peer-self',
            keyGeneration: 3,
            expectedKeyMaterial: 'different-non-null-material',
            expectedMembershipAt: membershipAt,
            latestAllowedMetadataAt: metadataAt,
          ),
          SelfRemovedAcceptedRollbackOutcome.refusedStateChanged,
        );
        expect(
          order,
          isEmpty,
          reason: 'non-null key mismatch must fail closed',
        );

        // Simulate a crash after strict primary deletion but before the exact
        // SQL fingerprint CAS removed the group, roster, and key row.
        await primary.delete(primaryStoreKey);
        order.clear();

        final result = await freshRepo.rollbackFreshAcceptedMaterialization(
          groupId: group.id,
          selfPeerId: 'peer-self',
          keyGeneration: 3,
          expectedKeyMaterial: 'base64-key-3',
          expectedMembershipAt: membershipAt,
          latestAllowedMetadataAt: metadataAt,
        );

        expect(result, SelfRemovedAcceptedRollbackOutcome.rolledBack);
        expect(order.first, 'projection:${group.id}');
        expect(await primary.containsKey(primaryStoreKey), isFalse);
        expect(
          await mirror.containsKey(sharedGroupPushKeyName(group.id, 3)),
          isFalse,
        );
        expect(
          await mirror.containsKey(sharedGroupMutedKeyName(group.id)),
          isFalse,
        );
        expect(await db.query('groups'), isEmpty);
        expect(await db.query('group_members'), isEmpty);
        expect(await db.query('group_keys'), isEmpty);
      },
    );

    test(
      'duplicate retry holds the per-group coordinator through native join',
      () async {
        await db.close();
        db = await openDatabase(inMemoryDatabasePath, version: 1);
        await runProductionOnCreate(db, 102);
        final membershipAt = DateTime.utc(2026, 7, 20, 13);
        final group = makeGroup().copyWith(lastMembershipEventAt: membershipAt);
        await dbInsertGroup(db, group.toMap());
        await dbInsertGroupMember(db, makeMember(peerId: 'peer-self').toMap());
        groupKeyStore = FakeSecureKeyStore();
        final coordinated = makeRepo(
          FakeSecureKeyStore(),
          selfRemovedShellAuthorityEnabled: true,
        );
        await coordinated.saveKey(makeKey(keyGeneration: 3));
        final nativeEntered = Completer<void>();
        final releaseNative = Completer<void>();

        final retry = coordinated.retryAcceptedReentryNative(
          groupId: group.id,
          selfPeerId: 'peer-self',
          authorizationId: 'fresh-invite',
          signedMembershipWatermark: membershipAt.toIso8601String(),
          signedIssuedAt: membershipAt.toIso8601String(),
          keyGeneration: 3,
          expectedKeyMaterial: 'base64-key-3',
          expectedFreshMembershipAt: membershipAt,
          latestAllowedMetadataAt: null,
          joinNative: () async {
            nativeEntered.complete();
            await releaseNative.future;
          },
        );
        await nativeEntered.future;
        var writerCompleted = false;
        final writer = coordinated
            .updateGroup(group.copyWith(name: 'newer writer'))
            .then((_) => writerCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(writerCompleted, isFalse);

        releaseNative.complete();
        expect((await retry).joined, isTrue);
        await writer;
        expect(writerCompleted, isTrue);
      },
    );

    test(
      'marked or absent group rejects delayed member committed key and draft writes without secure or projection residue',
      () async {
        final marked = await resetToMarkedV102();
        groupKeyStore = FakeSecureKeyStore();
        final guarded = makeRepo(
          FakeSecureKeyStore(),
          selfRemovedShellAuthorityEnabled: true,
        );
        await expectLater(guarded.saveMember(makeMember()), throwsStateError);
        await expectLater(guarded.saveKey(makeKey()), throwsStateError);
        await expectLater(
          guarded.savePendingKeyRotation(makeKey(keyGeneration: 2)),
          throwsStateError,
        );
        expect(await db.query('group_members'), isEmpty);
        expect(await db.query('group_keys'), isEmpty);
        expect(await db.query('group_key_rotation_drafts'), isEmpty);
        expect(
          await groupKeyStore.containsKey(
            groupKeyMaterialStoreName(marked.id, 1),
          ),
          isFalse,
        );
      },
    );

    test(
      'marked or absent group suppresses delayed group projection writes',
      () async {
        final marked = await resetToMarkedV102();
        final order = <String>[];
        final guarded = makeRepo(
          FakeSecureKeyStore(),
          projection: _RecordingProjection(order),
          selfRemovedShellAuthorityEnabled: true,
        );
        await guarded.saveGroup(
          makeGroup().copyWith(name: 'stale materializer'),
        );
        final stored = await guarded.getGroup(marked.id);
        expect(stored!.selfRemovedAt, marked.selfRemovedAt);
        expect(order, ['projection:${marked.id}']);
      },
    );

    test(
      'marked group refuses ordinary destructive methods and preserves terminal retry addresses',
      () async {
        final marked = await resetToMarkedV102();
        await db.insert('group_keys', {
          'group_id': marked.id,
          'key_generation': 1,
          'encrypted_key': 'legacy-address',
          'created_at': now.toIso8601String(),
        });
        final guarded = makeRepo(
          FakeSecureKeyStore(),
          selfRemovedShellAuthorityEnabled: true,
        );
        await expectLater(guarded.deleteGroup(marked.id), throwsStateError);
        await expectLater(
          guarded.removeAllMembers(marked.id),
          throwsStateError,
        );
        await expectLater(guarded.removeAllKeys(marked.id), throwsStateError);
        await expectLater(
          guarded.clearPendingKeyRotations(marked.id),
          throwsStateError,
        );
        expect(await db.query('groups'), hasLength(1));
        expect(await db.query('group_keys'), hasLength(1));
      },
    );

    test(
      'marked group hides retained terminal keys from ordinary readers and backfills',
      () async {
        final marked = await resetToMarkedV102();
        final storeName = groupKeyMaterialStoreName(marked.id, 1);
        groupKeyStore = FakeSecureKeyStore();
        await groupKeyStore.write(storeName, 'secret');
        await db.insert('group_keys', {
          'group_id': marked.id,
          'key_generation': 1,
          'encrypted_key': secureStoreReferenceForKey(storeName),
          'created_at': now.toIso8601String(),
        });
        final mirror = FakeSecureKeyStore();
        final guarded = makeRepo(
          mirror,
          selfRemovedShellAuthorityEnabled: true,
        );
        expect(await guarded.getLatestKey(marked.id), isNull);
        expect(await guarded.getKeyByGeneration(marked.id, 1), isNull);
        await guarded.mirrorAllKeysToSecureStore();
        expect(
          await mirror.containsKey(sharedGroupPushKeyName(marked.id, 1)),
          isFalse,
        );
      },
    );
  });
}
