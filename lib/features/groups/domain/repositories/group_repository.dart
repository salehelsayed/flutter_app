import '../models/group_key_info.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';

/// Repository interface for managing groups, members, and keys.
abstract class GroupRepository {
  // --- Groups ---

  /// Saves a group to the database. Replaces if ID already exists.
  Future<void> saveGroup(GroupModel group);

  /// Retrieves all groups, ordered by created_at DESC.
  Future<List<GroupModel>> getAllGroups();

  /// Retrieves a single group by ID.
  Future<GroupModel?> getGroup(String id);

  /// Updates a group in the database.
  Future<void> updateGroup(GroupModel group);

  /// Deletes a group by ID.
  Future<void> deleteGroup(String id);

  /// Retrieves only active (non-archived) groups.
  Future<List<GroupModel>> getActiveGroups();

  /// Archives a group by ID.
  Future<void> archiveGroup(String id);

  /// Unarchives a group by ID.
  Future<void> unarchiveGroup(String id);

  // --- Members ---

  /// Saves a member to the database. Replaces if (groupId, peerId) already exists.
  Future<void> saveMember(GroupMember member);

  /// Retrieves all members of a group.
  Future<List<GroupMember>> getMembers(String groupId);

  /// Retrieves a single member by group ID and peer ID.
  Future<GroupMember?> getMember(String groupId, String peerId);

  /// Updates the role of a group member.
  Future<void> updateMemberRole(String groupId, String peerId, MemberRole role);

  /// Removes a single member from a group.
  Future<void> removeMember(String groupId, String peerId);

  /// Removes all members from a group.
  Future<void> removeAllMembers(String groupId);

  // --- Keys ---

  /// Saves a group key to the database.
  Future<void> saveKey(GroupKeyInfo key);

  /// Retrieves the latest (highest generation) key for a group.
  Future<GroupKeyInfo?> getLatestKey(String groupId);

  /// Retrieves a key by group ID and generation.
  Future<GroupKeyInfo?> getKeyByGeneration(String groupId, int generation);

  /// Removes all keys for a group.
  Future<void> removeAllKeys(String groupId);
}

/// Optional repository capability for retaining removed-member verification
/// material so historical replay can still validate old signed envelopes.
abstract class RemovedGroupMemberSnapshotRepository {
  Future<void> saveRemovedMemberSnapshot(
    GroupMember member, {
    required DateTime removedAt,
  });

  Future<GroupMember?> getRemovedMemberSnapshot(String groupId, String peerId);
}
