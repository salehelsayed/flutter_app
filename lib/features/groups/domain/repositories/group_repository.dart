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

/// Optional persistence capability for committing terminal dissolve state and
/// retiring every display-outbox row owned by that exact group atomically.
abstract interface class AtomicGroupDissolveRepository {
  Future<void> commitDissolvedGroup(GroupModel group);
}

/// Routes terminal dissolve writes through [AtomicGroupDissolveRepository]
/// when available while preserving lightweight repository compatibility.
extension GroupDissolveCommit on GroupRepository {
  Future<void> commitDissolvedGroupTerminally(GroupModel group) async {
    if (!group.isDissolved) {
      throw ArgumentError.value(
        group.isDissolved,
        'group.isDissolved',
        'must be true for a terminal dissolve commit',
      );
    }
    final repository = this;
    if (repository is AtomicGroupDissolveRepository) {
      await (repository as AtomicGroupDissolveRepository).commitDissolvedGroup(
        group,
      );
      return;
    }
    await updateGroup(group);
  }
}

/// Strict external-state retirement for a confirmed voluntary group exit.
///
/// The SQL exit intent and its exact membership/key rows are the durable retry
/// addresses for secure-store and notification cleanup. Implementations must
/// retain those rows until every external deletion succeeds, then invoke
/// [finalizeSql] while still holding their same-group mutation lock. This
/// prevents a key or projection writer from slipping between external cleanup
/// and the final intent-last SQL transaction.
abstract interface class GroupExitCleanupRepository {
  Future<T> cleanupExactVoluntaryExit<T>({
    required String groupId,
    required String selfPeerId,
    required DateTime selfJoinedAt,
    required Future<T> Function() finalizeSql,
  });
}

/// One coherent authorization view used immediately before a forwarded media
/// upload starts. The group row, complete ordered roster, and latest key
/// generation must all come from the same storage snapshot; composing this
/// value from separate repository reads would reintroduce a membership/key
/// time-of-check race.
class GroupForwardAuthorizationSnapshot {
  const GroupForwardAuthorizationSnapshot({
    required this.group,
    required this.members,
    required this.latestKeyGeneration,
  });

  final GroupModel? group;
  final List<GroupMember> members;
  final int? latestKeyGeneration;
}

/// Optional fail-closed capability for repositories that can load a coherent
/// [GroupForwardAuthorizationSnapshot]. Forward delivery must not fall back to
/// sequential [GroupRepository] reads when this capability is absent or
/// returns null.
abstract class GroupForwardAuthorizationSnapshotRepository {
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId);
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

/// Optional persistence capability for the two protected membership watermark
/// columns. Ordinary full-row metadata writes intentionally preserve these
/// fields, so real membership events must advance them through this seam.
abstract class GroupMembershipWatermarkRepository {
  Future<bool> advanceGroupMembershipWatermark({
    required String groupId,
    required DateTime eventAt,
    String? eventId,
  });
}

enum SelfRemovedShellAuthorityShape {
  absent,
  unmarkedSelfPresent,
  unmarkedSelfAbsent,
  markedSelfPresent,
  markedSelfAbsent,
}

/// Repository-neutral view of the exact SQL authority token. The opaque token
/// is deliberately handed back to compare-and-swap mutations; callers cannot
/// manufacture delete authority from a stale model or message history.
class SelfRemovedShellAuthoritySnapshot {
  const SelfRemovedShellAuthoritySnapshot({
    required this.groupId,
    required this.selfPeerId,
    required this.shape,
    required this.selfRemovedAt,
    required this.lastMembershipEventAt,
    required this.lastMembershipEventId,
    required this.selfJoinedAt,
    required this.persistenceToken,
  });

  final String groupId;
  final String selfPeerId;
  final SelfRemovedShellAuthorityShape shape;
  final DateTime? selfRemovedAt;
  final DateTime? lastMembershipEventAt;
  final String? lastMembershipEventId;
  final DateTime? selfJoinedAt;
  final Object persistenceToken;
}

enum SelfRemovalAuthorityCommitOutcome {
  committed,
  refusedStateChanged,
  refusedStaleRemoval,
}

enum SelfRemovedShellMutationOutcome {
  committed,
  refusedStateChanged,
  refusedOutstandingReferences,
  refusedMediaRemaining,
  refusedFloorMissing,
  refusedTombstoneConflict,
}

class SelfRemovedShellMediaParent {
  const SelfRemovedShellMediaParent({
    required this.messageId,
    required this.timestamp,
  });

  final String messageId;
  final DateTime timestamp;
}

class SelfRemovedShellMediaBatch {
  const SelfRemovedShellMediaBatch({
    required this.outcome,
    required this.authority,
    required this.parents,
    required this.hasOverflow,
  });

  final SelfRemovedShellMutationOutcome outcome;
  final SelfRemovedShellAuthoritySnapshot authority;
  final List<SelfRemovedShellMediaParent> parents;
  final bool hasOverflow;
}

class SelfRemovedShellFreshnessFloor {
  const SelfRemovedShellFreshnessFloor({
    required this.groupId,
    required this.selfPeerId,
    required this.selfRemovedAt,
    required this.persistenceToken,
  });

  final String groupId;
  final String selfPeerId;
  final DateTime selfRemovedAt;
  final Object persistenceToken;
}

/// Domain-level signal for an exact removed-shell authority CAS loss.
///
/// Persistence implementations translate their private database exception to
/// this type so callers can preserve the public `refusedStateChanged`
/// disposition without treating an operational store failure as a race.
class SelfRemovedShellStateChangedException implements Exception {
  const SelfRemovedShellStateChangedException();
}

enum SelfRemovedAcceptedReentryOutcome {
  committed,
  refusedMissingFloor,
  refusedStateChanged,
  refusedInvalidMaterial,
  refusedMalformedAuthority,
  refusedStaleAuthority,
  refusedKeyState,
  refusedEvidenceInvalid,
  refusedBindingCollision,
}

class SelfRemovedAcceptedReentryResult {
  const SelfRemovedAcceptedReentryResult({
    required this.outcome,
    this.acceptedAt,
  });

  final SelfRemovedAcceptedReentryOutcome outcome;
  final DateTime? acceptedAt;

  bool get committed => outcome == SelfRemovedAcceptedReentryOutcome.committed;
}

enum SelfRemovedAcceptedRollbackOutcome {
  rolledBack,
  refusedBindingMissing,
  refusedAuthorizationMismatch,
  refusedStateChanged,
  refusedEvidenceInvalid,
}

enum SelfRemovedAcceptedRetryAuthorizationOutcome {
  authorized,
  refusedBindingMissing,
  refusedAuthorizationMismatch,
  refusedStateChanged,
  refusedEvidenceInvalid,
}

class SelfRemovedAcceptedNativeRetryResult {
  const SelfRemovedAcceptedNativeRetryResult({
    required this.outcome,
    this.group,
  });

  final SelfRemovedAcceptedRetryAuthorizationOutcome outcome;
  final GroupModel? group;

  bool get joined =>
      outcome == SelfRemovedAcceptedRetryAuthorizationOutcome.authorized &&
      group != null;
}

/// Plan 321 (C3 hardened): fresh-join projection atomicity.
///
/// A fresh accepted join must never publish the group into the notification
/// projection epoch-less (the N+2 incremental mirrors expose it for the whole
/// roster loop, and the iOS NSE drops epoch-less docs). The owning repository
/// suppresses its per-write projection mirror UPSERTS for the join scope
/// (removals always pass through) and then publishes ONE complete context from
/// committed rows. Discovered via an `is`-check like the shell capability —
/// never added to [GroupRepository] (large fake-implementor population).
abstract class FreshJoinProjectionAtomicity {
  /// Runs [action] with the group's projection mirror upserts suppressed.
  /// Refcounted per groupId: overlapping scopes only release at depth zero.
  Future<T> runWithSuppressedGroupProjectionMirrors<T>(
    String groupId,
    Future<T> Function() action,
  );

  /// Publishes the group's COMPLETE notification context from committed rows
  /// (authoritative group, full roster, LATEST committed key — never a caller
  /// pinned generation). Returns true only when a context document was
  /// actually written; unsupported types and missing authority return false.
  /// Storage failures throw — the caller owns the log-and-no-op decision.
  Future<bool> projectCommittedFreshJoin(String groupId);
}

/// Optional fail-closed capability owning every durable removed-shell
/// transition and its strict terminal external cleanup.
abstract class SelfRemovedGroupShellRepository {
  Future<SelfRemovedShellAuthoritySnapshot> loadSelfRemovedShellAuthority({
    required String groupId,
    required String selfPeerId,
  });

  /// Serializes the final re-read, one idempotent native leave, and atomic B3
  /// authority commit in that order.
  Future<SelfRemovalAuthorityCommitOutcome> commitSelfRemovalAuthority({
    required String groupId,
    required String selfPeerId,
    required DateTime expectedSelfJoinedAt,
    required DateTime removalAt,
    required String removalEventId,
    required Future<void> Function() leaveNative,
  });

  Future<SelfRemovedShellMediaBatch> loadSelfRemovedShellMediaParents({
    required SelfRemovedShellAuthoritySnapshot expected,
    required int limit,
  });

  /// Strictly removes notification authorization, primary key material,
  /// generation/mute mirrors, and finally their exact SQL addresses.
  Future<SelfRemovedShellMutationOutcome> terminalizeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
  });

  Future<SelfRemovedShellFreshnessFloor> appendSelfRemovedShellFreshnessFloor({
    required SelfRemovedShellAuthoritySnapshot expected,
  });

  Future<SelfRemovedShellFreshnessFloor?> loadSelfRemovedShellFreshnessFloor(
    String groupId,
  );

  /// Atomically crosses either a marked shell or an absent retained floor into
  /// an authenticated accepted membership. The durable floor/origin and the
  /// phase-unique SQL key address precede primary secure material; the final
  /// transaction requires that exact preparation and adds the binding.
  Future<SelfRemovedAcceptedReentryResult> commitAcceptedReentry({
    required GroupModel group,
    required List<GroupMember> roster,
    required GroupKeyInfo key,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required String bindingNonce,
  });

  /// Restores the exact marked or absent-floor shape selected by the newest
  /// matching durable accepted-state binding.
  Future<SelfRemovedAcceptedRollbackOutcome> rollbackAcceptedReentry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
  });

  /// Reconstructs the newest binding matching the current accepted state and
  /// authorizes a duplicate native retry only when the pending signed tuple,
  /// self identity, and key generation still match that binding.
  Future<SelfRemovedAcceptedRetryAuthorizationOutcome>
  authorizeAcceptedReentryRetry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
  });

  /// Holds the repository's per-group coordinator across final durable
  /// binding-or-fresh qualification, exact self/group/key reads, and one
  /// duplicate native join action.
  Future<SelfRemovedAcceptedNativeRetryResult> retryAcceptedReentryNative({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
    required String expectedKeyMaterial,
    required DateTime expectedFreshMembershipAt,
    required DateTime? latestAllowedMetadataAt,
    required Future<void> Function() joinNative,
  });

  /// Exact no-floor fresh rollback. Newer group/member/key state refuses and
  /// no sequence of public destructive repository calls is used.
  Future<SelfRemovedAcceptedRollbackOutcome>
  rollbackFreshAcceptedMaterialization({
    required String groupId,
    required String selfPeerId,
    required int keyGeneration,
    required String expectedKeyMaterial,
    required DateTime expectedMembershipAt,
    required DateTime? latestAllowedMetadataAt,
  });

  Future<SelfRemovedShellMutationOutcome> purgeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
    required SelfRemovedShellFreshnessFloor floor,
    required DateTime deletedAt,
  });
}
