import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

const _groupId = 'group-123';

GroupModel _makeGroup({String groupId = _groupId}) {
  return GroupModel(
    id: groupId,
    name: 'Orbit Group',
    type: GroupType.chat,
    topicName: '/mknoon/group/$groupId',
    createdAt: DateTime.utc(2026, 4, 6, 10),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );
}

GroupMember _makeMember({
  String groupId = _groupId,
  String peerId = 'peer-user-a',
  DateTime? joinedAt,
}) {
  return GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: 'User A',
    role: MemberRole.writer,
    joinedAt: joinedAt ?? DateTime.utc(2026, 4, 6, 10, 1),
  );
}

GroupInvitePayload _makeInvitePayload({String groupId = _groupId}) {
  return GroupInvitePayload(
    id: 'invite-123',
    groupId: groupId,
    groupKey: 'group-key',
    keyEpoch: 1,
    groupConfig: const {
      'name': 'Orbit Group',
      'groupType': 'chat',
      'description': 'invite pending',
      'createdBy': 'peer-admin',
      'createdAt': '2026-04-06T10:00:00.000Z',
      'members': [
        {
          'peerId': 'peer-admin',
          'username': 'Admin',
          'role': 'admin',
          'publicKey': 'pk-admin',
          'mlKemPublicKey': 'mlkem-admin',
        },
        {
          'peerId': 'peer-user-a',
          'username': 'User A',
          'role': 'writer',
          'publicKey': 'pk-user-a',
          'mlKemPublicKey': 'mlkem-user-a',
        },
      ],
    },
    senderPeerId: 'peer-admin',
    senderUsername: 'Admin',
    timestamp: '2026-04-06T10:00:00.000Z',
    invitePolicy: GroupInvitePolicy(
      expiresAt: DateTime.utc(2026, 4, 7, 10),
      allowedDevices: const ['peer-user-a'],
      assignedRole: 'writer',
      canInviteOthers: false,
      joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
      keyEpoch: 1,
    ),
  );
}

PendingGroupInvite _makePendingInvite({String groupId = _groupId}) {
  return PendingGroupInvite.fromPayload(
    _makeInvitePayload(groupId: groupId),
    receivedAt: DateTime.utc(2026, 4, 6, 10, 5),
  );
}

void main() {
  group('resolveGroupNotificationRouteTarget', () {
    test('returns the existing group without draining inbox', () async {
      final groupRepo = InMemoryGroupRepository();
      final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      var drainCalls = 0;

      await groupRepo.saveGroup(_makeGroup());

      final result = await resolveGroupNotificationRouteTarget(
        groupId: _groupId,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        drainOfflineInbox: () async {
          drainCalls += 1;
        },
      );

      expect(result.group, isNotNull);
      expect(result.group!.id, _groupId);
      expect(result.pendingInvite, isNull);
      expect(drainCalls, 0);
    });

    test(
      'returns the existing pending invite without draining inbox',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await pendingInviteRepo.savePendingInvite(_makePendingInvite());

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNull);
        expect(result.pendingInvite, isNotNull);
        expect(result.pendingInvite!.groupId, _groupId);
        expect(drainCalls, 0);
      },
    );

    test('drains inbox and resolves a newly stored pending invite', () async {
      final groupRepo = InMemoryGroupRepository();
      final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      var drainCalls = 0;

      final result = await resolveGroupNotificationRouteTarget(
        groupId: _groupId,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        drainOfflineInbox: () async {
          drainCalls += 1;
          await pendingInviteRepo.savePendingInvite(_makePendingInvite());
        },
      );

      expect(result.group, isNull);
      expect(result.pendingInvite, isNotNull);
      expect(result.pendingInvite!.groupId, _groupId);
      expect(drainCalls, 1);
    });

    test('drains inbox and resolves a newly materialized group', () async {
      final groupRepo = InMemoryGroupRepository();
      final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
      var drainCalls = 0;

      final result = await resolveGroupNotificationRouteTarget(
        groupId: _groupId,
        groupRepo: groupRepo,
        pendingInviteRepo: pendingInviteRepo,
        drainOfflineInbox: () async {
          drainCalls += 1;
          await groupRepo.saveGroup(_makeGroup());
        },
      );

      expect(result.group, isNotNull);
      expect(result.group!.id, _groupId);
      expect(result.pendingInvite, isNull);
      expect(drainCalls, 1);
    });

    test(
      'returns missing when neither group nor invite can be recovered',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNull);
        expect(result.pendingInvite, isNull);
        expect(drainCalls, 1);
      },
    );

    test(
      'returns missing for a stale removed-group notification after local cleanup',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.deleteGroup(_groupId);

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNull);
        expect(result.pendingInvite, isNull);
        expect(result.hasGroup, isFalse);
        expect(result.hasPendingInvite, isFalse);
        expect(drainCalls, 1);
      },
    );

    test(
      'UP-010 opens existing group only when local peer is a current member',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.saveMember(_makeMember(peerId: 'peer-user-a'));

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          localPeerId: 'peer-user-a',
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNotNull);
        expect(result.group!.id, _groupId);
        expect(result.pendingInvite, isNull);
        expect(drainCalls, 0);
      },
    );

    test(
      'UP-010 refuses stale removed group route when local member is absent',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await groupRepo.saveGroup(_makeGroup());

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          localPeerId: 'peer-user-a',
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNull);
        expect(result.pendingInvite, isNull);
        expect(result.hasGroup, isFalse);
        expect(result.hasPendingInvite, isFalse);
        expect(drainCalls, 1);
      },
    );

    test(
      'UP-010 recovers re-added local member before routing group notification',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await groupRepo.saveGroup(_makeGroup());

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          localPeerId: 'peer-user-a',
          drainOfflineInbox: () async {
            drainCalls += 1;
            await groupRepo.saveMember(
              _makeMember(
                peerId: 'peer-user-a',
                joinedAt: DateTime.utc(2026, 4, 6, 10, 30),
              ),
            );
          },
        );

        expect(result.group, isNotNull);
        expect(result.group!.id, _groupId);
        expect(result.pendingInvite, isNull);
        expect(drainCalls, 1);
      },
    );

    test(
      'UP-010 redirects to pending invite instead of stale removed group',
      () async {
        final groupRepo = InMemoryGroupRepository();
        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        var drainCalls = 0;

        await groupRepo.saveGroup(_makeGroup());
        await pendingInviteRepo.savePendingInvite(_makePendingInvite());

        final result = await resolveGroupNotificationRouteTarget(
          groupId: _groupId,
          groupRepo: groupRepo,
          pendingInviteRepo: pendingInviteRepo,
          localPeerId: 'peer-user-a',
          drainOfflineInbox: () async {
            drainCalls += 1;
          },
        );

        expect(result.group, isNull);
        expect(result.pendingInvite, isNotNull);
        expect(result.pendingInvite!.groupId, _groupId);
        expect(drainCalls, 0);
      },
    );
  });
}
