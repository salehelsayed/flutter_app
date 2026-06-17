import '../models/group_key_info.dart';
import '../models/group_member.dart';
import '../models/group_model.dart';

/// Finding 05 Phase 3: per-group rejoin-retry state. A value exists only for a
/// group that has failed to rejoin its topic and is being backed off.
class GroupRejoinState {
  const GroupRejoinState({required this.attemptCount, this.nextEligibleAt});

  /// How many consecutive rejoin attempts have failed for this group.
  final int attemptCount;

  /// Earliest time the next rejoin attempt is eligible; null = immediately.
  final DateTime? nextEligibleAt;
}

/// Repository interface for managing groups, members, and keys.
abstract class GroupRepository {
  // --- Groups ---

  /// Saves a group to the database. Replaces if ID already exists.
  Future<void> saveGroup(GroupModel group);

  /// Retrieves all groups, ordered by created_at DESC.
  Future<List<GroupModel>> getAllGroups();

  // --- Finding 05 Phase 3: bounded per-group rejoin retry ---

  /// Loads per-group rejoin-retry state (groupId → state) for groups that have
  /// failed to rejoin. Default empty keeps lightweight doubles compatible (no
  /// backoff — every group is attempted every pass, the prior behavior).
  Future<Map<String, GroupRejoinState>> loadGroupRejoinStates() async =>
      const {};

  /// Records a failed rejoin attempt: increments the attempt count and sets the
  /// exponential-backoff window. Default no-op.
  Future<void> recordGroupRejoinFailure(
    String groupId, {
    required DateTime nextEligibleAt,
  }) async {}

  /// Clears the rejoin-retry state for a group after a successful rejoin.
  /// Default no-op.
  Future<void> clearGroupRejoinState(String groupId) async {}

  /// Forces a stuck group's rejoin row immediately eligible (collapses its
  /// backoff window) so the next rejoin pass attempts it right away — the
  /// stuck-badge "Retry now" affordance (G2). Preserves the attempt count and
  /// the row (no auto-delete). Default no-op.
  Future<void> forceGroupRejoinEligible(String groupId) async {}

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

/// Optional repository capability (B4) for the persisted "last known device-set"
/// baseline a group member's per-device safety number is compared against.
abstract class GroupMemberDeviceSnapshotRepository {
  /// Persists/replaces [member]'s current active device set as the trusted
  /// baseline (TOFU). [savedAt] timestamps the write.
  Future<void> saveGroupMemberDeviceSnapshot(
    GroupMember member, {
    required DateTime savedAt,
  });

  /// The last-known device set for (groupId, peerId), or null if none saved yet.
  Future<List<GroupMemberDeviceIdentity>?> loadGroupMemberDeviceSnapshot(
    String groupId,
    String peerId,
  );
}

/// Optional repository capability for locally generated rotation keys that
/// have not been promoted to the committed group key set yet.
abstract class GroupKeyRotationDraftRepository {
  Future<void> savePendingKeyRotation(GroupKeyInfo key);

  Future<GroupKeyInfo?> getPendingKeyRotation(String groupId);

  Future<void> clearPendingKeyRotation(String groupId, int keyGeneration);

  Future<void> clearPendingKeyRotations(String groupId);
}
