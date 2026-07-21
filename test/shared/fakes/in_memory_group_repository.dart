import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_sibling_device.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_sibling_device_repository.dart';

bool _sameTestInstant(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == null && right == null;
  return left.toUtc().isAtSameMomentAs(right.toUtc());
}

/// In-memory [GroupRepository] for integration tests.
class InMemoryGroupRepository
    implements
        GroupRepository,
        GroupForwardAuthorizationSnapshotRepository,
        RemovedGroupMemberSnapshotRepository,
        GroupMemberDeviceSnapshotRepository,
        PendingSiblingDeviceRepository,
        GroupKeyRotationDraftRepository,
        GroupMembershipWatermarkRepository,
        GroupExitCleanupRepository,
        SelfRemovedGroupShellRepository {
  final Map<String, GroupModel> _groups = {};
  final Map<String, Map<String, GroupMember>> _members = {};
  final Map<String, Map<String, GroupMember>> _removedMemberSnapshots = {};
  final Map<String, List<GroupMemberDeviceIdentity>> _deviceSnapshots = {};
  final Map<String, PendingSiblingDevice> _pendingSiblingDevices = {};
  final Map<String, List<GroupKeyInfo>> _keys = {};
  final Map<String, GroupKeyInfo> _pendingKeyRotations = {};
  final Map<String, GroupRejoinState> _rejoinStates = {};
  final Map<String, SelfRemovedShellFreshnessFloor> _removalFloors = {};
  final Map<String, _AcceptedReentrySnapshot> _acceptedReentries = {};

  @override
  Future<Map<String, GroupRejoinState>> loadGroupRejoinStates() async =>
      Map<String, GroupRejoinState>.from(_rejoinStates);

  @override
  Future<void> recordGroupRejoinFailure(
    String groupId, {
    required DateTime nextEligibleAt,
  }) async {
    final existing = _rejoinStates[groupId];
    _rejoinStates[groupId] = GroupRejoinState(
      attemptCount: (existing?.attemptCount ?? 0) + 1,
      nextEligibleAt: nextEligibleAt,
    );
  }

  @override
  Future<void> clearGroupRejoinState(String groupId) async {
    _rejoinStates.remove(groupId);
  }

  @override
  Future<void> forceGroupRejoinEligible(String groupId) async {
    final existing = _rejoinStates[groupId];
    if (existing == null) return;
    // Collapse the backoff window (eligible immediately) while preserving the
    // attempt count and the row — mirrors the interface contract (G2 "Retry now").
    _rejoinStates[groupId] = GroupRejoinState(
      attemptCount: existing.attemptCount,
      nextEligibleAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  @override
  Future<void> savePendingSiblingDevice(PendingSiblingDevice device) async {
    _pendingSiblingDevices[device.id] = device;
  }

  @override
  Future<List<PendingSiblingDevice>> getPendingSiblingDevicesForGroup(
    String groupId,
  ) async =>
      _pendingSiblingDevices.values.where((d) => d.groupId == groupId).toList();

  @override
  Future<PendingSiblingDevice?> getPendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  ) async => _pendingSiblingDevices['$groupId:$memberPeerId:$deviceId'];

  @override
  Future<void> deletePendingSiblingDevice(
    String groupId,
    String memberPeerId,
    String deviceId,
  ) async {
    _pendingSiblingDevices.remove('$groupId:$memberPeerId:$deviceId');
  }

  @override
  Future<void> saveGroupMemberDeviceSnapshot(
    GroupMember member, {
    required DateTime savedAt,
  }) async {
    _deviceSnapshots['${member.groupId}:${member.peerId}'] = member
        .activeDevicesWithLegacyFallback();
  }

  @override
  Future<List<GroupMemberDeviceIdentity>?> loadGroupMemberDeviceSnapshot(
    String groupId,
    String peerId,
  ) async => _deviceSnapshots['$groupId:$peerId'];

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

  @override
  Future<GroupForwardAuthorizationSnapshot?>
  loadGroupForwardAuthorizationSnapshot(String groupId) async {
    // Capture every component without an await so test mutations cannot
    // interleave a mixed group/member/key view.
    final group = _groups[groupId];
    final members = (_members[groupId]?.values.toList() ?? <GroupMember>[])
      ..sort((a, b) {
        final joined = a.joinedAt.compareTo(b.joinedAt);
        return joined != 0 ? joined : a.peerId.compareTo(b.peerId);
      });
    final keys = _keys[groupId];
    int? latestKeyGeneration;
    if (keys != null && keys.isNotEmpty) {
      latestKeyGeneration = keys
          .map((key) => key.keyGeneration)
          .reduce((a, b) => a > b ? a : b);
    }
    return GroupForwardAuthorizationSnapshot(
      group: group,
      members: List<GroupMember>.unmodifiable(members),
      latestKeyGeneration: latestKeyGeneration,
    );
  }

  @override
  Future<bool> advanceGroupMembershipWatermark({
    required String groupId,
    required DateTime eventAt,
    String? eventId,
  }) async {
    final group = _groups[groupId];
    if (group == null) return false;
    final incoming = eventAt.toUtc();
    final stored = group.lastMembershipEventAt?.toUtc();
    if (stored != null && !incoming.isAfter(stored)) {
      if (!incoming.isAtSameMomentAs(stored) ||
          eventId == null ||
          group.lastMembershipEventId == null ||
          eventId.compareTo(group.lastMembershipEventId!) <= 0) {
        return false;
      }
    }
    _groups[groupId] = group.copyWith(
      lastMembershipEventAt: incoming,
      lastMembershipEventId: eventId,
    );
    return true;
  }

  @override
  Future<SelfRemovedShellAuthoritySnapshot> loadSelfRemovedShellAuthority({
    required String groupId,
    required String selfPeerId,
  }) async => _shellAuthority(groupId, selfPeerId);

  @override
  Future<SelfRemovalAuthorityCommitOutcome> commitSelfRemovalAuthority({
    required String groupId,
    required String selfPeerId,
    required DateTime expectedSelfJoinedAt,
    required DateTime removalAt,
    required String removalEventId,
    required Future<void> Function() leaveNative,
  }) async {
    final before = _shellAuthority(groupId, selfPeerId);
    if (before.shape != SelfRemovedShellAuthorityShape.unmarkedSelfPresent ||
        before.selfJoinedAt == null ||
        !before.selfJoinedAt!.isAtSameMomentAs(expectedSelfJoinedAt)) {
      return SelfRemovalAuthorityCommitOutcome.refusedStateChanged;
    }
    final incoming = removalAt.toUtc();
    final stored = before.lastMembershipEventAt?.toUtc();
    if (removalEventId.trim().isEmpty ||
        (stored != null &&
            (incoming.isBefore(stored) ||
                (incoming.isAtSameMomentAs(stored) &&
                    (before.lastMembershipEventId == null ||
                        removalEventId.compareTo(
                              before.lastMembershipEventId!,
                            ) <=
                            0))))) {
      return SelfRemovalAuthorityCommitOutcome.refusedStaleRemoval;
    }
    await leaveNative();
    final current = _shellAuthority(groupId, selfPeerId);
    if (current.shape != before.shape ||
        current.selfJoinedAt == null ||
        !current.selfJoinedAt!.isAtSameMomentAs(expectedSelfJoinedAt) ||
        current.lastMembershipEventAt != before.lastMembershipEventAt ||
        current.lastMembershipEventId != before.lastMembershipEventId) {
      return SelfRemovalAuthorityCommitOutcome.refusedStateChanged;
    }
    final group = _groups[groupId]!;
    _groups[groupId] = group.copyWith(
      selfRemovedAt: incoming,
      lastMembershipEventAt: incoming,
      lastMembershipEventId: removalEventId,
    );
    _members[groupId]?.remove(selfPeerId);
    return SelfRemovalAuthorityCommitOutcome.committed;
  }

  @override
  Future<SelfRemovedShellMediaBatch> loadSelfRemovedShellMediaParents({
    required SelfRemovedShellAuthoritySnapshot expected,
    required int limit,
  }) async => SelfRemovedShellMediaBatch(
    outcome: SelfRemovedShellMutationOutcome.committed,
    authority: _shellAuthority(expected.groupId, expected.selfPeerId),
    parents: const [],
    hasOverflow: false,
  );

  @override
  Future<SelfRemovedShellMutationOutcome> terminalizeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    final current = _shellAuthority(expected.groupId, expected.selfPeerId);
    if (current.shape != SelfRemovedShellAuthorityShape.markedSelfAbsent ||
        current.selfRemovedAt != expected.selfRemovedAt ||
        current.lastMembershipEventAt != expected.lastMembershipEventAt ||
        current.lastMembershipEventId != expected.lastMembershipEventId) {
      return SelfRemovedShellMutationOutcome.refusedStateChanged;
    }
    _keys.remove(expected.groupId);
    _pendingKeyRotations.remove(expected.groupId);
    return SelfRemovedShellMutationOutcome.committed;
  }

  @override
  Future<SelfRemovedShellFreshnessFloor> appendSelfRemovedShellFreshnessFloor({
    required SelfRemovedShellAuthoritySnapshot expected,
  }) async {
    final current = _shellAuthority(expected.groupId, expected.selfPeerId);
    if (current.shape != SelfRemovedShellAuthorityShape.markedSelfAbsent ||
        current.selfRemovedAt != expected.selfRemovedAt) {
      throw StateError('self-removal authority changed');
    }
    return _removalFloors.putIfAbsent(
      expected.groupId,
      () => SelfRemovedShellFreshnessFloor(
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
        selfRemovedAt: expected.selfRemovedAt!,
        persistenceToken: Object(),
      ),
    );
  }

  @override
  Future<SelfRemovedShellFreshnessFloor?> loadSelfRemovedShellFreshnessFloor(
    String groupId,
  ) async => _removalFloors[groupId];

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
    final watermark = DateTime.tryParse(signedMembershipWatermark)?.toUtc();
    final issuedAt = DateTime.tryParse(signedIssuedAt)?.toUtc();
    if (watermark == null ||
        issuedAt == null ||
        authorizationId.trim().isEmpty ||
        bindingNonce.trim().isEmpty ||
        key.groupId != group.id ||
        roster.any((member) => member.groupId != group.id) ||
        !roster.any((member) => member.peerId == selfPeerId)) {
      return const SelfRemovedAcceptedReentryResult(
        outcome: SelfRemovedAcceptedReentryOutcome.refusedInvalidMaterial,
      );
    }
    final acceptedAt = watermark.isAfter(issuedAt) ? watermark : issuedAt;
    final authority = _shellAuthority(group.id, selfPeerId);
    final floor = _removalFloors[group.id];
    final isMarked =
        authority.shape == SelfRemovedShellAuthorityShape.markedSelfAbsent;
    final isAbsentWithFloor =
        authority.shape == SelfRemovedShellAuthorityShape.absent &&
        floor != null;
    if (!isMarked && !isAbsentWithFloor) {
      return SelfRemovedAcceptedReentryResult(
        outcome: authority.shape == SelfRemovedShellAuthorityShape.absent
            ? SelfRemovedAcceptedReentryOutcome.refusedMissingFloor
            : SelfRemovedAcceptedReentryOutcome.refusedStateChanged,
      );
    }
    final lowerBound = isMarked
        ? authority.lastMembershipEventAt ?? authority.selfRemovedAt
        : floor!.selfRemovedAt;
    if (lowerBound == null || !acceptedAt.isAfter(lowerBound.toUtc())) {
      return const SelfRemovedAcceptedReentryResult(
        outcome: SelfRemovedAcceptedReentryOutcome.refusedStaleAuthority,
      );
    }
    if (isMarked) {
      await appendSelfRemovedShellFreshnessFloor(expected: authority);
    }
    _acceptedReentries[group.id] = _AcceptedReentrySnapshot(
      authorizationId: authorizationId,
      selfPeerId: selfPeerId,
      signedMembershipWatermark: signedMembershipWatermark,
      signedIssuedAt: signedIssuedAt,
      keyGeneration: key.keyGeneration,
      acceptedAt: acceptedAt,
      group: _groups[group.id],
      members: Map<String, GroupMember>.from(
        _members[group.id] ?? const <String, GroupMember>{},
      ),
      keys: List<GroupKeyInfo>.from(_keys[group.id] ?? const <GroupKeyInfo>[]),
    );
    _groups[group.id] = group.copyWith(
      selfRemovedAt: null,
      lastMembershipEventAt: acceptedAt,
      lastMembershipEventId: null,
    );
    _members[group.id] = {for (final member in roster) member.peerId: member};
    _keys[group.id] = <GroupKeyInfo>[key];
    return SelfRemovedAcceptedReentryResult(
      outcome: SelfRemovedAcceptedReentryOutcome.committed,
      acceptedAt: acceptedAt,
    );
  }

  @override
  Future<SelfRemovedAcceptedRollbackOutcome> rollbackAcceptedReentry({
    required String groupId,
    required String selfPeerId,
    required String authorizationId,
  }) async {
    final prior = _acceptedReentries[groupId];
    if (prior == null) {
      return SelfRemovedAcceptedRollbackOutcome.refusedBindingMissing;
    }
    if (prior.authorizationId != authorizationId) {
      return SelfRemovedAcceptedRollbackOutcome.refusedAuthorizationMismatch;
    }
    final current = _shellAuthority(groupId, selfPeerId);
    if (current.shape != SelfRemovedShellAuthorityShape.unmarkedSelfPresent ||
        current.lastMembershipEventAt == null ||
        !current.lastMembershipEventAt!.isAtSameMomentAs(prior.acceptedAt)) {
      return SelfRemovedAcceptedRollbackOutcome.refusedStateChanged;
    }
    if (prior.group == null) {
      _groups.remove(groupId);
      _members.remove(groupId);
      _keys.remove(groupId);
    } else {
      _groups[groupId] = prior.group!;
      _members[groupId] = Map<String, GroupMember>.from(prior.members);
      _keys[groupId] = List<GroupKeyInfo>.from(prior.keys);
    }
    _acceptedReentries.remove(groupId);
    return SelfRemovedAcceptedRollbackOutcome.rolledBack;
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
    final accepted = _acceptedReentries[groupId];
    if (accepted == null) {
      return SelfRemovedAcceptedRetryAuthorizationOutcome.refusedBindingMissing;
    }
    if (accepted.authorizationId != authorizationId) {
      return SelfRemovedAcceptedRetryAuthorizationOutcome
          .refusedAuthorizationMismatch;
    }
    final authority = _shellAuthority(groupId, selfPeerId);
    final latestKey = await getLatestKey(groupId);
    if (accepted.selfPeerId != selfPeerId ||
        accepted.signedMembershipWatermark != signedMembershipWatermark ||
        accepted.signedIssuedAt != signedIssuedAt ||
        accepted.keyGeneration != keyGeneration ||
        authority.shape != SelfRemovedShellAuthorityShape.unmarkedSelfPresent ||
        authority.lastMembershipEventAt == null ||
        !authority.lastMembershipEventAt!.isAtSameMomentAs(
          accepted.acceptedAt,
        ) ||
        authority.lastMembershipEventId != null ||
        latestKey?.keyGeneration != keyGeneration) {
      return SelfRemovedAcceptedRetryAuthorizationOutcome.refusedStateChanged;
    }
    return SelfRemovedAcceptedRetryAuthorizationOutcome.authorized;
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
    final authorization = await authorizeAcceptedReentryRetry(
      groupId: groupId,
      selfPeerId: selfPeerId,
      authorizationId: authorizationId,
      signedMembershipWatermark: signedMembershipWatermark,
      signedIssuedAt: signedIssuedAt,
      keyGeneration: keyGeneration,
    );
    final group = _groups[groupId];
    final self = _members[groupId]?[selfPeerId];
    final key = await getLatestKey(groupId);
    if (group == null ||
        group.selfRemovedAt != null ||
        group.isDissolved ||
        self == null ||
        key?.keyGeneration != keyGeneration ||
        key?.encryptedKey != expectedKeyMaterial) {
      return const SelfRemovedAcceptedNativeRetryResult(
        outcome:
            SelfRemovedAcceptedRetryAuthorizationOutcome.refusedStateChanged,
      );
    }
    if (authorization ==
        SelfRemovedAcceptedRetryAuthorizationOutcome.authorized) {
      await joinNative();
      return SelfRemovedAcceptedNativeRetryResult(
        outcome: authorization,
        group: group,
      );
    }
    if (authorization !=
        SelfRemovedAcceptedRetryAuthorizationOutcome.refusedBindingMissing) {
      return SelfRemovedAcceptedNativeRetryResult(outcome: authorization);
    }
    final authority = _shellAuthority(groupId, selfPeerId);
    if (_removalFloors[groupId] != null ||
        authority.shape != SelfRemovedShellAuthorityShape.unmarkedSelfPresent ||
        authority.lastMembershipEventId != null ||
        !_sameTestInstant(
          group.lastMembershipEventAt,
          expectedFreshMembershipAt,
        ) ||
        !_sameTestInstant(group.lastMetadataEventAt, latestAllowedMetadataAt)) {
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
  }

  @override
  Future<void> commitFreshDirectJoin({
    required GroupModel group,
    required GroupMember selfMember,
    required GroupKeyInfo key,
    required Future<void> Function() joinNative,
  }) async {
    final authority = _shellAuthority(group.id, selfMember.peerId);
    if (authority.shape != SelfRemovedShellAuthorityShape.absent ||
        _removalFloors[group.id] != null) {
      throw StateError('fresh direct join refused');
    }
    await joinNative();
    await saveGroup(group);
    await saveMember(selfMember);
    await saveKey(key);
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
    final group = _groups[groupId];
    final key = await getLatestKey(groupId);
    final authority = _shellAuthority(groupId, selfPeerId);
    if (_removalFloors[groupId] != null ||
        group == null ||
        group.selfRemovedAt != null ||
        group.isDissolved ||
        authority.shape != SelfRemovedShellAuthorityShape.unmarkedSelfPresent ||
        authority.lastMembershipEventId != null ||
        key?.keyGeneration != keyGeneration ||
        key?.encryptedKey != expectedKeyMaterial ||
        !_sameTestInstant(group.lastMembershipEventAt, expectedMembershipAt) ||
        !_sameTestInstant(group.lastMetadataEventAt, latestAllowedMetadataAt)) {
      return SelfRemovedAcceptedRollbackOutcome.refusedStateChanged;
    }
    _keys.remove(groupId);
    _pendingKeyRotations.remove(groupId);
    _members.remove(groupId);
    _groups.remove(groupId);
    return SelfRemovedAcceptedRollbackOutcome.rolledBack;
  }

  @override
  Future<SelfRemovedShellMutationOutcome> purgeSelfRemovedShell({
    required SelfRemovedShellAuthoritySnapshot expected,
    required SelfRemovedShellFreshnessFloor floor,
    required DateTime deletedAt,
  }) async {
    final current = _shellAuthority(expected.groupId, expected.selfPeerId);
    if (current.shape != SelfRemovedShellAuthorityShape.markedSelfAbsent ||
        current.selfRemovedAt != expected.selfRemovedAt) {
      return SelfRemovedShellMutationOutcome.refusedStateChanged;
    }
    if (_removalFloors[expected.groupId] != floor) {
      return SelfRemovedShellMutationOutcome.refusedFloorMissing;
    }
    _members.remove(expected.groupId);
    _keys.remove(expected.groupId);
    _pendingKeyRotations.remove(expected.groupId);
    _groups.remove(expected.groupId);
    return SelfRemovedShellMutationOutcome.committed;
  }

  SelfRemovedShellAuthoritySnapshot _shellAuthority(
    String groupId,
    String selfPeerId,
  ) {
    final group = _groups[groupId];
    final self = _members[groupId]?[selfPeerId];
    final marked = group?.selfRemovedAt != null;
    final shape = group == null
        ? SelfRemovedShellAuthorityShape.absent
        : switch ((marked, self != null)) {
            (false, true) => SelfRemovedShellAuthorityShape.unmarkedSelfPresent,
            (false, false) => SelfRemovedShellAuthorityShape.unmarkedSelfAbsent,
            (true, true) => SelfRemovedShellAuthorityShape.markedSelfPresent,
            (true, false) => SelfRemovedShellAuthorityShape.markedSelfAbsent,
          };
    return SelfRemovedShellAuthoritySnapshot(
      groupId: groupId,
      selfPeerId: selfPeerId,
      shape: shape,
      selfRemovedAt: group?.selfRemovedAt,
      lastMembershipEventAt: group?.lastMembershipEventAt,
      lastMembershipEventId: group?.lastMembershipEventId,
      selfJoinedAt: self?.joinedAt,
      persistenceToken: Object(),
    );
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

  Future<void> saveMemberBypassingValidationForTest(GroupMember member) async {
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
  Future<T> cleanupExactVoluntaryExit<T>({
    required String groupId,
    required String selfPeerId,
    required DateTime selfJoinedAt,
    required Future<T> Function() finalizeSql,
  }) async {
    final group = _groups[groupId];
    final self = _members[groupId]?[selfPeerId];
    if (group == null ||
        group.selfRemovedAt != null ||
        group.isDissolved ||
        self == null ||
        !_sameTestInstant(self.joinedAt, selfJoinedAt)) {
      throw StateError('Exact voluntary-exit authority is unavailable.');
    }
    return finalizeSql();
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
    if (groupKeys == null || groupKeys.isEmpty) {
      return;
    }

    final latestGeneration = groupKeys
        .map((key) => key.keyGeneration)
        .reduce((a, b) => a > b ? a : b);
    final minKeyGenerationToKeep = minRetainedGroupKeyGeneration(
      latestGeneration,
    );
    groupKeys.removeWhere((key) => key.keyGeneration < minKeyGenerationToKeep);
  }
}

class _AcceptedReentrySnapshot {
  const _AcceptedReentrySnapshot({
    required this.authorizationId,
    required this.selfPeerId,
    required this.signedMembershipWatermark,
    required this.signedIssuedAt,
    required this.keyGeneration,
    required this.acceptedAt,
    required this.group,
    required this.members,
    required this.keys,
  });

  final String authorizationId;
  final String selfPeerId;
  final String signedMembershipWatermark;
  final String signedIssuedAt;
  final int keyGeneration;
  final DateTime acceptedAt;
  final GroupModel? group;
  final Map<String, GroupMember> members;
  final List<GroupKeyInfo> keys;
}
