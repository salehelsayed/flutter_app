import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// In-memory [GroupRepository] for integration tests.
class InMemoryGroupRepository
    implements
        GroupRepository,
        RemovedGroupMemberSnapshotRepository,
        GroupKeyRotationDraftRepository {
  final Map<String, GroupModel> _groups = {};
  final Map<String, Map<String, GroupMember>> _members = {};
  final Map<String, Map<String, GroupMember>> _removedMemberSnapshots = {};
  final Map<String, List<GroupKeyInfo>> _keys = {};
  final Map<String, GroupKeyInfo> _pendingKeyRotations = {};

  // --- Groups ---

  @override
  Future<void> saveGroup(GroupModel group) async {
    _groups[group.id] = group;
  }

  @override
  Future<List<GroupModel>> getAllGroups() async {
    final list = _groups.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    return _groups[id];
  }

  @override
  Future<void> updateGroup(GroupModel group) async {
    _groups[group.id] = group;
  }

  @override
  Future<void> deleteGroup(String id) async {
    _groups.remove(id);
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    final list = _groups.values.where((g) => !g.isArchived).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<void> archiveGroup(String id) async {
    final group = _groups[id];
    if (group != null) {
      _groups[id] = group.copyWith(
        isArchived: true,
        archivedAt: DateTime.now().toUtc(),
      );
    }
  }

  @override
  Future<void> unarchiveGroup(String id) async {
    final group = _groups[id];
    if (group != null) {
      _groups[id] = group.copyWith(isArchived: false, archivedAt: null);
    }
  }

  // --- Members ---

  @override
  Future<void> saveMember(GroupMember member) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(member.peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(member.peerId, 'peerId', peerIdRejectReason);
    }
    final duplicateRejectReason = groupMemberDuplicatePeerIdVariantRejectReason(
      _members[member.groupId]?.values ?? const <GroupMember>[],
      member,
    );
    if (duplicateRejectReason != null) {
      throw StateError(duplicateRejectReason);
    }
    _members.putIfAbsent(member.groupId, () => {});
    _members[member.groupId]![member.peerId] = member;
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    final groupMembers = _members[groupId];
    if (groupMembers == null) return [];
    final list = groupMembers.values.toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return list;
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    return _members[groupId]?[peerId];
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
    final member = _members[groupId]?[peerId];
    if (member != null) {
      _members[groupId]![peerId] = member.copyWith(role: role);
    }
  }

  @override
  Future<void> removeMember(String groupId, String peerId) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(peerId, 'peerId', peerIdRejectReason);
    }
    _members[groupId]?.remove(peerId);
  }

  @override
  Future<void> saveRemovedMemberSnapshot(
    GroupMember member, {
    required DateTime removedAt,
  }) async {
    _removedMemberSnapshots.putIfAbsent(member.groupId, () => {});
    _removedMemberSnapshots[member.groupId]![member.peerId] = member;
  }

  @override
  Future<GroupMember?> getRemovedMemberSnapshot(
    String groupId,
    String peerId,
  ) async {
    return _removedMemberSnapshots[groupId]?[peerId];
  }

  @override
  Future<void> removeAllMembers(String groupId) async {
    _members.remove(groupId);
  }

  // --- Keys ---

  @override
  Future<void> saveKey(GroupKeyInfo key) async {
    _keys.putIfAbsent(key.groupId, () => []);
    // Remove existing key with same generation if present
    _keys[key.groupId]!.removeWhere(
      (k) => k.keyGeneration == key.keyGeneration,
    );
    _keys[key.groupId]!.add(key);
    _pruneObsoleteKeys(key.groupId);
  }

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    final groupKeys = _keys[groupId];
    if (groupKeys == null || groupKeys.isEmpty) return null;
    final sorted = groupKeys.toList()
      ..sort((a, b) => b.keyGeneration.compareTo(a.keyGeneration));
    return sorted.first;
  }

  @override
  Future<GroupKeyInfo?> getKeyByGeneration(
    String groupId,
    int generation,
  ) async {
    final groupKeys = _keys[groupId];
    if (groupKeys == null) return null;
    try {
      return groupKeys.firstWhere((k) => k.keyGeneration == generation);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removeAllKeys(String groupId) async {
    _keys.remove(groupId);
    _pendingKeyRotations.remove(groupId);
  }

  @override
  Future<void> savePendingKeyRotation(GroupKeyInfo key) async {
    _pendingKeyRotations[key.groupId] = key;
  }

  @override
  Future<GroupKeyInfo?> getPendingKeyRotation(String groupId) async {
    return _pendingKeyRotations[groupId];
  }

  @override
  Future<void> clearPendingKeyRotation(
    String groupId,
    int keyGeneration,
  ) async {
    final pending = _pendingKeyRotations[groupId];
    if (pending?.keyGeneration == keyGeneration) {
      _pendingKeyRotations.remove(groupId);
    }
  }

  @override
  Future<void> clearPendingKeyRotations(String groupId) async {
    _pendingKeyRotations.remove(groupId);
  }

  int get groupCount => _groups.length;

  void _pruneObsoleteKeys(String groupId) {
    final groupKeys = _keys[groupId];
    if (groupKeys == null || groupKeys.length <= 2) {
      return;
    }

    final latestGeneration = groupKeys
        .map((key) => key.keyGeneration)
        .reduce((a, b) => a > b ? a : b);
    final minKeyGenerationToKeep = latestGeneration - 1;
    groupKeys.removeWhere((key) => key.keyGeneration < minKeyGenerationToKeep);
  }
}
