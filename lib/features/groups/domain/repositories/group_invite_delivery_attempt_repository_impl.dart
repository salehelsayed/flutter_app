import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';

import 'group_invite_delivery_attempt_repository.dart';

class GroupInviteDeliveryAttemptRepositoryImpl
    implements GroupInviteDeliveryAttemptRepository {
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertGroupInviteDeliveryAttempt;
  final Future<Map<String, Object?>?> Function({
    required String groupId,
    required String peerId,
  })
  dbLoadGroupInviteDeliveryAttempt;
  final Future<List<Map<String, Object?>>> Function(String groupId)
  dbLoadGroupInviteDeliveryAttemptsForGroup;
  final Future<void> Function({
    required String groupId,
    required String peerId,
    required String status,
    required String updatedAt,
  })
  dbUpdateGroupInviteDeliveryAttemptStatus;
  final Future<int> Function({required String groupId, required String peerId})
  dbDeleteGroupInviteDeliveryAttempt;
  final Future<int> Function(String groupId)
  dbDeleteGroupInviteDeliveryAttemptsForGroup;

  GroupInviteDeliveryAttemptRepositoryImpl({
    required this.dbUpsertGroupInviteDeliveryAttempt,
    required this.dbLoadGroupInviteDeliveryAttempt,
    required this.dbLoadGroupInviteDeliveryAttemptsForGroup,
    required this.dbUpdateGroupInviteDeliveryAttemptStatus,
    required this.dbDeleteGroupInviteDeliveryAttempt,
    required this.dbDeleteGroupInviteDeliveryAttemptsForGroup,
  });

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPT_REPO_SAVE_START',
      details: {
        'groupId': _short(attempt.groupId, max: 8),
        'peerId': _short(attempt.peerId),
        'status': attempt.status.toValue(),
      },
    );

    await dbUpsertGroupInviteDeliveryAttempt(attempt.toMap());

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPT_REPO_SAVE_SUCCESS',
      details: {
        'groupId': _short(attempt.groupId, max: 8),
        'peerId': _short(attempt.peerId),
        'status': attempt.status.toValue(),
      },
    );
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async {
    final row = await dbLoadGroupInviteDeliveryAttempt(
      groupId: groupId,
      peerId: peerId,
    );
    if (row == null) return null;
    return GroupInviteDeliveryAttempt.fromMap(row);
  }

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async {
    final rows = await dbLoadGroupInviteDeliveryAttemptsForGroup(groupId);
    return rows.map(GroupInviteDeliveryAttempt.fromMap).toList(growable: false);
  }

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async {
    return (await getAttempt(groupId: groupId, peerId: peerId))?.status ??
        GroupInviteDeliveryStatus.unknown;
  }

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async {
    final attempts = await getAttemptsForGroup(groupId);
    return {for (final attempt in attempts) attempt.peerId: attempt.status};
  }

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final existing = await getAttempt(groupId: groupId, peerId: peerId);
    if (existing == null) {
      await saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          status: status,
          attemptedAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    await dbUpdateGroupInviteDeliveryAttemptStatus(
      groupId: groupId,
      peerId: peerId,
      status: status.toValue(),
      updatedAt: now.toIso8601String(),
    );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final existing = await getAttempt(groupId: groupId, peerId: peerId);
    if (existing == null) {
      await saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          attemptedAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    await saveAttempt(
      existing.copyWith(
        username: username,
        status: GroupInviteDeliveryStatus.joined,
        updatedAt: now,
        clearLastError: true,
      ),
    );
  }

  @override
  Future<int> deleteAttempt({required String groupId, required String peerId}) {
    return dbDeleteGroupInviteDeliveryAttempt(groupId: groupId, peerId: peerId);
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) {
    return dbDeleteGroupInviteDeliveryAttemptsForGroup(groupId);
  }
}

String _short(String value, {int max = 10}) =>
    value.length > max ? value.substring(0, max) : value;
