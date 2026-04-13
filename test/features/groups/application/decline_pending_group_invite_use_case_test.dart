import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/decline_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;

  PendingGroupInvite makeInvite({DateTime? receivedAt}) {
    final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc()).toUtc();
    final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
    final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
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
        'createdAt': createdAt.toIso8601String(),
      },
      senderPeerId: '12D3KooWAlice',
      senderUsername: 'Alice',
      timestamp: inviteTimestamp.toIso8601String(),
    );
    return PendingGroupInvite.fromPayload(
      payload,
      receivedAt: effectiveReceivedAt,
    );
  }

  setUp(() {
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
  });

  group('declinePendingGroupInvite', () {
    test('deletes pending invite on decline', () async {
      await pendingInviteRepo.savePendingInvite(makeInvite());

      final result = await declinePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
      );

      expect(result, DeclinePendingGroupInviteResult.success);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
    });

    test('returns expired when declining an expired invite', () async {
      await pendingInviteRepo.savePendingInvite(
        makeInvite(receivedAt: DateTime.utc(2026, 4, 1, 13, 0)),
      );

      final result = await declinePendingGroupInvite(
        pendingInviteRepo: pendingInviteRepo,
        groupId: 'grp-abc123',
        now: DateTime.utc(2026, 4, 12, 13, 0),
      );

      expect(result, DeclinePendingGroupInviteResult.expired);
      expect(await pendingInviteRepo.getPendingInvite('grp-abc123'), isNull);
    });

    test(
      'declining on one device does not clear the sibling device pending invite',
      () async {
        final phonePendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingInviteRepo = InMemoryPendingGroupInviteRepository();

        await phonePendingInviteRepo.savePendingInvite(makeInvite());
        await tabletPendingInviteRepo.savePendingInvite(makeInvite());

        final result = await declinePendingGroupInvite(
          pendingInviteRepo: phonePendingInviteRepo,
          groupId: 'grp-abc123',
        );

        expect(result, DeclinePendingGroupInviteResult.success);
        expect(
          await phonePendingInviteRepo.getPendingInvite('grp-abc123'),
          isNull,
        );
        expect(
          await tabletPendingInviteRepo.getPendingInvite('grp-abc123'),
          isNotNull,
        );
      },
    );
  });
}
