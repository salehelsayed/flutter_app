import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/sweep_expired_group_invites_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

PendingGroupInvite _invite({
  required String groupId,
  required DateTime expiresAt,
}) {
  final createdAt = expiresAt.subtract(const Duration(days: 7));
  return PendingGroupInvite(
    groupId: groupId,
    inviteId: 'invite-$groupId',
    payloadJson: '{}',
    groupName: 'Group $groupId',
    groupType: GroupType.chat,
    senderPeerId: '12D3KooWAlice',
    senderUsername: 'Alice',
    createdBy: '12D3KooWAlice',
    createdAt: createdAt,
    receivedAt: createdAt,
    expiresAt: expiresAt,
  );
}

GroupInviteRevocation _revocation({
  required String inviteId,
  required DateTime expiresAt,
}) {
  return GroupInviteRevocation(
    inviteId: inviteId,
    groupId: 'grp-$inviteId',
    revokedAt: expiresAt.subtract(const Duration(days: 7)),
    expiresAt: expiresAt,
  );
}

GroupInviteConsumption _consumption({
  required String inviteId,
  required DateTime expiresAt,
}) {
  return GroupInviteConsumption(
    inviteId: inviteId,
    groupId: 'grp-$inviteId',
    consumedAt: expiresAt.subtract(const Duration(days: 7)),
    expiresAt: expiresAt,
  );
}

GroupWelcomeKeyPackageTombstone _tombstone({
  required String packageId,
  required DateTime expiresAt,
}) {
  return GroupWelcomeKeyPackageTombstone(
    packageId: packageId,
    recipientDeviceId: 'device-$packageId',
    groupId: 'grp-$packageId',
    inviteId: 'invite-$packageId',
    publicMaterialHash: 'hash-$packageId',
    consumedAt: expiresAt.subtract(const Duration(days: 7)),
    expiresAt: expiresAt,
  );
}

void main() {
  late InMemoryPendingGroupInviteRepository repo;

  setUp(() {
    repo = InMemoryPendingGroupInviteRepository();
  });

  test(
    'sweepExpiredGroupInvites deletes only the expired rows across all four '
    'side tables and returns per-table counts',
    () async {
      final now = DateTime.utc(2026, 6, 17, 12);
      final past = now.subtract(const Duration(minutes: 1));
      final future = now.add(const Duration(days: 1));

      await repo.savePendingInvite(_invite(groupId: 'expired', expiresAt: past));
      await repo.savePendingInvite(_invite(groupId: 'valid', expiresAt: future));
      await repo.saveRevokedInvite(
        _revocation(inviteId: 'rev-expired', expiresAt: past),
      );
      await repo.saveRevokedInvite(
        _revocation(inviteId: 'rev-valid', expiresAt: future),
      );
      await repo.saveConsumedInvite(
        _consumption(inviteId: 'con-expired', expiresAt: past),
      );
      await repo.saveConsumedInvite(
        _consumption(inviteId: 'con-valid', expiresAt: future),
      );
      await repo.saveWelcomeKeyPackageTombstone(
        _tombstone(packageId: 'tomb-expired', expiresAt: past),
      );
      await repo.saveWelcomeKeyPackageTombstone(
        _tombstone(packageId: 'tomb-valid', expiresAt: future),
      );

      final result = await sweepExpiredGroupInvites(repo: repo, now: () => now);

      expect(result.pendingInvites, 1);
      expect(result.revokedInvites, 1);
      expect(result.consumedInvites, 1);
      expect(result.welcomeKeyPackageTombstones, 1);
      expect(result.total, 4);

      // Only the valid rows survive.
      expect(repo.count, 1);
      expect(repo.revokedCount, 1);
      expect(repo.consumedCount, 1);
      expect(repo.welcomeKeyPackageTombstoneCount, 1);
      expect(await repo.getPendingInvite('valid'), isNotNull);
      expect(await repo.getPendingInvite('expired'), isNull);
      expect(await repo.getRevokedInvite('rev-valid'), isNotNull);
      expect(await repo.getRevokedInvite('rev-expired'), isNull);
    },
  );

  test('sweepExpiredGroupInvites emits START and SUCCESS with deleted counts',
      () async {
    final flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    addTearDown(() => debugSetFlowEventSink(null));

    final now = DateTime.utc(2026, 6, 17, 12);
    await repo.savePendingInvite(
      _invite(groupId: 'expired', expiresAt: now.subtract(const Duration(minutes: 1))),
    );

    await sweepExpiredGroupInvites(repo: repo, now: () => now);

    expect(
      flowEvents.where((e) => e['event'] == 'GROUP_INVITE_SWEEP_START'),
      hasLength(1),
    );
    final success = flowEvents
        .where((e) => e['event'] == 'GROUP_INVITE_SWEEP_SUCCESS')
        .toList();
    expect(success, hasLength(1));
    final details = success.single['details'] as Map<String, dynamic>;
    expect(details['pending'], 1);
    expect(details['revoked'], 0);
    expect(details['consumed'], 0);
    expect(details['tombstones'], 0);
  });

  test('sweepExpiredGroupInvites returns .empty counts when nothing is expired',
      () async {
    final now = DateTime.utc(2026, 6, 17, 12);
    await repo.savePendingInvite(
      _invite(groupId: 'valid', expiresAt: now.add(const Duration(days: 1))),
    );

    final result = await sweepExpiredGroupInvites(repo: repo, now: () => now);

    expect(result.total, 0);
    expect(repo.count, 1);
  });
}
