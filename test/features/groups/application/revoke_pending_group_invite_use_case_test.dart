import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/revoke_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;

  PendingGroupInvite makeInvite() {
    final receivedAt = DateTime.utc(2026, 4, 29, 12);
    final payload = GroupInvitePayload(
      id: 'invite-1',
      groupId: 'grp-abc123',
      groupKey: 'base64-key',
      keyEpoch: 1,
      groupConfig: {
        'name': 'Book Club',
        'groupType': 'chat',
        'members': const [],
        'createdBy': '12D3KooWAlice',
        'createdAt': '2026-04-29T10:00:00.000Z',
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: '2026-04-29T10:05:00.000Z',
    );
    return PendingGroupInvite.fromPayload(payload, receivedAt: receivedAt);
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  });

  group('revokePendingGroupInvite', () {
    test('removes pending row and records a revocation tombstone', () async {
      await pendingInviteRepo.savePendingInvite(makeInvite());

      final result = await revokePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 29, 13),
        revokedBy: '12D3KooWAlice',
      );

      expect(result, RevokePendingGroupInviteResult.revoked);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);

      final revocation = await pendingInviteRepo.getRevokedInvite('invite-1');
      expect(revocation, isNotNull);
      expect(revocation!.groupId, 'grp-abc123');
      expect(revocation.revokedBy, '12D3KooWAlice');
      expect(revocation.isActiveAt(DateTime.utc(2026, 4, 30)), isTrue);
    });

    test('returns notFound without writing a tombstone', () async {
      final result = await revokePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'missing-group',
        now: DateTime.utc(2026, 4, 29, 13),
      );

      expect(result, RevokePendingGroupInviteResult.notFound);
      expect(pendingInviteRepo.revokedCount, 0);
    });
  });
}
