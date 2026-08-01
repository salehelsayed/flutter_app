import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';

class _InMemoryInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> _attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    _attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => _attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      _attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in _attempts.values.where(
      (attempt) => attempt.groupId == groupId,
    ))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(status: status, updatedAt: now);
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markRevoked({
    required String groupId,
    required String peerId,
    DateTime? revokedAt,
  }) async {
    final now = (revokedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.revoked,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.revoked,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    if (existing?.status == GroupInviteDeliveryStatus.joined) {
      return;
    }
    final now = (declinedAt ?? DateTime.now()).toUtc();
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.declined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.declined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = _attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      _attempts.remove(key);
    }
    return keys.length;
  }
}

void main() {
  GroupMember member(String peerId) => GroupMember(
    groupId: 'group-1',
    peerId: peerId,
    username: 'User-$peerId',
    role: MemberRole.writer,
    publicKey: 'pk-$peerId',
    joinedAt: DateTime.utc(2026, 6, 1),
  );

  test('stage-time fanout attempts persist needsResend rows', () async {
    // Plan 318 TC-318-04: the affirmative-local-evidence contract rests on the
    // add-member flow writing a persisted row for every staged invitee at
    // stage time, before any send result exists.
    final repo = _InMemoryInviteDeliveryAttemptRepository();

    await recordPendingGroupInviteFanoutAttempts(
      inviteDeliveryAttemptRepo: repo,
      groupId: 'group-1',
      members: [member('peer-staged-a'), member('peer-staged-b')],
      now: DateTime.utc(2026, 8, 1, 12),
    );

    final statuses = await repo.getStatusesForGroupMembers('group-1');
    expect(statuses, {
      'peer-staged-a': GroupInviteDeliveryStatus.needsResend,
      'peer-staged-b': GroupInviteDeliveryStatus.needsResend,
    });
  });

  test('stage-time fanout tolerates an absent repo without writing', () async {
    await recordPendingGroupInviteFanoutAttempts(
      inviteDeliveryAttemptRepo: null,
      groupId: 'group-1',
      members: [member('peer-staged-a')],
    );
  });
}
