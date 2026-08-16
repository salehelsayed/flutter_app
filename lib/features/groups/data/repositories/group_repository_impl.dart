import 'dart:async';

import 'package:flutter_app/core/database/helpers/linked_group_bootstrap_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart'
    as shell_db;
import 'package:flutter_app/core/notifications/group_reaction_notification_projection.dart';
import 'package:flutter_app/core/notifications/group_notification_reconciliation_signal.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

import '../../domain/models/group_key_info.dart';
import '../../domain/models/group_key_retention_policy.dart';
import '../../domain/models/group_member.dart';
import '../../domain/models/group_pending_broadcast.dart';
import '../../domain/models/pending_sibling_device.dart';
import '../../domain/repositories/pending_sibling_device_repository.dart';
import '../../domain/models/group_model.dart';
import '../../domain/repositories/group_pending_broadcast_repository.dart';
import '../../domain/repositories/group_repository.dart';
import '../../domain/repositories/linked_group_bootstrap_repository.dart';

String sharedGroupPushKeyName(String groupId, int keyGeneration) =>
    'group_key:$groupId:$keyGeneration';

/// 04-P0 SI-1 NSE: shared-Keychain key under which the app mirrors a group's
/// mute state ('1' when muted, deleted otherwise) so the out-of-process iOS
/// Notification Service Extension can honor mute. Read on the Swift side via
/// PushSharedKeyNames.groupMuted(groupId:).
String sharedGroupMutedKeyName(String groupId) => 'group_muted:$groupId';

bool _sameInstant(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == null && right == null;
  return left.toUtc().isAtSameMomentAs(right.toUtc());
}

bool _sameRow(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _sameGroupKey(GroupKeyInfo left, GroupKeyInfo right) =>
    left.groupId == right.groupId &&
    left.keyGeneration == right.keyGeneration &&
    left.encryptedKey == right.encryptedKey &&
    _sameInstant(left.createdAt, right.createdAt);

bool _sameMemberProjection(List<GroupMember> left, List<GroupMember> right) {
  if (left.length != right.length) return false;
  final leftRows = left.map((member) => member.toMap()).toList()
    ..sort(
      (a, b) => (a['peer_id'] as String).compareTo(b['peer_id'] as String),
    );
  final rightRows = right.map((member) => member.toMap()).toList()
    ..sort(
      (a, b) => (a['peer_id'] as String).compareTo(b['peer_id'] as String),
    );
  for (var index = 0; index < leftRows.length; index++) {
    if (!_sameRow(leftRows[index], rightRows[index])) return false;
  }
  return true;
}

/// Fail-closed authority handoff shared by each committed group mutation that
/// can change the NSE's current sender generation.
///
/// Keeping this boundary directly testable prevents a projection-without-
/// loader composition from silently committing SQL while stale shared bytes
/// remain eligible.
Future<T> runCommittedGroupSenderAuthorityHandoff<T>({
  required String groupId,
  required GroupReactionNotificationProjection? projection,
  required LoadGroupNotificationSenderAuthority? loadCommittedAuthority,
  required Future<T> Function() commitMutation,
}) async {
  if (projection == null) return commitMutation();
  if (loadCommittedAuthority == null) {
    throw StateError(
      'group sender-authority projection requires committed authority readback',
    );
  }
  await projection.retireGroupSenderAuthority(groupId);
  final result = await commitMutation();
  final authority = await loadCommittedAuthority(groupId);
  await projection.replaceGroupSenderAuthority(groupId, authority);
  return result;
}

/// Implementation of GroupRepository using constructor-injected DB helper functions.
class GroupRepositoryImpl
    implements
        GroupRepository,
        GroupForwardAuthorizationSnapshotRepository,
        RemovedGroupMemberSnapshotRepository,
        GroupMemberDeviceSnapshotRepository,
        PendingSiblingDeviceRepository,
        GroupKeyRotationDraftRepository,
        GroupMembershipWatermarkRepository,
        AtomicGroupDissolveRepository,
        AtomicProtectedGroupDissolveRepository,
        AtomicProtectedGroupKeyAuthorityRepository,
        AtomicProtectedGroupMetadataAuthorityRepository,
        GroupExitCleanupRepository,
        SelfRemovedGroupShellRepository,
        FreshJoinProjectionAtomicity,
        LinkedGroupBootstrapRepository,
        LinkedGroupBootstrapIntentGuard {
  // --- Group DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAllGroups;
  final Future<Map<String, Object?>?> Function(String id) dbLoadGroup;
  final Future<void> Function(Map<String, Object?> row) dbUpdateGroup;
  final Future<void> Function({
    required Map<String, Object?> expectedGroupRow,
    required List<Map<String, Object?>> expectedMemberRows,
    required int expectedLatestKeyGeneration,
    required Map<String, Object?> groupRow,
    required List<Map<String, Object?>> pendingBroadcastRows,
    required String authorityPreparedSourcePeerId,
    required String authorityPreparedSourceEventId,
    required String authorityPreparedSourceTimestamp,
    required Map<String, Object?> authorityPreparedPayload,
  })?
  dbCommitProtectedGroupMetadataAuthorityFn;
  final Future<void> Function(Map<String, Object?> row)? dbCommitDissolvedGroup;
  final Future<void> Function({
    required Map<String, Object?> groupRow,
    required List<Map<String, Object?>> expectedBroadcastRows,
    required String authorityCompleteSourcePeerId,
    required String authorityCompleteSourceEventId,
    required String authorityCompleteSourceTimestamp,
    required Map<String, Object?> authorityCompletePayload,
  })?
  dbCommitProtectedDissolvedGroup;
  final Future<void> Function(String id) dbDeleteGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadActiveGroups;
  final Future<void> Function(String id) dbArchiveGroup;
  final Future<void> Function(String id) dbUnarchiveGroup;
  final Future<bool> Function({
    required String groupId,
    required String eventAt,
    required String? eventId,
  })?
  dbAdvanceGroupMembershipWatermark;
  final Future<
    ({
      Map<String, Object?>? groupRow,
      List<Map<String, Object?>> memberRows,
      int? latestKeyGeneration,
    })
  >
  Function(String groupId)?
  dbLoadGroupForwardAuthorizationSnapshot;

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
  final Future<LinkedGroupBootstrapDbDisposition> Function({
    required Map<String, Object?> expectedGroup,
    required List<Map<String, Object?>> expectedMembers,
    required Map<String, Object?> expectedSelfMember,
    required int expectedLatestKeyGeneration,
    required String expectedLatestKeyCreatedAt,
    required Map<String, Object?> updatedSelfMember,
    required Map<String, Object?> pendingDevice,
    required Map<String, Object?> pendingBroadcast,
    required String authorityGenesisSourcePeerId,
    required String authorityGenesisSourceEventId,
    required String authorityGenesisSourceTimestamp,
    required Map<String, Object?> authorityGenesisPayload,
  })?
  dbCommitLinkedGroupBootstrapAuthoringFn;
  final Future<bool> Function({
    required Map<String, Object?> expectedDevice,
    required Map<String, Object?> expectedBroadcast,
  })?
  dbCompleteLinkedGroupBootstrapCustodyFn;
  final Future<LinkedGroupBootstrapMaterializationDbDisposition> Function({
    required Map<String, Object?> groupRow,
    required List<Map<String, Object?>> memberRows,
    required Map<String, Object?> keyRow,
    required String authorityGenesisSourcePeerId,
    required String authorityGenesisSourceEventId,
    required String authorityGenesisSourceTimestamp,
    required Map<String, Object?> authorityGenesisPayload,
  })?
  dbCommitLinkedGroupBootstrapMaterializationFn;
  final Future<bool> Function({
    required String groupId,
    required String transportPeerId,
  })?
  dbHasLinkedGroupBootstrapIntentFn;

  // --- Key DB helpers ---
  final Future<void> Function(Map<String, Object?> row) dbInsertGroupKey;
  final Future<void> Function({
    required Map<String, Object?> keyRow,
    required String authorityCompleteSourcePeerId,
    required String authorityCompleteSourceEventId,
    required String authorityCompleteSourceTimestamp,
    required Map<String, Object?> authorityCompletePayload,
  })?
  dbCommitProtectedGroupKeyAuthority;
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
  final GroupReactionNotificationProjection? groupReactionProjection;
  final Future<bool> Function(String groupId)? dbHasGroupExitCleanupPending;
  final bool selfRemovedShellAuthorityEnabled;
  final Future<shell_db.SelfRemovedGroupShellAuthoritySnapshot> Function({
    required String groupId,
    required String selfPeerId,
  })?
  dbLoadSelfRemovedGroupShellAuthority;
  final Future<shell_db.SelfRemovalAuthorityCommitResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
    required DateTime removalAt,
    required String removalEventId,
  })?
  dbCommitSelfRemovalAuthorityFn;
  final Future<shell_db.SelfRemovedGroupKeyReferenceLoadResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
  })?
  dbLoadRawSelfRemovedGroupKeyReferencesFn;
  final Future<shell_db.SelfRemovedGroupShellMutationResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
    required List<shell_db.SelfRemovedGroupKeyReference> expectedReferences,
  })?
  dbFinalizeSelfRemovedGroupKeyReferencesFn;
  final Future<shell_db.SelfRemovedGroupMediaParentLoadResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
    required int limit,
  })?
  dbLoadSelfRemovedGroupMediaParentsFn;
  final Future<shell_db.SelfRemovedGroupFreshnessFloorAppendResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
  })?
  dbAppendSelfRemovedGroupFreshnessFloorFn;
  final Future<shell_db.SelfRemovedGroupFreshnessFloor?> Function(
    String groupId,
  )?
  dbLoadSelfRemovedGroupFreshnessFloorFn;
  final Future<shell_db.SelfRemovedGroupAcceptedReentryPreparationResult>
  Function({
    required Map<String, Object?> groupRow,
    required List<Map<String, Object?>> rosterRows,
    required Map<String, Object?> stagedKeyRow,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required String bindingNonce,
  })?
  dbPrepareSelfRemovedGroupAcceptedReentryFn;
  final Future<shell_db.SelfRemovedGroupAcceptedReentryStageResult> Function({
    required shell_db.SelfRemovedGroupAcceptedReentryPreparation preparation,
    required Map<String, Object?> stagedKeyRow,
  })?
  dbStageSelfRemovedGroupAcceptedReentryKeyFn;
  final Future<shell_db.SelfRemovedGroupAcceptedReentryResult> Function({
    required shell_db.SelfRemovedGroupAcceptedReentryPreparation preparation,
    required Map<String, Object?> groupRow,
    required List<Map<String, Object?>> rosterRows,
    required Map<String, Object?> stagedKeyRow,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required String bindingNonce,
  })?
  dbCommitSelfRemovedGroupAcceptedReentryFn;
  final Future<shell_db.SelfRemovedGroupAcceptedReentryStageResult> Function({
    required shell_db.SelfRemovedGroupAcceptedReentryPreparation preparation,
    required Map<String, Object?> stagedKeyRow,
  })?
  dbFinalizeSelfRemovedGroupAcceptedReentryStagingFn;
  final Future<shell_db.SelfRemovedGroupAcceptedReentryStageResult> Function({
    required String groupId,
    required String selfPeerId,
    required shell_db.SelfRemovedGroupAcceptedReentryBinding binding,
  })?
  dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn;
  final Future<shell_db.SelfRemovedGroupAcceptedRollbackResult> Function({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required shell_db.SelfRemovedGroupAcceptedRollbackQualification
    qualification,
  })?
  dbRollbackSelfRemovedGroupAcceptedReentryFn;
  final Future<shell_db.SelfRemovedGroupAcceptedRollbackQualificationResult>
  Function({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
  })?
  dbQualifySelfRemovedGroupAcceptedRollbackFn;
  final Future<shell_db.SelfRemovedGroupFreshAcceptedRollbackPreparationResult>
  Function({
    required String groupId,
    required String selfPeerId,
    required int keyGeneration,
    required DateTime expectedMembershipAt,
    required DateTime? expectedMetadataAt,
  })?
  dbPrepareFreshAcceptedMaterializationRollbackFn;
  final Future<shell_db.SelfRemovedGroupAcceptedRollbackResult> Function({
    required shell_db.SelfRemovedGroupFreshAcceptedRollbackPreparation
    preparation,
  })?
  dbCommitFreshAcceptedMaterializationRollbackFn;
  final Future<shell_db.SelfRemovedGroupAcceptedRetryAuthorizationDisposition>
  Function({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
  })?
  dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn;
  final Future<shell_db.SelfRemovedGroupShellMutationResult> Function({
    required shell_db.SelfRemovedGroupShellAuthoritySnapshot expected,
    required shell_db.SelfRemovedGroupFreshnessFloor floor,
    required DateTime deletedAt,
  })?
  dbPurgeSelfRemovedGroupShellFn;

  // Finding 05 Phase 3: bounded per-group rejoin retry state.
  final Future<List<Map<String, Object?>>> Function()?
  dbLoadGroupRejoinStatesFn;
  final Future<void> Function(String groupId, {required int nextEligibleAtMs})?
  dbRecordGroupRejoinFailureFn;
  final Future<void> Function(String groupId)? dbClearGroupRejoinStateFn;
  final Future<void> Function(String groupId)? dbForceGroupRejoinEligibleFn;

  final Map<String, GroupKeyInfo> _pendingKeyRotationFallback = {};
  final Map<String, Future<void>> _groupMutationTails = {};
  LoadGroupNotificationSenderAuthority? _loadGroupNotificationSenderAuthority;
  bool _groupNotificationSenderAuthorityHandoffConfigured = false;

  GroupRepositoryImpl({
    required this.dbInsertGroup,
    required this.dbLoadAllGroups,
    required this.dbLoadGroup,
    required this.dbUpdateGroup,
    this.dbCommitProtectedGroupMetadataAuthorityFn,
    this.dbCommitDissolvedGroup,
    this.dbCommitProtectedDissolvedGroup,
    required this.dbDeleteGroup,
    required this.dbLoadActiveGroups,
    required this.dbArchiveGroup,
    required this.dbUnarchiveGroup,
    this.dbAdvanceGroupMembershipWatermark,
    this.dbLoadGroupForwardAuthorizationSnapshot,
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
    this.dbCommitLinkedGroupBootstrapAuthoringFn,
    this.dbCompleteLinkedGroupBootstrapCustodyFn,
    this.dbCommitLinkedGroupBootstrapMaterializationFn,
    this.dbHasLinkedGroupBootstrapIntentFn,
    this.dbLoadGroupRejoinStatesFn,
    this.dbRecordGroupRejoinFailureFn,
    this.dbClearGroupRejoinStateFn,
    this.dbForceGroupRejoinEligibleFn,
    required this.dbInsertGroupKey,
    this.dbCommitProtectedGroupKeyAuthority,
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
    this.groupReactionProjection,
    this.dbHasGroupExitCleanupPending,
    this.selfRemovedShellAuthorityEnabled = false,
    this.dbLoadSelfRemovedGroupShellAuthority,
    this.dbCommitSelfRemovalAuthorityFn,
    this.dbLoadRawSelfRemovedGroupKeyReferencesFn,
    this.dbFinalizeSelfRemovedGroupKeyReferencesFn,
    this.dbLoadSelfRemovedGroupMediaParentsFn,
    this.dbAppendSelfRemovedGroupFreshnessFloorFn,
    this.dbLoadSelfRemovedGroupFreshnessFloorFn,
    this.dbPrepareSelfRemovedGroupAcceptedReentryFn,
    this.dbStageSelfRemovedGroupAcceptedReentryKeyFn,
    this.dbCommitSelfRemovedGroupAcceptedReentryFn,
    this.dbFinalizeSelfRemovedGroupAcceptedReentryStagingFn,
    this.dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn,
    this.dbRollbackSelfRemovedGroupAcceptedReentryFn,
    this.dbQualifySelfRemovedGroupAcceptedRollbackFn,
    this.dbPrepareFreshAcceptedMaterializationRollbackFn,
    this.dbCommitFreshAcceptedMaterializationRollbackFn,
    this.dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn,
    this.dbPurgeSelfRemovedGroupShellFn,
  });

  void setGroupNotificationSenderAuthorityLoader(
    LoadGroupNotificationSenderAuthority? loader,
  ) {
    _groupNotificationSenderAuthorityHandoffConfigured = true;
    _loadGroupNotificationSenderAuthority = loader;
  }

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
      await _runGroupSenderAuthorityMutation(group.id, () async {
        await dbInsertGroup(group.toMap());
        await _projectAuthoritativeGroup(group.id);
      });
      emitGroupNotificationReconciliationSignal(group.id);

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
    await _runGroupMutation(group.id, () async {
      await dbUpdateGroup(group.toMap());
      final authoritative = await _projectAuthoritativeGroup(group.id);
      if (authoritative != null && authoritative.selfRemovedAt == null) {
        // 04-P0 SI-1 NSE: keep the shared-Keychain mute projection in sync so
        // the iOS NSE honors mute.
        await _mirrorGroupMutedForPush(authoritative.id, authoritative.isMuted);
      }
    });
    emitGroupNotificationReconciliationSignal(group.id);
  }

  @override
  Future<void> commitProtectedGroupMetadataAuthority({
    required GroupModel expectedGroup,
    required List<GroupMember> expectedMembers,
    required int expectedLatestKeyGeneration,
    required GroupModel group,
    required List<GroupPendingBroadcast> pendingBroadcasts,
    required GroupPendingBroadcastAuthorityFact authorityPrepared,
  }) async {
    final commit = dbCommitProtectedGroupMetadataAuthorityFn;
    if (commit == null) {
      throw StateError('protected metadata atomic persistence is unavailable');
    }
    if (expectedGroup.id != group.id ||
        expectedMembers.any((member) => member.groupId != group.id) ||
        pendingBroadcasts.any((broadcast) => broadcast.groupId != group.id)) {
      throw ArgumentError('invalid protected metadata authority');
    }
    await _runGroupMutation(group.id, () async {
      await commit(
        expectedGroupRow: expectedGroup.toMap(),
        expectedMemberRows: expectedMembers
            .map((member) => member.toMap())
            .toList(growable: false),
        expectedLatestKeyGeneration: expectedLatestKeyGeneration,
        groupRow: group.toMap(),
        pendingBroadcastRows: pendingBroadcasts
            .map((broadcast) => broadcast.toMap())
            .toList(growable: false),
        authorityPreparedSourcePeerId: authorityPrepared.sourcePeerId,
        authorityPreparedSourceEventId: authorityPrepared.sourceEventId,
        authorityPreparedSourceTimestamp: authorityPrepared.sourceTimestamp,
        authorityPreparedPayload: authorityPrepared.payload,
      );

      // Durable authority is now PREPARED. Projection mirrors are derived state
      // and must not turn the committed transaction into a false authoring
      // failure; authenticated recovery still owns strict native sync and
      // COMPLETE.
      try {
        final authoritative = await _projectAuthoritativeGroup(group.id);
        if (authoritative != null && authoritative.selfRemovedAt == null) {
          await _mirrorGroupMutedForPush(
            authoritative.id,
            authoritative.isMuted,
          );
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'GROUP_REPO_PROTECTED_METADATA_PROJECTION_DEFERRED',
          details: {'groupId': group.id, 'error': error.toString()},
        );
      }
    });
    emitGroupNotificationReconciliationSignal(group.id);
  }

  @override
  Future<void> commitDissolvedGroup(GroupModel group) async {
    if (!group.isDissolved) {
      throw ArgumentError.value(
        group.isDissolved,
        'group.isDissolved',
        'must be true for a terminal dissolve commit',
      );
    }
    await _runGroupSenderAuthorityMutation(group.id, () async {
      final commit = dbCommitDissolvedGroup;
      if (commit == null) {
        // Compatibility for focused repositories without the v106 outbox.
        // Production injects the atomic dissolved-row + exact-group cleanup
        // primitive through [dbCommitDissolvedGroup].
        await dbUpdateGroup(group.toMap());
      } else {
        await commit(group.toMap());
      }
      final authoritative = await _projectAuthoritativeGroup(group.id);
      if (authoritative != null && authoritative.selfRemovedAt == null) {
        await _mirrorGroupMutedForPush(authoritative.id, authoritative.isMuted);
      }
    });
    emitGroupNotificationReconciliationSignal(group.id);
  }

  @override
  Future<void> commitProtectedGroupDissolve({
    required GroupModel group,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
    required List<GroupPendingBroadcast> expectedBroadcasts,
  }) async {
    if (!group.isDissolved) {
      throw ArgumentError.value(
        group.isDissolved,
        'group.isDissolved',
        'must be true for a protected terminal dissolve commit',
      );
    }
    final commit = dbCommitProtectedDissolvedGroup;
    if (commit == null) {
      throw StateError('protected dissolve atomic persistence is unavailable');
    }
    await _runGroupSenderAuthorityMutation(group.id, () async {
      await commit(
        groupRow: group.toMap(),
        expectedBroadcastRows: expectedBroadcasts
            .map((broadcast) => broadcast.toMap())
            .toList(growable: false),
        authorityCompleteSourcePeerId: authorityComplete.sourcePeerId,
        authorityCompleteSourceEventId: authorityComplete.sourceEventId,
        authorityCompleteSourceTimestamp: authorityComplete.sourceTimestamp,
        authorityCompletePayload: authorityComplete.payload,
      );
      final authoritative = await _projectAuthoritativeGroup(group.id);
      if (authoritative != null && authoritative.selfRemovedAt == null) {
        await _mirrorGroupMutedForPush(authoritative.id, authoritative.isMuted);
      }
    });
    emitGroupNotificationReconciliationSignal(group.id);
  }

  @override
  Future<void> deleteGroup(String id) async {
    await _runGroupSenderAuthorityMutation(id, () async {
      final group = await _loadGroupModel(id);
      if (group?.selfRemovedAt != null) {
        throw StateError(
          'A marked removed-member shell requires terminal cleanup.',
        );
      }
      await dbDeleteGroup(id);
      await groupReactionProjection?.removeGroup(id);
    });
    emitGroupNotificationReconciliationSignal(id);
  }

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    final rows = await dbLoadActiveGroups();
    return rows.map((row) => GroupModel.fromMap(row)).toList();
  }

  @override
  Future<void> archiveGroup(String id) async {
    await _runGroupMutation(id, () async {
      await _requireOrdinaryGroupAuthority(id);
      await dbArchiveGroup(id);
      await _mirrorGroupContextForPush(id);
    });
    emitGroupNotificationReconciliationSignal(id);
  }

  @override
  Future<void> unarchiveGroup(String id) async {
    await _runGroupMutation(id, () async {
      await _requireOrdinaryGroupAuthority(id);
      await dbUnarchiveGroup(id);
      await _mirrorGroupContextForPush(id);
    });
    emitGroupNotificationReconciliationSignal(id);
  }

  @override
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId) async {
    final load = dbLoadGroupForwardAuthorizationSnapshot;
    if (load == null) return null;
    final rows = await load(groupId);
    return GroupForwardAuthorizationSnapshot(
      group: rows.groupRow == null ? null : GroupModel.fromMap(rows.groupRow!),
      members: List<GroupMember>.unmodifiable(
        rows.memberRows.map(GroupMember.fromMap),
      ),
      latestKeyGeneration: rows.latestKeyGeneration,
    );
  }

  @override
  Future<bool> advanceGroupMembershipWatermark({
    required String groupId,
    required DateTime eventAt,
    String? eventId,
  }) {
    final advance = dbAdvanceGroupMembershipWatermark;
    if (advance == null) return Future<bool>.value(false);
    return _runGroupSenderAuthorityMutation(
      groupId,
      () => advance(
        groupId: groupId,
        eventAt: eventAt.toUtc().toIso8601String(),
        eventId: eventId,
      ),
    );
  }

  @override
  Future<SelfRemovedShellAuthoritySnapshot> loadSelfRemovedShellAuthority({
    required String groupId,
    required String selfPeerId,
  }) async {
    final load = dbLoadSelfRemovedGroupShellAuthority;
    if (load == null) {
      throw StateError('Removed-shell persistence capability is unavailable.');
    }
    return _wrapShellAuthority(
      await load(groupId: groupId, selfPeerId: selfPeerId),
    );
  }

  @override
  Future<SelfRemovalAuthorityCommitOutcome> commitSelfRemovalAuthority({
    required String groupId,
    required String selfPeerId,
    required DateTime expectedSelfJoinedAt,
    required DateTime removalAt,
    required String removalEventId,
    required Future<void> Function() leaveNative,
  }) async {
    final load = dbLoadSelfRemovedGroupShellAuthority;
    final commit = dbCommitSelfRemovalAuthorityFn;
    if (load == null || commit == null) {
      throw StateError('Removed-shell persistence capability is unavailable.');
    }
    final outcome = await _runGroupSenderAuthorityMutation(groupId, () async {
      final expected = await load(groupId: groupId, selfPeerId: selfPeerId);
      if (expected.shape !=
              shell_db
                  .SelfRemovedGroupShellAuthorityShape
                  .unmarkedSelfPresent ||
          expected.selfJoinedAt == null ||
          !expected.selfJoinedAt!.toUtc().isAtSameMomentAs(
            expectedSelfJoinedAt.toUtc(),
          )) {
        return SelfRemovalAuthorityCommitOutcome.refusedStateChanged;
      }
      if (_isStaleRemovalAuthority(
        removalAt: removalAt,
        removalEventId: removalEventId,
        lastAt: expected.lastMembershipEventAt,
        lastEventId: expected.lastMembershipEventId,
      )) {
        return SelfRemovalAuthorityCommitOutcome.refusedStaleRemoval;
      }
      // Native leave is intentionally inside the repository mutation unit.
      // SQL remains unchanged when this throws.
      await leaveNative();
      final result = await commit(
        expected: expected,
        removalAt: removalAt.toUtc(),
        removalEventId: removalEventId,
      );
      return _mapCommitOutcome(result.disposition);
    });
    if (outcome == SelfRemovalAuthorityCommitOutcome.committed) {
      emitGroupNotificationReconciliationSignal(groupId);
    }
    return outcome;
  }

  @override
  Future<SelfRemovedShellMediaBatch> loadSelfRemovedShellMediaParents({
    required SelfRemovedShellAuthoritySnapshot expected,
    required int limit,
  }) async {
    final load = dbLoadSelfRemovedGroupMediaParentsFn;
    if (load == null) {
      throw StateError('Removed-shell media capability is unavailable.');
    }
    final result = await load(
      expected: _unwrapShellAuthority(expected),
      limit: limit,
    );
    return SelfRemovedShellMediaBatch(
      outcome: _mapMutationOutcome(result.disposition),
      authority: _wrapShellAuthority(result.authority),
      parents: result.batch.parents
          .map(
            (parent) => SelfRemovedShellMediaParent(
              messageId: parent.messageId,
              timestamp: parent.timestamp,
            ),
          )
          .toList(growable: false),
      hasOverflow: result.batch.hasOverflow,
    );
  }

  @override
  Future<SelfRemovedShellMutationOutcome> terminalizeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    final loadReferences = dbLoadRawSelfRemovedGroupKeyReferencesFn;
    final finalizeReferences = dbFinalizeSelfRemovedGroupKeyReferencesFn;
    if (loadReferences == null || finalizeReferences == null) {
      throw StateError('Removed-shell terminal capability is unavailable.');
    }
    return _runGroupSenderAuthorityMutation(expected.groupId, () async {
      final rawExpected = _unwrapShellAuthority(expected);
      final loaded = await loadReferences(expected: rawExpected);
      if (!loaded.loaded) return _mapMutationOutcome(loaded.disposition);

      // Fail closed in authorization order. Unlike ordinary mirror cleanup,
      // none of these terminal deletions may swallow an error.
      await groupReactionProjection?.removeGroupStrict(expected.groupId);
      for (final reference in loaded.references) {
        if (isSecureStoreReference(reference.encryptedKeyReference)) {
          final primary = groupKeyStore;
          if (primary == null) {
            throw StateError('Primary group-key store is unavailable.');
          }
          await primary.delete(
            secureStoreKeyFromReference(reference.encryptedKeyReference),
          );
        }
      }
      final mirror = pushSharedKeyStore;
      if (mirror != null) {
        for (final reference in loaded.references) {
          await mirror.delete(
            sharedGroupPushKeyName(reference.groupId, reference.keyGeneration),
          );
        }
        await mirror.delete(sharedGroupMutedKeyName(expected.groupId));
      }
      final finalized = await finalizeReferences(
        expected: rawExpected,
        expectedReferences: loaded.references,
      );
      return _mapMutationOutcome(finalized.disposition);
    });
  }

  @override
  Future<SelfRemovedShellFreshnessFloor> appendSelfRemovedShellFreshnessFloor({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    final append = dbAppendSelfRemovedGroupFreshnessFloorFn;
    if (append == null) {
      throw StateError('Removed-shell freshness-floor capability unavailable.');
    }
    try {
      final result = await _runGroupMutation(
        expected.groupId,
        () => append(expected: _unwrapShellAuthority(expected)),
      );
      return _wrapFreshnessFloor(result.floor);
    } on shell_db.SelfRemovedGroupShellStateChangedException {
      throw const SelfRemovedShellStateChangedException();
    }
  }

  @override
  Future<SelfRemovedShellFreshnessFloor?> loadSelfRemovedShellFreshnessFloor(
    String groupId,
  ) async {
    final load = dbLoadSelfRemovedGroupFreshnessFloorFn;
    if (load == null) {
      throw StateError('Removed-shell freshness-floor capability unavailable.');
    }
    final floor = await load(groupId);
    return floor == null ? null : _wrapFreshnessFloor(floor);
  }

  @override
  Future<SelfRemovedAcceptedReentryResult> commitAcceptedReentry({
    required GroupModel group,
    required List<GroupMember> roster,
    required GroupKeyInfo key,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required String bindingNonce,
  }) async {
    final prepare = dbPrepareSelfRemovedGroupAcceptedReentryFn;
    final stage = dbStageSelfRemovedGroupAcceptedReentryKeyFn;
    final commit = dbCommitSelfRemovedGroupAcceptedReentryFn;
    final rollback = dbRollbackSelfRemovedGroupAcceptedReentryFn;
    final qualifyRollback = dbQualifySelfRemovedGroupAcceptedRollbackFn;
    final finalizeStaging = dbFinalizeSelfRemovedGroupAcceptedReentryStagingFn;
    final finalizeRollback = dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn;
    if (prepare == null ||
        stage == null ||
        commit == null ||
        rollback == null ||
        qualifyRollback == null ||
        finalizeStaging == null ||
        finalizeRollback == null) {
      throw StateError('Accepted removed-shell capability is unavailable.');
    }
    if (group.id != key.groupId ||
        roster.any((member) => member.groupId != group.id)) {
      return const SelfRemovedAcceptedReentryResult(
        outcome: SelfRemovedAcceptedReentryOutcome.refusedInvalidMaterial,
      );
    }

    return _runGroupSenderAuthorityMutation(group.id, () async {
      final staged = _acceptedStorageRowAddress(
        key,
        bindingNonce: bindingNonce,
      );
      shell_db.SelfRemovedGroupAcceptedReentryPreparation? preparation;
      var addressStaged = false;
      var committed = false;
      try {
        final prepared = await prepare(
          groupRow: group.toMap(),
          rosterRows: roster.map((member) => member.toMap()).toList(),
          stagedKeyRow: staged.row,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          signedMembershipWatermark: signedMembershipWatermark,
          signedIssuedAt: signedIssuedAt,
          bindingNonce: bindingNonce,
        );
        if (!prepared.prepared) {
          return SelfRemovedAcceptedReentryResult(
            outcome: _mapAcceptedReentryOutcome(prepared.disposition),
          );
        }
        preparation = prepared.preparation!;

        // The durable floor/origin now precede every destructive boundary.
        // Retire old authority strictly while its SQL addresses remain the
        // retry enumeration, then atomically replace them with the accepted
        // address before primary material is written.
        await groupReactionProjection?.removeGroupStrict(group.id);
        await _terminalizeAcceptedPriorMaterial(
          groupId: group.id,
          references: preparation.retiringKeyReferences,
        );
        final stagedResult = await stage(
          preparation: preparation,
          stagedKeyRow: staged.row,
        );
        if (!stagedResult.staged) {
          return SelfRemovedAcceptedReentryResult(
            outcome: _mapAcceptedReentryOutcome(stagedResult.disposition),
          );
        }
        addressStaged = true;
        await _writeOwnedAcceptedStaging(staged);

        final result = await commit(
          preparation: preparation,
          groupRow: group.toMap(),
          rosterRows: roster.map((member) => member.toMap()).toList(),
          stagedKeyRow: staged.row,
          selfPeerId: selfPeerId,
          authorizationId: authorizationId,
          signedMembershipWatermark: signedMembershipWatermark,
          signedIssuedAt: signedIssuedAt,
          bindingNonce: bindingNonce,
        );
        if (!result.committed) {
          await _purgePreparedAcceptedStaging(
            groupId: group.id,
            staged: staged,
            preparation: preparation,
            finalize: finalizeStaging,
          );
          addressStaged = false;
          return SelfRemovedAcceptedReentryResult(
            outcome: _mapAcceptedReentryOutcome(result.disposition),
          );
        }
        committed = true;
        await _projectAcceptedReentry(
          groupId: group.id,
          keyGeneration: key.keyGeneration,
        );
        return SelfRemovedAcceptedReentryResult(
          outcome: SelfRemovedAcceptedReentryOutcome.committed,
          acceptedAt: result.acceptedAt,
        );
      } catch (_) {
        // A derived projection failure must not let native join observe a
        // partially exposed accepted state. Use the durable authorization
        // binding to restore the exact prior shape before surfacing failure.
        if (committed) {
          try {
            final qualified = await qualifyRollback(
              groupId: group.id,
              selfPeerId: selfPeerId,
              authorizationId: authorizationId,
            );
            final qualification = qualified.qualification;
            if (!qualified.qualified || qualification == null) {
              rethrow;
            }
            // Never cross back to marked/absent while accepted notification
            // authorization may remain. If strict removal fails, preserve the
            // committed accepted DB/key/binding as the only safe retry owner.
            await groupReactionProjection?.removeGroupStrict(group.id);
            final restored = await rollback(
              groupId: group.id,
              selfPeerId: selfPeerId,
              authorizationId: authorizationId,
              qualification: qualification,
            );
            if (restored.rolledBack) {
              await _deleteAcceptedBindingMaterial(
                groupId: group.id,
                binding: restored.binding,
              );
              final binding = restored.binding;
              if (binding == null) {
                throw StateError(
                  'Accepted rollback did not return its key address.',
                );
              }
              final finalized = await finalizeRollback(
                groupId: group.id,
                selfPeerId: selfPeerId,
                binding: binding,
              );
              if (!finalized.staged) {
                throw StateError(
                  'Accepted rollback key address changed before finalize.',
                );
              }
            }
          } catch (_) {
            // Preserve the original failure. The durable binding remains the
            // retry address when exact rollback could not finish here.
          }
        } else if (addressStaged && preparation != null) {
          try {
            await _purgePreparedAcceptedStaging(
              groupId: group.id,
              staged: staged,
              preparation: preparation,
              finalize: finalizeStaging,
            );
          } catch (_) {
            // Preserve the original fault. The SQL address remains the
            // marker/floor-bound retry enumeration if cleanup cannot finish.
          }
        }
        rethrow;
      }
    });
  }

  @override
  Future<SelfRemovedAcceptedRollbackOutcome> rollbackAcceptedReentry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
  }) async {
    final rollback = dbRollbackSelfRemovedGroupAcceptedReentryFn;
    final qualify = dbQualifySelfRemovedGroupAcceptedRollbackFn;
    final finalizeRollback = dbFinalizeSelfRemovedGroupAcceptedRollbackKeyFn;
    if (rollback == null || qualify == null || finalizeRollback == null) {
      throw StateError('Accepted removed-shell rollback is unavailable.');
    }
    return _runGroupSenderAuthorityMutation(groupId, () async {
      final qualified = await qualify(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
      );
      final qualification = qualified.qualification;
      if (!qualified.qualified || qualification == null) {
        return _mapAcceptedRollbackQualificationOutcome(qualified.disposition);
      }
      // Revoke recipient-owned notification authority before changing the DB
      // back to a marked or absent shape. Failure leaves accepted SQL and its
      // secure key address intact for an exact retry.
      await groupReactionProjection?.removeGroupStrict(groupId);
      final result = await rollback(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        qualification: qualification,
      );
      if (result.rolledBack) {
        await _deleteAcceptedBindingMaterial(
          groupId: groupId,
          binding: result.binding,
        );
        final binding = result.binding;
        if (binding == null) {
          throw StateError('Accepted rollback did not return its key address.');
        }
        final finalized = await finalizeRollback(
          groupId: groupId,
          selfPeerId: selfPeerId,
          binding: binding,
        );
        if (!finalized.staged) {
          throw StateError(
            'Accepted rollback key address changed before finalize.',
          );
        }
      } else {
        // The coordinator excludes repository writers between qualification
        // and CAS. A lower-level CAS refusal therefore signals out-of-band
        // state change; restore projection from the surviving accepted state.
        try {
          final currentKey = await dbLoadLatestGroupKey(groupId);
          if (currentKey != null) {
            await _projectAcceptedReentry(
              groupId: groupId,
              keyGeneration: GroupKeyInfo.fromMap(currentKey).keyGeneration,
            );
          }
        } catch (_) {
          // Preserve the exact refusal. A later authoritative backfill can
          // retry projection if the out-of-band writer also damaged material.
        }
      }
      return _mapAcceptedRollbackOutcome(result.disposition);
    });
  }

  @override
  Future<SelfRemovedAcceptedRetryAuthorizationOutcome>
  authorizeAcceptedReentryRetry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
    required String signedMembershipWatermark,
    required String signedIssuedAt,
    required int keyGeneration,
  }) async {
    final authorize = dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn;
    if (authorize == null) {
      throw StateError(
        'Accepted removed-shell retry authorization is unavailable.',
      );
    }
    return _runGroupMutation(groupId, () async {
      final result = await authorize(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        signedMembershipWatermark: signedMembershipWatermark,
        signedIssuedAt: signedIssuedAt,
        keyGeneration: keyGeneration,
      );
      return _mapAcceptedRetryAuthorizationOutcome(result);
    });
  }

  @override
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
  }) async {
    final authorize = dbAuthorizeSelfRemovedGroupAcceptedReentryRetryFn;
    final loadAuthority = dbLoadSelfRemovedGroupShellAuthority;
    final loadFloor = dbLoadSelfRemovedGroupFreshnessFloorFn;
    if (authorize == null || loadAuthority == null || loadFloor == null) {
      throw StateError(
        'Accepted removed-shell retry authorization is unavailable.',
      );
    }
    return _runGroupMutation(groupId, () async {
      final durable = await authorize(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        signedMembershipWatermark: signedMembershipWatermark,
        signedIssuedAt: signedIssuedAt,
        keyGeneration: keyGeneration,
      );
      final mapped = _mapAcceptedRetryAuthorizationOutcome(durable);
      final group = await _loadGroupModel(groupId);
      final selfRow = await dbLoadGroupMember(groupId, selfPeerId);
      final latestRow = await dbLoadLatestGroupKey(groupId);
      final latestKey = latestRow == null
          ? null
          : await _groupKeyFromRow(latestRow);
      if (group == null ||
          group.selfRemovedAt != null ||
          group.isDissolved ||
          selfRow == null ||
          latestKey == null ||
          latestKey.keyGeneration != keyGeneration ||
          latestKey.encryptedKey != expectedKeyMaterial) {
        return const SelfRemovedAcceptedNativeRetryResult(
          outcome:
              SelfRemovedAcceptedRetryAuthorizationOutcome.refusedStateChanged,
        );
      }

      if (mapped == SelfRemovedAcceptedRetryAuthorizationOutcome.authorized) {
        await joinNative();
        return SelfRemovedAcceptedNativeRetryResult(
          outcome: mapped,
          group: group,
        );
      }
      if (mapped !=
          SelfRemovedAcceptedRetryAuthorizationOutcome.refusedBindingMissing) {
        return SelfRemovedAcceptedNativeRetryResult(outcome: mapped);
      }

      final floor = await loadFloor(groupId);
      final authority = await loadAuthority(
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (floor != null ||
          authority.shape !=
              shell_db
                  .SelfRemovedGroupShellAuthorityShape
                  .unmarkedSelfPresent ||
          authority.lastMembershipEventId != null ||
          !_sameInstant(
            group.lastMembershipEventAt,
            expectedFreshMembershipAt,
          ) ||
          !_sameInstant(group.lastMetadataEventAt, latestAllowedMetadataAt)) {
        return const SelfRemovedAcceptedNativeRetryResult(
          outcome:
              SelfRemovedAcceptedRetryAuthorizationOutcome.refusedStateChanged,
        );
      }
      await joinNative();
      return SelfRemovedAcceptedNativeRetryResult(
        outcome: SelfRemovedAcceptedRetryAuthorizationOutcome.authorized,
        group: group,
      );
    });
  }

  @override
  Future<SelfRemovedAcceptedRollbackOutcome>
  rollbackFreshAcceptedMaterialization({
    required String groupId,
    required String selfPeerId,
    required int keyGeneration,
    required String expectedKeyMaterial,
    required DateTime expectedMembershipAt,
    required DateTime? latestAllowedMetadataAt,
  }) async {
    final prepare = dbPrepareFreshAcceptedMaterializationRollbackFn;
    final commit = dbCommitFreshAcceptedMaterializationRollbackFn;
    final primary = groupKeyStore;
    if (prepare == null || commit == null || primary == null) {
      throw StateError('Fresh accepted rollback is unavailable.');
    }
    return _runGroupSenderAuthorityMutation(groupId, () async {
      final prepared = await prepare(
        groupId: groupId,
        selfPeerId: selfPeerId,
        keyGeneration: keyGeneration,
        expectedMembershipAt: expectedMembershipAt.toUtc(),
        expectedMetadataAt: latestAllowedMetadataAt?.toUtc(),
      );
      final preparation = prepared.preparation;
      if (!prepared.prepared || preparation == null) {
        return _mapAcceptedRollbackQualificationOutcome(prepared.disposition);
      }

      final primaryStoreKey = secureStoreKeyFromReference(
        preparation.encryptedKeyReference,
      );
      final currentPrimaryMaterial = await primary.read(primaryStoreKey);
      if (currentPrimaryMaterial != null &&
          currentPrimaryMaterial != expectedKeyMaterial) {
        return SelfRemovedAcceptedRollbackOutcome.refusedStateChanged;
      }

      // The projection and external key stores are revoked while the exact SQL
      // fingerprint still owns their addresses. The final DB transaction then
      // performs one all-or-nothing CAS deletion of group, roster, and key.
      await groupReactionProjection?.removeGroupStrict(groupId);
      var externalDeletionStarted = false;
      try {
        externalDeletionStarted = true;
        await primary.delete(primaryStoreKey);
        final mirror = pushSharedKeyStore;
        if (mirror != null) {
          await mirror.delete(
            sharedGroupPushKeyName(groupId, preparation.keyGeneration),
          );
          await mirror.delete(sharedGroupMutedKeyName(groupId));
        }
        final result = await commit(preparation: preparation);
        if (!result.rolledBack) {
          try {
            await _restoreFreshAcceptedMaterializationAfterRefusal(
              groupId: groupId,
              primaryStoreKey: primaryStoreKey,
              expectedKeyMaterial: expectedKeyMaterial,
            );
          } catch (_) {
            // Preserve the exact CAS refusal. SQL still retains the retry
            // address if an out-of-band writer also prevents projection repair.
          }
        }
        return _mapAcceptedRollbackOutcome(result.disposition);
      } catch (_) {
        if (externalDeletionStarted) {
          try {
            await _restoreFreshAcceptedMaterializationAfterRefusal(
              groupId: groupId,
              primaryStoreKey: primaryStoreKey,
              expectedKeyMaterial: expectedKeyMaterial,
            );
          } catch (_) {
            // Preserve the original fault. SQL still retains the exact address
            // so a later authoritative repair can retry external projection.
          }
        }
        rethrow;
      }
    });
  }

  @override
  Future<SelfRemovedShellMutationOutcome> purgeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
    required SelfRemovedShellFreshnessFloor floor,
    required DateTime deletedAt,
  }) async {
    final purge = dbPurgeSelfRemovedGroupShellFn;
    if (purge == null) {
      throw StateError('Removed-shell purge capability is unavailable.');
    }
    final outcome = await _runGroupMutation(expected.groupId, () async {
      final result = await purge(
        expected: _unwrapShellAuthority(expected),
        floor: _unwrapFreshnessFloor(floor),
        deletedAt: deletedAt.toUtc(),
      );
      // Strict projection removal is an earlier, retryable step owned by
      // terminalizeSelfRemovedShell. No fallible external write may follow the
      // group-last SQL commit because its marker retry authority is now gone.
      return _mapMutationOutcome(result.disposition);
    });
    if (outcome == SelfRemovedShellMutationOutcome.committed) {
      emitGroupNotificationReconciliationSignal(expected.groupId);
    }
    return outcome;
  }

  // --- Members ---

  @override
  Future<void> saveMember(GroupMember member) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(member.peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(member.peerId, 'peerId', peerIdRejectReason);
    }
    await _runGroupSenderAuthorityMutation(member.groupId, () async {
      await _requireOrdinaryGroupAuthority(member.groupId);
      final duplicateRejectReason =
          groupMemberDuplicatePeerIdVariantRejectReason(
            await getMembers(member.groupId),
            member,
          );
      if (duplicateRejectReason != null) {
        throw StateError(duplicateRejectReason);
      }
      await dbInsertGroupMember(member.toMap());
      final authoritative = await _loadGroupModel(member.groupId);
      final stored = await dbLoadGroupMember(member.groupId, member.peerId);
      if ((selfRemovedShellAuthorityEnabled && authoritative == null) ||
          authoritative?.selfRemovedAt != null) {
        await groupReactionProjection?.removeGroup(member.groupId);
        throw StateError('Group membership authority changed during save.');
      }
      if (stored != null && !_projectionMirrorsSuppressed(member.groupId)) {
        await groupReactionProjection?.upsertMember(
          GroupMember.fromMap(stored),
        );
      }
    });
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
    await _runGroupSenderAuthorityMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      await dbUpdateGroupMemberRole(groupId, peerId, role.toValue());
      final row = await dbLoadGroupMember(groupId, peerId);
      if (row == null) {
        await groupReactionProjection?.removeMember(
          groupId: groupId,
          peerId: peerId,
        );
      } else if (!_projectionMirrorsSuppressed(groupId)) {
        await groupReactionProjection?.upsertMember(GroupMember.fromMap(row));
      }
    });
  }

  @override
  Future<void> removeMember(String groupId, String peerId) async {
    final peerIdRejectReason = groupMemberPeerIdRejectReason(peerId);
    if (peerIdRejectReason != null) {
      throw ArgumentError.value(peerId, 'peerId', peerIdRejectReason);
    }
    await _runGroupSenderAuthorityMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      await dbDeleteGroupMember(groupId, peerId);
      await groupReactionProjection?.removeMember(
        groupId: groupId,
        peerId: peerId,
      );
    });
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
  Future<bool> isLinkedGroupBootstrapIntent(PendingSiblingDevice device) async {
    final guard = dbHasLinkedGroupBootstrapIntentFn;
    if (guard == null) return false;
    return guard(
      groupId: device.groupId,
      transportPeerId: device.transportPeerId,
    );
  }

  @override
  Future<LinkedGroupBootstrapAuthorCommitOutcome>
  commitLinkedGroupBootstrapAuthoring({
    required GroupModel expectedGroup,
    required List<GroupMember> expectedMembers,
    required GroupMember expectedSelfMember,
    required GroupKeyInfo expectedLatestKey,
    required GroupMember updatedSelfMember,
    required PendingSiblingDevice pendingDevice,
    required GroupPendingBroadcast pendingBroadcast,
    required LinkedGroupBootstrapAuthorityGenesis authorityGenesis,
  }) async {
    final commit = dbCommitLinkedGroupBootstrapAuthoringFn;
    if (commit == null) {
      throw StateError('Linked group bootstrap authoring is unavailable.');
    }
    return _runGroupSenderAuthorityMutation(expectedGroup.id, () async {
      final currentGroup = await getGroup(expectedGroup.id);
      final currentSelf = await getMember(
        expectedGroup.id,
        expectedSelfMember.peerId,
      );
      final currentMembers = await getMembers(expectedGroup.id);
      final currentKey = await getLatestKey(expectedGroup.id);
      final updatedExpectedMembers = expectedMembers
          .map(
            (member) => member.peerId == expectedSelfMember.peerId
                ? updatedSelfMember
                : member,
          )
          .toList(growable: false);
      final rosterMatchesExpected =
          _sameMemberProjection(currentMembers, expectedMembers) ||
          _sameMemberProjection(currentMembers, updatedExpectedMembers);
      final selfMatchesExpected =
          _sameRow(
            currentSelf?.toMap() ?? const <String, Object?>{},
            expectedSelfMember.toMap(),
          ) ||
          _sameRow(
            currentSelf?.toMap() ?? const <String, Object?>{},
            updatedSelfMember.toMap(),
          );
      if (currentGroup == null ||
          currentSelf == null ||
          currentKey == null ||
          currentGroup.isDissolved ||
          !_sameRow(currentGroup.toMap(), expectedGroup.toMap()) ||
          !rosterMatchesExpected ||
          !selfMatchesExpected ||
          !_sameGroupKey(currentKey, expectedLatestKey)) {
        return LinkedGroupBootstrapAuthorCommitOutcome.refusedStateChanged;
      }
      final result = await commit(
        expectedGroup: expectedGroup.toMap(),
        expectedMembers: expectedMembers
            .map((member) => member.toMap())
            .toList(growable: false),
        expectedSelfMember: expectedSelfMember.toMap(),
        expectedLatestKeyGeneration: expectedLatestKey.keyGeneration,
        expectedLatestKeyCreatedAt: expectedLatestKey.createdAt
            .toUtc()
            .toIso8601String(),
        updatedSelfMember: updatedSelfMember.toMap(),
        pendingDevice: pendingDevice.toMap(),
        pendingBroadcast: pendingBroadcast.toMap(),
        authorityGenesisSourcePeerId: authorityGenesis.sourcePeerId,
        authorityGenesisSourceEventId: authorityGenesis.sourceEventId,
        authorityGenesisSourceTimestamp: authorityGenesis.sourceTimestamp,
        authorityGenesisPayload: authorityGenesis.payload,
      );
      return switch (result) {
        LinkedGroupBootstrapDbDisposition.committed =>
          LinkedGroupBootstrapAuthorCommitOutcome.committed,
        LinkedGroupBootstrapDbDisposition.duplicate =>
          LinkedGroupBootstrapAuthorCommitOutcome.duplicate,
        LinkedGroupBootstrapDbDisposition.refusedPendingConflict =>
          LinkedGroupBootstrapAuthorCommitOutcome.refusedPendingConflict,
        LinkedGroupBootstrapDbDisposition.refusedStateChanged =>
          LinkedGroupBootstrapAuthorCommitOutcome.refusedStateChanged,
      };
    });
  }

  @override
  Future<bool> completeLinkedGroupBootstrapCustody({
    required PendingSiblingDevice expectedDevice,
    required GroupPendingBroadcast expectedBroadcast,
  }) async {
    final complete = dbCompleteLinkedGroupBootstrapCustodyFn;
    if (complete == null) return false;
    return _runGroupMutation(
      expectedDevice.groupId,
      () => complete(
        expectedDevice: expectedDevice.toMap(),
        expectedBroadcast: expectedBroadcast.toMap(),
      ),
    );
  }

  @override
  Future<LinkedGroupBootstrapMaterializationOutcome>
  commitLinkedGroupBootstrapMaterialization({
    required String bootstrapId,
    required GroupModel group,
    required List<GroupMember> members,
    required GroupKeyInfo key,
    required LinkedGroupBootstrapAuthorityGenesis authorityGenesis,
  }) async {
    final commit = dbCommitLinkedGroupBootstrapMaterializationFn;
    final store = groupKeyStore;
    if (commit == null || store == null) {
      throw StateError(
        'Linked group bootstrap materialization is unavailable.',
      );
    }
    if (bootstrapId.trim().isEmpty ||
        group.id != key.groupId ||
        group.isDissolved ||
        members.isEmpty ||
        members.any((member) => member.groupId != group.id) ||
        authorityGenesis.sourcePeerId.trim().isEmpty ||
        authorityGenesis.sourceEventId.trim().isEmpty ||
        authorityGenesis.sourceTimestamp.trim().isEmpty ||
        authorityGenesis.payload.isEmpty) {
      return LinkedGroupBootstrapMaterializationOutcome.refusedConflict;
    }
    return _runGroupSenderAuthorityMutation(group.id, () async {
      final storeName = groupLinkedBootstrapKeyMaterialStoreName(
        group.id,
        key.keyGeneration,
        bootstrapId,
      );
      final existingMaterial = await store.read(storeName);
      if (existingMaterial != null && existingMaterial != key.encryptedKey) {
        return LinkedGroupBootstrapMaterializationOutcome.refusedConflict;
      }
      var wroteMaterial = false;
      if (existingMaterial == null) {
        await store.write(storeName, key.encryptedKey);
        wroteMaterial = true;
      }
      final stagedKey = GroupKeyInfo(
        groupId: key.groupId,
        keyGeneration: key.keyGeneration,
        encryptedKey: secureStoreReferenceForKey(storeName),
        createdAt: key.createdAt,
      );
      late final LinkedGroupBootstrapMaterializationDbDisposition dbResult;
      try {
        dbResult = await commit(
          groupRow: group.toMap(),
          memberRows: members.map((member) => member.toMap()).toList(),
          keyRow: stagedKey.toMap(),
          authorityGenesisSourcePeerId: authorityGenesis.sourcePeerId,
          authorityGenesisSourceEventId: authorityGenesis.sourceEventId,
          authorityGenesisSourceTimestamp: authorityGenesis.sourceTimestamp,
          authorityGenesisPayload: authorityGenesis.payload,
        );
      } catch (_) {
        if (wroteMaterial) {
          try {
            await store.delete(storeName);
          } catch (_) {}
        }
        rethrow;
      }
      if (dbResult ==
          LinkedGroupBootstrapMaterializationDbDisposition.refusedConflict) {
        if (wroteMaterial) {
          try {
            await store.delete(storeName);
          } catch (_) {}
        }
        return LinkedGroupBootstrapMaterializationOutcome.refusedConflict;
      }

      // Hydrated exact read-back is part of the durable handler boundary. A
      // failure here deliberately leaves the complete SQL projection and key
      // address so exact replay can classify it duplicate before relay ACK.
      final storedGroup = await getGroup(group.id);
      final storedMembers = await getMembers(group.id);
      final storedKey = await getLatestKey(group.id);
      if (storedGroup == null ||
          storedKey == null ||
          !_sameRow(storedGroup.toMap(), group.toMap()) ||
          !_sameMemberProjection(storedMembers, members) ||
          !_sameGroupKey(storedKey, key)) {
        throw StateError('Linked group bootstrap read-back mismatch.');
      }
      return dbResult ==
              LinkedGroupBootstrapMaterializationDbDisposition.duplicate
          ? LinkedGroupBootstrapMaterializationOutcome.duplicate
          : LinkedGroupBootstrapMaterializationOutcome.committed;
    });
  }

  @override
  Future<void> removeAllMembers(String groupId) async {
    await _runGroupSenderAuthorityMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      await dbDeleteAllGroupMembers(groupId);
      await groupReactionProjection?.removeAllMembers(groupId);
    });
  }

  // --- Keys ---

  @override
  Future<void> saveKey(GroupKeyInfo key) async {
    await _runGroupSenderAuthorityMutation(key.groupId, () async {
      await _requireOrdinaryGroupAuthority(key.groupId);
      final storageRow = await _toStorageRow(key);
      await dbInsertGroupKey(storageRow);
      final authoritative = await _loadGroupModel(key.groupId);
      final stored = await dbLoadGroupKeyByGeneration(
        key.groupId,
        key.keyGeneration,
      );
      if ((selfRemovedShellAuthorityEnabled && authoritative == null) ||
          authoritative?.selfRemovedAt != null ||
          stored == null) {
        await _deleteGroupKeyMirror(key);
        await _deleteGroupKeyMaterial(key);
        await groupReactionProjection?.removeGroup(key.groupId);
        throw StateError('Group key authority changed during save.');
      }
      if (!_projectionMirrorsSuppressed(key.groupId)) {
        await groupReactionProjection?.upsertKeyEpoch(key);
      }
      final hydratedKey = await _hydrateGroupKey(key);
      if (hydratedKey != null) {
        await _mirrorGroupKeyForPush(hydratedKey);
      }
      await _pruneObsoleteKeys(key.groupId);
    });
  }

  @override
  Future<void> commitProtectedGroupKeyAuthority({
    required GroupKeyInfo key,
    required ProtectedGroupAuthorityCompleteFact authorityComplete,
  }) async {
    final commit = dbCommitProtectedGroupKeyAuthority;
    if (commit == null) {
      throw StateError('protected key authority persistence is unavailable');
    }
    await _runGroupSenderAuthorityMutation(key.groupId, () async {
      await _requireOrdinaryGroupAuthority(key.groupId);
      final storageRow = await _toStorageRow(key);
      await commit(
        keyRow: storageRow,
        authorityCompleteSourcePeerId: authorityComplete.sourcePeerId,
        authorityCompleteSourceEventId: authorityComplete.sourceEventId,
        authorityCompleteSourceTimestamp: authorityComplete.sourceTimestamp,
        authorityCompletePayload: authorityComplete.payload,
      );
      final authoritative = await _loadGroupModel(key.groupId);
      final stored = await dbLoadGroupKeyByGeneration(
        key.groupId,
        key.keyGeneration,
      );
      if ((selfRemovedShellAuthorityEnabled && authoritative == null) ||
          authoritative?.selfRemovedAt != null ||
          stored == null) {
        await _deleteGroupKeyMirror(key);
        await _deleteGroupKeyMaterial(key);
        await groupReactionProjection?.removeGroup(key.groupId);
        throw StateError('Group key authority changed during protected save.');
      }
      if (!_projectionMirrorsSuppressed(key.groupId)) {
        await groupReactionProjection?.upsertKeyEpoch(key);
      }
      final hydratedKey = await _hydrateGroupKey(key);
      if (hydratedKey != null) {
        await _mirrorGroupKeyForPush(hydratedKey);
      }
      await _pruneObsoleteKeys(key.groupId);
    });
  }

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    if (!await _hasOrdinaryGroupAuthority(groupId)) return null;
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
  Future<void> forceGroupRejoinEligible(String groupId) async {
    final fn = dbForceGroupRejoinEligibleFn;
    if (fn == null) return;
    await fn(groupId);
  }

  @override
  Future<GroupKeyInfo?> getKeyByGeneration(
    String groupId,
    int generation,
  ) async {
    if (!await _hasOrdinaryGroupAuthority(groupId)) return null;
    final row = await dbLoadGroupKeyByGeneration(groupId, generation);
    if (row == null) return null;
    return _groupKeyFromRow(row);
  }

  @override
  Future<void> removeAllKeys(String groupId) async {
    await _runGroupSenderAuthorityMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      final existingKeys =
          (pushSharedKeyStore == null && groupKeyStore == null) ||
              dbLoadAllGroupKeys == null
          ? const <Map<String, Object?>>[]
          : await dbLoadAllGroupKeys!(groupId);
      await dbDeleteAllGroupKeys(groupId);
      await groupReactionProjection?.clearKeyEpoch(groupId);
      await _clearPendingKeyRotationsAssumesCoordinated(groupId);
      for (final row in existingKeys) {
        final key = GroupKeyInfo.fromMap(row);
        await _deleteGroupKeyMirror(key);
        await _deleteGroupKeyMaterial(key);
      }
    });
  }

  @override
  Future<T> cleanupExactVoluntaryExit<T>({
    required String groupId,
    required String selfPeerId,
    required DateTime selfJoinedAt,
    required Future<T> Function() finalizeSql,
  }) {
    return _runGroupSenderAuthorityMutation(groupId, () async {
      final group = await _loadGroupModel(groupId);
      if (group == null ||
          group.selfRemovedAt != null ||
          group.isDissolved ||
          group.dissolvedAt != null) {
        throw StateError(
          'Exact voluntary-exit group authority is unavailable.',
        );
      }
      final selfRow = await dbLoadGroupMember(groupId, selfPeerId);
      if (selfRow == null) {
        throw StateError(
          'Exact voluntary-exit self membership is unavailable.',
        );
      }
      final self = GroupMember.fromMap(selfRow);
      if (self.peerId != selfPeerId ||
          !_sameInstant(self.joinedAt, selfJoinedAt)) {
        throw StateError(
          'Voluntary-exit membership generation changed before cleanup.',
        );
      }

      final loadCommitted = dbLoadAllGroupKeys;
      final projection = groupReactionProjection;
      final mirror = pushSharedKeyStore;
      if (loadCommitted == null) {
        throw StateError(
          'Strict voluntary-exit key-reference cleanup is unavailable.',
        );
      }
      final references = <GroupKeyInfo>[];
      final seenAddresses = <String>{};
      void addReference(Map<String, Object?> row) {
        final key = GroupKeyInfo.fromMap(row);
        if (key.groupId != groupId) {
          throw StateError('Voluntary-exit key reference changed groups.');
        }
        final address = '${key.keyGeneration}\u0000${key.encryptedKey}';
        if (seenAddresses.add(address)) references.add(key);
      }

      for (final row in await loadCommitted(groupId)) {
        addReference(row);
      }
      final pendingRow = await dbLoadPendingGroupKeyRotation?.call(groupId);
      if (pendingRow != null) {
        addReference(pendingRow);
      } else {
        final pending = _pendingKeyRotationFallback[groupId];
        if (pending != null) addReference(pending.toMap());
      }

      // Fail closed in authorization order. SQL remains the retry address
      // until all external stores are clean and [finalizeSql] commits.
      final primary = groupKeyStore;
      if (references.isNotEmpty && primary == null) {
        throw StateError('Primary group-key store is unavailable.');
      }
      // Shared notification projections exist only on platforms where their
      // backing store is configured. Absence therefore means there is no
      // platform address to delete, while a configured store remains strict.
      await projection?.removeGroupStrict(groupId);
      for (final key in references) {
        if (isSecureStoreReference(key.encryptedKey)) {
          await primary!.delete(secureStoreKeyFromReference(key.encryptedKey));
        } else if (primary != null) {
          await primary.delete(
            groupKeyMaterialStoreName(key.groupId, key.keyGeneration),
          );
        }
      }
      if (mirror != null) {
        for (final key in references) {
          await mirror.delete(
            sharedGroupPushKeyName(key.groupId, key.keyGeneration),
          );
        }
        await mirror.delete(sharedGroupMutedKeyName(groupId));
      }

      final result = await finalizeSql();
      emitGroupNotificationReconciliationSignal(groupId);
      return result;
    });
  }

  @override
  Future<void> savePendingKeyRotation(GroupKeyInfo key) async {
    await _runGroupMutation(key.groupId, () async {
      await _requireOrdinaryGroupAuthority(key.groupId);
      final upsertPending = dbUpsertPendingGroupKeyRotation;
      if (upsertPending == null) {
        _pendingKeyRotationFallback[key.groupId] = key;
        return;
      }
      await upsertPending(await _toStorageRow(key));
      final authoritative = await _loadGroupModel(key.groupId);
      final stored = await dbLoadPendingGroupKeyRotation?.call(key.groupId);
      if ((selfRemovedShellAuthorityEnabled && authoritative == null) ||
          authoritative?.selfRemovedAt != null ||
          stored == null) {
        await _deleteGroupKeyMaterial(key);
        throw StateError('Group key-draft authority changed during save.');
      }
    });
  }

  @override
  Future<GroupKeyInfo?> getPendingKeyRotation(String groupId) async {
    if (!await _hasOrdinaryGroupAuthority(groupId)) return null;
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
    await _runGroupMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      await _clearPendingKeyRotationAssumesCoordinated(groupId, keyGeneration);
    });
  }

  @override
  Future<void> clearPendingKeyRotations(String groupId) async {
    await _runGroupMutation(groupId, () async {
      await _requireOrdinaryGroupAuthority(groupId);
      await _clearPendingKeyRotationsAssumesCoordinated(groupId);
    });
  }

  Future<void> mirrorAllKeysToSecureStore() async {
    if (pushSharedKeyStore == null || dbLoadAllGroupKeys == null) {
      return;
    }

    final groups = await dbLoadAllGroups();
    for (final group in groups) {
      final groupId = group['id'] as String?;
      if (groupId == null) continue;
      await _runGroupMutation(groupId, () async {
        if (await _mustSkipExitCleanupBackfill(groupId)) return;
        final authoritative = await dbLoadGroup(groupId);
        if (authoritative == null || authoritative['self_removed_at'] != null) {
          return;
        }
        final keyRows = await dbLoadAllGroupKeys!(groupId);
        for (final row in keyRows) {
          final key = await _groupKeyFromRow(row);
          if (key == null) continue;
          await _mirrorGroupKeyForPush(key);
        }
      });
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
      if (groupId == null) continue;
      await _runGroupMutation(groupId, () async {
        if (await _mustSkipExitCleanupBackfill(groupId)) return;
        final authoritative = await dbLoadGroup(groupId);
        if (authoritative == null || authoritative['self_removed_at'] != null) {
          return;
        }
        final isMuted = (authoritative['is_muted'] as int? ?? 0) == 1;
        await _mirrorGroupMutedForPush(groupId, isMuted);
      });
    }
  }

  /// Launch-time authoritative restore of recipient-owned iOS reaction state.
  /// Query failures stay best-effort just like the existing group key/mute
  /// mirrors; the extension fails closed until a later mutation or restart
  /// repairs the projection.
  Future<void> mirrorAllGroupReactionNotificationContexts({
    bool rethrowOnError = false,
  }) async {
    final projection = groupReactionProjection;
    if (projection == null) return;
    try {
      await projection.replaceContextsFromAuthoritativeLoader(() async {
        final rows = await dbLoadAllGroups();
        final groups = <GroupModel>[];
        final terminalGroupIds = <String>{};
        for (final row in rows) {
          final group = GroupModel.fromMap(row);
          if (group.selfRemovedAt != null ||
              await _mustSkipExitCleanupBackfill(group.id)) {
            terminalGroupIds.add(group.id);
            continue;
          }
          groups.add(group);
        }
        final membersByGroup = <String, List<GroupMember>>{};
        final latestKeysByGroup = <String, GroupKeyInfo?>{};
        for (final group in groups) {
          final memberRows = await dbLoadAllGroupMembers(group.id);
          membersByGroup[group.id] = memberRows
              .map(GroupMember.fromMap)
              .toList(growable: false);
          final keyRow = await dbLoadLatestGroupKey(group.id);
          latestKeysByGroup[group.id] = keyRow == null
              ? null
              : GroupKeyInfo.fromMap(keyRow);
        }
        return (
          groups: groups,
          membersByGroup: membersByGroup,
          latestKeysByGroup: latestKeysByGroup,
          terminalGroupIds: terminalGroupIds,
        );
      });
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_REACTION_PROJECTION_BACKFILL_ERROR',
        details: {'error': error.toString()},
      );
      if (rethrowOnError) rethrow;
    }
  }

  Future<void> mirrorAllGroupNotificationSenderAuthorities() async {
    final projection = groupReactionProjection;
    final load = _loadGroupNotificationSenderAuthority;
    if (projection == null || load == null) return;
    final authorities = <String, GroupNotificationSenderAuthority?>{};
    for (final row in await dbLoadAllGroups()) {
      final groupId = (row['id'] as String?)?.trim();
      if (groupId == null ||
          groupId.isEmpty ||
          row['self_removed_at'] != null) {
        continue;
      }
      authorities[groupId] = await load(groupId);
    }
    await projection.replaceAllGroupSenderAuthorities(authorities);
  }

  Future<bool> _mustSkipExitCleanupBackfill(String groupId) async {
    final check = dbHasGroupExitCleanupPending;
    if (check == null) return false;
    try {
      return await check(groupId);
    } catch (error) {
      // Query uncertainty is fail-closed: skipping a self-healing mirror is
      // recoverable, but republishing native-left authority is not.
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_REPO_EXIT_CLEANUP_BACKFILL_GUARD_ERROR',
        details: {'groupId': groupId, 'error': error.toString()},
      );
      return true;
    }
  }

  Future<void> _mirrorGroupContextForPush(String groupId) async {
    final projection = groupReactionProjection;
    if (projection == null) return;
    final row = await dbLoadGroup(groupId);
    if (row == null) {
      await projection.removeGroup(groupId);
      return;
    }
    final group = GroupModel.fromMap(row);
    if (group.selfRemovedAt != null) {
      await projection.removeGroupStrict(groupId);
      return;
    }
    if (_projectionMirrorsSuppressed(groupId)) return;
    await projection.upsertGroup(group);
  }

  Future<void> _clearPendingKeyRotationAssumesCoordinated(
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

  Future<void> _clearPendingKeyRotationsAssumesCoordinated(
    String groupId,
  ) async {
    final loadPending = dbLoadPendingGroupKeyRotation;
    final pendingRow = loadPending == null ? null : await loadPending(groupId);
    final pending = pendingRow == null
        ? _pendingKeyRotationFallback[groupId]
        : GroupKeyInfo.fromMap(pendingRow);
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

  Future<T> _runGroupMutation<T>(
    String groupId,
    Future<T> Function() action,
  ) async {
    final previous = _groupMutationTails[groupId];
    final gate = Completer<void>();
    final current = (previous ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => gate.future);
    _groupMutationTails[groupId] = current;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A failed mutation must not poison later retry attempts.
      }
    }
    try {
      return await action();
    } finally {
      if (!gate.isCompleted) gate.complete();
      if (identical(_groupMutationTails[groupId], current)) {
        _groupMutationTails.remove(groupId);
      }
    }
  }

  /// Serializes a mutation that can change the current sender tuple/key
  /// generation through the strict shared-Keychain authority handoff.
  /// Policy-only and housekeeping mutations intentionally keep using
  /// [_runGroupMutation], so projection storage availability cannot block
  /// otherwise unrelated SQL work.
  Future<T> _runGroupSenderAuthorityMutation<T>(
    String groupId,
    Future<T> Function() action,
  ) {
    // The incumbent projection-only composition mirrors recipient/display
    // state and has never published sender authority. Preserve that mode until
    // the authority loader is explicitly configured. Production configures it
    // immediately after construction; once activated, clearing/missing the
    // loader is a fail-closed composition error handled by the strict helper.
    if (!_groupNotificationSenderAuthorityHandoffConfigured) {
      return _runGroupMutation(groupId, action);
    }
    return _runGroupMutation(
      groupId,
      () => runCommittedGroupSenderAuthorityHandoff(
        groupId: groupId,
        projection: groupReactionProjection,
        loadCommittedAuthority: _loadGroupNotificationSenderAuthority,
        commitMutation: action,
      ),
    );
  }

  Future<GroupModel?> _loadGroupModel(String groupId) async {
    final row = await dbLoadGroup(groupId);
    return row == null ? null : GroupModel.fromMap(row);
  }

  Future<bool> _hasOrdinaryGroupAuthority(String groupId) async {
    final group = await _loadGroupModel(groupId);
    return (group != null || !selfRemovedShellAuthorityEnabled) &&
        group?.selfRemovedAt == null;
  }

  Future<GroupModel?> _requireOrdinaryGroupAuthority(String groupId) async {
    final group = await _loadGroupModel(groupId);
    if ((selfRemovedShellAuthorityEnabled && group == null) ||
        group?.selfRemovedAt != null) {
      throw StateError('Group is absent or has been locally self-removed.');
    }
    return group;
  }

  Future<GroupModel?> _projectAuthoritativeGroup(String groupId) async {
    final projection = groupReactionProjection;
    final authoritative = await _loadGroupModel(groupId);
    if (authoritative == null || authoritative.selfRemovedAt != null) {
      // Removals are NEVER suppressed (plan 321): a failure-branch or rollback
      // removal must fire even inside a fresh-join suppression scope.
      await projection?.removeGroupStrict(groupId);
      return authoritative;
    }
    if (_projectionMirrorsSuppressed(groupId)) return authoritative;
    await projection?.upsertGroup(authoritative);
    return authoritative;
  }

  /// Plan 321: per-groupId refcounted suppression of projection mirror
  /// UPSERTS. A fresh join publishes once, atomically, at the end of its save
  /// scope; the incremental mirrors would otherwise expose the group
  /// epoch-less for the whole roster loop. Removal paths never consult this.
  final Map<String, int> _suppressedProjectionMirrorDepths = <String, int>{};

  bool _projectionMirrorsSuppressed(String groupId) =>
      (_suppressedProjectionMirrorDepths[groupId] ?? 0) > 0;

  @override
  Future<T> runWithSuppressedGroupProjectionMirrors<T>(
    String groupId,
    Future<T> Function() action,
  ) async {
    _suppressedProjectionMirrorDepths[groupId] =
        (_suppressedProjectionMirrorDepths[groupId] ?? 0) + 1;
    try {
      return await action();
    } finally {
      final depth = (_suppressedProjectionMirrorDepths[groupId] ?? 1) - 1;
      if (depth <= 0) {
        _suppressedProjectionMirrorDepths.remove(groupId);
      } else {
        _suppressedProjectionMirrorDepths[groupId] = depth;
      }
    }
  }

  @override
  Future<bool> projectCommittedFreshJoin(String groupId) {
    // Same _runGroupMutation wrap as every _projectAcceptedReentry call site:
    // an unwrapped read-back could interleave with a concurrent removal and
    // resurrect its rows in the queued strict replace.
    return _runGroupMutation(groupId, () async {
      final projection = groupReactionProjection;
      if (projection == null) return false;
      final authoritative = await _loadGroupModel(groupId);
      if (authoritative == null || authoritative.selfRemovedAt != null) {
        return false;
      }
      if (!projection.supportsGroupType(authoritative.type)) {
        // Unsupported types (qa) carry no notification context by design —
        // parity with the incremental mirrors' benign no-op, and the strict
        // replace's ArgumentError must never fire for them.
        return false;
      }
      final memberRows = await dbLoadAllGroupMembers(groupId);
      // LATEST committed generation — never a caller-pinned one: a rotation
      // landing inside the suppressed scope must win the publish.
      final keyRow = await dbLoadLatestGroupKey(groupId);
      if (keyRow == null) return false;
      final hydratedKey = await _groupKeyFromRow(keyRow);
      if (hydratedKey == null) return false;
      final members = memberRows
          .map(GroupMember.fromMap)
          .toList(growable: false);
      await projection.replaceAcceptedGroupContextStrict(
        group: authoritative,
        members: members,
        key: hydratedKey,
      );
      await _mirrorGroupKeyForPush(hydratedKey);
      await _mirrorGroupMutedForPush(groupId, authoritative.isMuted);
      return true;
    });
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

  ({Map<String, Object?> row, String ownedStoreKey, String keyMaterial})
  _acceptedStorageRowAddress(GroupKeyInfo key, {required String bindingNonce}) {
    final row = Map<String, Object?>.from(key.toMap());
    final store = groupKeyStore;
    if (store == null || key.encryptedKey.isEmpty) {
      throw StateError('Accepted primary group-key material is unavailable.');
    }
    final storeKey = groupAcceptedKeyMaterialStoreName(
      key.groupId,
      key.keyGeneration,
      bindingNonce,
    );
    row['encrypted_key'] = secureStoreReferenceForKey(storeKey);
    return (row: row, ownedStoreKey: storeKey, keyMaterial: key.encryptedKey);
  }

  Future<void> _writeOwnedAcceptedStaging(
    ({Map<String, Object?> row, String ownedStoreKey, String keyMaterial})
    staged,
  ) async {
    final store = groupKeyStore;
    if (store == null) {
      throw StateError('Primary group-key store is unavailable.');
    }
    await store.write(staged.ownedStoreKey, staged.keyMaterial);
  }

  Future<void> _purgePreparedAcceptedStaging({
    required String groupId,
    required ({
      Map<String, Object?> row,
      String ownedStoreKey,
      String keyMaterial,
    })
    staged,
    required shell_db.SelfRemovedGroupAcceptedReentryPreparation preparation,
    required Future<shell_db.SelfRemovedGroupAcceptedReentryStageResult>
    Function({
      required shell_db.SelfRemovedGroupAcceptedReentryPreparation preparation,
      required Map<String, Object?> stagedKeyRow,
    })
    finalize,
  }) async {
    final store = groupKeyStore;
    if (store == null) {
      throw StateError('Primary group-key store is unavailable.');
    }
    await store.delete(staged.ownedStoreKey);
    final mirror = pushSharedKeyStore;
    if (mirror != null) {
      final generation = staged.row['key_generation'];
      if (generation is! int) {
        throw StateError('Accepted staged key generation is malformed.');
      }
      await mirror.delete(sharedGroupPushKeyName(groupId, generation));
      await mirror.delete(sharedGroupMutedKeyName(groupId));
    }
    final finalized = await finalize(
      preparation: preparation,
      stagedKeyRow: staged.row,
    );
    if (!finalized.staged) {
      throw StateError('Accepted staged key address changed before finalize.');
    }
  }

  Future<void> _deleteAcceptedBindingMaterial({
    required String groupId,
    required shell_db.SelfRemovedGroupAcceptedReentryBinding? binding,
  }) async {
    if (binding == null) {
      throw StateError('Accepted rollback did not return its key address.');
    }
    if (isSecureStoreReference(binding.encryptedKeyReference)) {
      final store = groupKeyStore;
      if (store == null) {
        throw StateError('Primary group-key store is unavailable.');
      }
      await store.delete(
        secureStoreKeyFromReference(binding.encryptedKeyReference),
      );
    }
    final mirror = pushSharedKeyStore;
    if (mirror != null) {
      await mirror.delete(
        sharedGroupPushKeyName(groupId, binding.keyGeneration),
      );
      await mirror.delete(sharedGroupMutedKeyName(groupId));
    }
  }

  Future<void> _restoreFreshAcceptedMaterializationAfterRefusal({
    required String groupId,
    required String primaryStoreKey,
    required String expectedKeyMaterial,
  }) async {
    final primary = groupKeyStore;
    if (primary == null) {
      throw StateError('Primary group-key store is unavailable.');
    }
    await primary.write(primaryStoreKey, expectedKeyMaterial);
    final currentKeyRow = await dbLoadLatestGroupKey(groupId);
    if (currentKeyRow == null) return;
    await _projectAcceptedReentry(
      groupId: groupId,
      keyGeneration: GroupKeyInfo.fromMap(currentKeyRow).keyGeneration,
    );
  }

  Future<void> _terminalizeAcceptedPriorMaterial({
    required String groupId,
    required List<shell_db.SelfRemovedGroupKeyReference>? references,
  }) async {
    if (references == null) {
      throw StateError(
        'Accepted transition did not return prior key addresses.',
      );
    }
    final primary = groupKeyStore;
    for (final reference in references) {
      if (isSecureStoreReference(reference.encryptedKeyReference)) {
        if (primary == null) {
          throw StateError('Primary group-key store is unavailable.');
        }
        await primary.delete(
          secureStoreKeyFromReference(reference.encryptedKeyReference),
        );
      }
    }
    final mirror = pushSharedKeyStore;
    if (mirror != null) {
      for (final reference in references) {
        await mirror.delete(
          sharedGroupPushKeyName(groupId, reference.keyGeneration),
        );
      }
      await mirror.delete(sharedGroupMutedKeyName(groupId));
    }
  }

  Future<void> _projectAcceptedReentry({
    required String groupId,
    required int keyGeneration,
  }) async {
    final authoritative = await _loadGroupModel(groupId);
    if (authoritative == null || authoritative.selfRemovedAt != null) {
      throw StateError('Accepted group authority did not commit.');
    }
    final memberRows = await dbLoadAllGroupMembers(groupId);
    final keyRow = await dbLoadGroupKeyByGeneration(groupId, keyGeneration);
    if (keyRow == null) {
      throw StateError('Accepted group key did not commit.');
    }
    final hydratedKey = await _groupKeyFromRow(keyRow);
    if (hydratedKey == null) {
      throw StateError('Accepted group key material is unavailable.');
    }

    final members = memberRows.map(GroupMember.fromMap).toList(growable: false);
    await groupReactionProjection?.replaceAcceptedGroupContextStrict(
      group: authoritative,
      members: members,
      key: hydratedKey,
    );
    await _mirrorGroupKeyForPush(hydratedKey);
    await _mirrorGroupMutedForPush(groupId, authoritative.isMuted);
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

    final keyName = sharedGroupPushKeyName(key.groupId, key.keyGeneration);
    try {
      // 164 (cold-start-3): presence-diff. A (groupId, keyGeneration) →
      // encryptedKey mapping is immutable — a key rotation mints a NEW generation
      // (hence a new name), so a present name already holds the correct
      // ciphertext. Skipping a redundant write keeps the launch-time backfill
      // near-zero-cost on a populated store while still mirroring any newly-added
      // generation. Kept INSIDE the try so a transient Keychain error on
      // containsKey falls through to the catch — this mirror stays best-effort
      // (saveKey and the backfill loop must never fail on a push-mirror hiccup).
      if (await store.containsKey(keyName)) {
        return;
      }
      await store.write(keyName, key.encryptedKey);
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

    final muteName = sharedGroupMutedKeyName(groupId);
    try {
      if (isMuted) {
        // 164 (cold-start-3): mute is a TOGGLING boolean under one stable name,
        // so use a VALUE-diff — skip the write when '1' is already stored.
        if (await store.read(muteName) == '1') {
          return;
        }
        await store.write(muteName, '1');
      } else {
        // Skip the delete when the projection is already absent.
        if (!await store.containsKey(muteName)) {
          return;
        }
        await store.delete(muteName);
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

SelfRemovedShellAuthoritySnapshot _wrapShellAuthority(
  shell_db.SelfRemovedGroupShellAuthoritySnapshot snapshot,
) {
  return SelfRemovedShellAuthoritySnapshot(
    groupId: snapshot.groupId,
    selfPeerId: snapshot.selfPeerId,
    shape: switch (snapshot.shape) {
      shell_db.SelfRemovedGroupShellAuthorityShape.absent =>
        SelfRemovedShellAuthorityShape.absent,
      shell_db.SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent =>
        SelfRemovedShellAuthorityShape.unmarkedSelfPresent,
      shell_db.SelfRemovedGroupShellAuthorityShape.unmarkedSelfAbsent =>
        SelfRemovedShellAuthorityShape.unmarkedSelfAbsent,
      shell_db.SelfRemovedGroupShellAuthorityShape.markedSelfPresent =>
        SelfRemovedShellAuthorityShape.markedSelfPresent,
      shell_db.SelfRemovedGroupShellAuthorityShape.markedSelfAbsent =>
        SelfRemovedShellAuthorityShape.markedSelfAbsent,
    },
    selfRemovedAt: snapshot.selfRemovedAt,
    lastMembershipEventAt: snapshot.lastMembershipEventAt,
    lastMembershipEventId: snapshot.lastMembershipEventId,
    selfJoinedAt: snapshot.selfJoinedAt,
    persistenceToken: snapshot,
  );
}

shell_db.SelfRemovedGroupShellAuthoritySnapshot _unwrapShellAuthority(
  SelfRemovedShellAuthoritySnapshot snapshot,
) {
  final token = snapshot.persistenceToken;
  if (token is! shell_db.SelfRemovedGroupShellAuthoritySnapshot) {
    throw ArgumentError.value(snapshot, 'expected', 'invalid authority token');
  }
  return token;
}

SelfRemovalAuthorityCommitOutcome _mapCommitOutcome(
  shell_db.SelfRemovalAuthorityCommitDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovalAuthorityCommitDisposition.committed =>
    SelfRemovalAuthorityCommitOutcome.committed,
  shell_db.SelfRemovalAuthorityCommitDisposition.refusedStateChanged =>
    SelfRemovalAuthorityCommitOutcome.refusedStateChanged,
  shell_db.SelfRemovalAuthorityCommitDisposition.refusedStaleRemoval =>
    SelfRemovalAuthorityCommitOutcome.refusedStaleRemoval,
};

SelfRemovedAcceptedReentryOutcome _mapAcceptedReentryOutcome(
  shell_db.SelfRemovedGroupAcceptedReentryDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.committed =>
    SelfRemovedAcceptedReentryOutcome.committed,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedMissingFloor =>
    SelfRemovedAcceptedReentryOutcome.refusedMissingFloor,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged =>
    SelfRemovedAcceptedReentryOutcome.refusedStateChanged,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial =>
    SelfRemovedAcceptedReentryOutcome.refusedInvalidMaterial,
  shell_db
      .SelfRemovedGroupAcceptedReentryDisposition
      .refusedMalformedAuthority =>
    SelfRemovedAcceptedReentryOutcome.refusedMalformedAuthority,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedStaleAuthority =>
    SelfRemovedAcceptedReentryOutcome.refusedStaleAuthority,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedKeyState =>
    SelfRemovedAcceptedReentryOutcome.refusedKeyState,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid =>
    SelfRemovedAcceptedReentryOutcome.refusedEvidenceInvalid,
  shell_db.SelfRemovedGroupAcceptedReentryDisposition.refusedBindingCollision =>
    SelfRemovedAcceptedReentryOutcome.refusedBindingCollision,
};

SelfRemovedAcceptedRollbackOutcome _mapAcceptedRollbackOutcome(
  shell_db.SelfRemovedGroupAcceptedRollbackDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovedGroupAcceptedRollbackDisposition.rolledBack =>
    SelfRemovedAcceptedRollbackOutcome.rolledBack,
  shell_db.SelfRemovedGroupAcceptedRollbackDisposition.refusedBindingMissing =>
    SelfRemovedAcceptedRollbackOutcome.refusedBindingMissing,
  shell_db
      .SelfRemovedGroupAcceptedRollbackDisposition
      .refusedAuthorizationMismatch =>
    SelfRemovedAcceptedRollbackOutcome.refusedAuthorizationMismatch,
  shell_db.SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged =>
    SelfRemovedAcceptedRollbackOutcome.refusedStateChanged,
  shell_db.SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid =>
    SelfRemovedAcceptedRollbackOutcome.refusedEvidenceInvalid,
};

SelfRemovedAcceptedRollbackOutcome _mapAcceptedRollbackQualificationOutcome(
  shell_db.SelfRemovedGroupAcceptedRollbackQualificationDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovedGroupAcceptedRollbackQualificationDisposition.qualified =>
    throw StateError('Qualified rollback is not a refusal.'),
  shell_db
      .SelfRemovedGroupAcceptedRollbackQualificationDisposition
      .refusedBindingMissing =>
    SelfRemovedAcceptedRollbackOutcome.refusedBindingMissing,
  shell_db
      .SelfRemovedGroupAcceptedRollbackQualificationDisposition
      .refusedAuthorizationMismatch =>
    SelfRemovedAcceptedRollbackOutcome.refusedAuthorizationMismatch,
  shell_db
      .SelfRemovedGroupAcceptedRollbackQualificationDisposition
      .refusedStateChanged =>
    SelfRemovedAcceptedRollbackOutcome.refusedStateChanged,
  shell_db
      .SelfRemovedGroupAcceptedRollbackQualificationDisposition
      .refusedEvidenceInvalid =>
    SelfRemovedAcceptedRollbackOutcome.refusedEvidenceInvalid,
};

SelfRemovedAcceptedRetryAuthorizationOutcome
_mapAcceptedRetryAuthorizationOutcome(
  shell_db.SelfRemovedGroupAcceptedRetryAuthorizationDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovedGroupAcceptedRetryAuthorizationDisposition.authorized =>
    SelfRemovedAcceptedRetryAuthorizationOutcome.authorized,
  shell_db
      .SelfRemovedGroupAcceptedRetryAuthorizationDisposition
      .refusedBindingMissing =>
    SelfRemovedAcceptedRetryAuthorizationOutcome.refusedBindingMissing,
  shell_db
      .SelfRemovedGroupAcceptedRetryAuthorizationDisposition
      .refusedAuthorizationMismatch =>
    SelfRemovedAcceptedRetryAuthorizationOutcome.refusedAuthorizationMismatch,
  shell_db
      .SelfRemovedGroupAcceptedRetryAuthorizationDisposition
      .refusedStateChanged =>
    SelfRemovedAcceptedRetryAuthorizationOutcome.refusedStateChanged,
  shell_db
      .SelfRemovedGroupAcceptedRetryAuthorizationDisposition
      .refusedEvidenceInvalid =>
    SelfRemovedAcceptedRetryAuthorizationOutcome.refusedEvidenceInvalid,
};

SelfRemovedShellMutationOutcome _mapMutationOutcome(
  shell_db.SelfRemovedGroupShellMutationDisposition disposition,
) => switch (disposition) {
  shell_db.SelfRemovedGroupShellMutationDisposition.committed =>
    SelfRemovedShellMutationOutcome.committed,
  shell_db.SelfRemovedGroupShellMutationDisposition.refusedStateChanged =>
    SelfRemovedShellMutationOutcome.refusedStateChanged,
  shell_db
      .SelfRemovedGroupShellMutationDisposition
      .refusedOutstandingReferences =>
    SelfRemovedShellMutationOutcome.refusedOutstandingReferences,
  shell_db.SelfRemovedGroupShellMutationDisposition.refusedMediaRemaining =>
    SelfRemovedShellMutationOutcome.refusedMediaRemaining,
  shell_db.SelfRemovedGroupShellMutationDisposition.refusedFloorMissing =>
    SelfRemovedShellMutationOutcome.refusedFloorMissing,
  shell_db.SelfRemovedGroupShellMutationDisposition.refusedTombstoneConflict =>
    SelfRemovedShellMutationOutcome.refusedTombstoneConflict,
};

SelfRemovedShellFreshnessFloor _wrapFreshnessFloor(
  shell_db.SelfRemovedGroupFreshnessFloor floor,
) => SelfRemovedShellFreshnessFloor(
  groupId: floor.groupId,
  selfPeerId: floor.selfPeerId,
  selfRemovedAt: floor.selfRemovedAt,
  persistenceToken: floor,
);

shell_db.SelfRemovedGroupFreshnessFloor _unwrapFreshnessFloor(
  SelfRemovedShellFreshnessFloor floor,
) {
  final token = floor.persistenceToken;
  if (token is! shell_db.SelfRemovedGroupFreshnessFloor) {
    throw ArgumentError.value(floor, 'floor', 'invalid freshness-floor token');
  }
  return token;
}

bool _isStaleRemovalAuthority({
  required DateTime removalAt,
  required String removalEventId,
  required DateTime? lastAt,
  required String? lastEventId,
}) {
  if (removalEventId.trim().isEmpty) return true;
  final stored = lastAt?.toUtc();
  if (stored == null) return false;
  final incoming = removalAt.toUtc();
  if (incoming.isBefore(stored)) return true;
  if (incoming.isAfter(stored)) return false;
  if (lastEventId == null) return true;
  return removalEventId.compareTo(lastEventId) <= 0;
}
