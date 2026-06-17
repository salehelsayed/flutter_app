import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/group_key_info.dart';
import '../models/group_key_retention_policy.dart';
import '../models/group_member.dart';
import '../models/pending_sibling_device.dart';
import 'pending_sibling_device_repository.dart';
import '../models/group_model.dart';
import 'group_repository.dart';

String sharedGroupPushKeyName(String groupId, int keyGeneration) =>
    'group_key:$groupId:$keyGeneration';

/// 04-P0 SI-1 NSE: shared-Keychain key under which the app mirrors a group's
/// mute state ('1' when muted, deleted otherwise) so the out-of-process iOS
/// Notification Service Extension can honor mute. Read on the Swift side via
/// PushSharedKeyNames.groupMuted(groupId:).
String sharedGroupMutedKeyName(String groupId) => 'group_muted:$groupId';

/// Implementation of GroupRepository using constructor-injected DB helper functions.
class GroupRepositoryImpl
    implements
        GroupRepository,
        RemovedGroupMemberSnapshotRepository,
        GroupMemberDeviceSnapshotRepository,
        PendingSiblingDeviceRepository,
        GroupKeyRotationDraftRepository {
  // --- Group DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAllGroups;
  final Future<Map<String, Object?>?> Function(String id) dbLoadGroup;
  final Future<void> Function(Map<String, Object?> row) dbUpdateGroup;
  final Future<void> Function(String id) dbDeleteGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadActiveGroups;
  final Future<void> Function(String id) dbArchiveGroup;
  final Future<void> Function(String id) dbUnarchiveGroup;

  // --- Member DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupMember;
  final Future<List<Map<String, Object?>>> Function(String groupId)
  dbLoadAllGroupMembers;
  final Future<Map<String, Object?>?> Function(String groupId, String peerId)
  dbLoadGroupMember;
  final Future<void> Function(String groupId, String peerId, String role)
  dbUpdateGroupMemberRole;
  final Future<void> Function(String groupId, String peerId)
  dbDeleteGroupMember;
  final Future<void> Function(String groupId) dbDeleteAllGroupMembers;
  final Future<void> Function(Map<String, Object?> row, String removedAt)?
  dbInsertRemovedGroupMemberSnapshot;
  final Future<Map<String, Object?>?> Function(String groupId, String peerId)?
  dbLoadRemovedGroupMemberSnapshot;
  final Future<void> Function(Map<String, Object?> row, String savedAt)?
  dbUpsertGroupMemberDeviceSnapshot;
  final Future<Map<String, Object?>?> Function(String groupId, String peerId)?
  dbLoadGroupMemberDeviceSnapshot;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertPendingSiblingDevice;
  final Future<List<Map<String, Object?>>> Function(String groupId)?
  dbLoadPendingSiblingDevicesForGroup;
  final Future<Map<String, Object?>?> Function(
    String groupId,
    String memberPeerId,
    String deviceId,
  )?
  dbLoadPendingSiblingDevice;
  final Future<void> Function(
    String groupId,
    String memberPeerId,
    String deviceId,
  )?
  dbDeletePendingSiblingDevice;

  // --- Key DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupKey;
  final Future<Map<String, Object?>?> Function(String groupId)
  dbLoadLatestGroupKey;
  final Future<Map<String, Object?>?> Function(String groupId, int generation)
  dbLoadGroupKeyByGeneration;
  final Future<void> Function(String groupId) dbDeleteAllGroupKeys;
  final Future<List<Map<String, Object?>>> Function(String groupId)?
  dbLoadAllGroupKeys;
  final Future<void> Function(String groupId, int minKeyGenerationToKeep)?
  dbDeleteGroupKeysBeforeGeneration;
  final Future<void> Function(Map<String, Object?> row)?
  dbUpsertPendingGroupKeyRotation;
  final Future<Map<String, Object?>?> Function(String groupId)?
  dbLoadPendingGroupKeyRotation;
  final Future<void> Function(String groupId, int keyGeneration)?
  dbDeletePendingGroupKeyRotation;
  final Future<void> Function(String groupId)? dbDeletePendingGroupKeyRotations;
  final SecureKeyStore? groupKeyStore;
  final SecureKeyStore? pushSharedKeyStore;

  // Finding 05 Phase 3: bounded per-group rejoin retry state.
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadGroupRejoinStatesFn;
  final Future<void> Function(String groupId, {required int nextEligibleAtMs})?
  dbRecordGroupRejoinFailureFn;
  final Future<void> Function(String groupId)? dbClearGroupRejoinStateFn;

  final Map<String, GroupKeyInfo> _pendingKeyRotationFallback = {};

  GroupRepositoryImpl({
    required this.dbInsertGroup,
    required this.dbLoadAllGroups,
    required this.dbLoadGroup,
    required this.dbUpdateGroup,
    required this.dbDeleteGroup,
    required this.dbLoadActiveGroups,
    required this.dbArchiveGroup,
    required this.dbUnarchiveGroup,
    required this.dbInsertGroupMember,
    required this.dbLoadAllGroupMembers,
    required this.dbLoadGroupMember,
    required this.dbUpdateGroupMemberRole,
    required this.dbDeleteGroupMember,
    required this.dbDeleteAllGroupMembers,
    this.dbInsertRemovedGroupMemberSnapshot,
    this.dbLoadRemovedGroupMemberSnapshot,
    this.dbUpsertGroupMemberDeviceSnapshot,
    this.dbLoadGroupMemberDeviceSnapshot,
    this.dbUpsertPendingSiblingDevice,
    this.dbLoadPendingSiblingDevicesForGroup,
    this.dbLoadPendingSiblingDevice,
    this.dbDeletePendingSiblingDevice,
    this.dbLoadGroupRejoinStatesFn,
    this.dbRecordGroupRejoinFailureFn,
    this.dbClearGroupRejoinStateFn,
    required this.dbInsertGroupKey,
    required this.dbLoadLatestGroupKey,
    required this.dbLoadGroupKeyByGeneration,
    required this.dbDeleteAllGroupKeys,
    this.dbLoadAllGroupKeys,
    this.dbDeleteGroupKeysBeforeGeneration,
    this.dbUpsertPendingGroupKeyRotation,
    this.dbLoadPendingGroupKeyRotation,
    this.dbDeletePendingGroupKeyRotation,
    this.dbDeletePendingGroupKeyRotations,
    this.groupKeyStore,
    this.pushSharedKeyStore,
  });

  // --- Groups ---

  @override
  Future<void> saveGroup(GroupModel group) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REPO_SAVE_START',
      details: {
        'id': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
      },
    );

    try {
      await dbInsertGroup(group.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_SAVE_SUCCESS',
        details: {
          'id': group.id.length > 8 ? group.id.substring(0, 8) : group.id,
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<GroupModel>> getAllGroups() async {
    final rows = await dbLoadAllGroups();
    return rows.map((row) => GroupModel.fromMap(row)).toList();
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    final row = await dbLoadGroup(id);
    if (row == null) return null;
    return GroupModel.fromMap(row);
  }

  @override
  Future<void> updateGroup(GroupModel group) async {
    await dbUpdateGroup(group.toMap());
    // 04-P0 SI-1 NSE: keep the shared-Keychain mute projection in sync so the
    // iOS NSE honors mute (idempotent; no-op when pushSharedKeyStore is unset).
    await _mirrorGroupMutedForPush(group.id, group.isMuted);
  }

  @override
  Future<void> deleteGroup(String id) async {
    await dbDeleteGroup(id);
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    final rows = await dbLoadActiveGroups();
    return rows.map((row) => GroupModel.fromMap(row)).toList();
  }

  @override
  Future<void> archiveGroup(String id) async {
    await dbArchiveGroup(id);
  }

  @override
  Future<void> unarchiveGroup(String id) async {
    await dbUnarchiveGroup(id);
  }

  // --- Members ---

  @override
  Future<void> saveMember(GroupMember member) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(member.peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(member.peerId, 'peerId', peerIdRejectReason);
    }
    final duplicateRejectReason = groupMemberDuplicatePeerIdVariantRejectReason(
      await getMembers(member.groupId),
      member,
    );
    if (duplicateRejectReason != null) {
      throw StateError(duplicateRejectReason);
    }
    await dbInsertGroupMember(member.toMap());
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    final rows = await dbLoadAllGroupMembers(groupId);
    return rows.map((row) => GroupMember.fromMap(row)).toList();
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    final row = await dbLoadGroupMember(groupId, peerId);
    if (row == null) return null;
    return GroupMember.fromMap(row);
  }

  @override
  Future<void> updateMemberRole(
    String groupId,
    String peerId,
    MemberRole role,
  ) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(peerId, 'peerId', peerIdRejectReason);
    }
    await dbUpdateGroupMemberRole(groupId, peerId, role.toValue());
  }

  @override
  Future<void> removeMember(String groupId, String peerId) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(peerId, 'peerId', peerIdRejectReason);
    }
    await dbDeleteGroupMember(groupId, peerId);
  }

  @override
  Future<void> saveRemovedMemberSnapshot(
    GroupMember member, {
    required DateTime removedAt,
  }) async {
    final insert = dbInsertRemovedGroupMemberSnapshot;
    if (insert == null) {
      return;
    }
    await insert(member.toMap(), removedAt.toUtc().toIso8601String());
  }

  @override
  Future<GroupMember?> getRemovedMemberSnapshot(
    String groupId,
    String peerId,
  ) async {
    final load = dbLoadRemovedGroupMemberSnapshot;
    if (load == null) {
      return null;
    }
    final row = await load(groupId, peerId);
    if (row == null) {
      return null;
    }
    return GroupMember.fromMap(row);
  }

  @override
  Future<void> saveGroupMemberDeviceSnapshot(
    GroupMember member, {
    required DateTime savedAt,
  }) async {
    final upsert = dbUpsertGroupMemberDeviceSnapshot;
    if (upsert == null) {
      return;
    }
    await upsert({
      'group_id': member.groupId,
      'peer_id': member.peerId,
      'public_key': member.publicKey,
      'ml_kem_public_key': member.mlKemPublicKey,
      'devices_json': GroupMemberDeviceIdentity.listToJsonString(
        member.activeDevicesWithLegacyFallback(),
      ),
    }, savedAt.toUtc().toIso8601String());
  }

  @override
  Future<List<GroupMemberDeviceIdentity>?> loadGroupMemberDeviceSnapshot(
    String groupId,
    String peerId,
  ) async {
    final load = dbLoadGroupMemberDeviceSnapshot;
    if (load == null) {
      return null;
    }
    final row = await load(groupId, peerId);
    if (row == null) {
      return null;
    }
    return GroupMemberDeviceIdentity.listFromJsonString(
      row['devices_json'] as String?,
    );
  }

  @override
  Future<void> savePendingSiblingDevice(PendingSiblingDevice device) async {
    final upsert = dbUpsertPendingSiblingDevice;
    if (upsert == null) return;
    await upsert(device.toMap());
  }

  @override
  Future<List<PendingSiblingDevice>> getPendingSiblingDevicesForGroup(
    String groupId,
  ) async {
    final load = dbLoadPendingSiblingDevicesForGroup;
    if (load == null) return const [];
    final rows = await load(groupId);
    return rows.map(PendingSiblingDevice.fromMap).toList();
  }

  @override
  Future<PendingSiblingDevice?> getPendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  ) async {
    final load = dbLoadPendingSiblingDevice;
    if (load == null) return null;
    final row = await load(groupId, memberPeerId, deviceId);
    return row == null ? null : PendingSiblingDevice.fromMap(row);
  }

  @override
  Future<void> deletePendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  ) async {
    final delete = dbDeletePendingSiblingDevice;
    if (delete == null) return;
    await delete(groupId, memberPeerId, deviceId);
  }

  @override
  Future<void> removeAllMembers(String groupId) async {
    await dbDeleteAllGroupMembers(groupId);
  }

  // --- Keys ---

  @override
  Future<void> saveKey(GroupKeyInfo key) async {
    await dbInsertGroupKey(await _toStorageRow(key));
    final hydratedKey = await _hydrateGroupKey(key);
    if (hydratedKey != null) {
      await _mirrorGroupKeyForPush(hydratedKey);
    }
    await _pruneObsoleteKeys(key.groupId);
  }

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    final row = await dbLoadLatestGroupKey(groupId);
    if (row == null) return null;
    return _groupKeyFromRow(row);
  }

  @override
  Future<Map<String, GroupRejoinState>> loadGroupRejoinStates() async {
    final fn = dbLoadGroupRejoinStatesFn;
    if (fn == null) return const {};
    final rows = await fn();
    final result = <String, GroupRejoinState>{};
    for (final row in rows) {
      final groupId = row['group_id'] as String?;
      if (groupId == null) continue;
      final nextMs = row['next_eligible_at'] as int?;
      result[groupId] = GroupRejoinState(
        attemptCount: (row['rejoin_attempt_count'] as int?) ?? 0,
        nextEligibleAt: nextMs != null
            ? DateTime.fromMillisecondsSinceEpoch(nextMs, isUtc: true)
            : null,
      );
    }
    return result;
  }

  @override
  Future<void> recordGroupRejoinFailure(
    String groupId, {
    required DateTime nextEligibleAt,
  }) async {
    final fn = dbRecordGroupRejoinFailureFn;
    if (fn == null) return;
    await fn(
      groupId,
      nextEligibleAtMs: nextEligibleAt.toUtc().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> clearGroupRejoinState(String groupId) async {
    final fn = dbClearGroupRejoinStateFn;
    if (fn == null) return;
    await fn(groupId);
  }

  @override
  Future<GroupKeyInfo?> getKeyByGeneration(
    String groupId,
    int generation,
  ) async {
    final row = await dbLoadGroupKeyByGeneration(groupId, generation);
    if (row == null) return null;
    return _groupKeyFromRow(row);
  }

  @override
  Future<void> removeAllKeys(String groupId) async {
    final existingKeys =
        (pushSharedKeyStore == null && groupKeyStore == null) ||
            dbLoadAllGroupKeys == null
        ? const <Map<String, Object?>>[]
        : await dbLoadAllGroupKeys!(groupId);
    await dbDeleteAllGroupKeys(groupId);
    await clearPendingKeyRotations(groupId);
    for (final row in existingKeys) {
      final key = GroupKeyInfo.fromMap(row);
      await _deleteGroupKeyMirror(key);
      await _deleteGroupKeyMaterial(key);
    }
  }

  @override
  Future<void> savePendingKeyRotation(GroupKeyInfo key) async {
    final upsertPending = dbUpsertPendingGroupKeyRotation;
    if (upsertPending == null) {
      _pendingKeyRotationFallback[key.groupId] = key;
      return;
    }

    await upsertPending(await _toStorageRow(key));
  }

  @override
  Future<GroupKeyInfo?> getPendingKeyRotation(String groupId) async {
    final loadPending = dbLoadPendingGroupKeyRotation;
    if (loadPending == null) {
      return _pendingKeyRotationFallback[groupId];
    }

    final row = await loadPending(groupId);
    if (row == null) return null;
    return _groupKeyFromRow(row);
  }

  @override
  Future<void> clearPendingKeyRotation(
    String groupId,
    int keyGeneration,
  ) async {
    final deletePending = dbDeletePendingGroupKeyRotation;
    if (deletePending == null) {
      final pending = _pendingKeyRotationFallback[groupId];
      if (pending?.keyGeneration == keyGeneration) {
        _pendingKeyRotationFallback.remove(groupId);
      }
      return;
    }

    await deletePending(groupId, keyGeneration);
    await _deletePendingKeyMaterialIfUncommitted(groupId, keyGeneration);
  }

  @override
  Future<void> clearPendingKeyRotations(String groupId) async {
    final pending = await getPendingKeyRotation(groupId);
    final deletePending = dbDeletePendingGroupKeyRotations;
    if (deletePending == null) {
      _pendingKeyRotationFallback.remove(groupId);
    } else {
      await deletePending(groupId);
    }

    if (pending != null) {
      await _deletePendingKeyMaterialIfUncommitted(
        groupId,
        pending.keyGeneration,
      );
    }
  }

  Future<void> mirrorAllKeysToSecureStore() async {
    if (pushSharedKeyStore == null || dbLoadAllGroupKeys == null) {
      return;
    }

    final groups = await dbLoadAllGroups();
    for (final group in groups) {
      final groupId = group['id'] as String?;
      if (groupId == null) {
        continue;
      }
      final keyRows = await dbLoadAllGroupKeys!(groupId);
      for (final row in keyRows) {
        final key = await _groupKeyFromRow(row);
        if (key == null) {
          continue;
        }
        await _mirrorGroupKeyForPush(key);
      }
    }
  }

  /// 04-P0 SI-1 NSE: launch-time backfill of the shared-Keychain mute
  /// projection for groups that were muted before this feature shipped (their
  /// mute state was never mirrored). Self-heals the projection from the DB.
  Future<void> mirrorAllMutedGroups() async {
    if (pushSharedKeyStore == null) {
      return;
    }

    final groups = await dbLoadAllGroups();
    for (final group in groups) {
      final groupId = group['id'] as String?;
      if (groupId == null) {
        continue;
      }
      final isMuted = (group['is_muted'] as int? ?? 0) == 1;
      await _mirrorGroupMutedForPush(groupId, isMuted);
    }
  }

  Future<void> _pruneObsoleteKeys(String groupId) async {
    final loadAllKeys = dbLoadAllGroupKeys;
    final deleteBeforeGeneration = dbDeleteGroupKeysBeforeGeneration;
    if (loadAllKeys == null || deleteBeforeGeneration == null) {
      return;
    }

    final rows = await loadAllKeys(groupId);
    if (rows.isEmpty) {
      return;
    }

    final keys = rows.map((row) => GroupKeyInfo.fromMap(row)).toList();
    final latestGeneration = keys
        .map((key) => key.keyGeneration)
        .reduce((a, b) => a > b ? a : b);
    final minKeyGenerationToKeep = minRetainedGroupKeyGeneration(
      latestGeneration,
    );
    final obsoleteKeys = keys
        .where((key) => key.keyGeneration < minKeyGenerationToKeep)
        .toList(growable: false);
    if (obsoleteKeys.isEmpty) {
      return;
    }

    await deleteBeforeGeneration(groupId, minKeyGenerationToKeep);
    for (final key in obsoleteKeys) {
      await _deleteGroupKeyMirror(key);
      await _deleteGroupKeyMaterial(key);
    }
  }

  Future<Map<String, Object?>> _toStorageRow(GroupKeyInfo key) async {
    final row = Map<String, Object?>.from(key.toMap());
    final store = groupKeyStore;
    if (store == null ||
        key.encryptedKey.isEmpty ||
        isSecureStoreReference(key.encryptedKey)) {
      return row;
    }

    final secureStoreKey = groupKeyMaterialStoreName(
      key.groupId,
      key.keyGeneration,
    );
    await store.write(secureStoreKey, key.encryptedKey);
    row['encrypted_key'] = secureStoreReferenceForKey(secureStoreKey);
    return row;
  }

  Future<GroupKeyInfo?> _groupKeyFromRow(Map<String, Object?> row) async {
    return _hydrateGroupKey(GroupKeyInfo.fromMap(row));
  }

  Future<GroupKeyInfo?> _hydrateGroupKey(GroupKeyInfo key) async {
    final store = groupKeyStore;
    if (!isSecureStoreReference(key.encryptedKey)) {
      return key;
    }

    if (store == null) {
      return null;
    }

    final hydrated = await store.read(
      secureStoreKeyFromReference(key.encryptedKey),
    );
    if (hydrated == null) {
      return null;
    }

    return GroupKeyInfo(
      groupId: key.groupId,
      keyGeneration: key.keyGeneration,
      encryptedKey: hydrated,
      createdAt: key.createdAt,
    );
  }

  Future<void> _mirrorGroupKeyForPush(GroupKeyInfo key) async {
    final store = pushSharedKeyStore;
    if (store == null) {
      return;
    }
    if (isSecureStoreReference(key.encryptedKey)) {
      return;
    }

    try {
      await store.write(
        sharedGroupPushKeyName(key.groupId, key.keyGeneration),
        key.encryptedKey,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_PUSH_KEY_MIRROR_ERROR',
        details: {
          'groupId': key.groupId.length > 8
              ? key.groupId.substring(0, 8)
              : key.groupId,
          'keyGeneration': key.keyGeneration,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _mirrorGroupMutedForPush(String groupId, bool isMuted) async {
    final store = pushSharedKeyStore;
    if (store == null) {
      return;
    }

    try {
      if (isMuted) {
        await store.write(sharedGroupMutedKeyName(groupId), '1');
      } else {
        await store.delete(sharedGroupMutedKeyName(groupId));
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_PUSH_MUTE_MIRROR_ERROR',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'isMuted': isMuted,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _deleteGroupKeyMirror(GroupKeyInfo key) async {
    final store = pushSharedKeyStore;
    if (store == null) {
      return;
    }

    try {
      await store.delete(
        sharedGroupPushKeyName(key.groupId, key.keyGeneration),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_PUSH_KEY_DELETE_MIRROR_ERROR',
        details: {
          'groupId': key.groupId.length > 8
              ? key.groupId.substring(0, 8)
              : key.groupId,
          'keyGeneration': key.keyGeneration,
          'error': e.toString(),
        },
      );
    }
  }

  Future<void> _deleteGroupKeyMaterial(GroupKeyInfo key) async {
    final store = groupKeyStore;
    if (store == null) {
      return;
    }

    await store.delete(
      groupKeyMaterialStoreName(key.groupId, key.keyGeneration),
    );
  }

  Future<void> _deletePendingKeyMaterialIfUncommitted(
    String groupId,
    int keyGeneration,
  ) async {
    final store = groupKeyStore;
    if (store == null) {
      return;
    }

    if (await getKeyByGeneration(groupId, keyGeneration) != null) {
      return;
    }

    await store.delete(groupKeyMaterialStoreName(groupId, keyGeneration));
  }
}
