import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/group_key_info.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';
import 'group_repository.dart';

String sharedGroupPushKeyName(String groupId, int keyGeneration) =>
    'group_key:$groupId:$keyGeneration';

/// Implementation of GroupRepository using constructor-injected DB helper functions.
class GroupRepositoryImpl
    implements GroupRepository, RemovedGroupMemberSnapshotRepository {
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
  final SecureKeyStore? groupKeyStore;
  final SecureKeyStore? pushSharedKeyStore;

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
    required this.dbInsertGroupKey,
    required this.dbLoadLatestGroupKey,
    required this.dbLoadGroupKeyByGeneration,
    required this.dbDeleteAllGroupKeys,
    this.dbLoadAllGroupKeys,
    this.dbDeleteGroupKeysBeforeGeneration,
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
    await dbUpdateGroupMemberRole(groupId, peerId, role.toValue());
  }

  @override
  Future<void> removeMember(String groupId, String peerId) async {
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
    for (final row in existingKeys) {
      final key = GroupKeyInfo.fromMap(row);
      await _deleteGroupKeyMirror(key);
      await _deleteGroupKeyMaterial(key);
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

  Future<void> _pruneObsoleteKeys(String groupId) async {
    final loadAllKeys = dbLoadAllGroupKeys;
    final deleteBeforeGeneration = dbDeleteGroupKeysBeforeGeneration;
    if (loadAllKeys == null || deleteBeforeGeneration == null) {
      return;
    }

    final rows = await loadAllKeys(groupId);
    if (rows.length <= 2) {
      return;
    }

    final keys = rows.map((row) => GroupKeyInfo.fromMap(row)).toList();
    final latestGeneration = keys
        .map((key) => key.keyGeneration)
        .reduce((a, b) => a > b ? a : b);
    final minKeyGenerationToKeep = latestGeneration - 1;
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
}
