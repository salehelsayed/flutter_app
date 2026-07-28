import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, Map<String, Object?>> rows;
  late GroupInviteDeliveryAttemptRepositoryImpl repository;

  String key(String groupId, String peerId) => '$groupId::$peerId';

  setUp(() {
    rows = {};
    repository = GroupInviteDeliveryAttemptRepositoryImpl(
      dbUpsertGroupInviteDeliveryAttempt: (row) async {
        rows[key(row['group_id']! as String, row['peer_id']! as String)] = row;
      },
      dbLoadGroupInviteDeliveryAttempt:
          ({required groupId, required peerId}) async {
            return rows[key(groupId, peerId)];
          },
      dbLoadGroupInviteDeliveryAttemptsForGroup: (groupId) async {
        return rows.values
            .where((row) => row['group_id'] == groupId)
            .toList(growable: false);
      },
      dbUpdateGroupInviteDeliveryAttemptStatus:
          ({
            required groupId,
            required peerId,
            required status,
            required updatedAt,
          }) async {
            final existing = rows[key(groupId, peerId)];
            rows[key(groupId, peerId)] = {
              if (existing != null) ...existing,
              'group_id': groupId,
              'peer_id': peerId,
              'status': status,
              'attempted_at': existing?['attempted_at'] ?? updatedAt,
              'updated_at': updatedAt,
              'last_error': null,
            };
          },
      dbDeleteGroupInviteDeliveryAttempt:
          ({required groupId, required peerId}) async {
            return rows.remove(key(groupId, peerId)) == null ? 0 : 1;
          },
      dbDeleteGroupInviteDeliveryAttemptsForGroup: (groupId) async {
        final before = rows.length;
        rows.removeWhere((_, row) => row['group_id'] == groupId);
        return before - rows.length;
      },
    );
  });

  test('round-trips all persisted invite delivery statuses', () async {
    final now = DateTime.utc(2026, 5, 7, 12);
    for (final status in GroupInviteDeliveryStatus.values) {
      if (status == GroupInviteDeliveryStatus.unknown) continue;
      await repository.saveAttempt(
        GroupInviteDeliveryAttempt(
          groupId: 'group-1',
          peerId: 'peer-${status.toValue()}',
          username: status.toValue(),
          status: status,
          attemptedAt: now,
          updatedAt: now,
        ),
      );
    }

    final attempts = await repository.getAttemptsForGroup('group-1');
    expect(
      attempts.map((attempt) => attempt.status).toSet(),
      containsAll([
        GroupInviteDeliveryStatus.sent,
        GroupInviteDeliveryStatus.queued,
        GroupInviteDeliveryStatus.needsResend,
        GroupInviteDeliveryStatus.cannotSend,
        GroupInviteDeliveryStatus.joined,
      ]),
    );
  });

  test('projects no-row legacy members as unknown', () async {
    final status = await repository.getStatusForMember(
      groupId: 'legacy-group',
      peerId: 'legacy-peer',
    );

    expect(status, GroupInviteDeliveryStatus.unknown);
  });

  test('maps helper rows without UI logic', () async {
    final now = DateTime.utc(2026, 5, 7, 12);
    await repository.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: 'group-1',
        peerId: 'peer-a',
        username: 'Alice',
        status: GroupInviteDeliveryStatus.needsResend,
        attemptedAt: now,
        updatedAt: now,
        lastError: 'send_failed',
      ),
    );

    final attempt = await repository.getAttempt(
      groupId: 'group-1',
      peerId: 'peer-a',
    );

    expect(attempt, isNotNull);
    expect(attempt!.username, 'Alice');
    expect(attempt.status, GroupInviteDeliveryStatus.needsResend);
    expect(attempt.lastError, 'send_failed');
  });

  test('markRevoked sets status to revoked and clears lastError', () async {
    final now = DateTime.utc(2026, 6, 17, 12);
    await repository.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: 'group-1',
        peerId: 'peer-a',
        status: GroupInviteDeliveryStatus.sent,
        attemptedAt: now,
        updatedAt: now,
        lastError: 'something',
        inviteId: 'invite-1',
      ),
    );

    await repository.markRevoked(groupId: 'group-1', peerId: 'peer-a');

    final attempt = await repository.getAttempt(
      groupId: 'group-1',
      peerId: 'peer-a',
    );
    expect(attempt!.status, GroupInviteDeliveryStatus.revoked);
    expect(attempt.lastError, isNull);
    // invite_id is preserved across the status change.
    expect(attempt.inviteId, 'invite-1');
  });

  test('markRevoked on a missing row creates a fresh revoked row', () async {
    await repository.markRevoked(groupId: 'group-1', peerId: 'ghost');
    final attempt = await repository.getAttempt(
      groupId: 'group-1',
      peerId: 'ghost',
    );
    expect(attempt!.status, GroupInviteDeliveryStatus.revoked);
  });

  test('markDeclined sets status to declined', () async {
    final now = DateTime.utc(2026, 6, 17, 12);
    await repository.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: 'group-1',
        peerId: 'peer-a',
        status: GroupInviteDeliveryStatus.sent,
        attemptedAt: now,
        updatedAt: now,
      ),
    );

    await repository.markDeclined(groupId: 'group-1', peerId: 'peer-a');

    final attempt = await repository.getAttempt(
      groupId: 'group-1',
      peerId: 'peer-a',
    );
    expect(attempt!.status, GroupInviteDeliveryStatus.declined);
  });

  test('markDeclined never downgrades a joined row (joined-wins)', () async {
    final now = DateTime.utc(2026, 6, 17, 12);
    await repository.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: 'group-1',
        peerId: 'peer-a',
        status: GroupInviteDeliveryStatus.joined,
        attemptedAt: now,
        updatedAt: now,
      ),
    );

    await repository.markDeclined(groupId: 'group-1', peerId: 'peer-a');

    final attempt = await repository.getAttempt(
      groupId: 'group-1',
      peerId: 'peer-a',
    );
    expect(attempt!.status, GroupInviteDeliveryStatus.joined);
  });
}
