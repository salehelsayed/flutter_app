import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../models/group_key_info.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';
import 'group_repository.dart';

/// Implementation of GroupRepository using constructor-injected DB helper functions.
class GroupRepositoryImpl implements GroupRepository {
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

  // --- Key DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupKey;
  final Future<Map<String, Object?>?> Function(String groupId)
      dbLoadLatestGroupKey;
  final Future<Map<String, Object?>?> Function(String groupId, int generation)
      dbLoadGroupKeyByGeneration;
  final Future<void> Function(String groupId) dbDeleteAllGroupKeys;

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
    required this.dbInsertGroupKey,
    required this.dbLoadLatestGroupKey,
    required this.dbLoadGroupKeyByGeneration,
    required this.dbDeleteAllGroupKeys,
  });

  // --- Groups ---

  @override
  Future<void> saveGroup(GroupModel group) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_REPO_SAVE_START',
      details: {'id': group.id.length > 8 ? group.id.substring(0, 8) : group.id},
    );

    try {
      await dbInsertGroup(group.toMap());

      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_SAVE_SUCCESS',
        details: {'id': group.id.length > 8 ? group.id.substring(0, 8) : group.id},
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
  Future<void> removeAllMembers(String groupId) async {
    await dbDeleteAllGroupMembers(groupId);
  }

  // --- Keys ---

  @override
  Future<void> saveKey(GroupKeyInfo key) async {
    await dbInsertGroupKey(key.toMap());
  }

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    final row = await dbLoadLatestGroupKey(groupId);
    if (row == null) return null;
    return GroupKeyInfo.fromMap(row);
  }

  @override
  Future<GroupKeyInfo?> getKeyByGeneration(
    String groupId,
    int generation,
  ) async {
    final row = await dbLoadGroupKeyByGeneration(groupId, generation);
    if (row == null) return null;
    return GroupKeyInfo.fromMap(row);
  }

  @override
  Future<void> removeAllKeys(String groupId) async {
    await dbDeleteAllGroupKeys(groupId);
  }
}
